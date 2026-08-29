import bcrypt from "bcryptjs";
import {
  MongoClient,
  Db,
  ObjectId,
  MongoClientOptions,
  Collection,
  UpdateResult,
  BulkWriteResult,
} from "mongodb";

exports("bcrypt_js", () => {
  return bcrypt;
});

// --- Polyfill de Performance (Entornos Legacy) ---
if (typeof global.performance === "undefined") {
  try {
    const { performance } = require("perf_hooks");
    global.performance = performance;
  } catch {
    console.warn("⚠️ [MongoDB] No se pudo cargar perf_hooks.");
  }
}

// --- Polyfill de Crypto (Para MongoDB / BSON) ---
if (
  typeof global.crypto === "undefined" ||
  typeof global.crypto.getRandomValues === "undefined"
) {
  try {
    const nodeCrypto = require("crypto");
    global.crypto = global.crypto || ({} as any);
    if (nodeCrypto.webcrypto) {
      global.crypto.getRandomValues = nodeCrypto.webcrypto.getRandomValues.bind(
        nodeCrypto.webcrypto,
      );
    } else {
      global.crypto.getRandomValues = function (buffer: any) {
        return nodeCrypto.randomFillSync(buffer);
      };
    }
  } catch {
    console.warn("⚠️ [MongoDB] No se pudo cargar crypto para polyfill.");
  }
}

// --- Sonda de contenedor del driver de Mongo (sandbox de FXServer) ---
// Al construir el MongoClient, el driver comprueba si existe /.dockerenv para meter
// "runtime: docker" en la metadata del handshake. Esa ruta está fuera del sandbox de
// FXServer ("no device found"), así que la lectura se deniega: el driver ya se come el
// error y sigue con "no estoy en un contenedor", pero la promesa se rechaza antes de que
// nadie la espere y Node escupe dos páginas de UnhandledPromiseRejection en cada arranque.
//
// Aquí se contesta lo MISMO que acababa contestando el sandbox (no accesible) sin llegar a
// tocar el disco, así que el resultado para el driver no cambia — solo desaparece el ruido.
// Lo único que se pierde es un campo de telemetría del driver que ya venía vacío. Si algún
// día este server corre DENTRO de Docker, seguirá diciendo que no: la alternativa es que el
// sandbox lo deniegue igual y con tres avisos.
try {
  const fsp = require("fs").promises;
  const access = fsp.access.bind(fsp);
  fsp.access = (path: unknown, ...rest: unknown[]) => {
    if (path !== "/.dockerenv") return access(path, ...rest);
    const denied = Promise.reject(new Error("ENOENT: fuera del sandbox de FXServer"));
    denied.catch(() => {}); // la rejection ya tiene dueño; el driver la vuelve a capturar
    return denied;
  };
} catch {
  console.warn("⚠️ [MongoDB] No se pudo silenciar la sonda de contenedor del driver.");
}

// --- Configuración (Cacheada al inicio) ---
// Leer las Convars una sola vez al iniciar el script ahorra CPU
const CONFIG = {
  URL: GetConvar("mongodb_url", "mongodb://localhost:27017"),
  DB_NAME: GetConvar("mongodb_database", "server"), // Configurable por variable
  OPTIONS: {
    serverSelectionTimeoutMS: 5000,
    connectTimeoutMS: GetConvarInt("mongodb_connect_timeout_ms", 5000),
    socketTimeoutMS: 45000,
    maxPoolSize: GetConvarInt("mongodb_max_pool_size", 10),
    minPoolSize: 1,
    monitorCommands: false,
    forceServerObjectId: false,
    // family: 4 // Descomentar si tienes problemas con IPv6
  } as MongoClientOptions,
};

// --- Utilidades ---

const HEX24 = /^[0-9a-fA-F]{24}$/;

/**
 * Convierte strings hex de 24 chars a ObjectId dentro del subárbol de un `_id`
 * (incluye operadores como { _id: { $in: [...] } }). El guard con regex es
 * necesario porque ObjectId.isValid() también acepta cualquier string de 12
 * bytes, lo que convertiría textos normales por accidente.
 */
function toObjectId(value: any): any {
  if (value instanceof ObjectId) return value;
  if (typeof value === "string") {
    return HEX24.test(value) ? new ObjectId(value) : value;
  }
  if (Array.isArray(value)) return value.map(toObjectId);
  if (value && typeof value === "object") {
    const out: any = {};
    for (const key in value) out[key] = toObjectId(value[key]);
    return out;
  }
  return value;
}

/**
 * El msgpack de CfxLua serializa la tabla vacía {} como array []; el driver
 * exige objetos planos para filter/update/options. Solo se aplica al valor
 * raíz: un array vacío anidado no es distinguible desde Lua de todas formas.
 */
function fixEmptyTable(value: any): any {
  if (value === null || value === undefined) return {};
  return Array.isArray(value) && value.length === 0 ? {} : value;
}

/**
 * Fechas BSON desde Lua (convención Extended JSON): el marcador
 * { "$date": <ms | string ISO> } se convierte a Date real al escribir.
 * Lua no tiene tipo fecha, y sin Date real los índices TTL no expiran nada.
 * A la vuelta no hay conversión: JSON.stringify serializa Date como ISO-8601.
 */
function toDates(node: any): any {
  if (!node || typeof node !== "object") return node;
  if (node instanceof ObjectId || node instanceof Date) return node;
  if (Array.isArray(node)) return node.map(toDates);

  const keys = Object.keys(node);
  if (keys.length === 1 && keys[0] === "$date") {
    const v = node["$date"];
    if (typeof v === "number" || typeof v === "string") return new Date(v);
  }

  const out: any = {};
  for (const key of keys) out[key] = toDates(node[key]);
  return out;
}

/** Normaliza documentos/updates: tabla vacía de msgpack + marcadores $date. */
function normalizeDoc(value: any): any {
  return toDates(fixEmptyTable(value));
}

/**
 * Normaliza un filtro: solo el subárbol de claves `_id` se convierte a
 * ObjectId. Sin heurísticas sobre otros campos (`*Id`): un string que
 * "parezca" hex no debe cambiar de tipo silenciosamente.
 */
function normalizeFilter(root: any): any {
  const walk = (node: any): any => {
    if (!node || typeof node !== "object") return node;
    if (Array.isArray(node)) return node.map(walk); // $or / $and
    const out: any = {};
    for (const key in node) {
      out[key] = key === "_id" ? toObjectId(node[key]) : walk(node[key]);
    }
    return out;
  };
  return toDates(walk(fixEmptyTable(root)));
}

/**
 * Normaliza las operaciones de bulkWrite. Cada op es `{ nombreOp: { ... } }`:
 * dentro, `filter` se normaliza como filtro (ObjectId bajo `_id`) y el resto
 * (`document`, `update`, `replacement`, `arrayFilters`…) como documento
 * ($date → Date). Los flags escalares (`upsert`) pasan tal cual.
 */
function normalizeBulkOps(ops: any): any[] {
  if (!Array.isArray(ops)) return [];

  return ops.map((op) => {
    if (!op || typeof op !== "object") return op;

    const out: any = {};
    for (const name in op) {
      const spec = op[name];
      if (!spec || typeof spec !== "object") {
        out[name] = spec;
        continue;
      }

      const model: any = {};
      for (const key in spec) {
        model[key] =
          key === "filter" ? normalizeFilter(spec[key]) : normalizeDoc(spec[key]);
      }
      out[name] = model;
    }
    return out;
  });
}

// --- Singleton de Conexión ---
class MongoService {
  private static instance: MongoService;
  private client: MongoClient;
  private db: Db | null = null;
  private isConnected: boolean = false;

  private constructor() {
    this.client = new MongoClient(CONFIG.URL, CONFIG.OPTIONS);

    this.client.on("open", () => {
      this.isConnected = true;
      console.log(`✅ [MongoDB] Conectado a base de datos: ${CONFIG.DB_NAME}`);
    });

    this.client.on("close", () => {
      this.isConnected = false;
      console.log("🔌 [MongoDB] Conexión cerrada");
    });

    this.client.on("error", (err) =>
      console.error("❌ [MongoDB] Error de cliente:", err),
    );
  }

  public static getInstance(): MongoService {
    if (!MongoService.instance) {
      MongoService.instance = new MongoService();
    }
    return MongoService.instance;
  }

  /**
   * Obtiene la instancia de la DB. Conecta si es necesario.
   * @param dbName Opcional, por si se quiere cambiar de DB dinámicamente
   */
  public async getDb(dbName: string = CONFIG.DB_NAME): Promise<Db> {
    // Si no estamos conectados, conectar.
    if (!this.isConnected) {
      await this.client.connect();
      // Verificación inicial (solo al conectar, no en cada query)
      this.db = this.client.db(dbName);
      await this.db.command({ ping: 1 });
      this.isConnected = true;
    }

    // Si cambiamos de DB o es la primera vez
    if (!this.db || this.db.databaseName !== dbName) {
      this.db = this.client.db(dbName);
    }

    return this.db;
  }

  public async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.close();
      this.isConnected = false;
      this.db = null;
    }
  }

  public isReady(): boolean {
    return this.isConnected;
  }
}

// --- Wrapper Genérico ---
//
// Protocolo del bridge: TODA operación de datos devuelve un string JSON con
// forma { ok: true, data?: ... } | { ok: false, error: "..." }. Así el lado
// Lua (kec.mongodb) distingue "no encontrado" (ok sin data) de "falló la DB"
// (ok=false) — el formato anterior devolvía un string de error que los
// consumidores confundían con datos o comparaban contra números.
async function execute(
  collectionName: string,
  operation: (col: Collection) => Promise<any>,
): Promise<string> {
  try {
    const service = MongoService.getInstance();
    const db = await service.getDb();
    const collection = db.collection(collectionName);

    const result = await operation(collection);

    const payload: { ok: true; data?: any } = { ok: true };
    if (result !== null && result !== undefined) payload.data = result;
    return JSON.stringify(payload);
  } catch (error: any) {
    const message = String(error?.message ?? error);
    console.error(`❌ [MongoDB] Error en '${collectionName}':`, message);
    return JSON.stringify({ ok: false, error: message });
  }
}

/** Forma de retorno común para updateOne/updateMany. */
function updateSummary(res: UpdateResult) {
  return {
    matched: res.matchedCount,
    modified: res.modifiedCount,
    upserted: res.upsertedId ? res.upsertedId.toHexString() : undefined,
  };
}

/** _ids generados por el bulk → hex, con el índice de la op como clave. */
function hexIdMap(ids: { [index: number]: any }) {
  const out: Record<string, string> = {};
  for (const index in ids) {
    const id = ids[index];
    out[index] = id instanceof ObjectId ? id.toHexString() : String(id);
  }
  return out;
}

/** Forma de retorno de bulkWrite: contadores + los _id que generó Mongo. */
function bulkSummary(res: BulkWriteResult) {
  return {
    inserted: res.insertedCount,
    matched: res.matchedCount,
    modified: res.modifiedCount,
    deleted: res.deletedCount,
    upserted: res.upsertedCount,
    insertedIds: hexIdMap(res.insertedIds),
    upsertedIds: hexIdMap(res.upsertedIds),
  };
}

// --- EXPORTS ---

// Inicialización explícita (Opcional, pero recomendada al iniciar el recurso)
exports("connect", async (dbName?: string) => {
  try {
    await MongoService.getInstance().getDb(dbName);
    return true;
  } catch (e) {
    return false;
  }
});

exports("disconnect", async () => {
  await MongoService.getInstance().disconnect();
});

exports("isConnected", () => {
  return MongoService.getInstance().isReady();
});

// Operaciones CRUD

exports("findOne", (col: string, filter: any) => {
  return execute(col, (c) => c.findOne(normalizeFilter(filter)));
});

exports("find", (col: string, filter: any, options?: any) => {
  return execute(col, (c) =>
    c.find(normalizeFilter(filter), fixEmptyTable(options)).toArray(),
  );
});

exports("insertOne", (col: string, doc: any) => {
  return execute(col, async (c) => {
    const res = await c.insertOne(normalizeDoc(doc));
    return res.insertedId.toHexString(); // hex plano, sin JSON anidado
  });
});

exports("insertMany", (col: string, docs: any[]) => {
  return execute(col, async (c) => {
    const res = await c.insertMany(toDates(docs));
    return Object.values(res.insertedIds).map((id) => id.toHexString());
  });
});

exports("deleteOne", (col: string, filter: any) => {
  return execute(col, async (c) => {
    const res = await c.deleteOne(normalizeFilter(filter));
    return res.deletedCount;
  });
});

exports("deleteMany", (col: string, filter: any) => {
  return execute(col, async (c) => {
    const res = await c.deleteMany(normalizeFilter(filter));
    return res.deletedCount;
  });
});

exports("updateOne", (col: string, filter: any, update: any, options?: any) => {
  return execute(col, async (c) => {
    const res = await c.updateOne(
      normalizeFilter(filter),
      normalizeDoc(update),
      fixEmptyTable(options),
    );
    return updateSummary(res);
  });
});

exports("updateMany", (col: string, filter: any, update: any, options?: any) => {
  return execute(col, async (c) => {
    const res = await c.updateMany(
      normalizeFilter(filter),
      normalizeDoc(update),
      fixEmptyTable(options),
    );
    return updateSummary(res);
  });
});

// Varias escrituras en un solo viaje (y un solo comando contra mongod). Ojo con
// los fallos parciales: el driver lanza si alguna op falla, así que el envelope
// sale { ok: false } y se pierden los contadores — con `ordered: true` (default)
// las ops anteriores ya están escritas, y con `ordered: false` todas menos la
// que falló. Reintentar solo es seguro si las ops son idempotentes.
exports("bulkWrite", (col: string, ops: any[], options?: any) => {
  return execute(col, async (c) => {
    const res = await c.bulkWrite(normalizeBulkOps(ops), fixEmptyTable(options));
    return bulkSummary(res);
  });
});

exports("aggregate", (col: string, pipeline: any[]) => {
  return execute(col, (c) =>
    c.aggregate(toDates(Array.isArray(pipeline) ? pipeline : [])).toArray(),
  );
});

// Índices. Imprescindible para TTL: createIndex({ expiresAt: 1 },
// { expireAfterSeconds: 0 }) + docs con expiresAt de tipo Date ($date).
// Idempotente si la definición no cambia; redefinir el mismo campo con
// options distintas devuelve error de Mongo (drop manual o collMod).
exports("createIndex", (col: string, keys: any, options?: any) => {
  return execute(col, (c) =>
    c.createIndex(fixEmptyTable(keys), fixEmptyTable(options)),
  );
});

exports("count", (col: string, filter: any) => {
  return execute(col, (c) => c.countDocuments(normalizeFilter(filter)));
});

// En el driver v6+ findOneAnd* devuelve el documento directamente (o null).
// returnDocument por defecto 'after'; el caller puede sobreescribirlo en options.
exports(
  "findOneAndUpdate",
  (col: string, filter: any, update: any, options?: any) => {
    return execute(col, (c) =>
      c.findOneAndUpdate(normalizeFilter(filter), normalizeDoc(update), {
        returnDocument: "after",
        ...fixEmptyTable(options),
      }),
    );
  },
);

exports("findOneAndDelete", (col: string, filter: any, options?: any) => {
  return execute(col, (c) =>
    c.findOneAndDelete(normalizeFilter(filter), fixEmptyTable(options)),
  );
});

exports(
  "findOneAndReplace",
  (col: string, filter: any, replacement: any, options?: any) => {
    return execute(col, (c) =>
      c.findOneAndReplace(normalizeFilter(filter), normalizeDoc(replacement), {
        returnDocument: "after",
        ...fixEmptyTable(options),
      }),
    );
  },
);

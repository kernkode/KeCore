import bcrypt from "bcryptjs";
import * as os from "os";
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

    // El rechazo va en el turno SIGUIENTE y no en el momento de devolver la promesa. FXServer cuenta
    // una promesa como huérfana en el instante en que se rechaza, así que con un `Promise.reject` ya
    // rechazado el `catch` del driver —que llega después, cuando hace el `await`— no le quitaba el
    // aviso: seguía saliendo el "Unhandled promise rejection in resource libs" con su stack. Estando
    // PENDIENTE al devolverla, el orden se invierte: primero el dueño, después el rechazo.
    return new Promise((_resolve, reject) => {
      setTimeout(() => reject(new Error("ENOENT: fuera del sandbox de FXServer")), 0);
    });
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
    // El plazo para ELEGIR servidor, que es el que cubre el arranque: mongod tarda más en estar listo
    // que FXServer, y con 5 s la primera consulta moría por timeout justo antes de que la conexión se
    // completara (auth preguntaba por el personaje y se llevaba un nil que no era verdad). El driver
    // reintenta DENTRO de ese plazo, así que con la base lista en dos segundos no se espera más: lo
    // único que cambia es que deja de fallar cuando tarda.
    serverSelectionTimeoutMS: GetConvarInt("mongodb_server_selection_timeout_ms", 30000),
    connectTimeoutMS: GetConvarInt("mongodb_connect_timeout_ms", 5000),
    socketTimeoutMS: 45000,
    maxPoolSize: GetConvarInt("mongodb_max_pool_size", 10),
    minPoolSize: 1,
    monitorCommands: false,
    forceServerObjectId: false,
    // El driver carga `os` con un `await import("os")` (lib/runtime_adapters.js), y en el bundle IIFE
    // que corre dentro de FXServer ese import dinámico se queda literal y no resuelve nunca. Su
    // promesa se rechaza, `makeClientMetadata` casca en su primera línea (`const { os } = await
    // runtime`) y el handshake sale sin el sub-documento `driver`: entonces el servidor rechaza TODAS
    // las operaciones con "Missing required sub-document 'driver' in the client metadata document",
    // que no suena a esto en absoluto. El propio driver deja la puerta abierta para runtimes donde
    // ese import falla — dándole el módulo ya cargado, el import dinámico ni se evalúa.
    runtimeAdapters: { os },
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


function normalizeIndexKeys(keys: any): any {
  const value = fixEmptyTable(keys);
  if (!Array.isArray(value)) return value;

  for (const pair of value) {
    if (!Array.isArray(pair) || pair.length !== 2 || typeof pair[0] !== "string") {
      throw new Error("createIndex keys must be ordered { { field, direction }, ... }");
    }
  }
  return value;
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
  /** La conexión en marcha, para que los que lleguen a la vez esperen a la MISMA. */
  private connecting: Promise<void> | null = null;

  private constructor() {
    this.client = new MongoClient(CONFIG.URL, CONFIG.OPTIONS);

    this.client.on("open", () => {
      this.isConnected = true;
      console.log(`✅ [MongoDB] Conectado a base de datos: ${CONFIG.DB_NAME}`);
    });

    this.client.on("close", () => {
      this.isConnected = false;
      // La conexión compartida ya no vale: el siguiente que pida DB tiene que abrir de nuevo y no
      // esperar a la promesa —ya cumplida— de la conexión que se acaba de caer.
      this.connecting = null;
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
    if (!this.isConnected) {
      // UNA conexión para todos los que lleguen a la vez. Sin esto, cada operación del arranque
      // —auth mirando el personaje, core cargando lo suyo— entraba aquí con `isConnected` en false y
      // lanzaba su propio `connect` + `ping`, cada uno con su plazo de selección corriendo por su
      // cuenta: el primero moría por timeout mientras la conexión de al lado se estaba completando.
      if (!this.connecting) this.connecting = this.open(dbName);

      try {
        await this.connecting;
      } finally {
        // Si salió mal, el siguiente lo vuelve a intentar en vez de heredar el fallo de este.
        if (!this.isConnected) this.connecting = null;
      }
    }

    // Si cambiamos de DB o es la primera vez
    if (!this.db || this.db.databaseName !== dbName) {
      this.db = this.client.db(dbName);
    }

    return this.db;
  }

  /** Conecta y comprueba que responde. Solo se llama desde `getDb`, una vez. */
  private async open(dbName: string): Promise<void> {
    await this.client.connect();

    // Verificación inicial (solo al conectar, no en cada query)
    this.db = this.client.db(dbName);
    await this.db.command({ ping: 1 });
    this.isConnected = true;
  }

  public async disconnect(): Promise<void> {
    if (this.client) {
      await this.client.close();
      this.isConnected = false;
      this.db = null;
      // Y la conexión compartida, fuera: si no, el siguiente `getDb` esperaría a una que ya se cerró.
      this.connecting = null;
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
    // Una tabla Lua no conserva el orden de campos; la lista de pares sí, y Mongo lo necesita
    // porque { a: 1, b: 1 } y { b: 1, a: 1 } son índices distintos.
    c.createIndex(normalizeIndexKeys(keys), fixEmptyTable(options)),
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

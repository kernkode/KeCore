import bcrypt from 'bcryptjs';
import { MongoClient, Db, ObjectId, MongoClientOptions, Collection, Document } from 'mongodb';

exports('bcrypt_js', () => {
    return bcrypt;
})

// --- Polyfill de Performance (Entornos Legacy) ---
if (typeof global.performance === 'undefined') {
    try {
        const { performance } = require('perf_hooks');
        global.performance = performance;
    } catch {
        console.warn('⚠️ [MongoDB] No se pudo cargar perf_hooks.');
    }
}

// --- Configuración (Cacheada al inicio) ---
// Leer las Convars una sola vez al iniciar el script ahorra CPU
const CONFIG = {
    URL: GetConvar('mongodb_url', 'mongodb://localhost:27017'),
    DB_NAME: GetConvar('mongodb_database', 'server'), // Configurable por variable
    OPTIONS: {
        serverSelectionTimeoutMS: 5000,
        connectTimeoutMS: GetConvarInt("mongodb_connect_timeout_ms", 5000),
        socketTimeoutMS: 45000,
        maxPoolSize: GetConvarInt('mongodb_max_pool_size', 10),
        minPoolSize: 1, 
        monitorCommands: false,
        forceServerObjectId: false,
        // family: 4 // Descomentar si tienes problemas con IPv6
    } as MongoClientOptions
};

// --- Utilidades ---

/**
 * Normaliza filtros recursivamente para convertir strings hexadecimales en ObjectId.
 * Optimizado para fallar rápido si no es necesario convertir.
 */
function normalizeFilter(filter: any): any {
    if (!filter) return {};
    
    // Caso base rápido
    if (filter instanceof ObjectId) return filter;
    
    // String ID directo
    if (typeof filter === 'string') {
        return ObjectId.isValid(filter) ? new ObjectId(filter) : filter;
    }

    // Arrays ($in, $or, etc)
    if (Array.isArray(filter)) {
        return filter.map(normalizeFilter);
    }

    // Objetos
    if (typeof filter === 'object') {
        const newObj: any = {};
        for (const key in filter) {
            const value = filter[key];
            
            // Solo convertimos _id o si es un operador que podría contener IDs
            if (key === '_id' || key.endsWith('Id')) {
                newObj[key] = normalizeFilter(value);
            } else {
                // Recursión profunda solo si es objeto o array
                newObj[key] = (typeof value === 'object' && value !== null) 
                    ? normalizeFilter(value) 
                    : value;
            }
        }
        return newObj;
    }

    return filter;
}

// --- Singleton de Conexión ---
class MongoService {
    private static instance: MongoService;
    private client: MongoClient;
    private db: Db | null = null;
    private isConnected: boolean = false;

    private constructor() {
        this.client = new MongoClient(CONFIG.URL, CONFIG.OPTIONS);
        
        this.client.on('open', () => {
            this.isConnected = true;
            console.log(`✅ [MongoDB] Conectado a base de datos: ${CONFIG.DB_NAME}`);
        });

        this.client.on('close', () => {
            this.isConnected = false;
            console.log('🔌 [MongoDB] Conexión cerrada');
        });
        
        this.client.on('error', (err) => console.error('❌ [MongoDB] Error de cliente:', err));
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

// --- Wrapper Genérico (Safe Execute) ---
async function execute<T>(
    collectionName: string, 
    operation: (col: Collection) => Promise<T>
): Promise<string | number | boolean | null> {
    try {
        const service = MongoService.getInstance();
        const db = await service.getDb();
        const collection = db.collection(collectionName);
        
        const result = await operation(collection);

        // Retorno optimizado para Lua/FiveM
        if (result === null || result === undefined) return null;
        if (typeof result === 'object') return JSON.stringify(result);
        return result as any; 

    } catch (error: any) {
        console.error(`❌ [MongoDB] Error en '${collectionName}':`, error.message);
        return JSON.stringify({ status: 'error', message: error.message });
    }
}

// --- EXPORTS ---

// Inicialización explícita (Opcional, pero recomendada al iniciar el recurso)
exports('connect', async (dbName?: string) => {
    try {
        await MongoService.getInstance().getDb(dbName);
        return true;
    } catch (e) {
        return false;
    }
});

exports('disconnect', async () => {
    await MongoService.getInstance().disconnect();
});

exports('isConnected', () => {
    return MongoService.getInstance().isReady();
});

// Operaciones CRUD

exports('findOne', (col: string, filter: any) => {
    return execute(col, c => c.findOne(normalizeFilter(filter)));
});

exports('find', (col: string, filter: any, options?: any) => {
    return execute(col, c => c.find(normalizeFilter(filter), options || {}).toArray());
});

exports('insertOne', (col: string, doc: any) => {
    return execute(col, async c => {
        const res = await c.insertOne(doc);
        return res.insertedId;
    });
});

exports('insertMany', (col: string, docs: any[]) => {
    return execute(col, async c => {
        const res = await c.insertMany(docs);
        return Object.values(res.insertedIds); // Devuelve array de IDs
    });
});

exports('deleteOne', (col: string, filter: any) => {
    return execute(col, async c => {
        const res = await c.deleteOne(normalizeFilter(filter));
        return res.deletedCount;
    });
});

exports('deleteMany', (col: string, filter: any) => {
    return execute(col, async c => {
        const res = await c.deleteMany(normalizeFilter(filter));
        return res.deletedCount;
    });
});

exports('updateOne', (col: string, filter: any, update: any) => {
    return execute(col, async c => {
        const res = await c.updateOne(normalizeFilter(filter), update);
        return res.modifiedCount;
    });
});

exports('updateMany', (col: string, filter: any, update: any) => {
    return execute(col, async c => {
        const res = await c.updateMany(normalizeFilter(filter), update);
        return res.modifiedCount;
    });
});

exports('aggregate', (col: string, pipeline: any[]) => {
    return execute(col, c => c.aggregate(pipeline).toArray());
});

exports('count', (col: string, filter: any) => {
    return execute(col, c => c.countDocuments(normalizeFilter(filter)));
});

// En drivers modernos (v5+), findOneAndUpdate devuelve un objeto ModifyResult o el doc directo según config.
// Forzamos returnDocument: 'after' para obtener el nuevo, o 'before' para el viejo.
exports('findOneAndUpdate', (col: string, filter: any, update: any, options: any) => {
    return execute(col, async c => {
        const opts = { returnDocument: 'after', ...options }; // Default devuelve el nuevo
        const res = await c.findOneAndUpdate(normalizeFilter(filter), update, opts);
        // Compatibilidad con drivers nuevos que devuelven el doc directamente o null
        return res; 
    });
});
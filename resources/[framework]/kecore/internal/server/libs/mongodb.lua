--[[
    kec.mongodb — query builder + schemas/modelos (estilo Mongoose) sobre el
    bridge TypeScript del recurso `libs` (driver oficial de MongoDB).

    Este archivo es la fuente editable: se transpila a
    performance/server/mongodb.lua (`bun run gen:performance`) y cada consumidor
    lo ejecuta LOCALMENTE vía @kecore/init.lua — solo la llamada final al bridge
    cruza recursos, nunca la cadena del builder.

    Protocolo del bridge: cada operación devuelve un string JSON con forma
    { ok = true, data = ... } | { ok = false, error = "..." }.

    Contrato de retorno: todos los métodos terminales devuelven
    (resultado, err). En fallo de DB el resultado es nil y err trae el mensaje;
    nunca se fabrican datos (un count fallido NO es 0, es nil).

    Uso rápido:
        local q = kec.mongodb:collection("characters")
        local docs, err = q:where("account_id", id):sort({ _id = 1 }):find()

        kec.mongodb:schema("Character", {
            collection = "characters",
            schema = { type = "object", properties = { ... }, required = { ... } },
            defaults = { position = { 0.0, 0.0, 72.0, 0.0 } }
        })
        local Character = kec.mongodb:model("Character") -- desde cualquier recurso
        local id, err = Character:create({ ... })         -- valida + defaults + insert
]]

kec.mongodb = {}

local bridge = exports.libs

--- Decodifica el envelope del bridge → (data, err).
--- ok sin data (p. ej. findOne sin resultado) devuelve (nil, nil).
local function decode(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil, "bridge sin respuesta (¿recurso 'libs' iniciado?)"
    end

    local okDecode, res = pcall(json.decode, raw)
    if not okDecode or type(res) ~= "table" then
        return nil, "respuesta ilegible del bridge: " .. tostring(raw)
    end

    if not res.ok then
        return nil, res.error or "error desconocido de MongoDB"
    end

    return res.data, nil
end

local function mergeInto(target, override)
    if override then
        for k, v in pairs(override) do target[k] = v end
    end
    return target
end

local function deepcopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepcopy(v) end
    return copy
end

-- ─────────────────────────────────────────────────────────────────────────
-- Fechas BSON
-- ─────────────────────────────────────────────────────────────────────────

--- Marcador de fecha BSON real (convención Extended JSON del bridge):
--- { ["$date"] = ms }. Úsalo en docs/filtros/updates donde necesites un
--- Date de verdad — p. ej. índices TTL, que ignoran números unix.
--- Al leer no hay conversión inversa: los Date vuelven como string ISO-8601.
---@param seconds number|nil unix seconds (default: ahora)
---@return table dateMarker
function kec.mongodb:date(seconds)
    return { ["$date"] = math.floor((seconds or os.time()) * 1000) }
end

-- ─────────────────────────────────────────────────────────────────────────
-- Query builder
-- ─────────────────────────────────────────────────────────────────────────

--- Crea un builder encadenable sobre una colección.
--- Los métodos terminales aceptan overrides en el orden estándar de MongoDB:
--- (filter, update, options).
function kec.mongodb:collection(collectionName)
    local query = {
        collection = collectionName,
        filter = {},
        update = nil,
        options = {},
        data = nil,
        documents = nil
    }

    -- Encadenables ---------------------------------------------------------

    function query:where(field, value)
        self.filter[field] = value
        return self
    end

    function query:limit(n) self.options.limit = n return self end
    function query:skip(n) self.options.skip = n return self end
    function query:sort(order) self.options.sort = order return self end
    function query:projection(fields) self.options.projection = fields return self end
    function query:set(data) self.data = data return self end
    function query:add(documents) self.documents = documents return self end
    function query:updateData(update) self.update = update return self end

    -- READ ------------------------------------------------------------------

    ---@return table|nil docs, string|nil err
    function query:find(filterOverride)
        mergeInto(self.filter, filterOverride)
        return decode(bridge:find(self.collection, self.filter, self.options))
    end

    ---@return table|nil doc, string|nil err
    function query:findOne(filterOverride)
        mergeInto(self.filter, filterOverride)
        self.options.limit = 1
        local docs, err = decode(bridge:find(self.collection, self.filter, self.options))
        if not docs then return nil, err end
        return docs[1]
    end

    query.first = query.findOne -- alias histórico

    ---@return number|nil count, string|nil err
    function query:count(filterOverride)
        mergeInto(self.filter, filterOverride)
        return decode(bridge:count(self.collection, self.filter))
    end

    ---@return boolean|nil exists, string|nil err
    function query:exists(filterOverride)
        local n, err = self:count(filterOverride)
        if n == nil then return nil, err end
        return n > 0
    end

    ---@return table|nil results, string|nil err
    function query:aggregate(pipeline)
        if type(pipeline) ~= "table" or #pipeline == 0 then
            error("aggregate: falta el pipeline (array de stages)")
        end
        return decode(bridge:aggregate(self.collection, pipeline))
    end

    -- WRITE -----------------------------------------------------------------

    --- Devuelve el _id insertado como string hex.
    ---@return string|nil insertedId, string|nil err
    function query:insertOne(doc)
        doc = doc or self.data
        if type(doc) ~= "table" or next(doc) == nil then
            error("insertOne: falta el documento (usa :set(doc) o pásalo como argumento)")
        end
        return decode(bridge:insertOne(self.collection, doc))
    end

    ---@return table|nil insertedIds, string|nil err
    function query:insertMany(docs)
        docs = docs or self.documents
        if type(docs) ~= "table" or #docs == 0 then
            error("insertMany: falta el array de documentos (usa :add(docs) o pásalo como argumento)")
        end
        return decode(bridge:insertMany(self.collection, docs))
    end

    --- Devuelve { matched, modified, upserted? } (upserted = _id hex si aplicó).
    ---@return table|nil result, string|nil err
    function query:updateOne(filterOverride, updateOverride, options)
        mergeInto(self.filter, filterOverride)
        local update = updateOverride or self.update
        if type(update) ~= "table" or next(update) == nil then
            error("updateOne: falta el update (usa :updateData(u) o pásalo como 2º argumento)")
        end
        return decode(bridge:updateOne(self.collection, self.filter, update, options or {}))
    end

    ---@return table|nil result, string|nil err
    function query:updateMany(filterOverride, updateOverride, options)
        mergeInto(self.filter, filterOverride)
        local update = updateOverride or self.update
        if type(update) ~= "table" or next(update) == nil then
            error("updateMany: falta el update (usa :updateData(u) o pásalo como 2º argumento)")
        end
        return decode(bridge:updateMany(self.collection, self.filter, update, options or {}))
    end

    ---@return number|nil deletedCount, string|nil err
    function query:deleteOne(filterOverride)
        mergeInto(self.filter, filterOverride)
        return decode(bridge:deleteOne(self.collection, self.filter))
    end

    ---@return number|nil deletedCount, string|nil err
    function query:deleteMany(filterOverride)
        mergeInto(self.filter, filterOverride)
        return decode(bridge:deleteMany(self.collection, self.filter))
    end

    --- Devuelve el documento (por defecto la versión posterior al update).
    ---@return table|nil doc, string|nil err
    function query:findOneAndUpdate(filterOverride, updateOverride, options)
        mergeInto(self.filter, filterOverride)
        local update = updateOverride or self.update
        if type(update) ~= "table" or next(update) == nil then
            error("findOneAndUpdate: falta el update (usa :updateData(u) o pásalo como 2º argumento)")
        end
        return decode(bridge:findOneAndUpdate(self.collection, self.filter, update, options or {}))
    end

    ---@return table|nil doc, string|nil err
    function query:findOneAndDelete(filterOverride, options)
        mergeInto(self.filter, filterOverride)
        return decode(bridge:findOneAndDelete(self.collection, self.filter, options or {}))
    end

    ---@return table|nil doc, string|nil err
    function query:findOneAndReplace(filterOverride, replacement, options)
        mergeInto(self.filter, filterOverride)
        replacement = replacement or self.data
        if type(replacement) ~= "table" then
            error("findOneAndReplace: falta el documento de reemplazo")
        end
        return decode(bridge:findOneAndReplace(self.collection, self.filter, replacement, options or {}))
    end

    --- Varias escrituras en un solo viaje al bridge (y un solo comando contra
    --- mongod). Cada op es una tabla con UNA clave, con la forma del driver:
    ---   { insertOne  = { document = doc } }
    ---   { updateOne  = { filter = f, update = { ["$set"] = d }, upsert = true } }
    ---   { updateMany = { filter = f, update = u } }
    ---   { replaceOne = { filter = f, replacement = doc } }
    ---   { deleteOne  = { filter = f } }  { deleteMany = { filter = f } }
    --- options: { ordered = false } para no parar en el primer fallo.
    --- OJO: si una op falla devuelve (nil, err) y se pierden los contadores,
    --- pero las escrituras que ya pasaron NO se deshacen (no hay transacción):
    --- reintentar solo es seguro si las ops son idempotentes.
    ---@return table|nil result { inserted, matched, modified, deleted, upserted, insertedIds, upsertedIds }
    ---@return string|nil err
    function query:bulkWrite(ops, options)
        if type(ops) ~= "table" or #ops == 0 then
            error("bulkWrite: falta el array de operaciones")
        end
        return decode(bridge:bulkWrite(self.collection, ops, options or {}))
    end

    -- INDEXES ----------------------------------------------------------------

    --- Crea un índice y devuelve su nombre. Para TTL:
    ---   :createIndex({ expiresAt = 1 }, { expireAfterSeconds = 0 })
    --- con docs que lleven expiresAt = kec.mongodb:date(unix). Idempotente si
    --- la definición no cambia; redefinir el mismo campo con options distintas
    --- devuelve (nil, err) de Mongo.
    ---@return string|nil indexName, string|nil err
    function query:createIndex(keys, options)
        if type(keys) ~= "table" or next(keys) == nil then
            error("createIndex: faltan las claves del índice, ej. { campo = 1 }")
        end
        return decode(bridge:createIndex(self.collection, keys, options or {}))
    end

    return query
end

-- ─────────────────────────────────────────────────────────────────────────
-- Schemas / Modelos
-- ─────────────────────────────────────────────────────────────────────────

-- Definiciones registradas por ESTE recurso: si kecore reinicia (y pierde el
-- registro central), este recurso las re-registra solo contra la instancia nueva.
local ownSchemas = {}

local function buildModel(name, definition)
    local model = {
        name = name,
        collectionName = definition.collection,
        definition = definition,
        validator = kec.zod:new(definition.schema)
    }

    --- Builder crudo sobre la colección del modelo (para sort/projection/etc).
    function model:collection()
        return kec.mongodb:collection(self.collectionName)
    end

    ---@return boolean ok, string err
    function model:validate(doc)
        return self.validator:validate(doc)
    end

    --- Aplica defaults, valida contra el schema e inserta.
    --- ponytail: valida solo en create; los updates ($set parciales) no se
    --- validan — valida a mano con model:validate si te importa ese camino.
    ---@return string|nil insertedId, string|nil err
    function model:create(doc)
        doc = doc or {}

        if self.definition.defaults then
            for k, v in pairs(self.definition.defaults) do
                if doc[k] == nil then doc[k] = deepcopy(v) end
            end
        end

        local ok, err = self.validator:validate(doc)
        if not ok then
            return nil, ("schema '%s': %s"):format(self.name, err)
        end

        return self:collection():insertOne(doc)
    end

    function model:find(filter) return self:collection():find(filter) end
    function model:findOne(filter) return self:collection():findOne(filter) end
    function model:count(filter) return self:collection():count(filter) end
    function model:exists(filter) return self:collection():exists(filter) end
    function model:updateOne(filter, update, options) return self:collection():updateOne(filter, update, options) end
    function model:updateMany(filter, update, options) return self:collection():updateMany(filter, update, options) end
    function model:deleteOne(filter) return self:collection():deleteOne(filter) end
    function model:deleteMany(filter) return self:collection():deleteMany(filter) end
    function model:findOneAndUpdate(filter, update, options) return self:collection():findOneAndUpdate(filter, update, options) end
    function model:bulkWrite(ops, options) return self:collection():bulkWrite(ops, options) end
    function model:aggregate(pipeline) return self:collection():aggregate(pipeline) end

    return model
end

--- Registra un schema en el registro central de kecore y devuelve su modelo.
--- definition = {
---     collection = "characters",           -- colección de MongoDB
---     schema     = { type = "object", ... } -- schema estilo kec.zod
---     defaults   = { campo = valor, ... }   -- opcional, aplicados en :create
--- }
function kec.mongodb:schema(name, definition)
    local err = kec.mongoSchemaRegister(name, definition)
    if err then
        error(("[mongodb] %s"):format(err))
    end

    ownSchemas[name] = definition
    return buildModel(name, definition)
end

--- Importa un modelo por nombre desde cualquier recurso. El recurso que
--- define el schema debe arrancar antes (orden de scripts.cfg).
--- Sin cache a propósito: cada model() construye desde la definición vigente
--- del registro, así un hot-reload del recurso que la define no deja modelos
--- rancios en los demás. OJO: un model capturado en variable top-level sí
--- queda fijado hasta que ese recurso reinicie.
function kec.mongodb:model(name)
    local definition = kec.mongoSchemaGet(name)
    if not definition then
        error(("[mongodb] schema '%s' no registrado. El recurso que lo define debe arrancar antes (scripts.cfg)."):format(name))
    end

    return buildModel(name, definition)
end

-- Si kecore reinicia, su registro central nace vacío; cada recurso re-registra
-- sus propios schemas contra la instancia nueva (refs frescas vía export).
AddEventHandler("onResourceStart", function(res)
    if res ~= "kecore" or next(ownSchemas) == nil then return end

    local fresh = exports.kecore:get()
    if type(fresh) ~= "table" or type(fresh.mongoSchemaRegister) ~= "function" then return end

    for name, definition in pairs(ownSchemas) do
        local err = fresh.mongoSchemaRegister(name, definition)
        if err then
            print(("^1[mongodb] re-registro de schema '%s' falló: %s^0"):format(name, err))
        end
    end
end)

-- ─────────────────────────────────────────────────────────────────────────
-- Conexión
-- ─────────────────────────────────────────────────────────────────────────

---@return boolean ok
function kec.mongodb:connect(databaseName)
    return bridge:connect(databaseName)
end

function kec.mongodb:disconnect()
    return bridge:disconnect()
end

---@return boolean
function kec.mongodb:isConnected()
    return bridge:isConnected()
end

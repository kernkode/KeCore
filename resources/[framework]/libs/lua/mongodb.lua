-- mongodb.lua
mongodb = {}
local mongo_bridge = exports.libs

-- Helper seguro para decodificar JSON
local function safeDecode(data)
    if not data or data == "" then return nil end
    local status, result = pcall(json.decode, data)
    if not status then
        print("^1[MongoDB] Error decoding JSON: " .. tostring(result) .. "^0")
        return nil
    end
    return result
end

-- Método para crear una instancia de consulta
function mongodb:collection(collectionName)
    local queryState = {
        collection = collectionName,
        filter = {},
        update = {},
        pipeline = {},
        options = {},
        data = nil,
        documents = nil
    }

    local methods = {}

    -- Inicializamos self con el estado
    for k, v in pairs(queryState) do
        methods[k] = v
    end

    function methods:where(field, value)
        self.filter[field] = value
        return self
    end

    function methods:limit(n)
        self.options.limit = n
        return self
    end

    function methods:skip(n)
        self.options.skip = n
        return self
    end

    function methods:sort(order)
        self.options.sort = order
        return self
    end

    function methods:projection(fields)
        self.options.projection = fields
        return self
    end

    function methods:set(data)
        self.data = data
        return self
    end

    function methods:add(documents)
        self.documents = documents
        return self
    end

    function methods:updateData(updateData) -- Renombrado de 'update' a 'updateData' para evitar conflictos
        self.update = updateData
        return self
    end

    -- READ: Ejecuta la búsqueda y devuelve todos los resultados
    function methods:find(filterOverride)
        -- Si se pasa un filtro aquí, se mezcla o sobreescribe el existente
        if filterOverride then 
            for k, v in pairs(filterOverride) do self.filter[k] = v end
        end

        local data = mongo_bridge:find(self.collection, self.filter, self.options)
        return safeDecode(data)
    end

    -- READ: Ejecuta y devuelve solo el primer resultado
    function methods:first(filterOverride)
        if filterOverride then 
            for k, v in pairs(filterOverride) do self.filter[k] = v end
        end
        
        self.options.limit = 1
        local data = mongo_bridge:find(self.collection, self.filter, self.options)
        local result = safeDecode(data)
        return result and result[1] or nil
    end
    
    -- READ: Alias para findOne (mismo comportamiento que first)
    function methods:findOne(filterOverride)
        return self:first(filterOverride)
    end

    -- READ: Ejecuta conteo
    function methods:count(filterOverride)
        if filterOverride then
            for k, v in pairs(filterOverride) do self.filter[k] = v end
        end
        return mongo_bridge:count(self.collection, self.filter)
    end

    function methods:exists(filterOverride)
        if filterOverride then
            for k, v in pairs(filterOverride) do self.filter[k] = v end
        end
        local count = mongo_bridge:count(self.collection, self.filter)
        return count > 0
    end

    -- AGGREGATION: Ejecuta pipeline
    function methods:aggregate(pipelineOverride)
        local pipe = pipelineOverride or self.pipeline
        if not pipe or #pipe == 0 then error("No pipeline provided for aggregate") end
        
        local data = mongo_bridge:aggregate(self.collection, pipe)
        return safeDecode(data)
    end

    -- WRITE: Insertar Uno
    function methods:insertOne(dataOverride)
        local doc = dataOverride or self.data
        if not doc then error("No data provided for insertOne") end
        return mongo_bridge:insertOne(self.collection, doc)
    end
    
    -- WRITE: Insertar Varios
    function methods:insertMany(documentsOverride)
        local docs = documentsOverride or self.documents
        if not docs then error("No documents provided for insertMany") end
        return mongo_bridge:insertMany(self.collection, docs)
    end
    
    -- WRITE: Actualizar Uno
    function methods:updateOne(updateDataOverride, filterOverride)
        local upd = updateDataOverride or self.update
        local flt = filterOverride or self.filter
        
        if not upd then error("No update data provided for updateOne") end
        -- Permitimos update sin filtro explícito (usando el del builder) si 'flt' está vacío, 
        -- pero MongoDB requiere un filtro aunque sea {}, así que lo validamos.
        
        return mongo_bridge:updateOne(self.collection, flt, upd)
    end
    
    -- WRITE: Actualizar Varios
    function methods:updateMany(updateDataOverride, filterOverride)
        local upd = updateDataOverride or self.update
        local flt = filterOverride or self.filter
        
        if not upd then error("No update data provided for updateMany") end
        
        return mongo_bridge:updateMany(self.collection, flt, upd)
    end
    
    -- WRITE: Eliminar Uno
    function methods:deleteOne(filterOverride)
        local flt = filterOverride or self.filter
        return mongo_bridge:deleteOne(self.collection, flt)
    end
    
    -- WRITE: Eliminar Varios
    function methods:deleteMany(filterOverride)
        local flt = filterOverride or self.filter
        return mongo_bridge:deleteMany(self.collection, flt)
    end
    
    -- FIND AND MODIFY
    function methods:findOneAndUpdate(updateDataOverride, options, filterOverride)
        local upd = updateDataOverride or self.update
        local flt = filterOverride or self.filter
        
        if not upd then error("No update data provided for findOneAndUpdate") end

        local data = mongo_bridge:findOneAndUpdate(self.collection, flt, upd, options or {})
        return safeDecode(data)
    end

    function methods:findOneAndDelete(filterOverride, options)
        local flt = filterOverride or self.filter
        local data = mongo_bridge:findOneAndDelete(self.collection, flt, options or {})
        return safeDecode(data)
    end

    function methods:findOneAndReplace(replacementOverride, options, filterOverride)
        local flt = filterOverride or self.filter
        local rep = replacementOverride or self.data
        
        if not rep then error("No replacement data provided for findOneAndReplace") end

        local data = mongo_bridge:findOneAndReplace(self.collection, flt, rep, options or {})
        return safeDecode(data)
    end

    return methods
end

function mongodb:connect(databaseName)
    return mongo_bridge:connect(databaseName)
end

function mongodb:disconnect()
    return mongo_bridge:disconnect()
end

function mongodb:isConnected()
    return mongo_bridge:isConnected()
end
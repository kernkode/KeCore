player_methods = {}

-- Establecer modelo del jugador
function player_methods:setModel(modelHash)
    kec:emitClient("setModel", self.id, modelHash)
end

-- Hacer spawn del jugador
function player_methods:spawn(coords, heading, modelHash)
    kec:emitClient("kec:setSpawn", self.id, coords, heading, modelHash)
end

function player_methods:setCoords(x, y, z, rot)
    kec:emitClient("kec:setCoords", self.id, x, y, z, rot)
end

function player_methods:setVariation(componentId, drawableId, textureId, paletteId)
    kec:emitClient("kec:setComponentVariation", self.id, componentId, drawableId, textureId, paletteId)
end

function player_methods:setModel(modelHash)
    if type(modelHash) == "string" then
        modelHash = kec:hash(modelHash)
    end

    SetPlayerModel(self.id, modelHash)
end

function player_methods:emit(name, ...)
    kec:emitClient(name, self.id, ...)
end

function player_methods:kick(reason)
    DropPlayer(self.id, reason)
end

function player_methods:setInfo(key, value)
    player_info[tostring(self.id)] = player_info[tostring(self.id)] or {}
    player_info[tostring(self.id)][key] = value
end

function player_methods:setInfoMultiple(infoTable)
    player_info[tostring(self.id)] = player_info[tostring(self.id)] or {}
    for key, value in pairs(infoTable) do
        player_info[tostring(self.id)][key] = value
    end
end

function player_methods:getInfo(key)
    return player_info[tostring(self.id)] and player_info[tostring(self.id)][key] or nil
end

function player_methods:getCoords()
    return GetEntityCoords(self:ped())
end

function player_methods:getRot()
    return GetEntityRotation(self:ped()).z
end

--- Establecer metadato sincronizados (stream)
---@param key any
---@param value any
---@return any
function player_methods:setStreamSyncedMeta(key, value)
    local ped = GetPlayerPed(self.id)
    Entity(ped).state:set(key, value, true)
end

--- Establecer múltiples metadatos sincronizados (stream) de una sola vez
---@param data table Tabla con pares clave-valor a establecer
---@return any
function player_methods:setStreamSyncedMetaMultiple(data)
    local ped = GetPlayerPed(self.id)
    local state = Entity(ped).state

    for key, value in pairs(data) do
        state:set(key, value, true)
    end
end

function player_methods:getStreamSyncedMeta(key)
    local ped = GetPlayerPed(self.id)
    return Entity(ped).state[key]
end

function player_methods:setSyncedMeta(key, value)
    local src = tostring(self.id)
    local section = self.type

    metadata[section][src] = metadata[section][src] or {}
    metadata[section][src][key] = value
    kec:emitAllClients("kec:setSyncedMeta", section, self.id, key, value)
end


--- Establecer múltiples metadatos sincronizados
---@param data table Tabla con los pares clave-valor (ej: { trabajo = "policia", rango = 2 })
function player_methods:setSyncedMetaMultiple(data)
    if type(data) ~= "table" then return end

    local source = tostring(self.id)
    local section = self.type
    metadata[section][source] = metadata[section][source] or {}

    for key, value in pairs(data) do
        metadata[section][source][key] = value
        kec:emitAllClients("kec:setSyncedMeta", section, self.id, key, value)
    end
end

function player_methods:getSyncedMeta(key)
    local source = tostring(self.id)
    if not metadata[self.type][source] then return nil end

    return metadata[self.type][source][key] or nil
end

function player_methods:ped()
    return GetPlayerPed(self.id)
end

function player_methods:clearMetadata()
    local src = tostring(self.id)
    local section = self.type

    if not metadata[section][src] then return end

    metadata[section][src] = nil
    kec:emitAllClients("kec:clearMetadata", section, self.id)
end

player_methods = {}



-- Hacer spawn del jugador
function player_methods:spawn(coords, heading, modelHash)
    kec:emitClient("kec:setSpawn", self.id, coords, heading, modelHash)
end

function player_methods:setCoords(x, y, z, rot)
    kec:emitClient("kec:setCoords", self.id, x, y, z, rot)
end

function player_methods:setIntoVehicle(vehicle, seat)
    seat = seat or -1
    local netId = type(vehicle) == "table" and vehicle.entity and NetworkGetNetworkIdFromEntity(vehicle.entity)
        or type(vehicle) == "number" and NetworkGetNetworkIdFromEntity(vehicle) or vehicle
    kec:emitClient("kec:setIntoVehicle", self.id, netId, seat)
end

function player_methods:setVariation(componentId, drawableId, textureId, paletteId)
    kec:emitClient("kec:setComponentVariation", self.id, componentId, drawableId, textureId, paletteId)
end

--- Aplica ropa de un DLC/addon (colección) por su nombre. Equivalente a
--- setDlcClothes de otros frameworks: resuelve el índice global del drawable
--- desde la colección, así funciona con addons cuyo índice varía según los
--- DLC cargados. `drawableId`/`textureId` son LOCALES a la colección.
--- @param collection string Nombre de la colección/DLC (p.ej. "sprayground")
function player_methods:setDlcClothes(collection, componentId, drawableId, textureId, paletteId)
    kec:emitClient("kec:setDlcClothes", self.id, collection, componentId, drawableId, textureId, paletteId)
end

--- Pone un PROP en el ped (sombrero, gafas, pendientes, reloj). `propId` es un
--- kec.enum.ePedPropIdx, que es un índice distinto del de los componentes de ropa.
function player_methods:setPropIndex(propId, drawableId, textureId)
    kec:emitClient("kec:setPropIndex", self.id, propId, drawableId, textureId)
end

--- Quita el prop de ese hueco: los props no tienen drawable vacío al que volver.
function player_methods:clearProp(propId)
    kec:emitClient("kec:clearProp", self.id, propId)
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
    local id = tostring(self.id)
    player_info[id] = player_info[id] or {}
    player_info[id][key] = value
end

function player_methods:setInfoMultiple(infoTable)
    local id = tostring(self.id)
    player_info[id] = player_info[id] or {}
    for key, value in pairs(infoTable) do
        player_info[id][key] = value
    end
end

function player_methods:getInfo(key)
    local info = player_info[tostring(self.id)]
    return info and info[key] or nil
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

--- Instancia (routing bucket) en la que está el jugador. 0 = mundo normal.
function player_methods:getBucket()
    return GetPlayerRoutingBucket(self.id)
end

--- Mueve al jugador a otra instancia y AVISA del cambio
--- (`kec:on_player_bucket_changed`). FiveM no tiene evento propio para esto, así que
--- este es el único camino: quien llame a SetPlayerRoutingBucket a pelo deja a los
--- recursos que dependen de la instancia (p.ej. los drops del inventario) creyendo que
--- el jugador sigue en la anterior.
---@param bucket number
---@return boolean ok
function player_methods:setBucket(bucket)
    bucket = math.floor(tonumber(bucket) or -1)
    if bucket < 0 then return false end

    local previous = GetPlayerRoutingBucket(self.id)
    if previous == bucket then return true end

    SetPlayerRoutingBucket(self.id, bucket)
    kec:emit("kec:onPlayerBucketChanged", self.id, bucket, previous)
    return true
end

function player_methods:clearMetadata()
    local src = tostring(self.id)
    local section = self.type

    if not metadata[section][src] then return end

    metadata[section][src] = nil
    kec:emitAllClients("kec:clearMetadata", section, self.id)
end

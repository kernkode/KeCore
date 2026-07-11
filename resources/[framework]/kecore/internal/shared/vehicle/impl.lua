--- #Statics Functions

--- Checks if the model is valid
---@param model integer | string
---@return boolean
function kec.vehicle:isValidModel(model)
    local modelHash

    if type(model) == "string" then
        modelHash = GetHashKey(model)
    else
        modelHash = model
    end

    -- Verificar si el hash existe en nuestra tabla
    return kec.vehicle.modelHashes[modelHash] == true
end

--- State bag names used by the vehicle system.
--- Keep existing values stable; some are already persisted/synchronized.
kec.vehicle.state = {
    EXTRAS = "extras",
    SIREN = "siren",
    MOD = "mod",
    MODS = "mods",
    WHEELS = "wheels",
    WINDOW_TINT = "windowTint",
    WHEEL_SMOKE_COLOR = "wheelSmokeColor",
    DEFORMATION = "deformation",
    REPAIR = "repair",
    BROKEN_DOORS = "brokensDoords",
    BROKEN_WINDOWS = "brokenWindows",
    TYRES = "tyres",
    ENGINE = "engine",
    DIRT = "dirt",
    INFO = "_kecVehicleInfo",
}

--- Checks if an entity exists and is a vehicle.
---@param entity integer
---@param waitCollision boolean|nil Client-side only: wait until collision has loaded.
---@return boolean
function kec.vehicle:isValidEntity(entity, waitCollision)
    if not entity or entity == kec.enum.entityType.INVALID_ENTITY_ID then
        return false
    end

    if not DoesEntityExist(entity) then
        return false
    end

    if GetEntityType(entity) ~= kec.enum.entityType.ENTITY_TYPE_VEHICLE then
        return false
    end

    if waitCollision and kec:isClient() then
        while not HasCollisionLoadedAroundEntity(entity) do
            if not DoesEntityExist(entity) then return false end
            Wait(250)
        end
    end

    return true
end

--- Mapa global de extras de sirenas por vehiculo (usado en cliente y servidor)
kec.vehicle.sirenIndexes = {
    [GetHashKey("polbuffalo6")] = {1, 2, 3, 4},
    [GetHashKey("polcaracara")] = {1, 2, 3, 4},
    [GetHashKey("polcoquette4")] = {1, 2, 3, 4}
}

--- Mapeo global de las llantas (tyres) segun el numero de ejes del vehiculo
kec.vehicle.tyreIndexes = {
    [2] = {0, 1, 4, 5}
}

-- AUTO-GENERATED from internal/server/vehicle/header.lua + server/vehicle/methods.lua + server/vehicle/vehicle.lua by scripts/builder/gen-performance.ts — DO NOT EDIT
-- Edit the internal/ source and run `bun run gen:performance` to regenerate.

local vehicle = {}

local vehicle_info = {}


local vehicle_methods = {}

local state = kec.vehicle.state

local function getInfoKey(vehicle)
    return tostring(vehicle.entity)
end

local function getInfoStore(vehicle)
    local key = getInfoKey(vehicle)
    local info = vehicle_info[key]

    if info then
        return info
    end

    info = Entity(vehicle.entity).state[state.INFO] or {}
    vehicle_info[key] = info

    return info
end

local function saveInfoStore(vehicle, info)
    vehicle_info[getInfoKey(vehicle)] = info
    Entity(vehicle.entity).state:set(state.INFO, info, false)
end

-- ============================================================
-- Blob de mods/tuning (state.MODS)
-- Acumulado server-side: cada setter fija su valor aquí para que persista.
-- getMods() lo lee al guardar; el handler de statebag del cliente lo aplica.
-- ============================================================

-- Lee el blob de mods desde el statebag como tabla (vacía si aún no hay datos).
local function readModsBlob(vehicle)
    local blob = Entity(vehicle.entity).state[state.MODS]

    if type(blob) == "string" then
        if blob == "" then return {} end
        local ok, decoded = pcall(json.decode, blob)
        blob = ok and decoded or nil
    end

    if type(blob) ~= "table" then return {} end

    return blob
end

-- Escribe el blob completo al statebag (replicado) para que los clientes lo apliquen.
local function writeModsBlob(vehicle, blob)
    Entity(vehicle.entity).state:set(state.MODS, json.encode(blob), true)
end

function vehicle_methods:destroy()
    vehicle_info[getInfoKey(self)] = nil
    Entity(self.entity).state:set(state.INFO, nil, false)
    DeleteEntity(self.entity)
end

function vehicle_methods:setNumberPlate(plate)
    SetVehicleNumberPlateText(self.entity, plate)
end

function vehicle_methods:getNumberPlate()
    return GetVehicleNumberPlateText(self.entity)
end

function vehicle_methods:setPrimaryColor(r, g, b)
    SetVehicleCustomPrimaryColour(self.entity, r, g, b)
end

function vehicle_methods:setSecondaryColor(r, g, b)
    SetVehicleCustomSecondaryColour(self.entity, r, g, b)
end

function vehicle_methods:setColors(c1, c2)
    SetVehicleColours(self.entity, c1, c2)
    -- Registrar en el info store (persiste en el statebag INFO de la entidad) para que
    -- el guardado lo lea con getInfo("colors"), igual que extras.
    self:setInfo("colors", { c1, c2 })
end

function vehicle_methods:setMod(modType, modIndex)
    Entity(self.entity).state:set(state.MOD, json.encode({modType, modIndex}), true)

    -- Acumular en el blob MODS para que el mod se persista (getMods lo lee al guardar).
    local blob = readModsBlob(self)
    blob.mods = blob.mods or {}
    blob.mods[tostring(modType)] = modIndex
    writeModsBlob(self, blob)
end

--- Empuja el set completo de mods/tuning al statebag para que los clientes lo apliquen.
--- Ruta de CARGA: el servidor lee los mods de la DB y los publica; el handler de statebag
--- del cliente (internal/client/vehicle/events.lua) los aplica a la entidad.
---@param props table Set serializado por el cliente (vehicle:serializeMods()).
function vehicle_methods:setMods(props)
    if type(props) ~= "table" then return end
    writeModsBlob(self, props)
end

--- Devuelve el set de mods/tuning acumulado, listo para guardar en la DB.
--- Cada setter del servidor (setMod, setWheelType, setWindowTint, setWheelSmokeColor, ...)
--- alimenta este blob. Devuelve una tabla (subdocumento) o nil si aún no hay datos, para
--- que el $set omita la clave y no la sobrescriba con null.
---@return table|nil
function vehicle_methods:getMods()
    local blob = readModsBlob(self)
    if not next(blob) then return nil end
    return blob
end

function vehicle_methods:setExtra(extraId, disable)
    local extras = self:getInfo(state.EXTRAS) or {}

    extras[tostring(extraId)] = disable
    self:setInfo(state.EXTRAS, extras)

    Entity(self.entity).state:set(state.EXTRAS, json.encode(extras), true)
end

function vehicle_methods:setExtras(extrasTable)
    local extras = self:getInfo(state.EXTRAS) or {}

    for extraId, disable in pairs(extrasTable) do
        extras[tostring(extraId)] = disable
    end
    
    self:setInfo(state.EXTRAS, extras)
    Entity(self.entity).state:set(state.EXTRAS, json.encode(extras), true)
end

function vehicle_methods:getColors()
    local primary, secondary = GetVehicleColours(self.entity)
    return primary, secondary
end

function vehicle_methods:setLivery(livery)
    self:setMod(48, livery)
end

function vehicle_methods:setWheelType(type)
    Entity(self.entity).state:set(state.WHEELS, json.encode({type}), true)

    local blob = readModsBlob(self)
    blob.wheelType = type
    writeModsBlob(self, blob)
end

function vehicle_methods:setWindowTint(tint)
    Entity(self.entity).state:set(state.WINDOW_TINT, json.encode({ tint }), true)

    local blob = readModsBlob(self)
    blob.windowTint = tint
    writeModsBlob(self, blob)
end

function vehicle_methods:setWheelSmokeColor(r, g, b)
    Entity(self.entity).state:set(state.WHEEL_SMOKE_COLOR, json.encode({ r, g, b }), true)

    local blob = readModsBlob(self)
    blob.tyreSmokeColor = { r, g, b }
    writeModsBlob(self, blob)
end

function vehicle_methods:getDeformationBase64()
    return Entity(self.entity).state[state.DEFORMATION] or ''
end

function vehicle_methods:getDoorsBrokenBase64()
    local doors = Entity(self.entity).state[state.BROKEN_DOORS] or {}
    if type(doors) == "table" then
        doors = json.encode(doors)
    end

    return kec.base64:encode(doors)
end

function vehicle_methods:setDoorsBrokenBase64(doors)
    doors = kec.base64:decode(doors)

    Entity(self.entity).state:set(state.BROKEN_DOORS, doors, true)
end

function vehicle_methods:getWindowsBrokenBase64()
    local windows = Entity(self.entity).state[state.BROKEN_WINDOWS] or {}
    if type(windows) == "table" then
        windows = json.encode(windows)
    end

    return kec.base64:encode(windows)
end

function vehicle_methods:setWindowsBrokenBase64(windows)
    windows = kec.base64:decode(windows)

    Entity(self.entity).state:set(state.BROKEN_WINDOWS, windows, true)
end

function vehicle_methods:setDeformationBase64(base64)
    Entity(self.entity).state:set(state.DEFORMATION, base64, true)
end

function vehicle_methods:repair()
    Entity(self.entity).state:set(state.DEFORMATION, nil, true)

    local isRepair = Entity(self.entity).state[state.REPAIR]
    if isRepair then
        Entity(self.entity).state:set(state.REPAIR, false, true)
        return
    end

    Entity(self.entity).state:set(state.REPAIR, true, true)
end

function vehicle_methods:getTyresBurst()
    return Entity(self.entity).state[state.TYRES] or {}
end

function vehicle_methods:getCoords()
    return GetEntityCoords(self.entity)
end

function vehicle_methods:getRot()
    return GetEntityRotation(self.entity).z
end

function vehicle_methods:getEngineHealth()
    return GetVehicleEngineHealth(self.entity)
end

function vehicle_methods:getBodyHealth()
    return GetVehicleBodyHealth(self.entity)
end

--- Establecer metadato sincronizados (stream)
---@param key any
---@param value any
---@return any
function vehicle_methods:streamSyncedMeta(key, value)
    if value then
        Entity(self.entity).state:set(key, value, true)
    end
end

function vehicle_methods:getStreamSyncedMeta(key)
    return Entity(self.entity).state[key]
end

function vehicle_methods:setInfo(key, value)
    local info = getInfoStore(self)
    info[key] = value
    saveInfoStore(self, info)
end

function vehicle_methods:setInfoMultiple(infoTable)
    local info = getInfoStore(self)

    for key, value in pairs(infoTable) do
        info[key] = value
    end

    saveInfoStore(self, info)
end

function vehicle_methods:getInfo(key)
    local info = getInfoStore(self)
    return info[key]
end

-- ============================================================
-- Siren Management
-- ============================================================

function vehicle_methods:hasSiren()
    local model = GetEntityModel(self.entity)
    return kec.vehicle.sirenIndexes[model] ~= nil
end

function vehicle_methods:isValidSirenIndex(index)
    local model = GetEntityModel(self.entity)
    local indexes = kec.vehicle.sirenIndexes[model]
    if not indexes then return false end

    local targetIndex = tonumber(index)
    for _, idx in ipairs(indexes) do
        if idx == targetIndex then
            return true
        end
    end

    return false
end

function vehicle_methods:setSiren(index)
    local model = GetEntityModel(self.entity)
    local indexes = kec.vehicle.sirenIndexes[model]
    if not indexes then return end

    local targetIndex = tonumber(index)
    Entity(self.entity).state:set(state.SIREN, targetIndex, true)
end


local function instance_vehicle(entity)
    if not kec.vehicle:isValidEntity(entity) then
        return nil
    end

    local instance = {
        id = NetworkGetNetworkIdFromEntity(entity),
        entity = entity,
        model = GetEntityModel(entity)
    }

    for methodName, methodFunction in pairs(vehicle_methods) do
        instance[methodName] = methodFunction
    end

    return instance
end

function vehicle:new(model, coords)
    if not coords then
        coords = vector4(0, 0, 0, 0)
    end

    if type(model) == "string" then
        model = kec:hash(model)
    end

    local id = CreateVehicleServerSetter(model, "automobile", coords.x, coords.y, coords.z, coords.w)
    SetEntityOrphanMode(id, 2)

    return instance_vehicle(id)
end

function vehicle:get(id)
    return instance_vehicle(id)
end

return vehicle

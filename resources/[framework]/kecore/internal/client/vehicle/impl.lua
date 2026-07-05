
-----------------------------------------------
local state = kec.vehicle.state

-- Tipos de mod "toggle" (on/off): se manejan con ToggleVehicleMod/IsToggleModOn en vez de
-- SetVehicleMod (turbo, xenón, humo de llantas, etc.). Se excluyen del recorrido numerado.
local VEHICLE_MOD_TOGGLES = { 17, 18, 19, 20, 21, 22 }
local IS_TOGGLE_MOD = {}
for _, t in ipairs(VEHICLE_MOD_TOGGLES) do IS_TOGGLE_MOD[t] = true end

--- Lee el set completo de mods/tuning de la entidad y lo devuelve como tabla plana.
--- Sólo cubre lo que NO tiene ya su propia ruta de persistencia (extras, sirena,
--- deformación, daños, motor y posición se guardan por separado).
---@return table
function vehicle_methods:serializeMods()
    local veh = self.entity
    if not DoesEntityExist(veh) then return {} end

    -- El modkit debe estar activo para poder leer/escribir mods.
    if GetVehicleModKit(veh) == 65535 then
        SetVehicleModKit(veh, 0)
    end

    -- Mods numerados del modkit (excluyendo los toggle). -1 = sin mod (stock).
    local mods = {}
    for modType = 0, 49 do
        if not IS_TOGGLE_MOD[modType] then
            mods[tostring(modType)] = GetVehicleMod(veh, modType)
        end
    end

    -- Mods toggle (turbo, xenón, humo, etc.).
    local toggles = {}
    for _, t in ipairs(VEHICLE_MOD_TOGGLES) do
        toggles[tostring(t)] = IsToggleModOn(veh, t)
    end

    -- Neón (4 lados + color).
    local neon = {}
    for i = 0, 3 do
        neon[tostring(i)] = IsVehicleNeonLightEnabled(veh, i)
    end
    local nr, ng, nb = GetVehicleNeonLightsColour(veh)

    -- Color de humo de llantas.
    local sr, sg, sb = GetVehicleTyreSmokeColor(veh)

    return {
        wheelType      = GetVehicleWheelType(veh),
        windowTint     = GetVehicleWindowTint(veh),
        livery         = GetVehicleLivery(veh),
        roofLivery     = GetVehicleRoofLivery(veh),
        plateIndex     = GetVehicleNumberPlateTextIndex(veh),
        xenonColor     = GetVehicleHeadlightsColour(veh),
        mods           = mods,
        toggles        = toggles,
        neon           = neon,
        neonColor      = { nr, ng, nb },
        tyreSmokeColor = { sr, sg, sb },
    }
end

--- Aplica un set de mods/tuning (el producido por serializeMods) a la entidad.
--- Tolerante a nil y a valores ausentes (round-trip parcial seguro).
---@param props table|string
function vehicle_methods:applyMods(props)
    local veh = self.entity
    if not props or not DoesEntityExist(veh) then return end

    if type(props) == "string" then
        props = json.decode(props)
    end
    if type(props) ~= "table" then return end

    if GetVehicleModKit(veh) == 65535 then
        SetVehicleModKit(veh, 0)
    end

    -- El tipo de rueda debe fijarse ANTES que los mods de rueda (23/24).
    if props.wheelType ~= nil then
        SetVehicleWheelType(veh, props.wheelType)
    end

    if type(props.mods) == "table" then
        for modType, modIndex in pairs(props.mods) do
            SetVehicleMod(veh, tonumber(modType), modIndex, false)
        end
    end

    if type(props.toggles) == "table" then
        for modType, on in pairs(props.toggles) do
            ToggleVehicleMod(veh, tonumber(modType), on and true or false)
        end
    end

    if props.livery ~= nil and props.livery >= 0 then
        SetVehicleLivery(veh, props.livery)
    end
    if props.roofLivery ~= nil and props.roofLivery >= 0 then
        SetVehicleRoofLivery(veh, props.roofLivery)
    end

    if props.windowTint ~= nil then
        SetVehicleWindowTint(veh, props.windowTint)
    end

    if props.plateIndex ~= nil then
        SetVehicleNumberPlateTextIndex(veh, props.plateIndex)
    end

    if props.xenonColor ~= nil and props.xenonColor >= 0 then
        SetVehicleHeadlightsColour(veh, props.xenonColor)
    end

    if type(props.neon) == "table" then
        for index, on in pairs(props.neon) do
            SetVehicleNeonLightEnabled(veh, tonumber(index), on and true or false)
        end
    end
    if type(props.neonColor) == "table" and #props.neonColor == 3 then
        SetVehicleNeonLightsColour(veh, props.neonColor[1], props.neonColor[2], props.neonColor[3])
    end

    if type(props.tyreSmokeColor) == "table" and #props.tyreSmokeColor == 3 then
        SetVehicleTyreSmokeColor(veh, props.tyreSmokeColor[1], props.tyreSmokeColor[2], props.tyreSmokeColor[3])
    end
end

function vehicle_methods:repair()
    if not DoesEntityExist(self.entity) then return print("No existe el vehiculo") end

    SetVehicleFixed(self.entity)
    SetVehicleDeformationFixed(self.entity)
    SetVehicleBodyHealth(self.entity, 1000.0)

    Entity(self.entity).state:set(state.BROKEN_DOORS, nil, true)
    Entity(self.entity).state:set(state.BROKEN_WINDOWS, nil, true)
    Entity(self.entity).state:set(state.TYRES, nil, true)
    Entity(self.entity).state:set(state.DEFORMATION, nil, true)
end

function vehicle_methods:getWindowsBroken()
    if not DoesEntityExist(self.entity) then return {} end

    local brokens = {}

    for i = 0, 7 do
        if not IsVehicleWindowIntact(self.entity, i) then
            brokens[tostring(i)] = true
        end
    end

    return brokens
end

function vehicle_methods:getDoorsBroken()
    if not DoesEntityExist(self.entity) then return {} end

    local brokens = {}

    for v = 0, GetNumberOfVehicleDoors(self.entity) - 1 do
        if IsVehicleDoorDamaged(self.entity, v) then
            brokens[tostring(v)] = true
        end
    end

    return brokens
end

function vehicle_methods:setDoorBroken(doorIndex, deleteDoor)
    local doors = self:getStreamSyncedMeta(state.BROKEN_DOORS) or {}

    doors[doorIndex] = deleteDoor
    Entity(self.entity).state:set(state.BROKEN_DOORS, doors, true)
end

function vehicle_methods:getAxleCount()
    return GetVehicleNumberOfWheels(self.entity) / 2
end

function vehicle_methods:getTyresBurst()
    if not DoesEntityExist(self.entity) then return {} end

    local wheels = self:getAxleCount()

    local tyres = {}
    for _, index in pairs(kec.vehicle.tyreIndexes[wheels] or {}) do
        tyres[tostring(index)] = IsVehicleTyreBurst(self.entity, index, false) == 1 and true or false
    end

    return tyres
end

function vehicle_methods:getIndexsTyres()
    if not DoesEntityExist(self.entity) then return {} end

    local wheels = self:getAxleCount()
    return kec.vehicle.tyreIndexes[wheels]
end

function vehicle_methods:setTyreBurst(index, broken)
    if broken then
        SetVehicleTyreBurst(self.entity, index, true, 1000)
    else
        SetVehicleTyreFixed(self.entity, index)
    end
end

function vehicle_methods:fixTyre(index)
    SetVehicleTyreFixed(self.entity, index)
end

function vehicle_methods:setStreamSyncedMeta(key, value, replicate)
    Entity(self.entity).state:set(key, value, replicate ~= false)
end

function vehicle_methods:getStreamSyncedMeta(key)
    return Entity(self.entity).state[key]
end

function kec.vehicle:get(entity)
    local instance = {
        entity = entity,
        netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or 0,
        model = GetEntityModel(entity)
    }

    for methodName, methodFunction in pairs(vehicle_methods) do
        instance[methodName] = methodFunction
    end

    return instance
end

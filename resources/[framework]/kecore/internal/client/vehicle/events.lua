local state = kec.vehicle.state
local function isValidVehicle(entity)
    return kec.vehicle:isValidEntity(entity, true)
end

AddStateBagChangeHandler(nil, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    SetVehicleInfluencesWantedLevel(entity, false)
end)

AddStateBagChangeHandler("engineHealth", nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end
    
    if type(value) == "number" then
        SetVehicleEngineHealth(entity, value + 0.0)
    end
end)

AddStateBagChangeHandler("bodyHealth", nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end
    
    if type(value) == "number" then
        SetVehicleBodyHealth(entity, value + 0.0)
    end
end)

AddStateBagChangeHandler(state.EXTRAS, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    for extraId, disable in pairs(value) do
        local id = tonumber(extraId)
        if id and DoesExtraExist(entity, id) then
            local disableInt = 0
            if type(disable) == "boolean" then
                disableInt = disable and 1 or 0
            elseif type(disable) == "number" then
                disableInt = disable
            end

            SetVehicleExtra(entity, id, disableInt)
        end
    end
end)

-- ============================================================
-- Siren StateBag (switch atomico sin parpadeo)
-- ============================================================

AddStateBagChangeHandler(state.SIREN, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    local targetIndex = tonumber(value)
    if not targetIndex then return end

    local model = GetEntityModel(entity)
    local indexes = kec.vehicle.sirenIndexes[model]
    if not indexes then return end

    -- Paso 1: Encender la seleccionada PRIMERO
    if DoesExtraExist(entity, targetIndex) then
        SetVehicleExtra(entity, targetIndex, 0)
    end

    -- Paso 2: Apagar todas las demas
    for _, idx in ipairs(indexes) do
        if idx ~= targetIndex and DoesExtraExist(entity, idx) then
            SetVehicleExtra(entity, idx, 1)
        end
    end
end)

AddStateBagChangeHandler(state.MOD, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    if GetVehicleModKit(entity) == 65535 then
        SetVehicleModKit(entity, 0)
    end

    local modType, modIndex = value[1], value[2]
    SetVehicleMod(entity, modType, modIndex, false)
end)

-- Set completo de mods/tuning: el servidor publica los mods guardados (carga) y aquí se
-- aplican de una sola vez. isValidVehicle espera a que cargue la colisión, igual que el resto.
AddStateBagChangeHandler(state.MODS, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end
    if type(value) ~= "table" then return end

    kec.vehicle:get(entity):applyMods(value)
end)

AddStateBagChangeHandler(state.WHEELS, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    local wheelType = value[1]
    local wheel = GetVehicleMod(entity, 23)

    SetVehicleWheelType(entity, wheelType)
    SetVehicleMod(entity, 23, wheel, false)
end)

AddStateBagChangeHandler(state.WINDOW_TINT, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    local tint = value[1]
    SetVehicleWindowTint(entity, tint)
end)

AddStateBagChangeHandler(state.WHEEL_SMOKE_COLOR, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    ToggleVehicleMod(entity, 20, true)

    local r, g, b = value[1], value[2], value[3]
    SetVehicleTyreSmokeColor(entity, r, g, b)
end)

-- state bag handler to apply any deformation
AddStateBagChangeHandler(state.DEFORMATION, nil, function(bagName, key, value, _unused, replicated)
	if (bagName:find("entity") == nil) then return end

	deformation:applyDeformation(GetEntityFromStateBagName(bagName), value)
end)

AddStateBagChangeHandler(state.REPAIR, nil, function(bagName, key, value, _unused, replicated)
    if (bagName:find("entity") == nil or value == false) then return end

    local entity = GetEntityFromStateBagName(bagName)
    local vehicle = kec.vehicle:get(entity)

    vehicle:repair()
    kec:emitServer("finishVehicleRepair", NetworkGetNetworkIdFromEntity(entity))
end)

AddStateBagChangeHandler(state.BROKEN_DOORS, nil, function(bagName, key, value, _unused, replicated)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        if value == "" then value = "[]" end
        value = json.decode(value)
    end

    if type(value) ~= "table" then return end

    for i, v in pairs(value) do
        SetVehicleDoorBroken(entity, tonumber(i), v)
    end
end)

AddStateBagChangeHandler(state.BROKEN_WINDOWS, nil, function(bagName, key, value, _unused, replicated)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        if value == "" then value = "[]" end
        value = json.decode(value)
    end

    if type(value) ~= "table" then return end

    for i, v in pairs(value) do
        if v then
            SmashVehicleWindow(entity, tonumber(i))
        end
    end
end)

AddStateBagChangeHandler(state.TYRES, nil, function(bagName, key, value, _unused, replicated)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    -- The tyres payload is keyed by tyre index as a STRING (see getTyresBurst),
    -- so iterate with pairs + tonumber; ipairs would find nothing and never apply.
    for i, isBurst in pairs(value) do
        local index = tonumber(i)
        if isBurst then
            SetVehicleTyreBurst(entity, index, true, 1000.0)
        else
            SetVehicleTyreFixed(entity, index)
        end
    end
end)

AddStateBagChangeHandler(state.DIRT, nil, function(bagName, key, value, _unused, replicated)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "number" then
        SetVehicleDirtLevel(entity, value + 0.0)
    end
end)

-- update state bag on taking damage
AddEventHandler("gameEventTriggered", function (name, args)
	if (name ~= "CEventNetworkEntityDamage") then return end

	local entity = args[1]
	if not IsEntityAVehicle(entity) then return end

    if not IsVehicleBlacklisted(entity) then
        deformation:handleDeformationUpdate(entity)
    end

    local vehicle = kec.vehicle:get(entity)

    local doors = vehicle:getDoorsBroken()
    Entity(entity).state:set(state.BROKEN_DOORS, doors, true)

    local tyres = vehicle:getTyresBurst()
    vehicle:setStreamSyncedMeta(state.TYRES, tyres, true)

    local windows = vehicle:getWindowsBroken()
    Entity(entity).state:set(state.BROKEN_WINDOWS, windows, true)
end)

local function isValidVehicle(entity)
    if entity == 0 or GetEntityType(entity) ~= 2 then return false end

    while not HasCollisionLoadedAroundEntity(entity) do
        if not DoesEntityExist(entity) then return false end
        Wait(250)
    end

    return true
end

AddStateBagChangeHandler(nil, nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    SetVehicleInfluencesWantedLevel(entity, false)
end)

AddStateBagChangeHandler("extras", nil, function(bagName, key, value, reserved, replicated)
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
local vehicles_sirens_indexs = {
    [GetHashKey("polbuffalo6")] = {1, 2, 3, 4}
}

AddStateBagChangeHandler("siren", nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    local targetIndex = tonumber(value)
    if not targetIndex then return end

    local model = GetEntityModel(entity)
    local indexes = vehicles_sirens_indexs[model]
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

AddStateBagChangeHandler("mod", nil, function(bagName, key, value, reserved, replicated)
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

AddStateBagChangeHandler("wheels", nil, function(bagName, key, value, reserved, replicated)
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

AddStateBagChangeHandler("windowTint", nil, function(bagName, key, value, reserved, replicated)
    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    local tint = value[1]
    SetVehicleWindowTint(entity, tint)
end)

AddStateBagChangeHandler("wheelSmokeColor", nil, function(bagName, key, value, reserved, replicated)
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
AddStateBagChangeHandler("deformation", nil, function(bagName, key, value, _unused, replicated)
	if (bagName:find("entity") == nil) then return end

	deformation:applyDeformation(GetEntityFromStateBagName(bagName), value)
end)

AddStateBagChangeHandler("repair", nil, function(bagName, key, value, _unused, replicated)
    print("repair applied: " .. tostring(value))
    if (bagName:find("entity") == nil or value == false) then return end

    local entity = GetEntityFromStateBagName(bagName)
    local vehicle = kec.vehicle:get(entity)

    vehicle:repair()
    kec:emitServer("finishVehicleRepair", NetworkGetNetworkIdFromEntity(entity))
end)

AddStateBagChangeHandler("brokensDoords", nil, function(bagName, key, value, _unused, replicated)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    if type(value) == "string" then
        value = json.decode(value)
    end

    for i, v in pairs(value) do
        print(entity .. " " .. i .. " " .. tostring(v))
        SetVehicleDoorBroken(entity, tonumber(i), v)
    end
end)

AddStateBagChangeHandler("tyres", nil, function(bagName, key, value, _unused, replicated)
    if value == nil then return end

    local entity = GetEntityFromStateBagName(bagName)
    if not isValidVehicle(entity) then return end

    local vehicle = kec.vehicle:get(entity)

    --local tyres = vehicle:getIndexsTyres()
    for i, isBurst in ipairs(value) do
        local damage = isBurst and 1000 or 0
        --vehicle:setTyreBurst(i, isBurst)
        SetVehicleTyreBurst(entity, i, true, damage)
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
    Entity(entity).state:set("brokensDoords", doors, true)

    local tyres = vehicle:getTyresBurst()
    vehicle:setStreamSyncedMeta("tyres", tyres, true)
end)
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

    SetVehicleAutoRepairDisabled(entity, true)

    if type(value) == "string" then
        value = json.decode(value)
    end

    for extraId, disable in pairs(value) do
        SetVehicleExtra(entity, extraId, disable)
        --print("extra " .. extraId .. " disabled: " .. tostring(disable))
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
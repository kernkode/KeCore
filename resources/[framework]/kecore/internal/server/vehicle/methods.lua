vehicle_methods = {}

function vehicle_methods:destroy()
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
end

function vehicle_methods:setMod(modType, modIndex)
    Entity(self.entity).state:set("mod", json.encode({modType, modIndex}), true)
end

function vehicle_methods:setExtra(extraId, disable)
    local extras = self:getInfo("extras") or {}

    extras[extraId] = disable
    self:setInfo("extras", extras)

    Entity(self.entity).state:set("extras", json.encode(extras), true)
end

function vehicle_methods:getColors()
    local primary, secondary = GetVehicleColours(self.entity)
    return primary, secondary
end

function vehicle_methods:setLivery(livery)
    self:setMod(48, livery)
end

function vehicle_methods:setWheelType(type)
    Entity(self.entity).state:set("wheels", json.encode({type}), true)
end

function vehicle_methods:setWindowTint(tint)
    Entity(self.entity).state:set("windowTint", json.encode({ tint }), true)
end

function vehicle_methods:setWheelSmokeColor(r, g, b)
    Entity(self.entity).state:set("wheelSmokeColor", json.encode({ r, g, b }), true)
end

function vehicle_methods:getDeformationBase64()
    return Entity(self.entity).state.deformation or ''
end

function vehicle_methods:getDoorsBrokenBase64()
    local doors = Entity(self.entity).state.brokensDoords or {}
    if type(doors) == "table" then
        doors = json.encode(doors)
    end

    return kec.base64:encode(doors)
end

function vehicle_methods:setDoorsBrokenBase64(doors)
    doors = kec.base64:decode(doors)

    Entity(self.entity).state:set("brokensDoords", doors, true)
end

function vehicle_methods:setDeformationBase64(base64)
    Entity(self.entity).state:set("deformation", base64, true)
end

function vehicle_methods:repair()
    Entity(self.entity).state:set("deformation", nil, true)

    local isRepair = Entity(self.entity).state.repair
    if isRepair then
        Entity(self.entity).state:set("repair", false, true)
        return
    end

    Entity(self.entity).state:set("repair", true, true)
end

function vehicle_methods:getTyresBurst()
    return Entity(self.entity).state.tyres or {}
end

function vehicle_methods:getCoords()
    return GetEntityCoords(self.entity)
end

function vehicle_methods:getRot()
    return GetEntityRotation(self.entity).z
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
    vehicle_info[tostring(self.id)] = vehicle_info[tostring(self.id)] or {}
    vehicle_info[tostring(self.id)][key] = value
end

function vehicle_methods:setInfoMultiple(infoTable)
    vehicle_info[tostring(self.id)] = vehicle_info[tostring(self.id)] or {}
    for key, value in pairs(infoTable) do
        vehicle_info[tostring(self.id)][key] = value
    end
end

function vehicle_methods:getInfo(key)
    return vehicle_info[tostring(self.id)] and vehicle_info[tostring(self.id)][key] or nil
end
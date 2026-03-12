local vehicle_tyres_index = {
    [2] = {0, 1, 4, 5}
}

-----------------------------------------------
function vehicle_methods:repair()
    if not DoesEntityExist(self.entity) then return print("No existe el vehiculo") end

    SetVehicleFixed(self.entity)
    SetVehicleDeformationFixed(self.entity)
    SetVehicleBodyHealth(self.entity, 1000.0)

    Entity(self.entity).state:set("brokensDoords", nil, true)
    Entity(self.entity).state:set("tyres", nil, true)
end

function vehicle_methods:getDoorsBroken()
    if not DoesEntityExist(self.entity) then return {} end

    local brokens = {}

    for v = 0, GetNumberOfVehicleDoors(self.entity) do
        if IsVehicleDoorDamaged(self.entity, v) then
            brokens[tostring(v)] = true
        end
    end

    --IsVehicleTyreBurst
    return brokens or {}
end

function vehicle_methods:setDoorBroken(doorIndex, deleteDoor)
    local doors = self:getStreamSyncedMeta("brokensDoords") or {}

    doors[doorIndex] = deleteDoor
    Entity(self.entity).state:set("brokensDoords", doors, true)
end

function vehicle_methods:getAxleCount()
    return GetVehicleNumberOfWheels(self.entity) / 2
end

function vehicle_methods:getTyresBurst()
    if not DoesEntityExist(self.entity) then return {} end

    local wheels = self:getAxleCount()

    local tyres = {}
    for _, index in pairs(vehicle_tyres_index[wheels] or {}) do
        tyres[tostring(index)] = IsVehicleTyreBurst(self.entity, index, false) == 1 and true or false
    end

    return tyres
end

function vehicle_methods:getIndexsTyres()
    if not DoesEntityExist(self.entity) then return {} end

    local wheels = self:getAxleCount()
    return vehicle_tyres_index[wheels]
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
    return Entity(self.entity).state[key] or nil
end

function kec.vehicle:get(entity)
    local instance = {
        entity = entity,
        netId = NetworkGetNetworkIdFromEntity(entity),
        model = GetEntityModel(entity)
    }

    for methodName, methodFunction in pairs(vehicle_methods) do
        instance[methodName] = methodFunction
    end

    return instance
end
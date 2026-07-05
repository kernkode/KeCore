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

function kec.vehicle:new(model, coords)
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

function kec.vehicle:get(id)
    return instance_vehicle(id)
end

local ENTITY_TYPE_VEHICLE = 2
local INVALID_ENTITY_ID = 0

local function instance_vehicle(entity)
    if DoesEntityExist(entity) == 0 then
        print("No existe el vehiculo: " .. entity)
        return "Error"
    end

    local type = GetEntityType(entity)

    if entity == INVALID_ENTITY_ID or type ~= ENTITY_TYPE_VEHICLE then return "Error" end

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

kec:on("finishVehicleRepair", function (player, netId)
    local vehicle = NetworkGetEntityFromNetworkId(netId)

    local veh = kec.vehicle:get(vehicle)
    Entity(veh.entity).state:set("repair", false, true)
end)
kec:on("finishVehicleRepair", function(_src, netId)
    local entity = NetworkGetEntityFromNetworkId(netId)
    local vehicle = kec.vehicle:get(entity)

    if not vehicle then return end

    Entity(vehicle.entity).state:set(kec.vehicle.state.REPAIR, false, true)
end)

kec:on("kec:vehicle:repair", function(entity)
    entity = NetworkGetEntityFromNetworkId(entity)

    local vehicle = kec.vehicle:get(entity)
    vehicle:repair()
end)

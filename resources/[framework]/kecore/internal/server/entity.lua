local function instance_entity(src)
    local entity = NetworkGetEntityFromNetworkId(src)

    local instance = {
        id = src,
        model = GetEntityModel(entity),
        type = GetEntityType(entity),
    }

    function instance:getCoords()
        return GetEntityCoords(entity)
    end

    return instance
end

function kec:entity(src)
    return instance_entity(src)
end
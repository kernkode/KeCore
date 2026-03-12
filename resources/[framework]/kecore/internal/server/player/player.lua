local function instance_player(src)
    if not src or src == 0 or GetPlayerName(src) == nil then
        return nil
    end

    if player_cache[tostring(src)] then
        return player_cache[tostring(src)]
    end

    local playerKey = tostring(src)

    local instance = {
        id = src,
        type = "player",
        name = GetPlayerName(src),
        identifiers = player_info[playerKey]?.identifiers or {},
    }

    if not player_info[playerKey] then
        local __identifiers = {}

        for _, key in pairs(GetPlayerIdentifiers(src)) do
            local identifierType = string.sub(key, 1, string.find(key, ":") - 1)
            local identifierValue = string.sub(key, string.find(key, ":") + 1)
            __identifiers[identifierType] = identifierValue
        end

        player_info[playerKey] = {
            identifiers = __identifiers
        }

        instance.identifiers = __identifiers
    end

    for methodName, methodFunction in pairs(player_methods) do
        instance[methodName] = methodFunction
    end

    if not player_cache[playerKey] then
        player_cache[playerKey] = instance
    end

    return instance
end

function kec:player(src)
    return instance_player(src)
end

kec:on_player_connected(function(player)
    player:emit("kec:updateMetadata", metadata)
end)
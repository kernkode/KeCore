
kec:on_player_disconnect(function(player)
    kec:setTimeout(function ()
        local source = tostring(player.id)
        player_cache[source] = nil

        if player_info[source] ~= nil then
            player_info[source] = nil
        end

        player:clearMetadata()

        print("delete all metadata of player: " .. player.id)
    end, 2000)
end)

kec:on_player_disconnect(function(player)
    kec:setTimeout(function ()
        local source = tostring(player.id)
        player_cache[source] = nil
        player_info[source] = nil

        player:clearMetadata()
    end, 2000)
end)
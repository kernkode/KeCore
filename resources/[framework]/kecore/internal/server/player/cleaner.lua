
kec:on_player_disconnect(function(player)
    local source = tostring(player.id)

    if pending_cleanups[source] then
        pending_cleanups[source]:cancel()
    end

    pending_cleanups[source] = kec:setTimeout(function()
        pending_cleanups[source] = nil
        player_cache[source] = nil
        player_info[source] = nil

        player:clearMetadata()
    end, 2000)
end)
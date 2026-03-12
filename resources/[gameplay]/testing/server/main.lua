kec:on_resource_start(function()
    print('core iniciado')
end)

kec:on_player_connecting(function(player, setKickReason, deferrals)
    print("connecting : " .. player.name)
end)

kec:on_player_connected(function(player)
    print("connected : " .. player.id)
end)

kec:on_player_disconnect(function(player)
    print("disconnected : " .. player.id)
end)

kec:on_player_death(function(player, data)
    player:spawn(vector3(-734.6901245117188, -1456.6021728515626, 4.999267578125), 1.0)
end)

kec:on_player_loaded(function(player)
    print("player loaded : " .. player.id)
end)
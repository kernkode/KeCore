
local function createEventWrapper(eventName)
    return function(self, handler)
        if kec:isServer() then
            self:on(eventName, function(source, data)
                local player = self:player(source)
                if player then
                    handler(player, data)
                end
            end)
        else
            self:on(eventName, function(...)
                handler(...)
            end)
        end
    end
end

kec.on_player_loaded = createEventWrapper("kec:onPlayerLoaded")
kec.on_player_death = createEventWrapper("kec:onPlayerDeath")
kec.on_player_kill_to_player = createEventWrapper("kec:onPlayerKillToPlayer")
kec.on_player_spawn = createEventWrapper("player:spawned")

if kec:isClient() then
    kec.on_raycast_entity = createEventWrapper("kec:onRaycastEntity")
    kec.on_entered_vehicle = createEventWrapper("kec:onPlayerEnteredVehicle")
    kec.on_exit_vehicle = createEventWrapper("kec:onPlayerExitVehicle")
    kec.on_gizmo_stop = createEventWrapper("kec:onGizmoStop")
end
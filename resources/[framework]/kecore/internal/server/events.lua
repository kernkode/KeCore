local events = {
    on_entity_created    = { name = "entityCreated", cancel = true },
    on_entity_creating   = { name = "entityCreating", cancel = true },
}

for method, data in pairs(events) do
    kec[method] = function(self, handler)
        self:on(data.name, function(...)
            if data.cancel and handler(...) == false then
                CancelEvent()
            elseif not data.cancel then
                handler(...)
            end
        end)
    end
end

--- Se llama cuando un jugador se conecta
--- @param self any
--- @param handler function
function kec:on_player_connected(handler)
    self:on("playerJoining", function(src)
        local player = kec:player(src)
        if player == nil then return end

        local ret = handler(player)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se llama cuando un jugador se desconecta
--- @param self any
--- @param handler function
function kec:on_player_disconnect(handler)
    self:on("playerDropped", function(src, reason, resourceName, clientDropReason)
        local player = kec:player(src)
        if not player then return end

        local ret = handler(player, {
            reason = reason,
            resourceName = resourceName,
            clientDropReason = clientDropReason
        })

        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se llama cuando un jugador se está conectando
--- @param self any
--- @param handler function
function kec:on_player_connecting(handler)
    self:on("playerConnecting", function(src, _, setKickReason, deferrals)
        local player = kec:player(src)
        if player == nil then return end

        local ret = handler(player, setKickReason, deferrals)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se utiliza para emitir un evento a todos los clientes de un recurso especifico
--- @param self any
--- @param handler function
function kec:on_player_restart(handler)
    local players = GetPlayers()
    local invoking = GetInvokingResource()

    self:on("onResourceStart", function(resourceName)
        if resourceName == invoking then
            Wait(500)
            for _, src in ipairs(players) do
                local player = kec:player(src)
                if player == nil then return end

                handler(player)
            end
        end
    end)
end
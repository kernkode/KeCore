-- AUTO-GENERATED from internal/server/events.lua by scripts/builder/gen-performance.ts — DO NOT EDIT
-- Edit the internal/ source and run `bun run gen:performance` to regenerate.

local events = {}

function events:on_entity_created(handler)
    self:on("entityCreated", function(...)
        if handler(...) == false then
            CancelEvent()
        end
    end)
end

function events:on_entity_creating(handler)
    self:on("entityCreating", function(...)
        if handler(...) == false then
            CancelEvent()
        end
    end)
end

--- Se llama cuando un jugador se conecta
--- @param self any
--- @param handler function
function events:on_player_connected(handler)
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
function events:on_player_disconnect(handler)
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

--- Se llama cuando un jugador cambia de instancia (routing bucket) con
--- `player:setBucket`. FiveM no tiene evento propio para esto, así que quien mueva
--- jugadores entre instancias debe usar ese método o los oyentes no se enterarán.
--- Va por `onLocal` (AddEventHandler, sin RegisterNetEvent): un cliente no puede
--- fingir un cambio de instancia.
--- @param self any
--- @param handler fun(player: table, bucket: number, previous: number)
function events:on_player_bucket_changed(handler)
    self:onLocal("kec:onPlayerBucketChanged", function(src, bucket, previous)
        local player = kec:player(src)
        if not player then return end

        handler(player, bucket, previous)
    end)
end

--- Se llama cuando un jugador se está conectando
--- @param self any
--- @param handler function
function events:on_player_connecting(handler)
    self:on("playerConnecting", function(src, _, setKickReason, deferrals)
        local player = kec:player(src)
        if player == nil then return end

        local ret = handler(player, setKickReason, deferrals)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Ejecuta `handler(player)` para cada jugador conectado cuando el recurso invocador se reinicia.
--- @param self any
--- @param handler function
function events:on_player_restart(handler)
    local invoking = GetInvokingResource()

    self:on("onResourceStart", function(resourceName)
        if resourceName == invoking then
            Wait(500)
            -- Snapshot the CURRENTLY connected players (capturing at registration
            -- time would freeze an empty list from script load).
            for _, src in ipairs(GetPlayers()) do
                local player = kec:player(src)
                -- Skip a player we can't resolve; don't abort the whole loop.
                if player ~= nil then
                    handler(player)
                end
            end
        end
    end)
end

--- Se dispara cuando un jugador recibe daño de arma. El handler puede devolver false
--- para cancelar el evento (CancelEvent).
--- @param handler fun(sender: number, data: table): boolean|nil
function events:on_weapon_damage(handler)
    self:on("weaponDamageEvent", function(sender, data)
        local ret = handler(tonumber(sender), data)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se dispara cuando se lanza un proyectil (granadas, cohetes, molotovs...).
--- El handler puede devolver false para cancelar el evento.
--- @param handler fun(sender: number, data: table): boolean|nil
function events:on_start_projectile(handler)
    self:on("startProjectileEvent", function(sender, data)
        local ret = handler(tonumber(sender), data)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se dispara cuando ocurre una explosión. El handler puede devolver false para
--- cancelar el evento.
--- @param handler fun(source: number, data: table): boolean|nil
function events:on_explosion(handler)
    self:on("explosionEvent", function(source, data)
        local ret = handler(tonumber(source), data)
        if ret == false then
            CancelEvent()
        end
    end)
end

return events

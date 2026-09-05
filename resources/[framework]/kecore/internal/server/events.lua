-- ------------------------------------------------------------
-- Wrappers de los eventos DEL MOTOR en servidor.
--
-- Todos van por `kec:onLocal` (AddEventHandler) y NINGUNO por `kec:on`: `RegisterNetEvent` no
-- abre solo tu handler, abre el NOMBRE del evento, y a partir de ahí cualquier cliente puede
-- dispararlo y corren todos los handlers que lo escuchen. Con `kec:on` aquí, un cliente podía
-- fingir su propio `playerDropped` (guardar y descargar su personaje sin desconectarse), su
-- `playerJoining`, un `entityCreated`, o disparar `onResourceStop` para que el limpiador de
-- kecore borrara los handlers del framework entero.
--
-- El tercer argumento de `onLocal` antepone el `source` del evento: los eventos por jugador lo
-- traen en la global del motor y no en los args. Los eventos de juego (daño, proyectil,
-- explosión) NO lo llevan —el emisor viene como primer argumento, `sender`—, así que van sin él.
-- ------------------------------------------------------------

function kec:on_entity_created(handler)
    self:onLocal("entityCreated", function(...)
        if handler(...) == false then
            CancelEvent()
        end
    end)
end

function kec:on_entity_creating(handler)
    self:onLocal("entityCreating", function(...)
        if handler(...) == false then
            CancelEvent()
        end
    end)
end

--- Se llama cuando un jugador se conecta
--- @param self any
--- @param handler function
function kec:on_player_connected(handler)
    self:onLocal("playerJoining", function(src)
        local player = kec:player(src)
        if player == nil then return end

        local ret = handler(player)
        if ret == false then
            CancelEvent()
        end
    end, true)
end

--- Se llama cuando un jugador se desconecta
--- @param self any
--- @param handler function
function kec:on_player_disconnect(handler)
    self:onLocal("playerDropped", function(src, reason, resourceName, clientDropReason)
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
    end, true)
end

--- Se llama cuando un jugador cambia de instancia (routing bucket) con
--- `player:setBucket`. FiveM no tiene evento propio para esto, así que quien mueva
--- jugadores entre instancias debe usar ese método o los oyentes no se enterarán.
--- El `src` viaja como argumento del emit (`player:setBucket`), no en la global del motor.
--- @param self any
--- @param handler fun(player: table, bucket: number, previous: number)
function kec:on_player_bucket_changed(handler)
    self:onLocal("kec:onPlayerBucketChanged", function(src, bucket, previous)
        local player = kec:player(src)
        if not player then return end

        handler(player, bucket, previous)
    end)
end

--- Se llama cuando un jugador se está conectando
--- @param self any
--- @param handler function
function kec:on_player_connecting(handler)
    self:onLocal("playerConnecting", function(src, _, setKickReason, deferrals)
        local player = kec:player(src)
        if player == nil then return end

        local ret = handler(player, setKickReason, deferrals)
        if ret == false then
            CancelEvent()
        end
    end, true)
end

--- Ejecuta `handler(player)` para cada jugador conectado cuando el recurso invocador se reinicia.
--- @param self any
--- @param handler function
function kec:on_player_restart(handler)
    local invoking = GetInvokingResource()

    self:onLocal("onResourceStart", function(resourceName)
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
function kec:on_weapon_damage(handler)
    self:onLocal("weaponDamageEvent", function(sender, data)
        local ret = handler(tonumber(sender), data)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se dispara cuando se lanza un proyectil (granadas, cohetes, molotovs...).
--- El handler puede devolver false para cancelar el evento.
--- @param handler fun(sender: number, data: table): boolean|nil
function kec:on_start_projectile(handler)
    self:onLocal("startProjectileEvent", function(sender, data)
        local ret = handler(tonumber(sender), data)
        if ret == false then
            CancelEvent()
        end
    end)
end

--- Se dispara cuando ocurre una explosión. El handler puede devolver false para
--- cancelar el evento.
--- @param handler fun(source: number, data: table): boolean|nil
function kec:on_explosion(handler)
    self:onLocal("explosionEvent", function(source, data)
        local ret = handler(tonumber(source), data)
        if ret == false then
            CancelEvent()
        end
    end)
end
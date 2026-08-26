-- AUTO-GENERATED from internal/client/player.lua by scripts/builder/gen-performance.ts — DO NOT EDIT
-- Edit the internal/ source and run `bun run gen:performance` to regenerate.

-- ------------------------------------------------------------
-- El jugador local.
--
-- GTA parte "yo" en DOS asas y cada native pide una de las dos: el índice de jugador
-- (`PlayerId`) y la entidad del ped (`PlayerPedId`). Darle la que no es NO da error —
-- `ClearPlayerWantedLevel` con un ped se traga la llamada y no limpia nada—, así que el que
-- llamaba tenía que saber cuál iba en cada native y acababa escribiendo cosas como
-- `SetPlayerCanDoDriveBy(PlayerId(), true)` con el ped al lado en la misma función. Ese reparto
-- se hace aquí UNA vez: ningún método de abajo recibe asa.
--
-- El ped no se cachea: cambia al revivir y al cambiar de modelo, y una copia guardada apunta a
-- una entidad borrada. Se lee en cada llamada, como en el resto del framework.
--
-- Solo hay un jugador local, así que `player` YA es la instancia (no una fábrica como
-- `kec.vehicle:get`). El equivalente en servidor es `kec:player(source)`, que sí necesita a
-- quién.
-- ------------------------------------------------------------
local player = {}

--- Índice de jugador (`PlayerId`). Estable durante toda la sesión.
---@return number
function player:id()
    return PlayerId()
end

--- Entidad del ped (`PlayerPedId`). Cambia al revivir y al cambiar de modelo: no la guardes.
---@return number
function player:ped()
    return PlayerPedId()
end

--- El id con el que te conoce el servidor (el `source` de allí).
---@return number
function player:serverId()
    return GetPlayerServerId(PlayerId())
end

--- Muerto según el motor (`IsPlayerDead`), que es lo que mira el juego para dejar de
--- responder a los controles.
---@return boolean
function player:isDead()
    return IsPlayerDead(PlayerId())
end

---@param toggle boolean
function player:setInvincible(toggle)
    SetPlayerInvincible(PlayerId(), toggle)
end

---@return boolean
function player:isInvincible()
    return GetPlayerInvincible(PlayerId())
end

--- El drive-by cubre TODOS los controles de disparo desde un vehículo (que cambian según el
--- asiento y el tipo de vehículo), así que apagarlo es la forma de bloquear el disparo sentado
--- sin ir control por control.
---@param toggle boolean
function player:setCanDoDriveBy(toggle)
    SetPlayerCanDoDriveBy(PlayerId(), toggle)
end

--- Limpia el nivel de búsqueda de la policía.
function player:clearWantedLevel()
    ClearPlayerWantedLevel(PlayerId())
end

--- Multiplicador del daño de las armas de FUEGO del jugador.
---@param modifier number
function player:setWeaponDamageModifier(modifier)
    SetPlayerWeaponDamageModifier(PlayerId(), modifier + 0.0)
end

--- Multiplicador del melé que REPARTE el jugador. Es uno por jugador, no por arma.
---@param modifier number
function player:setMeleeDamageModifier(modifier)
    SetPlayerMeleeWeaponDamageModifier(PlayerId(), modifier + 0.0, false)
end

--- Multiplicador del melé que ENTRA al jugador (el golpe de un NPC no pasa por el
--- multiplicador de arriba: ese es del que reparte). El native no está en todas las builds, así
--- que devuelve `false` en vez de reventar y el que llama decide si avisa.
---@param modifier number
---@return boolean applied
function player:setMeleeDefenseModifier(modifier)
    return pcall(SetPlayerMeleeWeaponDefenseModifier, PlayerId(), modifier + 0.0)
end

return player

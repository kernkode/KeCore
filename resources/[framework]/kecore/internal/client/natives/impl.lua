local isHealthRecharge = false
local HealthRechargeMultiplier = 1.0
local ped_variations = {}
-- Los props (sombreros, gafas, pendientes, relojes) se cachean APARTE de las variaciones
-- de componente: los dos van por índices que empiezan en 0 y significan cosas distintas
-- (ePedPropIdx vs ePedVarComp), así que mezclarlos haría que al revivir se restaurara un
-- sombrero como si fuera la cara.
local ped_props = {}
local tickRolling = nil

local FREEMODE_MODELS = {
    male = `mp_m_freemode_01`,
    female = `mp_f_freemode_01`
}

function native:cacheCurrentClothes(ped)
    if not ped_variations[ped] then ped_variations[ped] = {} end
    for i = 0, 11 do
        ped_variations[ped][i] = {
            drawable = GetPedDrawableVariation(ped, i),
            texture = GetPedTextureVariation(ped, i),
            palette = GetPedPaletteVariation(ped, i)
        }
    end
end

function native:spawn(coords, heading, modelHash)
    local oldPed = PlayerPedId()
    local player = PlayerId()

    -- Leer la ropa actual directo de GTA antes de que el motor la limpie al revivir
    self:cacheCurrentClothes(oldPed)

    if modelHash then
        self:setModel(modelHash)
    end

    local newPed = PlayerPedId()
    if oldPed ~= newPed then
        ped_variations[newPed] = ped_variations[oldPed]
        ped_variations[oldPed] = nil
        ped_props[newPed] = ped_props[oldPed]
        ped_props[oldPed] = nil
        DeleteEntity(oldPed)
    end

    while not isWorldLoaded do
        Wait(0)
    end

    ShutdownLoadingScreen()

    if IsPlayerDead(player) then
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    else
        self:setCoords(coords.x, coords.y, coords.z, heading)
    end

    -- Limpieza de estado (se ejecuta tanto para resurrección como para spawn vivo)
    ClearPedTasksImmediately(newPed)
    ClearPlayerWantedLevel(newPed)

    SetEntityVelocity(newPed, 0.0, 0.0, 0.0)
    self:setHealth(self:getMaxHealth())

    Wait(1)
    ClearPedBloodDamage(newPed)

    native:togglePvp(true)

    self:applyDefaultClothes()

    -- Pre-solicitar colision en la zona de spawn (Cayo Perico tarda en streamear)
    RequestCollisionAtCoord(coords.x, coords.y, coords.z)

    -- Congelar inmediatamente para que la gravedad no tire el ped antes de
    -- que el handler on_player_spawn termine de configurar el polling.
    FreezeEntityPosition(newPed, true)

    kec:emitServer("player:spawned")
    kec:emit("player:spawned")
end

-- Función para establecer posición
function native:setCoords(x, y, z, heading)
    SetEntityCoords(PlayerPedId(), x, y, z)
    SetEntityHeading(PlayerPedId(), heading)
end

-- Función para obtener salud máxima
function native:getMaxHealth()
    return GetPedMaxHealth(PlayerPedId())
end

-- Función para establecer salud
function native:setHealth(health)
    SetEntityHealth(PlayerPedId(), health)
end

-- ------------------------------------------------------------
-- El culatazo: `native:disablePedWeaponKnockout(ped, toggle)`.
--
-- Golpear con un arma de FUEGO en la mano quita 500 de vida de golpe y mata a cualquiera al
-- instante. Esos 500 no son el daño del arma: son el REMATE de melé del motor (el mismo que
-- tumba a un NPC de un golpe), y por eso no los toca ni el multiplicador de melé del jugador,
-- ni la defensa, ni el daño calibrado arma por arma. No hay native que lo apague.
--
-- Lo que sí se puede es que no lleguen a la barra de verdad: al ped se le pone COLCHÓN. El
-- máximo sube a 700 y la barra real —la de siempre: 200, de las que solo se juegan 100, porque
-- con 101 queda un punto de vida y con 100 el ped ya está muerto— se monta 500 más arriba:
--
--   700 barra llena · 601 un punto de vida · 600 muerto · 200..101 el colchón ya gastado
--
-- Así el remate deja al ped en 200: su barra real INTACTA, solo sin colchón. Ahí abajo no lo
-- puede dejar nada más —el daño normal no llega a quitar 100 y lo gordo (explosión, ráfaga de
-- perdigones) se pasa de largo y cae en el suelo—, así que esa vida es la firma del remate y
-- el tick le devuelve los 500.
--
-- El precio de subir el máximo lo paga el mismo tick: el motor mata a los 100 ABSOLUTOS, así
-- que con 700 de máximo un jugador aguantaría 600 de daño en vez de 100 y la tabla de daño del
-- server no querría decir nada. Al llegar al suelo del colchón (600) lo remata el script, y la
-- muerte se emite también desde aquí: sin un impacto que el motor marque como fatal,
-- `internal/client/events/custom.lua` no la ve.
--
-- Lo que el colchón NO arregla: la barra de vida del juego se dibuja sobre el máximo, así que
-- se ve casi llena hasta el último golpe (700 → 600 es el 100% → 83%). Para que lea bien, el
-- HUD tiene que pintar (vida - 600) / 100 y esconder la del juego.
--
-- Y por qué la barra real son 200 SIEMPRE, y no un parámetro: el truco solo funciona con una
-- barra real más ESTRECHA que el colchón. Con 200 (100 jugables) el remate deja al ped en la
-- franja 200..101, que está por debajo del suelo de muerte y no se confunde con nada. Con una
-- barra de 1000, el remate lo deja en 1000 y ahí también cae el daño de verdad: la devolución
-- se comería un golpe mortal y el ped no podría morir. Un ped con otra barra (el muñeco de
-- `/dummy` con la vida que le pida el staff) NO lleva colchón a propósito.
-- ------------------------------------------------------------
local FATAL        = 100                    -- umbral del motor: con 100 de vida el ped ya está muerto
local VANILLA_MAX  = 200                    -- la barra real, la que dice la tabla de daño
local KNOCKOUT     = 500                    -- lo que quita el remate de melé del motor
local BUFFERED_MAX = VANILLA_MAX + KNOCKOUT -- 700: barra real + colchón
local DEATH_FLOOR  = FATAL + KNOCKOUT       -- 600: la barra real a 0

local knockoutPeds = {}    -- ped con colchón → true
local tickKnockout = nil
local knockoutBroken = false -- true si el motor no deja montar el colchón: se apaga y no se reintenta

--- Una pasada de colchón sobre un ped: monta lo que falte, le devuelve el remate si se lo
--- acaba de comer, y lo remata si su barra real llegó a 0. Idempotente a propósito: vale
--- igual para armarlo y para mantenerlo cada frame.
local function knockoutPass(ped)
    if not DoesEntityExist(ped) then
        knockoutPeds[ped] = nil
        return
    end

    -- Muerto no se toca: la vida la pone el respawn, y devolverle nada aquí sería
    -- resucitarlo por la puerta de atrás.
    if IsEntityDead(ped) then return end

    -- El ped sale del respawn (y del cambio de modelo) con el máximo de fábrica: sin esto el
    -- colchón se pierde al reaparecer y el siguiente culatazo vuelve a matar de una.
    -- Y con las natives de PED, no las de entidad: `SetEntityMaxHealth` no sube el techo real
    -- del ped —la vida se queda clavada en su máximo de fábrica y la devolución no entra (es lo
    -- que pilló el guard de abajo)—, mientras que `SetPedMaxHealth` sí. Es la misma native con
    -- la que se arregla que la hembra freemode ande con 175 en vez de 200.
    if GetPedMaxHealth(ped) ~= BUFFERED_MAX then SetPedMaxHealth(ped, BUFFERED_MAX) end

    local health = GetEntityHealth(ped)

    if health > FATAL and health <= VANILLA_MAX then
        -- ponytail: se mira DÓNDE cae la vida, no de qué arma viene, porque solo el remate
        -- (500 fijos) la deja en la barra real sin colchón. Si algún día una explosión o una
        -- caída de entre 400 y 600 deja a alguien vivo, hay que mirar el impacto
        -- (`HasPedBeenDamagedByWeapon` con melé) antes de devolver nada.
        SetEntityHealth(ped, health + KNOCKOUT)

        -- Y se comprueba que la devolución HAYA ENTRADO, que es de lo que depende todo esto. Si
        -- el motor no deja pasar de la barra de fábrica del ped, la devolución lo deja con la
        -- barra LLENA en vez de con colchón: a partir de ahí cada golpe cae otra vez en la
        -- franja, se devuelve, y el ped no baja nunca de ahí. Inmortal, y sin una línea en
        -- consola que lo diga. Antes que eso, sin colchón y avisando.
        if GetEntityHealth(ped) < health + KNOCKOUT then
            knockoutBroken = true
            kec.log:warn("knockout", ("el motor no deja subir la vida de %d a %d (máximo %d): " ..
                "sin colchón, el culatazo vuelve a matar de una")
                :format(health, health + KNOCKOUT, GetPedMaxHealth(ped)))

            for buffered in pairs(knockoutPeds) do
                knockoutPeds[buffered] = nil
                if DoesEntityExist(buffered) then SetPedMaxHealth(buffered, VANILLA_MAX) end
            end

            if tickKnockout then
                tickKnockout:cancel()
                tickKnockout = nil
            end
        end
    elseif health <= DEATH_FLOOR then
        SetEntityHealth(ped, 0)

        -- Solo el jugador local: de un NPC con colchón no hay muerte que reportar.
        if ped ~= PlayerPedId() then return end

        local killer = GetPedSourceOfDeath(ped)
        local _, bone = GetPedLastDamageBone(ped)

        -- Mismos campos que la muerte de `client/events/custom.lua`, con lo que se puede
        -- saber sin el evento del motor: los golpes y el daño acumulado los lleva ese
        -- contador y aquí no hay ninguno.
        local data = {
            weaponHash = GetPedCauseOfDeath(ped),
            bone = bone,
            isHeadshot = false,
            hits = 0,
            total_damage = 0,
            killer = (killer ~= 0 and IsPedAPlayer(killer))
                and GetPlayerServerId(NetworkGetPlayerIndexFromPed(killer)) or 0
        }

        kec:emitServer("kec:onPlayerDeath", data)
        kec:emit("kec:onPlayerDeath", data)
    end
end

--- Quita el remate de melé (el culatazo) de un ped poniéndole 500 de vida de colchón por
--- encima de su barra real, que son los 200 de siempre. Llamarlo de más no hace nada: es
--- idempotente, así que puede ir en el mismo sitio donde se reponen los flags que el ped pierde
--- al reaparecer. Vale para cualquier ped con la barra normal (el jugador, el muñeco de
--- `/dummy`); un ped con la barra tocada no lo quiere (ver la cabecera).
---@param ped number
---@param toggle boolean
function native:disablePedWeaponKnockout(ped, toggle)
    if not toggle then
        knockoutPeds[ped] = nil

        if DoesEntityExist(ped) and GetPedMaxHealth(ped) == BUFFERED_MAX then
            if not IsEntityDead(ped) then
                SetEntityHealth(ped, math.max(FATAL, GetEntityHealth(ped) - KNOCKOUT))
            end

            SetPedMaxHealth(ped, VANILLA_MAX)
        end

        if tickKnockout and next(knockoutPeds) == nil then
            tickKnockout:cancel()
            tickKnockout = nil
        end

        return
    end

    -- Se vio que este build no deja montar el colchón: no se reintenta cada 500 ms ni se llena
    -- la consola de avisos.
    if knockoutBroken then return end

    knockoutPeds[ped] = true
    knockoutPass(ped)

    tickKnockout = tickKnockout or kec:everyTick(function()
        for buffered in pairs(knockoutPeds) do knockoutPass(buffered) end
    end)
end

-- Función para aplicar ropa por defecto
function native:applyDefaultClothes()
    local modelHash = self:getModel()

    if modelHash == FREEMODE_MODELS.male or modelHash == FREEMODE_MODELS.female then
        local default_shoes = FREEMODE_MODELS.male == modelHash and 34 or 35
        local components = {
            {0, 0, 0, 0},  -- Cara
            {2, 0, 0, 0},  -- Cabello
            {3, 0, 0, 0},  -- Brazos
            {4, 0, 0, 0},  -- Piernas
            {8, 0, 0, 0},  -- Camisa
            {6, default_shoes, 0, 0}, -- Zapatos
            {11, 0, 0, 0}  -- Chaleco
        }

        for _, component in ipairs(components) do
            -- Si no tiene alguna ropa aplicada aplica la ropa por defecto
            if not native:hasComponentVariation(component[1]) then
                native:setComponentVariation(component[1], component[2], component[3], component[4])
            end
        end

        -- Restaurar todas las prendas guardadas (útil al revivir tras morir, ya que GTA limpia el ped)
        local ped = PlayerPedId()
        if ped_variations[ped] then
            for compId, data in pairs(ped_variations[ped]) do
                SetPedComponentVariation(ped, compId, data.drawable, data.texture, data.palette)
            end
        end

        -- Los props se pierden igual al revivir y tienen su propia native.
        if ped_props[ped] then
            for propId, data in pairs(ped_props[ped]) do
                SetPedPropIndex(ped, propId, data.drawable, data.texture, true)
            end
        end
    end
end

function native:togglePvp(toggle)
    SetCanAttackFriendly(PlayerPedId(), toggle, false)
    NetworkSetFriendlyFireOption(toggle)
end

function native:getModel()
    return GetEntityModel(PlayerPedId())
end

function native:requestModel(model)
    return RequestModel(model)
end

function native:setHealthRechargeMultiplier(multiplier)
    HealthRechargeMultiplier = multiplier

    if not isHealthRecharge then
        SetPlayerHealthRechargeMultiplier(PlayerId(), HealthRechargeMultiplier)
    end

    isHealthRecharge = true
end

-- Streaming
function native:isModelInCdimage(modelHash)
    return IsModelInCdimage(modelHash)
end

function native:hasModelLoaded(modelHash)
    return HasModelLoaded(modelHash)
end

function native:releaseModel(modelHash)
    return SetModelAsNoLongerNeeded(modelHash)
end

function native:setModel(modelHash)
    local currentModel = self:getModel()
    if currentModel == modelHash then
        return false
    end

    if native:isModelInCdimage(modelHash) and IsModelValid(modelHash) then
        native:requestModel(modelHash)

        while not native:hasModelLoaded(modelHash) do
            Citizen.Wait(0)
        end

        SetPlayerModel(PlayerId(), modelHash)
        native:releaseModel(modelHash)

        if isHealthRecharge then
            SetPlayerHealthRechargeMultiplier(PlayerId(), HealthRechargeMultiplier)
        end

        self:applyDefaultClothes()
        return true
    end

    print("^ERROR: No se pudo cargar el modelo " .. modelHash)
    return false
end

local infiniteStamina = false
-- Función para toggle de stamina infinita
function native:toggleInfiniteStamina(toggle)
    if toggle and not infiniteStamina then
        CreateThread(function()
            while infiniteStamina do
                SetPlayerStamina(PlayerId(), 100.0)
                Wait(5 * 1000)
            end
        end)
    end

    infiniteStamina = toggle
    return true
end

function native:setComponentVariation(componentId, drawableId, textureId, paletteId)
    local ped = PlayerPedId()
    SetPedComponentVariation(ped, componentId, drawableId, textureId, paletteId)

    if not ped_variations[ped] then
        ped_variations[ped] = {}
    end

    ped_variations[ped][componentId] = {
        drawable = drawableId,
        texture = textureId,
        palette = paletteId
    }
end

--- Aplica una prenda de un DLC/addon (SHOP_PED_APPAREL) al ped por el nombre de
--- su colección. Equivalente a setDlcClothes de alt:V: en FiveM la vía DLC-aware
--- son las natives de colección. `dlcName` es el nombre de colección del addon
--- (el <dlcName> del .meta, p.ej. "sprayground"); `drawableId`/`textureId` son
--- LOCALES a esa colección. Cachea el índice GLOBAL resultante para que la
--- restauración de ropa tras respawn (applyDefaultClothes) lo vuelva a poner.
function native:setDlcClothes(dlcName, componentId, drawableId, textureId, paletteId)
    local ped = PlayerPedId()
    paletteId = paletteId or 0

    SetPedCollectionComponentVariation(ped, componentId, dlcName, drawableId, textureId, paletteId)

    -- Índice global equivalente (varía según los DLC del ped): lo guardamos para
    -- que el restore por SetPedComponentVariation tras revivir siga funcionando.
    local globalDrawable = GetPedDrawableGlobalIndexFromCollection(ped, componentId, dlcName, drawableId)

    if not ped_variations[ped] then
        ped_variations[ped] = {}
    end

    ped_variations[ped][componentId] = {
        drawable = globalDrawable,
        texture = textureId,
        palette = paletteId
    }
end

--- Pone un PROP en el ped (sombrero, gafas, pendientes, reloj). Es el otro juego de
--- "ropa": `propId` es un ePedPropIdx, NO un componente, y por eso va por su propia
--- native. Un drawable que no exista para el modelo deja el hueco vacío en vez de
--- avisar, así que los índices son distintos en hombre y en mujer.
function native:setPropIndex(propId, drawableId, textureId)
    local ped = PlayerPedId()
    textureId = textureId or 0

    SetPedPropIndex(ped, propId, drawableId, textureId, true)

    if not ped_props[ped] then
        ped_props[ped] = {}
    end

    ped_props[ped][propId] = { drawable = drawableId, texture = textureId }
end

--- Quita el prop de ese hueco. Es el "no llevar nada": los props no tienen un drawable
--- vacío al que volver (el 0 ya es un sombrero), así que quitarse uno es borrarlo.
function native:clearProp(propId)
    local ped = PlayerPedId()
    ClearPedProp(ped, propId)

    if ped_props[ped] then
        ped_props[ped][propId] = nil
    end
end

function native:hasComponentVariation(componentId)
    if not ped_variations[PlayerPedId()] then
        return false
    end

    return ped_variations[PlayerPedId()][componentId] ~= nil
end

function native:getComponentVariation(componentId)
    local ped = PlayerPedId()

    if not self:hasComponentVariation(componentId) then
        return {}
    end

    local data = ped_variations[ped][componentId]
    return data.drawable, data.texture, data.palette
end

-- Desactiva/Activa el ruedo con armas al apuntar
---@param toggle boolean
function native:disableRolling(toggle)
    if tickRolling ~= nil then
        if not toggle then
            tickRolling:cancel()
            tickRolling = nil
        end

        return
    end

    if not toggle then return end

    tickRolling = kec:everyTick(function()
        SetPedResetFlag(PlayerPedId(), 446, true) --Evita rodar con las armas
    end)
end

function native:getStreamSyncedMeta(ped, key)
    return Entity(ped).state[key]
end

--- Obtener metadato sincronizados
---@param key string
---@param src number ServerId
---@return nil|any
function native:getSyncedMeta(key, src)
    local serverId = tostring(src or GetPlayerServerId(PlayerId()))
    local playerData = metadata.player[serverId]
    return playerData and playerData[key] or nil
end

function native:warpIntoVehicle(netId, seat)
    seat = seat or -1
    local timeout = GetGameTimer() + 3000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < timeout do
        Wait(10)
    end
    if NetworkDoesEntityExistWithNetworkId(netId) then
        local veh = NetToVeh(netId)
        local ped = PlayerPedId()
        TaskWarpPedIntoVehicle(ped, veh, seat)
    end
end

function native:requestClipSet(clipSet)
    RequestClipSet(clipSet)
end

function native:setPedMovementClipset(ped, clipSet, speed)
    SetPedMovementClipset(ped, clipSet, speed)
end

function native:resetPedMovementClipset(ped, speed)
    ResetPedMovementClipset(ped, speed)
end

function native:setPedStrafeClipset(ped, clipSet)
    SetPedStrafeClipset(ped, clipSet)
end

function native:resetPedStrafeClipset(ped)
    ResetPedStrafeClipset(ped)
end

function native:setPedUsingActionMode(ped, toggle, p2, action)
    SetPedUsingActionMode(ped, toggle, p2, action)
end

function native:disableControlAction(index, control, disable)
    DisableControlAction(index, control, disable)
end

function native:isAimCamActive()
    return IsAimCamActive()
end
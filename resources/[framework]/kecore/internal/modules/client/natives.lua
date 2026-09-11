local kec = ...
local native = {}

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

    while not kec.isWorldLoaded do
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

    -- Por índice de JUGADOR, no por ped: con un ped el native se traga la llamada y el
    -- jugador reaparecía con la estrella de la policía puesta.
    ClearPlayerWantedLevel(player)

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
-- Así el remate deja al ped en 200: su barra real INTACTA, solo sin colchón. Pero la vida a la
-- que cae NO es la firma de nada: una GRANADA a los pies quita también 500 justos y deja al ped
-- exactamente ahí. Por eso el colchón se devuelve solo si el golpe fue de MELÉ
-- (`HasPedBeenDamagedByWeapon` con weaponType 1, que es el tipo de daño del culatazo aunque el
-- arma en la mano sea de fuego). Mirando solo dónde cae la vida, una explosión encima no hacía
-- NADA: caía en la franja, se le devolvían los 500 en el mismo frame y salía con la barra llena.
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

-- Olvidar el último golpe recibido. El flag de "me han dado con X" del motor es ACUMULATIVO
-- hasta que se limpia, y el colchón lo consulta para saber si el golpe de ESTE frame fue de
-- melé: sin limpiarlo, un puñetazo de hace diez minutos haría pasar por culatazo a la siguiente
-- explosión. Se captura una vez porque no está en todas las builds; si falta, el colchón vuelve
-- a fiarse solo de la vida (y una explosión de 500 justos no hará daño, ver la cabecera).
local clearLastDamage = ClearEntityLastWeaponDamage

--- Sube la vida los 500 del colchón, y comprueba que la subida HAYA ENTRADO: es de lo que
--- depende todo esto. Si el motor no deja pasar de la barra de fábrica del ped, la subida lo
--- deja con la barra LLENA en vez de con colchón, y a partir de ahí cada golpe cae otra vez en
--- la franja, se devuelve, y el ped no baja nunca de ahí: inmortal, y sin una línea en consola
--- que lo diga. Antes que eso, sin colchón y avisando.
local function fillBuffer(ped, health)
    SetEntityHealth(ped, health + KNOCKOUT)
    if GetEntityHealth(ped) >= health + KNOCKOUT then return end

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

--- Una pasada de colchón sobre un ped: lo monta si falta, le devuelve el remate si se lo acaba
--- de comer, y lo remata si su barra real llegó a 0. Idempotente a propósito: vale igual para
--- armarlo y para mantenerlo cada frame.
local function knockoutPass(ped)
    if not DoesEntityExist(ped) then
        knockoutPeds[ped] = nil
        return
    end

    -- Muerto no se toca: la vida la pone el respawn, y devolverle nada aquí sería
    -- resucitarlo por la puerta de atrás.
    if IsEntityDead(ped) then return end

    -- MONTAR. El ped sale del respawn (y del cambio de modelo) con el máximo de fábrica, así que
    -- esta rama es también la que lo repone. Subir el techo y rellenar los 500 van JUNTOS y en
    -- la misma pasada: con el máximo a 700 y la barra de fábrica a 200, el ped se queda por
    -- debajo del suelo de muerte y el mantenimiento de abajo lo remataría acto seguido.
    -- Y con las natives de PED, no las de entidad: `SetEntityMaxHealth` no sube el techo real
    -- del ped —la vida se queda clavada en su máximo de fábrica y la subida no entra (es lo que
    -- pilló el guard de `fillBuffer`)—, mientras que `SetPedMaxHealth` sí. Es la misma native
    -- con la que se arregla que la hembra freemode ande con 175 en vez de 200.
    if GetPedMaxHealth(ped) ~= BUFFERED_MAX then
        SetPedMaxHealth(ped, BUFFERED_MAX)

        local vanilla = GetEntityHealth(ped)
        if vanilla > FATAL and vanilla <= VANILLA_MAX then fillBuffer(ped, vanilla) end

        return
    end

    -- MANTENER.
    local health = GetEntityHealth(ped)

    -- ¿El golpe que acaba de entrar fue de MELÉ? Se lee ANTES de decidir nada y se olvida en la
    -- misma pasada, así que lo que se mira es siempre el golpe de ESTE frame.
    local melee = HasPedBeenDamagedByWeapon(ped, 0, 1) -- weaponType 1 = daño de melé
    if clearLastDamage then clearLastDamage(ped) end

    -- La vida cayó en la franja del colchón gastado Y fue un golpe: es el remate del culatazo, y
    -- se le devuelven los 500. Sin la condición del melé aquí entraba también una granada a los
    -- pies —quita 500 justos, los mismos— y la explosión acababa sin hacer NADA.
    --
    -- Si algún día el culatazo vuelve a matar de una, el sitio es ESTA línea: querría decir que
    -- el motor no marca ese golpe como melé y hay que buscarle otra firma. Se comprueba con
    -- `/dummy` y un arma de fuego en la mano (culatazo: no debe matar de un golpe; granada a los
    -- pies: debe matar).
    if melee and health > FATAL and health <= VANILLA_MAX then
        fillBuffer(ped, health)
        return
    end

    -- Por encima del suelo del colchón no hay nada que hacer: es daño normal y la barra real
    -- (601..700) todavía tiene puntos.
    if health > DEATH_FLOOR then return end

    -- La barra real llegó a 0: o se la comió el daño de verdad, o fue un impacto tan gordo que
    -- se pasó de largo del colchón (una explosión, una ráfaga de perdigones). Muerto.
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

--- Carga un modelo en memoria esperando con timeout
---@param modelHash number|string
---@param timeoutMs number|nil Tiempo máximo en ms (por defecto 3000)
---@return boolean success
function native:loadModel(modelHash, timeoutMs)
    if type(modelHash) == "string" then modelHash = kec:hash(modelHash) end
    if not self:isModelInCdimage(modelHash) then return false end

    self:requestModel(modelHash)
    local deadline = GetGameTimer() + (timeoutMs or 3000)
    while not self:hasModelLoaded(modelHash) and GetGameTimer() < deadline do
        Citizen.Wait(10)
    end
    return self:hasModelLoaded(modelHash)
end

function native:requestWeaponAsset(weaponHash, p1, extraComponentFlags)
    p1 = p1 or 31
    extraComponentFlags = extraComponentFlags or 0
    return RequestWeaponAsset(weaponHash, p1, extraComponentFlags)
end

function native:hasWeaponAssetLoaded(weaponHash)
    return HasWeaponAssetLoaded(weaponHash)
end

function native:removeWeaponAsset(weaponHash)
    return RemoveWeaponAsset(weaponHash)
end

--- Carga un asset de arma en memoria esperando con timeout
---@param weaponHash number|string
---@param timeoutMs number|nil Tiempo máximo en ms (por defecto 3000)
---@param extraComponentFlags number|nil Flags de componentes (por defecto 0)
---@return boolean success
function native:loadWeaponAsset(weaponHash, timeoutMs, extraComponentFlags)
    if type(weaponHash) == "string" then weaponHash = kec:hash(weaponHash) end

    self:requestWeaponAsset(weaponHash, 31, extraComponentFlags or 0)
    local deadline = GetGameTimer() + (timeoutMs or 3000)
    while not self:hasWeaponAssetLoaded(weaponHash) and GetGameTimer() < deadline do
        Citizen.Wait(10)
    end
    return self:hasWeaponAssetLoaded(weaponHash)
end

--- Loads an animation dictionary, the same way `loadModel` loads a model: yields until it is in
--- memory or the timeout runs out, so whatever comes next can assume the clip is there — or give up.
---
--- The default wait is shorter than a model's on purpose: what asks for a dictionary is a gesture,
--- and a gesture that takes a second to come out is a gesture that no longer matches what it was
--- reacting to.
---@param dict string
---@param timeoutMs number|nil Max wait in ms (1000 by default)
---@return boolean loaded
function native:loadAnimDict(dict, timeoutMs)
    if HasAnimDictLoaded(dict) then return true end

    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeoutMs or 1000)
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do
        Citizen.Wait(10)
    end
    return HasAnimDictLoaded(dict)
end

--- Plays an animation on a ped: loads the dictionary, plays the clip and stops needing the dictionary.
--- Returns how long the clip was given, in ms, or 0 if the dictionary never loaded — and then nothing
--- was played, so 0 is also "there is no gesture".
---
--- Loading YIELDS, so anything the gesture depends on can have changed by the time the clip starts.
--- Whatever has to hold true then is checked AFTER loading, which costs nothing because the second
--- call finds the dictionary already in memory:
---     if not native:loadAnimDict(dict) then return end
---     if prone:isDown() then return end   -- it could have hit the floor while the dict loaded
---     native:playAnim(ped, dict, clip, { ms = 1200, flag = 48 })
---
--- `ms` nil = whatever the clip lasts (`GetAnimDuration`), and -1 when the engine does not know: that
--- is "play it once and let it end", which is what a gesture wants. It comes back as the return value
--- so the caller can schedule against it without asking again.
---
--- The flags worth remembering: 0 = full body, and it nails the ped where it stands for as long as it
--- lasts; 48 = upper body and does not block, so the ped can keep walking and its own pose (a weapon
--- in the hand, for instance) survives underneath; 1 = loop.
---@param ped number
---@param dict string
---@param clip string
---@param opts table|nil { ms, flag, blendIn, blendOut, rate, lockX, lockY, lockZ, timeoutMs }
---@return number ms
function native:playAnim(ped, dict, clip, opts)
    opts = opts or {}
    if not self:loadAnimDict(dict, opts.timeoutMs) then return 0 end

    local ms = opts.ms
    if not ms then
        ms = math.floor((GetAnimDuration(dict, clip) or 0) * 1000)
        if ms <= 0 then ms = -1 end
    end

    -- 8.0 / -8.0 is a fast blend, which is what a gesture that answers a keypress needs: anything
    -- slower is seen as the ped starting late. `or` and not a nil check on purpose — a 0 passed on
    -- purpose is truthy in Lua and gets through.
    TaskPlayAnim(ped, dict, clip,
        opts.blendIn or 8.0, opts.blendOut or -8.0,
        ms, opts.flag or 0, opts.rate or 0.0,
        opts.lockX == true, opts.lockY == true, opts.lockZ == true)

    -- Released right after asking for it, which is what every gesture in the resources already did:
    -- the running task holds the clip, so this only says "I stop needing it" and lets the engine
    -- reclaim it once the gesture is over.
    RemoveAnimDict(dict)
    return ms
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
    local playerData = kec.metadata.player[serverId]
    return playerData and playerData[key] or nil
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

function native:hideHudComponents(components)
    if type(components) == "table" then
        for i = 1, #components do
            HideHudComponentThisFrame(components[i])
        end
    else
        HideHudComponentThisFrame(components)
    end
end

--- El espejo del de arriba: fuerza un componente del HUD ESTE frame. Hace falta para lo que el motor
--- esconde por su cuenta —la retícula deja de dibujarse mientras se renderiza una cámara de script—,
--- así que como el de esconder, se pide por frame.
function native:showHudComponents(components)
    if type(components) == "table" then
        for i = 1, #components do
            ShowHudComponentThisFrame(components[i])
        end
    else
        ShowHudComponentThisFrame(components)
    end
end

--- El radar del juego es, de hecho, el interruptor del HUD entero: media docena de sitios lo apagan
--- para decir "ahora no se pinta HUD" (la cámara del login, `kec.cam`, el cine de la muerte, los
--- prismáticos, el ajuste de apuntar) y [gameplay]/hud se esconde con él.
---
--- De ahí que la intención se apunte además en `kec.state.radar`: `IsRadarHidden` dice si el radar
--- está oculto AHORA, que no es lo mismo que si alguien lo ha querido ocultar, y hay cosas colgadas
--- del radar —el aro de [gameplay]/minimap, la brújula y los testigos de [gameplay]/hud— que se
--- pintan por su cuenta y necesitan la bandera, no el estado del motor.
function native:displayRadar(toggle)
    toggle = toggle and true or false
    kec.state.radar = toggle
    DisplayRadar(toggle)
end

--- La caja de un componente del HUD en píxeles, a partir de sus fracciones de `frontend.xml`,
--- alineada a la esquina inferior izquierda de la SAFEZONE (76 = 'L', 66 = 'B') como van los tres del
--- minimapa. `posY` se mide desde ABAJO, así que la esquina de arriba sale de `posY - sizeY`.
---
--- Hace falta porque [gameplay]/minimap reescribe esa caja (`SetMinimapComponentPosition`) para poder
--- redondear el radar, y entonces necesita saber dónde ha quedado: no hay native que lo devuelva.
---@param out table|nil Tabla a rellenar, para no crear una por medida
function native:hudComponentRect(posX, posY, sizeX, sizeY, out)
    local w, h = GetActiveScreenResolution()

    SetScriptGfxAlign(76, 66)
    local alignX, alignY = GetScriptGfxPosition(posX, posY - sizeY)
    ResetScriptGfxAlign()

    out = out or {}
    out.left = math.floor(alignX * w + 0.5)
    out.top = math.floor(alignY * h + 0.5)
    out.width = math.floor(sizeX * w + 0.5)
    out.height = math.floor(sizeY * h + 0.5)
    out.right = out.left + out.width
    out.bottom = out.top + out.height

    return out
end

--- El rectángulo que ocupa el minimapa en pantalla, en píxeles enteros. No hay native que lo
--- devuelva: el ancho y el alto son las cuentas del HUD del juego y la esquina sale de alinear a la
--- inferior izquierda de la SAFEZONE (76 = 'L', 66 = 'B'), que es lo que mete el juego cuando el
--- jugador la aprieta desde los ajustes. Depende de la resolución y de esa safezone, así que se
--- vuelve a medir en vez de guardarse.
---
--- De él cuelga todo lo que va pegado al mapa: la brújula y los testigos del coche de
--- [gameplay]/hud, y el círculo de [gameplay]/minimap, que se dibuja dentro.
---@param out table|nil Tabla a rellenar, para no crear una por medida
function native:radarRect(out)
    local aspect = GetAspectRatio(false)
    local w, h = GetActiveScreenResolution()
    local width = w / (4 * aspect)
    local height = h / 5.674

    SetScriptGfxAlign(76, 66)
    local alignX, alignY = GetScriptGfxPosition(-0.0045, 0.002 - 0.188888)
    ResetScriptGfxAlign()

    local x = alignX * w + h * 0.0074
    local y = alignY * h + h * 0.0095

    out = out or {}
    out.left = math.floor(x + 0.5)
    out.top = math.floor(y + 0.5)
    out.width = math.floor(width + 0.5)
    out.height = math.floor(height + 0.5)
    out.right = math.floor(x + width + 0.5)
    out.bottom = math.floor(y + height + 0.5)

    return out
end

return native

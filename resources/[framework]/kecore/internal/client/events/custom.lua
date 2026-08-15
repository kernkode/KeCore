
local isReloading = false
kec:setInterval(function()
    local ped = PlayerPedId()
    local reloading = IsPedReloading(ped)
    local weapon = GetSelectedPedWeapon(ped)

    if(reloading and not isReloading) then
        isReloading = true
        kec:emit("onReloadStart", weapon)
    elseif (not reloading and isReloading) then
        isReloading = false
        kec:emit("onReloadEnd", weapon)
    end
end, 100)

local currentWeapon = nil
local WEAPON_UNARMED = kec.weapons.models.WEAPON_UNARMED
kec:setInterval(function()
    local ped = PlayerPedId()
    local selectedWeapon = GetSelectedPedWeapon(ped)

    if selectedWeapon == currentWeapon then
        return
    end

    local isUnarmed = (selectedWeapon == WEAPON_UNARMED)
    local isWeaponReady, _ = GetAmmoInClip(ped, selectedWeapon)

    if isUnarmed or isWeaponReady then
        currentWeapon = selectedWeapon
        kec:emit("onChangeWeapon", selectedWeapon)
    end

end, 200)

local lastAttacker = nil
local hitCount = 0
local total_damage = 0

local function resetDamageTracker()
    hitCount = 0
    total_damage = 0
end

AddEventHandler('gameEventTriggered', function (name, args)
    if name ~= "CEventNetworkEntityDamage" then return end

    local victim, attacker, weaponHash = args[1], args[2], args[7]
    local isFatal           = args[6] == 1
    local playerPed         = PlayerPedId()
    local isVictimPlayer    = victim == playerPed
    local isAttackerPlayer  = attacker == playerPed
    local isHeadshot        = args[11] == 1
    local damage            = kec.math:bitsToFloat(args[3])

    if isVictimPlayer then
        if lastAttacker ~= attacker then
            resetDamageTracker()
        end

        lastAttacker = attacker
        hitCount = hitCount + 1
        total_damage = total_damage + damage
    end

    if not isFatal then return end

    local _, bone = GetPedLastDamageBone(victim)

    local eventName = nil
    local data = {
        weaponHash = weaponHash,
        bone = bone,
        isHeadshot = isHeadshot,
        hits = hitCount,
        total_damage = math.max(0, math.min(100, total_damage - 100))
    }

    if isVictimPlayer then
        eventName = "kec:onPlayerDeath"
        data.killer = GetPlayerServerId(NetworkGetPlayerIndexFromPed(attacker)) or 0
    elseif (isAttackerPlayer and victim ~= playerPed and IsPedAPlayer(victim)) then
        eventName = "kec:onPlayerKillToPlayer"
        data.victim = GetPlayerServerId(NetworkGetPlayerIndexFromPed(victim)) or 0
    end

    if eventName then
        kec:emitServer(eventName, data)
        kec:emit(eventName, data)
    end

    resetDamageTracker()
end)

AddEventHandler('gameEventTriggered', function (name, args)
    if (name ~= "CEventNetworkPlayerEnteredVehicle") then return end

    kec:emit("kec:onPlayerEnteredVehicle", args[2])
end)

local inVehicle = false
local lastVehicle = nil

kec:setInterval(function()
    -- Verificamos si el jugador está en un vehículo
    local inAnyVehicle = IsPedInAnyVehicle(PlayerPedId(), false)
    if inAnyVehicle and not inVehicle then
        inVehicle = true
        lastVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    elseif inVehicle and not inAnyVehicle then
        kec:emit("kec:onPlayerExitVehicle", lastVehicle)
        inVehicle = false
        lastVehicle = nil
    end
end, 200)

-- ------------------------------------------------------------
-- Disparos (`kec:onWeaponShoot`, se escucha con `kec:on_weapon_shoot`).
--
-- NO se usa `CEventGunShot`: es un evento de PERCEPCIÓN. Llega también cuando el ped solo
-- OYE el disparo (o se asusta), en una calle con NPCs salta varias veces por bala según a
-- cuántos afecta, y normalmente viene con la tabla de args vacía. Inservible para contar.
--
-- Lo que sí es exacto es la MUNICIÓN del arma: cada bala que sale la baja en uno. Se mira
-- por frame y la bajada solo cuenta si el ped está disparando de verdad (`IsPedShooting`),
-- que es lo que la distingue de un script reescribiendo la munición o del motor guardando el
-- arma. `IsPedShooting` no siempre cae en el mismo frame que la bajada, así que basta con
-- haberlo visto en los últimos `SHOT_GRACE` ms.
--
-- Se mira el TOTAL y no la recámara a propósito: la recámara la SUBEN los scripts (un
-- inventario que devuelve la reserva al cargador cada frame), y si esa subida cae en el mismo
-- frame que el disparo la bajada se tapa y la bala no se cuenta. El total no lo sube nadie
-- por frame — solo al equipar o recargar, y eso es una subida, no una bajada.
--
-- OJO: es cuenta de CLIENTE y el server no puede verificarla — GTA no manda por red "he
-- disparado", solo el daño (`weaponDamageEvent`) y los proyectiles. Esto sirve para que la
-- contabilidad no se PIERDA (el agujero era ese: si la lectura de munición se
-- desincronizaba, no se reportaba nada y las balas salían gratis), no como anticheat.
-- ------------------------------------------------------------
local SHOT_GRACE = 250          -- ms de margen entre ver `IsPedShooting` y la bajada
local MAX_SHOTS_PER_SECOND = 80 -- la minigun ronda 50 balas/s, así que 80 deja margen
local lastShotSeenAt = 0
local lastShotCheckAt = 0
local shotWeapon, shotAmmo = nil, 0

---@class kec.WeaponShootData
---@field ped number Ped que disparó (siempre el del jugador local).
---@field weapon number Hash del arma con la que se disparó.
---@field shots number Balas que salieron en este frame (>1 con cadencias altas).
---@field clip number Balas que quedan en la recámara después del disparo.
---@field ammo number Balas TOTALES del arma en el ped después del disparo.
kec:everyTick(function()
    local ped = PlayerPedId()
    local weapon = GetSelectedPedWeapon(ped)
    local ammo = GetAmmoInPedWeapon(ped, weapon)

    local now = GetGameTimer()
    local window = math.min(math.max(now - lastShotCheckAt, 16), 500)
    lastShotCheckAt = now

    if IsPedShooting(ped) then lastShotSeenAt = now end

    -- Cambio de arma: la munición de la nueva no se compara con la de la vieja.
    if weapon ~= shotWeapon then
        shotWeapon, shotAmmo = weapon, ammo
        return
    end

    local shots = shotAmmo - ammo
    shotAmmo = ammo

    -- La bajada se descarta, pero `shotAmmo` ya está actualizado: si no, una bajada
    -- rechazada se arrastraría y se cobraría en el siguiente disparo de verdad.
    if shots <= 0 or now - lastShotSeenAt > SHOT_GRACE then return end

    -- Tope por el tiempo REAL transcurrido: un script puede bajar la munición de golpe
    -- (equipar el arma con menos balas de las que el ped tenía), y si eso cae dentro del
    -- margen de un disparo de verdad se cobraría el cargador entero de una vez. Ninguna
    -- arma de GTA dispara tan rápido, así que un salto así no es un disparo.
    if shots > math.ceil(window / 1000 * MAX_SHOTS_PER_SECOND) then return end

    local _, clip = GetAmmoInClip(ped, weapon)

    kec:emit("kec:onWeaponShoot", {
        ped = ped,
        weapon = weapon,
        shots = shots,
        clip = clip,
        ammo = ammo
    })
end)
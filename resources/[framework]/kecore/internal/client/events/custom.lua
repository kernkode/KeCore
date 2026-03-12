
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
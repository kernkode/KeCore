-- Espera que el mundo se cargue.
CreateThread(function()
    local ped = PlayerPedId()

    while not NetworkIsPlayerActive(PlayerId()) do
        Citizen.Wait(100)
    end

    local timer = GetGameTimer()
    while (not HasCollisionLoadedAroundEntity(ped) and (GetGameTimer() - timer) < 5000) do
        Citizen.Wait(100)
    end

    timer = GetGameTimer()
    while not HaveAllStreamingRequestsCompleted(ped) and (GetGameTimer() - timer) < 5000 do
        Wait(100)
    end

    isWorldLoaded = true

    Wait(500)
    kec:emitServer("kec:onPlayerLoaded")
    kec:emit("kec:onPlayerLoaded")
end)

exports("isWorldLoaded", function()
    return isWorldLoaded
end)
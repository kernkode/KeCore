local vehicleDestroyedHandlers = {}

function kec:on_vehicle_destroyed(handler)
    table.insert(vehicleDestroyedHandlers, handler)
end

AddEventHandler('gameEventTriggered', function(eventName, eventData)
    if eventName ~= 'CEventNetworkEntityDamage' then return end
    if #vehicleDestroyedHandlers == 0 then return end

    local victim = eventData[1]
    if not victim or not DoesEntityExist(victim) then return end
    if not IsEntityAVehicle(victim) or not IsEntityDead(victim) then return end

    local plate = GetVehicleNumberPlateText(victim)
    local model = GetEntityModel(victim)

    for _, handler in ipairs(vehicleDestroyedHandlers) do
        handler(victim, plate, model)
    end
end)

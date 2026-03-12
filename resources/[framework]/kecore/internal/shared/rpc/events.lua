RegisterNetEvent(RPC_RESPONSE_EVENT, function(gen_id, result)
    finalizeRequest(gen_id, true, result)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Si este recurso se detiene, limpiamos todo
        for gen_id, req in pairs(pendingRequests) do
            if req.timeoutHandle then ClearTimeout(req.timeoutHandle) end
            if req.promise then req.promise:resolve(nil) end
        end
        pendingRequests = {}
    elseif cache[resourceName] then
        -- Si otro recurso que registró RPCs se detiene
        for _, func in ipairs(cache[resourceName]) do
            RemoveEventHandler(func)
        end
        cache[resourceName] = nil
    end
end)

RegisterNetEvent(RPC_ERROR_EVENT, function(gen_id, errorType)
    local req = pendingRequests[gen_id]
    if req then
        print(("^1[RPC ERROR] El RPC '%s' no existe en el destino. Abortando callback.^0"):format(req.name))
        finalizeRequest(gen_id, false, "RPC_NOT_FOUND", true)
    end
end)

-- Evento central que recibe todas las peticiones RPC de red
RegisterNetEvent(RPC_NETWORK_EVENT, function(rpc_name, gen_id, ...)
    local src = source
    local args = {...}

    local rpc_hash = tostring(kec:hash(rpc_name))
    local handlerData = registeredHandlers[rpc_hash]

    -- VALIDACIÓN INSTANTÁNEA
    if not handlerData or not handlerData.isNetwork then
        -- Determinamos quién es el "agresor" para el log
        local originName = "CLIENTE [" .. tostring(src) .. "]"
        if not IS_SERVER then
            originName = "EL SERVIDOR"
        end

        print(("^1[SEGURIDAD/RPC] Bloqueado: '%s' intentó ejecutar el RPC '%s' (inválido o local).^0"):format(originName, rpc_name))

        -- Devolver error para que el emisor no se quede colgado
        if IS_SERVER then
            TriggerClientEvent(RPC_ERROR_EVENT, src, gen_id, "NOT_FOUND_OR_LOCAL")
        else
            TriggerServerEvent(RPC_ERROR_EVENT, gen_id, "NOT_FOUND_OR_LOCAL")
        end
        return
    end

    -- Si pasa la validación, ejecutamos el handler de forma segura
    local success, result = pcall(function()
        if IS_SERVER then
            local player = kec:player(src)
            return handlerData.func(player, table.unpack(args))
        else
            return handlerData.func(table.unpack(args))
        end
    end)

    if not success then
        print(("^1[RPC ERROR] Fallo ejecutando '%s': %s^0"):format(rpc_name, tostring(result)))
        result = nil
    end

    -- Devolvemos la respuesta
    if IS_SERVER then
        kec:emitClient(RPC_RESPONSE_EVENT, src, gen_id, result)
    else
        kec:emitServer(RPC_RESPONSE_EVENT, gen_id, result)
    end
end)
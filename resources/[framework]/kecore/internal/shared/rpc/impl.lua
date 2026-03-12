kec.rpc = {}

-- Helper para finalizar una petición
function finalizeRequest(gen_id, success, result, isNotFoundError)
    local req = pendingRequests[gen_id]
    if not req then return end

    if req.timeoutHandle then ClearTimeout(req.timeoutHandle) end
    pendingRequests[gen_id] = nil

    if req.callback then
        -- Si es un error de "No encontrado", abortamos la ejecución del callback
        if isNotFoundError then
            return
        end

        Citizen.CreateThread(function()
            if success then
                req.callback(result)
            else
                req.callback(nil)
            end
        end)
    else
        -- Modo Await (Promesas)
        if success then
            req.promise:resolve(result)
        else
            req.promise:reject(result or "RPC Error")
        end
    end
end

local requestCounter = 0

local function getNextId()
    requestCounter = requestCounter + 1
    -- Si llega al límite de 16 bits, reiniciamos
    if requestCounter > 65535 then 
        requestCounter = 1 
    end
    return requestCounter
end

local function handleAwait(name, timeout, triggerCallback, responseCallback)
    local p = nil
    local gen_id = getNextId()
    timeout = timeout or DEFAULT_TIMEOUT

    if not responseCallback then p = promise.new() end

    pendingRequests[gen_id] = {
        name = name,
        promise = p,
        callback = responseCallback,
        resource = GetInvokingResource(),
        timeoutHandle = SetTimeout(timeout, function()
            finalizeRequest(gen_id, false, "RPC timeout: " .. name)
        end)
    }

    -- Ejecutar el disparo
    triggerCallback(gen_id)

    -- Si es modo callback, no hay nada que esperar aquí
    if responseCallback then return end

    -- MODO AWAIT SEGURO:
    -- Usamos pcall para que si la promesa se rechaza (p:reject), 
    -- el script no lance un "SCRIPT ERROR" y simplemente continúe.
    local success, result = pcall(Citizen.Await, p)

    if not success then
        -- Aquí 'result' contiene el mensaje de error ("RPC_NOT_FOUND" o "RPC timeout")
        -- Devolvemos nil para que el script que llamó al RPC pueda manejarlo
        return nil
    end

    return result
end


--------------------------------------------------------------------------------
-- MÉTODOS PÚBLICOS
--------------------------------------------------------------------------------

--- Registra una función para ser llamada remotamente
function kec.rpc:register(name, handler, isNetwork)
    if isNetwork == nil then isNetwork = true end

    local rpc_hash = tostring(kec:hash(name))
    local invokingRes = GetInvokingResource()
    
    -- Guardamos la función directamente para que el enrutador pueda usarla
    registeredHandlers[rpc_hash] = {
        isNetwork = isNetwork,
        func = handler 
    }

    -- SOLO registramos un evento local para uso interno dentro de la misma máquina
    local handler_func = AddEventHandler(rpc_hash, function(gen_id, ...)
        local args = {...}
        -- Validación estricta de que esto es puramente local
        if source ~= nil and tostring(source) ~= "" then return end

        local success, ret = pcall(function() return handler(table.unpack(args)) end)

        kec:emit(RPC_RESPONSE_EVENT, gen_id, success and ret or nil)
    end)

    if not cache[invokingRes] then cache[invokingRes] = {} end
    table.insert(cache[invokingRes], handler_func)
end

--- Llamada RPC Local
function kec.rpc:awaitLocal(name, timeout, ...)
    local rpc_hash = tostring(kec:hash(name))
    local handler = registeredHandlers[rpc_hash]

    if not handler then
        print(("^1[RPC ERROR] El RPC local '%s' no existe o no ha sido registrado. Ejecución abortada.^0"):format(name))
        return nil
    end

    if handler.isNetwork then
        print(("^1[RPC ERROR] El RPC local '%s' es de red y no puede ser llamado localmente. Ejecución abortada.^0"):format(name))
        return nil
    end

    local args = table.pack(...)
    local callback = nil

    -- Detectar callback en el primer argumento
    if type(args[1]) == "function" or (type(args[1]) == "table" and args[1].__cfx_functionReference) then
        callback = table.remove(args, 1)
        args.n = args.n - 1
    end

    -- VALIDACIÓN INMEDIATA: Comprobamos si el handler está registrado
    if not handler then
        print(("^1[RPC ERROR] El RPC local '%s' no existe o no ha sido registrado. Ejecución abortada.^0"):format(name))
        return nil
    end

    -- Si el evento sí existe, procedemos normalmente
    return handleAwait(name, timeout, function(gen_id)
        kec:emit(rpc_hash, gen_id, table.unpack(args, 1, args.n))
    end, callback)
end

--- Llamada RPC de Red (Server <-> Client)
function kec.rpc:await(name, timeout, ...)
    local args = table.pack(...)
    local callback = nil

    if type(args[1]) == "function" or (type(args[1]) == "table" and args[1].__cfx_functionReference) then
        callback = table.remove(args, 1)
        args.n = args.n - 1
    end

    return handleAwait(name, timeout, function(gen_id)
        if IS_SERVER then
            local targetSrc = args[1]
            if type(targetSrc) ~= "number" then
                return error("RPC await [Server]: El primer argumento debe ser el ID del jugador")
            end
            
            -- UN SOLO EVENTO: Enviamos al cliente la petición
            kec:emitClient("kec:rpc:triggerNetwork", targetSrc, name, gen_id, table.unpack(args, 2, args.n))
        else
            -- UN SOLO EVENTO: Enviamos al servidor la petición
            kec:emitServer("kec:rpc:triggerNetwork", name, gen_id, table.unpack(args, 1, args.n))
        end
    end, callback)
end
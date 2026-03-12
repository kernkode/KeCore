-- =========================================================
-- CORE DEL RPC (Server Side)
-- =========================================================
kec = kec or {}
kec.rpc = {}

-- Configuración
local DEFAULT_TIMEOUT = 5000
local IS_SERVER = IsDuplicityVersion()

-- Estado interno
local pendingRequests = {}
local registeredHandlers = {}

-- Eventos internos (Strings puros para evitar errores de Hashing)
local RPC_RESPONSE_EVENT = "kec:rpc:response"
local RPC_NETWORK_EVENT = "kec:rpc:triggerNetwork"

-- Helper para finalizar
local function finalizeRequest(gen_id, success, result)
    print(string.format("^3[DEBUG] Finalizando ID: %s | Success: %s^0", gen_id, tostring(success)))
    
    local req = pendingRequests[gen_id]
    if not req then return end

    if req.timeoutHandle then ClearTimeout(req.timeoutHandle) end
    pendingRequests[gen_id] = nil

    if req.callback then
        Citizen.CreateThread(function()
            if success then req.callback(result) else req.callback(nil) end
        end)
    else
        if success then req.promise:resolve(result) else req.promise:reject(result or "RPC Error") end
    end
end

local currentResource = GetCurrentResourceName()
local requestCounter = 0
local function getNextId()
    requestCounter = requestCounter + 1
    if requestCounter > 65535 then requestCounter = 1 end
    -- Combinamos el nombre del recurso que SOLICITA con el contador
    return currentResource .. "_" .. tostring(requestCounter)
end

local function handleAwait(name, timeout, triggerFunction, responseCallback)
    local p = nil
    local gen_id = getNextId()
    timeout = timeout or DEFAULT_TIMEOUT

    if not responseCallback then p = promise.new() end

    pendingRequests[gen_id] = {
        name = name,
        promise = p,
        callback = responseCallback,
        timeoutHandle = SetTimeout(timeout, function()
            print("^1[DEBUG] Timeout ID: " .. gen_id .. " ("..name..")^0")
            finalizeRequest(gen_id, false, "RPC timeout")
        end)
    }

    -- IMPORTANTE: SetTimeout(0) para asegurar que la promesa esté escuchando
    Citizen.SetTimeout(0, function()
        triggerFunction(gen_id)
    end)

    if responseCallback then return end

    local success, result = pcall(Citizen.Await, p)
    if not success then return nil end
    return result
end

--------------------------------------------------------------------------------
-- MÉTODOS PÚBLICOS
--------------------------------------------------------------------------------

function kec.rpc:register(name, handler, isNetwork)
    if isNetwork == nil then isNetwork = true end
    
    -- CAMBIO CLAVE: Usamos String en lugar de Hash
    local internalEventName = "kec:rpc:loc:" .. name
    print("^2[RPC] Registrando evento local: " .. internalEventName .. "^0")

    -- Guardamos metadata
    registeredHandlers[name] = { isNetwork = isNetwork, func = handler }

    -- Registramos el evento LOCAL
    AddEventHandler(internalEventName, function(gen_id, ...)
        print("^5[DEBUG] Handler activado para ID: " .. tostring(gen_id) .. "^0")
        
        -- Ejecutamos la función real
        local args = {...}
        local success, ret = pcall(function() return handler(table.unpack(args)) end)

        if not success then print("^1[ERROR] Fallo en handler: " .. tostring(ret) .. "^0") end

        -- Devolvemos respuesta
        kec:emit(RPC_RESPONSE_EVENT, gen_id, success and ret or nil)
    end)
end

function kec.rpc:awaitLocal(name, timeout, ...)
    local args = table.pack(...)
    local internalEventName = "kec:rpc:loc:" .. name

    return handleAwait(name, timeout, function(gen_id)
        print("^5[DEBUG] Disparando evento local: " .. internalEventName .. " | ID: " .. gen_id .. "^0")
        -- Usamos TriggerEvent con el STRING
        TriggerEvent(internalEventName, gen_id, table.unpack(args, 1, args.n))
    end)
end

-- Helpers básicos para que funcione el script
function kec:emit(name, ...) TriggerEvent(name, ...) end
function kec:emitClient(name, target, ...) TriggerClientEvent(name, target, ...) end

-- Manejador de respuestas (Genérico)
RegisterNetEvent(RPC_RESPONSE_EVENT, function(gen_id, result)
    finalizeRequest(gen_id, true, result)
end)


-- =========================================================
-- TU PRUEBA (Debe ir DESPUÉS de definir kec.rpc)
-- =========================================================

-- 1. Registramos
kec.rpc:register("auth:get_account_idx", function(discord)
    print("^2[EJECUCION REAL] auth:get_account_id ejecutado con: " .. tostring(discord) .. "^0")
    return "asd_retornado_correctamente"
end, false)

-- 2. Ejecutamos
Citizen.CreateThread(function()
    Citizen.Wait(500) -- Pequeña espera de cortesía
    print("Solicitando ID...")
    local account_id = kec.rpc:awaitLocal("auth:get_account_idx", nil, "mi_discord_id")
    print("-------------------------------------------------")
    print("RESULTADO FINAL:", account_id) 
    print("-------------------------------------------------")
end)
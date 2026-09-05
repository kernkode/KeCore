-- Configuración
DEFAULT_TIMEOUT = 5000
IS_SERVER = IsDuplicityVersion()

-- Estado interno encapsulado
kec._internal = kec._internal or {}
kec._internal.rpc = kec._internal.rpc or {
    cache = {},
    pendingRequests = {},
    registeredHandlers = {}
}

-- Estos tres son GLOBALES a propósito: los comparten header/impl/events, que son tres chunks
-- distintos del fxmanifest y no comparten locales. `rpcHandlerCache` y no `cache` porque un
-- nombre así de genérico en el _G de kecore es una colisión esperando a que alguien se olvide
-- de un `local` (events/manager.lua tiene su propio `cache`, ese sí local).
rpcHandlerCache = kec._internal.rpc.cache
pendingRequests = kec._internal.rpc.pendingRequests
registeredHandlers = kec._internal.rpc.registeredHandlers

RPC_ERROR_EVENT = "kec:rpc:error"
RPC_RESPONSE_EVENT = "kec:rpc:response"
RPC_NETWORK_EVENT = "kec:rpc:triggerNetwork"
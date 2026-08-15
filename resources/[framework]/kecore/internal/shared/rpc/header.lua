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

cache = kec._internal.rpc.cache
pendingRequests = kec._internal.rpc.pendingRequests
registeredHandlers = kec._internal.rpc.registeredHandlers

RPC_ERROR_EVENT = "kec:rpc:error"
RPC_RESPONSE_EVENT = "kec:rpc:response"
RPC_VALIDATE_EVENT = "kec:rpc:validate"
RPC_NETWORK_EVENT = "kec:rpc:triggerNetwork"
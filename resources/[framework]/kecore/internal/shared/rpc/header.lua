-- Configuración
DEFAULT_TIMEOUT = 5000
IS_SERVER = IsDuplicityVersion()

-- Estado interno
cache = {}
pendingRequests = {}
registeredHandlers = {}

RPC_ERROR_EVENT = "kec:rpc:error"
RPC_RESPONSE_EVENT = "kec:rpc:response"
RPC_VALIDATE_EVENT = "kec:rpc:validate"
RPC_NETWORK_EVENT = "kec:rpc:triggerNetwork"
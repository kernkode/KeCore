local cache = {}

-- `IsDuplicityVersion()` no cambia en toda la vida del proceso: se resuelve una vez y no en
-- cada despacho de cada evento.
local IS_SERVER = IsDuplicityVersion()

--- Llama al callback y deja el error en consola si revienta.
---
--- `withSource` antepone el `source` del evento como primer argumento: los eventos de red y
--- los del ciclo de vida del jugador lo traen en la global del motor y no en los args, y los
--- wrappers lo esperan delante. Se lee AQUÍ, en la VM de kecore, porque es la única donde el
--- motor lo pone: un consumidor con su copia inyectada de `server/events.lua` recibe el
--- callback como funcref y en su VM la global no vale nada.
---
--- Va fuera del handler a propósito: definida dentro se alojaba una closure en CADA despacho
--- de CADA evento.
local function dispatch(name, callback, withSource, ...)
    local ok, err

    if withSource and IS_SERVER and source ~= '' then
        ok, err = pcall(callback, source, ...)
    else
        ok, err = pcall(callback, ...)
    end

    -- El fallo de un callback SIEMPRE se imprime. Detrás de `debugEvents` (false por defecto)
    -- cualquier excepción de un handler quedaba muda: un kec:onPlayerLoaded que reventaba
    -- dejaba al cliente en la pantalla de carga sin una línea en consola. El pcall sigue: un
    -- handler roto no tumba al resto.
    if not ok then
        print(("^1[events] ERROR en el callback del evento '%s': %s^7"):format(name, err))
    end
end

--- Registra UN nombre de evento.
---
--- `net` es la diferencia que importa: `RegisterNetEvent` no abre solo tu handler, abre el
--- NOMBRE, y a partir de ahí un cliente puede disparar el evento y corren todos los handlers
--- que lo escuchen —incluidos los de `AddEventHandler`—. Solo va a `true` para los eventos que
--- de verdad cruzan la red; para los del motor (ciclo de vida, recursos, eventos de juego) el
--- registro es local o el cliente puede fingirlos.
local function register(name, callback, net, withSource)
    local handler

    if net then
        handler = RegisterNetEvent(name, function(...)
            dispatch(name, callback, withSource, ...)
        end)
    else
        handler = AddEventHandler(name, function(...)
            dispatch(name, callback, withSource, ...)
        end)
    end

    -- Se apunta cada handler al recurso que lo pidió (en array: un recurso registra muchos)
    -- para que el onResourceStop del final los quite TODOS y no solo el último.
    --
    -- Sin esto no los limpiaba nadie: este módulo NO se inyecta (no está en perf-modules.ts),
    -- así que el `kec:on` de un consumidor corre en la VM de kecore con el callback como
    -- referencia y el handler acaba siendo de kecore. Al reiniciar el consumidor su callback se
    -- quedaba registrado apuntando a una VM muerta, y el siguiente TriggerEvent imprimía
    -- "Execution of function reference in script host failed".
    local res = GetInvokingResource() or "this"
    if not cache[res] then cache[res] = {} end
    table.insert(cache[res], handler)
end

---Se Utiliza para escuchar un evento DE RED (el nombre queda abierto a la red)
---@param self any
---@param name string|table -- Puede ser un string con el nombre del evento o una tabla con múltiples nombres
---@param callback any
function kec:on(name, callback)
    -- Si name es una tabla, procesar múltiples eventos
    if type(name) == "table" then
        for _, eventName in ipairs(name) do
            if type(eventName) == "string" then
                register(eventName, callback, true, true)
            else
                error(("[events] Nombre de evento inválido en la tabla: %s"):format(tostring(eventName)), 2)
            end
        end
        return
    end

    -- Si name es un string, procesar un solo evento
    if type(name) == "string" then
        register(name, callback, true, true)
        return
    end

    error("[events] El parámetro 'name' debe ser un string o una tabla de strings", 2)
end

--- Escucha un evento LOCAL (AddEventHandler): no se puede disparar desde la red.
--- Es el registro que va con los eventos del motor y con los `kec:emit` de la propia máquina.
---@param name string
---@param callback function
---@param withSource boolean|nil `true` antepone el `source` del evento al callback (servidor)
function kec:onLocal(name, callback, withSource)
    register(name, callback, false, withSource)
end

function kec:on_player(name, handler)
    self:on(name, function (src, ...)
        local player = self:player(src)

        if player then
            handler(player, ...)
        end
    end)
end

---Se utiliza para emitir un evento a algun cliente.
---@param self any
---@param event any
---@param source any
---@param ... unknown
function kec:emitClient(event, source, ...)
    TriggerClientEvent(event, source, ...)
end

---Se utiliza para emitir un evento a todos los clientes
---@param self any
---@param event any
---@param ... unknown
function kec:emitAllClients(event, ...)
    TriggerClientEvent(event, -1, ...)
end

---Se utiliza para emitir un evento al servidor
---@param self any
---@param event any
---@param ... unknown
function kec:emitServer(event, ...)
    TriggerServerEvent(event, ...)
end

function kec:emit(event, ...)
    TriggerEvent(event, ...)
end

function kec:on_resource_start(handler)
    -- Capture the caller BEFORE registering; GetInvokingResource() inside the
    -- event callback returns the framework resource, not the original caller.
    local invokingRes = GetInvokingResource()
    -- En local: `onResourceStart` es del motor, y por `kec:on` el nombre quedaba abierto a la
    -- red (un cliente podía fingir el arranque de cualquier recurso).
    self:onLocal("onResourceStart", function(resourceName)
        if resourceName == invokingRes then
            Wait(1000)
            handler()
        end
    end)
end

function kec:on_resource_stop(handler)
    local invokingRes = GetInvokingResource()
    self:onLocal("onResourceStop", function(resourceName)
        if resourceName == invokingRes then
            handler()
        end
    end)
end

AddEventHandler("onResourceStop", function(resourceName)
    for _, func in ipairs(cache[resourceName] or {}) do
        RemoveEventHandler(func)
    end
    cache[resourceName] = nil
end)
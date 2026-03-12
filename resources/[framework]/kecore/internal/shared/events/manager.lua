local handlers = {}
local cache = {}

---Se Utiliza para escuchar un evento
---@param self any
---@param name string|table -- Puede ser un string con el nombre del evento o una tabla con múltiples nombres
---@param callback any
function kec:on(name, callback)
    -- Si name es una tabla, procesar múltiples eventos
    if type(name) == "table" then
        for _, eventName in ipairs(name) do
            if type(eventName) == "string" then
                self:registerSingleEvent(eventName, callback)
            else
                error(("[events] Nombre de evento inválido en la tabla: %s"):format(tostring(eventName)), 2)
            end
        end
        return
    end

    -- Si name es un string, procesar un solo evento
    if type(name) == "string" then
        self:registerSingleEvent(name, callback)
        return
    end

    error("[events] El parámetro 'name' debe ser un string o una tabla de strings", 2)
end

-- Función auxiliar para registrar un solo evento (para evitar duplicación de código)
function kec:registerSingleEvent(name, callback)
    if not handlers[name] then
        handlers[name] = {}
    end

    local success, err = pcall(function()
        local handler = RegisterNetEvent(name, function(...)
            local numArgs = select('#', ...)

            local function callFunc(fn, ...)
                if kec:isServer() then
                    if source == '' then
                        success, err = pcall(fn, ...)
                    else
                        success, err = pcall(fn, source, ...)
                    end
                else
                    success, err = pcall(fn, ...)
                end
            end

            callFunc(callback, ...)

            if not success and kec.debugEvents then
                print(("^1[events] ERROR en el callback del evento '%s': %s^7"):format(name, err))
            end
        end)

        cache[GetInvokingResource() or "this"] = handler
        handlers[name] = handler
        --print(("%s %s"):format(GetInvokingResource(), json.encode(handler)))
    end)

    if not success then
        error(("[events] Error al registrar el evento '%s': %s"):format(name, err), 2)
    end
end

function kec:onLocal(name, callback)
    -- Create the handler function that will be executed when the event is triggered.
    local handler = function(...)
        -- Use pcall to safely execute the provided callback, preventing resource crashes.
        local success, err = pcall(callback, ...)
        -- If an error occurred and debug mode is on, print the error to the console.
        if not success and shared.debugMode then
            print(("^1[events] ERROR en el callback del evento local '%s': %s^7"):format(name, err))
        end
    end

    -- Register the handler for the specified local event name.
    AddEventHandler(name, handler)
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
    self:on("onResourceStart", function(resourceName)
        if resourceName == GetInvokingResource() then
            Wait(1000)
            handler()
        end
    end)
end

function kec:on_resource_stop(handler)
    self:on("onResourceStop", function(resourceName)
        if resourceName == GetInvokingResource() then
            handler()
        end
    end)
end

AddEventHandler("onResourceStop", function(resourceName)
    print("Resource stopped: " .. resourceName)
    for key, func in pairs(cache) do
        if key == resourceName then
            RemoveEventHandler(func)
            print("Removed event handler for resource: " .. resourceName)
        end
    end
end)
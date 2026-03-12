-- Aseguramos que la tabla base existe

local axios = {}

-- Configuración por defecto
axios.defaults = {
    headers = {
        ['Content-Type'] = 'application/json',
        ['Accept'] = 'application/json'
    },
    timeout = 5000 -- 5 segundos
}

-- Helper para mezclar configuraciones
local function mergeConfigs(default, custom)
    local result = {}
    for k, v in pairs(default) do result[k] = v end
    for k, v in pairs(custom or {}) do result[k] = v end
    return result
end

-- Función base para todas las peticiones
function axios:request(method, url, data, config, cb)
    -- Determinamos qué configuración base usar (si venimos de una instancia o de la global)
    local baseConfig = config and config._instanceConfig or axios.defaults
    local finalConfig = mergeConfigs(baseConfig, config or {})

    local payload = data and json.encode(data) or ''
    local callbackCalled = false

    -- Manejo de timeout
    local timeoutTimer = nil
    if finalConfig.timeout then
        timeoutTimer = SetTimeout(finalConfig.timeout, function()
            if not callbackCalled and cb then
                callbackCalled = true
                cb('timeout', nil, nil)
            end
        end)
    end

    PerformHttpRequest(url, function(err, responseText, headers)
        -- Si ya se llamó al callback (por timeout), ignorar
        if callbackCalled then return end

        -- Cancelar el timeout si la respuesta llegó
        if timeoutTimer then ClearTimeout(timeoutTimer) end

        callbackCalled = true

        -- Procesar la respuesta
        local responseData = nil
        local success = (err == nil or err == 200)

        if success and responseText and responseText ~= '' then
            local successParse, parsed = pcall(json.decode, responseText)
            if successParse then
                responseData = parsed
            end
        end

        -- Retornar al callback
        if cb then
            local response = {
                data = responseData,
                status = err,
                headers = headers,
                config = finalConfig,
                request = {
                    method = method,
                    url = url,
                    data = data
                }
            }

            if success then
                cb(nil, response)
            else
                cb(err or 'request_failed', response)
            end
        end
    end, method, payload, finalConfig.headers)
end

-- Métodos HTTP --

function axios:get(url, config, cb)
    return self:request('GET', url, nil, config, cb)
end

function axios:post(url, data, config, cb)
    return self:request('POST', url, data, config, cb)
end

function axios:put(url, data, config, cb)
    return self:request('PUT', url, data, config, cb)
end

function axios:delete(url, data, config, cb)
    return self:request('DELETE', url, data, config, cb)
end

function axios:patch(url, data, config, cb)
    return self:request('PATCH', url, data, config, cb)
end

-- Método para crear instancia con configuración personalizada
function axios:create(instanceConfig)
    local instance = {}

    -- Configuración base para esta instancia
    local myConfig = mergeConfigs(axios.defaults, instanceConfig or {})

    -- Helpers para inyectar la configuración de la instancia en cada llamada
    function instance:get(url, config, cb)
        config = config or {}
        config._instanceConfig = myConfig
        return axios:get(url, config, cb)
    end

    function instance:post(url, data, config, cb)
        config = config or {}
        config._instanceConfig = myConfig
        return axios:post(url, data, config, cb)
    end

    function instance:put(url, data, config, cb)
        config = config or {}
        config._instanceConfig = myConfig
        return axios:put(url, data, config, cb)
    end

    function instance:delete(url, data, config, cb)
        config = config or {}
        config._instanceConfig = myConfig
        return axios:delete(url, data, config, cb)
    end

    function instance:patch(url, data, config, cb)
        config = config or {}
        config._instanceConfig = myConfig
        return axios:patch(url, data, config, cb)
    end

    return instance
end

return axios
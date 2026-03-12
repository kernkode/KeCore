local http = {}

local routes = { GET = {}, POST = {}, PUT = {}, DELETE = {} }
local isHandlerRunning = false

-- Utilidad: Decodificar URL (ej: "Hola%20Mundo" -> "Hola Mundo")
local function urlDecode(str)
    if not str then return "" end
    str = string.gsub(str, "+", " ")
    return string.gsub(str, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
end

-- Utilidad: Parsear Body
local function parseBody(bodyString, contentType)
    if not bodyString or bodyString == '' then return {} end

    -- Intentar JSON primero si parece JSON o el header lo dice
    if string.sub(bodyString, 1, 1) == "{" or string.sub(bodyString, 1, 1) == "[" then
        local success, result = pcall(json.decode, bodyString)
        if success then return result end
    end

    -- Fallback a Form Data (x-www-form-urlencoded)
    local data = {}
    for key, value in string.gmatch(bodyString, "([^&=]+)=([^&=]*)") do
        data[urlDecode(key)] = urlDecode(value)
    end
    return data
end

-- Utilidad: Emparejar rutas (Soporte para /users/:id)
local function matchRoute(method, requestPath)
    local methodRoutes = routes[method] or {}
    
    -- 1. Búsqueda exacta (Más rápida)
    if methodRoutes[requestPath] then
        return methodRoutes[requestPath], {}
    end

    -- 2. Búsqueda por patrón (Para :id)
    for routePattern, handler in pairs(methodRoutes) do
        -- Convertir ruta /item/:id a patrón Lua: ^/item/([^/]+)$
        if routePattern:find(":") then
            local luaPattern = "^" .. routePattern:gsub(":([%w_]+)", "([^/]+)") .. "$"
            local matches = { string.match(requestPath, luaPattern) }
            
            if #matches > 0 then
                -- Extraer nombres de parámetros
                local params = {}
                local i = 1
                for paramName in routePattern:gmatch(":([%w_]+)") do
                    params[paramName] = matches[i] or nil
                    i = i + 1
                end
                return handler, params
            end
        end
    end

    return nil, {}
end

local function startHttpHandler()
    if isHandlerRunning then return end
    isHandlerRunning = true

    print('[http] 🚀 HTTP Handler Iniciado')

    SetHttpHandler(function(req, res)
        local method = req.method
        local path = req.path

        -- Encontrar el handler y los parámetros
        local handler, params = matchRoute(method, path)

        -- Métodos Helper para la respuesta (Estilo Express)
        function res:status(code)
            self.writeHead(code)
            return self
        end

        function res:json(data, code)
            code = code or 200
            self.writeHead(code, { ['Content-Type'] = 'application/json' })
            self.send(json.encode(data))
        end

        function res:error(msg, code)
            self:json({ status = "error", message = msg }, code or 400)
        end

        if handler then
            -- Procesar la petición
            local function processRequest(rawBody)
                local body = parseBody(rawBody)
                
                -- Objeto Request mejorado
                local requestEnhanced = {
                    path = path,
                    method = method,
                    headers = req.headers,
                    body = body,
                    params = params, -- Ahora tenemos params de ruta (/users/:id)
                    query = req.query, -- Nota: FiveM a veces devuelve esto como string, cuidado
                    rawBody = rawBody
                }

                -- Ejecutar handler protegido contra errores
                local success, err = pcall(handler, requestEnhanced, res)
                if not success then
                    print('[http] 💥 Error en ruta ' .. path .. ': ' .. tostring(err))
                    res:error("Internal Server Error", 500)
                end
            end

            -- Obtener body si es necesario
            if (method == 'POST' or method == 'PUT') and req.setDataHandler then
                req.setDataHandler(function(data)
                    processRequest(data)
                end)
            else
                processRequest('')
            end
        else
            res.writeHead(404)
            res.send('Not Found')
        end
    end)
end

-- Función interna para registrar
local function addRoute(method, path, handler)
    if path:sub(1,1) ~= '/' then path = '/' .. path end
    
    if not routes[method] then routes[method] = {} end
    routes[method][path] = handler
    
    print(string.format('[http] Ruta registrada [%s] %s', method, path))
    
    -- Iniciar handler si es la primera ruta y no ha iniciado
    if not isHandlerRunning then
        -- Usamos un pequeño delay seguro para agrupar registros
        Citizen.SetTimeout(100, startHttpHandler)
    end
end

-- API Pública
function http:get(path, cb) addRoute('GET', path, cb) end
function http:post(path, cb) addRoute('POST', path, cb) end
function http:put(path, cb) addRoute('PUT', path, cb) end
function http:delete(path, cb) addRoute('DELETE', path, cb) end

return http

-- Examples
--[[
kec.http:post('/api', function(req, res)
    local data = req.body
    print('[DISCORD API] 📥 Petición recibida en /api: ' .. json.encode(data))

    -- Ahora puedes usar res:json directamente
    res:json({
        success = true,
        message = 'Petición procesada correctamente'
    })
end)

kec.http:get('/jugador/:id', function(req, res)
    -- Si entras a /jugador/55, req.params.id será "55"
    local id = req.params.id

    if id == "1" then
        res:json({ id = 1, name = "Admin" })
    else
        res:error("Jugador no encontrado", 404)
    end
end)
--]]
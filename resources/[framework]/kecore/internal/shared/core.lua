-- ------------------------------------------------------------
-- Estado compartido ENTRE RECURSOS.
-- Cada recurso guarda su propia copia de los valores, así que LEER es un acceso a
-- tabla: sin salto entre runtimes ni serialización. Las ESCRITURAS se replican con
-- un evento del lado, de modo que todos convergen y los onChange saltan en todos.
-- Ahí está la ventaja sobre exports para compartir datos: con exports pagas una
-- llamada entre runtimes en cada lectura; aquí solo al escribir.
--
-- OJO: el ámbito es POR LADO. El estado del server y el del cliente son dos
-- espacios distintos; para cruzarlos siguen estando los eventos y kec.rpc.
-- Un recurso que arranque tarde se siembra con exports.kecore:stateSnapshot().
-- ------------------------------------------------------------
local STATE_SYNC = "kec:state:sync"

local stateValues = {}
local stateListeners = {}
local thisResource = GetCurrentResourceName()

--- Aplica un valor al estado local y avisa a los listeners. Devuelve si cambió.
local function applyState(key, value)
    local oldValue = stateValues[key]
    if oldValue == value then return false end
    stateValues[key] = value

    local listeners = stateListeners[key]
    if listeners then
        for i = #listeners, 1, -1 do
            local ok, err = pcall(listeners[i], value, oldValue)
            if not ok and kec.debugMode then
                print(("^1[state] ERROR in onChange callback for '%s': %s^7"):format(tostring(key), tostring(err)))
            end
        end
    end
    return true
end

local stateObj = setmetatable({}, {
    __index = function(_, key)
        return stateValues[key]
    end,
    __newindex = function(_, key, value)
        if applyState(key, value) then
            TriggerEvent(STATE_SYNC, key, value, thisResource)
        end
    end
})

-- Escritura de otro recurso: solo se aplica local (quien la originó ya la aplicó,
-- y re-emitir aquí sería un bucle).
AddEventHandler(STATE_SYNC, function(key, value, from)
    if from ~= thisResource then applyState(key, value) end
end)

function stateObj:get(key)
    return stateValues[key]
end

function stateObj:set(key, value)
    stateObj[key] = value
end

function stateObj:onChange(key, callback)
    if type(callback) ~= "function" then return function() end end
    stateListeners[key] = stateListeners[key] or {}
    table.insert(stateListeners[key], callback)

    return function()
        if stateListeners[key] then
            for i, cb in ipairs(stateListeners[key]) do
                if cb == callback then
                    table.remove(stateListeners[key], i)
                    break
                end
            end
        end
    end
end

--- Foto del estado actual, para que un recurso que arranque después no empiece a
--- ciegas (init.lua la pide al cargar).
exports('stateSnapshot', function() return stateValues end)

---@class kec
kec = {
    debugMode = false,
    debugEvents = false,
    isWorldLoaded = false,
    state = stateObj,
    _internal = {}
}

metadata = {
    player = {},
    vehicle = {},
    object = {}
}

kec.metadata = metadata

function kec:isServer()
    return IsDuplicityVersion()
end

function kec:isClient()
    return not IsDuplicityVersion()
end

function kec:hash(str)
    return GetHashKey(str)
end

--- Logging unificado del framework: kec.log:<nivel>(modulo, texto, ...formatArgs)
--- warn/error siempre visibles; debug solo cuando kec.debugMode está activo.
--- Los args extra se pasan por string.format (si no hay args, el texto va tal cual).
kec.log = {}

local LOG_COLORS = {
    debug = "^5",
    info  = "^7",
    warn  = "^3",
    error = "^1",
}

local function writeLog(level, module, text, ...)
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    print(("%s[%s:%s] %s^7"):format(LOG_COLORS[level], module, level, text))
end

function kec.log:debug(module, text, ...)
    if not kec.debugMode then return end
    writeLog("debug", module, text, ...)
end

function kec.log:info(module, text, ...)
    writeLog("info", module, text, ...)
end

function kec.log:warn(module, text, ...)
    writeLog("warn", module, text, ...)
end

function kec.log:error(module, text, ...)
    writeLog("error", module, text, ...)
end

exports('get', function()
    return kec
end)

---@class kec
kec = {
    debugMode = false,
    debugEvents = false,
    isWorldLoaded = false,
    state = {} -- Almacenamiento seguro para variables entre scripts (reemplaza a _G)
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

-- ------------------------------------------------------------
-- Estado compartido ENTRE RECURSOS. La fábrica vive en un único archivo que también carga
-- @kecore/init.lua en cada consumidor; así cada VM conserva su propia tabla y metatabla sin un
-- árbol generado intermedio.
-- ------------------------------------------------------------
local function loadChunk(path, ...)
    local chunk = LoadResourceFile("kecore", path)
    if not chunk then error("[kecore] falta " .. path) end

    local compiled, err = load(chunk, "@@kecore/" .. path)
    if not compiled then error("[kecore] " .. path .. " no compila: " .. tostring(err)) end

    return compiled(...)
end

local stateFactory = loadChunk("internal/modules/shared/state.lua")
local stateObj = stateFactory(nil, "kecore")

exports('stateSnapshot', function() return stateObj:snapshot() end)

-- Modo desarrollo: sale de DEV_MODE en el .env, que el devkit pasa como `+set kec_dev 1`
-- (scripts/core/serverManager.ts). Por argumento y no en server.cfg a propósito: una copia
-- de producción arranca sin el devkit y así nunca lo tiene. Con txAdmin tampoco hay
-- argumentos, allí va `setr kec_dev 1` a mano. Sin nada, apagado.
local devConvar = GetConvar("kec_dev", "0")
local isDev = devConvar == "1" or devConvar == "true"

-- El cliente solo ve convars replicados y `+set` no lo es: se replica aquí para que el
-- `kec.dev` de un recurso de cliente valga lo mismo que el del servidor.
if IsDuplicityVersion() then
    SetConvarReplicated("kec_dev", isDev and "1" or "0")
end

---@class kec
kec = {
    dev = isDev,
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

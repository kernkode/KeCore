local DEBUG = false -- Cambiado a false para silenciar los prints individuales
local chunks = {
    { "performance/shared/timers",      "/"},
    { "performance/shared/zod",         "zod" },
    { "performance/shared/lzwson",      "lzwson" },
    { "performance/shared/base64",      "base64" },
    { "performance/shared/lru_cache",   "lru_cache" },
    { "performance/shared/utils",       "utils" },
    { "performance/shared/enum",        "enum" },
    { "performance/shared/weapons",     "weapons" },

    { "performance/client/raycast",     "raycast",      "client" },
    { "performance/client/keys",        "keys",         "client" },
    { "performance/client/label3d",     "label3d",      "client" },
    { "performance/client/scaleform",   "scaleform",    "client" },
    { "performance/client/natives",     "natives",      "client" },
    { "performance/client/player",      "player",       "client" },
    { "performance/client/vehicle",     "vehicle",      "client" },
    { "performance/client/controls",    "controls",     "client" },
    { "performance/client/events",      "/",            "client" },
    
    { "performance/server/os",          "os",           "server" },
    { "performance/server/axios",       "axios",        "server" },
    { "performance/server/http",        "http",         "server" },
    { "performance/server/discord",     "discord",      "server" },
    { "performance/server/mongodb",     "mongodb",      "server" },
    { "performance/server/events",      "/",            "server" },
    { "performance/server/vehicle",     "vehicle",      "server" },
}

local context = IsDuplicityVersion() and "server" or "client"
local name_resource = "kecore"

---@type table
kec = setmetatable(exports[name_resource]:get() or {}, {
    __index = function() return {} end
})

-- Estado compartido entre recursos: copia local de los valores (leer = acceso a
-- tabla, sin salto entre runtimes) y las escrituras se replican por evento del lado,
-- así todos convergen y los onChange saltan en todos. Ver internal/shared/core.lua.
local STATE_SYNC = "kec:state:sync"
local thisResource = GetCurrentResourceName()

-- Foto inicial: un recurso que arranca después de kecore no debe empezar a ciegas.
-- pcall porque `bun run update:core` puede traer un kecore sin este export y no
-- vale la pena tumbar el arranque del recurso entero por eso.
local okSnapshot, snapshot = pcall(function() return exports[name_resource]:stateSnapshot() end)
local stateValues = (okSnapshot and type(snapshot) == "table") and snapshot or {}
local stateListeners = {}

local function applyState(key, value)
    local oldValue = stateValues[key]
    if oldValue == value then return false end
    stateValues[key] = value

    local listeners = stateListeners[key]
    if listeners then
        for i = #listeners, 1, -1 do
            pcall(listeners[i], value, oldValue)
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

kec.state = stateObj

metadata = kec.metadata or {
    player = {},
    vehicle = {},
    object = {}
}
kec.metadata = metadata

if context == "client" then
    native = exports[name_resource]:natives()

    -- kec.label2d no se inyecta como los demás módulos: el que pinta es el CEF de kecore y
    -- SendNUIMessage solo habla con el del recurso que lo llama, así que la llamada tiene que
    -- SALTAR a kecore. Aquí se rearma la tabla con los mismos métodos, cada uno apuntando al
    -- export de internal/client/label2d_nui.lua.
    --
    -- Se pisa lo que venga en `get()`: esa copia trae los métodos como funcref y llamarlos con
    -- `:` mandaría la tabla del CONSUMIDOR como self. Se pisa a propósito para que haya un solo
    -- salto y sea siempre el mismo.
    --
    -- La lista va explícita (y no un __index que fabrique cualquier método) porque hay quien
    -- pregunta si el método existe antes de llamarlo: stickers/client/utils.lua hace
    -- `kec.label2d[kind]` y si no es función imprime por consola. Si se añade un método en
    -- label2d_nui.lua, va también aquí.
    local label2d = {}

    for _, method in ipairs({ "showText", "success", "error", "info", "warning", "hide", "clear" }) do
        -- El `_` se come el self de `kec.label2d:info(...)`. Y la llamada al export va con `:`
        -- porque en forma de punto Citizen se queda el primer argumento como self y se pierde.
        label2d[method] = function(_, ...)
            return exports[name_resource]:label2d(method, ...)
        end
    end

    kec.label2d = label2d

    AddEventHandler("kec:onPlayerLoaded", function()
        kec.isWorldLoaded = true
    end)
end

local function print_debug(text, ...)
    if DEBUG then
        print(string.format(text, ...))
    end
end

-- Modificado para retornar el error en vez de imprimirlo directamente
local function loadModule(name)
    print_debug("Loading module: %s.lua", name)
    local fileName = name .. ".lua"
    local chunk = LoadResourceFile(name_resource, fileName)

    if not chunk then
        return nil, "The file could not be read"
    end

    local compiled, err = load(chunk, fileName)
    if not compiled then
        return nil, "Syntax error: " .. err
    end

    return compiled(), nil
end

---@param module table
---@param path string
function injectModule(module, path)
    for k, inject in pairs(module) do
        if path == "/" then
            print_debug("Injecting: " .. k)
            kec[k] = inject
        elseif path == "natives" then
            native[k] = inject
            print_debug("Injecting: native." .. k)
        else
            if not rawget(kec, path) then
                kec[path] = {}
            end
            kec[path][k] = inject
            print_debug("Injecting: " .. path .. "." .. k)
        end
    end
end

-- Variables de control para el mensaje final
local all_loaded = true
local loaded_count = 0
local errors = {}

for _, data in ipairs(chunks) do
    local name, path, _context = table.unpack(data)
    
    -- Lógica simplificada (sin goto)
    if not _context or _context == context then
        local module, err = loadModule(name)

        if module then
            injectModule(module, path)
            loaded_count = loaded_count + 1
        else
            all_loaded = false
            -- Guardamos el error específico para imprimirlo al final
            table.insert(errors, string.format("- %s.lua (%s)", name, err))
        end
    end
end

-- Evaluación final: Un solo mensaje de éxito, o el reporte de errores
if all_loaded then
    print_debug("^2[kecore] %d modules loaded correctly on side %s.^0", loaded_count, context)
else
    print_debug("^1[kecore] CRITICAL ERROR: One or more modules failed to load:^0")
    for _, errMsg in ipairs(errors) do
        print("^1  " .. errMsg .. "^0")
    end
end

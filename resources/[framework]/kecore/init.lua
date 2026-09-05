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

-- Hay módulos de kecore que NO se inyectan como los demás porque tienen que vivir una sola vez:
-- el que pinta o el que suena es el CEF de kecore, y SendNUIMessage solo habla con el del recurso
-- que la llama; y un registro compartido (los emisores de audio del servidor) deja de tener
-- sentido si cada recurso lleva su copia. A esos se llega por su export, y aquí se rearma la tabla
-- con los mismos métodos para que las llamadas no cambien.
--
-- Se pisa lo que venga en `get()`: esa copia trae los métodos como funcref y llamarlos con `:`
-- mandaría la tabla del CONSUMIDOR como self. Se pisa a propósito para que haya un solo salto y
-- sea siempre el mismo.
--
-- La lista va explícita (y no un __index que fabrique cualquier método) porque hay quien pregunta
-- si el método existe antes de llamarlo: stickers/client/utils.lua hace `kec.label2d[kind]` y si
-- no es función lo imprime por consola. Si se añade un método al módulo, va también aquí.
local function facade(exportName, methods)
    local module = {}

    for _, method in ipairs(methods) do
        -- El `_` se come el self de `kec.label2d:info(...)`. Y la llamada al export va en forma de
        -- método porque en forma de punto Citizen se queda el primer argumento como self y se
        -- pierde.
        module[method] = function(_, ...)
            local resource = exports[name_resource]
            return resource[exportName](resource, method, ...)
        end
    end

    return module
end

---@type table
kec = setmetatable(exports[name_resource]:get() or {}, {
    __index = function() return {} end
})

-- Modo desarrollo. Se lee del convar y NO de lo que trae `get()`: la tabla de arriba lleva un
-- __index que devuelve {} para lo que no existe, y un {} es truthy — con un kecore viejo, un
-- `if kec.dev then` dejaría suelto en producción justo lo que se quería quitar. El convar lo
-- pone el devkit desde DEV_MODE (.env) y kecore lo replica al cliente.
local devConvar = GetConvar("kec_dev", "0")
kec.dev = devConvar == "1" or devConvar == "true"

-- Estado compartido entre recursos: copia local de los valores (leer = acceso a
-- tabla, sin salto entre runtimes) y las escrituras se replican por evento del lado,
-- así todos convergen y los onChange saltan en todos. Ver internal/shared/state.lua.
--
-- Foto inicial: un recurso que arranca después de kecore no debe empezar a ciegas.
-- pcall porque `bun run update:core` puede traer un kecore sin este export y no
-- vale la pena tumbar el arranque del recurso entero por eso.
local okSnapshot, snapshot = pcall(function() return exports[name_resource]:stateSnapshot() end)
local stateValues = (okSnapshot and type(snapshot) == "table") and snapshot or {}

metadata = kec.metadata or {
    player = {},
    vehicle = {},
    object = {}
}
kec.metadata = metadata

if context == "client" then
    native = exports[name_resource]:natives()

    kec.label2d = facade("label2d", {
        "showText", "success", "error", "info", "warning", "hide", "clear"
    })

    kec.audio = facade("audio", {
        "play", "stop", "stopAll", "occlusion", "flat", "position", "attach", "list",
        "setVolume", "setMasterVolume", "getMasterVolume"
    })

    AddEventHandler("kec:onPlayerLoaded", function()
        kec.isWorldLoaded = true
    end)
else
    kec.audio = facade("audio", { "play", "stop", "list", "resolve", "search" })
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

-- Estado compartido entre recursos. La implementación es la MISMA que corre dentro de kecore
-- (internal/shared/state.lua → performance/shared/state.lua): se compila aquí en vez de
-- inyectarse con `injectModule` porque `kec.state` es una tabla CON metatabla —el
-- `kec.state.x = 1` de las llamadas— y la inyección copia clave por clave, que se la come.
-- Antes esto era una segunda copia del módulo escrita a mano en este archivo, y las dos ya
-- habían empezado a divergir.
local stateFactory, stateErr = loadModule("performance/shared/state")

if type(stateFactory) == "function" then
    kec.state = stateFactory(stateValues)
else
    print(("^1[kecore] no se pudo cargar el estado compartido (%s): kec.state queda vacío^7")
        :format(tostring(stateErr)))
    kec.state = { get = function() end, set = function() end, onChange = function() return function() end end }
end

---@param module table
---@param path string
local function injectModule(module, path)
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

-- Evaluación final: en silencio si todo cargó (DEBUG lo cuenta), y el fallo SIEMPRE en consola.
-- Un módulo que no carga deja al recurso sin la mitad del framework: eso no puede depender de un
-- flag de debug (la cabecera del error iba por print_debug y no salía nunca).
if all_loaded then
    print_debug("^2[kecore] %d modules loaded correctly on side %s.^0", loaded_count, context)
else
    print("^1[kecore] ERROR: uno o más módulos no cargaron:^0")
    for _, errMsg in ipairs(errors) do
        print("^1  " .. errMsg .. "^0")
    end
end

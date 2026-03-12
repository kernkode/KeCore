local DEBUG = false -- Cambiado a false para silenciar los prints individuales
local chunks = {
    { "performance/shared/timers",      "/"},
    { "performance/shared/zod",         "zod" },
    { "performance/shared/lzwson",      "lzwson" },
    { "performance/shared/base64",      "/" },
    { "performance/shared/lru_cache",   "lru_cache" },
    { "performance/shared/utils",       "utils" },
    { "performance/shared/enum",        "enum" },

    { "performance/client/raycast",     "raycast",      "client" },
    { "performance/client/keys",        "keys",         "client" },
    { "performance/client/label3d",     "label3d",      "client" },
    { "performance/client/scaleform",   "scaleform",    "client" },
    --{ "performance/client/world",       "/",      "client" },
    { "performance/client/natives",     "natives",      "client" },
    
    { "performance/server/os",          "os",           "server" },
    { "performance/server/axios",       "axios",        "server" },
    { "performance/server/http",        "http",         "server" },
    { "performance/server/discord",     "discord",      "server" },
}

local context = IsDuplicityVersion() and "server" or "client"
local name_resource = "kecore"

---@type table
kec = setmetatable(exports[name_resource]:get() or {}, {
    __index = function() return {} end
})

if context == "client" then
    native = exports[name_resource]:natives()
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
        return nil, "No se pudo leer el archivo"
    end

    local compiled, err = load(chunk, fileName)
    if not compiled then
        return nil, "Error de sintaxis: " .. err
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
    print_debug("^2[kecore] %d módulos cargados correctamente en lado %s.^0", loaded_count, context)
else
    print_debug("^1[kecore] ERROR CRÍTICO: Falló la carga de uno o más módulos:^0")
    for _, errMsg in ipairs(errors) do
        print("^1  " .. errMsg .. "^0")
    end
end
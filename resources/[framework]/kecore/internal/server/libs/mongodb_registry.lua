--[[
    Registro central de schemas de MongoDB.

    Este archivo vive SOLO dentro del recurso kecore (no se transpila a
    performance/): la tabla `registry` de aquí es la única copia real. Los
    consumidores llegan a estas funciones como refs de la tabla base que
    entrega `exports.kecore:get()`, así cualquier recurso puede registrar un
    schema y cualquier otro puede importarlo por nombre.

    Son funciones con punto (sin self) a propósito: una llamada por ref con
    `:` serializaría la tabla kec completa del consumidor en cada invocación.
    Las definiciones son datos puros (strings/tablas), que cruzan recursos
    sin problema.
]]

local registry = {}

--- Registra (o re-registra, en hot-reload) la definición de un schema.
--- Devuelve un string de error o nil si todo fue bien (retorno único para
--- que el protocolo por refs sea inequívoco).
---@param name string
---@param definition table { collection = string, schema = tabla zod, defaults = table? }
---@return string|nil error
function kec.mongoSchemaRegister(name, definition)
    if type(name) ~= "string" or name == "" then
        return "schema sin nombre válido"
    end
    if type(definition) ~= "table"
        or type(definition.collection) ~= "string"
        or type(definition.schema) ~= "table" then
        return ("schema '%s' necesita 'collection' (string) y 'schema' (tabla zod)"):format(name)
    end

    if registry[name] then
        kec.log:warn("mongodb", "schema '%s' re-registrado (hot-reload)", name)
    end

    registry[name] = definition
    return nil
end

--- Devuelve la definición registrada bajo `name`, o nil si no existe.
---@param name string
---@return table|nil
function kec.mongoSchemaGet(name)
    return registry[name]
end

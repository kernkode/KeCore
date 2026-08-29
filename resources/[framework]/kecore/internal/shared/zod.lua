kec.zod = {}

-- Validador de esquemas en forma de JSON Schema, al día con zod 4.5
-- (https://zod.dev/blog/zod-4-5).
--
-- Cada restricción vive en UN sitio: `build` monta la lista de comprobaciones de un
-- nodo y las dos rutas —la rápida, que solo dice sí o no, y la que junta los
-- mensajes— recorren esa misma lista. Antes había dos implementaciones y ya habían
-- discrepado: la de `compile()` se dejaba enum, multipleOf, los topes de array y el
-- chequeo estricto de array, así que `compile():check` aceptaba datos que `validate`
-- rechazaba. Es el motivo por el que zod genera su fast-path DESDE el schema en vez
-- de escribirlo a mano.

-- Longitud en puntos de código y no en bytes, como en 4.5: `#` cuenta bytes, "José"
-- mide 5, y un apellido de 15 letras con acentos no pasaba un maxLength de 15.
local utf8_len = utf8 and utf8.len

local function str_len(value)
    if not utf8_len then return #value end
    -- UTF-8 roto (un byte suelto de un cliente hostil): no hay puntos de código que
    -- contar, así que se cuentan bytes antes que reventar.
    return utf8_len(value) or #value
end

-- Formatos de string. `creditCard` es el que estrena 4.5: de 12 a 19 dígitos,
-- separados como mucho por un espacio o un guión, y con checksum de Luhn.
local FORMATS = {
    creditCard = function(value)
        if not value:match("^%d[%d -]*%d$") then return false end
        if value:find("[ -][ -]") then return false end

        local digits = (value:gsub("[ -]", ""))
        local length = #digits
        if length < 12 or length > 19 then return false end

        local sum, double = 0, false

        for i = length, 1, -1 do
            local digit = digits:byte(i) - 48

            if double then
                digit = digit * 2
                if digit > 9 then digit = digit - 9 end
            end

            sum = sum + digit
            double = not double
        end

        return sum % 10 == 0
    end
}
-- zod no tiene esquemas sin tipo: `z.object({...})` ES un objeto. Aquí el `type`
-- podía faltar y entonces no se comprobaba NADA (el validador del alta de personaje
-- de auth aceptaba cualquier payload), así que cuando falta se deduce de las palabras
-- clave del nodo. Deducirlo es además lo que hace seguras las comprobaciones: sin
-- tipo, un payload que no sea tabla revienta al indexarlo. La lista va ordenada para
-- que un nodo con palabras clave de dos tipos —que es un schema mal escrito— deduzca
-- siempre lo mismo.
local INFERRED_TYPE = {
    { "properties", "object" }, { "required", "object" }, { "additionalProperties", "object" },
    { "items", "array" }, { "minItems", "array" }, { "maxItems", "array" }, { "uniqueItems", "array" },
    { "minLength", "string" }, { "maxLength", "string" }, { "pattern", "string" }, { "format", "string" },
    { "minimum", "number" }, { "maximum", "number" },
    { "exclusiveMinimum", "number" }, { "exclusiveMaximum", "number" }, { "multipleOf", "number" }
}

local function node_type(node)
    if node.type then return node.type end

    for i = 1, #INFERRED_TYPE do
        local keyword = INFERRED_TYPE[i]
        if node[keyword[1]] ~= nil then return keyword[2] end
    end

    return nil
end

local function type_test(expected)
    if expected == "object" then
        return function(value) return type(value) == "table" end
    end

    if expected == "array" then
        return function(value)
            if type(value) ~= "table" then return false end

            -- Estricta: una tabla con claves de texto no es un array.
            local count = 0
            for _ in pairs(value) do count = count + 1 end

            return count == #value
        end
    end

    return function(value) return type(value) == expected end
end
-- Una comprobación: dice si el valor pasa y, si le dan `errors`, deja ahí el mensaje.
-- El mensaje se formatea al montar el checker, no en cada fallo.
local function check_of(test, message)
    return function(value, errors)
        if test(value) then return true end
        if errors then errors[#errors + 1] = message end
        return false
    end
end

-- Sin `errors` corta en el primer fallo y no toca ni una cadena; con `errors` los
-- junta todos.
local function run(checks, value, errors, seen)
    local ok = true

    for i = 1, #checks do
        if not checks[i](value, errors, seen) then
            if not errors then return false end
            ok = false
        end
    end

    return ok
end

--- Monta el checker de un nodo del schema: `fn(value, errors, seen) -> boolean`.
--- `cache` reparte un checker por nodo, así un schema recursivo (un nodo que se
--- refiere a sí mismo) no monta un árbol infinito.
local function build(node, cache)
    cache = cache or {}

    local cached = cache[node]
    if cached then return cached end

    local checker

    -- Trampolín: mientras se monta este nodo, quien lo referencie se lleva un reenvío
    -- al checker que todavía no existe.
    cache[node] = function(value, errors, seen) return checker(value, errors, seen) end

    local checks = {}

    if node.minLength then
        local min = node.minLength
        checks[#checks + 1] = check_of(function(value) return str_len(value) >= min end,
            ("must be at least %d characters"):format(min))
    end
    if node.maxLength then
        local max = node.maxLength
        checks[#checks + 1] = check_of(function(value) return str_len(value) <= max end,
            ("must be at most %d characters"):format(max))
    end

    if node.pattern then
        local pattern = node.pattern
        checks[#checks + 1] = check_of(function(value) return value:match(pattern) ~= nil end,
            "does not match the required pattern")
    end

    local format = node.format and FORMATS[node.format]
    if format then
        checks[#checks + 1] = check_of(format, ("is not a valid '%s'"):format(node.format))
    end

    if node.minimum then
        local min = node.minimum
        checks[#checks + 1] = check_of(function(value) return value >= min end,
            ("must be greater than or equal to %s"):format(min))
    end

    if node.maximum then
        local max = node.maximum
        checks[#checks + 1] = check_of(function(value) return value <= max end,
            ("must be less than or equal to %s"):format(max))
    end

    if node.exclusiveMinimum then
        local min = node.exclusiveMinimum
        checks[#checks + 1] = check_of(function(value) return value > min end,
            ("must be greater than %s"):format(min))
    end

    if node.exclusiveMaximum then
        local max = node.exclusiveMaximum
        checks[#checks + 1] = check_of(function(value) return value < max end,
            ("must be less than %s"):format(max))
    end

    if node.enum then
        local allowed = {}
        for i = 1, #node.enum do allowed[node.enum[i]] = true end

        checks[#checks + 1] = check_of(function(value) return allowed[value] == true end,
            "is not an allowed value")
    end
    if node.multipleOf then
        local step = node.multipleOf
        checks[#checks + 1] = check_of(function(value) return value % step == 0 end,
            ("must be a multiple of %s"):format(step))
    end

    if node.minItems then
        local min = node.minItems
        checks[#checks + 1] = check_of(function(value) return #value >= min end,
            ("must have at least %d items"):format(min))
    end

    if node.maxItems then
        local max = node.maxItems
        checks[#checks + 1] = check_of(function(value) return #value <= max end,
            ("must have at most %d items"):format(max))
    end

    if node.uniqueItems then
        checks[#checks + 1] = check_of(function(value)
            local items = {}

            for i = 1, #value do
                -- ponytail: `tostring` de una tabla es su dirección, así que dos
                -- elementos iguales por contenido no cuentan como duplicado.
                local key = tostring(value[i])
                if items[key] then return false end
                items[key] = true
            end

            return true
        end, "has duplicate items")
    end

    if node.items then
        local item = build(node.items, cache)

        checks[#checks + 1] = function(value, errors, seen)
            local ok = true

            for i = 1, #value do
                if not item(value[i], nil, seen) then
                    if not errors then return false end
                    ok = false

                    -- Solo el elemento que falla paga la segunda pasada, la del mensaje.
                    local sub = {}
                    item(value[i], sub, seen)
                    for j = 1, #sub do errors[#errors + 1] = ("item [%d] %s"):format(i, sub[j]) end
                end
            end

            return ok
        end
    end
    if node.required then
        for i = 1, #node.required do
            local key = node.required[i]
            checks[#checks + 1] = check_of(function(value) return value[key] ~= nil end,
                ("property '%s' is required"):format(key))
        end
    end

    if node.properties then
        local properties = {}
        for key, sub_schema in pairs(node.properties) do properties[key] = build(sub_schema, cache) end

        checks[#checks + 1] = function(value, errors, seen)
            local ok = true

            for key, property_checker in pairs(properties) do
                local property = value[key]

                if property ~= nil and not property_checker(property, nil, seen) then
                    if not errors then return false end
                    ok = false

                    local sub = {}
                    property_checker(property, sub, seen)
                    for j = 1, #sub do errors[#errors + 1] = ("'%s' %s"):format(key, sub[j]) end
                end
            end

            return ok
        end
    end

    if node.additionalProperties == false then
        local allowed = {}
        if node.properties then
            for key in pairs(node.properties) do allowed[key] = true end
        end

        checks[#checks + 1] = function(value, errors)
            local ok = true

            for key in pairs(value) do
                if not allowed[key] then
                    if not errors then return false end
                    ok = false
                    errors[#errors + 1] = ("unrecognized property: '%s'"):format(key)
                end
            end

            return ok
        end
    end
    local expected = node_type(node)
    local test_type = expected and type_test(expected)
    local type_message = expected and ("must be type '%s'"):format(expected)
    local nests = node.properties ~= nil or node.items ~= nil

    checker = function(value, errors, seen)
        -- Si no es del tipo no se sigue: el resto de restricciones no aplican y varias
        -- reventarían (indexar un número, medir un booleano).
        if test_type and not test_type(value) then
            if errors then errors[#errors + 1] = type_message end
            return false
        end

        if not nests then return run(checks, value, errors, seen) end

        -- Dato cíclico (4.5 los acepta): si esta tabla ya está en la rama que se está
        -- recorriendo, no se vuelve a entrar. `seen` se crea en el nodo más externo que
        -- anida, así un schema plano no paga ninguna tabla.
        seen = seen or {}
        if seen[value] then return true end

        seen[value] = true
        local ok = run(checks, value, errors, seen)
        seen[value] = nil

        return ok
    end

    cache[node] = checker
    return checker
end

local Validator = {}
Validator.__index = Validator

-- El árbol de comprobaciones se monta la primera vez que se usa el validador y se
-- queda en la instancia, igual que `import "zod/compile"` compila en el primer parse.
-- `:compile()` solo adelanta ese trabajo.
local function compiled(validator)
    local built = validator._checker

    if not built then
        built = build(validator.schema)
        validator._checker = built
    end

    return built
end
--- Los métodos van en una metatabla compartida, no colgados de la instancia: eso es
--- lo que en 4.5 le quitó a zod un orden de magnitud de memoria por schema, y aquí un
--- validador pasa de doce closures a una tabla con el schema dentro.
function kec.zod:new(schema)
    return setmetatable({ schema = schema }, Validator)
end

--- Deja montado el camino rápido y devuelve EL MISMO validador: un schema compilado
--- se usa exactamente igual que uno sin compilar.
function Validator:compile()
    compiled(self)
    return self
end

--- `z.validate()`: ¿vale el dato? Sin mensajes y cortando en el primer fallo.
---@return boolean
function Validator:is_valid(data)
    return compiled(self)(data)
end

---@return boolean ok, string errors
function Validator:validate(data)
    local checker = compiled(self)

    -- Primero el camino rápido: si el dato vale, no se formatea ni un mensaje. Solo
    -- cuando falla se recorre otra vez para juntarlos, que es como zod cae del
    -- fast-path compilado al parser normal, el único que sabe dar el detalle.
    if checker(data) then
        self.errors = nil
        return true, ""
    end

    local errors = {}
    checker(data, errors)
    self.errors = errors

    return false, table.concat(errors, ", ")
end

function Validator:check(data)
    return self:validate(data)
end

function Validator:get_error_string()
    return self.errors and table.concat(self.errors, ", ") or ""
end

function Validator:clear_errors()
    self.errors = nil
end

function Validator:copy()
    return kec.zod:new(self.schema)
end
--- `z.deepPartial()`: el mismo schema sin `required` en ningún nivel, para validar un
--- $set parcial contra el schema del documento sin exigir el documento entero.
---@return table schema
function kec.zod:deepPartial(schema)
    local partial = {}

    for key, value in pairs(schema) do
        if key ~= "required" then partial[key] = value end
    end

    if schema.properties then
        local properties = {}

        for key, sub_schema in pairs(schema.properties) do
            properties[key] = type(sub_schema) == "table" and self:deepPartial(sub_schema) or sub_schema
        end

        partial.properties = properties
    end

    if type(schema.items) == "table" then
        partial.items = self:deepPartial(schema.items)
    end

    return partial
end

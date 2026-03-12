kec.zod = {}

function kec.zod:new(schema)
    local validator = {
        schema = schema,
        errors = {}
    }

    function validator:compile()
        local _schema = self.schema
        local function build_checker(node)
            local checks = {}

            if node.type == "string" then
                table.insert(checks, function(v) return type(v) == "string" end)
                if node.minLength then local m=node.minLength; table.insert(checks, function(v) return #v >= m end) end
                if node.maxLength then local m=node.maxLength; table.insert(checks, function(v) return #v <= m end) end
                if node.pattern then local p=node.pattern; table.insert(checks, function(v) return string.match(v, p) ~= nil end) end

            elseif node.type == "number" then
                table.insert(checks, function(v) return type(v) == "number" end)
                if node.minimum then local m=node.minimum; table.insert(checks, function(v) return v >= m end) end
                if node.maximum then local m=node.maximum; table.insert(checks, function(v) return v <= m end) end

            elseif node.type == "boolean" then
                table.insert(checks, function(v) return type(v) == "boolean" end)

            elseif node.type == "array" then
                table.insert(checks, function(v) return type(v) == "table" end)
                if node.items then
                    local item_check = build_checker(node.items)
                    table.insert(checks, function(v)
                        for i = 1, #v do
                            if not item_check(v[i]) then return false end
                        end
                        return true
                    end)
                end

            elseif node.type == "object" then
                table.insert(checks, function(v) return type(v) == "table" end)
                
                if node.additionalProperties == false then
                    local allowed = {}
                    if node.properties then
                        for k, _ in pairs(node.properties) do allowed[k] = true end
                    end
                    table.insert(checks, function(v)
                        for k, _ in pairs(v) do
                            if not allowed[k] then return false end
                        end
                        return true
                    end)
                end

                if node.required then
                    for _, key in ipairs(node.required) do
                        table.insert(checks, function(v) return v[key] ~= nil end)
                    end
                end
                
                if node.properties then
                    local prop_checks = {}
                    for key, sub_schema in pairs(node.properties) do
                        prop_checks[key] = build_checker(sub_schema)
                    end
                    table.insert(checks, function(v)
                        for key, checker in pairs(prop_checks) do
                            if v[key] ~= nil and not checker(v[key]) then return false end
                        end
                        return true
                    end)
                end
            end

            return function(data)
                for i = 1, #checks do
                    if not checks[i](data) then return false end
                end
                return true
            end
        end

        local root_checker = build_checker(_schema)
        return {
            check = function(_, data)
                return root_checker(data)
            end
        }
    end

    function validator:_validate_type(value, field_def)
        local actual_type = type(value)
        local expected_type = field_def.type
        
        if expected_type == "array" then
            local is_array = actual_type == "table"
            if is_array then
                -- Comprobación estricta para evitar tablas mixtas
                local count = 0
                for _ in pairs(value) do count = count + 1 end
                is_array = (count == #value)
            end
            return is_array, expected_type
        elseif expected_type == "object" then
            return actual_type == "table", expected_type
        else
            return actual_type == expected_type, expected_type
        end
    end
    
    function validator:_validate_string(value, field_def)
        local errors = {}
        if field_def.minLength and #value < field_def.minLength then table.insert(errors, string.format("debe tener al menos %d caracteres", field_def.minLength)) end
        if field_def.maxLength and #value > field_def.maxLength then table.insert(errors, string.format("no puede tener más de %d caracteres", field_def.maxLength)) end
        if field_def.pattern and not value:match(field_def.pattern) then table.insert(errors, "no cumple con el patrón requerido") end
        if field_def.enum and not self:_in_table(value, field_def.enum) then table.insert(errors, "no es un valor permitido") end
        return errors
    end
    
    function validator:_validate_number(value, field_def)
        local errors = {}
        if field_def.minimum and value < field_def.minimum then table.insert(errors, string.format("debe ser mayor o igual a %s", field_def.minimum)) end
        if field_def.maximum and value > field_def.maximum then table.insert(errors, string.format("debe ser menor o igual a %s", field_def.maximum)) end
        if field_def.exclusiveMinimum and value <= field_def.exclusiveMinimum then table.insert(errors, string.format("debe ser mayor que %s", field_def.exclusiveMinimum)) end
        if field_def.exclusiveMaximum and value >= field_def.exclusiveMaximum then table.insert(errors, string.format("debe ser menor que %s", field_def.exclusiveMaximum)) end
        if field_def.enum and not self:_in_table(value, field_def.enum) then table.insert(errors, "no es un valor permitido") end
        if field_def.multipleOf and value % field_def.multipleOf ~= 0 then table.insert(errors, string.format("debe ser múltiplo de %s", field_def.multipleOf)) end
        return errors
    end
    
    function validator:_validate_boolean(value, field_def) return {} end
    
    function validator:_validate_array(value, field_def)
        local errors = {}
        if field_def.minItems and #value < field_def.minItems then table.insert(errors, string.format("debe tener al menos %d elementos", field_def.minItems)) end
        if field_def.maxItems and #value > field_def.maxItems then table.insert(errors, string.format("no puede tener más de %d elementos", field_def.maxItems)) end
        if field_def.uniqueItems then
            local seen = {}
            for _, item in ipairs(value) do
                local key = tostring(item)
                if seen[key] then table.insert(errors, "tiene elementos duplicados"); break end
                seen[key] = true
            end
        end
        if field_def.items then
            for i, item in ipairs(value) do
                local item_errors = self:_validate_field(item, field_def.items, string.format("[%d]", i))
                for _, err in ipairs(item_errors) do table.insert(errors, string.format("elemento [%d] %s", i, err)) end
            end
        end
        return errors
    end
    
    function validator:_validate_object(value, field_def)
        local errors = {}
        
        -- 1. Validar requeridos (Incluso si no están en properties)
        if field_def.required then
            for _, req_prop in ipairs(field_def.required) do
                if value[req_prop] == nil then
                    table.insert(errors, string.format("propiedad '%s' es requerida", req_prop))
                end
            end
        end
        
        -- 2. Validar sub-propiedades
        if field_def.properties then
            for prop_name, prop_schema in pairs(field_def.properties) do
                local prop_value = value[prop_name]
                if prop_value ~= nil then
                    local prop_errors = self:_validate_field(prop_value, prop_schema, prop_name)
                    for _, err in ipairs(prop_errors) do
                        table.insert(errors, string.format("'%s' %s", prop_name, err))
                    end
                end
            end
        end

        -- 3. Validar additionalProperties
        if field_def.additionalProperties == false then
            for key, _ in pairs(value) do
                if not field_def.properties or not field_def.properties[key] then
                    table.insert(errors, string.format("propiedad no permitida: '%s'", key))
                end
            end
        end

        return errors
    end

    function validator:_in_table(value, table)
        for _, v in ipairs(table) do
            if v == value then return true end
        end
        return false
    end

    function validator:_validate_field(value, field_def, field_name)
        local errors = {}
        
        if field_def.type == nil then
            return errors -- Early exit si el esquema no requiere un tipo específico
        end

        local is_valid_type, expected_type = self:_validate_type(value, field_def)
        if not is_valid_type then
            table.insert(errors, string.format("debe ser tipo '%s'", expected_type))
            return errors
        end
        
        local type_validators = {
            string = self._validate_string,
            number = self._validate_number,
            boolean = self._validate_boolean,
            array = self._validate_array,
            object = self._validate_object
        }
        
        local validator_func = type_validators[field_def.type]
        if validator_func then
            local type_errors = validator_func(self, value, field_def)
            for _, err in ipairs(type_errors) do table.insert(errors, err) end
        end
        return errors
    end
    
    function validator:validate(data)
        -- Delegamos todo a _validate_field. Esto resuelve el problema de los schemas raíz
        -- que son de tipo array o tipos primitivos, y elimina código duplicado.
        self.errors = self:_validate_field(data, self.schema, "root")
        return #self.errors == 0, table.concat(self.errors, ", ")
    end
    
    function validator:check(data)
        local ok, errors = self:validate(data)
        return ok, errors
    end
    
    function validator:get_error_string() return table.concat(self.errors, ", ") end
    function validator:clear_errors() self.errors = {} end
    function validator:copy() return kec.zod:new(self.schema) end
    
    return validator
end
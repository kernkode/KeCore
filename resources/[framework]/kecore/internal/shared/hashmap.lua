kec.map = {}

-- Función que crea y devuelve un nuevo HashMap
function kec.map:new()
    local data = {}
    local quantity = 0

    -- == INTERFAZ PÚBLICA ==
    local instance = {}

    -- Insertar o actualizar
    instance.put = function(clave, valor)
        if clave == nil then return end -- Protección contra claves nil

        -- Si el valor es nil, es una eliminación
        if valor == nil then
            instance.remove(clave)
            return
        end

        -- Si la clave es nueva, aumentamos el contador
        if data[clave] == nil then
            quantity = quantity + 1
        end

        data[clave] = valor
    end

    -- Obtener valor
    instance.get = function(clave)
        return data[clave]
    end

    -- Eliminar valor
    instance.remove = function(clave)
        if data[clave] ~= nil then
            data[clave] = nil
            quantity = quantity - 1
            return true
        end
        return false
    end

    -- Verificar existencia
    instance.contains = function(clave)
        return data[clave] ~= nil
    end

    -- Obtener tamaño
    instance.size = function()
        return quantity
    end

    -- Iterador personalizado
    -- Devuelve una función iteradora para usar en bucles for
    instance.iterator = function()
        return pairs(data)
    end

    -- Vaciar el mapa
    instance.clear = function()
        data = {}
        quantity = 0
    end

    return instance
end
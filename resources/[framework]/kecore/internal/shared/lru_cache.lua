-- lru_cache.lua
kec.lru_cache = {}

function kec.lru_cache:new(max_size)
    local data = {
        max_size = max_size or 100,
        cache_map = {},  -- Mapa clave -> nodo
        head = nil,      -- Nodo más reciente (MRU)
        tail = nil,      -- Nodo menos reciente (LRU)
        size = 0
    }
    
    -- Función interna para crear un nodo con soporte de tiempo
    -- ttl: tiempo de vida en milisegundos
    local function create_node(key, value, ttl)
        local expire_at = nil
        if ttl and ttl > 0 then
            expire_at = GetGameTimer() + ttl
        end

        return {
            key = key,
            value = value,
            expire_at = expire_at,
            prev = nil,
            next = nil
        }
    end
    
    -- Mover un nodo al frente (indica que fue usado recientemente)
    local function move_to_front(node)
        if data.head == node then return end
        
        -- Desconectar de la posición actual
        if node.prev then node.prev.next = node.next end
        if node.next then node.next.prev = node.prev end
        
        if data.tail == node then
            data.tail = node.prev
        end
        
        -- Insertar al inicio
        node.prev = nil
        node.next = data.head
        
        if data.head then
            data.head.prev = node
        end
        
        data.head = node
        
        if not data.tail then
            data.tail = node
        end
    end

    --- Borra los elementos que ya han expirado para liberar memoria
    --- @return number total_borrados
    function data:purge_expired()
        local count = 0
        local current = data.tail -- Empezamos por el más viejo (más probable de haber expirado)
        local now = GetGameTimer()
        
        while current do
            local prev_node = current.prev -- Guardamos referencia antes de borrar
            if current.expire_at and now > current.expire_at then
                self:remove(current.key)
                count = count + 1
            end
            current = prev_node
        end
        return count
    end

    --- Obtener un valor del cache
    function data:get(key)
        local node = data.cache_map[key]
        if not node then return nil end

        -- Verificar si expiró
        if node.expire_at and GetGameTimer() > node.expire_at then
            self:remove(key)
            return nil
        end
        
        move_to_front(node)
        return node.value
    end
    
    --- Insertar o actualizar un valor
    --- @param ttl number|nil Opcional: tiempo de vida en milisegundos
    function data:put(key, value, ttl)
        local node = data.cache_map[key]
        
        if node then
            -- Actualizar existente
            node.value = value
            if ttl then
                node.expire_at = GetGameTimer() + ttl
            else
                node.expire_at = nil
            end
            move_to_front(node)
        else
            -- Si está lleno, primero intentamos borrar expirados
            if data.size >= data.max_size then
                self:purge_expired()
            end

            -- Si sigue lleno tras la purga, borramos el LRU (el tail)
            if data.size >= data.max_size then
                if data.tail then
                    self:remove(data.tail.key)
                end
            end
            
            node = create_node(key, value, ttl)
            data.cache_map[key] = node
            
            if data.head then
                node.next = data.head
                data.head.prev = node
                data.head = node
            else
                data.head = node
                data.tail = node
            end
            
            data.size = data.size + 1
        end
    end
    
    --- Remover un elemento específico
    function data:remove(key)
        local node = data.cache_map[key]
        if not node then return false end
        
        if node.prev then node.prev.next = node.next end
        if node.next then node.next.prev = node.prev end
        
        if data.head == node then data.head = node.next end
        if data.tail == node then data.tail = node.prev end
        
        data.cache_map[key] = nil
        data.size = data.size - 1
        return true
    end
    
    function data:clear()
        data.cache_map = {}
        data.head = nil
        data.tail = nil
        data.size = 0
    end
    
    function data:get_size() return data.size end
    
    function data:has(key)
        local node = data.cache_map[key]
        if not node then return false end
        -- Si existe pero expiró, lo tratamos como si no existiera
        if node.expire_at and GetGameTimer() > node.expire_at then
            self:remove(key)
            return false
        end
        return true
    end
    
    function data:keys()
        local keys = {}
        local current = data.head
        while current do
            table.insert(keys, current.key)
            current = current.next
        end
        return keys
    end
    
    return data
end
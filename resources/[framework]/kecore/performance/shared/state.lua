-- AUTO-GENERATED from internal/shared/state.lua by scripts/builder/gen-performance.ts — DO NOT EDIT
-- Edit the internal/ source and run `bun run gen:performance` to regenerate.

-- ------------------------------------------------------------
-- Estado compartido ENTRE RECURSOS.
--
-- Cada recurso guarda su propia copia de los valores, así que LEER es un acceso a tabla: sin
-- salto entre runtimes ni serialización. Las ESCRITURAS se replican con un evento del lado, de
-- modo que todos convergen y los onChange saltan en todos. Ahí está la ventaja sobre exports
-- para compartir datos: con exports pagas una llamada entre runtimes en cada lectura; aquí solo
-- al escribir.
--
-- OJO: el ámbito es POR LADO. El estado del server y el del cliente son dos espacios distintos;
-- para cruzarlos siguen estando los eventos y kec.rpc.
--
-- ------------------------------------------------------------
-- Este archivo es un CHUNK, no un script del fxmanifest: devuelve una FÁBRICA y quien la llama
-- se queda con su propia tabla de valores. Se compila dos veces —una en kecore
-- (internal/shared/core.lua) y otra por cada consumidor (@kecore/init.lua)—, y por eso el código
-- vive aquí una sola vez: era el mismo `applyState` + `stateObj` copiado en los dos ficheros, y
-- ya habían empezado a divergir (el aviso del onChange roto estaba solo en la copia de kecore).
--
-- Y no puede ir por la inyección normal de `performance/**`: `injectModule` copia el módulo clave
-- por clave con pairs, y esto es una tabla CON metatabla —el `kec.state.x = 1` de las llamadas—
-- que la copia se lleva por delante.
-- ------------------------------------------------------------

local STATE_SYNC = "kec:state:sync"

--- @param initial table|nil Foto de la que parte el estado (el snapshot de kecore, o nada)
--- @return table state
return function(initial)
    local stateValues = initial or {}
    local stateListeners = {}
    local thisResource = GetCurrentResourceName()

    --- Aplica un valor al estado local y avisa a los listeners. Devuelve si cambió.
    local function applyState(key, value)
        local oldValue = stateValues[key]
        if oldValue == value then return false end
        stateValues[key] = value

        local listeners = stateListeners[key]
        if listeners then
            for i = #listeners, 1, -1 do
                local ok, err = pcall(listeners[i], value, oldValue)
                -- Siempre en consola, mismo criterio que los handlers de eventos: un onChange
                -- que revienta en silencio es una pantalla de carga sin explicación.
                if not ok then
                    print(("^1[state] ERROR en el onChange de '%s': %s^7")
                        :format(tostring(key), tostring(err)))
                end
            end
        end

        return true
    end

    local state = setmetatable({}, {
        __index = function(_, key)
            return stateValues[key]
        end,
        __newindex = function(_, key, value)
            if applyState(key, value) then
                TriggerEvent(STATE_SYNC, key, value, thisResource)
            end
        end
    })

    -- Los métodos van con rawset y no como `function state:get(...)`: escribirlos normal pasaba
    -- por el __newindex de arriba, o sea que `get`, `set` y `onChange` se guardaban como si
    -- fueran VALORES del estado y se replicaban por el evento de sync (tres funcref a todos los
    -- recursos en cada arranque). Como claves de verdad, además, el __index no se consulta para
    -- ellas: llamar a `state:get` no paga metatabla.
    rawset(state, "get", function(_, key)
        return stateValues[key]
    end)

    rawset(state, "set", function(_, key, value)
        state[key] = value
    end)

    rawset(state, "onChange", function(_, key, callback)
        if type(callback) ~= "function" then return function() end end
        stateListeners[key] = stateListeners[key] or {}
        table.insert(stateListeners[key], callback)

        return function()
            local listeners = stateListeners[key]
            if not listeners then return end

            for i, cb in ipairs(listeners) do
                if cb == callback then
                    table.remove(listeners, i)
                    break
                end
            end
        end
    end)

    --- La tabla de valores tal cual, para que kecore la pueda publicar por export y un recurso
    --- que arranque tarde no empiece a ciegas.
    rawset(state, "snapshot", function()
        return stateValues
    end)

    -- Escritura de otro recurso: solo se aplica local (quien la originó ya la aplicó, y
    -- re-emitir aquí sería un bucle).
    AddEventHandler(STATE_SYNC, function(key, value, from)
        if from ~= thisResource then applyState(key, value) end
    end)

    return state
end

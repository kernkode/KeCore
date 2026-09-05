-- AUTO-GENERATED from internal/shared/timers.lua by scripts/builder/gen-performance.ts — DO NOT EDIT
-- Edit the internal/ source and run `bun run gen:performance` to regenerate.

local timers = {}

---Active timers
local actives = {}

---Counter for unique IDs
local nextId = 1

local function handle_timer(id)
    local instance = {
        id = id
    }

    function instance:cancel()
        timers:clearTimer(self.id)
    end

    function instance:isRunning()
        return timers:isRunning(self.id)
    end

    return instance
end

---Clears a timer by its ID
---@param id number
---@return boolean success
function timers:clearTimer(id)
    -- Un id que ya no está corriendo NO es un error: cancelar un tick que se apagó solo (o
    -- cancelarlo dos veces) es normal, y avisar de eso llenaba la consola. Solo se avisa de un
    -- id ausente, que sí es un fallo de quien llama.
    if id == nil then
        warn("Warning: clearTimer called without an ID")
        return false
    end

    if actives[id] == nil then return false end

    actives[id] = nil
    return true
end

---Creates a timer that runs every tick (every frame)
---@param fn fun(): boolean|nil Function to execute. Return false to stop the timer.
---@param time number|nil Milisegundos entre pasadas. 0 (o nada) = cada frame; con un valor es un
---                       bucle auto-frenado, así que no hace falta comparar relojes a mano dentro.
---@return table instance
function timers:everyTick(fn, time)
    local id = nextId
    nextId = nextId + 1
    actives[id] = true

    time = time or 0

    Citizen.CreateThread(function()
        while actives[id] do
            local shouldContinue = true
            local success, result = pcall(fn)

            if not success then
                print("Error en el tick:", result)
                shouldContinue = false
            elseif result ~= nil then
                shouldContinue = result ~= false
            end

            if not shouldContinue then
                break
            end

            Wait(time)
        end
        actives[id] = nil
    end)
    return handle_timer(id)
end

---Checks if a timer is currently running
---@param id number|nil
---@return boolean
function timers:isRunning(id)
    return actives[id] ~= nil
end

---Creates a timer that runs at specified intervals
---@param fn fun(id) Function to execute
---@param time number Interval in milliseconds
---@return table instance
function timers:setInterval(fn, time)
    local id = nextId
    nextId = nextId + 1
    actives[id] = true

    Citizen.CreateThread(function()
        while actives[id] do
            Wait(time)

            if actives[id] == nil then break end
            -- pcall(fn, id) y no pcall(function() fn(id) end): la closure se alojaba en CADA
            -- pasada del interval.
            local success, result = pcall(fn, id)

            if not success then
                print("Error en el intervalo:", result)
                break
            end
        end
        actives[id] = nil
    end)
    return handle_timer(id)
end

---Creates a timer that runs once after a timeout
---@param fn fun() Function to execute
---@param timeout number Timeout in milliseconds
---@return table instance
function timers:setTimeout(fn, timeout)
    local id = nextId
    nextId = nextId + 1
    actives[id] = true

    CreateThread(function()
        Wait(timeout)
        if actives[id] then
            local success, result = pcall(fn)
            if not success then
                print("Error en el timeout:", result)
            end
        end
        actives[id] = nil
    end)
    return handle_timer(id)
end

---
-- Función auxiliar para parsear el string de tiempo.
-- Devuelve el tiempo total en segundos.
---
local function parseTime(timeString)
    local totalSeconds = 0

    for part in string.gmatch(timeString, "([^:]+)") do
        local num, unit = string.match(part, "(%d+)(%a+)")

        if num and unit then
            num = tonumber(num)
            if unit == "s" then
                totalSeconds = totalSeconds + num
            elseif unit == "m" then
                totalSeconds = totalSeconds + (num * 60)
            elseif unit == "h" then
                totalSeconds = totalSeconds + (num * 3600)
            elseif unit == "d" then
                totalSeconds = totalSeconds + (num * 86400)
            else
                print("Advertencia: Unidad desconocida '" .. unit .. "'")
            end
        end
    end
    return totalSeconds
end

---
-- Función auxiliar para formatear los segundos a formato MM:SS
---
local function formatTime(totalSeconds)
    if totalSeconds <= 0 then return "0:00" end

    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60

    -- Formatear para que siempre muestre 2 dígitos en los segundos
    return string.format("%d:%02d", minutes, seconds)
end

---
-- FUNCIÓN DE COOLDOWN PARA FIVEM (USANDO kec)
-- Inicia una cuenta regresiva usando setInterval.
-- @param timeString string Tiempo en formato como "10s", "1m:30s", "1h:30m:10s"
-- @return table|nil Instancia del timer, o nil si el tiempo es inválido
---
function timers:countDown(key, timeString)
    local totalSeconds = parseTime(timeString)

    if totalSeconds <= 0 then
        print("[Cooldown] Error: Tiempo inválido '" .. timeString .. "'")
        return nil
    end

    local currentSeconds = totalSeconds

    -- Iniciar el timer usando timers:setInterval
    local timer = timers:setInterval(function(id)
        if currentSeconds <= 1 then
            timers:clearTimer(id)
            kec:emit("onCountdownFinish", key)
            return
        end

        currentSeconds = currentSeconds - 1
        kec:emit("onCountdownUpdate", key, formatTime(currentSeconds))
    end, 1000)

    return timer
end

return timers

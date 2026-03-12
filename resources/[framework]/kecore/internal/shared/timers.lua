---Active timers
local actives = {}

---Timers cache
local cache = {}

---Counter for unique IDs
local nextId = 1

local function handle_timer(id)
    local instance = {
        id = id
    }

    function instance:cancel()
        kec:clearTimer(self.id)
    end

    function instance:isRunning()
        return kec:isRunning(self.id)
    end

    return instance
end

---Clears a timer by its ID
---@param id number
---@return boolean success
function kec:clearTimer(id)
    if id and actives[id] ~= nil then
        actives[id] = nil
        cache[id] = nil
        return true
    else
        warn("Warning: clearTimer called with invalid ID: " .. tostring(id))
        return false
    end
end

---Creates a timer that runs every tick (every frame)
---@param fn fun(): boolean|nil Function to execute. Return false to stop the timer.
---@return table instance
function kec:everyTick(fn, time)
    local id = nextId
    nextId = nextId + 1
    actives[id] = true

    time = time or 0

    cache[id] = {
        callingResource = GetInvokingResource()
    }

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
        cache[id] = nil
    end)
    return handle_timer(id)
end

---Checks if a timer is currently running
---@param id number|nil
---@return boolean
function kec:isRunning(id)
    return actives[id] ~= nil
end

---Creates a timer that runs at specified intervals
---@param fn fun(id) Function to execute
---@param time number Interval in milliseconds
---@return table instance
function kec:setInterval(fn, time)
    local id = nextId
    nextId = nextId + 1
    actives[id] = true
    cache[id] = {
        callingResource = GetInvokingResource()
    }

    Citizen.CreateThread(function()
        while actives[id] do
            if not actives[id] then break end

            Wait(time)

            if actives[id] == nil then break end
            local success, result = pcall(function()
                fn(id)
            end)

            if not success then
                print("Error en el intervalo:", result)
                break
            end
        end
        actives[id] = nil
        cache[id] = nil
    end)
    return handle_timer(id)
end

---Creates a timer that runs once after a timeout
---@param fn fun() Function to execute
---@param timeout number Timeout in milliseconds
---@return table instance
function kec:setTimeout(fn, timeout)
    local id = nextId
    nextId = nextId + 1
    actives[id] = true

    cache[id] = {
        callingResource = GetInvokingResource()
    }

    CreateThread(function()
        Wait(timeout)
        if actives[id] then
            local success, result = pcall(fn)
            if not success then
                print("Error en el timeout:", result)
            end
        end
        actives[id] = nil
        cache[id] = nil
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
-- @return number|nil ID del timer, o nil si el tiempo es inválido
---
function kec:countDown(key, timeString)
    local totalSeconds = parseTime(timeString)

    if totalSeconds <= 0 then
        print("[Cooldown] Error: Tiempo inválido '" .. timeString .. "'")
        return nil
    end

    local currentSeconds = totalSeconds

    -- Iniciar el timer usando kec:setInterval
    local timerId = kec:setInterval(function(id)
        if currentSeconds <= 1 then
            kec:clearTimer(id)
            print("[Cooldown] ¡Tiempo terminado! ID: " .. key)
            kec:emit("onCountdownFinish", key)
            return
        end

        currentSeconds = currentSeconds - 1
        local formattedTime = formatTime(currentSeconds)
        print("[Cooldown] Tiempo restante: " .. formattedTime)
        kec:emit("onCountdownUpdate", key, formattedTime)
    end, 1000)

    print("[Cooldown] Timer de cuenta regresiva iniciado. ID: " .. timerId)
    return timerId
end

AddEventHandler("onResourceStop", function(resourceName)
    for id, data in pairs(cache) do
        if data and data.callingResource == resourceName then
            kec:clearTimer(id)
        end
    end
end)
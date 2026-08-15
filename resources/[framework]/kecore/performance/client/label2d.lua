-- AUTO-GENERATED from internal/client/label2d.lua by scripts/builder/gen-performance.ts — DO NOT EDIT
-- Edit the internal/ source and run `bun run gen:performance` to regenerate.

-- ============================================================
-- label2d — Módulo de textos temporales en pantalla 2D (toasts)
-- Uso:
--   label2d:showText("Texto", { r=60, g=255, b=60 }, 2000)
--   label2d:success("Motor encendido", 2000)
--   label2d:error("Motor apagado", 2000)
--   label2d:info("Información", 2000)
-- ============================================================

local label2d = {}

local activeTexts = {}
local textIdCounter = 0

--- Muestra un texto temporal en pantalla
---@param text string Texto a mostrar
---@param options table|nil Tabla de opciones { color = {r,g,b}, duration = ms, position = {x,y}, font = num, scale = num }
---@return number id ID del texto para poder cancelarlo con label2d:hide(id)
function label2d:showText(text, options)
    textIdCounter = textIdCounter + 1
    local id = textIdCounter
    
    options = options or {}

    -- Limpiamos cualquier otro label 2D que esté activo para que solo haya uno a la vez
    self:clear()

    activeTexts[id] = {
        text = text,
        color = options.color or { r = 255, g = 255, b = 255 },
        expire = GetGameTimer() + (options.duration or 2000),
        -- y = 0.83: bajo, pero no tanto como 0.90 — la hotbar del inventario va centrada
        -- abajo (bottom 26px + 52px de slot, y hasta 96px el aviso del propio inventario),
        -- así que a 0.90 el toast caía justo detrás: a 720p entero, a 1080p la mitad de
        -- abajo. Ningún sitio que llame a label2d pasa `position`, así que la altura de
        -- TODOS los avisos (motor, compuerta, seguro, inventario...) la manda esta línea.
        position = options.position or { x = 0.5, y = 0.83 },
        font = options.font or 4,
        scale = options.scale or 0.45
    }

    return id
end

--- Atajos de color
function label2d:success(text, duration, options)
    options = options or {}
    -- Verde menta claro en vez del verde puro (60,255,60): sobre el día de GTA y con el
    -- borde negro del DrawText, el verde saturado se leía apagado. Subir el rojo y el azul
    -- lo aclara sin perder el "esto ha ido bien".
    options.color = options.color or { r = 130, g = 255, b = 165 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

function label2d:error(text, duration, options)
    options = options or {}
    options.color = options.color or { r = 255, g = 60, b = 60 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

function label2d:info(text, duration, options)
    options = options or {}
    options.color = options.color or { r = 60, g = 160, b = 255 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

function label2d:warning(text, duration, options)
    options = options or {}
    options.color = options.color or { r = 255, g = 200, b = 60 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

--- Ocultar un texto por su ID antes de que expire
---@param id number
function label2d:hide(id)
    activeTexts[id] = nil
end

--- Limpiar todos los textos activos
function label2d:clear()
    activeTexts = {}
end

-- Render loop interno
kec:everyTick(function()
    local now = GetGameTimer()

    for id, data in pairs(activeTexts) do
        if now >= data.expire then
            activeTexts[id] = nil
        else
            SetTextFont(data.font)
            SetTextScale(0.0, data.scale)
            SetTextColour(data.color.r, data.color.g, data.color.b, 255)
            SetTextCentre(true)
            SetTextDropshadow(1, 0, 0, 0, 255)
            SetTextEdge(1, 0, 0, 0, 150)
            SetTextEntry("STRING")
            AddTextComponentString(data.text)
            DrawText(data.position.x, data.position.y)
        end
    end
end)

return label2d

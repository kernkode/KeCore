-- ============================================================
-- kec.label2d — Avisos de texto en pantalla (NUI)
--
-- Vive SOLO en kecore y a propósito NO está en scripts/builder/perf-modules.ts: el
-- `ui_page` es de este recurso y `SendNUIMessage` solo habla con el CEF de quien lo llama,
-- así que si esto se inyectara en los consumidores cada uno se lo mandaría a un CEF que no
-- tiene. Los demás recursos llegan por el export de abajo, que @kecore/init.lua envuelve en
-- un `kec.label2d` con la misma pinta de siempre.
--
-- El temporizador es de la SPA: el `duration` viaja en el mensaje y allí se apaga solo, así
-- que aquí no queda ni un tick por frame. El label2d de antes recorría su lista de textos en
-- un everyTick, y encima uno por recurso consumidor.
--
-- El dibujo: svelte-src/src/App.svelte + Label2d.svelte.
--
-- Uso:
--   kec.label2d:showText("Texto", { duration = 2000, size = 26, outline = true })
--   kec.label2d:success("Motor encendido", 2000)
--   kec.label2d:error("Motor apagado", 2000)
--   kec.label2d:info("hola {43ff64d9}soy yo")   -- ver el color de tramo abajo
--
-- Color por tramos, dentro del propio texto: `{rrggbbaa}` (o `{rrggbb}`, alfa a tope)
-- pinta lo que va DETRÁS, y `{}` vuelve al color base del aviso. No hay límite de
-- cambios. Una llave que no encierre 6 u 8 hexadecimales se queda tal cual, así que un
-- texto con llaves de verdad no se rompe.
-- ============================================================

kec.label2d = {}

-- El aspecto por defecto de TODOS los avisos, y el único sitio donde se cambia: tocar aquí
-- mueve de golpe el aviso del motor, de la compuerta, del inventario... Cada llamada puede
-- pisar lo que quiera pasándolo en `options`.
local DEFAULTS = {
    color    = "#ffffffff",
    duration = 2000,
    -- y = 0.83: bajo, pero no tanto como 0.90 — la hotbar del inventario va centrada
    -- abajo (bottom 26px + 52px de slot, y hasta 96px el aviso del propio inventario),
    -- así que a 0.90 el aviso caía justo detrás. `x`/`y` son fracciones de pantalla y
    -- `y` es el borde de ARRIBA del texto, como en el DrawText de antes.
    x = 0.5,
    y = 0.83,
    align = "center",
    -- Píxeles A 1080p: la SPA los pasa a rem, así que el aviso mide lo mismo en pantalla
    -- a 720p que a 4K.
    size = 24,
    font = "barlow",
    weight = 500,
    -- La sombra va puesta salvo que se apague: es la que hacía legible el texto sobre el
    -- cielo claro de GTA (el `SetTextDropshadow` de antes).
    shadow = true,
    -- Y el contorno también: es el `SetTextEdge` que llevaban todos los avisos del DrawText, y
    -- sin él un texto claro sobre el cielo o sobre la nieve se pierde. `outline = false` en una
    -- llamada lo quita, pero por defecto TODOS lo llevan.
    outline = true,
    -- Grosor del borde en px a 1080p.
    outlineWidth = 2.8,
    outlineColor = "#000000ff"
}

-- La escala de DrawText no era una medida: `SetTextScale(0.0, 0.45)` con la fuente 4 salía
-- a unos 24px de alto a 1080p. Las llamadas que ya existen pasan `scale` (0.36–0.45), así
-- que se traduce en vez de romperlas. Es CALIBRACIÓN, a ojo: si los avisos viejos salen
-- grandes o pequeños, este número es el que se mueve.
local SCALE_TO_PX = 54

-- El contador vive una sola vez (aquí), así que un número suelto ya es único para todos los
-- recursos: no hace falta prefijo.
local counter = 0

--- Acepta el `{ r, g, b }` de siempre o un hexadecimal ("43ff64d9", "#43ff64") y devuelve
--- el "#rrggbbaa" que espera el CSS. nil si no es ni una cosa ni la otra.
local function toColor(value)
    if type(value) == "string" then
        local hex = (value:gsub("^#", ""))
        if #hex == 6 then hex = hex .. "ff" end
        return "#" .. hex
    end

    if type(value) ~= "table" then return nil end

    -- math.floor porque %02x revienta con un float que no sea entero.
    return ("#%02x%02x%02x%02x"):format(
        math.floor(value.r or 255),
        math.floor(value.g or 255),
        math.floor(value.b or 255),
        math.floor(value.a or 255)
    )
end

--- Muestra un aviso en pantalla. Solo hay uno a la vez: el nuevo pisa al anterior.
---@param text string Texto, con los tramos de color `{rrggbbaa}` opcionales
---@param options table|nil {
---   color = { r, g, b } | "rrggbbaa",  -- color base
---   duration = 2000,                   -- ms de visibilidad
---   position = { x = 0.5, y = 0.83 },  -- fracciones de pantalla
---   align = "center" | "left" | "right",
---   size = 22,                         -- px a 1080p
---   font = "chalet" | "oswald" | "pricedown" | <familia CSS>,
---   weight = 400,                      -- grosor de la letra
---   shadow = true,
---   outline = true, outlineWidth = 1, outlineColor = "000000"  -- puesto por defecto
--- }
---@return number id Para cancelarlo antes de tiempo con kec.label2d:hide(id)
function kec.label2d:showText(text, options)
    options = options or {}
    counter = counter + 1

    local id = counter
    local position = options.position or {}

    -- Un `font` numérico es la fuente de DrawText de las llamadas de antes (0, 4...). Ya no
    -- significa nada, y colarlo en un font-family dejaría el aviso en la fuente del sistema.
    local font = type(options.font) == "string" and options.font or DEFAULTS.font

    -- La sombra y el contorno se leen así y no con un `== true` a secas: los dos van PUESTOS por
    -- defecto, y un `== true` los apagaría siempre que la llamada no los pidiera a mano.
    local shadow = options.shadow
    if shadow == nil then shadow = DEFAULTS.shadow end

    local outline = options.outline
    if outline == nil then outline = DEFAULTS.outline end

    SendNUIMessage({
        action = "label2d",
        label = {
            id = id,
            text = tostring(text),
            color = toColor(options.color) or DEFAULTS.color,
            duration = options.duration or DEFAULTS.duration,
            x = position.x or DEFAULTS.x,
            y = position.y or DEFAULTS.y,
            align = options.align or DEFAULTS.align,
            size = options.size or (options.scale and options.scale * SCALE_TO_PX) or DEFAULTS.size,
            font = font,
            weight = options.weight or DEFAULTS.weight,
            shadow = shadow == true,
            outline = outline == true,
            outlineWidth = options.outlineWidth or DEFAULTS.outlineWidth,
            outlineColor = toColor(options.outlineColor) or DEFAULTS.outlineColor
        }
    })

    return id
end

--- Atajos de color
function kec.label2d:success(text, duration, options)
    options = options or {}
    -- Verde menta claro en vez del verde puro (60,255,60): sobre el día de GTA y con el
    -- contorno oscuro, el verde saturado se leía apagado.
    options.color = options.color or { r = 130, g = 255, b = 165 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

function kec.label2d:error(text, duration, options)
    options = options or {}
    options.color = options.color or { r = 255, g = 60, b = 60 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

function kec.label2d:info(text, duration, options)
    options = options or {}
    options.color = options.color or { r = 60, g = 160, b = 255 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

function kec.label2d:warning(text, duration, options)
    options = options or {}
    options.color = options.color or { r = 255, g = 200, b = 60 }
    options.duration = duration or options.duration
    return self:showText(text, options)
end

--- Ocultar un aviso por su ID antes de que expire. Si ya lo pisó otro, no hace nada: el id
--- que llega no es el que está en pantalla y ese no es suyo para taparlo.
---@param id number
function kec.label2d:hide(id)
    if not id then return end
    SendNUIMessage({ action = "label2d", label = { id = id, hide = true } })
end

--- Quitar el aviso que haya, sea de quien sea.
function kec.label2d:clear()
    SendNUIMessage({ action = "label2d", label = { clear = true } })
end

-- La puerta para los demás recursos. Es UN export con el nombre del método dentro, y no la
-- tabla publicada tal cual: al cruzar de recurso el `self` sería la COPIA del consumidor, y
-- los métodos dejarían de encontrar ni el contador ni los DEFAULTS —en silencio—. Así el
-- `self` que llega se descarta y siempre se llama sobre la tabla de verdad, la de aquí.
--
-- Del otro lado lo envuelve @kecore/init.lua, que reconstruye un `kec.label2d` con los mismos
-- métodos; ningún recurso llama a este export a mano.
exports('label2d', function(method, ...)
    local fn = kec.label2d[method]

    if type(fn) ~= "function" then
        print(("^1[label2d] no existe el método '%s'^7"):format(tostring(method)))
        return
    end

    return fn(kec.label2d, ...)
end)

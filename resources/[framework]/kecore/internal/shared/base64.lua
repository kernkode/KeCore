kec.base64 = {}

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local b64chars_table = {}

-- Crear tabla inversa para decodificación rápida
for i = 1, 64 do
    b64chars_table[b64chars:sub(i, i)] = i - 1
end

function kec.base64:encode(data)
    local strData = tostring(data or "")
    if strData == "" then return "" end

    -- Usamos string.gsub en lugar de data:gsub para evitar errores de metatabla en FiveM
    local bit_pattern = string.gsub(strData, '.', function(x) 
        local r, b = '', string.byte(x)
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'

    local encoded = string.gsub(bit_pattern, '%d%d%d?%d?%d?%d?', function(x)
        if (string.len(x) < 6) then return '' end
        local c = 0
        for i = 1, 6 do c = c + (string.sub(x, i, i) == '1' and 2^(6-i) or 0) end
        return string.sub(b64chars, c+1, c+1)
    end)

    local padding = ({ '', '==', '=' })[#strData % 3 + 1]
    return encoded .. padding
end

function kec.base64:decode(data)
    local strData = tostring(data or "")
    if strData == "" then return "" end

    -- Limpiar caracteres no válidos
    strData = string.gsub(strData, '[^'..b64chars..'=]', '')

    local bit_pattern = string.gsub(strData, '.', function(x)
        if (x == '=') then return '' end
        local val = b64chars_table[x]
        if not val then return '' end
        
        local r = ''
        for i = 6, 1, -1 do r = r .. (val % 2^i - val % 2^(i-1) > 0 and '1' or '0') end
        return r
    end)

    return string.gsub(bit_pattern, '%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if (string.len(x) ~= 8) then return '' end
        local c = 0
        for i = 1, 8 do c = c + (string.sub(x, i, i) == '1' and 2^(8-i) or 0) end
        return string.char(c)
    end)
end
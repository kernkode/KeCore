kec.lzwson = {}

-- Caracteres de escape para evitar problemas en el transporte de red de FiveM
function kec.lzwson:escape_str(s)
    local mapping = {["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\\"] = "\\\\", ['"'] = '\\"'}
    return string.gsub(s, ".", mapping)
end

-- Algoritmo LZW: Compresión
local function lzw_compress(payload)
    local dict = {}
    for i = 0, 255 do
        dict[string.char(i)] = i
    end
    
    local current = ""
    local result = {}
    local code = 256
    local dict_size = 256
    
    for i = 1, #payload do
        local char = string.sub(payload, i, i)
        local next_str = current .. char
        
        if dict[next_str] then
            current = next_str
        else
            table.insert(result, string.char(math.floor(dict[current] / 256)) .. string.char(dict[current] % 256))
            dict[next_str] = dict_size
            dict_size = dict_size + 1
            current = char
        end
    end
    
    if #current > 0 then
        table.insert(result, string.char(math.floor(dict[current] / 256)) .. string.char(dict[current] % 256))
    end
    
    return table.concat(result)
end

-- Algoritmo LZW: Descompresión
local function lzw_decompress(payload)
    local dict = {}
    for i = 0, 255 do
        dict[i] = string.char(i)
    end
    
    local current_code = string.byte(payload, 1) * 256 + string.byte(payload, 2)
    local current = dict[current_code]
    local result = {current}
    local dict_size = 256
    local i = 3
    
    while i <= #payload do
        local next_code = string.byte(payload, i) * 256 + string.byte(payload, i + 1)
        i = i + 2
        
        local entry
        if dict[next_code] then
            entry = dict[next_code]
        elseif next_code == dict_size then
            entry = current .. string.sub(current, 1, 1)
        else
            return nil -- Error de descompresión
        end
        
        table.insert(result, entry)
        dict[dict_size] = current .. string.sub(entry, 1, 1)
        dict_size = dict_size + 1
        current = entry
    end
    
    return table.concat(result)
end

--- Empaqueta una tabla Lua, la convierte a JSON y la comprime
-- @param data (table): La tabla de datos a enviar
-- @return (string): String binario comprimido
function kec.lzwson:pack(data)
    if not data then return nil end
    local jsonString = json.encode(data)
    -- Solo comprimimos si vale la pena (overhead vs tamaño)
    if #jsonString < 50 then
        return "RAW:" .. jsonString
    end
    return "LZW:" .. lzw_compress(jsonString)
end

--- Desempaqueta el string comprimido y devuelve la tabla Lua
-- @param compressedString (string): El string recibido
-- @return (table): La tabla de datos original
function kec.lzwson:unpack(compressedString)
    if not compressedString then return nil end

    if string.sub(compressedString, 1, 4) == "RAW:" then
        return json.decode(string.sub(compressedString, 5))
    elseif string.sub(compressedString, 1, 4) == "LZW:" then
        local jsonString = lzw_decompress(string.sub(compressedString, 5))
        return json.decode(jsonString)
    else
        -- Fallback por si acaso se envía texto plano sin prefijo
        return json.decode(compressedString)
    end
end

function kec.lzwson:compare(originalSize, compressedData)
    local newSize = #compressedData
    print(string.format("^2Compresión: %d bytes -> %d bytes (Ahorro: %d%%)^7",
        originalSize, newSize, math.floor((1 - (newSize/originalSize)) * 100)))
end
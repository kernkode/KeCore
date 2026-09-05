-- ============================================================
-- kec.audio (servidor) — quién está sonando y por qué segundo va
--
-- El que suena es el CEF de cada jugador (ver internal/client/audio_nui.lua). Este lado solo
-- hace dos cosas que el cliente no puede hacer solo:
--
--   1. Repartir un emisor a todo el mundo o a unos cuantos.
--   2. Que todos oigan EL MISMO SEGUNDO. Cada emisor global se apunta con el reloj del servidor
--      al arrancar, así que al que entra tarde —o al que reinicia kecore y pierde su CEF— se le
--      manda la canción por donde va, no desde el principio.
--
-- Vive SOLO en kecore y NO se transpila a performance/, por lo mismo que mongodb_registry.lua:
-- la tabla `sources` de aquí tiene que ser la única copia. Si se inyectara, cada recurso llevaría
-- su propio registro y ninguno sabría lo que están tocando los demás. Los consumidores llegan por
-- el export del final, que @kecore/init.lua envuelve en un `kec.audio`.
--
-- Uso:
--   kec.audio:play({ id = "disco", url = stream, coords = { x = ..., y = ..., z = ... }, loop = true })
--   kec.audio:play({ url = stream, netId = netId, loop = true })          -- se mueve con el coche
--   kec.audio:play({ url = stream, target = source, volume = 0.5 })       -- solo para uno
--   kec.audio:stop("disco")
-- ============================================================

kec.audio = {}

local EV_PLAY = "kec:audio:play"
local EV_STOP = "kec:audio:stop"
local EV_SYNC = "kec:audio:sync"

---@type table<string, table> id -> emisor vivo
local sources = {}

--- El emisor tal y como lo recibe el cliente, con el `offset` recalculado AHORA.
--- Es el único sitio que hace la cuenta del reloj, y por eso vale igual para el primer envío que
--- para el jugador que llega media canción después.
--- Devuelve nil si es una pista de un solo pase que ya se ha terminado (solo se puede saber si
--- alguien dijo cuánto duraba).
local function payload(id, src)
    local elapsed = (GetGameTimer() - src.startedAt) / 1000.0

    if not src.loop and src.duration and elapsed > src.duration then
        sources[id] = nil
        return nil
    end

    return {
        id = id,
        url = src.url,
        volume = src.volume,
        loop = src.loop,
        -- El módulo de la duración lo hace el CEF, que es el único que sabe lo que dura de verdad
        -- el fichero (aquí puede no saberse, y en un directo no existe).
        offset = src.offset + elapsed,
        netId = src.netId,
        coords = src.coords,
        occlusion = src.occlusion,
        flat = src.flat,
        refDistance = src.refDistance,
        maxDistance = src.maxDistance
    }
end

--- Un punto en tabla plana. Un vector3 del servidor viaja igual, pero así el registro guarda siempre
--- la misma forma y el cliente no tiene que distinguir.
local function point(p)
    if not p or not p.x then return nil end
    return { x = p.x + 0.0, y = p.y + 0.0, z = p.z + 0.0 }
end

--- Arranca un emisor.
---@param opts table {
---   url = "https://...",       -- obligatorio
---   id = "disco",              -- por defecto un uuid; repetir un id pisa el emisor anterior
---   target = source | { source, ... } | nil,  -- nil = todo el mundo
---   entity = veh | netId = 12, -- se mueve con la entidad
---   coords = { x, y, z },      -- o se queda quieto ahí
---   duration = 213,            -- segundos; solo para retirar del registro una pista que acabó
---   volume, loop, offset, refDistance, maxDistance, occlusion, flat  -- ver el cliente
--- }
---@return string|nil id
function kec.audio:play(opts)
    if type(opts) ~= "table" or type(opts.url) ~= "string" then
        kec.log:error("kec.audio", "play necesita al menos { url = \"...\" }")
        return nil
    end

    local id = tostring(opts.id or kec.utils:uuid())

    local netId = opts.netId
    if not netId and opts.entity then
        netId = NetworkGetNetworkIdFromEntity(opts.entity)
    end

    sources[id] = {
        url = opts.url,
        volume = opts.volume,
        loop = opts.loop == true,
        offset = opts.offset or 0.0,
        duration = opts.duration,
        netId = netId,
        coords = point(opts.coords),
        occlusion = opts.occlusion,
        flat = opts.flat,
        refDistance = opts.refDistance,
        maxDistance = opts.maxDistance,
        target = opts.target,
        -- El reloj del servidor en ms desde que arrancó. Monotónico, que es lo que hace falta:
        -- os.time() solo tiene segundos y un cambio de hora del sistema lo mueve.
        startedAt = GetGameTimer()
    }

    local list = { payload(id, sources[id]) }

    if opts.target == nil then
        kec:emitAllClients(EV_PLAY, list)
    elseif type(opts.target) == "table" then
        for _, target in ipairs(opts.target) do
            kec:emitClient(EV_PLAY, target, list)
        end
    else
        kec:emitClient(EV_PLAY, opts.target, list)
    end

    return id
end

--- Para un emisor en todos los clientes a los que se les mandó.
---@param id string
function kec.audio:stop(id)
    id = tostring(id)
    local src = sources[id]
    if not src then return end

    sources[id] = nil

    if src.target == nil then
        kec:emitAllClients(EV_STOP, id)
    elseif type(src.target) == "table" then
        for _, target in ipairs(src.target) do
            kec:emitClient(EV_STOP, target, id)
        end
    else
        kec:emitClient(EV_STOP, src.target, id)
    end
end

--- Los emisores vivos, por id. Copia: el registro es de aquí.
---@return table
function kec.audio:list()
    local out = {}
    for id, src in pairs(sources) do
        out[id] = { url = src.url, loop = src.loop, netId = src.netId, coords = src.coords }
    end
    return out
end

--- Convierte un link de YouTube en algo que el CEF pueda tocar.
---
--- Lo hace el relay del devkit (scripts/core/audio.ts), no este proceso: hace falta yt-dlp, y la
--- URL que da googlevideo caduca y no siempre manda CORS — el relay las tapa las dos cosas y
--- devuelve una URL estable. Aquí solo se pega la parte pública, que es la única que este lado
--- sabe (por qué IP le llegan los jugadores).
---
--- Convars (config.cfg): `audio_api_url` (interno, con la clave), `audio_public_url` (lo que ven
--- los clientes; por defecto el mismo) y `audio_api_key` (la API_KEY del .env del devkit).
---
---@param url string Link de YouTube, en cualquiera de sus formas
---@param cb fun(track: table|nil, err: string|nil) track = { id, url, title, duration, isLive }
function kec.audio:resolve(url, cb)
    local api = GetConvar("audio_api_url", "")
    local key = GetConvar("audio_api_key", "")

    if api == "" or key == "" then
        cb(nil, "faltan las convars audio_api_url / audio_api_key (ver config.cfg)")
        return
    end

    local public = GetConvar("audio_public_url", api)

    kec.axios:post(api .. "/api/audio/resolve", { url = url }, {
        -- Las cabeceras se pisan enteras (el merge de axios es plano), así que el Content-Type va
        -- también aquí o el POST sale sin él.
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["x-api-key"] = key
        },
        -- yt-dlp tarda un par de segundos largos la primera vez; los 5 s por defecto se quedan
        -- cortos y devolverían un timeout con la resolución ya en marcha.
        timeout = 30000
    }, function(err, response)
        local data = response and response.data

        if err or type(data) ~= "table" or not data.path then
            cb(nil, (data and data.error) or ("el relay no resolvió el link (" .. tostring(err) .. ")"))
            return
        end

        cb({
            -- El id del vídeo tal como lo ha entendido el relay: es lo que hay que guardar para
            -- volver a poner esto (un link pegado a mano y el id pelado acaban en el mismo id).
            id = data.id,
            url = public .. data.path,
            title = data.title,
            duration = data.duration,
            isLive = data.isLive
        })
    end)
end

--- Busca en YouTube por texto y devuelve una lista para elegir, que es lo que ahorra tener que pegar
--- un link. Lo hace el mismo relay del devkit, y con `--flat-playlist`: de cada resultado vuelve lo
--- que trae la página de búsqueda y NO su URL tocable, así que del elegido hay que pasar por
--- `resolve` (le vale el id pelado).
---
--- Las mismas convars que `resolve`, y no hace falta la pública: aquí no viaja ninguna URL.
---
---@param query string Lo que se busca, tal como lo ha escrito el jugador
---@param limit number|nil Cuántos resultados como mucho (el relay topa en 10)
---@param cb fun(results: table|nil, err: string|nil) results = { { id, title, duration, channel } }
function kec.audio:search(query, limit, cb)
    local api = GetConvar("audio_api_url", "")
    local key = GetConvar("audio_api_key", "")

    if api == "" or key == "" then
        cb(nil, "faltan las convars audio_api_url / audio_api_key (ver config.cfg)")
        return
    end

    kec.axios:post(api .. "/api/audio/search", { query = query, limit = limit }, {
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/json",
            ["x-api-key"] = key
        },
        -- Una búsqueda es un yt-dlp más, así que se le da el mismo margen largo que al resolve.
        timeout = 30000
    }, function(err, response)
        local data = response and response.data

        if err or type(data) ~= "table" or type(data.results) ~= "table" then
            cb(nil, (data and data.error) or ("el relay no buscó (" .. tostring(err) .. ")"))
            return
        end

        cb(data.results)
    end)
end

--- Todo lo que le toca a un jugador, con el segundo por el que va cada cosa.
local function snapshotFor(target)
    local list, n = {}, 0

    for id, src in pairs(sources) do
        local mine = src.target == nil or src.target == target

        if not mine and type(src.target) == "table" then
            for _, t in ipairs(src.target) do
                if t == target then
                    mine = true
                    break
                end
            end
        end

        if mine then
            local data = payload(id, src)
            if data then
                n = n + 1
                list[n] = data
            end
        end
    end

    return list, n
end

local function sendSnapshot(target)
    local list, n = snapshotFor(target)
    if n > 0 then kec:emitClient(EV_PLAY, target, list) end
end

-- El que acaba de entrar: la música del mundo ya llevaba un rato sonando.
kec:on_player_loaded(function(player)
    sendSnapshot(player.id)
end)

-- Y el que perdió su CEF porque kecore se reinició en caliente: lo pide él (el cliente no puede
-- saber por dónde iba la canción, el reloj es de aquí).
--
-- Con freno, porque esto lo dispara el cliente: sin él, uno que lo pidiera en bucle tendría al
-- servidor rearmando y mandando la foto todo el rato. Un reinicio de kecore lo pide UNA vez.
local lastSync = {}
local SYNC_COOLDOWN_MS = 5000

kec:on(EV_SYNC, function(source)
    if not source then return end

    local now = GetGameTimer()
    if lastSync[source] and now - lastSync[source] < SYNC_COOLDOWN_MS then return end

    lastSync[source] = now
    sendSnapshot(source)
end)

kec:on_player_disconnect(function(player)
    lastSync[player.id] = nil
end)

-- Un export con el método dentro, no la tabla: al cruzar de recurso el `self` sería la copia del
-- consumidor y los métodos perderían `sources` en silencio. Igual que label2d_nui.lua.
exports('audio', function(method, ...)
    local fn = kec.audio[method]

    if type(fn) ~= "function" then
        print(("^1[kec.audio] no existe el método '%s'^7"):format(tostring(method)))
        return
    end

    return fn(kec.audio, ...)
end)

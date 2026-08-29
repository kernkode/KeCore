-- ============================================================
-- kec.audio — sonido 3D en el CEF (música, streams, one-shots)
--
-- GTA no sabe tocar una URL: su audio son contenedores precocinados (.awc + dat54), así que
-- el que suena aquí es el CEF con la Web Audio API. Ella trae el panner HRTF, el paso-bajo y
-- la reverb que hacen falta para que la música de un coche se mueva con él y para que la de
-- una discoteca se oiga desde la calle como si estuviera sonando dentro.
--
-- Vive SOLO en kecore y a propósito NO está en scripts/builder/perf-modules.ts, por lo mismo
-- que label2d_nui.lua: el `ui_page` es de este recurso y SendNUIMessage solo habla con el CEF
-- de quien la llama, así que una copia inyectada en un consumidor le hablaría a un CEF que no
-- tiene. Los demás recursos llegan por el export del final, que @kecore/init.lua envuelve en
-- un `kec.audio` con estos mismos métodos.
--
-- El grafo de audio y los mandos del sonido (corte del filtro, mezcla de reverb) están en
-- svelte-src/src/audio.ts. Aquí solo vive la parte que necesita al juego: dónde está cada
-- emisor respecto de la cámara y si hay una pared en medio.
--
-- Uso:
--   kec.audio:play({ url = "https://...", entity = veh, loop = true })
--   kec.audio:play({ url = "https://...", coords = vector3(...), volume = 0.8 })
--   kec.audio:play({ url = "nui://kecore/html/beep.ogg" })   -- sin sitio: 2D, en tu cabeza
--   kec.audio:stop(id)
-- ============================================================

kec.audio = {}

-- Cómo suena un emisor si nadie dice lo contrario, y el único sitio donde se cambia.
local DEFAULTS = {
    volume = 1.0,
    loop = false,
    offset = 0.0,
    -- Metros. Dentro de refDistance suena a volumen entero y a partir de maxDistance ya no se
    -- oye; entre medias cae con el modelo inverso del panner. 40 m es el radio de una manzana:
    -- suficiente para oír el bajo de la disco desde la esquina.
    refDistance = 2.0,
    maxDistance = 40.0,
    -- Cuánto se lo comen las paredes cuando NO estás en la misma sala (o en el mismo coche).
    -- 0 = como si no hubiera pared, 1 = tapiado. Es el mando a mover si desde fuera se oye
    -- demasiado claro o demasiado poco; lo que hace con este número está en audio.ts.
    muffle = 0.85
}

-- 20 Hz. El panner interpola entre mensaje y mensaje (rampa de 60 ms en audio.ts), así que a
-- 50 ms ya suena continuo y cuesta un tercio de lo que costaría mandarlo por frame.
local TICK_MS = 50

-- Por debajo de esto no se manda el emisor: la posición no ha cambiado lo bastante para que se
-- note. Con la cámara quieta esto deja el tick en cero mensajes.
local MOVE_EPSILON = 0.05

local KVP_MASTER = "kec:audio:master"

local EV_PLAY = "kec:audio:play"
local EV_STOP = "kec:audio:stop"
local EV_SYNC = "kec:audio:sync"

local RAD = math.pi / 180

---@type table<string, table> id -> emisor vivo
local sources = {}
local spatialCount = 0
local tick = nil

-- Volumen general del jugador, persistido en su máquina: es SU ajuste, no el del servidor.
-- Se guarda como string y no con SetResourceKvpFloat porque un KVP sin poner devuelve 0.0, que
-- es indistinguible de "lo tiene al mínimo".
local master = tonumber(GetResourceKvpString(KVP_MASTER) or "") or 1.0

--- La entidad de un emisor, resolviendo el netId si hace falta.
--- Un emisor del servidor viaja por netId y puede llegar antes de que la entidad esté
--- streameada: entonces devuelve 0 y el emisor se salta ESE tick, pero sigue vivo (se resuelve
--- solo en cuanto el coche entre en el radio). Uno creado en el cliente con un handle local no
--- tiene netId, así que si desaparece ya no vuelve.
---@return number entity, boolean gone
local function resolveEntity(src)
    if src.entity and DoesEntityExist(src.entity) then
        return src.entity, false
    end

    if not src.netId then
        return 0, src.entity ~= nil
    end

    local entity = NetworkGetEntityFromNetworkId(src.netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        src.entity = entity
        return entity, false
    end

    return 0, false
end

--- Cuánto se lo come la pared, de 0 a 1.
--- Una native por emisor y nada más: lo que hace falta saber es si estás en la MISMA sala que
--- el sonido, no dónde está cada ladrillo.
--- ponytail: no hay raycast, así que una pared suelta (un muro en un descampado) no tapa nada.
--- El día que haga falta, un StartShapeTestLosProbe a 5 Hz con el resultado interpolado.
local function occlusionOf(src, ped, pedVehicle, pedInterior)
    if src.space == "vehicle" then
        return (pedVehicle ~= 0 and pedVehicle == src.entity) and 0.0 or src.muffle
    end

    if src.space == "interior" then
        return (pedInterior == src.interior) and 0.0 or src.muffle
    end

    return 0.0
end

--- En qué sala vive el sonido, que es lo que decide si las paredes se lo comen.
--- Se calcula UNA vez (no por tick): un coche no deja de ser un coche y una disco no se mueve.
--- Si la entidad todavía no está streameada no se puede saber, así que se deja sin decidir y se
--- vuelve a intentar en cuanto se resuelva — hasta entonces el emisor suena sin amortiguar, que
--- es el fallo que menos molesta (se oye, en vez de no oírse).
local function detectSpace(src, entity)
    if entity and entity ~= 0 then
        if GetEntityType(entity) == 2 then
            src.space = "vehicle"
            return
        end

        local interior = GetInteriorFromEntity(entity)
        if interior ~= 0 then
            src.space, src.interior = "interior", interior
            return
        end

        src.space = "open"
        return
    end

    if src.coords then
        local interior = GetInteriorAtCoords(src.coords.x, src.coords.y, src.coords.z)
        if interior ~= 0 then
            src.space, src.interior = "interior", interior
        else
            src.space = "open"
        end
    end
end

--- Pasa las coordenadas del mundo al espacio de la cámara y manda la tanda al CEF.
--- Se transforma AQUÍ para que el listener del CEF se quede quieto en el origen: así el mensaje
--- lleva solo la posición de cada emisor y no hace falta mandarle también la orientación de la
--- cámara (que cambia cada frame) ni que él haga la matriz.
local function update()
    local cam = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)

    -- Base de la cámara: adelante, derecha y arriba. El roll se ignora a propósito (la cámara
    -- de GTA solo lo usa en cinemáticas y en el audio no se nota).
    local pitch, yaw = rot.x * RAD, rot.z * RAD
    local cp = math.cos(pitch)
    local fx, fy, fz = -math.sin(yaw) * cp, math.cos(yaw) * cp, math.sin(pitch)
    local rx, ry = math.cos(yaw), math.sin(yaw)
    -- arriba = derecha × adelante (rz es 0, así que los términos que lo llevan se caen)
    local ux, uy, uz = ry * fz, -rx * fz, rx * fy - ry * fx

    local ped = kec.player:ped()
    local pedVehicle = GetVehiclePedIsIn(ped, false)
    local pedInterior = GetInteriorFromEntity(ped)

    -- Claves de una letra: este mensaje sale 20 veces por segundo y el JSON lo paga entero.
    local list, n = {}, 0

    for id, src in pairs(sources) do
        local sx, sy, sz

        if src.spatial then
            if src.coords then
                sx, sy, sz = src.coords.x, src.coords.y, src.coords.z
            else
                local entity, gone = resolveEntity(src)
                if gone then
                    kec.audio:stop(id)
                elseif entity ~= 0 then
                    -- Primera vez que se resuelve: ya se puede saber si es un coche o una sala.
                    if not src.space then detectSpace(src, entity) end

                    local coords = GetEntityCoords(entity)
                    sx, sy, sz = coords.x, coords.y, coords.z
                end
            end
        end

        if sx then
            local dx, dy, dz = sx - cam.x, sy - cam.y, sz - cam.z
            local ax = dx * rx + dy * ry
            local ay = dx * ux + dy * uy + dz * uz
            local az = -(dx * fx + dy * fy + dz * fz)
            local oc = occlusionOf(src, ped, pedVehicle, pedInterior)

            if oc ~= src.oc
                or math.abs(ax - src.ax) > MOVE_EPSILON
                or math.abs(ay - src.ay) > MOVE_EPSILON
                or math.abs(az - src.az) > MOVE_EPSILON
            then
                src.ax, src.ay, src.az, src.oc = ax, ay, az, oc
                n = n + 1
                list[n] = { i = id, x = ax, y = ay, z = az, o = oc }
            end
        end
    end

    if n > 0 then
        SendNUIMessage({ action = "audio", op = "pos", list = list })
    end
end

--- El tick solo existe mientras haya algo que colocar en el mundo: un beep 2D no lo arranca.
local function syncTick()
    if spatialCount > 0 and not tick then
        tick = kec:everyTick(update, TICK_MS)
    elseif spatialCount <= 0 and tick then
        tick:cancel()
        tick = nil
    end
end

--- Arranca un emisor.
---@param opts table {
---   url = "https://..." | "nui://recurso/ruta.ogg",   -- obligatorio
---   id = "disco",              -- por defecto un uuid; repetir un id pisa el emisor anterior
---   volume = 1.0, loop = false,
---   offset = 0.0,              -- segundo por el que empieza (lo usa la sincronía del servidor)
---   entity = veh | netId = 12, -- se mueve con la entidad
---   coords = vector3(...),     -- o se queda quieto ahí
---   -- sin entity ni coords: 2D, suena igual desde donde sea (avisos, UI)
---   refDistance = 2.0, maxDistance = 40.0,
---   space = "vehicle"|"interior"|"open",  -- se autodetecta; esto es para forzarlo
---   muffle = 0.85              -- cuánto se lo come la pared cuando no estás dentro
--- }
---@return string|nil id
function kec.audio:play(opts)
    if type(opts) ~= "table" or type(opts.url) ~= "string" then
        kec.log:error("kec.audio", "play necesita al menos { url = \"...\" }")
        return nil
    end

    -- El esquema se comprueba aquí porque la URL viene de fuera (del servidor, o de otro
    -- recurso) y acaba en el `src` de un <audio> dentro del CEF. Solo lo que puede sonar.
    if not opts.url:match("^https?://") and not opts.url:match("^nui://") then
        kec.log:error("kec.audio", "url no soportada (%s): solo http, https o nui", opts.url)
        return nil
    end

    local id = tostring(opts.id or kec.utils:uuid())
    if sources[id] then self:stop(id) end

    local spatial = (opts.entity ~= nil) or (opts.netId ~= nil) or (opts.coords ~= nil)

    local src = {
        spatial = spatial,
        entity = opts.entity,
        netId = opts.netId,
        coords = opts.coords,
        space = opts.space,
        muffle = opts.muffle or DEFAULTS.muffle,
        -- Posición ya mandada, para el filtro de "no se ha movido". Lejísimos, para que el
        -- primer tick siempre pase el filtro y el emisor se coloque antes de sonar del todo.
        ax = math.huge, ay = math.huge, az = math.huge, oc = -1
    }

    sources[id] = src

    if spatial then
        if not src.space then
            detectSpace(src, src.entity or (src.netId and NetworkGetEntityFromNetworkId(src.netId)))
        end

        spatialCount = spatialCount + 1
        syncTick()
    end

    SendNUIMessage({
        action = "audio",
        op = "play",
        source = {
            id = id,
            url = opts.url,
            volume = opts.volume or DEFAULTS.volume,
            loop = opts.loop == true,
            offset = opts.offset or DEFAULTS.offset,
            spatial = spatial,
            refDistance = opts.refDistance or DEFAULTS.refDistance,
            maxDistance = opts.maxDistance or DEFAULTS.maxDistance
        }
    })

    return id
end

--- Para un emisor y se lleva su <audio> del CEF.
---@param id string
function kec.audio:stop(id)
    local src = sources[tostring(id)]
    if not src then return end

    sources[tostring(id)] = nil

    if src.spatial then
        spatialCount = spatialCount - 1
        syncTick()
    end

    SendNUIMessage({ action = "audio", op = "stop", id = tostring(id) })
end

--- Para todos. Lo usa el servidor al vaciar el mundo, y el volumen general no se toca.
function kec.audio:stopAll()
    sources = {}
    spatialCount = 0
    syncTick()
    SendNUIMessage({ action = "audio", op = "stopAll" })
end

--- Volumen de UN emisor, 0..1. Es relativo al general del jugador.
function kec.audio:setVolume(id, volume)
    if not sources[tostring(id)] then return end
    SendNUIMessage({
        action = "audio",
        op = "volume",
        id = tostring(id),
        volume = math.max(0.0, math.min(1.0, tonumber(volume) or 1.0))
    })
end

--- Volumen general del jugador, 0..1. Se guarda en SU máquina y se aplica al arrancar.
function kec.audio:setMasterVolume(volume)
    master = math.max(0.0, math.min(1.0, tonumber(volume) or 1.0))
    SetResourceKvp(KVP_MASTER, tostring(master))
    SendNUIMessage({ action = "audio", op = "master", volume = master })
end

---@return number
function kec.audio:getMasterVolume()
    return master
end

-- El volumen guardado en la máquina del jugador tiene que llegar al CEF ANTES que cualquier
-- emisor, o el primero suena a tope. El CEF no está listo en el mismo frame en el que arranca el
-- recurso, así que va en el frame siguiente (y por eso no es un setTimeout(0), ver
-- everytick-en-vez-de-settimeout-0).
if master ~= 1.0 then
    kec:everyTick(function()
        SendNUIMessage({ action = "audio", op = "master", volume = master })
        return false
    end)
end

-- ── Los emisores que manda el servidor ───────────────────────────────────────────────────────
-- Siempre en lista (de uno o de muchos): así el que llega tarde y el emisor suelto usan el mismo
-- camino. El `offset` ya viene calculado por el servidor con su reloj, que es lo que hace que
-- todos oigan el mismo segundo.
kec:on(EV_PLAY, function(list)
    if type(list) ~= "table" then return end
    for _, opts in ipairs(list) do
        kec.audio:play(opts)
    end
end)

kec:on(EV_STOP, function(id)
    if id then kec.audio:stop(id) else kec.audio:stopAll() end
end)

-- Si kecore se reinicia en caliente, el CEF es nuevo y esta tabla está vacía: hay que volver a
-- pedirle al servidor lo que ya estaba sonando. En la conexión inicial esto llega antes de que el
-- jugador exista y el servidor devuelve una lista vacía; el envío de verdad lo hace él en
-- kec:on_player_loaded. Con margen porque el evento no sale si la red aún no está montada.
kec:setTimeout(function() kec:emitServer(EV_SYNC) end, 2000)

-- La puerta para los demás recursos: UN export con el nombre del método dentro, no la tabla
-- publicada tal cual. Al cruzar de recurso el `self` sería la COPIA del consumidor y los métodos
-- perderían `sources`, el tick y el volumen —en silencio—. Mismo motivo y misma forma que el
-- export de label2d_nui.lua. Del otro lado lo envuelve @kecore/init.lua.
exports('audio', function(method, ...)
    local fn = kec.audio[method]

    if type(fn) ~= "function" then
        print(("^1[kec.audio] no existe el método '%s'^7"):format(tostring(method)))
        return
    end

    return fn(kec.audio, ...)
end)

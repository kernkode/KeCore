-- ============================================================
-- kec.audio — sonido 3D en el CEF (música, streams, one-shots)
--
-- GTA no sabe tocar una URL: su audio son contenedores precocinados (.awc + dat54), así que
-- el que suena aquí es el CEF con la Web Audio API. Ella trae el panner HRTF, el paso-bajo y
-- la reverb que hacen falta para que la música de un coche se mueva con él y para que la de
-- una discoteca se oiga desde la calle como si estuviera sonando dentro.
--
-- Esto es un MOTOR, no un sistema. Hace lo que solo se puede hacer desde aquí —resolver la entidad
-- de un emisor, pasar el mundo al espacio de la cámara, mandar al CEF solo lo que cambió— y no tiene
-- ninguna opinión sobre por qué algo suena tapado. Eso lo decide quien lo usa, con `occlusion`:
-- una disco mira su interior y su puerta, un coche mira si vas dentro, y otro puede tirar un raycast
-- o inventarse lo que quiera. Cada recurso trae su regla y no hereda la de nadie.
--
-- Vive SOLO en kecore y a propósito NO está en scripts/builder/perf-modules.ts, por lo mismo
-- que label2d_nui.lua: el `ui_page` es de este recurso y SendNUIMessage solo habla con el CEF
-- de quien la llama, así que una copia inyectada en un consumidor le hablaría a un CEF que no
-- tiene. Los demás recursos llegan por el export del final, que @kecore/init.lua envuelve en
-- un `kec.audio` con estos mismos métodos.
--
-- El grafo de audio y los mandos del sonido (a cuántos Hz corta el filtro con oclusión 1, cuánta
-- reverb entra) están en svelte-src/src/audio.ts.
--
-- Uso:
--   local id = kec.audio:play({ url = "https://...", entity = veh, loop = true })
--   local id = kec.audio:play({ url = "https://...", coords = vector3(...), volume = 0.8 })
--   kec.audio:play({ url = "nui://kecore/html/beep.ogg" })   -- sin sitio: 2D, en tu cabeza
--   kec.audio:occlusion(id, 0.85)   -- lo tapa una pared: TÚ decides cuándo y cuánto
--   kec.audio:flat(id, true)        -- sin panner, la mezcla original (vas dentro del coche)
--   kec.audio:position(id, x, y, z) -- moverlo, o kec.audio:attach(id, entity) para que siga a algo
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
    maxDistance = 40.0
}

-- 20 Hz. El panner interpola entre mensaje y mensaje (rampa de 60 ms en audio.ts), así que a
-- 50 ms ya suena continuo y cuesta un tercio de lo que costaría mandarlo por frame.
local TICK_MS = 50

-- Cada cuánto se vuelve a intentar resolver el netId de un emisor que este cliente todavía no tiene
-- (ver `resolveEntity`). Un segundo es de sobra: el coche tiene que entrar en los ~150 m del
-- streaming y aún le quedan 100 para acercarse a los 45 en los que se oye.
local RETRY_MS = 1000

-- Por debajo de esto no se manda el emisor: la posición no ha cambiado lo bastante para que se
-- note. Con la cámara quieta esto deja el tick en cero mensajes.
local MOVE_EPSILON = 0.05

local KVP_MASTER = "kec:audio:master"

local EV_PLAY = "kec:audio:play"
local EV_STOP = "kec:audio:stop"
local EV_SYNC = "kec:audio:sync"

-- Estos dos son LOCALES (TriggerEvent, no red): avisan a los demás recursos de este cliente de que un
-- emisor ya existe o ya no. Hacen falta porque quien manda la oclusión no suele ser quien crea el
-- emisor —una disco la arranca el servidor— y hasta que llega no hay a quién ponérsela.
--   kec:onLocal("kec:audio:started", function(id) ... end)
local EV_STARTED = "kec:audio:started"
local EV_STOPPED = "kec:audio:stopped"

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
---
--- El reintento va a RETRY_MS y no en cada tick: preguntarle al motor por un netId que este cliente
--- no tiene suelta un aviso por llamada (`GetNetworkObject: no object by ID`), y a 20 Hz eso es la
--- consola llena mientras un coche con música está fuera de streaming. No se pierde nada: a esa
--- distancia el emisor está muy por encima de su `maxDistance`, así que no se oye de todas formas.
---@return number entity, boolean gone
local function resolveEntity(src)
    if src.entity and DoesEntityExist(src.entity) then
        return src.entity, false
    end

    if not src.netId then
        return 0, src.entity ~= nil
    end

    local now = GetGameTimer()
    if src.triedAt and now - src.triedAt < RETRY_MS then
        return 0, false
    end

    src.triedAt = now

    local entity = NetworkGetEntityFromNetworkId(src.netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        src.entity = entity
        return entity, false
    end

    return 0, false
end

--- Pasa las coordenadas del mundo al espacio de la cámara y manda la tanda al CEF.
--- Se transforma AQUÍ para que el listener del CEF se quede quieto en el origen: así el mensaje
--- lleva solo la posición de cada emisor y no hace falta mandarle también la orientación de la
--- cámara (que cambia cada frame) ni que él haga la matriz.
---
--- La oclusión no se calcula: se manda la que el dueño del emisor haya dejado puesta con
--- `kec.audio:occlusion`. Este tick solo la acarrea, y solo cuando ha cambiado.
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

            -- En 2D la posición ya no pinta nada, así que solo se manda cuando cambia el modo o la
            -- oclusión: conduciendo, el bamboleo de la cámara mandaría un mensaje por tick para mover
            -- un panner que nadie está oyendo.
            local moved = not src.flat and (
                math.abs(ax - src.ax) > MOVE_EPSILON
                or math.abs(ay - src.ay) > MOVE_EPSILON
                or math.abs(az - src.az) > MOVE_EPSILON
            )

            if moved or src.oc ~= src.sentOc or src.flat ~= src.sentFlat then
                src.ax, src.ay, src.az = ax, ay, az
                src.sentOc, src.sentFlat = src.oc, src.flat
                n = n + 1
                -- `d`: en 2D, sin panner. La posición viaja igual, y es la que deja el panner
                -- puesto en su sitio para el instante en que te bajes del coche.
                list[n] = { i = id, x = ax, y = ay, z = az, o = src.oc, d = src.flat }
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
---   occlusion = 0.0,           -- cuánta pared hay de salida; se cambia con kec.audio:occlusion
---   flat = false               -- sin panner, la mezcla original tal cual
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
        -- Lo que el dueño del emisor quiere que se oiga. Arranca sin pared: kecore no sabe si hay
        -- una y no se la inventa.
        oc = tonumber(opts.occlusion) or 0.0,
        flat = opts.flat == true,
        -- Lo ya mandado, para el filtro de "no ha cambiado nada". Lejísimos y con una oclusión
        -- imposible para que el primer tick pase el filtro siempre y el emisor quede colocado
        -- antes de sonar del todo. `sentFlat` empieza sin valor por lo mismo.
        ax = math.huge, ay = math.huge, az = math.huge, sentOc = -1, sentFlat = nil
    }

    sources[id] = src

    if spatial then
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

    TriggerEvent(EV_STARTED, id)

    return id
end

--- Cuánta pared hay entre el emisor y quien escucha, de 0 (ninguna) a 1 (tapiado).
---
--- kecore no lo calcula. No sabe si tu música está detrás de una pared, dentro de un coche o al aire,
--- y adivinarlo era justo lo que ataba a todos al mismo sistema: lo pone el dueño del emisor, con la
--- regla que le dé la gana. Este lado solo lo acarrea hasta el CEF, que es quien lo convierte en Hz y
--- dB (ver TUNING en svelte-src/src/audio.ts).
---
--- Llámalo SOLO cuando el número cambie de verdad: desde otro recurso esto cruza de VM (es un export)
--- y por frame sale carísimo. Con un umbral de un 2% en el llamador no se nota ni al oído.
---
--- En un emisor 2D no hace nada: sin sitio no hay pared que valga.
---@param id string
---@param value number 0..1
---@return boolean applied false si ese emisor no existe (todavía) en este cliente
function kec.audio:occlusion(id, value)
    local src = sources[tostring(id)]
    if not src then return false end

    src.oc = math.max(0.0, math.min(1.0, tonumber(value) or 0.0))
    return true
end

--- Quita el panner: el emisor suena con su mezcla original, como si el altavoz te rodeara.
---
--- Es lo que quiere un coche por dentro. El panner coloca el sonido respecto de la CÁMARA, y la de GTA
--- va varios metros por detrás del coche: sentado dentro, la música se oía venir de delante y girar
--- cada vez que giras la cámara. Un interior grande NO lo quiere — una disco se anda por dentro y la
--- música tiene que seguir estando en la cabina del DJ.
---
--- La posición se sigue mandando: es la que deja el panner en su sitio para cuando te bajes.
---@param id string
---@param value boolean
---@return boolean applied false si ese emisor no existe (todavía) en este cliente
function kec.audio:flat(id, value)
    local src = sources[tostring(id)]
    if not src then return false end

    src.flat = value == true
    return true
end

--- Mueve un emisor con sitio. Acepta (id, x, y, z) o (id, vector3).
--- Deja de seguir a la entidad, si seguía a alguna. Un emisor 2D no puede pasar a tener sitio: el CEF
--- le montó el grafo sin panner, así que eso pide un `play` nuevo.
function kec.audio:position(id, x, y, z)
    local src = sources[tostring(id)]
    if not src or not src.spatial then return end

    if type(x) ~= "number" then
        if not x then return end
        x, y, z = x.x, x.y, x.z
    end

    src.coords = { x = x + 0.0, y = y + 0.0, z = z + 0.0 }
    src.entity, src.netId = nil, nil
end

--- Que el emisor siga a una entidad, lo contrario de `position`. Mismo aviso: 2D no pasa a 3D.
---@param id string
---@param entity number
function kec.audio:attach(id, entity)
    local src = sources[tostring(id)]
    if not src or not src.spatial then return end

    src.coords, src.netId = nil, nil
    src.entity = entity
end

--- Los ids de los emisores vivos en este cliente.
---
--- Es lo que necesita un recurso que arranca —o que se reinicia— para engancharse a emisores que ya
--- existían: de esos no va a llegar ningún `kec:audio:started`, porque el aviso pasó antes de que él
--- estuviera escuchando.
---@return string[]
function kec.audio:list()
    local ids, n = {}, 0

    for id in pairs(sources) do
        n = n + 1
        ids[n] = id
    end

    return ids
end

--- Para un emisor y se lleva su <audio> del CEF.
---@param id string
function kec.audio:stop(id)
    id = tostring(id)
    local src = sources[id]
    if not src then return end

    sources[id] = nil

    if src.spatial then
        spatialCount = spatialCount - 1
        syncTick()
    end

    SendNUIMessage({ action = "audio", op = "stop", id = id })
    TriggerEvent(EV_STOPPED, id)
end

--- Para todos. Lo usa el servidor al vaciar el mundo, y el volumen general no se toca.
function kec.audio:stopAll()
    local ids = {}
    for id in pairs(sources) do ids[#ids + 1] = id end

    sources = {}
    spatialCount = 0
    syncTick()
    SendNUIMessage({ action = "audio", op = "stopAll" })

    -- Uno por uno y no un aviso a secas: al que sigue la oclusión de SU emisor le da igual que se
    -- hayan parado los demás, y así el que escucha no tiene que saber qué había vivo.
    for _, id in ipairs(ids) do TriggerEvent(EV_STOPPED, id) end
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

// El motor de sonido del overlay: lo que suena cuando un recurso llama a `kec.audio:play`.
//
// GTA no toca URLs, así que la música (el stream de YouTube que resuelve el relay, un .ogg del
// propio recurso) sale de aquí, del CEF, con la Web Audio API. Ella pone las tres cosas que el
// juego no da: el panner HRTF que coloca el sonido alrededor de la cabeza, un paso-bajo que
// imita la pared, y una reverb para que lo de dentro suene a dentro.
//
// Quien manda es `internal/client/audio_nui.lua`: él sabe dónde está cada emisor y si hay una
// pared en medio, y manda las posiciones YA PASADAS al espacio de la cámara (20 veces por
// segundo). Por eso aquí el listener no se mueve nunca: se queda en el origen mirando a -Z, que
// es como viene por defecto.
//
// Y una cosa que no se oye pero se paga: el <audio> de un emisor que se sale de su radio se PAUSA
// (ver `resume`). Fuera de maxDistance el panner ya lo silenciaba, pero los bytes seguían bajando
// igual, y un emisor global se manda a TODOS los jugadores.
//
// Esto no pinta nada, así que no es un componente: es un módulo con su listener, igual que la
// precarga de fuentes vive en main.ts.

type PlayMessage = {
    id: string
    url: string
    volume: number
    loop: boolean
    offset: number
    spatial: boolean
    refDistance: number
    maxDistance: number
}

// Claves de una letra porque este mensaje llega 20 veces por segundo y el JSON se paga entero:
// i = id, x/y/z = posición en el espacio de la cámara, o = oclusión 0..1, d = suena en 2D
// (dentro del coche del que sale la música: ver `listenTo` en audio_nui.lua).
type PosItem = { i: string; x: number; y: number; z: number; o: number; d?: boolean }

type AudioMessage = {
    action: 'audio'
    op: 'play' | 'stop' | 'stopAll' | 'volume' | 'master' | 'pos'
    source?: PlayMessage
    id?: string
    volume?: number
    list?: PosItem[]
}

// Los mandos del sonido. Si algo se oye mal, se mueve AQUÍ: el Lua solo manda un número de
// oclusión de 0 a 1 y esta tabla decide qué significa en Hz y en decibelios.
const TUNING = {
    // Corte del paso-bajo con la puerta abierta y con la puerta cerrada. 300 Hz deja pasar el
    // bombo y el bajo y se come todo lo demás: es lo que oyes desde la calle de una disco. Son DOS
    // en cascada (ver `wall`), así que a partir de ahí cae 24 dB por octava.
    LOWPASS_OPEN: 20000,
    LOWPASS_SHUT: 300,
    // Y además baja de volumen: una pared no solo filtra, también tapa.
    GAIN_SHUT: 0.35,
    // Mezcla de reverb. Un poco siempre (la sala en la que está el altavoz) y bastante más
    // cuando estás fuera: lo que llega ahí es rebote, no el altavoz directo.
    REVERB_DRY: 0.15,
    REVERB_SHUT: 0.7,
    // Segundos. La posición llega cada 50 ms y se interpola hasta la siguiente; el filtro va más
    // lento a propósito, para que cruzar una puerta sea un barrido y no un click.
    POS_RAMP: 0.06,
    // Lo que tarda un cambio de estado —la pared, el paso a 2D— no es fijo: se fija la VELOCIDAD del
    // barrido y el tamaño del salto decide cuánto dura. FILTER_RAMP es el suelo y FILTER_SWEEP lo que
    // duraría un cambio entero, de 0 a 1.
    //
    // Es que los dos casos que hay no se parecen en nada. Cruzar la puerta de una disco llega en
    // empujones pequeños y seguidos (su regla empuja 10 veces por segundo) y ahí solo hace falta unir
    // un empujón con el siguiente: 250 ms. Subirse a un coche es UN salto de 0.85 de una vez, y con
    // esos mismos 250 ms suena a interruptor; a esta velocidad son ~850 ms, lo que tarda una puerta en
    // cerrarse.
    FILTER_RAMP: 0.25,
    FILTER_SWEEP: 1.0,
    // Largo de la reverb generada.
    IR_SECONDS: 1.2,
    // A partir de maxDistance × esto se pausa el <audio>. Pasado maxDistance el panner ya no deja
    // oír nada, pero el elemento sigue tirando bytes; el margen está para que el rearranque —que
    // tiene que rebufferar— caiga donde todavía no se oye. Ceiling: llegando en coche a 100 km/h
    // puede que la música arranque medio segundo tarde.
    CULL_MARGIN: 1.5
}

type Source = {
    el: HTMLAudioElement
    // La pared: dos paso-bajos en cascada. Se guardan los dos porque la oclusión los mueve a la vez.
    wall: BiquadFilterNode[]
    gain: GainNode
    wet: GainNode | null
    panner: PannerNode | null
    // Los dos caminos de salida de un emisor con sitio. Están montados los dos siempre y se cruzan
    // con una rampa: desconectar y reconectar el nodo al vuelo daría un click justo al abrir la
    // puerta del coche, que es cuando se cambia.
    spatialOut: GainNode | null
    directOut: GainNode | null
    volume: number
    loop: boolean
    // Instante (en segundos del reloj del CEF) en el que la pista estaba en su segundo 0. Es lo que
    // permite reengancharla por donde iría después de haber estado pausada.
    epoch: number
    // (maxDistance × CULL_MARGIN)², para comparar con la distancia al cuadrado y no sacar raíces en
    // el bucle de posiciones.
    cull2: number
    audible: boolean
    placed: boolean
    oc: number
    direct: boolean
}

const sources = new Map<string, Source>()

let ctx: AudioContext | null = null
let master: GainNode
let reverb: ConvolverNode
let masterVolume = 1

// La respuesta al impulso de la reverb se GENERA: ruido con caída exponencial. Suena a sala
// grande de sobra para esto y ahorra meter un .wav de IR en el `files{}` del recurso.
function impulseResponse(context: AudioContext): AudioBuffer {
    const length = Math.floor(context.sampleRate * TUNING.IR_SECONDS)
    const buffer = context.createBuffer(2, length, context.sampleRate)

    for (let ch = 0; ch < 2; ch++) {
        const data = buffer.getChannelData(ch)
        for (let i = 0; i < length; i++) {
            data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / length, 2.5)
        }
    }

    return buffer
}

// El AudioContext se crea en el primer `play` y no al cargar la página: un jugador que nunca
// oiga nada no paga ni un hilo de audio. El `resume` es por la política de autoplay — el CEF de
// FiveM no da un gesto del usuario nunca, así que si algún día la aplica, esto es lo que
// desatasca.
function ensureContext(): AudioContext {
    if (ctx) {
        if (ctx.state === 'suspended') void ctx.resume()
        return ctx
    }

    ctx = new AudioContext()

    master = ctx.createGain()
    master.gain.value = masterVolume
    master.connect(ctx.destination)

    // UN convolver para todos los emisores, no uno por emisor: la reverb es difusa, no tiene
    // dirección, así que compartir el bus suena igual y cuesta un nodo en vez de N. Va DESPUÉS
    // del panner de cada uno a propósito: la cola llega a los dos oídos, como en la vida.
    reverb = ctx.createConvolver()
    reverb.buffer = impulseResponse(ctx)
    reverb.connect(master)

    // Para poder engancharle un analizador desde las pruebas del navegador.
    ;(window as unknown as { __kecAudio?: unknown }).__kecAudio = { ctx, master, sources }

    return ctx
}

function stop(id: string) {
    const src = sources.get(id)
    if (!src) return

    sources.delete(id)
    src.el.pause()
    // Sin `src` y con load(): si no, el CEF se queda descargando el stream de un emisor que ya
    // no suena hasta que el GC pase por el elemento.
    src.el.removeAttribute('src')
    src.el.load()
    src.gain.disconnect()
    for (const f of src.wall) f.disconnect()
    src.panner?.disconnect()
    src.spatialOut?.disconnect()
    src.directOut?.disconnect()
    src.wet?.disconnect()
}

/**
 * Un paso-bajo de los que hacen la pared.
 *
 * Van DOS en cascada, y no uno, porque uno solo cae 12 dB por octava: con el corte en 300 Hz, a
 * 500 Hz —donde vive la melodía— apenas se comía 12 dB y la música se oía "igual pero más sorda" en
 * vez de quedarse en el bombo. Medido con dos: 500 Hz baja 21 dB en vez de 12, y 100 Hz sigue
 * intacto, que es lo que tiene que pasar (el bombo atraviesa la pared, la voz no).
 *
 * Q de Butterworth en los dos para que la cascada no haga un resalte en la esquina del corte.
 */
function wall(context: AudioContext): BiquadFilterNode {
    const filter = context.createBiquadFilter()
    filter.type = 'lowpass'
    filter.frequency.value = TUNING.LOWPASS_OPEN
    filter.Q.value = Math.SQRT1_2
    return filter
}

/**
 * Lleva un parámetro hasta `target` en `seconds`, DESDE DONDE ESTÁ AHORA. Con `seconds` a 0 lo pone de
 * golpe.
 *
 * El ancla —leer el valor y ponerlo con `setValueAtTime` en `now`— es lo que hace que esto sea una
 * transición y no un salto, y no sobra: una rampa de la Web Audio interpola desde el ÚLTIMO evento de
 * la línea de tiempo, no desde el instante en el que la pides. Aquí el último evento es de hace
 * minutos —la oclusión solo se toca al cruzar una puerta o subirse a un coche—, así que el origen queda
 * tan atrás que en el primer sample el valor ya está pegado al destino. Medido en un
 * OfflineAudioContext: una rampa de 250 ms de 1 a 0 pedida 2 s después del último evento empieza
 * valiendo 0.11, el 89% del camino hecho de una vez (−19 dB en un sample). Eso era el "click" de
 * subirse al coche.
 *
 * `cancelAndHoldAtTime` no vale para esto: sin nada programado por delante que cancelar no deja ningún
 * evento donde agarrarse y se mide exactamente igual que sin ancla (medido también). Y el orden
 * importa: primero se LEE el valor de ahora —el de mitad de una rampa anterior, si la hay— y luego se
 * cancela, porque cancelar sin más devuelve el parámetro al valor del evento previo.
 */
function ramp(param: AudioParam, target: number, now: number, seconds: number, exponential = false): void {
    const from = param.value
    param.cancelScheduledValues(now)

    if (seconds <= 0) {
        param.setValueAtTime(target, now)
        return
    }

    param.setValueAtTime(from, now)

    if (exponential) param.exponentialRampToValueAtTime(target, now + seconds)
    else param.linearRampToValueAtTime(target, now + seconds)
}

/** El volumen de un emisor con la pared de ahora puesta: una pared no solo filtra, también tapa. */
function occludedGain(src: Source, occlusion: number): number {
    return src.volume * (1 - (1 - TUNING.GAIN_SHUT) * occlusion)
}

/**
 * Deja el <audio> en el segundo por el que iría la pista AHORA y lo arranca. Único sitio que la pone
 * en marcha, venga de un `play` o de volver a entrar en el radio después de estar pausada.
 *
 * No hace falta preguntarle nada al servidor para reengancharla: el `offset` del `play` ya dijo por
 * dónde iba la pista cuando llegó el emisor, y desde entonces avanza a un segundo por segundo, igual
 * en todas las máquinas. Guardando el instante de su segundo 0 (`epoch`) el CEF lo sabe solo.
 *
 * El reloj es `performance.now` y no `ctx.currentTime` porque el del contexto se para si el contexto
 * se suspende, y entonces la canción se quedaría atrás.
 */
function resume(id: string, src: Source) {
    const elapsed = performance.now() / 1000 - src.epoch
    const total = src.el.duration

    if (Number.isFinite(total) && total > 0) {
        if (src.loop) src.el.currentTime = elapsed % total
        else if (elapsed >= total) return stop(id) // se acabó mientras estabas lejos
        else src.el.currentTime = elapsed
    } else if (Number.isNaN(total)) {
        // Los metadatos no han llegado, así que todavía no se sabe a qué segundo saltar: se reintenta
        // cuando lleguen. (Un directo da Infinity y no cae aquí: ahí no hay seek que hacer y se
        // arranca por donde vaya el buffer, con el desfase que eso traiga.)
        src.el.addEventListener('loadedmetadata', () => {
            if (src.audible) resume(id, src)
        }, { once: true })
    }

    void src.el.play().catch(() => {
        // Si el CEF lo bloquea, el siguiente mensaje de posición lo reintenta.
    })
}

function play(msg: PlayMessage) {
    const context = ensureContext()
    stop(msg.id)

    const el = new Audio()
    // Sin esto el MediaElementSource sale mudo con una URL de otro origen (el stream del relay):
    // el navegador la marca como "tainted" y no deja leer sus muestras.
    el.crossOrigin = 'anonymous'
    el.loop = msg.loop
    // Un emisor con sitio no precarga NADA: con `auto`, poner el src ya se baja el fichero entero
    // aunque el elemento esté pausado y aunque nadie lo llegue a oír nunca (comprobado: readyState 4
    // sin un solo `play`). Lo arranca el primer `resume`, cuando ya se sabe que está a tiro.
    // ponytail: al alejarse solo se pausa, no se suelta el src, así que lo ya bajado se queda en
    // memoria. Si algún día molesta, `removeAttribute('src')` + `load()` como en `stop`, a cambio de
    // rebufferar entero cada vez que vuelves.
    el.preload = msg.spatial ? 'none' : 'auto'
    el.src = msg.url

    const node = context.createMediaElementSource(el)

    const filters = [wall(context), wall(context)]

    const gain = context.createGain()
    // Un emisor con sitio empieza callado: el panner todavía está en el origen (encima de tu
    // cabeza) y hasta el primer mensaje de posición, 50 ms después, sonaría a todo volumen y
    // centrado. El primer `pos` lo sube.
    gain.gain.value = msg.spatial ? 0 : msg.volume

    node.connect(filters[0])
    filters[0].connect(filters[1])
    filters[1].connect(gain)

    let panner: PannerNode | null = null
    let wet: GainNode | null = null
    let spatialOut: GainNode | null = null
    let directOut: GainNode | null = null

    if (msg.spatial) {
        panner = context.createPanner()
        panner.panningModel = 'HRTF'
        panner.distanceModel = 'inverse'
        panner.refDistance = msg.refDistance
        panner.maxDistance = msg.maxDistance
        panner.rolloffFactor = 1

        // Dos salidas montadas a la vez, una con panner y otra sin él, y se cruzan con rampa. La
        // sin panner es para cuando vas DENTRO del coche que lleva la música: ahí la mezcla
        // original es la buena y el panner solo estorba (ver `listenTo` en audio_nui.lua). Empieza
        // en 3D y el primer `pos` dice cuál toca.
        spatialOut = context.createGain()
        spatialOut.gain.value = 1
        directOut = context.createGain()
        directOut.gain.value = 0

        gain.connect(panner)
        panner.connect(spatialOut)
        spatialOut.connect(master)

        gain.connect(directOut)
        directOut.connect(master)

        wet = context.createGain()
        wet.gain.value = TUNING.REVERB_DRY
        gain.connect(wet)
        wet.connect(reverb)
    } else {
        gain.connect(master)
    }

    const src: Source = {
        el, wall: filters, gain, wet, panner, spatialOut, directOut,
        volume: msg.volume,
        loop: msg.loop,
        epoch: performance.now() / 1000 - msg.offset,
        cull2: (msg.maxDistance * TUNING.CULL_MARGIN) ** 2,
        // Un emisor con sitio no arranca hasta que el primer `pos` diga que está a tiro: si sonara
        // ya, alguien al otro lado del mapa se bajaría la pista de una disco que no oye.
        audible: !msg.spatial,
        placed: !msg.spatial,
        oc: 0,
        direct: false
    }

    sources.set(msg.id, src)

    if (!msg.spatial) resume(msg.id, src)
}

// La tanda de posiciones del tick de Lua. Vienen ya en el espacio de la cámara, así que se
// enchufan tal cual al panner: el listener no se toca nunca.
function place(list: PosItem[]) {
    if (!ctx) return
    const now = ctx.currentTime

    for (const p of list) {
        const src = sources.get(p.i)
        if (!src || !src.panner) continue

        const direct = p.d === true
        // Yendo en el coche del que sale la música no hay distancia que valga: siempre se oye.
        const audible = direct || (p.x * p.x + p.y * p.y + p.z * p.z) <= src.cull2

        // Cuánto duran los cambios que traiga este mensaje, proporcional al salto de oclusión (ver
        // FILTER_SWEEP): el paso a 2D viaja siempre con él, así que los dos se cruzan a la vez.
        //
        // El PRIMER mensaje de un emisor no es una transición sino el estado con el que empieza, y ese
        // se pone de golpe. Si no, la música de un coche arrancaría clara y se iría tapando ella sola
        // durante un segundo, y la que pones ya sentado dentro entraría barriendo desde el panner.
        const secs = src.placed
            ? Math.max(TUNING.FILTER_RAMP, Math.abs(p.o - src.oc) * TUNING.FILTER_SWEEP)
            : 0

        // Al volver de 2D a 3D la posición del panner está vieja (has conducido con él parado), así
        // que se pone de golpe en vez de rampar: si no, arrancaría el barrido desde donde estaba el
        // coche cuando te subiste.
        if (!direct && src.direct) {
            src.panner.positionX.setValueAtTime(p.x, now)
            src.panner.positionY.setValueAtTime(p.y, now)
            src.panner.positionZ.setValueAtTime(p.z, now)
        } else {
            // La rampa evita el zipper noise de saltar 20 veces por segundo, y de paso hace que a
            // 50 ms el movimiento se vea continuo.
            src.panner.positionX.linearRampToValueAtTime(p.x, now + TUNING.POS_RAMP)
            src.panner.positionY.linearRampToValueAtTime(p.y, now + TUNING.POS_RAMP)
            src.panner.positionZ.linearRampToValueAtTime(p.z, now + TUNING.POS_RAMP)
        }

        // El primer mensaje es el que sube el volumen: hasta aquí el emisor estaba colocado en el
        // origen y callado.
        if (!src.placed) {
            src.placed = true
            src.gain.gain.setValueAtTime(src.volume, now)
        }

        // Cruzar el radio de corte pausa el <audio> o lo reengancha. Pausado, el CEF deja de tirar
        // bytes en cuanto llena lo que tenga bufereado: la pista de una disco no la paga quien está
        // al otro lado del mapa. El volumen no se toca — de eso ya se encarga el panner.
        if (audible !== src.audible) {
            src.audible = audible
            if (audible) resume(p.i, src)
            else src.el.pause()

            // `resume` puede haberlo retirado: una pista sin bucle que se acabó mientras estabas
            // lejos. Sin esto, lo que queda del bucle rampa nodos ya desconectados.
            if (!sources.has(p.i)) continue
        }

        // Cruce entre la salida con panner y la de la mezcla original, con la misma duración que el
        // filtro: es el otro cambio que trae subirse al coche y tienen que ir juntos.
        if (direct !== src.direct) {
            src.direct = direct
            if (src.spatialOut) ramp(src.spatialOut.gain, direct ? 0 : 1, now, secs)
            if (src.directOut) ramp(src.directOut.gain, direct ? 1 : 0, now, secs)
        }

        if (p.o === src.oc) continue
        src.oc = p.o

        // Corte exponencial y no lineal: el oído oye en octavas, así que a mitad de camino lo que
        // suena "medio tapado" es la media geométrica (2,6 kHz), no la aritmética (10 kHz).
        const cutoff = TUNING.LOWPASS_SHUT * Math.pow(TUNING.LOWPASS_OPEN / TUNING.LOWPASS_SHUT, 1 - p.o)
        for (const f of src.wall) ramp(f.frequency, cutoff, now, secs, true)

        ramp(src.gain.gain, occludedGain(src, p.o), now, secs)

        if (src.wet) {
            const wet = TUNING.REVERB_DRY + (TUNING.REVERB_SHUT - TUNING.REVERB_DRY) * p.o
            ramp(src.wet.gain, wet, now, secs)
        }
    }
}

function onMessage(event: MessageEvent) {
    const msg = event.data as AudioMessage
    if (!msg || msg.action !== 'audio') return

    switch (msg.op) {
        case 'play':
            if (msg.source) play(msg.source)
            break

        case 'stop':
            if (msg.id) stop(msg.id)
            break

        case 'stopAll':
            for (const id of [...sources.keys()]) stop(id)
            break

        case 'pos':
            if (msg.list) place(msg.list)
            break

        case 'volume': {
            const src = msg.id ? sources.get(msg.id) : undefined
            if (!src || msg.volume === undefined || !ctx) break
            src.volume = msg.volume
            // Se reaplica pasando por la oclusión de ahora, o subir el volumen desde fuera desharía el
            // amortiguado de la pared. Por el mismo camino que el resto y no con un `.value` a pelo:
            // un escalón de ganancia hace click, y la especificación IGNORA el `.value` mientras haya
            // automatización pendiente, así que a mitad de subirte al coche el cambio se perdería.
            ramp(src.gain.gain, occludedGain(src, src.oc), ctx.currentTime, TUNING.POS_RAMP)
            break
        }

        case 'master':
            if (msg.volume === undefined) break
            masterVolume = msg.volume
            // Puede llegar antes del primer emisor (el ajuste guardado del jugador), y entonces
            // todavía no hay contexto: se guarda y lo coge `ensureContext`.
            if (ctx) master.gain.value = masterVolume
            break
    }
}

export function initAudio() {
    window.addEventListener('message', onMessage)
}

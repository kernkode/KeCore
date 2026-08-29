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
// i = id, x/y/z = posición en el espacio de la cámara, o = oclusión 0..1.
type PosItem = { i: string; x: number; y: number; z: number; o: number }

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
    // Corte del paso-bajo con la puerta abierta y con la puerta cerrada. 350 Hz deja pasar el
    // bombo y el bajo y se come todo lo demás: es lo que oyes desde la calle de una disco.
    LOWPASS_OPEN: 20000,
    LOWPASS_SHUT: 350,
    // Y además baja de volumen: una pared no solo filtra, también tapa.
    GAIN_SHUT: 0.35,
    // Mezcla de reverb. Un poco siempre (la sala en la que está el altavoz) y bastante más
    // cuando estás fuera: lo que llega ahí es rebote, no el altavoz directo.
    REVERB_DRY: 0.15,
    REVERB_SHUT: 0.7,
    // Segundos. La posición llega cada 50 ms y se interpola hasta la siguiente; el filtro va más
    // lento a propósito, para que cruzar una puerta sea un barrido y no un click.
    POS_RAMP: 0.06,
    FILTER_RAMP: 0.25,
    // Largo de la reverb generada.
    IR_SECONDS: 1.2
}

type Source = {
    el: HTMLAudioElement
    filter: BiquadFilterNode
    gain: GainNode
    wet: GainNode | null
    panner: PannerNode | null
    volume: number
    placed: boolean
    oc: number
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
    src.filter.disconnect()
    src.panner?.disconnect()
    src.wet?.disconnect()
}

function play(msg: PlayMessage) {
    const context = ensureContext()
    stop(msg.id)

    const el = new Audio()
    // Sin esto el MediaElementSource sale mudo con una URL de otro origen (el stream del relay):
    // el navegador la marca como "tainted" y no deja leer sus muestras.
    el.crossOrigin = 'anonymous'
    el.loop = msg.loop
    el.preload = 'auto'
    el.src = msg.url

    const node = context.createMediaElementSource(el)

    const filter = context.createBiquadFilter()
    filter.type = 'lowpass'
    filter.frequency.value = TUNING.LOWPASS_OPEN

    const gain = context.createGain()
    // Un emisor con sitio empieza callado: el panner todavía está en el origen (encima de tu
    // cabeza) y hasta el primer mensaje de posición, 50 ms después, sonaría a todo volumen y
    // centrado. El primer `pos` lo sube.
    gain.gain.value = msg.spatial ? 0 : msg.volume

    node.connect(filter)
    filter.connect(gain)

    let panner: PannerNode | null = null
    let wet: GainNode | null = null

    if (msg.spatial) {
        panner = context.createPanner()
        panner.panningModel = 'HRTF'
        panner.distanceModel = 'inverse'
        panner.refDistance = msg.refDistance
        panner.maxDistance = msg.maxDistance
        panner.rolloffFactor = 1
        gain.connect(panner)
        panner.connect(master)

        wet = context.createGain()
        wet.gain.value = TUNING.REVERB_DRY
        gain.connect(wet)
        wet.connect(reverb)
    } else {
        gain.connect(master)
    }

    sources.set(msg.id, {
        el, filter, gain, wet, panner,
        volume: msg.volume,
        placed: !msg.spatial,
        oc: 0
    })

    // El salto al segundo que toca (la sincronía del servidor) no se puede hacer hasta que se
    // sepa la duración, y en un directo no se puede hacer nunca: ahí `duration` es Infinity.
    if (msg.offset > 0) {
        el.addEventListener('loadedmetadata', () => {
            if (!Number.isFinite(el.duration) || el.duration <= 0) return
            el.currentTime = msg.loop ? msg.offset % el.duration : Math.min(msg.offset, el.duration)
        }, { once: true })
    }

    void el.play().catch(() => {
        // Si el CEF lo bloquea, el siguiente mensaje de posición lo reintenta.
    })
}

// La tanda de posiciones del tick de Lua. Vienen ya en el espacio de la cámara, así que se
// enchufan tal cual al panner: el listener no se toca nunca.
function place(list: PosItem[]) {
    if (!ctx) return
    const now = ctx.currentTime

    for (const p of list) {
        const src = sources.get(p.i)
        if (!src || !src.panner) continue

        // La rampa evita el zipper noise de saltar 20 veces por segundo, y de paso hace que a
        // 50 ms el movimiento se vea continuo.
        src.panner.positionX.linearRampToValueAtTime(p.x, now + TUNING.POS_RAMP)
        src.panner.positionY.linearRampToValueAtTime(p.y, now + TUNING.POS_RAMP)
        src.panner.positionZ.linearRampToValueAtTime(p.z, now + TUNING.POS_RAMP)

        // El primer mensaje es el que sube el volumen: hasta aquí el emisor estaba colocado en el
        // origen y callado.
        if (!src.placed) {
            src.placed = true
            src.gain.gain.setValueAtTime(src.volume, now)
            if (src.el.paused) void src.el.play().catch(() => {})
        }

        if (p.o === src.oc) continue
        src.oc = p.o

        // Corte exponencial y no lineal: el oído oye en octavas, así que a mitad de camino lo que
        // suena "medio tapado" es la media geométrica (2,6 kHz), no la aritmética (10 kHz).
        const cutoff = TUNING.LOWPASS_SHUT * Math.pow(TUNING.LOWPASS_OPEN / TUNING.LOWPASS_SHUT, 1 - p.o)
        src.filter.frequency.exponentialRampToValueAtTime(cutoff, now + TUNING.FILTER_RAMP)
        src.gain.gain.linearRampToValueAtTime(
            src.volume * (1 - (1 - TUNING.GAIN_SHUT) * p.o),
            now + TUNING.FILTER_RAMP
        )
        src.wet?.gain.linearRampToValueAtTime(
            TUNING.REVERB_DRY + (TUNING.REVERB_SHUT - TUNING.REVERB_DRY) * p.o,
            now + TUNING.FILTER_RAMP
        )
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
            if (!src || msg.volume === undefined) break
            src.volume = msg.volume
            // Se reaplica pasando por la oclusión de ahora, o subir el volumen desde fuera
            // desharía el amortiguado de la pared.
            src.gain.gain.value = src.volume * (1 - (1 - TUNING.GAIN_SHUT) * src.oc)
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

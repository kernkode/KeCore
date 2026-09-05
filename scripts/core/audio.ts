/**
 * El relay de audio: lo que convierte un link de YouTube en algo que el CEF de cada jugador
 * pueda tocar, y en una URL que no caduque.
 *
 * Por qué un relay y no la URL directa de googlevideo: esa URL caduca (~6 h), a veces viene
 * atada a la IP que la resolvió, y depende de que googlevideo mande cabeceras CORS — sin ellas
 * el `createMediaElementSource` del CEF sale mudo y no hay 3D ni filtro que aplicar. Sirviéndola
 * desde aquí, el cliente ve UNA URL estable, con Range (o sea, con seek para la sincronía) y sin
 * nada de CORS que negociar.
 *
 * Una pista con final se baja UNA vez a `cache/audio/` y desde ahí se sirve a todo el mundo: lo que
 * se paga por oyente es la subida (~130 kbps), no también la bajada. Un directo no tiene final que
 * guardar, así que ese sigue siendo un pipe por oyente. Lo bajado NO se queda en disco para siempre:
 * caduca a las 24 h (`CACHE_TTL_MS`).
 *
 * OJO, esto queda expuesto a internet (los jugadores tienen que llegar). Por eso:
 *   - Escucha en su propio puerto, no en el del API de control (ese tiene /api/stop y
 *     /api/restart y no debería salir de la máquina).
 *   - Solo acepta IDs de vídeo de YouTube, así que no es un proxy HTTP abierto.
 *   - Cada URL lleva un token firmado con API_KEY: sin token no se sirve nada.
 *
 * Quien lo usa desde el juego es `kec.audio:resolve` —y `kec.audio:search`, para no tener que pegar
 * un link— (internal/server/audio.lua).
 */

import { spawn } from 'node:child_process';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, unlinkSync } from 'node:fs';
import { rename, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import chalk from 'chalk';
import { log } from './logger.ts';
import { API_CONFIG, AUDIO_CACHE_PATH, AUDIO_CONFIG } from './configs.ts';

type Resolved = {
    id: string;
    title: string;
    duration: number;
    isLive: boolean;
    abr: number;
    /** Contenedor que eligió `pickAudio`: da el nombre del fichero en caché y su content-type. */
    ext: string;
    url: string;
    /** Cuándo deja de valer la URL directa (ms epoch). */
    expiresAt: number;
};

/** Un resultado de búsqueda: lo justo para pintar una lista y luego pedir el id que se elija. */
type Found = {
    id: string;
    title: string;
    duration: number;
    channel: string;
};

/**
 * El content-type de cada contenedor. Se pone a mano porque por extensión un `.webm` es
 * `video/webm` aunque dentro solo haya audio, y a un `<audio>` conviene darle el tipo bueno: un
 * fallo de códec suena exactamente igual que un fallo de red (silencio, sin un error que mirar).
 */
const MIME: Record<string, string> = {
    webm: 'audio/webm',
    m4a: 'audio/mp4',
    mp4: 'audio/mp4',
    opus: 'audio/ogg',
    ogg: 'audio/ogg',
    mp3: 'audio/mpeg'
};

/** Un id de vídeo de YouTube y nada más: es lo que impide que esto sea un proxy abierto. */
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

/** Lo que vale un token de reproducción. Una pista en bucle en una disco dura toda la noche. */
const TOKEN_TTL_MS = 24 * 60 * 60 * 1000;

/** Margen antes de que caduque la URL de googlevideo, para no servir un 403 a medio segundo. */
const EXPIRY_MARGIN_MS = 60_000;

/** yt-dlp tarda 1-3 s de normal; más de esto es que algo se colgó. */
const RESOLVE_TIMEOUT_MS = 25_000;

/** Cuántos resultados devuelve una búsqueda como mucho: es una lista para elegir, no un catálogo. */
const SEARCH_MAX = 10;

/** Una búsqueda no resuelve los formatos de cada vídeo (`--flat-playlist`), así que tarda menos. */
const SEARCH_TIMEOUT_MS = 20_000;

const cache = new Map<string, Resolved>();

/** Saca el id de un link de YouTube en cualquiera de sus formas, o del id pelado. */
export function videoIdFrom(input: string): string | null {
    const raw = (input || '').trim();
    if (VIDEO_ID.test(raw)) return raw;

    let url: URL;
    try {
        url = new URL(raw);
    } catch {
        return null;
    }

    const host = url.hostname.replace(/^www\./, '');
    if (host === 'youtu.be') {
        const id = url.pathname.slice(1);
        return VIDEO_ID.test(id) ? id : null;
    }

    if (host !== 'youtube.com' && host !== 'm.youtube.com' && host !== 'music.youtube.com') {
        return null;
    }

    const v = url.searchParams.get('v');
    if (v && VIDEO_ID.test(v)) return v;

    // /shorts/<id>, /embed/<id>, /live/<id>
    const parts = url.pathname.split('/').filter(Boolean);
    const last = parts[parts.length - 1];
    return last && VIDEO_ID.test(last) ? last : null;
}

/**
 * Corre yt-dlp y devuelve su JSON. Se mata si tarda demasiado, para no dejar procesos colgados.
 *
 * Los argumentos van en un array y NO en una línea de comandos: `spawn` sin shell no interpreta nada,
 * que es lo que hace que meter el texto que ha escrito un jugador en una búsqueda no sea una
 * inyección.
 */
function runYtDlp(args: string[], timeoutMs = RESOLVE_TIMEOUT_MS): Promise<any> {
    return new Promise((resolve, reject) => {
        const child = spawn('yt-dlp', [
            '--no-warnings',
            '--no-progress',
            '-J',
            ...args
        ], { windowsHide: true });

        let out = '';
        let err = '';

        const timer = setTimeout(() => {
            child.kill();
            reject(new Error(`yt-dlp no respondió en ${timeoutMs} ms`));
        }, timeoutMs);

        child.stdout.on('data', (chunk) => { out += chunk; });
        child.stderr.on('data', (chunk) => { err += chunk; });

        child.on('error', (error) => {
            clearTimeout(timer);
            reject(new Error(`no se pudo ejecutar yt-dlp (¿está instalado?): ${error.message}`));
        });

        child.on('close', (code) => {
            clearTimeout(timer);
            if (code !== 0) return reject(new Error(err.trim() || `yt-dlp salió con código ${code}`));

            try {
                resolve(JSON.parse(out));
            } catch {
                reject(new Error('yt-dlp no devolvió JSON'));
            }
        });
    });
}

/**
 * Elige la pista de audio. Se prefiere **opus/webm** y no el m4a aunque tenga más bitrate: el
 * opus es libre y lo toca cualquier build de Chromium, mientras que el AAC depende de con qué
 * códecs se haya compilado el CEF — y un fallo de códec suena igual que un fallo de red, o sea
 * a silencio sin un error que mirar.
 *
 * Y de las que quedan, la de MENOS bitrate que llegue a 96 kbps: esto lo paga el relay por cada
 * oyente, y para música de fondo en un coche 128 kbps ya es más de lo que se nota.
 */
function pickAudio(formats: any[]): any | null {
    const audio = (formats || []).filter((f) =>
        f?.url && f.acodec && f.acodec !== 'none' && (!f.vcodec || f.vcodec === 'none')
    );

    if (audio.length === 0) return null;

    const opus = audio.filter((f) => String(f.acodec).startsWith('opus'));
    const pool = opus.length > 0 ? opus : audio;

    pool.sort((a, b) => (a.abr || 0) - (b.abr || 0));
    return pool.find((f) => (f.abr || 0) >= 96) || pool[pool.length - 1];
}

/** Resuelve (o reusa) la URL directa de un vídeo. */
async function resolve(id: string): Promise<Resolved> {
    const hit = cache.get(id);
    if (hit && hit.expiresAt > Date.now()) return hit;

    // Lo que ya está bajado no se resuelve: no hay URL que buscar (ver `fromDisk`).
    const saved = fromDisk(id);
    if (saved) {
        cache.set(id, saved);
        return saved;
    }

    const info = await runYtDlp(['--no-playlist', `https://www.youtube.com/watch?v=${id}`]);
    const format = pickAudio(info.formats);

    if (!format) throw new Error('el vídeo no tiene ninguna pista de audio suelta');

    // googlevideo pone su propia caducidad en la URL. Si no viene, media hora y a re-resolver.
    const expire = Number(new URL(format.url).searchParams.get('expire')) * 1000;
    const expiresAt = Number.isFinite(expire) && expire > Date.now()
        ? expire - EXPIRY_MARGIN_MS
        : Date.now() + 30 * 60_000;

    const resolved: Resolved = {
        id,
        title: String(info.title || id),
        duration: Number(info.duration) || 0,
        isLive: info.is_live === true,
        abr: Math.round(format.abr || 0),
        ext: String(format.ext || 'webm'),
        url: format.url,
        expiresAt
    };

    cache.set(id, resolved);
    return resolved;
}

// ── La pista en disco ────────────────────────────────────────────────────────────────────────
// Con fecha de caducidad: lo que pase de CACHE_TTL_MS lo tira `sweep`, así que la carpeta no crece
// sola y ninguna canción se queda guardada indefinidamente.

/**
 * Lo que se guarda junto a la pista bajada. Es justo lo que NO cambia: el título y la duración de un
 * vídeo son los mismos mañana, y un fichero en disco no caduca. Lo único por lo que había que volver
 * a preguntar era la URL de googlevideo, y para servir de disco no hace falta ninguna.
 */
type Meta = Pick<Resolved, 'title' | 'duration' | 'abr' | 'ext'>;

const metaPath = (id: string): string => join(AUDIO_CACHE_PATH, `${id}.json`);
const mediaPath = (id: string, ext: string): string => join(AUDIO_CACHE_PATH, `${id}.${ext}`);

/**
 * La pista que ya está bajada, con su ficha, sin pasar por yt-dlp.
 *
 * Esto no es solo por velocidad: YouTube corta con un "confirma que no eres un bot" a quien pregunta
 * mucho, y el arranque le preguntaba otra vez por las MISMAS pistas de las discotecas en cada
 * reinicio. Cuando eso pasaba, el local se quedaba mudo con la canción entera en `cache/audio/`.
 */
function fromDisk(id: string): Resolved | null {
    try {
        const meta = JSON.parse(readFileSync(metaPath(id), 'utf8')) as Meta;
        if (!meta?.ext || !existsSync(mediaPath(id, meta.ext))) return null;

        // Sin URL y sin caducidad a propósito: lo que se sirve es el fichero. Si alguien lo borra,
        // `handleStream` no lo encuentra, tira la caché y el siguiente intento resuelve de cero.
        return { ...meta, id, isLive: false, url: '', expiresAt: Infinity };
    } catch {
        return null;
    }
}

/** Deja la ficha junto a la pista, una sola vez. */
async function remember(info: Resolved): Promise<void> {
    if (existsSync(metaPath(info.id))) return;

    const meta: Meta = {
        title: info.title,
        duration: info.duration,
        abr: info.abr,
        ext: info.ext
    };

    try {
        await writeFile(metaPath(info.id), JSON.stringify(meta));
    } catch {
        // Una ficha que no se pudo escribir solo cuesta volver a preguntar: no es motivo para
        // dejar de servir la canción.
    }
}

/**
 * Lo que vive una pista en disco. No es una LRU: el mtime es la fecha en la que se BAJÓ y servirla no
 * lo toca, así que esto es un techo de retención de verdad — una canción que se pone todos los días
 * también caduca y se vuelve a bajar. Es lo que se le pide a este relay, no un descuido.
 */
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/** Cada cuánto se mira. Al arrancar, y luego a este ritmo: en producción el relay vive semanas. */
const SWEEP_EVERY_MS = 60 * 60 * 1000;

/**
 * Tira de `cache/audio/` todo lo que haya pasado de CACHE_TTL_MS: el audio, su ficha y cualquier
 * `.part` que dejara un relay muerto a media descarga. Va por el mtime de cada fichero, así que no
 * hay ninguna lista que mantener — la carpeta ES el registro.
 *
 * Con el fichero se va su entrada en memoria: la que sale de `fromDisk` no caduca nunca (`url` vacía,
 * `expiresAt` infinito), así que sin esto el siguiente oyente se comería un 502 mientras el relay
 * descubre por su cuenta que el fichero ya no está.
 *
 * ponytail: un barrido periódico, no un temporizador por pista. El techo real es CACHE_TTL_MS +
 * SWEEP_EVERY_MS (25 h con estos números); si alguna vez tuviera que ser al minuto, un timer por pista.
 */
function sweep(): void {
    const cutoff = Date.now() - CACHE_TTL_MS;
    let removed = 0;

    let names: string[];
    try {
        names = readdirSync(AUDIO_CACHE_PATH);
    } catch {
        return; // la carpeta todavía no existe: no hay nada que barrer
    }

    for (const name of names) {
        const file = join(AUDIO_CACHE_PATH, name);

        try {
            if (statSync(file).mtimeMs > cutoff) continue;
            unlinkSync(file);
        } catch {
            // En Windows no se puede borrar un fichero que se está sirviendo, y uno a medio bajar
            // tampoco: se queda para el barrido siguiente.
            continue;
        }

        // Un id de YouTube no lleva puntos, así que lo que va delante del primero lo es, venga de
        // `<id>.webm`, `<id>.json` o `<id>.webm.part`.
        const [id] = name.split('.');
        if (id) cache.delete(id);

        removed++;
    }

    if (removed > 0) {
        log(`audio: ${removed} fichero(s) caducado(s) de cache/audio`, { resourceColor: chalk.yellow });
    }
}

/** Descargas en vuelo, por fichero: el segundo oyente espera a la primera en vez de repetirla. */
const inflight = new Map<string, Promise<void>>();

/**
 * Baja la pista entera UNA vez.
 *
 * Antes esto era un `fetch` a googlevideo **por petición**: cuarenta jugadores oyendo lo mismo eran
 * cuarenta bajadas además de cuarenta subidas, los mismos bytes cuarenta veces. Y de paso se va el
 * problema de la URL que caduca a mitad de canción, porque un fichero en disco no caduca — ni tiene
 * que rebufferar cuando alguien salta a otro segundo.
 *
 * Se escribe en `.part` y se renombra al acabar: es lo que impide servir un fichero a medias si el
 * relay se muere en mitad de la descarga.
 */
function download(info: Resolved, file: string): Promise<void> {
    const running = inflight.get(file);
    if (running) return running;

    const job = (async () => {
        log(`audio: bajando ${info.id} (${info.title})`, { resourceColor: chalk.yellow });

        // `Range: bytes=0-` pidiendo el fichero ENTERO no es redundante: googlevideo estrangula la
        // petición sin Range a la velocidad de reproducción (medido: 26 KB/s contra 5,5 MB/s con
        // ella, o sea 150×). Antes no se notaba porque el que pedía rangos era el CEF y por eso
        // llegaba a tiempo; bajándola de una, sin esto una canción de 4 min tardaría 2 min.
        const upstream = await fetch(info.url, {
            headers: { range: 'bytes=0-' },
            redirect: 'follow'
        });

        if (!upstream.ok || !upstream.body) {
            throw new Error(`googlevideo respondió ${upstream.status}`);
        }

        const part = `${file}.part`;
        await Bun.write(part, upstream);
        await rename(part, file);
    })().finally(() => inflight.delete(file));

    inflight.set(file, job);
    return job;
}

// ── Token ────────────────────────────────────────────────────────────────────────────────────
// Sin esto, el endpoint de streaming sería un proxy de YouTube gratis para cualquiera que viera
// una URL en el CEF. Firma el id y su caducidad con API_KEY, que ya es el secreto de la casa.
// ponytail: no hay límite de tasa, así que quien tenga un token válido puede tirar bytes sin tope.
// Si alguien abusa, una cuota por IP en este mismo handler.

function sign(id: string, expiry: number): string {
    return createHmac('sha256', API_CONFIG.apiKey || '')
        .update(`${id}.${expiry}`)
        .digest('base64url');
}

function verify(id: string, token: unknown): boolean {
    if (typeof token !== 'string') return false;

    const [rawExpiry, signature] = token.split('.');
    const expiry = Number(rawExpiry);

    if (!signature || !Number.isFinite(expiry) || expiry < Date.now()) return false;

    const expected = Buffer.from(sign(id, expiry));
    const given = Buffer.from(signature);

    return expected.length === given.length && timingSafeEqual(expected, given);
}

// ── Rutas ────────────────────────────────────────────────────────────────────────────────────

/**
 * Cabeceras que se copian tal cual de googlevideo: son las que hacen que el seek funcione. Solo las
 * necesita el camino del directo — lo que sale de disco lo cabecea Bun a partir del `Bun.file`.
 */
const PASSTHROUGH = ['content-type', 'content-length', 'content-range', 'accept-ranges'];

/** El cuerpo si viene en JSON, y `{}` si no: uno roto no tiene que tumbar la petición. */
const bodyOf = async (req: Request): Promise<Record<string, unknown>> =>
    await req.json().catch(() => ({})) as Record<string, unknown>;

async function handleResolve(req: Request): Promise<Response> {
    const body = await bodyOf(req);
    const id = videoIdFrom(String(body.url ?? new URL(req.url).searchParams.get('url') ?? ''));

    if (!id) {
        return Response.json({ error: 'url no es un vídeo de YouTube' }, { status: 400 });
    }

    try {
        const info = await resolve(id);
        const expiry = Date.now() + TOKEN_TTL_MS;

        return Response.json({
            id,
            title: info.title,
            duration: info.duration,
            isLive: info.isLive,
            abr: info.abr,
            // Solo el camino: la parte pública de la URL la pone el servidor de juego, que es
            // quien sabe por qué IP/dominio le llegan los jugadores (convar audio_public_url).
            path: `/api/audio/stream/${id}?t=${expiry}.${sign(id, expiry)}`
        });
    } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        log(`audio: no se pudo resolver ${id}: ${message}`, { resourceColor: chalk.red });
        return Response.json({ error: message }, { status: 502 });
    }
}

/**
 * Buscar por texto en YouTube, para no tener que pegar un link.
 *
 * Va con `--flat-playlist`: de cada resultado se queda lo que trae la página de búsqueda (id, título,
 * duración, canal) y NO se resuelven sus formatos, que es una llamada a googlevideo por vídeo. Del
 * elegido ya se encarga `/resolve` cuando el jugador lo pulse — resolver diez para tocar uno sería
 * pagar diez veces por nada.
 *
 * Pide la clave igual que el resolve: cada llamada arranca un yt-dlp, así que esto lo llama el
 * servidor de juego y nadie más.
 */
async function handleSearch(req: Request): Promise<Response> {
    const body = await bodyOf(req);
    const params = new URL(req.url).searchParams;
    const query = String(body.query ?? params.get('query') ?? '').trim().replace(/\s+/g, ' ');
    const limit = Math.min(SEARCH_MAX, Math.max(1, Math.floor(Number(body.limit) || SEARCH_MAX)));

    if (query.length < 2 || query.length > 100) {
        return Response.json({ error: 'la búsqueda está vacía o es demasiado larga' }, { status: 400 });
    }

    try {
        const info = await runYtDlp(['--flat-playlist', `ytsearch${limit}:${query}`], SEARCH_TIMEOUT_MS);

        const results: Found[] = (info?.entries ?? [])
            // Un resultado sin id de vídeo no se puede tocar (una playlist, un canal): fuera.
            .filter((entry: any) => VIDEO_ID.test(String(entry?.id ?? '')))
            .slice(0, limit)
            .map((entry: any) => ({
                id: String(entry.id),
                title: String(entry.title || entry.id),
                duration: Math.max(0, Math.round(Number(entry.duration) || 0)),
                channel: String(entry.channel || entry.uploader || '')
            }));

        return Response.json({ results });
    } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        log(`audio: no se pudo buscar "${query}": ${message}`, { resourceColor: chalk.red });
        return Response.json({ error: message }, { status: 502 });
    }
}

/**
 * Un directo, tal como viene: no tiene final, así que no hay nada que guardar en disco y se paga una
 * conexión con googlevideo por oyente.
 */
async function pipeUpstream(id: string, info: Resolved, req: Request): Promise<Response> {
    const range = req.headers.get('range');

    const upstream = await fetch(info.url, {
        headers: range ? { range } : undefined,
        redirect: 'follow',
        // Si el jugador se aleja y el CEF corta, hay que cortar también con googlevideo o el relay
        // se queda descargando una canción que ya nadie oye.
        signal: req.signal
    });

    if (!upstream.ok && upstream.status !== 206) {
        // Un 403 aquí suele ser una URL caducada que el `expire` no delató: se tira la caché
        // para que el siguiente intento re-resuelva de cero.
        cache.delete(id);
        return new Response(null, { status: 502 });
    }

    const headers = new Headers();
    for (const header of PASSTHROUGH) {
        const value = upstream.headers.get(header);
        if (value) headers.set(header, value);
    }

    return new Response(upstream.body, { status: upstream.status, headers });
}

async function handleStream(req: Request, id: string): Promise<Response> {
    if (!VIDEO_ID.test(id)) return new Response(null, { status: 400 });

    if (!verify(id, new URL(req.url).searchParams.get('t'))) {
        return new Response(null, { status: 403 });
    }

    try {
        const info = await resolve(id);

        if (info.isLive) return await pipeUpstream(id, info, req);

        const file = mediaPath(id, info.ext);

        if (!existsSync(file)) {
            try {
                await download(info, file);
            } catch (error: unknown) {
                // Casi siempre es la URL de googlevideo caducada sin que su `expire` lo dijera: se
                // tira la caché para que el siguiente intento re-resuelva de cero.
                cache.delete(id);
                const message = error instanceof Error ? error.message : String(error);
                log(`audio: no se pudo bajar ${id}: ${message}`, { resourceColor: chalk.red });
                return new Response(null, { status: 502 });
            }
        }

        // Aquí es el único punto donde la pista está SEGURO en disco —se acabe de bajar o estuviera
        // de antes—, así que es donde se deja su ficha: desde ahora esta canción no necesita YouTube.
        // Y por eso las que ya estaban bajadas de antes también acaban teniendo la suya.
        void remember(info);

        // El tipo se pone a mano (ver MIME). De lo demás —Range, 206, content-length, o sea lo que
        // necesita el seek de la sincronía— se encarga Bun al ver un `Bun.file` de cuerpo.
        return new Response(Bun.file(file), {
            headers: {
                'content-type': MIME[info.ext] ?? 'audio/webm',
                // Esta sí a mano: Bun no la manda en la respuesta completa, y es la que le dice al
                // `<audio>` que puede pedir trozos en vez de tragarse la canción entera.
                'accept-ranges': 'bytes'
            }
        });
    } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        log(`audio: fallo sirviendo ${id}: ${message}`, { resourceColor: chalk.red });
        return new Response(null, { status: 502 });
    }
}

/**
 * Puerto aparte del API de control a propósito: este tiene que estar abierto a los jugadores y
 * ese no.
 */
export function startAudioAPI() {
    mkdirSync(AUDIO_CACHE_PATH, { recursive: true });

    // Antes de servir nada: un relay que ha estado parado dos días arranca con la carpeta entera
    // caducada, y de ahí en adelante se mira sola.
    sweep();
    setInterval(sweep, SWEEP_EVERY_MS);

    // El resolve y la búsqueda piden la clave: los llama el servidor de juego, no el navegador de
    // nadie (y cada uno arranca un yt-dlp).
    const onlyServer = (handler: (req: Request) => Promise<Response>) => (req: Request) =>
        API_CONFIG.apiKey && req.headers.get('x-api-key') === API_CONFIG.apiKey
            ? handler(req)
            : Response.json({ error: 'Invalid API key' }, { status: 401 });

    const server = Bun.serve({
        port: AUDIO_CONFIG.port,
        // Sin `hostname`: este es el que tiene que salir de la máquina, que es de donde vienen los
        // CEF de los jugadores.
        //
        // Y con el techo de inactividad en vez de los 10 s por defecto de Bun: una pista que el
        // `<audio>` ya tiene buffereada deja el socket quieto mientras suena, y con los 10 s la
        // conexión se cortaba en medio (express no cerraba nunca, así que esto es lo que había).
        // 255 s es el máximo que acepta Bun.
        idleTimeout: 255,
        routes: {
            '/api/audio/resolve': { POST: onlyServer(handleResolve) },
            '/api/audio/search': { POST: onlyServer(handleSearch) },
            // El stream no puede pedir la clave (va en el src de un <audio>): le vale el token.
            '/api/audio/stream/:id': { GET: (req) => handleStream(req, req.params.id) }
        }
    });

    log(`🔊 Audio relay listening on port ${chalk.red(AUDIO_CONFIG.port)}`, {
        resourceColor: chalk.green,
        textColor: chalk.hex('#1abc9c')
    });

    return server;
}

// Arrancable a pelo con `bun scripts/core/audio.ts`. En producción FXServer no lo lanza el devkit,
// y el relay no necesita nada de él: solo `API_KEY` y `AUDIO_PORT` del .env, y yt-dlp en el PATH.
if (import.meta.main) startAudioAPI();

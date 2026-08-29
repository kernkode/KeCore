/**
 * El relay de audio: lo que convierte un link de YouTube en algo que el CEF de cada jugador
 * pueda tocar, y en una URL que no caduque.
 *
 * Por qué un relay y no la URL directa de googlevideo: esa URL caduca (~6 h), a veces viene
 * atada a la IP que la resolvió, y depende de que googlevideo mande cabeceras CORS — sin ellas
 * el `createMediaElementSource` del CEF sale mudo y no hay 3D ni filtro que aplicar. Sirviéndola
 * desde aquí, el cliente ve UNA URL estable, con Range (o sea, con seek para la sincronía) y sin
 * nada de CORS que negociar. Se paga en ancho de banda: ~130 kbps por oyente.
 *
 * OJO, esto queda expuesto a internet (los jugadores tienen que llegar). Por eso:
 *   - Escucha en su propio puerto, no en el del API de control (ese tiene /api/stop y
 *     /api/restart y no debería salir de la máquina).
 *   - Solo acepta IDs de vídeo de YouTube, así que no es un proxy HTTP abierto.
 *   - Cada URL lleva un token firmado con API_KEY: sin token no se sirve nada.
 *
 * Quien lo usa desde el juego es `kec.audio:resolve` (internal/server/audio.lua).
 */

import express, { type Express, type Request, type Response } from 'express';
import { spawn } from 'node:child_process';
import { createHmac, timingSafeEqual } from 'node:crypto';
import { Readable } from 'node:stream';
import chalk from 'chalk';
import { log } from './logger.ts';
import { API_CONFIG, AUDIO_CONFIG } from './configs.ts';

type Resolved = {
    id: string;
    title: string;
    duration: number;
    isLive: boolean;
    abr: number;
    url: string;
    /** Cuándo deja de valer la URL directa (ms epoch). */
    expiresAt: number;
};

/** Un id de vídeo de YouTube y nada más: es lo que impide que esto sea un proxy abierto. */
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;

/** Lo que vale un token de reproducción. Una pista en bucle en una disco dura toda la noche. */
const TOKEN_TTL_MS = 24 * 60 * 60 * 1000;

/** Margen antes de que caduque la URL de googlevideo, para no servir un 403 a medio segundo. */
const EXPIRY_MARGIN_MS = 60_000;

/** yt-dlp tarda 1-3 s de normal; más de esto es que algo se colgó. */
const RESOLVE_TIMEOUT_MS = 25_000;

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

/** Corre yt-dlp y devuelve su JSON. Se mata si tarda demasiado, para no dejar procesos colgados. */
function runYtDlp(id: string): Promise<any> {
    return new Promise((resolve, reject) => {
        const child = spawn('yt-dlp', [
            '--no-playlist',
            '--no-warnings',
            '--no-progress',
            '-J',
            `https://www.youtube.com/watch?v=${id}`
        ], { windowsHide: true });

        let out = '';
        let err = '';

        const timer = setTimeout(() => {
            child.kill();
            reject(new Error(`yt-dlp no respondió en ${RESOLVE_TIMEOUT_MS} ms`));
        }, RESOLVE_TIMEOUT_MS);

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

    const info = await runYtDlp(id);
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
        url: format.url,
        expiresAt
    };

    cache.set(id, resolved);
    return resolved;
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

/** Cabeceras que se copian tal cual de googlevideo: son las que hacen que el seek funcione. */
const PASSTHROUGH = ['content-type', 'content-length', 'content-range', 'accept-ranges'];

async function handleResolve(req: Request, res: Response): Promise<void> {
    const id = videoIdFrom(String(req.body?.url ?? req.query.url ?? ''));

    if (!id) {
        res.status(400).json({ error: 'url no es un vídeo de YouTube' });
        return;
    }

    try {
        const info = await resolve(id);
        const expiry = Date.now() + TOKEN_TTL_MS;

        res.json({
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
        res.status(502).json({ error: message });
    }
}

async function handleStream(req: Request, res: Response): Promise<void> {
    const id = String(req.params.id || '');

    if (!VIDEO_ID.test(id)) {
        res.status(400).end();
        return;
    }

    if (!verify(id, req.query.t)) {
        res.status(403).end();
        return;
    }

    try {
        const info = await resolve(id);
        const range = req.headers.range;

        const upstream = await fetch(info.url, {
            headers: range ? { range } : undefined,
            redirect: 'follow'
        });

        if (!upstream.ok && upstream.status !== 206) {
            // Un 403 aquí suele ser una URL caducada que el `expire` no delató: se tira la caché
            // para que el siguiente intento re-resuelva de cero.
            cache.delete(id);
            res.status(502).end();
            return;
        }

        for (const header of PASSTHROUGH) {
            const value = upstream.headers.get(header);
            if (value) res.setHeader(header, value);
        }

        res.status(upstream.status);

        if (!upstream.body) {
            res.end();
            return;
        }

        const body = Readable.fromWeb(upstream.body as any);
        // Si el jugador se aleja y el CEF corta, hay que cortar también con googlevideo o el
        // relay se queda descargando una canción que ya nadie oye.
        res.on('close', () => body.destroy());
        body.pipe(res);
    } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        log(`audio: fallo sirviendo ${id}: ${message}`, { resourceColor: chalk.red });
        if (!res.headersSent) res.status(502).end();
    }
}

/**
 * Puerto aparte del API de control a propósito: este tiene que estar abierto a los jugadores y
 * ese no.
 */
export async function startAudioAPI(): Promise<Express> {
    const app: Express = express();

    app.use(express.json());

    // El resolve pide la clave: lo llama el servidor de juego, no el navegador de nadie.
    app.post('/api/audio/resolve', (req, res, next) => {
        if (req.headers['x-api-key'] !== API_CONFIG.apiKey || !API_CONFIG.apiKey) {
            res.status(401).json({ error: 'Invalid API key' });
            return;
        }
        next();
    }, handleResolve);

    // El stream no puede pedirla (va en el src de un <audio>): lo que le vale es el token.
    app.get('/api/audio/stream/:id', handleStream);

    app.listen(AUDIO_CONFIG.port, () => {
        log(`🔊 Audio relay listening on port ${chalk.red(AUDIO_CONFIG.port)}`, {
            resourceColor: chalk.green,
            textColor: chalk.hex('#1abc9c')
        });
    });

    return app;
}

// Arrancable a pelo con `bun scripts/core/audio.ts`. En producción FXServer no lo lanza el devkit,
// y el relay no necesita nada de él: solo `API_KEY` y `AUDIO_PORT` del .env, y yt-dlp en el PATH.
if (import.meta.main) void startAudioAPI();

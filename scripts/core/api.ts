import chalk from 'chalk';
import { serverManager } from './serverManager.ts';
import { log } from './logger.ts';
import { API_CONFIG } from './configs.ts';

// --- Authentication ---

/**
 * Devuelve la respuesta con la que se corta la petición, o `null` si puede pasar.
 *
 * Sin CORS a propósito: esta API no la llama un navegador, la llaman herramientas (curl, el panel,
 * un cron). Un `Access-Control-Allow-Origin: *` en endpoints que paran y reinician el servidor es
 * justo lo que no quieres que pueda intentar una página cualquiera.
 */
function reject(req: Request): Response | null {
    if (!API_CONFIG.apiKey) {
        log('Error: API_KEY is not configured in the .env file', { resourceColor: chalk.red });
        return Response.json({ error: 'Incorrect API configuration' }, { status: 500 });
    }

    if (req.headers.get('x-api-key') !== API_CONFIG.apiKey) {
        return Response.json({ error: 'Invalid API key' }, { status: 401 });
    }

    return null;
}

type Handler = (req: Request) => Response | Promise<Response>;

/** Envuelve un handler para que solo se ejecute con la clave puesta. */
const withKey = (handler: Handler): Handler => (req) => reject(req) ?? handler(req);

/** Traduce una excepción del handler al 500 que ya devolvía la API. */
async function orError(what: string, handler: () => Promise<Response>): Promise<Response> {
    try {
        return await handler();
    } catch (error: unknown) {
        const message = error instanceof Error ? error.message : String(error);
        log(`Error in REST API (${what}): ${message}`, { resourceColor: chalk.red });
        return Response.json({ error: message }, { status: 500 });
    }
}

// --- Function to wait with timeout ---
async function waitWithTimeout(
    condition: () => Promise<boolean> | boolean,
    timeoutMs = 30000,
    checkInterval = 100
): Promise<boolean> {
    return new Promise((resolve, reject) => {
        const startTime = Date.now();
        let intervalId: NodeJS.Timeout;
        let timeoutId: NodeJS.Timeout;

        const cleanup = () => {
            clearInterval(intervalId);
            clearTimeout(timeoutId);
        };

        const checkCondition = async () => {
            try {
                if (await condition()) {
                    cleanup();
                    resolve(true);
                } else if (Date.now() - startTime > timeoutMs) {
                    cleanup();
                    resolve(false);
                }
            } catch (error) {
                cleanup();
                reject(error);
            }
        };

        intervalId = setInterval(checkCondition, checkInterval);
        timeoutId = setTimeout(() => {
            cleanup();
            resolve(false);
        }, timeoutMs);

        // Start the verification immediately
        checkCondition();
    });
}

// --- Start the API server ---
export function startRestAPI() {
    // A 127.0.0.1 y no a 0.0.0.0: aquí viven /api/stop y /api/restart, y con el bind por defecto
    // quedaban expuestos a la red entera con la API_KEY como única puerta. El relay de audio
    // (scripts/core/audio.ts) es el que SÍ tiene que salir de la máquina, y va en otro puerto
    // (ver el comentario de AUDIO_CONFIG en configs.ts).
    const server = Bun.serve({
        port: API_CONFIG.port,
        hostname: '127.0.0.1',
        // /api/restart contesta cuando el servidor ha vuelto a autenticarse: entre el `quit`, la
        // espera a que suelte los puertos y los 30 s de margen puede tardar más de un minuto sin
        // mandar un byte, y con los 10 s de inactividad por defecto de Bun el que llama se comía
        // una conexión cortada. 255 s es el máximo que acepta.
        idleTimeout: 255,
        routes: {
            '/api/status': {
                GET: withKey(() => Response.json({
                    status: 'online',
                    serverRunning: serverManager.isRunning(),
                    lastRestart: new Date().toISOString()
                }))
            },

            '/api/stop': {
                POST: withKey(() => orError('stop', async () => {
                    await serverManager.stop();
                    return Response.json({ success: true, message: 'Server stopped successfully' });
                }))
            },

            '/api/start': {
                POST: withKey(() => orError('start', async () => {
                    await serverManager.start();
                    return Response.json({ success: true, message: 'Server started successfully' });
                }))
            },

            '/api/restart': {
                POST: withKey((req) => orError('restart', async () => {
                    if (!serverManager.isAuthenticated()) {
                        return Response.json({ error: 'The server has not fully started.' }, { status: 400 });
                    }

                    const { reason } = await req.json().catch(() => ({})) as { reason?: string };
                    log(`Restart request received. Reason: ${reason || 'Scheduled restart'}`,
                        { resourceColor: chalk.yellow });

                    await serverManager.restart();

                    if (!await waitWithTimeout(() => serverManager.isAuthenticated())) {
                        log('Timeout: The server did not authenticate in 30 seconds', { resourceColor: chalk.red });
                        return Response.json({
                            error: 'Timeout: The server did not complete the restart in the expected time',
                            partialSuccess: true
                        }, { status: 408 });
                    }

                    return Response.json({ success: true, message: 'Server restarted successfully' });
                }))
            }
        }
    });

    log(`🌐 REST API listening on 127.0.0.1:${chalk.red(API_CONFIG.port)}`,
        { resourceColor: chalk.green, textColor: chalk.hex('#1abc9c') });

    return server;
}

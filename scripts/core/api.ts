import express, { Express, Request, Response, NextFunction } from 'express';
import bodyParser from 'body-parser';
import cors from 'cors';
import chalk from 'chalk';

import { serverManager } from './serverManager.ts';
import { log } from './logger.ts';
import { API_CONFIG } from './configs.ts';

// --- Tipos e Interfaces para mayor claridad ---

// Define la forma esperada del cuerpo de la solicitud para /restart
interface RestartRequestBody {
    reason?: string;
}

// --- Middleware de autenticación ---
function authenticate(req: Request, res: Response, next: NextFunction): void {
    const apiKey = req.headers['x-api-key'] as string;
    const ip = req.ip || req.socket.remoteAddress || '';
    const regex = /^::ffff:/;
    
    //const clientIP = regex.test(ip) ? ip.replace(regex, '') : ip;
    
    if (!API_CONFIG.apiKey) {
        log('Error: API_KEY no está configurada en el archivo .env', { resourceColor: chalk.red });
        res.status(500).json({ error: 'Configuración de API incorrecta' });
        return;
    }

    if (!apiKey || apiKey !== API_CONFIG.apiKey) {
        res.status(401).json({ error: 'API key inválida' });
        return;
    }
    
    next();
}

// --- Función para esperar con timeout ---
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

        // Iniciar la verificación inmediatamente
        checkCondition();
    });
}

// --- Iniciar el servidor API ---
export async function startRestAPI(): Promise<Express> {
    const app: Express = express();
    
    app.use(cors());
    app.use(bodyParser.json());

    // --- Endpoints ---

    app.get('/api/status', authenticate, (req: Request, res: Response) => {
        res.json({
            status: 'online',
            serverRunning: serverManager.isRunning(),
            lastRestart: new Date().toISOString()
        });
    });

    app.post('/api/stop', authenticate, async (req: Request, res: Response) => {
        try {
            await serverManager.stop();
            res.json({ success: true, message: 'Servidor detenido exitosamente' });
        } catch (error: unknown) {
            const message = error instanceof Error ? error.message : String(error);
            log(`Error en API REST (stop): ${message}`, { resourceColor: chalk.red });
            res.status(500).json({ error: message });
        }
    });

    app.post('/api/start', authenticate, async (req: Request, res: Response) => {
        try {
            await serverManager.start();
            res.json({ success: true, message: 'Servidor iniciado exitosamente' });
        } catch (error: unknown) {
            const message = error instanceof Error ? error.message : String(error);
            log(`Error en API REST (start): ${message}`, { resourceColor: chalk.red });
            res.status(500).json({ error: message });
        }
    });
    
    app.post('/api/restart', authenticate, async (req: Request<{}, {}, RestartRequestBody>, res: Response) => {
        if (!serverManager.isAutenticated()) {
            return res.status(400).json({ error: 'El servidor no ha arrancado por completo.' });
        }
        
        try {
            const reason = req.body?.reason || 'Reinicio programado';
            log(`Solicitud de reinicio recibida. Motivo: ${reason}`, { resourceColor: chalk.yellow });
            
            await serverManager.restart();

            const isAuthenticated = await waitWithTimeout(() => serverManager.isAutenticated());

            if (!isAuthenticated) {
                log('Timeout: El servidor no se autenticó en 30 segundos', { resourceColor: chalk.red });
                return res.status(408).json({ 
                    error: 'Timeout: El servidor no completó el reinicio en el tiempo esperado',
                    partialSuccess: true,
                });
            }

            res.json({ success: true, message: 'Servidor reiniciado exitosamente' });
        } catch (error: unknown) {
            const message = error instanceof Error ? error.message : String(error);
            log(`Error en API REST (restart): ${message}`, { resourceColor: chalk.red });
            res.status(500).json({ error: message });
        }
    });
    
    app.listen(API_CONFIG.port, () => {
        log(`🌐 API REST escuchando en puerto ${chalk.red(API_CONFIG.port)}`, { resourceColor: chalk.green, textColor: chalk.hex('#1abc9c') });
    });
    
    return app;
}
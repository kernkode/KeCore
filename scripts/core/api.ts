import express, { Express, Request, Response, NextFunction } from 'express';
import bodyParser from 'body-parser';
import cors from 'cors';
import chalk from 'chalk';

import { serverManager } from './serverManager.ts';
import { log } from './logger.ts';
import { API_CONFIG } from './configs.ts';

// --- Types and Interfaces for clarity ---

// Defines the expected shape of the request body for /restart
interface RestartRequestBody {
    reason?: string;
}

// --- Authentication Middleware ---
function authenticate(req: Request, res: Response, next: NextFunction): void {
    const apiKey = req.headers['x-api-key'] as string;
    const ip = req.ip || req.socket.remoteAddress || '';
    const regex = /^::ffff:/;
    
    //const clientIP = regex.test(ip) ? ip.replace(regex, '') : ip;
    
    if (!API_CONFIG.apiKey) {
        log('Error: API_KEY is not configured in the .env file', { resourceColor: chalk.red });
        res.status(500).json({ error: 'Incorrect API configuration' });
        return;
    }

    if (!apiKey || apiKey !== API_CONFIG.apiKey) {
        res.status(401).json({ error: 'Invalid API key' });
        return;
    }
    
    next();
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
            res.json({ success: true, message: 'Server stopped successfully' });
        } catch (error: unknown) {
            const message = error instanceof Error ? error.message : String(error);
            log(`Error in REST API (stop): ${message}`, { resourceColor: chalk.red });
            res.status(500).json({ error: message });
        }
    });

    app.post('/api/start', authenticate, async (req: Request, res: Response) => {
        try {
            await serverManager.start();
            res.json({ success: true, message: 'Server started successfully' });
        } catch (error: unknown) {
            const message = error instanceof Error ? error.message : String(error);
            log(`Error in REST API (start): ${message}`, { resourceColor: chalk.red });
            res.status(500).json({ error: message });
        }
    });
    
    app.post('/api/restart', authenticate, async (req: Request<{}, {}, RestartRequestBody>, res: Response) => {
        if (!serverManager.isAutenticated()) {
            return res.status(400).json({ error: 'The server has not fully started.' });
        }
        
        try {
            const reason = req.body?.reason || 'Scheduled restart';
            log(`Restart request received. Reason: ${reason}`, { resourceColor: chalk.yellow });
            
            await serverManager.restart();

            const isAuthenticated = await waitWithTimeout(() => serverManager.isAutenticated());

            if (!isAuthenticated) {
                log('Timeout: The server did not authenticate in 30 seconds', { resourceColor: chalk.red });
                return res.status(408).json({ 
                    error: 'Timeout: The server did not complete the restart in the expected time',
                    partialSuccess: true,
                });
            }

            res.json({ success: true, message: 'Server restarted successfully' });
        } catch (error: unknown) {
            const message = error instanceof Error ? error.message : String(error);
            log(`Error in REST API (restart): ${message}`, { resourceColor: chalk.red });
            res.status(500).json({ error: message });
        }
    });
    
    app.listen(API_CONFIG.port, () => {
        log(`🌐 REST API listening on port ${chalk.red(API_CONFIG.port)}`, { resourceColor: chalk.green, textColor: chalk.hex('#1abc9c') });
    });
    
    return app;
}
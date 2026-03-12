import path from 'path';
import fs from 'fs';
import fkill from 'fkill';
import chalk from 'chalk';
import { spawn, ChildProcess, exec } from 'child_process';
import { LRUCache } from 'lru-cache';
import { log, writeToLog, clearLogFile } from './logger.ts';
import { CWD, FXSERVER_EXECUTABLE } from './configs.ts';
import net from 'net';

// Definir interfaces para los contextos de esbuild
interface EsbuildContext {
    dispose(): Promise<void>;
}

export const esbuildContexts = new Map<string, EsbuildContext>(); // Caché para contextos de esbuild
export const resourceRootCache = new LRUCache<string, any>({ max: 500 }); // Limitar a 500 entradas
export const pendingRestarts = new Set<string>();
// Cache para el archivo de configuración
const configCache = new Map<string, string>();

// Verifica si un puerto está en uso
async function isPortInUse(port: string | number): Promise<boolean> {
    const portNumber = typeof port === 'string' ? parseInt(port) : port;
    return new Promise((resolve) => {
        const tester = net.createServer()
            .once('error', () => resolve(true))
            .once('listening', () => {
                tester.once('close', () => resolve(false)).close();
            })
            .listen(portNumber);
    });
}

class ServerManager {
    public childProcess: ChildProcess | null = null;
    private isShuttingDown: boolean = false;
    private Authenticated: boolean = false;
    private tcp_port: string;
    private udp_port: string;

    constructor() {
        const tcpEndpoint = String(process.env.ENDPOINT_TCP || '');
        const udpEndpoint = String(process.env.ENDPOINT_UDP || '');
        
        this.tcp_port = tcpEndpoint.split(':')[1] || '30120';
        this.udp_port = udpEndpoint.split(':')[1] || '30120';
    }

    isRunning(): boolean {
        return this.childProcess !== null && !this.childProcess.killed;
    }

    isAutenticated(): boolean {
        return this.Authenticated;
    }

    isUsingTxAdmin(): boolean {
        return process.env.USE_TXADMIN === 'true';
    }

    async start(): Promise<void> {
        try {
            await clearLogFile();
        } catch (error: any) {
            log(`Error clearing log file: ${error.message}`, { resourceColor: chalk.red });
        }
    
        if (this.childProcess) {
            log("Deteniendo servidor anterior...");
            await fkill(this.childProcess.pid!, { force: true, silent: true }).catch(() => {});
        }
    
        log("Iniciando FXServer...", { textColor: chalk.hex('#1abc9c') });
    
        const SERVER_CFG_PATH = path.resolve('server.cfg');
        try {
            fs.accessSync(FXSERVER_EXECUTABLE);
            fs.accessSync(SERVER_CFG_PATH);
            
            const useTxAdmin = this.isUsingTxAdmin()
            const commonArgs = ['+exec', 'server.cfg', '+set', 'onesync', 'on'];

            const spawnArgs = useTxAdmin ? [] : [...commonArgs];

            this.childProcess = spawn(FXSERVER_EXECUTABLE, spawnArgs, {
                cwd: CWD,
                stdio: ['pipe', 'pipe', 'pipe'],
                shell: false,
                windowsHide: true,
            });
    
            this.childProcess.stdout?.on('data', (data: Buffer) => {
                process.stdout.write(data);
                writeToLog(data.toString());

                const text = "Authenticated with cfx.re Nucleus";
                if(data.includes(text)){
                    this.Authenticated = true;
                }
            });
    
            this.childProcess.stderr?.on('data', (data: Buffer) => {
                process.stderr.write(chalk.red(`[FXSERVER_ERROR] ${data}`));
                writeToLog(data.toString());
            });
    
            this.childProcess.on('close', (code: number | null) => {
                log(`Servidor cerrado (codigo ${code})`, { resourceColor: chalk.red });
                writeToLog(String(code));
            });
    
            this.childProcess.on('error', (err: Error) => {
                log(`Error al iniciar el servidor: ${err.message}`, { resourceColor: chalk.red });
                writeToLog(err.message);
                process.exit(1);
            });
    
        } catch (error: any) {
            if (error.path === FXSERVER_EXECUTABLE) {
                log(`FXServer no encontrado en: ${FXSERVER_EXECUTABLE}`, { resourceColor: chalk.red });
            } else {
                log(`server.cfg no encontrado en: ${SERVER_CFG_PATH}`, { resourceColor: chalk.red });
            }
            process.exit(1);
        }
    }

    async stop(): Promise<void> {
        if (this.childProcess && this.childProcess.pid) {
            log("Deteniendo servidor...", { resourceColor: chalk.hex('#1abc9c') });
            await fkill(this.childProcess.pid, { force: true, silent: true }).catch(() => {});
        }
    }
    
    /** Envía un comando a la consola de FXServer. */
    async sendCommand(command: string): Promise<void> {
        if (!this.isRunning() || !this.childProcess?.stdin) return;
        process.stdout.write(chalk.gray(`>> ${command}\n`));
        this.childProcess.stdin.write(`${command}\n`);
        console.log("comando ejecutado");
    }

    async restart(): Promise<void> {
        log("Iniciando reinicio completo del servidor...", { resourceColor: chalk.yellow });

        // 1. Detener el servidor actual de manera más robusta
        if (this.isRunning()) {
            try {
                this.Authenticated = false;
                log("Enviando comando 'quit' al servidor...", { resourceColor: chalk.yellow });
                await this.sendCommand('quit');

                // Esperar con timeout mejorado
                const exitPromise = new Promise<void>((resolve) => {
                    if (this.childProcess) {
                        this.childProcess.once('exit', () => resolve());
                    } else {
                        resolve();
                    }
                });

                await Promise.race([
                    exitPromise,
                    new Promise<void>((_, reject) => 
                        setTimeout(() => reject(new Error('Timeout al detener el servidor')), 15000))
                ]);

            } catch (error: any) {
                log(`Error al detener normalmente: ${error.message}`, { resourceColor: chalk.yellow });
                
                // Fuerza el cierre de todos los procesos relacionados
                try {
                    log("Forzando cierre de procesos...", { resourceColor: chalk.yellow });
                    if (this.childProcess?.pid) {
                        await fkill(this.childProcess.pid, { force: true, silent: true });
                    }
                    await fkill(FXSERVER_EXECUTABLE, { force: true, silent: true });
                    
                    // Limpieza adicional para Windows
                    if (process.platform === "win32") {
                        await fkill('FXServer.exe', { force: true, silent: true });
                    }
                } catch (killError: any) {
                    log(`Error al forzar cierre: ${killError.message}`, { resourceColor: chalk.red });
                }
            } finally {
                this.childProcess = null;
            }
        }

        // 2. Esperar liberación de puertos y recursos
        const PORT_CHECK_INTERVAL = 1000;
        const MAX_WAIT_TIME = 30000; // 30 segundos máximo
        let elapsed = 0;
        
        log("Verificando estado del puerto...", { resourceColor: chalk.yellow });
        
        while (elapsed < MAX_WAIT_TIME) {
            const tcpInUse = await isPortInUse(this.tcp_port);
            const udpInUse = await isPortInUse(this.udp_port);
            
            if (!tcpInUse && !udpInUse) {
                break;
            }
            
            await new Promise(resolve => setTimeout(resolve, PORT_CHECK_INTERVAL));
            elapsed += PORT_CHECK_INTERVAL;
            log(`Esperando liberación del puerto... (${elapsed/1000}s)`, { resourceColor: chalk.yellow });
        }

        if (elapsed >= MAX_WAIT_TIME) {
            log("Advertencia: No se pudo liberar el puerto después de 30 segundos", { resourceColor: chalk.yellow });
        }

        // 3. Limpiar caches y contextos
        log("Limpiando cachés...", { resourceColor: chalk.yellow });
        const disposePromises = Array.from(esbuildContexts.values()).map(ctx => ctx.dispose());
        await Promise.all(disposePromises);
        esbuildContexts.clear();
        resourceRootCache.clear();

        // 4. Pequeña espera adicional para asegurar liberación
        await new Promise(resolve => setTimeout(resolve, 2000));

        // 5. Reiniciar el servidor
        try {
            await this.start();
            log("Servidor reiniciado exitosamente", { resourceColor: chalk.green });
        } catch (error: any) {
            log(`Error crítico al reiniciar: ${error.message}`, { resourceColor: chalk.red });
            throw error;
        }
    }

    /** Cierra la aplicación de forma segura. */
    async shutdown(): Promise<void> {
        if (this.isShuttingDown) return;
        this.isShuttingDown = true;
        log("Cerrando servicios...");
    
        const disposePromises = Array.from(esbuildContexts.values()).map(ctx => ctx.dispose());
        await Promise.all(disposePromises);
        log("Contextos de compilacion limpiados.", { resourceColor: chalk.yellow });
    
        if (this.isRunning() && this.childProcess?.pid) {
            await fkill(this.childProcess.pid, { force: true, silent: true });
            log("Proceso del servidor terminado.", { resourceColor: chalk.yellow });
        }
        process.exit(0);
    }

    /** Reinicia un recurso en el servidor. */
    async restartResource(resourceName: string): Promise<void> {
        if (pendingRestarts.has(resourceName)) return;
        pendingRestarts.add(resourceName);
        
        try {
            log(`Reiniciando...`, { resourceName, resourceColor: chalk.yellow });
            await this.sendCommand(`ensure ${resourceName}`);
        } finally {
            pendingRestarts.delete(resourceName);
        }
    }

    editConfig(name: string, value: string): void {
        const serverCfgPath = path.resolve('server.cfg');
        
        try {
            // 1. Obtener datos (Cache o Disco)
            let data: string;
            if (configCache.has(serverCfgPath)) {
                data = configCache.get(serverCfgPath)!;
            } else {
                if (!fs.existsSync(serverCfgPath)) {
                    log(`server.cfg no encontrado en: ${serverCfgPath}`, { resourceColor: chalk.red });
                    return;
                }
                data = fs.readFileSync(serverCfgPath, 'utf8');
                configCache.set(serverCfgPath, data);
            }
            
            // 2. Crear Expresión Regular
            // Explicación del Regex:
            // ^          -> Inicio de línea (gracias al flag 'm')
            // (\s*)      -> Grupo 1: Captura indentación (espacios/tabs) antes del nombre
            // ${name}    -> El nombre del parámetro exacto
            // (?:\s+|$)  -> Debe haber un espacio después del nombre O fin de línea (evita falsos positivos como 'set' vs 'sets')
            // .* -> El resto de la línea (el valor antiguo)
            const regex = new RegExp(`^(\\s*)${name}(?:\\s+|$).*`, 'm');
            
            let newData: string;

            if (regex.test(data)) {
                // 3. CASO A: El parámetro YA EXISTE -> Reemplazar
                // $1 mantiene la indentación original
                newData = data.replace(regex, `$1${name} ${value}`);
            } else {
                // 4. CASO B: El parámetro NO EXISTE -> Agregar al final
                // Asegurar que haya un salto de línea antes de agregar
                const prefix = data.endsWith('\n') ? '' : '\n';
                newData = `${data}${prefix}${name} ${value}\n`;
            }
            
            // 5. Guardar solo si hubo cambios
            if (newData !== data) {
                fs.writeFileSync(serverCfgPath, newData, 'utf8');
                configCache.set(serverCfgPath, newData); // Actualizar caché
                // Opcional: Loguear el cambio
                // log(`Config ${name} actualizada a ${value}`, { resourceColor: chalk.cyan });
            }
            
        } catch (err: any) {
            console.error('Error al editar server.cfg:', err);
            configCache.delete(serverCfgPath); // Invalidar caché en caso de error
        }
    }
}

export const serverManager = new ServerManager();
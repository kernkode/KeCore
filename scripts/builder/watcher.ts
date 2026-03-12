import chokidar from 'chokidar';
import chalk from 'chalk';
import type { FSWatcher } from 'chokidar';
import { RESOURCES_PATH, CHOKIDAR_OPTIONS } from '../core/configs.ts';
import { log } from '../core/logger.ts';
import { buildManager } from './build-manager.ts';

class Watcher {
    private watcher: FSWatcher;

    constructor() {
        this.watcher = chokidar.watch(RESOURCES_PATH, CHOKIDAR_OPTIONS);
    }

    start(): void {
        log("Configurando watcher para cambios...");

        this.watcher
            .on('change', (filePath: string) => {
                buildManager.handleFileChange(filePath).catch((error: Error) => {
                    console.error('Error handling file change:', error);
                });
            })
            .on('error', (err: unknown | any) => {
                log(`Error en Watcher: ${err.message}`, { textColor: chalk.red });
            });

        log("Entorno listo. Servidor corriendo y watchers activos.");
    }

    close(): Promise<void> {
        if (this.watcher) {
            return this.watcher.close();
        }
        return Promise.resolve();
    }
}

export const watcher = new Watcher();
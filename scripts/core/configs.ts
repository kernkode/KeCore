import dotenv from 'dotenv';
import path from 'path';

// Carga las variables de entorno desde .env
export const environment = dotenv.config({ quiet: true });

// Interfaz para la configuración de la API
interface ApiConfig {
    port: number;
    apiKey: string | undefined;
}

// Configuración de la API
export const API_CONFIG: ApiConfig = {
    port: parseInt(process.env.API_PORT || '49152'),
    apiKey: process.env.API_KEY, // La clave ahora viene del entorno
};

import type { BuildOptions } from 'esbuild';

export const ESBUILD_OPTIONS: BuildOptions = {
    bundle: true,
    platform: 'node',
    target: 'es2020',
    format: 'cjs',
    logLevel: 'error',
    sourcemap: false,
    minify: false,
    treeShaking: true,
    define: {
        '__dirname': '"./"' // Define __dirname si es necesario
    }
};

// Interfaz para las opciones de chokidar
interface ChokidarOptions {
    ignored: (RegExp | string)[];
    persistent: boolean;
    ignoreInitial: boolean;
    awaitWriteFinish: {
        stabilityThreshold: number;
        pollInterval: number;
    };
}

export const CHOKIDAR_OPTIONS: ChokidarOptions = {
    ignored: [
        /(^|[\/\\])\../, // Archivos dotfiles
        /node_modules/,
        /\.git/,
        /dist[\/\\]/,
        /\.(sw[px]|~|tmp|log)$/ // Archivos temporales/swap
    ],
    persistent: true,
    ignoreInitial: true,
    awaitWriteFinish: { stabilityThreshold: 0, pollInterval: 0 },
};

export const CWD: string = process.cwd();
export const RESOURCES_PATH: string = path.resolve('resources');
export const FXSERVER_EXECUTABLE: string = path.resolve('artifacts', process.platform === "win32" ? 'FXServer.exe' : 'FXServer');
export const INITIAL_BUILD_CONCURRENCY: number = 4;
export const LOG_FILE_PATH: string = path.resolve('cache', 'log.txt');
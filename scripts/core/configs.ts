import path from "path";

// El .env lo carga Bun solo, así que aquí no hay nada que inicializar: lo que falte se nota en la
// comprobación de variables obligatorias de scripts/start.ts.

// Interfaz para la configuración de la API
interface ApiConfig {
  port: number;
  apiKey: string | undefined;
}

// Configuración de la API
export const API_CONFIG: ApiConfig = {
  port: parseInt(process.env.API_PORT || "49152"),
  apiKey: process.env.API_KEY, // La clave ahora viene del entorno
};

// El relay de audio (scripts/core/audio.ts) escucha en SU puerto y no en el del API de control:
// este tiene que estar abierto a los jugadores para que sus CEF puedan tirar del stream, y el de
// control (con /api/stop y /api/restart) no debería salir de la máquina.
export const AUDIO_CONFIG = {
  port: parseInt(process.env.AUDIO_PORT || "30122"),
};

import type { BuildOptions } from "esbuild";

export const ESBUILD_OPTIONS: BuildOptions = {
  bundle: true,
  platform: "node",
  target: "es2020",
  format: "iife",
  logLevel: "error",
  sourcemap: false,
  minify: false,
  treeShaking: true,
  define: {
    __dirname: '"./"', // Define __dirname si es necesario
  },
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
    /\.(sw[px]|~|tmp|log)$/, // Archivos temporales/swap
  ],
  persistent: true,
  ignoreInitial: true,
  awaitWriteFinish: { stabilityThreshold: 0, pollInterval: 0 },
};

export const CWD: string = process.cwd();
export const RESOURCES_PATH: string = path.resolve("resources");
// FiveM para GTAV Enhanced (FXSERVER="enhanced") reparte el servidor como `cfx-server`, no como
// `FXServer`. La edición se decide con el .env y no mirando qué hay en artifacts/: al cambiarla el
// updater borra el directorio, así que solo puede haber un binario.
// ponytail: en Linux las dos ediciones vienen en proot (artifacts/alpine/opt/cfx-server/<bin>) y el
// arranque real es artifacts/run.sh; aquí se apunta al binario suelto, como se hacía ya.
const SERVER_EXE: string =
  process.env.FXSERVER === "enhanced"
    ? (process.platform === "win32" ? "cfx-server.exe" : "cfx-server")
    : (process.platform === "win32" ? "FXServer.exe" : "FXServer");
export const FXSERVER_EXECUTABLE: string = path.resolve("artifacts", SERVER_EXE);
export const LOG_FILE_PATH: string = path.resolve("cache", "log.txt");
// Donde el relay de audio guarda las pistas ya bajadas: UNA descarga por pista, no una por oyente.
export const AUDIO_CACHE_PATH: string = path.resolve("cache", "audio");

import * as cheerio from 'cheerio';
import path from 'path';
import { execSync } from 'child_process';
import sevenZip from '7zip-min';
import chalk from 'chalk';
import { log } from '../core/logger.ts';
import { existsSync, readFileSync, writeFileSync, mkdirSync, rmSync, unlinkSync } from 'fs';

// Cfx publica dos empaquetados del servidor: el de siempre (FiveM/RedM), que sale del listado de
// artifacts, y el de FiveM para GTAV Enhanced, con otro binario (cfx-server) y otra descarga.
const SERVER_EXES: string[] = process.platform === 'win32'
    ? ['FXServer.exe', 'cfx-server.exe']
    : ['FXServer', 'cfx-server'];

const LEGACY_CHANNEL = process.platform === 'win32' ? 'build_server_windows' : 'build_proot_linux';
const LEGACY_BASE_URL = `https://runtime.fivem.net/artifacts/fivem/${LEGACY_CHANNEL}/master/`;

// Enhanced no tiene listado de artifacts ni API de versiones: la única fuente pública de la build
// vigente es la página de descargas de los docs, que la lleva dentro del JSON de Next.js
// (#__NEXT_DATA__ → props.pageProps.enhanced). Si Cfx cambia esa página hay que volver a mirar
// ahí; no hay endpoint estable al que apuntar. Los ficheros salen de downloads.cfx-services.net
// con un UUID opaco y distinto por fichero, así que la URL tampoco se puede construir a mano.
const ENHANCED_TARGET = 'enhanced';
const ENHANCED_PAGE_URL = 'https://docs.fivem.net/docs/server-download/';
const ENHANCED_OS = process.platform === 'win32' ? 'windows' : 'linux';

// Rutas absolutas a propósito: en Bun 1.4 sobre Windows `rmSync` con una ruta relativa no borra
// nada y tampoco lanza, así que la limpieza al cambiar de edición se quedaba en el log.
const OUTPUT_DIR = path.resolve('artifacts');
// El archivo se baja fuera de artifacts/ porque al cambiar de edición ese directorio se borra.
const DOWNLOAD_DIR = path.resolve('cache');
const CACHE_FILE = path.resolve(OUTPUT_DIR, '.fxserver_version');

/** Objetivos que acepta `FXSERVER` en el .env y `bun run update <target>`. */
export const isValidTarget = (target: string): boolean =>
    ['latest', 'recommended', ENHANCED_TARGET].includes(target) || /^\d+$/.test(target);

const isEnhancedId = (id: string): boolean => id.startsWith(`${ENHANCED_TARGET}-`);

/** Número de build de una identidad, sea `35245-<hash>/server.7z` o `enhanced-139`. */
const versionOf = (id: string): string => id.split('-')[isEnhancedId(id) ? 1 : 0];

/** Cómo se le muestra una build al usuario: `35245` la legacy, `enhanced 139` la de Enhanced. */
const labelOf = (id: string): string => isEnhancedId(id) ? `enhanced ${versionOf(id)}` : versionOf(id);

export interface VersionInfo {
    /** Identidad exacta de la build: es lo que se guarda en .fxserver_version. */
    id: string;
    version: string;
    url: string;
    fileName: string;
}

export interface UpdateInfo {
    available: boolean;
    current?: string | null;
    latest?: string | null;
    currentVersion?: string;
    latestVersion?: string;
    message?: string;
    versionTransition?: string;
}

/**
 * El HTML de una página. Se comprueba el estado a mano porque `fetch` no lanza con un 4xx/5xx, y
 * una página de error se parsea igual de bien que la buena: el fallo saldría luego, sin decir dónde.
 */
async function fetchText(url: string): Promise<string> {
    const response = await fetch(url);
    if (!response.ok) throw new Error(`${url} respondió ${response.status}`);
    return response.text();
}

/** La build de Enhanced vigente, sacada del JSON que la página de descargas trae embebido. */
async function resolveEnhanced(): Promise<VersionInfo | null> {
    const $ = cheerio.load(await fetchText(ENHANCED_PAGE_URL));
    const nextData = JSON.parse($('#__NEXT_DATA__').text() || '{}');
    const builds = nextData?.props?.pageProps?.enhanced?.[ENHANCED_OS];
    const build = Array.isArray(builds) ? builds[0] : null; // la primera es la más reciente

    if (!build?.downloadURL) return null;

    // El número de build viene en el subtítulo ("build 139") y es lo único comparable entre dos
    // descargas: el UUID de la URL cambia por fichero y no dice nada del orden.
    const version = String(build.subtitle ?? '').match(/\d+/)?.[0];
    if (!version) return null;

    return {
        id: `${ENHANCED_TARGET}-${version}`,
        version,
        url: build.downloadURL,
        fileName: build.displayName || path.basename(new URL(build.downloadURL).pathname),
    };
}

/** La build pedida de la legacy: el href del listado ya viene como `<version>-<hash>/<fichero>`. */
async function resolveLegacy(updateTarget: string): Promise<VersionInfo | null> {
    const $ = cheerio.load(await fetchText(LEGACY_BASE_URL));

    let href: string | undefined;

    if (updateTarget === 'latest') {
        href = $('.panel-block.is-active').attr('href');
    } else if (updateTarget === 'recommended') {
        // El botón "LATEST RECOMMENDED" es el único <a> que cuelga de un .panel-block.
        href = $('.panel-block a').first().attr('href');
    } else {
        $('.panel').find('a').each((_, elem) => {
            const candidate = $(elem).attr('href');
            if (candidate?.replace('./', '').split('-')[0] !== updateTarget) return;
            href = candidate;
            return false; // corta el each
        });
    }

    if (!href) return null;

    const id = href.replace('./', '');
    return { id, version: id.split('-')[0], url: `${LEGACY_BASE_URL}${id}`, fileName: path.basename(id) };
}

/** Resuelve la build a instalar para el objetivo pedido, sea de la edición que sea. */
function resolveVersion(updateTarget: string): Promise<VersionInfo | null> {
    return updateTarget === ENHANCED_TARGET ? resolveEnhanced() : resolveLegacy(updateTarget);
}

export function isFXServerRunning(): boolean {
    // Se miran los binarios de las dos ediciones: el que estorba para actualizar es el que esté
    // corriendo, no el de la edición que se va a instalar.
    return SERVER_EXES.some(exe => {
        try {
            const command = process.platform === 'win32'
                ? `tasklist /FI "IMAGENAME eq ${exe}"`
                : `ps aux | grep ${exe} | grep -v grep`;
            return execSync(command).toString().includes(exe);
        } catch {
            // `grep` sin coincidencias sale con código 1 y execSync lanza: eso es que no corre.
            return false;
        }
    });
}

// Función para guardar la versión en caché
export function cacheVersion(version: string): void {
    try {
        writeFileSync(CACHE_FILE, version, 'utf-8');
    } catch (error: any) {
        console.error('Error guardando caché de versión:', error.message);
    }
}

// Función para leer la versión almacenada en caché
export function getCachedVersion(): string | null {
    try {
        if (existsSync(CACHE_FILE)) {
            return readFileSync(CACHE_FILE, 'utf-8').trim();
        }
        return null;
    } catch (error: any) {
        console.error('Error leyendo caché de versión:', error.message);
        return null;
    }
}

export async function isAvailableUpdate(updateTarget: string = 'latest'): Promise<UpdateInfo> {
    // Una versión clavada a mano (FXSERVER="35245") no se toca: solo se comprueban los objetivos
    // que siguen a un canal.
    if (!['latest', 'recommended', ENHANCED_TARGET].includes(updateTarget)) {
        return { available: false };
    }

    try {
        const currentVersion = getCachedVersion();

        // Si no hay versión instalada, siempre hay "actualización disponible"
        if (!currentVersion) {
            return {
                available: true,
                current: null,
                latest: null,
                message: 'No hay versión instalada. Se requiere instalación completa.'
            };
        }

        const latestVersionInfo = await resolveVersion(updateTarget);

        if (!latestVersionInfo) {
            return {
                available: false,
                current: currentVersion,
                latest: null,
                message: 'No se pudo obtener información de versión disponible'
            };
        }

        // Se comparan las identidades completas y no los números: entre ediciones no son
        // comparables (build 139 de Enhanced contra 35245 de la legacy) y cambiar de edición
        // también es algo que hay que descargar.
        const isUpdateAvailable = currentVersion !== latestVersionInfo.id;
        const transition = `${labelOf(currentVersion)} → ${labelOf(latestVersionInfo.id)}`;

        return {
            available: isUpdateAvailable,
            current: currentVersion,
            latest: latestVersionInfo.id,
            currentVersion: labelOf(currentVersion),
            latestVersion: labelOf(latestVersionInfo.id),
            message: isUpdateAvailable
                ? `Actualización disponible: ${transition}`
                : `Ya tienes la versión más reciente (${labelOf(currentVersion)})`,
            versionTransition: transition
        };

    } catch (error: any) {
        console.error('Error verificando actualizaciones:', error.message);
        return {
            available: false,
            current: getCachedVersion(),
            latest: null,
            message: `Error al verificar actualizaciones: ${error.message}`
        };
    }
}

export async function downloadAndExtractFXServer(updateTarget: string = 'latest'): Promise<void> {
    try {
        // Verificar si FXServer está en ejecución
        if (isFXServerRunning()) {
            console.error('Error: FXServer está actualmente en ejecución.');
            console.error('Por favor, cierra FXServer antes de intentar actualizar.');
            return;
        }

        const build = await resolveVersion(updateTarget);
        if (!build) {
            throw new Error(`Update target not found: ${updateTarget}`);
        }

        // Verificar si ya tenemos esta versión
        const cachedVersion = getCachedVersion();
        if (cachedVersion === build.id) {
            log(`Ya tienes instalada la versión ${updateTarget} (${labelOf(build.id)})`, { resourceName: 'scripts:updater' });
            return;
        }

        log(`[↓] Descargando FXServer ${updateTarget} (versión ${chalk.bold.hex('#89F336')(build.version)})...`, { resourceName: 'scripts:updater' });

        mkdirSync(DOWNLOAD_DIR, { recursive: true });
        const archivePath = path.resolve(DOWNLOAD_DIR, build.fileName);

        const response = await fetch(build.url);
        if (!response.ok) throw new Error(`la descarga respondió ${response.status}`);
        await Bun.write(archivePath, response);

        log('FXServer descargado correctamente.', { resourceName: 'scripts:updater' });
        log('Descomprimiendo archivo...', { resourceName: 'scripts:updater' });

        // Cambiar de edición no es actualizar: la legacy trae citizen/ y la de Enhanced
        // coreclr_server/ + system_resources/, así que extraer una encima de la otra deja los
        // ficheros de la anterior por medio (los dos binarios incluidos). Se limpia y se extrae
        // sobre un directorio vacío.
        if (cachedVersion && isEnhancedId(cachedVersion) !== isEnhancedId(build.id)) {
            log('Cambio de edición: limpiando artifacts/ antes de extraer.', { resourceName: 'scripts:updater' });
            rmSync(OUTPUT_DIR, { recursive: true, force: true });
        }
        mkdirSync(OUTPUT_DIR, { recursive: true });

        await sevenZip.unpack(archivePath, OUTPUT_DIR);

        // El .tar.xz de Linux necesita dos pasadas: la primera deja el .tar dentro de artifacts/.
        if (build.fileName.endsWith('.tar.xz')) {
            const tarPath = path.resolve(OUTPUT_DIR, build.fileName.slice(0, -'.xz'.length));
            if (existsSync(tarPath)) {
                await sevenZip.unpack(tarPath, OUTPUT_DIR);
                unlinkSync(tarPath);
            }
        }

        log('Descompresión completada.', { resourceName: 'scripts:updater' });

        // Eliminar el archivo descargado y guardar en caché
        unlinkSync(archivePath);
        cacheVersion(build.id);
        log(`Versión ${labelOf(build.id)} instalada correctamente.`, { resourceName: 'scripts:updater' });

    } catch (error: any) {
        console.error('Error en el proceso:', error.message);
        throw error;
    }
}

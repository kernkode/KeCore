import axios from 'axios';
import * as cheerio from 'cheerio';
import path from 'path';
import { execSync } from 'child_process';
import { pipeline } from 'stream/promises';
import sevenZip from '7zip-min';
import chalk from 'chalk';
import { log } from '../core/logger.ts';
import { existsSync, readFileSync, writeFileSync, mkdirSync, createWriteStream, unlinkSync } from 'fs';

const FXSERVER_EXE = process.platform === "win32" ? 'FXServer.exe' : 'FXServer';
const UpdateChannel = process.platform === "win32" ? 'build_server_windows' : 'build_proot_linux';
const FXSERVER_BASE_URL = 'https://runtime.fivem.net/artifacts/fivem/' + UpdateChannel + '/master/';
const OUTPUT_DIR = './artifacts';
const CACHE_FILE = path.resolve(OUTPUT_DIR, '.fxserver_version');

export async function getUUID(updateTarget: string = 'latest'): Promise<string> {
    try {
        const response = await axios.get(FXSERVER_BASE_URL);
        const $ = cheerio.load(response.data);
        
        let UUID: string | null = null;

        if (updateTarget === 'latest') {
            const href = $('.panel-block.is-active').attr('href');
            if (href) {
                UUID = href.replace('./', '');
            }
        } else if (updateTarget === 'recommended') {
            const href = $('.panel-block a').attr('href');
            if (href) {
                UUID = href.replace('./', '');
            }
        } else {
            $('.panel').find('a').each((i, elem) => {
                const href = $(elem).attr('href');
                if (href) {
                    const VersionNumber = href.replace('./', '').split('-')[0];
                    if (VersionNumber === updateTarget) {
                        UUID = href.replace('./', '');
                        return false; // Break the loop
                    }
                }
            });
        }

        if (!UUID) {
            throw new Error(`Update target not found: ${updateTarget}`);
        }

        return UUID;
    } catch (error: any) {
        console.error('Error al obtener UUID:', error.message);
        throw error;
    }
}

export function isFXServerRunning(): boolean {
    try {
        if (process.platform === "win32") {
            // Para Windows
            const command = `tasklist /FI "IMAGENAME eq ${FXSERVER_EXE}"`;
            const output = execSync(command).toString();
            return output.includes(FXSERVER_EXE);
        } else {
            // Para Linux/macOS
            const command = `ps aux | grep ${FXSERVER_EXE} | grep -v grep`;
            const output = execSync(command).toString();
            return output.includes(FXSERVER_EXE);
        }
    } catch (error: any) {
        console.error('Error al verificar procesos:', error.message);
        return false;
    }
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

export interface UpdateInfo {
    available: boolean;
    current?: string | null;
    latest?: string | null;
    currentVersion?: string;
    latestVersion?: string;
    message?: string;
    versionTransition?: string;
}

export interface VersionInfo {
    uuid: string;
    version: string;
    changelog?: string;
    date?: string | null;
    url: string;
}

export async function isAvailableUpdate(updateTarget: string = 'latest'): Promise<UpdateInfo> {
    if (updateTarget !== "latest" && updateTarget !== "recommended") {
        return { available: false };
    }

    try {
        // Obtener la versión actual en caché
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

        // Obtener la versión más reciente disponible
        const latestVersionInfo = await getVersionInfo(updateTarget);
        
        if (!latestVersionInfo) {
            return {
                available: false,
                current: currentVersion,
                latest: null,
                message: 'No se pudo obtener información de versión disponible'
            };
        }

        const currentVersionNumber = currentVersion.split('-')[0];
        const latestVersionNumber = latestVersionInfo.uuid.split('-')[0];

        // Comparar versiones
        const isUpdateAvailable = parseInt(latestVersionNumber) !== parseInt(currentVersionNumber);

        return {
            available: isUpdateAvailable,
            current: currentVersion,
            latest: latestVersionInfo.uuid,
            currentVersion: currentVersionNumber,
            latestVersion: latestVersionNumber,
            message: isUpdateAvailable 
                ? `Actualización disponible: ${currentVersionNumber} → ${latestVersionNumber}`
                : `Ya tienes la versión más reciente (${currentVersionNumber})`,
            versionTransition: `${currentVersionNumber} → ${latestVersionNumber}`
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

        // Obtener el UUID de la versión solicitada
        const DownloadInternalID = await getUUID(updateTarget);
        const versionNumber = DownloadInternalID.split('-')[0];

        // Verificar si ya tenemos esta versión
        const cachedVersion = getCachedVersion();
        if (cachedVersion === DownloadInternalID) {
            log(`Ya tienes instalada la versión ${updateTarget} (${versionNumber})`, { resourceName: 'scripts:updater' });
            return;
        }

        log(`[↓] Descargando FXServer ${updateTarget} (versión ${chalk.bold.hex('#89F336')(versionNumber)})...`, { resourceName: 'scripts:updater' });

        // Crear directorio si no existe
        mkdirSync(OUTPUT_DIR, { recursive: true });

        const downloadUrl = `${FXSERVER_BASE_URL}${DownloadInternalID}`;
        const sevenZPath = path.resolve(OUTPUT_DIR, 'fxserver.7z');

        // Descargar el archivo
        const response = await axios({
            method: 'get',
            url: downloadUrl,
            responseType: 'stream',
        });

        const writer = createWriteStream(sevenZPath);
        await pipeline(response.data, writer);

        log('FXServer descargado correctamente.', { resourceName: 'scripts:updater' });
        log('Descomprimiendo archivo...', { resourceName: 'scripts:updater' });

        // Descomprimir el archivo
        await new Promise<void>((resolve, reject) => {
            sevenZip.unpack(sevenZPath, OUTPUT_DIR, (err: any) => {
                if (err) {
                    console.error('Error al descomprimir:', err);
                    reject(err);
                    return;
                }
                log('Descompresión completada.', { resourceName: 'scripts:updater' });
                resolve();
            });
        });

        // Eliminar el archivo .7z y guardar en caché
        unlinkSync(sevenZPath);
        cacheVersion(DownloadInternalID);
        log(`Versión ${versionNumber} instalada correctamente.`, { resourceName: 'scripts:updater' });

    } catch (error: any) {
        console.error('Error en el proceso:', error.message);
        throw error;
    }
}

// Función auxiliar para obtener información de versión
async function getVersionInfo(updateTarget: string = 'latest'): Promise<VersionInfo | null> {
    try {
        const response = await axios.get(FXSERVER_BASE_URL);
        const $ = cheerio.load(response.data);
        
        let uuid: string | null = null;
        let changelog: string | undefined = undefined;
        let date: string | null = null;

        if (updateTarget === 'latest') {
            const latestElement = $('.panel-block.is-active');
            const href = latestElement.attr('href');
            if (href) {
                uuid = href.replace('./', '');
            }
            changelog = latestElement.find('.changelog-data').text().trim();
            date = latestElement.find('time').attr('datetime') || null;
        } else if (updateTarget === 'recommended') {
            const recommendedElement = $('.panel-block a').first();
            const href = recommendedElement.attr('href');
            if (href) {
                uuid = href.replace('./', '');
            }
            changelog = recommendedElement.find('.changelog-data').text().trim();
            date = recommendedElement.find('time').attr('datetime') || null;
        } else {
            $('.panel').find('a').each((i, elem) => {
                const href = $(elem).attr('href');
                if (href) {
                    const versionNumber = href.replace('./', '').split('-')[0];
                    if (versionNumber === updateTarget) {
                        uuid = href.replace('./', '');
                        changelog = $(elem).find('.changelog-data').text().trim();
                        date = $(elem).find('time').attr('datetime') || null;
                        return false; // Break the loop
                    }
                }
            });
        }

        if (!uuid) {
            return null;
        }

        return {
            uuid,
            version: uuid.split('-')[0],
            changelog,
            date,
            url: `${FXSERVER_BASE_URL}${uuid}`
        };

    } catch (error: any) {
        console.error('Error obteniendo información de versión:', error.message);
        return null;
    }
}
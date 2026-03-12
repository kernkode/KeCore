import axios, { AxiosInstance, AxiosResponse } from 'axios';
import path from 'path';
import fs from 'fs';
import fsp from 'fs/promises';
import crypto from 'crypto';
import { promisify } from 'util';
import { pipeline } from 'stream';
import chalk from 'chalk';

const pipelineAsync = promisify(pipeline);

const GITHUB_USER = 'kernkode';
const GITHUB_REPO = 'next.js'; // Cambia esto al repo real de tu framework si es necesario
const FOLDER_PATH = 'resources/[framework]/kecore';
const DEST_PATH = './kecore';

const CACHE_DIR = './cache';
const CACHE_FILE = path.join(CACHE_DIR, 'github_downloader_cache.json');

// Interfaces para los tipos de datos
interface GitHubContentItem {
    name: string;
    path: string;
    type: 'file' | 'dir';
    download_url: string | null;
}

interface Cache {
    _lastCommitSha?: string; // Guardamos el hash del último commit de la carpeta
    [key: string]: string | undefined;
}

// Configuración de axios para el contenido
const apiClient: AxiosInstance = axios.create({
    baseURL: `https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents/`,
    headers: { 
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Node.js GitHub Downloader' 
    },
    timeout: 30000
});

// Obtener el SHA del último commit de una carpeta específica
async function getLatestFolderCommit(user: string, repo: string, folderPath: string): Promise<string | null> {
    try {
        const url = `https://api.github.com/repos/${user}/${repo}/commits`;
        const response = await axios.get(url, {
            params: {
                path: folderPath,
                per_page: 1
            },
            headers: {
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'Node.js GitHub Downloader'
            }
        });

        if (response.data && response.data.length > 0) {
            return response.data[0].sha;
        }
        return null;
    } catch (error: any) {
        console.error(chalk.red(`Error verificando la versión en GitHub: ${error.message}`));
        return null;
    }
}

// Función para generar hash
async function generateHash(content: Buffer): Promise<string> {
    return crypto.createHash('sha256').update(content).digest('hex');
}

// Cargar caché
async function loadCache(): Promise<Cache> {
    try {
        await fsp.mkdir(CACHE_DIR, { recursive: true });
        const cacheData = await fsp.readFile(CACHE_FILE, 'utf-8');
        return JSON.parse(cacheData) as Cache;
    } catch (error: any) {
        if (error.code !== 'ENOENT') {
            console.error(chalk.red(`Error cargando caché: ${error.message}`));
        }
        return {};
    }
}

// Guardar caché
async function saveCache(cache: Cache): Promise<void> {
    try {
        await fsp.writeFile(CACHE_FILE, JSON.stringify(cache, null, 2));
    } catch (error: any) {
        console.error(chalk.red(`Error guardando caché: ${error.message}`));
    }
}

// Descargar archivo con streaming
async function downloadFile(url: string, filePath: string): Promise<void> {
    const response = await axios({
        url,
        method: 'GET',
        responseType: 'stream'
    });
    
    const writer = fs.createWriteStream(filePath);
    await pipelineAsync(response.data, writer);
}

// Función principal para descargar la carpeta
async function downloadGitHubFolder(
    user: string, 
    repo: string, 
    folderPath: string, 
    destPath: string, 
    cache: Cache
): Promise<void> {
    try {
        const response: AxiosResponse<GitHubContentItem[]> = await apiClient.get(folderPath);
        await fsp.mkdir(destPath, { recursive: true });

        // Procesar archivos en paralelo
        const downloadPromises = response.data.map(async (item: GitHubContentItem) => {
            const itemPath = path.join(destPath, item.name);
            const cacheKey = `${user}/${repo}/${item.path}`;
            
            if (item.type === 'file') {
                try {
                    // Verificar caché individual por si un archivo fue modificado localmente
                    if (cache[cacheKey]) {
                        try {
                            const existingContent = await fsp.readFile(itemPath);
                            const existingHash = await generateHash(existingContent);
                            
                            if (cache[cacheKey] === existingHash) {
                                console.log(chalk.gray(`- [CACHÉ] Archivo intacto: ${item.path}`));
                                return;
                            }
                        } catch (error) {
                            // El archivo no existe, continuar con descarga
                        }
                    }

                    if (!item.download_url) {
                        console.error(chalk.red(`No hay URL de descarga para: ${item.path}`));
                        return;
                    }

                    console.log(chalk.blue(`- Descargando: ${item.path}`));
                    await downloadFile(item.download_url, itemPath);
                    const fileContent = await fsp.readFile(itemPath);
                    cache[cacheKey] = await generateHash(fileContent);
                    
                } catch (error: any) {
                    console.error(chalk.red(`Error procesando ${item.path}: ${error.message}`));
                }
            } else if (item.type === 'dir') {
                console.log(chalk.green(`- Accediendo al directorio: ${item.path}`));
                await downloadGitHubFolder(user, repo, item.path, itemPath, cache);
            }
        });

        await Promise.all(downloadPromises);
        
    } catch (error: any) {
        console.error(chalk.red(`Error procesando ${folderPath}: ${error.message}`));
    }
}

// Función principal
async function main(): Promise<void> {
    console.time(chalk.yellow('Tiempo total de ejecución'));
    
    try {
        console.log(chalk.cyan('Cargando caché local...'));
        const cache = await loadCache();
        
        console.log(chalk.cyan('Verificando última versión en GitHub...'));
        const latestCommit = await getLatestFolderCommit(GITHUB_USER, GITHUB_REPO, FOLDER_PATH);

        if (latestCommit) {
            if (cache['_lastCommitSha'] === latestCommit) {
                console.log(chalk.green.bold('✅ El framework ya está en la última versión. No se requieren descargas.'));
                return; // Salimos de la ejecución porque ya está actualizado
            }
            console.log(chalk.yellow(`Nueva versión detectada (${latestCommit.substring(0, 7)}). Actualizando...`));
        } else {
            console.log(chalk.yellow('No se pudo verificar la versión global, forzando revisión archivo por archivo...'));
        }
        
        console.log(chalk.cyan(`Iniciando escaneo y descarga de: ${FOLDER_PATH}`));
        await downloadGitHubFolder(GITHUB_USER, GITHUB_REPO, FOLDER_PATH, DEST_PATH, cache);
        
        // Guardamos el nuevo SHA una vez que la descarga se haya completado
        if (latestCommit) {
            cache['_lastCommitSha'] = latestCommit;
        }

        console.log(chalk.cyan('Guardando caché...'));
        await saveCache(cache);
        
        console.log(chalk.green.bold('🚀 ¡Proceso completado con éxito!'));
    } catch (err: any) {
        console.error(chalk.red.bold('Error en el proceso principal:'), chalk.red(err));
    } finally {
        console.timeEnd(chalk.yellow('Tiempo total de ejecución'));
    }
}

main().catch(err => console.error(chalk.red.bold('Error no manejado:'), chalk.red(err)));
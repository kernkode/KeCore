import axios, { AxiosInstance, AxiosResponse } from 'axios';
import path from 'path';
import fs from 'fs';
import fsp from 'fs/promises';
import crypto from 'crypto';
import { promisify } from 'util';
import { pipeline } from 'stream';
import chalk from 'chalk';

const pipelineAsync = promisify(pipeline);

const GITHUB_USER = 'vercel';
const GITHUB_REPO = 'next.js';
const FOLDER_PATH = 'examples/basic-css';
const DEST_PATH = './nextjs-basic-css';

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
    [key: string]: string;
}

// Configuración de axios
const apiClient: AxiosInstance = axios.create({
    baseURL: `https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents/`,
    headers: { 
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Node.js GitHub Downloader' 
    },
    timeout: 30000
});

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
        await fsp.writeFile(CACHE_FILE, JSON.stringify(cache));
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
                    // Verificar caché
                    if (cache[cacheKey]) {
                        try {
                            const existingContent = await fsp.readFile(itemPath);
                            const existingHash = await generateHash(existingContent);
                            
                            if (cache[cacheKey] === existingHash) {
                                console.log(chalk.gray(`- [CACHÉ] Archivo actual: ${item.path}`));
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
                console.log(chalk.green(`- Creando directorio: ${item.path}`));
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
        console.log(chalk.cyan('Cargando caché...'));
        const cache = await loadCache();
        
        console.log(chalk.cyan(`Iniciando descarga de: ${FOLDER_PATH}`));
        await downloadGitHubFolder(GITHUB_USER, GITHUB_REPO, FOLDER_PATH, DEST_PATH, cache);
        
        console.log(chalk.cyan('Guardando caché...'));
        await saveCache(cache);
        
        console.log(chalk.green.bold('¡Proceso completado con éxito!'));
    } catch (err: any) {
        console.error(chalk.red.bold('Error en el proceso principal:'), chalk.red(err));
    } finally {
        console.timeEnd(chalk.yellow('Tiempo total de ejecución'));
    }
}

main().catch(err => console.error(chalk.red.bold('Error no manejado:'), chalk.red(err)));
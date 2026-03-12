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
const GITHUB_REPO = 'KeCore'; 
const FOLDER_PATH = 'resources/[framework]/kecore';
const DEST_PATH = './resources/[framework]';

// Interfaz actualizada para incluir el 'sha' que nos da GitHub
interface GitHubContentItem {
    name: string;
    path: string;
    type: 'file' | 'dir';
    download_url: string | null;
    sha: string; // Hash nativo de Git para este archivo
}

const apiClient: AxiosInstance = axios.create({
    baseURL: `https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/contents/`,
    headers: { 
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Node.js GitHub Downloader' 
    },
    timeout: 30000
});

// Función CLAVE: Calcula el hash del archivo local exactamente como lo hace Git/GitHub
function generateGitSha(content: Buffer): string {
    const header = `blob ${content.length}\0`;
    const store = Buffer.concat([Buffer.from(header, 'utf8'), content]);
    return crypto.createHash('sha1').update(store).digest('hex');
}

async function downloadFile(url: string, filePath: string): Promise<void> {
    const response = await axios({
        url,
        method: 'GET',
        responseType: 'stream'
    });
    
    const writer = fs.createWriteStream(filePath);
    await pipelineAsync(response.data, writer);
}

// Función para explorar y comparar carpetas
async function downloadGitHubFolder(
    user: string, 
    repo: string, 
    folderPath: string, 
    destPath: string
): Promise<void> {
    try {
        const response: AxiosResponse<GitHubContentItem[]> = await apiClient.get(folderPath);
        await fsp.mkdir(destPath, { recursive: true });

        // Procesar archivos en paralelo
        const downloadPromises = response.data.map(async (item: GitHubContentItem) => {
            const itemPath = path.join(destPath, item.name);
            
            if (item.type === 'file') {
                try {
                    // 1. Intentamos leer el archivo local
                    const existingContent = await fsp.readFile(itemPath);
                    // 2. Calculamos su Git SHA
                    const localSha = generateGitSha(existingContent);
                    
                    // 3. Comparamos local vs remoto
                    if (localSha === item.sha) {
                        console.log(chalk.gray(`- [INTACTO] ${item.path}`));
                        return; // Es idéntico, saltamos la descarga
                    } else {
                        console.log(chalk.yellow(`- [ACTUALIZANDO] ${item.path} (Modificado o desactualizado)`));
                    }
                } catch (error: any) {
                    if (error.code === 'ENOENT') {
                        console.log(chalk.magenta(`- [FALTANTE] ${item.path} (No existe localmente)`));
                    } else {
                        console.log(chalk.red(`- Error leyendo ${item.path}: ${error.message}`));
                    }
                }

                if (!item.download_url) {
                    console.error(chalk.red(`No hay URL de descarga para: ${item.path}`));
                    return;
                }

                // Si llegamos aquí, el archivo falta o es diferente, así que lo descargamos
                console.log(chalk.blue(`  ↳ Descargando: ${item.path}`));
                await downloadFile(item.download_url, itemPath);
                
            } else if (item.type === 'dir') {
                console.log(chalk.green(`- Accediendo al directorio: ${item.path}`));
                await downloadGitHubFolder(user, repo, item.path, itemPath);
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
        console.log(chalk.cyan(`Iniciando escaneo y sincronización inteligente de: ${FOLDER_PATH}`));
        // Ya no necesitamos el chequeo de commit global que bloqueaba todo,
        // ahora el script validará archivo por archivo súper rápido.
        
        await downloadGitHubFolder(GITHUB_USER, GITHUB_REPO, FOLDER_PATH, DEST_PATH);
        
        console.log(chalk.green.bold('🚀 ¡Sincronización completada con éxito!'));
    } catch (err: any) {
        console.error(chalk.red.bold('Error en el proceso principal:'), chalk.red(err));
    } finally {
        console.timeEnd(chalk.yellow('Tiempo total de ejecución'));
    }
}

main().catch(err => console.error(chalk.red.bold('Error no manejado:'), chalk.red(err)));
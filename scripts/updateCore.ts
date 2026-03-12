import axios, { AxiosInstance, AxiosResponse } from 'axios';
import path from 'path';
import fs from 'fs';
import fsp from 'fs/promises';
import { promisify } from 'util';
import { pipeline } from 'stream';
import chalk from 'chalk';

const pipelineAsync = promisify(pipeline);

const GITHUB_USER = 'kernkode';
const GITHUB_REPO = 'KeCore';
const FOLDER_PATH = 'resources/[framework]/kecore';
const DEST_PATH = './resources/[framework]/kecore';
const BRANCH = 'main'; // Cambia si usas otra rama

// ─── Tipos ───────────────────────────────────────────────
interface TreeItem {
    path: string;
    mode: string;
    type: 'blob' | 'tree';
    sha: string;
    size?: number;
    url: string;
}

interface TreeResponse {
    sha: string;
    tree: TreeItem[];
    truncated: boolean;
}

interface FileInfo {
    remotePath: string;   // path relativo dentro del repo
    localPath: string;    // path en disco
    sha: string;
    size: number;
    downloadUrl: string;
}

// ─── Cliente API ─────────────────────────────────────────
const apiClient: AxiosInstance = axios.create({
    baseURL: `https://api.github.com/repos/${GITHUB_USER}/${GITHUB_REPO}/`,
    headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Node.js GitHub Downloader'
    },
    timeout: 30000
});

async function getLocalGitSha(filePath: string): Promise<string | null> {
    try {
        let content = await fsp.readFile(filePath);
        
        // NORMALIZACIÓN: Convertir saltos de línea de Windows (CRLF) a Unix (LF)
        // Esto es necesario porque GitHub calcula el SHA usando LF.
        const contentStr = content.toString('utf8');
        const normalizedContentStr = contentStr.replace(/\r\n/g, '\n');
        
        // Volvemos a convertir a Buffer para calcular el hash correcto
        content = Buffer.from(normalizedContentStr, 'utf8');

        const header = `blob ${content.length}\0`;
        const store = Buffer.concat([Buffer.from(header), content]);
        return require('crypto').createHash('sha1').update(store).digest('hex');
    } catch (error: any) {
        if (error.code === 'ENOENT') return null; // No existe
        throw error;
    }
}

// ─── Obtener TODO el árbol en UNA sola petición ──────────
async function getFullTree(): Promise<TreeItem[]> {
    console.log(chalk.cyan('🌳 Obteniendo árbol completo del repositorio (1 sola petición)...\n'));

    const response: AxiosResponse<TreeResponse> = await apiClient.get(
        `git/trees/${BRANCH}?recursive=1`
    );

    if (response.data.truncated) {
        console.log(chalk.yellow('⚠️  El árbol está truncado (repo muy grande). Algunos archivos podrían faltar.'));
    }

    return response.data.tree;
}

// ─── Filtrar solo los archivos de la carpeta objetivo ────
function filterTreeToFolder(tree: TreeItem[], folderPath: string): FileInfo[] {
    const prefix = folderPath.endsWith('/') ? folderPath : folderPath + '/';

    return tree
        .filter(item => item.type === 'blob' && item.path.startsWith(prefix))
        .map(item => {
            // Path relativo a la carpeta destino
            const relativePath = item.path.substring(prefix.length);

            return {
                remotePath: item.path,
                localPath: path.join(DEST_PATH, relativePath),
                sha: item.sha,
                size: item.size || 0,
                downloadUrl: `https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/${item.path}`
            };
        });
}

// ─── Descargar archivo con stream ────────────────────────
async function downloadFile(url: string, filePath: string): Promise<void> {
    // Crear directorio padre si no existe
    await fsp.mkdir(path.dirname(filePath), { recursive: true });

    const response = await axios({
        url,
        method: 'GET',
        responseType: 'stream'
    });

    const writer = fs.createWriteStream(filePath);
    await pipelineAsync(response.data, writer);
}

// ─── Procesar cada archivo ───────────────────────────────
async function processFile(file: FileInfo): Promise<'intact' | 'updated' | 'new'> {
    const localSha = await getLocalGitSha(file.localPath);

    // Archivo no existe localmente
    if (localSha === null) {
        console.log(chalk.magenta(`  📥 [NUEVO]         ${file.remotePath}`));
        await downloadFile(file.downloadUrl, file.localPath);
        return 'new';
    }

    // Comparar SHA (exactamente como lo hace Git)
    if (localSha === file.sha) {
        console.log(chalk.gray(`  ✅ [INTACTO]       ${file.remotePath}`));
        return 'intact';
    }

    // SHA diferente → actualizar
    console.log(chalk.yellow(`  🔄 [ACTUALIZANDO]  ${file.remotePath}`));
    await downloadFile(file.downloadUrl, file.localPath);
    return 'updated';
}

// ─── Main ────────────────────────────────────────────────
async function main(): Promise<void> {
    console.time(chalk.yellow('⏱️  Tiempo total'));

    try {
        console.log(chalk.cyan.bold(`
╔═══════════════════════════════════════════════╗
║  📦 Sincronización Inteligente de KeCore       ║
║  🔍 Comparando por SHA de Git (1 petición API) ║
╚═══════════════════════════════════════════════╝
        `));

        // ① UNA sola petición para obtener todo el árbol
        const fullTree = await getFullTree();

        // ② Filtrar solo los archivos de nuestra carpeta
        const files = filterTreeToFolder(fullTree, FOLDER_PATH);

        if (files.length === 0) {
            console.log(chalk.red(`❌ No se encontraron archivos en: ${FOLDER_PATH}`));
            return;
        }

        console.log(chalk.cyan(`📂 ${files.length} archivos encontrados en ${FOLDER_PATH}\n`));

        // ③ Crear directorios necesarios
        const dirs = new Set(files.map(f => path.dirname(f.localPath)));
        await Promise.all([...dirs].map(dir => fsp.mkdir(dir, { recursive: true })));

        // ④ Procesar todos los archivos en paralelo (con límite de concurrencia)
        const CONCURRENCY = 10;
        const stats = { intact: 0, updated: 0, new: 0 };

        for (let i = 0; i < files.length; i += CONCURRENCY) {
            const batch = files.slice(i, i + CONCURRENCY);
            const results = await Promise.all(batch.map(file => processFile(file)));

            for (const result of results) {
                stats[result]++;
            }
        }

        // ⑤ Resumen
        console.log(chalk.green.bold(`
╔═══════════════════════════════════════════════╗
║  🚀 ¡Sincronización completada!                ║
╠═══════════════════════════════════════════════╣
║  ✅ Intactos:     ${String(stats.intact).padStart(4)}                        ║
║  🔄 Actualizados: ${String(stats.updated).padStart(4)}                        ║
║  📥 Nuevos:       ${String(stats.new).padStart(4)}                        ║
║  📊 Total:        ${String(files.length).padStart(4)}                        ║
╚═══════════════════════════════════════════════╝
        `));

    } catch (err: any) {
        console.error(chalk.red.bold('Error:'), chalk.red(err.message));
    } finally {
        console.timeEnd(chalk.yellow('⏱️  Tiempo total'));
    }
}

main().catch(err => console.error(chalk.red.bold('Error no manejado:'), chalk.red(err)));

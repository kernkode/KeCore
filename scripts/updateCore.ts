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
const BRANCH = 'main';

// ─── CONFIGURACIÓN DE DIRECTORIOS ───────────────────────
// Agrega o quita carpetas aquí fácilmente
interface SyncFolder {
    remote: string;  // Path en el repo de GitHub
    local: string;   // Path destino en disco
}

const SYNC_FOLDERS: SyncFolder[] = [
    {
        remote: 'resources/[framework]/kecore',
        local: './resources/[framework]/kecore'
    },
    {
        remote: 'scripts',
        local: './scripts'
    },
    // Agrega más carpetas aquí:
    // {
    //     remote: 'resources/[standalone]/otro-recurso',
    //     local: './resources/[standalone]/otro-recurso'
    // },
];

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
    remotePath: string;
    localPath: string;
    sha: string;
    size: number;
    downloadUrl: string;
}

interface SyncStats {
    intact: number;
    updated: number;
    new: number;
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

// ─── SHA local (algoritmo de Git) ────────────────────────
async function getLocalGitSha(filePath: string): Promise<string | null> {
    try {
        let content = await fsp.readFile(filePath);

        // Normalizar CRLF → LF (GitHub usa LF)
        const contentStr = content.toString('utf8');
        const normalizedContentStr = contentStr.replace(/\r\n/g, '\n');
        content = Buffer.from(normalizedContentStr, 'utf8');

        const header = `blob ${content.length}\0`;
        const store = Buffer.concat([Buffer.from(header), content]);
        return crypto.createHash('sha1').update(store).digest('hex');
    } catch (error: any) {
        if (error.code === 'ENOENT') return null;
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
        console.log(chalk.yellow('⚠️  Árbol truncado (repo muy grande). Algunos archivos podrían faltar.'));
    }

    return response.data.tree;
}

// ─── Filtrar archivos para UNA carpeta ───────────────────
function filterTreeToFolder(tree: TreeItem[], folder: SyncFolder): FileInfo[] {
    const prefix = folder.remote.endsWith('/') ? folder.remote : folder.remote + '/';

    return tree
        .filter(item => item.type === 'blob' && item.path.startsWith(prefix))
        .map(item => {
            const relativePath = item.path.substring(prefix.length);

            return {
                remotePath: item.path,
                localPath: path.join(folder.local, relativePath),
                sha: item.sha,
                size: item.size || 0,
                downloadUrl: `https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}/${item.path}`
            };
        });
}

// ─── Descargar archivo ───────────────────────────────────
async function downloadFile(url: string, filePath: string): Promise<void> {
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

    if (localSha === null) {
        console.log(chalk.magenta(`    📥 [NUEVO]         ${file.remotePath}`));
        await downloadFile(file.downloadUrl, file.localPath);
        return 'new';
    }

    if (localSha === file.sha) {
        console.log(chalk.gray(`    ✅ [INTACTO]       ${file.remotePath}`));
        return 'intact';
    }

    console.log(chalk.yellow(`    🔄 [ACTUALIZANDO]  ${file.remotePath}`));
    await downloadFile(file.downloadUrl, file.localPath);
    return 'updated';
}

// ─── Procesar UNA carpeta ────────────────────────────────
async function syncFolder(
    tree: TreeItem[],
    folder: SyncFolder,
    concurrency: number
): Promise<SyncStats> {
    const files = filterTreeToFolder(tree, folder);
    const stats: SyncStats = { intact: 0, updated: 0, new: 0 };

    if (files.length === 0) {
        console.log(chalk.red(`  ❌ No se encontraron archivos en: ${folder.remote}\n`));
        return stats;
    }

    console.log(chalk.cyan(`  📂 ${files.length} archivos encontrados\n`));

    // Crear directorios necesarios
    const dirs = new Set(files.map(f => path.dirname(f.localPath)));
    await Promise.all([...dirs].map(dir => fsp.mkdir(dir, { recursive: true })));

    // Procesar en batches
    for (let i = 0; i < files.length; i += concurrency) {
        const batch = files.slice(i, i + concurrency);
        const results = await Promise.all(batch.map(file => processFile(file)));

        for (const result of results) {
            stats[result]++;
        }
    }

    return stats;
}

// ─── Main ────────────────────────────────────────────────
async function main(): Promise<void> {
    console.time(chalk.yellow('⏱️  Tiempo total'));

    try {
        const folderList = SYNC_FOLDERS.map(f => f.remote).join(', ');

        console.log(chalk.cyan.bold(`
╔════════════════════════════════════════════════════╗
║  📦 Sincronización Inteligente de KeCore            ║
║  🔍 Comparando por SHA de Git (1 petición API)      ║
║  📁 Carpetas: ${folderList.padEnd(36)}║
╚════════════════════════════════════════════════════╝
        `));

        // ① UNA sola petición para obtener todo el árbol
        const fullTree = await getFullTree();

        const CONCURRENCY = 10;
        const totalStats: SyncStats = { intact: 0, updated: 0, new: 0 };
        let totalFiles = 0;

        // ② Iterar cada carpeta usando el MISMO árbol
        for (const folder of SYNC_FOLDERS) {
            console.log(chalk.blue.bold(`\n┌─ 📁 ${folder.remote}`));
            console.log(chalk.blue(`│  → ${folder.local}`));

            const folderStats = await syncFolder(fullTree, folder, CONCURRENCY);

            // Acumular stats globales
            totalStats.intact += folderStats.intact;
            totalStats.updated += folderStats.updated;
            totalStats.new += folderStats.new;

            const folderTotal = folderStats.intact + folderStats.updated + folderStats.new;
            totalFiles += folderTotal;

            console.log(chalk.blue(`│`));
            console.log(chalk.blue(`└─ ✅ ${folderStats.intact} intactos | 🔄 ${folderStats.updated} actualizados | 📥 ${folderStats.new} nuevos`));
        }

        // ③ Resumen global
        console.log(chalk.green.bold(`
╔════════════════════════════════════════════════════╗
║  🚀 ¡Sincronización completada!                     ║
╠════════════════════════════════════════════════════╣
║  📁 Carpetas:      ${String(SYNC_FOLDERS.length).padStart(4)}                           ║
║  ✅ Intactos:      ${String(totalStats.intact).padStart(4)}                           ║
║  🔄 Actualizados:  ${String(totalStats.updated).padStart(4)}                           ║
║  📥 Nuevos:        ${String(totalStats.new).padStart(4)}                           ║
║  📊 Total:         ${String(totalFiles).padStart(4)}                           ║
╚════════════════════════════════════════════════════╝
        `));

    } catch (err: any) {
        console.error(chalk.red.bold('Error:'), chalk.red(err.message));
    } finally {
        console.timeEnd(chalk.yellow('⏱️  Tiempo total'));
    }
}

main().catch(err => console.error(chalk.red.bold('Error no manejado:'), chalk.red(err)));

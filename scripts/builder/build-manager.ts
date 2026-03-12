import path from 'path';
import chalk from 'chalk';
import esbuild from 'esbuild';
import fs from 'fs/promises';
import { log } from '../core/logger.ts';

import { 
    serverManager,
    esbuildContexts,
    resourceRootCache,
} from '../core/serverManager.ts';

import { 
    RESOURCES_PATH,
    ESBUILD_OPTIONS,
    INITIAL_BUILD_CONCURRENCY
} from '../core/configs.ts';

interface BuildResult {
    success: boolean;
    message?: string;
}

interface EsbuildContext {
    rebuild: () => Promise<esbuild.BuildResult>;
    dispose: () => Promise<void>;
}

class BuildManager {
    private debounceTimer: NodeJS.Timeout | null = null;
    private isCompiling: boolean = false;
    
    /** Performs initial compilation of all resources. */
    async runInitialBuilds(): Promise<void> {
        log("Searching and compiling all resources...", { textColor: chalk.hex('#db6934ff') });
        const resourceDirs = await this.findResourceDirs(RESOURCES_PATH);
        const resourcePaths = resourceDirs.map(dir => path.relative(RESOURCES_PATH, dir));
        log(`${resourcePaths.length} resources found.`, { textColor: chalk.hex('#db6934ff') });

        let hasErrors = false;
        for (let i = 0; i < resourcePaths.length; i += INITIAL_BUILD_CONCURRENCY) {
            const batch = resourcePaths.slice(i, i + INITIAL_BUILD_CONCURRENCY);
            const results = await Promise.all(
                batch.map(p => this.compileResource(p).catch(() => ({ success: false })))
            );
            if (results.some(r => !r.success)) {
                hasErrors = true;
            }
        }

        if (hasErrors) {
            log("Errors in initial compilation. Fix and restart.", { textColor: chalk.red });
            process.exit(1);
        }
        log("Initial compilation completed.", { textColor: chalk.hex('#89F336') });
    }

    /** Recursively searches for all resource directories. */
    async findResourceDirs(startPath: string): Promise<string[]> {
        const foundDirs: string[] = [];
        const search = async (currentPath: string): Promise<void> => {
            const entries = await fs.readdir(currentPath, { withFileTypes: true });
            if (entries.some(e => e.name === 'fxmanifest.lua' && e.isFile())) {
                foundDirs.push(currentPath);
            } else {
                const subdirs = entries.filter(e => e.isDirectory());
                await Promise.all(subdirs.map(dir => search(path.join(currentPath, dir.name))));
            }
        };
        await search(startPath);
        return foundDirs;
    }

    /** Finds resource root (directory with fxmanifest.lua) by climbing up from a path. */
    async findResourceRoot(filePath: string): Promise<string | null> {
        if (resourceRootCache.has(filePath)) {
            return resourceRootCache.get(filePath) || null;
        }
    
        let currentDir = path.dirname(filePath);
        const resourcesPathParent = path.dirname(RESOURCES_PATH);
        
        while (currentDir !== RESOURCES_PATH && currentDir !== resourcesPathParent) {
            try {
                await fs.access(path.join(currentDir, 'fxmanifest.lua'));
                resourceRootCache.set(filePath, currentDir);
                return currentDir;
            } catch {
                currentDir = path.dirname(currentDir);
            }
        }
        return null;
    }

    /** Handles a detected file change using debouncing. */
    async handleFileChange(filePath: string): Promise<void> {
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer);
        }
    
        this.debounceTimer = setTimeout(async () => {
            if (this.isCompiling) return;

            const resourceRoot = await this.findResourceRoot(filePath);
            if (!resourceRoot) return;
    
            const resourceName = path.basename(resourceRoot);
            const resourceRelativePath = path.relative(RESOURCES_PATH, resourceRoot);
            
            log(`Batch change detected: ${path.basename(filePath)}`, { 
                resourceName: resourceName, 
                textColor: chalk.cyan 
            });
    
            this.isCompiling = true;
            try {
                let shouldRestart = false;
                
                if (filePath.endsWith('.ts')) {
                    const { success } = await this.compileResource(resourceRelativePath);
                    shouldRestart = success;
                } else if (filePath.endsWith('fxmanifest.lua')) {
                    log(`Change detected in fxmanifest.lua - restarting resource`, { 
                        resourceName: resourceName, 
                        textColor: chalk.magenta 
                    });
                    await serverManager.sendCommand(`refresh`);
                    shouldRestart = true;
                } else {
                    shouldRestart = true;
                }
    
                if (shouldRestart) {
                    await serverManager.restartResource(resourceName);
                }
            } catch (error) {
                const errorMessage = error instanceof Error ? error.message : 'Unknown error';
                log(`Error processing change: ${errorMessage}`, { 
                    resourceName: resourceName, 
                    textColor: chalk.red 
                });
            } finally {
                this.isCompiling = false;
            }
        }, 100);
    }

    async compileResource(resourcePath: string): Promise<BuildResult> {
        const resourceName = path.basename(resourcePath);
        const RESOURCE_ROOT = path.join(RESOURCES_PATH, resourcePath);
        const SRC_PATH = path.join(RESOURCE_ROOT, 'src');
        const ENTRY_POINT = path.join(SRC_PATH, 'main.ts');
        const DIST_PATH = path.join(RESOURCE_ROOT, 'dist');
        const OUTPUT_FILE = path.join(DIST_PATH, 'main.js');

        try {
            await fs.access(ENTRY_POINT);
        } catch {
            return { 
                success: true, 
                message: "Not a TypeScript resource." 
            };
        }

        try {
            log("Compiling TypeScript...", { 
                resourceName: resourceName, 
                textColor: chalk.hex('#3498db') 
            });
            
            let ctx = esbuildContexts.get(resourceName) as EsbuildContext | undefined;
            if (!ctx) {
                await fs.rm(DIST_PATH, { recursive: true, force: true });
                await fs.mkdir(DIST_PATH, { recursive: true });

                const context = await esbuild.context({
                    ...ESBUILD_OPTIONS,
                    entryPoints: [ENTRY_POINT],
                    outfile: OUTPUT_FILE,
                    tsconfig: path.join(RESOURCE_ROOT, 'tsconfig.json'),
                });

                esbuildContexts.set(resourceName, context);
                ctx = context;
            }

            const result = await ctx.rebuild();
            if (result.errors.length > 0) {
                log(`Compilation errors:`, { 
                    resourceName: resourceName, 
                    textColor: chalk.red 
                });
                result.errors.forEach(err => console.error(chalk.red(err.text)));
                return { success: false };
            }

            log("Compiled successfully.", { 
                resourceName: resourceName,
                textColor: chalk.hex('#89F336')
            });

            return { success: true };
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : 'Unknown error';
            log(`Compilation error: ${errorMessage}`, { 
                resourceName: resourceName, 
                resourceColor: chalk.red 
            });
            
            const ctx = esbuildContexts.get(resourceName) as EsbuildContext | undefined;
            if (ctx) {
                await ctx.dispose();
                esbuildContexts.delete(resourceName);
            }
            return { success: false };
        }
    }
}

export const buildManager = new BuildManager();
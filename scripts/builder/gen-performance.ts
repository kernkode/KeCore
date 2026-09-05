/**
 * Generates the `performance/**` Lua tree from `internal/**`.
 *
 * `internal/` is the single source of truth. The `performance/` copies are what
 * consumer resources inject via `@kecore/init.lua`; keeping them generated avoids
 * the two trees drifting out of sync (which previously caused real bugs, e.g.
 * `discord` calling a bare global `axios` that is `nil` in consumers).
 *
 * Run directly:  bun scripts/builder/gen-performance.ts
 * Or import `generatePerformance()` (called by scripts/start.ts before builds).
 */
import path from 'path';
import fs from 'fs/promises';
import crypto from 'crypto';
import chalk from 'chalk';
import { log } from '../core/logger.ts';
import { RESOURCES_PATH } from '../core/configs.ts';
import { PERF_MODULES, type PerfModule } from './perf-modules.ts';

const KECORE_PATH = path.join(RESOURCES_PATH, '[framework]', 'kecore');
const INTERNAL_PATH = path.join(KECORE_PATH, 'internal');
const PERFORMANCE_PATH = path.join(KECORE_PATH, 'performance');
const HASH_FILE = path.join(PERFORMANCE_PATH, '.hash');

/** Escapes a string for safe use inside a RegExp. */
function escapeRegex(s: string): string {
    return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function header(srcRel: string): string {
    return (
        `-- AUTO-GENERATED from internal/${srcRel.replace(/\\/g, '/')} ` +
        `by scripts/builder/gen-performance.ts — DO NOT EDIT\n` +
        `-- Edit the internal/ source and run \`bun run gen:performance\` to regenerate.\n\n`
    );
}

function sourceList(mod: PerfModule): string[] {
    return Array.isArray(mod.src) ? mod.src : [mod.src];
}

/**
 * Namespaced module: `kec.<name>` (own table + own methods) becomes a `local <name>`
 * that is returned. Cross-module refs (`kec.axios`, `kec.zod`, ...) and core calls
 * (`kec:isServer`, `kec:emit`, ...) are intentionally left untouched.
 */
function transformNamespaced(src: string, name: string): string {
    const n = escapeRegex(name);
    // Own references: kec.<name>(.|:|=| ...) -> <name>
    let out = src.replace(new RegExp(`kec\\.${n}\\b`, 'g'), name);
    // Turn the first top-level declaration (`<name> = ...`) into a local.
    out = out.replace(new RegExp(`^${n}\\s*=`, 'm'), `local ${name} =`);
    return `${out.trimEnd()}\n\nreturn ${name}\n`;
}

/**
 * Extension module: internal extends `kec.<name>` but may also read shared data
 * from that same framework namespace. Only declarations and owned methods are
 * moved to the returned local module.
 */
function transformExtension(src: string, name: string): string {
    const n = escapeRegex(name);
    let out = src.replace(new RegExp(`^kec\\.${n}\\s*=\\s*\\{\\}\\s*$`, 'm'), '');
    out = out.replace(new RegExp(`function\\s+kec\\.${n}([:.])`, 'g'), `function ${name}$1`);
    out = out.replace(/^vehicle_methods\s*=/m, 'local vehicle_methods =');
    out = out.replace(/^vehicle_info\s*=/m, 'local vehicle_info =');
    return `local ${name} = {}\n\n${out.trimEnd()}\n\nreturn ${name}\n`;
}

/**
 * Flat module (timers): methods are defined directly on `kec:` in internal. Move
 * only the methods THIS file defines onto a `local <name>` table, leaving foreign
 * `kec:` calls (e.g. `kec:emit`) alone.
 */
function transformFlat(src: string, name: string): string {
    const owned = new Set(
        [...src.matchAll(/function\s+kec[:.](\w+)/g)].map(m => m[1])
    );
    let out = src;
    for (const method of owned) {
        const m = escapeRegex(method);
        out = out.replace(new RegExp(`kec([:.])${m}\\b`, 'g'), `${name}$1${method}`);
    }
    return `local ${name} = {}\n\n${out.trimEnd()}\n\nreturn ${name}\n`;
}

/**
 * Native module: internal relies on the globals `native` and `isWorldLoaded`
 * (from internal/client/header.lua + world.lua) which do not exist inside consumer
 * resources. Wrap `native` as a local and use the `metadata` reference captured
 * once by @kecore/init.lua; no exports are used in hot paths.
 */
function transformNative(src: string, name: string): string {
    // Boolean reads of the global `isWorldLoaded` -> call the shim function.
    const out = src.replace(/\bisWorldLoaded\b(?!\s*\()/g, 'isWorldLoaded()');
    const preamble =
        `local ${name} = {}\n\n` +
        `local function isWorldLoaded()\n` +
        `    return kec.isWorldLoaded == true\n` +
        `end\n\n`;
    return `${preamble}${out.trimEnd()}\n\nreturn ${name}\n`;
}

function transform(mod: PerfModule, src: string): string {
    // Normalize CRLF -> LF so generated files have stable, clean diffs.
    const normalized = src.replace(/\r\n/g, '\n');
    switch (mod.mode) {
        case 'namespaced': return transformNamespaced(normalized, mod.name);
        case 'flat':       return transformFlat(normalized, mod.name);
        case 'native':     return transformNative(normalized, mod.name);
        case 'extension':  return transformExtension(normalized, mod.name);
        // Already a standalone chunk that returns its own value: nothing to rewrite.
        case 'chunk':      return `${normalized.trimEnd()}\n`;
    }
}

async function computeInternalHash(): Promise<string> {
    const hashes = await Promise.all(
        PERF_MODULES.flatMap((mod) => sourceList(mod).map(async (src) => {
            const srcPath = path.join(INTERNAL_PATH, src);
            const content = await fs.readFile(srcPath, 'utf8').catch(() => '');
            return crypto.createHash('sha256').update(content).digest('hex');
        }))
    );
    return crypto.createHash('sha256').update(hashes.join('')).digest('hex');
}

async function shouldRegenerate(): Promise<boolean> {
    try {
        const savedHash = await fs.readFile(HASH_FILE, 'utf8');
        const currentHash = await computeInternalHash();
        return savedHash.trim() !== currentHash;
    } catch {
        return true;
    }
}

/** Generates every performance module. Returns the number of files written. */
export async function generatePerformance(): Promise<number> {
    if (!await shouldRegenerate()) {
        log('performance/ is up-to-date (skipped)', {
            resourceName: 'scripts:gen', textColor: chalk.hex('#89F336'),
        });
        return 0;
    }

    let written = 0;

    await Promise.all(
        PERF_MODULES.map(async (mod) => {
            const outPath = path.join(PERFORMANCE_PATH, mod.out);

            let src: string;
            try {
                const sources = await Promise.all(
                    sourceList(mod).map((srcRel) => fs.readFile(path.join(INTERNAL_PATH, srcRel), 'utf8'))
                );
                src = sources.join('\n\n');
            } catch {
                log(`Missing internal source: internal/${sourceList(mod).join(', internal/')}`, {
                    resourceName: 'scripts:gen', resourceColor: chalk.red,
                });
                throw new Error(`gen-performance: cannot read ${sourceList(mod).join(', ')}`);
            }

            const content = header(sourceList(mod).join(' + ')) + transform(mod, src);
            await fs.mkdir(path.dirname(outPath), { recursive: true });
            await fs.writeFile(outPath, content, 'utf8');
            written++;
        })
    );

    const currentHash = await computeInternalHash();
    await fs.writeFile(HASH_FILE, currentHash, 'utf8');

    log(`performance/ regenerated (${written} modules)`, {
        resourceName: 'scripts:gen', textColor: chalk.hex('#89F336'),
    });
    return written;
}

if (import.meta.main) {
    generatePerformance().catch((err: unknown) => {
        const message = err instanceof Error ? err.message : String(err);
        log(`gen-performance failed: ${message}`, {
            resourceName: 'scripts:gen', resourceColor: chalk.red,
        });
        process.exit(1);
    });
}

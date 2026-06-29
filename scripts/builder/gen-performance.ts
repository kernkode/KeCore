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
import chalk from 'chalk';
import { log } from '../core/logger.ts';
import { RESOURCES_PATH } from '../core/configs.ts';
import { PERF_MODULES, type PerfModule } from './perf-modules.ts';

const KECORE_PATH = path.join(RESOURCES_PATH, '[framework]', 'kecore');
const INTERNAL_PATH = path.join(KECORE_PATH, 'internal');
const PERFORMANCE_PATH = path.join(KECORE_PATH, 'performance');

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
 * resources. Wrap `native` as a local and shim `isWorldLoaded` via the export.
 */
function transformNative(src: string, name: string): string {
    // Boolean reads of the global `isWorldLoaded` -> call the shim function.
    const out = src.replace(/\bisWorldLoaded\b(?!\s*\()/g, 'isWorldLoaded()');
    const preamble =
        `local ${name} = {}\n\n` +
        `local function isWorldLoaded()\n` +
        `    return exports.kecore:isWorldLoaded()\n` +
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
    }
}

/** Generates every performance module. Returns the number of files written. */
export async function generatePerformance(): Promise<number> {
    let written = 0;

    await Promise.all(
        PERF_MODULES.map(async (mod) => {
            const srcPath = path.join(INTERNAL_PATH, mod.src);
            const outPath = path.join(PERFORMANCE_PATH, mod.out);

            let src: string;
            try {
                src = await fs.readFile(srcPath, 'utf8');
            } catch {
                log(`Missing internal source: internal/${mod.src}`, {
                    resourceName: 'scripts:gen', resourceColor: chalk.red,
                });
                throw new Error(`gen-performance: cannot read ${srcPath}`);
            }

            const content = header(mod.src) + transform(mod, src);
            await fs.mkdir(path.dirname(outPath), { recursive: true });
            await fs.writeFile(outPath, content, 'utf8');
            written++;
        })
    );

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

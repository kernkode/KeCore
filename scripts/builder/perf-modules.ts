/**
 * Declarative config that maps each `performance/**` output module to its
 * canonical source under `internal/**`. The `performance/` tree is GENERATED
 * from `internal/` by `gen-performance.ts` — `internal/` is the single source
 * of truth. Do not hand-edit the generated files.
 *
 * mode:
 *   - 'namespaced': internal declares `kec.<name> = {}` and methods as
 *     `function kec.<name>:m`. Output declares `local <name> = {}` + `return <name>`.
 *   - 'flat': internal defines methods directly on `kec:` (e.g. `function kec:setTimeout`).
 *     Output moves only THIS file's own methods onto `local <name>`, keeping core
 *     calls like `kec:emit` untouched.
 *   - 'native': internal uses the globals `native` / `isWorldLoaded` / `metadata`
 *     (defined in `internal/client/header.lua`) which do not exist in consumer
 *     resources. Output wraps `native` as a local module and shims `isWorldLoaded`
 *     via the kecore export.
 */
export type PerfMode = 'namespaced' | 'flat' | 'native';

export interface PerfModule {
    /** Destination path relative to `resources/[framework]/kecore/performance/`. */
    out: string;
    /** Source path relative to `resources/[framework]/kecore/internal/`. */
    src: string;
    /** Local module variable name in the generated file. */
    name: string;
    mode: PerfMode;
}

export const PERF_MODULES: PerfModule[] = [
    // shared
    { out: 'shared/timers.lua',    src: 'shared/timers.lua',    name: 'timers',    mode: 'flat'       },
    { out: 'shared/base64.lua',    src: 'shared/base64.lua',    name: 'base64',    mode: 'namespaced' },
    { out: 'shared/zod.lua',       src: 'shared/zod.lua',       name: 'zod',       mode: 'namespaced' },
    { out: 'shared/lzwson.lua',    src: 'shared/lzwson.lua',    name: 'lzwson',    mode: 'namespaced' },
    { out: 'shared/lru_cache.lua', src: 'shared/lru_cache.lua', name: 'lru_cache', mode: 'namespaced' },
    { out: 'shared/utils.lua',     src: 'shared/utils.lua',     name: 'utils',     mode: 'namespaced' },
    { out: 'shared/enum.lua',      src: 'shared/enum.lua',      name: 'enum',      mode: 'namespaced' },

    // client
    { out: 'client/raycast.lua',   src: 'client/raycast.lua',          name: 'raycast',   mode: 'namespaced' },
    { out: 'client/keys.lua',      src: 'client/keys.lua',             name: 'keys',      mode: 'namespaced' },
    { out: 'client/label3d.lua',   src: 'client/label3d.lua',          name: 'label3d',   mode: 'namespaced' },
    { out: 'client/scaleform.lua', src: 'client/natives/scaleform.lua', name: 'scaleform', mode: 'namespaced' },
    { out: 'client/natives.lua',   src: 'client/natives/impl.lua',     name: 'native',    mode: 'native'     },

    // server
    { out: 'server/os.lua',        src: 'server/libs/os.lua',      name: 'os',      mode: 'namespaced' },
    { out: 'server/axios.lua',     src: 'server/libs/axios.lua',   name: 'axios',   mode: 'namespaced' },
    { out: 'server/http.lua',      src: 'server/libs/http.lua',    name: 'http',    mode: 'namespaced' },
    { out: 'server/discord.lua',   src: 'server/libs/discord.lua', name: 'discord', mode: 'namespaced' },
];

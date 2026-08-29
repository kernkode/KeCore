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
 *     resources. Output wraps `native` as a local module and reads `isWorldLoaded`
 *     from the already-captured `kec` table.
 *   - 'extension': internal extends an existing namespace such as `kec.vehicle`
 *     but must keep shared refs (`kec.vehicle.state`, etc.) pointing at the
 *     already-captured framework table.
 */
export type PerfMode = 'namespaced' | 'flat' | 'native' | 'extension';

export interface PerfModule {
    /** Destination path relative to `resources/[framework]/kecore/performance/`. */
    out: string;
    /** Source path relative to `resources/[framework]/kecore/internal/`. */
    src: string | string[];
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
    { out: 'shared/weapons.lua',   src: 'shared/weapons.lua',   name: 'weapons',   mode: 'namespaced' },

    // client
    { out: 'client/raycast.lua',   src: 'client/raycast.lua',          name: 'raycast',   mode: 'namespaced' },
    { out: 'client/keys.lua',      src: 'client/keys.lua',             name: 'keys',      mode: 'namespaced' },
    { out: 'client/label3d.lua',   src: 'client/label3d.lua',          name: 'label3d',   mode: 'namespaced' },
    // client/label2d_nui.lua NO se transpila a propósito: el ui_page es de kecore y
    // SendNUIMessage solo llega al CEF de quien lo llama, así que el módulo tiene que vivir
    // una sola vez (allí) y los consumidores llegan por su export, que envuelve init.lua.
    // client/audio_nui.lua tampoco, por lo mismo: el AudioContext y los <audio> viven en ese
    // mismo CEF.
    { out: 'client/scaleform.lua', src: 'client/natives/scaleform.lua', name: 'scaleform', mode: 'namespaced' },
    { out: 'client/natives.lua',   src: 'client/natives/impl.lua',     name: 'native',    mode: 'native'     },
    { out: 'client/player.lua',    src: 'client/player.lua',           name: 'player',    mode: 'namespaced' },
    {
        out: 'client/vehicle.lua',
        src: ['client/vehicle/header.lua', 'client/vehicle/impl.lua'],
        name: 'vehicle',
        mode: 'extension',
    },
    {
        // header.lua seeds kec.controls (+ the input map), impl.lua adds the cursor methods.
        out: 'client/controls.lua',
        src: ['client/controls/header.lua', 'client/controls/impl.lua'],
        name: 'controls',
        mode: 'namespaced',
    },
    { out: 'client/events.lua',    src: 'client/events/game_events.lua', name: 'events',  mode: 'flat'       },

    // server
    { out: 'server/os.lua',        src: 'server/libs/os.lua',      name: 'os',      mode: 'namespaced' },
    { out: 'server/axios.lua',     src: 'server/libs/axios.lua',   name: 'axios',   mode: 'namespaced' },
    { out: 'server/http.lua',      src: 'server/libs/http.lua',    name: 'http',    mode: 'namespaced' },
    { out: 'server/discord.lua',   src: 'server/libs/discord.lua', name: 'discord', mode: 'namespaced' },
    // mongodb_registry.lua NO se transpila a propósito: el registro de schemas
    // debe vivir una sola vez (en kecore) y los consumidores llegan por refs.
    // server/audio.lua tampoco: el registro de emisores (con el reloj de cada uno) tiene que ser
    // único o nadie sabría por qué segundo va la música de los demás.
    { out: 'server/mongodb.lua',   src: 'server/libs/mongodb.lua', name: 'mongodb', mode: 'namespaced' },
    { out: 'server/events.lua',    src: 'server/events.lua',        name: 'events',  mode: 'flat'       },
    {
        out: 'server/vehicle.lua',
        src: ['server/vehicle/header.lua', 'server/vehicle/methods.lua', 'server/vehicle/vehicle.lua'],
        name: 'vehicle',
        mode: 'extension',
    },
];

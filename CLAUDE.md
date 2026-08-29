# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A FiveM server **plus** the framework that runs on it, in one tree:

- `scripts/` — TypeScript dev harness, runs in **Bun** *outside* FXServer. Spawns FXServer, compiles resources, hot-reloads, exposes a REST control API.
- `resources/[framework]/kecore` — the KeCore framework itself (Lua, runs *inside* FXServer). Everything hangs off a global `kec` table.
- `resources/[framework]/libs` — server-only TS bridge (MongoDB driver + bcrypt) exposed to Lua via `exports`.
- `resources/[gameplay]/testing` — throwaway consumer resource; the reference for how a consumer wires itself up.
- `artifacts/` — downloaded FXServer build (gitignored, managed by `scripts/update.ts`).

## Commands

```bash
bun run dev                # the whole environment (see startup order below)
bun run gen:performance    # regenerate performance/ from internal/  — required after editing internal/
bun run update             # download/extract FXServer artifact (recommended channel)
bun run update:latest      # ...latest channel;  bun run update:version <build> for a pinned build
bun run update:core        # pull kecore/ + scripts/ from GitHub main, comparing git SHAs — OVERWRITES local files
```

NUI (the `kec.label2d` overlay) is a separate Svelte app, built by hand:

```bash
cd "resources/[framework]/kecore/svelte-src" && bun install && bun run build   # → ../html
```

Before the first `bun run dev`: copy `examples/.env.example` → `.env`, `examples/config.cfg.example` → `config.cfg`, `examples/server.cfg.example` → `server.cfg` (all three land in the repo root and are gitignored). Startup hard-exits if `FXSERVER`, `ENDPOINT_TCP` or `ENDPOINT_UDP` is missing from `.env`, or if the endpoint port is already in use.

**There is no test runner.** No `test` script, no framework, no `scripts/test/`. Lua changes can only be verified by running the server and exercising them in-game. esbuild only transpiles, so for real type checking on a TS resource run `bunx tsc --noEmit -p "resources/[framework]/libs/tsconfig.json"` (each TS resource carries its own `tsconfig.json`).

## Harness architecture (`scripts/`)

`start.ts` order: check `.env` → update FXServer artifact if a newer one exists → `generatePerformance()` → `buildManager.runInitialBuilds()` → `serverManager.start()` → `startRestAPI()` → `watcher.start()`. Your stdin is piped into the FXServer console, so you can type server commands into the same terminal.

- **Resource discovery** — `findResourceDirs` walks `resources/` and stops at the first directory containing `fxmanifest.lua`. **Resource name == folder name** (`path.basename`).
- **Hot reload** — chokidar → 100 ms debounce → group changed files by nearest `fxmanifest.lua` ancestor. A `.ts` change rebuilds via a persistent esbuild context (`src/main.ts` → `dist/main.js`, IIFE/es2020, per-resource `tsconfig.json`); an `fxmanifest.lua` change sends `refresh` first; then `ensure <resourceName>` over FXServer stdin.
- **`serverManager`** — spawns FXServer with `+exec server.cfg +set onesync on` (no args at all when `USE_TXADMIN=true`; txAdmin passes its own). `onesync` is a CLI arg on purpose — it is an internal ConVar and is already frozen by the time `server.cfg` executes. `editConfig()` rewrites `endpoint_add_tcp/udp` in `server.cfg` from `.env` on every start: **`.env` is the source of truth for endpoints**.
- **REST API** — express on `API_PORT`, every route behind an `x-api-key` header matching `API_KEY`. `/api/status|start|stop|restart`.

## kecore: `internal/` vs `performance/` — read this before editing Lua

The framework exists as two Lua trees:

- `internal/**` — **the single source of truth.** Loaded into the kecore resource itself by `fxmanifest.lua` (shared/server/client_scripts) and attached to the global `kec` (plus the intentional globals `native`, `metadata`, `isWorldLoaded`).
- `performance/**` — **generated; never hand-edit.** Consumer resources declare `shared_script '@kecore/init.lua'`; `init.lua` does `LoadResourceFile` + `load()` per module and injects the result into the consumer's *own* `kec`. Calls then hit a local table instead of paying a cross-runtime funcref hop.

After any edit under `internal/`, run `bun run gen:performance` (`bun run dev` also does it). The module list and per-module transform mode live in `scripts/builder/perf-modules.ts`; the transforms (`namespaced` / `flat` / `native` / `extension`) live in `scripts/builder/gen-performance.ts`.

Gotchas that cost real time:

- `performance/.hash` gates regeneration and hashes **only the `internal/` sources**. Editing the generator or `perf-modules.ts` will *not* trigger a regen — delete `performance/.hash` to force one.
- Adding a module means **three** edits: the file in `internal/` + kecore's `fxmanifest.lua`, an entry in `PERF_MODULES`, and an entry in the `chunks` table in `init.lua` (module path → inject key; `"/"` means inject flat onto `kec`, otherwise `kec.<key>`).
- Some modules are **deliberately not transpiled**, because they must exist exactly once: `client/label2d_nui.lua` (the `ui_page` CEF belongs to kecore and `SendNUIMessage` only reaches the caller's own CEF, so `init.lua` re-wraps the methods as export jumps — extend that explicit method list when adding one), `server/libs/mongodb_registry.lua` (schema registry), and `shared/events/**`, `shared/rpc/**`, `math.lua`, `hashmap.lua`. Consumers still reach those through the `kec` table returned by `exports.kecore:get()`, as funcrefs.

## Framework internals

**Consumer contract.** `init.lua` sets `kec = exports.kecore:get()` wrapped in a metatable whose `__index` returns `{}`, so a missing module degrades instead of erroring on nil. It then injects the performance modules, rebuilds `kec.label2d`, and seeds `kec.state` from `exports.kecore:stateSnapshot()` (pcall'd — an older kecore may lack that export).

**`kec.state`** (`internal/shared/core.lua`, mirrored in `init.lua`). Every resource keeps its own copy of the values, so **reads are plain table access**; writes replicate through the `kec:state:sync` event so all resources converge and every `onChange` fires. That is the win over exports for shared data — you pay only on write. Scope is **per side**: server state and client state are separate spaces, cross them with events or `kec.rpc`.

**Events** (`internal/shared/events/`). `kec:on` (net, accepts a string or an array of names), `kec:onLocal`, `kec:emit` / `emitClient` / `emitAllClients` / `emitServer`, plus the `on_player_loaded` / `on_player_death` / `on_resource_start` / `on_resource_stop` wrappers in `impl.lua`. On the server `kec:on` prepends `source` to the callback args when `source ~= ''`. Because consumers call these as funcrefs, their handlers are registered inside **kecore's** Lua state; `manager.lua` keeps a per-resource array of handlers and removes them on `onResourceStop`. Handler errors always print — the `pcall` keeps one bad handler from taking down the rest.

**RPC** (`internal/shared/rpc/`). `kec.rpc:register` / `:await` / `:awaitLocal`, default timeout 5000 ms. No performance copy: it only ever runs in kecore's single Lua state.

**Cross-file state.** Files loaded by `fxmanifest.lua` are separate chunks, so a `local` cannot be shared between them. The convention is a `header.lua` that seeds `kec._internal.<domain>` and aliases it to bare globals used by the sibling files (`player_info`, `player_cache`, `pendingRequests`, `vehicle_methods`, ...). kecore's `_G` is isolated, so this is contained — but prefer `kec._internal` for anything new instead of adding another bare global. `native`, `metadata` and `isWorldLoaded` must stay globals: the generator's `native` transform and `exports('natives')` depend on them.

**Naming trap.** `kec.vehicle` is a shared data table (`shared/vehicle/models.lua`), while `kec.player` is a *function* (`kec:player(src)`), so player state cannot hang off `kec.player.*`.

**Logging.** `kec.log:debug|info|warn|error(module, text, ...)` — extra args go through `string.format`. `debug` is gated by `kec.debugMode`, event tracing by `kec.debugEvents`; `warn`/`error` are always visible.

**`libs` resource.** `libs/src/main.ts` owns the MongoDB driver; every data op returns a **JSON string** `{ok:true,data?} | {ok:false,error}` so the Lua side can tell "not found" from "DB failed". It also normalizes msgpack quirks (empty table → `{}`), converts 24-hex `_id` values to `ObjectId`, and expands `{"$date": ...}` markers to real `Date`s (needed for TTL indexes). `lua/main.lua` exports `import` for `bcrypt` only — Mongo is reached as `kec.mongodb`. Start order in `scripts.cfg`: `libs` → `kecore` → gameplay resources.

**API reference:** `resources/[framework]/kecore/docs/*.md`.

## Conventions

- Comments and log strings in the Lua framework are mostly **Spanish**; `scripts/` is mixed. Match the file you are editing.
- **Commit messages are always written in English**, conventional-commits format: `feat(kecore): reactive state across resources`. Commits before 2026-08-26 have Spanish subjects — do not follow them.
- `.env`, `config.cfg` and `server.cfg` are gitignored; the tracked templates live in `examples/` (`examples/.env.example`, ...) — add new keys there too.
- Generated files carry an `AUTO-GENERATED ... DO NOT EDIT` header. If you are about to edit one, you are in the wrong tree.

# KeCore

KeCore is a FiveM framework and development environment. The framework itself is Lua and runs inside FXServer; around it sits a Bun toolchain that manages the server artifact, compiles TypeScript resources, reloads them on save, and exposes a REST API for process control.

Everything the framework exposes is reachable through one global table, `kec`.

## Requirements

| Requirement | Notes |
| --- | --- |
| Bun | 1.x — runs the toolchain, no Node.js installation needed |
| FXServer | downloaded automatically into `artifacts/` |
| License key | a cfx.re key from [keymaster](https://keymaster.fivem.net) |
| MongoDB | only if you use `kec.mongodb` |

## Setup

```bash
bun install                    # postinstall downloads the recommended FXServer build
cp .env.example .env
cp config.cfg.example config.cfg
cp server.cfg.example server.cfg
```

The three config files are gitignored, so each machine keeps its own. Fill in at least:

- `.env` — `API_KEY`, `ENDPOINT_TCP`, `ENDPOINT_UDP`, `FXSERVER`
- `server.cfg` — `sv_licenseKey`
- `config.cfg` — `mongodb_url`, if MongoDB is used

Then start the environment:

```bash
bun run dev
```

This regenerates the framework's `performance/` tree, compiles every TypeScript resource, starts FXServer and the REST API, and watches `resources/` for changes. The FXServer console is attached to the same terminal, so server commands can be typed directly into it.

## Scripts

| Command | Description |
| --- | --- |
| `bun run dev` | Start the full development environment |
| `bun run gen:performance` | Regenerate `performance/` from `internal/` |
| `bun run update` | Install the recommended FXServer build |
| `bun run update:latest` | Install the latest FXServer build |
| `bun run update:version <build>` | Install a specific build number |
| `bun run update:core` | Sync `kecore/` and `scripts/` from the upstream repository, comparing git SHAs. Overwrites local changes in those paths |

The framework's NUI overlay is a separate Svelte application and is built on demand:

```bash
cd "resources/[framework]/kecore/svelte-src"
bun install && bun run build     # output: ../html
```

## Configuration

`.env` holds machine-local settings and secrets:

| Key | Description |
| --- | --- |
| `API_PORT` / `API_KEY` | Port and shared secret for the REST control API |
| `ENDPOINT_TCP` / `ENDPOINT_UDP` | Server endpoints. Source of truth: they are written into `server.cfg` on every start |
| `FXSERVER` | Artifact channel: `latest`, `recommended`, or a build number |
| `USE_TXADMIN` / `TXHOST_TXA_PORT` | Hand process management to txAdmin instead of passing arguments directly |
| `DISCORD_TOKEN` | Bot token for `kec.discord`, or `disable` |

`config.cfg` holds server convars: `mongodb_url`, `mongodb_max_pool_size`, `mongodb_connect_timeout_ms`, `ENABLE_POPULATION`, `ENTITY_CREATION`.

## Development workflow

Changes under `resources/` are batched with a short debounce, grouped per resource, and applied without restarting FXServer:

| Change | Action |
| --- | --- |
| `.ts` under a resource's `src/` | esbuild rebuild (`src/main.ts` → `dist/main.js`), then `ensure <resource>` |
| `fxmanifest.lua` | `refresh`, then `ensure <resource>` |
| Any other file | `ensure <resource>` |

A resource is any directory containing an `fxmanifest.lua`; its folder name is its resource name.

### REST API

| Endpoint | Description |
| --- | --- |
| `GET /api/status` | Process status |
| `POST /api/start` | Start FXServer |
| `POST /api/stop` | Stop FXServer |
| `POST /api/restart` | Full restart, waits for re-authentication |

Every request requires an `x-api-key` header matching `API_KEY`. The API listens on all interfaces, so keep its port closed at the firewall and use a long random key — it can stop and restart the server.

## Layout

```
scripts/                        Bun toolchain (builder, updater, REST API, process manager)
resources/[framework]/kecore/   the framework
  internal/                     source of truth, loaded by kecore itself
  performance/                  generated copies injected into consumer resources
  svelte-src/ → html/           NUI overlay
  docs/                         API reference
resources/[framework]/libs/     server-only TypeScript bridge (MongoDB driver, bcrypt)
resources/[gameplay]/           game resources
artifacts/                      FXServer build (downloaded)
```

## Using the framework

A resource opts in from its manifest; no other wiring is required:

```lua
shared_scripts {
    '@kecore/init.lua'
}
```

Events and RPC:

```lua
-- server
kec:on("shop:buy", function(source, itemId)      -- source is prepended on the server
    kec.log:info("shop", "player %s bought %s", source, itemId)
    kec:emitClient("shop:bought", source, itemId)
end)

kec.rpc:register("shop:getStock", function(source, shopId)
    return { bread = 4 }
end)

-- client: await yields until the reply arrives, so it runs inside a thread or
-- an event handler, never at the top level of the file
kec:on("shop:open", function()
    local stock = kec.rpc:await("shop:getStock", 5000, "grocery")
    print(stock and stock.bread)                 -- nil on timeout
end)
```

Shared state, replicated across resources on the same side:

```lua
kec.state:set("weather", "EXTRASUNNY")

kec.state:onChange("weather", function(new, old)
    print(("weather %s -> %s"):format(old, new))
end)
```

Timers, cleaned up automatically when the resource stops:

```lua
-- a tick stops itself by returning false
local tick = kec:everyTick(function()
    if done then return false end
end)

-- or is cancelled through its handle. setTimeout runs in its own thread and
-- returns immediately, so the cancel has to happen inside the callback.
kec:setTimeout(function()
    tick:cancel()
end, 2000)
```

Documents validated against a schema before they reach MongoDB:

```lua
local Character = kec.mongodb:schema("Character", {
    collection = "characters",
    schema = {
        type = "object",
        properties = { name = { type = "string" }, cash = { type = "number" } },
        required = { "name" }
    },
    defaults = { cash = 500 }
})

local id, err = Character:create({ name = "John Doe" })
local doc = Character:findOne({ name = "John Doe" })
```

Client side, key bindings and on-screen text:

```lua
kec.keys:bind({
    name = "toggleLight",
    description = "Toggle flashlight",
    Mapper = "KEYBOARD",
    Key = "H",
    keydown = function()
        kec.label2d:info("Flashlight on", 1500)
    end
})
```

Also available: `kec.zod` for runtime payload validation, `kec.axios` and `kec.http` for outbound requests and in-resource routes, `kec.discord` for bot operations, `kec.lru_cache`, `kec.vehicle`, `kec.raycast`, `kec.label3d`, and the `native` wrapper around local-player natives.

## Framework internals

`internal/` is the single source of truth: kecore loads it through its own manifest and attaches everything to `kec`. `performance/` is generated from `internal/` by `scripts/builder/gen-performance.ts`, and it is what `@kecore/init.lua` injects into each consumer resource — so a call from a consumer resolves against a local table instead of crossing the runtime boundary every time.

`performance/` is never edited by hand. After changing anything under `internal/`, run `bun run gen:performance`; `bun run dev` does it on start. The module list and per-module transform modes live in `scripts/builder/perf-modules.ts`.

## Documentation

- [Core, state and timers](resources/%5Bframework%5D/kecore/docs/CORE_AND_TIMERS.md)
- [Events and RPC](resources/%5Bframework%5D/kecore/docs/EVENTS_AND_RPC.md)
- [Client API](resources/%5Bframework%5D/kecore/docs/CLIENT_API.md)
- [Server API](resources/%5Bframework%5D/kecore/docs/SERVER_API.md)

Hosted documentation: <https://kecore-docs.vercel.app/>

## License

MIT

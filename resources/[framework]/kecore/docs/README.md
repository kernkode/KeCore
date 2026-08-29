# KeCore Framework Documentation

Welcome to the official documentation for **KeCore**, the core framework powering the FiveM / RedM server infrastructure.

## Documentation Structure

- [Core and Timers](./CORE_AND_TIMERS.md): Initialization, `kec.state`, unified logging system, and optimized timers (`everyTick`, `setInterval`, `setTimeout`).
- [Events and RPC](./EVENTS_AND_RPC.md): Local/network events, game/player event wrappers, and the asynchronous RPC system.
- [Client API](./CLIENT_API.md): Native player methods (`native`), key bindings (`kec.keys`), 2D/3D UI elements, raycasting, scaleform, and client-side vehicle wrappers.
- [Server API](./SERVER_API.md): Player management, Entities, Server-side Vehicles, HTTP Server, Axios HTTP Client, Discord Integration, and MongoDB/Schemas.
- [Audio](./AUDIO.md): Positional audio streaming (`kec.audio`) — 3D emitters, interior/vehicle occlusion, server clock sync, the YouTube relay, and production deployment.

## Architecture

- **Consumer Resources**: Declare `@kecore/init.lua` in their `shared_scripts` to access the global `kec` object.
- **Internal Structure**:
  - `internal/`: Contains editable source code used during development.
  - `performance/`: Contains generated bundle/distribution code. (Run `bun run gen:performance` after modifying `internal/`).
- **Global Shared State**:
  - `kec.state`: Shared table for storing cross-script state variables without polluting `_G`.

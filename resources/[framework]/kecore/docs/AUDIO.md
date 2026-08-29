# Audio (`kec.audio`)

Positional audio streaming: play a URL — a YouTube track resolved by the server, an internet radio
stream, a local `.ogg` — anywhere in the world, in 3D, with walls muffling it.

GTA's own audio engine cannot do this: it plays pre-baked containers (`.awc` + `dat54` metadata),
not arbitrary URLs. So the sound is produced by **kecore's CEF** through the Web Audio API, which
brings the three things the game engine will not give you: an HRTF panner that places the sound
around the listener's head, a low-pass filter that imitates a wall, and reverb so that what is
playing indoors sounds like it is indoors.

Typical uses: music in a car that moves with it and can be heard from the pavement, a nightclub
whose bass leaks into the street, a radio in a shop, UI one-shots.

---

## How it works

```
[any resource]   kec.audio:play{ url = ..., entity = veh, loop = true }
       │ export → façade rebuilt by @kecore/init.lua (one hop, like kec.label2d)
       ▼
internal/server/audio.lua      registry of live emitters + server clock (sync)
       │ net event, emitters travel by netId or coords
       ▼
internal/client/audio_nui.lua  20 Hz tick: world → camera space, occlusion
       │ SendNUIMessage
       ▼
svelte-src/src/audio.ts        AudioContext: <audio> → lowpass → gain → HRTF panner → master
       │ <audio src>                                  └→ send → shared convolver (reverb bus)
       ▼
scripts/core/audio.ts          yt-dlp (cached) → fetch googlevideo → piped to the client
```

Both Lua modules live **only inside kecore** and are deliberately absent from
`scripts/builder/perf-modules.ts`:

- The client one owns the CEF. `SendNUIMessage` only reaches the CEF of the resource that calls it,
  so an injected copy inside a consumer would be talking to a CEF that does not exist there.
- The server one owns the emitter registry. If it were injected, every resource would carry its own
  copy and none of them would know what the others are playing.

Consumers reach both through a single export, which `@kecore/init.lua` wraps back into `kec.audio`
with the same method names — exactly the pattern documented for `kec.label2d`. Call sites never see
the export.

---

## Client API

```lua
local id = kec.audio:play({
    url = "https://...",            -- required: http/https (the relay) or nui://resource/path.ogg
    id = "disco",                   -- optional; reusing an id replaces that emitter
    volume = 1.0,
    loop = false,
    offset = 0.0,                   -- second to start at (this is what the server sync uses)
    entity = veh,                   -- follows the entity...
    netId = 12,                     -- ...or by netId (how it arrives from the server)
    coords = vector3(x, y, z),      -- or stays there
    refDistance = 2.0,              -- m: full volume within this radius
    maxDistance = 40.0,             -- m: inaudible beyond this
    space = "vehicle",              -- "vehicle" | "interior" | "open"; auto-detected
    muffle = 0.85                   -- how much the wall eats it when you are not inside
})

kec.audio:stop(id)
kec.audio:stopAll()
kec.audio:setVolume(id, 0.5)        -- relative to the player's master volume
kec.audio:setMasterVolume(0.8)      -- the player's own setting, persisted with SetResourceKvp
kec.audio:getMasterVolume() -> number
```

With no `entity`, `netId` or `coords` the emitter is **2D**: it sounds the same wherever you are.
That is what UI beeps and one-shots want.

Only `url` is required; everything else falls back to the `DEFAULTS` table at the top of
`internal/client/audio_nui.lua`. URLs are checked against `http`, `https` and `nui` schemes before
reaching the CEF, since they come from outside (the server, another resource) and end up as the
`src` of an `<audio>` element.

## Server API

```lua
kec.audio:resolve(url, function(track, err)
    if not track then return kec.log:error("disco", err) end
    -- track = { url, title, duration, isLive }

    kec.audio:play({
        id = "disco",
        url = track.url,
        duration = track.duration,   -- only used to drop a finished one-shot from the registry
        coords = { x = -1605.0, y = -3012.0, z = -76.0 },
        loop = true
    })
end)

kec.audio:play({ url = track.url, netId = netId, loop = true })       -- follows the car
kec.audio:play({ url = track.url, entity = veh })                    -- entity works too
kec.audio:play({ url = track.url, target = source, volume = 0.5 })   -- one player only
kec.audio:play({ url = track.url, target = { 1, 4, 9 } })            -- a few
kec.audio:stop("disco")
kec.audio:list() -> table                                            -- live emitters by id
```

`target = nil` means everyone, **including whoever connects later**. The remaining options are the
client ones (`volume`, `loop`, `offset`, `space`, `muffle`, `refDistance`, `maxDistance`).

---

## Space and occlusion

Occlusion is a single number, `0..1`, computed on the client at 20 Hz and sent with the position.
It comes from `space`, which is **auto-detected once** when the emitter starts, so no caller has to
think about it:

| `space` | Detected when | Sounds clean only when |
|---|---|---|
| `"vehicle"` | the entity is a vehicle | you are inside **that** vehicle |
| `"interior"` | the coords (or the entity) are inside an interior | you are inside that interior |
| `"open"` | neither | always — never muffled |

Pass `space` explicitly to override the detection. If the emitter arrives by `netId` and the entity
is not streamed in yet, detection is deferred until it resolves; until then the emitter plays
unmuffled, which is the least annoying way to be wrong (you hear it, rather than not hearing it).

`muffle` is how much is taken away when you are outside — the per-emitter dial. At `muffle = 0.85`
(the default) an outside listener gets the low-pass down to 350 Hz, the volume at 35 % and the
reverb send up to 0.70. Measured in a browser with an analyser on the master bus: 6 kHz drops 37 dB
while 200 Hz only drops 8 dB. That difference is the effect — you hear the bass from the street and
lose everything above it.

The transition uses a 250 ms ramp, so walking through a door is a sweep and not a click.

Occlusion has one deliberate blind spot: there is **no raycast**, so a wall that is not part of an
interior (a plain wall in a field) blocks nothing. The interior check covers the two cases the
system was built for and costs one native per emitter per tick. A `StartShapeTestLosProbe` at ~5 Hz
with an interpolated result is the natural upgrade.

## Synchronisation

Every emitter is stamped with `startedAt = GetGameTimer()` (the server's monotonic clock) when it
starts. Whenever that emitter is sent to somebody, the elapsed time is recomputed and travels as
`offset`, which the CEF applies as a seek once it knows the track duration.

That single mechanism covers three situations:

- **Everyone already connected** gets `offset = 0`, so there is no seek at all: each CEF starts as
  soon as its buffer fills. They start together.
- **A late joiner** (`kec:on_player_loaded`) gets the exact second. Nobody restarts the song.
- **A player whose CEF was replaced** by a hot reload of kecore asks for the snapshot itself, and
  gets the same treatment. That request is rate-limited to one per 5 s per player, because it is
  client-triggered.

What is *not* compensated: the one-way latency of the event and how long each CEF takes to buffer
before sound comes out. Neither is knowable from the server. So this is "the same second", not "the
same millisecond". For background music that is invisible — each player only ever hears their own
output. Anything that needs frame accuracy (a light show following the beat) needs a real clock
handshake, which this does not do.

## Tuning

Two tables, two scopes. Both are the only place their values live:

- `TUNING` in `svelte-src/src/audio.ts` — the *sound*: filter cutoffs, gain floor, reverb wet/dry,
  ramp lengths, impulse-response length. Changing it requires rebuilding the SPA.
- `DEFAULTS` in `internal/client/audio_nui.lua` — the *world*: default volume, distances, `muffle`.
  Plus `TICK_MS` (20 Hz) and `MOVE_EPSILON` (5 cm dead-band).

The reverb impulse response is generated at runtime (noise with an exponential decay), so there is
no IR file to ship in `files{}`. One shared convolver serves every emitter: reverb is diffuse and
has no direction, so sharing the bus sounds the same and costs one node instead of N.

---

## The relay (`scripts/core/audio.ts`)

A YouTube link is not playable by itself: the direct `googlevideo.com` URL expires (~6 h), is
sometimes bound to the IP that resolved it, and depends on that host sending CORS headers — without
them `createMediaElementSource` produces silence in the CEF and there is nothing to pan or filter.
So the relay does two jobs:

| Route | Auth | Does |
|---|---|---|
| `POST /api/audio/resolve` | `x-api-key` header | runs `yt-dlp -J`, picks the audio track, caches the direct URL until its own `expire`, returns metadata plus a signed path |
| `GET /api/audio/stream/:id?t=…` | signed token in the URL | re-resolves if expired, fetches upstream passing the client's `Range`, pipes the body back with `content-type` / `content-range` / `accept-ranges` |

The client therefore sees **one stable URL** with working `Range` requests — which is what the
`offset` seek needs — and no CORS to negotiate.

Format choice: **opus/webm is preferred over m4a even at a lower bitrate**. Opus is royalty-free and
plays in any Chromium build, whereas AAC depends on which codecs the CEF was compiled with, and a
codec failure sounds exactly like a network failure (silence, no error to read). Among the remaining
tracks the lowest one that still reaches 96 kbps wins, because the relay pays for every listener.

Security properties, since the stream endpoint has to be reachable from the internet:

- It only accepts 11-character YouTube video IDs, so it is not an open HTTP proxy.
- Every URL carries an HMAC-SHA256 of `id` + expiry signed with `API_KEY`, valid 24 h and reissued
  on every `play`. No token, no bytes.
- It listens on its **own port**, not the control API's. That one has `/api/stop` and
  `/api/restart` and should never leave the machine.
- There is no rate limit: a valid token can pull bytes without a cap. Add a per-IP quota in
  `handleStream` if anyone abuses it.

## Production setup

### 1. Run the relay

In development `bun run dev` starts it for you. In production FXServer is usually launched directly
or by txAdmin, so the relay has to run as its own process:

```bash
bun scripts/core/audio.ts        # reads API_KEY and AUDIO_PORT from .env; needs yt-dlp on PATH
```

Put it behind whatever keeps it alive (systemd, pm2, a Windows service). It holds no state beyond an
in-memory URL cache, so restarting it is free — the next request just re-resolves. One relay can
serve several game servers.

### 2. Convars

The server side reads three convars:

| Convar | What | Where it comes from |
|---|---|---|
| `audio_api_url` | internal address of the relay | `+set` from the devkit; by hand otherwise |
| `audio_api_key` | must equal `API_KEY` in `.env` | idem |
| `audio_public_url` | address **players** use to reach the relay | by hand; defaults to `audio_api_url` |

With `bun run dev` and `USE_TXADMIN=false`, the devkit passes the first two as launch arguments
(`scripts/core/serverManager.ts`), so the key stays only in `.env` and never touches a file in git.
With txAdmin — which receives no arguments — or a bare FXServer, set all three yourself:

```cfg
set audio_api_url "http://127.0.0.1:30122"
set audio_api_key "the same value as API_KEY in .env"
set audio_public_url "https://audio.yourdomain.com"
```

Keep those out of a committed `.cfg`: put them in a gitignored file and `exec` it from `server.cfg`.

> **Trap:** `config.cfg` is currently never executed — the `exec config.cfg` on line 13 of
> `server.cfg` is swallowed by an unterminated comment (`# These resources will start by
> defaultexec config.cfg`). Anything you add there is silently ignored. Put convars in `server.cfg`
> itself, or fix that line first and check nothing else in `config.cfg` surprises you.

### 3. Reachability

Open `AUDIO_PORT` (30122 by default) inbound on TCP. Every player's CEF connects to it directly —
the game server does not proxy the audio.

### 4. TLS

**Verify this in game before opening the server.** kecore's NUI page is served from an `https://`
origin, so a plain `http://` media URL can be blocked or auto-upgraded as mixed content by Chromium.
`127.0.0.1` is exempt (it is a trustworthy origin), which is why local testing works with plain
http and proves nothing about production.

If it turns out to be blocked, put a reverse proxy with a certificate in front of the relay and set
`audio_public_url` to the `https://` name. Caddy does it in two lines:

```
audio.yourdomain.com {
    reverse_proxy 127.0.0.1:30122
}
```

The symptom to look for: the track resolves fine (the console prints its title) but nothing plays.

### 5. Keep yt-dlp updated

YouTube changes its player regularly and breaks extractors; yt-dlp ships fixes within days. A relay
that worked for months will start returning "el vídeo no tiene ninguna pista de audio suelta" or
timing out. Update it on a schedule:

```bash
yt-dlp -U          # or: pip install -U yt-dlp / winget upgrade yt-dlp
```

This is the one part of the system that rots on its own. Nothing else needs touching.

### 6. Bandwidth

Roughly **130 kbps per listening client**, out of the relay. The honest number is worse than it
looks, because an emitter with `target = nil` is sent to *every* connected player: distance only
decides volume (the panner silences anything past `maxDistance`), not whether the stream is
downloaded. A nightclub track with 48 players online is ~6 Mbit/s even if five people can hear it.

Ways out, in order of laziness:

1. `target` the players who should get it, and re-target as they move — fine for a shop or a small
   venue.
2. A clock handshake at connect, after which the client can compute the current second on its own
   and pause the `<audio>` element while the emitter is out of range, resuming in the right place.
   ~15 lines, no API change. This is the proper fix and it is not implemented.
3. Fewer kbps: raise the floor in `pickAudio` and take a lower-bitrate track.

### 7. If the relay goes down

`kec.audio:resolve` calls back with an error, so a resource that checks `track` will just not start
the music. Emitters already playing lose their byte stream and stall — they stay in the server
registry, so a `stop`/`play` cycle restores them once the relay is back. Nothing on the game server
crashes.

---

## Known limits

Deliberate simplifications, each with its upgrade path. They are marked `ponytail:` in the code.

- **No distance culling of the stream.** See *Bandwidth* above.
- **No occlusion raycast.** Only interiors and vehicles muffle.
- **No station / queue.** One track per emitter, looping or not. A server-side queue that advances
  by itself and broadcasts track changes goes on top without touching the engine.
- **No rate limit on the relay.** A valid token can pull bytes without a cap.
- **Sync is per-second, not per-frame.** Buffering and ping are not compensated.
- **The relay is not part of FXServer.** It is a devkit process; production has to keep it running.

## Testing

There is no committed test suite (by choice — see the repo conventions). Three levels of throwaway
checks, only the last of which needs the game:

**1. The maths, without FiveM.** There is no Lua binary on the dev machine, but `wasmoon` runs real
Lua 5.4: install it in a scratch directory and load `internal/client/audio_nui.lua` as-is, with the
natives stubbed as plain Lua functions and `kec` as a small fake table. Stub `kec:everyTick` so it
hands you the tick function, then drive the real path — `kec.audio:play(...)` → tick →
`SendNUIMessage` — and assert on the message. Worth covering: an emitter straight ahead gives
`z = -distance`, to the right `x = +distance`, behind `z = +distance`; yaw 90° puts north on the
right; pitch 90° turns "above" into "ahead"; occlusion is 0 inside the car and `muffle` outside; and
a second tick with nothing moved sends no message at all.

Load harness + module + cases as **one** chunk, and mind that a `local` in the module shadows a
harness local of the same name (`local tick`, the timer handle, will eat a helper called `tick`).

**2. The audio graph, in a browser.** Build the SPA, serve `html/` statically and drive it with
`postMessage`, exactly like previewing any other NUI. `window.__kecAudio` exposes `{ ctx, master,
sources }`, so a test can hang a `ChannelSplitter` plus two `AnalyserNode`s off the master and
inject an oscillator straight into a source's `filter` — no media autoplay needed. That measures the
production graph: panning left/right separation, and the high band collapsing when occlusion goes
to 1.

**3. The relay, end to end.**

```bash
curl -X POST http://127.0.0.1:30122/api/audio/resolve \
     -H "x-api-key: $API_KEY" -H "content-type: application/json" \
     -d '{"url":"https://youtu.be/jNQXAC9IVRw"}'

curl -r 0-1000 -D - "http://127.0.0.1:30122/api/audio/stream/<id>?t=<token>" -o /dev/null
```

The second one should answer `206` with a `content-range` header and an audio content type. Also
worth checking that the bad paths refuse: no API key on `resolve` (401), a non-YouTube URL (400), no
token on `stream` (403), and a token with a tampered expiry (403).

**In game**, the throwaway resource `[gameplay]/audio_test` registers `/musica <link>`,
`/musicacoche <link>` and `/musicastop`. Its commands are unrestricted on purpose so they can be run
from the chat in a local session — delete the folder and its `scripts.cfg` line before going live,
or it is an open megaphone.


## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `faltan las convars audio_api_url / audio_api_key` | txAdmin or a bare FXServer: the devkit did not pass the launch arguments. Set them in `server.cfg`. |
| `el relay no resolvió el link` with a timeout | the relay is not running, or `audio_api_url` points somewhere else |
| `el vídeo no tiene ninguna pista de audio suelta` | outdated yt-dlp, or a private / region-blocked / age-gated video |
| The title prints but nothing is heard | mixed content (see *TLS*), the CEF blocking autoplay, or the emitter is out of `maxDistance` |
| It is heard, but flat and unpositioned | the emitter has no `entity` / `netId` / `coords`, so it is 2D |
| It is never muffled from outside | `space` resolved to `"open"` — the coords are not inside an interior, or the entity had not streamed in when it started. Force `space` and `muffle`. |
| Everyone starts the song from the beginning | the emitter is being re-created instead of reused; only `resolve` + one `play` should happen, and late joiners are served by the registry |
| Changing `TUNING` does nothing | the SPA was not rebuilt: `cd svelte-src && bun run build` |

## Files

| File | Role |
|---|---|
| `internal/client/audio_nui.lua` | emitter registry, 20 Hz tick, camera-space transform, occlusion, KVP volume, façade export |
| `internal/server/audio.lua` | emitter registry, clock sync, snapshots, `resolve`, façade export |
| `svelte-src/src/audio.ts` | the Web Audio graph and every sound dial (`TUNING`) |
| `init.lua` | rebuilds `kec.audio` from the export on both sides |
| `scripts/core/audio.ts` | yt-dlp resolver, token signing, streaming relay |
| `scripts/core/configs.ts` | `AUDIO_CONFIG.port` (`AUDIO_PORT`, default 30122) |
| `scripts/core/serverManager.ts` | passes `audio_api_url` / `audio_api_key` to FXServer |






# Audio (`kec.audio`)

Positional audio streaming: play a URL — a YouTube track resolved by the server, an internet radio
stream, a local `.ogg` — anywhere in the world, in 3D, and muffle it as much as you want.

GTA's own audio engine cannot do this: it plays pre-baked containers (`.awc` + `dat54` metadata),
not arbitrary URLs. So the sound is produced by **kecore's CEF** through the Web Audio API, which
brings the three things the game engine will not give you: an HRTF panner that places the sound
around the listener's head, a low-pass filter that imitates a wall, and reverb so that what is
playing indoors sounds like it is indoors.

This is an **engine, not a system**. It does what can only be done from in here — resolve an
emitter's entity, transform the world into camera space, send the CEF only what changed — and holds
no opinion about *why* something sounds muffled. That is one number, `occlusion`, and the resource
that owns the emitter sets it with whatever rule it likes: a venue looks at its interior and its
door, a car looks at whether you are riding in it, something else could cast a ray. Every consumer
brings its own rule and inherits nobody else's.

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
internal/client/audio_nui.lua  20 Hz tick: world → camera space, carries occlusion
       │ SendNUIMessage
       ▼
svelte-src/src/audio.ts        AudioContext: <audio> → wall (2 lowpass) → gain → HRTF → master
       │ <audio src>                                  └→ send → shared convolver (reverb bus)
       ▼
scripts/core/audio.ts          yt-dlp (cached) → track downloaded once to cache/audio/ → swept at 24 h
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
    occlusion = 0.0,                -- how much wall it starts behind
    flat = false                    -- start with the panner bypassed
})

kec.audio:occlusion(id, 0.85) -> boolean   -- 0..1; false if that emitter does not exist here
kec.audio:flat(id, true) -> boolean        -- bypass the panner: the track's own mix
kec.audio:position(id, x, y, z)            -- move it; also takes (id, vector3)
kec.audio:attach(id, entity)               -- or have it follow something
kec.audio:list() -> string[]               -- ids alive on this client
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
    -- track = { id, url, title, duration, isLive }

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

-- Search instead of asking for a link. Results are not playable: pick one and resolve its `id`,
-- which `resolve` takes as-is.
kec.audio:search("bruno mars", 10, function(results, err)
    if not results then return kec.log:error("vehmenu", err) end
    -- results = { { id, title, duration, channel }, ... }

    kec.audio:resolve(results[1].id, function(track) ... end)
end)
```

`search` runs one `yt-dlp --flat-playlist`, so it costs a single call no matter how many results come
back: each entry carries only what the search page already knew, and no format is resolved until
something is picked. It is capped at ten — it is a list to choose from, not a catalogue.

`target = nil` means everyone, **including whoever connects later**. The remaining options are the
client ones (`volume`, `loop`, `offset`, `refDistance`, `maxDistance`, `occlusion`, `flat`).

Note that occlusion is *per listener*, so a server-side value is only a starting point: the real one
is pushed by whatever client-side rule owns that emitter.

---

## Occlusion

Occlusion is a single number, `0..1`, that travels to the CEF with the position at 20 Hz. **kecore
does not compute it.** It cannot know whether your music is behind a wall, inside a car or out in the
open, and guessing was exactly what tied every consumer to one model — so the resource that owns the
emitter sets it, with whatever rule it wants:

```lua
kec:setInterval(function()
    -- your rule, whatever it is: rooms, distance to a door, a raycast, a coin flip
    kec.audio:occlusion(id, muffled and 0.85 or 0.0)
end, 100)
```

Two rules worth copying live in the repo already: `[gameplay]/disco/client/impl.lua` (interior +
doorway) and `[gameplay]/core/client/vehicle/radio.lua` (are you riding in that car), the second one
published as a library so any resource can load it with `@core/client/vehicle/radio.lua`.

Call `occlusion` only when the number actually changes. From another resource it crosses a VM (it is
an export), so per frame is expensive; a 2 % threshold in the caller is inaudible and turns a walking
player into a handful of calls. It returns `false` if that emitter does not exist on this client yet
— which is normal when the server created it — so a caller that records "already pushed" should only
do so when it returns true.

Since the emitter is often created by the server, two **local** events say when there is something to
drive:

```lua
kec:onLocal("kec:audio:started", function(id) end)
kec:onLocal("kec:audio:stopped", function(id) end)
```

Those only cover what happens while you are listening. Anything already playing when your resource
started — the usual case after a `restart` — never fires `started` for you, so seed from
`kec.audio:list()` once at load or the rule will sit there driving nothing:

```lua
for _, id in ipairs(kec.audio:list()) do live[id] = true end
```

### What the number does

The mapping is exponential (the ear hears in octaves), so the result is *not* linear in it: at `1.0`
the low-pass sits at `LOWPASS_SHUT` (300 Hz), the volume at 35 % and the reverb send at 0.70, while
at 0.9 the corner has already moved up to 456 Hz and at 0.85 to ~560 Hz. **A venue wants 1.0** — at
0.9, 500 Hz still walks through nearly untouched, which is exactly what "you can hear the song
clearly from the street" sounds like.

The wall is **two cascaded lowpasses** (24 dB/octave), not one. Measured in a browser with an
analyser on the master bus, drop from occlusion 0 to 1:

| 100 Hz | 200 Hz | 500 Hz | 1 kHz | 2 kHz | 6 kHz |
|---|---|---|---|---|---|
| −7 dB | −6 dB | −23 dB | −49 dB | −74 dB | −112 dB |

That shape *is* the effect: the kick and the bassline get through the wall and everything carrying
the melody does not. With a single filter (12 dB/octave) 500 Hz only lost 12 dB and 1 kHz 29 dB, and
the result sounded like the same music slightly duller rather than a club heard from the pavement.

### How long a change takes

The transition is **rate-limited, not fixed**: `FILTER_RAMP` (250 ms) is the floor and `FILTER_SWEEP`
(1 s) is what a whole 0 → 1 change would take, so the duration is proportional to the size of the
jump. The two consumers need very different things from it. A doorway arrives as small, frequent
pushes — the disco's rule pushes 10 times a second — and only needs one push joined to the next, which
is the 250 ms floor. Getting into a car is a single 0.85 jump, and at 250 ms that is a switch rather
than a transition: it now sweeps over ~850 ms, about as long as a door takes to close.

Two things are exempt. The **first message** for an emitter is applied instantly — it is the state the
emitter starts in, not a transition, so music in a car starts already muffled instead of opening up
and closing on its own over a second. And a ramp is always anchored at the instant it is requested
(`ramp()` in `audio.ts`): a Web Audio ramp interpolates from the *last event on the timeline*, and
since occlusion is only touched when you cross a door or a car body, that event can be minutes old —
measured, a 250 ms ramp requested 2 s after the last event starts 89 % of the way to its target, which
is a jump with extra steps. That was what made getting into a car sound like a switch.

### Flat: no panner

`kec.audio:flat(id, true)` bypasses the panner and gives you the track's own mix.

The panner positions sound relative to the **camera**, and GTA's chase camera sits several metres
behind the car. Sitting inside, that made the music arrive from up ahead, swing around whenever the
camera swung, and lose volume to distance attenuation. Flat is what a speaker surrounding you
actually sounds like. Measured: from outside at 5 m to the right, L −38 dB / R −33 dB; flat, both
channels equal and ~8 dB louder, because the direct path skips the distance rolloff.

A big interior does **not** want this. A nightclub is big, you walk around inside it, and the music
has to stay at the DJ booth.

Both output paths (through the panner and around it) are wired up permanently and crossfaded over the
same duration as the filter — they always travel in the same message — so switching does not click.
While an emitter is flat, positions stop being sent altogether — it only reports when the mode or the
occlusion changes, since nobody is listening to a panner. The message that reports the switch back
carries the position of that moment, and the panner is snapped to it rather than ramped, so the sound
does not sweep in from wherever the emitter was when it went flat.

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

### Out of range: paused

An emitter that is out of earshot still cost a stream, because the panner silences it but the
`<audio>` element keeps pulling bytes — and a `target = nil` emitter is sent to *every* player. So
the CEF **pauses the element** past `maxDistance × TUNING.CULL_MARGIN` (1.5), and a spatial emitter
does not start at all until the first position says it is within that radius (`preload = 'none'`;
with `'auto'` merely assigning `src` downloads the whole track, measured: `readyState` 4 without a
single `play()`).

Coming back into range needs the right second, and that costs nothing either: `offset` already said
where the track was when the emitter arrived, and from then on it advances at one second per second
on every machine. The CEF stores the instant of the track's second 0 (`epoch`, from
`performance.now`) and computes `elapsed % duration` on resume. **No clock handshake with the server
is involved** — the docs used to list one as the fix for this; it is not needed.

Two cases are exempt: 2D emitters (they have no position) and the vehicle you are riding in
(`d = true`), which is audible at any distance by definition.

The 1.5× margin exists so the re-buffer happens where nothing can be heard yet. Ceiling: arriving at
100 km/h, the music may start half a second late.

## Tuning

Two tables, two scopes. Both are the only place their values live:

- `TUNING` in `svelte-src/src/audio.ts` — the *sound*: filter cutoffs, gain floor, reverb wet/dry,
  ramp lengths, impulse-response length, plus `CULL_MARGIN` (how far past `maxDistance` the element
  is paused). Changing it requires rebuilding the SPA.
- `DEFAULTS` in `internal/client/audio_nui.lua` — the *world*: default volume, distances. Plus
  `TICK_MS` (20 Hz) and `MOVE_EPSILON` (5 cm dead-band). How much a wall eats is **not** here: that is
  the number each consumer pushes.

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
| `POST /api/audio/search` | `x-api-key` header | runs `yt-dlp --flat-playlist -J` over `ytsearchN:<query>` and returns up to ten `{ id, title, duration, channel }`; resolves no formats |
| `GET /api/audio/stream/:id?t=…` | signed token in the URL | downloads the track **once** to `cache/audio/<id>.<ext>` and serves it with `res.sendFile`; a live stream has no end to store, so that one stays a per-listener pipe |

The client therefore sees **one stable URL** with working `Range` requests — which is what the
`offset` seek needs — and no CORS to negotiate.

Why to disk instead of piping upstream per request: forty players listening to the same track used to
mean forty downloads from googlevideo *on top of* forty uploads to players — the same bytes fetched
forty times. From disk, upstream is paid once. It also removes a whole class of failure: a file does
not expire mid-song, so the "URL expired, wipe the cache and re-resolve" path only ever runs on the
first download, and a seek is served locally instead of by a fresh upstream range request.

### Retention: 24 h

Nothing stays on disk indefinitely. `sweep()` deletes everything in `cache/audio/` whose mtime is
older than `CACHE_TTL_MS` (24 h) — the audio, its `.json` sidecar and any `.part` a relay killed
mid-download left behind — and runs once at startup plus every `SWEEP_EVERY_MS` (1 h), so the real
ceiling is 25 h.

It is deliberately **not an LRU**: serving a file does not touch its mtime, so the clock runs from the
download and a track played every day expires and is fetched again anyway. The point is a hard
retention ceiling, not a hot set.

Sweeping a track that is still playing costs nothing — a finite `<audio>` is buffered whole (see
*Bandwidth*), so no further request is ever made for it. A player who arrives after it was swept
re-resolves and re-downloads: the sweep drops that id from the in-memory URL cache too, so what
follows is a normal cold start instead of the 502 that a stale `fromDisk` entry would produce. On
Windows a file being served cannot be unlinked, so that one is simply left for the next sweep.

> **Trap worth knowing:** googlevideo **throttles a request with no `Range` header** to roughly
> playback speed. Measured on the same URL: 26 KB/s without it, 5.5 MB/s with `Range: bytes=0-` —
> 150× and it is the *presence* of the header that matters, not the chunking. The old code never hit
> this because the ranged requests were the CEF's own. `download()` therefore asks for `bytes=0-`
> even though it wants the whole file; without that line a 4-minute song takes ~2 minutes to cache
> and the first listener waits for all of it.

Concurrent cold requests are deduplicated by an in-flight map keyed by file, so five players
arriving at once produce one download (`audio: bajando <id>` appears once in the log). The file is
written as `<id>.<ext>.part` and renamed on completion, so a relay killed mid-download never leaves a
truncated track behind to be served.

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

The cost of a track with an end is its **file size, once per player who gets close enough to hear
it** — not a sustained bitrate. Two things make that true, and both were measured:

- A finite `<audio>` with a known `content-length` is buffered whole and then loops off the buffer.
  Checked in Chromium with a 3.84 MB file: exactly one request (`Range: bytes=0-`), three loops over
  25 s, zero further requests, `buffered` covering the full duration. So a 4-minute song at 128 kbps
  is ~4 MB per player and then silence on the wire, however long the club stays open.
- Players out of range download nothing at all (see *Out of range: paused*). A spatial emitter that
  never comes within `maxDistance × 1.5` produces zero requests.

A **live stream** is the case that still costs continuously: it cannot be buffered ahead, the relay
cannot cache it, and it is ~130 kbps per listener downstream *plus* one googlevideo connection per
listener upstream. If a venue can use a looping track instead of a radio stream, that is the whole
optimisation.

What is left, in order of laziness:

1. Fewer kbps: raise the floor in `pickAudio` and take a lower-bitrate track.
2. `target` the players who should get it — only worth it for something private, since range culling
   already stops the bytes for everyone who cannot hear it.

There is no way around the per-player downstream copy: HTTP has no multicast.

### 7. If the relay goes down

`kec.audio:resolve` calls back with an error, so a resource that checks `track` will just not start
the music. Emitters already playing keep whatever the CEF has buffered — a looping track that was
fully downloaded does not even notice — and anything that still needs bytes stalls. They stay in the
server registry, so a `stop`/`play` cycle restores them once the relay is back. Nothing on the game
server crashes. Tracks still in `cache/audio/` survive a relay restart, so they come back without
touching YouTube — as long as they are inside the 24 h window (see *Retention*); the startup sweep
clears whatever aged out while the relay was down.

---

## Known limits

Deliberate simplifications, each with its upgrade path. They are marked `ponytail:` in the code.

- **No occlusion of its own.** The engine carries the number and never works it out, so an emitter
  nobody drives is heard clean through everything. That is the point, not an oversight.
- **No station / queue.** One track per emitter, looping or not. A server-side queue that advances
  by itself and broadcasts track changes goes on top without touching the engine.
- **The disk cache is time-bounded, not use-bounded.** Anything older than 24 h goes, however popular
  it is, so a venue looping the same track pays one re-resolve and one re-download a day. A per-serve
  `utimesSync` would turn it into an LRU — at the cost of a hot track living on disk forever, which is
  exactly what the 24 h rule exists to prevent.
- **Culling pauses, it does not release.** What a source already downloaded stays in memory while you
  are away, which is what makes coming back instant. Dropping the `src` (as `stop` does) would free
  it at the cost of re-buffering on every return.
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
right; pitch 90° turns "above" into "ahead"; whatever `occlusion` and `flat` were last set to comes
back out in `o` and `d`; and a second tick with nothing moved and nothing set sends no message at all.

The same harness runs a consumer's rule: load `[gameplay]/disco/shared/header.lua` plus its
`client/impl.lua` with `kec.audio` faked, and assert the number it pushes for a listener inside the
room, out on the street and standing in the doorway.

Load harness + module + cases as **one** chunk, and mind that a `local` in the module shadows a
harness local of the same name (`local tick`, the timer handle, will eat a helper called `tick`).

**2. The audio graph, in a browser.** Build the SPA, serve `html/` statically and drive it with
`postMessage`, exactly like previewing any other NUI. `window.__kecAudio` exposes `{ ctx, master,
sources }`, so a test can hang an `AnalyserNode` off the master and inject an oscillator straight into
a source's `wall[0]` — no media autoplay needed, and a `url` that 404s keeps the element silent so the
oscillator is the only signal. That measures the production graph: panning left/right separation, and
the per-frequency drop of the wall (the table under *Space and occlusion* was produced this way —
sweep a few frequencies at `o = 0`, then at `o = 1`, and subtract).

Range culling needs real media, so serve a generated WAV from the same throwaway server and have it
log every request. Worth asserting, all from one `op: 'play'` plus hand-made `op: 'pos'` messages:
a spatial emitter is `paused` with **zero** requests until a position puts it inside
`maxDistance × 1.5`; it pauses again when one puts it outside; on return `currentTime` equals
`(paused_at + seconds_away) % duration` (30 ms was the observed error); and `d = true` keeps it
playing at 200 m. Autoplay needs a user gesture that a click cannot give — the overlay covers the
page and Playwright reports *"html intercepts pointer events"* — so send a keypress instead.

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

With the disk cache there are two more properties to check, both visible from `curl`. Delete
`cache/audio/` first, then request the same path twice: the cold one should still be fast (~50 ms for
a 250 KB track — if it takes seconds, the `Range: bytes=0-` in `download()` got lost and googlevideo
is throttling), and the warm one a few milliseconds. Then delete the file again and fire five
requests at once with `&`: the relay log must print `audio: bajando <id>` exactly once, and no
`.part` file may be left behind.

The sweep needs no curl, and must not be pointed at the real cache: `AUDIO_CACHE_PATH` is
`path.resolve("cache", "audio")`, so running from a throwaway cwd puts it there instead. Create
`cache/audio/` in a scratch directory, back-date some files with `utimesSync` (25 h), then import the
module and call `startAudioAPI()` with `AUDIO_PORT` on a free port — the startup sweep is the real one.
Assert the back-dated `.webm`, `.json` and `.webm.part` are gone and the fresh pair is untouched.

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
| It is never muffled | nothing is pushing `occlusion` for that emitter — the engine never muffles on its own. Check the rule's tick is running and that `kec.audio:occlusion` is not returning false (the emitter has not arrived on this client yet) |
| Everyone starts the song from the beginning | the emitter is being re-created instead of reused; only `resolve` + one `play` should happen, and late joiners are served by the registry |
| The music starts a moment late as you arrive | the re-buffer after culling; raise `TUNING.CULL_MARGIN` |
| Nothing is heard and the relay was never asked for the track | the emitter is spatial and no position has put it inside `maxDistance × 1.5` yet (an entity that has not streamed in sends no position at all) |
| The first listener of a new track waits a long time | the cold download is being throttled: check `download()` still sends `Range: bytes=0-` |
| Changing `TUNING` does nothing | the SPA was not rebuilt: `cd svelte-src && bun run build` |

## Files

| File | Role |
|---|---|
| `internal/client/audio_nui.lua` | emitter registry, 20 Hz tick, camera-space transform, occlusion/flat setters, KVP volume, façade export |
| `internal/server/audio.lua` | emitter registry, clock sync, snapshots, `resolve`, façade export |
| `svelte-src/src/audio.ts` | the Web Audio graph, range culling / resume, and every sound dial (`TUNING`) |
| `init.lua` | rebuilds `kec.audio` from the export on both sides |
| `scripts/core/audio.ts` | yt-dlp resolver, token signing, disk cache, streaming relay |
| `scripts/core/configs.ts` | `AUDIO_CONFIG.port` (`AUDIO_PORT`, default 30122), `AUDIO_CACHE_PATH` |
| `scripts/core/serverManager.ts` | passes `audio_api_url` / `audio_api_key` to FXServer |






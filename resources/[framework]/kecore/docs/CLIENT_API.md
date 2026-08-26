# Client API

## Native Player Methods (`native`)

The client API exposes the global `native` object for interacting with the local player ped.

```lua
native:spawn(coords, heading, modelHash)
native:setCoords(x, y, z, heading)
native:getHealth()
native:setHealth(health)
native:togglePvp(toggle)
native:setModel(modelHash)
native:toggleInfiniteStamina(toggle)
native:setComponentVariation(componentId, drawableId, textureId, paletteId)
```

---

## Key Bindings (`kec.keys`)

Allows registering key mappings using FiveM's native `RegisterKeyMapping`.

```lua
kec.keys:bind({
    name = "myAction",
    description = "Key description",
    Mapper = "KEYBOARD",
    Key = "LSHIFT",
    keydown = function()
        -- Executed when key is pressed
    end,
    keyup = function()
        -- Executed when key is released
    end
})
```

---

## 2D and 3D Labels (`label2d` / `label3d`)

### 2D Floating UI Notifications

Drawn by kecore's own NUI (`svelte-src/src/Label2d.svelte`), not by `DrawText`. Inside the text,
`{rrggbbaa}` (or `{rrggbb}`) colours whatever comes **after** it and `{}` restores the base colour.

```lua
kec.label2d:success("Operation successful", 2000)
kec.label2d:error("An error occurred", 2000)
kec.label2d:warning("Warning", 2000)
kec.label2d:info("hello {43ff64d9}it's me")

kec.label2d:showText("Notice", {
    color = "43ff64d9",                -- or { r = 67, g = 255, b = 100 }
    duration = 2000,
    position = { x = 0.5, y = 0.83 },  -- screen fractions; y is the top edge
    align = "center",                  -- "center" | "left" | "right"
    size = 22,                         -- px at 1080p, scales with screen height
    font = "chalet",                   -- "chalet" | "oswald" | "pricedown" | <CSS family>
    weight = 400,
    shadow = true,
    outline = true, outlineWidth = 1, outlineColor = "000000"   -- on by default
})
```

One notice at a time: a new one replaces the previous. The module lives once in
`internal/client/label2d_nui.lua` (never transpiled into `performance/`); other resources reach it
through its export, which `@kecore/init.lua` wraps back into `kec.label2d`. Defaults live in the
`DEFAULTS` table of that file.

### In-World 3D Text

```lua
local label = kec.label3d:new()
label:filter({
    text = "Point of Interest",
    scale = { x = 0.4, y = 0.4 },
    colors = { r = 255, g = 255, b = 255, a = 255 }
})
label:render(x, y, z)
```

---

## Client Vehicle (`kec.vehicle`)

```lua
local veh = kec.vehicle:get(entity)

veh:repair()
veh:serializeMods()
veh:applyMods(props)
veh:setDirtLevel(0.0)
veh:setStreamSyncedMeta(key, value, replicate)
```

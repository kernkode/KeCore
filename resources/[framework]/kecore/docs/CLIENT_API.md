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

```lua
kec.label2d:success("Operation successful", 2000, { scale = 0.4 })
kec.label2d:error("An error occurred", 2000, { scale = 0.4 })
kec.label2d:warning("Warning", 2000, { scale = 0.4 })
kec.label2d:info("Information", 2000, { scale = 0.4 })
```

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

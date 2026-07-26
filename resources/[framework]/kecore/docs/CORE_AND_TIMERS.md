# Core and Timers

## Shared Core

The global `kec` table provides environment utilities and shared state management.

```lua
kec:isServer() -- Returns true if currently running on the server
kec:isClient() -- Returns true if currently running on the client
kec:hash(str)  -- Generates a FiveM GetHashKey
```

### Shared State (`kec.state`)

To avoid using Lua's global environment table `_G`, KeCore provides `kec.state` to store variables across different files within the same resource or framework cleanly.

```lua
-- Save state variable
kec.state.concussionEndTime = GetGameTimer() + 5000

-- Read state variable from another script
if kec.state.concussionEndTime and GetGameTimer() < kec.state.concussionEndTime then
    -- Player is currently concussed
end
```

### Logging System

Unified logging system with color support and log levels (`debug`, `info`, `warn`, `error`).

```lua
kec.log:debug(module, text, ...) -- Visible only when kec.debugMode = true
kec.log:info(module, text, ...)
kec.log:warn(module, text, ...)
kec.log:error(module, text, ...)
```

---

## Timers

KeCore replaces traditional `Citizen.CreateThread` loops with an optimized timer system that automatically cleans up active threads when a resource stops.

### `kec:everyTick(fn[, waitMs])`
Executes the function every frame (or every `waitMs` milliseconds).

```lua
local tick = kec:everyTick(function()
    -- Logic executed per tick/frame
    if finished then
        return false -- Automatically stops the tick
    end
end)

-- Manually cancel
tick:cancel()
```

### `kec:setInterval(fn, ms)`
Executes the function repeatedly after every specified time interval in milliseconds.

```lua
local interval = kec:setInterval(function(id)
    print("1 second has passed")
end, 1000)

interval:cancel()
```

### `kec:setTimeout(fn, ms)`
Executes the function once after the specified delay in milliseconds.

```lua
local timeout = kec:setTimeout(function()
    print("Executed after 2 seconds")
end, 2000)
```

### Timer Handle Methods
All timers return a handle object with the following methods:
- `cancel()`: Cancels the active timer.
- `isRunning()`: Returns `true` if the timer is currently running.
- `kec:clearTimer(id)`: Clears the timer by its ID.

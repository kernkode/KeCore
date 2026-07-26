# Events and RPC

## Event System

KeCore wraps Citizen/FiveM event handling, making it easy to listen to and emit local and network events.

```lua
-- Event Listeners
kec:on("eventName", function(data) ... end)
kec:onLocal("localEventName", function(data) ... end)

-- Event Emitters
kec:emit("event", ...)
kec:emitServer("serverEvent", ...)
kec:emitClient("clientEvent", targetSource, ...)
kec:emitAllClients("allClientsEvent", ...)
```

### Specialized Event Wrappers

KeCore provides direct callbacks for common resource lifecycle and player events:

```lua
-- Resource Lifecycle
kec:on_resource_start(function(resourceName) ... end)
kec:on_resource_stop(function(resourceName) ... end)

-- Player (Server / Client)
kec:on_player_loaded(function(player) ... end)
kec:on_player_death(function(victim, killer, reason) ... end)
kec:on_player_spawn(function() ... end)

-- Client
kec:on_raycast_entity(function(entity) ... end)
kec:on_entered_vehicle(function(vehicle, seat) ... end)
kec:on_exit_vehicle(function(vehicle, seat) ... end)

-- Server
kec:on_player_connected(function(source) ... end)
kec:on_player_disconnect(function(source, reason) ... end)
```

---

## RPC System (Remote Procedure Calls)

Facilitates bidirectional asynchronous calls between client and server.

### Registering an RPC

```lua
-- Register RPC on server or client
kec.rpc:register("getData", function(source, arg1)
    return { status = "ok", data = arg1 }
end, true) -- true for network RPC (default), false for local
```

### Calling an RPC (`await`)

```lua
-- On Client (awaiting server response)
local res = kec.rpc:await("getData", 5000, "parameter")

-- On Server (awaiting target client response)
local res = kec.rpc:await("getClientData", 5000, targetSource, "parameter")
```

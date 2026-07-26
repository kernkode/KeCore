# Server API

## Player (`kec:player`)

On the server, `kec:player(source)` returns an object-oriented wrapper for player interactions.

```lua
local player = kec:player(source)

player:spawn(coords, heading, modelHash)
player:getCoords()
player:emit("eventName", ...)
player:kick("Kick reason")
player:setInfo(key, value)
player:getInfo(key)
player:setStreamSyncedMeta(key, value)
```

---

## Server Vehicle (`kec.vehicle`)

Server-side vehicle creation and manipulation.

```lua
-- Create new vehicle
local veh = kec.vehicle:new("adder", vector4(0.0, 0.0, 72.0, 0.0))

-- Get wrapper for existing entity
local veh = kec.vehicle:get(entity)

veh:setNumberPlate("ROLEPLAY")
veh:setPrimaryColor(255, 0, 0)
veh:setEngineHealth(1000.0)
veh:repair()
veh:destroy()
```

---

## MongoDB and Schemas (BSON / Models)

KeCore includes an asynchronous ORM/ODM for MongoDB with Zod schema validation.

```lua
-- Register Schema
kec.mongodb:schema("Character", {
    collection = "characters",
    schema = { 
        type = "object", 
        properties = { name = { type = "string" } },
        required = { "name" }
    }
})

-- Use Model
local Character = kec.mongodb:model("Character")

-- Create Document
local id, err = Character:create({ name = "John Doe" })

-- Queries
local doc, err = Character:findOne({ name = "John Doe" })
local docs, err = Character:find({ status = "active" })
```

---

## HTTP Client / Axios (`kec.axios`)

```lua
kec.axios:get("https://api.example.com/data", {}, function(err, response)
    if not err then
        print(response.data)
    end
end)
```

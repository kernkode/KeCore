-- Mongo models call these central registry functions dynamically. The singleton registry loaded
-- next replaces the placeholders before any gameplay resource can register a schema.
kec.mongoSchemaRegister = function() return "schema registry is not ready" end
kec.mongoSchemaGet = function() return nil end

local chunk = LoadResourceFile("kecore", "internal/modules/load.lua")
if not chunk then error("[kecore] missing internal/modules/load.lua") end

local loadModules, err = load(chunk, "@@kecore/internal/modules/load.lua")
if not loadModules then error("[kecore] module loader does not compile: " .. tostring(err)) end
loadModules()("server", { kec = kec, owner = "kecore" })

local chunk = LoadResourceFile("kecore", "internal/modules/load.lua")
if not chunk then error("[kecore] missing internal/modules/load.lua") end

local loadModules, err = load(chunk, "@@kecore/internal/modules/load.lua")
if not loadModules then error("[kecore] module loader does not compile: " .. tostring(err)) end
loadModules()("client", { kec = kec, owner = "kecore", setNative = function(value) native = value end })

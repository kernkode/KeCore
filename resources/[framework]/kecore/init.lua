local context = IsDuplicityVersion() and "server" or "client"
local resourceName = "kecore"

local function loadChunk(path, ...)
    local chunk = LoadResourceFile(resourceName, path)
    if not chunk then error("[kecore] missing " .. path, 0) end

    local compiled, err = load(chunk, "@@kecore/" .. path)
    if not compiled then error("[kecore] " .. path .. " does not compile: " .. tostring(err), 0) end
    return compiled(...)
end

local function facade(exportName, methods)
    local module = {}
    for _, method in ipairs(methods) do
        module[method] = function(_, ...)
            local resource = exports[resourceName]
            return resource[exportName](resource, method, ...)
        end
    end
    return module
end

---@type table
kec = setmetatable(exports[resourceName]:get() or {}, {
    __index = function() return {} end
})

-- Read the convar directly: the compatibility metatable above returns a truthy table for a
-- missing key, which would accidentally enable development-only code against an older kecore.
local devConvar = GetConvar("kec_dev", "0")
kec.dev = devConvar == "1" or devConvar == "true"

local okSnapshot, snapshot = pcall(function() return exports[resourceName]:stateSnapshot() end)
local stateValues = (okSnapshot and type(snapshot) == "table") and snapshot or {}

metadata = kec.metadata or { player = {}, vehicle = {}, object = {} }
kec.metadata = metadata

if context == "client" then
    native = {}
    kec.label2d = facade("label2d", {
        "showText", "success", "error", "info", "warning", "hide", "clear"
    })
    kec.audio = facade("audio", {
        "play", "stop", "stopAll", "occlusion", "flat", "position", "attach", "list",
        "setVolume", "setMasterVolume", "getMasterVolume"
    })

    AddEventHandler("kec:onPlayerLoaded", function()
        kec.isWorldLoaded = true
    end)
else
    kec.audio = facade("audio", { "play", "stop", "list", "resolve", "search" })
end

local stateFactory = loadChunk("internal/modules/shared/state.lua")
kec.state = stateFactory(stateValues, GetCurrentResourceName())

local loadModules = loadChunk("internal/modules/load.lua")
loadModules(context, {
    kec = kec,
    owner = GetCurrentResourceName(),
    setNative = function(value) native = value end
})

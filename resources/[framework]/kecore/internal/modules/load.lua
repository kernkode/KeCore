local RESOURCE = "kecore"
local ROOT = "internal/modules/"

local function read(path, targetKec, owner)
    local chunk = LoadResourceFile(RESOURCE, path)
    if not chunk then return nil, "file not found" end

    local compiled, err = load(chunk, ("@@%s/%s"):format(RESOURCE, path))
    if not compiled then return nil, "syntax error: " .. tostring(err) end

    local ok, value = pcall(compiled, targetKec, owner)
    if not ok then return nil, "runtime error: " .. tostring(value) end
    if type(value) ~= "table" then return nil, "module did not return a table" end
    return value
end

local function install(entry, module, targetKec, options)
    local target = entry.target
    if target == "native" then
        if options.setNative then options.setNative(module) else native = module end
        return
    end

    if target ~= "/" then
        if entry.extend then
            local namespace = rawget(targetKec, target) or {}
            for key, value in pairs(module) do namespace[key] = value end
            targetKec[target] = namespace
        else
            targetKec[target] = module
        end
        return
    end

    for key, value in pairs(module) do
        targetKec[key] = value
    end
end

local function loadManifest()
    local chunk = LoadResourceFile(RESOURCE, ROOT .. "manifest.lua")
    if not chunk then return nil, "manifest not found" end

    local compiled, err = load(chunk, "@@kecore/internal/modules/manifest.lua")
    if not compiled then return nil, "manifest syntax error: " .. tostring(err) end

    local ok, manifest = pcall(compiled)
    if not ok then return nil, "manifest runtime error: " .. tostring(manifest) end
    if type(manifest) ~= "table" then return nil, "manifest did not return a table" end
    return manifest
end

return function(context, options)
    options = options or {}
    local manifest, manifestErr = loadManifest()
    if not manifest then error("[kecore] " .. manifestErr, 0) end

    local targetKec = options.kec or kec
    local owner = options.owner or GetCurrentResourceName()
    local errors = {}
    for _, entry in ipairs(manifest) do
        if not entry.side or entry.side == context then
            local module, err = read(entry.path, targetKec, owner)
            if module then
                install(entry, module, targetKec, options)
            else
                errors[#errors + 1] = ("- %s (%s)"):format(entry.path, err)
            end
        end
    end

    if #errors > 0 then
        error("[kecore] one or more modules failed to load:\n" .. table.concat(errors, "\n"), 0)
    end
end

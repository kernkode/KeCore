kec:on("kec:clearMetadata", function(section, id)
    metadata[section][tostring(id)] = nil
end)

kec:on("kec:setSyncedMeta", function(section, source, key, value)
    print("kec:setSyncedMeta", section, source, key, value)
    if source ~= nil and key ~= nil then
        local src = tostring(source)
        metadata[section][src] = metadata[section][src] or {}
        metadata[section][src][tostring(key)] = value
    end
end)

kec:on("kec:updateMetadata", function(newMetadata)
    metadata = newMetadata
end)
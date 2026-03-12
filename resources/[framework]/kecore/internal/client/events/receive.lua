kec:on("kec:setSpawn", function(coords, heading, modelHash)
    native:spawn(coords, heading, modelHash)
end)

kec:on("kec:setCoords", function(x, y, z, rot)
    native:setCoords(x, y, z, rot)
end)

kec:on("kec:setComponentVariation", function(componentId, drawableId, textureId, paletteId)
    print("componentId: " .. componentId .. ", drawableId: " .. drawableId .. ", textureId: " .. textureId .. ", paletteId: " .. paletteId)
    native:setComponentVariation(componentId, drawableId, textureId, paletteId)
end)

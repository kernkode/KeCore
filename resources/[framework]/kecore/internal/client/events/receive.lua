kec:on("kec:setSpawn", function(coords, heading, modelHash)
    native:spawn(coords, heading, modelHash)
end)

kec:on("kec:setCoords", function(x, y, z, rot)
    native:setCoords(x, y, z, rot)
end)

kec:on("kec:setComponentVariation", function(componentId, drawableId, textureId, paletteId)
    native:setComponentVariation(componentId, drawableId, textureId, paletteId)
end)

kec:on("kec:setDlcClothes", function(collection, componentId, drawableId, textureId, paletteId)
    native:setDlcClothes(collection, componentId, drawableId, textureId, paletteId)
end)

kec:on("kec:setPropIndex", function(propId, drawableId, textureId)
    native:setPropIndex(propId, drawableId, textureId)
end)

kec:on("kec:clearProp", function(propId)
    native:clearProp(propId)
end)

kec:on("kec:setIntoVehicle", function(netId, seat)
    native:warpIntoVehicle(netId, seat)
end)

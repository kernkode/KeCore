---@class raycast
local raycast = {
    ---@class TraceFlags
    ---Banderas que definen qué tipos de entidades deben ser consideradas en el raycast
    eTraceFlags = {
        ---No considerar ningún tipo de colisión
        None = 0,
        ---Considerar colisión con el mundo/terreno
        World = 1,
        ---Considerar colisión con vehículos
        Vehicles = 2,
        ---Considerar colisión con peds/personajes
        Peds = 4,
        ---Considerar colisión con ragdolls/cuerpos físicos
        Ragdolls = 8,
        ---Considerar colisión con objetos
        Objects = 16,
        ---Considerar colisión con pickups/objetos recogibles
        Pickup = 32,
        ---Considerar colisión con vidrio
        Glass = 64,
        ---Considerar colisión con ríos/agua
        River = 128,
        ---Considerar colisión con follaje/vegetación
        Foliage = 256,
        ---Considerar colisión con todos los tipos de entidades
        Everything = 511
    },

    ---@class TraceOptionFlags
    ---Opciones adicionales para configurar el comportamiento del raycast
    eTraceOptionFlags = {
        ---Sin opciones especiales
        None = 0,
        ---Ignorar colisiones con vidrio
        IgnoreGlass = 1,
        ---Ignorar superficies transparentes/see-through
        IgnoreSeeThrough = 2,
        ---Ignorar superficies sin colisión
        IgnoreNoCollision = 4,
        ---Configuración por defecto (ignorar vidrio, transparentes y sin colisión)
        Default = 7
    },

    ---@class RaycastState
    ---Estados posibles de un raycast
    eState = {
        ---El raycast falló o no se pudo completar
        Failed = 0,
        ---El raycast está en proceso
        Pending = 1,
        ---El raycast se completó exitosamente
        Finished = 2
    }
}

function raycast:startShapeTestMouseCursor(traceFlags, entityIgnore, traceOptions)
    return StartShapeTestSurroundingCoords(traceFlags, entityIgnore, traceOptions)
end

function raycast:getShapeTestResult(handle)
    local state, isCollided, endCoords, surfaceNormal, entityHit = GetShapeTestResult(handle)
    return {
        state = state,
        isCollided = isCollided,
        endCoords = endCoords,
        surfaceNormal = surfaceNormal,
        entityHit = entityHit
    }
end

return raycast
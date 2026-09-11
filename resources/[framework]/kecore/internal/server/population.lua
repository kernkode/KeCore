local config = {
    -- activar la poblacion
    enablePopulation = GetConvarBool("ENABLE_POPULATION", false),

    -- solo el servidor puede crear entidades (Ped, Vehicles, Objects, etc)
    -- solo funciona si se activa la poblacion
    enableClientEntityCreation = GetConvarBool("ENTITY_CREATION", false),
    global_bucket = 0
}

local function applyRules(bucket)
    SetRoutingBucketPopulationEnabled(bucket, config.enablePopulation)
    SetRoutingBucketEntityLockdownMode(bucket, config.enableClientEntityCreation and "inactive" or "strict")
end

applyRules(config.global_bucket)

-- Un cubo NUEVO no nace con las reglas del mundo: FiveM le da la población encendida y el lockdown
-- en "inactive", así que una instancia cualquiera —el login de auth, un interior— traería tráfico y
-- dejaría al cliente crear entidades aunque el mundo lo tenga prohibido. Se le ponen las MISMAS la
-- primera vez que alguien entra en él, que es cuando este lado se entera de que existe.
--
-- Por el evento de `player:setBucket` y no por una API que llame quien crea la instancia: así el
-- dueño de la regla sigue siendo uno solo (este archivo) y no hay forma de estrenar un cubo sin
-- pasar por aquí.
local configured = { [config.global_bucket] = true }

kec:on_player_bucket_changed(function(_, bucket)
    if configured[bucket] then return end
    configured[bucket] = true

    applyRules(bucket)
end)

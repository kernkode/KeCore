config = {
    -- activar la poblacion
    enablePopulation = GetConvarBool("ENABLE_POPULATION", false),

    -- solo el servidor puede crear entidades (Ped, Vehicles, Objects, etc)
    -- solo funciona si se activa la poblacion
    enableClientEntityCreation = GetConvarBool("ENTITY_CREATION", false),
    global_bucket = 0
}

SetRoutingBucketPopulationEnabled(config.global_bucket, config.enablePopulation)
SetRoutingBucketEntityLockdownMode(config.global_bucket, config.enableClientEntityCreation and "inactive" or "strict")
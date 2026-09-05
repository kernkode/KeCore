
-----------------------------------------------
local state = kec.vehicle.state

-- Tipos de mod "toggle" (on/off): se manejan con ToggleVehicleMod/IsToggleModOn en vez de
-- SetVehicleMod (turbo, xenón, humo de llantas, etc.). Se excluyen del recorrido numerado.
local VEHICLE_MOD_TOGGLES = { 17, 18, 19, 20, 21, 22 }
local IS_TOGGLE_MOD = {}
for _, t in ipairs(VEHICLE_MOD_TOGGLES) do IS_TOGGLE_MOD[t] = true end

--- Lee el set completo de mods/tuning de la entidad y lo devuelve como tabla plana.
--- Sólo cubre lo que NO tiene ya su propia ruta de persistencia (extras, sirena,
--- deformación, daños, motor y posición se guardan por separado).
---@return table
function vehicle_methods:serializeMods()
    local veh = self.entity
    if not DoesEntityExist(veh) then return {} end

    -- El modkit debe estar activo para poder leer/escribir mods.
    if GetVehicleModKit(veh) == 65535 then
        SetVehicleModKit(veh, 0)
    end

    -- Mods numerados del modkit (excluyendo los toggle). -1 = sin mod (stock).
    local mods = {}
    for modType = 0, 49 do
        if not IS_TOGGLE_MOD[modType] then
            mods[tostring(modType)] = GetVehicleMod(veh, modType)
        end
    end

    -- Mods toggle (turbo, xenón, humo, etc.).
    local toggles = {}
    for _, t in ipairs(VEHICLE_MOD_TOGGLES) do
        toggles[tostring(t)] = IsToggleModOn(veh, t)
    end

    -- Neón (4 lados + color).
    local neon = {}
    for i = 0, 3 do
        neon[tostring(i)] = IsVehicleNeonLightEnabled(veh, i)
    end
    local nr, ng, nb = GetVehicleNeonLightsColour(veh)

    -- Color de humo de llantas.
    local sr, sg, sb = GetVehicleTyreSmokeColor(veh)

    return {
        wheelType      = GetVehicleWheelType(veh),
        windowTint     = GetVehicleWindowTint(veh),
        livery         = GetVehicleLivery(veh),
        roofLivery     = GetVehicleRoofLivery(veh),
        plateIndex     = GetVehicleNumberPlateTextIndex(veh),
        xenonColor     = GetVehicleHeadlightsColour(veh),
        mods           = mods,
        toggles        = toggles,
        neon           = neon,
        neonColor      = { nr, ng, nb },
        tyreSmokeColor = { sr, sg, sb },
    }
end

--- Aplica un set de mods/tuning (el producido por serializeMods) a la entidad.
--- Tolerante a nil y a valores ausentes (round-trip parcial seguro).
---@param props table|string
function vehicle_methods:applyMods(props)
    local veh = self.entity
    if not props or not DoesEntityExist(veh) then return end

    if type(props) == "string" then
        props = json.decode(props)
    end
    if type(props) ~= "table" then return end

    if GetVehicleModKit(veh) == 65535 then
        SetVehicleModKit(veh, 0)
    end

    -- El tipo de rueda debe fijarse ANTES que los mods de rueda (23/24).
    if props.wheelType ~= nil then
        SetVehicleWheelType(veh, props.wheelType)
    end

    if type(props.mods) == "table" then
        for modType, modIndex in pairs(props.mods) do
            SetVehicleMod(veh, tonumber(modType), modIndex, false)
        end
    end

    if type(props.toggles) == "table" then
        for modType, on in pairs(props.toggles) do
            ToggleVehicleMod(veh, tonumber(modType), on and true or false)
        end
    end

    if props.livery ~= nil and props.livery >= 0 then
        SetVehicleLivery(veh, props.livery)
    end
    if props.roofLivery ~= nil and props.roofLivery >= 0 then
        SetVehicleRoofLivery(veh, props.roofLivery)
    end

    if props.windowTint ~= nil then
        SetVehicleWindowTint(veh, props.windowTint)
    end

    if props.plateIndex ~= nil then
        SetVehicleNumberPlateTextIndex(veh, props.plateIndex)
    end

    if props.xenonColor ~= nil and props.xenonColor >= 0 then
        SetVehicleHeadlightsColour(veh, props.xenonColor)
    end

    if type(props.neon) == "table" then
        for index, on in pairs(props.neon) do
            SetVehicleNeonLightEnabled(veh, tonumber(index), on and true or false)
        end
    end
    if type(props.neonColor) == "table" and #props.neonColor == 3 then
        SetVehicleNeonLightsColour(veh, props.neonColor[1], props.neonColor[2], props.neonColor[3])
    end

    if type(props.tyreSmokeColor) == "table" and #props.tyreSmokeColor == 3 then
        SetVehicleTyreSmokeColor(veh, props.tyreSmokeColor[1], props.tyreSmokeColor[2], props.tyreSmokeColor[3])
    end
end

function vehicle_methods:repair()
    if not DoesEntityExist(self.entity) then return print("No existe el vehiculo") end

    SetVehicleFixed(self.entity)
    SetVehicleDeformationFixed(self.entity)
    SetVehicleBodyHealth(self.entity, 1000.0)

    Entity(self.entity).state:set(state.BROKEN_DOORS, nil, true)
    Entity(self.entity).state:set(state.BROKEN_WINDOWS, nil, true)
    Entity(self.entity).state:set(state.TYRES, nil, true)
    Entity(self.entity).state:set(state.DEFORMATION, nil, true)

    -- Y la salud sembrada al spawnear el coche. Su handler (client/vehicle/events.lua) la reaplica
    -- CADA vez que un cliente vuelve a streamear la entidad, así que dejarla con el valor de antes
    -- deshacía la reparación en cuanto el coche salía y volvía a entrar en el stream —o en cuanto
    -- su dueño reconectaba y la readoptaba—. Sin statebag manda la salud real de la entidad, que
    -- es la que acaba de arreglar SetVehicleFixed.
    --
    -- Las claves a mano porque no están en `kec.vehicle.state`: son las que escriben
    -- `setEngineHealth`/`setBodyHealth` del servidor y auth al restaurar los coches.
    Entity(self.entity).state:set("engineHealth", nil, true)
    Entity(self.entity).state:set("bodyHealth", nil, true)
end

function vehicle_methods:getWindowsBroken()
    if not DoesEntityExist(self.entity) then return {} end

    local brokens = {}

    for i = 0, 7 do
        if not IsVehicleWindowIntact(self.entity, i) then
            brokens[tostring(i)] = true
        end
    end

    return brokens
end

function vehicle_methods:getDoorsBroken()
    if not DoesEntityExist(self.entity) then return {} end

    local brokens = {}

    for v = 0, GetNumberOfVehicleDoors(self.entity) - 1 do
        if IsVehicleDoorDamaged(self.entity, v) then
            brokens[tostring(v)] = true
        end
    end

    return brokens
end

function vehicle_methods:setDoorBroken(doorIndex, deleteDoor)
    local doors = self:getStreamSyncedMeta(state.BROKEN_DOORS) or {}

    doors[doorIndex] = deleteDoor
    Entity(self.entity).state:set(state.BROKEN_DOORS, doors, true)
end

function vehicle_methods:getAxleCount()
    return GetVehicleNumberOfWheels(self.entity) / 2
end

function vehicle_methods:getTyresBurst()
    if not DoesEntityExist(self.entity) then return {} end

    local wheels = self:getAxleCount()

    local tyres = {}
    for _, index in pairs(kec.vehicle.tyreIndexes[wheels] or {}) do
        tyres[tostring(index)] = IsVehicleTyreBurst(self.entity, index, false) == 1 and true or false
    end

    return tyres
end

function vehicle_methods:getIndexsTyres()
    if not DoesEntityExist(self.entity) then return {} end

    local wheels = self:getAxleCount()
    return kec.vehicle.tyreIndexes[wheels]
end

function vehicle_methods:setTyreBurst(index, broken)
    if broken then
        SetVehicleTyreBurst(self.entity, index, true, 1000)
    else
        SetVehicleTyreFixed(self.entity, index)
    end
end

function vehicle_methods:fixTyre(index)
    SetVehicleTyreFixed(self.entity, index)
end

function vehicle_methods:setStreamSyncedMeta(key, value, replicate)
    Entity(self.entity).state:set(key, value, replicate ~= false)
end

function vehicle_methods:getStreamSyncedMeta(key)
    return Entity(self.entity).state[key]
end

--- Establece el nivel de suciedad del vehiculo (0.0 = limpio, 15.0 = max sucio).
--- Aplica directamente el native en el cliente.
---@param level number 0.0 a 15.0
function vehicle_methods:setDirtLevel(level)
    if not DoesEntityExist(self.entity) then return end

    level = tonumber(level)
    if not level then return end

    SetVehicleDirtLevel(self.entity, math.max(0.0, math.min(15.0, level)))
end

--- Devuelve el nivel de suciedad del vehiculo (0.0 = limpio, 15.0 = max sucio).
---@return number
function vehicle_methods:getDirtLevel()
    if not DoesEntityExist(self.entity) then return 0.0 end

    return GetVehicleDirtLevel(self.entity)
end

-- ------------------------------------------------------------
-- La clase del vehículo, y los dos predicados que se preguntan siempre: si vuela y si se pedalea.
--
-- Viven aquí y no en cada recurso porque `GetVehicleClass` y los números que devuelve estaban
-- copiados en media docena de sitios (el arranque del motor, la gasolina, el cuadro del HUD, el
-- cinturón, el panel del coche), y cada copia traía su propia caché y su propia constante.
--
-- Es de CLIENTE: en el servidor ese native no existe, y `GetVehicleType` —el único que hay en los
-- dos lados— mete las bicis y las motos en el mismo saco.
--
-- La caché va por MODELO y no por entidad: la clase es la misma para todos los vehículos de un
-- modelo y los handles de entidad se reciclan, así que una tabla por entidad habría que barrerla
-- para que el vehículo que hereda un handle no se quede con la clase del anterior. Cada recurso
-- lleva su copia del módulo, y con ella su caché, igual que el resto de `performance/**`.
-- ------------------------------------------------------------

--- model -> clase
local classes = {}

--- La clase de este vehículo. `model` es opcional: se lo pasa quien ya lo tenga leído (`get`).
---@param entity integer
---@param model integer|nil
---@return integer
local function classOf(entity, model)
    model = model or GetEntityModel(entity)
    local class = classes[model]

    if class == nil then
        class = GetVehicleClass(entity)
        classes[model] = class
    end

    return class
end

--- Las dos preguntas, sobre la CLASE ya resuelta: así la fórmula tiene un solo dueño y `get` no
--- vuelve a leer nada para dejar los campos puestos.
local function isAircraftClass(class)
    local eClass = kec.enum.eVehicleClass

    return class == eClass.HELICOPTER or class == eClass.PLANE
end

local function isCycleClass(class)
    return class == kec.enum.eVehicleClass.CYCLE
end

--- La clase del vehículo, de `kec.enum.eVehicleClass`. Cacheada por modelo, así que se puede
--- preguntar dentro de un bucle.
---@param entity integer
---@return integer
function kec.vehicle:classOf(entity)
    return classOf(entity)
end

--- ¿Vuela? Helicópteros y aviones, los que tienen aspas o turbinas que arrancar.
---@param entity integer
---@return boolean
function kec.vehicle:isAircraft(entity)
    return isAircraftClass(classOf(entity))
end

--- ¿Es una bici? Lo que se mueve a pedales: sin motor, sin depósito, sin luces y sin cinturón.
---@param entity integer
---@return boolean
function kec.vehicle:isCycle(entity)
    return isCycleClass(classOf(entity))
end

function kec.vehicle:get(entity)
    local model = GetEntityModel(entity)
    local class = classOf(entity, model)

    local instance = {
        entity = entity,
        netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity) or 0,
        model = model,
        -- La clase y sus dos preguntas van como VALOR y no como método: no cambian mientras la
        -- entidad exista, así que se resuelven una vez aquí y se leen sin paréntesis
        -- (`veh.isAircraft`). Los métodos de abajo sí son funciones.
        class = class,
        isAircraft = isAircraftClass(class),
        isCycle = isCycleClass(class)
    }

    for methodName, methodFunction in pairs(vehicle_methods) do
        instance[methodName] = methodFunction
    end

    return instance
end

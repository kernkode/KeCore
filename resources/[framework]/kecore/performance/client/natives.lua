local native = {}

local isHealthRecharge = false
local HealthRechargeMultiplier = 1.0
local ped_variations = {}
local tickRolling = nil

local FREEMODE_MODELS = {
    male = `mp_m_freemode_01`,
    female = `mp_f_freemode_01`
}

local function isWorldLoaded()
    return exports.kecore:isWorldLoaded()
end

function native:spawn(coords, heading, modelHash)
    local oldPed = PlayerPedId()
    local player = PlayerId()

    if modelHash then
        self:setModel(modelHash)
    end

    local newPed = PlayerPedId()
    if oldPed ~= newPed then
        DeleteEntity(oldPed)
    end

    while not isWorldLoaded() do
        Wait(0)
    end

    if isWorldLoaded() then
        ShutdownLoadingScreen()
    end

    if IsPlayerDead(player) then
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, true, false)
    else
        return self:setCoords(coords.x, coords.y, coords.z, heading)
    end

    -- Limpieza de estado
    ClearPedTasksImmediately(newPed)
    ClearPlayerWantedLevel(newPed)

    SetEntityVelocity(newPed, 0.0, 0.0, 0.0)
    self:setHealth(self:getMaxHealth())

    Wait(1)
    ClearPedBloodDamage(newPed)

    native:togglePvp(true)

    self:applyDefaultClothes()

    kec:emitServer("player:spawned")
    kec:emit("player:spawned")
    print("has sido spawneado")

    -- Freeze the ped
    FreezeEntityPosition(newPed, false)
end

-- Función para establecer posición
function native:setCoords(x, y, z, heading)
    SetEntityCoords(PlayerPedId(), x, y, z)
    SetEntityHeading(PlayerPedId(), heading)
end

-- Función para obtener salud máxima
function native:getMaxHealth()
    return GetEntityMaxHealth(PlayerPedId())
end

-- Función para establecer salud
function native:setHealth(health)
    SetEntityHealth(PlayerPedId(), health)
end

-- Función para aplicar ropa por defecto
function native:applyDefaultClothes()
    local modelHash = self:getModel()

    if modelHash == FREEMODE_MODELS.male or modelHash == FREEMODE_MODELS.female then
        local default_shoes = FREEMODE_MODELS.male == modelHash and 34 or 35
        local components = {
            {0, 0, 0, 0},  -- Cara
            {2, 0, 0, 0},  -- Cabello
            {3, 0, 0, 0},  -- Brazos
            {4, 0, 0, 0},  -- Piernas
            {8, 0, 0, 0},  -- Camisa
            {6, default_shoes, 0, 0}, -- Zapatos
            {11, 0, 0, 0}  -- Chaleco
        }

        for _, component in ipairs(components) do
            -- Si no tiene alguna ropa aplicada aplica la ropa por defecto
            if not native:hasComponentVariation(component[1]) then
                native:setComponentVariation(component[1], component[2], component[3], component[4])
            end
        end
    end
end

function native:togglePvp(toggle)
    SetCanAttackFriendly(PlayerPedId(), toggle, false)
    NetworkSetFriendlyFireOption(toggle)
end

function native:getModel()
    return GetEntityModel(PlayerPedId())
end

function native:requestModel(model)
    return RequestModel(model)
end

function native:setHealthRechargeMultiplier(multiplier)
    HealthRechargeMultiplier = multiplier

    if not isHealthRecharge then
        SetPlayerHealthRechargeMultiplier(PlayerId(), HealthRechargeMultiplier)
    end

    isHealthRecharge = true
end

-- Streaming
function native:isModelInCdimage(modelHash)
    return IsModelInCdimage(modelHash)
end

function native:hasModelLoaded(modelHash)
    return HasModelLoaded(modelHash)
end

function native:releaseModel(modelHash)
    return SetModelAsNoLongerNeeded(modelHash)
end

function native:setModel(modelHash)
    local currentModel = self:getModel()
    if currentModel == modelHash then
        return false
    end

    if native:isModelInCdimage(modelHash) and IsModelValid(modelHash) then
        if currentModel == modelHash then
            return false;
        end

        native:requestModel(modelHash)

        while not native:hasModelLoaded(modelHash) do
            Citizen.Wait(0)
        end

        SetPlayerModel(PlayerId(), modelHash)
        native:releaseModel(modelHash)

        if isHealthRecharge then
            SetPlayerHealthRechargeMultiplier(PlayerId(), HealthRechargeMultiplier)
        end

        self:applyDefaultClothes()
        return true
    end

    print("^ERROR: No se pudo cargar el modelo " .. modelHash)
    return false
end

local infiniteStamina = false
-- Función para toggle de stamina infinita
function native:toggleInfiniteStamina(toggle)
    if toggle and not infiniteStamina then
        CreateThread(function()
            while infiniteStamina do
                SetPlayerStamina(PlayerId(), 100.0)
                Wait(5 * 1000)
            end
        end)
    end

    infiniteStamina = toggle
    return true
end

function native:setComponentVariation(componentId, drawableId, textureId, paletteId)
    local ped = PlayerPedId()
    SetPedComponentVariation(ped, componentId, drawableId, textureId, paletteId)

    if not ped_variations[ped] then
        ped_variations[ped] = {}
    end

    ped_variations[ped][componentId] = {
        drawable = drawableId,
        texture = textureId,
        palette = paletteId
    }
end

function native:hasComponentVariation(componentId)
    if not ped_variations[PlayerPedId()] then
        return false
    end

    return ped_variations[PlayerPedId()][componentId] ~= nil
end

function native:getComponentVariation(componentId)
    local ped = PlayerPedId()

    if not self:hasComponentVariation(componentId) then
        return {}
    end

    local data = ped_variations[ped][componentId]
    return data.drawable, data.texture, data.palette
end

-- Desactiva/Activa el ruedo con armas al apuntar
---@param toggle boolean
function native:disableRolling(toggle)
    if tickRolling ~= nil then
        if not toggle then
            tickRolling:cancel()
            tickRolling = nil
        end

        return
    end

    if not toggle then return end

    tickRolling = kec:everyTick(function()
        SetPedResetFlag(PlayerPedId(), 446, true) --Evita rodar con las armas
    end)
end

function native:getStreamSyncedMeta(ped, key)
    return Entity(ped).state[key]
end

--- Obtener metadato sincronizados
---@param key string
---@param src number ServerId
---@return nil|any
function native:getSyncedMeta(key, src)
    local serverId = tostring(src or GetPlayerServerId(PlayerId()))
    local playerData = metadata.player[serverId]
    return playerData and playerData[key] or nil
end

return native
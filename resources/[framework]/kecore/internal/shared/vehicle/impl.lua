--- #Statics Functions

--- Checks if the model is valid
---@param model integer | string
---@return boolean
function kec.vehicle:isValidModel(model)
    local modelHash

    if type(model) == "string" then
        modelHash = GetHashKey(model)
    else
        modelHash = model
    end

    -- Verificar si el hash existe en nuestra tabla
    return kec.vehicle.modelHashes[modelHash] == true
end
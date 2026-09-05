-- controls/header.lua (loaded first) seeds kec.controls with the input map;
-- preserve it instead of clobbering with a fresh table.
kec.controls = kec.controls or {}
local isCursor = false

function kec.controls:toggleCursor(toggle)
    if isCursor == toggle then
        return
    end

    isCursor = toggle

    if isCursor then
        EnterCursorMode()
    else
        LeaveCursorMode()
    end
end

function kec.controls:isCursorVisible()
    return isCursor
end

--- Deshabilita una lista o un único control en el pad especificado.
function kec.controls:disable(padIndex, control, disable)
    local pad = padIndex or 0
    local toggle = disable == nil and true or disable
    if type(control) == "table" then
        for i = 1, #control do
            DisableControlAction(pad, control[i], toggle)
        end
    else
        DisableControlAction(pad, control, toggle)
    end
end

--- Deshabilita múltiples controles pasando una tabla o un control único.
function kec.controls:disableMultiple(padIndex, controlList, disable)
    local pad = padIndex or 0
    local toggle = disable == nil and true or disable
    if type(controlList) == "table" then
        for i = 1, #controlList do
            DisableControlAction(pad, controlList[i], toggle)
        end
    else
        DisableControlAction(pad, controlList, toggle)
    end
end

--- Habilita múltiples controles pasando una tabla o un control único.
function kec.controls:enableMultiple(padIndex, controlList, enable)
    local pad = padIndex or 0
    local toggle = enable == nil and true or enable
    if type(controlList) == "table" then
        for i = 1, #controlList do
            EnableControlAction(pad, controlList[i], toggle)
        end
    else
        EnableControlAction(pad, controlList, toggle)
    end
end

--- Deshabilita un rango correlativo de controles [fromControl, toControl].
function kec.controls:disableRange(padIndex, fromControl, toControl, disable)
    local pad = padIndex or 0
    local toggle = disable == nil and true or disable
    for control = fromControl, toControl do
        DisableControlAction(pad, control, toggle)
    end
end

--- Comprueba si un control está pulsado (tanto habilitado como deshabilitado).
function kec.controls:isPressed(padIndex, control)
    local pad = padIndex or 0
    return IsControlPressed(pad, control) or IsDisabledControlPressed(pad, control)
end

--- Comprueba si un control deshabilitado está pulsado.
function kec.controls:isDisabledPressed(padIndex, control)
    return IsDisabledControlPressed(padIndex or 0, control)
end

--- Comprueba si un control acaba de ser pulsado (habilitado o deshabilitado).
function kec.controls:isJustPressed(padIndex, control)
    local pad = padIndex or 0
    return IsControlJustPressed(pad, control) or IsDisabledControlJustPressed(pad, control)
end

--- Comprueba si un control acaba de ser soltado (habilitado o deshabilitado).
function kec.controls:isJustReleased(padIndex, control)
    local pad = padIndex or 0
    return IsControlJustReleased(pad, control) or IsDisabledControlJustReleased(pad, control)
end

--- Comprueba si cualquiera de los controles indicados está pulsado en cualquiera de los pads indicados.
function kec.controls:isAnyPressed(pads, controls)
    local padList = type(pads) == "table" and pads or { pads or 0 }
    local ctrlList = type(controls) == "table" and controls or { controls }

    for p = 1, #padList do
        local pad = padList[p]
        for c = 1, #ctrlList do
            local ctrl = ctrlList[c]
            if IsControlPressed(pad, ctrl) or IsDisabledControlPressed(pad, ctrl) then
                return true
            end
        end
    end
    return false
end

--- Comprobación exhaustiva y optimizada de si el jugador está apuntando (pie, primera persona, cámara de aim o drive-by).
---
--- A manos vacías NO se apunta. Hace falta decirlo porque de las comprobaciones de abajo la mitad
--- son del BOTÓN (control 25, el click derecho), y ese se pulsa igual sin nada en la mano: sin esta
--- guarda un click derecho desarmado esconde el minimapa, el hotbar y el dinero. La guarda existía
--- en inventory (`equippedHash ~= nil`) y se perdió al traer la detección aquí.
local WEAPON_UNARMED = kec.weapons.models.WEAPON_UNARMED

function kec.controls:isAiming(ped, playerId)
    ped = ped or PlayerPedId()
    playerId = playerId or PlayerId()

    if GetSelectedPedWeapon(ped) == WEAPON_UNARMED then return false end

    return IsControlPressed(0, 25)
        or IsDisabledControlPressed(0, 25)
        or IsPlayerFreeAiming(playerId)
        or (native and native.isAimCamActive and native:isAimCamActive() or IsAimCamActive())
        or IsControlPressed(1, 25)
        or IsDisabledControlPressed(1, 25)
        or IsControlPressed(2, 25)
        or IsDisabledControlPressed(2, 25)
        or IsControlPressed(0, 68)
        or IsDisabledControlPressed(0, 68)
        or (GetPedConfigFlag(ped, 78, true) == 1)
end

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if kec.controls:isCursorVisible() then
            kec.controls:toggleCursor(false)
        end
    end
end)
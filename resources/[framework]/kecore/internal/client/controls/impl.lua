kec.controls = {}
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

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if kec.controls:isCursorVisible() then
            kec.controls:toggleCursor(false)
        end
    end
end)
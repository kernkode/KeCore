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

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        if kec.controls:isCursorVisible() then
            kec.controls:toggleCursor(false)
        end
    end
end)
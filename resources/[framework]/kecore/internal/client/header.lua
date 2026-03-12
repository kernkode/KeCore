---@class natives
native = {}
metadata = {
    player = {},
    vehicle = {}
}

---@type boolean
isWorldLoaded = false

exports('natives', function()
    return native
end)
---@class kec
kec = {
    debugMode = false,
    debugEvents = false
}

metadata = {
    player = {},
    vehicle = {},
    object = {}
}

function kec:isServer()
    return IsDuplicityVersion()
end

function kec:isClient()
    return not IsDuplicityVersion()
end

function kec:hash(str)
    return GetHashKey(str)
end

exports('get', function()
    return kec
end)

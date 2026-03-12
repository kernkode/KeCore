local keys = {}

function keys:bind(data)
    local name = data.name

    local keydown = data.keydown
    local keyup = data.keyup
    local Mapper = data.Mapper
    local Key = data.Key

    pcall(function()
        if keydown then
            RegisterCommand("+" .. name, keydown, false)
        end

        if keyup then
            RegisterCommand("-" .. name, keyup, false)
        end

        RegisterKeyMapping(string.format("+%s", name), data.description, Mapper, Key)
    end)

    return data
end

return keys
kec.label3d = {}

local model_scale = kec.zod:new({
    type = "object",
    properties = {
        x = {
            type = "number"
        },
        y = {
            type = "number"
        }
    },
    required = { "x", "y" },
    additionalProperties = false
}):compile()

local model_colors = kec.zod:new({
    type = "object",
    properties = {
        r = { type = "number" },
        g = { type = "number" },
        b = { type = "number" },
        a = { type = "number" }
    },
    required = { "r", "g", "b", "a" },
    additionalProperties = false
}):compile()

local model_text = kec.zod:new({
    type = "string",
    maxLength = 64
}):compile()

function kec.label3d:new()
    local instance = {
        center = 1,
        proportional = 1,
        font = 4,
        scale = {x = 0.4, y = 0.4},
        colors = {
            r = 255,
            g = 255,
            b = 255,
            a = 255
        },
        outline = true,
        text = "no text",
        hashText = kec:hash("no text")
    }

    function instance:render(x, y, z)
        local onScreen, _x, _y = GetScreenCoordFromWorldCoord(x, y, z)

        if not onScreen then
            return
        end

        SetTextScale(self.scale.x, self.scale.y)
        SetTextFont(self.font)
        SetTextProportional(1)
        SetTextColour(self.colors.r, self.colors.g, self.colors.b, self.colors.a)
        SetTextEntry("STRING")
        SetTextCentre(self.center)

        if self.outline then
            SetTextOutline()
        end

        AddTextComponentString(self.text)
        DrawText(_x, _y)
    end

    function instance:filter(filter)
        if filter == nil then
            return
        end

        if model_scale:check(filter.scale) then
            self.scale = filter.scale
        end

        if model_colors:check(filter.colors) then
            self.colors = filter.colors
        end

        if model_text:check(filter.text) then
            self.text = filter.text
            print(#self.text)
        end

        return self
    end

    return instance
end
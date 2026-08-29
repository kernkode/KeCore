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
        -- `GetScreenCoordFromWorldCoord` proyecta con la cámara del frame ANTERIOR, así que el
        -- punto que devuelve no es donde el motor va a pintar ese sitio del mundo en ESTE frame.
        -- A pie no se nota; en un coche a 200 km/h la cámara avanza casi un metro por frame y el
        -- desfase (más el que mete cada frame de duración distinta) hace saltar el texto arriba y
        -- abajo respecto a la cabeza. `SetDrawOrigin` ancla el dibujo en la coordenada del MUNDO y
        -- deja la proyección al motor, ya en el frame que se está pintando: el texto se queda
        -- quieto sobre el ped a cualquier velocidad. La proyección de aquí se queda solo para
        -- recortar lo que no cabe en pantalla, y en el borde un frame de desfase no se ve.
        if not GetScreenCoordFromWorldCoord(x, y, z) then
            return
        end

        SetTextScale(self.scale.x, self.scale.y)
        SetTextFont(self.font)
        SetTextProportional(self.proportional)
        SetTextColour(self.colors.r, self.colors.g, self.colors.b, self.colors.a)
        SetTextEntry("STRING")
        SetTextCentre(self.center)

        if self.outline then
            SetTextOutline()
        end

        AddTextComponentString(self.text)

        -- Con el origen puesto, el DrawText va en OFFSET desde el punto proyectado: (0,0) ES el
        -- punto. Y se limpia en el acto, que el origen es global al frame.
        SetDrawOrigin(x, y, z, 0)
        DrawText(0.0, 0.0)
        ClearDrawOrigin()
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
        end

        return self
    end

    return instance
end
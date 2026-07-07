kec.cam = {}

--- Verifica si un handle de camara es valido
local function IsValidCam(handle)
    return handle and handle ~= 0 and DoesCamExist(handle)
end

--- Crea una nueva instancia de camara controlada por script
function kec.cam:new()
    local handle = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)

    if not IsValidCam(handle) then
        kec.log:error("kec.cam", "Fallo al crear la camara (handle: " .. tostring(handle) .. ")")
        return nil
    end

    local instance = {
        pos = nil,
        rot = nil,
        handle = handle,
        active = false,
        filter = {}
    }

    --- Verifica si la camara sigue siendo valida
    function instance:isValid()
        return IsValidCam(self.handle)
    end

    --- Establece la posicion de la camara
    function instance:setCoords(coords)
        if not self:isValid() then
            kec.log:warn("kec.cam", "Intento de setCoords en camara invalida")
            return self
        end

        if not coords or type(coords) ~= "vector3" then
            kec.log:warn("kec.cam", "setCoords requiere vector3")
            return self
        end

        SetCamCoord(self.handle, coords.x, coords.y, coords.z)
        self.pos = coords
        return self
    end

    --- Establece la rotacion de la camara
    function instance:setRot(rot)
        if not self:isValid() then
            kec.log:warn("kec.cam", "Intento de setRot en camara invalida")
            return self
        end

        if not rot or type(rot) ~= "vector3" then
            kec.log:warn("kec.cam", "setRot requiere vector3")
            return self
        end

        SetCamRot(self.handle, rot.x, rot.y, rot.z, 2)
        self.rot = rot
        return self
    end

    --- Establece el FOV de la camara
    function instance:setFov(fov)
        if not self:isValid() then
            kec.log:warn("kec.cam", "Intento de setFov en camara invalida")
            return self
        end

        if not fov or type(fov) ~= "number" then
            kec.log:warn("kec.cam", "setFov requiere un numero")
            return self
        end

        SetCamFov(self.handle, fov)
        return self
    end

    --- Activa la camara y la renderiza
    function instance:enable()
        if not self:isValid() then
            kec.log:warn("kec.cam", "Intento de enable en camara invalida")
            return self
        end

        if self.active then
            return self
        end

        SetCamActive(self.handle, true)
        RenderScriptCams(true, false, 0, true, true)
        self.active = true
        return self
    end

    --- Desactiva la camara sin destruirla (opcionalmente con interpolacion)
    ---@param ease boolean -- Si true, hace transicion suave
    ---@param easeTime number -- Duracion de la transicion en ms (default 1000)
    function instance:disable(ease, easeTime)
        if not self:isValid() then
            kec.log:warn("kec.cam", "Intento de disable en camara invalida")
            return self
        end

        SetCamActive(self.handle, false)
        RenderScriptCams(false, ease or false, easeTime or (ease and 1000 or 0), true, true)
        self.active = false
        return self
    end

    --- Aplica flags/configuraciones a la camara
    function instance:flags(filter)
        if not filter then
            return self
        end

        if filter.displayRadar ~= nil then
            DisplayRadar(filter.displayRadar)
            self.filter.displayRadar = filter.displayRadar
        end

        return self
    end

    --- Restaura configuraciones modificadas por flags
    function instance:restoreFilters()
        if self.filter.displayRadar == false then
            DisplayRadar(true)
            self.filter.displayRadar = nil
        end
    end

    --- Destruye la camara y limpia recursos (SNAP instantaneo - sin interpolacion)
    function instance:destroy()
        -- Siempre restaurar filtros primero para evitar dejar el radar oculto
        self:restoreFilters()

        if self:isValid() then
            -- Desactivar SIN transicion (snap inmediato a la camara de gameplay/interpolada)
            SetCamActive(self.handle, false)
            RenderScriptCams(false, false, 0, true, true)
            self.active = false

            DestroyCam(self.handle, false)
            self.handle = nil
        else
            -- Asegurar que las camaras scripteadas se desactiven incluso si esta instancia ya no es valida
            RenderScriptCams(false, false, 0, true, true)
        end
    end

    return instance
end
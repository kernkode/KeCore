kec.cam = {}

function kec.cam:new()
    local handle = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    local instance = {
        pos = nil,
        rot = nil,
        handle = handle,
        filter = {}
    }

    function instance:setCoords(coords)
        SetCamCoord(handle, coords.x, coords.y, coords.z)
        self.pos = coords
        return self
    end

    function instance:setRot(_rot)
        SetCamRot(handle, _rot.x, _rot.y, _rot.z, 2)
        self.rot = _rot
        return self
    end

    function instance:destroy()
        if self.filter.diplayRadar == false then
            DisplayRadar(true)
        end

        DestroyCam(handle, false)
        RenderScriptCams(false, false, 0, true, true)
    end

    function instance:setFov(fov)
        SetCamFov(handle, fov)
        return self
    end

    function instance:enable()
        SetCamActive(handle, true)
        RenderScriptCams(true, false, 0, true, true)
        return self
    end

    function instance:flags(filter)
        if filter.diplayRadar ~= nil then
            DisplayRadar(filter.diplayRadar)
            self.filter.diplayRadar = filter.diplayRadar
        end
        return self
    end

    function instance:disable()
        SetCamActive(handle, false)
        RenderScriptCams(false, false, 0, true, true)
    end

    return instance
end
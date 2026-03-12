kec.scaleform = {}

function kec.scaleform:new(scaleformName, methodName)
    local instance = {}
    local scaleformHandle = RequestScaleformMovie(scaleformName)
    local isShowing = false
    local drawThread = nil

    while not HasScaleformMovieLoaded(scaleformHandle) do
        Citizen.Wait(0)
    end

    -- Función interna para el bucle de dibujado
    local function drawLoop()
        while isShowing do
            DrawScaleformMovieFullscreen(scaleformHandle, 255, 255, 255, 255, 0)
            Citizen.Wait(0)
        end
    end

    -- Función para agregar múltiples parámetros
    function instance:addParam(slot, params)
        BeginScaleformMovieMethod(scaleformHandle, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(slot)

        -- Recorrer todos los parámetros proporcionados
        for i = 1, #params do
            local param = params[i]

            -- Determinar si es un input de control o texto normal
            if string.sub(param, 1, 1) == "~" and string.sub(param, -1) == "~" then
                ScaleformMovieMethodAddParamTextureNameString(param)
            else
                -- Para texto normal
                BeginTextCommandScaleformString("STRING")
                AddTextComponentSubstringPlayerName(param)
                EndTextCommandScaleformString()
            end
        end

        EndScaleformMovieMethod()
        return self
    end

    -- Función para mostrar el scaleform en un bucle
    function instance:show()
        if isShowing then
            return self  -- Ya está mostrando
        end

        isShowing = true

        BeginScaleformMovieMethod(scaleformHandle, methodName)
        EndScaleformMovieMethod()

        -- Crear el hilo de dibujado
        drawThread = Citizen.CreateThread(drawLoop)

        return self
    end

    -- Función para detener la visualización
    function instance:hide()
        isShowing = false

        if drawThread then
            Citizen.Wait(0)  -- Pequeña espera para asegurar que el hilo termine
        end

        return self
    end

    -- Función para verificar si está mostrando
    function instance:isShowing()
        return isShowing
    end

    -- Función para alternar la visualización
    function instance:toggle()
        if isShowing then
            return self:hide()
        else
            return self:show()
        end
    end

    -- Función para dibujar una sola vez
    function instance:drawOnce()
        BeginScaleformMovieMethod(scaleformHandle, methodName)
        EndScaleformMovieMethod()

        DrawScaleformMovieFullscreen(scaleformHandle, 255, 255, 255, 255, 0)
        return self
    end

    -- Función para limpiar el scaleform
    function instance:destroy()
        self:hide()  -- Detener la visualización primero

        SetScaleformMovieAsNoLongerNeeded(scaleformHandle)
        return nil
    end

    return instance
end
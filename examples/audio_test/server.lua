-- DESECHABLE. Comandos para oír kec.audio en local sin montar nada. Cuando el recurso de verdad
-- (una disco, la radio de un coche) esté hecho, se borra esta carpeta y su línea de scripts.cfg.
--
-- Los comandos van SIN restringir a propósito, para poder probar desde el chat en una partida
-- local. En un servidor de verdad esto sería un megáfono abierto: cualquiera podría poner lo que
-- quisiera a todo el mundo.

local ID_ZONA = "test_zona"
local ID_COCHE = "test_coche"

--- Resuelve el link y llama a `andPlay` con la pista. Un solo sitio para los errores.
local function withTrack(url, andPlay)
    if not url or url == "" then
        print("^3[audio_test] uso: /musica <link de youtube>^7")
        return
    end

    kec.audio:resolve(url, function(track, err)
        if not track then
            print(("^1[audio_test] %s^7"):format(err))
            return
        end

        print(("^2[audio_test] %s (%ss)^7"):format(track.title, track.duration))
        andPlay(track)
    end)
end

-- Sonando donde estás: si lo lanzas dentro de un interior, se autodetecta y desde fuera se oye
-- amortiguado. Es la prueba de la discoteca.
RegisterCommand("musica", function(source, args)
    local player = kec:player(source)
    if not player then return end

    local coords = player:getCoords()

    withTrack(args[1], function(track)
        kec.audio:play({
            id = ID_ZONA,
            url = track.url,
            duration = track.duration,
            coords = { x = coords.x, y = coords.y, z = coords.z },
            loop = true
        })
    end)
end, false)

-- Sonando en el coche en el que estás: se mueve con él y desde fuera se oye el bajo.
RegisterCommand("musicacoche", function(source, args)
    local player = kec:player(source)
    if not player then return end

    local vehicle = GetVehiclePedIsIn(player:ped(), false)
    if vehicle == 0 then
        print("^3[audio_test] no estás en un coche^7")
        return
    end

    withTrack(args[1], function(track)
        kec.audio:play({
            id = ID_COCHE,
            url = track.url,
            duration = track.duration,
            entity = vehicle,
            loop = true
        })
    end)
end, false)

RegisterCommand("musicastop", function()
    kec.audio:stop(ID_ZONA)
    kec.audio:stop(ID_COCHE)
end, false)

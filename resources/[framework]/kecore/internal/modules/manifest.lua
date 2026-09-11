return {
    -- Shared modules. Order matters: later modules may use earlier namespaces.
    { path = "internal/modules/shared/timers.lua", target = "/" },
    { path = "internal/modules/shared/zod.lua", target = "zod" },
    { path = "internal/modules/shared/lzwson.lua", target = "lzwson" },
    { path = "internal/modules/shared/base64.lua", target = "base64" },
    { path = "internal/modules/shared/lru_cache.lua", target = "lru_cache" },
    { path = "internal/modules/shared/utils.lua", target = "utils" },
    { path = "internal/modules/shared/enum.lua", target = "enum" },
    { path = "internal/modules/shared/weapons.lua", target = "weapons" },

    -- El catálogo de vehículos: qué modelos existen (a mano, agrupados por DLC) y la clase de GTA de
    -- cada uno. Es lo que contesta `kec.vehicle:isValidModel`, y de donde el servidor saca la clase
    -- (el native `GetVehicleClass` no existe ahí; en el cliente sí, y por eso no lo necesita).
    { path = "internal/modules/shared/vehicle/models.lua", target = "vehicle", extend = true },

    { path = "internal/modules/client/raycast.lua", target = "raycast", side = "client" },
    { path = "internal/modules/client/keys.lua", target = "keys", side = "client" },
    { path = "internal/modules/client/label3d.lua", target = "label3d", side = "client" },
    { path = "internal/modules/client/scaleform.lua", target = "scaleform", side = "client" },
    { path = "internal/modules/client/natives.lua", target = "native", side = "client" },
    { path = "internal/modules/client/player.lua", target = "player", side = "client" },
    { path = "internal/modules/client/vehicle.lua", target = "vehicle", side = "client", extend = true },
    { path = "internal/modules/client/controls.lua", target = "controls", side = "client" },
    { path = "internal/modules/client/events.lua", target = "/", side = "client" },

    { path = "internal/modules/server/os.lua", target = "os", side = "server" },
    { path = "internal/modules/server/axios.lua", target = "axios", side = "server" },
    { path = "internal/modules/server/http.lua", target = "http", side = "server" },
    { path = "internal/modules/server/discord.lua", target = "discord", side = "server" },
    { path = "internal/modules/server/mongodb.lua", target = "mongodb", side = "server" },
    { path = "internal/modules/server/events.lua", target = "/", side = "server" },
    { path = "internal/modules/server/vehicle.lua", target = "vehicle", side = "server", extend = true },
}

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_scripts {
    'internal/shared/core.lua',

    'internal/shared/enum.lua',
    'internal/shared/timers.lua',

    'internal/shared/events/manager.lua',
    'internal/shared/events/impl.lua',

    'internal/shared/rpc/header.lua',
    'internal/shared/rpc/impl.lua',
    'internal/shared/rpc/events.lua',
    --'internal/shared/rpc/test.lua',

    'internal/shared/math.lua',
    'internal/shared/utils.lua',
    'internal/shared/weapons.lua',
    'internal/shared/lru_cache.lua',
    'internal/shared/base64.lua',
    'internal/shared/zod.lua',
    'internal/shared/lzwson.lua',
    'internal/shared/hashmap.lua',

    'internal/shared/vehicle/models.lua',
    'internal/shared/vehicle/impl.lua'
}

server_scripts {
    'internal/server/events.lua',
    'internal/server/entity.lua',

    'internal/server/player/header.lua',
    'internal/server/player/methods.lua',
    'internal/server/player/player.lua',
    'internal/server/player/cleaner.lua',

    'internal/server/vehicle/header.lua',
    'internal/server/vehicle/methods.lua',
    'internal/server/vehicle/vehicle.lua',

    'internal/server/libs/os.lua',
    'internal/server/libs/axios.lua',
    'internal/server/libs/http.lua',
    'internal/server/libs/discord.lua',

    'internal/server/population.lua'
}

client_scripts {
    'internal/client/header.lua',

    'internal/client/natives/impl.lua',
    'internal/client/natives/scaleform.lua',

    'internal/client/world.lua',
    'internal/client/raycast.lua',
    'internal/client/cam.lua',
    'internal/client/keys.lua',
    'internal/client/label3d.lua',

    'internal/client/controls/header.lua',
    'internal/client/controls/impl.lua',

    'internal/client/events/custom.lua',
    'internal/client/events/receive.lua',
    'internal/client/events/metadata.lua',

    'internal/client/vehicle/header.lua',
    'internal/client/vehicle/impl.lua',
    'internal/client/vehicle/deformation.lua',
    'internal/client/vehicle/events.lua',
    'internal/client/vehicle/rpc.lua',

    'internal/client/gizmo/buffer.lua',
    'internal/client/gizmo/impl.lua',
    'internal/client/gizmo/keys.lua',
}

files {
    "init.lua",
    "performance/**.lua"
}
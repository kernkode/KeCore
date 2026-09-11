fx_version 'cerulean'
game 'gta5'
lua54 'yes'

shared_scripts {
    'internal/shared/core.lua',

    'internal/shared/events/manager.lua',
    'internal/shared/events/impl.lua',

    'internal/shared/rpc/header.lua',
    'internal/shared/rpc/impl.lua',
    'internal/shared/rpc/events.lua',

    'internal/shared/math.lua',
    'internal/shared/hashmap.lua',

    'internal/shared/vehicle/impl.lua'
}

server_scripts {
    'internal/server/bootstrap.lua',
    'internal/server/libs/mongodb_registry.lua',

    'internal/server/entity.lua',

    'internal/server/player/header.lua',
    'internal/server/player/methods.lua',
    'internal/server/player/player.lua',
    'internal/server/player/cleaner.lua',

    'internal/server/vehicle/events.lua',

    'internal/server/audio.lua',

    'internal/server/population.lua'
}

client_scripts {
    'internal/client/header.lua',
    'internal/client/bootstrap.lua',

    'internal/client/world.lua',
    'internal/client/cam.lua',
    'internal/client/label2d_nui.lua',
    'internal/client/audio_nui.lua',

    'internal/client/events/custom.lua',
    'internal/client/events/receive.lua',
    'internal/client/events/metadata.lua',

    'internal/client/vehicle/deformation.lua',
    'internal/client/vehicle/events.lua',

    'internal/client/gizmo/buffer.lua',
    'internal/client/gizmo/impl.lua',
    'internal/client/gizmo/keys.lua',
}

-- El overlay del framework (los avisos de kec.label2d) y el motor de sonido de kec.audio. El CEF
-- es de kecore porque los módulos se usan desde todos los recursos y SendNUIMessage solo llega al
-- CEF de quien la llama: ver internal/client/label2d_nui.lua y internal/client/audio_nui.lua.
-- Nunca coge foco.
ui_page 'html/index.html'

files {
    "init.lua",
    "internal/modules/**.lua",
    "html/**"
}

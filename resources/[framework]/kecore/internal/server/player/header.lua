kec._internal = kec._internal or {}
kec._internal.player = kec._internal.player or {
    info = {},
    cache = {},
    pendingCleanups = {}
}

player_info = kec._internal.player.info
player_cache = kec._internal.player.cache
pending_cleanups = kec._internal.player.pendingCleanups

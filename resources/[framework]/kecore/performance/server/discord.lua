---@class discord
local discord = {
    -- Most commonly used permissions
    permissions = {
        -- General permissions
        NONE = 0,                                     -- 0
        CREATE_INSTANT_INVITE = 0x1,              -- 1
        KICK_MEMBERS = 0x2,                       -- 2
        BAN_MEMBERS = 0x4,                        -- 4
        ADMINISTRATOR = 0x8,                      -- 8
        MANAGE_CHANNELS = 0x10,                   -- 16
        MANAGE_GUILD = 0x20,                      -- 32
        ADD_REACTIONS = 0x40,                     -- 64
        VIEW_AUDIT_LOG = 0x80,                    -- 128
        PRIORITY_SPEAKER = 0x100,                 -- 256
        STREAM = 0x200,                           -- 512
        VIEW_CHANNEL = 0x400,                     -- 1024
        SEND_MESSAGES = 0x800,                    -- 2048
        SEND_TTS_MESSAGES = 0x1000,               -- 4096
        MANAGE_MESSAGES = 0x2000,                 -- 8192
        EMBED_LINKS = 0x4000,                     -- 16384
        ATTACH_FILES = 0x8000,                    -- 32768
        READ_MESSAGE_HISTORY = 0x10000,           -- 65536
        MENTION_EVERYONE = 0x20000,               -- 131072
        USE_EXTERNAL_EMOJIS = 0x40000,            -- 262144
        VIEW_GUILD_INSIGHTS = 0x80000,            -- 524288
        CONNECT = 0x100000,                       -- 1048576
        SPEAK = 0x200000,                         -- 2097152
        MUTE_MEMBERS = 0x400000,                  -- 4194304
        DEAFEN_MEMBERS = 0x800000,                -- 8388608
        MOVE_MEMBERS = 0x1000000,                 -- 16777216
        CHANGE_NICKNAME = 0x2000000,              -- 33554432
        MANAGE_NICKNAMES = 0x4000000,             -- 67108864
        MANAGE_ROLES = 0x8000000,                 -- 134217728
        MANAGE_WEBHOOKS = 0x10000000,             -- 268435456
        MANAGE_EMOJIS_AND_STICKERS = 0x40000000,  -- 1073741824
        USE_APPLICATION_COMMANDS = 0x80000000,    -- 2147483648
        REQUEST_TO_SPEAK = 0x100000000,           -- 4294967296
        MANAGE_EVENTS = 0x200000000,              -- 8589934592
        MANAGE_THREADS = 0x400000000,             -- 17179869184
        CREATE_PUBLIC_THREADS = 0x800000000,      -- 34359738368
        CREATE_PRIVATE_THREADS = 0x1000000000,    -- 68719476736
        USE_EXTERNAL_STICKERS = 0x2000000000,     -- 137438953472
        SEND_MESSAGES_IN_THREADS = 0x4000000000,  -- 274877906944
        USE_EMBEDDED_ACTIVITIES = 0x8000000000,   -- 549755813888
        MODERATE_MEMBERS = 0x10000000000          -- 1099511627776
    }
}

---
---Obtiene la URL del avatar de Discord de un jugador de forma síncrona.
---Utiliza el wrapper de axios para realizar la petición a la API de Discord.
---@param discordId (number) El ID de Discord del jugador.
---@return string La URL del avatar del jugador o una imagen por defecto.
---
function discord:getDiscordAvatar(discordId)
    local avatarUrl = "https://archive.org/download/discordprofilepictures/discordyellow.png" -- URL por defecto si falla

    if discordId then
        local promise = promise.new()

        local config = {
            headers = {
                ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN')
            }
        }

        axios:get('https://discordapp.com/api/users/' .. discordId, config, function(err, response)
            if not err and response and response.status == 200 and response.data then
                local userData = response.data
                if userData.avatar then
                    local isAnimated = string.sub(userData.avatar, 1, 2) == 'a_'
                    avatarUrl = string.format(
                        "https://cdn.discordapp.com/avatars/%s/%s%s",
                        discordId,
                        userData.avatar,
                        isAnimated and ".gif" or ".png"
                    )
                end
            else
                print(('Error al obtener avatar de Discord para ID %s: %s'):format(discordId, err or 'respuesta_invalida'))
            end
            promise:resolve()
        end)
        Citizen.Await(promise)
    end
    return avatarUrl
end

---
---Obtiene el nombre de usuario de Discord de un jugador de forma síncrona.
---Utiliza el wrapper de axios para realizar la petición a la API de Discord.
---@param discordId (number) El ID de Discord del jugador.
---@return string El nombre de usuario de Discord o "Usuario Desconocido" si falla.
---
function discord:getDiscordUsername(discordId)
    local discordName = "Usuario Desconocido" -- Nombre por defecto si falla

    if discordId then
        local promise = promise.new()

        local config = {
            headers = {
                ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN')
            }
        }

        axios:get('https://discordapp.com/api/users/' .. discordId, config, function(err, response)
            if not err and response and response.status == 200 and response.data then
                local userData = response.data
                if userData.username then
                    -- Si tiene discriminator (ej: Usuario#1234)
                    if userData.discriminator and userData.discriminator ~= "0" then
                        discordName = userData.username .. "#" .. userData.discriminator
                    else
                        discordName = userData.username
                    end
                end
            else
                print(('Error al obtener nombre de Discord para ID %s: %s'):format(discordId, err or 'respuesta_invalida'))
            end
            promise:resolve()
        end)
        Citizen.Await(promise)
    end
    return discordName
end

---
---Obtiene el nombre de visualización de Discord (Global Name) de un jugador.
---Si no tiene un nombre global, devuelve su nombre de usuario único como respaldo.
---@param discordId (number) El ID de Discord del jugador.
---@return string El nombre de visualización de Discord o "Usuario Desconocido" si falla.
---
function discord:getDiscordDisplayName(discordId)
    local displayName = "Usuario Desconocido" -- Nombre por defecto si falla

    if discordId then
        local promise = promise.new()

        local config = {
            headers = {
                ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN')
            }
        }

        axios:get('https://discordapp.com/api/users/' .. discordId, config, function(err, response)
            if not err and response and response.status == 200 and response.data then
                local userData = response.data

                -- Prioriza el 'global_name' (el nombre "normal" o de visualización).
                -- Si este no está definido o es nulo, usa el 'username' como alternativa.
                if userData.global_name or userData.username then
                    displayName = userData.global_name or userData.username
                end
            else
                print(('Error al obtener el nombre global de Discord para ID %s: %s'):format(discordId, err or 'respuesta_invalida'))
            end
            promise:resolve()
        end)
        Citizen.Await(promise)
    end
    return displayName
end

---
---Obtiene la URL del banner de perfil de Discord de un jugador de forma síncrona.
---Utiliza el wrapper de axios para realizar la petición a la API de Discord.
---@param discordId (number) El ID de Discord del jugador.
---@return string La URL del banner del jugador o nil si no tiene banner.
---
function discord:getDiscordBanner(discordId)
    local bannerUrl = "https://i.pinimg.com/originals/02/87/d3/0287d3ba8b3330fca99f69e2001d3168.gif"

    if discordId then
        local promise = promise.new()

        local config = {
            headers = {
                ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN')
            }
        }

        axios:get('https://discordapp.com/api/users/' .. discordId, config, function(err, response)
            if not err and response and response.status == 200 and response.data then
                local userData = response.data

                -- Verificar si el usuario tiene banner
                if userData.banner then
                    local isAnimated = string.sub(userData.banner, 1, 2) == 'a_'
                    bannerUrl = string.format(
                        "https://cdn.discordapp.com/banners/%s/%s.%s?size=512",
                        discordId,
                        userData.banner,
                        isAnimated and "gif" or "png"
                    )
                end
            else
                print(('Error al obtener banner de Discord para ID %s: %s'):format(discordId, err or 'respuesta_invalida'))
            end
            promise:resolve()
        end)
        Citizen.Await(promise)
    end
    return bannerUrl
end

---
---Crea un nuevo rol en el servidor de Discord y devuelve su ID.
---@param guildId string El ID del servidor de Discord
---@param roleData table Los datos del rol a crear
---@param cb function Callback que recibe (error, roleId)
---
function discord:createRole(guildId, roleData, cb)
    if not guildId or not roleData then
        if cb then cb("guildId_y_roleData_son_requeridos", nil) end
        return
    end

    local config = {
        headers = {
            ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN'),
            ['Content-Type'] = 'application/json'
        }
    }

    axios:post(
        'https://discord.com/api/v10/guilds/' .. guildId .. '/roles',
        roleData,
        config,
        function(err, response)
            if err then
                print(('Error al crear rol en el servidor %s: %s'):format(guildId, err))
                if cb then cb(err, nil) end
                return
            end

            if response and response.data and response.data.id then
                local roleId = response.data.id
                print(('Rol creado exitosamente. ID del rol: %s'):format(roleId))
                if cb then cb(nil, roleId) end
            else
                print(('Respuesta inesperada al crear rol: %s'):format(json.encode(response)))
                if cb then cb('respuesta_invalida', nil) end
            end
        end
    )
end

---
---Versión síncrona para crear un rol (usa Citizen.Await)
---@param guildId string El ID del servidor de Discord
---@param roleData table Los datos del rol a crear
---@return string|nil roleId La ID del rol creado o nil si hubo error
---
function discord:createRoleSync(guildId, roleData)
    local promise = promise.new()

    self:createRole(guildId, roleData, function(err, roleId)
        if err then
            promise:resolve(nil)
        else
            promise:resolve(roleId)
        end
    end)

    return Citizen.Await(promise)
end

---
---Elimina un rol del servidor de Discord.
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol a eliminar
---@param cb function Callback que recibe (error, success)
---
function discord:deleteRole(guildId, roleId, cb)
    if not guildId or not roleId then
        if cb then cb("guildId_y_roleId_son_requeridos", false) end
        return
    end

    local config = {
        headers = {
            ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN', DiscordBotToken)
        }
    }

    axios:delete(
        'https://discord.com/api/v10/guilds/' .. guildId .. '/roles/' .. roleId,
        nil,
        config,
        function(err, response)
            -- Discord devuelve 204 No Content en eliminación exitosa
            -- Consideramos éxito cualquier código 2xx
            if response and (response.status >= 200 and response.status < 300) then
                --print(('Rol %s eliminado exitosamente del servidor %s'):format(roleId, guildId))
                if cb then cb(nil, true) end
            else
                local errorMsg = err or ('Código HTTP: %s'):format(response and response.status or 'desconocido')
                print(('Error al eliminar rol %s del servidor %s: %s'):format(roleId, guildId, errorMsg))
                if cb then cb(errorMsg, false) end
            end
        end
    )
end

---
---Versión síncrona para eliminar un rol (usa Citizen.Await)
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol a eliminar
---@return boolean success True si se eliminó correctamente
---
function discord:deleteRoleSync(guildId, roleId)
    local promise = promise.new()

    self:deleteRole(guildId, roleId, function(err, success)
        promise:resolve(success)
    end)

    return Citizen.Await(promise)
end

---
---Obtiene información de un rol específico
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol
---@param cb function Callback que recibe (error, roleData)
---
function discord:getRole(guildId, roleId, cb)
    if not guildId or not roleId then
        if cb then cb("guildId_y_roleId_son_requeridos", nil) end
        return
    end

    local config = {
        headers = {
            ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN')
        }
    }

    axios:get(
        'https://discord.com/api/v10/guilds/' .. guildId .. '/roles/' .. roleId,
        config,
        function(err, response)
            if err then
                print(('Error al obtener información del rol %s: %s'):format(roleId, err))
                if cb then cb(err, nil) end
                return
            end

            if response and response.data then
                if cb then cb(nil, response.data) end
            else
                if cb then cb('rol_no_encontrado', nil) end
            end
        end
    )
end

---
---Obtiene todos los roles del servidor
---@param guildId string El ID del servidor de Discord
---@param cb function Callback que recibe (error, roles)
---
function discord:getAllRoles(guildId, cb)
    if not guildId then
        if cb then cb("guildId_es_requerido", nil) end
        return
    end

    local config = {
        headers = {
            ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN')
        }
    }

    axios:get(
        'https://discord.com/api/v10/guilds/' .. guildId .. '/roles',
        config,
        function(err, response)
            if err then
                print(('Error al obtener roles del servidor %s: %s'):format(guildId, err))
                if cb then cb(err, nil) end
                return
            end

            if response and response.data then
                if cb then cb(nil, response.data) end
            else
                if cb then cb('error_obteniendo_roles', nil) end
            end
        end
    )
end

---
---Le quita un rol específico a un usuario en el servidor.
---Endpoint: DELETE /guilds/{guild.id}/members/{user.id}/roles/{role.id}
---@param guildId string El ID del servidor de Discord.
---@param targetDiscordId string El ID del usuario al que se le quitará el rol.
---@param roleId string El ID del rol que se va a quitar.
---@param cb function Callback que recibe (error, success).
---
function discord:removeUserRole(guildId, targetDiscordId, roleId, cb)
    if not guildId or not targetDiscordId or not roleId then
        if cb then cb("Faltan datos: guildId, targetDiscordId o roleId", false) end
        return
    end

    local config = {
        headers = {
            ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN'),
            ['Content-Type'] = 'application/json'
        }
    }

    axios:delete(
        'https://discord.com/api/v10/guilds/' .. guildId .. '/members/' .. targetDiscordId .. '/roles/' .. roleId,
        nil, 
        config,
        function(err, response)
            -- CORRECCIÓN:
            -- Verificamos primero si response existe y el status es 204 (Éxito sin contenido).
            -- Si es 204, ignoramos 'err' porque suele ser un error de parseo de JSON vacío.
            local isSuccess204 = response and tonumber(response.status) == 204
            local isSuccess200 = not err and response and tonumber(response.status) == 200
            
            if isSuccess204 or isSuccess200 then
                -- print(('Rol %s removido del usuario %s'):format(roleId, targetDiscordId))
                if cb then cb(nil, true) end
            else
                local errorMsg = err or ('Código HTTP: %s'):format(response and response.status or 'desconocido')
                print(('Error al quitar rol al usuario %s: %s'):format(targetDiscordId, errorMsg))
                if cb then cb(errorMsg, false) end
            end
        end
    )
end

---
---Versión síncrona para quitar un rol a un usuario.
---@param guildId string El ID del servidor.
---@param targetDiscordId string El ID del usuario.
---@param roleId string El ID del rol.
---@return boolean success True si se quitó correctamente.
---
function discord:removeUserRoleSync(guildId, targetDiscordId, roleId)
    local promise = promise.new()

    self:removeUserRole(guildId, targetDiscordId, roleId, function(err, success)
        promise:resolve(success)
    end)

    return Citizen.Await(promise)
end

---
---Modifica un rol existente en el servidor de Discord.
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol a modificar
---@param roleData table Los datos del rol a actualizar (nombre, color, permisos, etc.)
---@param cb function Callback que recibe (error, updatedRoleData)
---
function discord:modifyRole(guildId, roleId, roleData, cb)
    if not guildId or not roleId or not roleData then
        if cb then cb("guildId, roleId y roleData son requeridos", nil) end
        return
    end

    local config = {
        headers = {
            ['Authorization'] = 'Bot ' .. kec.os:getEnv('DISCORD_TOKEN'),
            ['Content-Type'] = 'application/json'
        }
    }

    axios:patch(
        'https://discord.com/api/v10/guilds/' .. guildId .. '/roles/' .. roleId,
        roleData,
        config,
        function(err, response)
            if err then
                print(('Error al modificar rol %s en el servidor %s: %s'):format(roleId, guildId, err))
                if cb then cb(err, nil) end
                return
            end

            if response and response.data then
                print(('Rol %s modificado exitosamente'):format(roleId))
                if cb then cb(nil, response.data) end
            else
                print(('Respuesta inesperada al modificar rol: %s'):format(json.encode(response)))
                if cb then cb('respuesta_invalida', nil) end
            end
        end
    )
end

---
---Versión síncrona para modificar un rol (usa Citizen.Await)
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol a modificar
---@param roleData table Los datos del rol a actualizar
---@return table|nil updatedRoleData Los datos del rol actualizado o nil si hubo error
---
function discord:modifyRoleSync(guildId, roleId, roleData)
    local promise = promise.new()

    self:modifyRole(guildId, roleId, roleData, function(err, updatedRoleData)
        if err then
            promise:resolve(nil)
        else
            promise:resolve(updatedRoleData)
        end
    end)

    return Citizen.Await(promise)
end

---
---Función específica para cambiar solo el nombre de un rol
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol a modificar
---@param newName string El nuevo nombre para el rol
---@param cb function Callback que recibe (error, success)
---
function discord:changeRoleName(guildId, roleId, newName, cb)
    if not guildId or not roleId or not newName then
        if cb then cb("guildId, roleId y newName son requeridos", false) end
        return
    end

    local roleData = {
        name = newName
    }

    self:modifyRole(guildId, roleId, roleData, function(err, updatedRoleData)
        if err then
            if cb then cb(err, false) end
        else
            if cb then cb(nil, true) end
        end
    end)
end

---
---Versión síncrona para cambiar solo el nombre de un rol
---@param guildId string El ID del servidor de Discord
---@param roleId string El ID del rol a modificar
---@param newName string El nuevo nombre para el rol
---@return boolean success True si se cambió el nombre correctamente
---
function discord:changeRoleNameSync(guildId, roleId, newName)
    local promise = promise.new()

    self:changeRoleName(guildId, roleId, newName, function(err, success)
        promise:resolve(success)
    end)

    return Citizen.Await(promise)
end

return discord
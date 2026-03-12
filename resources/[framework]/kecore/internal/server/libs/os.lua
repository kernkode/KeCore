-- Only server-side

---@class os
kec.os = {}

--- Get the value of an environment variable.
---@param key string The name of the environment variable.
---@param default? any The default value to return if the environment variable is not set.
---@return any The value of the environment variable.
function kec.os:getEnv(key, default)
    local result = exports['shared']:getEnv(key)

    if result == nil then return default end
    if result == "true" then return true end
    if result == "false" then return false end

    return result
end
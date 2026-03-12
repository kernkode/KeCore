--- Módulo de interfaz para la librería de hashing `bcrypt`.
-- Este script es solo para uso en el lado del servidor.

---@type table Importación de la librería bcrypt desde el recurso 'shared' typescript.
local bcrypt_bridge = exports.libs:bcrypt_js()

---@class bcrypt
bcrypt = {}

--- Hashea una contraseña de forma asíncrona.
-- No bloquea el hilo principal, ideal para operaciones en entornos de alta concurrencia.
---@param password string La contraseña en texto plano que se va a hashear.
---@param salt string|number La sal a utilizar, o el número de rondas para generar una.
---@param ... any Argumentos adicionales, como una función de callback `function(err, hash)`.
---@return any El valor de retorno depende de la implementación subyacente (a menudo no devuelve nada directamente, usa el callback).
function bcrypt:hash(password, salt, ...)
    return bcrypt_bridge.hash(password, salt, ...)
end

--- Hashea una contraseña de forma síncrona.
-- **Bloquea el hilo principal** hasta que se complete el hashing. Usar con precaución.
---@param password string La contraseña en texto plano que se va a hashear.
---@param salt string|number La sal a utilizar, o el número de rondas (cost factor) para generar una (p. ej., 10).
---@return string La contraseña hasheada.
function bcrypt:hashSync(password, salt)
    return bcrypt_bridge.hashSync(password, salt)
end

--- Compara una contraseña en texto plano con un hash de forma asíncrona.
-- Es la forma segura de verificar si una contraseña es correcta sin exponer el hash.
---@param password string La contraseña en texto plano a verificar.
---@param hash string El hash contra el que se va a comparar.
---@param ... any Argumentos adicionales, como una función de callback `function(err, result)`.
---@return any Depende de la implementación, usualmente maneja el resultado a través del callback.
function bcrypt:compare(password, hash, ...)
    return bcrypt_bridge.compare(password, hash, ...)
end

--- Compara una contraseña en texto plano con un hash de forma síncrona.
-- **Bloquea el hilo principal** hasta que se complete la comparación.
---@param password string La contraseña en texto plano a verificar.
---@param hash string El hash contra el que se va a comparar.
---@return boolean `true` si la contraseña coincide con el hash, `false` en caso contrario.
function bcrypt:compareSync(password, hash)
    return bcrypt_bridge.compareSync(password, hash)
end

--- Genera una sal (salt) de forma asíncrona.
-- La sal es una cadena aleatoria que se añade a la contraseña antes del hashing para mayor seguridad.
---@param rounds? number El factor de coste o número de rondas. Mayor número es más seguro pero más lento. Por defecto suele ser 10.
---@param ... any Argumentos adicionales, como un callback `function(err, salt)`.
---@return any Depende de la implementación.
function bcrypt:genSalt(rounds, ...)
    return bcrypt_bridge.genSalt(rounds, ...)
end

--- Genera una sal (salt) de forma síncrona.
-- **Bloquea el hilo principal** durante la generación.
---@param rounds? number El factor de coste (p. ej., 10).
---@return string La sal generada.
function bcrypt:genSaltSync(rounds)
    return bcrypt_bridge.genSaltSync(rounds)
end

--- Extrae la sal de un hash bcrypt existente.
-- El hash de bcrypt ya contiene la sal, esta función permite obtenerla.
---@param hash string El hash completo del que se extraerá la sal.
---@return string La porción de la sal del hash.
function bcrypt:getSalt(hash)
    return bcrypt_bridge.getSalt(hash)
end

--- Obtiene el número de rondas (factor de coste) de un hash existente.
-- Permite saber cuán "costoso" fue generar un hash específico.
---@param hash string El hash completo.
---@return number El número de rondas utilizado para crear el hash.
function bcrypt:getRounds(hash)
    return bcrypt_bridge.getRounds(hash)
end
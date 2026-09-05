-- Solo bcrypt: mongodb ya no se pide a libs, vive en kecore como `kec.mongodb`. Y el import
-- aborta entero en cuanto un módulo no está, así que pedirlo dejaba `bcrypt` en nil también.
if kec:isServer() then
    bcrypt = exports.libs:import("bcrypt")
end
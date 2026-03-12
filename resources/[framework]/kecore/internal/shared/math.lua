kec.math = {

    ---@param self any
    ---@param a number
    ---@param b number
    ---@return number
    max = function(self, a, b)
        return a > b and a or b
    end,


    ---@param self any
    ---@param a number
    ---@param b number
    ---@return number
    min = function(self, a, b)
        return a < b and a or b
    end,

    --- Convierte un vector de ángulos de Euler (en grados) a una matriz de transformación 4x4.
    ---@param euler vector3 tabla con las claves x, y, z representando los ángulos de Euler. Ej: { x = 0, y = 0, z = 0 }
    ---@return table tabla de tablas que representa la matriz 4x4.
    eulerToMatrix = function(self, euler)
        local x, y, z = euler.x, euler.y, euler.z
        local degToRad = math.pi / 180

        local cx = math.cos(x * degToRad)
        local sx = math.sin(x * degToRad)
        local cy = math.cos(y * degToRad)
        local sy = math.sin(y * degToRad)
        local cz = math.cos(z * degToRad)
        local sz = math.sin(z * degToRad)

        return {
            {cy*cz, sx*sy*cz - cx*sz, cx*sy*cz + sx*sz, 0},
            {cy*sz, sx*sy*sz + cx*cz, cx*sy*sz - sx*cz, 0},
            {-sy,   sx*cy,            cx*cy,            0},
            {0,     0,                0,                1}
        }
    end,

    --- Rota un vector 3D utilizando un cuaternión.
    ---@param v vector3 tabla que representa el vector a rotar. Ej: { x = 1, y = 0, z = 0 }
    ---@param q table tabla (array) que representa el cuaternión. Ej: { qx, qy, qz, qw }
    ---@return table nueva tabla que representa el vector rotado.
    rotateVectorByQuaternion = function(self, v, q)
        local x, y, z = v.x, v.y, v.z
        local qx, qy, qz, qw = q[1], q[2], q[3], q[4]

        local uv = {
            x = qy * z - qz * y,
            y = qz * x - qx * z,
            z = qx * y - qy * x
        }

        local uuv = {
            x = qy * uv.z - qz * uv.y,
            y = qz * uv.x - qx * uv.z,
            z = qx * uv.y - qy * uv.x
        }

        return {
            x = x + 2 * (qw * uv.x + uuv.x),
            y = y + 2 * (qw * uv.y + uuv.y),
            z = z + 2 * (qw * uv.z + uuv.z)
        }
    end,

    --- Realiza una interpolación lineal entre dos números.
    ---@param start number valor inicial (cuando t=0).
    ---@param _end number valor final (cuando t=1).
    ---@param t number factor de interpolación, usualmente entre 0.0 y 1.0.
    ---@return number valor interpolado.
    lerp = function(self, start, _end, t)
        return start * (1 - t) + _end * t;
    end,

    --- Convierte un cuaternión a una matriz de rotación 3x3.
    ---@param q table tabla (array) que representa el cuaternión en el formato {x, y, z, w}.
    ---@return table tabla de tablas que representa la matriz 3x3.
    quaternionToMatrix = function (self, q)
        local x, y, z, w = q[1], q[2], q[3], q[4]

        local xx, yy, zz = x * x, y * y, z * z
        local xy, xz, yz = x * y, x * z, y * z
        local xw, yw, zw = x * w, y * w, z * w

        local m00 = 1 - 2 * (yy + zz)
        local m01 = 2 * (xy - zw)
        local m02 = 2 * (xz + yw)

        local m10 = 2 * (xy + zw)
        local m11 = 1 - 2 * (xx + zz)
        local m12 = 2 * (yz - xw)

        local m20 = 2 * (xz - yw)
        local m21 = 2 * (yz + xw)
        local m22 = 1 - 2 * (xx + yy)

        return {
            {m00, m01, m02},
            {m10, m11, m12},
            {m20, m21, m22}
        }
    end,

    --- Convierte un cuaternión a ángulos de Euler (en grados)
    ---@param q table: Cuaternión en formato {x, y, z, w}
    ---@return vector3: Ángulos de Euler en grados (pitch, yaw, roll)
    quaternionToEuler = function (self, q)
        local x, y, z, w = q[1], q[2], q[3], q[4]

        -- Normalizar el cuaternión
        local magnitude = math.sqrt(w*w + x*x + y*y + z*z)
        local nx, ny, nz, nw
        if magnitude == 0 then
            nx, ny, nz, nw = 0, 0, 0, 1
        else
            nx, ny, nz, nw = x/magnitude, y/magnitude, z/magnitude, w/magnitude
        end

        -- Convertir quaternion a matriz de rotación usando el método de la clase
        local matrix = self:quaternionToMatrix({nx, ny, nz, nw})
        local pitch, yaw, roll

        local sinPitch = -matrix[2][3]  -- matrix[2][3] equivale a matrix[1][2] en JS (indexado desde 1)
        sinPitch = math.max(-1, math.min(1, sinPitch))  -- Clamp para evitar NaN
        pitch = math.asin(sinPitch)

        -- Comprobar si estamos cerca de los polos para evitar Gimbal Lock
        if math.abs(sinPitch) < 0.99999 then
            yaw = math.atan(matrix[1][3], matrix[3][3])  -- math.atan(y,x) en Lua 5.4+
            roll = math.atan(matrix[2][1], matrix[2][2])
        else
            -- Caso de Gimbal Lock
            yaw = math.atan(-matrix[3][1], matrix[1][1])
            roll = 0
        end

        -- Convertir a grados y devolver como vector3
        local radToDeg = 180 / math.pi
        return vector3(
            pitch * radToDeg,
            yaw * radToDeg,
            roll * radToDeg
        )
    end,

    --- Convierte una matriz de rotación 3x3 a ángulos de Euler (en grados)
    ---@param matrix table: Matriz 3x3 de rotación (indexada desde 1)
    ---@return vector3: Ángulos de Euler en grados (pitch, yaw, roll)
    matrixToEuler = function (self, matrix)
        local x, y, z

        -- Lua usa indexado desde 1, ajustamos los índices
        if matrix[3][1] < 1 then
            if matrix[3][1] > -1 then
                y = math.asin(-matrix[3][1])
                x = math.atan(matrix[3][2], matrix[3][3])  -- math.atan(y,x) en Lua 5.4+
                z = math.atan(matrix[2][1], matrix[1][1])
            else
                -- Caso especial cuando matrix[3][1] = -1
                y = math.pi / 2
                x = math.atan(matrix[1][2], matrix[1][3])
                z = 0
            end
        else
            -- Caso especial cuando matrix[3][1] = 1
            y = -math.pi / 2
            x = math.atan(-matrix[1][2], -matrix[1][3])
            z = 0
        end

        -- Convertir radianes a grados
        local radToDeg = 180 / math.pi
        return vector3(x * radToDeg, y * radToDeg, z * radToDeg)
    end,

    -- Multiplica dos matrices de 4x4.
    ---@param a number[][] La primera matriz.
    ---@param b number[][] La segunda matriz.
    ---@return number[][] La matriz resultante.
    multiplyMatrices = function(self, a, b)
        local result = {}

        for i = 1, 4 do
            result[i] = {}
            for j = 1, 4 do
                result[i][j] = 0
                for k = 1, 4 do
                    result[i][j] = result[i][j] + (a[i][k] * b[k][j])
                end
            end
        end

        return result
    end,

    ---
    -- Convierte un Vector3 de rotación (ángulos de Euler en grados) a un cuaternión.
    ---@param rot vector3 El vector de rotación con claves {x, y, z} donde x=pitch, y=roll, z=yaw.
    ---@return table Un cuaternión en formato {x, y, z, w}.
    --
    eulerToQuaternion = function(self, rot)
        -- Constante para convertir grados a radianes
        local degToRad = math.pi / 180

        -- Convertimos los ángulos de grados a radianes
        local pitch = rot.x * degToRad
        local roll = rot.y * degToRad
        local yaw = rot.z * degToRad

        -- Calculamos el coseno y seno de la mitad de cada ángulo
        local cy = math.cos(yaw * 0.5)
        local sy = math.sin(yaw * 0.5)
        local cp = math.cos(pitch * 0.5)
        local sp = math.sin(pitch * 0.5)
        local cr = math.cos(roll * 0.5)
        local sr = math.sin(roll * 0.5)

        -- Calculamos los componentes del cuaternión (fórmula de conversión Euler a Cuaternión)
        local w = cr * cp * cy + sr * sp * sy
        local x = sr * cp * cy - cr * sp * sy
        local y = cr * sp * cy + sr * cp * sy
        local z = cr * cp * sy - sr * sp * cy

        -- Retornamos el cuaternión como una tabla
        return {x, y, z, w}
    end,

    -- Multiplica dos cuaterniones.
    ---@param q1 table El primer cuaternión en formato {x, y, z, w}.
    ---@param q2 table El segundo cuaternión en formato {x, y, z, w}.
    ---@return table El cuaternión resultante en formato {x, y, z, w}.
    multiplyQuaternions = function(self, q1, q2)
        -- Asignamos los componentes de cada cuaternión a variables locales.
        -- Lua usa indexación base 1, así que q1[1] es x, q1[2] es y, etc.
        local x1, y1, z1, w1 = q1[1], q1[2], q1[3], q1[4]
        local x2, y2, z2, w2 = q2[1], q2[2], q2[3], q2[4]

        -- Calculamos y retornamos el nuevo cuaternión en una tabla.
        -- El orden de retorno es {x, y, z, w}.
        return {
            w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, -- Componente x resultante
            w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2, -- Componente y resultante
            w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, -- Componente z resultante
            w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2  -- Componente w resultante
        }
    end,

    -- Realiza una interpolación lineal (Lerp) entre dos vectores.
    ---@param v1 vector3 El vector de inicio en formato {x, y, z}.
    ---@param v2 vector3 El vector de destino en formato {x, y, z}.
    ---@param t number El factor de interpolación, usualmente un valor entre 0.0 y 1.0.
    ---@return vector3 El nuevo vector interpolado en formato {x, y, z}.
    lerpVector = function(self, v1, v2, t)
        return {
            x = v1.x + (v2.x - v1.x) * t,
            y = v1.y + (v2.y - v1.y) * t,
            z = v1.z + (v2.z - v1.z) * t
        }
    end,
}

function kec.math:vector3()
    --- Crea un nuevo vector3
    ---@param x number|nil Coordenada X (default: 0)
    ---@param y number|nil Coordenada Y (default: 0)
    ---@param z number|nil Coordenada Z (default: 0)
    ---@return table Vector3 con métodos
    function new(x, y, z)
        local newVector = {
            x = x or 0,
            y = y or 0,
            z = z or 0
        }

        --- Normaliza el vector (longitud = 1)
        ---@return table Nuevo vector normalizado
        function newVector:normalize()
            local length = math.sqrt(self.x^2 + self.y^2 + self.z^2)
            -- Evitar división por cero
            if length > 0 then
                return shared.math.vector3.new(
                    self.x / length,
                    self.y / length,
                    self.z / length
                )
            end
            return shared.math.vector3.new(0, 0, 0)
        end

        --- Calcula la longitud/magnitud del vector
        ---@return number Longitud del vector
        function newVector:length()
            return math.sqrt(self.x^2 + self.y^2 + self.z^2)
        end

        --- Representación string del vector
        ---@return string String formateado
        function newVector:toString()
            return string.format("Vector3(%.2f, %.2f, %.2f)", self.x, self.y, self.z)
        end

        --- Suma con otro vector
        ---@param other table Otro vector3
        ---@return table Nuevo vector resultante
        function newVector:add(other)
            return shared.math.vector3.new(
                self.x + other.x,
                self.y + other.y,
                self.z + other.z
            )
        end

        --- Producto punto con otro vector
        ---@param other table Otro vector3
        ---@return number Valor del producto punto
        function newVector:dot(other)
            return self.x * other.x + self.y * other.y + self.z * other.z
        end

        --- Producto cruz con otro vector
        ---@param other table Otro vector3
        ---@return table Nuevo vector resultante
        function newVector:cross(other)
            return shared.math.vector3.new(
                self.y * other.z - self.z * other.y,
                self.z * other.x - self.x * other.z,
                self.x * other.y - self.y * other.x
            )
        end

        return newVector
    end
end

function kec.math:bitsToFloat(intVal)
    return string.unpack("f", string.pack("I4", intVal))
end
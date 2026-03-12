kec.gizmo = {}

scaleform = nil

Buffer.__index = Buffer

Buffer.EndBig, Buffer.EndLittle = ">", "<"

function Buffer:_ef(big) return big and self.EndBig or self.EndLittle end

function Buffer:_pack(offset, code, value)
    local packed = self.blob:blob_pack(offset, code, value)
    if self.cangrow or packed == self.blob then
        self.blob = packed
        self.length = #packed
        return true
    end
end

function Buffer:Buffer() return self.blob end
function Buffer:ByteLength() return self.length end
function Buffer:ByteOffset() return self.offset end

function Buffer:SubView(offset, length)
    return setmetatable({
        blob = self.blob,
        length = length or self.length,
        offset = 1 + (offset or 0),
        cangrow = false
    }, Buffer)
end

for label, datatype in pairs(Buffer.Types) do
    Buffer["Get" .. label] = function(self, offset, endian)
        offset = (offset or 0)
        if offset < 0 then return nil end
        local pos = self.offset + offset
        local v = self.blob:blob_unpack(pos, self:_ef(endian) .. datatype.code)
        return v
    end

    Buffer["Set" .. label] = function(self, offset, value, endian)
        offset = offset or 0
        if offset < 0 or value == nil then return self end
        local pos = self.offset + offset
        local size = (datatype.size < 0 and #value) or datatype.size
        if not self.cangrow and pos + size - 1 > self.length then
            error("cannot grow dataview")
        end
        if not self:_pack(pos, self:_ef(endian) .. datatype.code, value) then
            error("cannot grow subview")
        end
        return self
    end
end

for label, datatype in pairs(Buffer.FixedTypes) do
    local prefix = "c"
    Buffer["GetFixed" .. label] = function(self, offset, typelen, endian)
        if not typelen or (offset or 0) < 0 then return nil end
        local pos = self.offset + offset
        if pos + typelen - 1 > self.length then return nil end
        return self.blob:blob_unpack(pos, self:_ef(endian) .. prefix .. typelen)
    end

    Buffer["SetFixed" .. label] = function(self, offset, typelen, value, endian)
        if not typelen or value == nil or (offset or 0) < 0 then return self end
        local pos = self.offset + offset
        if not self.cangrow and pos + typelen - 1 > self.length then
            error("cannot grow dataview")
        end
        if not self:_pack(pos, self:_ef(endian) .. prefix .. typelen, value) then
            error("cannot grow subview")
        end
        return self
    end
end

function Buffer.new(length, blob)
    return setmetatable({
        blob = blob or string.blob(length or 0),
        length = length or 0,
        offset = 1,
        cangrow = true
    }, Buffer)
end

local function normalizeVec(v)
    local len = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if len == 0 then return vector3(0.0, 0.0, 0.0) end
    local inv = 1 / len
    return vector3(v.x * inv, v.y * inv, v.z * inv)
end

local function makeEntityMatrix(entity)
    local f, r, u, a = GetEntityMatrix(entity)
    return Buffer.new(64)
        :SetFloat32(0, r[1]):SetFloat32(4, r[2]):SetFloat32(8, r[3]):SetFloat32(12, 0)
        :SetFloat32(16, f[1]):SetFloat32(20, f[2]):SetFloat32(24, f[3]):SetFloat32(28, 0)
        :SetFloat32(32, u[1]):SetFloat32(36, u[2]):SetFloat32(40, u[3]):SetFloat32(44, 0)
        :SetFloat32(48, a[1]):SetFloat32(52, a[2]):SetFloat32(56, a[3]):SetFloat32(60, 1)
end

local function RotationToEuler(forward, right, up)
    forward, right, up = normalizeVec(forward), normalizeVec(right), normalizeVec(up)

    local fz = math.max(-1.0, math.min(1.0, forward.z))
    local pitch = math.deg(math.asin(fz))
    local roll = -math.deg(math.atan(right.z, up.z))
    local yaw = math.deg(math.atan(-forward.x, forward.y))
    return pitch, roll, yaw
end

local function applyEntityMatrix(entity, view)
    local tx, ty, tz = view:GetFloat32(48), view:GetFloat32(52), view:GetFloat32(56)
    local forward = vector3(view:GetFloat32(16), view:GetFloat32(20), view:GetFloat32(24))
    local right   = vector3(view:GetFloat32(0), view:GetFloat32(4), view:GetFloat32(8))
    local up      = vector3(view:GetFloat32(32), view:GetFloat32(36), view:GetFloat32(40))

    SetEntityCoordsNoOffset(entity, tx, ty, tz, false, false, false)

    local pitch, roll, yaw = RotationToEuler(forward, right, up)
    SetEntityRotation(entity, pitch, roll, yaw, 2, true)
end

local function CrossProduct(a, b)
    return vector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
end

local function DrawPlayerGizmo(entity)
    local forward = normalizeVec(GetEntityForwardVector(entity))
    local up = vector3(0.0, 0.0, 1.0)
    local right = normalizeVec(CrossProduct(forward, up))
    up = normalizeVec(CrossProduct(right, forward))

    local matrixBuffer = makeEntityMatrix(entity)
    if DrawGizmo(matrixBuffer:Buffer(), "Editor1") then
        applyEntityMatrix(entity, matrixBuffer)
    end
end

local entitySelected, tick

function kec.gizmo:use(entity)
    if self:isRunning() then return end

    scaleform = kec.scaleform:new("INSTRUCTIONAL_BUTTONS", "DRAW_INSTRUCTIONAL_BUTTONS")
    scaleform:addParam(0, {"~INPUT_FRONTEND_RDOWN~", "Terminar"})
    scaleform:addParam(1, {"~INPUT_MOVE_UP_ONLY~", "Movimiento"})
    scaleform:addParam(2, {"~INPUT_RELOAD~", "Rotación"})
    scaleform:show()

    entitySelected = entity

    if GetEntityType(entity) ~= 1 then
        SetEntityDrawOutline(entity, true)
    end

    if DoesEntityExist(entity) then
        FreezeEntityPosition(entity, true)
        tick = kec:everyTick(function()
            if DoesEntityExist(entity) then
                DrawPlayerGizmo(entity)
            else
                self:stop()
            end
        end)
    end
end

function kec.gizmo:stop()
    if tick and tick:isRunning() then
        tick:cancel()
    end
    if entitySelected and DoesEntityExist(entitySelected) then
        FreezeEntityPosition(entitySelected, false)
        scaleform:destroy()

        if GetEntityType(entitySelected) ~= 1 then
            SetEntityDrawOutline(entitySelected, false)
        end

        kec:emit("kec:onGizmoStop", entitySelected)
    end
    entitySelected = nil
end

function kec.gizmo:isRunning()
    return tick and tick:isRunning() or false
end

AddEventHandler("onResourceStop", function(resourceName)
    
end)
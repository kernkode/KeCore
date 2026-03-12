Buffer = {}

local packSizes = {
    j = string.packsize("j"),
    J = string.packsize("J"),
    n = string.packsize("n")
}

Buffer.Types = {
    Int8   = { code = "i1", size = 1 },
    Uint8  = { code = "I1", size = 1 },
    Int16  = { code = "i2", size = 2 },
    Uint16 = { code = "I2", size = 2 },
    Int32  = { code = "i4", size = 4 },
    Uint32 = { code = "I4", size = 4 },
    Int64  = { code = "i8", size = 8 },
    Uint64 = { code = "I8", size = 8 },
    Float32 = { code = "f", size = 4 },
    Float64 = { code = "d", size = 8 },
    LuaInt  = { code = "j", size = packSizes.j },
    ULuaInt = { code = "J", size = packSizes.J },
    LuaNum  = { code = "n", size = packSizes.n },
    String  = { code = "z", size = -1 }
}

Buffer.FixedTypes = {
    String = { code = "c" },
    Int    = { code = "i" },
    Uint   = { code = "I" }
}

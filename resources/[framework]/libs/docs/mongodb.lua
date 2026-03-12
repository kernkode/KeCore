local result = mongodb:collection('accounts'):projection({ _id = 0, email = 1}):find({ discord = "1290152069872877592" })

local ret = mongodb:collection("characters")
    :projection({ _id = 0, slot = 1, firstname = 1, lastname = 1}) -- Extrae campos especificos
    :sort({ _id = 1 }) -- Ordena por identifiers
    :find({ account_id = "6970b5fd16035c2cf185beb9" }) -- Busca por identificador

print("ret: " .. json.encode(ret))

local result = mongodb:collection('accounts'):projection({ _id = 0, discord = 1}):find({ discord = "1290152069872877592" })
print("services: " .. json.encode(result))

local ret = mongodb:collection("characters")
    :projection({ _id = 0, slot = 1, firstname = 1, lastname = 1})
    :sort({ _id = 1 })
    :find({ account_id = "6970b5fd16035c2cf185beb9" })

print("ret: " .. json.encode(ret))

print("result: " .. json.encode(mongodb:collection('accounts'):projection({ _id = 1}):find({ discord = "1290152069872877592" })))

print("id: " .. kec.rpc:awaitLocal("accounts:get_account_id", nil, "1290152069872877592"))
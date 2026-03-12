local libs = {
    mongodb = mongodb,
    bcrypt = bcrypt
}

exports('import', function(...)
    local args = {...}
    local results = {}

    for i, module in ipairs(args) do
        if not libs[module] then
            print(("^1[libs] El módulo '%s' no existe. Ejecución abortada.^0"):format(module))
            return nil
        end

        results[i] = libs[module]
    end

    return table.unpack(results, 1, #results)
end)
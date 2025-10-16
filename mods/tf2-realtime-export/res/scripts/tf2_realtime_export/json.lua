local M = {}

local function escape(str)
    local replacements = {
        ["\\"] = "\\\\",
        ['"'] = '\\"',
        ['\b'] = "\\b",
        ['\f'] = "\\f",
        ['\n'] = "\\n",
        ['\r'] = "\\r",
        ['\t'] = "\\t",
    }
    return str:gsub('[\\"\b\f\n\r\t]', replacements)
end

local function encodeValue(value, buffer, stack)
    local t = type(value)
    if t == "nil" then
        table.insert(buffer, "null")
    elseif t == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            table.insert(buffer, "null")
        else
            table.insert(buffer, tostring(value))
        end
    elseif t == "boolean" then
        table.insert(buffer, value and "true" or "false")
    elseif t == "string" then
        table.insert(buffer, '"' .. escape(value) .. '"')
    elseif t == "table" then
        if stack[value] then
            error("circular table detected while encoding JSON")
        end
        stack[value] = true

        local isArray = true
        local maxIndex = 0
        for k, _ in pairs(value) do
            if type(k) ~= "number" then
                isArray = false
                break
            else
                if k > maxIndex then maxIndex = k end
            end
        end

        if isArray then
            table.insert(buffer, "[")
            for i = 1, maxIndex do
                if i > 1 then
                    table.insert(buffer, ",")
                end
                encodeValue(value[i], buffer, stack)
            end
            table.insert(buffer, "]")
        else
            table.insert(buffer, "{")
            local first = true
            for k, v in pairs(value) do
                if first then
                    first = false
                else
                    table.insert(buffer, ",")
                end
                table.insert(buffer, '"' .. escape(tostring(k)) .. '":')
                encodeValue(v, buffer, stack)
            end
            table.insert(buffer, "}")
        end

        stack[value] = nil
    else
        table.insert(buffer, '"' .. escape(tostring(value)) .. '"')
    end
end

function M.encode(value)
    local buffer = {}
    local stack = {}
    local ok, err = pcall(encodeValue, value, buffer, stack)
    if not ok then
        print("[TF2ANALYTICS] JSON encoding failed: " .. tostring(err))
        return nil
    end
    return table.concat(buffer)
end

return M

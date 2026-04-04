---@diagnostic disable: undefined-global
--- 本地存档系统
--- 使用 File API 将 GameState 序列化为 JSON 存储
local M = {}

local CACHE_PATH = "save/cache_main.json"

--- 保存游戏状态到本地
function M.save(state)
    state.timestamp = os.time()

    local ok, json_str = pcall(cjson.encode, state)
    if not ok then
        print("[SaveLocal] Encode error: " .. tostring(json_str))
        return false
    end

    fileSystem:CreateDir("save")
    local file = File(CACHE_PATH, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[SaveLocal] Failed to open for writing: " .. CACHE_PATH)
        return false
    end

    file:WriteString(json_str)
    file:Close()
    print("[SaveLocal] Saved, credits=" .. tostring(state.economy.credits))
    return true
end

--- 从本地加载游戏状态
function M.load()
    if not fileSystem:FileExists(CACHE_PATH) then
        print("[SaveLocal] No save file found")
        return nil
    end

    local file = File(CACHE_PATH, FILE_READ)
    if not file or not file:IsOpen() then
        print("[SaveLocal] Failed to open for reading")
        return nil
    end

    local raw = file:ReadString()
    file:Close()

    if not raw or raw == "" then
        print("[SaveLocal] Empty save file")
        return nil
    end

    local ok, data = pcall(cjson.decode, raw)
    if not ok then
        print("[SaveLocal] Decode error: " .. tostring(data))
        return nil
    end

    print("[SaveLocal] Loaded, credits=" .. tostring(data.economy and data.economy.credits))
    return data
end

function M.exists()
    return fileSystem:FileExists(CACHE_PATH)
end

return M

---@diagnostic disable: undefined-global
--- JSON 配置加载器
--- 懒加载 + 缓存，所有配置在用到时加载一次
local M = {}
local _cache = {}

--- 加载 JSON 配置文件（路径相对于资源根目录）
---@param path string 资源路径，如 "data/routes/routes.json"
---@return table|nil
function M.load(path)
    if _cache[path] then return _cache[path] end

    local file = cache:GetFile(path)
    if not file then
        print("[DataLoader] Failed to open: " .. path)
        return nil
    end

    local raw = file:ReadString()
    if not raw or raw == "" then
        print("[DataLoader] Empty file: " .. path)
        return nil
    end

    local ok, data = pcall(cjson.decode, raw)
    if not ok then
        print("[DataLoader] JSON parse error in " .. path .. ": " .. tostring(data))
        return nil
    end

    _cache[path] = data
    return data
end

function M.reload(path)
    _cache[path] = nil
    return M.load(path)
end

function M.clear_cache()
    _cache = {}
end

return M

--- 钟楼书院·档案阅览系统
--- 根据好感等级解锁不同层次的档案短文
--- 档案内容存储在 assets/configs/archives.json
local DataLoader = require("data_loader/loader")
local Goodwill   = require("settlement/goodwill")

local M = {}

-- 懒加载档案数据
---@type table|nil
local _entries = nil

--- 加载档案配置（懒加载）
---@return table[]
local function _load()
    if not _entries then
        local data = DataLoader.load("configs/archives.json")
        _entries = data and data.entries or {}
    end
    return _entries
end

--- 获取当前可阅读的档案列表
--- 根据 bell_tower 的好感值过滤
---@param state table
---@return table[] entries  可阅读的档案条目
function M.get_available(state)
    local entries = _load()
    local sett = state.settlements and state.settlements.bell_tower
    local gw = sett and sett.goodwill or 0
    local result = {}
    for _, entry in ipairs(entries) do
        if gw >= (entry.required_goodwill or 0) then
            table.insert(result, entry)
        end
    end
    return result
end

--- 获取所有档案（不论好感，用于统计总数）
---@return table[]
function M.get_all()
    return _load()
end

--- 标记一份档案为已读
---@param state table
---@param entry_id string
function M.mark_read(state, entry_id)
    if not state.narrative then return end
    if not state.narrative.archives_read then
        state.narrative.archives_read = {}
    end
    state.narrative.archives_read[entry_id] = true
end

--- 检查是否已读
---@param state table
---@param entry_id string
---@return boolean
function M.is_read(state, entry_id)
    if not state.narrative then return false end
    if not state.narrative.archives_read then return false end
    return state.narrative.archives_read[entry_id] == true
end

--- 已读计数
---@param state table
---@return number read, number total
function M.get_progress(state)
    local entries = _load()
    local total = #entries
    local read = 0
    if state.narrative and state.narrative.archives_read then
        for _, entry in ipairs(entries) do
            if state.narrative.archives_read[entry.id] then
                read = read + 1
            end
        end
    end
    return read, total
end

--- 获取可用但未读的条目数量（用于按钮角标）
---@param state table
---@return number
function M.get_unread_count(state)
    local available = M.get_available(state)
    local count = 0
    for _, entry in ipairs(available) do
        if not M.is_read(state, entry.id) then
            count = count + 1
        end
    end
    return count
end

--- 按 tier 分组返回可用档案
---@param state table
---@return table { public = {...}, internal = {...}, sealed = {...} }
function M.get_grouped(state)
    local available = M.get_available(state)
    local groups = { public = {}, internal = {}, sealed = {} }
    for _, entry in ipairs(available) do
        local tier = entry.tier or "public"
        if groups[tier] then
            table.insert(groups[tier], entry)
        end
    end
    return groups
end

return M

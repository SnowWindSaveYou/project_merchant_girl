--- 轻量任务追踪
--- 基于 flags 的任务发现/完成判定，不引入额外状态机
--- 任务数据来源：configs/quests.json
local DataLoader = require("data_loader/loader")
local NpcManager = require("narrative/npc_manager")

local M = {}

local DATA_PATH = "configs/quests.json"

-- ============================================================
-- 数据加载
-- ============================================================

--- 获取全部任务定义（懒加载）
---@return table[]
local function get_all_defs()
    local data = DataLoader.load(DATA_PATH)
    if not data or not data.quests then return {} end
    return data.quests
end

-- ============================================================
-- 状态查询
-- ============================================================

--- 判断单个任务状态
---@param state table gameState
---@param quest table 任务定义
---@return string status "unknown"|"active"|"completed"
local function quest_status(state, quest)
    local flags = state.flags or {}
    if flags[quest.complete_flag] then
        return "completed"
    end
    if flags[quest.trigger_flag] then
        return "active"
    end
    return "unknown"
end

--- 获取所有已触发（含完成）的任务，附带状态
---@param state table
---@return table[] items { quest, status }
function M.get_discovered(state)
    local result = {}
    for _, q in ipairs(get_all_defs()) do
        local s = quest_status(state, q)
        if s ~= "unknown" then
            table.insert(result, { quest = q, status = s })
        end
    end
    return result
end

--- 获取进行中任务
---@param state table
---@return table[] items
function M.get_active(state)
    local result = {}
    for _, q in ipairs(get_all_defs()) do
        if quest_status(state, q) == "active" then
            table.insert(result, q)
        end
    end
    return result
end

--- 获取已完成任务
---@param state table
---@return table[] items
function M.get_completed(state)
    local result = {}
    for _, q in ipairs(get_all_defs()) do
        if quest_status(state, q) == "completed" then
            table.insert(result, q)
        end
    end
    return result
end

--- 进行中任务数量
---@param state table
---@return number
function M.active_count(state)
    return #M.get_active(state)
end

--- 获取任务关联 NPC 名称
---@param npc_id string
---@return string
function M.get_npc_name(npc_id)
    local npc = NpcManager.get_npc(npc_id)
    return npc and npc.name or npc_id
end

--- 获取任务关联 NPC chibi 头像路径
---@param npc_id string
---@return string|nil
function M.get_npc_chibi(npc_id)
    local npc = NpcManager.get_npc(npc_id)
    return npc and npc.chibi or nil
end

return M

--- 基础埋点系统
--- 提供里程碑（一次性标记）和计数器（累计统计）两类追踪
local Flags = require("core/flags")

local M = {}

-- ============================================================
-- 里程碑定义
-- ============================================================

--- 里程碑前缀（与普通 flag 区分）
local MILESTONE_PREFIX = "milestone_"

--- 里程碑元数据（描述 + 检查函数）
M.MILESTONES = {
    first_trip     = { desc = "首次出发" },
    first_delivery = { desc = "首次交付订单" },
    first_combat   = { desc = "首次遭遇战斗" },
    first_explore  = { desc = "首次探索" },
    first_upgrade  = { desc = "首次升级模块" },
    credits_1000   = { desc = "累计收入达到 1000",
        check = function(state) return state.stats.total_earnings >= 1000 end },
    trips_10       = { desc = "完成 10 趟行程",
        check = function(state) return state.stats.total_trips >= 10 end },
    all_settlements = { desc = "访问全部主聚落",
        check = function(state)
            local required = { "greenhouse", "tower", "ruins_camp", "bell_tower" }
            for _, sid in ipairs(required) do
                local sett = state.settlements[sid]
                if not sett or not sett.visited then return false end
            end
            return true
        end },
}

-- ============================================================
-- 里程碑 API
-- ============================================================

--- 标记一个里程碑（幂等，重复调用无副作用）
---@param state table
---@param milestone_id string
---@return boolean newly_set 是否是本次新标记的
function M.milestone(state, milestone_id)
    local flag_id = MILESTONE_PREFIX .. milestone_id
    if Flags.has(state, flag_id) then
        return false
    end
    Flags.set(state, flag_id)
    print("[Tracker] Milestone reached: " .. milestone_id)
    return true
end

--- 查询里程碑是否已达成
---@param state table
---@param milestone_id string
---@return boolean
function M.has_milestone(state, milestone_id)
    return Flags.has(state, MILESTONE_PREFIX .. milestone_id)
end

--- 检查条件型里程碑（适合在行程结束等关键节点调用）
---@param state table
---@return string[] newly_reached 本次新达成的里程碑列表
function M.check_conditional(state)
    local newly = {}
    for mid, def in pairs(M.MILESTONES) do
        if def.check and not M.has_milestone(state, mid) then
            if def.check(state) then
                M.milestone(state, mid)
                table.insert(newly, mid)
            end
        end
    end
    return newly
end

-- ============================================================
-- 计数器 API
-- ============================================================

--- 累加计数器
---@param state table
---@param key string stats 中的字段名
---@param delta number|nil 增量，默认 1
function M.count(state, key, delta)
    delta = delta or 1
    state.stats[key] = (state.stats[key] or 0) + delta
end

--- 读取计数器
---@param state table
---@param key string
---@return number
function M.get(state, key)
    return state.stats[key] or 0
end

return M

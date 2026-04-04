--- 事件调度器
--- 行程中按时间片触发随机事件，替代旧的"到站后一次性触发"
local EventPool = require("events/event_pool")

local M = {}

-- ============================================================
-- 配置
-- ============================================================
M.CHECK_INTERVAL_MIN = 10  -- 最短检查间隔（秒）
M.CHECK_INTERVAL_MAX = 20  -- 最长检查间隔（秒）
M.TRIGGER_CHANCE     = 0.5 -- 每次检查触发事件的概率
M.MAX_EVENTS_PER_TRIP = 3  -- 单趟最多触发事件数

-- 里程节点额外检查点（进度百分比）
M.MILESTONE_CHECKS = { 0.25, 0.50, 0.75 }

-- ============================================================
-- 调度器状态初始化
-- ============================================================

--- 创建新的调度器状态（出发时调用）
function M.new_timer()
    return {
        elapsed       = 0,
        next_check_at = M._random_interval(),
        events_triggered = 0,
        milestones_hit   = {},  -- { [1]=false, [2]=false, [3]=false }
        pending_event    = nil, -- 待展示给 UI 的事件
    }
end

--- 生成随机检查间隔
function M._random_interval()
    return M.CHECK_INTERVAL_MIN
        + math.random() * (M.CHECK_INTERVAL_MAX - M.CHECK_INTERVAL_MIN)
end

-- ============================================================
-- 主调度：在 HandleUpdate 中每帧调用
-- ============================================================

--- 推进事件调度器，返回触发的事件（如果有）
---@param state table
---@param dt number
---@param progress number 当前行程总进度 [0,1]
---@param context table|nil 当前段的上下文 { edge_type, node_type }
---@return table|nil event 触发的事件
function M.update(state, dt, progress, context)
    local timer = state.flow.event_timer
    if not timer then return nil end

    -- 已达单趟上限
    if timer.events_triggered >= M.MAX_EVENTS_PER_TRIP then
        return nil
    end

    -- 如果有待处理事件还没展示，不再触发新的
    if timer.pending_event then return nil end

    timer.elapsed = timer.elapsed + dt

    local triggered_event = nil

    -- 1. 里程节点检查
    for i, milestone in ipairs(M.MILESTONE_CHECKS) do
        if not timer.milestones_hit[i] and progress >= milestone then
            timer.milestones_hit[i] = true
            triggered_event = M._try_pick(state, context)
            if triggered_event then break end
        end
    end

    -- 2. 时间片检查
    if not triggered_event and timer.elapsed >= timer.next_check_at then
        timer.elapsed = 0
        timer.next_check_at = M._random_interval()
        triggered_event = M._try_pick(state, context)
    end

    if triggered_event then
        timer.events_triggered = timer.events_triggered + 1
        timer.pending_event = triggered_event
        EventPool.set_cooldown(state, triggered_event.id, 3)
        return triggered_event
    end

    return nil
end

--- 内部：尝试按概率抽取事件
function M._try_pick(state, context)
    -- 基础概率
    local chance = M.TRIGGER_CHANCE

    -- 上下文加成
    if context then
        -- 危险边/危险节点提升触发概率
        if context.edge_type == "shortcut" then
            chance = chance + 0.15
        end
        if context.node_type == "hazard" then
            chance = chance + 0.2
        end
    end

    if math.random() > chance then return nil end

    -- 构建事件池筛选上下文
    local filter_ctx = nil
    if context then
        local tags = {}
        if context.edge_type then table.insert(tags, "route_" .. context.edge_type) end
        if context.node_type then table.insert(tags, "route_" .. context.node_type) end
        filter_ctx = {
            scene       = "drive",        -- 行驶中触发的事件
            active_tags = tags,
        }
    end

    -- 从事件池中筛选并加权抽取
    local evt = EventPool.pick(state, filter_ctx)
    return evt
end

--- 确认事件已被 UI 展示和处理
function M.clear_pending(state)
    local timer = state.flow.event_timer
    if timer then
        timer.pending_event = nil
    end
end

--- 是否有待处理事件
function M.has_pending(state)
    local timer = state.flow.event_timer
    return timer and timer.pending_event ~= nil
end

--- 获取待处理事件
function M.get_pending(state)
    local timer = state.flow.event_timer
    return timer and timer.pending_event
end

return M

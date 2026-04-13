--- 叙事导演系统
--- 主动推送主线内容，确保玩家感受到叙事的存在
--- 主线对话 (main_story) 由本系统直接弹出，不走篝火池
--- 篝火系统只负责日常对话 (daily)，与主线完全独立
local Flags        = require("core/flags")
local Flow         = require("core/flow")
local DialoguePool = require("narrative/dialogue_pool")
local EventScheduler = require("events/event_scheduler")
local Loader       = require("data_loader/loader")
local Graph        = require("map/world_graph")

local M = {}

-- ============================================================
-- 配置
-- ============================================================

-- 故事事件配置缓存
local story_events_ = nil

local function _load_story_events()
    if story_events_ then return end
    local data = Loader.load("configs/story_events.json")
    story_events_ = data and data.events or {}
end

-- 已检查过的事件 ID（避免重复入队）
-- 存储在 state.narrative._director_queued 中

-- ============================================================
-- 主线对话直接触发（不走篝火系统）
-- ============================================================

--- 检查当前是否有应自动触发的主线对话
--- 主线对话 (type=main_story) 条件满足时必须直接弹出：
---   - 不经过 Campfire.start()（不消耗篝火次数）
---   - 不依赖 audioScene="campfire"（任何场景都可触发）
---   - 玩家看完主线后仍可正常使用篝火
---@param state table
---@param include_arrival_only boolean|nil 到达时为 true，包含 arrival_only 对话
---@return table|nil dialogue  应自动触发的主线对话，nil 表示无
function M.check_pending_story_dialogue(state, include_arrival_only)
    local loc = state.map.current_location
    if not loc then return nil end

    local node = Graph.get_node(loc)
    if not node then return nil end

    -- 从对话池中筛选，找第一个 is_story 且 type=main_story 的
    local pool = DialoguePool.filter(state, node.type, { include_arrival_only = include_arrival_only })
    for _, d in ipairs(pool) do
        if d.is_story and d.type == "main_story" then
            return d
        end
    end
    return nil
end

-- ============================================================
-- 剧情事件强制入队
-- ============================================================

--- 检查所有剧情事件，条件满足且未入队的自动入队
--- 应在到达聚落、行程结束等时机调用
---@param state table
function M.check_and_queue_story_events(state)
    _load_story_events()
    if not story_events_ then return end

    -- 初始化已入队记录
    if not state.narrative._director_queued then
        state.narrative._director_queued = {}
    end

    for _, evt in ipairs(story_events_) do
        local eid = evt.event_id
        -- 已入队过则跳过
        if not state.narrative._director_queued[eid] then
            -- 检查条件是否满足
            local conditions_met = true

            -- required_flags
            if evt.required_flags then
                for _, f in ipairs(evt.required_flags) do
                    if not Flags.has(state, f) then
                        conditions_met = false
                        break
                    end
                end
            end

            -- forbidden_flags（只要任一存在就不满足）
            if conditions_met and evt.forbidden_flags then
                for _, f in ipairs(evt.forbidden_flags) do
                    if Flags.has(state, f) then
                        conditions_met = false
                        break
                    end
                end
            end

            if conditions_met then
                -- 标记已入队（防止重复）
                state.narrative._director_queued[eid] = true
                -- 强制入队
                EventScheduler.queue_story_event(state, eid)
            end
        end
    end
end

-- ============================================================
-- 到达聚落后综合检查
-- ============================================================

--- 到达聚落后调用，执行所有叙事推送逻辑
--- 主线对话由本系统直接弹出（不经过篝火），玩家看完仍可正常篝火
---@param state table
---@return table|nil action  { type="story_dialogue", dialogue } 或 nil
function M.on_node_arrival(state)
    -- 1. 检查剧情事件入队
    M.check_and_queue_story_events(state)

    -- 2. 检查主线对话自动触发（到达时包含 arrival_only 对话）
    local story_d = M.check_pending_story_dialogue(state, true)
    if story_d then
        -- 设置冷却，防止重复触发
        DialoguePool.set_cooldown(state, story_d.id, story_d.cooldown or 4)
        return { type = "story_dialogue", dialogue = story_d }
    end

    return nil
end

--- 行程结束后调用，检查剧情事件入队
---@param state table
function M.on_trip_finish(state)
    M.check_and_queue_story_events(state)
end

--- 在 home 页面每帧调用，检查是否有待自动触发的主线内容
--- 用于处理非到达场景下的主线触发（如条件刚好满足时）
---@param state table
---@return table|nil action  同 on_node_arrival
function M.check_home_auto_trigger(state)
    -- 只在 home 页面且停在节点时检查
    local curPage = require("ui/router").current()
    if curPage ~= "home" then return nil end

    -- 不在行驶中
    if Flow.get_phase(state) == Flow.Phase.TRAVELLING then return nil end

    -- 已使用过篝火不影响主线触发（主线独立于篝火）

    -- 检查主线对话自动触发（主页不包含 arrival_only 对话）
    local story_d = M.check_pending_story_dialogue(state, false)
    if story_d then
        DialoguePool.set_cooldown(state, story_d.id, story_d.cooldown or 4)
        return { type = "story_dialogue", dialogue = story_d }
    end

    return nil
end

return M

--- 地图交互模式管理
--- 从 screen_map.lua 提取：模式枚举、状态、策略、模式转换函数
local Flow         = require("core/flow")
local RoutePlanner = require("map/route_planner")
local Graph        = require("map/world_graph")
local Tutorial     = require("narrative/tutorial")
local Flags        = require("core/flags")
local DialoguePool = require("narrative/dialogue_pool")
local SoundMgr     = require("ui/sound_manager")

local M = {}

-- ============================================================
-- 模式枚举
-- ============================================================
M.MapState = {
    BROWSE        = "browse",
    ROUTE_PREVIEW = "route_preview",
    MANUAL_PLAN   = "manual_plan",
}

-- ============================================================
-- 模式状态（页面级）
-- ============================================================
M.mapMode = {
    state      = M.MapState.BROWSE,
    target     = nil,           -- 目标节点 id
    strategy   = "fastest",     -- 当前策略
    plans      = nil,           -- { fastest, safest, balanced }
    activePlan = nil,           -- 当前显示的 plan
    waypoints  = {},            -- 手动模式途经点
    manualPlan = nil,           -- 手动模式路线
    destList   = nil,           -- 多目的地列表
}

-- ============================================================
-- 策略名称 & 颜色映射
-- ============================================================
M.STRATEGY_NAMES = {
    fastest  = "最快",
    safest   = "最安全",
    balanced = "平衡",
}
M.STRATEGY_COLORS = {
    fastest  = "map_route_fastest",
    safest   = "map_route_safest",
    balanced = "map_route_balanced",
    manual   = "map_route_manual",
}

-- ============================================================
-- 辅助函数
-- ============================================================

--- 获取旅行中的有效规划起点（下一到达节点），非旅行返回 current_location
---@param state table
---@return string|nil
function M.getEffectiveOrigin(state)
    if state and Flow.get_phase(state) == Flow.Phase.TRAVELLING
       and state.flow.route_plan then
        return RoutePlanner.get_next_arrival_node(state.flow.route_plan)
            or state.map.current_location
    end
    return state and state.map.current_location or nil
end

--- 教程首次出发拦截：检查是否需要播放出发对话
---@param plan table
---@param state table
---@param router table
---@return boolean 是否触发了教程
function M.tryTutorialDeparture(plan, state, router)
    local tutPhase = Tutorial.get_phase(state)
    if tutPhase == Tutorial.Phase.TRAVEL_TO_GREENHOUSE
        and not Flags.has(state, "tutorial_first_departure_done") then
        local departure = DialoguePool.get("SD_TUTORIAL_FIRST_DEPARTURE")
        if departure then
            Flow.start_travel(state, plan)
            router.navigate("campfire", {
                dialogue = departure,
                consumed = false,
                returnTo = "home",
            })
            return true
        end
    end
    return false
end

-- ============================================================
-- 模式转换
-- ============================================================

--- 进入路线预览模式
---@param nodeId string
---@param state table
---@param cam table 相机状态（设置 selected）
---@param rebuildPanel function
function M.enterRoutePreview(nodeId, state, cam, rebuildPanel)
    local mm = M.mapMode
    mm.state = M.MapState.ROUTE_PREVIEW
    mm.target = nodeId
    mm.strategy = "fastest"

    local travelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING
    if travelling and state.flow.route_plan then
        local fromId = RoutePlanner.get_next_arrival_node(state.flow.route_plan)
        if fromId then
            mm.plans = RoutePlanner.auto_plan_all_strategies_from(state, fromId, nodeId)
        else
            mm.plans = RoutePlanner.auto_plan_all_strategies(state, nodeId)
        end
    else
        mm.plans = RoutePlanner.auto_plan_all_strategies(state, nodeId)
    end

    mm.activePlan = mm.plans.fastest
    mm.waypoints = {}
    mm.manualPlan = nil
    mm.destList = nil
    cam.selected = nodeId
    rebuildPanel()
end

--- 进入手动规划模式
---@param targetId string
---@param state table
---@param rebuildPanel function
function M.enterManualPlan(targetId, state, rebuildPanel)
    local travelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING
    local origin
    if travelling and state.flow.route_plan then
        origin = RoutePlanner.get_next_arrival_node(state.flow.route_plan)
            or state.map.current_location
    else
        origin = state.map.current_location
    end

    local mm = M.mapMode
    mm.state = M.MapState.MANUAL_PLAN
    mm.target = targetId
    mm.plans = nil
    mm.activePlan = nil
    mm.strategy = "manual"

    local fromOvr = travelling and origin or nil
    if targetId and targetId ~= origin then
        mm.waypoints = { origin, targetId }
        mm.manualPlan = RoutePlanner.manual_plan_with_fill(state, mm.waypoints, fromOvr)
    else
        mm.waypoints = { origin }
        mm.manualPlan = nil
    end
    rebuildPanel()
end

--- 退出到浏览模式
---@param cam table
---@param rebuildPanel function
function M.exitToBase(cam, rebuildPanel)
    local mm = M.mapMode
    mm.state = M.MapState.BROWSE
    mm.target = nil
    mm.plans = nil
    mm.activePlan = nil
    mm.waypoints = {}
    mm.manualPlan = nil
    mm.destList = nil
    cam.selected = nil
    rebuildPanel()
end

--- 切换策略
---@param strat string
---@param rebuildPanel function
function M.switchStrategy(strat, rebuildPanel)
    local mm = M.mapMode
    if mm.state ~= M.MapState.ROUTE_PREVIEW then return end
    mm.strategy = strat
    if mm.plans then
        mm.activePlan = mm.plans[strat]
    end
    rebuildPanel()
end

--- 重置模式状态（页面首次进入时调用）
function M.reset()
    local mm = M.mapMode
    mm.state      = M.MapState.BROWSE
    mm.target     = nil
    mm.strategy   = "fastest"
    mm.plans      = nil
    mm.activePlan = nil
    mm.waypoints  = {}
    mm.manualPlan = nil
    mm.destList   = nil
end

return M

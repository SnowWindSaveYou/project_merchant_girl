--- 核心流程状态机
--- IDLE → MAP → PREPARE → ROUTE_PLAN → TRAVELLING → ARRIVAL → SETTLEMENT → SUMMARY → IDLE
local RoutePlanner   = require("map/route_planner")
local OrderBook      = require("economy/order_book")
local EventScheduler = require("events/event_scheduler")

local M = {}

M.Phase = {
    IDLE       = "idle",
    MAP        = "map",        -- 查看大地图
    PREPARE    = "prepare",    -- 订单簿管理（接单、装载）
    ROUTE_PLAN = "route_plan", -- 路线规划确认
    TRAVELLING = "travelling",
    ARRIVAL    = "arrival",    -- 到达节点（中间节点或终点）
    SETTLEMENT = "settlement", -- 在聚落中（交易、接单）
    SUMMARY    = "summary",    -- 行程结算
}

function M.get_phase(state)
    return state.flow.phase
end

function M.set_phase(state, phase)
    state.flow.phase = phase
end

--- 进入地图页面
function M.enter_map(state)
    state.flow.phase = M.Phase.MAP
end

--- 进入订单簿管理
function M.enter_prepare(state)
    state.flow.phase = M.Phase.PREPARE
end

--- 进入路线规划
function M.enter_route_plan(state)
    state.flow.phase = M.Phase.ROUTE_PLAN
end

--- 确认路线规划并出发
---@param state table
---@param plan table route_plan（由 route_planner 生成）
function M.start_travel(state, plan)
    if not plan or not plan.route_plan_id then
        print("[Flow] ERROR: 需要 route_plan_id 才能出发")
        return false
    end

    -- 装载所有已接订单
    OrderBook.load_all_accepted(state)

    -- 出发时清除当前聚落的可接订单缓存（下次到达时重新生成）
    OrderBook.clear_all_available(state)

    state.flow.phase = M.Phase.TRAVELLING
    state.flow.route_plan = plan
    state.flow.event_timer = EventScheduler.new_timer()

    return true
end

--- 每帧更新行驶进度
--- 返回 arrival_info 当到达一个节点时
function M.update_travel(state, dt)
    if state.flow.phase ~= M.Phase.TRAVELLING then return nil end
    local plan = state.flow.route_plan
    if not plan then return nil end

    local arrival = RoutePlanner.advance(plan, dt)
    return arrival
end

--- 获取当前行程总进度
function M.get_travel_progress(state)
    return RoutePlanner.get_progress(state.flow.route_plan)
end

--- 获取当前段信息
function M.get_current_segment(state)
    return RoutePlanner.get_current_segment(state.flow.route_plan)
end

--- 处理到达节点
--- 更新位置、检查自动交付、返回结果
---@param state table
---@param arrival_info table { arrived_node, arrived_edge, finished }
---@return table arrival_result
function M.handle_node_arrival(state, arrival_info)
    local node_id = arrival_info.arrived_node
    state.map.current_location = node_id

    -- 1. 自动交付匹配的订单
    local delivered, reward = OrderBook.auto_deliver(state, node_id)

    -- 2. 标记聚落已访问
    if state.settlements[node_id] then
        state.settlements[node_id].visited = true
    end

    -- 3. 发现新节点（标记为已知）
    if not state.map.known_nodes[node_id] then
        state.map.known_nodes[node_id] = true
    end

    -- 4. 到达聚落时生成可接订单（仅一次，缓存到 state）
    local Graph = require("map/world_graph")
    local node = Graph.get_node(node_id)
    if node and node.type == "settlement" then
        OrderBook.generate_on_arrival(state, node_id)
    end

    return {
        node_id        = node_id,
        delivered      = delivered,
        delivery_reward = reward,
        is_final       = arrival_info.finished,
    }
end

--- 完成整趟行程，进入结算
function M.finish_trip(state)
    local plan = state.flow.route_plan

    -- 检查订单超时
    OrderBook.check_expirations(state)

    local result = {
        total_time     = plan and plan.total_time or 0,
        total_fuel     = plan and plan.total_fuel or 0,
        strategy       = plan and plan.strategy or "unknown",
        destination    = state.map.current_location,
    }

    -- 更新统计
    state.stats.total_trips = state.stats.total_trips + 1

    -- 扣除燃料
    if plan then
        state.truck.fuel = math.max(0, state.truck.fuel - plan.total_fuel)
    end

    -- 切换到结算
    state.flow.phase = M.Phase.SUMMARY
    state.flow.route_plan = nil
    state.flow.event_timer = nil

    return result
end

--- 结算完成，回到空闲
function M.finish_summary(state)
    state.flow.phase = M.Phase.IDLE
end

--- 回到主页（从地图/订单簿返回）
function M.back_to_idle(state)
    state.flow.phase = M.Phase.IDLE
end

return M

--- 核心流程状态机
--- IDLE → MAP → PREPARE → ROUTE_PLAN → TRAVELLING → ARRIVAL → SETTLEMENT → SUMMARY → IDLE
local RoutePlanner        = require("map/route_planner")
local OrderBook           = require("economy/order_book")
local EventScheduler      = require("events/event_scheduler")
local ItemUse             = require("economy/item_use")
local Ticker              = require("core/ticker")
local Pricing             = require("economy/pricing")
local Goodwill            = require("settlement/goodwill")
local SettlementEventPool = require("events/settlement_event_pool")
local WaypointEventPool   = require("events/waypoint_event_pool")
local WanderingNpc        = require("narrative/wandering_npc")
local LetterSystem        = require("narrative/letter_system")
local Chatter             = require("travel/chatter")
local Radio               = require("travel/radio")
local Scenery             = require("travel/scenery")
local Environment         = require("travel/environment")
local RoadLoot            = require("travel/road_loot")
local Tracker             = require("analytics/tracker")
local Skills              = require("character/skills")

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
    state.flow.chatter = Chatter.init()
    if not state.flow.radio then
        state.flow.radio = Radio.init()
    else
        Radio.reset_broadcast(state.flow.radio)
    end
    state.flow.scenery = Scenery.init()
    state.flow.environment = Environment.init()
    state.flow.road_loot = RoadLoot.init()
    -- 初始 segment 环境推演 + 掉落物规划
    if plan.segments and #plan.segments > 0 then
        Environment.on_segment_enter(state.flow.environment, plan.segments[1])
        RoadLoot.on_segment_enter(state, plan.segments[1])
    end

    -- 埋点
    Tracker.milestone(state, "first_trip")

    return true
end

--- 每帧更新行驶进度
--- 返回 arrival_info 当到达一个节点时
function M.update_travel(state, dt)
    if state.flow.phase ~= M.Phase.TRAVELLING then return nil end
    local plan = state.flow.route_plan
    if not plan then return nil end

    -- fatigued：行驶速度 -10%
    local speed_mult = Ticker.get_speed_mult(state)
    local arrival = RoutePlanner.advance(plan, dt * speed_mult)
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

    -- 0. 重置本次停留使用标记（篝火/NPC拜访 每次到达只能各一次）
    state._visit_used = {}

    -- 1. 自动交付匹配的订单
    local delivered, reward = OrderBook.auto_deliver(state, node_id)

    -- 埋点：交付订单
    if delivered and #delivered > 0 then
        Tracker.milestone(state, "first_delivery")
        Tracker.count(state, "trades_completed", #delivered)
    end

    -- 2. 标记聚落已访问
    if state.settlements[node_id] then
        state.settlements[node_id].visited = true
    end

    -- 3. 发现新节点（标记为已知）
    if not state.map.known_nodes[node_id] then
        state.map.known_nodes[node_id] = true
    end

    -- 4. poisoned：每段行程额外消耗耐久 -5
    local poisoned = ItemUse.has_status(state, "linli", "poisoned")
        or ItemUse.has_status(state, "taoxia", "poisoned")
    if poisoned then
        local poison_dmg = 5
        state.truck.durability = math.max(0, state.truck.durability - poison_dmg)
    end

    -- 5. 到达聚落时生成可接订单 + 据点服务
    local Graph = require("map/world_graph")
    local node = Graph.get_node(node_id)
    local services_log = {}
    if node and node.type == "settlement" then
        OrderBook.generate_on_arrival(state, node_id)

        -- 据点休整：仅高好感据点(Lv2+)自动清除 demoralized
        local gw = state.settlements[node_id] and state.settlements[node_id].goodwill or 0
        if Goodwill.is_unlocked(gw, "rest_area") then
            for _, cid in ipairs({ "linli", "taoxia" }) do
                if ItemUse.has_status(state, cid, "demoralized") then
                    ItemUse.clear_status(state, cid, "demoralized")
                    local charName = cid == "linli" and "林砾" or "陶夏"
                    table.insert(services_log,
                        charName .. " 在友好据点休整，士气恢复了")
                end
            end
        end

        -- 据点自动修理：恢复 10 点耐久（免费基础服务）+ 协同修理技能加成
        if state.truck.durability < state.truck.durability_max then
            local base_repair = 10 + Skills.get_repair_bonus(state)
            local repair = math.min(base_repair, state.truck.durability_max - state.truck.durability)
            state.truck.durability = state.truck.durability + repair
            table.insert(services_log, "据点工匠修补了货车（耐久 +" .. repair .. "）")
        end

        -- 供需衰减（每趟到达聚落时触发）
        Pricing.decay_supply_demand(state)

        -- 聚落内事件检查（30% 概率触发）
        SettlementEventPool.check_on_arrival(state, node_id)
    else
        -- 非聚落路点事件检查（25% 概率触发）
        WaypointEventPool.check_on_arrival(state, node_id, node and node.type or "resource")
    end

    -- 埋点：检查全聚落访问里程碑
    Tracker.check_conditional(state)

    return {
        node_id         = node_id,
        delivered       = delivered,
        delivery_reward = reward,
        is_final        = arrival_info.finished,
        services_log    = services_log,
    }
end

--- 自由出发：前往相邻节点（探索未知 或 前往已知区域）
--- 不需要订单也可出发，构建单段路线直接上路
---@param state table
---@param target_node_id string 目标节点 ID（可以是未知节点）
---@return boolean ok
---@return string|nil error_msg
function M.start_exploration(state, target_node_id)
    local Graph = require("map/world_graph")
    local from_id = state.map.current_location

    -- 必须直接相邻
    local edge = Graph.get_edge(from_id, target_node_id)
    if not edge then
        return false, "没有通路"
    end

    -- 隐藏节点未解锁
    local target_def = Graph.NODES[target_node_id]
    if target_def and target_def.hidden then
        local known = state.map.known_nodes or {}
        if not known[target_node_id] then
            return false, "未知区域，需要线索才能前往"
        end
    end

    -- 条件探索旗标检查
    if target_def and target_def.explore_flag then
        local flags = state.flags or {}
        if not flags[target_def.explore_flag] then
            return false, "此区域暂时无法前往，需要更多情报"
        end
    end

    -- 燃料检查
    if state.truck.fuel < edge.fuel_cost then
        return false, "燃料不足"
    end

    -- 构建单段路线计划
    local target_node = Graph.get_node(target_node_id)
    local is_known = state.map.known_nodes and state.map.known_nodes[target_node_id]

    local plan = {
        route_plan_id   = "explore_" .. os.time(),
        strategy        = "exploration",
        path            = { from_id, target_node_id },
        segments        = {
            {
                from      = from_id,
                to        = target_node_id,
                from_name = Graph.get_node_name(from_id),
                to_name   = is_known
                    and (target_node and target_node.name or target_node_id)
                    or "未知区域",
                edge_id   = edge.id,
                edge_type = edge.type,
                time_sec  = edge.travel_time_sec,
                fuel_cost = edge.fuel_cost,
                danger    = edge.danger,
            },
        },
        total_time      = edge.travel_time_sec,
        total_fuel      = edge.fuel_cost,
        max_danger      = edge.danger,
        segment_index   = 0,
        segment_elapsed = 0,
    }

    -- 随身携带已接订单（如果有的话）
    OrderBook.load_all_accepted(state)

    state.flow.phase       = M.Phase.TRAVELLING
    state.flow.route_plan  = plan
    state.flow.event_timer = EventScheduler.new_timer()
    state.flow.chatter     = Chatter.init()
    if not state.flow.radio then
        state.flow.radio = Radio.init()
    else
        Radio.reset_broadcast(state.flow.radio)
    end
    state.flow.scenery     = Scenery.init()
    state.flow.environment = Environment.init()
    state.flow.road_loot   = RoadLoot.init()
    if plan.segments and #plan.segments > 0 then
        Environment.on_segment_enter(state.flow.environment, plan.segments[1])
        RoadLoot.on_segment_enter(state, plan.segments[1])
    end

    -- 埋点
    Tracker.milestone(state, "first_explore")
    Tracker.count(state, "explorations_done")

    return true
end

--- 旅行中替换剩余路线（保留当前段，后续段替换为新路线）
---@param state table
---@param new_plan table 从下一个到达节点开始的新 plan
---@return boolean ok
function M.reroute(state, new_plan)
    if state.flow.phase ~= M.Phase.TRAVELLING then
        print("[Flow] ERROR: reroute 只能在旅行中调用")
        return false
    end
    if not new_plan then
        print("[Flow] ERROR: reroute 需要有效的 new_plan")
        return false
    end

    local current_plan = state.flow.route_plan
    if not current_plan then
        print("[Flow] ERROR: 当前没有路线计划")
        return false
    end

    local merged = RoutePlanner.merge_plan(current_plan, new_plan)
    state.flow.route_plan = merged
    print("[Flow] Rerouted: " .. #merged.segments .. " segments, strategy=" .. (merged.strategy or "?"))
    return true
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

    -- 埋点：检查条件型里程碑（trips_10, credits_1000 等）
    Tracker.check_conditional(state)

    -- 技能解锁检查
    Skills.check_unlocks(state)

    -- 事件冷却递减
    SettlementEventPool.tick_cooldowns(state)
    WaypointEventPool.tick_cooldowns(state)

    -- 流浪 NPC 迁移（50% 概率移动到新位置）
    WanderingNpc.migrate_all(state)

    -- 信件系统：扫描并入队新信件
    LetterSystem.scan_and_enqueue(state)

    -- 燃料已在 ticker.advance() 中按帧实时扣除，此处不再重复扣除

    -- 切换到结算
    state.flow.phase = M.Phase.SUMMARY
    state.flow.route_plan = nil
    state.flow.event_timer = nil
    state.flow.chatter = nil
    -- radio 保留：不清除，让用户的开关/频道偏好跨旅行保持
    state.flow.scenery = nil
    state.flow.environment = nil
    state.flow.road_loot = nil

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

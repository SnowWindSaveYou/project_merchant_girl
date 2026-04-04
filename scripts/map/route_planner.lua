--- 路线规划模块
--- 手动/自动规划多站点路线，生成 route_plan_id
local Graph = require("map/world_graph")

local M = {}

-- ============================================================
-- 规划策略
-- ============================================================
M.Strategy = {
    FASTEST  = "fastest",
    SAFEST   = "safest",
    BALANCED = "balanced",
    MANUAL   = "manual",
}

-- ============================================================
-- 序号
-- ============================================================
local _plan_seq = 0

local function next_plan_id()
    _plan_seq = _plan_seq + 1
    return "rp_" .. _plan_seq .. "_" .. os.time()
end

-- ============================================================
-- 从路径节点列表构建详细 route_plan
-- ============================================================

--- 计算路线各项指标
---@param path string[] 节点 id 有序列表
---@return table|nil plan
local function build_plan_from_path(path, strategy)
    if not path or #path < 2 then return nil end

    local segments = {}
    local total_time = 0
    local total_fuel = 0
    local max_danger = "low"

    local DANGER_RANK = { low = 1, normal = 2, high = 3 }
    local RANK_DANGER = { [1] = "low", [2] = "normal", [3] = "high" }

    for i = 1, #path - 1 do
        local edge = Graph.get_edge(path[i], path[i + 1])
        if not edge then
            return nil -- 路径不连通
        end
        table.insert(segments, {
            from       = path[i],
            to         = path[i + 1],
            from_name  = Graph.get_node_name(path[i]),
            to_name    = Graph.get_node_name(path[i + 1]),
            edge_id    = edge.id,
            edge_type  = edge.type,
            time_sec   = edge.travel_time_sec,
            fuel_cost  = edge.fuel_cost,
            danger     = edge.danger_level,
        })
        total_time = total_time + edge.travel_time_sec
        total_fuel = total_fuel + edge.fuel_cost
        local dr = DANGER_RANK[edge.danger_level] or 2
        if dr > (DANGER_RANK[max_danger] or 1) then
            max_danger = RANK_DANGER[dr]
        end
    end

    return {
        route_plan_id = next_plan_id(),
        strategy      = strategy or "manual",
        path          = path,
        segments      = segments,
        total_time    = total_time,
        total_fuel    = total_fuel,
        max_danger    = max_danger,
        segment_index = 0,  -- 当前正在走的段（0=未出发）
        segment_elapsed = 0,
    }
end

-- ============================================================
-- 公开 API
-- ============================================================

--- 自动规划路线（从当前位置到目标节点）
---@param state table
---@param to_id string 目标节点
---@param strategy string "fastest"|"safest"|"balanced"
---@return table|nil plan
function M.auto_plan(state, to_id, strategy)
    local from_id = state.map.current_location
    if from_id == to_id then return nil end

    strategy = strategy or M.Strategy.FASTEST
    local path

    if strategy == M.Strategy.FASTEST then
        path = Graph.find_fastest_path(from_id, to_id, state)
    elseif strategy == M.Strategy.SAFEST then
        path = Graph.find_safest_path(from_id, to_id, state)
    elseif strategy == M.Strategy.BALANCED then
        -- balanced: 取 fastest 和 safest 中总时间较短但 danger 更低的
        local fast = Graph.find_fastest_path(from_id, to_id, state)
        local safe = Graph.find_safest_path(from_id, to_id, state)
        if fast and safe then
            local fp = build_plan_from_path(fast, "fastest")
            local sp = build_plan_from_path(safe, "safest")
            if fp and sp then
                -- 综合评分：时间 + 风险惩罚
                local DANGER_PENALTY = { low = 0, normal = 30, high = 80 }
                local fs = fp.total_time + (DANGER_PENALTY[fp.max_danger] or 0)
                local ss = sp.total_time + (DANGER_PENALTY[sp.max_danger] or 0)
                path = fs <= ss and fast or safe
            else
                path = fast or safe
            end
        else
            path = fast or safe
        end
    end

    if not path then return nil end
    return build_plan_from_path(path, strategy)
end

--- 手动规划路线（玩家手选节点序列）
---@param state table
---@param waypoints string[] 有序节点 id 列表（含起点）
---@return table|nil plan
---@return string? error_msg
function M.manual_plan(state, waypoints)
    if not waypoints or #waypoints < 2 then
        return nil, "至少需要起点和一个目的地"
    end

    -- 验证起点
    if waypoints[1] ~= state.map.current_location then
        return nil, "起点必须是当前位置"
    end

    -- 验证每段都有边连接且节点已知
    local known = state.map.known_nodes or {}
    for i = 2, #waypoints do
        if not known[waypoints[i]] then
            return nil, Graph.get_node_name(waypoints[i]) .. " 尚未探索"
        end
        local edge = Graph.get_edge(waypoints[i - 1], waypoints[i])
        if not edge then
            return nil, Graph.get_node_name(waypoints[i - 1]) .. " 与 "
                .. Graph.get_node_name(waypoints[i]) .. " 之间没有通路"
        end
    end

    return build_plan_from_path(waypoints, M.Strategy.MANUAL)
end

--- 一次性计算三种策略的路线（用于地图路线预览）
---@param state table
---@param to_id string 目标节点
---@return table { fastest = plan|nil, safest = plan|nil, balanced = plan|nil }
function M.auto_plan_all_strategies(state, to_id)
    return {
        fastest  = M.auto_plan(state, to_id, M.Strategy.FASTEST),
        safest   = M.auto_plan(state, to_id, M.Strategy.SAFEST),
        balanced = M.auto_plan(state, to_id, M.Strategy.BALANCED),
    }
end

--- 手动规划路线（自动填充非相邻节点间的路径）
---@param state table
---@param waypoints string[] 用户手选的途经点列表（含起点，可以不相邻）
---@return table|nil plan
---@return string|nil error_msg
function M.manual_plan_with_fill(state, waypoints)
    if not waypoints or #waypoints < 2 then
        return nil, "至少需要起点和一个目的地"
    end
    if waypoints[1] ~= state.map.current_location then
        return nil, "起点必须是当前位置"
    end

    local known = state.map.known_nodes or {}
    for i = 2, #waypoints do
        if not known[waypoints[i]] then
            return nil, Graph.get_node_name(waypoints[i]) .. " 尚未探索"
        end
    end

    -- 对每对途经点，填充中间路径
    local full_path = { waypoints[1] }
    for i = 2, #waypoints do
        local edge = Graph.get_edge(waypoints[i - 1], waypoints[i])
        if edge then
            -- 相邻：直接连接
            table.insert(full_path, waypoints[i])
        else
            -- 非相邻：用 BFS 填充
            local sub = Graph.find_path(waypoints[i - 1], waypoints[i], state)
            if not sub or #sub < 2 then
                return nil, Graph.get_node_name(waypoints[i - 1]) .. " 无法到达 "
                    .. Graph.get_node_name(waypoints[i])
            end
            for j = 2, #sub do
                table.insert(full_path, sub[j])
            end
        end
    end

    return build_plan_from_path(full_path, M.Strategy.MANUAL)
end

--- 为多个目的地自动规划经过所有目的地的路线
--- 使用贪心最近邻策略
---@param state table
---@param dest_ids string[] 需要经过的目的地集合
---@param strategy string
---@return table|nil plan
function M.auto_plan_multi(state, dest_ids, strategy)
    if not dest_ids or #dest_ids == 0 then return nil end

    strategy = strategy or M.Strategy.FASTEST
    local from = state.map.current_location

    -- 贪心：每次走到最近的未访问目的地
    local remaining = {}
    for _, d in ipairs(dest_ids) do remaining[d] = true end

    local full_path = { from }
    local current = from

    while next(remaining) do
        local best_dest, best_path, best_cost = nil, nil, math.huge
        for dest, _ in pairs(remaining) do
            local p
            if strategy == M.Strategy.SAFEST then
                p = Graph.find_safest_path(current, dest, state)
            else
                p = Graph.find_fastest_path(current, dest, state)
            end
            if p then
                local cost = 0
                for i = 1, #p - 1 do
                    local e = Graph.get_edge(p[i], p[i + 1])
                    cost = cost + (e and e.travel_time_sec or 999)
                end
                if cost < best_cost then
                    best_cost = cost
                    best_path = p
                    best_dest = dest
                end
            end
        end

        if not best_dest then break end -- 有目的地不可达
        remaining[best_dest] = nil

        -- 拼接路径（跳过起点避免重复）
        for i = 2, #best_path do
            table.insert(full_path, best_path[i])
        end
        current = best_dest
    end

    if #full_path < 2 then return nil end
    return build_plan_from_path(full_path, strategy)
end

-- ============================================================
-- 行驶推进
-- ============================================================

--- 推进 route_plan 的行驶进度
--- 返回 { arrived_node = id } 当到达一个节点时，nil 表示还在路上
---@param plan table route_plan
---@param dt number 时间步长（秒）
---@return table|nil arrival_info
function M.advance(plan, dt)
    if not plan or not plan.segments then return nil end

    -- 首次出发：进入第一段
    if plan.segment_index == 0 then
        plan.segment_index = 1
        plan.segment_elapsed = 0
    end

    local seg = plan.segments[plan.segment_index]
    if not seg then return nil end -- 已全部走完

    plan.segment_elapsed = plan.segment_elapsed + dt

    if plan.segment_elapsed >= seg.time_sec then
        -- 到达本段终点
        local arrived_node = seg.to
        local arrived_edge = seg

        -- 前进到下一段
        plan.segment_index = plan.segment_index + 1
        plan.segment_elapsed = 0

        local finished = plan.segment_index > #plan.segments

        return {
            arrived_node = arrived_node,
            arrived_edge = arrived_edge,
            finished     = finished,
        }
    end
    return nil
end

--- 获取当前行驶总进度 [0, 1]
function M.get_progress(plan)
    if not plan or not plan.segments or #plan.segments == 0 then return 0 end
    if plan.segment_index == 0 then return 0 end
    if plan.segment_index > #plan.segments then return 1.0 end

    local completed_time = 0
    for i = 1, plan.segment_index - 1 do
        completed_time = completed_time + plan.segments[i].time_sec
    end
    local seg = plan.segments[plan.segment_index]
    if seg then
        completed_time = completed_time + math.min(plan.segment_elapsed, seg.time_sec)
    end
    return math.min(completed_time / plan.total_time, 1.0)
end

--- 获取当前段的信息（用于 UI 显示）
function M.get_current_segment(plan)
    if not plan or plan.segment_index == 0 then return nil end
    return plan.segments[plan.segment_index]
end

--- 路线是否已走完
function M.is_finished(plan)
    if not plan or not plan.segments then return true end
    return plan.segment_index > #plan.segments
end

return M

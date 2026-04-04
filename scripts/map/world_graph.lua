--- 大地图网状节点模型（Graph）
--- Node + Edge 结构，支持多种节点类型和边类型
local M = {}

-- ============================================================
-- 节点类型
-- ============================================================
M.NodeType = {
    SETTLEMENT = "settlement",
    RESOURCE   = "resource",
    TRANSIT    = "transit",
    HAZARD     = "hazard",
    STORY      = "story",
}

-- ============================================================
-- 边类型
-- ============================================================
M.EdgeType = {
    MAIN_ROAD = "main_road",
    PATH      = "path",
    SHORTCUT  = "shortcut",
}

-- ============================================================
-- 首版节点定义（7 个节点）
-- ============================================================
M.NODES = {
    {
        id   = "greenhouse",
        name = "温室社区",
        type = "settlement",
        x = 100, y = 400, -- UI 布局坐标（逻辑坐标，非像素）
        desc = "以旧生态穹顶为核心的农业聚落",
    },
    {
        id   = "tower",
        name = "北穹塔台",
        type = "settlement",
        x = 500, y = 100,
        desc = "建在旧防空观测塔群上的技术聚落",
    },
    {
        id   = "ruins_camp",
        name = "废墟游民营地",
        type = "settlement",
        x = 500, y = 450,
        desc = "塌陷商场周边的流动型拾荒聚落",
    },
    {
        id   = "crossroads",
        name = "旧公路交叉口",
        type = "transit",
        x = 300, y = 250,
        desc = "一处半废弃的高速匝道，可补给和分道",
    },
    {
        id   = "old_warehouse",
        name = "废弃仓库",
        type = "resource",
        x = 350, y = 400,
        desc = "锈蚀铁皮仓库群，可能有旧时代物资",
    },
    {
        id   = "danger_pass",
        name = "塌陷高架",
        type = "hazard",
        x = 200, y = 120,
        desc = "断裂的高架桥段，通行风险极高",
    },
    {
        id   = "signal_relay",
        name = "信号中继站",
        type = "story",
        x = 450, y = 280,
        desc = "废弃的通信中继站，偶有微弱信号",
    },
}

-- ============================================================
-- 首版边定义
-- ============================================================
M.EDGES = {
    -- 主干道：温室 → 交叉口 → 塔台（安全但慢）
    {
        id = "edge_gh_cross",
        from = "greenhouse", to = "crossroads",
        type = "main_road",
        travel_time_sec = 50,
        fuel_cost = 8,
        danger_level = "low",
        bidirectional = true,
    },
    {
        id = "edge_cross_tower",
        from = "crossroads", to = "tower",
        type = "main_road",
        travel_time_sec = 55,
        fuel_cost = 9,
        danger_level = "low",
        bidirectional = true,
    },
    -- 捷径：温室 → 塌陷高架 → 塔台（快但危险）
    {
        id = "edge_gh_danger",
        from = "greenhouse", to = "danger_pass",
        type = "shortcut",
        travel_time_sec = 25,
        fuel_cost = 6,
        danger_level = "high",
        bidirectional = true,
    },
    {
        id = "edge_danger_tower",
        from = "danger_pass", to = "tower",
        type = "shortcut",
        travel_time_sec = 20,
        fuel_cost = 5,
        danger_level = "high",
        bidirectional = true,
    },
    -- 小径：交叉口 → 废弃仓库（探索）
    {
        id = "edge_cross_warehouse",
        from = "crossroads", to = "old_warehouse",
        type = "path",
        travel_time_sec = 30,
        fuel_cost = 5,
        danger_level = "normal",
        bidirectional = true,
    },
    -- 小径：交叉口 → 信号中继站
    {
        id = "edge_cross_signal",
        from = "crossroads", to = "signal_relay",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger_level = "normal",
        bidirectional = true,
    },
    -- 主干道：信号中继站 → 废墟游民营地
    {
        id = "edge_signal_ruins",
        from = "signal_relay", to = "ruins_camp",
        type = "main_road",
        travel_time_sec = 40,
        fuel_cost = 7,
        danger_level = "normal",
        bidirectional = true,
    },
    -- 小径：废弃仓库 → 废墟游民营地
    {
        id = "edge_warehouse_ruins",
        from = "old_warehouse", to = "ruins_camp",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger_level = "normal",
        bidirectional = true,
    },
}

-- ============================================================
-- 索引表（启动时构建）
-- ============================================================
M.BY_NODE_ID = {}
M.ADJ = {} -- adjacency: ADJ[node_id] = { {edge, neighbor_id}, ... }

local function build_index()
    M.BY_NODE_ID = {}
    M.ADJ = {}
    for _, n in ipairs(M.NODES) do
        M.BY_NODE_ID[n.id] = n
        M.ADJ[n.id] = {}
    end
    for _, e in ipairs(M.EDGES) do
        table.insert(M.ADJ[e.from], { edge = e, to = e.to })
        if e.bidirectional then
            table.insert(M.ADJ[e.to], { edge = e, to = e.from })
        end
    end
end
build_index()

-- ============================================================
-- API
-- ============================================================

--- 获取节点信息
function M.get_node(node_id)
    return M.BY_NODE_ID[node_id]
end

--- 获取节点名称
function M.get_node_name(node_id)
    local n = M.BY_NODE_ID[node_id]
    return n and n.name or node_id
end

--- 获取从 node_id 出发的所有邻居（边+目标）
--- 只返回 state 中已知的节点
function M.get_neighbors(node_id, state)
    local raw = M.ADJ[node_id] or {}
    if not state then return raw end
    local known = state.map.known_nodes or {}
    local result = {}
    for _, adj in ipairs(raw) do
        if known[adj.to] then
            table.insert(result, adj)
        end
    end
    return result
end

--- 获取两个节点间的边（如果直接相连）
function M.get_edge(from_id, to_id)
    local adjs = M.ADJ[from_id] or {}
    for _, adj in ipairs(adjs) do
        if adj.to == to_id then
            return adj.edge
        end
    end
    return nil
end

--- 获取所有聚落节点
function M.get_settlements()
    local result = {}
    for _, n in ipairs(M.NODES) do
        if n.type == "settlement" then
            table.insert(result, n)
        end
    end
    return result
end

--- BFS 寻路：返回从 from 到 to 的最短路径（节点 id 列表）
--- 只走已知节点
function M.find_path(from_id, to_id, state)
    if from_id == to_id then return { from_id } end
    local known = state and state.map.known_nodes or {}
    local visited = { [from_id] = true }
    local parent = {}
    local queue = { from_id }
    local head = 1

    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        local adjs = M.ADJ[cur] or {}
        for _, adj in ipairs(adjs) do
            if not visited[adj.to] and (not state or known[adj.to]) then
                visited[adj.to] = true
                parent[adj.to] = cur
                if adj.to == to_id then
                    -- 回溯路径
                    local path = {}
                    local node = to_id
                    while node do
                        table.insert(path, 1, node)
                        node = parent[node]
                    end
                    return path
                end
                table.insert(queue, adj.to)
            end
        end
    end
    return nil -- 不可达
end

--- Dijkstra 最短时间路径
function M.find_fastest_path(from_id, to_id, state)
    return M._dijkstra(from_id, to_id, state, "travel_time_sec")
end

--- Dijkstra 最安全路径（danger_level 映射为权重）
local DANGER_WEIGHT = { low = 1, normal = 3, high = 8 }
function M.find_safest_path(from_id, to_id, state)
    return M._dijkstra(from_id, to_id, state, nil, function(edge)
        return (DANGER_WEIGHT[edge.danger_level] or 5) * edge.travel_time_sec
    end)
end

--- 通用 Dijkstra
function M._dijkstra(from_id, to_id, state, weight_key, weight_fn)
    local known = state and state.map.known_nodes or {}
    local dist = { [from_id] = 0 }
    local parent = {}
    local visited = {}
    local all = {}
    for id, _ in pairs(M.BY_NODE_ID) do
        if not state or known[id] or id == from_id then
            table.insert(all, id)
            if id ~= from_id then dist[id] = math.huge end
        end
    end

    while true do
        -- 找最小 dist 未访问节点
        local u, ud = nil, math.huge
        for _, id in ipairs(all) do
            if not visited[id] and (dist[id] or math.huge) < ud then
                u = id; ud = dist[id]
            end
        end
        if not u or u == to_id then break end
        visited[u] = true

        local adjs = M.ADJ[u] or {}
        for _, adj in ipairs(adjs) do
            if not visited[adj.to] and (not state or known[adj.to]) then
                local w
                if weight_fn then
                    w = weight_fn(adj.edge)
                else
                    w = adj.edge[weight_key] or 1
                end
                local alt = ud + w
                if alt < (dist[adj.to] or math.huge) then
                    dist[adj.to] = alt
                    parent[adj.to] = u
                end
            end
        end
    end

    if not parent[to_id] and from_id ~= to_id then return nil end
    local path = {}
    local node = to_id
    while node do
        table.insert(path, 1, node)
        node = parent[node]
    end
    return path
end

return M

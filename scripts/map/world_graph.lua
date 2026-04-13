--- 大地图网状节点模型（Graph）
--- Node + Edge 结构，支持多种节点类型和边类型
--- 数据从 assets/configs/map_graph.json 加载
local M = {}

local Loader = require "data_loader.loader"

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
-- 从 JSON 配置加载节点和边数据
-- ============================================================
local function load_graph_data()
    local raw = Loader.load("configs/map_graph.json")
    if not raw then
        print("[WorldGraph] ERROR: Failed to load configs/map_graph.json")
        return {}, {}
    end
    return raw.nodes or {}, raw.edges or {}
end

M.NODES, M.EDGES = load_graph_data()

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

--- 获取从 node_id 出发的未探索邻居（未知节点）
function M.get_unknown_neighbors(node_id, state)
    local raw = M.ADJ[node_id] or {}
    if not state then return {} end
    local known = state.map.known_nodes or {}
    local result = {}
    for _, adj in ipairs(raw) do
        if not known[adj.to] then
            local node = M.BY_NODE_ID[adj.to]
            -- 隐藏节点：除非已被 unlock_route 解锁，否则不显示在探索面板
            if node and node.hidden then
                -- skip hidden nodes
            else
                table.insert(result, adj)
            end
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

--- 获取所有节点
function M.get_all_nodes()
    return M.NODES
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

--- Dijkstra 最安全路径（danger 映射为权重）
local DANGER_WEIGHT = { safe = 1, normal = 3, danger = 8 }
function M.find_safest_path(from_id, to_id, state)
    return M._dijkstra(from_id, to_id, state, nil, function(edge)
        return (DANGER_WEIGHT[edge.danger] or 5) * edge.travel_time_sec
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

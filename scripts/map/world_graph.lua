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
-- 节点定义（12 个节点）
-- ============================================================
M.NODES = {
    -- ===== 聚落（4 个） =====
    {
        id   = "greenhouse",
        name = "温室社区",
        type = "settlement",
        x = 80, y = 400,
        desc = "以旧生态穹顶为核心的农业聚落",
    },
    {
        id   = "tower",
        name = "北穹塔台",
        type = "settlement",
        x = 500, y = 80,
        desc = "建在旧防空观测塔群上的技术聚落",
    },
    {
        id   = "ruins_camp",
        name = "废墟游民营地",
        type = "settlement",
        x = 550, y = 450,
        desc = "塌陷商场周边的流动型拾荒聚落",
    },
    {
        id   = "bell_tower",
        name = "钟楼书院",
        type = "settlement",
        x = 750, y = 250,
        desc = "围绕旧钟楼建立的学者聚落，收藏大量末世前书籍",
    },
    -- ===== 中转 / 功能节点 =====
    {
        id   = "crossroads",
        name = "旧公路交叉口",
        type = "transit",
        x = 280, y = 250,
        desc = "一处半废弃的高速匝道，可补给和分道",
    },
    {
        id   = "old_warehouse",
        name = "废弃仓库",
        type = "resource",
        x = 350, y = 420,
        desc = "锈蚀铁皮仓库群，可能有旧时代物资",
    },
    {
        id   = "danger_pass",
        name = "塌陷高架",
        type = "hazard",
        x = 180, y = 120,
        desc = "断裂的高架桥段，通行风险极高",
    },
    {
        id   = "signal_relay",
        name = "信号中继站",
        type = "story",
        x = 450, y = 280,
        desc = "废弃的通信中继站，偶有微弱信号",
    },
    -- ===== 新增节点 =====
    {
        id   = "dry_riverbed",
        name = "干涸河床",
        type = "transit",
        x = 650, y = 400,
        desc = "早已干涸的河道，沙尘中偶见旧桥墩残骸",
    },
    {
        id   = "radar_hill",
        name = "雷达山丘",
        type = "resource",
        x = 650, y = 120,
        desc = "山顶有座废弃军用雷达站，零件散落一地",
    },
    {
        id   = "sunken_plaza",
        name = "沉降广场",
        type = "hazard",
        x = 400, y = 500,
        desc = "地面塌陷形成的凹地，有变异生物出没",
    },
    {
        id   = "hermit_cave",
        name = "隐士洞窟",
        type = "story",
        x = 150, y = 520,
        desc = "深藏山壁中的隐居者洞穴，据说住着一位知晓旧时代秘密的老人",
    },
    -- ===== 前哨站（4 个，Phase 11 新增） =====
    {
        id   = "greenhouse_farm",
        name = "外围农场",
        type = "settlement",
        x = 120, y = 530,
        desc = "温室社区南侧的露天耕地，种植抗辐射作物",
    },
    {
        id   = "dome_outpost",
        name = "穹顶哨站",
        type = "settlement",
        x = 380, y = 140,
        desc = "塔台技术派在西南方向设立的前沿观测站",
    },
    {
        id   = "metro_camp",
        name = "地铁营地",
        type = "settlement",
        x = 620, y = 520,
        desc = "废弃地铁隧道内的拾荒者据点，善于修理旧物",
    },
    {
        id   = "old_church",
        name = "旧教堂",
        type = "settlement",
        x = 820, y = 350,
        desc = "钟楼书院东南的废弃教堂，被学者们改造为分院",
    },
}

-- ============================================================
-- 边定义
-- ============================================================
M.EDGES = {
    -- ===== 原有边 =====
    -- 主干道：温室 → 交叉口 → 塔台（安全但慢）
    {
        id = "edge_gh_cross",
        from = "greenhouse", to = "crossroads",
        type = "main_road",
        travel_time_sec = 50,
        fuel_cost = 8,
        danger = "safe",
        bidirectional = true,
    },
    {
        id = "edge_cross_tower",
        from = "crossroads", to = "tower",
        type = "main_road",
        travel_time_sec = 55,
        fuel_cost = 9,
        danger = "safe",
        bidirectional = true,
    },
    -- 捷径：温室 → 塌陷高架 → 塔台（快但危险）
    {
        id = "edge_gh_danger",
        from = "greenhouse", to = "danger_pass",
        type = "shortcut",
        travel_time_sec = 25,
        fuel_cost = 6,
        danger = "danger",
        bidirectional = true,
    },
    {
        id = "edge_danger_tower",
        from = "danger_pass", to = "tower",
        type = "shortcut",
        travel_time_sec = 20,
        fuel_cost = 5,
        danger = "danger",
        bidirectional = true,
    },
    -- 小径：交叉口 → 废弃仓库（探索）
    {
        id = "edge_cross_warehouse",
        from = "crossroads", to = "old_warehouse",
        type = "path",
        travel_time_sec = 30,
        fuel_cost = 5,
        danger = "normal",
        bidirectional = true,
    },
    -- 小径：交叉口 → 信号中继站
    {
        id = "edge_cross_signal",
        from = "crossroads", to = "signal_relay",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger = "normal",
        bidirectional = true,
    },
    -- 主干道：信号中继站 → 废墟游民营地
    {
        id = "edge_signal_ruins",
        from = "signal_relay", to = "ruins_camp",
        type = "main_road",
        travel_time_sec = 40,
        fuel_cost = 7,
        danger = "normal",
        bidirectional = true,
    },
    -- 小径：废弃仓库 → 废墟游民营地
    {
        id = "edge_warehouse_ruins",
        from = "old_warehouse", to = "ruins_camp",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger = "normal",
        bidirectional = true,
    },

    -- ===== 新增边：连接钟楼书院 =====
    -- 信号中继站 → 钟楼书院（主路，学者常走）
    {
        id = "edge_signal_bell",
        from = "signal_relay", to = "bell_tower",
        type = "main_road",
        travel_time_sec = 45,
        fuel_cost = 7,
        danger = "normal",
        bidirectional = true,
    },
    -- 塔台 → 雷达山丘（小径，技术据点关联）
    {
        id = "edge_tower_radar",
        from = "tower", to = "radar_hill",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger = "normal",
        bidirectional = true,
    },
    -- 雷达山丘 → 钟楼书院（小径，东侧通道）
    {
        id = "edge_radar_bell",
        from = "radar_hill", to = "bell_tower",
        type = "path",
        travel_time_sec = 40,
        fuel_cost = 7,
        danger = "normal",
        bidirectional = true,
    },
    -- 废墟营地 → 干涸河床（主路，南线通道）
    {
        id = "edge_ruins_riverbed",
        from = "ruins_camp", to = "dry_riverbed",
        type = "main_road",
        travel_time_sec = 30,
        fuel_cost = 5,
        danger = "safe",
        bidirectional = true,
    },
    -- 干涸河床 → 钟楼书院（小径，东南入口）
    {
        id = "edge_riverbed_bell",
        from = "dry_riverbed", to = "bell_tower",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger = "normal",
        bidirectional = true,
    },
    -- 废弃仓库 → 沉降广场（捷径，高危）
    {
        id = "edge_warehouse_sunken",
        from = "old_warehouse", to = "sunken_plaza",
        type = "shortcut",
        travel_time_sec = 20,
        fuel_cost = 4,
        danger = "danger",
        bidirectional = true,
    },
    -- 沉降广场 → 废墟营地（小径）
    {
        id = "edge_sunken_ruins",
        from = "sunken_plaza", to = "ruins_camp",
        type = "path",
        travel_time_sec = 25,
        fuel_cost = 5,
        danger = "normal",
        bidirectional = true,
    },
    -- 温室 → 隐士洞窟（小径，叙事线路）
    {
        id = "edge_gh_hermit",
        from = "greenhouse", to = "hermit_cave",
        type = "path",
        travel_time_sec = 40,
        fuel_cost = 7,
        danger = "normal",
        bidirectional = true,
    },
    -- 隐士洞窟 → 沉降广场（捷径，危险地下通道）
    {
        id = "edge_hermit_sunken",
        from = "hermit_cave", to = "sunken_plaza",
        type = "shortcut",
        travel_time_sec = 30,
        fuel_cost = 5,
        danger = "danger",
        bidirectional = true,
    },

    -- ===== 前哨站连接（Phase 11 新增 8 条） =====
    -- 温室 → 外围农场（安全短途）
    {
        id = "edge_gh_farm",
        from = "greenhouse", to = "greenhouse_farm",
        type = "path",
        travel_time_sec = 25,
        fuel_cost = 4,
        danger = "safe",
        bidirectional = true,
    },
    -- 外围农场 → 隐士洞窟（小径）
    {
        id = "edge_farm_hermit",
        from = "greenhouse_farm", to = "hermit_cave",
        type = "path",
        travel_time_sec = 30,
        fuel_cost = 5,
        danger = "normal",
        bidirectional = true,
    },
    -- 穹顶哨站 → 交叉口（小径）
    {
        id = "edge_dome_cross",
        from = "dome_outpost", to = "crossroads",
        type = "path",
        travel_time_sec = 30,
        fuel_cost = 5,
        danger = "normal",
        bidirectional = true,
    },
    -- 穹顶哨站 → 塔台（安全主路）
    {
        id = "edge_dome_tower",
        from = "dome_outpost", to = "tower",
        type = "main_road",
        travel_time_sec = 25,
        fuel_cost = 4,
        danger = "safe",
        bidirectional = true,
    },
    -- 地铁营地 → 废墟营地（安全短途）
    {
        id = "edge_metro_ruins",
        from = "metro_camp", to = "ruins_camp",
        type = "path",
        travel_time_sec = 20,
        fuel_cost = 3,
        danger = "safe",
        bidirectional = true,
    },
    -- 地铁营地 → 干涸河床（小径）
    {
        id = "edge_metro_riverbed",
        from = "metro_camp", to = "dry_riverbed",
        type = "path",
        travel_time_sec = 25,
        fuel_cost = 4,
        danger = "normal",
        bidirectional = true,
    },
    -- 旧教堂 → 钟楼书院（安全主路）
    {
        id = "edge_church_bell",
        from = "old_church", to = "bell_tower",
        type = "main_road",
        travel_time_sec = 20,
        fuel_cost = 3,
        danger = "safe",
        bidirectional = true,
    },
    -- 旧教堂 → 干涸河床（小径）
    {
        id = "edge_church_riverbed",
        from = "old_church", to = "dry_riverbed",
        type = "path",
        travel_time_sec = 35,
        fuel_cost = 6,
        danger = "normal",
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

--- 获取从 node_id 出发的未探索邻居（未知节点）
function M.get_unknown_neighbors(node_id, state)
    local raw = M.ADJ[node_id] or {}
    if not state then return {} end
    local known = state.map.known_nodes or {}
    local result = {}
    for _, adj in ipairs(raw) do
        if not known[adj.to] then
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

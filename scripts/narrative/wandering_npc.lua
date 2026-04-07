--- 流浪 NPC 管理
--- 不固定在某个聚落，每趟行程后随机迁移到另一个地图节点
local Graph = require("map/world_graph")

local M = {}

-- 流浪 NPC 定义（不在 NPC_DATA 中设 settlement）
M.WANDERERS = {
    meng_hui = {
        id    = "meng_hui",
        name  = "孟回",
        title = "行脚医生",
        icon  = "💊",
        color = { 128, 168, 128, 255 },
        bg    = {  32,  44,  36, 240 },
        -- 偏好出现的节点类型（权重加成）
        prefer_types = { "settlement", "transit" },
    },
    ming_sha = {
        id    = "ming_sha",
        name  = "鸣砂",
        title = "独行商人",
        icon  = "🎒",
        color = { 178, 148,  98, 255 },
        bg    = {  44,  38,  28, 240 },
        prefer_types = { "settlement", "resource" },
    },
}

--- 获取流浪 NPC 定义
---@param npc_id string
---@return table|nil
function M.get_wanderer(npc_id)
    return M.WANDERERS[npc_id]
end

--- 初始化流浪 NPC 位置（首次调用或存档兼容）
---@param state table
function M.ensure_init(state)
    if not state.narrative then state.narrative = {} end
    if not state.narrative.wanderer_locations then
        state.narrative.wanderer_locations = {}
    end
    local locs = state.narrative.wanderer_locations
    for wid, _ in pairs(M.WANDERERS) do
        if not locs[wid] then
            locs[wid] = M._random_location(wid)
        end
    end
end

--- 获取某流浪 NPC 当前所在节点
---@param state table
---@param npc_id string
---@return string|nil node_id
function M.get_location(state, npc_id)
    M.ensure_init(state)
    return state.narrative.wanderer_locations[npc_id]
end

--- 获取当前节点上的所有流浪 NPC
---@param state table
---@param node_id string
---@return table[] wanderer list
function M.get_wanderers_at(state, node_id)
    M.ensure_init(state)
    local result = {}
    for wid, loc in pairs(state.narrative.wanderer_locations) do
        if loc == node_id then
            local w = M.WANDERERS[wid]
            if w then
                table.insert(result, w)
            end
        end
    end
    return result
end

--- 每趟行程结束后，随机迁移所有流浪 NPC
---@param state table
function M.migrate_all(state)
    M.ensure_init(state)
    local locs = state.narrative.wanderer_locations
    for wid, _ in pairs(M.WANDERERS) do
        -- 50% 概率迁移
        if math.random() < 0.5 then
            local old = locs[wid]
            local new_loc = M._random_location(wid, old)
            locs[wid] = new_loc
            print("[WanderingNpc] " .. wid .. ": " .. (old or "?") .. " -> " .. new_loc)
        end
    end
end

--- 随机选择一个节点（偏好特定类型）
---@param npc_id string
---@param exclude string|nil 排除的节点
---@return string
function M._random_location(npc_id, exclude)
    local wanderer = M.WANDERERS[npc_id]
    local nodes = Graph.get_all_nodes()
    local prefer = {}
    if wanderer and wanderer.prefer_types then
        for _, t in ipairs(wanderer.prefer_types) do
            prefer[t] = true
        end
    end

    local candidates = {}
    local tw = 0
    for _, node in ipairs(nodes) do
        if node.id ~= exclude then
            local w = 1
            if prefer[node.type] then w = 3 end
            table.insert(candidates, { node = node, weight = w })
            tw = tw + w
        end
    end

    if #candidates == 0 then return exclude or "greenhouse" end

    local roll = math.random() * tw
    local acc = 0
    for _, c in ipairs(candidates) do
        acc = acc + c.weight
        if roll <= acc then return c.node.id end
    end
    return candidates[#candidates].node.id
end

return M

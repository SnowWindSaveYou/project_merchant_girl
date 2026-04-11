--- 路点事件池（非聚落节点）
--- 从 JSON 加载路点事件，按 node_type / node_id / flag / 冷却筛选
--- 镜像 settlement_event_pool.lua 的架构
local Flags      = require("core/flags")
local DataLoader = require("data_loader/loader")

local M = {}

local CONFIG_PATH = "configs/waypoint_events.json"

M._events    = {}   -- array of event tables
M._by_id     = {}   -- id -> event
M._loaded    = false

-- ============================================================
-- 加载
-- ============================================================
function M._load()
    if M._loaded then return end
    M._loaded = true

    local data = DataLoader.load(CONFIG_PATH)
    if not data then
        print("[WaypointEventPool] Config not found")
        return
    end

    M._events = {}
    M._by_id  = {}

    for _, raw in ipairs(data.events or {}) do
        table.insert(M._events, raw)
        M._by_id[raw.id] = raw
    end

    print("[WaypointEventPool] Loaded " .. #M._events .. " events")
end

-- ============================================================
-- 筛选
-- ============================================================

--- 筛选某路点可用的事件
---@param state table 游戏状态
---@param node_id string 当前节点 ID
---@param node_type string 当前节点类型 (resource/hazard/transit/story)
---@return table[] 可用事件
function M.filter(state, node_id, node_type)
    M._load()

    local cooldowns = state._waypoint_event_cooldowns or {}
    local available = {}

    for _, evt in ipairs(M._events) do
        local ok = true

        -- 1. 节点类型匹配
        if evt.node_types then
            local type_match = false
            for _, nt in ipairs(evt.node_types) do
                if nt == node_type or nt == "any" then
                    type_match = true
                    break
                end
            end
            if not type_match then ok = false end
        end

        -- 2. 精确节点匹配（可选，用于特定节点专属事件）
        if ok and evt.node_ids then
            local id_match = false
            for _, nid in ipairs(evt.node_ids) do
                if nid == node_id then
                    id_match = true
                    break
                end
            end
            if not id_match then ok = false end
        end

        -- 3. 冷却
        if ok and (cooldowns[evt.id] or 0) > 0 then
            ok = false
        end

        -- 4. required_flags
        if ok and evt.required_flags and #evt.required_flags > 0 then
            for _, flag in ipairs(evt.required_flags) do
                if not Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        -- 5. forbidden_flags
        if ok and evt.forbidden_flags and #evt.forbidden_flags > 0 then
            for _, flag in ipairs(evt.forbidden_flags) do
                if Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        if ok then
            table.insert(available, evt)
        end
    end

    return available
end

--- 加权随机抽取一个路点事件
---@param state table
---@param node_id string
---@param node_type string
---@return table|nil
function M.pick(state, node_id, node_type)
    local pool = M.filter(state, node_id, node_type)
    if #pool == 0 then return nil end

    local tw = 0
    for _, e in ipairs(pool) do
        tw = tw + (e.weight or 50)
    end

    local roll = math.random() * tw
    local acc = 0
    for _, e in ipairs(pool) do
        acc = acc + (e.weight or 50)
        if roll <= acc then return e end
    end
    return pool[#pool]
end

--- 按 ID 获取
---@param id string
---@return table|nil
function M.get(id)
    M._load()
    return M._by_id[id]
end

-- ============================================================
-- 冷却管理
-- ============================================================

--- 设置事件冷却
function M.set_cooldown(state, event_id, turns)
    if not state._waypoint_event_cooldowns then
        state._waypoint_event_cooldowns = {}
    end
    local evt = M._by_id[event_id]
    local cd = turns or (evt and evt.cooldown) or 4
    state._waypoint_event_cooldowns[event_id] = cd
end

--- 所有冷却递减 1（行程结束时调用）
function M.tick_cooldowns(state)
    if not state._waypoint_event_cooldowns then return end
    for k, v in pairs(state._waypoint_event_cooldowns) do
        if v > 0 then
            state._waypoint_event_cooldowns[k] = v - 1
        end
    end
end

--- 到达非聚落节点时检测是否触发事件（25% 概率）
--- 触发后将事件存入 state.flow.pending_waypoint_event
---@param state table
---@param node_id string
---@param node_type string
---@return table|nil 触发的事件
function M.check_on_arrival(state, node_id, node_type)
    -- 25% 触发概率
    if math.random() > 0.25 then return nil end

    local evt = M.pick(state, node_id, node_type)
    if not evt then return nil end

    -- 存入 pending 供 UI 使用
    if not state.flow then state.flow = {} end
    state.flow.pending_waypoint_event = evt

    return evt
end

return M

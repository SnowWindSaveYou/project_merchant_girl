--- 聚落内事件池
--- 从 JSON 加载聚落本地事件，按 settlement / 好感度 / flag / 冷却筛选
local Flags      = require("core/flags")
local DataLoader = require("data_loader/loader")

local M = {}

local CONFIG_PATH = "configs/settlement_events.json"

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
        print("[SettlementEventPool] Config not found")
        return
    end

    M._events = {}
    M._by_id  = {}

    for _, raw in ipairs(data.events or {}) do
        table.insert(M._events, raw)
        M._by_id[raw.id] = raw
    end

    print("[SettlementEventPool] Loaded " .. #M._events .. " events")
end

-- ============================================================
-- 筛选
-- ============================================================

--- 筛选某聚落可用的事件
---@param state table 游戏状态
---@param settlement_id string 当前聚落 ID
---@return table[] 可用事件
function M.filter(state, settlement_id)
    M._load()

    local cooldowns = state._settlement_event_cooldowns or {}
    local goodwill  = 0
    if state.settlements[settlement_id] then
        goodwill = state.settlements[settlement_id].goodwill or 0
    end

    local available = {}

    for _, evt in ipairs(M._events) do
        local ok = true

        -- 1. 聚落匹配
        if evt.settlement ~= settlement_id then
            ok = false
        end

        -- 2. 冷却
        if ok and (cooldowns[evt.id] or 0) > 0 then
            ok = false
        end

        -- 3. 好感下限
        if ok and evt.goodwill_min and goodwill < evt.goodwill_min then
            ok = false
        end

        -- 4. required_flags
        if ok and evt.required_flags then
            for _, flag in ipairs(evt.required_flags) do
                if not Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        -- 5. forbidden_flags
        if ok and evt.forbidden_flags then
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

--- 加权随机抽取一个聚落事件
---@param state table
---@param settlement_id string
---@return table|nil
function M.pick(state, settlement_id)
    local pool = M.filter(state, settlement_id)
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
    if not state._settlement_event_cooldowns then
        state._settlement_event_cooldowns = {}
    end
    local evt = M._by_id[event_id]
    local cd = turns or (evt and evt.cooldown) or 5
    state._settlement_event_cooldowns[event_id] = cd
end

--- 所有冷却递减 1（行程结束时调用）
function M.tick_cooldowns(state)
    if not state._settlement_event_cooldowns then return end
    for k, v in pairs(state._settlement_event_cooldowns) do
        if v > 0 then
            state._settlement_event_cooldowns[k] = v - 1
        end
    end
end

--- 到达聚落时检测是否触发事件（30% 概率）
--- 触发后将事件存入 state.flow.pending_settlement_event
---@param state table
---@param settlement_id string
---@return table|nil 触发的事件
function M.check_on_arrival(state, settlement_id)
    -- 30% 触发概率
    if math.random() > 0.30 then return nil end

    local evt = M.pick(state, settlement_id)
    if not evt then return nil end

    -- 存入 pending 供 UI 使用
    if not state.flow then state.flow = {} end
    state.flow.pending_settlement_event = evt

    return evt
end

return M

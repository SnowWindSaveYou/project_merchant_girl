--- NPC 对话池（配置驱动版）
--- 从 JSON 加载 NPC 对话数据，按 npc_id / 好感度 / flag / 冷却筛选
local Flags      = require("core/flags")
local DataLoader = require("data_loader/loader")

local M = {}

local CONFIG_PATH = "configs/npc_dialogues.json"

-- 内部数据
M._dialogues = {}   -- array of dialogue tables
M._by_id     = {}   -- id -> dialogue
M._loaded    = false

-- ============================================================
-- 加载
-- ============================================================

function M._load()
    if M._loaded then return end
    M._loaded = true

    local data = DataLoader.load(CONFIG_PATH)
    if not data then
        print("[NpcDialoguePool] Config not found")
        return
    end

    M._dialogues = {}
    M._by_id     = {}

    for _, raw in ipairs(data.dialogues or {}) do
        table.insert(M._dialogues, raw)
        M._by_id[raw.id] = raw
    end

    print("[NpcDialoguePool] Loaded " .. #M._dialogues .. " dialogues")
end

-- ============================================================
-- 筛选
-- ============================================================

--- 按当前状态筛选某 NPC 的可用对话
---@param state table
---@param npc_id string NPC 标识
---@return table[]
function M.filter(state, npc_id)
    M._load()

    local cooldowns = state.narrative and state.narrative.npc_cooldowns or {}
    local settlement_id = nil

    -- 获取 NPC 对应聚落的好感度
    -- 驻留 NPC：映射到固定聚落
    -- 流浪 NPC：使用当前所在位置的好感度
    local NPC_SETTLEMENT = {
        shen_he      = "greenhouse",
        han_ce       = "tower",
        wu_shiqi     = "ruins_camp",
        bai_shu      = "bell_tower",
        zhao_miao    = "greenhouse_farm",
        cheng_yuan   = "dome_outpost",
        a_xiu        = "metro_camp",
        su_mo        = "old_church",
        dao_yu       = "ruins_camp",
        xie_ling     = "bell_tower",
    }
    -- 流浪 NPC 集合
    local WANDERING_NPCS = { meng_hui = true, ming_sha = true }

    settlement_id = NPC_SETTLEMENT[npc_id]
    if not settlement_id and WANDERING_NPCS[npc_id] then
        -- 流浪 NPC：用玩家当前所在位置的好感度
        settlement_id = state.map and state.map.current_location or nil
    end
    local goodwill = 0
    if settlement_id and state.settlements[settlement_id] then
        goodwill = state.settlements[settlement_id].goodwill or 0
    end

    local available = {}

    for _, d in ipairs(M._dialogues) do
        local ok = true

        -- 1. NPC 匹配
        if d.npc_id ~= npc_id then
            ok = false
        end

        -- 2. 冷却
        if ok and (cooldowns[d.id] or 0) > 0 then
            ok = false
        end

        -- 3. 好感范围
        if ok then
            local gmin = d.goodwill_min or 0
            local gmax = d.goodwill_max or 999
            if goodwill < gmin or goodwill > gmax then
                ok = false
            end
        end

        -- 4. required_flags
        if ok and d.required_flags then
            for _, flag in ipairs(d.required_flags) do
                if not Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        -- 5. forbidden_flags
        if ok and d.forbidden_flags then
            for _, flag in ipairs(d.forbidden_flags) do
                if Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        if ok then
            table.insert(available, d)
        end
    end

    return available
end

--- 加权随机抽取一段对话
---@param state table
---@param npc_id string
---@return table|nil
function M.pick(state, npc_id)
    local pool = M.filter(state, npc_id)
    if #pool == 0 then return nil end

    local tw = 0
    for _, d in ipairs(pool) do
        tw = tw + (d.weight or 50)
    end

    local roll = math.random() * tw
    local acc = 0
    for _, d in ipairs(pool) do
        acc = acc + (d.weight or 50)
        if roll <= acc then return d end
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

--- 设置对话冷却
function M.set_cooldown(state, dialogue_id, turns)
    if not state.narrative then return end
    if not state.narrative.npc_cooldowns then
        state.narrative.npc_cooldowns = {}
    end
    local d = M._by_id[dialogue_id]
    local cd = turns or (d and d.cooldown) or 3
    state.narrative.npc_cooldowns[dialogue_id] = cd
end

--- 所有冷却递减 1（行程结束时调用）
function M.tick_cooldowns(state)
    if not state.narrative or not state.narrative.npc_cooldowns then return end
    for k, v in pairs(state.narrative.npc_cooldowns) do
        if v > 0 then
            state.narrative.npc_cooldowns[k] = v - 1
        end
    end
end

return M

--- 篝火对话池（配置驱动版）
--- 从 JSON 加载对话数据，按关系阶段 / flag / 冷却筛选
local Flags      = require("core/flags")
local DataLoader = require("data_loader/loader")

local M = {}

local CONFIG_PATH         = "configs/campfire_dialogues.json"
local STORY_CONFIG_PATH   = "configs/story_dialogues.json"
local TUTORIAL_CONFIG_PATH = "configs/tutorial_dialogues.json"

-- 内部数据
M._dialogues    = {}   -- array of dialogue tables
M._by_id        = {}   -- id -> dialogue
M._loaded       = false

-- ============================================================
-- 关系阶段判定
-- ============================================================

--- 根据两角色关系值返回当前阶段
---@param state table
---@return string "early"|"mid"|"late"
function M.get_relation_stage(state)
    local r = 0
    if state.character then
        r = math.max(
            state.character.linli  and state.character.linli.relation  or 0,
            state.character.taoxia and state.character.taoxia.relation or 0
        )
    end
    if r >= 60 then return "late" end
    if r >= 20 then return "mid" end
    return "early"
end

-- ============================================================
-- 加载
-- ============================================================

function M._load()
    if M._loaded then return end
    M._loaded = true

    local data = DataLoader.load(CONFIG_PATH)
    if not data then
        print("[DialoguePool] Config not found")
        return
    end

    M._dialogues = {}
    M._by_id     = {}

    for _, raw in ipairs(data.dialogues or {}) do
        table.insert(M._dialogues, raw)
        M._by_id[raw.id] = raw
    end

    print("[DialoguePool] Loaded " .. #M._dialogues .. " dialogues")

    -- 加载主线剧情对话（合并到同一个池中）
    local story_data = DataLoader.load(STORY_CONFIG_PATH)
    if story_data then
        local count = 0
        for _, raw in ipairs(story_data.dialogues or {}) do
            raw.is_story = true  -- 标记为主线对话
            table.insert(M._dialogues, raw)
            M._by_id[raw.id] = raw
            count = count + 1
        end
        if count > 0 then
            print("[DialoguePool] Loaded " .. count .. " story dialogues")
        end
    end

    -- 加载教程对话（合并到同一个池中，但标记为 is_tutorial）
    local tut_data = DataLoader.load(TUTORIAL_CONFIG_PATH)
    if tut_data then
        local count = 0
        for _, raw in ipairs(tut_data.dialogues or {}) do
            raw.is_tutorial = true  -- 标记为教程对话
            table.insert(M._dialogues, raw)
            M._by_id[raw.id] = raw
            count = count + 1
        end
        if count > 0 then
            print("[DialoguePool] Loaded " .. count .. " tutorial dialogues")
        end
    end
end

-- ============================================================
-- 筛选
-- ============================================================

--- 检查对话是否匹配当前节点类型
---@param d table 对话数据
---@param node_type string|nil 当前节点类型
---@return boolean
local function match_node_type(d, node_type)
    local nt = d.node_types
    -- 无 node_types 字段或空数组 → 任意节点可用
    if not nt or #nt == 0 then return true end
    -- 包含 "any" → 任意可用
    for _, t in ipairs(nt) do
        if t == "any" then return true end
        if t == node_type then return true end
    end
    return false
end

--- 按当前状态筛选可用对话
---@param state table
---@param node_type string|nil 当前节点类型（nil 时不做节点过滤）
---@return table[]
function M.filter(state, node_type)
    M._load()

    local stage = M.get_relation_stage(state)
    local cooldowns = state.narrative and state.narrative.campfire_cooldowns or {}
    local available = {}

    for _, d in ipairs(M._dialogues) do
        local ok = true

        -- 1. 冷却
        if (cooldowns[d.id] or 0) > 0 then
            ok = false
        end

        -- 2. 节点类型
        if ok and node_type then
            if not match_node_type(d, node_type) then
                ok = false
            end
        end

        -- 3. 关系阶段
        if ok and d.relation_stage and d.relation_stage ~= "any" then
            if d.relation_stage ~= stage then
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

        -- 6. arrival_only：仅供到达拦截使用，不进入篝火对话池
        if ok and d.arrival_only then
            ok = false
        end

        -- 7. min_trips（最低行程数要求）
        if ok and d.min_trips then
            local trips = state.stats and state.stats.total_trips or 0
            if trips < d.min_trips then
                ok = false
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
---@param node_type string|nil 当前节点类型
---@return table|nil
function M.pick(state, node_type)
    local pool = M.filter(state, node_type)
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
    if not state.narrative.campfire_cooldowns then
        state.narrative.campfire_cooldowns = {}
    end
    local d = M._by_id[dialogue_id]
    local cd = turns or (d and d.cooldown) or 3
    state.narrative.campfire_cooldowns[dialogue_id] = cd
end

--- 所有冷却递减 1（行程结束时调用）
function M.tick_cooldowns(state)
    if not state.narrative or not state.narrative.campfire_cooldowns then return end
    for k, v in pairs(state.narrative.campfire_cooldowns) do
        if v > 0 then
            state.narrative.campfire_cooldowns[k] = v - 1
        end
    end
end

return M

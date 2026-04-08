--- 篝火会话管理
--- 检查开启条件、消耗资源、抽取对话、执行选择结果
local DialoguePool = require("narrative/dialogue_pool")
local EventExec    = require("events/event_executor")
local ItemUse      = require("economy/item_use")
local Graph        = require("map/world_graph")

local M = {}

-- ============================================================
-- 条件检查
-- ============================================================

--- 获取当前节点类型
---@param state table
---@return string|nil node_type
---@return table|nil node
local function get_current_node(state)
    local loc = state.map.current_location
    local node = Graph.get_node(loc)
    return node and node.type or nil, node
end

--- 检查是否可以开启篝火
---@param state table
---@return boolean ok
---@return string|nil reason 不可开启时的原因
function M.can_start(state)
    -- 1. 必须停在某个节点（非行驶中）
    local node_type, node = get_current_node(state)
    if not node then
        return false, "行驶中无法点篝火"
    end

    -- 2. 必须有食物或燃料
    local cargo = state.truck.cargo or {}
    local has_food = (cargo.food_can or 0) >= 1
    local has_fuel = (cargo.fuel_cell or 0) >= 1
    if not has_food and not has_fuel then
        return false, "需要 1 罐头食品或 1 燃料芯"
    end

    -- 3. 必须有可用对话（按当前节点类型筛选）
    local pool = DialoguePool.filter(state, node_type)
    if #pool == 0 then
        return false, "暂时没有新的话题"
    end

    return true, nil
end

--- 获取关系阶段描述
---@param state table
---@return string stage 阶段标识 ("early"/"mid"/"late")
---@return string label 阶段显示名
function M.get_relation_stage(state)
    local stage = DialoguePool.get_relation_stage(state)
    local labels = { early = "初识", mid = "默契", late = "羁绊" }
    return stage, labels[stage] or stage
end

-- ============================================================
-- 会话流程
-- ============================================================

--- 开启篝火会话：消耗资源，抽取对话
---@param state table
---@return table|nil dialogue 对话数据（nil 表示无可用对话）
---@return string|nil consumed 消耗的物品 ID
function M.start(state)
    local ok, reason = M.can_start(state)
    if not ok then
        print("[Campfire] Cannot start: " .. (reason or "unknown"))
        return nil, nil
    end

    -- 消耗资源（优先 food_can）
    local cargo = state.truck.cargo or {}
    local consumed
    if (cargo.food_can or 0) >= 1 then
        ItemUse.consume(state, "food_can", 1)
        consumed = "food_can"
    else
        ItemUse.consume(state, "fuel_cell", 1)
        consumed = "fuel_cell"
    end

    -- 抽取对话（按当前节点类型）
    local node_type = get_current_node(state)
    local dialogue = DialoguePool.pick(state, node_type)
    if not dialogue then
        print("[Campfire] No dialogue available after consume")
        return nil, consumed
    end

    -- 设置冷却
    DialoguePool.set_cooldown(state, dialogue.id)

    -- 计数
    if not state.narrative then state.narrative = {} end
    state.narrative.campfire_count = (state.narrative.campfire_count or 0) + 1

    print("[Campfire] Started: " .. dialogue.id .. " (" .. dialogue.title .. ")")
    return dialogue, consumed
end

--- 开启指定对话的篝火会话（主线剧情强制触发）
--- 跳过池抽取，直接使用指定 dialogue_id，仍消耗资源
---@param state table
---@param dialogue_id string 对话 ID（必须存在于 dialogue_pool 中）
---@return table|nil dialogue
---@return string|nil consumed
function M.start_with_dialogue(state, dialogue_id)
    -- 消耗资源（与普通 start 相同，优先 food_can）
    local cargo = state.truck.cargo or {}
    local consumed
    if (cargo.food_can or 0) >= 1 then
        ItemUse.consume(state, "food_can", 1)
        consumed = "food_can"
    elseif (cargo.fuel_cell or 0) >= 1 then
        ItemUse.consume(state, "fuel_cell", 1)
        consumed = "fuel_cell"
    end
    -- 注：即使没有资源也允许触发（主线剧情不应被资源阻断）

    local dialogue = DialoguePool.get(dialogue_id)
    if not dialogue then
        print("[Campfire] Story dialogue not found: " .. tostring(dialogue_id))
        return nil, consumed
    end

    DialoguePool.set_cooldown(state, dialogue.id)

    if not state.narrative then state.narrative = {} end
    state.narrative.campfire_count = (state.narrative.campfire_count or 0) + 1

    print("[Campfire] Story dialogue forced: " .. dialogue.id .. " (" .. dialogue.title .. ")")
    return dialogue, consumed
end

--- 执行选择结果
---@param state table
---@param dialogue table 当前对话数据
---@param choice_index number 选择索引（1-based）
---@return table result { ops_log, memory, result_text }
function M.apply_choice(state, dialogue, choice_index)
    local choices = dialogue.choices or {}
    local choice = choices[choice_index]
    if not choice then
        print("[Campfire] Invalid choice index: " .. tostring(choice_index))
        return { ops_log = {}, result_text = "" }
    end

    -- 执行 ops（复用 event_executor）
    local ops_log = EventExec.apply(state, choice.ops)

    -- 存储 memory
    local memory = choice.memory
    if memory then
        if not state.narrative then state.narrative = {} end
        if not state.narrative.memories then state.narrative.memories = {} end
        -- 避免重复
        local exists = false
        for _, m in ipairs(state.narrative.memories) do
            if m.id == memory.id then exists = true; break end
        end
        if not exists then
            table.insert(state.narrative.memories, {
                id    = memory.id,
                title = memory.title,
                desc  = memory.desc,
                time  = os.time(),
            })
            print("[Campfire] Memory added: " .. memory.id)
        end
    end

    return {
        ops_log     = ops_log,
        memory      = memory,
        result_text = choice.result_text or "",
    }
end

return M

--- 闲逛系统
--- 玩家在聚落中随意逛逛，体验当地风土人情
--- 消耗 1 饮用水，随机体验 2-3 个场景
local DataLoader = require("data_loader/loader")
local EventExec  = require("events/event_executor")
local ItemUse    = require("economy/item_use")
local Flags      = require("core/flags")
local Graph      = require("map/world_graph")

local M = {}

local CONFIG_PATH = "configs/stroll_scenes.json"

-- 懒加载场景数据 { settlement_id = [ scene, ... ] }
local _data   = nil
local _loaded = false

local function ensure_loaded()
    if _loaded then return end
    _loaded = true
    _data = DataLoader.load(CONFIG_PATH)
    if not _data then
        print("[Stroll] Config not found: " .. CONFIG_PATH)
        _data = {}
    end
    -- 统计
    local total = 0
    for sid, scenes in pairs(_data) do
        total = total + #scenes
    end
    print("[Stroll] Loaded " .. total .. " scenes")
end

-- ============================================================
-- 条件检查
-- ============================================================

--- 检查是否可以闲逛
---@param state table
---@return boolean ok
---@return string|nil reason
function M.can_start(state)
    -- 1. 必须在聚落节点
    local loc = state.map.current_location
    local node = Graph.get_node(loc)
    if not node or node.type ~= "settlement" then
        return false, "只能在聚落闲逛", nil
    end

    -- 2. 本次停留未闲逛过
    local used = state._visit_used or {}
    if used.stroll then
        return false, "本次停留已逛过", nil
    end

    -- 3. 有水
    local cargo = state.truck.cargo or {}
    if (cargo.water or 0) < 1 then
        return false, "需要 1 饮用水", nil
    end

    -- 4. 该聚落有可用场景
    ensure_loaded()
    local scenes = _data[loc]
    if not scenes or #scenes == 0 then
        return false, "这里没什么可逛的", nil
    end

    -- 按好感过滤
    local goodwill = 0
    if state.settlements[loc] then
        goodwill = state.settlements[loc].goodwill or 0
    end
    local available = 0
    for _, scene in ipairs(scenes) do
        if goodwill >= (scene.min_goodwill or 0) then
            available = available + 1
        end
    end
    if available == 0 then
        return false, "这里没什么可逛的", nil
    end

    return true, nil
end

-- ============================================================
-- 开始闲逛
-- ============================================================

--- 开始闲逛：消耗水，随机抽 2-3 个场景
---@param state table
---@return table[]|nil scenes 场景列表
---@return string|nil consumed 消耗的物品 ID
function M.start(state)
    local ok, reason = M.can_start(state)
    if not ok then
        print("[Stroll] Cannot start: " .. (reason or "unknown"))
        return nil, nil
    end

    -- 消耗 1 水
    ItemUse.consume(state, "water", 1)
    local consumed = "water"

    -- 标记本次停留已使用
    if not state._visit_used then state._visit_used = {} end
    state._visit_used.stroll = true

    -- 按好感过滤
    local loc = state.map.current_location
    local allScenes = _data[loc] or {}
    local goodwill = 0
    if state.settlements[loc] then
        goodwill = state.settlements[loc].goodwill or 0
    end

    local pool = {}
    for _, scene in ipairs(allScenes) do
        if goodwill >= (scene.min_goodwill or 0) then
            table.insert(pool, scene)
        end
    end

    -- 随机抽 2-3 个不重复场景
    local count = math.min(#pool, math.random(2, 3))
    local picked = {}
    local used_indices = {}

    for _ = 1, count do
        -- 从剩余池中随机选一个
        local attempts = 0
        while attempts < 50 do
            local idx = math.random(1, #pool)
            if not used_indices[idx] then
                used_indices[idx] = true
                table.insert(picked, pool[idx])
                break
            end
            attempts = attempts + 1
        end
    end

    print("[Stroll] Started at " .. loc .. ", " .. #picked .. " scenes picked")
    return picked, consumed
end

-- ============================================================
-- 执行选择
-- ============================================================

--- 执行某个场景中的选择
---@param state table
---@param scene table 场景数据
---@param choice_index number 选择索引（1-based）
---@return table result { ops_log, result_text }
function M.apply_choice(state, scene, choice_index)
    local choices = scene.choices or {}
    local choice = choices[choice_index]
    if not choice then
        print("[Stroll] Invalid choice index: " .. tostring(choice_index))
        return { ops_log = {}, result_text = "" }
    end

    -- 执行 ops
    local ops_log = EventExec.apply(state, choice.ops)

    -- 处理 set_flags
    if choice.set_flags then
        for _, flag_id in ipairs(choice.set_flags) do
            Flags.set(state, flag_id)
        end
    end

    -- 处理 clear_flags
    if choice.clear_flags then
        for _, flag_id in ipairs(choice.clear_flags) do
            Flags.clear(state, flag_id)
        end
    end

    return {
        ops_log     = ops_log,
        result_text = choice.result_text or "",
    }
end

return M

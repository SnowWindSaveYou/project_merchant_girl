--- 信件系统核心模块
--- 负责信件加载、触发条件检查、入队、领取、标记已读
local DataLoader = require("data_loader/loader")
local Flags      = require("core/flags")

local M = {}

local LETTERS_PATH = "configs/letters.json"

--- 已解析的信件配置（懒加载）
---@type table[]|nil
local _letters = nil

-- ============================================================
-- 数据加载
-- ============================================================

--- 获取全部信件配置
---@return table[]
function M.get_all_letters()
    if _letters then return _letters end
    local raw = DataLoader.load(LETTERS_PATH)
    if raw and raw.letters then
        _letters = raw.letters
    else
        _letters = {}
        print("[LetterSystem] WARNING: Failed to load " .. LETTERS_PATH)
    end
    return _letters
end

--- 根据ID获取单封信件配置
---@param letter_id string
---@return table|nil
function M.get_letter(letter_id)
    local all = M.get_all_letters()
    for _, letter in ipairs(all) do
        if letter.id == letter_id then
            return letter
        end
    end
    return nil
end

-- ============================================================
-- 兼容旧存档：确保 letters 字段存在
-- ============================================================
local function _ensure(state)
    local n = state.narrative
    if not n.letters_pending   then n.letters_pending   = {} end
    if not n.letters_read      then n.letters_read      = {} end
    if not n.letters_delivered  then n.letters_delivered  = {} end
end

-- ============================================================
-- 触发条件检查
-- ============================================================

--- 检查一封信是否满足触发条件
---@param state table
---@param letter table 信件配置
---@return boolean
local function _check_trigger(state, letter)
    local trigger = letter.trigger
    if not trigger then return true end

    -- 必须旗标
    if trigger.required_flags then
        for _, flag in ipairs(trigger.required_flags) do
            if not Flags.has(state, flag) then
                return false
            end
        end
    end

    -- 禁止旗标
    if trigger.forbidden_flags then
        for _, flag in ipairs(trigger.forbidden_flags) do
            if Flags.has(state, flag) then
                return false
            end
        end
    end

    -- 最低行程数
    if trigger.after_trips then
        if (state.stats.total_trips or 0) < trigger.after_trips then
            return false
        end
    end

    -- 最低章节
    if trigger.min_chapter then
        if (state.narrative.chapter or 0) < trigger.min_chapter then
            return false
        end
    end

    -- 角色关系要求
    if trigger.min_relation then
        for char_id, minVal in pairs(trigger.min_relation) do
            local char = state.character[char_id]
            local rel = char and char.relation or 0
            if rel < minVal then
                return false
            end
        end
    end

    return true
end

-- ============================================================
-- 信件扫描与入队
-- ============================================================

--- 扫描所有信件，将满足条件且未曾入队的信件加入待领取队列
--- 通常在每趟行程结束时调用
---@param state table
---@return string[] new_ids 本次新加入的信件ID列表
function M.scan_and_enqueue(state)
    _ensure(state)
    local all = M.get_all_letters()
    local new_ids = {}

    for _, letter in ipairs(all) do
        local lid = letter.id
        -- 跳过已触发过的（无论是否已读）
        if state.narrative.letters_delivered[lid] then
            goto continue
        end
        -- 检查触发条件
        if _check_trigger(state, letter) then
            table.insert(state.narrative.letters_pending, lid)
            state.narrative.letters_delivered[lid] = true
            table.insert(new_ids, lid)
            print("[LetterSystem] Enqueued: " .. lid)
        end
        ::continue::
    end

    return new_ids
end

-- ============================================================
-- 查询
-- ============================================================

--- 是否有待领取信件
---@param state table
---@return boolean
function M.has_pending(state)
    _ensure(state)
    return #state.narrative.letters_pending > 0
end

--- 获取待领取信件数量
---@param state table
---@return number
function M.pending_count(state)
    _ensure(state)
    return #state.narrative.letters_pending
end

--- 获取待领取信件列表（完整配置）
---@param state table
---@return table[]
function M.get_pending_letters(state)
    _ensure(state)
    local result = {}
    for _, lid in ipairs(state.narrative.letters_pending) do
        local letter = M.get_letter(lid)
        if letter then
            table.insert(result, letter)
        end
    end
    return result
end

--- 获取已读信件列表（完整配置）
---@param state table
---@return table[]
function M.get_read_letters(state)
    _ensure(state)
    local all = M.get_all_letters()
    local result = {}
    for _, letter in ipairs(all) do
        if state.narrative.letters_read[letter.id] then
            table.insert(result, letter)
        end
    end
    return result
end

--- 已读信件数量
---@param state table
---@return number
function M.read_count(state)
    _ensure(state)
    local count = 0
    for _ in pairs(state.narrative.letters_read) do
        count = count + 1
    end
    return count
end

-- ============================================================
-- 领取与阅读
-- ============================================================

--- 领取所有待领取信件（从 pending 移到 read）
--- 返回领取的信件配置列表
---@param state table
---@return table[]
function M.collect_all(state)
    _ensure(state)
    local collected = {}
    for _, lid in ipairs(state.narrative.letters_pending) do
        local letter = M.get_letter(lid)
        if letter then
            table.insert(collected, letter)
            state.narrative.letters_read[lid] = true
        end
    end
    state.narrative.letters_pending = {}
    return collected
end

--- 领取单封信件
---@param state table
---@param letter_id string
---@return table|nil letter 领取的信件配置
function M.collect_one(state, letter_id)
    _ensure(state)
    -- 从 pending 中移除
    for i, lid in ipairs(state.narrative.letters_pending) do
        if lid == letter_id then
            table.remove(state.narrative.letters_pending, i)
            state.narrative.letters_read[letter_id] = true
            return M.get_letter(letter_id)
        end
    end
    return nil
end

--- 标记信件已读（阅读信纸后调用，应用效果）
---@param state table
---@param letter table 信件配置
function M.apply_effects(state, letter)
    if not letter.effects then return end
    local effects = letter.effects

    -- 设置旗标
    if effects.set_flags then
        for _, flag in ipairs(effects.set_flags) do
            Flags.set(state, flag)
        end
    end

    -- 解锁线索（设置对应旗标供 NPC 对话检测）
    if effects.unlock_hint then
        Flags.set(state, "hint_" .. effects.unlock_hint)
    end
end

-- ============================================================
-- 调试接口
-- ============================================================

--- 强制入队一封信（调试用）
---@param state table
---@param letter_id string
function M.debug_enqueue(state, letter_id)
    _ensure(state)
    if not state.narrative.letters_delivered[letter_id] then
        table.insert(state.narrative.letters_pending, letter_id)
        state.narrative.letters_delivered[letter_id] = true
        print("[LetterSystem] DEBUG enqueued: " .. letter_id)
    else
        -- 已触发过，强制重新入队
        -- 先从 read 移除
        state.narrative.letters_read[letter_id] = nil
        -- 检查是否已在 pending 中
        for _, lid in ipairs(state.narrative.letters_pending) do
            if lid == letter_id then return end
        end
        table.insert(state.narrative.letters_pending, letter_id)
        print("[LetterSystem] DEBUG re-enqueued: " .. letter_id)
    end
end

--- 重置所有信件状态（调试用）
---@param state table
function M.debug_reset(state)
    _ensure(state)
    state.narrative.letters_pending   = {}
    state.narrative.letters_read      = {}
    state.narrative.letters_delivered  = {}
    print("[LetterSystem] DEBUG: All letter state reset")
end

return M

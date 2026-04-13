--- 路景描写系统
--- 行驶中定时展示环境描写文本，营造公路旅行氛围
--- 与 Chatter 互斥：仅在没有对话气泡时才显示
--- 不需要玩家交互，纯叙事性质
local DataLoader = require("data_loader/loader")
local Flags      = require("core/flags")

local M = {}

local CONFIG_PATH = "configs/scenery.json"

-- ============================================================
-- 配置
-- ============================================================
M.FIRST_DELAY_MIN  = 20   -- 首次路景最短等待（秒）
M.FIRST_DELAY_MAX  = 30
M.INTERVAL_MIN     = 15   -- 后续间隔最短
M.INTERVAL_MAX     = 25
M.DISPLAY_DURATION = 5    -- 默认显示时长（秒）
M.MAX_PER_TRIP     = 6    -- 单趟最多路景数
M.SILENCE_BOOST_THRESHOLD = 45  -- 长时间无内容后提升静默类权重（秒）
M.SILENCE_WEIGHT_MULT     = 3   -- 静默类权重倍率

-- ============================================================
-- 内部数据
-- ============================================================
local _entries = nil  -- 路景池（懒加载）

local function _load_entries()
    if _entries then return _entries end
    local data = DataLoader.load(CONFIG_PATH)
    if data and data.entries then
        _entries = data.entries
        print("[Scenery] Loaded " .. #_entries .. " entries")
    else
        _entries = {}
        print("[Scenery] No entries found")
    end
    return _entries
end

local function _random_interval(lo, hi)
    return lo + math.random() * (hi - lo)
end

-- ============================================================
-- 公开 API
-- ============================================================

--- 创建初始状态（出发时调用）
---@return table
function M.init()
    return {
        elapsed            = 0,
        next_check         = _random_interval(M.FIRST_DELAY_MIN, M.FIRST_DELAY_MAX),
        current            = nil,   -- { id, text, category, duration, shown_time }
        shown_ids          = {},
        total_shown        = 0,
        no_content_elapsed = 0,     -- 距上次显示任何内容的计时（用于静默增权）
    }
end

--- 每帧驱动（由 screen_home.update 调用）
---@param state table 游戏状态
---@param dt number 帧间隔
---@param progress number 行程进度 [0,1]
---@param segment table|nil 当前路段信息
---@param chatter_active boolean 是否正有对话气泡
function M.update(state, dt, progress, segment, chatter_active)
    local sc = state.flow.scenery
    if not sc then return end

    -- 1. 如果有正在显示的路景，更新计时
    if sc.current then
        sc.current.shown_time = sc.current.shown_time + dt
        sc.no_content_elapsed = 0  -- 有内容在显示时重置
        if sc.current.shown_time >= sc.current.duration then
            sc.current = nil  -- 到期消失
        end
        return
    end

    -- 2. 让步给 Chatter：对话正在显示时不触发路景
    if chatter_active then
        sc.no_content_elapsed = 0  -- 有对话也算"有内容"
        return
    end

    -- 3. 累计无内容时间
    sc.no_content_elapsed = sc.no_content_elapsed + dt

    -- 4. 达到上限
    if sc.total_shown >= M.MAX_PER_TRIP then return end

    -- 5. 推进定时器
    sc.elapsed = sc.elapsed + dt
    if sc.elapsed < sc.next_check then return end

    -- 6. 时间到，尝试抽取
    sc.elapsed = 0
    sc.next_check = _random_interval(M.INTERVAL_MIN, M.INTERVAL_MAX)

    local entry = M._pick(state, progress, segment)
    if entry then
        sc.current = {
            id         = entry.id,
            text       = entry.text,
            category   = entry.category,
            duration   = entry.duration or M.DISPLAY_DURATION,
            shown_time = 0,
        }
        sc.shown_ids[entry.id] = true
        sc.total_shown = sc.total_shown + 1
        sc.no_content_elapsed = 0
    end
end

--- 获取当前正在显示的路景
---@param state table
---@return table|nil  { id, text, category, duration, shown_time }
function M.get_current(state)
    local sc = state.flow.scenery
    return sc and sc.current
end

--- 手动关闭当前路景
---@param state table
function M.dismiss(state)
    local sc = state.flow.scenery
    if sc then sc.current = nil end
end

-- ============================================================
-- 内部：加权随机抽取
-- ============================================================

--- 筛选并加权随机抽取一条路景
---@param state table
---@param progress number
---@param segment table|nil
---@return table|nil
function M._pick(state, progress, segment)
    local pool = _load_entries()
    local candidates = {}
    local sc = state.flow.scenery
    local edge_type = segment and segment.edge_type or nil

    -- 判断是否处于"长时间无内容"状态
    local silence_boost = sc.no_content_elapsed >= M.SILENCE_BOOST_THRESHOLD

    for _, entry in ipairs(pool) do
        local ok = true

        -- 去重：本趟已展示过
        if sc.shown_ids[entry.id] then ok = false end

        -- 进度范围
        if ok and entry.progress_range then
            local lo, hi = entry.progress_range[1], entry.progress_range[2]
            if progress < lo or progress > hi then ok = false end
        end

        -- 路况过滤
        if ok and entry.edge_types and #entry.edge_types > 0 then
            local match = false
            for _, et in ipairs(entry.edge_types) do
                if et == edge_type then match = true; break end
            end
            if not match then ok = false end
        end

        -- 特定路段 ID 过滤
        if ok and entry.edge_ids and #entry.edge_ids > 0 then
            local edge_id = segment and segment.edge_id or nil
            local match = false
            for _, eid in ipairs(entry.edge_ids) do
                if eid == edge_id then match = true; break end
            end
            if not match then ok = false end
        end

        -- required_flags
        if ok and entry.required_flags and #entry.required_flags > 0 then
            for _, flag in ipairs(entry.required_flags) do
                if not Flags.has(state, flag) then ok = false; break end
            end
        end

        -- forbidden_flags
        if ok and entry.forbidden_flags and #entry.forbidden_flags > 0 then
            for _, flag in ipairs(entry.forbidden_flags) do
                if Flags.has(state, flag) then ok = false; break end
            end
        end

        if ok then
            -- 计算有效权重：长时间无内容时提升静默类权重
            local w = entry.weight or 20
            if silence_boost and entry.category == "silence" then
                w = w * M.SILENCE_WEIGHT_MULT
            end
            table.insert(candidates, { entry = entry, weight = w })
        end
    end

    if #candidates == 0 then return nil end

    -- 加权随机
    local tw = 0
    for _, c in ipairs(candidates) do tw = tw + c.weight end
    local roll = math.random() * tw
    local acc = 0
    for _, c in ipairs(candidates) do
        acc = acc + c.weight
        if roll <= acc then return c.entry end
    end
    return candidates[#candidates].entry
end

return M

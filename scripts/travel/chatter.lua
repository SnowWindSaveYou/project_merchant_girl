--- 车内日常对话系统
--- 行驶中定时从对话池抽取林砾/陶夏的短对话，营造陪伴感
--- 不打断挂机节奏，部分对话可点击回应获得关系加成
local DataLoader = require("data_loader/loader")
local Flags      = require("core/flags")

local M = {}

local CONFIG_PATH = "configs/chatter.json"

-- ============================================================
-- 配置
-- ============================================================
M.FIRST_DELAY_MIN  = 15   -- 首次对话最短等待（秒）
M.FIRST_DELAY_MAX  = 20
M.INTERVAL_MIN     = 25   -- 后续间隔最短
M.INTERVAL_MAX     = 40
M.DISPLAY_DURATION = 8    -- 默认显示时长（秒）
M.MAX_PER_TRIP     = 10   -- 单趟最多对话数

-- ============================================================
-- 内部数据
-- ============================================================
local _dialogues = nil  -- 对话池（懒加载）

local function _load_dialogues()
    if _dialogues then return _dialogues end
    local data = DataLoader.load(CONFIG_PATH)
    if data and data.dialogues then
        _dialogues = data.dialogues
        print("[Chatter] Loaded " .. #_dialogues .. " dialogues")
    else
        _dialogues = {}
        print("[Chatter] No dialogues found")
    end
    return _dialogues
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
        elapsed     = 0,
        next_check  = _random_interval(M.FIRST_DELAY_MIN, M.FIRST_DELAY_MAX),
        current     = nil,   -- { id, speaker, text, response?, duration, shown_time }
        shown_ids   = {},
        total_shown = 0,
    }
end

--- 每帧驱动（由 screen_home.update 调用）
local _chatterUpdateLogged = false
---@param state table 游戏状态
---@param dt number 帧间隔
---@param progress number 行程进度 [0,1]
---@param segment table|nil 当前路段信息
function M.update(state, dt, progress, segment)
    local ch = state.flow.chatter
    if not ch then return end

    if not _chatterUpdateLogged then
        print(string.format("[Chatter] First update call, next_check=%.1f", ch.next_check))
        _chatterUpdateLogged = true
    end

    -- 1. 如果有正在显示的对话，更新计时
    if ch.current then
        ch.current.shown_time = ch.current.shown_time + dt
        if ch.current.shown_time >= ch.current.duration then
            ch.current = nil  -- 到期消失
        end
        return  -- 有对话显示时不触发新的
    end

    -- 2. 达到上限
    if ch.total_shown >= M.MAX_PER_TRIP then return end

    -- 3. 推进定时器
    ch.elapsed = ch.elapsed + dt
    if ch.elapsed < ch.next_check then return end

    -- 4. 时间到，尝试抽取
    ch.elapsed = 0
    ch.next_check = _random_interval(M.INTERVAL_MIN, M.INTERVAL_MAX)
    print(string.format("[Chatter] Timer fired, progress=%.2f, trying pick (#%d/%d)",
        progress or 0, ch.total_shown + 1, M.MAX_PER_TRIP))

    local dlg = M._pick(state, progress, segment)
    if dlg then
        print("[Chatter] Picked: " .. dlg.id .. " speaker=" .. dlg.speaker)
    else
        print("[Chatter] No candidate matched")
    end
    if dlg then
        ch.current = {
            id         = dlg.id,
            speaker    = dlg.speaker,
            text       = dlg.text,
            response   = dlg.response,
            duration   = dlg.duration or M.DISPLAY_DURATION,
            shown_time = 0,
        }
        ch.shown_ids[dlg.id] = true
        ch.total_shown = ch.total_shown + 1
    end
end

--- 获取当前正在显示的对话
---@param state table
---@return table|nil
function M.get_current(state)
    local ch = state.flow.chatter
    return ch and ch.current
end

--- 玩家点击回应
---@param state table
function M.respond(state)
    local ch = state.flow.chatter
    if not ch or not ch.current or not ch.current.response then return end

    local resp = ch.current.response
    local effect = resp.effect
    if effect then
        -- 关系变化
        if effect.relation_taoxia then
            state.character.taoxia.relation =
                state.character.taoxia.relation + effect.relation_taoxia
        end
        if effect.relation_linli then
            state.character.linli.relation =
                state.character.linli.relation + effect.relation_linli
        end
        -- flag 设置
        if effect.set_flag then
            Flags.set(state, effect.set_flag)
        end
    end

    -- 回应后立即消失
    ch.current = nil
end

--- 手动关闭当前对话
---@param state table
function M.dismiss(state)
    local ch = state.flow.chatter
    if ch then ch.current = nil end
end

-- ============================================================
-- 内部：加权随机抽取
-- ============================================================

--- 筛选并加权随机抽取一条对话
---@param state table
---@param progress number
---@param segment table|nil
---@return table|nil
function M._pick(state, progress, segment)
    local pool = _load_dialogues()
    local candidates = {}

    local edge_type = segment and segment.edge_type or nil

    for _, dlg in ipairs(pool) do
        local ok = true

        -- 去重：本趟已展示过
        local ch = state.flow.chatter
        if ch.shown_ids[dlg.id] then ok = false end

        -- 进度范围
        if ok and dlg.progress_range then
            local lo, hi = dlg.progress_range[1], dlg.progress_range[2]
            if progress < lo or progress > hi then ok = false end
        end

        -- 路况过滤
        if ok and dlg.edge_types and #dlg.edge_types > 0 then
            local match = false
            for _, et in ipairs(dlg.edge_types) do
                if et == edge_type then match = true; break end
            end
            if not match then ok = false end
        end

        -- required_flags
        if ok and dlg.required_flags and #dlg.required_flags > 0 then
            for _, flag in ipairs(dlg.required_flags) do
                if not Flags.has(state, flag) then ok = false; break end
            end
        end

        -- forbidden_flags
        if ok and dlg.forbidden_flags and #dlg.forbidden_flags > 0 then
            for _, flag in ipairs(dlg.forbidden_flags) do
                if Flags.has(state, flag) then ok = false; break end
            end
        end

        if ok then
            table.insert(candidates, dlg)
        end
    end

    if #candidates == 0 then return nil end

    -- 加权随机
    local tw = 0
    for _, d in ipairs(candidates) do tw = tw + (d.weight or 50) end
    local roll = math.random() * tw
    local acc = 0
    for _, d in ipairs(candidates) do
        acc = acc + (d.weight or 50)
        if roll <= acc then return d end
    end
    return candidates[#candidates]
end

return M

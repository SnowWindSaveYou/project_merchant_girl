--- 收音机/无线电系统
--- 行驶中可切换频道收听不同内容，偶尔给小奖励
--- 频道：鸣砂播报 / 聚落广播 / 神秘信号
local DataLoader = require("data_loader/loader")
local Flags      = require("core/flags")

local M = {}

local CONFIG_PATH = "configs/radio_broadcasts.json"

-- ============================================================
-- 配置
-- ============================================================
M.FIRST_DELAY    = 5     -- 开启后首条播报延迟（秒）
M.INTERVAL_MIN   = 20    -- 播报轮换最短间隔
M.INTERVAL_MAX   = 30    -- 播报轮换最长间隔
M.DISPLAY_DURATION = 10  -- 默认播报显示时长（秒）

M.CHANNELS = { "mingsha", "settlement", "mystery" }
M.CHANNEL_NAMES = {
    mingsha    = "鸣砂",
    settlement = "聚落",
    mystery    = "???",
}

-- ============================================================
-- 内部数据
-- ============================================================
local _broadcasts = nil  -- { channel_name = { broadcast... } }

local function _load_broadcasts()
    if _broadcasts then return _broadcasts end
    local data = DataLoader.load(CONFIG_PATH)
    if data and data.broadcasts then
        _broadcasts = data.broadcasts
        local total = 0
        for _, list in pairs(_broadcasts) do total = total + #list end
        print("[Radio] Loaded " .. total .. " broadcasts")
    else
        _broadcasts = {}
        print("[Radio] No broadcasts found")
    end
    return _broadcasts
end

local function _random_interval()
    return M.INTERVAL_MIN + math.random() * (M.INTERVAL_MAX - M.INTERVAL_MIN)
end

-- ============================================================
-- 公开 API
-- ============================================================

--- 创建初始状态（出发时调用）
---@return table
function M.init()
    return {
        on       = false,
        channel  = "mingsha",
        elapsed  = 0,
        next_at  = M.FIRST_DELAY,
        current  = nil,  -- { id, text, reward?, duration, shown_time, reward_claimed }
        shown_ids = {},
    }
end

--- 每帧驱动
---@param state table 游戏状态
---@param dt number 帧间隔
function M.update(state, dt)
    local r = state.flow.radio
    if not r or not r.on then return end

    -- 如果有当前播报，更新显示计时
    if r.current then
        r.current.shown_time = r.current.shown_time + dt
        if r.current.shown_time >= r.current.duration then
            r.current = nil  -- 到期消失
        else
            -- 还在显示中，不触发新的
            r.elapsed = r.elapsed + dt
            return
        end
    end

    -- 推进定时器
    r.elapsed = r.elapsed + dt
    if r.elapsed < r.next_at then return end

    -- 时间到，播下一条
    r.elapsed = 0
    r.next_at = _random_interval()

    local broadcast = M._pick(state, r.channel)
    if broadcast then
        r.current = {
            id            = broadcast.id,
            text          = broadcast.text,
            reward        = broadcast.reward,
            duration      = broadcast.duration or M.DISPLAY_DURATION,
            shown_time    = 0,
            reward_claimed = false,
        }
        r.shown_ids[broadcast.id] = true
    end
end

--- 获取当前正在播放的广播
---@param state table
---@return table|nil
function M.get_current(state)
    local r = state.flow.radio
    return r and r.current
end

--- 开关收音机
---@param state table
function M.toggle(state)
    M.set_on(state, not M.is_on(state))
end

--- 显式设置收音机开关（幂等，防止移动端 touch+mouse 双触发）
---@param state table
---@param on boolean
function M.set_on(state, on)
    local r = state.flow.radio
    if not r then return end
    if r.on == on then return end   -- 同值跳过，防双触发
    r.on = on
    if r.on then
        -- 刚开启，重置定时器，短延迟后播第一条
        r.elapsed = 0
        r.next_at = M.FIRST_DELAY
        r.current = nil
    else
        r.current = nil
    end
end

--- 切换频道
---@param state table
---@param channel string "mingsha"|"settlement"|"mystery"
function M.switch_channel(state, channel)
    local r = state.flow.radio
    if not r then return end
    if r.channel == channel then return end

    r.channel = channel
    r.current = nil
    r.elapsed = 0
    r.next_at = 2  -- 切台后 2s 播新内容

    -- 立即尝试播一条
    -- （不在这里做，让 update 在 2s 后自动播）
end

--- 领取当前播报的奖励
---@param state table
---@return table|nil reward 领取的奖励信息
function M.claim_reward(state)
    local r = state.flow.radio
    if not r or not r.current then return nil end
    local cur = r.current
    if not cur.reward or cur.reward_claimed then return nil end

    cur.reward_claimed = true
    local reward = cur.reward

    -- 应用奖励
    if reward.type == "credits" then
        state.economy.credits = state.economy.credits + (reward.value or 0)
    elseif reward.type == "flag" then
        if reward.value then
            Flags.set(state, reward.value)
        end
    elseif reward.type == "info" then
        -- 情报类：目前仅做提示，不改变数值
    end

    return reward
end

--- 收音机是否开启
---@param state table
---@return boolean
function M.is_on(state)
    local r = state.flow.radio
    return r and r.on or false
end

--- 获取当前频道
---@param state table
---@return string
function M.get_channel(state)
    local r = state.flow.radio
    return r and r.channel or "mingsha"
end

-- ============================================================
-- 内部：加权随机抽取
-- ============================================================

function M._pick(state, channel)
    local all = _load_broadcasts()
    local pool = all[channel]
    if not pool or #pool == 0 then return nil end

    local r = state.flow.radio
    local candidates = {}

    for _, b in ipairs(pool) do
        -- 去重：本趟已播放过的跳过（池子不大时允许重复）
        if not r.shown_ids[b.id] then
            table.insert(candidates, b)
        end
    end

    -- 如果全部播完了，重置（允许重复）
    if #candidates == 0 then
        candidates = pool
    end

    -- 加权随机
    local tw = 0
    for _, b in ipairs(candidates) do tw = tw + (b.weight or 50) end
    local roll = math.random() * tw
    local acc = 0
    for _, b in ipairs(candidates) do
        acc = acc + (b.weight or 50)
        if roll <= acc then return b end
    end
    return candidates[#candidates]
end

return M

--- 环境系统：区域中景 + 晨夜变化 + 天气效果
--- 与 Chatter/Scenery/Radio 并列，在每次进入新 segment 时计算
--- 区域/天气/时段，驱动 driving_scene 切换视觉效果。
---
--- API:
---   Environment.init()                         -> env_state
---   Environment.on_segment_enter(env, segment)  -> 更新 env 内部状态
---   Environment.get_current(env)                -> { region, weather, timeOfDay }

local Graph = require("map/world_graph")

local M = {}

-- ============================================================
-- 节点 → 地形景观映射
-- ============================================================
-- 4 种地形：urban(城郊废墟) / wild(荒野) / canyon(峡谷) / forest(枯木林)
-- 按节点地理位置和类型分配，默认 wild
local NODE_REGION = {
    -- 城郊废墟 (urban) — 聚落、城市遗迹、工业设施
    greenhouse      = "urban",
    greenhouse_farm = "wild",    -- 外围农场偏荒野
    tower           = "urban",
    dome_outpost    = "urban",
    ruins_camp      = "urban",
    metro_camp      = "urban",
    bell_tower      = "urban",
    old_church      = "urban",
    old_warehouse   = "urban",
    old_logistics   = "urban",
    underground_market = "urban",
    printing_ruins  = "urban",
    -- 峡谷/山地 (canyon) — 危险地带、山丘、隘口
    danger_pass     = "canyon",
    radar_hill      = "canyon",
    wind_gap        = "canyon",
    crater_rim      = "canyon",
    sunken_plaza    = "canyon",
    dust_station    = "canyon",
    -- 枯木林 (forest) — 自然区域、洞穴、沼泽
    dead_forest     = "forest",
    mushroom_cave   = "forest",
    toxic_marsh     = "forest",
    mist_valley     = "forest",
    hermit_cave     = "forest",
    overgrown_bridge = "forest",
    stone_garden    = "forest",
    -- 荒野 (wild) — 开阔地带、公路、资源点（默认）
    crossroads      = "wild",
    solar_field     = "wild",
    irrigation_canal = "wild",
    junkyard        = "wild",
    scrap_yard      = "wild",
    dry_riverbed    = "wild",
    signal_relay    = "wild",
    weather_station = "wild",
    sewer_maze      = "wild",
    military_bunker = "wild",
    toll_gate       = "wild",
    broadcast_tower = "wild",
    rust_bridge     = "wild",
    signal_bunker   = "wild",
    old_archives    = "urban",
}

-- ============================================================
-- 时段循环
-- ============================================================
local TIME_CYCLE = { "dawn", "day", "dusk", "night" }

-- ============================================================
-- 天气权重表 —— 按 danger 等级加权随机
-- ============================================================
-- danger: "safe" / "normal" / "danger"（来自 edge 数据）
local WEATHER_TABLE = {
    safe   = { { "clear", 70 }, { "cloudy", 30 } },
    normal = { { "clear", 20 }, { "cloudy", 40 }, { "fog", 30 }, { "rain", 10 } },
    danger = { { "cloudy", 20 }, { "fog", 25 }, { "rain", 35 }, { "snow", 20 } },
}

--- 根据权重随机选择
---@param weighted table { { name, weight }, ... }
---@return string
local function weightedRandom(weighted)
    local total = 0
    for _, entry in ipairs(weighted) do
        total = total + entry[2]
    end
    local r = math.random(total)
    local acc = 0
    for _, entry in ipairs(weighted) do
        acc = acc + entry[2]
        if r <= acc then
            return entry[1]
        end
    end
    return weighted[#weighted][1]
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 初始化环境状态
---@return table env_state
function M.init()
    return {
        timeCounter = 0,       -- 累计 segment 计数，用于时段循环
        region      = "wild",
        weather     = "clear",
        timeOfDay   = "day",
    }
end

--- 进入新 segment 时调用
--- 推断目标节点区域、推进时段、随机天气
---@param env table env_state（由 init 返回）
---@param segment table 当前 segment（含 to, danger 等字段）
function M.on_segment_enter(env, segment)
    if not env or not segment then return end

    -- 1. 推断区域（基于目标节点）
    local targetId = segment.to
    if targetId then
        env.region = NODE_REGION[targetId] or "wild"
    end

    -- 2. 推进时段（每 segment +1，4 相位循环）
    env.timeCounter = env.timeCounter + 1
    local idx = ((env.timeCounter - 1) % #TIME_CYCLE) + 1
    env.timeOfDay = TIME_CYCLE[idx]

    -- 3. 随机天气（按 danger 等级加权）
    local danger = segment.danger or "normal"
    local weatherPool = WEATHER_TABLE[danger] or WEATHER_TABLE.normal
    env.weather = weightedRandom(weatherPool)
end

--- 获取当前环境状态的快照
---@param env table env_state
---@return table { region:string, weather:string, timeOfDay:string }
function M.get_current(env)
    if not env then
        return { region = "wild", weather = "clear", timeOfDay = "day" }
    end
    return {
        region    = env.region,
        weather   = env.weather,
        timeOfDay = env.timeOfDay,
    }
end

return M

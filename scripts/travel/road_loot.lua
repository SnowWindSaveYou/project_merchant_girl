--- 路面掉落物系统
--- 行驶中随机在路面生成可拾取的物品/货币，玩家点击收集
--- 与 Chatter/Scenery/Environment 并列的旅行子系统
---
--- API:
---   RoadLoot.init()                              -> loot_state
---   RoadLoot.on_segment_enter(state, segment)     -> 规划本段掉落
---   RoadLoot.update(state, dt)                    -> 推进计时/激活
---   RoadLoot.try_pickup(state, drop)              -> 拾取奖励
---   RoadLoot.get_active_drops(state)              -> 当前可见掉落列表

local Goods      = require("economy/goods")
local ItemUse    = require("economy/item_use")
local CargoUtils = require("economy/cargo_utils")

local M = {}

-- ============================================================
-- 掉落物类型表
-- ============================================================
-- icon: 图片路径（assets/image/ 下，引用时省略 assets/）
-- reward_type: "credits" | "cargo"
-- reward_id:   cargo 类型的 goods_id
-- reward_min/max: 奖励数量范围
-- weight: 基础权重（越高越常见）
-- danger_only: true 时仅在 danger 路段出现
local LOOT_TABLE = {
    {
        id          = "credit_chip",
        name        = "信用芯片",
        icon        = "image/loot_credit_chip_20260409034646.png",
        reward_type = "credits",
        reward_min  = 2,
        reward_max  = 6,
        weight      = 35,
    },
    {
        id          = "food_can",
        name        = "罐头食品",
        icon        = "image/loot_food_can_20260409034634.png",
        reward_type = "cargo",
        reward_id   = "food_can",
        reward_min  = 1,
        reward_max  = 1,
        weight      = 15,
    },
    {
        id          = "metal_scrap",
        name        = "废金属",
        icon        = "image/loot_metal_scrap_20260409034650.png",
        reward_type = "cargo",
        reward_id   = "metal_scrap",
        reward_min  = 1,
        reward_max  = 1,
        weight      = 20,
    },
    {
        id          = "circuit",
        name        = "电路板",
        icon        = "image/loot_circuit_20260409034640.png",
        reward_type = "cargo",
        reward_id   = "circuit",
        reward_min  = 1,
        reward_max  = 1,
        weight      = 6,
    },
    {
        id          = "old_book",
        name        = "旧书",
        icon        = "image/loot_old_book_20260409040404.png",
        reward_type = "cargo",
        reward_id   = "old_book",
        reward_min  = 1,
        reward_max  = 1,
        weight      = 8,
    },
    {
        id          = "medicine",
        name        = "医疗包",
        icon        = "image/loot_medicine_20260409034642.png",
        reward_type = "cargo",
        reward_id   = "medicine",
        reward_min  = 1,
        reward_max  = 1,
        weight      = 4,
    },
    {
        id          = "supply_crate",
        name        = "补给箱",
        icon        = "image/loot_supply_crate_20260409034705.png",
        reward_type = "credits",
        reward_min  = 8,
        reward_max  = 15,
        weight      = 3,
    },
    {
        id          = "ammo",
        name        = "弹药链",
        icon        = "image/loot_ammo_20260409034711.png",
        reward_type = "cargo",
        reward_id   = "ammo",
        reward_min  = 1,
        reward_max  = 1,
        weight      = 4,
        danger_only = true,
    },
}

-- ============================================================
-- 配置常量
-- ============================================================
local SPAWN_DELAY_MIN    = 6    -- 掉落物出现最短延迟（秒）
local SPAWN_DELAY_MAX    = 18   -- 最长延迟
local LIFETIME           = 60   -- 安全兜底（实际由 driving_scene 按屏幕位置过期）
local MAX_VISIBLE        = 1    -- 同时可见最大数量

-- 危险等级 → 每段掉落物数量
local DENSITY = {
    safe   = { 1, 2 },
    normal = { 1, 2 },
    danger = { 2, 3 },
}

-- 掉落物在路面 y 范围 (widget 比例)
local DROP_Y_MIN = 0.72
local DROP_Y_MAX = 0.86

-- 图标在路面上的绘制尺寸（像素）
M.ICON_SIZE = 32

-- 路面滚动速度（与 driving_scene 的 SCROLL_SPEED 和地面层 speed 一致）
M.SCROLL_SPEED   = 50   -- px/s
M.GROUND_SPEED   = 1.0  -- 地面层速度系数

-- ============================================================
-- 内部工具
-- ============================================================

--- 加权随机选择
---@param pool table { { entry, weight }, ... }
---@return table|nil entry
local function weightedPick(pool)
    if #pool == 0 then return nil end
    local total = 0
    for _, c in ipairs(pool) do total = total + c.weight end
    local r = math.random() * total
    local acc = 0
    for _, c in ipairs(pool) do
        acc = acc + c.weight
        if r <= acc then return c.entry end
    end
    return pool[#pool].entry
end

--- 生成掉落物初始 x 位置（左侧，将随路面向右漂移经过整个画面）
---@return number xNorm 初始归一化 x [-0.15, 0.10]
local function randomDropX()
    return -0.15 + math.random() * 0.25
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 初始化掉落物状态
---@return table loot_state
function M.init()
    return {
        queue         = {},    -- 待激活的掉落物列表（含 spawnDelay）
        active        = {},    -- 当前可见的掉落物
        picked_count  = 0,     -- 本趟已拾取数
        total_spawned = 0,     -- 本趟已生成数
    }
end

--- 进入新 segment 时规划掉落物
---@param state table 游戏全局状态（含 state.flow.road_loot）
---@param segment table 路段信息（含 danger）
function M.on_segment_enter(state, segment)
    local ls = state.flow.road_loot
    if not ls then return end

    local danger = segment and segment.danger or "normal"
    local range = DENSITY[danger] or DENSITY.normal
    local count = math.random(range[1], range[2])

    -- 构建候选池（按 danger 过滤）
    local pool = {}
    for _, loot in ipairs(LOOT_TABLE) do
        if not loot.danger_only or danger == "danger" then
            table.insert(pool, { entry = loot, weight = loot.weight })
        end
    end

    -- 生成掉落队列，每个有不同的延迟
    for i = 1, count do
        local picked = weightedPick(pool)
        if picked then
            local drop = {
                loot_id    = picked.id,
                icon       = picked.icon,
                name       = picked.name,
                reward_type = picked.reward_type,
                reward_id  = picked.reward_id,
                -- 奖励随机数量
                reward_amount = math.random(picked.reward_min, picked.reward_max),
                -- 掉落位置 (归一化)
                xNorm      = randomDropX(),
                yNorm      = DROP_Y_MIN + math.random() * (DROP_Y_MAX - DROP_Y_MIN),
                -- 延迟出现
                spawnDelay = SPAWN_DELAY_MIN + math.random() * (SPAWN_DELAY_MAX - SPAWN_DELAY_MIN)
                            + (i - 1) * 2,  -- 错开出现
                -- 状态
                lifetime   = 0,
                alive      = true,
            }
            table.insert(ls.queue, drop)
            ls.total_spawned = ls.total_spawned + 1
        end
    end

    print(string.format("[RoadLoot] Segment enter (danger=%s): queued %d drops", danger, count))
end

--- 每帧更新：推进延迟计时、管理激活/过期
---@param state table
---@param dt number
function M.update(state, dt)
    local ls = state.flow.road_loot
    if not ls then return end

    -- 1. 推进队列中的延迟计时
    local visibleCount = #ls.active
    local toRemove = {}
    for i, drop in ipairs(ls.queue) do
        drop.spawnDelay = drop.spawnDelay - dt
        if drop.spawnDelay <= 0 and visibleCount < MAX_VISIBLE then
            -- 激活
            drop.lifetime = 0
            table.insert(ls.active, drop)
            table.insert(toRemove, i)
            visibleCount = visibleCount + 1
        end
    end
    -- 移除已激活的（从后往前删）
    for j = #toRemove, 1, -1 do
        table.remove(ls.queue, toRemove[j])
    end

    -- 2. 更新已激活掉落物的生命周期，清理已过期或已死亡的
    local expired = {}
    for i, drop in ipairs(ls.active) do
        drop.lifetime = drop.lifetime + dt
        -- alive=false 由 driving_scene 在掉落物漂出屏幕时标记
        if drop.lifetime >= LIFETIME or not drop.alive then
            table.insert(expired, i)
        end
    end
    for j = #expired, 1, -1 do
        table.remove(ls.active, expired[j])
    end
end

--- 尝试拾取掉落物
---@param state table 游戏全局状态
---@param drop table 掉落物对象（来自 active 列表）
---@return table|nil feedback { name, reward_text, reward_type }
function M.try_pickup(state, drop)
    if not drop or not drop.alive then return nil end

    -- 货物类型：仓位不足时拒绝拾取（货币不受限）
    if drop.reward_type == "cargo" then
        local free = CargoUtils.get_cargo_free(state)
        if free < drop.reward_amount then
            return {
                name        = drop.name,
                reward_text = "货舱已满",
                reward_type = "blocked",
                x           = drop._renderXNorm or drop.xNorm,
                y           = drop.yNorm,
            }
        end
    end

    drop.alive = false

    -- 从 active 列表移除
    local ls = state.flow.road_loot
    if ls then
        for i, d in ipairs(ls.active) do
            if d == drop then
                table.remove(ls.active, i)
                break
            end
        end
        ls.picked_count = ls.picked_count + 1
    end

    -- 发放奖励
    local reward_text = ""
    if drop.reward_type == "credits" then
        state.economy.credits = state.economy.credits + drop.reward_amount
        reward_text = "+" .. drop.reward_amount .. " 信用点"
    elseif drop.reward_type == "cargo" then
        ItemUse.add(state, drop.reward_id, drop.reward_amount)
        local g = Goods.get(drop.reward_id)
        local gName = g and g.name or drop.reward_id
        reward_text = "+" .. drop.reward_amount .. " " .. gName
    end

    print(string.format("[RoadLoot] Picked: %s → %s", drop.name, reward_text))

    return {
        name        = drop.name,
        reward_text = reward_text,
        reward_type = drop.reward_type,
        x           = drop._renderXNorm or drop.xNorm,  -- 使用漂移后的视觉位置
        y           = drop.yNorm,
    }
end

--- 获取当前可见的掉落物列表（用于渲染）
---@param state table
---@return table[] drops
function M.get_active_drops(state)
    local ls = state.flow.road_loot
    if not ls then return {} end
    return ls.active
end

return M

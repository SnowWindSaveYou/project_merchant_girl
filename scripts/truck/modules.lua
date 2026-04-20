--- 货车模块升级系统
--- 定义 5 个模块的等级上限、升级成本和效果
local Tracker = require("analytics/tracker")

local M = {}

-- ============================================================
-- 模块定义
-- ============================================================
M.DEFS = {
    engine = {
        name     = "引擎系统",
        desc     = "提升行驶速度，降低燃耗",
        max_level = 3,
        --- 可升级的聚落
        upgrade_at = { tower = true, ruins_camp = true },
        costs = {
            [1] = { credits = 80,  materials = { circuit = 1 } },
            [2] = { credits = 160, materials = { circuit = 2 } },
            [3] = { credits = 300, materials = { circuit = 3, fuel_cell = 1 } },
        },
        effects = {
            [1] = { speed_mult = 1.10, fuel_mult = 1.0,  desc = "速度 +10%" },
            [2] = { speed_mult = 1.10, fuel_mult = 0.85, desc = "速度 +10%, 燃耗 -15%" },
            [3] = { speed_mult = 1.20, fuel_mult = 0.85, desc = "速度 +20%, 燃耗 -15%" },
        },
    },
    cargo_bay = {
        name     = "货仓升级",
        desc     = "扩容货仓并改善内部环境",
        max_level = 3,
        upgrade_at = { greenhouse = true, ruins_camp = true },
        costs = {
            [1] = { credits = 100, materials = { metal_scrap = 3 } },
            [2] = { credits = 200, materials = { metal_scrap = 5 } },
            [3] = { credits = 350, materials = { metal_scrap = 8, circuit = 1 } },
        },
        effects = {
            [1] = { cargo_slots = 14, truck_image = "image/edited_truck_home_mid_20260420100832.png",  desc = "仓位 → 14, 内饰改善" },
            [2] = { cargo_slots = 18, truck_image = "image/truck_home_clean.png",                      desc = "仓位 → 18, 内饰翻新" },
            [3] = { cargo_slots = 22, truck_image = "image/truck_home_clean.png",                      desc = "仓位 → 22" },
        },
    },
    radar = {
        name     = "探测雷达",
        desc     = "获取更多市场与敌情信息",
        max_level = 3,
        upgrade_at = { tower = true, bell_tower = true },
        costs = {
            [1] = { credits = 120, materials = { circuit = 2 } },
            [2] = { credits = 240, materials = { circuit = 3 } },
            [3] = { credits = 400, materials = { circuit = 5, metal_scrap = 2 } },
        },
        effects = {
            [1] = { hidden_bonus = 0.15, desc = "隐藏点发现 +15%" },
            [2] = { price_visible = true, desc = "可查看各聚落供需" },
            [3] = { enemy_warning = true, desc = "遇袭预警提示" },
        },
    },
    cold_storage = {
        name     = "冷藏货柜",
        desc     = "保存食品鲜度，解锁高价订单",
        max_level = 2,
        upgrade_at = { greenhouse = true },
        costs = {
            [1] = { credits = 150, materials = { metal_scrap = 3, circuit = 1 } },
            [2] = { credits = 300, materials = { metal_scrap = 5, circuit = 2 } },
        },
        effects = {
            [1] = { fresh_preserve = true, desc = "生鲜不腐坏" },
            [2] = { premium_food_orders = true, desc = "可接高价食品单" },
        },
    },
    turret = {
        name     = "车顶机枪",
        desc     = "提升战斗火力和保全率",
        max_level = 3,
        upgrade_at = { tower = true, ruins_camp = true },
        costs = {
            [1] = { credits = 100, materials = { ammo = 2, metal_scrap = 2 } },
            [2] = { credits = 200, materials = { ammo = 3, metal_scrap = 3 } },
            [3] = { credits = 350, materials = { ammo = 5, metal_scrap = 5, circuit = 1 } },
        },
        effects = {
            [1] = { firepower_mult = 1.0,  repel_bonus = 0,    desc = "基础火力" },
            [2] = { firepower_mult = 1.3,  repel_bonus = 0.30, desc = "火力 +30%, 驱逐 +30%" },
            [3] = { firepower_mult = 1.5,  repel_bonus = 0.50, desc = "火力 +50%, 保全 +50%" },
        },
    },
}

-- 模块 ID 顺序（用于 UI 迭代）
M.ORDER = { "engine", "cargo_bay", "radar", "cold_storage", "turret" }

--- 获取当前模块等级
---@param state table
---@param module_id string
---@return number
function M.get_level(state, module_id)
    return state.truck.modules[module_id] or 0
end

--- 获取模块效果（当前等级）
---@param state table
---@param module_id string
---@return table|nil effects
function M.get_effects(state, module_id)
    local lv = M.get_level(state, module_id)
    if lv <= 0 then return nil end
    local def = M.DEFS[module_id]
    return def and def.effects[lv]
end

--- 检查是否可以在当前聚落升级
---@param state table
---@param module_id string
---@return boolean can_upgrade
---@return string|nil reason 失败原因
function M.can_upgrade(state, module_id)
    local def = M.DEFS[module_id]
    if not def then return false, "未知模块" end

    local cur_lv = M.get_level(state, module_id)
    if cur_lv >= def.max_level then return false, "已满级" end

    -- 聚落限制
    local loc = state.map.current_location
    if not def.upgrade_at[loc] then
        -- 找出可升级的聚落名
        local names = {}
        for sid, _ in pairs(def.upgrade_at) do
            table.insert(names, sid)
        end
        return false, "仅在 " .. table.concat(names, "/") .. " 可升级"
    end

    -- 成本检查
    local next_lv = cur_lv + 1
    local cost = def.costs[next_lv]
    if not cost then return false, "无升级数据" end

    if state.economy.credits < cost.credits then
        return false, "信用点不足（需 " .. cost.credits .. "）"
    end

    for mat_id, need in pairs(cost.materials) do
        local have = state.truck.cargo[mat_id] or 0
        if have < need then
            return false, mat_id .. " 不足（需 " .. need .. "）"
        end
    end

    return true
end

--- 执行升级
---@param state table
---@param module_id string
---@return boolean success
---@return string|nil error
function M.upgrade(state, module_id)
    local ok, reason = M.can_upgrade(state, module_id)
    if not ok then return false, reason end

    local def = M.DEFS[module_id]
    local cur_lv = M.get_level(state, module_id)
    local next_lv = cur_lv + 1
    local cost = def.costs[next_lv]

    -- 扣除信用点
    state.economy.credits = state.economy.credits - cost.credits

    -- 扣除材料
    for mat_id, need in pairs(cost.materials) do
        state.truck.cargo[mat_id] = (state.truck.cargo[mat_id] or 0) - need
        if state.truck.cargo[mat_id] <= 0 then
            state.truck.cargo[mat_id] = nil
        end
    end

    -- 提升等级
    state.truck.modules[module_id] = next_lv

    -- 埋点
    Tracker.milestone(state, "first_upgrade")
    Tracker.count(state, "modules_upgraded")

    -- cargo_bay 立即生效：更新仓位上限
    if module_id == "cargo_bay" then
        local eff = def.effects[next_lv]
        if eff and eff.cargo_slots then
            state.truck.cargo_slots = eff.cargo_slots
        end
    end

    return true
end

-- ============================================================
-- 便捷查询：各系统使用
-- ============================================================

--- 行驶速度倍率（engine 模块）
function M.get_speed_mult(state)
    local eff = M.get_effects(state, "engine")
    return eff and eff.speed_mult or 1.0
end

--- 燃料消耗倍率（engine 模块）
function M.get_fuel_mult(state)
    local eff = M.get_effects(state, "engine")
    return eff and eff.fuel_mult or 1.0
end

--- 火力倍率（turret 模块）
function M.get_firepower_mult(state)
    local eff = M.get_effects(state, "turret")
    return eff and eff.firepower_mult or 1.0
end

--- 驱逐加成（turret 模块）
function M.get_repel_bonus(state)
    local eff = M.get_effects(state, "turret")
    return eff and eff.repel_bonus or 0
end

--- 隐藏点发现加成（radar 模块）
function M.get_hidden_bonus(state)
    local eff = M.get_effects(state, "radar")
    return eff and eff.hidden_bonus or 0
end

--- 是否可查看价格（radar Lv2+）
function M.can_see_prices(state)
    local eff = M.get_effects(state, "radar")
    return eff and eff.price_visible or false
end

--- 是否有敌情预警（radar Lv3）
function M.has_enemy_warning(state)
    local eff = M.get_effects(state, "radar")
    return eff and eff.enemy_warning or false
end

return M

--- 聚落好感等级系统
--- 好感值 → 等级 → 折扣 / 功能解锁
local M = {}

-- ============================================================
-- 等级阈值
-- ============================================================
M.LEVELS = {
    { threshold =  0, name = "陌生",   discount = 0    },  -- Lv0
    { threshold = 30, name = "熟悉",   discount = 0.05 },  -- Lv1: 5% 折扣
    { threshold = 60, name = "信任",   discount = 0.10 },  -- Lv2: 10% 折扣
    { threshold = 90, name = "盟友",   discount = 0.15 },  -- Lv3: 15% 折扣
}

--- 获取好感等级 (0~3)
---@param goodwill number
---@return number level
function M.get_level(goodwill)
    local lv = 0
    for i, def in ipairs(M.LEVELS) do
        if goodwill >= def.threshold then
            lv = i - 1
        end
    end
    return lv
end

--- 获取等级信息
---@param goodwill number
---@return table { level, name, discount, next_threshold }
function M.get_info(goodwill)
    local lv = M.get_level(goodwill)
    local def = M.LEVELS[lv + 1]
    local next_def = M.LEVELS[lv + 2]
    return {
        level     = lv,
        name      = def.name,
        discount  = def.discount,
        next_threshold = next_def and next_def.threshold or nil,
    }
end

--- 获取价格折扣倍率（买入价乘以此值）
--- 好感越高，买入越便宜
---@param goodwill number
---@return number multiplier (0.85 ~ 1.0)
function M.get_buy_discount(goodwill)
    local info = M.get_info(goodwill)
    return 1.0 - info.discount
end

--- 获取卖出加成倍率
--- 好感越高，卖出越贵
---@param goodwill number
---@return number multiplier (1.0 ~ 1.10)
function M.get_sell_bonus(goodwill)
    local info = M.get_info(goodwill)
    return 1.0 + info.discount * 0.67  -- 卖出加成约为买入折扣的 2/3
end

--- 聚落功能解锁检查
---@param goodwill number
---@param feature string "specialty_goods"|"rest_area"|"emergency_call"
---@return boolean
function M.is_unlocked(goodwill, feature)
    local lv = M.get_level(goodwill)
    if feature == "specialty_goods" then return lv >= 1 end
    if feature == "rest_area"       then return lv >= 2 end
    if feature == "emergency_call"  then return lv >= 3 end
    return false
end

-- ============================================================
-- 势力好感溢出
-- ============================================================
local Factions -- 延迟加载，避免循环依赖

--- 好感变动后调用：同势力其他聚落获得 50% 溢出
---@param state table
---@param settlement_id string  发生好感变动的聚落
---@param delta number          原始变动量（正或负）
function M.apply_faction_spillover(state, settlement_id, delta)
    if delta == 0 then return end
    if not Factions then
        Factions = require("settlement/factions")
    end
    local siblings = Factions.get_siblings(settlement_id)
    local spill = math.floor(delta * 0.5 + 0.5)
    if spill == 0 then return end
    for _, sid in ipairs(siblings) do
        local sett = state.settlements[sid]
        if sett then
            sett.goodwill = (sett.goodwill or 0) + spill
        end
    end
end

return M

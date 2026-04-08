--- 四层定价系统
--- 基础价 × 聚落类目修正 × 好感折扣 × 供需修正 = 最终价格
--- demoralized 状态会恶化交易价格
local Goods    = require("economy/goods")
local ItemUse  = require("economy/item_use")
local Goodwill = require("settlement/goodwill")
local Skills   = require("character/skills")
local Intel    = require("settlement/intel")

local M = {}

--- 检查士气低落（任一角色）
---@param state table|nil
---@return boolean
local function is_demoralized(state)
    if not state then return false end
    return ItemUse.has_status(state, "linli", "demoralized")
        or ItemUse.has_status(state, "taoxia", "demoralized")
end

--- 聚落类目修正系数 { buy = 买入乘数, sell = 卖出乘数 }
--- buy  = 玩家买入时的价格乘数（越低越便宜，产地低）
--- sell = 玩家卖出时的价格乘数（越高越赚钱，需求地高）
--- ⚠️ 同一聚落内，sell 必须严格 < buy（商人赚差价），防止原地套利
--- 跨聚落利润来自：A 地低 buy 买入 → B 地高 sell 卖出
M.MODIFIERS = {
    greenhouse = {
        survival   = { buy = 0.8, sell = 0.6 },   -- 产地：买入便宜，卖出更低
        industrial = { buy = 1.4, sell = 1.2 },   -- 需求：买入贵，卖出稍低
        cultural   = { buy = 1.0, sell = 0.8 },   -- 中性
        military   = { buy = 1.2, sell = 1.0 },   -- 略需
    },
    tower = {
        survival   = { buy = 1.3, sell = 1.1 },   -- 需求
        industrial = { buy = 0.8, sell = 0.6 },   -- 产地
        cultural   = { buy = 1.1, sell = 0.9 },   -- 略需
        military   = { buy = 1.0, sell = 0.8 },   -- 中性
    },
    ruins_camp = {
        survival   = { buy = 1.2, sell = 1.0 },   -- 略需
        industrial = { buy = 1.2, sell = 1.0 },   -- 略需
        cultural   = { buy = 0.7, sell = 0.5 },   -- 产地
        military   = { buy = 0.9, sell = 0.7 },   -- 产地偏低
    },
    bell_tower = {
        survival   = { buy = 1.1, sell = 0.9 },   -- 略需
        industrial = { buy = 1.0, sell = 0.8 },   -- 中性
        cultural   = { buy = 0.7, sell = 0.5 },   -- 产地（书院藏书多）
        military   = { buy = 1.4, sell = 1.2 },   -- 需求（防御薄弱）
    },
    -- ===== 前哨站（继承首都倾向，略有偏差） =====
    greenhouse_farm = {
        survival   = { buy = 0.75, sell = 0.55 },  -- 产地偏低（农场更强）
        industrial = { buy = 1.5,  sell = 1.3 },   -- 需求偏高
        cultural   = { buy = 1.1,  sell = 0.9 },   -- 略需
        military   = { buy = 1.1,  sell = 0.9 },   -- 略需
    },
    dome_outpost = {
        survival   = { buy = 1.2, sell = 1.0 },    -- 需求
        industrial = { buy = 0.85, sell = 0.65 },   -- 产地（技术相关）
        cultural   = { buy = 1.2,  sell = 1.0 },   -- 略需
        military   = { buy = 0.9,  sell = 0.7 },   -- 中性偏低
    },
    metro_camp = {
        survival   = { buy = 1.3, sell = 1.1 },    -- 需求（隧道缺食物）
        industrial = { buy = 1.0, sell = 0.8 },    -- 中性
        cultural   = { buy = 0.8, sell = 0.6 },    -- 产地偏低（回收旧物）
        military   = { buy = 0.85, sell = 0.65 },   -- 产地（拆解弹药）
    },
    old_church = {
        survival   = { buy = 1.2, sell = 1.0 },    -- 略需
        industrial = { buy = 1.1, sell = 0.9 },    -- 略需
        cultural   = { buy = 0.75, sell = 0.55 },   -- 产地（藏经阁）
        military   = { buy = 1.3,  sell = 1.1 },   -- 需求（防御薄弱）
    },
}

--- 获取供需修正系数
---@param state table|nil
---@param settlement_id string
---@param goods_id string
---@return number 正值=涨价, 负值=降价
local function get_supply_demand_mod(state, settlement_id, goods_id)
    if not state then return 0 end
    local sett = state.settlements[settlement_id]
    if not sett or not sett.supply_demand then return 0 end
    local sd = sett.supply_demand[goods_id] or 0
    -- sd 正=供过于求(降价), 负=供不应求(涨价)
    return -sd / 100
end

--- 玩家在该聚落 **买入** 某商品需要支付的价格
--- @param goods_id string
--- @param settlement_id string
--- @param state table|nil  传入 state 时应用好感折扣/供需/demoralized
function M.get_buy_price(goods_id, settlement_id, state)
    local g = Goods.get(goods_id)
    if not g then return 0 end
    local mods = M.MODIFIERS[settlement_id]
    local cat_mod = mods and mods[g.category]
    local modifier = cat_mod and cat_mod.buy or 1.0
    -- 好感折扣（买入更便宜）
    if state then
        local sett = state.settlements[settlement_id]
        if sett then
            modifier = modifier * Goodwill.get_buy_discount(sett.goodwill or 0)
        end
    end
    -- 供需修正
    local sd_mod = get_supply_demand_mod(state, settlement_id, goods_id)
    modifier = modifier * (1 + sd_mod)
    -- demoralized：买入价格 +5%（砍价能力下降）
    if is_demoralized(state) then modifier = modifier * 1.05 end
    -- 技能：临场砍价 + 心有灵犀（买入更便宜）
    if state then
        local skill_disc = Skills.get_buy_discount(state)
        if skill_disc > 0 then modifier = modifier * (1 - skill_disc) end
    end
    -- 价格情报：掌握该聚落物价趋势，买入价 -8%
    if state then
        local price_intels = Intel.get_active_of_type(state, "price")
        for _, info in ipairs(price_intels) do
            if info.target_settlement == settlement_id then
                modifier = modifier * 0.92
                break
            end
        end
    end
    return math.max(1, math.floor(g.base_price * modifier + 0.5))
end

--- 玩家在该聚落 **卖出** 某商品能获得的收入
--- @param goods_id string
--- @param settlement_id string
--- @param state table|nil  传入 state 时应用好感加成/供需/demoralized
function M.get_sell_price(goods_id, settlement_id, state)
    local g = Goods.get(goods_id)
    if not g then return 0 end
    local mods = M.MODIFIERS[settlement_id]
    local cat_mod = mods and mods[g.category]
    local modifier = cat_mod and cat_mod.sell or 1.0
    -- 好感加成（卖出更贵）
    if state then
        local sett = state.settlements[settlement_id]
        if sett then
            modifier = modifier * Goodwill.get_sell_bonus(sett.goodwill or 0)
        end
    end
    -- 供需修正
    local sd_mod = get_supply_demand_mod(state, settlement_id, goods_id)
    modifier = modifier * (1 + sd_mod)
    -- demoralized：卖出价格 -5%（谈判能力下降）
    if is_demoralized(state) then modifier = modifier * 0.95 end
    -- 技能：临场砍价 + 心有灵犀（卖出更贵）
    if state then
        local skill_bonus = Skills.get_sell_bonus(state)
        if skill_bonus > 0 then modifier = modifier * (1 + skill_bonus) end
    end
    -- 价格情报：掌握该聚落物价趋势，卖出价 +8%
    if state then
        local price_intels = Intel.get_active_of_type(state, "price")
        for _, info in ipairs(price_intels) do
            if info.target_settlement == settlement_id then
                modifier = modifier * 1.08
                break
            end
        end
    end
    return math.max(1, math.floor(g.base_price * modifier + 0.5))
end

--- 交易后更新供需值
---@param state table
---@param settlement_id string
---@param goods_id string
---@param delta number  正=玩家卖出(供给增加), 负=玩家买入(需求增加)
function M.update_supply_demand(state, settlement_id, goods_id, delta)
    local sett = state.settlements[settlement_id]
    if not sett then return end
    if not sett.supply_demand then sett.supply_demand = {} end
    local cur = sett.supply_demand[goods_id] or 0
    if delta > 0 then
        -- 玩家卖出：供给增加
        sett.supply_demand[goods_id] = cur + delta * 5
    else
        -- 玩家买入：需求增加
        sett.supply_demand[goods_id] = cur + delta * 3
    end
end

--- 供需衰减（每趟行程调用一次）
---@param state table
function M.decay_supply_demand(state)
    for _, sett in pairs(state.settlements) do
        if sett.supply_demand then
            for gid, val in pairs(sett.supply_demand) do
                -- 向 0 衰减 10%
                sett.supply_demand[gid] = math.floor(val * 0.9 + 0.5)
                if math.abs(sett.supply_demand[gid]) < 1 then
                    sett.supply_demand[gid] = nil
                end
            end
        end
    end
end

--- 获取供需标签（UI 显示用）
---@param state table
---@param settlement_id string
---@param goods_id string
---@return string|nil label, table|nil color
function M.get_supply_demand_label(state, settlement_id, goods_id)
    if not state then return nil end
    local sett = state.settlements[settlement_id]
    if not sett or not sett.supply_demand then return nil end
    local sd = sett.supply_demand[goods_id] or 0
    if sd <= -20 then
        return "紧缺", { 220, 80, 80, 255 }
    elseif sd <= -10 then
        return "需求", { 218, 165, 82, 255 }
    elseif sd >= 20 then
        return "过剩", { 100, 160, 100, 255 }
    elseif sd >= 10 then
        return "充足", { 140, 180, 140, 255 }
    end
    return nil
end

return M

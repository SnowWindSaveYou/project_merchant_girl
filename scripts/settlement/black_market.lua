--- 废墟营地·黑市淘货 & 砍价博弈
--- 到达营地时刷新随机商品 → 3 回合砍价 → 品质随机
--- 数据存储在 state.settlements.ruins_camp.market
local Goods    = require("economy/goods")
local Goodwill = require("settlement/goodwill")

local M = {}

-- 商品池：每件商品有基础 ID、可能的品质范围
M.ITEM_POOL = {
    { goods_id = "circuit",     label = "来路不明的电路板", quality_range = { 0.6, 1.3 } },
    { goods_id = "fuel_cell",   label = "旧燃料芯",       quality_range = { 0.7, 1.2 } },
    { goods_id = "medicine",    label = "不知名药剂",      quality_range = { 0.5, 1.4 } },
    { goods_id = "metal_scrap", label = "废铁堆里翻到的零件", quality_range = { 0.8, 1.1 } },
    { goods_id = "ammo",        label = "锈迹斑斑的弹药",  quality_range = { 0.6, 1.2 } },
    { goods_id = "old_book",    label = "封面掉了的旧书",  quality_range = { 0.5, 1.5 } },
    { goods_id = "music_disc",  label = "划痕唱片",        quality_range = { 0.4, 1.6 } },
    { goods_id = "smoke_bomb",  label = "自制烟雾弹",      quality_range = { 0.7, 1.1 } },
    { goods_id = "water",       label = "密封水壶",        quality_range = { 0.8, 1.0 } },
    { goods_id = "food_can",    label = "没有标签的罐头",  quality_range = { 0.6, 1.3 } },
}

--- 确保黑市状态存在
---@param state table
local function _ensure(state)
    local sett = state.settlements.ruins_camp
    if not sett then
        state.settlements.ruins_camp = { goodwill = 0, visited = false, reputation = 100 }
        sett = state.settlements.ruins_camp
    end
    if not sett.market then
        sett.market = {
            items         = {},   -- 当前货架
            last_refresh  = -1,   -- 上次刷新时的 total_trips
            total_trades  = 0,
            total_profit  = 0,    -- 累计省钱（差值）
        }
    end
    return sett.market
end

--- 刷新黑市货架（到达时调用）
---@param state table
function M.refresh(state)
    local market = _ensure(state)
    local trips  = state.stats.total_trips or 0
    if market.last_refresh == trips then return end -- 同趟不重复刷新
    market.last_refresh = trips

    local sett = state.settlements.ruins_camp
    local gw   = sett and sett.goodwill or 0

    -- 3~5 件商品
    local count = math.random(3, 5)
    local items = {}
    local pool  = {}
    for i, v in ipairs(M.ITEM_POOL) do pool[i] = v end

    for _ = 1, count do
        if #pool == 0 then break end
        local idx  = math.random(1, #pool)
        local def  = pool[idx]
        table.remove(pool, idx)

        local goods = Goods.get(def.goods_id)
        local basePrice = goods and goods.base_price or 20

        -- 品质：好感越高劣质概率越低
        local qMin = def.quality_range[1]
        local qMax = def.quality_range[2]
        -- 好感提高下限
        local gwBonus = math.min(0.3, gw * 0.003)
        qMin = math.min(qMax, qMin + gwBonus)
        local quality = qMin + math.random() * (qMax - qMin)

        -- 实际价值 = 基础价 * 品质
        local realValue = math.floor(basePrice * quality + 0.5)
        -- 卖家初始报价 = 实际价值 * 130-180%（好感越高越实在）
        local markup = 1.3 + math.random() * 0.5
        markup = markup - gw * 0.003 -- 好感降低溢价
        markup = math.max(1.1, markup)
        local askPrice = math.floor(realValue * markup + 0.5)

        table.insert(items, {
            goods_id   = def.goods_id,
            label      = def.label,
            quality    = quality,
            real_value = realValue,
            ask_price  = askPrice,
            sold       = false,
        })
    end
    market.items = items
end

--- 获取当前货架
---@param state table
---@return table[]
function M.get_items(state)
    local market = _ensure(state)
    return market.items
end

--- 砍价：玩家出价
--- 返回卖家回应
---@param state table
---@param item_index number 1-based
---@param offer number 玩家出价
---@return string result  "accept"|"counter"|"angry"|"walk_away"
---@return number|nil counter_price  卖家还价（仅 counter 时有值）
---@return number|nil anger_delta    好感变化
function M.haggle(state, item_index, offer)
    local market = _ensure(state)
    local item = market.items[item_index]
    if not item or item.sold then return "walk_away" end

    local realValue = item.real_value
    local askPrice  = item.ask_price

    -- 玩家出价 >= 报价：直接成交
    if offer >= askPrice then
        return "accept"
    end

    -- 出价太低（< 实际价值的 70%）：卖家生气
    if offer < realValue * 0.7 then
        return "angry", nil, -2
    end

    -- 合理范围内（70%-100% 实际价值）：卖家还价
    local counterPrice = math.floor((offer + askPrice) * 0.5 + 0.5)
    counterPrice = math.max(realValue, counterPrice)  -- 不低于实际价值
    return "counter", counterPrice
end

--- 成交
---@param state table
---@param item_index number
---@param final_price number
---@return boolean success
---@return table|nil result { goods_id, label, quality, price }
function M.buy(state, item_index, final_price)
    local market = _ensure(state)
    local item = market.items[item_index]
    if not item or item.sold then return false end

    -- 扣钱
    if state.economy.credits < final_price then
        return false
    end
    state.economy.credits = state.economy.credits - final_price
    item.sold = true

    -- 给货
    state.truck.cargo[item.goods_id] = (state.truck.cargo[item.goods_id] or 0) + 1

    -- 统计
    market.total_trades = market.total_trades + 1
    local saved = item.ask_price - final_price
    market.total_profit = market.total_profit + saved

    return true, {
        goods_id = item.goods_id,
        label    = item.label,
        quality  = item.quality,
        price    = final_price,
    }
end

--- 获取统计
---@param state table
---@return number trades, number saved
function M.get_stats(state)
    local market = _ensure(state)
    return market.total_trades, market.total_profit
end

return M

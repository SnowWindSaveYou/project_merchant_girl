--- 三层定价系统
--- 基础价 × 聚落类目修正 = 最终价格
local Goods = require("economy/goods")

local M = {}

--- 聚落类目修正系数 { buy = 买入乘数, sell = 卖出乘数 }
--- buy < 1 表示该聚落产出此类商品，买入便宜
--- sell > 1 表示该聚落需求此类商品，卖出赚钱
M.MODIFIERS = {
    greenhouse = {
        survival   = { buy = 0.7, sell = 0.8 },
        industrial = { buy = 1.3, sell = 1.4 },
        cultural   = { buy = 1.0, sell = 1.0 },
        military   = { buy = 1.2, sell = 1.1 },
    },
    tower = {
        survival   = { buy = 1.3, sell = 1.3 },
        industrial = { buy = 0.7, sell = 0.8 },
        cultural   = { buy = 1.1, sell = 1.5 },
        military   = { buy = 1.0, sell = 1.0 },
    },
    ruins_camp = {
        survival   = { buy = 1.1, sell = 1.2 },
        industrial = { buy = 1.2, sell = 1.1 },
        cultural   = { buy = 0.6, sell = 0.5 },
        military   = { buy = 0.8, sell = 0.9 },
    },
    bell_tower = {
        survival   = { buy = 1.2, sell = 1.2 },
        industrial = { buy = 1.1, sell = 1.0 },
        cultural   = { buy = 0.6, sell = 0.7 },
        military   = { buy = 1.3, sell = 1.4 },
    },
}

--- 玩家在该聚落 **买入** 某商品需要支付的价格
function M.get_buy_price(goods_id, settlement_id)
    local g = Goods.get(goods_id)
    if not g then return 0 end
    local mods = M.MODIFIERS[settlement_id]
    local cat_mod = mods and mods[g.category]
    local modifier = cat_mod and cat_mod.buy or 1.0
    return math.floor(g.base_price * modifier + 0.5)
end

--- 玩家在该聚落 **卖出** 某商品能获得的收入
function M.get_sell_price(goods_id, settlement_id)
    local g = Goods.get(goods_id)
    if not g then return 0 end
    local mods = M.MODIFIERS[settlement_id]
    local cat_mod = mods and mods[g.category]
    local modifier = cat_mod and cat_mod.sell or 1.0
    return math.floor(g.base_price * modifier + 0.5)
end

return M

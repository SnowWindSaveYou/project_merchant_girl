--- 订单生成器
--- 根据当前聚落和路线生成可接取的运输订单
local Goods = require("economy/goods")
local Pricing = require("economy/pricing")

local M = {}

--- 各聚落擅长出产的商品
local SETTLEMENT_GOODS = {
    greenhouse = { "food_can", "water", "medicine" },
    tower      = { "circuit", "fuel_cell", "metal_scrap" },
    ruins_camp = { "metal_scrap", "ammo", "smoke_bomb" },
    bell_tower = { "old_book", "music_disc" },
}

--- 为当前位置的所有路线生成订单列表
---@param state table
---@param routes table[] 从 Travel.get_available_routes 获取
---@return table[] orders
function M.generate(state, routes)
    local location = state.map.current_location
    local pool = SETTLEMENT_GOODS[location] or { "food_can" }
    local orders = {}
    local seq = 0

    for _, route in ipairs(routes) do
        -- 每条路线至少 1 个稳定订单
        seq = seq + 1
        local g_id = pool[math.random(1, #pool)]
        local g = Goods.get(g_id)
        local count = math.random(2, math.min(5, g.stack_limit))
        local buy_total = Pricing.get_buy_price(g_id, route.from) * count
        local sell_total = Pricing.get_sell_price(g_id, route.to) * count
        local reward = math.max(20, math.floor((sell_total - buy_total) * 0.8 + 30))

        table.insert(orders, {
            order_id   = "ord_" .. seq .. "_" .. os.time(),
            route_id   = route.route_id,
            from       = route.from,
            to         = route.to,
            from_name  = route.from_name,
            to_name    = route.to_name,
            goods_id   = g_id,
            goods_name = g.name,
            count      = count,
            reward     = reward,
            risk       = route.danger_level,
            description = "运送" .. g.name .. " ×" .. count .. " 到" .. route.to_name,
        })

        -- 50% 概率追加一个高利润大单
        if math.random() > 0.5 then
            seq = seq + 1
            local g2_id = pool[math.random(1, #pool)]
            local g2 = Goods.get(g2_id)
            local c2 = math.random(4, math.min(8, g2.stack_limit))
            local r2 = math.floor(reward * 1.4 + math.random(10, 25))

            table.insert(orders, {
                order_id   = "ord_" .. seq .. "_" .. os.time(),
                route_id   = route.route_id,
                from       = route.from,
                to         = route.to,
                from_name  = route.from_name,
                to_name    = route.to_name,
                goods_id   = g2_id,
                goods_name = g2.name,
                count      = c2,
                reward     = r2,
                risk       = route.danger_level,
                description = "大批运送" .. g2.name .. " ×" .. c2 .. " 到" .. route.to_name,
            })
        end
    end

    return orders
end

return M

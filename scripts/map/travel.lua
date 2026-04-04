--- 路线与行驶数据
--- Phase 01 只做 greenhouse ↔ tower 两条路线
local M = {}

--- 聚落名称映射
M.SETTLEMENT_NAMES = {
    greenhouse = "温室社区",
    tower      = "北穹塔台",
    ruins_camp = "废墟游民营地",
    bell_tower = "钟楼书院",
}

--- 初始路线数据（Phase 01 硬编码）
local INITIAL_ROUTES = {
    {
        route_id       = "route_greenhouse_tower",
        from           = "greenhouse",
        to             = "tower",
        from_name      = "温室社区",
        to_name        = "北穹塔台",
        distance       = 100,
        danger_level   = "low",
        travel_time_sec = 60, -- Phase 01 测试用 60 秒
    },
    {
        route_id       = "route_tower_greenhouse",
        from           = "tower",
        to             = "greenhouse",
        from_name      = "北穹塔台",
        to_name        = "温室社区",
        distance       = 100,
        danger_level   = "low",
        travel_time_sec = 60,
    },
}

--- 获取当前位置可用的路线
function M.get_available_routes(state)
    local routes = {}
    local location = state.map.current_location
    for _, route in ipairs(INITIAL_ROUTES) do
        if route.from == location then
            table.insert(routes, route)
        end
    end
    return routes
end

--- 根据 route_id 获取路线
function M.get_route(route_id)
    for _, route in ipairs(INITIAL_ROUTES) do
        if route.route_id == route_id then
            return route
        end
    end
    return nil
end

--- 为当前位置生成可接取的订单
function M.generate_orders(state)
    local routes = M.get_available_routes(state)
    local orders = {}
    for i, route in ipairs(routes) do
        table.insert(orders, {
            order_id    = "order_" .. i .. "_" .. os.time(),
            route_id    = route.route_id,
            from        = route.from,
            to          = route.to,
            from_name   = route.from_name,
            to_name     = route.to_name,
            cargo       = { food_can = 2 },
            reward      = 50 + math.random(0, 30),
            description = "运送物资到" .. route.to_name,
        })
    end
    return orders
end

function M.get_settlement_name(id)
    return M.SETTLEMENT_NAMES[id] or id
end

return M

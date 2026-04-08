--- 北穹塔台·情报交换站
--- 跑商自动收集路况 → 到达塔台兑换天气/价格/安全情报
--- 数据存储在 state.settlements.tower.intel
local Goodwill = require("settlement/goodwill")

local M = {}

-- ============================================================
-- 情报类型定义
-- ============================================================
M.INTEL_TYPES = {
    weather  = { name = "天气预报", desc = "下趟旅途的天气状况",       cost = 1, duration = 1 },
    price    = { name = "价格情报", desc = "目标聚落的当前物价趋势",   cost = 2, duration = 1 },
    security = { name = "安全预警", desc = "哪条路有掠夺者活动",       cost = 2, duration = 2 },
    tip      = { name = "商机情报", desc = "某聚落紧急需求某种商品",   cost = 3, duration = 1 },
    location = { name = "位置情报", desc = "获取隐藏地点的坐标",       cost = 5, duration = 0, unlock = true },
}

--- 确保情报系统状态存在
---@param state table
local function _ensure(state)
    local sett = state.settlements.tower
    if not sett then
        state.settlements.tower = { goodwill = 0, visited = false, reputation = 100 }
        sett = state.settlements.tower
    end
    if not sett.intel then
        sett.intel = {
            route_data     = 0,     -- 累积路况数据点数
            active_intel   = {},    -- { { type, desc_text, trips_left } }
            total_exchanged = 0,    -- 累计交换次数
        }
    end
    return sett.intel
end

--- 每次行程结束自动收集路况数据
--- 走过的路线段越多越偏僻，数据越多
---@param state table
---@param segments_count number  本次行程路线段数
---@param had_shortcut boolean 是否走了捷径
function M.earn_route_data(state, segments_count, had_shortcut)
    local intel = _ensure(state)
    local base = math.max(1, segments_count)
    if had_shortcut then base = base + 1 end
    intel.route_data = intel.route_data + base
end

--- 获取当前可用数据点
---@param state table
---@return number
function M.get_route_data(state)
    local intel = _ensure(state)
    return intel.route_data
end

--- 获取可交换的情报类型列表（根据好感等级）
---@param state table
---@return table[]  { id, name, desc, cost, available }
function M.get_available_types(state)
    local sett = state.settlements.tower
    local gw = sett and sett.goodwill or 0
    local lv = Goodwill.get_level(gw)
    local intel = _ensure(state)

    local result = {}
    -- Lv1: 天气
    if lv >= 1 then
        table.insert(result, {
            id = "weather", name = M.INTEL_TYPES.weather.name,
            desc = M.INTEL_TYPES.weather.desc,
            cost = M.INTEL_TYPES.weather.cost,
            available = intel.route_data >= M.INTEL_TYPES.weather.cost,
        })
    end
    -- Lv1: 价格
    if lv >= 1 then
        table.insert(result, {
            id = "price", name = M.INTEL_TYPES.price.name,
            desc = M.INTEL_TYPES.price.desc,
            cost = M.INTEL_TYPES.price.cost,
            available = intel.route_data >= M.INTEL_TYPES.price.cost,
        })
    end
    -- Lv2: 安全
    if lv >= 2 then
        table.insert(result, {
            id = "security", name = M.INTEL_TYPES.security.name,
            desc = M.INTEL_TYPES.security.desc,
            cost = M.INTEL_TYPES.security.cost,
            available = intel.route_data >= M.INTEL_TYPES.security.cost,
        })
    end
    -- Lv2: 商机
    if lv >= 2 then
        table.insert(result, {
            id = "tip", name = M.INTEL_TYPES.tip.name,
            desc = M.INTEL_TYPES.tip.desc,
            cost = M.INTEL_TYPES.tip.cost,
            available = intel.route_data >= M.INTEL_TYPES.tip.cost,
        })
    end
    return result
end

--- 交换情报
---@param state table
---@param intel_type string
---@return boolean success, string|nil result_text
function M.exchange(state, intel_type)
    local def = M.INTEL_TYPES[intel_type]
    if not def then return false, "未知情报类型" end
    local intel = _ensure(state)
    if intel.route_data < def.cost then
        return false, "路况数据不足"
    end

    intel.route_data = intel.route_data - def.cost
    intel.total_exchanged = intel.total_exchanged + 1

    -- 生成情报文本（简化：随机描述）
    local texts = {
        weather  = {
            "下趟旅途预计晴朗，适合出行。",
            "前方可能有沙尘天气，注意减速。",
            "天气转凉，道路可能有霜冻。",
            "预报显示路途天气稳定。",
        },
        security = {
            "东线公路近期有掠夺者出没，建议绕行。",
            "小径区域较为安全，近期无异常。",
            "捷径附近发现可疑营火痕迹，谨慎通行。",
            "目前所有主要路线安全状况良好。",
        },
    }

    -- ============================================================
    -- 商机情报：注入真实供需变化
    -- ============================================================
    if intel_type == "tip" then
        -- 随机选择一个聚落和对应紧缺商品
        local tip_combos = {
            { settlement = "bell_tower",  goods = "old_book",    name = "钟楼书院", goods_name = "旧书" },
            { settlement = "greenhouse",  goods = "water",       name = "温室社区", goods_name = "净水" },
            { settlement = "ruins_camp",  goods = "fuel_cell",   name = "废墟营地", goods_name = "燃料芯" },
            { settlement = "tower",       goods = "circuit",     name = "北穹塔台", goods_name = "电路板" },
            { settlement = "greenhouse",  goods = "ammo",        name = "温室社区", goods_name = "弹药" },
            { settlement = "bell_tower",  goods = "metal_scrap", name = "钟楼书院", goods_name = "废金属" },
            { settlement = "ruins_camp",  goods = "food_can",    name = "废墟营地", goods_name = "罐头" },
            { settlement = "tower",       goods = "water",       name = "北穹塔台", goods_name = "净水" },
        }
        local combo = tip_combos[math.random(1, #tip_combos)]

        -- 注入供需：supply_demand 负值 = 供不应求 → 涨价
        local sett_data = state.settlements[combo.settlement]
        if sett_data then
            if not sett_data.supply_demand then sett_data.supply_demand = {} end
            local cur = sett_data.supply_demand[combo.goods] or 0
            sett_data.supply_demand[combo.goods] = cur - 30  -- 强烈紧缺
        end

        local text = combo.name .. "急需" .. combo.goods_name .. "，价格翻倍收购！限时 1 趟。"
        table.insert(intel.active_intel, {
            type       = intel_type,
            name       = def.name,
            desc_text  = text,
            trips_left = def.duration,
            -- 额外数据：用于地图显示
            target_settlement = combo.settlement,
            target_goods      = combo.goods,
        })
        return true, text
    end

    -- ============================================================
    -- 价格情报：记录目标聚落信息（用于定价加成判定）
    -- ============================================================
    if intel_type == "price" then
        -- 随机选择一个聚落
        local price_targets = {
            { id = "greenhouse",  name = "温室社区" },
            { id = "tower",       name = "北穹塔台" },
            { id = "ruins_camp",  name = "废墟营地" },
            { id = "bell_tower",  name = "钟楼书院" },
        }
        local target = price_targets[math.random(1, #price_targets)]
        local text = target.name .. "的物价趋势已掌握，交易将更有优势。"
        table.insert(intel.active_intel, {
            type       = intel_type,
            name       = def.name,
            desc_text  = text,
            trips_left = def.duration,
            target_settlement = target.id,
        })
        return true, text
    end

    -- 位置情报：解锁隐藏节点
    if intel_type == "location" then
        -- 查找尚未解锁的隐藏节点
        local Graph = require("map/world_graph")
        local known = state.map.known_nodes or {}
        local candidates = {}
        for _, node in ipairs(Graph.NODES) do
            if node.hidden and not known[node.id] then
                table.insert(candidates, node)
            end
        end
        if #candidates == 0 then
            return false, "没有更多可发现的隐藏地点"
        end
        local chosen = candidates[math.random(1, #candidates)]
        -- 解锁该节点
        state.map.known_nodes[chosen.id] = true
        local text = "获得关键情报：" .. chosen.name .. " 的位置已标记在地图上！"
        -- 位置情报不存入活跃列表（duration=0，一次性效果）
        return true, text
    end

    local pool = texts[intel_type] or { "暂无详细情报。" }
    local text = pool[math.random(1, #pool)]

    -- 存入活跃情报
    table.insert(intel.active_intel, {
        type       = intel_type,
        name       = def.name,
        desc_text  = text,
        trips_left = def.duration,
    })

    return true, text
end

--- 行程结束后：过期已用完的情报
---@param state table
function M.tick_intel(state)
    local intel = _ensure(state)
    local remaining = {}
    for _, info in ipairs(intel.active_intel) do
        info.trips_left = info.trips_left - 1
        if info.trips_left > 0 then
            table.insert(remaining, info)
        end
    end
    intel.active_intel = remaining
end

--- 获取当前活跃情报列表
---@param state table
---@return table[]
function M.get_active_intel(state)
    local intel = _ensure(state)
    return intel.active_intel
end

--- 检查是否有某类型的活跃情报
---@param state table
---@param intel_type string  "weather"|"price"|"security"|"tip"
---@return boolean
function M.has_active(state, intel_type)
    local intel = _ensure(state)
    for _, info in ipairs(intel.active_intel) do
        if info.type == intel_type then return true end
    end
    return false
end

--- 获取某类型的所有活跃情报
---@param state table
---@param intel_type string
---@return table[]
function M.get_active_of_type(state, intel_type)
    local intel = _ensure(state)
    local result = {}
    for _, info in ipairs(intel.active_intel) do
        if info.type == intel_type then
            table.insert(result, info)
        end
    end
    return result
end

--- 获取统计
---@param state table
---@return number exchanged, number data_points
function M.get_stats(state)
    local intel = _ensure(state)
    return intel.total_exchanged, intel.route_data
end

return M

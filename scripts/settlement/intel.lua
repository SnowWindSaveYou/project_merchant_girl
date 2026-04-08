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
        price    = {
            "温室社区近期食品需求旺盛，罐头价格上涨 15%。",
            "废墟营地弹药充足，价格略有下降。",
            "塔台目前电路板库存紧张，可溢价出售。",
            "各聚落物价平稳，无明显波动。",
        },
        security = {
            "东线公路近期有掠夺者出没，建议绕行。",
            "小径区域较为安全，近期无异常。",
            "捷径附近发现可疑营火痕迹，谨慎通行。",
            "目前所有主要路线安全状况良好。",
        },
        tip      = {
            "钟楼书院急需旧书，价格翻倍收购！限时 1 趟。",
            "温室急需净水，愿意高价收购。",
            "废墟营地有人高价求购燃料芯。",
            "塔台需要医疗包，价格上浮 20%。",
        },
    }

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

--- 获取统计
---@param state table
---@return number exchanged, number data_points
function M.get_stats(state)
    local intel = _ensure(state)
    return intel.total_exchanged, intel.route_data
end

return M

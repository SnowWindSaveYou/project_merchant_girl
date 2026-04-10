--- 订单簿系统（OrderBook）
--- 支持多订单并持、接单与出发解耦、途经自动交付
--- 含积压副作用与聚落信誉系统
local Goods      = require("economy/goods")
local Pricing    = require("economy/pricing")
local Graph      = require("map/world_graph")
local CargoUtils = require("economy/cargo_utils")
local ItemUse    = require("economy/item_use")

local M = {}

-- ============================================================
-- 订单状态
-- ============================================================
M.Status = {
    AVAILABLE = "available", -- 可接
    ACCEPTED  = "accepted",  -- 已接未装载
    LOADED    = "loaded",    -- 已装载在车
    DELIVERED = "delivered", -- 已送达
    EXPIRED   = "expired",   -- 超时失效
    ABANDONED = "abandoned", -- 玩家主动放弃
}

-- ============================================================
-- 积压等级阈值
-- ============================================================
M.Backlog = {
    NORMAL_MAX  = 6,   -- 0~6 单：正常
    CROWDED_MAX = 9,   -- 7~9 单：拥挤
    -- 10+ 单：过载
}

--- 获取当前积压等级
---@param state table
---@return string level  "normal" | "crowded" | "overloaded"
function M.get_backlog_level(state)
    local n = M.active_count(state)
    if n <= M.Backlog.NORMAL_MAX then
        return "normal"
    elseif n <= M.Backlog.CROWDED_MAX then
        return "crowded"
    else
        return "overloaded"
    end
end

--- 获取积压信息（用于 UI 展示）
---@return table { level, count, reward_penalty, goodwill_mult, desc }
function M.get_backlog_info(state)
    local level = M.get_backlog_level(state)
    local count = M.active_count(state)
    local consec = (state.stats and state.stats.consecutive_expires) or 0

    local reward_penalty = 0    -- 奖励下调百分比
    local goodwill_mult  = 1.0  -- 好感获取倍率
    local desc = "正常"

    if level == "crowded" then
        reward_penalty = 5 + consec * 3   -- 拥挤 -5%，每连续超时再 -3%
        goodwill_mult  = 0.9
        desc = "拥挤"
    elseif level == "overloaded" then
        reward_penalty = 12 + consec * 5  -- 过载 -12%，每连续超时再 -5%
        goodwill_mult  = 0.7
        desc = "过载"
    elseif consec >= 2 then
        -- 正常积压但连续超时 >= 2 也有轻微惩罚
        reward_penalty = consec * 2
        goodwill_mult  = 0.95
        desc = "信誉受损"
    end

    reward_penalty = math.min(reward_penalty, 30)  -- 上限 30%

    return {
        level          = level,
        count          = count,
        reward_penalty = reward_penalty,
        goodwill_mult  = goodwill_mult,
        desc           = desc,
        consecutive_expires = consec,
    }
end

-- ============================================================
-- 各聚落擅长出产的商品（出发地可提供的货源）
-- ============================================================
local SETTLEMENT_GOODS = {
    greenhouse      = { "food_can", "water", "medicine" },
    tower           = { "circuit", "fuel_cell", "metal_scrap" },
    ruins_camp      = { "metal_scrap", "ammo", "smoke_bomb" },
    bell_tower      = { "old_book", "music_disc", "medicine" },
    -- 前哨站（继承首都商品池，各有特色）
    greenhouse_farm = { "food_can", "water", "medicine" },
    dome_outpost    = { "circuit", "fuel_cell", "metal_scrap" },
    metro_camp      = { "metal_scrap", "ammo", "smoke_bomb" },
    old_church      = { "old_book", "music_disc", "medicine" },
}

-- ============================================================
-- 序号计数器（保证同一局 order_id 唯一）
-- ============================================================
local _seq = 0

local function next_order_id()
    _seq = _seq + 1
    return "ord_" .. _seq .. "_" .. os.time()
end

-- ============================================================
-- 订单生成（到达聚落时调用一次，缓存到 state.map.available_orders）
-- ============================================================

--- 到达聚落时生成订单并缓存（只在到达时调用一次）
--- 如果缓存已有内容则不重新生成
---@param state table
---@param settlement_id string 到达的聚落 id
---@return table[] orders  缓存中的可接订单列表
function M.generate_on_arrival(state, settlement_id)
    -- 确保缓存结构存在
    if not state.map.available_orders then
        state.map.available_orders = {}
    end

    -- 教程订单覆盖：教程阶段生成固定订单
    local Tutorial = require("narrative/tutorial")
    local tutorial_orders = Tutorial.get_tutorial_orders(state, settlement_id)
    if tutorial_orders then
        state.map.available_orders[settlement_id] = tutorial_orders
        return tutorial_orders
    end

    -- 如果缓存中已有该聚落的订单（同次停留），直接返回
    if state.map.available_orders[settlement_id]
       and #state.map.available_orders[settlement_id] > 0 then
        return state.map.available_orders[settlement_id]
    end

    -- 生成新一批订单
    local orders = M._generate_batch(state, settlement_id)
    state.map.available_orders[settlement_id] = orders
    return orders
end

--- 获取当前缓存的可接订单（不触发生成）
---@param state table
---@param settlement_id string
---@return table[]
function M.get_available(state, settlement_id)
    if not state.map.available_orders then return {} end
    return state.map.available_orders[settlement_id] or {}
end

--- 清除某聚落的缓存订单（出发离开时调用）
function M.clear_available(state, settlement_id)
    if state.map.available_orders then
        state.map.available_orders[settlement_id] = nil
    end
end

--- 清除所有聚落缓存订单
function M.clear_all_available(state)
    state.map.available_orders = {}
end

--- 内部：生成一批订单（2~4 个），考虑积压惩罚
---@param state table
---@param settlement_id string
---@return table[]
function M._generate_batch(state, settlement_id)
    local pool = SETTLEMENT_GOODS[settlement_id] or { "food_can" }
    local destinations = {}

    -- 收集所有其他已知聚落作为可能目的地
    for _, node in ipairs(Graph.NODES) do
        if node.type == "settlement" and node.id ~= settlement_id then
            local known = state.map.known_nodes or {}
            if known[node.id] then
                table.insert(destinations, node)
            end
        end
    end

    -- 至少要有一个目的地
    if #destinations == 0 then return {} end

    local backlog = M.get_backlog_info(state)
    local orders = {}

    -- 1. 稳定单（必定生成 —— 保底）
    local dest1 = destinations[math.random(1, #destinations)]
    table.insert(orders, M._make_order(pool, settlement_id, dest1.id, "stable", backlog))

    -- 2. 高利润单：积压越重，出现概率越低
    local lucrative_chance = 1.0
    if backlog.level == "crowded" then
        lucrative_chance = 0.5
    elseif backlog.level == "overloaded" then
        lucrative_chance = 0.15
    end
    if math.random() < lucrative_chance then
        local dest2 = destinations[math.random(1, #destinations)]
        table.insert(orders, M._make_order(pool, settlement_id, dest2.id, "lucrative", backlog))
    else
        -- 降级为稳定单
        local dest2 = destinations[math.random(1, #destinations)]
        table.insert(orders, M._make_order(pool, settlement_id, dest2.id, "stable", backlog))
    end

    -- 3. 50% 概率追加一个风险单（过载时降为 20%）
    local risky_chance = 0.5
    if backlog.level == "overloaded" then risky_chance = 0.2 end
    if math.random() < risky_chance then
        local dest3 = destinations[math.random(1, #destinations)]
        table.insert(orders, M._make_order(pool, settlement_id, dest3.id, "risky", backlog))
    end

    -- 4. 30% 概率再追加一个随机单（过载时不追加）
    if backlog.level ~= "overloaded" and math.random() < 0.3 then
        local dest4 = destinations[math.random(1, #destinations)]
        table.insert(orders, M._make_order(pool, settlement_id, dest4.id, "stable", backlog))
    end

    -- 检查聚落信誉：信誉过低时减少订单数量
    local sett = state.settlements[settlement_id]
    local rep = sett and sett.reputation or 100
    if rep < 50 and #orders > 2 then
        -- 信誉低于 50 时最多保留 2 个订单
        while #orders > 2 do
            table.remove(orders, #orders)
        end
    elseif rep < 30 and #orders > 1 then
        -- 信誉低于 30 时只保留保底 1 个
        while #orders > 1 do
            table.remove(orders, #orders)
        end
    end

    return orders
end

--- 内部：生成单个订单（考虑积压惩罚对 reward 的下调）
function M._make_order(goods_pool, from_id, to_id, kind, backlog)
    local g_id = goods_pool[math.random(1, #goods_pool)]
    local g = Goods.get(g_id)
    local from_name = Graph.get_node_name(from_id)
    local to_name   = Graph.get_node_name(to_id)

    local count, deadline_sec, risk_level
    if kind == "stable" then
        count = math.random(2, math.min(5, g.stack_limit))
        deadline_sec = 600  -- 10 分钟
        risk_level = "low"
    elseif kind == "lucrative" then
        count = math.random(4, math.min(8, g.stack_limit))
        deadline_sec = 900  -- 15 分钟
        risk_level = "normal"
    elseif kind == "risky" then
        count = math.random(3, math.min(6, g.stack_limit))
        deadline_sec = 480  -- 8 分钟
        risk_level = "high"
    else
        count = math.random(2, math.min(5, g.stack_limit))
        deadline_sec = 600
        risk_level = "low"
    end

    local buy_total  = Pricing.get_buy_price(g_id, from_id) * count
    local sell_total = Pricing.get_sell_price(g_id, to_id) * count
    local base_reward = math.max(20, math.floor((sell_total - buy_total) * 0.8 + 30))

    if kind == "lucrative" then
        base_reward = math.floor(base_reward * 1.4 + math.random(10, 25))
    elseif kind == "risky" then
        base_reward = math.floor(base_reward * 1.6 + math.random(15, 30))
    end

    -- 积压惩罚：下调 base_reward
    if backlog and backlog.reward_penalty > 0 then
        local factor = 1.0 - backlog.reward_penalty / 100
        base_reward = math.max(15, math.floor(base_reward * factor))
    end

    return {
        order_id     = next_order_id(),
        from         = from_id,
        to           = to_id,
        from_name    = from_name,
        to_name      = to_name,
        goods_id     = g_id,
        goods_name   = g.name,
        count        = count,
        base_reward  = base_reward,
        deadline_sec = deadline_sec,
        risk_level   = risk_level,
        status       = M.Status.AVAILABLE,
        accepted_at  = nil,
        description  = "运送" .. g.name .. " ×" .. count .. " 到" .. to_name,
    }
end

-- ============================================================
-- 订单簿操作
-- ============================================================

--- 获取订单簿（state 中的引用）
function M.get_book(state)
    if not state.economy.order_book then
        state.economy.order_book = {}
    end
    return state.economy.order_book
end

--- 接取订单：把 available 订单加入订单簿，状态改为 accepted
--- 同时装载货物到货舱并记录委托
---@return boolean success
---@return string? error_msg
function M.accept_order(state, order)
    local book = M.get_book(state)

    -- 检查是否已接过
    for _, o in ipairs(book) do
        if o.order_id == order.order_id then
            return false, "订单已接取"
        end
    end

    -- 仓位检查：货物需要实际占用货舱
    local free = CargoUtils.get_cargo_free(state)
    if free < order.count then
        return false, "仓位不足（需 " .. order.count .. " 格，剩余 " .. free .. " 格）"
    end

    -- 从缓存中移除该订单
    if state.map.available_orders then
        for sid, list in pairs(state.map.available_orders) do
            for i, o in ipairs(list) do
                if o.order_id == order.order_id then
                    table.remove(list, i)
                    break
                end
            end
        end
    end

    -- 加入订单簿
    local entry = {}
    for k, v in pairs(order) do entry[k] = v end
    entry.status = M.Status.ACCEPTED
    entry.accepted_at = os.time()

    table.insert(book, entry)

    -- 装载货物到货舱 & 记录委托
    local gid = order.goods_id
    state.truck.cargo[gid] = (state.truck.cargo[gid] or 0) + order.count
    CargoUtils.add_committed(state, gid, order.count)

    -- 接单时解锁目的地节点（使其在地图上可见）
    if order.to and state.map.known_nodes then
        if not state.map.known_nodes[order.to] then
            state.map.known_nodes[order.to] = true
            print("[OrderBook] Discovered destination: " .. order.to)
        end
    end

    return true
end

--- 检查订单是否可放弃（教程/任务订单不可放弃）
---@param order table
---@return boolean
function M.can_abandon(order)
    if order.is_tutorial or order.no_abandon then
        return false
    end
    return true
end

--- 放弃订单（扣信誉 3 点，退还货物，清除委托）
function M.abandon_order(state, order_id)
    local book = M.get_book(state)
    for _, o in ipairs(book) do
        if o.order_id == order_id then
            -- 教程/任务订单不可放弃
            if not M.can_abandon(o) then
                return false, "该委托无法放弃"
            end
            if o.status == M.Status.ACCEPTED or o.status == M.Status.LOADED then
                o.status = M.Status.ABANDONED
                -- 轻微信誉扣分
                M._adjust_reputation(state, o.from, -3)

                -- 退还货物：从货舱移除委托数量（最多移除实际持有量）
                local gid = o.goods_id
                local held = state.truck.cargo[gid] or 0
                local remove_count = math.min(o.count, held)
                if remove_count > 0 then
                    state.truck.cargo[gid] = held - remove_count
                    if state.truck.cargo[gid] <= 0 then
                        state.truck.cargo[gid] = nil
                    end
                end

                -- 清除委托记录
                CargoUtils.remove_committed(state, gid, o.count)

                return true
            end
            return false, "该订单状态不可放弃"
        end
    end
    return false, "订单不存在"
end

--- 标记订单为已装载（出发前）
--- 注意：B2 方案下接单即装载，此函数保留用于状态标记
function M.load_order(state, order_id)
    local book = M.get_book(state)
    for _, o in ipairs(book) do
        if o.order_id == order_id and o.status == M.Status.ACCEPTED then
            o.status = M.Status.LOADED
            return true
        end
    end
    return false
end

--- 批量装载所有 accepted 订单（标记状态为 LOADED）
--- B2 方案下货物已在接单时装入货舱，此处仅更新状态标记
function M.load_all_accepted(state)
    local book = M.get_book(state)
    local count = 0
    for _, o in ipairs(book) do
        if o.status == M.Status.ACCEPTED then
            o.status = M.Status.LOADED
            count = count + 1
        end
    end
    return count
end

-- ============================================================
-- 途经自动交付
-- ============================================================

--- 当到达某节点时，检查并自动交付匹配的订单
--- B2 方案：按实际持有货物比例交付，分全额/部分/失败三档
---   全额：货物充足 → 全额奖励 + 信誉 +2
---   部分：0 < 实际 < 需求 → 按比例奖励，信誉不变
---   失败：货物为 0 → 无奖励，信誉 -5
--- 交付优先级：按截止时间从早到晚分配稀缺货物
---@param state table
---@param arrived_node_id string
---@return table[] delivered_orders  所有处理过的订单（含 delivery_result 字段）
---@return number total_reward
function M.auto_deliver(state, arrived_node_id)
    local book = M.get_book(state)
    local delivered = {}
    local total_reward = 0
    local now = os.time()
    local backlog = M.get_backlog_info(state)

    -- 按 deadline 排序（先到期的先交）
    local candidates = {}
    for _, o in ipairs(book) do
        if o.to == arrived_node_id
            and (o.status == M.Status.ACCEPTED or o.status == M.Status.LOADED)
        then
            table.insert(candidates, o)
        end
    end
    table.sort(candidates, function(a, b)
        return (a.accepted_at or 0) + (a.deadline_sec or 600)
             < (b.accepted_at or 0) + (b.deadline_sec or 600)
    end)

    -- 临时可用库存副本（多个订单共享同一货物时按优先级分配）
    local avail = {}
    for gid, cnt in pairs(state.truck.cargo) do
        if cnt > 0 then avail[gid] = cnt end
    end

    for _, o in ipairs(candidates) do
        -- 检查是否超时
        local deadline_at = (o.accepted_at or 0) + (o.deadline_sec or 600)
        if now > deadline_at then
            o.status = M.Status.EXPIRED
            M._adjust_reputation(state, o.to, -5)
            state.stats.consecutive_expires = (state.stats.consecutive_expires or 0) + 1

            -- 超时也要清除委托 & 退还货物
            CargoUtils.remove_committed(state, o.goods_id, o.count)
            -- 超时的货物留在货舱，不扣除

            o.delivery_result = "expired"
            o.delivered_count = 0
            o.partial_reward  = 0
            table.insert(delivered, o)
        else
            -- 按库存分配
            local gid = o.goods_id
            local have = avail[gid] or 0
            local need = o.count
            local give = math.min(have, need)

            -- 从临时库存扣除
            if give > 0 then
                avail[gid] = have - give
            end

            -- 判定交付等级
            local reward = 0
            local result = "failed"

            if give >= need then
                -- 全额交付
                result = "full"
                reward = o.base_reward
                M._adjust_reputation(state, o.to, 2)
                local goodwill_gain = math.floor(3 * backlog.goodwill_mult)
                if state.settlements[o.to] then
                    state.settlements[o.to].goodwill =
                        (state.settlements[o.to].goodwill or 0) + goodwill_gain
                end
                state.stats.consecutive_expires = 0
            elseif give > 0 then
                -- 部分交付：按比例计算奖励，信誉不变
                result = "partial"
                reward = math.floor(o.base_reward * give / need)
            else
                -- 完全失败：无奖励，扣信誉
                result = "failed"
                reward = 0
                M._adjust_reputation(state, o.to, -5)
            end

            o.status          = M.Status.DELIVERED
            o.delivery_result = result
            o.delivered_count = give
            o.partial_reward  = reward

            if reward > 0 then
                state.economy.credits = state.economy.credits + reward
                total_reward = total_reward + reward
            end

            -- 从实际货舱扣除交付的货物
            if give > 0 then
                local cur = state.truck.cargo[gid] or 0
                cur = cur - give
                if cur <= 0 then
                    state.truck.cargo[gid] = nil
                else
                    state.truck.cargo[gid] = cur
                end
            end

            -- 清除委托记录
            CargoUtils.remove_committed(state, gid, need)

            table.insert(delivered, o)
        end
    end

    -- 连续超时 >= 3：士气低落
    if (state.stats.consecutive_expires or 0) >= 3 then
        local target = math.random() < 0.5 and "linli" or "taoxia"
        ItemUse.add_status(state, target, "demoralized")
    end

    return delivered, total_reward
end

-- ============================================================
-- 信誉调整（内部）
-- ============================================================
function M._adjust_reputation(state, settlement_id, delta)
    local sett = state.settlements[settlement_id]
    if not sett then return end
    if not sett.reputation then sett.reputation = 100 end
    sett.reputation = math.max(0, math.min(150, sett.reputation + delta))
end

-- ============================================================
-- 查询工具
-- ============================================================

--- 获取指定状态的订单列表
function M.get_by_status(state, status)
    local book = M.get_book(state)
    local result = {}
    for _, o in ipairs(book) do
        if o.status == status then
            table.insert(result, o)
        end
    end
    return result
end

--- 获取活跃订单（accepted + loaded）
function M.get_active(state)
    local book = M.get_book(state)
    local result = {}
    for _, o in ipairs(book) do
        if o.status == M.Status.ACCEPTED or o.status == M.Status.LOADED then
            table.insert(result, o)
        end
    end
    return result
end

--- 按目的地分组活跃订单
function M.group_by_destination(state)
    local active = M.get_active(state)
    local groups = {}
    for _, o in ipairs(active) do
        if not groups[o.to] then
            groups[o.to] = { dest_id = o.to, dest_name = o.to_name, orders = {} }
        end
        table.insert(groups[o.to].orders, o)
    end
    return groups
end

--- 获取某订单的剩余时间（秒），<0 表示已超时
function M.get_remaining_time(order)
    if not order.accepted_at then return order.deadline_sec or 600 end
    local deadline_at = order.accepted_at + (order.deadline_sec or 600)
    return deadline_at - os.time()
end

--- 检查并标记所有超时订单（同时处理信誉扣分和委托清除）
--- 连续超时 >= 3 时施加 demoralized 状态
function M.check_expirations(state)
    local book = M.get_book(state)
    local expired_count = 0
    local now = os.time()
    for _, o in ipairs(book) do
        if (o.status == M.Status.ACCEPTED or o.status == M.Status.LOADED) then
            local deadline_at = (o.accepted_at or 0) + (o.deadline_sec or 600)
            if now > deadline_at then
                o.status = M.Status.EXPIRED
                expired_count = expired_count + 1
                M._adjust_reputation(state, o.to, -5)
                state.stats.consecutive_expires = (state.stats.consecutive_expires or 0) + 1
                -- 清除委托记录（货物留在货舱）
                CargoUtils.remove_committed(state, o.goods_id, o.count)
            end
        end
    end

    -- 连续超时 >= 3：士气低落
    if (state.stats.consecutive_expires or 0) >= 3 then
        local target = math.random() < 0.5 and "linli" or "taoxia"
        ItemUse.add_status(state, target, "demoralized")
    end

    return expired_count
end

--- 清理已完结的订单（delivered / expired / abandoned）
--- 保留最近 N 条历史记录
function M.cleanup(state, keep_history)
    keep_history = keep_history or 10
    local book = M.get_book(state)
    local active = {}
    local history = {}
    for _, o in ipairs(book) do
        if o.status == M.Status.ACCEPTED or o.status == M.Status.LOADED then
            table.insert(active, o)
        else
            table.insert(history, o)
        end
    end
    -- 只保留最近 keep_history 条历史
    while #history > keep_history do
        table.remove(history, 1)
    end
    -- 合并
    state.economy.order_book = {}
    for _, o in ipairs(active) do
        table.insert(state.economy.order_book, o)
    end
    for _, o in ipairs(history) do
        table.insert(state.economy.order_book, o)
    end
end

--- 活跃订单数量
function M.active_count(state)
    return #M.get_active(state)
end

--- 获取所有活跃订单的目的地节点 id 集合
function M.get_destination_set(state)
    local active = M.get_active(state)
    local set = {}
    for _, o in ipairs(active) do
        set[o.to] = true
    end
    return set
end

return M

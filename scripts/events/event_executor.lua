--- 事件执行器
--- 将 "add_credit:20" 格式的指令统一应用到 state
--- 支持设计文档定义的全部 16 种 ops
local Flags    = require("core/flags")
local ItemUse  = require("economy/item_use")
local Goodwill = require("settlement/goodwill")

--- demoralized 好感衰减倍率
local function goodwill_mult(state)
    local demoralized = ItemUse.has_status(state, "linli", "demoralized")
        or ItemUse.has_status(state, "taoxia", "demoralized")
    return demoralized and 0.8 or 1.0
end

local M = {}

--- 批量执行操作列表，返回执行日志
---@param state table
---@param ops string[]
---@return string[] log 每条 op 的执行结果描述
function M.apply(state, ops)
    if not ops then return {} end
    local log = {}
    for _, op in ipairs(ops) do
        local msg = M.apply_one(state, op)
        if msg then table.insert(log, msg) end
    end
    return log
end

--- 执行单条操作，返回结果描述
---@param state table
---@param op string
---@return string|nil
function M.apply_one(state, op)
    -- 支持多段参数: "action:arg1:arg2" → action="action", value="arg1:arg2"
    local action, value = op:match("^([^:]+):(.+)$")
    if not action then
        print("[EventExec] Invalid op: " .. op)
        return nil
    end
    local num = tonumber(value)

    -- ====== 经济 ======

    if action == "add_credit" or action == "add_credits" then
        state.economy.credits = math.max(0, state.economy.credits + (num or 0))

    elseif action == "add_fuel" then
        state.truck.fuel = math.max(0, math.min(state.truck.fuel_max, state.truck.fuel + (num or 0)))

    elseif action == "add_durability" then
        state.truck.durability = math.max(0, math.min(state.truck.durability_max, state.truck.durability + (num or 0)))

    -- ====== 伤害/修复（与 add_durability 互补，语义更清晰） ======

    elseif action == "add_damage" then
        -- "add_damage:15" → 货车受到 15 点伤害
        local dmg = num or 0
        state.truck.durability = math.max(0, state.truck.durability - dmg)

    elseif action == "repair_damage" then
        -- "repair_damage:10" → 修复 10 点耐久
        local rep = num or 0
        state.truck.durability = math.min(state.truck.durability_max, state.truck.durability + rep)

    -- ====== 好感/关系 ======

    elseif action == "add_goodwill" then
        -- 支持两种格式:
        -- "add_goodwill:5"              → 对当前聚落加好感
        -- "add_goodwill:greenhouse:10"  → 对指定聚落加好感
        -- demoralized 状态：好感获取 -20%
        -- 势力溢出：同势力其他聚落获得 50% 好感
        local gw_mult = goodwill_mult(state)
        local target_sid, amt = value:match("^(.+):([%d%-]+)$")
        if target_sid and state.settlements[target_sid] then
            local raw = tonumber(amt) or 0
            local final = (raw > 0) and math.floor(raw * gw_mult + 0.5) or raw
            state.settlements[target_sid].goodwill = state.settlements[target_sid].goodwill + final
            Goodwill.apply_faction_spillover(state, target_sid, final)
        else
            -- 无 settlement 参数，对当前聚落操作
            local loc = state.flow.travel and state.flow.travel.to or state.map.current_location
            if state.settlements[loc] then
                local raw = num or 0
                local final = (raw > 0) and math.floor(raw * gw_mult + 0.5) or raw
                state.settlements[loc].goodwill = state.settlements[loc].goodwill + final
                Goodwill.apply_faction_spillover(state, loc, final)
            end
        end

    elseif action == "add_relation" then
        -- 通用关系: "add_relation:2" → 双角色各加 1（向上取整分配）
        local total = num or 0
        local half = math.ceil(total / 2)
        state.character.linli.relation  = state.character.linli.relation  + half
        state.character.taoxia.relation = state.character.taoxia.relation + (total - half)

    elseif action == "add_relation_linli" then
        state.character.linli.relation = state.character.linli.relation + (num or 0)

    elseif action == "add_relation_taoxia" then
        state.character.taoxia.relation = state.character.taoxia.relation + (num or 0)

    -- ====== 物品 ======

    elseif action == "consume_goods" then
        -- "consume_goods:water:1" → 消耗 1 个 water
        local gid, cnt = value:match("^(.+):(%d+)$")
        if gid then
            ItemUse.consume(state, gid, tonumber(cnt) or 1)
        end

    elseif action == "add_goods" then
        -- "add_goods:metal_scrap:2" → 获得 2 个 metal_scrap
        local gid, cnt = value:match("^(.+):(%d+)$")
        if gid then
            ItemUse.add(state, gid, tonumber(cnt) or 1)
        end

    elseif action == "lose_goods" then
        -- "lose_goods:food_can:3" → 丢失 3 个 food_can（与 consume_goods 语义相同但更明确）
        local gid, cnt = value:match("^(.+):(%d+)$")
        if gid then
            ItemUse.consume(state, gid, tonumber(cnt) or 1)
        end

    -- ====== 时间 ======

    elseif action == "add_time" then
        -- "add_time:10" → 行程增加 10 秒
        -- 如果在行程中，增加当前段的已用时间；否则仅记录日志
        local timer = state.flow.event_timer
        if timer then
            timer.elapsed = timer.elapsed + (num or 0)
        end

    -- ====== 旗标 ======

    elseif action == "set_flag" then
        Flags.set(state, value)

    elseif action == "clear_flag" then
        Flags.clear(state, value)

    -- ====== 地图/解锁 ======

    elseif action == "unlock_route" then
        -- "unlock_route:danger_pass" → 将节点标记为已知
        if state.map.known_nodes then
            state.map.known_nodes[value] = true
        end

    elseif action == "unlock_clue" then
        -- "unlock_clue:night_market_1" → 记录线索到叙事系统
        if not state.narrative.clues then state.narrative.clues = {} end
        state.narrative.clues[value] = true

    elseif action == "unlock_event" then
        -- "unlock_event:EVT_023" → 将特定事件解锁（通过设置对应旗标）
        Flags.set(state, "event_unlocked_" .. value)

    -- ====== 角色状态 ======

    elseif action == "add_status" then
        -- "add_status:linli:fatigued" 或 "add_status:fatigued"（默认双角色）
        local char_id, sid = value:match("^(.+):(.+)$")
        if char_id and (char_id == "linli" or char_id == "taoxia") then
            ItemUse.add_status(state, char_id, sid)
        else
            -- 无角色指定，随机施加给一个角色
            local target = math.random() < 0.5 and "linli" or "taoxia"
            ItemUse.add_status(state, target, value)
        end

    elseif action == "clear_status" then
        -- "clear_status:linli:fatigued" 或 "clear_status:fatigued"（清除所有角色的）
        local char_id, sid = value:match("^(.+):(.+)$")
        if char_id and (char_id == "linli" or char_id == "taoxia") then
            ItemUse.clear_status(state, char_id, sid)
        else
            ItemUse.clear_status(state, "linli", value)
            ItemUse.clear_status(state, "taoxia", value)
        end

    -- ====== 战斗/订单 ======

    elseif action == "start_combat" then
        -- "start_combat:ambush_light" → 标记待处理战斗
        state.flow.pending_combat = value
        print("[EventExec] Combat queued: " .. value)

    elseif action == "start_explore" then
        -- "start_explore:abandoned_warehouse" → 标记待处理探索
        state.flow.pending_explore = value
        print("[EventExec] Explore queued: " .. value)

    elseif action == "spawn_order" then
        -- "spawn_order:urgent_medicine" → 在当前聚落注入一个特殊订单
        if not state.map.injected_orders then state.map.injected_orders = {} end
        table.insert(state.map.injected_orders, value)
        print("[EventExec] Order injected: " .. value)

    else
        print("[EventExec] Unknown: " .. action)
    end

    return action .. ":" .. value
end

return M

--- 车载迎击逻辑
--- FTL 式战术决策：玩家每回合选一个战术，陶夏自动开火
--- 目标：逃脱进度达到阈值 = 脱离；耐久归零 = 重创
local Config  = require("combat/combat_config")
local ItemUse = require("economy/item_use")
local Modules = require("truck/modules")
local Goods   = require("economy/goods")
local Tracker = require("analytics/tracker")
local Skills  = require("character/skills")

local M = {}

--- 迎击状态枚举
M.Phase = {
    INTRO     = "intro",      -- 遭遇描述
    ACTIVE    = "active",     -- 战术选择中
    RESOLVING = "resolving",  -- 本回合结算动画
    RESULT    = "result",     -- 最终结果
}

-- ============================================================
-- 创建迎击战斗实例
-- ============================================================

--- 根据敌人模板 ID 创建战斗状态
---@param state table 游戏状态
---@param enemy_id string 敌人模板 ID（如 "ambush_light"）
---@return table combat 战斗实例
function M.create(state, enemy_id)
    local template = Config.AMBUSH_ENEMIES[enemy_id]
    if not template then
        template = Config.AMBUSH_ENEMIES["ambush_light"]
        enemy_id = "ambush_light"
    end

    -- 埋点
    Tracker.milestone(state, "first_combat")
    Tracker.count(state, "combats_fought")

    local ammo_count = state.truck.cargo["ammo"] or 0
    local smoke_count = state.truck.cargo["smoke_bomb"] or 0

    return {
        enemy_id    = enemy_id,
        enemy       = template,
        phase       = M.Phase.INTRO,

        -- 战斗数值（雷达 Lv3 敌情预警：初始威胁 -20%）
        threat          = Modules.has_enemy_warning(state)
                          and math.floor(template.threat * 0.8 + 0.5)
                          or template.threat,
        escape_progress = 0,
        escape_threshold = math.max(10,
            math.floor(template.escape_threshold
                * (1 - Modules.get_repel_bonus(state))
                * (1 - Skills.get_escape_reduction(state))
                + 0.5)),
        rounds_total    = template.rounds,
        round_current   = 0,

        -- 资源快照
        ammo_available  = ammo_count,
        smoke_available = smoke_count,
        ammo_used       = 0,
        ammo_per_round  = true,   -- 每回合消耗 1 发弹药

        -- 累计结果
        total_dmg_taken = 0,
        total_fuel_cost = 0,
        cargo_lost      = {},  -- { [goods_id] = count }

        -- 回合日志
        round_log       = {},  -- 每回合的文本描述
        last_round      = nil, -- 最近一回合结果 { tactic, dmg, escape_add, narration }

        -- 最终结果
        outcome         = nil, -- "escaped" | "repelled" | "wrecked"
    }
end

-- ============================================================
-- 进入战术选择
-- ============================================================

function M.start_combat(combat)
    combat.phase = M.Phase.ACTIVE
    combat.round_current = 1
end

-- ============================================================
-- 获取当前可用战术
-- ============================================================

--- 返回每个战术的可用性信息
---@param combat table
---@return table[] tactics { id, tactic, available, reason }
function M.get_available_tactics(combat)
    local result = {}
    for _, tid in ipairs(Config.TACTIC_ORDER) do
        local t = Config.TACTICS[tid]
        local available = true
        local reason = nil

        if t.requires_ammo and combat.ammo_available <= 0 then
            available = true  -- 仍可选择，但效果削弱
            reason = t.no_ammo_desc
        end
        if t.requires_smoke and combat.smoke_available <= 0 then
            available = false
            reason = t.no_smoke_desc
        end

        table.insert(result, {
            id        = tid,
            tactic    = t,
            available = available,
            reason    = reason,
        })
    end
    return result
end

-- ============================================================
-- 执行一回合
-- ============================================================

--- 玩家选择战术后执行一回合
---@param state table 游戏状态
---@param combat table 战斗实例
---@param tactic_id string 战术 ID
---@return table round_result { tactic_name, dmg_taken, escape_add, threat_after, narration, finished }
function M.execute_round(state, combat, tactic_id)
    local tactic = Config.TACTICS[tactic_id]
    if not tactic then
        tactic = Config.TACTICS["evade"]
        tactic_id = "evade"
    end

    local enemy = combat.enemy
    local narration = {}

    -- 1. 烟幕特殊处理
    if tactic_id == "smoke" and combat.smoke_available > 0 then
        ItemUse.consume(state, "smoke_bomb", 1)
        combat.smoke_available = combat.smoke_available - 1
        combat.escape_progress = combat.escape_threshold + 1
        table.insert(narration, "林砾拉下烟幕弹拉环——浓烟瞬间吞没了追兵视线！")
        table.insert(narration, "货车在烟幕掩护下急速驶离。")

        local result = {
            tactic_name = tactic.name,
            dmg_taken   = 0,
            escape_add  = tactic.escape_add,
            threat_after = combat.threat,
            narration   = table.concat(narration, "\n"),
            finished    = true,
        }
        combat.last_round = result
        table.insert(combat.round_log, result)
        combat.outcome = "escaped"
        combat.phase = M.Phase.RESULT
        return result
    end

    -- 2. 计算逃脱进度增加（林砾受伤时驾驶能力下降 -25%）
    local escape_add = tactic.escape_add
    if ItemUse.has_status(state, "linli", "wounded") then
        escape_add = math.floor(escape_add * 0.75 + 0.5)
    end
    combat.escape_progress = combat.escape_progress + escape_add
    table.insert(narration, tactic.icon .. " " .. tactic.name .. "！")

    -- 3. 陶夏开火（自动）—— 每回合消耗 1 发弹药
    local has_ammo_this_round = false
    if combat.ammo_available > 0 then
        ItemUse.consume(state, "ammo", 1)
        combat.ammo_available = combat.ammo_available - 1
        combat.ammo_used = combat.ammo_used + 1
        has_ammo_this_round = true
    end

    local firepower = Config.NO_AMMO_FIREPOWER
    if has_ammo_this_round then
        firepower = Config.AMMO_FIREPOWER
        if tactic_id == "steady" then
            -- 稳车射击时额外削减威胁
            firepower = firepower + (tactic.threat_reduce or 0)
        end
    end
    if ItemUse.has_status(state, "taoxia", "wounded") then
        firepower = math.floor(firepower * 0.5 + 0.5)
    end
    -- turret 模块火力加成
    firepower = math.floor(firepower * Modules.get_firepower_mult(state) + 0.5)
    combat.threat = math.max(5, combat.threat - firepower)

    if has_ammo_this_round then
        if ItemUse.has_status(state, "taoxia", "wounded") then
            table.insert(narration, "陶夏忍着伤痛开火，火力不如平时。")
        else
            table.insert(narration, "陶夏架起机枪猛烈还击，压制了追兵火力。")
        end
    else
        table.insert(narration, "陶夏没有弹药，只能用手枪零星还击。")
    end

    -- 4. 敌人攻击
    local base_dmg = enemy.atk_min + math.random() * (enemy.atk_max - enemy.atk_min)
    local threat_factor = combat.threat / 100
    local dmg = math.floor(base_dmg * threat_factor * tactic.dmg_mult + 0.5)
    dmg = math.max(0, dmg)

    state.truck.durability = math.max(0, state.truck.durability - dmg)
    combat.total_dmg_taken = combat.total_dmg_taken + dmg

    if dmg > 0 then
        table.insert(narration, "货车被击中，受到 " .. dmg .. " 点损伤！")
    else
        table.insert(narration, "成功规避了敌人攻击。")
    end

    -- 5. 燃料消耗
    if tactic.fuel_cost and tactic.fuel_cost > 0 then
        state.truck.fuel = math.max(0, state.truck.fuel - tactic.fuel_cost)
        combat.total_fuel_cost = combat.total_fuel_cost + tactic.fuel_cost
    end

    -- 6. （弹药已在第3步按回合消耗，每回合消耗1发）

    -- 7. 检查战斗结束条件
    local finished = false

    if combat.escape_progress >= combat.escape_threshold then
        combat.outcome = "escaped"
        finished = true
        table.insert(narration, "成功甩脱追兵！")
    elseif state.truck.durability <= 0 then
        combat.outcome = "wrecked"
        finished = true
        state.truck.durability = 1  -- 不真正归零，保留最低耐久
        table.insert(narration, "货车严重损毁！不得不紧急停车修理...")
        -- 重创时掉货
        M._drop_cargo(state, combat)
    elseif combat.round_current >= combat.rounds_total then
        -- 回合用尽，根据威胁判定
        if combat.threat <= 20 then
            combat.outcome = "repelled"
            table.insert(narration, "追兵士气崩溃，放弃了追击！")
        else
            combat.outcome = "escaped"
            table.insert(narration, "勉强脱离了追兵。")
        end
        finished = true
    end

    combat.round_current = combat.round_current + 1

    if finished then
        combat.phase = M.Phase.RESULT
    end

    local result = {
        tactic_name  = tactic.name,
        dmg_taken    = dmg,
        escape_add   = escape_add,
        threat_after = combat.threat,
        narration    = table.concat(narration, "\n"),
        finished     = finished,
    }
    combat.last_round = result
    table.insert(combat.round_log, result)
    return result
end

-- ============================================================
-- 货物掉落
-- ============================================================

function M._drop_cargo(state, combat)
    for gid, count in pairs(state.truck.cargo) do
        if count > 0 then
            -- 价值加权：贵重货物更难掉落
            local info = Goods.get(gid)
            local base = info and info.base_price or 20
            local chance = math.max(0.15, math.min(0.55, 0.6 - base * 0.008))
            if math.random() < chance then
                local drop = math.min(count, math.random(1, Config.CARGO_DROP_MAX))
                state.truck.cargo[gid] = count - drop
                if state.truck.cargo[gid] <= 0 then
                    state.truck.cargo[gid] = nil
                end
                combat.cargo_lost[gid] = (combat.cargo_lost[gid] or 0) + drop
            end
        end
    end
end

-- ============================================================
-- 获取战斗摘要
-- ============================================================

--- 生成战斗结果摘要文本
---@param combat table
---@return table summary { title, lines, outcome }
function M.get_summary(combat)
    local title, lines = "", {}
    local outcome = combat.outcome or "escaped"

    if outcome == "escaped" then
        title = "成功脱离"
        table.insert(lines, "在追兵的围追堵截中成功逃脱。")
    elseif outcome == "repelled" then
        title = "击退追兵"
        table.insert(lines, "陶夏的火力将追兵成功击退！")
    elseif outcome == "wrecked" then
        title = "遭受重创"
        table.insert(lines, "货车严重受损，部分货物散落在路上。")
    end

    if combat.total_dmg_taken > 0 then
        table.insert(lines, "耐久损失：" .. combat.total_dmg_taken)
    end
    if combat.total_fuel_cost > 0 then
        table.insert(lines, "额外油耗：" .. combat.total_fuel_cost)
    end
    if combat.ammo_used > 0 then
        table.insert(lines, "弹药消耗：" .. combat.ammo_used)
    end

    -- 掉货
    for gid, cnt in pairs(combat.cargo_lost) do
        local g = Goods.get(gid)
        local gname = g and g.name or gid
        table.insert(lines, "丢失：" .. gname .. " x" .. cnt)
    end

    -- 击退奖励
    if outcome == "repelled" and combat.enemy.loot_on_repel then
        for _, loot in ipairs(combat.enemy.loot_on_repel) do
            if math.random() < loot.chance then
                table.insert(lines, "缴获：" .. (Goods.get(loot.id) and Goods.get(loot.id).name or loot.id)
                    .. " x" .. loot.count)
            end
        end
    end

    return {
        title   = title,
        lines   = lines,
        outcome = outcome,
    }
end

-- ============================================================
-- 应用战后效果到游戏状态
-- ============================================================

--- 战斗结束后回写角色状态等
---@param state table
---@param combat table
function M.apply_aftermath(state, combat)
    -- 埋点：击退计数
    if combat.outcome == "repelled" then
        Tracker.count(state, "combats_repelled")
    end

    -- 击退：发放战利品
    if combat.outcome == "repelled" and combat.enemy.loot_on_repel then
        for _, loot in ipairs(combat.enemy.loot_on_repel) do
            if math.random() < loot.chance then
                ItemUse.add(state, loot.id, loot.count)
            end
        end
    end

    -- 重创：施加疲劳
    if combat.outcome == "wrecked" then
        ItemUse.add_status(state, "linli", "fatigued")
    end

    -- 中等以上伤害：可能受伤
    if combat.total_dmg_taken >= 15 then
        if math.random() < 0.4 then
            local target = math.random() < 0.5 and "linli" or "taoxia"
            ItemUse.add_status(state, target, "wounded")
        end
    end

    -- 清除待处理战斗标记
    state.flow.pending_combat = nil
end

return M

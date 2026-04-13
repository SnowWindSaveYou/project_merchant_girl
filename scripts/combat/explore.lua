--- 资源点探索战逻辑
--- 进入 → 搜索（多个搜刮点）→ 遭遇（可能）→ 撤离
--- 核心循环：搜一个箱子 → 判定是否遭遇 → 选择继续或撤离
local Config  = require("combat/combat_config")
local ItemUse = require("economy/item_use")
local Goods   = require("economy/goods")
local Modules = require("truck/modules")

local M = {}

--- 探索状态枚举
M.Phase = {
    INTRO      = "intro",       -- 进入场景描述
    EXPLORING  = "exploring",   -- 正在探索，选择下一步
    LOOTING    = "looting",     -- 搜刮结果展示
    ENCOUNTER  = "encounter",   -- 遭遇敌人
    FIGHTING   = "fighting",    -- 战斗中（回合制简化）
    EXTRACTING = "extracting",  -- 撤离中
    RESULT     = "result",      -- 最终结果
}

-- ============================================================
-- 创建探索实例
-- ============================================================

--- 根据房间 ID 创建探索状态
---@param state table 游戏状态
---@param room_id string|nil 房间模板 ID（nil = 随机选择）
---@return table explore 探索实例
function M.create(state, room_id)
    -- 随机选择房间
    if not room_id then
        local ids = Config.EXPLORE_ROOM_IDS
        room_id = ids[math.random(1, #ids)]
    end

    local template = Config.EXPLORE_ROOMS[room_id]
    if not template then
        room_id = Config.EXPLORE_ROOM_IDS[1]
        template = Config.EXPLORE_ROOMS[room_id]
    end

    -- 构建搜刮点状态
    local crates = {}
    for i, c in ipairs(template.crates) do
        crates[i] = {
            name    = c.name,
            icon    = c.icon,
            loot    = c.loot,
            looted  = false,
            result  = nil,   -- 搜刮后的结果 { items_found }
        }
    end

    -- 构建敌人状态
    local enemies = {}
    for i, e in ipairs(template.enemies) do
        enemies[i] = {
            name = e.name,
            desc = e.desc,
            hp   = e.hp,
            atk  = e.atk,
            alive = true,
        }
    end

    local ammo_count = state.truck.cargo["ammo"] or 0

    -- 体力动态化：基于卡车耐久，雷达加成额外体力
    local base_hp = 40 + math.floor(state.truck.durability * 0.1)
    local radar_bonus = Modules.get_hidden_bonus(state)  -- 0 or 0.15
    local hp_max = math.floor(base_hp * (1 + radar_bonus) + 0.5)

    return {
        room_id     = room_id,
        room        = template,
        phase       = M.Phase.INTRO,

        crates      = crates,
        enemies     = enemies,
        active_enemy = nil,  -- 当前遭遇的敌人索引

        -- 玩家状态
        ammo_available = ammo_count,
        player_hp      = hp_max,
        player_hp_max  = hp_max,

        -- 累计结果
        items_found     = {},  -- { [goods_id] = count } 搜到的（延迟入包）
        items_committed = {},  -- { [goods_id] = count } 最终实际获得的
        total_dmg_taken = 0,
        hazards_faced   = 0,

        -- 进度
        crates_opened  = 0,
        encounters_had = 0,

        -- 最终
        outcome = nil,  -- "success" | "wounded_retreat" | "fled"

        -- 日志
        log = {},
    }
end

-- ============================================================
-- 进入探索
-- ============================================================

function M.start_explore(explore)
    explore.phase = M.Phase.EXPLORING
    table.insert(explore.log, "进入了" .. explore.room.name .. "。")
end

-- ============================================================
-- 获取当前可执行动作
-- ============================================================

--- 返回当前阶段可用的动作列表
---@param state table 游戏状态（用于检查物品库存）
---@param explore table
---@return table[] actions { id, name, icon, desc, available }
function M.get_actions(state, explore)
    local actions = {}

    if explore.phase == M.Phase.EXPLORING then
        -- 列出未搜索的箱子
        for i, crate in ipairs(explore.crates) do
            if not crate.looted then
                table.insert(actions, {
                    id   = "loot_" .. i,
                    name = "搜索" .. crate.name,
                    icon = "📦",
                    desc = "搜刮这个容器",
                    available = true,
                })
            end
        end

        -- 使用医疗包（有医疗包且 HP 未满时可用）
        local med_count = state.truck.cargo["medicine"] or 0
        if med_count > 0 and explore.player_hp < explore.player_hp_max then
            table.insert(actions, {
                id   = "use_medicine",
                name = "使用医疗包",
                icon = "💊",
                desc = "恢复 20 点体力（剩余 " .. med_count .. " 个）",
                available = true,
            })
        end

        -- 撤离选项（始终可用）
        table.insert(actions, {
            id   = "extract",
            name = "撤离",
            icon = "🚪",
            desc = "带着收获安全撤退",
            available = true,
        })

    elseif explore.phase == M.Phase.ENCOUNTER or explore.phase == M.Phase.FIGHTING then
        table.insert(actions, {
            id   = "fight",
            name = "战斗",
            icon = "⚔️",
            desc = "与敌人交战",
            available = true,
        })
        table.insert(actions, {
            id   = "flee",
            name = "逃跑",
            icon = "🏃",
            desc = "放弃搜刮，紧急撤离",
            available = true,
        })
    end

    return actions
end

-- ============================================================
-- 执行动作
-- ============================================================

--- 执行玩家选择的动作
---@param state table 游戏状态
---@param explore table 探索实例
---@param action_id string 动作 ID
---@return table result { narration, phase_changed, finished }
function M.execute_action(state, explore, action_id)
    if action_id == "extract" then
        return M._do_extract(state, explore)
    elseif action_id == "flee" then
        return M._do_flee(state, explore)
    elseif action_id == "fight" then
        return M._do_fight(state, explore)
    elseif action_id == "use_medicine" then
        return M._do_use_medicine(state, explore)
    elseif action_id:sub(1, 5) == "loot_" then
        local idx = tonumber(action_id:sub(6))
        if idx then
            return M._do_loot(state, explore, idx)
        end
    end

    return { narration = "无效操作", phase_changed = false, finished = false }
end

-- ============================================================
-- 使用医疗包
-- ============================================================

function M._do_use_medicine(state, explore)
    local med_count = state.truck.cargo["medicine"] or 0
    if med_count <= 0 then
        return { narration = "没有医疗包了", phase_changed = false, finished = false }
    end
    if explore.player_hp >= explore.player_hp_max then
        return { narration = "体力已满，不需要治疗", phase_changed = false, finished = false }
    end

    ItemUse.consume(state, "medicine", 1)
    local heal = 20
    local old_hp = explore.player_hp
    explore.player_hp = math.min(explore.player_hp_max, explore.player_hp + heal)
    local actual_heal = explore.player_hp - old_hp

    table.insert(explore.log, "使用医疗包（+" .. actual_heal .. " HP）")
    return {
        narration = "💊 使用了一个医疗包，恢复了 " .. actual_heal .. " 点体力。\n当前体力：" .. explore.player_hp .. "/" .. explore.player_hp_max,
        phase_changed = false,
        finished = false,
    }
end

-- ============================================================
-- 搜刮
-- ============================================================

function M._do_loot(state, explore, crate_idx)
    local crate = explore.crates[crate_idx]
    if not crate or crate.looted then
        return { narration = "已经搜过了", phase_changed = false, finished = false }
    end

    crate.looted = true
    explore.crates_opened = explore.crates_opened + 1
    local narration = {}

    -- 掷骰获取物品（延迟入包：先记录到 items_found，结算时才写入 state）
    -- 雷达加成：提高搜刮物发现概率
    local radar_bonus = Modules.get_hidden_bonus(state)  -- 0 or 0.15
    local found = {}
    for _, loot in ipairs(crate.loot) do
        if math.random() < math.min(loot.chance + radar_bonus, 0.95) then
            explore.items_found[loot.id] = (explore.items_found[loot.id] or 0) + loot.count
            local g = Goods.get(loot.id)
            table.insert(found, (g and g.name or loot.id) .. " x" .. loot.count)
        end
    end

    if #found > 0 then
        table.insert(narration, "在" .. crate.name .. "中找到了：")
        for _, item in ipairs(found) do
            table.insert(narration, "  · " .. item)
        end
    else
        table.insert(narration, crate.name .. "里空空如也。")
    end

    crate.result = found

    -- 搜刮后判定是否遭遇危险
    if math.random() < explore.room.hazard_chance then
        -- 随机选一个活着的敌人
        local alive_enemies = {}
        for i, e in ipairs(explore.enemies) do
            if e.alive then table.insert(alive_enemies, i) end
        end

        if #alive_enemies > 0 then
            local enemy_idx = alive_enemies[math.random(1, #alive_enemies)]
            explore.active_enemy = enemy_idx
            explore.phase = M.Phase.ENCOUNTER
            explore.encounters_had = explore.encounters_had + 1
            local enemy = explore.enemies[enemy_idx]
            table.insert(narration, "")
            table.insert(narration, "⚠️ 惊动了" .. enemy.name .. "！")
            table.insert(narration, enemy.desc)
            table.insert(explore.log, "遭遇：" .. enemy.name)

            return {
                narration = table.concat(narration, "\n"),
                phase_changed = true,
                finished = false,
            }
        else
            -- 所有敌人已清除
            table.insert(narration, "周围很安全。")
        end
    end

    -- 检查是否所有箱子都搜过了
    local all_looted = true
    for _, c in ipairs(explore.crates) do
        if not c.looted then all_looted = false; break end
    end
    if all_looted then
        table.insert(narration, "")
        table.insert(narration, "所有可搜索的地方都查看完了。")
    end

    table.insert(explore.log, "搜索：" .. crate.name)
    return {
        narration = table.concat(narration, "\n"),
        phase_changed = false,
        finished = false,
    }
end

-- ============================================================
-- 战斗（简化回合制）
-- ============================================================

function M._do_fight(state, explore)
    local enemy_idx = explore.active_enemy
    if not enemy_idx then
        explore.phase = M.Phase.EXPLORING
        return { narration = "没有敌人", phase_changed = true, finished = false }
    end

    local enemy = explore.enemies[enemy_idx]
    local narration = {}

    -- 玩家攻击（wounded 时战斗力下降）
    local player_atk = Config.EXPLORE_PLAYER_ATK
    if ItemUse.has_status(state, "linli", "wounded") then
        player_atk = math.floor(player_atk * 0.6 + 0.5)
    end
    local taoxia_atk = Config.EXPLORE_NO_AMMO_ATK
    if explore.ammo_available > 0 then
        taoxia_atk = Config.EXPLORE_TAOXIA_ATK
    end
    if ItemUse.has_status(state, "taoxia", "wounded") then
        taoxia_atk = math.floor(taoxia_atk * 0.5 + 0.5)
    end
    local total_atk = player_atk + taoxia_atk

    -- 加入随机浮动
    total_atk = math.floor(total_atk * (0.8 + math.random() * 0.4))

    enemy.hp = enemy.hp - total_atk
    table.insert(narration, "林砾挥动扳手攻击" .. enemy.name .. "！（-" .. total_atk .. " HP）")

    if explore.ammo_available > 0 then
        table.insert(narration, "陶夏开枪掩护。")
    end

    if enemy.hp <= 0 then
        enemy.alive = false
        explore.active_enemy = nil
        explore.phase = M.Phase.EXPLORING
        table.insert(narration, enemy.name .. "被击倒了！")

        -- 弹药消耗
        if explore.ammo_available > 0 then
            ItemUse.consume(state, "ammo", 1)
            explore.ammo_available = explore.ammo_available - 1
        end

        return {
            narration = table.concat(narration, "\n"),
            phase_changed = true,
            finished = false,
        }
    end

    -- 敌人反击
    local enemy_dmg = math.floor(enemy.atk * (0.7 + math.random() * 0.6))
    explore.player_hp = explore.player_hp - enemy_dmg
    explore.total_dmg_taken = explore.total_dmg_taken + enemy_dmg
    table.insert(narration, enemy.name .. "反击！（-" .. enemy_dmg .. " HP）")
    table.insert(narration, "剩余体力：" .. math.max(0, explore.player_hp) .. "/" .. explore.player_hp_max)

    -- 弹药消耗
    if explore.ammo_available > 0 then
        ItemUse.consume(state, "ammo", 1)
        explore.ammo_available = explore.ammo_available - 1
    end

    -- 玩家 HP 耗尽 → 强制撤离
    if explore.player_hp <= 0 then
        explore.phase = M.Phase.RESULT
        explore.outcome = "wounded_retreat"

        -- 负伤撤退只保留少量搜刮物
        M._commit_loot(state, explore, 0.3)

        table.insert(narration, "")
        table.insert(narration, "伤势过重，不得不紧急撤离！")

        -- 映射到货车耐久
        local durability_loss = math.floor(explore.total_dmg_taken * 0.5)
        state.truck.durability = math.max(1, state.truck.durability - durability_loss)
        ItemUse.add_status(state, "linli", "wounded")

        return {
            narration = table.concat(narration, "\n"),
            phase_changed = true,
            finished = true,
        }
    end

    explore.phase = M.Phase.FIGHTING

    return {
        narration = table.concat(narration, "\n"),
        phase_changed = false,
        finished = false,
    }
end

-- ============================================================
-- 逃跑
-- ============================================================

function M._do_flee(state, explore)
    explore.phase = M.Phase.RESULT
    explore.outcome = "fled"

    -- 逃跑只保留一半搜刮物
    M._commit_loot(state, explore, 0.5)

    local narration = { "紧急撤离！部分物资散落在逃跑途中。" }

    -- 逃跑受到一次攻击
    if explore.active_enemy then
        local enemy = explore.enemies[explore.active_enemy]
        if enemy and enemy.alive then
            local dmg = math.floor(enemy.atk * 0.5)
            explore.total_dmg_taken = explore.total_dmg_taken + dmg
            state.truck.durability = math.max(1, state.truck.durability - dmg)
            table.insert(narration, "逃跑时被" .. enemy.name .. "击中（-" .. dmg .. " 耐久）")
        end
    end

    table.insert(explore.log, "逃跑撤离")
    return {
        narration = table.concat(narration, "\n"),
        phase_changed = true,
        finished = true,
    }
end

-- ============================================================
-- 搜刮物提交（延迟入包：按比例实际写入 state）
-- ============================================================

--- 将搜刮物按 fraction 比例写入游戏状态
---@param state table
---@param explore table
---@param fraction number 0~1，1.0=全部保留，0.5=保留一半
function M._commit_loot(state, explore, fraction)
    explore.items_committed = {}
    for gid, count in pairs(explore.items_found) do
        local actual = math.floor(count * fraction + 0.5)
        if actual > 0 then
            ItemUse.add(state, gid, actual)
            explore.items_committed[gid] = actual
        end
    end
end

-- ============================================================
-- 正常撤离
-- ============================================================

function M._do_extract(state, explore)
    explore.phase = M.Phase.RESULT
    explore.outcome = "success"

    -- 提交全部搜刮物
    M._commit_loot(state, explore, 1.0)

    -- 映射探索中受到的伤害到货车耐久
    if explore.total_dmg_taken > 0 then
        local durability_loss = math.floor(explore.total_dmg_taken * 0.3)
        state.truck.durability = math.max(1, state.truck.durability - durability_loss)
    end

    local narration = { "安全撤离了" .. explore.room.name .. "。" }
    if next(explore.items_committed) then
        table.insert(narration, "本次收获：")
        for gid, cnt in pairs(explore.items_committed) do
            local g = Goods.get(gid)
            table.insert(narration, "  · " .. (g and g.name or gid) .. " x" .. cnt)
        end
    else
        table.insert(narration, "一无所获。")
    end

    table.insert(explore.log, "安全撤离")
    return {
        narration = table.concat(narration, "\n"),
        phase_changed = true,
        finished = true,
    }
end

-- ============================================================
-- 获取探索摘要
-- ============================================================

---@param explore table
---@return table summary { title, lines, outcome }
function M.get_summary(explore)
    local title, lines = "", {}
    local outcome = explore.outcome or "success"

    if outcome == "success" then
        title = "探索完成"
        table.insert(lines, "安全完成了" .. explore.room.name .. "的探索。")
    elseif outcome == "wounded_retreat" then
        title = "负伤撤退"
        table.insert(lines, "在" .. explore.room.name .. "中受了重伤，被迫撤退。")
    elseif outcome == "fled" then
        title = "紧急撤离"
        table.insert(lines, "面对危险，选择了紧急撤离。")
    end

    -- 物品收获（显示实际提交的物品）
    local committed = explore.items_committed or {}
    if next(committed) then
        table.insert(lines, "")
        table.insert(lines, "获得物资：")
        for gid, cnt in pairs(committed) do
            local g = Goods.get(gid)
            local found_cnt = explore.items_found[gid] or cnt
            local suffix = ""
            if found_cnt > cnt then
                suffix = "（搜到 " .. found_cnt .. "，丢失 " .. (found_cnt - cnt) .. "）"
            end
            table.insert(lines, "  " .. (g and g.name or gid) .. " x" .. cnt .. suffix)
        end
    elseif next(explore.items_found) then
        -- 搜到了但全部丢失
        table.insert(lines, "")
        table.insert(lines, "搜到的物资全部遗落……")
    end

    if explore.total_dmg_taken > 0 then
        table.insert(lines, "")
        table.insert(lines, "受到伤害：" .. explore.total_dmg_taken)
    end

    return {
        title   = title,
        lines   = lines,
        outcome = outcome,
    }
end

--- 战后效果回写
---@param state table
---@param explore table
function M.apply_aftermath(state, explore)
    -- 中毒效果（军事哨站特有）
    if explore.room_id == "military_outpost" and explore.encounters_had > 0 then
        if math.random() < 0.2 then
            ItemUse.add_status(state, "linli", "poisoned")
        end
    end
end

return M

--- 角色技能系统
--- 个人技能（基于埋点计数器解锁）+ 协同技能（基于关系等级解锁）
local Modules = require("truck/modules")

local M = {}

-- ============================================================
-- 个人技能定义
-- ============================================================

M.PERSONAL = {
    -- ── 林砾 ──
    precision_repair = {
        owner   = "linli",
        name    = "精密检修",
        desc    = "出发前额外降低 8% 故障率",
        icon    = "🔧",
        unlock  = function(state)
            return (state.stats.combats_fought or 0) >= 3
        end,
        unlock_desc = "完成 3 次战斗",
        unlock_key  = "combats_fought",
        unlock_need = 3,
        effects = { fault_reduction = 0.08 },
    },
    static_calc = {
        owner   = "linli",
        name    = "静态测算",
        desc    = "长途路线时间误差降低，离线收益更稳定",
        icon    = "📐",
        unlock  = function(state)
            return (state.stats.total_trips or 0) >= 5
        end,
        unlock_desc = "完成 5 趟行程",
        unlock_key  = "total_trips",
        unlock_need = 5,
        effects = { offline_stability = true },
    },
    load_balance = {
        owner   = "linli",
        name    = "载重平衡",
        desc    = "高载重状态下燃料消耗额外 -10%",
        icon    = "⚖️",
        unlock  = function(state)
            return Modules.get_level(state, "cargo_bay") >= 3
        end,
        unlock_desc = "货舱扩容达到 Lv3",
        unlock_key  = "cargo_bay_lv",
        unlock_need = 3,
        effects = { fuel_discount = 0.10 },
    },

    -- ── 陶夏 ──
    bargain = {
        owner   = "taoxia",
        name    = "临场砍价",
        desc    = "买入价格 -5%，卖出价格 +5%",
        icon    = "💰",
        unlock  = function(state)
            return (state.stats.trades_completed or 0) >= 10
        end,
        unlock_desc = "完成 10 次交易",
        unlock_key  = "trades_completed",
        unlock_need = 10,
        effects = { buy_discount = 0.05, sell_bonus = 0.05 },
    },
    scav_sense = {
        owner   = "taoxia",
        name    = "废土嗅觉",
        desc    = "隐藏补给点与特殊事件出现率提升",
        icon    = "👃",
        unlock  = function(state)
            return (state.stats.events_triggered or 0) >= 8
        end,
        unlock_desc = "触发 8 次随机事件",
        unlock_key  = "events_triggered",
        unlock_need = 8,
        effects = { event_bonus = 0.15 },
    },
    preemptive = {
        owner   = "taoxia",
        name    = "先声夺人",
        desc    = "遭遇劫掠时货物保全率额外 +15%",
        icon    = "⚡",
        unlock  = function(state)
            return (state.stats.combats_repelled or 0) >= 5
        end,
        unlock_desc = "击退 5 次追兵",
        unlock_key  = "combats_repelled",
        unlock_need = 5,
        effects = { escape_bonus = 0.15 },
    },
}

-- 按角色分组的 ID 列表（UI 迭代用）
M.PERSONAL_ORDER = {
    linli  = { "precision_repair", "static_calc", "load_balance" },
    taoxia = { "bargain", "scav_sense", "preemptive" },
}

-- ============================================================
-- 协同技能定义
-- ============================================================

M.SYNERGY = {
    synergy_repair = {
        name    = "默契配合",
        desc    = "据点修理量 +5",
        icon    = "🤝",
        relation_req = 20,
        effects = { repair_bonus = 5 },
    },
    synergy_guard = {
        name    = "协同警戒",
        desc    = "战斗逃脱阈值 -10%",
        icon    = "🛡️",
        relation_req = 40,
        effects = { escape_threshold_reduction = 0.10 },
    },
    synergy_trade = {
        name    = "心有灵犀",
        desc    = "买卖价格各再优 3%",
        icon    = "✨",
        relation_req = 60,
        effects = { buy_discount = 0.03, sell_bonus = 0.03 },
    },
}

M.SYNERGY_ORDER = { "synergy_repair", "synergy_guard", "synergy_trade" }

-- ============================================================
-- 状态初始化（兼容旧存档）
-- ============================================================

--- 确保 state.character 有 skills 字段（旧存档兼容）
---@param state table
local function ensure_fields(state)
    for _, cid in ipairs({ "linli", "taoxia" }) do
        if not state.character[cid].skills then
            state.character[cid].skills = {}
        end
    end
    if not state.character.synergy_skills then
        state.character.synergy_skills = {}
    end
end

-- ============================================================
-- 核心 API
-- ============================================================

--- 检查并解锁满足条件的技能
--- 返回本次新解锁的技能列表 { { id, name, type } }
---@param state table
---@return table[] newly_unlocked
function M.check_unlocks(state)
    ensure_fields(state)
    local newly = {}

    -- 个人技能
    for sid, def in pairs(M.PERSONAL) do
        local char = state.character[def.owner]
        if not char.skills[sid] and def.unlock(state) then
            char.skills[sid] = true
            table.insert(newly, { id = sid, name = def.name, type = "personal", owner = def.owner })
            print("[Skills] Unlocked personal: " .. def.name .. " (" .. def.owner .. ")")
        end
    end

    -- 协同技能（取两人关系的较低值）
    local min_relation = math.min(
        state.character.linli.relation or 0,
        state.character.taoxia.relation or 0
    )
    for sid, def in pairs(M.SYNERGY) do
        if not state.character.synergy_skills[sid] and min_relation >= def.relation_req then
            state.character.synergy_skills[sid] = true
            table.insert(newly, { id = sid, name = def.name, type = "synergy" })
            print("[Skills] Unlocked synergy: " .. def.name)
        end
    end

    return newly
end

--- 查询某技能是否已解锁
---@param state table
---@param skill_id string
---@return boolean
function M.is_unlocked(state, skill_id)
    ensure_fields(state)
    -- 个人技能
    local def = M.PERSONAL[skill_id]
    if def then
        return state.character[def.owner].skills[skill_id] == true
    end
    -- 协同技能
    if M.SYNERGY[skill_id] then
        return state.character.synergy_skills[skill_id] == true
    end
    return false
end

--- 获取全部技能及其当前状态（UI 用）
---@param state table
---@return table { personal = { linli = {...}, taoxia = {...} }, synergy = {...} }
function M.get_all(state)
    ensure_fields(state)
    local result = {
        personal = { linli = {}, taoxia = {} },
        synergy = {},
    }

    -- 个人技能
    for _, cid in ipairs({ "linli", "taoxia" }) do
        for _, sid in ipairs(M.PERSONAL_ORDER[cid]) do
            local def = M.PERSONAL[sid]
            local unlocked = state.character[cid].skills[sid] == true
            -- 计算当前进度
            local current = 0
            if sid == "load_balance" then
                current = Modules.get_level(state, "cargo_bay")
            elseif def.unlock_key then
                current = state.stats[def.unlock_key] or 0
            end
            table.insert(result.personal[cid], {
                id          = sid,
                name        = def.name,
                desc        = def.desc,
                icon        = def.icon,
                unlocked    = unlocked,
                unlock_desc = def.unlock_desc,
                current     = current,
                need        = def.unlock_need,
            })
        end
    end

    -- 协同技能
    local min_relation = math.min(
        state.character.linli.relation or 0,
        state.character.taoxia.relation or 0
    )
    for _, sid in ipairs(M.SYNERGY_ORDER) do
        local def = M.SYNERGY[sid]
        local unlocked = state.character.synergy_skills[sid] == true
        table.insert(result.synergy, {
            id           = sid,
            name         = def.name,
            desc         = def.desc,
            icon         = def.icon,
            unlocked     = unlocked,
            relation_req = def.relation_req,
            relation_cur = min_relation,
        })
    end

    return result
end

-- ============================================================
-- 效果查询 API（各系统调用）
-- ============================================================

--- 获取买入折扣总和（bargain + synergy_trade）
---@param state table
---@return number discount 0~1 之间
function M.get_buy_discount(state)
    ensure_fields(state)
    local d = 0
    if M.is_unlocked(state, "bargain") then
        d = d + M.PERSONAL.bargain.effects.buy_discount
    end
    if M.is_unlocked(state, "synergy_trade") then
        d = d + M.SYNERGY.synergy_trade.effects.buy_discount
    end
    return d
end

--- 获取卖出加成总和（bargain + synergy_trade）
---@param state table
---@return number bonus 0~1 之间
function M.get_sell_bonus(state)
    ensure_fields(state)
    local b = 0
    if M.is_unlocked(state, "bargain") then
        b = b + M.PERSONAL.bargain.effects.sell_bonus
    end
    if M.is_unlocked(state, "synergy_trade") then
        b = b + M.SYNERGY.synergy_trade.effects.sell_bonus
    end
    return b
end

--- 获取燃料折扣（load_balance，仅高载重时生效）
---@param state table
---@return number discount 0 或 0.10
function M.get_fuel_discount(state)
    ensure_fields(state)
    if not M.is_unlocked(state, "load_balance") then return 0 end
    -- 检查是否高载重（超过 50% 仓位）
    local used = 0
    for _, v in pairs(state.truck.cargo) do used = used + v end
    if used >= state.truck.cargo_slots * 0.5 then
        return M.PERSONAL.load_balance.effects.fuel_discount
    end
    return 0
end

--- 获取逃脱阈值缩减比例（preemptive + synergy_guard）
---@param state table
---@return number reduction 0~1
function M.get_escape_reduction(state)
    ensure_fields(state)
    local r = 0
    if M.is_unlocked(state, "preemptive") then
        r = r + M.PERSONAL.preemptive.effects.escape_bonus
    end
    if M.is_unlocked(state, "synergy_guard") then
        r = r + M.SYNERGY.synergy_guard.effects.escape_threshold_reduction
    end
    return r
end

--- 获取据点修理加成（synergy_repair）
---@param state table
---@return number bonus 0 或 5
function M.get_repair_bonus(state)
    ensure_fields(state)
    if M.is_unlocked(state, "synergy_repair") then
        return M.SYNERGY.synergy_repair.effects.repair_bonus
    end
    return 0
end

--- 获取事件发现加成（scav_sense）
---@param state table
---@return number bonus 0 或 0.15
function M.get_event_bonus(state)
    ensure_fields(state)
    if M.is_unlocked(state, "scav_sense") then
        return M.PERSONAL.scav_sense.effects.event_bonus
    end
    return 0
end

return M

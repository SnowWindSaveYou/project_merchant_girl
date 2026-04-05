--- 物品使用系统
--- 定义可消耗物品的使用效果，并提供统一的使用接口
--- 同时包含角色负面状态管理
local Goods = require("economy/goods")

local M = {}

-- ============================================================
-- 角色负面状态定义与辅助
-- ============================================================

M.STATUS_DEFS = {
    fatigued    = { name = "疲劳",   desc = "行驶速度 -10%，事件判定略差" },
    wounded     = { name = "受伤",   desc = "对应角色技能暂时失效" },
    poisoned    = { name = "中毒",   desc = "每段行程额外消耗耐久 -5" },
    demoralized = { name = "士气低落", desc = "好感获取 -20%，交易价格略差" },
}

--- 为角色施加负面状态（同一状态不叠加）
---@param state table
---@param char_id string "linli" | "taoxia"
---@param status_id string
function M.add_status(state, char_id, status_id)
    local char = state.character[char_id]
    if not char then return end
    if not char.status then char.status = {} end
    for _, s in ipairs(char.status) do
        if s == status_id then return end
    end
    table.insert(char.status, status_id)
end

--- 清除角色的指定负面状态
---@param state table
---@param char_id string
---@param status_id string
function M.clear_status(state, char_id, status_id)
    local char = state.character[char_id]
    if not char or not char.status then return end
    for i, s in ipairs(char.status) do
        if s == status_id then
            table.remove(char.status, i)
            return
        end
    end
end

--- 清除角色全部负面状态（据点休整）
---@param state table
---@param char_id string
function M.clear_all_status(state, char_id)
    local char = state.character[char_id]
    if not char then return end
    char.status = {}
end

--- 检查角色是否有指定状态
---@param state table
---@param char_id string
---@param status_id string
---@return boolean
function M.has_status(state, char_id, status_id)
    local char = state.character[char_id]
    if not char or not char.status then return false end
    for _, s in ipairs(char.status) do
        if s == status_id then return true end
    end
    return false
end

--- 获取所有角色的负面状态摘要
---@param state table
---@return table[] { char_id, char_name, statuses }
function M.get_all_statuses(state)
    local result = {}
    for _, cid in ipairs({ "linli", "taoxia" }) do
        local char = state.character[cid]
        if char and char.status and #char.status > 0 then
            table.insert(result, {
                char_id   = cid,
                char_name = cid == "linli" and "林砾" or "陶夏",
                statuses  = char.status,
            })
        end
    end
    return result
end

-- ============================================================
-- 可使用物品定义
-- ============================================================

M.USABLE = {
    fuel_cell = {
        action_name = "补充燃料",
        desc        = "恢复 25 点燃料",
        ---@param state table
        ---@return boolean, string
        effect = function(state)
            if state.truck.fuel >= state.truck.fuel_max then
                return false, "燃料已满"
            end
            state.truck.fuel = math.min(state.truck.fuel_max, state.truck.fuel + 25)
            return true, "燃料 +25"
        end,
    },
    metal_scrap = {
        action_name = "应急修补",
        desc        = "恢复 15 点耐久",
        ---@param state table
        ---@return boolean, string
        effect = function(state)
            if state.truck.durability >= state.truck.durability_max then
                return false, "耐久已满"
            end
            state.truck.durability = math.min(state.truck.durability_max, state.truck.durability + 15)
            return true, "耐久 +15"
        end,
    },
    medicine = {
        action_name = "使用医疗包",
        desc        = "清除一个角色负面状态",
        ---@param state table
        ---@return boolean, string
        effect = function(state)
            for _, name in ipairs({ "linli", "taoxia" }) do
                local char = state.character[name]
                if char and char.status and #char.status > 0 then
                    local removed = table.remove(char.status, 1)
                    local charName = name == "linli" and "林砾" or "陶夏"
                    local statusDef = M.STATUS_DEFS[removed]
                    local statusName = statusDef and statusDef.name or removed
                    return true, charName .. " 清除了「" .. statusName .. "」"
                end
            end
            return false, "没有需要治疗的状态"
        end,
    },
}

-- ============================================================
-- 公共接口
-- ============================================================

--- 检查物品是否可使用
---@param goods_id string
---@return boolean
function M.is_usable(goods_id)
    return M.USABLE[goods_id] ~= nil
end

--- 获取物品使用信息
---@param goods_id string
---@return table|nil
function M.get_info(goods_id)
    return M.USABLE[goods_id]
end

--- 使用物品（从货舱消耗 1 个并执行效果）
---@param state table
---@param goods_id string
---@return boolean success
---@return string message
function M.use(state, goods_id)
    local info = M.USABLE[goods_id]
    if not info then
        return false, "该物品不可使用"
    end

    local held = state.truck.cargo[goods_id] or 0
    if held <= 0 then
        return false, "没有该物品"
    end

    local ok, msg = info.effect(state)
    if not ok then
        return false, msg
    end

    state.truck.cargo[goods_id] = held - 1
    if state.truck.cargo[goods_id] <= 0 then
        state.truck.cargo[goods_id] = nil
    end

    return true, msg
end

--- 从货舱消耗指定数量的物品（事件系统用）
---@param state table
---@param goods_id string
---@param count number
---@return boolean
function M.consume(state, goods_id, count)
    local held = state.truck.cargo[goods_id] or 0
    if held < count then
        return false
    end
    state.truck.cargo[goods_id] = held - count
    if state.truck.cargo[goods_id] <= 0 then
        state.truck.cargo[goods_id] = nil
    end
    return true
end

--- 向货舱添加指定数量的物品
---@param state table
---@param goods_id string
---@param count number
---@return boolean
function M.add(state, goods_id, count)
    local g = Goods.get(goods_id)
    if not g then return false end
    local held = state.truck.cargo[goods_id] or 0
    state.truck.cargo[goods_id] = math.min(held + count, g.stack_limit)
    return true
end

return M

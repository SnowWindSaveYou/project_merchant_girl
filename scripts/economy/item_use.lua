--- 物品使用系统
--- 定义可消耗物品的使用效果，并提供统一的使用接口
local Goods = require("economy/goods")

local M = {}

--- 可使用物品定义
--- effect(state) 返回 true 表示使用成功，false 表示条件不满足
M.USABLE = {
    fuel_cell = {
        action_name = "补充燃料",
        desc        = "恢复 25 点燃料",
        ---@param state table
        ---@return boolean
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
        ---@return boolean
        effect = function(state)
            if state.truck.durability >= state.truck.durability_max then
                return false, "耐久已满"
            end
            state.truck.durability = math.min(state.truck.durability_max, state.truck.durability + 15)
            return true, "耐久 +15"
        end,
    },
    -- medicine 暂时只定义，负面状态系统实现后再生效
    -- medicine = {
    --     action_name = "使用医疗包",
    --     desc        = "清除一个负面状态",
    --     effect = function(state) ... end,
    -- },
}

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

    -- 消耗 1 个
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

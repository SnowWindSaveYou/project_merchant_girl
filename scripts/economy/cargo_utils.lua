--- 货舱容量与委托货物工具
--- 集中管理仓位计算、委托追踪，供 UI 和逻辑模块共用
local M = {}

--- 当前货舱总占用量
---@param state table
---@return number
function M.get_cargo_used(state)
    local total = 0
    for _, count in pairs(state.truck.cargo) do
        if count > 0 then total = total + count end
    end
    return total
end

--- 剩余空闲仓位
---@param state table
---@return number
function M.get_cargo_free(state)
    return state.truck.cargo_slots - M.get_cargo_used(state)
end

--- 某物品的委托数量
---@param state table
---@param goods_id string
---@return number
function M.get_committed(state, goods_id)
    if not state.truck.committed then return 0 end
    return state.truck.committed[goods_id] or 0
end

--- 全部委托货物总量
---@param state table
---@return number
function M.get_total_committed(state)
    local total = 0
    if not state.truck.committed then return 0 end
    for _, count in pairs(state.truck.committed) do
        if count > 0 then total = total + count end
    end
    return total
end

--- 某物品当前持有量是否低于委托量
---@param state table
---@param goods_id string
---@return boolean
function M.is_below_committed(state, goods_id)
    local held = state.truck.cargo[goods_id] or 0
    local committed = M.get_committed(state, goods_id)
    return committed > 0 and held < committed
end

--- 是否存在任何物品低于委托量
---@param state table
---@return boolean
function M.has_any_shortage(state)
    if not state.truck.committed then return false end
    for gid, committed in pairs(state.truck.committed) do
        if committed > 0 then
            local held = state.truck.cargo[gid] or 0
            if held < committed then return true end
        end
    end
    return false
end

--- 增加委托记录
---@param state table
---@param goods_id string
---@param count number
function M.add_committed(state, goods_id, count)
    if not state.truck.committed then state.truck.committed = {} end
    state.truck.committed[goods_id] = (state.truck.committed[goods_id] or 0) + count
end

--- 减少委托记录（下限 0，归零时移除键）
---@param state table
---@param goods_id string
---@param count number
function M.remove_committed(state, goods_id, count)
    if not state.truck.committed then return end
    local cur = state.truck.committed[goods_id] or 0
    cur = cur - count
    if cur <= 0 then
        state.truck.committed[goods_id] = nil
    else
        state.truck.committed[goods_id] = cur
    end
end

return M

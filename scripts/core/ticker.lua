--- 时间推进器
--- 负责在线 dt 推进和离线秒数推进
local RoutePlanner = require("map/route_planner")
local ItemUse      = require("economy/item_use")
local Modules      = require("truck/modules")

local M = {}

--- 检查任一角色是否有指定状态
---@param state table
---@param status_id string
---@return boolean
local function anyone_has_status(state, status_id)
    return ItemUse.has_status(state, "linli", status_id)
        or ItemUse.has_status(state, "taoxia", status_id)
end

--- 每帧推进
function M.advance(state, dt)
    state.stats.play_time = state.stats.play_time + dt

    -- 行驶中消耗燃料（引擎模块可降低燃耗）
    if state.flow.phase == "travelling" then
        local fuel_rate = 0.3 * Modules.get_fuel_mult(state)
        state.truck.fuel = math.max(0, state.truck.fuel - fuel_rate * dt)
    end
end

--- 获取行驶速度倍率（引擎模块加速 × 疲劳减速）
---@param state table
---@return number multiplier
function M.get_speed_mult(state)
    local mult = Modules.get_speed_mult(state)
    if anyone_has_status(state, "fatigued") then
        mult = mult * 0.9
    end
    return mult
end

--- 离线推进（返回结果表）
function M.advance_offline(state, elapsed_sec)
    if state.flow.phase ~= "travelling" then return nil end
    local plan = state.flow.route_plan
    if not plan then return nil end

    -- 燃料消耗（引擎模块可降低燃耗）
    local fuel_rate = 0.3 * Modules.get_fuel_mult(state)
    state.truck.fuel = math.max(0, state.truck.fuel - fuel_rate * elapsed_sec)

    -- 模拟推进（按秒步进，检测到达）
    local arrivals = {}
    local remaining = elapsed_sec
    local step = 1.0 -- 每步 1 秒

    while remaining > 0 do
        local dt = math.min(step, remaining)
        remaining = remaining - dt

        local arrival = RoutePlanner.advance(plan, dt)
        if arrival then
            table.insert(arrivals, arrival)
            if arrival.finished then
                state.flow.phase = "arrival"
                break
            end
        end
    end

    return {
        elapsed_sec = elapsed_sec,
        arrivals = arrivals,
        arrived = state.flow.phase == "arrival",
    }
end

return M

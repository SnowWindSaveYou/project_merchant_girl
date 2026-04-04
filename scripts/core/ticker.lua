--- 时间推进器
--- 负责在线 dt 推进和离线秒数推进
local RoutePlanner = require("map/route_planner")

local M = {}

--- 每帧推进
function M.advance(state, dt)
    state.stats.play_time = state.stats.play_time + dt

    -- 行驶中消耗燃料
    if state.flow.phase == "travelling" then
        local fuel_rate = 0.3 -- 每秒消耗燃料
        state.truck.fuel = math.max(0, state.truck.fuel - fuel_rate * dt)
    end
end

--- 离线推进（返回结果表）
function M.advance_offline(state, elapsed_sec)
    if state.flow.phase ~= "travelling" then return nil end
    local plan = state.flow.route_plan
    if not plan then return nil end

    -- 燃料消耗
    local fuel_rate = 0.3
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

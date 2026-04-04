--- 离线时间补偿
local M = {}

local MAX_OFFLINE_SEC = 8 * 3600 -- 最多补偿 8 小时

--- 计算离线了多少秒
function M.calculate(state)
    if not state.timestamp then return 0 end
    local now = os.time()
    local elapsed = now - state.timestamp
    if elapsed < 0 then elapsed = 0 end
    return math.min(elapsed, MAX_OFFLINE_SEC)
end

--- 应用离线补偿，返回结果表或 nil（不足 5 秒则跳过）
function M.apply(state, Ticker)
    local elapsed = M.calculate(state)
    if elapsed <= 5 then return nil end

    local arrived = Ticker.advance_offline(state, elapsed)

    return {
        elapsed_sec = elapsed,
        arrived     = arrived,
    }
end

return M

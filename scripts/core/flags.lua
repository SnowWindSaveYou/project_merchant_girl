--- 旗标（Flag）系统
--- 命名约定：flag_{模块}_{描述}，例如 flag_doll_resolved、flag_night_market_found
local M = {}

function M.set(state, flag_id)
    state.flags[flag_id] = true
end

function M.has(state, flag_id)
    return state.flags[flag_id] == true
end

function M.clear(state, flag_id)
    state.flags[flag_id] = nil
end

return M

--- 战斗结果处理
--- 统一入口：战斗结束后回写主循环状态
local Ambush  = require("combat/ambush")
local Explore = require("combat/explore")

local M = {}

--- 处理车载迎击结果
---@param state table
---@param combat table ambush 战斗实例
---@return table summary
function M.finalize_ambush(state, combat)
    -- 应用战后效果
    Ambush.apply_aftermath(state, combat)
    -- 生成摘要
    return Ambush.get_summary(combat)
end

--- 处理资源点探索结果
---@param state table
---@param explore table explore 战斗实例
---@return table summary
function M.finalize_explore(state, explore)
    -- 应用战后效果
    Explore.apply_aftermath(state, explore)
    -- 生成摘要
    return Explore.get_summary(explore)
end

return M

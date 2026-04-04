--- Shell 组装器
--- 统一管理全局顶部状态栏 + 底部导航栏，包裹各页面内容
local UI          = require("urhox-libs/UI")
local ShellTop    = require("ui/shell_top")
local ShellBottom = require("ui/shell_bottom")
local Theme       = require("ui/theme")

local M = {}

--- 需要 Shell 包裹的页面
local SHELLED = {
    home       = true,
    map        = true,
    orders     = true,
    cargo      = true,
    shop       = true,
    route_plan = true,
}

--- 页面名 → 底栏高亮 tab 映射
local SCREEN_TO_TAB = {
    home       = "home",
    map        = "map",
    orders     = "orders",
    cargo      = "cargo",
    shop       = "home",        -- 交易所从据点进入，属于首页 tab
    route_plan = "orders",      -- 路线规划是委托流程的延续
}

--- 判断页面是否需要 Shell 包裹
---@param screenName string
---@return boolean
function M.is_shelled(screenName)
    return SHELLED[screenName] == true
end

--- 用 Shell 包裹页面内容
---@param state table
---@param content table 页面 create() 返回的 widget
---@param screenName string
---@param router table
---@return table 完整 Shell widget 树
function M.create(state, content, screenName, router)
    local activeTab = SCREEN_TO_TAB[screenName] or "home"

    return UI.Panel {
        id = "shellRoot",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%",
                children = {
                    ShellTop.create(state),
                    UI.Panel {
                        id = "shellContent",
                        width = "100%", flexGrow = 1, flexShrink = 1,
                        children = { content },
                    },
                    ShellBottom.create(state, activeTab, screenName, router),
                },
            },
        },
    }
end

--- 每帧更新顶栏数值
---@param state table
---@param dt number
function M.update(state, dt)
    local root = UI.GetRoot()
    if not root then return end

    local creditsLbl = root:FindById("shellCredits")
    if creditsLbl then creditsLbl:SetText("$ " .. tostring(state.economy.credits)) end

    local fuelPct = math.floor(state.truck.fuel)
    local fuelLbl = root:FindById("shellFuelVal")
    if fuelLbl then
        fuelLbl:SetText(fuelPct .. "%")
        fuelLbl:SetFontColor(fuelPct > 30 and Theme.colors.text_secondary or Theme.colors.danger)
    end

    local durPct = math.floor(state.truck.durability)
    local durLbl = root:FindById("shellDurVal")
    if durLbl then
        durLbl:SetText(durPct .. "%")
        durLbl:SetFontColor(durPct > 30 and Theme.colors.text_secondary or Theme.colors.danger)
    end

    local cargoUsed = 0
    for _, count in pairs(state.truck.cargo) do
        if count > 0 then cargoUsed = cargoUsed + count end
    end
    local cargoLbl = root:FindById("shellCargoVal")
    if cargoLbl then cargoLbl:SetText(cargoUsed .. "/" .. state.truck.cargo_slots) end
end

return M

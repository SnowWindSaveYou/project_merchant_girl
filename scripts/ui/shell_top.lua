--- 全局顶部状态栏
--- 显示信用点、燃料、耐久、货舱容量，Shell 每帧通过 FindById 更新数值
local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")

local M = {}

--- 创建顶部状态栏
---@param state table
---@return table widget
function M.create(state)
    local fuelPct = math.floor(state.truck.fuel)
    local durPct  = math.floor(state.truck.durability)
    local cargoUsed = 0
    for _, count in pairs(state.truck.cargo) do
        if count > 0 then cargoUsed = cargoUsed + count end
    end

    return UI.Panel {
        id = "shellStatusBar",
        width = "100%", height = 40,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = Theme.colors.bg_secondary,
        borderBottomWidth = 1, borderColor = Theme.colors.border,
        children = {
            UI.Label {
                id = "shellCredits",
                text = "$ " .. tostring(state.economy.credits),
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.accent,
            },
            UI.Panel { flexGrow = 1 },
            M.chip("燃料", fuelPct .. "%", "shellFuelVal",
                fuelPct > 30 and Theme.colors.text_secondary or Theme.colors.danger),
            M.chip("耐久", durPct .. "%", "shellDurVal",
                durPct > 30 and Theme.colors.text_secondary or Theme.colors.danger),
            M.chip("货舱", cargoUsed .. "/" .. state.truck.cargo_slots,
                "shellCargoVal", Theme.colors.text_secondary),
        },
    }
end

--- 状态栏小标签
function M.chip(label, value, valueId, color)
    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        marginLeft = 12, gap = 3,
        children = {
            UI.Label {
                text = label,
                fontSize = 10,
                fontColor = Theme.colors.text_dim,
            },
            UI.Label {
                id = valueId,
                text = value,
                fontSize = Theme.sizes.font_small,
                fontColor = color,
            },
        },
    }
end

return M

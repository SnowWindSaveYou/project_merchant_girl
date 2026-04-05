--- 全局顶部状态栏
--- 显示信用点、燃料、耐久、货舱容量、角色状态
--- 旅行中：额外显示旅行进度条、目的地、剩余时间
--- Shell 每帧通过 FindById 更新数值
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local CargoUtils   = require("economy/cargo_utils")
local ItemUse      = require("economy/item_use")
local Flow         = require("core/flow")
local RoutePlanner = require("map/route_planner")
local Graph        = require("map/world_graph")

local M = {}

-- 状态图标映射
local STATUS_ICONS = {
    fatigued    = "😴",
    wounded     = "🩹",
    poisoned    = "☠",
    demoralized = "😞",
}

--- 创建顶部状态栏
---@param state table
---@return table widget
function M.create(state)
    local fuelPct = math.floor(state.truck.fuel)
    local durPct  = math.floor(state.truck.durability)
    local cargoUsed = CargoUtils.get_cargo_used(state)
    local hasShortage = CargoUtils.has_any_shortage(state)

    -- 收集角色状态图标
    local statusIcons = {}
    for _, cid in ipairs({ "linli", "taoxia" }) do
        local char = state.character[cid]
        if char and char.status then
            for _, sid in ipairs(char.status) do
                local icon = STATUS_ICONS[sid]
                if icon then
                    table.insert(statusIcons, icon)
                end
            end
        end
    end
    local statusText = table.concat(statusIcons, "")

    local barChildren = {
        UI.Label {
            id = "shellCredits",
            text = "$ " .. tostring(state.economy.credits),
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.accent,
        },
    }

    -- 有负面状态时显示图标
    if #statusIcons > 0 then
        table.insert(barChildren, UI.Label {
            id = "shellStatusIcons",
            text = statusText,
            fontSize = 12,
            fontColor = Theme.colors.warning,
            marginLeft = 8,
        })
    end

    table.insert(barChildren, UI.Panel { flexGrow = 1 })
    table.insert(barChildren, M.chip("燃料", fuelPct .. "%", "shellFuelVal",
        fuelPct > 30 and Theme.colors.text_secondary or Theme.colors.danger))
    table.insert(barChildren, M.chip("耐久", durPct .. "%", "shellDurVal",
        durPct > 30 and Theme.colors.text_secondary or Theme.colors.danger))
    table.insert(barChildren, M.chip("货舱", cargoUsed .. "/" .. state.truck.cargo_slots,
        "shellCargoVal", hasShortage and Theme.colors.danger or Theme.colors.text_secondary))

    local statusBar = UI.Panel {
        id = "shellStatusBar",
        width = "100%", height = 40,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 12, paddingRight = 12,
        backgroundColor = Theme.colors.bg_secondary,
        borderBottomWidth = 1, borderColor = Theme.colors.border,
        children = barChildren,
    }

    -- 旅行进度条（仅旅行中显示）
    local isTravelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING
    local plan = state.flow.route_plan

    if isTravelling and plan then
        local progress = RoutePlanner.get_progress(plan)
        local seg = RoutePlanner.get_current_segment(plan)

        -- 计算最终目的地名称
        local finalDest = "?"
        if plan.path and #plan.path > 0 then
            finalDest = Graph.get_node_name(plan.path[#plan.path])
        end

        -- 计算剩余时间
        local remaining = 0
        if seg then
            remaining = math.max(0, seg.time_sec - (plan.segment_elapsed or 0))
            for i = (plan.segment_index or 0) + 1, #plan.segments do
                remaining = remaining + plan.segments[i].time_sec
            end
        end

        local travelStrip = UI.Panel {
            id = "shellTravelStrip",
            width = "100%", height = 28,
            flexDirection = "row", alignItems = "center",
            paddingLeft = 12, paddingRight = 12,
            backgroundColor = { 22, 36, 48, 240 },
            borderBottomWidth = 1, borderColor = { 50, 80, 100, 120 },
            gap = 8,
            children = {
                UI.Label {
                    id = "shellTravelIcon",
                    text = "🚚",
                    fontSize = 12,
                },
                UI.ProgressBar {
                    id = "shellTravelProgress",
                    value = progress,
                    flexGrow = 1, height = 6,
                    variant = "info",
                },
                UI.Label {
                    id = "shellTravelDest",
                    text = "→ " .. finalDest,
                    fontSize = 10,
                    fontColor = Theme.colors.info,
                },
                UI.Label {
                    id = "shellTravelTime",
                    text = string.format("%d:%02d",
                        math.floor(remaining / 60),
                        math.floor(remaining % 60)),
                    fontSize = 10,
                    fontColor = Theme.colors.text_secondary,
                },
            },
        }

        return UI.Panel {
            id = "shellTopContainer",
            width = "100%",
            children = {
                statusBar,
                travelStrip,
            },
        }
    end

    return statusBar
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

--- 全局顶部状态栏
--- 显示信用点、燃料、耐久、货舱容量、角色状态
--- 旅行中：额外显示旅行进度条、目的地、剩余时间、收音机面板
--- Shell 每帧通过 FindById 更新数值
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local CargoUtils   = require("economy/cargo_utils")
local ItemUse      = require("economy/item_use")
local Flow         = require("core/flow")
local RoutePlanner = require("map/route_planner")
local Graph        = require("map/world_graph")
local Radio        = require("travel/radio")
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local Flags        = require("core/flags")
local F            = require("ui/ui_factory")
local SketchBorder = require("ui/sketch_border")

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
        UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            children = {
                F.icon { icon = "credits", size = 28 },
                UI.Label {
                    id = "shellCredits",
                    text = tostring(state.economy.credits),
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.accent,
                },
            },
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
        fuelPct > 30 and Theme.colors.text_secondary or Theme.colors.danger, "fuel"))
    table.insert(barChildren, M.chip("耐久", durPct .. "%", "shellDurVal",
        durPct > 30 and Theme.colors.text_secondary or Theme.colors.danger, "durability"))
    table.insert(barChildren, M.chip("货舱", cargoUsed .. "/" .. state.truck.cargo_slots,
        "shellCargoVal", hasShortage and Theme.colors.danger or Theme.colors.text_secondary, "tab_cargo"))

    local statusBar = UI.Panel {
        id = "shellStatusBar",
        width = "100%", height = 40,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 16, paddingRight = 16,
        backgroundColor = Theme.colors.bg_secondary,
        backgroundImage = Theme.textures.topbar,
        backgroundFit = "cover",
        children = barChildren,
    }
    SketchBorder.register(statusBar, "card")

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
            backgroundColor = Theme.colors.travel_strip_bg,
            borderBottomWidth = 1, borderColor = Theme.colors.travel_strip_border,
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

        -- 收音机面板（旅行中：进度条下方）
        local radioStrip = M.createRadioStrip(state)

        return UI.Panel {
            id = "shellTopContainer",
            width = "100%",
            children = {
                statusBar,
                travelStrip,
                radioStrip,
            },
        }
    end

    -- 非旅行（据点）：也显示收音机
    local radioStrip = M.createRadioStrip(state)
    if radioStrip then
        return UI.Panel {
            id = "shellTopContainer",
            width = "100%",
            children = {
                statusBar,
                radioStrip,
            },
        }
    end

    return statusBar
end

--- 获取下一个频道（循环切换）
---@param current string
---@return string
local function _next_channel(current)
    for i, ch in ipairs(Radio.CHANNELS) do
        if ch == current then
            return Radio.CHANNELS[(i % #Radio.CHANNELS) + 1]
        end
    end
    return Radio.CHANNELS[1]
end

--- 逐步展示气泡序列（供收音机教程使用）
function M._showBubbleSequence(parent, state, steps, index)
    if index > #steps then return end
    local step = steps[index]
    SpeechBubble.show(parent, {
        portrait  = step.portrait,
        speaker   = step.speaker,
        text      = step.text,
        autoHide  = 0,
        onDismiss = function()
            M._showBubbleSequence(parent, state, steps, index + 1)
        end,
    })
end

--- 收音机迷你面板（紧凑横条样式，嵌入顶栏）
--- 据点和旅行中都可见；无 radio 状态时返回 nil
---@param state table
---@return table|nil widget
function M.createRadioStrip(state)
    local r = state.flow and state.flow.radio
    if not r then return nil end

    local isOn    = Radio.is_on(state)
    local channel = Radio.get_channel(state)
    local cur     = Radio.get_current(state)

    local stripChildren = {}

    -- 左侧：收音机开关图标按钮
    local radioIcon = F.icon {
        icon = isOn and "radio_on" or "radio",
        size = 28,
    }
    radioIcon:SetStyle({ id = "shellRadioToggle" })
    radioIcon.onClick = function(self)
        local turningOn = not isOn
        Radio.set_on(state, turningOn)
        -- 首次打开收音机：标记 pending，等 shell 重建后再触发气泡
        if turningOn then
            local steps = Tutorial.get_radio_intro_steps(state)
            if steps then
                Flags.set(state, "tutorial_radio_intro")
                M._pendingRadioTutorial = { state = state, steps = steps }
            end
        end
    end
    table.insert(stripChildren, radioIcon)

    if isOn then
        -- 单个频道按钮：点击循环切换
        local chName = Radio.CHANNEL_NAMES[channel] or channel
        table.insert(stripChildren, F.actionBtn {
            id = "shellRadioCh",
            text = chName,
            variant = "primary",
            width = "auto",
            height = 22,
            fontSize = 9,
            paddingLeft = 10, paddingRight = 10,
            onClick = function(self)
                local nextCh = _next_channel(channel)
                Radio.switch_channel(state, nextCh)
            end,
        })

        -- 播报文字区域（NanoVG 在此 Panel 上方绘制平滑滚动字幕）
        if cur then
            table.insert(stripChildren, UI.Panel {
                id = "shellRadioTextArea",
                flexGrow = 1, flexShrink = 1,
                height = "100%",
            })
            -- 有奖励且未领取
            if cur.reward and not cur.reward_claimed then
                local rewardLabel = "领取"
                if cur.reward.type == "credits" then
                    rewardLabel = "+$" .. tostring(cur.reward.value or 0)
                elseif cur.reward.type == "info" then
                    rewardLabel = "记下"
                end
                table.insert(stripChildren, F.actionBtn {
                    id = "shellRadioReward",
                    text = rewardLabel,
                    variant = "primary",
                    width = "auto",
                    height = 22,
                    fontSize = 9,
                    paddingLeft = 10, paddingRight = 10,
                    onClick = function(self)
                        Radio.claim_reward(state)
                    end,
                })
            end
        else
            table.insert(stripChildren, UI.Label {
                id = "shellRadioText",
                text = "...",
                fontSize = 10,
                fontColor = Theme.colors.text_dim,
                flexGrow = 1,
            })
        end
    else
        -- 关闭状态：简短提示
        table.insert(stripChildren, UI.Label {
            id = "shellRadioText",
            text = "收音机已关闭",
            fontSize = 10,
            fontColor = Theme.colors.text_dim,
            flexGrow = 1,
        })
    end

    return UI.Panel {
        id = "shellRadioStrip",
        width = "100%", height = 28,
        flexDirection = "row", alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        backgroundColor = isOn and Theme.colors.radio_on_bg or Theme.colors.radio_off_bg,
        borderBottomWidth = 1,
        borderColor = isOn and Theme.colors.radio_on_border or Theme.colors.radio_off_border,
        gap = 4,
        children = stripChildren,
    }
end

--- 状态栏小标签
---@param label string 文字标签（图标不可用时的回退）
---@param value string 数值文字
---@param valueId string UI 查找 ID
---@param color table 数值颜色
---@param iconKey string|nil Theme.icons 中的 key
function M.chip(label, value, valueId, color, iconKey)
    local labelChild
    if iconKey and Theme.icons[iconKey] then
        labelChild = F.icon { icon = iconKey, size = 26 }
    else
        labelChild = UI.Label {
            text = label,
            fontSize = 10,
            fontColor = Theme.colors.text_dim,
        }
    end
    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        marginLeft = 12, gap = 3,
        children = {
            labelChild,
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

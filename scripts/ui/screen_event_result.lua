--- 事件结果页
--- 显示玩家选择后的结果文本，然后继续流程
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local EventScheduler = require("events/event_scheduler")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local event  = params and params.event or {}
    local choice = params and params.choice or {}

    return UI.Panel {
        id = "eventResultScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = "90%", maxWidth = 420,
                padding = Theme.sizes.padding_large,
                backgroundColor = Theme.colors.bg_card,
                borderRadius = Theme.sizes.radius_large,
                borderWidth = Theme.sizes.border, borderColor = Theme.colors.border,
                gap = 14, alignItems = "center",
                children = {
                    UI.Label {
                        text = event.title or "事件结果",
                        fontSize = Theme.sizes.font_large, fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = choice.result_text or "...",
                        fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_secondary,
                        textAlign = "center", lineHeight = 1.5,
                    },
                    UI.Button {
                        text = "继续",
                        variant = "primary", width = "100%", height = 44, marginTop = 8,
                        onClick = function(self)
                            -- 清除待处理事件标记
                            EventScheduler.clear_pending(state)

                            -- 行程中事件：回到首页继续行驶
                            -- 结算前事件：跳到结算页
                            local pending = state._pending_summary
                            state._pending_summary = nil
                            if pending then
                                router.navigate("summary", {
                                    result = pending.result,
                                    delivered_orders = pending.delivered_orders,
                                })
                            else
                                router.navigate("home")
                            end
                        end,
                    },
                },
            },
        },
    }
end

function M.update(state, dt, r) end

return M

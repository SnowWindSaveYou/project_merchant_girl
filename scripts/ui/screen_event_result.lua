--- 事件结果页
--- 显示玩家选择后的结果文本，然后继续流程
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F = require("ui/ui_factory")
local EventScheduler = require("events/event_scheduler")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local event  = params and params.event or {}
    local choice = params and params.choice or {}

    return F.overlay {
        id = "eventResultScreen",
        children = {
            F.card {
                width = "90%", maxWidth = 420,
                padding = Theme.sizes.padding_large,
                gap = 14, alignItems = "center",
                enterAnim = true,
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
                    F.actionBtn {
                        text = "继续",
                        variant = "primary", marginTop = 8,
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

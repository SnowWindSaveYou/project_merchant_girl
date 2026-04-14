--- 事件结果页
--- 显示玩家选择后的结果文本，然后继续流程
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F = require("ui/ui_factory")
local EventScheduler = require("events/event_scheduler")
local Graph = require("map/world_graph")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local event  = params and params.event or {}
    local choice = params and params.choice or {}

    -- 解析背景图：事件自身 > 行驶中按地形 > 聚落 CG
    local REGION_BG = {
        urban  = "image/bg_generic_ruins_industrial_20260409080003.png",
        wild   = "image/bg_generic_road_20260409075956.png",
        canyon = "image/bg_generic_wilderness_20260409080002.png",
        forest = "image/bg_generic_wilderness_20260409080002.png",
    }
    local bgImage = event.background or nil
    if not bgImage then
        if state.flow and state.flow.phase == "travelling" then
            local region = state.flow.environment and state.flow.environment.region or "wild"
            bgImage = REGION_BG[region] or REGION_BG.wild
        else
            local loc = state.map and state.map.current_location
            if loc then
                local node = Graph.get_node(loc)
                bgImage = node and node.bg or nil
            end
        end
    end

    return F.overlay {
        id = "eventResultScreen",
        backgroundImage = bgImage,
        children = {
            F.popupCard {
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

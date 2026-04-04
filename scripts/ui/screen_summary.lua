--- 结算页
--- 显示行程收益、已交付订单、耗时等摘要信息
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Flow = require("core/flow")
local Graph = require("map/world_graph")
local OrderBook = require("economy/order_book")
local SaveLocal = require("save/save_local")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local result = params and params.result or {}

    local totalTime = result.total_time or 0
    local totalFuel = result.total_fuel or 0
    local strategy  = result.strategy or "unknown"
    local destName  = Graph.get_node_name(result.destination or state.map.current_location)

    -- 收集本趟交付的订单
    local deliveredOrders = params and params.delivered_orders or {}
    local totalReward = 0
    for _, o in ipairs(deliveredOrders) do
        totalReward = totalReward + (o.base_reward or 0)
    end

    -- 剩余活跃订单
    local remaining = OrderBook.get_active(state)

    -- 清理已完结订单
    OrderBook.cleanup(state)

    local mins = math.floor(totalTime / 60)
    local secs = math.floor(totalTime % 60)

    -- 到达后自动保存
    SaveLocal.save(state)

    -- 交付详情列表
    local deliveryCards = {}
    if #deliveredOrders > 0 then
        for _, o in ipairs(deliveredOrders) do
            table.insert(deliveryCards, UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = o.goods_name .. " ×" .. o.count .. " → " .. o.to_name,
                        fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_primary,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = "+$" .. o.base_reward,
                        fontSize = Theme.sizes.font_small, fontColor = Theme.colors.success,
                    },
                },
            })
        end
    else
        table.insert(deliveryCards, UI.Label {
            text = "本趟未交付任何订单",
            fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_dim,
            textAlign = "center", width = "100%",
        })
    end

    local STRATEGY_NAMES = {
        fastest = "最快", safest = "最安全", balanced = "平衡", manual = "手动",
    }

    return UI.Panel {
        id = "summaryScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%",
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Panel {
                        width = "90%", maxWidth = 420,
                        padding = Theme.sizes.padding_large,
                        backgroundColor = Theme.colors.bg_card,
                        borderRadius = Theme.sizes.radius_large,
                        borderWidth = Theme.sizes.border, borderColor = Theme.colors.border,
                        gap = 10, alignItems = "center",
                        overflow = "scroll",
                        children = {
                            UI.Label {
                                text = "行程结算",
                                fontSize = Theme.sizes.font_title, fontColor = Theme.colors.text_primary,
                            },
                            UI.Label {
                                text = "抵达 " .. destName,
                                fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.info,
                            },
                            UI.Panel { width = "100%", height = 1, backgroundColor = Theme.colors.divider },
                            -- 路线信息
                            createResultRow("策略", STRATEGY_NAMES[strategy] or strategy),
                            createResultRow("耗时", string.format("%d分%02d秒", mins, secs)),
                            createResultRow("燃料消耗", tostring(totalFuel)),
                            UI.Panel { width = "100%", height = 1, backgroundColor = Theme.colors.divider },
                            -- 交付订单
                            UI.Label {
                                text = "交付明细",
                                fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_primary,
                                width = "100%",
                            },
                            UI.Panel {
                                width = "100%", gap = 4,
                                children = deliveryCards,
                            },
                            UI.Panel { width = "100%", height = 1, backgroundColor = Theme.colors.divider },
                            -- 收入
                            UI.Label {
                                text = "+ $ " .. tostring(totalReward),
                                fontSize = 28, fontColor = Theme.colors.success,
                            },
                            UI.Label {
                                text = "当前信用点  $ " .. tostring(state.economy.credits),
                                fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.accent,
                            },
                            -- 剩余订单
                            #remaining > 0 and UI.Label {
                                text = "剩余 " .. #remaining .. " 个活跃订单",
                                fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_dim,
                            } or UI.Panel { height = 0 },
                            UI.Label {
                                text = "累计行程 " .. tostring(state.stats.total_trips) .. " 趟",
                                fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_dim,
                            },
                            -- 继续按钮
                            UI.Button {
                                text = "继续行商",
                                variant = "primary", width = "100%", height = 48, marginTop = 8,
                                onClick = function(self)
                                    Flow.finish_summary(state)
                                    router.navigate("home")
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

function M.update(state, dt, r) end

--- 结果信息行
function createResultRow(label, value)
    return UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label { text = label, fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_secondary },
            UI.Label { text = value, fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_primary },
        },
    }
end

return M

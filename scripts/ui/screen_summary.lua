--- 结算页
--- 显示行程收益、已交付订单、耗时等摘要信息
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F = require("ui/ui_factory")
local Flow = require("core/flow")
local Graph = require("map/world_graph")
local OrderBook = require("economy/order_book")
local SaveLocal = require("save/save_local")
local SoundMgr  = require("ui/sound_manager")

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

    -- 收集本趟交付的订单（含 delivery_result 字段）
    local deliveredOrders = params and params.delivered_orders or {}
    local totalReward = 0
    for _, o in ipairs(deliveredOrders) do
        totalReward = totalReward + (o.partial_reward or o.base_reward or 0)
    end

    -- 剩余活跃订单
    local remaining = OrderBook.get_active(state)

    -- 有交付奖励时播放金币音效
    if totalReward > 0 then
        SoundMgr.play("coins")
    end

    -- 清理已完结订单
    OrderBook.cleanup(state)

    local mins = math.floor(totalTime / 60)
    local secs = math.floor(totalTime % 60)

    -- 到达后自动保存
    SaveLocal.save(state)

    -- 交付详情列表
    local RESULT_LABEL = {
        full    = { tag = "全额", color = Theme.colors.success },
        partial = { tag = "部分", color = Theme.colors.warning },
        failed  = { tag = "失败", color = Theme.colors.danger },
        expired = { tag = "超时", color = Theme.colors.danger },
    }

    local deliveryCards = {}
    if #deliveredOrders > 0 then
        for _, o in ipairs(deliveredOrders) do
            local dr = o.delivery_result or "full"
            local info = RESULT_LABEL[dr] or RESULT_LABEL.full
            local reward = o.partial_reward or o.base_reward or 0

            -- 左侧：货物信息 + 交付标签
            local leftText = o.goods_name .. " "
            if dr == "partial" then
                leftText = leftText .. (o.delivered_count or 0) .. "/" .. o.count
            else
                leftText = leftText .. "×" .. o.count
            end
            leftText = leftText .. " → " .. o.to_name

            -- 右侧：奖励金额
            local rewardText = reward > 0 and ("+$" .. reward) or "$0"

            table.insert(deliveryCards, UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                gap = 4,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6, flexShrink = 1,
                        children = {
                            UI.Label {
                                text = "[" .. info.tag .. "]",
                                fontSize = Theme.sizes.font_tiny,
                                fontColor = info.color,
                            },
                            UI.Label {
                                text = leftText,
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.text_primary,
                                flexShrink = 1,
                            },
                        },
                    },
                    UI.Label {
                        text = rewardText,
                        fontSize = Theme.sizes.font_small,
                        fontColor = reward > 0 and info.color or Theme.colors.text_dim,
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

    -- 解析当前聚落背景图
    local bgImage = nil
    local loc = state.map and state.map.current_location
    if loc then
        local nodeInfo = Graph.get_node(loc)
        bgImage = nodeInfo and nodeInfo.bg or nil
    end

    return F.overlay {
        id = "summaryScreen",
        backgroundImage = bgImage,
        children = {
            UI.ScrollView {
                width = "90%", maxWidth = 420,
                maxHeight = "85%",
                children = {
                    F.card {
                        id = "summaryScroll",
                        width = "100%",
                        padding = Theme.sizes.padding_large,
                        gap = 10, alignItems = "center",
                        enterAnim = true,
                        children = {
                            UI.Label {
                                text = "行程结算",
                                fontSize = Theme.sizes.font_title, fontColor = Theme.colors.text_primary,
                            },
                            UI.Label {
                                text = "抵达 " .. destName,
                                fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.info,
                            },
                            F.divider(),
                            -- 路线信息
                            createResultRow("策略", STRATEGY_NAMES[strategy] or strategy),
                            createResultRow("耗时", string.format("%d分%02d秒", mins, secs)),
                            createResultRow("燃料消耗", tostring(totalFuel)),
                            F.divider(),
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
                            F.divider(),
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
                            F.actionBtn {
                                text = "继续行商",
                                variant = "primary", height = 48, marginTop = 8,
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

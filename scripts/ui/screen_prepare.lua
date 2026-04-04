--- 订单簿管理页
--- 查看已接订单、按目的地分组、取消订单、前往路线规划
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Flow = require("core/flow")
local OrderBook = require("economy/order_book")
local Graph = require("map/world_graph")
local Goods = require("economy/goods")

local M = {}
---@type table
local router = nil

local RISK_LABEL = { low = "低", normal = "中", high = "高" }
local RISK_COLOR = {
    low    = Theme.colors.success,
    normal = Theme.colors.accent,
    high   = Theme.colors.danger,
}

function M.create(state, params, r)
    router = r

    local activeOrders = OrderBook.get_active(state)
    local groups = OrderBook.group_by_destination(state)
    local location = state.map.current_location
    local curNode = Graph.get_node(location)
    local isSettlement = curNode and curNode.type == "settlement"

    local contentChildren = {}

    -- ── 可接取订单区域（仅在聚落时显示） ──
    if isSettlement then
        local available = OrderBook.get_available(state, location)
        if #available > 0 then
            table.insert(contentChildren, UI.Label {
                text = curNode.name .. " · 可接订单",
                fontSize = Theme.sizes.font_large,
                fontColor = Theme.colors.text_primary,
            })
            for _, order in ipairs(available) do
                table.insert(contentChildren, createAvailableOrderCard(state, order))
            end

            -- 分割线
            table.insert(contentChildren, UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Theme.colors.border,
                marginTop = 4, marginBottom = 4,
            })
        else
            table.insert(contentChildren, UI.Panel {
                width = "100%", padding = 12,
                backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "当前聚落暂无新订单",
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_dim,
                    },
                },
            })
        end
    end

    -- ── 持有订单区域 ──
    table.insert(contentChildren, UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label { text = "持有订单", fontSize = Theme.sizes.font_large, fontColor = Theme.colors.text_primary },
            UI.Label {
                text = #activeOrders .. " 个",
                fontSize = Theme.sizes.font_large, fontColor = Theme.colors.accent,
            },
        },
    })

    if #activeOrders == 0 then
        table.insert(contentChildren, UI.Panel {
            width = "100%", padding = 20,
            backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
            alignItems = "center", gap = 4,
            children = {
                UI.Label {
                    text = "暂无持有订单",
                    fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_dim,
                },
            },
        })
    else
        for destId, group in pairs(groups) do
            table.insert(contentChildren, createDestGroup(state, group))
        end
    end

    -- 底部操作
    local bottomChildren = {}

    if #activeOrders > 0 then
        table.insert(bottomChildren, UI.Button {
            text = "规划路线并出发",
            variant = "primary", width = "100%", height = 48,
            onClick = function(self)
                Flow.enter_route_plan(state)
                router.navigate("route_plan")
            end,
        })
    end

    return UI.Panel {
        id = "prepareScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            -- 内容（可滚动）
            UI.Panel {
                width = "100%", flexGrow = 1, flexShrink = 1,
                padding = Theme.sizes.padding, gap = 10,
                overflow = "scroll",
                children = contentChildren,
            },
            -- 底部操作按钮
            UI.Panel {
                width = "100%", padding = Theme.sizes.padding, gap = 8,
                backgroundColor = Theme.colors.bg_secondary,
                borderTopWidth = 1, borderColor = Theme.colors.border,
                children = bottomChildren,
            },
        },
    }
end

function M.update(state, dt, r) end

--- 目的地分组卡片
function createDestGroup(state, group)
    local orderCards = {}
    for _, order in ipairs(group.orders) do
        local remaining = OrderBook.get_remaining_time(order)
        local timeText = remaining > 0
            and string.format("剩余 %d:%02d", math.floor(remaining / 60), remaining % 60)
            or "已超时"
        local timeColor = remaining > 120 and Theme.colors.text_secondary
            or remaining > 0 and Theme.colors.accent
            or Theme.colors.danger

        table.insert(orderCards, UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = Theme.colors.bg_secondary, borderRadius = Theme.sizes.radius_small,
            gap = 4,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = order.goods_name .. " ×" .. order.count,
                            fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_primary,
                            flexShrink = 1,
                        },
                        UI.Label {
                            text = "+$" .. order.base_reward,
                            fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.success,
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row", gap = 8,
                            children = {
                                UI.Label {
                                    text = "风险 " .. (RISK_LABEL[order.risk_level] or "?"),
                                    fontSize = Theme.sizes.font_tiny,
                                    fontColor = RISK_COLOR[order.risk_level] or Theme.colors.text_dim,
                                },
                                UI.Label {
                                    text = timeText,
                                    fontSize = Theme.sizes.font_tiny, fontColor = timeColor,
                                },
                            },
                        },
                        UI.Button {
                            text = "放弃",
                            variant = "text", height = 24,
                            onClick = function(self)
                                OrderBook.abandon_order(state, order.order_id)
                                router.navigate("orders") -- 刷新
                            end,
                        },
                    },
                },
            },
        })
    end

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        borderWidth = Theme.sizes.border, borderColor = Theme.colors.accent,
        gap = 8,
        children = {
            UI.Label {
                text = "🎯 " .. group.dest_name .. " (" .. #group.orders .. "单)",
                fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.accent,
            },
            UI.Panel {
                width = "100%", gap = 6,
                children = orderCards,
            },
        },
    }
end

--- 可接取订单卡片
function createAvailableOrderCard(state, order)
    local destName = Graph.get_node_name(order.to)
    local goodsInfo = Goods.get(order.goods_id)
    local goodsName = goodsInfo and goodsInfo.name or order.goods_id
    local riskColor = RISK_COLOR[order.risk_level] or Theme.colors.text_dim
    local riskText  = RISK_LABEL[order.risk_level] or "?"

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.success,
        gap = 6,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = goodsName .. " ×" .. (order.count or 1),
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = "+$" .. tostring(order.base_reward),
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.success,
                    },
                },
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 8,
                        children = {
                            UI.Label {
                                text = "→ " .. destName,
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.accent,
                            },
                            UI.Label {
                                text = "风险 " .. riskText,
                                fontSize = Theme.sizes.font_tiny,
                                fontColor = riskColor,
                            },
                        },
                    },
                    UI.Button {
                        text = "接取",
                        variant = "primary", height = 28, paddingLeft = 14, paddingRight = 14,
                        onClick = function(self)
                            local ok, err = OrderBook.accept_order(state, order)
                            if ok then
                                print("[Orders] Accepted: " .. (order.order_id or "?"))
                            else
                                print("[Orders] Accept failed: " .. (err or ""))
                            end
                            router.navigate("orders") -- 刷新
                        end,
                    },
                },
            },
        },
    }
end

return M

--- 首页 — 末世行商主界面
--- 据点模式：插画 + 信息卡 + 操作按钮
--- 行驶模式：进度条 + 订单摘要
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Goods        = require("economy/goods")

local M = {}
---@type table
local router = nil

-- 据点主题色（插画背景渐变底色）
local SETTLEMENT_THEMES = {
    greenhouse  = { bg = { 38, 52, 38, 255 }, accent = { 108, 148,  96, 255 }, icon = "🌿" },
    tower       = { bg = { 32, 40, 54, 255 }, accent = { 112, 142, 168, 255 }, icon = "🗼" },
    ruins_camp  = { bg = { 48, 38, 30, 255 }, accent = { 168, 128,  82, 255 }, icon = "🏚" },
}
local DEFAULT_THEME = { bg = { 40, 38, 36, 255 }, accent = Theme.colors.accent, icon = "📍" }

-- ============================================================
-- 页面创建
-- ============================================================
function M.create(state, params, r)
    router = r

    local phase        = Flow.get_phase(state)
    local isTravelling = (phase == Flow.Phase.TRAVELLING)
    local location     = state.map.current_location
    local curNode      = Graph.get_node(location)

    if isTravelling then
        return createTravelView(state)
    else
        return createSettlementView(state, curNode)
    end
end

-- ============================================================
-- 每帧更新（行驶中动态刷新进度/时间）
-- ============================================================
function M.update(state, dt, r)
    if Flow.get_phase(state) ~= Flow.Phase.TRAVELLING then return end
    local plan = state.flow.route_plan
    if not plan then return end

    local root = UI.GetRoot()
    if not root then return end

    local progress = RoutePlanner.get_progress(plan)

    local bar = root:FindById("travelProgress")
    if bar then bar:SetValue(progress) end

    local pct = root:FindById("travelPct")
    if pct then pct:SetText(math.floor(progress * 100) .. "%") end

    -- 剩余时间
    local seg = RoutePlanner.get_current_segment(plan)
    local remaining = 0
    if seg then
        remaining = math.max(0, seg.time_sec - (plan.segment_elapsed or 0))
        for i = plan.segment_index + 1, #plan.segments do
            remaining = remaining + plan.segments[i].time_sec
        end
    end
    local timeLabel = root:FindById("travelTime")
    if timeLabel then
        timeLabel:SetText(string.format(
            "%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))
    end
end

-- ============================================================
-- 据点视图：上半插画 + 下半信息卡 & 按钮
-- ============================================================
function createSettlementView(state, curNode)
    local nodeId = curNode and curNode.id or ""
    local theme  = SETTLEMENT_THEMES[nodeId] or DEFAULT_THEME
    local activeOrders = OrderBook.get_active(state)
    local isSettlement = curNode and curNode.type == "settlement"

    -- 节点类型图标
    local typeIcons = {
        settlement = "🏘", resource = "📦", transit = "🔀",
        hazard = "⚠", story = "📡",
    }
    local nodeIcon = curNode and (typeIcons[curNode.type] or "") or ""

    -- ── 上半部：据点插画区 ──
    local illustrationPanel = UI.Panel {
        id = "settlementIllustration",
        width = "100%", flexGrow = 1, flexShrink = 1,
        minHeight = 120,
        backgroundColor = theme.bg,
        justifyContent = "center", alignItems = "center",
        gap = 8,
        children = {
            UI.Label {
                text = theme.icon,
                fontSize = 56,
                textAlign = "center",
            },
            UI.Label {
                text = curNode and curNode.name or "未知区域",
                fontSize = Theme.sizes.font_title,
                fontColor = theme.accent,
                textAlign = "center",
            },
            UI.Label {
                text = curNode and curNode.desc or "",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
                textAlign = "center",
                paddingLeft = 24, paddingRight = 24,
            },
        },
    }

    -- ── 下半部：信息卡 + 按钮列表 ──
    local lowerChildren = {}

    -- 信息卡片：位置 + 类型
    table.insert(lowerChildren, UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Label {
                        text = nodeIcon,
                        fontSize = Theme.sizes.font_large,
                    },
                    UI.Label {
                        text = curNode and curNode.name or "未知",
                        fontSize = Theme.sizes.font_large,
                        fontColor = Theme.colors.text_primary,
                    },
                },
            },
            UI.Label {
                text = isSettlement and "聚落" or (curNode and curNode.type or ""),
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
        },
    })

    -- 活跃订单摘要
    if #activeOrders > 0 then
        table.insert(lowerChildren, UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = "活跃订单",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                },
                UI.Label {
                    text = #activeOrders .. " 个待配送",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.accent,
                },
            },
        })
    end

    -- 积压警告
    local backlogInfo = OrderBook.get_backlog_info(state)
    if backlogInfo.level ~= "normal" or backlogInfo.consecutive_expires >= 2 then
        table.insert(lowerChildren, createBacklogWarning(backlogInfo))
    end

    -- ── 操作按钮区 ──
    if isSettlement then
        -- 委托
        table.insert(lowerChildren, UI.Button {
            text = "📋 接取委托",
            variant = "secondary",
            width = "100%", height = 44,
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                Flow.enter_prepare(state)
                router.navigate("orders")
            end,
        })

        -- 交易所
        table.insert(lowerChildren, UI.Button {
            text = "🏪 交易所",
            variant = "secondary",
            width = "100%", height = 44,
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                router.navigate("shop")
            end,
        })

        -- 出发（仅有活跃订单时）
        if #activeOrders > 0 then
            table.insert(lowerChildren, UI.Button {
                text = "🚚 出发",
                variant = "primary",
                width = "100%", height = 44,
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    Flow.enter_route_plan(state)
                    router.navigate("route_plan")
                end,
            })
        end

        -- 剧情预留：到处逛逛
        table.insert(lowerChildren, UI.Button {
            text = "🔍 到处逛逛",
            variant = "outline",
            width = "100%", height = 40,
            fontSize = Theme.sizes.font_small,
            onClick = function(self)
                print("[Home] 剧情/探索功能待开发")
            end,
        })
    else
        -- 非聚落节点：只有查看地图和委托
        if #activeOrders > 0 then
            table.insert(lowerChildren, UI.Button {
                text = "🚚 出发",
                variant = "primary",
                width = "100%", height = 44,
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    Flow.enter_route_plan(state)
                    router.navigate("route_plan")
                end,
            })
        end
    end

    local lowerPanel = UI.Panel {
        id = "settlementActions",
        width = "100%",
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = lowerChildren,
    }

    -- ── 组装 ──
    return UI.Panel {
        id = "homeScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            illustrationPanel,
            lowerPanel,
        },
    }
end

-- ============================================================
-- 行驶视图：进度条 + 目的地 + 订单摘要
-- ============================================================
function createTravelView(state)
    local plan       = state.flow.route_plan or {}
    local progress   = RoutePlanner.get_progress(plan)
    local seg        = RoutePlanner.get_current_segment(plan)
    local destName   = seg and seg.to_name or "?"
    local orderCnt   = OrderBook.active_count(state)
    local activeOrders = OrderBook.get_active(state)

    -- 剩余时间计算
    local remaining = 0
    if seg and plan.segments then
        remaining = math.max(0, seg.time_sec - (plan.segment_elapsed or 0))
        for i = (plan.segment_index or 0) + 1, #plan.segments do
            remaining = remaining + plan.segments[i].time_sec
        end
    end

    local contentChildren = {}

    -- 行驶进度卡片
    table.insert(contentChildren, UI.Panel {
        id = "travelStrip",
        width = "100%", padding = 14,
        backgroundColor = { 28, 42, 58, 240 },
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.info,
        gap = 10,
        children = {
            -- 目标 + 时间
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "→ " .. destName,
                        fontSize = Theme.sizes.font_large,
                        fontColor = Theme.colors.info,
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 10, alignItems = "center",
                        children = {
                            UI.Label {
                                text = orderCnt .. " 单",
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.accent,
                            },
                            UI.Label {
                                id = "travelTime",
                                text = string.format("%d:%02d",
                                    math.floor(remaining / 60),
                                    math.floor(remaining % 60)),
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.text_secondary,
                            },
                        },
                    },
                },
            },
            -- 进度条
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 8,
                children = {
                    UI.ProgressBar {
                        id = "travelProgress",
                        value = progress,
                        flexGrow = 1, height = 10,
                        variant = "info",
                    },
                    UI.Label {
                        id = "travelPct",
                        text = math.floor(progress * 100) .. "%",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                        width = 36, textAlign = "right",
                    },
                },
            },
        },
    })

    -- 活跃订单列表
    if #activeOrders > 0 then
        table.insert(contentChildren, UI.Label {
            text = "配送中的订单",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            marginTop = 4,
        })
        for _, order in ipairs(activeOrders) do
            table.insert(contentChildren, UI.Panel {
                width = "100%", padding = 10,
                backgroundColor = Theme.colors.bg_card,
                borderRadius = Theme.sizes.radius_small,
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = order.description or (order.from_name .. " → " .. order.to_name),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_primary,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = "+$" .. tostring(order.base_reward),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.success,
                    },
                },
            })
        end
    end

    -- 积压警告
    local backlogInfo = OrderBook.get_backlog_info(state)
    if backlogInfo.level ~= "normal" or backlogInfo.consecutive_expires >= 2 then
        table.insert(contentChildren, createBacklogWarning(backlogInfo))
    end

    -- 货舱概览
    table.insert(contentChildren, createCargoSummary(state))

    return UI.Panel {
        id = "homeScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = contentChildren,
    }
end

-- ============================================================
-- 货舱概览（简版，行驶中展示）
-- ============================================================
function createCargoSummary(state)
    local items = {}
    for gid, count in pairs(state.truck.cargo) do
        if count > 0 then
            local g = Goods.get(gid)
            table.insert(items, (g and g.name or gid) .. " x" .. count)
        end
    end
    local text = #items > 0 and table.concat(items, " · ") or "空"

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        gap = 2,
        children = {
            UI.Label {
                text = "货舱",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
            UI.Label {
                text = text,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
            },
        },
    }
end

-- ============================================================
-- 积压警告
-- ============================================================
function createBacklogWarning(info)
    local bg = info.level == "overloaded"
        and { 72, 28, 28, 220 } or { 64, 54, 20, 220 }

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = bg,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1,
        borderColor = info.level == "overloaded"
            and Theme.colors.danger or Theme.colors.warning,
        flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "委托: " .. info.desc,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.warning,
                flexShrink = 1,
            },
            UI.Label {
                text = "奖励 -" .. info.reward_penalty .. "%",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.danger,
            },
        },
    }
end

return M

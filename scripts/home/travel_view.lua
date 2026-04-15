--- 行驶视图 — 行驶中的进度条 + 目的地 + 订单摘要 + 路景/对话
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Goods        = require("economy/goods")
local CargoUtils   = require("economy/cargo_utils")
local Chatter      = require("travel/chatter")
local Scenery      = require("travel/scenery")
local DrivingScene = require("travel/chibi_scene")
local SketchBorder = require("ui/sketch_border")

local M = {}

-- ============================================================
-- 积压警告（与 settlement_view 共用逻辑，体量小直接复制）
-- ============================================================
local function createBacklogWarning(info)
    local bg = info.level == "overloaded"
        and Theme.colors.home_backlog_danger or Theme.colors.home_backlog_warning

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

-- ============================================================
-- 货舱概览（简版，行驶中展示）
-- ============================================================
local function createCargoSummary(state)
    local used = CargoUtils.get_cargo_used(state)
    local hasShortage = CargoUtils.has_any_shortage(state)

    -- 构建货物图标网格
    local itemWidgets = {}
    for gid, count in pairs(state.truck.cargo) do
        if count > 0 then
            local g = Goods.get(gid)
            local name = g and g.name or gid
            local committed = CargoUtils.get_committed(state, gid)
            local countText = "x" .. count
            if committed > 0 then
                countText = countText .. "(委" .. committed .. ")"
            end
            local cat = g and g.category and Goods.CATEGORIES[g.category]
            local catColor = cat and cat.color or Theme.colors.text_primary

            local itemChildren = {}
            -- 图标
            if g and g.icon then
                table.insert(itemChildren, UI.Panel {
                    width = 24, height = 24,
                    backgroundImage = g.icon,
                    backgroundFit = "contain",
                })
            end
            -- 名称 + 数量
            table.insert(itemChildren, UI.Label {
                text = name,
                fontSize = Theme.sizes.font_tiny,
                fontColor = catColor,
            })
            table.insert(itemChildren, UI.Label {
                text = countText,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_secondary,
            })

            table.insert(itemWidgets, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = itemChildren,
            })
        end
    end

    local cargoChildren = {
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = "货舱",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                },
                UI.Label {
                    text = used .. "/" .. state.truck.cargo_slots,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                },
            },
        },
    }
    -- 如果有货物则显示图标网格，否则显示"空"
    if #itemWidgets > 0 then
        table.insert(cargoChildren, UI.Panel {
            width = "100%",
            flexDirection = "row", flexWrap = "wrap", gap = 8,
            children = itemWidgets,
        })
    else
        table.insert(cargoChildren, UI.Label {
            text = "空",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_dim,
        })
    end

    if hasShortage then
        table.insert(cargoChildren, UI.Label {
            text = "⚠ 委托货物不足",
            fontSize = Theme.sizes.font_tiny,
            fontColor = Theme.colors.danger,
        })
    end

    return F.card {
        width = "100%", padding = 10,
        borderWidth = hasShortage and 1 or 0,
        borderColor = hasShortage and Theme.colors.danger or nil,
        gap = 2,
        children = cargoChildren,
    }
end

-- ============================================================
-- 路景描写文本（行驶中）
-- ============================================================
local function createSceneryText(state)
    local cur = Scenery.get_current(state)
    if not cur then return nil end

    local catColors = {
        window  = { 140, 160, 180, 255 },
        cabin   = { 170, 155, 140, 255 },
        sound   = { 140, 170, 150, 255 },
        time    = { 180, 165, 130, 255 },
        micro   = { 160, 150, 165, 255 },
        silence = { 120, 120, 120, 255 },
    }
    local textColor = catColors[cur.category] or Theme.colors.text_dim

    return UI.Panel {
        width = "100%", paddingTop = 4, paddingBottom = 4,
        paddingLeft = 20, paddingRight = 20,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label {
                text = cur.text,
                fontSize = Theme.sizes.font_small,
                fontColor = textColor,
                textAlign = "center",
            },
        },
    }
end

-- ============================================================
-- 车内日常对话气泡（行驶中）
-- ============================================================
local function createChatterBubble(state)
    local cur = Chatter.get_current(state)
    if not cur then return nil end

    local speakerNames = { linli = "林砾", taoxia = "陶夏" }
    local speakerColorKeys = {
        linli  = "chatter_linli_name",
        taoxia = "chatter_taoxia_name",
    }
    local name  = speakerNames[cur.speaker] or cur.speaker
    local color = Theme.colors[speakerColorKeys[cur.speaker]] or Theme.colors.accent
    local avatar = Theme.avatars[cur.speaker] or Theme.avatars.linli

    -- 文字列子元素
    local textChildren = {
        -- 说话人
        UI.Label {
            text = name,
            fontSize = Theme.sizes.font_small,
            fontColor = color,
        },
        -- 对话内容
        UI.Label {
            text = cur.text,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_primary,
        },
    }

    -- 可回应的对话：显示回应按钮
    if cur.response then
        table.insert(textChildren, F.actionBtn {
            text = cur.response.label or "回应",
            variant = "secondary",
            height = 30,
            fontSize = Theme.sizes.font_small,
            onClick = function(self)
                Chatter.respond(state)
            end,
        })
    end

    return F.card {
        width = "100%",
        backgroundColor = Theme.colors.chatter_bubble_bg,
        flexDirection = "row",
        alignItems = "flex-start",
        padding = 10,
        gap = 8,
        children = {
            -- 头像
            UI.Panel {
                width = 36, height = 36,
                borderRadius = 18,
                backgroundImage = avatar,
                backgroundFit = "cover",
                flexShrink = 0,
            },
            -- 文字区域
            UI.Panel {
                flex = 1, flexShrink = 1,
                gap = 4,
                children = textChildren,
            },
        },
    }
end

-- ============================================================
-- 行驶视图创建
-- ============================================================
function M.create(state)
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

    -- ── 行驶视差场景 ──
    local drivingWidget = DrivingScene.createWidget({
        height = 260,
        borderRadius = Theme.sizes.radius,
    })
    SketchBorder.register(drivingWidget, "card")
    table.insert(contentChildren, drivingWidget)

    -- 当前路段描述
    local EDGE_TYPE_LABEL = { main_road = "公路", path = "小径", shortcut = "捷径" }
    local segFrom = seg and seg.from_name or "?"
    local segTo   = seg and seg.to_name or "?"
    local segType = seg and (EDGE_TYPE_LABEL[seg.edge_type] or "") or ""
    local locationDesc = segType ~= "" and (segFrom .. " → " .. segTo .. "（" .. segType .. "）")
        or (segFrom .. " → " .. segTo)

    -- 最终目的地名
    local finalDest = "?"
    if plan.path and #plan.path > 0 then
        local finalNode = Graph.get_node(plan.path[#plan.path])
        finalDest = finalNode and finalNode.name or plan.path[#plan.path]
    end

    -- 行驶进度卡片
    table.insert(contentChildren, F.card {
        id = "travelStrip",
        width = "100%", padding = 14,
        enterAnim = true, enterDelay = 0.1,
        imageTint = Theme.colors.home_travel_tint,
        borderWidth = 1, borderColor = Theme.colors.info,
        gap = 10,
        children = {
            -- 当前位置：道路上
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 6,
                children = {
                    UI.Label {
                        text = "🚚",
                        fontSize = 16,
                    },
                    UI.Label {
                        id = "travelLocation",
                        text = locationDesc,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                        flexShrink = 1,
                    },
                },
            },
            -- 目标 + 时间
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "→ " .. finalDest,
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

    -- ── 路景描写（与对话互斥，仅在无对话时显示） ──
    local sceneryWidget = createSceneryText(state)
    if sceneryWidget then
        table.insert(contentChildren, sceneryWidget)
    end

    -- ── 车内日常对话气泡 ──
    local chatterWidget = createChatterBubble(state)
    if chatterWidget then
        table.insert(contentChildren, chatterWidget)
    end

    -- 收音机面板已移至全局顶栏（shell_top.lua）

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

return M

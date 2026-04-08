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
local CargoUtils   = require("economy/cargo_utils")
local Goodwill     = require("settlement/goodwill")
local Modules      = require("truck/modules")
local Campfire     = require("narrative/campfire")
local NpcManager          = require("narrative/npc_manager")
local SettlementEventPool = require("events/settlement_event_pool")
local WanderingNpc        = require("narrative/wandering_npc")
local QuestLog            = require("narrative/quest_log")
local Chatter             = require("travel/chatter")
local Radio               = require("travel/radio")

local M = {}
---@type table
local router = nil

-- 行驶中状态追踪（用于检测变化触发 UI 重建）
local _prevChatterId  = nil
local _prevRadioOn    = nil
local _prevRadioCh    = nil
local _prevBroadcastId = nil

-- 地图节点 → 资源点探索房间 ID（Phase 06 连接）
local NODE_EXPLORE_ROOM = {
    old_warehouse = "abandoned_warehouse",
    radar_hill    = "radar_station",
}

-- 据点主题色（插画背景渐变底色）
local SETTLEMENT_THEMES = {
    greenhouse      = { bg = { 38, 52, 38, 255 }, accent = { 108, 148,  96, 255 }, icon = "🌿" },
    tower           = { bg = { 32, 40, 54, 255 }, accent = { 112, 142, 168, 255 }, icon = "🗼" },
    ruins_camp      = { bg = { 48, 38, 30, 255 }, accent = { 168, 128,  82, 255 }, icon = "🏚" },
    bell_tower      = { bg = { 42, 36, 46, 255 }, accent = { 148, 128, 168, 255 }, icon = "🔔" },
    -- 前哨站
    greenhouse_farm = { bg = { 34, 48, 32, 255 }, accent = {  96, 138,  80, 255 }, icon = "🌱" },
    dome_outpost    = { bg = { 30, 36, 48, 255 }, accent = {  96, 126, 152, 255 }, icon = "📡" },
    metro_camp      = { bg = { 44, 36, 28, 255 }, accent = { 152, 112,  72, 255 }, icon = "🚇" },
    old_church      = { bg = { 38, 32, 42, 255 }, accent = { 132, 112, 148, 255 }, icon = "🕯" },
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

    -- late-init：兼容老存档（行驶中加载但 flow 里没有 chatter/radio）
    if isTravelling then
        if not state.flow.chatter then
            state.flow.chatter = Chatter.init()
        end
        if not state.flow.radio then
            state.flow.radio = Radio.init()
        end
        -- 同步追踪变量到当前真实状态，避免首帧误判为"变化"导致无限重建
        local initChat = Chatter.get_current(state)
        _prevChatterId   = initChat and initChat.id or nil
        _prevRadioOn     = Radio.is_on(state)
        _prevRadioCh     = Radio.get_channel(state)
        local initBr = Radio.get_current(state)
        _prevBroadcastId = initBr and initBr.id or nil
    end

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
    local seg = RoutePlanner.get_current_segment(plan)

    -- ── 驱动 Chatter / Radio ──
    Chatter.update(state, dt, progress, seg)
    Radio.update(state, dt)

    -- ── 检测 Chatter / Radio 状态变化 → 重建 UI ──
    local curChat = Chatter.get_current(state)
    local chatId  = curChat and curChat.id or nil
    local radioOn = Radio.is_on(state)
    local radioCh = Radio.get_channel(state)
    local curBroadcast = Radio.get_current(state)
    local broadcastId  = curBroadcast and curBroadcast.id or nil

    local needRebuild = false
    if chatId ~= _prevChatterId then needRebuild = true end
    if radioOn ~= _prevRadioOn then needRebuild = true end
    if radioCh ~= _prevRadioCh then needRebuild = true end
    if broadcastId ~= _prevBroadcastId then needRebuild = true end

    _prevChatterId  = chatId
    _prevRadioOn    = radioOn
    _prevRadioCh    = radioCh
    _prevBroadcastId = broadcastId

    if needRebuild then
        r.navigate("home")
        return
    end

    -- ── 常规 UI 刷新（进度条 / 时间 / 路段） ──
    local bar = root:FindById("travelProgress")
    if bar then bar:SetValue(progress) end

    local pct = root:FindById("travelPct")
    if pct then pct:SetText(math.floor(progress * 100) .. "%") end

    -- 剩余时间
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

    -- 更新当前路段描述
    local locLabel = root:FindById("travelLocation")
    if locLabel and seg then
        local EDGE_TYPE_LABEL = { main_road = "公路", path = "小径", shortcut = "捷径" }
        local segType = EDGE_TYPE_LABEL[seg.edge_type] or ""
        local desc = segType ~= ""
            and (seg.from_name .. " → " .. seg.to_name .. "（" .. segType .. "）")
            or  (seg.from_name .. " → " .. seg.to_name)
        locLabel:SetText(desc)
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

    -- ── 成长目标卡片 ──
    table.insert(lowerChildren, createProgressCard(state))

    -- ── 操作按钮区 ──
    if isSettlement then
        -- 聚落事件（到达时触发的本地事件）
        local pendingEvt = state.flow and state.flow.pending_settlement_event or nil
        if pendingEvt then
            table.insert(lowerChildren, UI.Button {
                text = "⚡ " .. (pendingEvt.title or "聚落事件"),
                variant = "primary",
                width = "100%", height = 44,
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    local evt = state.flow.pending_settlement_event
                    state.flow.pending_settlement_event = nil
                    SettlementEventPool.set_cooldown(state, evt.id)
                    router.navigate("event", {
                        event = evt,
                        source = "settlement",
                    })
                end,
            })
        end

        -- NPC 拜访
        local npc = NpcManager.get_npc_for_settlement(nodeId)
        if npc then
            local canVisit, visitReason = NpcManager.can_visit(state, npc.id)
            table.insert(lowerChildren, UI.Button {
                text = canVisit
                    and (npc.icon .. " 拜访 " .. npc.name)
                    or  (npc.icon .. " " .. npc.name .. "（" .. (visitReason or "不可用") .. "）"),
                variant = "secondary",
                width = "100%", height = 44,
                fontSize = Theme.sizes.font_normal,
                disabled = not canVisit,
                onClick = function(self)
                    if not canVisit then return end
                    local dialogue = NpcManager.start_visit(state, npc.id)
                    if dialogue then
                        router.navigate("npc", { npc_id = npc.id, dialogue = dialogue })
                    end
                end,
            })
        end

        -- 流浪 NPC（聚落内遇见）
        local wanderersHere = WanderingNpc.get_wanderers_at(state, nodeId)
        for _, w in ipairs(wanderersHere) do
            local wid = w.id
            local wnpc = NpcManager.get_npc(wid)
            if wnpc then
                local wCanVisit, wReason = NpcManager.can_visit(state, wid)
                table.insert(lowerChildren, UI.Button {
                    text = wCanVisit
                        and (wnpc.icon .. " 遇见 " .. wnpc.name .. "（" .. wnpc.title .. "）")
                        or  (wnpc.icon .. " " .. wnpc.name .. "（" .. (wReason or "不可用") .. "）"),
                    variant = "secondary",
                    width = "100%", height = 44,
                    fontSize = Theme.sizes.font_normal,
                    disabled = not wCanVisit,
                    onClick = function(self)
                        if not wCanVisit then return end
                        local dialogue = NpcManager.start_visit(state, wid)
                        if dialogue then
                            router.navigate("npc", { npc_id = wid, dialogue = dialogue })
                        end
                    end,
                })
            end
        end

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

        -- 篝火
        local canCamp, campReason = Campfire.can_start(state)
        table.insert(lowerChildren, UI.Button {
            text = canCamp and "🔥 篝火休憩" or ("🔥 篝火（" .. (campReason or "不可用") .. "）"),
            variant = "secondary",
            width = "100%", height = 44,
            fontSize = Theme.sizes.font_normal,
            disabled = not canCamp,
            onClick = function(self)
                if not canCamp then return end
                local dialogue, consumed = Campfire.start(state)
                if dialogue then
                    router.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                end
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

    else
        -- 非聚落节点：流浪 NPC 遇见
        local wanderersHere = WanderingNpc.get_wanderers_at(state, nodeId)
        for _, w in ipairs(wanderersHere) do
            local wid = w.id
            local wnpc = NpcManager.get_npc(wid)
            if wnpc then
                local wCanVisit, wReason = NpcManager.can_visit(state, wid)
                table.insert(lowerChildren, UI.Button {
                    text = wCanVisit
                        and (wnpc.icon .. " 遇见 " .. wnpc.name .. "（" .. wnpc.title .. "）")
                        or  (wnpc.icon .. " " .. wnpc.name .. "（" .. (wReason or "不可用") .. "）"),
                    variant = "secondary",
                    width = "100%", height = 44,
                    fontSize = Theme.sizes.font_normal,
                    disabled = not wCanVisit,
                    onClick = function(self)
                        if not wCanVisit then return end
                        local dialogue = NpcManager.start_visit(state, wid)
                        if dialogue then
                            router.navigate("npc", { npc_id = wid, dialogue = dialogue })
                        end
                    end,
                })
            end
        end

        -- 非聚落节点：出发按钮（如有订单）
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

        -- 篝火（非聚落节点）
        local canCamp, campReason = Campfire.can_start(state)
        table.insert(lowerChildren, UI.Button {
            text = canCamp and "🔥 篝火休憩" or ("🔥 篝火（" .. (campReason or "不可用") .. "）"),
            variant = "secondary",
            width = "100%", height = 44,
            fontSize = Theme.sizes.font_normal,
            disabled = not canCamp,
            onClick = function(self)
                if not canCamp then return end
                local dialogue, consumed = Campfire.start(state)
                if dialogue then
                    router.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                end
            end,
        })

        -- 资源点特殊行动：搜刮此地
        if NODE_EXPLORE_ROOM[nodeId] then
            table.insert(lowerChildren, UI.Button {
                text = "🔍 搜刮此地",
                variant = "secondary",
                width = "100%", height = 44,
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    router.navigate("explore", { room_id = NODE_EXPLORE_ROOM[nodeId] })
                end,
            })
        end
    end

    -- 探索区域已迁移到地图页面（screen_map）

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
    table.insert(contentChildren, UI.Panel {
        id = "travelStrip",
        width = "100%", padding = 14,
        backgroundColor = { 28, 42, 58, 240 },
        borderRadius = Theme.sizes.radius,
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

    -- ── 车内日常对话气泡 ──
    local chatterWidget = createChatterBubble(state)
    if chatterWidget then
        table.insert(contentChildren, chatterWidget)
    end

    -- ── 收音机面板 ──
    table.insert(contentChildren, createRadioPanel(state))

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
            local name = g and g.name or gid
            local committed = CargoUtils.get_committed(state, gid)
            if committed > 0 then
                name = name .. " x" .. count .. "(委" .. committed .. ")"
            else
                name = name .. " x" .. count
            end
            table.insert(items, name)
        end
    end
    local text = #items > 0 and table.concat(items, " · ") or "空"

    local used = CargoUtils.get_cargo_used(state)
    local hasShortage = CargoUtils.has_any_shortage(state)

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
        UI.Label {
            text = text,
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_primary,
        },
    }

    if hasShortage then
        table.insert(cargoChildren, UI.Label {
            text = "⚠ 委托货物不足",
            fontSize = Theme.sizes.font_tiny,
            fontColor = Theme.colors.danger,
        })
    end

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        borderWidth = hasShortage and 1 or 0,
        borderColor = hasShortage and Theme.colors.danger or nil,
        gap = 2,
        children = cargoChildren,
    }
end

-- ============================================================
-- 成长目标（中期目标概览）
-- ============================================================
function createProgressCard(state)
    local items = {}

    -- 1. 货车模块升级进度
    local totalLv, maxLv = 0, 0
    for _, mid in ipairs(Modules.ORDER) do
        totalLv = totalLv + Modules.get_level(state, mid)
        maxLv   = maxLv + Modules.DEFS[mid].max_level
    end
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "模块升级",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = totalLv .. " / " .. maxLv,
                fontSize = Theme.sizes.font_small,
                fontColor = totalLv >= maxLv and Theme.colors.success or Theme.colors.info,
            },
        },
    })

    -- 2. 各势力好感进度（按势力分组）
    local Factions = require("settlement/factions")
    local factionOrder = { "farm", "tech", "scav", "scholar" }
    local gwParts = {}
    for _, fid in ipairs(factionOrder) do
        local fi = Factions.get_faction_info(fid)
        if fi then
            -- 显示首都好感等级
            local capSett = state.settlements[fi.capital]
            local capGw   = capSett and capSett.goodwill or 0
            local capInfo = Goodwill.get_info(capGw)
            local capNode = Graph.get_node(fi.capital)
            local capName = capNode and capNode.name or fi.capital
            -- 缩短名称
            if #capName > 6 then capName = string.sub(capName, 1, 6) end
            table.insert(gwParts, fi.icon .. capName .. " Lv" .. capInfo.level)
        end
    end
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "势力好感",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = table.concat(gwParts, " "),
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    -- 3. 角色关系 + 阶段名
    local _, stageLabel = Campfire.get_relation_stage(state)
    local charParts = {}
    for _, cid in ipairs({ "linli", "taoxia" }) do
        local char = state.character[cid]
        local rel  = char and char.relation or 0
        local cName = cid == "linli" and "林砾" or "陶夏"
        table.insert(charParts, cName .. " " .. math.floor(rel))
    end
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "角色关系",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center",
                children = {
                    UI.Label {
                        text = table.concat(charParts, "  "),
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = "·" .. stageLabel,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.accent,
                    },
                },
            },
        },
    })

    -- 4. 篝火 / 回忆
    local campCount = state.narrative and state.narrative.campfire_count or 0
    local memCount  = state.narrative and state.narrative.memories
        and #state.narrative.memories or 0
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "篝火·回忆",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = campCount .. " 次篝火  " .. memCount .. " 段回忆",
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    -- 5. 任务线索
    local activeQuests = QuestLog.active_count(state)
    local completedQuests = #QuestLog.get_completed(state)
    local questTotal = activeQuests + completedQuests
    if questTotal > 0 then
        table.insert(items, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            onClick = function(self)
                router.navigate("quest_log")
            end,
            children = {
                UI.Label {
                    text = "📜 任务线索",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                },
                UI.Label {
                    text = activeQuests .. " 进行中  " .. completedQuests .. " 已完成  ›",
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = activeQuests > 0
                        and Theme.colors.info or Theme.colors.text_primary,
                },
            },
        })
    end

    -- 6. 总里程
    local trips = state.stats and state.stats.total_trips or 0
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "完成行程",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = trips .. " 趟",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    -- 组合
    table.insert(items, 1, UI.Label {
        text = "成长目标",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 4,
        children = items,
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

-- ============================================================
-- 车内日常对话气泡（行驶中）
-- 没有对话时返回 nil，不占布局空间
-- ============================================================
function createChatterBubble(state)
    local cur = Chatter.get_current(state)
    if not cur then return nil end

    local speakerNames = { linli = "林砾", taoxia = "陶夏" }
    local speakerColors = {
        linli  = { 80, 140, 200, 255 },
        taoxia = { 200, 130, 80, 255 },
    }
    local name  = speakerNames[cur.speaker] or cur.speaker
    local color = speakerColors[cur.speaker] or Theme.colors.accent

    local bubbleChildren = {
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
        table.insert(bubbleChildren, UI.Button {
            text = cur.response.label or "回应",
            variant = "secondary",
            height = 30,
            fontSize = Theme.sizes.font_small,
            onClick = function(self)
                Chatter.respond(state)
            end,
        })
    end

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = { 32, 38, 48, 230 },
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = color,
        gap = 4,
        children = bubbleChildren,
    }
end

-- ============================================================
-- 收音机面板（行驶中始终显示，可开关）
-- ============================================================
function createRadioPanel(state)
    local isOn    = Radio.is_on(state)
    local channel = Radio.get_channel(state)
    local cur     = Radio.get_current(state)

    local radioChildren = {}

    -- 顶栏：标题 + 开关按钮
    table.insert(radioChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "📻 收音机",
                fontSize = Theme.sizes.font_small,
                fontColor = isOn and Theme.colors.info or Theme.colors.text_dim,
            },
            UI.Button {
                text = isOn and "关闭" or "开启",
                variant = isOn and "secondary" or "primary",
                height = 28,
                fontSize = Theme.sizes.font_tiny,
                onClick = function(self)
                    Radio.toggle(state)
                end,
            },
        },
    })

    if isOn then
        -- 频道切换行
        local channelButtons = {}
        for _, ch in ipairs(Radio.CHANNELS) do
            local isActive = (ch == channel)
            table.insert(channelButtons, UI.Button {
                text = Radio.CHANNEL_NAMES[ch] or ch,
                variant = isActive and "primary" or "secondary",
                height = 26,
                fontSize = Theme.sizes.font_tiny,
                flexGrow = 1,
                onClick = function(self)
                    Radio.switch_channel(state, ch)
                end,
            })
        end
        table.insert(radioChildren, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6,
            children = channelButtons,
        })

        -- 当前播报内容
        if cur then
            table.insert(radioChildren, UI.Label {
                text = cur.text,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
            })
            -- 有奖励且未领取
            if cur.reward and not cur.reward_claimed then
                local rewardLabel = "领取"
                if cur.reward.type == "credits" then
                    rewardLabel = "领取 +$" .. tostring(cur.reward.value or 0)
                elseif cur.reward.type == "info" then
                    rewardLabel = "记下情报"
                end
                table.insert(radioChildren, UI.Button {
                    text = rewardLabel,
                    variant = "primary",
                    height = 28,
                    fontSize = Theme.sizes.font_tiny,
                    onClick = function(self)
                        Radio.claim_reward(state)
                    end,
                })
            end
        else
            table.insert(radioChildren, UI.Label {
                text = "...",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
                textAlign = "center",
            })
        end
    end

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = isOn and { 28, 36, 28, 220 } or { 36, 36, 36, 180 },
        borderRadius = Theme.sizes.radius,
        borderWidth = 1,
        borderColor = isOn and { 60, 100, 60, 200 } or Theme.colors.border,
        gap = 6,
        children = radioChildren,
    }
end

return M

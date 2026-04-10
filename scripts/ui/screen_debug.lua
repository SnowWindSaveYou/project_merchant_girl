--- 调试作弊面板
--- 按 P 三次打开，提供旅行加速、货物调整、金币调整等功能
local UI         = require("urhox-libs/UI")
local Theme      = require("ui/theme")
local F          = require("ui/ui_factory")
local Goods      = require("economy/goods")
local Flow       = require("core/flow")
local RoutePlanner = require("map/route_planner")
local CargoUtils = require("economy/cargo_utils")
local EventPool  = require("events/event_pool")
local Graph      = require("map/world_graph")
local Goodwill   = require("settlement/goodwill")
local Farm       = require("settlement/farm")
local Intel      = require("settlement/intel")
local BlackMarket = require("settlement/black_market")
local Archives   = require("settlement/archives")
local Flags      = require("core/flags")
local Tutorial   = require("narrative/tutorial")

local M = {}
---@type table
local router = nil

-- 事件列表展开状态
local eventListExpanded = false

-- ============================================================
-- 辅助：带 +/- 按钮的数值调节行
-- ============================================================

---@param label string
---@param valueText string
---@param onMinus function
---@param onPlus function
---@param extraChildren? table
local function adjustRow(label, valueText, onMinus, onPlus, extraChildren)
    local row = {
        UI.Label {
            text = label,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            width = 100,
        },
        UI.Button {
            text = "−10", width = 48, height = 32,
            fontSize = Theme.sizes.font_small,
            variant = "outline",
            onClick = function() onMinus(10) end,
        },
        UI.Button {
            text = "−1", width = 40, height = 32,
            fontSize = Theme.sizes.font_small,
            variant = "outline",
            onClick = function() onMinus(1) end,
        },
        UI.Label {
            text = valueText,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.accent,
            width = 50, textAlign = "center",
        },
        UI.Button {
            text = "+1", width = 40, height = 32,
            fontSize = Theme.sizes.font_small,
            variant = "outline",
            onClick = function() onPlus(1) end,
        },
        UI.Button {
            text = "+10", width = 48, height = 32,
            fontSize = Theme.sizes.font_small,
            variant = "outline",
            onClick = function() onPlus(10) end,
        },
    }
    if extraChildren then
        for _, c in ipairs(extraChildren) do
            table.insert(row, c)
        end
    end
    return UI.Panel {
        width = "100%", flexDirection = "row",
        alignItems = "center", gap = 6,
        children = row,
    }
end

-- ============================================================
-- 页面创建
-- ============================================================

function M.create(state, params, r)
    router = r
    return M._build(state)
end

function M._build(state)
    local sections = {}

    -- ── 标题栏 ──
    table.insert(sections, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 8,
        borderBottom = 1, borderColor = Theme.colors.divider,
        children = {
            UI.Label {
                text = "DEBUG PANEL",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.danger,
                fontWeight = "bold",
            },
            UI.Button {
                text = "关闭", width = 64, height = 32,
                fontSize = Theme.sizes.font_small,
                variant = "danger",
                onClick = function()
                    M._close(state)
                end,
            },
        },
    })

    -- ── 0. 教程快捷 ──
    local tutPhase = Tutorial.get_phase(state)
    local tutComplete = Tutorial.is_complete(state)
    local tutChildren = {
        UI.Label {
            text = "当前阶段: " .. tutPhase .. (tutComplete and " (已完成)" or ""),
            fontSize = Theme.sizes.font_normal,
            fontColor = tutComplete and Theme.colors.text_dim or Theme.colors.warning,
        },
    }
    if not tutComplete then
        table.insert(tutChildren, UI.Button {
            text = "一键完成所有教程",
            width = "100%", height = 40,
            fontSize = Theme.sizes.font_normal,
            variant = "danger",
            onClick = function()
                -- 设置所有教程相关 flags
                local tutFlags = {
                    "tutorial_started",
                    "tutorial_arrived_greenhouse",
                    "tutorial_campfire_done",
                    "tutorial_explore_guided",
                    "tutorial_arrived_tower",
                    "tutorial_explore_home_shown",
                    "tutorial_map_explore_shown",
                    "tutorial_shop_intro",
                    "tutorial_truck_intro",
                    "tutorial_radio_intro",
                    "tutorial_auto_plan_intro",
                    "tutorial_explore_scavenge",
                }
                for _, f in ipairs(tutFlags) do
                    Flags.set(state, f)
                end
                -- 清理教程订单
                local book = state.economy and state.economy.order_book or {}
                local cleaned = {}
                for _, o in ipairs(book) do
                    if not o.is_tutorial then
                        table.insert(cleaned, o)
                    end
                end
                if state.economy then
                    state.economy.order_book = cleaned
                end
                print("[Debug] All tutorials completed, " .. #tutFlags .. " flags set")
                M._refresh(state)
            end,
        })
    end
    table.insert(sections, M._sectionCard("教程", tutChildren))

    -- ── 1. 金币调整 ──
    table.insert(sections, M._sectionCard("金币", {
        adjustRow(
            "Credits",
            tostring(state.economy.credits),
            function(n)
                state.economy.credits = math.max(0, state.economy.credits - n)
                M._refresh(state)
            end,
            function(n)
                state.economy.credits = state.economy.credits + n
                M._refresh(state)
            end,
            {
                UI.Button {
                    text = "+100", width = 52, height = 32,
                    fontSize = Theme.sizes.font_small,
                    variant = "primary",
                    onClick = function()
                        state.economy.credits = state.economy.credits + 100
                        M._refresh(state)
                    end,
                },
                UI.Button {
                    text = "+1000", width = 56, height = 32,
                    fontSize = Theme.sizes.font_small,
                    variant = "primary",
                    onClick = function()
                        state.economy.credits = state.economy.credits + 1000
                        M._refresh(state)
                    end,
                },
            }
        ),
    }))

    -- ── 2. 旅行加速 ──
    local travelChildren = {}
    local phase = Flow.get_phase(state)
    if phase == Flow.Phase.TRAVELLING and state.flow.route_plan then
        local progress = RoutePlanner.get_progress(state.flow.route_plan)
        local pct = math.floor(progress * 100)
        table.insert(travelChildren, UI.Label {
            text = "当前进度: " .. pct .. "%",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_primary,
        })
        table.insert(travelChildren, UI.Panel {
            width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap",
            children = {
                UI.Button {
                    text = "推进 +20%", height = 36,
                    fontSize = Theme.sizes.font_small,
                    variant = "primary",
                    onClick = function()
                        M._advanceTravel(state, 0.20)
                    end,
                },
                UI.Button {
                    text = "推进 +50%", height = 36,
                    fontSize = Theme.sizes.font_small,
                    variant = "primary",
                    onClick = function()
                        M._advanceTravel(state, 0.50)
                    end,
                },
                UI.Button {
                    text = "直接到达", height = 36,
                    fontSize = Theme.sizes.font_small,
                    variant = "danger",
                    onClick = function()
                        M._advanceTravel(state, 1.0)
                    end,
                },
            },
        })
    else
        table.insert(travelChildren, UI.Label {
            text = "当前未在旅途中（阶段: " .. tostring(phase) .. "）",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_dim,
        })
    end
    table.insert(sections, M._sectionCard("旅行加速", travelChildren))

    -- ── 3. 货物调整 ──
    local cargoChildren = {}
    for _, g in ipairs(Goods.ALL) do
        local gid = g.id
        local current = state.truck.cargo[gid] or 0
        local committed = CargoUtils.get_committed(state, gid)
        local valText = tostring(current)
        if committed > 0 then
            valText = valText .. " (委" .. committed .. ")"
        end
        table.insert(cargoChildren, adjustRow(
            g.name,
            valText,
            function(n)
                local cur = state.truck.cargo[gid] or 0
                state.truck.cargo[gid] = math.max(0, cur - n)
                if state.truck.cargo[gid] == 0 then
                    state.truck.cargo[gid] = nil
                end
                M._refresh(state)
            end,
            function(n)
                local cur = state.truck.cargo[gid] or 0
                state.truck.cargo[gid] = cur + n
                M._refresh(state)
            end
        ))
    end
    table.insert(sections, M._sectionCard("货物", cargoChildren))

    -- ── 4. 燃料 / 耐久 ──
    local truckChildren = {
        adjustRow(
            "燃料",
            tostring(math.floor(state.truck.fuel)),
            function(n)
                state.truck.fuel = math.max(0, state.truck.fuel - n)
                M._refresh(state)
            end,
            function(n)
                state.truck.fuel = math.min(state.truck.fuel_max, state.truck.fuel + n)
                M._refresh(state)
            end
        ),
        adjustRow(
            "耐久",
            tostring(math.floor(state.truck.durability)),
            function(n)
                state.truck.durability = math.max(0, state.truck.durability - n)
                M._refresh(state)
            end,
            function(n)
                state.truck.durability = math.min(state.truck.durability_max, state.truck.durability + n)
                M._refresh(state)
            end
        ),
    }
    table.insert(sections, M._sectionCard("货车", truckChildren))

    -- ── 4.5 地图节点 ──
    local mapChildren = {}
    local knownCount = 0
    local totalCount = #Graph.NODES
    for _, node in ipairs(Graph.NODES) do
        if state.map.known_nodes[node.id] then
            knownCount = knownCount + 1
        end
    end
    table.insert(mapChildren, UI.Label {
        text = "已知节点: " .. knownCount .. " / " .. totalCount,
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_primary,
    })
    table.insert(mapChildren, UI.Panel {
        width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap",
        children = {
            UI.Button {
                text = "解锁全部节点", height = 36,
                fontSize = Theme.sizes.font_small,
                variant = "primary",
                onClick = function()
                    for _, node in ipairs(Graph.NODES) do
                        state.map.known_nodes[node.id] = true
                    end
                    print("[Debug] All " .. totalCount .. " map nodes unlocked")
                    M._refresh(state)
                end,
            },
            UI.Button {
                text = "重置为初始", height = 36,
                fontSize = Theme.sizes.font_small,
                variant = "danger",
                onClick = function()
                    state.map.known_nodes = {
                        greenhouse = true,
                        tower      = true,
                        crossroads = true,
                    }
                    print("[Debug] Map nodes reset to initial 3")
                    M._refresh(state)
                end,
            },
        },
    })
    table.insert(sections, M._sectionCard("地图节点", mapChildren))

    -- ── 5. 聚落子系统调试 ──
    local settlementChildren = {}

    -- 好感度调整（四大据点）
    local SETTLE_IDS = {
        { id = "greenhouse",  name = "温室" },
        { id = "tower",       name = "北穹塔台" },
        { id = "ruins_camp",  name = "废墟营地" },
        { id = "bell_tower",  name = "钟楼书院" },
    }
    table.insert(settlementChildren, UI.Label {
        text = "好感度",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
    })
    for _, s in ipairs(SETTLE_IDS) do
        local sid = s.id
        local sett = state.settlements[sid]
        local gw = sett and sett.goodwill or 0
        local info = Goodwill.get_info(gw)
        table.insert(settlementChildren, adjustRow(
            s.name .. " Lv" .. info.level,
            tostring(gw),
            function(n)
                if state.settlements[sid] then
                    state.settlements[sid].goodwill = math.max(0, (state.settlements[sid].goodwill or 0) - n)
                end
                M._refresh(state)
            end,
            function(n)
                if state.settlements[sid] then
                    state.settlements[sid].goodwill = math.min(100, (state.settlements[sid].goodwill or 0) + n)
                end
                M._refresh(state)
            end
        ))
    end

    -- 培育农场
    table.insert(settlementChildren, UI.Label {
        text = "培育农场",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
        marginTop = 8,
    })
    local farmSlots = Farm.get_slots(state)
    for i, slot in ipairs(farmSlots) do
        local slotText = slot.crop_id
            and (slot.crop_id .. " " .. (slot.trips_elapsed or 0) .. "/" .. (slot.growth_trips or "?"))
            or "空"
        table.insert(settlementChildren, UI.Panel {
            width = "100%", flexDirection = "row",
            alignItems = "center", gap = 6,
            children = {
                UI.Label {
                    text = "槽" .. i .. ": " .. slotText,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_primary,
                    flexGrow = 1,
                },
                UI.Button {
                    text = "推进1趟", width = 72, height = 30,
                    fontSize = Theme.sizes.font_tiny,
                    variant = "outline",
                    onClick = function()
                        Farm.advance_trip(state)
                        M._refresh(state)
                    end,
                },
                UI.Button {
                    text = "清空", width = 48, height = 30,
                    fontSize = Theme.sizes.font_tiny,
                    variant = "danger",
                    onClick = function()
                        local slots = Farm.get_slots(state)
                        if slots[i] then
                            slots[i] = { crop_id = nil }
                        end
                        M._refresh(state)
                    end,
                },
            },
        })
    end

    -- 情报站
    local intelData = Intel.get_route_data(state)
    local intelExchanged, _ = Intel.get_stats(state)
    table.insert(settlementChildren, UI.Label {
        text = "情报站",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
        marginTop = 8,
    })
    table.insert(settlementChildren, adjustRow(
        "数据点",
        tostring(intelData),
        function(n)
            local st = state.settlements.tower
            if st and st.intel then
                st.intel.route_data = math.max(0, st.intel.route_data - n)
            end
            M._refresh(state)
        end,
        function(n)
            local st = state.settlements.tower
            if st and st.intel then
                st.intel.route_data = st.intel.route_data + n
            end
            M._refresh(state)
        end
    ))
    local activeIntel = Intel.get_active_intel(state)
    table.insert(settlementChildren, UI.Label {
        text = "活跃情报: " .. #activeIntel .. "  累计兑换: " .. intelExchanged,
        fontSize = Theme.sizes.font_small,
        fontColor = Theme.colors.text_dim,
    })

    -- 黑市
    local marketItems = BlackMarket.get_items(state)
    local marketTrades, marketSaved = BlackMarket.get_stats(state)
    table.insert(settlementChildren, UI.Label {
        text = "黑市",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
        marginTop = 8,
    })
    table.insert(settlementChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        alignItems = "center", gap = 8,
        children = {
            UI.Label {
                text = "货架: " .. #marketItems .. " 件  交易: " .. marketTrades .. "  省: $" .. marketSaved,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
                flexGrow = 1,
            },
            UI.Button {
                text = "强制刷新", width = 80, height = 30,
                fontSize = Theme.sizes.font_tiny,
                variant = "primary",
                onClick = function()
                    -- 重置 last_refresh 强制刷新
                    local mkt = state.settlements.ruins_camp
                        and state.settlements.ruins_camp.market
                    if mkt then mkt.last_refresh = -1 end
                    BlackMarket.refresh(state)
                    M._refresh(state)
                end,
            },
        },
    })

    -- 档案
    local archRead, archTotal = Archives.get_progress(state)
    table.insert(settlementChildren, UI.Label {
        text = "档案",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
        marginTop = 8,
    })
    table.insert(settlementChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        alignItems = "center", gap = 8,
        children = {
            UI.Label {
                text = "已读: " .. archRead .. "/" .. archTotal,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
                flexGrow = 1,
            },
            UI.Button {
                text = "重置已读", width = 80, height = 30,
                fontSize = Theme.sizes.font_tiny,
                variant = "danger",
                onClick = function()
                    if state.narrative then
                        state.narrative.archives_read = {}
                    end
                    M._refresh(state)
                end,
            },
        },
    })

    table.insert(sections, M._sectionCard("聚落子系统", settlementChildren))

    -- ── 6. 事件触发（折叠/展开） ──
    local eventChildren = {}
    EventPool._load_config()
    local allEvents = EventPool.EVENTS

    -- 标题行：点击展开/收起
    table.insert(eventChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "共 " .. #allEvents .. " 个事件",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
            UI.Button {
                text = eventListExpanded and "收起" or "展开列表",
                width = 80, height = 30,
                fontSize = Theme.sizes.font_small,
                variant = "outline",
                onClick = function()
                    eventListExpanded = not eventListExpanded
                    M._refresh(state)
                end,
            },
        },
    })

    -- 展开时显示完整事件列表
    if eventListExpanded then
        for _, evt in ipairs(allEvents) do
            local evtCapture = evt
            table.insert(eventChildren, UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 8,
                paddingVertical = 4,
                borderBottom = 1, borderColor = Theme.colors.divider,
                children = {
                    UI.Panel {
                        flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Label {
                                text = evt.title or evt.id,
                                fontSize = Theme.sizes.font_normal,
                                fontColor = Theme.colors.text_primary,
                            },
                            UI.Label {
                                text = evt.id .. (evt.pool and (" [" .. evt.pool .. "]") or ""),
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.text_dim,
                            },
                        },
                    },
                    UI.Button {
                        text = "触发", width = 56, height = 32,
                        fontSize = Theme.sizes.font_small,
                        variant = "primary",
                        onClick = function()
                            if router then
                                router.navigate("event", { event = evtCapture })
                            end
                        end,
                    },
                },
            })
        end
    end
    table.insert(sections, M._sectionCard("事件触发", eventChildren))

    -- ── 组装页面 ──
    return UI.Panel {
        width = "100%", height = "100%",
        backgroundColor = { 20, 18, 16, 240 },
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%",
                children = {
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Panel {
                                width = "100%", padding = Theme.sizes.padding,
                                gap = 12,
                                children = sections,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================
-- 区块卡片
-- ============================================================

function M._sectionCard(title, children)
    local all = {
        UI.Label {
            text = title,
            fontSize = Theme.sizes.font_large,
            fontColor = Theme.colors.accent,
            fontWeight = "bold",
            paddingBottom = 4,
        },
    }
    for _, c in ipairs(children) do
        table.insert(all, c)
    end
    return F.card {
        width = "100%", padding = 12,
        gap = 8,
        children = all,
    }
end

-- ============================================================
-- 操作
-- ============================================================

--- 推进旅行进度（设置标志位，由 main 循环驱动到达逻辑）
function M._advanceTravel(state, fraction)
    local plan = state.flow.route_plan
    if not plan then return end
    if fraction >= 1.0 then
        -- 直接到达：设置标志位，main 循环逐段触发到达
        state._debug_instant_arrive = true
        print("[Debug] Instant arrive requested")
    else
        -- 部分推进：存储需要快进的秒数
        local totalTime = plan.total_time or 0
        local advanceSec = totalTime * fraction
        state._debug_advance_secs = (state._debug_advance_secs or 0) + advanceSec
        print("[Debug] Travel fast-forward +" .. math.floor(advanceSec) .. "s")
    end
    -- 关闭面板回到首页，让 main 循环处理行驶逻辑
    if router then router.navigate("home") end
end

--- 关闭面板，回到之前的页面
function M._close(state)
    if not router then return end
    local phase = Flow.get_phase(state)
    if phase == Flow.Phase.TRAVELLING then
        router.navigate("home")
    elseif phase == Flow.Phase.IDLE or phase == Flow.Phase.SETTLEMENT then
        router.navigate("home")
    else
        router.navigate("home")
    end
end

--- 刷新面板（重新构建 UI）
function M._refresh(state)
    if not router then return end
    router.refresh()
end

return M

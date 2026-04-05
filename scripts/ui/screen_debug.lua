--- 调试作弊面板
--- 按 P 三次打开，提供旅行加速、货物调整、金币调整等功能
local UI         = require("urhox-libs/UI")
local Theme      = require("ui/theme")
local Goods      = require("economy/goods")
local Flow       = require("core/flow")
local RoutePlanner = require("map/route_planner")
local CargoUtils = require("economy/cargo_utils")
local EventPool  = require("events/event_pool")

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

    -- ── 5. 事件触发（折叠/展开） ──
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
    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
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

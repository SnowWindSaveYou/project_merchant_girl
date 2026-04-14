--- 地图 UI 面板与模态框
--- 从 screen_map.lua 提取：节点弹窗、未知节点弹窗、自动计划弹窗、路线面板、探索面板
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Intel        = require("settlement/intel")
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local Flags        = require("core/flags")
local SketchBorder = require("ui/sketch_border")
local SoundMgr     = require("ui/sound_manager")
local DialoguePool = require("narrative/dialogue_pool")
local MapMode      = require("map/map_mode")

local M = {}

-- ============================================================
-- 显示常量
-- ============================================================
local NODE_ICON = {
    settlement = "🏘", resource = "📦", transit = "🔀",
    hazard     = "⚠",  story    = "📡",
}
local EDGE_LABEL      = { main_road = "主干道", path = "小径", shortcut = "捷径" }
local DANGER_STR      = { safe = "低", normal = "中", danger = "高" }
local EDGE_TYPE_LABEL = { main_road = "公路", path = "小径", shortcut = "捷径" }
local DANGER_LABEL_MAP = { safe = "低", normal = "中", danger = "高" }
local DANGER_COLOR    = {
    safe   = Theme.colors.success,
    normal = Theme.colors.accent,
    danger = Theme.colors.danger,
}
local NODE_TYPE_LABEL = {
    settlement = "聚落", resource = "资源点", transit = "中转站",
    hazard = "危险区", story = "遗迹",
}

-- ============================================================
-- 模块级引用（由 init 设置）
-- ============================================================
---@type table|nil
local state_  = nil
---@type table|nil
local router_ = nil
---@type table|nil
local modal_  = nil
---@type table|nil
local routePanel_   = nil
---@type table|nil
local explorePanel_ = nil
-- 折叠状态
local exploreCollapsed_ = {
    unknown = true,
    known   = true,
}

-- ============================================================
-- 初始化 / 状态更新
-- ============================================================

--- 设置模块引用（由 screen_map 的 create 调用）
---@param refs table { state, router, modal, routePanel, explorePanel }
function M.init(refs)
    state_        = refs.state
    router_       = refs.router
    modal_        = refs.modal
    routePanel_   = refs.routePanel
    explorePanel_ = refs.explorePanel
end

--- 每帧更新 state 引用
---@param state table
function M.setState(state)
    state_ = state
end

-- ============================================================
-- 辅助
-- ============================================================
local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then return m .. "分" .. s .. "秒" end
    return s .. "秒"
end

-- ============================================================
-- Modal 弹窗：节点信息
-- ============================================================
function M.openNodeModal(nodeId, cam)
    if not modal_ then return end
    local node = Graph.get_node(nodeId)
    if not node then return end

    local current = state_.map.current_location

    -- 教程锁定
    local tutPhase = Tutorial.get_phase(state_)
    if (tutPhase == Tutorial.Phase.SPAWN or tutPhase == Tutorial.Phase.TRAVEL_TO_GREENHOUSE)
        and nodeId ~= current and nodeId ~= "greenhouse" then
        local root = UI.GetRoot()
        if root then
            local hints = {
                { portrait = Tutorial.AVATAR_LINLI,  speaker = "林砾", text = "先别急，把手头的委托办了再说。" },
                { portrait = Tutorial.AVATAR_TAOXIA, speaker = "陶夏", text = "那边以后再去吧，我们先到温室社区看看。" },
            }
            local hint = hints[math.random(#hints)]
            hint.autoHide = 3
            SpeechBubble.show(root, hint)
        end
        return
    end

    local destSet = OrderBook.get_destination_set(state_)
    local isCur   = nodeId == current
    local isDest  = destSet[nodeId]

    local icon = NODE_ICON[node.type] or "●"
    modal_:SetTitle(icon .. "  " .. node.name)
    modal_:ClearContent()

    -- 状态角标
    if isCur then
        modal_:AddContent(UI.Label {
            text = "📍 当前位置",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.map_current,
            marginBottom = 4,
        })
    elseif isDest then
        modal_:AddContent(UI.Label {
            text = "🎯 订单目标",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.accent,
            marginBottom = 4,
        })
    end

    -- 描述
    modal_:AddContent(UI.Label {
        text = node.desc or "",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
        marginBottom = 8,
    })

    -- 类型标签
    local typeNames = {
        settlement = "聚落", resource = "资源点", transit = "中转站",
        hazard = "危险区域", story = "故事节点",
    }
    modal_:AddContent(UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        marginBottom = 8,
        children = {
            UI.Label {
                text = "类型",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
            UI.Label {
                text = typeNames[node.type] or node.type,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
    local planOrigin = MapMode.getEffectiveOrigin(state_)
    local edge = Graph.get_edge(planOrigin, nodeId)

    if edge then
        local dangerColor = DANGER_STR[edge.danger] == "高"
            and Theme.colors.danger or Theme.colors.info

        modal_:AddContent(UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = Theme.colors.bg_secondary,
            borderRadius = Theme.sizes.radius_small,
            gap = 4,
            children = {
                UI.Label {
                    text = "直达路线",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.info,
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = EDGE_LABEL[edge.type] or edge.type,
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_secondary,
                        },
                        UI.Label {
                            text = edge.travel_time_sec .. "秒 · 燃料" .. edge.fuel_cost,
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_secondary,
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = "危险等级",
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_dim,
                        },
                        UI.Label {
                            text = DANGER_STR[edge.danger] or "?",
                            fontSize = Theme.sizes.font_small,
                            fontColor = dangerColor,
                        },
                    },
                },
            },
        })

        if travelling then
            modal_:AddContent(UI.Panel {
                width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                children = {
                    F.actionBtn {
                        text = "查看路线",
                        variant = "primary", flexGrow = 1, height = 40,
                        onClick = function(self)
                            modal_:Close()
                            MapMode.enterRoutePreview(nodeId, state_, cam, function() M.rebuildPanel(cam) end)
                        end,
                    },
                },
            })
        else
            local canDepart = state_.truck.fuel >= edge.fuel_cost
            modal_:AddContent(UI.Panel {
                width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                children = {
                    F.actionBtn {
                        text = canDepart and "直接出发" or "燃料不足",
                        variant = "primary", flexGrow = 1, height = 40,
                        disabled = not canDepart,
                        sound = false,
                        onClick = function(self)
                            modal_:Close()
                            local plan = RoutePlanner.auto_plan(state_, nodeId, "fastest")
                            if plan then
                                SoundMgr.play("depart")
                                if not MapMode.tryTutorialDeparture(plan, state_, router_) then
                                    Flow.start_travel(state_, plan)
                                    router_.navigate("home")
                                end
                            end
                        end,
                    },
                    F.actionBtn {
                        text = "查看路线",
                        variant = "secondary", flexGrow = 1, height = 40,
                        onClick = function(self)
                            modal_:Close()
                            MapMode.enterRoutePreview(nodeId, state_, cam, function() M.rebuildPanel(cam) end)
                        end,
                    },
                },
            })
        end
    elseif nodeId ~= planOrigin then
        local path = Graph.find_path(planOrigin, nodeId, state_)
        if path and #path > 1 then
            modal_:AddContent(UI.Panel {
                width = "100%", padding = 10,
                backgroundColor = Theme.colors.bg_secondary,
                borderRadius = Theme.sizes.radius_small,
                children = {
                    UI.Label {
                        text = "经过 " .. (#path - 1) .. " 站可达",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.info,
                    },
                },
            })

            if travelling then
                modal_:AddContent(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        F.actionBtn {
                            text = "规划新路线",
                            variant = "primary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                modal_:Close()
                                MapMode.enterRoutePreview(nodeId, state_, cam, function() M.rebuildPanel(cam) end)
                            end,
                        },
                    },
                })
            else
                modal_:AddContent(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        F.actionBtn {
                            text = "规划路线",
                            variant = "primary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                modal_:Close()
                                MapMode.enterRoutePreview(nodeId, state_, cam, function() M.rebuildPanel(cam) end)
                            end,
                        },
                        F.actionBtn {
                            text = "手动规划",
                            variant = "secondary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                modal_:Close()
                                MapMode.enterManualPlan(nodeId, state_, function() M.rebuildPanel(cam) end)
                            end,
                        },
                    },
                })
            end
        else
            modal_:AddContent(UI.Panel {
                width = "100%", padding = 10,
                backgroundColor = Theme.colors.bg_secondary,
                borderRadius = Theme.sizes.radius_small,
                children = {
                    UI.Label {
                        text = "暂不可达",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_dim,
                    },
                },
            })
        end
    end

    modal_:Open()
end

-- ============================================================
-- Modal 弹窗：未知节点探索
-- ============================================================
function M.openUnknownNodeModal(nodeId)
    if not modal_ or not state_ then return end
    local node = Graph.get_node(nodeId)
    if not node then return end
    local current = state_.map.current_location

    -- 教程锁定
    local tutPhase = Tutorial.get_phase(state_)
    if tutPhase == Tutorial.Phase.SPAWN or tutPhase == Tutorial.Phase.TRAVEL_TO_GREENHOUSE then
        local root = UI.GetRoot()
        if root then
            local hints = {
                { portrait = Tutorial.AVATAR_LINLI,  speaker = "林砾", text = "未知区域先不急，等把这单跑完再探索。" },
                { portrait = Tutorial.AVATAR_TAOXIA, speaker = "陶夏", text = "感觉那边挺危险的……我们还是先完成委托吧。" },
            }
            local hint = hints[math.random(#hints)]
            hint.autoHide = 3
            SpeechBubble.show(root, hint)
        end
        return
    end

    local edge = Graph.get_edge(current, nodeId)
    if not edge then return end

    -- 条件探索旗标
    local flagLocked = false
    if node.explore_flag then
        local flags = state_.flags or {}
        flagLocked = not flags[node.explore_flag]
    end

    local title = flagLocked and ("🔒 " .. node.name) or "❓ 未知区域"
    modal_:SetTitle(title)
    modal_:ClearContent()

    if flagLocked then
        modal_:AddContent(UI.Label {
            text = "需要更多情报才能前往此区域",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_dim,
            marginBottom = 8,
        })
    else
        modal_:AddContent(UI.Label {
            text = "前方是未探索的区域，是否前往探索？",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            marginBottom = 8,
        })
    end

    local fuelOk = state_.truck.fuel >= edge.fuel_cost
    local dColor = DANGER_COLOR[edge.danger] or Theme.colors.text_dim

    modal_:AddContent(UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_secondary,
        borderRadius = Theme.sizes.radius_small,
        gap = 4,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = EDGE_LABEL[edge.type] or edge.type,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = edge.travel_time_sec .. "秒 · 燃料" .. edge.fuel_cost,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                },
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = "危险等级",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_dim,
                    },
                    UI.Label {
                        text = DANGER_STR[edge.danger] or "?",
                        fontSize = Theme.sizes.font_small,
                        fontColor = dColor,
                    },
                },
            },
        },
    })

    if not fuelOk then
        modal_:AddContent(UI.Label {
            text = "⛽ 当前燃料 " .. math.floor(state_.truck.fuel) .. "%，需要 " .. edge.fuel_cost .. "%",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.danger,
            marginTop = 4,
        })
    end

    local canExplore = fuelOk and not flagLocked
    modal_:AddContent(F.actionBtn {
        text = flagLocked and "🔒 需要情报" or (fuelOk and "前往探索" or "燃料不足"),
        variant = canExplore and "primary" or "secondary",
        height = 40, marginTop = 8,
        disabled = not canExplore,
        onClick = function(self)
            modal_:Close()
            local ok, err = Flow.start_exploration(state_, nodeId)
            if ok then
                router_.navigate("home")
            else
                print("[Explore] " .. (err or "failed"))
            end
        end,
    })

    modal_:Open()
end

-- ============================================================
-- Modal 弹窗：自动计划设置
-- ============================================================
local function showAutoPlanTutorialStep(parent, state, steps, index, onComplete)
    if index > #steps then
        Flags.set(state, "tutorial_auto_plan_intro")
        if onComplete then onComplete() end
        return
    end
    local step = steps[index]
    SpeechBubble.show(parent, {
        portrait  = step.portrait,
        speaker   = step.speaker,
        text      = step.text,
        autoHide  = 0,
        onDismiss = function()
            showAutoPlanTutorialStep(parent, state, steps, index + 1, onComplete)
        end,
    })
end

function M.openAutoPlanModal()
    if not modal_ or not state_ then return end

    local introSteps = Tutorial.get_auto_plan_intro_steps(state_)
    if introSteps then
        local root = UI.GetRoot()
        if root then
            showAutoPlanTutorialStep(root, state_, introSteps, 1, function()
                M.openAutoPlanModal()
            end)
            return
        end
    end

    if not state_.auto_plan then
        state_.auto_plan = { refuel_threshold = 30, auto_accept_orders = false }
    end
    local ap = state_.auto_plan

    modal_:SetSize("md")
    modal_:SetTitle("⚙ 自动计划")
    modal_:ClearContent()

    modal_:AddContent(UI.Label {
        text = "经过聚落时自动执行的操作",
        fontSize = Theme.sizes.font_small,
        fontColor = Theme.colors.text_dim,
        marginBottom = 8,
    })

    -- 自动补油
    local fuelValueLabel = UI.Label {
        text = ap.refuel_threshold > 0 and (ap.refuel_threshold .. "%") or "关闭",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.accent,
        width = 42,
        textAlign = "right",
    }

    modal_:AddContent(UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_secondary,
        borderRadius = Theme.sizes.radius_small,
        gap = 6, marginBottom = 8,
        children = {
            UI.Label {
                text = "⛽ 自动补充燃料",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = "油量低于设定值时，经过聚落自动补满",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 8, marginTop = 4,
                children = {
                    UI.Slider {
                        flex = 1, height = 28,
                        min = 0, max = 80, step = 5,
                        value = ap.refuel_threshold,
                        onChange = function(self, v)
                            local val = math.floor(v / 5 + 0.5) * 5
                            ap.refuel_threshold = val
                            fuelValueLabel:SetText(val > 0 and (val .. "%") or "关闭")
                        end,
                    },
                    fuelValueLabel,
                },
            },
        },
    })

    -- 自动接单
    modal_:AddContent(UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_secondary,
        borderRadius = Theme.sizes.radius_small,
        gap = 6,
        children = {
            UI.Label {
                text = "📦 自动接取顺路单",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = "经过聚落时自动接取运力允许的顺路订单",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", justifyContent = "space-between",
                marginTop = 4,
                children = {
                    UI.Label {
                        text = "自动接单",
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_secondary,
                    },
                    F.actionBtn {
                        text = ap.auto_accept_orders and "已开启" or "已关闭",
                        variant = ap.auto_accept_orders and "primary" or "secondary",
                        width = 72, height = 32,
                        onClick = function(self)
                            ap.auto_accept_orders = not ap.auto_accept_orders
                            M.openAutoPlanModal()
                        end,
                    },
                },
            },
        },
    })

    modal_:AddContent(F.actionBtn {
        text = "确定",
        variant = "primary",
        height = 40, marginTop = 12,
        onClick = function(self)
            modal_:SetSize("sm")
            modal_:Close()
        end,
    })

    modal_:Open()
end

-- ============================================================
-- 底部路线面板重建
-- ============================================================
---@param cam table MapCamera.cam
function M.rebuildPanel(cam)
    if not routePanel_ then return end
    routePanel_:ClearChildren()

    local mm = MapMode.mapMode

    if mm.state == MapMode.MapState.BROWSE then
        routePanel_:SetStyle({ height = 0, padding = 0, display = "none" })
        if explorePanel_ then
            M.rebuildExplorePanel()
        end
        return
    end

    routePanel_:SetStyle({ height = "auto", padding = 12, display = "flex" })
    if explorePanel_ then
        explorePanel_:SetStyle({ display = "none" })
    end

    local isTravelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING

    if mm.state == MapMode.MapState.ROUTE_PREVIEW then
        local plan = mm.activePlan

        -- 标题行
        local titleText
        if mm.destList and #mm.destList > 1 then
            local names = {}
            for _, d in ipairs(mm.destList) do
                table.insert(names, Graph.get_node_name(d))
            end
            titleText = "配送: " .. table.concat(names, " → ")
        else
            local targetNode = Graph.get_node(mm.target)
            local targetName = targetNode and targetNode.name or mm.target or "?"
            titleText = isTravelling
                and ("🚚 改道 → " .. targetName)
                or ("目标: " .. targetName)
        end
        routePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = titleText,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = isTravelling and Theme.colors.accent or Theme.colors.text_primary,
                },
                F.actionBtn {
                    text = "✕", variant = "secondary",
                    width = 32, height = 32,
                    onClick = function(self)
                        MapMode.exitToBase(cam, function() M.rebuildPanel(cam) end)
                    end,
                },
            },
        })

        -- 策略按钮行
        local stratBtns = {}
        for _, strat in ipairs({ "fastest", "safest", "balanced" }) do
            local isActive = mm.strategy == strat
            table.insert(stratBtns, F.actionBtn {
                text = MapMode.STRATEGY_NAMES[strat],
                variant = isActive and "primary" or "secondary",
                flexGrow = 1, height = 34,
                onClick = function(self)
                    MapMode.switchStrategy(strat, function() M.rebuildPanel(cam) end)
                end,
            })
        end
        routePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, marginTop = 6,
            children = stratBtns,
        })

        -- 路线信息
        if plan then
            local DANGER_LABEL = { safe = "低", normal = "中", danger = "高" }
            routePanel_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", gap = 12, marginTop = 6,
                justifyContent = "space-around",
                children = {
                    UI.Label {
                        text = "⏱ " .. formatTime(plan.total_time),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = "⛽ " .. plan.total_fuel,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = "⚠ " .. (DANGER_LABEL[plan.max_danger] or "?"),
                        fontSize = Theme.sizes.font_small,
                        fontColor = plan.max_danger == "danger" and Theme.colors.danger
                            or Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = "📍 " .. #plan.path .. "站",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                },
            })

            local canDepart = state_.truck.fuel >= plan.total_fuel
            if isTravelling then
                routePanel_:AddChild(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        F.actionBtn {
                            text = "确认改道",
                            variant = "primary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                if plan then
                                    local ok = Flow.reroute(state_, plan)
                                    if ok then
                                        MapMode.exitToBase(cam, function() M.rebuildPanel(cam) end)
                                    end
                                end
                            end,
                        },
                    },
                })
            else
                routePanel_:AddChild(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        F.actionBtn {
                            text = "手动规划",
                            variant = "secondary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                MapMode.enterManualPlan(mm.target, state_, function() M.rebuildPanel(cam) end)
                            end,
                        },
                        F.actionBtn {
                            text = canDepart and "确认出发" or "燃料不足",
                            variant = "primary", flexGrow = 2, height = 40,
                            disabled = not canDepart,
                            sound = false,
                            onClick = function(self)
                                if canDepart and plan then
                                    SoundMgr.play("depart")
                                    if not MapMode.tryTutorialDeparture(plan, state_, router_) then
                                        Flow.start_travel(state_, plan)
                                        router_.navigate("home")
                                    end
                                end
                            end,
                        },
                    },
                })
            end
        else
            routePanel_:AddChild(UI.Label {
                text = "无法规划到该目标的路线",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.danger,
                marginTop = 6,
            })
        end

    elseif mm.state == MapMode.MapState.MANUAL_PLAN then
        -- 标题行
        routePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = "手动规划 (已选 " .. #mm.waypoints .. " 点)",
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.map_waypoint,
                },
                F.actionBtn {
                    text = "✕", variant = "secondary",
                    width = 32, height = 32,
                    onClick = function(self)
                        MapMode.exitToBase(cam, function() M.rebuildPanel(cam) end)
                    end,
                },
            },
        })

        -- 途经点序列
        if #mm.waypoints > 0 then
            local names = {}
            for _, wpId in ipairs(mm.waypoints) do
                table.insert(names, Graph.get_node_name(wpId))
            end
            routePanel_:AddChild(UI.Label {
                text = table.concat(names, " → "),
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
                marginTop = 4,
            })
        end

        -- 路线信息
        local plan = mm.manualPlan
        if plan then
            local DANGER_LABEL = { safe = "低", normal = "中", danger = "高" }
            routePanel_:AddChild(UI.Panel {
                width = "100%", flexDirection = "row", gap = 12, marginTop = 6,
                justifyContent = "space-around",
                children = {
                    UI.Label {
                        text = "⏱ " .. formatTime(plan.total_time),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = "⛽ " .. plan.total_fuel,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = "⚠ " .. (DANGER_LABEL[plan.max_danger] or "?"),
                        fontSize = Theme.sizes.font_small,
                        fontColor = plan.max_danger == "danger" and Theme.colors.danger
                            or Theme.colors.text_secondary,
                    },
                },
            })
        end

        -- 操作按钮
        routePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
            children = {
                F.actionBtn {
                    text = "撤销",
                    variant = "secondary", flexGrow = 1, height = 40,
                    disabled = #mm.waypoints <= 1,
                    onClick = function(self)
                        if #mm.waypoints > 1 then
                            table.remove(mm.waypoints)
                            if #mm.waypoints >= 2 then
                                local fromOvr = isTravelling and MapMode.getEffectiveOrigin(state_) or nil
                                mm.manualPlan = RoutePlanner.manual_plan_with_fill(state_, mm.waypoints, fromOvr)
                            else
                                mm.manualPlan = nil
                            end
                            M.rebuildPanel(cam)
                        end
                    end,
                },
                F.actionBtn {
                    text = isTravelling
                        and (plan and "确认改道" or "请选择途经点")
                        or  (plan and "确认出发" or "请选择途经点"),
                    variant = "primary", flexGrow = 2, height = 40,
                    disabled = not plan or (plan and state_.truck.fuel < plan.total_fuel),
                    onClick = function(self)
                        if plan then
                            if isTravelling then
                                local ok = Flow.reroute(state_, plan)
                                if ok then
                                    MapMode.exitToBase(cam, function() M.rebuildPanel(cam) end)
                                end
                            else
                                if not MapMode.tryTutorialDeparture(plan, state_, router_) then
                                    Flow.start_travel(state_, plan)
                                    router_.navigate("home")
                                end
                            end
                        end
                    end,
                },
            },
        })

        routePanel_:AddChild(UI.Label {
            text = "💡 点击地图上的节点添加途经点",
            fontSize = Theme.sizes.font_tiny,
            fontColor = Theme.colors.text_dim,
            marginTop = 4, textAlign = "center", width = "100%",
        })
    end
end

-- ============================================================
-- 探索区域面板重建
-- ============================================================
function M.rebuildExplorePanel()
    if not explorePanel_ or not state_ then return end
    explorePanel_:ClearChildren()

    local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
    if travelling then
        explorePanel_:SetStyle({ display = "none" })
        return
    end

    local nodeId   = state_.map.current_location
    local unknowns = Graph.get_unknown_neighbors(nodeId, state_)
    local knowns   = Graph.get_neighbors(nodeId, state_)

    local hasUnknowns = #unknowns > 0
    local hasKnowns   = #knowns > 0

    if not hasUnknowns and not hasKnowns then
        explorePanel_:SetStyle({ display = "none" })
        return
    end

    explorePanel_:SetStyle({ display = "flex" })

    -- 未探索区域
    if hasUnknowns then
        local collapsed = exploreCollapsed_.unknown

        explorePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            paddingTop = 4, paddingBottom = 4,
            onClick = function(self)
                exploreCollapsed_.unknown = not exploreCollapsed_.unknown
                M.rebuildExplorePanel()
            end,
            children = {
                UI.Label {
                    text = "🗺 未探索区域",
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.text_secondary,
                },
                UI.Label {
                    text = collapsed and "▶ " .. #unknowns or "▼ " .. #unknowns,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                },
            },
        })

        if not collapsed then
            for _, adj in ipairs(unknowns) do
                local edge   = adj.edge
                local fuelOk = state_.truck.fuel >= edge.fuel_cost
                local dColor = DANGER_COLOR[edge.danger] or Theme.colors.text_dim

                local targetDef = Graph.NODES[adj.to]
                local flagLocked = false
                if targetDef and targetDef.explore_flag then
                    local flags = state_.flags or {}
                    flagLocked = not flags[targetDef.explore_flag]
                end

                local canExplore = fuelOk and not flagLocked
                local btnText = flagLocked and "🔒 需要情报"
                    or (fuelOk and "探索" or "燃料不足")
                local labelText = flagLocked and ("🔒 " .. (targetDef and targetDef.name or "未知区域"))
                    or "❓ 未知区域"

                local unknownCard = UI.Panel {
                    width = "100%", padding = 10,
                    backgroundColor = Theme.colors.bg_card,
                    borderRadius = Theme.sizes.radius_small,
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexShrink = 1, gap = 2,
                            children = {
                                UI.Label {
                                    text = labelText,
                                    fontSize = Theme.sizes.font_normal,
                                    fontColor = flagLocked and Theme.colors.text_dim
                                        or Theme.colors.text_primary,
                                },
                                UI.Panel {
                                    flexDirection = "row", gap = 8,
                                    children = {
                                        UI.Label {
                                            text = EDGE_TYPE_LABEL[edge.type] or edge.type,
                                            fontSize = Theme.sizes.font_tiny,
                                            fontColor = Theme.colors.text_dim,
                                        },
                                        UI.Label {
                                            text = "危险:" .. (DANGER_LABEL_MAP[edge.danger] or "?"),
                                            fontSize = Theme.sizes.font_tiny,
                                            fontColor = dColor,
                                        },
                                        UI.Label {
                                            text = "⛽" .. edge.fuel_cost,
                                            fontSize = Theme.sizes.font_tiny,
                                            fontColor = fuelOk and Theme.colors.text_dim
                                                or Theme.colors.danger,
                                        },
                                    },
                                },
                            },
                        },
                        F.actionBtn {
                            text = btnText,
                            variant = canExplore and "primary" or "secondary",
                            height = 32, paddingLeft = 14, paddingRight = 14,
                            disabled = not canExplore,
                            onClick = function(self)
                                local ok, err = Flow.start_exploration(state_, adj.to)
                                if ok then
                                    router_.navigate("home")
                                else
                                    print("[Explore] " .. (err or "failed"))
                                end
                            end,
                        },
                    },
                }
                SketchBorder.register(unknownCard, "card")
                explorePanel_:AddChild(unknownCard)
            end
        end
    end

    -- 已知区域
    if hasKnowns then
        local collapsed = exploreCollapsed_.known

        if hasUnknowns then
            explorePanel_:AddChild(UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Theme.colors.border,
                marginTop = 4, marginBottom = 4,
            })
        end

        explorePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            paddingTop = 4, paddingBottom = 4,
            onClick = function(self)
                exploreCollapsed_.known = not exploreCollapsed_.known
                M.rebuildExplorePanel()
            end,
            children = {
                UI.Label {
                    text = "🚶 前往已知区域",
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.text_secondary,
                },
                UI.Label {
                    text = collapsed and "▶ " .. #knowns or "▼ " .. #knowns,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                },
            },
        })

        if not collapsed then
            for _, adj in ipairs(knowns) do
                local edge       = adj.edge
                local targetNode = Graph.get_node(adj.to)
                local fuelOk     = state_.truck.fuel >= edge.fuel_cost
                local tName      = targetNode and targetNode.name or adj.to
                local tType      = targetNode and (NODE_TYPE_LABEL[targetNode.type] or "") or ""

                local knownCard = UI.Panel {
                    width = "100%", padding = 10,
                    backgroundColor = Theme.colors.bg_card,
                    borderRadius = Theme.sizes.radius_small,
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexShrink = 1, gap = 2,
                            children = {
                                UI.Label {
                                    text = tName,
                                    fontSize = Theme.sizes.font_normal,
                                    fontColor = Theme.colors.text_primary,
                                },
                                UI.Panel {
                                    flexDirection = "row", gap = 8,
                                    children = {
                                        UI.Label {
                                            text = tType,
                                            fontSize = Theme.sizes.font_tiny,
                                            fontColor = Theme.colors.text_dim,
                                        },
                                        UI.Label {
                                            text = "⛽" .. edge.fuel_cost,
                                            fontSize = Theme.sizes.font_tiny,
                                            fontColor = fuelOk and Theme.colors.text_dim
                                                or Theme.colors.danger,
                                        },
                                    },
                                },
                            },
                        },
                        F.actionBtn {
                            text = fuelOk and "前往" or "燃料不足",
                            variant = fuelOk and "outline" or "secondary",
                            height = 32, paddingLeft = 14, paddingRight = 14,
                            disabled = not fuelOk,
                            onClick = function(self)
                                local ok, err = Flow.start_exploration(state_, adj.to)
                                if ok then
                                    router_.navigate("home")
                                else
                                    print("[Travel] " .. (err or "failed"))
                                end
                            end,
                        },
                    },
                }
                SketchBorder.register(knownCard, "card")
                explorePanel_:AddChild(knownCard)
            end
        end
    end
end

--- 从订单页进入的多目的地路线规划
---@param cam table
function M.enterOrderRoutePreview(cam)
    local destSet = OrderBook.get_destination_set(state_)
    local destList = {}
    for d, _ in pairs(destSet) do table.insert(destList, d) end
    if #destList == 0 then return end

    local mm = MapMode.mapMode
    if #destList == 1 then
        mm.destList = destList
        MapMode.enterRoutePreview(destList[1], state_, cam, function() M.rebuildPanel(cam) end)
        mm.destList = destList
        return
    end

    mm.state = MapMode.MapState.ROUTE_PREVIEW
    mm.target = destList[1]
    mm.strategy = "fastest"
    mm.destList = destList
    mm.plans = {
        fastest  = RoutePlanner.auto_plan_multi(state_, destList, "fastest"),
        safest   = RoutePlanner.auto_plan_multi(state_, destList, "safest"),
        balanced = RoutePlanner.auto_plan_multi(state_, destList, "balanced"),
    }
    mm.activePlan = mm.plans.fastest
    mm.waypoints = {}
    mm.manualPlan = nil
    cam.selected = nil
    M.rebuildPanel(cam)
end

--- 重置折叠状态
function M.reset()
    exploreCollapsed_.unknown = true
    exploreCollapsed_.known   = true
end

return M

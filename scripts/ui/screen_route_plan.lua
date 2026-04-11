--- 路线规划页面
--- 手动/自动选择路线，确认出发
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Flow = require("core/flow")
local Graph = require("map/world_graph")
local RoutePlanner = require("map/route_planner")
local OrderBook = require("economy/order_book")
local F = require("ui/ui_factory")
local SoundMgr = require("ui/sound_manager")

local M = {}
---@type table
local router = nil

local DANGER_LABEL = { low = "低", normal = "中", high = "高" }
local DANGER_COLOR = {
    low    = Theme.colors.success,
    normal = Theme.colors.accent,
    high   = Theme.colors.danger,
}

local STRATEGY_NAMES = {
    fastest  = "最快路线",
    safest   = "最安全路线",
    balanced = "平衡路线",
}

function M.create(state, params, r)
    router = r

    local destId = params and params.dest_id
    local strategy = params and params.strategy or "fastest"

    -- 获取活跃订单的目的地
    local destSet = OrderBook.get_destination_set(state)
    local destList = {}
    for d, _ in pairs(destSet) do table.insert(destList, d) end

    -- 如果没指定目的地，尝试自动选第一个
    if not destId and #destList > 0 then
        destId = destList[1]
    end

    -- 生成路线规划
    ---@type table|nil
    local plan = nil
    ---@type string|nil
    local planError = nil

    if destId then
        if #destList > 1 then
            -- 多目的地：自动串联
            plan = RoutePlanner.auto_plan_multi(state, destList, strategy)
            if not plan then planError = "无法规划到所有目的地的路线" end
        else
            plan = RoutePlanner.auto_plan(state, destId, strategy)
            if not plan then planError = "无法到达 " .. Graph.get_node_name(destId) end
        end
    end

    -- 构建内容
    local contentChildren = {}

    -- 订单目的地摘要
    table.insert(contentChildren, UI.Label {
        text = "本趟配送目标",
        fontSize = Theme.sizes.font_large, fontColor = Theme.colors.text_primary,
    })

    if #destList == 0 then
        table.insert(contentChildren, F.card {
            width = "100%", padding = 16,
            children = {
                UI.Label {
                    text = "尚未接取任何订单",
                    fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_dim,
                    textAlign = "center", width = "100%",
                },
            },
        })
    else
        local groups = OrderBook.group_by_destination(state)
        for _, group in pairs(groups) do
            table.insert(contentChildren, F.card {
                width = "100%", padding = 10,
                gap = 2,
                children = {
                    UI.Label {
                        text = "🎯 " .. group.dest_name,
                        fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.accent,
                    },
                    UI.Label {
                        text = #group.orders .. " 个订单",
                        fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_secondary,
                    },
                },
            })
        end
    end

    -- 策略选择
    table.insert(contentChildren, UI.Label {
        text = "路线策略", fontSize = Theme.sizes.font_large,
        fontColor = Theme.colors.text_primary, marginTop = 8,
    })

    table.insert(contentChildren, UI.Panel {
        width = "100%", flexDirection = "row", gap = 8,
        children = {
            createStrategyBtn(state, destId, "fastest", strategy),
            createStrategyBtn(state, destId, "safest", strategy),
            createStrategyBtn(state, destId, "balanced", strategy),
        },
    })

    -- 路线详情
    if planError then
        table.insert(contentChildren, UI.Panel {
            width = "100%", padding = 16,
            backgroundColor = { 60, 30, 30, 200 }, borderRadius = Theme.sizes.radius,
            children = {
                UI.Label {
                    text = planError,
                    fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.danger,
                    textAlign = "center", width = "100%",
                },
            },
        })
    elseif plan then
        table.insert(contentChildren, UI.Label {
            text = STRATEGY_NAMES[strategy] or "路线详情",
            fontSize = Theme.sizes.font_large, fontColor = Theme.colors.text_primary, marginTop = 8,
        })

        -- 路线概览
        table.insert(contentChildren, F.card {
            width = "100%", padding = 12,
            gap = 6,
            children = {
                createInfoRow("总耗时", formatTime(plan.total_time)),
                createInfoRow("总燃料", tostring(plan.total_fuel)),
                createInfoRow("最高风险", DANGER_LABEL[plan.max_danger] or "?",
                    DANGER_COLOR[plan.max_danger]),
                createInfoRow("途经节点", tostring(#plan.path) .. " 个"),
            },
        })

        -- 路线节点序列
        table.insert(contentChildren, createPathVisualization(plan, destSet))

        -- 出发按钮
        local canDepart = state.truck.fuel >= plan.total_fuel
        table.insert(contentChildren, F.actionBtn {
            text = canDepart and "确认出发" or "燃料不足",
            variant = "primary",
            height = 48, marginTop = 8,
            disabled = not canDepart,
            sound = false,
            onClick = function(self)
                if canDepart then
                    SoundMgr.play("depart")

                    Flow.start_travel(state, plan)
                    router.navigate("home")
                end
            end,
        })
    end

    return UI.Panel {
        id = "routePlanScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 8,
        overflow = "scroll",
        children = contentChildren,
    }
end

function M.update(state, dt, r) end

--- 策略选择按钮
function createStrategyBtn(state, destId, strat, current)
    local isActive = strat == current
    return F.actionBtn {
        text = STRATEGY_NAMES[strat] or strat,
        variant = isActive and "primary" or "secondary",
        flexGrow = 1, height = 36,
        onClick = function(self)
            Flow.enter_route_plan(state)
            router.navigate("route_plan", { dest_id = destId, strategy = strat })
        end,
    }
end

--- 路径可视化（节点序列 + 边信息）
function createPathVisualization(plan, destSet)
    local children = {}
    for i, nodeId in ipairs(plan.path) do
        local node = Graph.get_node(nodeId)
        local isDest = destSet[nodeId]
        local isStart = i == 1
        local isEnd = i == #plan.path

        -- 节点标记
        local label = ""
        if isStart then label = "起点 · "
        elseif isEnd then label = "终点 · "
        elseif isDest then label = "交付 · "
        end

        local nodeColor = Theme.colors.text_primary
        if isStart then nodeColor = Theme.colors.success
        elseif isDest then nodeColor = Theme.colors.accent
        end

        table.insert(children, UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
            children = {
                UI.Panel {
                    width = 10, height = 10,
                    borderRadius = 5,
                    backgroundColor = nodeColor,
                },
                UI.Label {
                    text = label .. (node and node.name or nodeId),
                    fontSize = Theme.sizes.font_normal, fontColor = nodeColor,
                },
            },
        })

        -- 边信息（在两个节点之间）
        if i < #plan.path then
            local seg = plan.segments[i]
            if seg then
                local eStyle = { label = seg.edge_type, color = Theme.colors.text_dim }
                if seg.edge_type == "main_road" then
                    eStyle = { label = "主干道", color = Theme.colors.success }
                elseif seg.edge_type == "path" then
                    eStyle = { label = "小径", color = Theme.colors.accent }
                elseif seg.edge_type == "shortcut" then
                    eStyle = { label = "捷径", color = Theme.colors.danger }
                end

                table.insert(children, UI.Panel {
                    width = "100%", paddingLeft = 20, flexDirection = "row", gap = 8,
                    children = {
                        UI.Label { text = "│", fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_dim },
                        UI.Label {
                            text = eStyle.label .. " " .. seg.time_sec .. "s  燃料" .. seg.fuel_cost,
                            fontSize = Theme.sizes.font_tiny, fontColor = eStyle.color,
                        },
                    },
                })
            end
        end
    end

    return F.card {
        width = "100%", padding = 12,
        gap = 4,
        children = children,
    }
end

--- 信息行
function createInfoRow(label, value, valueColor)
    return UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label { text = label, fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_secondary },
            UI.Label { text = value, fontSize = Theme.sizes.font_normal, fontColor = valueColor or Theme.colors.text_primary },
        },
    }
end

--- 格式化秒数
function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then return m .. "分" .. s .. "秒" end
    return s .. "秒"
end

return M

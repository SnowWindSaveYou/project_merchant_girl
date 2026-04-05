--- 大地图页面 — NanoVG 节点网络可视化
--- 绘制网状节点、不同线型连线、拖拽平移、滚轮缩放、节点选中弹窗
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Goods        = require("economy/goods")

local M = {}

-- 模块引用
local router_ = nil
---@type table
local state_  = nil

-- ============================================================
-- 地图交互模式
-- ============================================================
local MapState = {
    BROWSE        = "browse",
    ROUTE_PREVIEW = "route_preview",
    MANUAL_PLAN   = "manual_plan",
}

local mapMode = {
    state      = MapState.BROWSE,
    target     = nil,           -- 目标节点 id
    strategy   = "fastest",     -- 当前策略
    plans      = nil,           -- { fastest, safest, balanced }
    activePlan = nil,           -- 当前显示的 plan
    waypoints  = {},            -- 手动模式途经点
    manualPlan = nil,           -- 手动模式路线
}

-- 底部面板引用
---@type table|nil
local routePanel_ = nil

-- 探索区域面板引用
---@type table|nil
local explorePanel_ = nil
-- 折叠状态
local exploreCollapsed_ = {
    unknown = false,  -- 默认展开
    known   = false,  -- 默认展开
}

-- 边类型 & 危险等级显示
local EDGE_TYPE_LABEL = { main_road = "公路", path = "小径", shortcut = "捷径" }
local DANGER_LABEL_MAP = { safe = "低", normal = "中", danger = "高" }
local DANGER_COLOR    = {
    safe   = Theme.colors.success,
    normal = Theme.colors.accent,
    danger = Theme.colors.danger,
}

-- 节点类型中文
local NODE_TYPE_LABEL = {
    settlement = "聚落", resource = "资源点", transit = "中转站",
    hazard = "危险区", story = "遗迹",
}

-- ============================================================
-- 常量
-- ============================================================
local NODE_R        = 16      -- 节点圆半径
local HIT_R_SQ      = 26 * 26 -- 点击判定半径平方
local DRAG_THRESH   = 5       -- 拖拽触发阈值(px)
local ZOOM_MIN      = 0.6
local ZOOM_MAX      = 2.5
local ZOOM_STEP     = 0.12

local NODE_ICON = {
    settlement = "🏘", resource = "📦", transit = "🔀",
    hazard     = "⚠",  story    = "📡",
}
local EDGE_LABEL  = { main_road = "主干道", path = "小径", shortcut = "捷径" }
local DANGER_STR  = { safe = "低", normal = "中", danger = "高" }

-- ============================================================
-- 地图相机 & 输入状态（页面级，非全局）
-- ============================================================
local cam = {
    panX = 0, panY = 0, scale = 1.0,
    selected = nil,        -- 选中节点 id
    font     = nil,        -- NanoVG 字体句柄
    -- 画布绝对矩形（逻辑坐标，每帧更新）
    cx = 0, cy = 0, cw = 1, ch = 1,
    initialized = false,
}

local inp = {
    wasDown = false,
    pressX  = 0, pressY = 0,
    lastX   = 0, lastY  = 0,
    isDrag  = false,
}

-- Modal 引用
---@type table|nil
local modal_ = nil

-- ============================================================
-- 策略名称 & 颜色映射
-- ============================================================
local STRATEGY_NAMES = {
    fastest  = "最快",
    safest   = "最安全",
    balanced = "平衡",
}
local STRATEGY_COLORS = {
    fastest  = "map_route_fastest",
    safest   = "map_route_safest",
    balanced = "map_route_balanced",
    manual   = "map_route_manual",
}

-- ============================================================
-- 模式转换函数（前置声明，实现在面板之后）
-- ============================================================
local enterRoutePreview  -- (nodeId)
local enterManualPlan    -- (targetId)
local exitToBase         -- ()
local switchStrategy     -- (strat)
local rebuildPanel       -- ()
local rebuildExplorePanel -- ()

--- 获取旅行中的有效规划起点（下一到达节点），非旅行返回 current_location
local function getEffectiveOrigin()
    if state_ and Flow.get_phase(state_) == Flow.Phase.TRAVELLING
       and state_.flow.route_plan then
        return RoutePlanner.get_next_arrival_node(state_.flow.route_plan)
            or state_.map.current_location
    end
    return state_ and state_.map.current_location or nil
end

-- ============================================================
-- 坐标转换
-- ============================================================
--- 世界坐标 → 屏幕逻辑坐标
local function w2s(wx, wy)
    return wx * cam.scale + cam.panX + cam.cx,
           wy * cam.scale + cam.panY + cam.cy
end

--- 屏幕逻辑坐标 → 世界坐标
local function s2w(sx, sy)
    return (sx - cam.cx - cam.panX) / cam.scale,
           (sy - cam.cy - cam.panY) / cam.scale
end

--- 逻辑坐标是否在地图可交互区域
local function inMapArea(lx, ly)
    return lx >= cam.cx and lx <= cam.cx + cam.cw
       and ly >= cam.cy and ly <= cam.cy + cam.ch
end

--- 查找逻辑坐标下的已知节点
local function findNodeAt(lx, ly, known)
    local bestId, bestDSq = nil, HIT_R_SQ
    for _, node in ipairs(Graph.NODES) do
        if known[node.id] then
            local sx, sy = w2s(node.x, node.y)
            local dx, dy = lx - sx, ly - sy
            local dSq = dx * dx + dy * dy
            if dSq < bestDSq then
                bestDSq = dSq
                bestId  = node.id
            end
        end
    end
    return bestId
end

-- ============================================================
-- NanoVG 绘制辅助
-- ============================================================
local function fc(nvg, c, a)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], a or c[4]))
end
local function sc(nvg, c, a)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], a or c[4]))
end

--- 画虚线 / 点线
local function dashedLine(nvg, x1, y1, x2, y2, dashLen, gapLen)
    local dx, dy = x2 - x1, y2 - y1
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end
    local ux, uy = dx / dist, dy / dist
    local t = 0
    while t < dist do
        local e = math.min(t + dashLen, dist)
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, x1 + ux * t, y1 + uy * t)
        nvgLineTo(nvg, x1 + ux * e, y1 + uy * e)
        nvgStroke(nvg)
        t = e + gapLen
    end
end

-- ============================================================
-- 绘制：边
-- ============================================================
local function drawEdges(nvg, known)
    for _, e in ipairs(Graph.EDGES) do
        if known[e.from] and known[e.to] then
            local nf = Graph.get_node(e.from)
            local nt = Graph.get_node(e.to)
            if nf and nt then
                local x1, y1 = w2s(nf.x, nf.y)
                local x2, y2 = w2s(nt.x, nt.y)

                if e.type == "main_road" then
                    sc(nvg, Theme.colors.map_road)
                    nvgStrokeWidth(nvg, 3)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, x1, y1)
                    nvgLineTo(nvg, x2, y2)
                    nvgStroke(nvg)
                elseif e.type == "path" then
                    sc(nvg, Theme.colors.map_path)
                    nvgStrokeWidth(nvg, 2)
                    dashedLine(nvg, x1, y1, x2, y2, 8, 6)
                elseif e.type == "shortcut" then
                    sc(nvg, Theme.colors.map_shortcut)
                    nvgStrokeWidth(nvg, 2)
                    dashedLine(nvg, x1, y1, x2, y2, 3, 5)
                end

                -- 中点标注：时间 + 危险等级
                local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, mx - 18, my - 8, 36, 16, 8)
                fc(nvg, Theme.colors.bg_primary, 190)
                nvgFill(nvg)

                nvgFontFaceId(nvg, cam.font)
                nvgFontSize(nvg, 10)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                fc(nvg, Theme.colors.text_dim)
                nvgText(nvg, mx, my, e.travel_time_sec .. "s", nil)

                if e.danger == "danger" then
                    fc(nvg, Theme.colors.danger)
                    nvgFontSize(nvg, 12)
                    nvgText(nvg, mx, my - 14, "⚠", nil)
                end
            end
        end
    end
end

-- ============================================================
-- 绘制：节点
-- ============================================================
local function drawNodes(nvg, known, current, destSet, time)
    for _, node in ipairs(Graph.NODES) do
        local sx, sy = w2s(node.x, node.y)
        local isKnown = known[node.id]
        local isCur   = node.id == current
        local isDest  = destSet[node.id]
        local isSel   = cam.selected == node.id

        if not isKnown then
            -- 未知节点：暗淡小圆 + 问号
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, NODE_R * 0.55)
            fc(nvg, Theme.colors.map_unknown)
            nvgFill(nvg)
            nvgFontFaceId(nvg, cam.font)
            nvgFontSize(nvg, 11)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            fc(nvg, Theme.colors.text_dim, 100)
            nvgText(nvg, sx, sy, "?", nil)
        else
            local col = isCur  and Theme.colors.map_current
                     or isDest and Theme.colors.map_dest
                     or Theme.colors.map_node

            -- 脉冲光环（当前位置动态呼吸效果）
            if isCur then
                local pulse = 0.4 + 0.6 * math.abs(math.sin(time * 1.8))
                local pr = NODE_R + 6 + 3 * math.sin(time * 1.8)
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, pr)
                fc(nvg, col, math.floor(45 * pulse))
                nvgFill(nvg)
            elseif isDest or isSel then
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, NODE_R + 5)
                fc(nvg, col, 45)
                nvgFill(nvg)
            end

            -- 选中圈
            if isSel then
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, sy, NODE_R + 3)
                sc(nvg, Theme.colors.text_primary, 170)
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            end

            -- 节点底圆
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, NODE_R)
            fc(nvg, Theme.colors.bg_card)
            nvgFill(nvg)
            sc(nvg, col, 220)
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)

            -- 图标
            nvgFontFaceId(nvg, cam.font)
            nvgFontSize(nvg, 15)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            fc(nvg, col)
            nvgText(nvg, sx, sy, NODE_ICON[node.type] or "●", nil)

            -- 名称标签
            nvgFontSize(nvg, 11)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            fc(nvg, Theme.colors.text_primary, 200)
            nvgText(nvg, sx, sy + NODE_R + 4, node.name, nil)

            -- 角标
            if isCur then
                nvgFontSize(nvg, 13)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                fc(nvg, col)
                nvgText(nvg, sx, sy - NODE_R - 2, "📍", nil)
            end
            if isDest then
                nvgFontSize(nvg, 11)
                nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
                fc(nvg, Theme.colors.accent)
                nvgText(nvg, sx + NODE_R * 0.6, sy - NODE_R * 0.6, "🎯", nil)
            end
        end
    end
end

-- ============================================================
-- 绘制：图例
-- ============================================================
local function drawLegend(nvg)
    local lx = cam.cx + cam.cw - 110
    local ly = cam.cy + 10
    local rowH = 16

    -- 背景
    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, lx - 8, ly - 6, 106, rowH * 3 + 20, 6)
    fc(nvg, Theme.colors.bg_primary, 210)
    nvgFill(nvg)

    nvgFontFaceId(nvg, cam.font)
    nvgFontSize(nvg, 10)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    -- 主干道（实线）
    local y = ly + rowH * 0.5
    sc(nvg, Theme.colors.map_road)
    nvgStrokeWidth(nvg, 2)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, lx, y); nvgLineTo(nvg, lx + 22, y)
    nvgStroke(nvg)
    fc(nvg, Theme.colors.text_secondary)
    nvgText(nvg, lx + 28, y, "主干道", nil)

    -- 小径（虚线）
    y = y + rowH
    sc(nvg, Theme.colors.map_path)
    nvgStrokeWidth(nvg, 2)
    dashedLine(nvg, lx, y, lx + 22, y, 6, 4)
    fc(nvg, Theme.colors.text_secondary)
    nvgText(nvg, lx + 28, y, "小径", nil)

    -- 捷径（点线）
    y = y + rowH
    sc(nvg, Theme.colors.map_shortcut)
    nvgStrokeWidth(nvg, 2)
    dashedLine(nvg, lx, y, lx + 22, y, 3, 4)
    fc(nvg, Theme.colors.text_secondary)
    nvgText(nvg, lx + 28, y, "捷径(危)", nil)
end

-- ============================================================
-- 绘制：路线高亮
-- ============================================================
local function drawRoutePath(nvg, plan, colorKey)
    if not plan or not plan.path or #plan.path < 2 then return end
    local col = Theme.colors[colorKey] or Theme.colors.map_route_fastest

    -- 1. 发光底层
    for i = 1, #plan.path - 1 do
        local n1 = Graph.get_node(plan.path[i])
        local n2 = Graph.get_node(plan.path[i + 1])
        if n1 and n2 then
            local x1, y1 = w2s(n1.x, n1.y)
            local x2, y2 = w2s(n2.x, n2.y)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            sc(nvg, Theme.colors.map_route_glow)
            nvgStrokeWidth(nvg, 10)
            nvgStroke(nvg)
        end
    end

    -- 2. 主线
    for i = 1, #plan.path - 1 do
        local n1 = Graph.get_node(plan.path[i])
        local n2 = Graph.get_node(plan.path[i + 1])
        if n1 and n2 then
            local x1, y1 = w2s(n1.x, n1.y)
            local x2, y2 = w2s(n2.x, n2.y)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            sc(nvg, col)
            nvgStrokeWidth(nvg, 4)
            nvgStroke(nvg)
        end
    end

    -- 3. 方向箭头（每段中点）
    for i = 1, #plan.path - 1 do
        local n1 = Graph.get_node(plan.path[i])
        local n2 = Graph.get_node(plan.path[i + 1])
        if n1 and n2 then
            local x1, y1 = w2s(n1.x, n1.y)
            local x2, y2 = w2s(n2.x, n2.y)
            local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            local dx, dy = x2 - x1, y2 - y1
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 20 then
                local ux, uy = dx / dist, dy / dist
                -- 垂直方向
                local px, py = -uy, ux
                local sz = 5
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, mx + ux * sz, my + uy * sz)
                nvgLineTo(nvg, mx - ux * sz + px * sz, my - uy * sz + py * sz)
                nvgLineTo(nvg, mx - ux * sz - px * sz, my - uy * sz - py * sz)
                nvgClosePath(nvg)
                fc(nvg, col, 220)
                nvgFill(nvg)
            end
        end
    end
end

-- ============================================================
-- 绘制：活跃旅行路线（已走过灰色 + 剩余亮色 + 卡车位置）
-- ============================================================
local function drawActiveRoute(nvg, plan, time)
    if not plan or not plan.segments or #plan.segments == 0 then return end
    if not plan.path or #plan.path < 2 then return end

    local segIdx = plan.segment_index or 0
    if segIdx == 0 then return end

    -- 1. 已走过的段（灰色）
    for i = 1, math.min(segIdx - 1, #plan.path - 1) do
        local n1 = Graph.get_node(plan.path[i])
        local n2 = Graph.get_node(plan.path[i + 1])
        if n1 and n2 then
            local x1, y1 = w2s(n1.x, n1.y)
            local x2, y2 = w2s(n2.x, n2.y)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            sc(nvg, Theme.colors.map_route_done)
            nvgStrokeWidth(nvg, 3)
            nvgStroke(nvg)
        end
    end

    -- 2. 当前段及剩余段（亮色 + 发光）
    local startSeg = math.max(segIdx, 1)
    for i = startSeg, #plan.path - 1 do
        local n1 = Graph.get_node(plan.path[i])
        local n2 = Graph.get_node(plan.path[i + 1])
        if n1 and n2 then
            local x1, y1 = w2s(n1.x, n1.y)
            local x2, y2 = w2s(n2.x, n2.y)
            -- 发光底层
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            sc(nvg, Theme.colors.map_route_glow)
            nvgStrokeWidth(nvg, 10)
            nvgStroke(nvg)
            -- 主线
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            sc(nvg, Theme.colors.map_route_active)
            nvgStrokeWidth(nvg, 4)
            nvgStroke(nvg)
        end
    end

    -- 3. 方向箭头（剩余段中点）
    for i = startSeg, #plan.path - 1 do
        local n1 = Graph.get_node(plan.path[i])
        local n2 = Graph.get_node(plan.path[i + 1])
        if n1 and n2 then
            local x1, y1 = w2s(n1.x, n1.y)
            local x2, y2 = w2s(n2.x, n2.y)
            local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
            local dx, dy = x2 - x1, y2 - y1
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 20 then
                local ux, uy = dx / dist, dy / dist
                local px, py = -uy, ux
                local sz = 5
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, mx + ux * sz, my + uy * sz)
                nvgLineTo(nvg, mx - ux * sz + px * sz, my - uy * sz + py * sz)
                nvgLineTo(nvg, mx - ux * sz - px * sz, my - uy * sz - py * sz)
                nvgClosePath(nvg)
                fc(nvg, Theme.colors.map_route_active, 220)
                nvgFill(nvg)
            end
        end
    end

    -- 4. 卡车插值位置
    local seg = plan.segments[segIdx]
    if seg then
        local fromNode = Graph.get_node(seg.from)
        local toNode   = Graph.get_node(seg.to)
        if fromNode and toNode then
            local t = 0
            if seg.time_sec > 0 then
                t = math.min((plan.segment_elapsed or 0) / seg.time_sec, 1.0)
            end
            -- 在世界坐标插值
            local wx = fromNode.x + (toNode.x - fromNode.x) * t
            local wy = fromNode.y + (toNode.y - fromNode.y) * t
            local tx, ty = w2s(wx, wy)

            -- 卡车呼吸光圈
            local pulse = 0.5 + 0.5 * math.abs(math.sin(time * 2.5))
            local pr = 14 + 4 * math.sin(time * 2.5)
            nvgBeginPath(nvg)
            nvgCircle(nvg, tx, ty, pr)
            fc(nvg, Theme.colors.map_truck, math.floor(60 * pulse))
            nvgFill(nvg)

            -- 卡车实心点
            nvgBeginPath(nvg)
            nvgCircle(nvg, tx, ty, 7)
            fc(nvg, Theme.colors.map_truck)
            nvgFill(nvg)

            -- 卡车图标
            nvgFontFaceId(nvg, cam.font)
            nvgFontSize(nvg, 16)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            fc(nvg, { 40, 30, 10, 255 })
            nvgText(nvg, tx, ty, "🚚", nil)
        end
    end
end

--- 绘制手动模式的途经点标记
local function drawWaypoints(nvg, waypoints)
    for i, wpId in ipairs(waypoints) do
        local node = Graph.get_node(wpId)
        if node then
            local sx, sy = w2s(node.x, node.y)
            -- 外圈
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, sy, NODE_R + 6)
            sc(nvg, Theme.colors.map_waypoint)
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
            -- 序号
            nvgFontFaceId(nvg, cam.font)
            nvgFontSize(nvg, 10)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            fc(nvg, Theme.colors.map_waypoint)
            nvgText(nvg, sx + NODE_R + 8, sy - NODE_R - 2, tostring(i), nil)
        end
    end
end

-- ============================================================
-- 绘制：网格（微弱参考线）
-- ============================================================
local function drawGrid(nvg)
    local gc = Theme.colors.map_grid
    sc(nvg, gc)
    nvgStrokeWidth(nvg, 1)
    local gs = 50 * cam.scale
    if gs < 10 then return end

    local ox = cam.panX % gs + cam.cx
    local oy = cam.panY % gs + cam.cy
    for gx = ox, cam.cx + cam.cw, gs do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, gx, cam.cy)
        nvgLineTo(nvg, gx, cam.cy + cam.ch)
        nvgStroke(nvg)
    end
    for gy = oy, cam.cy + cam.ch, gs do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, cam.cx, gy)
        nvgLineTo(nvg, cam.cx + cam.cw, gy)
        nvgStroke(nvg)
    end
end

-- ============================================================
-- 主绘制入口
-- ============================================================
local function drawMap(nvg, layout)
    cam.cx = layout.x
    cam.cy = layout.y
    cam.cw = layout.w
    cam.ch = layout.h

    -- 惰性初始化字体
    if not cam.font then
        cam.font = nvgCreateFont(nvg, "map-sans", "Fonts/MiSans-Regular.ttf")
    end

    -- 首次打开：居中到当前位置（旅行中居中到卡车插值位置）
    if not cam.initialized and state_ then
        local centerX, centerY = nil, nil
        local plan = state_.flow.route_plan
        local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
        if travelling and plan and plan.segment_index and plan.segment_index > 0 then
            local seg = plan.segments[plan.segment_index]
            if seg then
                local fn = Graph.get_node(seg.from)
                local tn = Graph.get_node(seg.to)
                if fn and tn then
                    local t = 0
                    if seg.time_sec > 0 then
                        t = math.min((plan.segment_elapsed or 0) / seg.time_sec, 1.0)
                    end
                    centerX = fn.x + (tn.x - fn.x) * t
                    centerY = fn.y + (tn.y - fn.y) * t
                end
            end
        end
        if not centerX then
            local curNode = Graph.get_node(state_.map.current_location)
            if curNode then
                centerX = curNode.x
                centerY = curNode.y
            end
        end
        if centerX then
            cam.scale = math.min(cam.cw, cam.ch) / 480
            cam.scale = math.max(ZOOM_MIN, math.min(cam.scale, ZOOM_MAX))
            cam.panX = cam.cw / 2 - centerX * cam.scale
            cam.panY = cam.ch / 2 - centerY * cam.scale
        end
        cam.initialized = true
    end

    local known   = state_.map.known_nodes or {}
    local current = state_.map.current_location
    local destSet = OrderBook.get_destination_set(state_)
    local time    = os.clock()

    -- 1) 背景
    nvgBeginPath(nvg)
    nvgRect(nvg, cam.cx, cam.cy, cam.cw, cam.ch)
    fc(nvg, Theme.colors.map_bg)
    nvgFill(nvg)

    -- 2) 裁剪到画布，绘制地图内容
    nvgSave(nvg)
    nvgIntersectScissor(nvg, cam.cx, cam.cy, cam.cw, cam.ch)

    drawGrid(nvg)
    drawEdges(nvg, known)

    -- 路线高亮（在边之上、节点之下）
    local isTravelling = state_ and Flow.get_phase(state_) == Flow.Phase.TRAVELLING
    if isTravelling and state_.flow.route_plan then
        -- 旅行中：绘制活跃路线（已走灰色 + 剩余亮色 + 卡车位置）
        drawActiveRoute(nvg, state_.flow.route_plan, time)
    elseif mapMode.state == MapState.ROUTE_PREVIEW and mapMode.activePlan then
        local colorKey = STRATEGY_COLORS[mapMode.strategy] or "map_route_fastest"
        drawRoutePath(nvg, mapMode.activePlan, colorKey)
    elseif mapMode.state == MapState.MANUAL_PLAN and mapMode.manualPlan then
        drawRoutePath(nvg, mapMode.manualPlan, "map_route_manual")
        drawWaypoints(nvg, mapMode.waypoints)
    end

    drawNodes(nvg, known, current, destSet, time)

    nvgRestore(nvg)

    -- 3) 覆盖 UI 层（不受裁剪约束）
    drawLegend(nvg)
end

-- ============================================================
-- Modal 弹窗：节点信息
-- ============================================================
local function openNodeModal(nodeId)
    if not modal_ then return end
    local node = Graph.get_node(nodeId)
    if not node then return end

    local current = state_.map.current_location
    local destSet = OrderBook.get_destination_set(state_)
    local isCur   = nodeId == current
    local isDest  = destSet[nodeId]

    -- 设置标题
    local icon = NODE_ICON[node.type] or "●"
    modal_:SetTitle(icon .. "  " .. node.name)

    -- 构建内容
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

    -- 旅行状态判断
    local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING

    -- 旅行中以下一到达节点为有效起点判断路线
    local planOrigin = travelling and getEffectiveOrigin() or current

    -- 直连路线信息 & 操作按钮
    local edge = Graph.get_edge(planOrigin, nodeId)
    local reachable = false

    if edge then
        reachable = true
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

        -- 相邻节点操作按钮
        if travelling then
            -- 旅行中允许重新规划路线
            modal_:AddContent(UI.Panel {
                width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                children = {
                    UI.Button {
                        text = "查看路线",
                        variant = "primary", flexGrow = 1, height = 40,
                        onClick = function(self)
                            modal_:Close()
                            enterRoutePreview(nodeId)
                        end,
                    },
                },
            })
        elseif not travelling then
            local canDepart = state_.truck.fuel >= edge.fuel_cost
            modal_:AddContent(UI.Panel {
                width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                children = {
                    UI.Button {
                        text = canDepart and "直接出发" or "燃料不足",
                        variant = "primary", flexGrow = 1, height = 40,
                        disabled = not canDepart,
                        onClick = function(self)
                            modal_:Close()
                            local plan = RoutePlanner.auto_plan(state_, nodeId, "fastest")
                            if plan then
                                Flow.start_travel(state_, plan)
                                router_.navigate("home")
                            end
                        end,
                    },
                    UI.Button {
                        text = "查看路线",
                        variant = "secondary", flexGrow = 1, height = 40,
                        onClick = function(self)
                            modal_:Close()
                            enterRoutePreview(nodeId)
                        end,
                    },
                },
            })
        end
    elseif nodeId ~= planOrigin then
        -- 非直连：显示路径距离
        local path = Graph.find_path(planOrigin, nodeId, state_)
        if path and #path > 1 then
            reachable = true
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

            -- 非相邻可达节点操作按钮
            if travelling then
                -- 旅行中允许重新规划路线
                modal_:AddContent(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        UI.Button {
                            text = "规划新路线",
                            variant = "primary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                modal_:Close()
                                enterRoutePreview(nodeId)
                            end,
                        },
                    },
                })
            elseif not travelling then
                modal_:AddContent(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        UI.Button {
                            text = "规划路线",
                            variant = "primary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                modal_:Close()
                                enterRoutePreview(nodeId)
                            end,
                        },
                        UI.Button {
                            text = "手动规划",
                            variant = "secondary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                modal_:Close()
                                enterManualPlan(nodeId)
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
-- 格式化秒数
-- ============================================================
local function formatTime(seconds)
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then return m .. "分" .. s .. "秒" end
    return s .. "秒"
end

-- ============================================================
-- 底部面板重建
-- ============================================================
rebuildPanel = function()
    if not routePanel_ then return end

    -- 清空面板子节点
    routePanel_:ClearChildren()

    if mapMode.state == MapState.BROWSE then
        -- 浏览模式：隐藏路线面板，显示探索面板
        routePanel_:SetStyle({ height = 0, padding = 0, display = "none" })
        if explorePanel_ then
            rebuildExplorePanel()
        end
        return
    end

    routePanel_:SetStyle({ height = "auto", padding = 12, display = "flex" })
    -- 路线模式：隐藏探索面板
    if explorePanel_ then
        explorePanel_:SetStyle({ display = "none" })
    end

    local isTravelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING

    if mapMode.state == MapState.ROUTE_PREVIEW then
        local plan = mapMode.activePlan
        local targetNode = Graph.get_node(mapMode.target)
        local targetName = targetNode and targetNode.name or mapMode.target or "?"

        -- 标题行
        local titleText = isTravelling
            and ("🚚 改道 → " .. targetName)
            or ("目标: " .. targetName)
        routePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = titleText,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = isTravelling and Theme.colors.accent or Theme.colors.text_primary,
                },
                UI.Button {
                    text = "✕", variant = "secondary",
                    width = 32, height = 32,
                    onClick = function(self) exitToBase() end,
                },
            },
        })

        -- 策略按钮行
        local stratBtns = {}
        for _, strat in ipairs({ "fastest", "safest", "balanced" }) do
            local isActive = mapMode.strategy == strat
            table.insert(stratBtns, UI.Button {
                text = STRATEGY_NAMES[strat],
                variant = isActive and "primary" or "secondary",
                flexGrow = 1, height = 34,
                onClick = function(self) switchStrategy(strat) end,
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

            -- 操作按钮
            local canDepart = state_.truck.fuel >= plan.total_fuel
            if isTravelling then
                -- 旅行中：改道确认
                routePanel_:AddChild(UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 8,
                    children = {
                        UI.Button {
                            text = "确认改道",
                            variant = "primary", flexGrow = 1, height = 40,
                            onClick = function(self)
                                if plan then
                                    local ok = Flow.reroute(state_, plan)
                                    if ok then
                                        exitToBase()
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
                        UI.Button {
                            text = "手动规划",
                            variant = "secondary", flexGrow = 1, height = 40,
                            onClick = function(self) enterManualPlan(mapMode.target) end,
                        },
                        UI.Button {
                            text = canDepart and "确认出发" or "燃料不足",
                            variant = "primary", flexGrow = 2, height = 40,
                            disabled = not canDepart,
                            onClick = function(self)
                                if canDepart and plan then
                                    Flow.start_travel(state_, plan)
                                    router_.navigate("home")
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

    elseif mapMode.state == MapState.MANUAL_PLAN then
        -- 标题行
        routePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = "手动规划 (已选 " .. #mapMode.waypoints .. " 点)",
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.map_waypoint,
                },
                UI.Button {
                    text = "✕", variant = "secondary",
                    width = 32, height = 32,
                    onClick = function(self) exitToBase() end,
                },
            },
        })

        -- 途经点序列
        if #mapMode.waypoints > 0 then
            local names = {}
            for _, wpId in ipairs(mapMode.waypoints) do
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
        local plan = mapMode.manualPlan
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
                UI.Button {
                    text = "撤销",
                    variant = "secondary", flexGrow = 1, height = 40,
                    disabled = #mapMode.waypoints <= 1,
                    onClick = function(self)
                        if #mapMode.waypoints > 1 then
                            table.remove(mapMode.waypoints)
                            -- 重新计算路线
                            if #mapMode.waypoints >= 2 then
                                local fromOvr = isTravelling and getEffectiveOrigin() or nil
                                mapMode.manualPlan = RoutePlanner.manual_plan_with_fill(state_, mapMode.waypoints, fromOvr)
                            else
                                mapMode.manualPlan = nil
                            end
                            rebuildPanel()
                        end
                    end,
                },
                UI.Button {
                    text = isTravelling
                        and (plan and "确认改道" or "请选择途经点")
                        or  (plan and "确认出发" or "请选择途经点"),
                    variant = "primary", flexGrow = 2, height = 40,
                    disabled = not plan or (plan and state_.truck.fuel < plan.total_fuel),
                    onClick = function(self)
                        if plan then
                            if isTravelling then
                                local ok = Flow.reroute(state_, plan)
                                if ok then exitToBase() end
                            else
                                Flow.start_travel(state_, plan)
                                router_.navigate("home")
                            end
                        end
                    end,
                },
            },
        })

        -- 提示
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
rebuildExplorePanel = function()
    if not explorePanel_ or not state_ then return end
    explorePanel_:ClearChildren()

    -- 旅行中隐藏探索面板
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

    -- ── 未探索区域（折叠区） ──
    if hasUnknowns then
        local collapsed = exploreCollapsed_.unknown

        -- 标题行（可点击折叠）
        explorePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            paddingTop = 4, paddingBottom = 4,
            onClick = function(self)
                exploreCollapsed_.unknown = not exploreCollapsed_.unknown
                rebuildExplorePanel()
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

                explorePanel_:AddChild(UI.Panel {
                    width = "100%", padding = 10,
                    backgroundColor = { 40, 36, 28, 220 },
                    borderRadius = Theme.sizes.radius_small,
                    borderWidth = 1, borderColor = Theme.colors.warning,
                    flexDirection = "row", justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexShrink = 1, gap = 2,
                            children = {
                                UI.Label {
                                    text = "❓ 未知区域",
                                    fontSize = Theme.sizes.font_normal,
                                    fontColor = Theme.colors.text_primary,
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
                        UI.Button {
                            text = fuelOk and "探索" or "燃料不足",
                            variant = fuelOk and "primary" or "secondary",
                            height = 32, paddingLeft = 14, paddingRight = 14,
                            disabled = not fuelOk,
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
                })
            end
        end
    end

    -- ── 前往已知区域（折叠区） ──
    if hasKnowns then
        local collapsed = exploreCollapsed_.known

        -- 分隔（如果上面有未探索区域）
        if hasUnknowns then
            explorePanel_:AddChild(UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Theme.colors.border,
                marginTop = 4, marginBottom = 4,
            })
        end

        -- 标题行（可点击折叠）
        explorePanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            paddingTop = 4, paddingBottom = 4,
            onClick = function(self)
                exploreCollapsed_.known = not exploreCollapsed_.known
                rebuildExplorePanel()
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

                explorePanel_:AddChild(UI.Panel {
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
                        UI.Button {
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
                })
            end
        end
    end
end

-- ============================================================
-- 模式转换实现
-- ============================================================
enterRoutePreview = function(nodeId)
    mapMode.state = MapState.ROUTE_PREVIEW
    mapMode.target = nodeId
    mapMode.strategy = "fastest"

    -- 旅行中：从下一个到达节点出发规划
    local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
    if travelling and state_.flow.route_plan then
        local fromId = RoutePlanner.get_next_arrival_node(state_.flow.route_plan)
        if fromId then
            mapMode.plans = RoutePlanner.auto_plan_all_strategies_from(state_, fromId, nodeId)
        else
            mapMode.plans = RoutePlanner.auto_plan_all_strategies(state_, nodeId)
        end
    else
        mapMode.plans = RoutePlanner.auto_plan_all_strategies(state_, nodeId)
    end

    mapMode.activePlan = mapMode.plans.fastest
    mapMode.waypoints = {}
    mapMode.manualPlan = nil
    cam.selected = nodeId
    rebuildPanel()
end

enterManualPlan = function(targetId)
    -- 旅行中：起点为下一个到达节点；否则为当前位置
    local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
    local origin
    if travelling and state_.flow.route_plan then
        origin = RoutePlanner.get_next_arrival_node(state_.flow.route_plan)
            or state_.map.current_location
    else
        origin = state_.map.current_location
    end

    mapMode.state = MapState.MANUAL_PLAN
    mapMode.target = targetId
    mapMode.plans = nil
    mapMode.activePlan = nil
    mapMode.strategy = "manual"

    -- 初始化途经点：起点 + 目标
    local fromOvr = travelling and origin or nil
    if targetId and targetId ~= origin then
        mapMode.waypoints = { origin, targetId }
        mapMode.manualPlan = RoutePlanner.manual_plan_with_fill(state_, mapMode.waypoints, fromOvr)
    else
        mapMode.waypoints = { origin }
        mapMode.manualPlan = nil
    end
    rebuildPanel()
end

exitToBase = function()
    mapMode.state = MapState.BROWSE
    mapMode.target = nil
    mapMode.plans = nil
    mapMode.activePlan = nil
    mapMode.waypoints = {}
    mapMode.manualPlan = nil
    cam.selected = nil
    rebuildPanel()
end

switchStrategy = function(strat)
    if mapMode.state ~= MapState.ROUTE_PREVIEW then return end
    mapMode.strategy = strat
    if mapMode.plans then
        mapMode.activePlan = mapMode.plans[strat]
    end
    rebuildPanel()
end

-- ============================================================
-- 输入处理
-- ============================================================
local function handleInput(dt)
    if not state_ or cam.cw < 2 then return end
    -- 等待首帧渲染完成后才处理输入，确保 cam 值精确
    if not cam.initialized then return end
    -- Modal 打开时不处理地图输入
    if modal_ and modal_:IsOpen() then return end

    local uiScale = UI.GetScale()
    local mx  = input.mousePosition.x / uiScale
    local my  = input.mousePosition.y / uiScale

    local isDown     = input:GetMouseButtonDown(MOUSEB_LEFT)
    local justPress  = isDown and not inp.wasDown
    local justRelease = not isDown and inp.wasDown

    -- 按下
    if justPress then
        inp.pressX = mx
        inp.pressY = my
        inp.isDrag = false
    end

    -- 拖拽判定
    if isDown and not inp.isDrag then
        local dx = mx - inp.pressX
        local dy = my - inp.pressY
        if dx * dx + dy * dy > DRAG_THRESH * DRAG_THRESH then
            inp.isDrag = true
        end
    end

    -- 拖拽平移
    if isDown and inp.isDrag then
        local dx = mx - inp.lastX
        local dy = my - inp.lastY
        if not justPress then
            cam.panX = cam.panX + dx
            cam.panY = cam.panY + dy
        end
    end

    inp.lastX = mx
    inp.lastY = my

    -- 松开 —— 点击判定（按模式分支）
    if justRelease and not inp.isDrag then
        local cx, cy = inp.pressX, inp.pressY

        if inMapArea(cx, cy) then
            local known = state_.map.known_nodes or {}
            local nodeId = findNodeAt(cx, cy, known)

            if mapMode.state == MapState.BROWSE then
                -- 浏览模式：点击节点打开弹窗
                if nodeId then
                    cam.selected = nodeId
                    openNodeModal(nodeId)
                else
                    cam.selected = nil
                end

            elseif mapMode.state == MapState.ROUTE_PREVIEW then
                -- 路线预览模式：点击其他节点切换目标，点空白退出
                if nodeId and nodeId ~= state_.map.current_location then
                    enterRoutePreview(nodeId)
                elseif not nodeId then
                    exitToBase()
                end

            elseif mapMode.state == MapState.MANUAL_PLAN then
                -- 手动规划模式：点击节点添加/移除途经点
                if nodeId then
                    local current = state_.map.current_location
                    if nodeId == current then
                        -- 忽略起点点击
                    else
                        -- 检查是否已在途经点列表中
                        local existIdx = nil
                        for i, wp in ipairs(mapMode.waypoints) do
                            if wp == nodeId then existIdx = i; break end
                        end

                        if existIdx then
                            -- 已选中：移除该点及之后的所有点
                            for i = #mapMode.waypoints, existIdx, -1 do
                                table.remove(mapMode.waypoints, i)
                            end
                        else
                            -- 新增途经点
                            table.insert(mapMode.waypoints, nodeId)
                        end

                        -- 重新计算路线
                        if #mapMode.waypoints >= 2 then
                            local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
                            local fromOvr = travelling and getEffectiveOrigin() or nil
                            mapMode.manualPlan = RoutePlanner.manual_plan_with_fill(state_, mapMode.waypoints, fromOvr)
                        else
                            mapMode.manualPlan = nil
                        end
                        rebuildPanel()
                    end
                end
                -- 点空白不退出（防误触）
            end
        end
    end

    inp.wasDown = isDown

    -- 滚轮缩放（向鼠标位置缩放）
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 and inMapArea(mx, my) then
        local lx = mx - cam.cx
        local ly = my - cam.cy
        local wx = (lx - cam.panX) / cam.scale
        local wy = (ly - cam.panY) / cam.scale

        cam.scale = cam.scale + wheel * ZOOM_STEP
        cam.scale = math.max(ZOOM_MIN, math.min(cam.scale, ZOOM_MAX))

        cam.panX = lx - wx * cam.scale
        cam.panY = ly - wy * cam.scale
    end
end

-- ============================================================
-- 页面生命周期
-- ============================================================
function M.create(state, params, r)
    router_ = r
    state_  = state
    cam.initialized = false
    cam.selected    = nil
    cam.dragging    = false
    inp.wasDown     = false
    inp.isDrag      = false

    -- 重置模式状态
    mapMode.state      = MapState.BROWSE
    mapMode.target     = nil
    mapMode.strategy   = "fastest"
    mapMode.plans      = nil
    mapMode.activePlan = nil
    mapMode.waypoints  = {}
    mapMode.manualPlan = nil

    -- 预估画布尺寸（避免首帧 cam 值为默认值导致输入失效）
    local uiScale = UI.GetScale()
    cam.cw = graphics:GetWidth() / uiScale
    cam.ch = graphics:GetHeight() / uiScale
    cam.cx = 0
    cam.cy = 0

    -- 全屏画布 Panel，自定义 NanoVG 渲染
    local canvas = UI.Panel {
        id     = "mapCanvas",
        width  = "100%",
        flexGrow = 1,
        backgroundColor = Theme.colors.map_bg,
    }

    -- 注入自定义渲染：地图绘制替代子节点渲染
    canvas.CustomRenderChildren = function(self, nvg, renderFn)
        drawMap(nvg, self:GetAbsoluteLayout())
    end

    -- Modal 弹窗（浮在画布上方）
    modal_ = UI.Modal {
        size = "sm",
        title = "",
        closeOnOverlay = true,
        closeOnEscape = true,
        onClose = function(self)
            cam.selected = nil
        end,
    }

    -- 探索区域面板（地图下方，可折叠）
    explorePanel_ = UI.Panel {
        id = "explorePanel",
        width = "100%",
        padding = Theme.sizes.padding,
        backgroundColor = Theme.colors.bg_primary,
        gap = 6,
        overflow = "scroll",
        flexShrink = 1,
    }
    rebuildExplorePanel()

    -- 底部路线面板（初始隐藏）
    routePanel_ = UI.Panel {
        id = "routePanel",
        width = "100%",
        height = 0,
        padding = 0,
        display = "none",
        backgroundColor = Theme.colors.bg_card,
        borderTopWidth = 1,
        borderColor = Theme.colors.border,
        gap = 0,
    }

    return UI.Panel {
        id = "mapScreen",
        width = "100%", height = "100%",
        children = {
            canvas,
            explorePanel_,
            routePanel_,
            modal_,
        },
    }
end

function M.update(state, dt, r)
    state_ = state
    handleInput(dt)
end

return M

--- 地图 NanoVG 渲染模块
--- 从 screen_map.lua 提取：所有 NanoVG 绘制函数（节点、边、路线、情报、图例）
local Theme     = require("ui/theme")
local Graph     = require("map/world_graph")
local MapCamera = require("map/map_camera")
local Flow      = require("core/flow")
local Intel     = require("settlement/intel")
local Goods     = require("economy/goods")
local OrderBook = require("economy/order_book")

local M = {}

-- ============================================================
-- 显示常量
-- ============================================================
local NODE_ICON = {
    settlement = "🏘", resource = "📦", transit = "🔀",
    hazard     = "⚠",  story    = "📡",
}
local EDGE_LABEL  = { main_road = "主干道", path = "小径", shortcut = "捷径" }
local DANGER_STR  = { safe = "低", normal = "中", danger = "高" }

-- 情报图层状态
local intelLayerVisible_ = false
-- 自动计划按钮 hitbox
local autoPlanBtn_ = { x = 0, y = 0, w = 0, h = 0 }

--- 获取/设置情报图层可见性
function M.isIntelVisible() return intelLayerVisible_ end
function M.toggleIntel() intelLayerVisible_ = not intelLayerVisible_ end

--- 获取自动计划按钮 hitbox
function M.getAutoPlanBtn() return autoPlanBtn_ end

--- 获取情报切换按钮 hitbox（由 drawIntelToggle 计算）
---@return table {x, y, w, h}
function M.getIntelToggleRect()
    local c = MapCamera.cam
    return { x = c.cx + c.cw - 108, y = c.cy + 80, w = 96, h = 28 }
end

-- ============================================================
-- NanoVG 辅助
-- ============================================================
local function fc(nvg, c, a)
    nvgFillColor(nvg, nvgRGBA(c[1], c[2], c[3], a or c[4]))
end
local function sc(nvg, c, a)
    nvgStrokeColor(nvg, nvgRGBA(c[1], c[2], c[3], a or c[4]))
end

--- 画虚线
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
-- pin 形状路径（水滴形）
-- ============================================================
--- cx, cy 是 pin 尖端的位置，r 是头部圆的半径
local function pinPath(nvg, cx, cy, r)
    local PIN_H = MapCamera.PIN_H
    local headCY = cy - r * PIN_H

    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx, cy)

    nvgBezierTo(nvg,
        cx + r * 0.4,  cy - r * 0.35,
        cx + r,        headCY + r * 0.45,
        cx + r,        headCY)

    nvgArc(nvg, cx, headCY, r, 0, math.pi, NVG_CCW)

    nvgBezierTo(nvg,
        cx - r,        headCY + r * 0.45,
        cx - r * 0.4,  cy - r * 0.35,
        cx, cy)

    nvgClosePath(nvg)
end

-- ============================================================
-- 绘制：网格
-- ============================================================
local function drawGrid(nvg)
    local c = MapCamera.cam
    local gc = Theme.colors.map_grid
    sc(nvg, gc)
    nvgStrokeWidth(nvg, 1)
    local gs = 50 * c.scale
    if gs < 10 then return end

    local ox = c.panX % gs + c.cx
    local oy = c.panY % gs + c.cy
    for gx = ox, c.cx + c.cw, gs do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, gx, c.cy)
        nvgLineTo(nvg, gx, c.cy + c.ch)
        nvgStroke(nvg)
    end
    for gy = oy, c.cy + c.ch, gs do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, c.cx, gy)
        nvgLineTo(nvg, c.cx + c.cw, gy)
        nvgStroke(nvg)
    end
end

-- ============================================================
-- 绘制：边
-- ============================================================
local function drawEdges(nvg, known)
    local w2s = MapCamera.w2s
    local font = MapCamera.cam.font

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

                -- 中点标注
                local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, mx - 18, my - 8, 36, 16, 8)
                fc(nvg, Theme.colors.map_edge_label_bg)
                nvgFill(nvg)

                nvgFontFaceId(nvg, font)
                nvgFontSize(nvg, 10)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                fc(nvg, Theme.colors.map_label_text)
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
local function drawNodes(nvg, known, current, destSet, time, adjacentUnknowns)
    local w2s = MapCamera.w2s
    local cam = MapCamera.cam
    local NODE_R = MapCamera.NODE_R
    local PIN_H  = MapCamera.PIN_H

    for _, node in ipairs(Graph.NODES) do
        local sx, sy = w2s(node.x, node.y)
        local isKnown = known[node.id]
        local isCur   = node.id == current
        local isDest  = destSet[node.id]
        local isSel   = cam.selected == node.id

        if not isKnown then
            local isAdjacent = adjacentUnknowns and adjacentUnknowns[node.id]
            if isAdjacent then
                local pulse = 0.4 + 0.6 * math.abs(math.sin(time * 1.5))
                local adjR = NODE_R * 0.65
                pinPath(nvg, sx, sy, adjR + 3 * math.sin(time * 1.5))
                fc(nvg, Theme.colors.warning, math.floor(35 * pulse))
                nvgFill(nvg)
                pinPath(nvg, sx, sy, adjR)
                fc(nvg, { 55, 48, 30, 200 })
                nvgFill(nvg)
                sc(nvg, Theme.colors.warning, math.floor(160 * pulse))
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
                local headCY = sy - adjR * PIN_H
                nvgFontFaceId(nvg, cam.font)
                nvgFontSize(nvg, 13)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                fc(nvg, Theme.colors.warning, 220)
                nvgText(nvg, sx, headCY, "?", nil)
            else
                local smallR = NODE_R * 0.4
                pinPath(nvg, sx, sy, smallR)
                fc(nvg, Theme.colors.map_unknown)
                nvgFill(nvg)
                local headCY = sy - smallR * PIN_H
                nvgFontFaceId(nvg, cam.font)
                nvgFontSize(nvg, 10)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                fc(nvg, Theme.colors.map_label_text, 120)
                nvgText(nvg, sx, headCY, "?", nil)
            end
        else
            local pinR = NODE_R
            local pinY = sy
            local col

            if isCur then
                col = { 220, 50, 50, 255 }
                pinR = NODE_R * 1.35
                local floatOff = -(math.sin(time * 2.0) * 0.5 + 0.5) * 4.0
                pinY = sy + floatOff
            elseif isDest then
                col = Theme.colors.map_dest
            else
                col = Theme.colors.map_node
            end

            local headCY = pinY - pinR * PIN_H

            -- 投影
            if isCur then
                local lift = (math.sin(time * 2.0) * 0.5 + 0.5)
                local shadowAlpha = 45 - 15 * lift
                local shadowScale = 1.0 - 0.2 * lift
                nvgBeginPath(nvg)
                nvgEllipse(nvg, sx, sy + 2, pinR * 0.6 * shadowScale, pinR * 0.18 * shadowScale)
                fc(nvg, { 0, 0, 0, math.floor(shadowAlpha) })
                nvgFill(nvg)
            end

            -- 脉冲光环
            if isCur then
                local pulse = 0.4 + 0.6 * math.abs(math.sin(time * 1.8))
                pinPath(nvg, sx, pinY, pinR + 4 + 2 * math.sin(time * 1.8))
                fc(nvg, col, math.floor(40 * pulse))
                nvgFill(nvg)
            elseif isDest or isSel then
                pinPath(nvg, sx, pinY, pinR + 4)
                fc(nvg, col, 40)
                nvgFill(nvg)
            end

            -- 选中描边
            if isSel then
                pinPath(nvg, sx, pinY, pinR + 2)
                sc(nvg, Theme.colors.text_primary, 170)
                nvgStrokeWidth(nvg, 1.5)
                nvgStroke(nvg)
            end

            -- pin 本体
            pinPath(nvg, sx, pinY, pinR)
            fc(nvg, Theme.colors.map_node_fill)
            nvgFill(nvg)
            sc(nvg, col, 220)
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)

            -- 头部内圆
            local innerR = pinR * 0.7
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, headCY, innerR)
            fc(nvg, col, 50)
            nvgFill(nvg)

            -- 图标
            nvgFontFaceId(nvg, cam.font)
            nvgFontSize(nvg, isCur and 17 or 15)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            fc(nvg, col)
            nvgText(nvg, sx, headCY, NODE_ICON[node.type] or "●", nil)

            -- 名称标签
            nvgFontSize(nvg, isCur and 12 or 11)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
            local tw = nvgTextBounds(nvg, 0, 0, node.name, nil)
            local lbx = sx - tw / 2 - 3
            local lby = headCY - pinR - 2
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, lbx, lby - 14, tw + 6, 16, 3)
            fc(nvg, Theme.colors.map_label_bg)
            nvgFill(nvg)
            fc(nvg, Theme.colors.map_label_text)
            nvgText(nvg, sx, lby, node.name, nil)

            -- 目的地角标
            if isDest then
                nvgFontSize(nvg, 11)
                nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
                fc(nvg, Theme.colors.accent)
                nvgText(nvg, sx + pinR * 0.5, headCY - pinR * 0.5, "🎯", nil)
            end
        end
    end
end

-- ============================================================
-- 绘制：图例
-- ============================================================
local function drawLegend(nvg)
    local c = MapCamera.cam
    local lx = c.cx + c.cw - 110
    local ly = c.cy + 10
    local rowH = 16

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, lx - 8, ly - 6, 106, rowH * 3 + 20, 6)
    fc(nvg, Theme.colors.map_legend_bg)
    nvgFill(nvg)
    sc(nvg, Theme.colors.map_road, 80)
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgFontFaceId(nvg, c.font)
    nvgFontSize(nvg, 10)
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

    local y = ly + rowH * 0.5
    sc(nvg, Theme.colors.map_road)
    nvgStrokeWidth(nvg, 2)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, lx, y); nvgLineTo(nvg, lx + 22, y)
    nvgStroke(nvg)
    fc(nvg, Theme.colors.map_label_text)
    nvgText(nvg, lx + 28, y, "主干道", nil)

    y = y + rowH
    sc(nvg, Theme.colors.map_path)
    nvgStrokeWidth(nvg, 2)
    dashedLine(nvg, lx, y, lx + 22, y, 6, 4)
    fc(nvg, Theme.colors.map_label_text)
    nvgText(nvg, lx + 28, y, "小径", nil)

    y = y + rowH
    sc(nvg, Theme.colors.map_shortcut)
    nvgStrokeWidth(nvg, 2)
    dashedLine(nvg, lx, y, lx + 22, y, 3, 4)
    fc(nvg, Theme.colors.map_label_text)
    nvgText(nvg, lx + 28, y, "捷径(危)", nil)
end

-- ============================================================
-- 绘制：情报图层
-- ============================================================
local function drawIntelLayer(nvg, state, time)
    if not state or not intelLayerVisible_ then return end
    local intels = Intel.get_active_intel(state)
    if #intels == 0 then return end

    local cam = MapCamera.cam
    local w2s = MapCamera.w2s
    local NODE_R = MapCamera.NODE_R
    local PIN_H  = MapCamera.PIN_H

    nvgFontFaceId(nvg, cam.font)

    local settlement_nodes = {}
    for _, node in ipairs(Graph.NODES) do
        if node.type == "settlement" then
            settlement_nodes[node.id] = node
        end
    end

    for _, info in ipairs(intels) do
        if info.type == "tip" and info.target_settlement then
            local node = settlement_nodes[info.target_settlement]
                      or Graph.get_node(info.target_settlement)
            if node then
                local sx, sy = w2s(node.x, node.y)
                local hcy = sy - NODE_R * PIN_H
                local pulse = 0.5 + 0.5 * math.abs(math.sin(time * 2.2))
                nvgBeginPath(nvg)
                nvgCircle(nvg, sx, hcy, NODE_R + 6 + 3 * math.sin(time * 2.2))
                fc(nvg, Theme.colors.intel_tip, math.floor(50 * pulse))
                nvgFill(nvg)
                nvgFontSize(nvg, 16)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                fc(nvg, Theme.colors.intel_tip)
                nvgText(nvg, sx + NODE_R + 2, hcy - NODE_R + 2, "💰", nil)
                local g = Goods.get(info.target_goods)
                if g then
                    nvgFontSize(nvg, 9)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
                    local lbl = "急需" .. g.name
                    local tw = nvgTextBounds(nvg, 0, 0, lbl, nil)
                    nvgBeginPath(nvg)
                    nvgRoundedRect(nvg, sx - tw / 2 - 3, hcy - NODE_R - 16, tw + 6, 13, 3)
                    fc(nvg, { 180, 50, 40, 200 })
                    nvgFill(nvg)
                    fc(nvg, { 255, 240, 220, 240 })
                    nvgText(nvg, sx, hcy - NODE_R - 4, lbl, nil)
                end
            end

        elseif info.type == "price" and info.target_settlement then
            local node = settlement_nodes[info.target_settlement]
                      or Graph.get_node(info.target_settlement)
            if node then
                local sx, sy = w2s(node.x, node.y)
                local hcy = sy - NODE_R * PIN_H
                nvgFontSize(nvg, 14)
                nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_BOTTOM)
                fc(nvg, Theme.colors.intel_price)
                nvgText(nvg, sx + NODE_R + 2, hcy, "📊", nil)
                nvgFontSize(nvg, 9)
                nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
                local lbl = "物价已掌握"
                local tw = nvgTextBounds(nvg, 0, 0, lbl, nil)
                nvgBeginPath(nvg)
                nvgRoundedRect(nvg, sx - tw / 2 - 3, sy + 4, tw + 6, 13, 3)
                fc(nvg, { 140, 110, 30, 180 })
                nvgFill(nvg)
                fc(nvg, { 255, 245, 220, 240 })
                nvgText(nvg, sx, sy + 5, lbl, nil)
            end
        end
    end
end

--- 绘制情报图层切换按钮 + 全局情报状态指示器
local function drawIntelToggle(nvg, state)
    if not state then return end
    local intels = Intel.get_active_intel(state)
    local cam = MapCamera.cam

    local bx = cam.cx + cam.cw - 108
    local by = cam.cy + 80
    local bw, bh = 96, 28

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx, by, bw, bh, 14)
    if intelLayerVisible_ then
        fc(nvg, Theme.colors.intel_toggle_active)
    else
        fc(nvg, Theme.colors.intel_toggle_bg)
    end
    nvgFill(nvg)
    sc(nvg, Theme.colors.map_road, 100)
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgFontFaceId(nvg, cam.font)
    nvgFontSize(nvg, 11)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    fc(nvg, { 240, 235, 225, 240 })
    local label = intelLayerVisible_ and "📡 情报 ON" or "📡 情报 OFF"
    nvgText(nvg, bx + bw / 2, by + bh / 2, label, nil)

    if #intels > 0 then
        local badge = tostring(#intels)
        nvgBeginPath(nvg)
        nvgCircle(nvg, bx + bw - 4, by + 4, 8)
        fc(nvg, Theme.colors.intel_tip)
        nvgFill(nvg)
        nvgFontSize(nvg, 9)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        fc(nvg, { 255, 255, 255, 255 })
        nvgText(nvg, bx + bw - 4, by + 4, badge, nil)
    end

    -- 全局情报状态指示器
    if intelLayerVisible_ and #intels > 0 then
        local iy = by + bh + 6
        for _, info in ipairs(intels) do
            local icon, col, txt
            if info.type == "security" then
                icon = "🛡"; col = Theme.colors.intel_security
                txt = "安全预警(" .. info.trips_left .. "趟)"
            elseif info.type == "weather" then
                icon = "🌤"; col = Theme.colors.intel_weather
                txt = "天气预报(" .. info.trips_left .. "趟)"
            elseif info.type == "price" then
                icon = "📊"; col = Theme.colors.intel_price
                txt = info.desc_text and string.sub(info.desc_text, 1, 30) or "价格情报"
            elseif info.type == "tip" then
                icon = "💰"; col = Theme.colors.intel_tip
                txt = info.desc_text and string.sub(info.desc_text, 1, 30) or "商机情报"
            else
                icon = "📄"; col = Theme.colors.text_dim
                txt = info.desc_text or info.type
            end

            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, bx - 10, iy, bw + 10, 18, 4)
            fc(nvg, { col[1], col[2], col[3], 40 })
            nvgFill(nvg)

            nvgFontSize(nvg, 10)
            nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
            fc(nvg, col)
            nvgText(nvg, bx - 6, iy + 9, icon .. " " .. txt, nil)
            iy = iy + 22
        end
    end

    -- 自动计划按钮
    local apY = by + bh + 6
    if intelLayerVisible_ and #intels > 0 then
        apY = apY + #intels * 22 + 4
    end
    local apW, apH = 96, 28
    autoPlanBtn_.x = bx
    autoPlanBtn_.y = apY
    autoPlanBtn_.w = apW
    autoPlanBtn_.h = apH

    nvgBeginPath(nvg)
    nvgRoundedRect(nvg, bx, apY, apW, apH, 14)
    fc(nvg, Theme.colors.bg_secondary)
    nvgFill(nvg)
    sc(nvg, Theme.colors.accent, 100)
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    nvgFontFaceId(nvg, cam.font)
    nvgFontSize(nvg, 11)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    fc(nvg, Theme.colors.accent)
    nvgText(nvg, bx + apW / 2, apY + apH / 2, "⚙ 自动计划", nil)
end

-- ============================================================
-- 绘制：路线高亮
-- ============================================================
local function drawRoutePath(nvg, plan, colorKey)
    if not plan or not plan.path or #plan.path < 2 then return end
    local w2s = MapCamera.w2s
    local col = Theme.colors[colorKey] or Theme.colors.map_route_fastest

    -- 发光底层
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

    -- 主线
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

    -- 方向箭头
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
-- 绘制：活跃旅行路线
-- ============================================================
local function drawActiveRoute(nvg, plan, time)
    if not plan or not plan.segments or #plan.segments == 0 then return end
    if not plan.path or #plan.path < 2 then return end
    local w2s = MapCamera.w2s
    local cam = MapCamera.cam

    local segIdx = plan.segment_index or 0
    if segIdx == 0 then return end

    -- 已走过的段（灰色）
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

    -- 当前段及剩余段
    local startSeg = math.max(segIdx, 1)
    for i = startSeg, #plan.path - 1 do
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
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, x1, y1)
            nvgLineTo(nvg, x2, y2)
            sc(nvg, Theme.colors.map_route_active)
            nvgStrokeWidth(nvg, 4)
            nvgStroke(nvg)
        end
    end

    -- 方向箭头（剩余段）
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

    -- 卡车插值位置
    local seg = plan.segments[segIdx]
    if seg then
        local fromNode = Graph.get_node(seg.from)
        local toNode   = Graph.get_node(seg.to)
        if fromNode and toNode then
            local t = 0
            if seg.time_sec > 0 then
                t = math.min((plan.segment_elapsed or 0) / seg.time_sec, 1.0)
            end
            local wx = fromNode.x + (toNode.x - fromNode.x) * t
            local wy = fromNode.y + (toNode.y - fromNode.y) * t
            local tx, ty = w2s(wx, wy)

            local pulse = 0.5 + 0.5 * math.abs(math.sin(time * 2.5))
            local pr = 14 + 4 * math.sin(time * 2.5)
            nvgBeginPath(nvg)
            nvgCircle(nvg, tx, ty, pr)
            fc(nvg, Theme.colors.map_truck, math.floor(60 * pulse))
            nvgFill(nvg)

            if not cam.truckIcon then
                cam.truckIcon = nvgCreateImage(nvg, "image/chibi_truck_q.png", 0)
            end
            if cam.truckIcon and cam.truckIcon > 0 then
                local iconSize = 40
                local halfIcon = iconSize * 0.5
                local dirX = toNode.x - fromNode.x
                local dirY = toNode.y - fromNode.y
                local angle = math.atan(dirY, dirX)
                nvgSave(nvg)
                nvgTranslate(nvg, tx, ty)
                nvgRotate(nvg, angle - math.pi)
                local normAngle = angle % (2 * math.pi)
                if normAngle > math.pi * 0.5 and normAngle < math.pi * 1.5 then
                    -- 朝左半边，正常
                else
                    nvgScale(nvg, 1, -1)
                end
                local paint = nvgImagePattern(nvg, -halfIcon, -halfIcon, iconSize, iconSize, 0, cam.truckIcon, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, -halfIcon, -halfIcon, iconSize, iconSize)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
                nvgRestore(nvg)
            end
        end
    end
end

--- 绘制手动模式途经点标记
local function drawWaypoints(nvg, waypoints)
    local w2s = MapCamera.w2s
    local cam = MapCamera.cam
    local NODE_R = MapCamera.NODE_R
    local PIN_H  = MapCamera.PIN_H

    for i, wpId in ipairs(waypoints) do
        local node = Graph.get_node(wpId)
        if node then
            local sx, sy = w2s(node.x, node.y)
            local hcy = sy - NODE_R * PIN_H
            nvgBeginPath(nvg)
            nvgCircle(nvg, sx, hcy, NODE_R + 6)
            sc(nvg, Theme.colors.map_waypoint)
            nvgStrokeWidth(nvg, 2)
            nvgStroke(nvg)
            nvgFontFaceId(nvg, cam.font)
            nvgFontSize(nvg, 10)
            nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
            fc(nvg, Theme.colors.map_waypoint)
            nvgText(nvg, sx + NODE_R + 8, hcy - NODE_R, tostring(i), nil)
        end
    end
end

-- ============================================================
-- 主绘制入口
-- ============================================================

--- 绘制完整地图
---@param nvg userdata NanoVG context
---@param layout table {x, y, w, h}
---@param state table 游戏状态
---@param mapMode table 模式状态（来自 map_mode）
function M.drawMap(nvg, layout, state, mapMode)
    local cam = MapCamera.cam
    local w2s = MapCamera.w2s
    local NODE_R = MapCamera.NODE_R
    local MapState = require("map/map_mode").MapState
    local STRATEGY_COLORS_ref = require("map/map_mode").STRATEGY_COLORS

    cam.cx = layout.x
    cam.cy = layout.y
    cam.cw = layout.w
    cam.ch = layout.h

    -- 惰性初始化字体
    if not cam.font then
        cam.font = nvgCreateFont(nvg, "map-sans", "Fonts/MiSans-Regular.ttf")
    end

    -- 首次居中
    MapCamera.initCamera(state, Flow)

    local known   = state.map.known_nodes or {}
    local current = state.map.current_location
    local destSet = OrderBook.get_destination_set(state)
    local time    = os.clock()

    -- 1) 背景底色
    nvgBeginPath(nvg)
    nvgRect(nvg, cam.cx, cam.cy, cam.cw, cam.ch)
    fc(nvg, Theme.colors.map_bg)
    nvgFill(nvg)

    -- 2) 裁剪区域
    nvgSave(nvg)
    nvgIntersectScissor(nvg, cam.cx, cam.cy, cam.cw, cam.ch)

    -- 桌子背景参数
    local TABLE_SHRINK = 0.85
    local mapCX, mapCY = 460, 300
    do
        local scaleX = 1000 / 539 * TABLE_SHRINK
        local scaleY = 680  / 393 * TABLE_SHRINK
        cam._tableWX = mapCX - 978.5 * scaleX
        cam._tableWY = mapCY - 547.5 * scaleY
        cam._tableWW = 1935 * scaleX
        cam._tableWH = 1080 * scaleY
    end

    -- 桌子背景图
    if not cam.tableBgImage then
        cam.tableBgImage = nvgCreateImage(nvg, "image/edited_map_table_bg_v7_20260411080504.png", 0)
    end
    if cam.tableBgImage and cam.tableBgImage > 0 then
        local tbX, tbY   = w2s(cam._tableWX, cam._tableWY)
        local tbX2, tbY2 = w2s(cam._tableWX + cam._tableWW, cam._tableWY + cam._tableWH)
        local tbW = tbX2 - tbX
        local tbH = tbY2 - tbY
        local drawX = math.max(tbX, cam.cx)
        local drawY = math.max(tbY, cam.cy)
        local drawR = math.min(tbX + tbW, cam.cx + cam.cw)
        local drawB = math.min(tbY + tbH, cam.cy + cam.ch)
        if drawR > drawX and drawB > drawY then
            local paint = nvgImagePattern(nvg, tbX, tbY, tbW, tbH, 0, cam.tableBgImage, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, drawX, drawY, drawR - drawX, drawB - drawY)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
        end
    end

    -- 地图背景图
    if not cam.bgImage then
        cam.bgImage = nvgCreateImage(nvg, "image/edited_map_bg_mashu_v2_20260411070244.png", 0)
    end
    if cam.bgImage and cam.bgImage > 0 then
        local bgX, bgY    = w2s(-40, -40)
        local bgX2, bgY2  = w2s(960, 640)
        local bgW = bgX2 - bgX
        local bgH = bgY2 - bgY
        local drawX = math.max(bgX, cam.cx)
        local drawY = math.max(bgY, cam.cy)
        local drawR = math.min(bgX + bgW, cam.cx + cam.cw)
        local drawB = math.min(bgY + bgH, cam.cy + cam.ch)
        if drawR > drawX and drawB > drawY then
            local paint = nvgImagePattern(nvg, bgX, bgY, bgW, bgH, 0, cam.bgImage, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, drawX, drawY, drawR - drawX, drawB - drawY)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
        end
    end

    drawGrid(nvg)
    drawEdges(nvg, known)

    -- 未知邻居虚线
    local adjacentUnknowns = {}
    local isTravellingNow = Flow.get_phase(state) == Flow.Phase.TRAVELLING
    if not isTravellingNow then
        local unknowns_list = Graph.get_unknown_neighbors(current, state)
        for _, adj in ipairs(unknowns_list) do
            adjacentUnknowns[adj.to] = true
        end
        local curNode = Graph.get_node(current)
        if curNode then
            for _, adj in ipairs(unknowns_list) do
                local targetNode = Graph.get_node(adj.to)
                if targetNode then
                    local x1, y1 = w2s(curNode.x, curNode.y)
                    local x2, y2 = w2s(targetNode.x, targetNode.y)
                    local edge = adj.edge
                    local pulse = 0.5 + 0.5 * math.abs(math.sin(time * 1.2))
                    local alpha = math.floor(120 * pulse)

                    if edge and edge.type == "main_road" then
                        sc(nvg, Theme.colors.map_road, alpha)
                        nvgStrokeWidth(nvg, 2.5)
                        dashedLine(nvg, x1, y1, x2, y2, 8, 5)
                    elseif edge and edge.type == "shortcut" then
                        sc(nvg, Theme.colors.map_shortcut, alpha)
                        nvgStrokeWidth(nvg, 2)
                        dashedLine(nvg, x1, y1, x2, y2, 3, 5)
                    else
                        sc(nvg, Theme.colors.map_path, alpha)
                        nvgStrokeWidth(nvg, 2)
                        dashedLine(nvg, x1, y1, x2, y2, 6, 5)
                    end

                    if edge then
                        local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
                        nvgBeginPath(nvg)
                        nvgRoundedRect(nvg, mx - 18, my - 8, 36, 16, 8)
                        fc(nvg, Theme.colors.map_edge_label_bg, math.floor(180 * pulse))
                        nvgFill(nvg)
                        nvgFontFaceId(nvg, cam.font)
                        nvgFontSize(nvg, 10)
                        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                        fc(nvg, Theme.colors.map_label_text, alpha)
                        nvgText(nvg, mx, my, edge.travel_time_sec .. "s", nil)
                        if edge.danger == "danger" then
                            fc(nvg, Theme.colors.danger, alpha)
                            nvgFontSize(nvg, 12)
                            nvgText(nvg, mx, my - 14, "⚠", nil)
                        end
                    end
                end
            end
        end
    end

    -- 路线高亮
    local isTravelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING
    if isTravelling and state.flow.route_plan then
        drawActiveRoute(nvg, state.flow.route_plan, time)
    elseif mapMode.state == MapState.ROUTE_PREVIEW and mapMode.activePlan then
        local colorKey = STRATEGY_COLORS_ref[mapMode.strategy] or "map_route_fastest"
        drawRoutePath(nvg, mapMode.activePlan, colorKey)
    elseif mapMode.state == MapState.MANUAL_PLAN and mapMode.manualPlan then
        drawRoutePath(nvg, mapMode.manualPlan, "map_route_manual")
        drawWaypoints(nvg, mapMode.waypoints)
    end

    -- 桌面物件覆盖层
    if not cam.tableOverlay then
        cam.tableOverlay = nvgCreateImage(nvg, "image/edited_map_table_bg_v7_overlay_20260411080504.png", 0)
    end
    if cam.tableOverlay and cam.tableOverlay > 0 then
        local olX, olY   = w2s(cam._tableWX, cam._tableWY)
        local olX2, olY2 = w2s(cam._tableWX + cam._tableWW, cam._tableWY + cam._tableWH)
        local olW = olX2 - olX
        local olH = olY2 - olY
        local drawX = math.max(olX, cam.cx)
        local drawY = math.max(olY, cam.cy)
        local drawR = math.min(olX + olW, cam.cx + cam.cw)
        local drawB = math.min(olY + olH, cam.cy + cam.ch)
        if drawR > drawX and drawB > drawY then
            local paint = nvgImagePattern(nvg, olX, olY, olW, olH, 0, cam.tableOverlay, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, drawX, drawY, drawR - drawX, drawB - drawY)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)
        end
    end

    drawNodes(nvg, known, current, destSet, time, adjacentUnknowns)
    drawIntelLayer(nvg, state, time)

    nvgRestore(nvg)

    -- 3) 覆盖 UI 层（不受裁剪）
    drawLegend(nvg)
    drawIntelToggle(nvg, state)
end

return M

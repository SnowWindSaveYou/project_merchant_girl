--- 地图相机、坐标变换与输入处理
--- 从 screen_map.lua 提取，独立管理地图视口和交互状态
local UI    = require("urhox-libs/UI")
local Graph = require("map/world_graph")

local M = {}

-- ============================================================
-- 常量
-- ============================================================
M.NODE_R      = 16      -- 节点圆半径
M.PIN_H       = 1.4     -- pin 头部圆心相对于尖端的偏移系数
local HIT_R_SQ    = 26 * 26 -- 点击判定半径平方
local DRAG_THRESH = 5       -- 拖拽触发阈值(px)
local ZOOM_MIN    = 0.6
local ZOOM_MAX    = 2.5
local ZOOM_STEP   = 0.12

-- ============================================================
-- 相机状态（页面级，非全局）
-- ============================================================
M.cam = {
    panX = 0, panY = 0, scale = 1.0,
    selected = nil,        -- 选中节点 id
    font     = nil,        -- NanoVG 字体句柄
    -- 画布绝对矩形（逻辑坐标，每帧更新）
    cx = 0, cy = 0, cw = 1, ch = 1,
    initialized = false,
    -- 背景/覆盖层图片句柄
    bgImage     = nil,
    tableBgImage = nil,
    tableOverlay = nil,
    truckIcon   = nil,
    -- 桌子背景世界坐标（drawMap 初始化时填充）
    _tableWX = 0, _tableWY = 0, _tableWW = 0, _tableWH = 0,
}

-- ============================================================
-- 输入状态
-- ============================================================
local inp = {
    wasDown = false,
    pressX  = 0, pressY = 0,
    lastX   = 0, lastY  = 0,
    isDrag  = false,
    -- 双指缩放
    pinching      = false,
    lastPinchDist = 0,
    pinchCooldown = 0,
}

-- ============================================================
-- 坐标转换
-- ============================================================

--- 世界坐标 → 屏幕逻辑坐标
---@param wx number
---@param wy number
---@return number sx, number sy
function M.w2s(wx, wy)
    local c = M.cam
    return wx * c.scale + c.panX + c.cx,
           wy * c.scale + c.panY + c.cy
end

--- 屏幕逻辑坐标 → 世界坐标
---@param sx number
---@param sy number
---@return number wx, number wy
function M.s2w(sx, sy)
    local c = M.cam
    return (sx - c.cx - c.panX) / c.scale,
           (sy - c.cy - c.panY) / c.scale
end

--- 逻辑坐标是否在地图可交互区域
---@param lx number
---@param ly number
---@return boolean
function M.inMapArea(lx, ly)
    local c = M.cam
    return lx >= c.cx and lx <= c.cx + c.cw
       and ly >= c.cy and ly <= c.cy + c.ch
end

-- ============================================================
-- 节点查找
-- ============================================================

--- 查找逻辑坐标下的已知节点
---@param lx number
---@param ly number
---@param known table
---@return string|nil nodeId
function M.findNodeAt(lx, ly, known)
    local bestId, bestDSq = nil, HIT_R_SQ
    for _, node in ipairs(Graph.NODES) do
        if known[node.id] then
            local sx, sy = M.w2s(node.x, node.y)
            local hcy = sy - M.NODE_R * M.PIN_H
            local dx, dy = lx - sx, ly - hcy
            local dSq = dx * dx + dy * dy
            if dSq < bestDSq then
                bestDSq = dSq
                bestId  = node.id
            end
        end
    end
    return bestId
end

--- 查找逻辑坐标下的可探索未知邻居节点
---@param lx number
---@param ly number
---@param current string
---@param state table
---@return string|nil nodeId
function M.findAdjacentUnknownNodeAt(lx, ly, current, state)
    local unknowns = Graph.get_unknown_neighbors(current, state)
    local bestId, bestDSq = nil, HIT_R_SQ
    local adjR = M.NODE_R * 0.65
    for _, adj in ipairs(unknowns) do
        local node = Graph.get_node(adj.to)
        if node then
            local sx, sy = M.w2s(node.x, node.y)
            local hcy = sy - adjR * M.PIN_H
            local dx, dy = lx - sx, ly - hcy
            local dSq = dx * dx + dy * dy
            if dSq < bestDSq then
                bestDSq = dSq
                bestId  = adj.to
            end
        end
    end
    return bestId
end

-- ============================================================
-- 相机初始化
-- ============================================================

--- 首次打开地图时居中到当前位置（或旅行中居中到卡车插值位置）
---@param state table
---@param Flow table
function M.initCamera(state, Flow)
    local c = M.cam
    if c.initialized then return end

    local centerX, centerY = nil, nil
    local plan = state.flow.route_plan
    local travelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING
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
        local curNode = Graph.get_node(state.map.current_location)
        if curNode then
            centerX = curNode.x
            centerY = curNode.y
        end
    end
    if centerX then
        c.scale = math.min(c.cw, c.ch) / 480
        c.scale = math.max(ZOOM_MIN, math.min(c.scale, ZOOM_MAX))
        c.panX = c.cw / 2 - centerX * c.scale
        c.panY = c.ch / 2 - centerY * c.scale
    end
    c.initialized = true
end

--- 重置相机和输入状态（页面首次进入时调用）
function M.reset()
    local c = M.cam
    c.initialized = false
    c.selected    = nil

    inp.wasDown     = false
    inp.isDrag      = false
    inp.pinching    = false
    inp.lastPinchDist = 0
    inp.pinchCooldown = 0
end

--- 预估画布尺寸（避免首帧 cam 值为默认值导致输入失效）
function M.preEstimateCanvas()
    local uiScale = UI.GetScale()
    local c = M.cam
    c.cw = graphics:GetWidth() / uiScale
    c.ch = graphics:GetHeight() / uiScale
    c.cx = 0
    c.cy = 0
end

-- ============================================================
-- 输入处理
-- ============================================================

--- 处理地图输入（拖拽平移、滚轮/双指缩放、点击判定）
---@param dt number
---@param state table
---@param modalOpen boolean 模态框是否打开
---@param callbacks table { onNodeClick, onUnknownClick, onEmptyClick, onIntelToggle, onAutoPlan, autoPlanBtn, intelToggleRect }
function M.handleInput(dt, state, modalOpen, callbacks)
    local c = M.cam
    if not state or c.cw < 2 then return end
    if not c.initialized then return end
    if modalOpen then return end

    local uiScale = UI.GetScale()
    local mx = input.mousePosition.x / uiScale
    local my = input.mousePosition.y / uiScale

    -- ── 双指缩放 ──
    local numTouches = input:GetNumTouches()
    if numTouches >= 2 then
        local t0 = input:GetTouch(0)
        local t1 = input:GetTouch(1)
        local dx = t1.position.x / uiScale - t0.position.x / uiScale
        local dy = t1.position.y / uiScale - t0.position.y / uiScale
        local dist = math.sqrt(dx * dx + dy * dy)

        local cx = (t0.position.x + t1.position.x) / 2 / uiScale
        local cy = (t0.position.y + t1.position.y) / 2 / uiScale

        if inp.pinching and inp.lastPinchDist > 10 then
            local factor = dist / inp.lastPinchDist
            if factor > 0.5 and factor < 2.0 then
                local lx = cx - c.cx
                local ly = cy - c.cy
                local wx = (lx - c.panX) / c.scale
                local wy = (ly - c.panY) / c.scale

                c.scale = c.scale * factor
                c.scale = math.max(ZOOM_MIN, math.min(c.scale, ZOOM_MAX))

                c.panX = lx - wx * c.scale
                c.panY = ly - wy * c.scale
            end
        end

        inp.pinching = true
        inp.lastPinchDist = dist
        inp.pinchCooldown = 0.2
        inp.wasDown = false
        return
    end

    -- 双指刚松开冷却期
    if inp.pinching then
        inp.pinching = false
        inp.lastPinchDist = 0
        inp.wasDown = false
        return
    end
    if inp.pinchCooldown > 0 then
        inp.pinchCooldown = inp.pinchCooldown - dt
        inp.wasDown = false
        return
    end

    -- ── 鼠标/单指 ──
    local isDown     = input:GetMouseButtonDown(MOUSEB_LEFT)
    local justPress  = isDown and not inp.wasDown
    local justRelease = not isDown and inp.wasDown

    if justPress then
        inp.pressX = mx
        inp.pressY = my
        inp.isDrag = false
    end

    if isDown and not inp.isDrag then
        local dx = mx - inp.pressX
        local dy = my - inp.pressY
        if dx * dx + dy * dy > DRAG_THRESH * DRAG_THRESH then
            inp.isDrag = true
        end
    end

    if isDown and inp.isDrag then
        local dx = mx - inp.lastX
        local dy = my - inp.lastY
        if not justPress then
            c.panX = c.panX + dx
            c.panY = c.panY + dy
        end
    end

    inp.lastX = mx
    inp.lastY = my

    -- 点击判定
    if justRelease and not inp.isDrag then
        local px, py = inp.pressX, inp.pressY

        -- 情报切换按钮
        local itRect = callbacks.intelToggleRect
        if itRect and px >= itRect.x and px <= itRect.x + itRect.w
           and py >= itRect.y and py <= itRect.y + itRect.h then
            if callbacks.onIntelToggle then callbacks.onIntelToggle() end
            inp.wasDown = isDown
            return
        end

        -- 自动计划按钮
        local ab = callbacks.autoPlanBtn
        if ab and px >= ab.x and px <= ab.x + ab.w
           and py >= ab.y and py <= ab.y + ab.h then
            if callbacks.onAutoPlan then callbacks.onAutoPlan() end
            inp.wasDown = isDown
            return
        end

        -- 地图节点点击
        if M.inMapArea(px, py) then
            local known = state.map.known_nodes or {}
            local nodeId = M.findNodeAt(px, py, known)

            if nodeId then
                if callbacks.onNodeClick then
                    callbacks.onNodeClick(nodeId)
                end
            else
                local unknownId = M.findAdjacentUnknownNodeAt(
                    px, py, state.map.current_location, state)
                if unknownId then
                    if callbacks.onUnknownClick then
                        callbacks.onUnknownClick(unknownId)
                    end
                else
                    if callbacks.onEmptyClick then
                        callbacks.onEmptyClick()
                    end
                end
            end
        end
    end

    inp.wasDown = isDown

    -- 滚轮缩放
    local wheel = input.mouseMoveWheel
    if wheel ~= 0 and M.inMapArea(mx, my) then
        local lx = mx - c.cx
        local ly = my - c.cy
        local wx = (lx - c.panX) / c.scale
        local wy = (ly - c.panY) / c.scale

        c.scale = c.scale + wheel * ZOOM_STEP
        c.scale = math.max(ZOOM_MIN, math.min(c.scale, ZOOM_MAX))

        c.panX = lx - wx * c.scale
        c.panY = ly - wy * c.scale
    end
end

return M

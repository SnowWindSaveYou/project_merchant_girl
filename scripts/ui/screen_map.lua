--- 大地图页面 — 控制器
--- 协调子模块：MapCamera（相机/输入）、MapMode（模式）、MapRenderer（渲染）、MapPanels（面板/弹窗）
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local SketchBorder = require("ui/sketch_border")

local MapCamera   = require("map/map_camera")
local MapMode     = require("map/map_mode")
local MapRenderer = require("map/map_renderer")
local MapPanels   = require("map/map_panels")

local M = {}

-- 模块引用
local router_ = nil
---@type table
local state_  = nil

-- Modal 引用
---@type table|nil
local modal_ = nil

-- ============================================================
-- 页面生命周期
-- ============================================================
function M.create(state, params, r)
    router_ = r
    state_  = state

    local cam = MapCamera.cam

    -- refresh 时保留相机和模式状态，仅重置交互态
    local isRefresh = F.skipEnterAnim
    if not isRefresh then
        MapCamera.reset()
        MapMode.reset()
        MapPanels.reset()
    end

    MapCamera.preEstimateCanvas()

    -- 全屏画布 Panel，自定义 NanoVG 渲染
    local canvas = UI.Panel {
        id     = "mapCanvas",
        width  = "100%",
        flexGrow = 1,
        backgroundColor = Theme.colors.map_bg,
    }

    -- 注入自定义渲染
    canvas.CustomRenderChildren = function(self, nvg, renderFn)
        MapRenderer.drawMap(nvg, self:GetAbsoluteLayout(), state_, MapMode.mapMode)
    end

    -- Modal 弹窗
    modal_ = UI.Modal {
        size = "sm",
        title = "",
        closeOnOverlay = true,
        closeOnEscape = true,
        onClose = function(self)
            cam.selected = nil
            self:SetSize("sm")
        end,
    }
    modal_.borderRadius_ = Theme.sizes.radius

    -- 自定义 Modal 渲染（游戏 Theme 风格）
    modal_.RenderModalContent = function(self, nvg)
        local UiLib = require("urhox-libs/UI/Core/UI")
        local screenWidth  = UiLib.GetWidth() or 800
        local screenHeight = UiLib.GetHeight() or 600
        local borderRadius = self.borderRadius_
        local title = self.title_
        local showCloseButton = self.showCloseButton_

        local headerHeight   = 56
        local footerHeight   = 64
        local contentPadding = 16

        local SIZE_PRESETS = {
            sm = { width = 320, maxHeight = 400 },
            md = { width = 480, maxHeight = 600 },
            lg = { width = 640, maxHeight = 720 },
            xl = { width = 800, maxHeight = 800 },
            fullscreen = { width = "90%", maxHeight = "90%" },
        }
        local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
        local modalWidth    = sizePreset.width
        local modalMaxHeight = sizePreset.maxHeight

        if type(modalWidth) == "string" and modalWidth:match("%%$") then
            modalWidth = screenWidth * tonumber(modalWidth:match("(%d+)")) / 100
        end
        if type(modalMaxHeight) == "string" and modalMaxHeight:match("%%$") then
            modalMaxHeight = screenHeight * tonumber(modalMaxHeight:match("(%d+)")) / 100
        end

        local alpha     = self.animProgress_
        local animScale = 0.9 + 0.1 * alpha

        -- 遮罩
        local ov = Theme.colors.bg_overlay
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, screenWidth, screenHeight)
        nvgFillColor(nvg, nvgRGBA(ov[1], ov[2], ov[3], math.floor((ov[4] or 160) * alpha)))
        nvgFill(nvg)

        -- 布局计算
        local contentAreaWidth = modalWidth - contentPadding * 2
        local modalHeight = self:CalculateContentHeight(contentAreaWidth)
                + (title and headerHeight or 0)
                + (self.footerWidget_ and footerHeight or 0)
        modalHeight = math.min(modalHeight, modalMaxHeight)

        local modalX = (screenWidth  - modalWidth  * animScale) / 2
        local modalY = (screenHeight - modalHeight * animScale) / 2

        nvgSave(nvg)
        nvgTranslate(nvg, screenWidth / 2, screenHeight / 2)
        nvgScale(nvg, animScale, animScale)
        nvgTranslate(nvg, -screenWidth / 2, -screenHeight / 2)

        -- 阴影
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, modalX - 4, modalY - 2, modalWidth + 8, modalHeight + 12, borderRadius + 4)
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(60 * alpha)))
        nvgFill(nvg)

        -- 背景
        local bg = Theme.colors.bg_card
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, modalX, modalY, modalWidth, modalHeight, borderRadius)
        nvgFillColor(nvg, nvgRGBA(bg[1], bg[2], bg[3], math.floor(245 * alpha)))
        nvgFill(nvg)

        -- 边框
        local bc = Theme.colors.border
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, modalX, modalY, modalWidth, modalHeight, borderRadius)
        nvgStrokeColor(nvg, nvgRGBA(bc[1], bc[2], bc[3], math.floor(100 * alpha)))
        nvgStrokeWidth(nvg, 1)
        nvgStroke(nvg)

        self.modalLayout_ = { x = modalX, y = modalY, w = modalWidth, h = modalHeight }

        local contentY = modalY

        -- Header
        if title then
            contentY = self:RenderHeader(nvg, modalX, modalY, modalWidth, title, showCloseButton, alpha)
        elseif showCloseButton then
            self:RenderCloseButton(nvg, modalX + modalWidth - 44, modalY + 8, alpha)
            contentY = modalY + 16
        end

        -- 内容区域
        local footerHeightActual = self.footerWidget_ and footerHeight or 0
        local contentHeight = modalHeight - (contentY - modalY) - footerHeightActual

        if #self.contentContainer_.children > 0 then
            YGNodeCalculateLayout(self.contentContainer_.node, contentAreaWidth, contentHeight, YGDirectionLTR)
            self.contentContainer_.renderOffsetX_ = modalX + contentPadding
            self.contentContainer_.renderOffsetY_ = contentY
            self.contentContainer_.renderWidth_   = contentAreaWidth
            self.contentContainer_.renderHeight_  = contentHeight

            nvgSave(nvg)
            nvgIntersectScissor(nvg, modalX + contentPadding, contentY, contentAreaWidth, contentHeight)
            UiLib.RenderWidgetSubtree(self.contentContainer_, nvg)
            nvgRestore(nvg)
        end

        -- Footer
        if self.footerWidget_ then
            self:RenderFooter(nvg, modalX, modalY + modalHeight - footerHeight, modalWidth, footerHeight, alpha)
        end

        -- 素描边框
        local ink = Theme.sketch.ink_color
        local function sketchLine(x1, y1, x2, y2, seed)
            local segs = 16
            local dx, dy = x2 - x1, y2 - y1
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 1 then return end
            local nx, ny = -dy / len, dx / len
            nvgBeginPath(nvg)
            for i = 0, segs do
                local t = i / segs
                local jx = (math.sin(seed + i * 2.3) * 0.5) * 1.5
                local jy = (math.cos(seed + i * 3.1) * 0.5) * 1.5
                local px = x1 + dx * t + nx * jx
                local py = y1 + dy * t + ny * jy
                if i == 0 then
                    nvgMoveTo(nvg, px, py)
                else
                    nvgLineTo(nvg, px, py)
                end
            end
            nvgStrokeColor(nvg, nvgRGBA(ink[1], ink[2], ink[3], ink[4]))
            nvgStrokeWidth(nvg, 1.2)
            nvgLineCap(nvg, NVG_ROUND)
            nvgLineJoin(nvg, NVG_ROUND)
            nvgStroke(nvg)
        end

        local x, y, w, h = modalX, modalY, modalWidth, modalHeight
        local seed = 42
        sketchLine(x, y, x + w, y, seed + 1)
        sketchLine(x + w, y, x + w, y + h, seed + 2)
        sketchLine(x + w, y + h, x, y + h, seed + 3)
        sketchLine(x, y + h, x, y, seed + 4)

        local cornerLen = math.min(w, h) * 0.06
        nvgStrokeColor(nvg, nvgRGBA(ink[1], ink[2], ink[3], ink[4]))
        nvgStrokeWidth(nvg, 2.0)
        nvgLineCap(nvg, NVG_ROUND)
        local corners = {
            { x, y,         x + cornerLen, y,         x, y + cornerLen },
            { x + w, y,     x + w - cornerLen, y,     x + w, y + cornerLen },
            { x + w, y + h, x + w - cornerLen, y + h, x + w, y + h - cornerLen },
            { x, y + h,     x + cornerLen, y + h,     x, y + h - cornerLen },
        }
        for _, c in ipairs(corners) do
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, c[3], c[4])
            nvgLineTo(nvg, c[1], c[2])
            nvgLineTo(nvg, c[5], c[6])
            nvgStroke(nvg)
        end

        nvgRestore(nvg)
    end

    -- 探索区域面板
    local explorePanel = UI.Panel {
        id = "explorePanel",
        width = "100%",
        padding = Theme.sizes.padding,
        backgroundColor = Theme.colors.bg_primary,
        gap = 6,
        overflow = "scroll",
        flexShrink = 1,
    }
    SketchBorder.register(explorePanel, "card")

    -- 底部路线面板（初始隐藏）
    local routePanel = UI.Panel {
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

    -- 初始化面板模块
    MapPanels.init({
        state        = state,
        router       = r,
        modal        = modal_,
        routePanel   = routePanel,
        explorePanel = explorePanel,
    })
    MapPanels.rebuildExplorePanel()

    -- 从订单页带着 route_plan 模式进入
    if params and params.mode == "route_plan" then
        MapPanels.enterOrderRoutePreview(cam)
    end

    -- 教程引导气泡
    local tutBubble = nil
    local bubbleCfg = Tutorial.get_bubble_config(state, "map")
    if bubbleCfg then
        tutBubble = SpeechBubble.createWidget(bubbleCfg)
    end

    return UI.Panel {
        id = "mapScreen",
        width = "100%", height = "100%",
        children = {
            canvas,
            explorePanel,
            routePanel,
            modal_,
            tutBubble,
        },
    }
end

-- ============================================================
-- 输入处理（委托给 MapCamera，通过回调分发点击事件）
-- ============================================================
local function handleInput(dt)
    if not state_ then return end
    local cam = MapCamera.cam
    local mm  = MapMode.mapMode
    local modalOpen = modal_ and modal_:IsOpen() or false

    local function rebuildPanel()
        MapPanels.rebuildPanel(cam)
    end

    MapCamera.handleInput(dt, state_, modalOpen, {
        intelToggleRect = MapRenderer.getIntelToggleRect(),
        autoPlanBtn     = MapRenderer.getAutoPlanBtn(),

        onIntelToggle = function()
            MapRenderer.toggleIntel()
        end,

        onAutoPlan = function()
            MapPanels.openAutoPlanModal()
        end,

        onNodeClick = function(nodeId)
            if mm.state == MapMode.MapState.BROWSE then
                cam.selected = nodeId
                MapPanels.openNodeModal(nodeId, cam)

            elseif mm.state == MapMode.MapState.ROUTE_PREVIEW then
                if nodeId ~= state_.map.current_location then
                    MapMode.enterRoutePreview(nodeId, state_, cam, rebuildPanel)
                end

            elseif mm.state == MapMode.MapState.MANUAL_PLAN then
                local current = state_.map.current_location
                if nodeId ~= current then
                    local existIdx = nil
                    for i, wp in ipairs(mm.waypoints) do
                        if wp == nodeId then existIdx = i; break end
                    end
                    if existIdx then
                        for i = #mm.waypoints, existIdx, -1 do
                            table.remove(mm.waypoints, i)
                        end
                    else
                        table.insert(mm.waypoints, nodeId)
                    end
                    if #mm.waypoints >= 2 then
                        local travelling = Flow.get_phase(state_) == Flow.Phase.TRAVELLING
                        local fromOvr = travelling and MapMode.getEffectiveOrigin(state_) or nil
                        mm.manualPlan = RoutePlanner.manual_plan_with_fill(state_, mm.waypoints, fromOvr)
                    else
                        mm.manualPlan = nil
                    end
                    rebuildPanel()
                end
            end
        end,

        onUnknownClick = function(unknownId)
            if mm.state == MapMode.MapState.BROWSE then
                MapPanels.openUnknownNodeModal(unknownId)
            end
        end,

        onEmptyClick = function()
            if mm.state == MapMode.MapState.BROWSE then
                cam.selected = nil
            elseif mm.state == MapMode.MapState.ROUTE_PREVIEW then
                MapMode.exitToBase(cam, rebuildPanel)
            end
        end,
    })
end

function M.update(state, dt, r)
    state_ = state
    MapPanels.setState(state)
    SpeechBubble.update(dt)
    handleInput(dt)
end

return M

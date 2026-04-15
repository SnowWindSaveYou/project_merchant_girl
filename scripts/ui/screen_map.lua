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

    -- Modal 弹窗（使用统一的羊皮纸风格组件）
    modal_ = F.parchmentModal {
        size = "sm",
        title = "",
        closeOnOverlay = true,
        closeOnEscape = true,
        onClose = function(self)
            cam.selected = nil
            self:SetSize("sm")
        end,
    }

    -- 探索区域面板
    local explorePanel = UI.Panel {
        id = "explorePanel",
        width = "100%",
        padding = Theme.sizes.padding,
        backgroundColor = Theme.colors.bg_primary,
        backgroundImage = Theme.textures.parchment,
        backgroundFit = "cover",
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
        backgroundImage = Theme.textures.parchment,
        backgroundFit = "cover",
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

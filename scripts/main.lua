--- 末世行商 - 主入口
--- Post-Apocalyptic Merchant - Main Entry
local UI = require("urhox-libs/UI")

-- 核心模块
local State          = require("core/state")
local Flow           = require("core/flow")
local Ticker         = require("core/ticker")
local SaveLocal      = require("save/save_local")
local Offline        = require("save/offline")
local Router         = require("ui/router")
local EventPool      = require("events/event_pool")
local EventScheduler = require("events/event_scheduler")
local RoutePlanner   = require("map/route_planner")
local OrderBook      = require("economy/order_book")
local Graph          = require("map/world_graph")

-- 页面模块
local ScreenHome        = require("ui/screen_home")
local ScreenPrepare     = require("ui/screen_prepare")
local ScreenSummary     = require("ui/screen_summary")
local ScreenShop        = require("ui/screen_shop")
local ScreenEvent       = require("ui/screen_event")
local ScreenEventResult = require("ui/screen_event_result")
local ScreenMap         = require("ui/screen_map")
local ScreenRoutePlan   = require("ui/screen_route_plan")
local ScreenCargo       = require("ui/screen_cargo")

-- 游戏状态
---@type table
local gameState = nil
local saveTimer = 0
local SAVE_INTERVAL = 30

-- 行程中累计交付记录（用于最终结算展示）
local tripDeliveries = {}

-- ============================================================
-- 生命周期
-- ============================================================

function Start()
    graphics.windowTitle = "末世行商"

    -- 1. 初始化 UI
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 2. 加载或创建状态
    local saved = SaveLocal.load()
    if saved then
        gameState = saved
        -- 兼容旧存档：补充新字段
        if not gameState.economy.order_book then
            gameState.economy.order_book = {}
        end
        if not gameState.map.known_nodes then
            gameState.map.known_nodes = {
                greenhouse = true,
                tower = true,
                crossroads = true,
            }
        end
        if not gameState.map.available_orders then
            gameState.map.available_orders = {}
        end
        if not gameState.stats.consecutive_expires then
            gameState.stats.consecutive_expires = 0
        end
        -- 聚落信誉兼容
        for sid, sett in pairs(gameState.settlements) do
            if not sett.reputation then sett.reputation = 100 end
        end
        -- 如果当前在聚落且没有缓存订单，生成一批（等价于"到达"）
        local curLoc = gameState.map.current_location
        local curNodeInfo = Graph.get_node(curLoc)
        if curNodeInfo and curNodeInfo.type == "settlement" then
            OrderBook.generate_on_arrival(gameState, curLoc)
        end
        print("[Main] Loaded save, credits=" .. tostring(gameState.economy.credits))

        local offResult = Offline.apply(gameState, Ticker)
        if offResult then
            print("[Main] Offline " .. offResult.elapsed_sec .. "s")
            if offResult.arrived then
                print("[Main] Arrived during offline!")
            end
        end
    else
        gameState = State.new()
        -- 新游戏：为初始聚落生成可接订单
        OrderBook.generate_on_arrival(gameState, gameState.map.current_location)
        print("[Main] New game")
    end

    -- 3. 注册页面
    Router.init(gameState)
    Router.register("home",         ScreenHome)
    Router.register("orders",       ScreenPrepare)
    Router.register("summary",      ScreenSummary)
    Router.register("shop",         ScreenShop)
    Router.register("event",        ScreenEvent)
    Router.register("event_result", ScreenEventResult)
    Router.register("map",          ScreenMap)
    Router.register("route_plan",   ScreenRoutePlan)
    Router.register("cargo",        ScreenCargo)

    -- 4. 初始页面
    local phase = Flow.get_phase(gameState)
    if phase == Flow.Phase.ARRIVAL then
        handleTripFinish()
    else
        if phase ~= Flow.Phase.TRAVELLING then
            gameState.flow.phase = Flow.Phase.IDLE
        end
        Router.navigate("home")
    end

    -- 5. 主循环
    SubscribeToEvent("Update", "HandleUpdate")
    print("=== 末世行商 启动完成 ===")
end

function Stop()
    if gameState then
        SaveLocal.save(gameState)
        print("[Main] Saved on exit")
    end
    UI.Shutdown()
end

-- ============================================================
-- 行程完成处理
-- ============================================================
function handleTripFinish()
    local result = Flow.finish_trip(gameState)
    EventPool.tick_cooldowns(gameState)

    Router.navigate("summary", {
        result = result,
        delivered_orders = tripDeliveries,
    })
    tripDeliveries = {}
end

-- ============================================================
-- 到达节点处理（中间节点或终点）
-- ============================================================
function handleNodeArrival(arrivalInfo)
    local arrResult = Flow.handle_node_arrival(gameState, arrivalInfo)

    -- 记录交付的订单
    if arrResult.delivered and #arrResult.delivered > 0 then
        for _, o in ipairs(arrResult.delivered) do
            table.insert(tripDeliveries, o)
        end
        print("[Main] 自动交付 " .. #arrResult.delivered .. " 个订单于 "
            .. Graph.get_node_name(arrResult.node_id))
    end

    -- 如果是最终节点，进入结算
    if arrResult.is_final then
        handleTripFinish()
    end
    -- 中间节点不中断行驶，继续前进
end

-- ============================================================
-- 主循环
-- ============================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 1. 推进时间
    Ticker.advance(gameState, dt)

    -- 2. 行驶中逻辑
    if Flow.get_phase(gameState) == Flow.Phase.TRAVELLING then
        -- 2a. 检查到达节点
        local arrival = Flow.update_travel(gameState, dt)
        if arrival then
            print("[Main] Arrived at node: " .. arrival.arrived_node)
            handleNodeArrival(arrival)
        end

        -- 2b. 行程中事件调度（仅在首页显示时触发，避免打断其他页面）
        if Router.current() == "home" and not EventScheduler.has_pending(gameState) then
            local plan = gameState.flow.route_plan
            local progress = RoutePlanner.get_progress(plan)
            local seg = RoutePlanner.get_current_segment(plan)
            local context = nil
            if seg then
                local toNode = Graph.get_node(seg.to)
                context = {
                    edge_type = seg.edge_type,
                    node_type = toNode and toNode.type or nil,
                }
            end

            local evt = EventScheduler.update(gameState, dt, progress, context)
            if evt then
                print("[Main] Travel event triggered: " .. evt.id)
                Router.navigate("event", { event = evt })
            end
        end
    end

    -- 3. 更新当前页面
    Router.update(dt)

    -- 4. 自动保存
    saveTimer = saveTimer + dt
    if saveTimer >= SAVE_INTERVAL then
        saveTimer = 0
        SaveLocal.save(gameState)
    end
end

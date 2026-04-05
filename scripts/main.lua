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
local ScreenAmbush      = require("ui/screen_ambush")
local ScreenExplore     = require("ui/screen_explore")
local ScreenDebug       = require("ui/screen_debug")
local ScreenTruck       = require("ui/screen_truck")

-- 游戏状态
---@type table
local gameState = nil
local saveTimer = 0
local SAVE_INTERVAL = 30

-- 行程中累计交付记录（用于最终结算展示）
local tripDeliveries = {}

-- 调试面板：快速连点 3 次打开（右上角触屏 或 键盘 P）
local debugTapCount = 0
local debugTapTimer = 0
local DEBUG_TAP_WINDOW = 1.0       -- 1 秒内点 3 次
local DEBUG_TAP_ZONE_PX = 80       -- 右上角热区大小（物理像素）

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
        -- 委托货物追踪兼容（B2 方案新增）
        if not gameState.truck.committed then
            gameState.truck.committed = {}
        end
        if not gameState.stats.consecutive_expires then
            gameState.stats.consecutive_expires = 0
        end
        -- 聚落信誉兼容
        for sid, sett in pairs(gameState.settlements) do
            if not sett.reputation then sett.reputation = 100 end
        end
        -- 角色状态兼容
        for _, cid in ipairs({ "linli", "taoxia" }) do
            local char = gameState.character[cid]
            if char and not char.status then char.status = {} end
            if char and not char.relation then char.relation = 0 end
        end
        -- 货车模块兼容
        if not gameState.truck.modules then
            gameState.truck.modules = {
                engine = 1, cargo_bay = 0, radar = 0,
                cold_storage = 0, turret = 0,
            }
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
            -- 处理离线期间的到达事件（自动交付、发现节点等）
            if offResult.arrivals then
                for _, arrival in ipairs(offResult.arrivals) do
                    print("[Main] Offline arrival: " .. arrival.arrived_node)
                    local arrResult = Flow.handle_node_arrival(gameState, arrival)
                    if arrResult.delivered and #arrResult.delivered > 0 then
                        for _, o in ipairs(arrResult.delivered) do
                            table.insert(tripDeliveries, o)
                        end
                    end
                end
            end
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
    Router.register("ambush",       ScreenAmbush)
    Router.register("explore",      ScreenExplore)
    Router.register("debug",        ScreenDebug)
    Router.register("truck",        ScreenTruck)

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

    -- 6. 调试面板触发：监听触摸和鼠标点击事件
    SubscribeToEvent("TouchBegin", "HandleDebugTouch")
    SubscribeToEvent("MouseButtonDown", "HandleDebugClick")

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

    -- 0. 调试面板：计时器衰减
    if debugTapTimer > 0 then
        debugTapTimer = debugTapTimer - dt
        if debugTapTimer <= 0 then
            debugTapCount = 0
        end
    end

    -- 1. 推进时间
    Ticker.advance(gameState, dt)

    -- 2. 行驶中逻辑
    if Flow.get_phase(gameState) == Flow.Phase.TRAVELLING then
        -- 2z. 调试：直接到达（逐段触发完整到达逻辑）
        if gameState._debug_instant_arrive then
            gameState._debug_instant_arrive = nil
            gameState._debug_advance_secs = nil
            print("[Debug] Processing instant arrive...")
            while Flow.get_phase(gameState) == Flow.Phase.TRAVELLING do
                local plan = gameState.flow.route_plan
                if not plan or not plan.segments then break end
                if plan.segment_index == 0 then
                    plan.segment_index = 1
                    plan.segment_elapsed = 0
                end
                local seg = plan.segments[plan.segment_index]
                if not seg then break end
                local segRemain = seg.time_sec - plan.segment_elapsed
                local arrival = Flow.update_travel(gameState, segRemain)
                if arrival then
                    print("[Debug] Arrived at: " .. arrival.arrived_node)
                    handleNodeArrival(arrival)
                else
                    break
                end
            end
        end

        -- 2y. 调试：快进指定秒数（逐段推进，正确触发到达）
        if gameState._debug_advance_secs and gameState._debug_advance_secs > 0 then
            local remTime = gameState._debug_advance_secs
            gameState._debug_advance_secs = nil
            print("[Debug] Fast-forwarding " .. math.floor(remTime) .. "s...")
            while remTime > 0 and Flow.get_phase(gameState) == Flow.Phase.TRAVELLING do
                local plan = gameState.flow.route_plan
                if not plan or not plan.segments then break end
                if plan.segment_index == 0 then
                    plan.segment_index = 1
                    plan.segment_elapsed = 0
                end
                local seg = plan.segments[plan.segment_index]
                if not seg then break end
                local segRemain = seg.time_sec - plan.segment_elapsed
                if remTime >= segRemain then
                    local arrival = Flow.update_travel(gameState, segRemain)
                    remTime = remTime - segRemain
                    if arrival then
                        print("[Debug] Arrived at: " .. arrival.arrived_node)
                        handleNodeArrival(arrival)
                    else
                        break
                    end
                else
                    Flow.update_travel(gameState, remTime)
                    remTime = 0
                end
            end
        end

        -- 页面分类（挂机游戏：旅行在所有常规页面后台继续）
        local curPage = Router.current()
        -- 特殊流程页面：战斗/探索期间停车，事件期间行驶但延迟到达
        local truck_stopped = curPage == "ambush"
            or curPage == "explore"
            or gameState.flow.pending_combat
            or gameState.flow.pending_explore
        -- 事件流程中：行驶继续但到达延迟处理
        local in_event = curPage == "event"
            or curPage == "event_result"
        -- 常规页面（home/map/orders/cargo 等）：一切正常后台运行
        local on_regular_page = not truck_stopped and not in_event
            and curPage ~= "summary"

        -- 2a. 行驶推进 + 到达处理（所有非停车页面都推进）
        if not truck_stopped then
            local arrival = Flow.update_travel(gameState, dt)
            if arrival then
                if in_event then
                    -- 事件流程中到达：延迟处理，不打断玩家
                    gameState.flow._deferred_arrival = arrival
                    print("[Main] Arrival deferred (in event): " .. arrival.arrived_node)
                else
                    -- 常规页面（含 map/orders/cargo）：直接后台处理到达
                    print("[Main] Arrived at node: " .. arrival.arrived_node)
                    handleNodeArrival(arrival)
                end
            end
        end

        -- 2a2. 处理延迟到达（事件结束后回到任何常规页面即处理）
        if on_regular_page and gameState.flow._deferred_arrival then
            local arrival = gameState.flow._deferred_arrival
            gameState.flow._deferred_arrival = nil
            print("[Main] Processing deferred arrival: " .. arrival.arrived_node)
            handleNodeArrival(arrival)
        end

        -- 2b. 检查待处理战斗（仅在首页跳转，避免打断其他页面操作）
        if on_regular_page and curPage == "home" and gameState.flow.pending_combat then
            local combat_id = gameState.flow.pending_combat
            gameState.flow.pending_combat = nil
            print("[Main] Entering combat: " .. combat_id)
            Router.navigate("ambush", { enemy_id = combat_id })
        end

        -- 2b2. 检查待处理探索（仅在首页跳转）
        if on_regular_page and curPage == "home" and gameState.flow.pending_explore then
            local room_id = gameState.flow.pending_explore
            gameState.flow.pending_explore = nil
            print("[Main] Entering explore: " .. room_id)
            Router.navigate("explore", { room_id = room_id })
        end

        -- 2c. 行程中事件调度（仅在首页触发，避免打断 map/orders 等页面操作）
        local on_home = curPage == "home"
        if on_home and EventScheduler.has_pending(gameState) then
            EventScheduler.clear_pending(gameState)
        end
        if on_home then
            local plan = gameState.flow.route_plan
            local progress = RoutePlanner.get_progress(plan)
            local seg = RoutePlanner.get_current_segment(plan)
            local context = nil
            if seg then
                local toNode = Graph.get_node(seg.to)
                context = {
                    edge_type    = seg.edge_type,
                    node_type    = toNode and toNode.type or nil,
                    danger = seg.danger,
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

-- ============================================================
-- 调试面板：触屏 / 鼠标点击右上角 3 次打开
-- ============================================================

--- 统一处理调试面板触发
local function debugTapAt(x, y)
    local screenW = graphics:GetWidth()
    -- 只响应右上角区域
    if x < screenW - DEBUG_TAP_ZONE_PX or y > DEBUG_TAP_ZONE_PX then
        return
    end
    debugTapCount = debugTapCount + 1
    debugTapTimer = DEBUG_TAP_WINDOW
    print("[Debug] Tap #" .. debugTapCount .. " at (" .. x .. "," .. y .. ")")
    if debugTapCount >= 3 then
        debugTapCount = 0
        debugTapTimer = 0
        if Router.current() == "debug" then
            Router.navigate("home")
        else
            print("[Debug] Opening debug panel")
            Router.navigate("debug")
        end
    end
end

--- 触摸事件（移动端）
---@param eventType string
---@param eventData TouchBeginEventData
function HandleDebugTouch(eventType, eventData)
    local x = eventData:GetInt("X")
    local y = eventData:GetInt("Y")
    debugTapAt(x, y)
end

--- 鼠标点击事件（PC 端）
---@param eventType string
---@param eventData table
function HandleDebugClick(eventType, eventData)
    local button = eventData:GetInt("Button")
    if button ~= MOUSEB_LEFT then return end
    local mx = input:GetMousePosition().x
    local my = input:GetMousePosition().y
    debugTapAt(mx, my)
end

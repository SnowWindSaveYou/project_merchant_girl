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
local SketchBorder   = require("ui/sketch_border")
local EventPool      = require("events/event_pool")
local EventScheduler = require("events/event_scheduler")
local RoutePlanner   = require("map/route_planner")
local OrderBook      = require("economy/order_book")
local Graph          = require("map/world_graph")

local FloatingText      = require("ui/floating_text")

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
local ScreenCampfire    = require("ui/screen_campfire")
local ScreenNpc         = require("ui/screen_npc")
local ScreenQuestLog    = require("ui/screen_quest_log")
local ScreenArchives    = require("ui/screen_archives")
local ScreenFarm        = require("ui/screen_farm")
local ScreenIntel       = require("ui/screen_intel")
local ScreenBlackMarket = require("ui/screen_black_market")
local ScreenStroll      = require("ui/screen_stroll")
local ScreenLetter       = require("ui/screen_letter")
local ScreenMailbox      = require("ui/screen_mailbox")
local ScreenLetterPickup = require("ui/screen_letter_pickup")
local DialoguePool      = require("narrative/dialogue_pool")
local NpcDialoguePool   = require("narrative/npc_dialogue_pool")
local Flags             = require("core/flags")
local WanderingNpc      = require("narrative/wandering_npc")
local Farm              = require("settlement/farm")
local Intel             = require("settlement/intel")
local BlackMarket       = require("settlement/black_market")
local MainStory         = require("narrative/main_story")
local Tutorial          = require("narrative/tutorial")
local StoryDirector     = require("narrative/story_director")

-- 游戏状态
---@type table
local gameState = nil
local saveTimer = 0
local SAVE_INTERVAL = 30

-- 行程中累计交付记录（用于最终结算展示）
local tripDeliveries = {}

-- ============================================================
-- 到达拦截器（通用机制）
-- 注册函数签名: function(state, node_id) -> action|nil
-- action = { type = "dialogue", dialogue = DialogueData }
-- 先注册的优先级高；命中即停止后续检查
-- ============================================================
local arrivalInterceptors = {}

--- 注册一个到达拦截器
--- @param handler fun(state: table, node_id: string): table|nil
local function registerArrivalInterceptor(handler)
    table.insert(arrivalInterceptors, handler)
end

--- 遍历所有拦截器，返回第一个命中的 action 或 nil
local function checkArrivalIntercepts(state, node_id)
    for _, handler in ipairs(arrivalInterceptors) do
        local action = handler(state, node_id)
        if action then return action end
    end
    return nil
end

-- 注册：教程到达拦截
registerArrivalInterceptor(function(state, node_id)
    return Tutorial.on_arrival(state, node_id)
end)

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

    -- 1b. 初始化手绘边框 NanoVG overlay
    SketchBorder.init()
    SketchBorder.patchProgressBar()

    -- 1c. 初始化全局飘字系统
    FloatingText.init()
    local ItemUse = require("economy/item_use")
    ItemUse._on_item_change = function(goods_id, delta)
        FloatingText.notify_item(goods_id, delta)
    end

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
        -- 前哨站聚落兼容（Phase 11）
        local newSettlements = {
            greenhouse_farm = { goodwill = 5,  visited = false, reputation = 100 },
            dome_outpost    = { goodwill = 0,  visited = false, reputation = 100 },
            metro_camp      = { goodwill = 0,  visited = false, reputation = 100 },
            old_church      = { goodwill = 0,  visited = false, reputation = 100 },
        }
        for sid, defaults in pairs(newSettlements) do
            if not gameState.settlements[sid] then
                gameState.settlements[sid] = defaults
            end
        end
        -- 隐藏聚落兼容（地图扩展）
        if not gameState.settlements.underground_market then
            gameState.settlements.underground_market = { goodwill = 0, visited = false, reputation = 100 }
        end
        -- 叙事系统兼容
        if not gameState.narrative then
            gameState.narrative = {
                story_flags = {}, memories = {},
                campfire_cooldowns = {}, campfire_count = 0,
            }
        end
        if not gameState.narrative.campfire_cooldowns then
            gameState.narrative.campfire_cooldowns = {}
        end
        if not gameState.narrative.campfire_count then
            gameState.narrative.campfire_count = 0
        end
        if not gameState.narrative.npc_cooldowns then
            gameState.narrative.npc_cooldowns = {}
        end
        if not gameState.narrative.npc_visit_count then
            gameState.narrative.npc_visit_count = {}
        end
        -- 档案阅读记录兼容
        if not gameState.narrative.archives_read then
            gameState.narrative.archives_read = {}
        end
        -- 主线章节兼容 (Phase 4)
        if gameState.narrative.chapter == nil then
            gameState.narrative.chapter = 0
        end
        if not gameState.narrative.chapter_flags then
            gameState.narrative.chapter_flags = {}
        end
        -- 聚落子系统状态兼容（farm / intel / market）
        local settSubs = {
            greenhouse = { "farm",   { slots = {}, harvested = {} } },
            tower      = { "intel",  { route_data = 0, active_intel = {}, total_exchanged = 0 } },
            ruins_camp = { "market", { items = {}, last_refresh = 0, total_trades = 0, total_profit = 0 } },
        }
        for sid, def in pairs(settSubs) do
            local sett = gameState.settlements[sid]
            if sett and not sett[def[1]] then
                sett[def[1]] = def[2]
            end
        end
        -- 流浪 NPC 位置兼容
        WanderingNpc.ensure_init(gameState)
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
    Router.register("campfire",     ScreenCampfire)
    Router.register("npc",          ScreenNpc)
    Router.register("quest_log",    ScreenQuestLog)
    Router.register("archives",     ScreenArchives)
    Router.register("farm",         ScreenFarm)
    Router.register("intel",        ScreenIntel)
    Router.register("black_market", ScreenBlackMarket)
    Router.register("stroll",       ScreenStroll)
    Router.register("letter",         ScreenLetter)
    Router.register("mailbox",        ScreenMailbox)
    Router.register("letter_pickup",  ScreenLetterPickup)

    -- 4. 初始页面
    local phase = Flow.get_phase(gameState)
    if phase == Flow.Phase.ARRIVAL then
        handleTripFinish()
    else
        if phase ~= Flow.Phase.TRAVELLING then
            gameState.flow.phase = Flow.Phase.IDLE
        end
        -- 序章未完成时自动触发（新游戏或中途退出后重进）
        if not Flags.has(gameState, "sd_prologue_01_done") then
            local prologue = DialoguePool.get("SD_PROLOGUE_01")
            if prologue then
                Router.navigate("campfire", { dialogue = prologue, consumed = false })
            else
                Router.navigate("home")
            end
        else
            Router.navigate("home")
        end
    end

    -- 5. 主循环
    SubscribeToEvent("Update", "HandleUpdate")

    -- 6. 后台/息屏：监听焦点变化，失去焦点时保存，恢复时补偿离线时间
    SubscribeToEvent("InputFocus", "HandleInputFocus")

    -- 7. 调试面板触发：监听触摸和鼠标点击事件
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
-- 后台/息屏处理（挂机核心）
-- ============================================================

---@param eventType string
---@param eventData InputFocusEventData
function HandleInputFocus(eventType, eventData)
    local focus = eventData:GetBool("Focus")
    local minimized = eventData:GetBool("Minimized")

    if not focus or minimized then
        -- 失去焦点（息屏/切后台）：立即保存状态
        if gameState then
            SaveLocal.save(gameState)
            print("[Main] Saved on focus lost (minimized=" .. tostring(minimized) .. ")")
        end
    else
        -- 恢复焦点（亮屏/切回前台）：计算离线补偿
        if gameState then
            local offResult = Offline.apply(gameState, Ticker)
            if offResult then
                print("[Main] Resume: offline " .. offResult.elapsed_sec .. "s")
                -- 处理离线期间的到达事件
                if offResult.arrivals then
                    for _, arrival in ipairs(offResult.arrivals) do
                        print("[Main] Resume arrival: " .. arrival.arrived_node)
                        handleNodeArrival(arrival)
                    end
                end
                if offResult.arrived then
                    print("[Main] Arrived during background!")
                end
            end
            -- 更新 timestamp 为当前时间，避免下次重复补偿
            gameState.timestamp = os.time()
            saveTimer = 0 -- 重置自动保存计时器
        end
    end
end

-- ============================================================
-- 行程完成处理
-- ============================================================
function handleTripFinish()
    local result = Flow.finish_trip(gameState)
    EventPool.tick_cooldowns(gameState)
    DialoguePool.tick_cooldowns(gameState)
    NpcDialoguePool.tick_cooldowns(gameState)

    -- 聚落子系统行程钩子
    Farm.advance_trip(gameState)
    local plan = gameState.flow.route_plan
    local segCount = plan and plan.segments and #plan.segments or 1
    local hadShortcut = false
    if plan and plan.segments then
        for _, seg in ipairs(plan.segments) do
            if seg.edge_type == "shortcut" then hadShortcut = true; break end
        end
    end
    Intel.earn_route_data(gameState, segCount, hadShortcut)
    Intel.tick_intel(gameState)
    BlackMarket.refresh(gameState)

    -- 主线章节推进检查 (Phase 4)
    local advanced, newChapter = MainStory.check_advance(gameState)
    if advanced and newChapter then
        print("[Main] Chapter advanced to: " .. newChapter.name .. " - " .. newChapter.subtitle)
    end

    -- 叙事导演：行程结束后检查剧情事件入队
    StoryDirector.on_trip_finish(gameState)

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
    -- 到达剧情拦截（必须在 Flow.handle_node_arrival 之前检查）
    -- 命中时先播放到达叙事，对话结束后再处理订单交付 / 行程结算，
    -- 避免"还没到就已经交货结算"的时序错乱
    -- 注册新拦截器：见上方 registerArrivalInterceptor()
    local intercept = checkArrivalIntercepts(gameState, arrivalInfo.arrived_node)
    if intercept and intercept.type == "dialogue" and intercept.dialogue then
        print("[Main] Arrival intercept at " .. arrivalInfo.arrived_node
            .. " — deferring arrival processing until dialogue ends")
        -- 先更新当前位置，确保对话背景图能正确解析到目标聚落
        gameState.map.current_location = arrivalInfo.arrived_node
        -- 将原始到达信息存入延迟队列，对话结束回到常规页面后再处理
        gameState.flow._deferred_arrival = arrivalInfo
        Router.navigate("campfire", {
            dialogue = intercept.dialogue,
            consumed = false,
        })
        return
    end

    -- 无拦截：正常处理到达
    local arrResult = Flow.handle_node_arrival(gameState, arrivalInfo)

    -- 记录交付的订单
    if arrResult.delivered and #arrResult.delivered > 0 then
        for _, o in ipairs(arrResult.delivered) do
            table.insert(tripDeliveries, o)
        end
        print("[Main] 自动交付 " .. #arrResult.delivered .. " 个订单于 "
            .. Graph.get_node_name(arrResult.node_id))
    end

    -- 叙事导演：到达后检查是否有应自动触发的主线内容
    -- 仅在最终节点（已停稳）时检查，中间节点不停
    if arrResult.is_final then
        local directorAction = StoryDirector.on_node_arrival(gameState)
        if directorAction and directorAction.type == "story_dialogue" then
            print("[Main] StoryDirector: auto-triggering story dialogue: "
                .. (directorAction.dialogue and directorAction.dialogue.id or "?"))
            -- 标记延迟结算：订单已交付但行程尚未结算，对话结束后再执行 handleTripFinish
            gameState.flow._deferred_trip_finish = true
            Router.navigate("campfire", {
                dialogue = directorAction.dialogue,
                consumed = false,
            })
            return
        end
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

    -- 页面分类（需在行驶/非行驶分支之前声明，两个分支都用）
    local curPage = Router.current()
    local truck_stopped = curPage == "ambush"
        or curPage == "explore"
    local in_event = curPage == "event"
        or curPage == "event_result"
    local on_regular_page = not truck_stopped and not in_event
        and curPage ~= "summary"

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

        -- 2a2. 处理延迟到达（事件/对话结束后回到非对话常规页面即处理）
        -- 排除 campfire/npc：教程拦截将到达延迟到对话结束后，
        -- 若在对话页面就处理会因 flag 未设置导致无限循环
        if on_regular_page
            and curPage ~= "campfire" and curPage ~= "npc"
            and gameState.flow._deferred_arrival then
            local arrival = gameState.flow._deferred_arrival
            gameState.flow._deferred_arrival = nil
            print("[Main] Processing deferred arrival: " .. arrival.arrived_node)
            handleNodeArrival(arrival)
        end

        -- 2a3. 处理延迟行程结算（StoryDirector 到达触发对话后，对话结束再执行）
        if on_regular_page
            and curPage ~= "campfire" and curPage ~= "npc"
            and gameState.flow._deferred_trip_finish then
            gameState.flow._deferred_trip_finish = nil
            print("[Main] Processing deferred trip finish")
            handleTripFinish()
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

    -- 2d. 非行驶中：处理延迟行程结算 + 叙事导演检查
    elseif on_regular_page then
        -- 2d1. 延迟行程结算（StoryDirector 对话结束后）
        if curPage ~= "campfire" and curPage ~= "npc"
            and gameState.flow._deferred_trip_finish then
            gameState.flow._deferred_trip_finish = nil
            print("[Main] Processing deferred trip finish (non-travelling)")
            handleTripFinish()
        end
        -- 2d2. 叙事导演：home 页主线对话自动触发
        if curPage == "home" then
            local directorAction = StoryDirector.check_home_auto_trigger(gameState)
            if directorAction and directorAction.type == "story_dialogue" then
                print("[Main] StoryDirector: auto-triggering story dialogue on home: "
                    .. (directorAction.dialogue and directorAction.dialogue.id or "?"))
                Router.navigate("campfire", {
                    dialogue = directorAction.dialogue,
                    consumed = false,
                })
            end
        end
    end

    -- 3. 更新当前页面
    Router.update(dt)

    -- 3b. 更新全局飘字
    FloatingText.update(dt)

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

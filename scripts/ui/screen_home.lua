--- 首页 — 末世行商主界面
--- 据点模式：插画 + 信息卡 + 操作按钮
--- 行驶模式：进度条 + 订单摘要
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Goods        = require("economy/goods")
local CargoUtils   = require("economy/cargo_utils")
local Goodwill     = require("settlement/goodwill")
local Modules      = require("truck/modules")
local Campfire     = require("narrative/campfire")
local NpcManager          = require("narrative/npc_manager")
local SettlementEventPool = require("events/settlement_event_pool")
local WaypointEventPool   = require("events/waypoint_event_pool")
local WanderingNpc        = require("narrative/wandering_npc")
local QuestLog            = require("narrative/quest_log")
local Chatter             = require("travel/chatter")
local Radio               = require("travel/radio")
local Scenery             = require("travel/scenery")
local DrivingScene        = require("travel/chibi_scene")
local Environment         = require("travel/environment")
local RoadLoot            = require("travel/road_loot")
local Archives            = require("settlement/archives")
local Farm                = require("settlement/farm")
local Intel               = require("settlement/intel")
local BlackMarket         = require("settlement/black_market")
local Flags               = require("core/flags")
local UnlockStories       = require("narrative/unlock_stories")
local Stroll              = require("narrative/stroll")
local MainStory           = require("narrative/main_story")
local LetterSystem        = require("narrative/letter_system")
local Tutorial            = require("narrative/tutorial")
local SpeechBubble        = require("ui/speech_bubble")
local SketchBorder        = require("ui/sketch_border")

local M = {}
---@type table
local router = nil

-- 行驶中状态追踪（用于检测变化触发 UI 重建）
local _prevChatterId   = nil
local _prevSceneryId   = nil
local _prevSegmentIndex = nil

-- 地图节点 → 探索房间 ID（Phase 06 连接）
local NODE_EXPLORE_ROOM = {
    -- 资源节点
    old_warehouse   = "abandoned_warehouse",
    radar_hill      = "radar_station",
    irrigation_canal = "irrigation_tunnels",
    mushroom_cave   = "mushroom_grotto",
    solar_field     = "solar_panels",
    junkyard        = "junk_heap",
    printing_ruins  = "print_shop",
    scrap_yard      = "scrap_pit",
    old_logistics   = "logistics_depot",
    -- 危险节点（高危高回报）
    sewer_maze      = "sewer_depths",
    military_bunker = "bunker_interior",
    crater_rim      = "crater_salvage",
}

-- 据点主题色（插画背景渐变底色）
local SETTLEMENT_THEMES = {
    greenhouse      = { bg = { 38, 52, 38, 255 }, accent = { 108, 148,  96, 255 }, icon = "🌿" },
    tower           = { bg = { 32, 40, 54, 255 }, accent = { 112, 142, 168, 255 }, icon = "🗼" },
    ruins_camp      = { bg = { 48, 38, 30, 255 }, accent = { 168, 128,  82, 255 }, icon = "🏚" },
    bell_tower      = { bg = { 42, 36, 46, 255 }, accent = { 148, 128, 168, 255 }, icon = "🔔" },
    -- 前哨站
    greenhouse_farm = { bg = { 34, 48, 32, 255 }, accent = {  96, 138,  80, 255 }, icon = "🌱" },
    dome_outpost    = { bg = { 30, 36, 48, 255 }, accent = {  96, 126, 152, 255 }, icon = "📡" },
    metro_camp      = { bg = { 44, 36, 28, 255 }, accent = { 152, 112,  72, 255 }, icon = "🚇" },
    old_church      = { bg = { 38, 32, 42, 255 }, accent = { 132, 112, 148, 255 }, icon = "🕯" },
}
local DEFAULT_THEME = { bg = { 40, 38, 36, 255 }, accent = Theme.colors.accent, icon = "📍" }

-- ============================================================
-- 页面创建
-- ============================================================
function M.create(state, params, r)
    router = r

    local phase        = Flow.get_phase(state)
    local isTravelling = (phase == Flow.Phase.TRAVELLING)
    local location     = state.map.current_location
    local curNode      = Graph.get_node(location)

    -- late-init：兼容老存档（行驶中加载但 flow 里没有 chatter/radio）
    if isTravelling then
        if not state.flow.chatter then
            state.flow.chatter = Chatter.init()
        end
        -- radio 初始化已移至 shell.lua
        if not state.flow.scenery then
            state.flow.scenery = Scenery.init()
        end
        -- 同步追踪变量到当前真实状态，避免首帧误判为"变化"导致无限重建
        local initChat = Chatter.get_current(state)
        _prevChatterId   = initChat and initChat.id or nil
        local initScn = Scenery.get_current(state)
        _prevSceneryId   = initScn and initScn.id or nil
        -- late-init road_loot
        if not state.flow.road_loot then
            state.flow.road_loot = RoadLoot.init()
        end
        -- 同步 segment 索引 + 初始环境推送到 DrivingScene
        local plan = state.flow.route_plan
        _prevSegmentIndex = plan and plan.segment_index or nil
        if state.flow.environment then
            DrivingScene.setEnvironment(Environment.get_current(state.flow.environment))
        end
        -- 传入 state 供纸娃娃/装备渲染使用
        DrivingScene.setMode("driving")
        DrivingScene.setState(state)
        DrivingScene.setDriving(true)
        -- 设置掉落物点击回调
        DrivingScene.setDropCallback(function(drop)
            local feedback = RoadLoot.try_pickup(state, drop)
            if feedback then
                DrivingScene.addFeedback(feedback)
                if feedback.reward_type == "blocked" then
                    SoundMgr.play("error")
                else
                    SoundMgr.play("pickup")
                end
            end
        end)
        -- 初始同步掉落物到 DrivingScene
        DrivingScene.setDrops(RoadLoot.get_active_drops(state))
        -- 行驶中清除聚落中景覆盖
        DrivingScene.clearSettlement()
    else
        -- 停泊：设置 DrivingScene 为停泊模式 + 聚落专属中景
        DrivingScene.setMode("driving")
        DrivingScene.setState(state)
        DrivingScene.setDriving(false)
        local nodeId = curNode and curNode.id or ""
        DrivingScene.setSettlement(nodeId)
    end

    -- 纸娃娃点击回调（行驶/停泊都有效）
    DrivingScene.setChibiClickCallback(function(chibi, isNpc)
        SoundMgr.play("bubble_pop")
    end)

    if isTravelling then
        return createTravelView(state)
    else
        -- 教程阶段：确保教程订单已生成
        -- SPAWN：序章对话设置 tutorial_started 后回到 home，需要重新生成
        -- GREENHOUSE_FREE：到达温室社区时 generate_on_arrival 在对话前调用，
        --   此时 phase 还是 TRAVEL_TO_GREENHOUSE，教程订单2 不会生成。
        --   对话完成后 flag 切换为 GREENHOUSE_FREE，需重新生成以产出北穹塔台订单。
        local tutPhase = Tutorial.get_phase(state)
        if tutPhase == Tutorial.Phase.SPAWN
            or tutPhase == Tutorial.Phase.GREENHOUSE_FREE
            or tutPhase == Tutorial.Phase.EXPLORE then
            local loc = state.map.current_location
            -- 检查教程订单是否已在 order_book 中（已接则不需要重新生成）
            local needRegen = true
            local book = state.economy and state.economy.order_book or {}
            for _, o in ipairs(book) do
                if o.is_tutorial and (o.status == "accepted" or o.status == "loaded") then
                    needRegen = false
                    break
                end
            end
            if needRegen then
                if state.map.available_orders then
                    state.map.available_orders[loc] = nil
                end
                OrderBook.generate_on_arrival(state, loc)
            end
        end

        return createSettlementView(state, curNode)
    end
end

-- ============================================================
-- 每帧更新（行驶中动态刷新进度/时间）
-- ============================================================
function M.update(state, dt, r)
    if Flow.get_phase(state) ~= Flow.Phase.TRAVELLING then
        -- 停泊时也需要驱动纸娃娃动画和点击检测
        DrivingScene.update(dt)
        return
    end
    local plan = state.flow.route_plan
    if not plan then return end

    local root = UI.GetRoot()
    if not root then return end

    local progress = RoutePlanner.get_progress(plan)
    local seg = RoutePlanner.get_current_segment(plan)

    -- ── 检测 segment 切换 → 更新环境 + 掉落规划 ──
    local curSegIdx = plan.segment_index or 0
    if curSegIdx ~= _prevSegmentIndex then
        _prevSegmentIndex = curSegIdx
        -- segment 切换：推演新环境
        if state.flow.environment and seg then
            Environment.on_segment_enter(state.flow.environment, seg)
            DrivingScene.setEnvironment(Environment.get_current(state.flow.environment))
        end
        -- segment 切换：规划新掉落物
        if seg then
            RoadLoot.on_segment_enter(state, seg)
        end
    end

    -- ── 驱动 Chatter / Scenery / RoadLoot ──
    -- （Radio.update 已移至 shell.lua 全局调用）
    DrivingScene.update(dt)
    RoadLoot.update(state, dt)
    DrivingScene.setDrops(RoadLoot.get_active_drops(state))

    -- ── 教程：路面拾取提示（首次出现掉落物时触发一次）──
    if not Flags.has(state, "tutorial_loot_hint_shown") then
        local tutPhase = Tutorial.get_phase(state)
        if tutPhase == Tutorial.Phase.TRAVEL_TO_GREENHOUSE
            or tutPhase == Tutorial.Phase.EXPLORE then
            local drops = RoadLoot.get_active_drops(state)
            if drops and #drops > 0 then
                Flags.set(state, "tutorial_loot_hint_shown")
                -- 延迟 1 秒后显示提示，避免和其他 UI 冲突
                local hintTimer = 1.0
                local hintShown = false
                local origUpdate = M._lootHintUpdate
                M._lootHintUpdate = function(ldt)
                    if hintShown then return end
                    hintTimer = hintTimer - ldt
                    if hintTimer <= 0 then
                        hintShown = true
                        M._lootHintUpdate = nil
                        local uiRoot = UI.GetRoot()
                        if uiRoot then
                            SpeechBubble.show(uiRoot, {
                                portrait = Tutorial.AVATAR_LINLI,
                                speaker  = "林砾",
                                text     = "路上有些散落的物资，点一下就能捡起来！",
                                autoHide = 4,
                            })
                        end
                    end
                end
            end
        end
    end
    -- 驱动拾取提示延迟计时
    if M._lootHintUpdate then
        M._lootHintUpdate(dt)
    end

    Chatter.update(state, dt, progress, seg)
    local chatterActive = Chatter.get_current(state) ~= nil
    Scenery.update(state, dt, progress, seg, chatterActive)

    -- ── 检测 Chatter / Scenery 状态变化 → 重建 UI ──
    -- （收音机状态变化已由 shell.lua 检测并触发顶栏重建）
    local curChat = Chatter.get_current(state)
    local chatId  = curChat and curChat.id or nil
    local curScn = Scenery.get_current(state)
    local scnId  = curScn and curScn.id or nil

    local needRebuild = false
    if chatId ~= _prevChatterId then needRebuild = true end
    if scnId ~= _prevSceneryId then needRebuild = true end

    _prevChatterId   = chatId
    _prevSceneryId   = scnId

    if needRebuild then
        r.navigate("home")
        return
    end

    -- ── 常规 UI 刷新（进度条 / 时间 / 路段） ──
    local bar = root:FindById("travelProgress")
    if bar then bar:SetValue(progress) end

    local pct = root:FindById("travelPct")
    if pct then pct:SetText(math.floor(progress * 100) .. "%") end

    -- 剩余时间
    local remaining = 0
    if seg then
        remaining = math.max(0, seg.time_sec - (plan.segment_elapsed or 0))
        for i = plan.segment_index + 1, #plan.segments do
            remaining = remaining + plan.segments[i].time_sec
        end
    end
    local timeLabel = root:FindById("travelTime")
    if timeLabel then
        timeLabel:SetText(string.format(
            "%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60)))
    end

    -- 更新当前路段描述
    local locLabel = root:FindById("travelLocation")
    if locLabel and seg then
        local EDGE_TYPE_LABEL = { main_road = "公路", path = "小径", shortcut = "捷径" }
        local segType = EDGE_TYPE_LABEL[seg.edge_type] or ""
        local desc = segType ~= ""
            and (seg.from_name .. " → " .. seg.to_name .. "（" .. segType .. "）")
            or  (seg.from_name .. " → " .. seg.to_name)
        locLabel:SetText(desc)
    end
end

-- ============================================================
-- 据点视图：上半插画 + 下半信息卡 & 按钮
-- ============================================================
-- 成长目标弹窗状态
local _showProgressPopup = false

-- ── 短暂休整：气泡对话变体 ──────────────────────────────────
local _transitRestDialogues = {
    function(repair)
        local rl = repair > 0
            and string.format("……补了%d点耐久，还行。", repair)
            or  "……车况还行，不用大修。"
        return {
            { speaker = "陶夏", portrait = Theme.avatars.taoxia, text = "歇会儿吧，正好把罐头热一热。" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = "……我先看看车。" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = rl },
            { speaker = "陶夏", portrait = Theme.avatars.taoxia, text = "吃饱喝足，继续赶路！" },
        }
    end,
    function(repair)
        local rl = repair > 0
            and string.format("……修复了%d点，暂时没问题。", repair)
            or  "……底盘没什么问题，不用修。"
        return {
            { speaker = "陶夏", portrait = Theme.avatars.taoxia, text = "肚子饿了……开个罐头？" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = "……水也喝一口。我去检查下底盘。" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = rl },
            { speaker = "陶夏", portrait = Theme.avatars.taoxia, text = "林砾你真厉害，每次都修得好好的。" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = "……正常维护而已。" },
        }
    end,
    function(repair)
        local rl = repair > 0
            and string.format("……好了，耐久恢复了%d点。", repair)
            or  "……检查了一圈，暂时不用修。"
        return {
            { speaker = "陶夏", portrait = Theme.avatars.taoxia, text = "终于能喘口气了，来吃东西！" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = "……嗯，趁这会儿我把松动的地方紧一下。" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = rl },
            { speaker = "陶夏", portrait = Theme.avatars.taoxia, text = "效率真高，那我们继续？" },
            { speaker = "林砾", portrait = Theme.avatars.linli,  text = "……走吧。" },
        }
    end,
}

local function showTransitRestBubbles(steps, index)
    index = index or 1
    if index > #steps then
        router.navigate("home")
        return
    end
    local uiRoot = UI.GetRoot()
    if not uiRoot then
        router.navigate("home")
        return
    end
    local step = steps[index]
    SpeechBubble.show(uiRoot, {
        portrait  = step.portrait,
        speaker   = step.speaker,
        text      = step.text,
        autoHide  = 0,
        onDismiss = function()
            showTransitRestBubbles(steps, index + 1)
        end,
    })
end

function createSettlementView(state, curNode)
    local nodeId = curNode and curNode.id or ""
    local theme  = SETTLEMENT_THEMES[nodeId] or DEFAULT_THEME
    local activeOrders = OrderBook.get_active(state)
    local isSettlement = curNode and curNode.type == "settlement"

    -- CG 背景图（从节点 bg 字段获取）
    local bgImage = curNode and curNode.bg or nil

    -- ── 下半部：操作按钮列表 ──
    local lowerChildren = {}
    local tutPhase = Tutorial.get_phase(state)

    -- ── 教程 SPAWN 阶段：锁定操作，只允许接取委托 ──
    if tutPhase == Tutorial.Phase.SPAWN then
        table.insert(lowerChildren, F.actionBtn {
            text = "📋 接取委托",
            variant = "primary",
            height = 48,
            fontSize = Theme.sizes.font_normal,
            highlight = true,
            onClick = function(self)
                Flow.enter_prepare(state)
                router.navigate("orders")
            end,
        })
        -- 跳过后续所有按钮，直接进入下方 UI 组装

    elseif tutPhase == Tutorial.Phase.GREENHOUSE_FREE then
        -- GREENHOUSE_FREE = 到达温室但未接北穹订单
        -- 允许：NPC 对话 + 接单（高亮）+ 篝火；阻止：出发

        -- NPC 拜访
        local settlementNpcs = NpcManager.get_npcs_for_settlement(nodeId)
        for _, npc in ipairs(settlementNpcs) do
            local canVisit, visitReason = NpcManager.can_visit(state, npc.id)
            table.insert(lowerChildren, F.actionBtn {
                text = canVisit
                    and (npc.icon .. " 拜访 " .. npc.name)
                    or  (npc.icon .. " " .. npc.name .. "（" .. (visitReason or "不可用") .. "）"),
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not canVisit,
                onClick = function(self)
                    if not canVisit then return end
                    local dialogue = NpcManager.start_visit(state, npc.id)
                    if dialogue then
                        router.navigate("npc", { npc_id = npc.id, dialogue = dialogue })
                    end
                end,
            })
        end

        -- 接取委托（高亮引导）
        table.insert(lowerChildren, F.actionBtn {
            text = "📋 接取委托",
            variant = "primary",
            height = 48,
            fontSize = Theme.sizes.font_normal,
            highlight = true,
            onClick = function(self)
                Flow.enter_prepare(state)
                router.navigate("orders")
            end,
        })
        -- 篝火仍可用
        local canCamp, campReason = Campfire.can_start(state)
        local hasStoryTopic = canCamp and Campfire.has_story_topic(state)
        if canCamp then
            local campLabel = hasStoryTopic
                and "🔥 篝火休憩 · 有话题要谈"
                or  "🔥 篝火休憩"
            table.insert(lowerChildren, F.actionBtn {
                text = campLabel,
                variant = hasStoryTopic and "primary" or "secondary",
                fontSize = Theme.sizes.font_normal,
                highlight = hasStoryTopic or nil,
                onClick = function(self)
                    local dialogue, consumed = Campfire.start(state)
                    if dialogue then
                        router.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                    end
                end,
            })
        end
        -- 不显示出发按钮，阻止跑路

    else -- 正常流程

    -- 积压警告（保留，重要信息）
    local backlogInfo = OrderBook.get_backlog_info(state)
    if backlogInfo.level ~= "normal" or backlogInfo.consecutive_expires >= 2 then
        table.insert(lowerChildren, createBacklogWarning(backlogInfo))
    end

    -- ── 操作按钮区 ──
    if isSettlement then
        -- 聚落事件（到达时触发的本地事件）
        local pendingEvt = state.flow and state.flow.pending_settlement_event or nil
        if pendingEvt then
            table.insert(lowerChildren, F.actionBtn {
                text = "⚡ " .. (pendingEvt.title or "聚落事件"),
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                sound = "event",
                onClick = function(self)
                    local evt = state.flow.pending_settlement_event
                    state.flow.pending_settlement_event = nil
                    SettlementEventPool.set_cooldown(state, evt.id)
                    router.navigate("event", {
                        event = evt,
                        source = "settlement",
                    })
                end,
            })
        end

        -- NPC 拜访（支持同一聚落多个驻扎 NPC）
        local settlementNpcs = NpcManager.get_npcs_for_settlement(nodeId)
        for _, npc in ipairs(settlementNpcs) do
            local canVisit, visitReason = NpcManager.can_visit(state, npc.id)
            table.insert(lowerChildren, F.actionBtn {
                text = canVisit
                    and (npc.icon .. " 拜访 " .. npc.name)
                    or  (npc.icon .. " " .. npc.name .. "（" .. (visitReason or "不可用") .. "）"),
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not canVisit,
                onClick = function(self)
                    if not canVisit then return end
                    local dialogue = NpcManager.start_visit(state, npc.id)
                    if dialogue then
                        router.navigate("npc", { npc_id = npc.id, dialogue = dialogue })
                    end
                end,
            })
        end

        -- 流浪 NPC（聚落内遇见）
        local wanderersHere = WanderingNpc.get_wanderers_at(state, nodeId)
        for _, w in ipairs(wanderersHere) do
            local wid = w.id
            local wnpc = NpcManager.get_npc(wid)
            if wnpc then
                local wCanVisit, wReason = NpcManager.can_visit(state, wid)
                table.insert(lowerChildren, F.actionBtn {
                    text = wCanVisit
                        and (wnpc.icon .. " 遇见 " .. wnpc.name .. "（" .. wnpc.title .. "）")
                        or  (wnpc.icon .. " " .. wnpc.name .. "（" .. (wReason or "不可用") .. "）"),
                    variant = "secondary",
                    fontSize = Theme.sizes.font_normal,
                    disabled = not wCanVisit,
                    onClick = function(self)
                        if not wCanVisit then return end
                        local dialogue = NpcManager.start_visit(state, wid)
                        if dialogue then
                            router.navigate("npc", { npc_id = wid, dialogue = dialogue })
                        end
                    end,
                })
            end
        end

        -- 信件领取（雪冬送信）
        if LetterSystem.has_pending(state) then
            local pendingCount = LetterSystem.pending_count(state)
            table.insert(lowerChildren, F.actionBtn {
                text = "📨 雪冬送来了 " .. pendingCount .. " 封信",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                highlight = true,
                onClick = function(self)
                    local letters = LetterSystem.collect_all(state)
                    if letters and #letters > 0 then
                        router.navigate("letter", {
                            letters = letters,
                            state = state,
                            onFinish = function()
                                router.navigate("home")
                            end,
                        })
                    end
                end,
            })
        end

        -- 委托
        table.insert(lowerChildren, F.actionBtn {
            text = "📋 接取委托",
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                Flow.enter_prepare(state)
                router.navigate("orders")
            end,
        })

        -- 交易所
        table.insert(lowerChildren, F.actionBtn {
            text = "🏪 交易所",
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                router.navigate("shop")
            end,
        })

        -- ── 聚落专属功能按钮 ──
        local settGw = state.settlements[nodeId]
            and state.settlements[nodeId].goodwill or 0

        -- 档案阅览 (bell_tower)
        if nodeId == "bell_tower" then
            local archUnlocked = Goodwill.is_unlocked(settGw, "archives")
            local unreadCount = archUnlocked and Archives.get_unread_count(state) or 0
            local archLabel = archUnlocked
                and ("📖 档案阅览" .. (unreadCount > 0 and (" (" .. unreadCount .. " 未读)") or ""))
                or  "📖 档案阅览（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                text = archLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not archUnlocked,
                onClick = function(self)
                    if not archUnlocked then return end
                    if not Flags.has(state, "unlock_seen_archives") then
                        local d = UnlockStories.get("archives")
                        router.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "archives" })
                    else
                        router.navigate("archives")
                    end
                end,
            })
        end

        -- 培育农场 (greenhouse)
        if nodeId == "greenhouse" then
            local farmUnlocked = Goodwill.is_unlocked(settGw, "farm")
            local farmSlots = Farm.get_slots(state)
            local busyCount = 0
            for _, slot in ipairs(farmSlots) do
                if slot.crop_id then busyCount = busyCount + 1 end
            end
            local farmLabel = farmUnlocked
                and ("🌱 培育农场" .. (busyCount > 0 and (" (" .. busyCount .. " 栽种中)") or ""))
                or  "🌱 培育农场（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                text = farmLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not farmUnlocked,
                onClick = function(self)
                    if not farmUnlocked then return end
                    if not Flags.has(state, "unlock_seen_farm") then
                        local d = UnlockStories.get("farm")
                        router.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "farm" })
                    else
                        router.navigate("farm")
                    end
                end,
            })
        end

        -- 情报站 (tower)
        if nodeId == "tower" then
            local intelUnlocked = Goodwill.is_unlocked(settGw, "intel")
            local routeData = 0
            if intelUnlocked then
                routeData = Intel.get_route_data(state)
            end
            local intelLabel = intelUnlocked
                and ("📡 情报站" .. (routeData > 0 and (" (数据点: " .. routeData .. ")") or ""))
                or  "📡 情报站（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                text = intelLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not intelUnlocked,
                onClick = function(self)
                    if not intelUnlocked then return end
                    if not Flags.has(state, "unlock_seen_intel") then
                        local d = UnlockStories.get("intel")
                        router.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "intel" })
                    else
                        router.navigate("intel")
                    end
                end,
            })
        end

        -- 黑市 (ruins_camp)
        if nodeId == "ruins_camp" then
            local marketUnlocked = Goodwill.is_unlocked(settGw, "black_market")
            local itemCount = 0
            if marketUnlocked then
                local items = BlackMarket.get_items(state)
                itemCount = #items
            end
            local marketLabel = marketUnlocked
                and ("🏚 黑市" .. (itemCount > 0 and (" (" .. itemCount .. " 件商品)") or ""))
                or  "🏚 黑市（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                text = marketLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not marketUnlocked,
                onClick = function(self)
                    if not marketUnlocked then return end
                    if not Flags.has(state, "unlock_seen_black_market") then
                        local d = UnlockStories.get("black_market")
                        router.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "black_market" })
                    else
                        router.navigate("black_market")
                    end
                end,
            })
        end

        -- 闲逛
        local canStroll, strollReason = Stroll.can_start(state)
        local strollLabel
        if canStroll then
            strollLabel = "🚶 四处逛逛（消耗 1 饮用水）"
        else
            strollLabel = "🚶 四处逛逛（" .. (strollReason or "不可用") .. "）"
        end
        table.insert(lowerChildren, F.actionBtn {
            text = strollLabel,
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            disabled = not canStroll,
            onClick = function(self)
                if not canStroll then return end
                local scenes, consumed = Stroll.start(state)
                if scenes and #scenes > 0 then
                    router.navigate("stroll", { scenes = scenes, consumed = consumed })
                end
            end,
        })

        -- 信箱（已读信件回顾）
        if LetterSystem.read_count(state) > 0 then
            table.insert(lowerChildren, F.actionBtn {
                text = "📬 信箱（" .. LetterSystem.read_count(state) .. " 封）",
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    router.navigate("mailbox")
                end,
            })
        end

        -- 篝火（有主线话题且可用时高亮）
        local canCamp, campReason, isCampFree = Campfire.can_start(state)
        local hasStoryTopic = canCamp and Campfire.has_story_topic(state)
        local isFirstStoryVisit = curNode and curNode.type == "story"
            and not (state._visited_story_nodes and state._visited_story_nodes[nodeId])
        local campLabel
        if canCamp then
            if hasStoryTopic then
                campLabel = "🔥 篝火休憩 · 有话题要谈"
            elseif isCampFree then
                campLabel = "🔥 篝火休憩"
            else
                -- 显示将消耗的物品
                local cargo = state.truck.cargo or {}
                local costName = (cargo.food_can or 0) >= 1 and "罐头食品" or "燃料芯"
                campLabel = "🔥 篝火休憩（消耗 1 " .. costName .. "）"
            end
        else
            campLabel = "🔥 篝火（" .. (campReason or "不可用") .. "）"
        end
        local campHighlight = hasStoryTopic or isFirstStoryVisit
        table.insert(lowerChildren, F.actionBtn {
            text = campLabel,
            variant = campHighlight and "primary" or "secondary",
            fontSize = Theme.sizes.font_normal,
            disabled = not canCamp,
            highlight = campHighlight or nil,
            onClick = function(self)
                if not canCamp then return end
                -- 标记故事节点已访问
                if isFirstStoryVisit then
                    if not state._visited_story_nodes then state._visited_story_nodes = {} end
                    state._visited_story_nodes[nodeId] = true
                end
                local dialogue, consumed = Campfire.start(state)
                if dialogue then
                    router.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                end
            end,
        })

        -- 出发（仅有活跃订单时）
        if #activeOrders > 0 then
            table.insert(lowerChildren, F.actionBtn {
                text = "🚚 出发",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    Flow.enter_map(state)
                    router.navigate("map", { mode = "route_plan" })
                end,
            })
        end

    else
        -- 非聚落节点：流浪 NPC 遇见
        local wanderersHere = WanderingNpc.get_wanderers_at(state, nodeId)
        for _, w in ipairs(wanderersHere) do
            local wid = w.id
            local wnpc = NpcManager.get_npc(wid)
            if wnpc then
                local wCanVisit, wReason = NpcManager.can_visit(state, wid)
                table.insert(lowerChildren, F.actionBtn {
                    text = wCanVisit
                        and (wnpc.icon .. " 遇见 " .. wnpc.name .. "（" .. wnpc.title .. "）")
                        or  (wnpc.icon .. " " .. wnpc.name .. "（" .. (wReason or "不可用") .. "）"),
                    variant = "secondary",
                    fontSize = Theme.sizes.font_normal,
                    disabled = not wCanVisit,
                    onClick = function(self)
                        if not wCanVisit then return end
                        local dialogue = NpcManager.start_visit(state, wid)
                        if dialogue then
                            router.navigate("npc", { npc_id = wid, dialogue = dialogue })
                        end
                    end,
                })
            end
        end

        -- 路点事件（到达非聚落节点时触发的随机事件）
        local pendingWP = state.flow and state.flow.pending_waypoint_event or nil
        if pendingWP then
            table.insert(lowerChildren, F.actionBtn {
                text = "⚡ " .. (pendingWP.title or "路点事件"),
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                sound = "event",
                onClick = function(self)
                    local evt = state.flow.pending_waypoint_event
                    state.flow.pending_waypoint_event = nil
                    WaypointEventPool.set_cooldown(state, evt.id)
                    router.navigate("event", {
                        event = evt,
                        source = "waypoint",
                    })
                end,
            })
        end

        -- 非聚落节点：出发按钮（如有订单）
        if #activeOrders > 0 then
            table.insert(lowerChildren, F.actionBtn {
                text = "🚚 出发",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    Flow.enter_map(state)
                    router.navigate("map", { mode = "route_plan" })
                end,
            })
        end

        -- 中转站快速休整（transit 节点专属）
        if curNode and curNode.type == "transit" then
            local restUsed = state._visit_used and state._visit_used.transit_rest
            local hasFood  = (state.truck.cargo["food_can"] or 0) >= 1
            local hasWater = (state.truck.cargo["water"] or 0) >= 1
            local canRest  = not restUsed and hasFood and hasWater
            local restReason = restUsed and "已休整过"
                or (not hasFood and "缺少食物")
                or (not hasWater and "缺少饮水")
                or nil
            table.insert(lowerChildren, F.actionBtn {
                text = canRest and "⛺ 短暂休整"
                    or ("⛺ 休整（" .. (restReason or "不可用") .. "）"),
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not canRest,
                onClick = function(self)
                    if not canRest then return end
                    local ItemUse = require("economy/item_use")
                    ItemUse.consume(state, "food_can", 1)
                    ItemUse.consume(state, "water", 1)
                    local repair = math.min(5, state.truck.durability_max - state.truck.durability)
                    state.truck.durability = state.truck.durability + repair
                    if not state._visit_used then state._visit_used = {} end
                    state._visit_used.transit_rest = true
                    -- 随机选一组对话，用气泡链式播放
                    local variant = _transitRestDialogues[math.random(#_transitRestDialogues)]
                    local steps = variant(repair)
                    -- 末尾追加数值汇总气泡
                    table.insert(steps, {
                        speaker = "林砾", portrait = Theme.avatars.linli,
                        text = string.format(
                            "罐头 -1　饮水 -1\n耐久 %d → %d（+%d）",
                            state.truck.durability - repair,
                            state.truck.durability, repair),
                    })
                    showTransitRestBubbles(steps, 1)
                end,
            })
        end

        -- 篝火（非聚落节点，有主线话题且可用时高亮）
        local canCamp, campReason, isCampFree = Campfire.can_start(state)
        local hasStoryTopic = canCamp and Campfire.has_story_topic(state)
        -- 故事节点首次到达时，额外提示有故事可发现
        local isFirstStoryVisit = curNode and curNode.type == "story"
            and not (state._visited_story_nodes and state._visited_story_nodes[nodeId])
        local campLabel
        if canCamp then
            if isFirstStoryVisit then
                campLabel = "🔥 篝火休憩 · 此地似有故事"
            elseif hasStoryTopic then
                campLabel = "🔥 篝火休憩 · 有话题要谈"
            else
                campLabel = "🔥 篝火休憩"
            end
        else
            campLabel = "🔥 篝火（" .. (campReason or "不可用") .. "）"
        end
        table.insert(lowerChildren, F.actionBtn {
            text = campLabel,
            variant = hasStoryTopic and "primary" or "secondary",
            fontSize = Theme.sizes.font_normal,
            disabled = not canCamp,
            highlight = hasStoryTopic or nil,
            onClick = function(self)
                if not canCamp then return end
                local dialogue, consumed = Campfire.start(state)
                if dialogue then
                    router.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                end
            end,
        })

        -- 资源点特殊行动：搜刮此地
        if NODE_EXPLORE_ROOM[nodeId] then
            table.insert(lowerChildren, F.actionBtn {
                text = "🔍 搜刮此地",
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    router.navigate("explore", { room_id = NODE_EXPLORE_ROOM[nodeId] })
                end,
            })
        end
    end

    end -- 教程 SPAWN 锁定分支结束

    -- 探索区域已迁移到地图页面（screen_map）

    local lowerPanel = F.card {
        id = "settlementActions",
        width = "100%",
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        enterAnim = true, enterDelay = 0.05,
        imageTint = Theme.colors.home_lower_tint,
        children = lowerChildren,
    }

    -- ── 组装：全屏背景 + 内容叠层 ──
    local rootChildren = {}

    -- 层 1：CG 背景（全屏绝对定位）
    if bgImage then
        table.insert(rootChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundImage = bgImage,
            backgroundFit = "cover",
        })
        -- 底部渐变遮罩（让下方按钮区可读）
        table.insert(rootChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundColor = { 0, 0, 0, 0 },
            backgroundGradient = {
                direction = "to-bottom",
                colors = {
                    { 0, 0, 0, 0 },                    -- 顶部完全透明
                    { 0, 0, 0, 0 },                    -- 中上段透明
                    Theme.colors.home_gradient_mid,     -- 中段微渐变
                    Theme.colors.home_gradient_bot,     -- 底部较淡
                },
            },
        })
    end

    -- 层 2：顶部聚落信息卡（半透明背景框 + 名称 + 描述）
    local nodeName = curNode and curNode.name or "未知区域"
    local nodeDesc = curNode and curNode.desc or ""
    table.insert(rootChildren, UI.Panel {
        width = "100%",
        paddingTop = 8, paddingLeft = 12, paddingRight = 12, paddingBottom = 4,
        children = {
            (function()
                local infoChildren = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Panel {
                                flexDirection = "row", alignItems = "center", gap = 6,
                                children = {
                                    UI.Label {
                                        text = theme.icon,
                                        fontSize = 20,
                                    },
                                    UI.Label {
                                        text = nodeName,
                                        fontSize = Theme.sizes.font_large,
                                        fontColor = Theme.colors.home_title,
                                    },
                                },
                            },
                            UI.Label {
                                text = isSettlement and "聚落" or (curNode and curNode.type or ""),
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.home_label_dim,
                            },
                        },
                    },
                }
                if nodeDesc ~= "" then
                    table.insert(infoChildren, UI.Label {
                        text = nodeDesc,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.home_desc,
                    })
                end
                local infoPanel = UI.Panel {
                    width = "100%",
                    padding = 10,
                    backgroundColor = Theme.colors.home_overlay,
                    borderRadius = Theme.sizes.radius,
                    gap = 4,
                    children = infoChildren,
                }
                SketchBorder.register(infoPanel, "card")
                return infoPanel
            end)(),
        },
    })

    -- 层 3：占位弹性区域（停泊首页不显示驾驶场景，仅展示 CG 背景）
    table.insert(rootChildren, UI.Panel {
        flexGrow = 1, flexBasis = 0,
    })

    -- 层 4：悬浮按钮行（成长目标 + 活跃订单）
    -- 教程 SPAWN 阶段隐藏悬浮按钮，减少干扰
    local floatingButtons = {}
    if tutPhase == Tutorial.Phase.SPAWN then
        -- 不添加任何悬浮按钮
    else
    -- 成长目标按钮
    table.insert(floatingButtons, F.actionBtn {
        text = "📊 成长目标",
        variant = "secondary",
        width = "auto",
        height = 32,
        fontSize = Theme.sizes.font_small,
        backgroundColor = Theme.colors.home_float_btn_bg,
        borderColor = theme.accent,
        borderWidth = 1,
        borderRadius = Theme.sizes.radius,
        onClick = function(self)
            _showProgressPopup = not _showProgressPopup
            router.navigate("home")
        end,
    })
    -- 活跃订单按钮
    if #activeOrders > 0 then
        table.insert(floatingButtons, F.actionBtn {
            text = "📋 订单 " .. #activeOrders,
            variant = "secondary",
            width = "auto",
            height = 32,
            fontSize = Theme.sizes.font_small,
            backgroundColor = Theme.colors.home_float_btn_bg,
            borderColor = Theme.colors.accent,
            borderWidth = 1,
            borderRadius = Theme.sizes.radius,
            onClick = function(self)
                Flow.enter_prepare(state)
                router.navigate("orders")
            end,
        })
    end
    end -- 教程 SPAWN 悬浮按钮分支结束
    table.insert(rootChildren, UI.Panel {
        width = "100%",
        paddingLeft = 12, paddingRight = 12, paddingBottom = 4,
        flexDirection = "row", gap = 8,
        justifyContent = "flex-end",
        children = floatingButtons,
    })

    -- 层 5：按钮列表区域
    table.insert(rootChildren, lowerPanel)

    -- 层 6：成长目标弹窗（全屏遮罩 + 卡片）
    if _showProgressPopup then
        table.insert(rootChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundColor = Theme.colors.home_popup_overlay,
            justifyContent = "center", alignItems = "center",
            padding = 20,
            onClick = function(self)
                _showProgressPopup = false
                router.navigate("home")
            end,
            children = {
                UI.Panel {
                    id = "homeProgressScroll",
                    width = "100%", maxHeight = "80%",
                    backgroundColor = Theme.colors.bg_primary,
                    borderRadius = Theme.sizes.radius,
                    borderWidth = 1, borderColor = Theme.colors.border,
                    padding = 4,
                    overflow = "scroll",
                    onClick = function(self) end,  -- 阻止穿透关闭
                    children = {
                        createProgressCard(state),
                        F.actionBtn {
                            text = "关闭",
                            variant = "secondary",
                            height = 40,
                            marginTop = 8,
                            fontSize = Theme.sizes.font_normal,
                            onClick = function(self)
                                _showProgressPopup = false
                                router.navigate("home")
                            end,
                        },
                    },
                },
            },
        })
    end

    -- 层 7：教程引导气泡（绝对定位浮层）
    -- [Layout] 气泡位置和显示条件可能需要随 UI 重构调整
    local bubbleCfg = Tutorial.get_bubble_config(state, "home")
    if bubbleCfg then
        table.insert(rootChildren, SpeechBubble.createWidget(bubbleCfg))
    end

    return UI.Panel {
        id = "homeScreen",
        width = "100%", height = "100%",
        backgroundColor = bgImage and Theme.colors.home_root_fallback or Theme.colors.bg_primary,
        children = rootChildren,
    }
end

-- ============================================================
-- 行驶视图：进度条 + 目的地 + 订单摘要
-- ============================================================
function createTravelView(state)
    local plan       = state.flow.route_plan or {}
    local progress   = RoutePlanner.get_progress(plan)
    local seg        = RoutePlanner.get_current_segment(plan)
    local destName   = seg and seg.to_name or "?"
    local orderCnt   = OrderBook.active_count(state)
    local activeOrders = OrderBook.get_active(state)

    -- 剩余时间计算
    local remaining = 0
    if seg and plan.segments then
        remaining = math.max(0, seg.time_sec - (plan.segment_elapsed or 0))
        for i = (plan.segment_index or 0) + 1, #plan.segments do
            remaining = remaining + plan.segments[i].time_sec
        end
    end

    local contentChildren = {}

    -- ── 行驶视差场景 ──
    local drivingWidget = DrivingScene.createWidget({
        height = 260,
        borderRadius = Theme.sizes.radius,
    })
    SketchBorder.register(drivingWidget, "card")
    table.insert(contentChildren, drivingWidget)

    -- 当前路段描述
    local EDGE_TYPE_LABEL = { main_road = "公路", path = "小径", shortcut = "捷径" }
    local segFrom = seg and seg.from_name or "?"
    local segTo   = seg and seg.to_name or "?"
    local segType = seg and (EDGE_TYPE_LABEL[seg.edge_type] or "") or ""
    local locationDesc = segType ~= "" and (segFrom .. " → " .. segTo .. "（" .. segType .. "）")
        or (segFrom .. " → " .. segTo)

    -- 最终目的地名
    local finalDest = "?"
    if plan.path and #plan.path > 0 then
        local finalNode = Graph.get_node(plan.path[#plan.path])
        finalDest = finalNode and finalNode.name or plan.path[#plan.path]
    end

    -- 行驶进度卡片
    table.insert(contentChildren, F.card {
        id = "travelStrip",
        width = "100%", padding = 14,
        enterAnim = true, enterDelay = 0.1,
        imageTint = Theme.colors.home_travel_tint,
        borderWidth = 1, borderColor = Theme.colors.info,
        gap = 10,
        children = {
            -- 当前位置：道路上
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 6,
                children = {
                    UI.Label {
                        text = "🚚",
                        fontSize = 16,
                    },
                    UI.Label {
                        id = "travelLocation",
                        text = locationDesc,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                        flexShrink = 1,
                    },
                },
            },
            -- 目标 + 时间
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "→ " .. finalDest,
                        fontSize = Theme.sizes.font_large,
                        fontColor = Theme.colors.info,
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 10, alignItems = "center",
                        children = {
                            UI.Label {
                                text = orderCnt .. " 单",
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.accent,
                            },
                            UI.Label {
                                id = "travelTime",
                                text = string.format("%d:%02d",
                                    math.floor(remaining / 60),
                                    math.floor(remaining % 60)),
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.text_secondary,
                            },
                        },
                    },
                },
            },
            -- 进度条
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", gap = 8,
                children = {
                    UI.ProgressBar {
                        id = "travelProgress",
                        value = progress,
                        flexGrow = 1, height = 10,
                        variant = "info",
                    },
                    UI.Label {
                        id = "travelPct",
                        text = math.floor(progress * 100) .. "%",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                        width = 36, textAlign = "right",
                    },
                },
            },
        },
    })

    -- ── 路景描写（与对话互斥，仅在无对话时显示） ──
    local sceneryWidget = createSceneryText(state)
    if sceneryWidget then
        table.insert(contentChildren, sceneryWidget)
    end

    -- ── 车内日常对话气泡 ──
    local chatterWidget = createChatterBubble(state)
    if chatterWidget then
        table.insert(contentChildren, chatterWidget)
    end

    -- 收音机面板已移至全局顶栏（shell_top.lua）

    -- 活跃订单列表
    if #activeOrders > 0 then
        table.insert(contentChildren, UI.Label {
            text = "配送中的订单",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            marginTop = 4,
        })
        for _, order in ipairs(activeOrders) do
            table.insert(contentChildren, UI.Panel {
                width = "100%", padding = 10,
                backgroundColor = Theme.colors.bg_card,
                borderRadius = Theme.sizes.radius_small,
                flexDirection = "row", justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = order.description or (order.from_name .. " → " .. order.to_name),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_primary,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = "+$" .. tostring(order.base_reward),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.success,
                    },
                },
            })
        end
    end

    -- 积压警告
    local backlogInfo = OrderBook.get_backlog_info(state)
    if backlogInfo.level ~= "normal" or backlogInfo.consecutive_expires >= 2 then
        table.insert(contentChildren, createBacklogWarning(backlogInfo))
    end

    -- 货舱概览
    table.insert(contentChildren, createCargoSummary(state))

    return UI.Panel {
        id = "homeScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = contentChildren,
    }
end

-- ============================================================
-- 货舱概览（简版，行驶中展示）
-- ============================================================
function createCargoSummary(state)
    local used = CargoUtils.get_cargo_used(state)
    local hasShortage = CargoUtils.has_any_shortage(state)

    -- 构建货物图标网格
    local itemWidgets = {}
    for gid, count in pairs(state.truck.cargo) do
        if count > 0 then
            local g = Goods.get(gid)
            local name = g and g.name or gid
            local committed = CargoUtils.get_committed(state, gid)
            local countText = "x" .. count
            if committed > 0 then
                countText = countText .. "(委" .. committed .. ")"
            end
            local cat = g and g.category and Goods.CATEGORIES[g.category]
            local catColor = cat and cat.color or Theme.colors.text_primary

            local itemChildren = {}
            -- 图标
            if g and g.icon then
                table.insert(itemChildren, UI.Panel {
                    width = 24, height = 24,
                    backgroundImage = g.icon,
                    backgroundFit = "contain",
                })
            end
            -- 名称 + 数量
            table.insert(itemChildren, UI.Label {
                text = name,
                fontSize = Theme.sizes.font_tiny,
                fontColor = catColor,
            })
            table.insert(itemChildren, UI.Label {
                text = countText,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_secondary,
            })

            table.insert(itemWidgets, UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = itemChildren,
            })
        end
    end

    local cargoChildren = {
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = "货舱",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                },
                UI.Label {
                    text = used .. "/" .. state.truck.cargo_slots,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                },
            },
        },
    }
    -- 如果有货物则显示图标网格，否则显示"空"
    if #itemWidgets > 0 then
        table.insert(cargoChildren, UI.Panel {
            width = "100%",
            flexDirection = "row", flexWrap = "wrap", gap = 8,
            children = itemWidgets,
        })
    else
        table.insert(cargoChildren, UI.Label {
            text = "空",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_dim,
        })
    end

    if hasShortage then
        table.insert(cargoChildren, UI.Label {
            text = "⚠ 委托货物不足",
            fontSize = Theme.sizes.font_tiny,
            fontColor = Theme.colors.danger,
        })
    end

    return F.card {
        width = "100%", padding = 10,
        borderWidth = hasShortage and 1 or 0,
        borderColor = hasShortage and Theme.colors.danger or nil,
        gap = 2,
        children = cargoChildren,
    }
end

-- ============================================================
-- 成长目标（中期目标概览）
-- ============================================================
function createProgressCard(state)
    local items = {}

    -- 1. 货车模块升级进度
    local totalLv, maxLv = 0, 0
    for _, mid in ipairs(Modules.ORDER) do
        totalLv = totalLv + Modules.get_level(state, mid)
        maxLv   = maxLv + Modules.DEFS[mid].max_level
    end
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "模块升级",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = totalLv .. " / " .. maxLv,
                fontSize = Theme.sizes.font_small,
                fontColor = totalLv >= maxLv and Theme.colors.success or Theme.colors.info,
            },
        },
    })

    -- 2. 各势力好感进度（按势力分组）
    local Factions = require("settlement/factions")
    local factionOrder = { "farm", "tech", "scav", "scholar" }
    local gwParts = {}
    for _, fid in ipairs(factionOrder) do
        local fi = Factions.get_faction_info(fid)
        if fi then
            -- 显示首都好感等级
            local capSett = state.settlements[fi.capital]
            local capGw   = capSett and capSett.goodwill or 0
            local capInfo = Goodwill.get_info(capGw)
            local capNode = Graph.get_node(fi.capital)
            local capName = capNode and capNode.name or fi.capital
            -- 缩短名称
            if #capName > 6 then capName = string.sub(capName, 1, 6) end
            table.insert(gwParts, fi.icon .. capName .. " Lv" .. capInfo.level)
        end
    end
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "势力好感",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = table.concat(gwParts, " "),
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    -- 3. 角色关系 + 阶段名
    local _, stageLabel = Campfire.get_relation_stage(state)
    local charParts = {}
    for _, cid in ipairs({ "linli", "taoxia" }) do
        local char = state.character[cid]
        local rel  = char and char.relation or 0
        local cName = cid == "linli" and "林砾" or "陶夏"
        table.insert(charParts, cName .. " " .. math.floor(rel))
    end
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "角色关系",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center",
                children = {
                    UI.Label {
                        text = table.concat(charParts, "  "),
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = "·" .. stageLabel,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.accent,
                    },
                },
            },
        },
    })

    -- 4. 篝火 / 回忆
    local campCount = state.narrative and state.narrative.campfire_count or 0
    local memCount  = state.narrative and state.narrative.memories
        and #state.narrative.memories or 0
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "篝火·回忆",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = campCount .. " 次篝火  " .. memCount .. " 段回忆",
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    -- 5. 任务线索
    local activeQuests = QuestLog.active_count(state)
    local completedQuests = #QuestLog.get_completed(state)
    local questTotal = activeQuests + completedQuests
    if questTotal > 0 then
        table.insert(items, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            onClick = function(self)
                router.navigate("quest_log")
            end,
            children = {
                UI.Label {
                    text = "📜 任务线索",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                },
                UI.Label {
                    text = activeQuests .. " 进行中  " .. completedQuests .. " 已完成  ›",
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = activeQuests > 0
                        and Theme.colors.info or Theme.colors.text_primary,
                },
            },
        })
    end

    -- 6. 总里程
    local trips = state.stats and state.stats.total_trips or 0
    table.insert(items, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "完成行程",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = trips .. " 趟",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_primary,
            },
        },
    })

    -- 0. 主线章节（置顶）
    local chName, chSub = MainStory.get_display(state)
    local hints = MainStory.get_progress_hints(state)
    local hintParts = {}
    for _, h in ipairs(hints) do
        if not h.done then
            table.insert(hintParts, h.progress and (h.text .. " " .. h.progress) or h.text)
        end
    end
    local hintText = #hintParts > 0
        and ("下一章: " .. hintParts[1])
        or ""
    table.insert(items, 1, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "📖 " .. chName,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.accent,
            },
            UI.Panel {
                flexDirection = "row", gap = 4, alignItems = "center",
                children = {
                    UI.Label {
                        text = chSub,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_primary,
                    },
                    hintText ~= "" and UI.Label {
                        text = hintText,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_secondary,
                    } or nil,
                },
            },
        },
    })

    -- 组合
    table.insert(items, 1, UI.Label {
        text = "成长目标",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_card, borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 4,
        children = items,
    }
end

-- ============================================================
-- 积压警告
-- ============================================================
function createBacklogWarning(info)
    local bg = info.level == "overloaded"
        and Theme.colors.home_backlog_danger or Theme.colors.home_backlog_warning

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = bg,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1,
        borderColor = info.level == "overloaded"
            and Theme.colors.danger or Theme.colors.warning,
        flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "委托: " .. info.desc,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.warning,
                flexShrink = 1,
            },
            UI.Label {
                text = "奖励 -" .. info.reward_penalty .. "%",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.danger,
            },
        },
    }
end

-- ============================================================
-- 路景描写文本（行驶中）
-- 没有路景时返回 nil，不占布局空间
-- 纯叙事文字，居中灰色，营造公路旅行氛围
-- ============================================================
function createSceneryText(state)
    local cur = Scenery.get_current(state)
    if not cur then return nil end

    -- 类别对应的微弱装饰色
    local catColors = {
        window  = { 140, 160, 180, 255 },
        cabin   = { 170, 155, 140, 255 },
        sound   = { 140, 170, 150, 255 },
        time    = { 180, 165, 130, 255 },
        micro   = { 160, 150, 165, 255 },
        silence = { 120, 120, 120, 255 },
    }
    local textColor = catColors[cur.category] or Theme.colors.text_dim

    return UI.Panel {
        width = "100%", paddingTop = 4, paddingBottom = 4,
        paddingLeft = 20, paddingRight = 20,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Label {
                text = cur.text,
                fontSize = Theme.sizes.font_small,
                fontColor = textColor,
                textAlign = "center",
            },
        },
    }
end

-- ============================================================
-- 车内日常对话气泡（行驶中）
-- 没有对话时返回 nil，不占布局空间
-- ============================================================
function createChatterBubble(state)
    local cur = Chatter.get_current(state)
    if not cur then return nil end

    local speakerNames = { linli = "林砾", taoxia = "陶夏" }
    local speakerColorKeys = {
        linli  = "chatter_linli_name",
        taoxia = "chatter_taoxia_name",
    }
    local name  = speakerNames[cur.speaker] or cur.speaker
    local color = Theme.colors[speakerColorKeys[cur.speaker]] or Theme.colors.accent
    local avatar = Theme.avatars[cur.speaker] or Theme.avatars.linli

    -- 文字列子元素
    local textChildren = {
        -- 说话人
        UI.Label {
            text = name,
            fontSize = Theme.sizes.font_small,
            fontColor = color,
        },
        -- 对话内容
        UI.Label {
            text = cur.text,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_primary,
        },
    }

    -- 可回应的对话：显示回应按钮
    if cur.response then
        table.insert(textChildren, F.actionBtn {
            text = cur.response.label or "回应",
            variant = "secondary",
            height = 30,
            fontSize = Theme.sizes.font_small,
            onClick = function(self)
                Chatter.respond(state)
            end,
        })
    end

    return F.card {
        width = "100%",
        backgroundColor = Theme.colors.chatter_bubble_bg,
        flexDirection = "row",
        alignItems = "flex-start",
        padding = 10,
        gap = 8,
        children = {
            -- 头像
            UI.Panel {
                width = 36, height = 36,
                borderRadius = 18,
                backgroundImage = avatar,
                backgroundFit = "cover",
                flexShrink = 0,
            },
            -- 文字区域
            UI.Panel {
                flex = 1, flexShrink = 1,
                gap = 4,
                children = textChildren,
            },
        },
    }
end

return M

--- 首页控制器 — 末世行商主界面
--- 调度据点视图（settlement_view）和行驶视图（travel_view）
--- 负责 DrivingScene late-init、Chatter/Scenery/RoadLoot 驱动、UI 增量刷新
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
local RoutePlanner = require("map/route_planner")
local Chatter      = require("travel/chatter")
local Scenery      = require("travel/scenery")
local DrivingScene = require("travel/chibi_scene")
local Environment  = require("travel/environment")
local RoadLoot     = require("travel/road_loot")
local Tutorial     = require("narrative/tutorial")
local Flags        = require("core/flags")
local SpeechBubble = require("ui/speech_bubble")
local SoundMgr     = require("ui/sound_manager")

local SettlementView = require("home/settlement_view")
local TravelView     = require("home/travel_view")

local M = {}
---@type table
local router = nil

-- 行驶中状态追踪（用于检测变化触发 UI 重建）
local _prevChatterId    = nil
local _prevSceneryId    = nil
local _prevSegmentIndex = nil

-- ============================================================
-- 页面创建
-- ============================================================
function M.create(state, params, r)
    router = r
    SettlementView.init({ router = r })

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
        return TravelView.create(state)
    else
        -- 教程阶段：确保教程订单已生成
        -- 适用于所有定义了 order 的教程阶段（spawn / explore_to_ruins 等）
        local _tutPhase, tutDef = Tutorial.get_phase(state)
        if tutDef and tutDef.order then
            local loc = state.map.current_location
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

        return SettlementView.create(state, curNode)
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
    DrivingScene.update(dt)
    RoadLoot.update(state, dt)
    DrivingScene.setDrops(RoadLoot.get_active_drops(state))

    -- ── 教程：路面拾取提示（首次出现掉落物时触发一次）──
    if not Flags.has(state, "tutorial_loot_hint_shown") then
        local tutPhase = Tutorial.get_phase(state)
        if tutPhase == Tutorial.Phase.TRAVEL_TO_GREENHOUSE then
            local drops = RoadLoot.get_active_drops(state)
            if drops and #drops > 0 then
                Flags.set(state, "tutorial_loot_hint_shown")
                local hintTimer = 1.0
                local hintShown = false
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

return M

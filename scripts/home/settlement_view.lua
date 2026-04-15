--- 据点视图 — 聚落/节点停泊时的 UI 界面
--- 包含：CG 背景 + 信息卡 + 操作按钮列表 + 成长目标弹窗
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")
local Flow         = require("core/flow")
local Graph        = require("map/world_graph")
local OrderBook    = require("economy/order_book")
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
local router_ = nil

-- ============================================================
-- 常量
-- ============================================================

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
    greenhouse      = { bg = { 38, 52, 38, 255 }, accent = { 108, 148,  96, 255 }, icon = "map_settlement" },
    tower           = { bg = { 32, 40, 54, 255 }, accent = { 112, 142, 168, 255 }, icon = "map_settlement" },
    ruins_camp      = { bg = { 48, 38, 30, 255 }, accent = { 168, 128,  82, 255 }, icon = "map_hazard" },
    bell_tower      = { bg = { 42, 36, 46, 255 }, accent = { 148, 128, 168, 255 }, icon = "map_settlement" },
    -- 前哨站
    greenhouse_farm = { bg = { 34, 48, 32, 255 }, accent = {  96, 138,  80, 255 }, icon = "map_resource" },
    dome_outpost    = { bg = { 30, 36, 48, 255 }, accent = {  96, 126, 152, 255 }, icon = "map_story" },
    metro_camp      = { bg = { 44, 36, 28, 255 }, accent = { 152, 112,  72, 255 }, icon = "map_transit" },
    old_church      = { bg = { 38, 32, 42, 255 }, accent = { 132, 112, 148, 255 }, icon = "map_settlement" },
}
local DEFAULT_THEME = { bg = { 40, 38, 36, 255 }, accent = Theme.colors.accent, icon = "location" }

-- ============================================================
-- 模块级状态
-- ============================================================
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
        router_.navigate("home")
        return
    end
    local uiRoot = UI.GetRoot()
    if not uiRoot then
        router_.navigate("home")
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

-- ============================================================
-- 积压警告
-- ============================================================
local function createBacklogWarning(info)
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
-- 成长目标（中期目标概览）
-- ============================================================
local function createProgressCard(state)
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
            local capSett = state.settlements[fi.capital]
            local capGw   = capSett and capSett.goodwill or 0
            local capInfo = Goodwill.get_info(capGw)
            local capNode = Graph.get_node(fi.capital)
            local capName = capNode and capNode.name or fi.capital
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
                router_.navigate("quest_log")
            end,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        F.icon { icon = "scroll", size = 20 },
                        UI.Label {
                            text = "任务线索",
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_secondary,
                        },
                    },
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
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    F.icon { icon = "book", size = 20 },
                    UI.Label {
                        text = chName,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.accent,
                    },
                },
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
        backgroundImage = Theme.textures.parchment, backgroundFit = "cover",
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 4,
        children = items,
    }
end

-- ============================================================
-- 初始化（由控制器调用，传入 router 引用）
-- ============================================================
function M.init(refs)
    router_ = refs.router
end

-- ============================================================
-- 据点视图创建
-- ============================================================
function M.create(state, curNode)
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
            icon = "tab_orders",
            text = "接取委托",
            variant = "primary",
            height = 48,
            fontSize = Theme.sizes.font_normal,
            highlight = true,
            onClick = function(self)
                Flow.enter_prepare(state)
                router_.navigate("orders")
            end,
        })
        -- 跳过后续所有按钮，直接进入下方 UI 组装

    elseif tutPhase == Tutorial.Phase.AT_GREENHOUSE then
        -- AT_GREENHOUSE = 抵达温室社区，引导使用交易所
        -- 允许：NPC 对话 + 交易所（高亮）+ 委托 + 篝火；出发锁定

        -- NPC 拜访
        local settlementNpcs = NpcManager.get_npcs_for_settlement(nodeId)
        for _, npc in ipairs(settlementNpcs) do
            local canVisit, visitReason = NpcManager.can_visit(state, npc.id)
            table.insert(lowerChildren, F.actionBtn {
                icon = npc.chibi,
                iconSize = 24,
                iconRound = true,
                text = canVisit
                    and ("拜访 " .. npc.name)
                    or  (npc.name .. "（" .. (visitReason or "不可用") .. "）"),
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not canVisit,
                onClick = function(self)
                    if not canVisit then return end
                    local dialogue = NpcManager.start_visit(state, npc.id)
                    if dialogue then
                        router_.navigate("npc", { npc_id = npc.id, dialogue = dialogue })
                    end
                end,
            })
        end

        -- 交易所（高亮引导：教程要求玩家访问交易所才能推进）
        table.insert(lowerChildren, F.actionBtn {
            icon = "exchange",
            text = "交易所",
            variant = "primary",
            height = 48,
            fontSize = Theme.sizes.font_normal,
            highlight = true,
            onClick = function(self)
                router_.navigate("shop")
            end,
        })

        -- 接取委托
        table.insert(lowerChildren, F.actionBtn {
            icon = "tab_orders",
            text = "接取委托",
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                Flow.enter_prepare(state)
                router_.navigate("orders")
            end,
        })

        -- 篝火仍可用
        local canCamp, campReason = Campfire.can_start(state)
        local hasStoryTopic = canCamp and Campfire.has_story_topic(state)
        if canCamp then
            local campLabel = hasStoryTopic
                and "篝火休憩 · 有话题要谈"
                or  "篝火休憩"
            table.insert(lowerChildren, F.actionBtn {
                icon = "campfire",
                text = campLabel,
                variant = hasStoryTopic and "primary" or "secondary",
                fontSize = Theme.sizes.font_normal,
                highlight = hasStoryTopic or nil,
                onClick = function(self)
                    local dialogue, consumed = Campfire.start(state)
                    if dialogue then
                        router_.navigate("campfire", { dialogue = dialogue, consumed = consumed })
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
                icon = "lightning",
                text = pendingEvt.title or "聚落事件",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                sound = "event",
                onClick = function(self)
                    local evt = state.flow.pending_settlement_event
                    state.flow.pending_settlement_event = nil
                    SettlementEventPool.set_cooldown(state, evt.id)
                    router_.navigate("event", {
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
                icon = npc.chibi,
                iconSize = 24,
                iconRound = true,
                text = canVisit
                    and ("拜访 " .. npc.name)
                    or  (npc.name .. "（" .. (visitReason or "不可用") .. "）"),
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not canVisit,
                onClick = function(self)
                    if not canVisit then return end
                    local dialogue = NpcManager.start_visit(state, npc.id)
                    if dialogue then
                        router_.navigate("npc", { npc_id = npc.id, dialogue = dialogue })
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
                    icon = wnpc.chibi,
                    iconSize = 24,
                    iconRound = true,
                    text = wCanVisit
                        and ("遇见 " .. wnpc.name .. "（" .. wnpc.title .. "）")
                        or  (wnpc.name .. "（" .. (wReason or "不可用") .. "）"),
                    variant = "secondary",
                    fontSize = Theme.sizes.font_normal,
                    disabled = not wCanVisit,
                    onClick = function(self)
                        if not wCanVisit then return end
                        local dialogue = NpcManager.start_visit(state, wid)
                        if dialogue then
                            router_.navigate("npc", { npc_id = wid, dialogue = dialogue })
                        end
                    end,
                })
            end
        end

        -- 信件领取（雪冬送信）
        if LetterSystem.has_pending(state) then
            local pendingCount = LetterSystem.pending_count(state)
            table.insert(lowerChildren, F.actionBtn {
                icon = "letter",
                text = "雪冬送来了 " .. pendingCount .. " 封信",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                highlight = true,
                onClick = function(self)
                    router_.navigate("letter_pickup")
                end,
            })
        end

        -- 委托
        table.insert(lowerChildren, F.actionBtn {
            icon = "tab_orders",
            text = "接取委托",
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                Flow.enter_prepare(state)
                router_.navigate("orders")
            end,
        })

        -- 交易所
        table.insert(lowerChildren, F.actionBtn {
            icon = "exchange",
            text = "交易所",
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            onClick = function(self)
                router_.navigate("shop")
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
                and ("档案阅览" .. (unreadCount > 0 and (" (" .. unreadCount .. " 未读)") or ""))
                or  "档案阅览（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                icon = "book",
                text = archLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not archUnlocked,
                onClick = function(self)
                    if not archUnlocked then return end
                    if not Flags.has(state, "unlock_seen_archives") then
                        local d = UnlockStories.get("archives")
                        router_.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "archives" })
                    else
                        router_.navigate("archives")
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
                and ("培育农场" .. (busyCount > 0 and (" (" .. busyCount .. " 栽种中)") or ""))
                or  "培育农场（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                icon = "map_resource",
                text = farmLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not farmUnlocked,
                onClick = function(self)
                    if not farmUnlocked then return end
                    if not Flags.has(state, "unlock_seen_farm") then
                        local d = UnlockStories.get("farm")
                        router_.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "farm" })
                    else
                        router_.navigate("farm")
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
                and ("情报站" .. (routeData > 0 and (" (数据点: " .. routeData .. ")") or ""))
                or  "情报站（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                icon = "map_story",
                text = intelLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not intelUnlocked,
                onClick = function(self)
                    if not intelUnlocked then return end
                    if not Flags.has(state, "unlock_seen_intel") then
                        local d = UnlockStories.get("intel")
                        router_.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "intel" })
                    else
                        router_.navigate("intel")
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
                and ("黑市" .. (itemCount > 0 and (" (" .. itemCount .. " 件商品)") or ""))
                or  "黑市（好感不足）"
            table.insert(lowerChildren, F.actionBtn {
                icon = "map_hazard",
                text = marketLabel,
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                disabled = not marketUnlocked,
                onClick = function(self)
                    if not marketUnlocked then return end
                    if not Flags.has(state, "unlock_seen_black_market") then
                        local d = UnlockStories.get("black_market")
                        router_.navigate("npc", { npc_id = d.npc_id, dialogue = d, _return_to = "black_market" })
                    else
                        router_.navigate("black_market")
                    end
                end,
            })
        end

        -- 闲逛
        local canStroll, strollReason = Stroll.can_start(state)
        local strollLabel
        if canStroll then
            strollLabel = "四处逛逛（消耗 1 饮用水）"
        else
            strollLabel = "四处逛逛（" .. (strollReason or "不可用") .. "）"
        end
        table.insert(lowerChildren, F.actionBtn {
            icon = "walking",
            text = strollLabel,
            variant = "secondary",
            fontSize = Theme.sizes.font_normal,
            disabled = not canStroll,
            onClick = function(self)
                if not canStroll then return end
                local scenes, consumed = Stroll.start(state)
                if scenes and #scenes > 0 then
                    router_.navigate("stroll", { scenes = scenes, consumed = consumed })
                end
            end,
        })

        -- 信箱已迁移到货仓 tab（随时可查看）

        -- 篝火（有主线话题且可用时高亮）
        local canCamp, campReason, isCampFree = Campfire.can_start(state)
        local hasStoryTopic = canCamp and Campfire.has_story_topic(state)
        local isFirstStoryVisit = curNode and curNode.type == "story"
            and not (state._visited_story_nodes and state._visited_story_nodes[nodeId])
        local campLabel
        if canCamp then
            if hasStoryTopic then
                campLabel = "篝火休憩 · 有话题要谈"
            elseif isCampFree then
                campLabel = "篝火休憩"
            else
                -- 显示将消耗的物品
                local cargo = state.truck.cargo or {}
                local costName = (cargo.food_can or 0) >= 1 and "罐头食品" or "燃料芯"
                campLabel = "篝火休憩（消耗 1 " .. costName .. "）"
            end
        else
            campLabel = "篝火（" .. (campReason or "不可用") .. "）"
        end
        local campHighlight = hasStoryTopic or isFirstStoryVisit
        table.insert(lowerChildren, F.actionBtn {
            icon = "campfire",
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
                    router_.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                end
            end,
        })

        -- 出发（仅有活跃订单时）
        if #activeOrders > 0 then
            table.insert(lowerChildren, F.actionBtn {
                icon = "tab_truck",
                text = "出发",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    Flow.enter_map(state)
                    router_.navigate("map", { mode = "route_plan" })
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
                    icon = wnpc.chibi,
                    iconSize = 24,
                    iconRound = true,
                    text = wCanVisit
                        and ("遇见 " .. wnpc.name .. "（" .. wnpc.title .. "）")
                        or  (wnpc.name .. "（" .. (wReason or "不可用") .. "）"),
                    variant = "secondary",
                    fontSize = Theme.sizes.font_normal,
                    disabled = not wCanVisit,
                    onClick = function(self)
                        if not wCanVisit then return end
                        local dialogue = NpcManager.start_visit(state, wid)
                        if dialogue then
                            router_.navigate("npc", { npc_id = wid, dialogue = dialogue })
                        end
                    end,
                })
            end
        end

        -- 路点事件（到达非聚落节点时触发的随机事件）
        local pendingWP = state.flow and state.flow.pending_waypoint_event or nil
        if pendingWP then
            table.insert(lowerChildren, F.actionBtn {
                icon = "lightning",
                text = pendingWP.title or "路点事件",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                sound = "event",
                onClick = function(self)
                    local evt = state.flow.pending_waypoint_event
                    state.flow.pending_waypoint_event = nil
                    WaypointEventPool.set_cooldown(state, evt.id)
                    router_.navigate("event", {
                        event = evt,
                        source = "waypoint",
                    })
                end,
            })
        end

        -- 非聚落节点：出发按钮（如有订单）
        if #activeOrders > 0 then
            table.insert(lowerChildren, F.actionBtn {
                icon = "tab_truck",
                text = "出发",
                variant = "primary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    Flow.enter_map(state)
                    router_.navigate("map", { mode = "route_plan" })
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
                icon = "tent",
                text = canRest and "短暂休整"
                    or ("休整（" .. (restReason or "不可用") .. "）"),
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
                campLabel = "篝火休憩 · 此地似有故事"
            elseif hasStoryTopic then
                campLabel = "篝火休憩 · 有话题要谈"
            else
                campLabel = "篝火休憩"
            end
        else
            campLabel = "篝火（" .. (campReason or "不可用") .. "）"
        end
        table.insert(lowerChildren, F.actionBtn {
            icon = "campfire",
            text = campLabel,
            variant = hasStoryTopic and "primary" or "secondary",
            fontSize = Theme.sizes.font_normal,
            disabled = not canCamp,
            highlight = hasStoryTopic or nil,
            onClick = function(self)
                if not canCamp then return end
                local dialogue, consumed = Campfire.start(state)
                if dialogue then
                    router_.navigate("campfire", { dialogue = dialogue, consumed = consumed })
                end
            end,
        })

        -- 资源点特殊行动：搜刮此地
        if NODE_EXPLORE_ROOM[nodeId] then
            table.insert(lowerChildren, F.actionBtn {
                icon = "search",
                text = "搜刮此地",
                variant = "secondary",
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    router_.navigate("explore", { room_id = NODE_EXPLORE_ROOM[nodeId] })
                end,
            })
        end
    end

    end -- 教程 SPAWN 锁定分支结束

    -- 探索区域已迁移到地图页面（screen_map）

    -- 外层 Panel 负责背景图渲染（不滚动，保证 backgroundImage 生效）
    -- 内层 F.card 带 overflow="scroll" 会被升级为 ScrollView（不支持 backgroundImage）
    local lowerPanel = UI.Panel {
        id = "settlementActionsWrap",
        width = "100%", flexShrink = 1,
        backgroundImage = Theme.textures.notebook_bg,
        backgroundFit = "cover",
        borderRadius = Theme.sizes.radius,
        children = {
            F.card {
                id = "settlementActions",
                width = "100%",
                padding = Theme.sizes.padding, gap = 10,
                enterAnim = true, enterDelay = 0.05,
                sketch = false,  -- 边框画在外层
                children = lowerChildren,
            },
        },
    }
    SketchBorder.register(lowerPanel, "card")

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
                                    F.icon { icon = (Theme.icons[theme.icon] and theme.icon or "location"), size = 20 },
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
        icon = "target",
        iconSize = 16,
        text = "成长目标",
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
            router_.navigate("home")
        end,
    })
    -- 活跃订单按钮
    if #activeOrders > 0 then
        table.insert(floatingButtons, F.actionBtn {
            icon = "tab_orders",
            iconSize = 16,
            text = "订单 " .. #activeOrders,
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
                router_.navigate("orders")
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
                router_.navigate("home")
            end,
            children = {
                UI.Panel {
                    id = "homeProgressScroll",
                    width = "100%", maxHeight = "80%",
                    backgroundColor = Theme.colors.bg_primary,
                    backgroundImage = Theme.textures.parchment,
                    backgroundFit = "cover",
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
                                router_.navigate("home")
                            end,
                        },
                    },
                },
            },
        })
    end

    -- 层 7：教程引导气泡（绝对定位浮层）
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

return M

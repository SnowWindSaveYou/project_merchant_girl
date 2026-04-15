--- 订单簿管理页
--- 查看已接订单、按目的地分组、取消订单、前往路线规划
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local Flow         = require("core/flow")
local OrderBook    = require("economy/order_book")
local Graph        = require("map/world_graph")
local Goods        = require("economy/goods")
local CargoUtils   = require("economy/cargo_utils")
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local DialoguePool = require("narrative/dialogue_pool")
local Flags        = require("core/flags")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")

local M = {}
---@type table
local router = nil
--- 页面根容器引用（供命令式气泡使用）
local screenRoot_ = nil
--- 入场教程对话是否已显示（防止页面刷新重复触发）
local enterDialogueShown_ = false

local RISK_LABEL = { low = "低", normal = "中", high = "高" }
local RISK_COLOR = {
    low    = Theme.colors.success,
    normal = Theme.colors.accent,
    high   = Theme.colors.danger,
}

-- 模块级旅行状态（供子函数使用）
local isTravelling_ = false

-- ============================================================
-- 教程对话序列定义
-- ============================================================
local LINLI_PORTRAIT  = Tutorial.AVATAR_LINLI
local TAOXIA_PORTRAIT = Tutorial.AVATAR_TAOXIA

--- 教程对话序列表
local TUT_SEQUENCES = {
    -- SPAWN 阶段进入委托界面
    spawn_enter = {
        { portrait = TAOXIA_PORTRAIT, speaker = "陶夏", text = "这就是委托板！上面会贴出各个聚落的运货需求。" },
        { portrait = LINLI_PORTRAIT,  speaker = "林砾", text = "挑一个目的地顺路的单子接。货物会自动装车。" },
        { portrait = TAOXIA_PORTRAIT, speaker = "陶夏", text = "先找个简单的单子试试吧——去温室社区的那个看起来不错！" },
    },
    -- SPAWN 阶段接单后
    spawn_accept = {
        { portrait = LINLI_PORTRAIT,  speaker = "林砾", text = "单子接好了，货已经装车。" },
        { portrait = TAOXIA_PORTRAIT, speaker = "陶夏", text = "出发吧！去地图界面规划路线就能上路了！" },
    },
    -- GREENHOUSE 阶段进入委托界面
    greenhouse_enter = {
        { portrait = LINLI_PORTRAIT,  speaker = "林砾", text = "温室社区的委托板。看看有什么新单子。" },
        { portrait = TAOXIA_PORTRAIT, speaker = "陶夏", text = "接单之前看看仓位够不够哦——满了可装不下！" },
    },
    -- GREENHOUSE 阶段接单后（气泡过渡，随后跳完整对话）
    greenhouse_accept = {
        { portrait = TAOXIA_PORTRAIT, speaker = "陶夏", text = "接到新单了！目的地是北穹塔台！" },
        { portrait = LINLI_PORTRAIT,  speaker = "林砾", text = "嗯……不过去北穹的路还没探通，我们商量一下怎么走。" },
    },
}

--- 显示教程对话序列（逐条弹出，点击后切换下一条）
---@param seqKey string TUT_SEQUENCES 中的 key
---@param onComplete function|nil 全部对话结束后回调
local function showTutorialSequence(seqKey, onComplete)
    local seq = TUT_SEQUENCES[seqKey]
    if not seq or #seq == 0 or not screenRoot_ then return end

    local idx = 1
    local function showNext()
        if idx > #seq then
            if onComplete then onComplete() end
            return
        end
        local step = seq[idx]
        idx = idx + 1
        SpeechBubble.show(screenRoot_, {
            portrait = step.portrait,
            speaker  = step.speaker,
            text     = step.text,
            autoHide = 0,
            onDismiss = function()
                showNext()
            end,
        })
    end
    showNext()
end

function M.create(state, params, r)
    router = r
    isTravelling_ = Flow.get_phase(state) == Flow.Phase.TRAVELLING

    local activeOrders = OrderBook.get_active(state)
    local groups = OrderBook.group_by_destination(state)
    local location = state.map.current_location
    local curNode = Graph.get_node(location)
    local isSettlement = curNode and curNode.type == "settlement"

    local cargoUsed = CargoUtils.get_cargo_used(state)
    local cargoFree = CargoUtils.get_cargo_free(state)

    local contentChildren = {}

    -- ── 仓位状态栏 ──
    table.insert(contentChildren, F.card {
        width = "100%", padding = 10,
        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "货舱空位",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = cargoFree .. " / " .. state.truck.cargo_slots .. " 格",
                fontSize = Theme.sizes.font_normal,
                fontColor = cargoFree <= 0 and Theme.colors.danger
                    or cargoFree <= 2 and Theme.colors.warning
                    or Theme.colors.success,
            },
        },
    })

    -- ── 旅行中提示 ──
    local isTravelling = isTravelling_
    if isTravelling then
        table.insert(contentChildren, UI.Panel {
            width = "100%", padding = 12,
            backgroundColor = Theme.colors.home_travel_tint,
            borderRadius = Theme.sizes.radius,
            borderWidth = 1, borderColor = Theme.colors.info,
            flexDirection = "row", alignItems = "center", gap = 8,
            children = {
                UI.Label {
                    text = "🚚",
                    fontSize = 16,
                },
                UI.Label {
                    text = "旅途中 — 到达聚落后可接取新订单",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.info,
                    flexShrink = 1,
                },
            },
        })
    end

    -- ── 可接取订单区域（仅在聚落且非旅行时显示） ──
    if isSettlement and not isTravelling then
        local available = OrderBook.get_available(state, location)
        if #available > 0 then
            table.insert(contentChildren, UI.Label {
                text = curNode.name .. " · 可接订单",
                fontSize = Theme.sizes.font_large,
                fontColor = Theme.colors.text_primary,
            })
            for _, order in ipairs(available) do
                table.insert(contentChildren, createAvailableOrderCard(state, order))
            end

            -- 分割线
            table.insert(contentChildren, UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Theme.colors.border,
                marginTop = 4, marginBottom = 4,
            })
        else
            table.insert(contentChildren, F.card {
                width = "100%", padding = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "当前聚落暂无新订单",
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_dim,
                    },
                },
            })
        end
    end

    -- ── 持有订单区域 ──
    table.insert(contentChildren, F.card {
        width = "100%", padding = 12,
        flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label { text = "持有订单", fontSize = Theme.sizes.font_large, fontColor = Theme.colors.text_primary },
            UI.Label {
                text = #activeOrders .. " 个",
                fontSize = Theme.sizes.font_large, fontColor = Theme.colors.accent,
            },
        },
    })

    if #activeOrders == 0 then
        table.insert(contentChildren, F.card {
            width = "100%", padding = 20,
            alignItems = "center", gap = 4,
            children = {
                UI.Label {
                    text = "暂无持有订单",
                    fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_dim,
                },
            },
        })
    else
        for destId, group in pairs(groups) do
            table.insert(contentChildren, createDestGroup(state, group))
        end
    end

    -- 底部操作
    local bottomChildren = {}

    if #activeOrders > 0 and not isTravelling then
        table.insert(bottomChildren, F.actionBtn {
            text = "规划路线并出发",
            variant = "primary", height = 48,
            onClick = function(self)
                Flow.enter_map(state)
                router.navigate("map", { mode = "route_plan" })
            end,
        })
    end

    local root = UI.Panel {
        id = "prepareScreen",
        width = "100%", height = "100%",
        children = {
            -- 内容（可滚动）
            UI.Panel {
                id = "prepareScroll",
                width = "100%", flexGrow = 1, flexShrink = 1,
                padding = Theme.sizes.padding, gap = 10,
                overflow = "scroll",
                children = contentChildren,
            },
            -- 底部操作按钮
            UI.Panel {
                width = "100%", padding = Theme.sizes.padding, gap = 8,
                borderTopWidth = 1, borderColor = Theme.colors.border,
                children = bottomChildren,
            },
        },
    }
    screenRoot_ = root

    -- ── 教程入场对话（仅首次进入时播放） ──
    if not enterDialogueShown_ then
        enterDialogueShown_ = true
        local tutPhase = Tutorial.get_phase(state)
        if tutPhase == Tutorial.Phase.SPAWN then
            showTutorialSequence("spawn_enter")
        elseif tutPhase == Tutorial.Phase.GREENHOUSE_FREE
            or tutPhase == Tutorial.Phase.EXPLORE then
            showTutorialSequence("greenhouse_enter")
        end
    end

    return root
end

function M.update(state, dt, r)
    SpeechBubble.update(dt)
end

--- 目的地分组卡片
function createDestGroup(state, group)
    local orderCards = {}
    for _, order in ipairs(group.orders) do
        local remaining = OrderBook.get_remaining_time(order)
        local timeText = remaining > 0
            and string.format("剩余 %d:%02d", math.floor(remaining / 60), remaining % 60)
            or "已超时"
        local timeColor = remaining > 120 and Theme.colors.text_secondary
            or remaining > 0 and Theme.colors.accent
            or Theme.colors.danger

        table.insert(orderCards, UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = Theme.colors.bg_secondary, borderRadius = Theme.sizes.radius_small,
            gap = 4,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = order.goods_name .. " ×" .. order.count,
                            fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_primary,
                            flexShrink = 1,
                        },
                        UI.Label {
                            text = "+$" .. order.base_reward,
                            fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.success,
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row", gap = 8,
                            children = {
                                UI.Label {
                                    text = "风险 " .. (RISK_LABEL[order.risk_level] or "?"),
                                    fontSize = Theme.sizes.font_tiny,
                                    fontColor = RISK_COLOR[order.risk_level] or Theme.colors.text_dim,
                                },
                                UI.Label {
                                    text = timeText,
                                    fontSize = Theme.sizes.font_tiny, fontColor = timeColor,
                                },
                            },
                        },
                        OrderBook.can_abandon(order) and F.actionBtn {
                            text = "放弃",
                            variant = "text", width = "auto", height = 24,
                            onClick = function(self)
                                OrderBook.abandon_order(state, order.order_id)
                                router.navigate("orders") -- 刷新
                            end,
                        } or nil,
                    },
                },
            },
        })
    end

    return F.card {
        width = "100%", padding = 12,
        borderWidth = Theme.sizes.border, borderColor = Theme.colors.accent,
        gap = 8,
        children = {
            UI.Label {
                text = "🎯 " .. group.dest_name .. " (" .. #group.orders .. "单)",
                fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.accent,
            },
            UI.Panel {
                width = "100%", gap = 6,
                children = orderCards,
            },
        },
    }
end

--- 可接取订单卡片
function createAvailableOrderCard(state, order)
    local destName = Graph.get_node_name(order.to)
    local goodsInfo = Goods.get(order.goods_id)
    local goodsName = goodsInfo and goodsInfo.name or order.goods_id
    local riskColor = RISK_COLOR[order.risk_level] or Theme.colors.text_dim
    local riskText  = RISK_LABEL[order.risk_level] or "?"

    local free = CargoUtils.get_cargo_free(state)
    local needSlots = order.count or 1
    local canAccept = free >= needSlots

    return F.card {
        width = "100%", padding = 12,
        borderWidth = 1, borderColor = canAccept and Theme.colors.success or Theme.colors.border,
        gap = 6,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = goodsName .. " ×" .. needSlots,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = "+$" .. tostring(order.base_reward),
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.success,
                    },
                },
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 8,
                        children = {
                            UI.Label {
                                text = "→ " .. destName,
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.accent,
                            },
                            UI.Label {
                                text = "风险 " .. riskText,
                                fontSize = Theme.sizes.font_tiny,
                                fontColor = riskColor,
                            },
                            UI.Label {
                                text = "需 " .. needSlots .. " 格",
                                fontSize = Theme.sizes.font_tiny,
                                fontColor = canAccept and Theme.colors.text_dim or Theme.colors.danger,
                            },
                        },
                    },
                    F.actionBtn {
                        text = canAccept and "接取" or "仓位不足",
                        variant = canAccept and "primary" or "secondary",
                        width = "auto", height = 28, paddingLeft = 14, paddingRight = 14,
                        disabled = not canAccept,
                        onClick = function(self)
                            local ok, err = OrderBook.accept_order(state, order)
                            if ok then
                                print("[Orders] Accepted: " .. (order.order_id or "?"))
                                -- 教程订单接取后显示对话
                                if order.is_tutorial then
                                    local tutPhase = Tutorial.get_phase(state)
                                    if tutPhase == Tutorial.Phase.SPAWN
                                        or tutPhase == Tutorial.Phase.TRAVEL_TO_GREENHOUSE then
                                        showTutorialSequence("spawn_accept", function()
                                            router.navigate("orders")
                                        end)
                                        return
                                    elseif order.to == "tower"
                                        and not Flags.has(state, "tutorial_explore_guided") then
                                        -- 接北穹订单 → 直接进入"未知的路"完整对话
                                        -- 对话结束回主界面后由 EXPLORE 气泡引导操作
                                        local exploreDialogue = DialoguePool.get("SD_TUTORIAL_EXPLORE_HINT")
                                        if exploreDialogue then
                                            router.navigate("campfire", {
                                                dialogue = exploreDialogue,
                                                consumed = false,
                                            })
                                            return
                                        end
                                    end
                                end
                            else
                                print("[Orders] Accept failed: " .. (err or ""))
                            end
                            router.navigate("orders") -- 刷新
                        end,
                    },
                },
            },
        },
    }
end

return M

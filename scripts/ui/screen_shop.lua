--- 聚落交易所
--- 在当前聚落买卖商品 + 补给维修服务 + 模块升级 + 休整
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local Goods        = require("economy/goods")
local Pricing      = require("economy/pricing")
local Graph        = require("map/world_graph")
local CargoUtils   = require("economy/cargo_utils")
local Goodwill     = require("settlement/goodwill")
local Modules      = require("truck/modules")
local ItemUse      = require("economy/item_use")
local Tutorial     = require("narrative/tutorial")
local Flags        = require("core/flags")
local SpeechBubble = require("ui/speech_bubble")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")
local NpcManager   = require("narrative/npc_manager")
local SketchBorder = require("ui/sketch_border")

-- NPC 立绘映射（与 gal_dialogue 保持一致）
local NPC_PORTRAITS = {
    shen_he    = "image/portrait_shen_he_20260406000120.png",
    han_ce     = "image/portrait_han_ce_20260406000106.png",
    wu_shiqi   = "image/portrait_wu_shiqi_20260406000058.png",
    bai_shu    = "image/portrait_bai_shu_20260406000056.png",
    meng_hui   = "image/portrait_meng_hui_20260406000106.png",
    ming_sha   = "image/portrait_ming_sha_20260406000227.png",
    dao_yu     = "image/portrait_dao_yu_20260408072957.png",
    xie_ling   = "image/portrait_xie_ling_20260408073029.png",
    ji_wei     = "image/portrait_ji_wei_20260408124639.png",
    old_gan    = "image/portrait_old_gan_20260408124632.png",
    a_xiu      = "image/portrait_a_xiu_20260409120249.png",
    cheng_yuan = "image/portrait_cheng_yuan_20260409120343.png",
    su_mo      = "image/portrait_su_mo_20260409120418.png",
    xue_dong   = "image/portrait_xue_dong_20260412064247.png",
}

-- 势力通用立绘（NPC 无独立立绘时的 fallback）
local FACTION_PORTRAITS = {
    farm    = "image/portrait_faction_farm_20260406000212.png",
    tech    = "image/portrait_faction_tech_20260406000259.png",
    scav    = "image/portrait_faction_scav_20260406000214.png",
    scholar = "image/portrait_faction_scholar_20260406000214.png",
}

-- 聚落 → 势力映射（用于 fallback 立绘）
local SETTLEMENT_FACTION = {
    greenhouse      = "farm",
    greenhouse_farm = "farm",
    tower           = "tech",
    bell_tower      = "scholar",
    ruins_camp      = "scav",
    dome_outpost    = "tech",
    metro_camp      = "scav",
    old_church      = "scholar",
}

--- 获取 NPC 立绘路径（独立立绘 → 势力 fallback → nil）
local function get_portrait(npc_id, settlement_id)
    if npc_id and NPC_PORTRAITS[npc_id] then
        return NPC_PORTRAITS[npc_id]
    end
    local faction = settlement_id and SETTLEMENT_FACTION[settlement_id]
    if faction and FACTION_PORTRAITS[faction] then
        return FACTION_PORTRAITS[faction]
    end
    return FACTION_PORTRAITS.farm  -- 最终 fallback
end

-- NPC 商店问候语（按 NPC 个性）
local SHOP_GREETINGS = {
    shen_he    = { "欢迎来温室补给，价格公道。", "需要什么尽管开口，我们量力供应。", "辛苦跑一趟，先看看货架吧。" },
    han_ce     = { "塔台物资有限，但质量保证。", "来啦，今天带了什么好东西？", "交易讲信用，咱们痛快点。" },
    wu_shiqi   = { "废墟的规矩——先验货，再谈价。", "别磨蹭，看上什么直接说。", "东西虽旧，但都管用。" },
    bai_shu    = { "书院的库存都在这了，请过目。", "以物易物也行，学问无价嘛。", "别急，慢慢挑。" },
    zhao_miao  = { "新鲜蔬果刚收的，便宜卖了。", "农场的东西实在，不掺假。", "多买点吧，路上好补给。" },
    cheng_yuan = { "哨站资源紧张，别太挑了。", "能匀出来的都在这了。", "快进快出，别耽误巡逻。" },
    a_xiu      = { "地铁营地啥都有，就是贵点~", "修车的零件也有，要不要看看？", "嘿嘿，今天有好东西到货。" },
    su_mo      = { "旧教堂的存货……将就看吧。", "安静点交易，别惊动外面。", "东西不多，但都精挑细选过。" },
}

-- 通用问候（未匹配 NPC 时的后备）
local GENERIC_GREETINGS = {
    "欢迎光临，看看需要什么。",
    "货架上的东西随便挑。",
    "今天有新到的货，要看看吗？",
}

-- 模块级状态
local _shopGreeting = nil
local _shopNpc      = nil
local _npcPortrait  = nil
local _bgImage      = nil

--- 据点服务定价
local SERVICE = {
    refuel = { unit = 10, cost = 15, label = "加油", desc = "燃料 +10" },
    repair = { unit = 10, cost = 20, label = "维修", desc = "耐久 +10" },
    rest   = { cost = 10, label = "休整", desc = "清除一项负面状态" },
}

local M = {}
---@type table
local router = nil

--- 交易所教程气泡：逐步展示并在最后设置 flag
local shopTutorialShown_ = false

function M.create(state, params, r)
    router = r
    local location = state.map.current_location
    local locName = Graph.get_node_name(location)

    -- 查找当地 NPC（每次都执行，确保 NPC 信息可用）
    local npc = NpcManager.get_npc_for_settlement(location)
    _shopNpc = npc
    _npcPortrait = get_portrait(npc and npc.id, location)

    -- 聚落背景图
    local node = Graph.get_node(location)
    _bgImage = node and node.bg or nil

    -- 首次进入时随机问候语（refresh 时保持不变）
    if not _shopGreeting then
        if npc then
            local greetings = SHOP_GREETINGS[npc.id] or GENERIC_GREETINGS
            _shopGreeting = greetings[math.random(#greetings)]
        else
            _shopGreeting = GENERIC_GREETINGS[math.random(#GENERIC_GREETINGS)]
        end
    end

    local fuelPct  = math.floor(state.truck.fuel / state.truck.fuel_max * 100 + 0.5)
    local duraPct  = math.floor(state.truck.durability / state.truck.durability_max * 100 + 0.5)
    local fuelFull = state.truck.fuel >= state.truck.fuel_max
    local duraFull = state.truck.durability >= state.truck.durability_max

    local cargoUsed = CargoUtils.get_cargo_used(state)
    local cargoFree = CargoUtils.get_cargo_free(state)
    local cargoFull = cargoFree <= 0

    -- 好感（仅用于判断休整站解锁）
    local sett = state.settlements[location]
    local gw = sett and sett.goodwill or 0

    local contentChildren = {}

    -- NPC 信息
    local npcName  = _shopNpc and _shopNpc.name or "店员"
    local npcIcon  = _shopNpc and _shopNpc.icon or "🏪"
    local npcColor = _shopNpc and _shopNpc.color or { 148, 148, 148, 255 }

    -- 标题和气泡会放到背景层上（见下方 layerChildren），不放 contentChildren

    -- ── 补给站 ──
    table.insert(contentChildren, F.card {
        padding = 12,
        gap = 8,
        children = {
            UI.Label {
                text = "补给站",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.info,
            },
            -- 燃料状态 + 加油按钮
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel { gap = 2, children = {
                        UI.Label {
                            text = "燃料  " .. math.floor(state.truck.fuel) .. " / " .. state.truck.fuel_max,
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_primary,
                        },
                        UI.ProgressBar {
                            value = state.truck.fuel / state.truck.fuel_max,
                            width = 120, height = 6,
                            variant = fuelPct < 25 and "danger" or fuelPct < 50 and "warning" or "success",
                        },
                    }},
                    F.actionBtn {
                        text = SERVICE.refuel.label .. "  $" .. SERVICE.refuel.cost,
                        variant = "primary", height = 32, width = 110,
                        disabled = fuelFull or state.economy.credits < SERVICE.refuel.cost,
                        onClick = function(self)
                            if not fuelFull and state.economy.credits >= SERVICE.refuel.cost then
                                state.economy.credits = state.economy.credits - SERVICE.refuel.cost
                                state.truck.fuel = math.min(state.truck.fuel_max, state.truck.fuel + SERVICE.refuel.unit)
                                router.refresh()
                            end
                        end,
                    },
                },
            },
            -- 耐久状态 + 维修按钮
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel { gap = 2, children = {
                        UI.Label {
                            text = "耐久  " .. math.floor(state.truck.durability) .. " / " .. state.truck.durability_max,
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_primary,
                        },
                        UI.ProgressBar {
                            value = state.truck.durability / state.truck.durability_max,
                            width = 120, height = 6,
                            variant = duraPct < 25 and "danger" or duraPct < 50 and "warning" or "success",
                        },
                    }},
                    F.actionBtn {
                        text = SERVICE.repair.label .. "  $" .. SERVICE.repair.cost,
                        variant = "primary", height = 32, width = 110,
                        disabled = duraFull or state.economy.credits < SERVICE.repair.cost,
                        onClick = function(self)
                            if not duraFull and state.economy.credits >= SERVICE.repair.cost then
                                state.economy.credits = state.economy.credits - SERVICE.repair.cost
                                state.truck.durability = math.min(state.truck.durability_max, state.truck.durability + SERVICE.repair.unit)
                                router.refresh()
                            end
                        end,
                    },
                },
            },
        },
    })

    -- ── 商品交易 ──
    table.insert(contentChildren, F.sectionTitle("商品交易"))

    for _, g in ipairs(Goods.ALL) do
        local buyP  = Pricing.get_buy_price(g.id, location, state)
        local sellP = Pricing.get_sell_price(g.id, location, state)
        local held  = state.truck.cargo[g.id] or 0
        local catInfo = Goods.CATEGORIES[g.category]
        local committed = CargoUtils.get_committed(state, g.id)
        local belowCommitted = committed > 0 and held <= committed

        -- 持有标签：含委托标注
        local heldText = "持有 " .. held
        local heldColor = held > 0 and Theme.colors.text_primary or Theme.colors.text_dim
        if committed > 0 then
            heldText = heldText .. " (委托 " .. committed .. ")"
            if belowCommitted then
                heldColor = Theme.colors.danger
            end
        end

        -- 卖出按钮：卖到低于委托量时加警告
        local sellText = "卖出"
        local sellVariant = "secondary"
        if belowCommitted then
            sellText = "⚠ 卖出"
            sellVariant = "danger"
        end

        -- 供需标签
        local sdLabel, sdColor = Pricing.get_supply_demand_label(state, location, g.id)

        -- 价格行子元素
        local priceChildren = {
            UI.Label {
                text = "买 $" .. buyP .. "  /  卖 $" .. sellP,
                fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_secondary,
            },
        }
        if sdLabel then
            table.insert(priceChildren, UI.Label {
                text = sdLabel,
                fontSize = Theme.sizes.font_tiny,
                fontColor = sdColor,
                marginLeft = 6,
            })
        end

        table.insert(contentChildren, F.card {
            padding = 12,
            gap = 6,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                            g.icon and UI.Panel {
                                width = 26, height = 26,
                                backgroundImage = g.icon,
                                backgroundFit = "contain",
                            } or nil,
                            UI.Label { text = g.name, fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_primary },
                        }},
                        UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                            UI.Label { text = catInfo.name, fontSize = Theme.sizes.font_tiny, fontColor = catInfo.color },
                        }},
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Panel { flexDirection = "row", alignItems = "center", children = priceChildren },
                        UI.Label {
                            text = heldText,
                            fontSize = Theme.sizes.font_small,
                            fontColor = heldColor,
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 4,
                    children = {
                        F.actionBtn {
                            text = cargoFull and "仓位已满" or "买入",
                            variant = "primary", flexGrow = 1, height = 34,
                            disabled = cargoFull or state.economy.credits < buyP,
                            sound = false,
                            onClick = function(self)
                                if not cargoFull and state.economy.credits >= buyP then
                                    state.economy.credits = state.economy.credits - buyP
                                    state.truck.cargo[g.id] = (state.truck.cargo[g.id] or 0) + 1
                                    Pricing.update_supply_demand(state, location, g.id, -1)
                                    SoundMgr.play("coins")
                                    router.refresh()
                                end
                            end,
                        },
                        F.actionBtn {
                            text = sellText, variant = sellVariant, flexGrow = 1, height = 34,
                            disabled = held <= 0,
                            sound = false,
                            onClick = function(self)
                                if (state.truck.cargo[g.id] or 0) > 0 then
                                    state.economy.credits = state.economy.credits + sellP
                                    state.truck.cargo[g.id] = state.truck.cargo[g.id] - 1
                                    if state.truck.cargo[g.id] <= 0 then state.truck.cargo[g.id] = nil end
                                    Pricing.update_supply_demand(state, location, g.id, 1)
                                    SoundMgr.play("coins")
                                    router.refresh()
                                end
                            end,
                        },
                    },
                },
            },
        })
    end

    -- ── 休整站（需好感 Lv2+） ──
    local restUnlocked = Goodwill.is_unlocked(gw, "rest_area")
    local allStatuses = ItemUse.get_all_statuses(state)
    local hasAnyStatus = #allStatuses > 0

    if restUnlocked then
        local restChildren = {
            UI.Label {
                text = "休整站",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.info,
            },
        }

        if hasAnyStatus then
            for _, info in ipairs(allStatuses) do
                for _, sid in ipairs(info.statuses) do
                    local sDef = ItemUse.STATUS_DEFS[sid]
                    local sName = sDef and sDef.name or sid
                    local canAfford = state.economy.credits >= SERVICE.rest.cost
                    table.insert(restChildren, UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {
                                text = info.char_name .. " · " .. sName,
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.danger,
                            },
                            F.actionBtn {
                                text = "治疗 $" .. SERVICE.rest.cost,
                                variant = "primary", height = 28, width = 100,
                                disabled = not canAfford,
                                onClick = function(self)
                                    if state.economy.credits >= SERVICE.rest.cost then
                                        state.economy.credits = state.economy.credits - SERVICE.rest.cost
                                        ItemUse.clear_status(state, info.char_id, sid)
                                        router.refresh()
                                    end
                                end,
                            },
                        },
                    })
                end
            end
        else
            table.insert(restChildren, UI.Label {
                text = "状态良好，无需休整",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            })
        end

        table.insert(contentChildren, F.card {
            padding = 12, marginTop = 4,
            gap = 8,
            children = restChildren,
        })
    end

    -- ── 模块升级 ──
    local upgradeCards = {}
    for _, mid in ipairs(Modules.ORDER) do
        local def = Modules.DEFS[mid]
        local lv = Modules.get_level(state, mid)
        local canUp, reason = Modules.can_upgrade(state, mid)
        local isMaxed = lv >= def.max_level
        local atRightPlace = def.upgrade_at[location]

        -- 只在可升级聚落或已满级时显示
        if atRightPlace or isMaxed then
            local effDesc = ""
            if lv > 0 then
                local eff = def.effects[lv]
                effDesc = eff and eff.desc or ""
            end

            local nextDesc = ""
            local costText = ""
            if not isMaxed then
                local nextEff = def.effects[lv + 1]
                nextDesc = nextEff and nextEff.desc or ""
                local cost = def.costs[lv + 1]
                if cost then
                    local parts = { "$" .. cost.credits }
                    for mat_id, need in pairs(cost.materials) do
                        local matG = Goods.get(mat_id)
                        local matName = matG and matG.name or mat_id
                        local have = state.truck.cargo[mat_id] or 0
                        local color_hint = have >= need and "" or "!"
                        table.insert(parts, matName .. color_hint .. " x" .. need)
                    end
                    costText = table.concat(parts, " + ")
                end
            end

            local cardChildren = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = def.name .. "  Lv" .. lv .. (isMaxed and " (MAX)" or ""),
                            fontSize = Theme.sizes.font_normal,
                            fontColor = isMaxed and Theme.colors.success or Theme.colors.text_primary,
                        },
                    },
                },
            }
            if lv > 0 and effDesc ~= "" then
                table.insert(cardChildren, UI.Label {
                    text = "当前: " .. effDesc,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = Theme.colors.text_dim,
                })
            end
            if not isMaxed then
                table.insert(cardChildren, UI.Label {
                    text = "升级 → " .. nextDesc,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.info,
                })
                table.insert(cardChildren, UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    marginTop = 2,
                    children = {
                        UI.Label {
                            text = costText,
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = canUp and Theme.colors.text_secondary or Theme.colors.danger,
                        },
                        F.actionBtn {
                            text = "升级",
                            variant = "primary", height = 28, width = 80,
                            disabled = not canUp,
                            sound = false,
                            onClick = function(self)
                                local ok, err = Modules.upgrade(state, mid)
                                if ok then
                                    SoundMgr.play("success")
                                    router.refresh()
                                end
                            end,
                        },
                    },
                })
                if not canUp and reason then
                    table.insert(cardChildren, UI.Label {
                        text = reason,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_dim,
                    })
                end
            end

            table.insert(upgradeCards, UI.Panel {
                width = "100%", padding = 10, gap = 4,
                backgroundColor = Theme.colors.bg_secondary,
                borderRadius = Theme.sizes.radius_small,
                children = cardChildren,
            })
        end
    end

    if #upgradeCards > 0 then
        table.insert(contentChildren, F.sectionTitle("模块升级"))
        for _, card in ipairs(upgradeCards) do
            table.insert(contentChildren, card)
        end
    end

    -- 检查是否需要显示交易所教程
    local needShopTutorial = not shopTutorialShown_
        and Tutorial.get_shop_tutorial_steps(state) ~= nil
    if needShopTutorial then
        shopTutorialShown_ = true
    end

    -- ═══════════════════════════════════════════════
    -- 分层布局：底层 背景+立绘  |  上层 内容Panel
    -- ═══════════════════════════════════════════════

    local layerChildren = {}

    -- 底层 1：背景图（全屏，与首页一致）
    if _bgImage then
        table.insert(layerChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundImage = _bgImage,
            backgroundFit = "cover",
        })
        table.insert(layerChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundColor = { 0, 0, 0, 0 },
            backgroundGradient = {
                direction = "to-bottom",
                colors = {
                    { 0, 0, 0, 0 },
                    { 0, 0, 0, 0 },
                    Theme.colors.home_gradient_mid,
                    Theme.colors.home_gradient_bot,
                },
            },
        })
    end

    -- 底层 2：标题（在立绘后面，先插入）
    local titlePanel = UI.Panel {
        backgroundColor = Theme.colors.home_overlay,
        borderRadius = Theme.sizes.radius,
        padding = 10, gap = 4,
        flexDirection = "row", alignItems = "center", gap = 6,
        children = {
            UI.Label { text = npcIcon, fontSize = 20 },
            UI.Label {
                text = npcName .. " · " .. locName .. " 交易所",
                fontSize = Theme.sizes.font_large,
                fontColor = Theme.colors.home_title,
            },
        },
    }
    SketchBorder.register(titlePanel, "card")
    table.insert(layerChildren, UI.Panel {
        position = "absolute", left = 12, top = 8, right = 12,
        children = { titlePanel },
    })

    -- 底层 3+4：全屏容器（立绘+气泡，参考 gal_dialogue 布局）
    table.insert(layerChildren, UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", left = 0, top = 0,
        children = {
            -- 右侧立绘（left=27% 等效于 right=-22%，规避 UI 库负百分比解析问题）
            _npcPortrait and UI.Panel {
                width = "95%", height = "95%",
                position = "absolute", left = "27%", top = "3%",
                backgroundImage = _npcPortrait,
                backgroundFit = "contain",
            } or nil,
            -- 左侧气泡
            UI.Panel {
                position = "absolute", left = "3%", top = "18%",
                maxWidth = "40%",
                backgroundColor = { 245, 240, 228, 230 },
                padding = 10, paddingLeft = 14, paddingRight = 14,
                borderRadius = Theme.sizes.radius,
                boxShadow = {
                    { x = 0, y = 2, blur = 10, spread = 2, color = { 0, 0, 0, 80 } },
                },
                children = {
                    UI.Label {
                        text = "「" .. (_shopGreeting or GENERIC_GREETINGS[1]) .. "」",
                        fontSize = Theme.sizes.font_normal,
                        fontColor = { 50, 45, 38, 230 },
                        lineHeight = 1.4,
                    },
                },
            },
        },
    })

    -- 上层：外层 Panel 负责背景图（不滚动，保证 backgroundImage 生效）
    -- overflow="scroll" 会将 Panel 升级为 ScrollView，而 ScrollView 不支持 backgroundImage
    local contentPanel = UI.Panel {
        width = "100%",
        height = "65%",
        overflow = "hidden",
        backgroundColor = Theme.colors.home_lower_tint,
        backgroundImage = Theme.textures.notebook_bg,
        backgroundFit = "cover",
        borderRadius = Theme.sizes.radius_large,
        borderRadiusBottomLeft = 0, borderRadiusBottomRight = 0,
        children = {
            UI.ScrollView {
                width = "100%",
                flexGrow = 1, flexBasis = 0,
                padding = Theme.sizes.padding, gap = 10,
                paddingBottom = 40,
                children = contentChildren,
            },
        },
    }
    SketchBorder.register(contentPanel, "card")

    table.insert(layerChildren, UI.Panel {
        width = "100%", height = "100%",
        paddingTop = _bgImage and "38%" or 0,
        justifyContent = "flex-end",
        children = { contentPanel },
    })

    local rootPanel = UI.Panel {
        id = "shopScreen",
        width = "100%", height = "100%",
        children = layerChildren,
    }

    -- 教程气泡：在 create 阶段排入，由 update 首帧触发
    M._pendingTutorial = needShopTutorial and state or nil
    M._rootPanel = rootPanel

    return rootPanel
end

--- 逐步展示教程气泡序列
local function showTutorialStep(parent, state, steps, index)
    if index > #steps then
        -- 全部播完，设置 flag
        Flags.set(state, "tutorial_shop_intro")
        return
    end
    local step = steps[index]
    SpeechBubble.show(parent, {
        portrait = step.portrait,
        speaker  = step.speaker,
        text     = step.text,
        autoHide = 0,
        onDismiss = function()
            showTutorialStep(parent, state, steps, index + 1)
        end,
    })
end

function M.update(state, dt, r)
    SpeechBubble.update(dt)

    -- 首帧触发教程气泡序列
    if M._pendingTutorial and M._rootPanel then
        local tutState = M._pendingTutorial
        M._pendingTutorial = nil
        local steps = Tutorial.get_shop_tutorial_steps(tutState)
        if steps then
            showTutorialStep(M._rootPanel, tutState, steps, 1)
        end
    end
end

return M

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

    local fuelPct  = math.floor(state.truck.fuel / state.truck.fuel_max * 100 + 0.5)
    local duraPct  = math.floor(state.truck.durability / state.truck.durability_max * 100 + 0.5)
    local fuelFull = state.truck.fuel >= state.truck.fuel_max
    local duraFull = state.truck.durability >= state.truck.durability_max

    local cargoUsed = CargoUtils.get_cargo_used(state)
    local cargoFree = CargoUtils.get_cargo_free(state)
    local cargoFull = cargoFree <= 0

    -- 好感信息
    local sett = state.settlements[location]
    local gw = sett and sett.goodwill or 0
    local gwInfo = Goodwill.get_info(gw)

    local contentChildren = {
        UI.Label {
            text = locName .. " · 交易所",
            fontSize = Theme.sizes.font_title,
            fontColor = Theme.colors.text_primary,
        },
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 2,
            children = {
                UI.Label {
                    text = "持有  $ " .. tostring(state.economy.credits),
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.accent,
                },
                UI.Label {
                    text = "仓位 " .. cargoUsed .. "/" .. state.truck.cargo_slots,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = cargoFull and Theme.colors.danger or Theme.colors.text_secondary,
                },
            },
        },
        -- 好感度
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Label {
                    text = "好感: " .. gwInfo.name .. " (Lv" .. gwInfo.level .. ")",
                    fontSize = Theme.sizes.font_small,
                    fontColor = gwInfo.level >= 2 and Theme.colors.success
                        or gwInfo.level >= 1 and Theme.colors.info
                        or Theme.colors.text_dim,
                },
                UI.Label {
                    text = gwInfo.next_threshold
                        and (math.floor(gw) .. " / " .. gwInfo.next_threshold)
                        or (math.floor(gw) .. " (MAX)"),
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                },
            },
        },

        -- ── 补给站 ──
        UI.Panel {
            width = "100%", padding = 12,
            backgroundColor = Theme.colors.bg_card,
            borderRadius = Theme.sizes.radius,
            borderWidth = Theme.sizes.border,
            borderColor = Theme.colors.border,
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
                        UI.Button {
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
                        UI.Button {
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
        },

        -- ── 分隔 ──
        UI.Label {
            text = "商品交易",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            marginTop = 4,
        },
    }

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

        table.insert(contentChildren, UI.Panel {
            width = "100%",
            padding = 12,
            backgroundColor = Theme.colors.bg_card,
            borderRadius = Theme.sizes.radius,
            borderWidth = Theme.sizes.border,
            borderColor = Theme.colors.border,
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
                        UI.Button {
                            text = cargoFull and "仓位已满" or "买入",
                            variant = "primary", flexGrow = 1, height = 34,
                            disabled = cargoFull or state.economy.credits < buyP,
                            onClick = function(self)
                                if not cargoFull and state.economy.credits >= buyP then
                                    state.economy.credits = state.economy.credits - buyP
                                    state.truck.cargo[g.id] = (state.truck.cargo[g.id] or 0) + 1
                                    Pricing.update_supply_demand(state, location, g.id, -1)
                                    router.refresh()
                                end
                            end,
                        },
                        UI.Button {
                            text = sellText, variant = sellVariant, flexGrow = 1, height = 34,
                            disabled = held <= 0,
                            onClick = function(self)
                                if (state.truck.cargo[g.id] or 0) > 0 then
                                    state.economy.credits = state.economy.credits + sellP
                                    state.truck.cargo[g.id] = state.truck.cargo[g.id] - 1
                                    if state.truck.cargo[g.id] <= 0 then state.truck.cargo[g.id] = nil end
                                    Pricing.update_supply_demand(state, location, g.id, 1)
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
                            UI.Button {
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

        table.insert(contentChildren, UI.Panel {
            width = "100%", padding = 12, marginTop = 4,
            backgroundColor = Theme.colors.bg_card,
            borderRadius = Theme.sizes.radius,
            borderWidth = Theme.sizes.border,
            borderColor = Theme.colors.border,
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
                        UI.Button {
                            text = "升级",
                            variant = "primary", height = 28, width = 80,
                            disabled = not canUp,
                            onClick = function(self)
                                local ok, err = Modules.upgrade(state, mid)
                                if ok then router.refresh() end
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
        table.insert(contentChildren, UI.Label {
            text = "模块升级",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            marginTop = 4,
        })
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

    local rootPanel = UI.Panel {
        id = "shopScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = contentChildren,
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

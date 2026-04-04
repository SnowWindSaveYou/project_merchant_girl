--- 聚落交易所
--- 在当前聚落买卖商品 + 补给维修服务
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Goods = require("economy/goods")
local Pricing = require("economy/pricing")
local Graph = require("map/world_graph")

--- 据点服务定价
local SERVICE = {
    refuel = { unit = 10, cost = 15, label = "加油", desc = "燃料 +10" },
    repair = { unit = 10, cost = 20, label = "维修", desc = "耐久 +10" },
}

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local location = state.map.current_location
    local locName = Graph.get_node_name(location)

    local fuelPct  = math.floor(state.truck.fuel / state.truck.fuel_max * 100 + 0.5)
    local duraPct  = math.floor(state.truck.durability / state.truck.durability_max * 100 + 0.5)
    local fuelFull = state.truck.fuel >= state.truck.fuel_max
    local duraFull = state.truck.durability >= state.truck.durability_max

    local contentChildren = {
        UI.Label {
            text = locName .. " · 交易所",
            fontSize = Theme.sizes.font_title,
            fontColor = Theme.colors.text_primary,
        },
        UI.Label {
            text = "持有  $ " .. tostring(state.economy.credits),
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.accent,
            marginBottom = 4,
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
                                    router.navigate("shop")
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
                                    router.navigate("shop")
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
        local buyP  = Pricing.get_buy_price(g.id, location)
        local sellP = Pricing.get_sell_price(g.id, location)
        local held  = state.truck.cargo[g.id] or 0
        local catInfo = Goods.CATEGORIES[g.category]

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
                        UI.Label { text = g.name, fontSize = Theme.sizes.font_normal, fontColor = Theme.colors.text_primary },
                        UI.Label { text = catInfo.name, fontSize = Theme.sizes.font_tiny, fontColor = catInfo.color },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = "买 $" .. buyP .. "  /  卖 $" .. sellP,
                            fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_secondary,
                        },
                        UI.Label {
                            text = "持有 " .. held,
                            fontSize = Theme.sizes.font_small,
                            fontColor = held > 0 and Theme.colors.text_primary or Theme.colors.text_dim,
                        },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", gap = 8, marginTop = 4,
                    children = {
                        UI.Button {
                            text = "买入", variant = "primary", flexGrow = 1, height = 34,
                            disabled = state.economy.credits < buyP,
                            onClick = function(self)
                                if state.economy.credits >= buyP then
                                    state.economy.credits = state.economy.credits - buyP
                                    state.truck.cargo[g.id] = (state.truck.cargo[g.id] or 0) + 1
                                    router.navigate("shop")
                                end
                            end,
                        },
                        UI.Button {
                            text = "卖出", variant = "secondary", flexGrow = 1, height = 34,
                            disabled = held <= 0,
                            onClick = function(self)
                                if (state.truck.cargo[g.id] or 0) > 0 then
                                    state.economy.credits = state.economy.credits + sellP
                                    state.truck.cargo[g.id] = state.truck.cargo[g.id] - 1
                                    if state.truck.cargo[g.id] <= 0 then state.truck.cargo[g.id] = nil end
                                    router.navigate("shop")
                                end
                            end,
                        },
                    },
                },
            },
        })
    end

    return UI.Panel {
        id = "shopScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = contentChildren,
    }
end

function M.update(state, dt, r) end

return M

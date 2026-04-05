--- 货舱页面
--- 显示货车容量、货物列表、空状态、物品使用
local UI         = require("urhox-libs/UI")
local Theme      = require("ui/theme")
local Goods      = require("economy/goods")
local ItemUse    = require("economy/item_use")
local CargoUtils = require("economy/cargo_utils")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local cargo = state.truck.cargo
    local slots = state.truck.cargo_slots

    -- 计算货物总量
    local totalUsed = CargoUtils.get_cargo_used(state)
    local totalCommitted = CargoUtils.get_total_committed(state)
    local hasShortage = CargoUtils.has_any_shortage(state)
    local itemList = {}
    for gid, count in pairs(cargo) do
        if count > 0 then
            local g = Goods.get(gid)
            local committed = CargoUtils.get_committed(state, gid)
            table.insert(itemList, {
                id        = gid,
                name      = g and g.name or gid,
                count     = count,
                cat       = g and g.category or "unknown",
                committed = committed,
                shortage  = committed > 0 and count < committed,
            })
        end
    end

    -- 按名称排序
    table.sort(itemList, function(a, b) return a.name < b.name end)

    local usageRatio = totalUsed / math.max(slots, 1)
    local barColor = usageRatio > 0.9 and Theme.colors.danger
        or usageRatio > 0.6 and Theme.colors.warning
        or Theme.colors.success

    local children = {}

    -- 容量卡片
    table.insert(children, UI.Panel {
        width = "100%", padding = 14,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        gap = 8,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "货舱容量",
                        fontSize = Theme.sizes.font_large,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = totalUsed .. " / " .. slots,
                        fontSize = Theme.sizes.font_large,
                        fontColor = barColor,
                    },
                },
            },
            UI.ProgressBar {
                value = usageRatio,
                width = "100%", height = 10,
                variant = usageRatio > 0.9 and "danger"
                    or usageRatio > 0.6 and "warning"
                    or "success",
            },
        },
    })

    -- 委托货物短缺警告
    if hasShortage then
        table.insert(children, UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = { 72, 28, 28, 220 },
            borderRadius = Theme.sizes.radius,
            borderWidth = 1, borderColor = Theme.colors.danger,
            flexDirection = "row", alignItems = "center", gap = 8,
            children = {
                UI.Label {
                    text = "⚠ 委托货物不足！部分订单将无法全额交付",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.danger,
                    flexShrink = 1,
                },
            },
        })
    elseif totalCommitted > 0 then
        table.insert(children, UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = { 40, 45, 55, 200 },
            borderRadius = Theme.sizes.radius,
            borderWidth = 1, borderColor = Theme.colors.info,
            children = {
                UI.Label {
                    text = "委托货物 " .. totalCommitted .. " 件 — 使用前请注意保留",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.info,
                },
            },
        })
    end

    -- 货物列表 / 空状态
    if #itemList == 0 then
        table.insert(children, UI.Panel {
            width = "100%", padding = 40,
            alignItems = "center", gap = 8,
            children = {
                UI.Label {
                    text = "📦",
                    fontSize = 40,
                    textAlign = "center",
                },
                UI.Label {
                    text = "货舱为空",
                    fontSize = Theme.sizes.font_large,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
                UI.Label {
                    text = "前往聚落交易所购买货物",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
            },
        })
    else
        table.insert(children, UI.Label {
            text = "货物清单",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            marginTop = 4,
        })

        for _, item in ipairs(itemList) do
            local catInfo = Goods.CATEGORIES and Goods.CATEGORIES[item.cat]
            local catName  = catInfo and catInfo.name or ""
            local catColor = catInfo and catInfo.color or Theme.colors.text_dim
            local useInfo  = ItemUse.get_info(item.id)

            -- 数量标签：含委托提示
            local countText = "×" .. item.count
            local countColor = Theme.colors.accent
            if item.committed > 0 then
                countText = countText .. " (委托 " .. item.committed .. ")"
                if item.shortage then
                    countColor = Theme.colors.danger
                end
            end

            local rightChildren = {
                UI.Label {
                    text = countText,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = countColor,
                },
            }

            if useInfo then
                -- 使用按钮：低于委托量时加警示文字
                local btnText = useInfo.action_name
                if item.shortage then
                    btnText = "⚠ " .. btnText
                end
                table.insert(rightChildren, UI.Button {
                    text = btnText,
                    variant = item.shortage and "danger" or "secondary",
                    height = 28, width = 80,
                    onClick = function(self)
                        local ok, msg = ItemUse.use(state, item.id)
                        if ok then
                            print("[Cargo] " .. msg)
                        else
                            print("[Cargo] 无法使用: " .. msg)
                        end
                        router.refresh()
                    end,
                })
            end

            -- 物品名行
            local nameChildren = {
                UI.Label {
                    text = item.name,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = item.shortage and Theme.colors.danger or Theme.colors.text_primary,
                },
            }
            if catName ~= "" then
                table.insert(nameChildren, UI.Label {
                    text = catName,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = catColor,
                })
            end
            if useInfo then
                table.insert(nameChildren, UI.Label {
                    text = useInfo.desc,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = Theme.colors.text_dim,
                })
            end

            local itemChildren = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, flexShrink = 1,
                    children = nameChildren,
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8,
                    children = rightChildren,
                },
            }

            -- 短缺物品加红色左边框
            local cardBorder = Theme.sizes.border
            local cardBorderColor = Theme.colors.border
            if item.shortage then
                cardBorder = 2
                cardBorderColor = Theme.colors.danger
            end

            table.insert(children, UI.Panel {
                width = "100%", padding = 12,
                backgroundColor = Theme.colors.bg_card,
                borderRadius = Theme.sizes.radius_small,
                borderWidth = cardBorder,
                borderColor = cardBorderColor,
                flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = itemChildren,
            })
        end
    end

    return UI.Panel {
        id = "cargoScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = children,
    }
end

function M.update(state, dt, r) end

return M

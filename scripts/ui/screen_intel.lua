--- 北穹塔台·情报交换站页面
--- 展示路况数据余额、可交换情报、已获情报
local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F     = require("ui/ui_factory")
local Intel = require("settlement/intel")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r

    local exchanged, dataPoints = Intel.get_stats(state)
    local available = Intel.get_available_types(state)
    local activeIntel = Intel.get_active_intel(state)

    local children = {}

    -- ── 标题栏 ──
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "📡 情报交换站",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = "数据: " .. dataPoints .. " 点",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.info,
            },
        },
    })

    -- ── 说明 ──
    table.insert(children, UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = Theme.colors.bg_intel_hint,
        borderRadius = Theme.sizes.radius,
        children = {
            UI.Label {
                text = "每次跑商自动收集路况数据。用数据点在塔台交换情报。",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            },
        },
    })

    -- ── 可交换情报 ──
    if #available > 0 then
        table.insert(children, UI.Label {
            text = "可交换情报",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.info,
            marginTop = 4,
        })
        for _, info in ipairs(available) do
            local canBuy = info.available
            table.insert(children, F.card {
                width = "100%", padding = 10,
                borderWidth = 1, borderColor = canBuy and Theme.colors.info or Theme.colors.border,
                gap = 4,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {
                                text = info.name,
                                fontSize = Theme.sizes.font_normal,
                                fontColor = Theme.colors.text_primary,
                            },
                            UI.Label {
                                text = info.cost .. " 数据点",
                                fontSize = Theme.sizes.font_small,
                                fontColor = canBuy and Theme.colors.info or Theme.colors.text_dim,
                            },
                        },
                    },
                    UI.Label {
                        text = info.desc,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_secondary,
                    },
                    F.actionBtn {
                        text = canBuy and "交换" or "数据不足",
                        variant = canBuy and "primary" or "secondary",
                        disabled = not canBuy,
                        height = 32,
                        fontSize = Theme.sizes.font_small,
                        onClick = function(self)
                            if not canBuy then return end
                            local ok, text = Intel.exchange(state, info.id)
                            if ok then
                                print("[Intel] Exchanged: " .. info.name .. " -> " .. text)
                            end
                            router.navigate("intel")
                        end,
                    },
                },
            })
        end
    else
        table.insert(children, UI.Panel {
            width = "100%", padding = 16,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "提升塔台好感以解锁情报交换",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
            },
        })
    end

    -- ── 已获情报 ──
    if #activeIntel > 0 then
        table.insert(children, UI.Label {
            text = "当前情报",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.success,
            marginTop = 8,
        })
        for _, info in ipairs(activeIntel) do
            table.insert(children, UI.Panel {
                width = "100%", padding = 8,
                backgroundColor = Theme.colors.bg_intel_active,
                borderRadius = Theme.sizes.radius_small,
                gap = 2,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {
                                text = info.name,
                                fontSize = Theme.sizes.font_small,
                                fontColor = Theme.colors.info,
                            },
                            UI.Label {
                                text = "剩余 " .. info.trips_left .. " 趟",
                                fontSize = Theme.sizes.font_tiny,
                                fontColor = Theme.colors.text_dim,
                            },
                        },
                    },
                    UI.Label {
                        text = info.desc_text,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_primary,
                    },
                },
            })
        end
    end

    -- ── 统计 ──
    if exchanged > 0 then
        table.insert(children, UI.Label {
            text = "累计交换 " .. exchanged .. " 次",
            fontSize = Theme.sizes.font_tiny,
            fontColor = Theme.colors.text_dim,
            marginTop = 8,
            textAlign = "center",
        })
    end

    return UI.Panel {
        id = "intelScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 8,
        overflow = "scroll",
        children = children,
    }
end

function M.update(state, dt, r) end

return M

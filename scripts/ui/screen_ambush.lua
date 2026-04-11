--- 车载迎击 UI
--- FTL 式战术选择界面：威胁条 + 逃脱进度 + 4个战术按钮
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local Ambush       = require("combat/ambush")
local CombatResult = require("combat/combat_result")
local Config       = require("combat/combat_config")

--- 地形 → 路途背景映射（战斗发生在行驶中）
local REGION_BG = {
    urban  = "image/bg_generic_ruins_industrial_20260409080003.png",
    wild   = "image/bg_generic_road_20260409075956.png",
    canyon = "image/bg_generic_wilderness_20260409080002.png",
    forest = "image/bg_generic_wilderness_20260409080002.png",
}

--- 威胁等级 → 战况场景图
local THREAT_SCENE = {
    low  = "image/battle_scene_low_20260411061159.png",
    mid  = "image/battle_scene_mid_20260411061210.png",
    high = "image/battle_scene_high_20260411061202.png",
}

--- 战术 → 动作画面图
local TACTIC_SCENE = {
    accelerate = "image/battle_act_accelerate_20260411061410.png",
    steady     = "image/battle_act_fire_20260411061400.png",
    evade      = "image/battle_act_evade_20260411061331.png",
    smoke      = "image/battle_act_smoke_20260411061340.png",
}

local M = {}
---@type table
local router = nil
---@type table
local combat = nil
---@type string|nil
local bgImage_ = nil

-- ============================================================
-- 页面创建
-- ============================================================

function M.create(state, params, r)
    router = r
    local enemy_id = params and params.enemy_id or "ambush_light"

    -- 解析路途背景
    local region = state.flow and state.flow.environment and state.flow.environment.region or "wild"
    bgImage_ = REGION_BG[region] or REGION_BG.wild

    combat = Ambush.create(state, enemy_id)

    return M._build_intro_view(state)
end

-- ============================================================
-- INTRO 视图：遭遇描述
-- ============================================================

function M._build_intro_view(state)
    local enemy = combat.enemy

    return F.overlay {
        id = "ambushScreen",
        backgroundImage = bgImage_,
        contentWidth = "90%",
        children = {
            F.card {
                maxWidth = 420,
                padding = Theme.sizes.padding_large,
                borderWidth = 2, borderColor = Theme.colors.danger,
                gap = 16, alignItems = "center",
                enterAnim = true,
                children = {
                    UI.Label {
                        text = "⚠️ 遭遇袭击",
                        fontSize = Theme.sizes.font_title,
                        fontColor = Theme.colors.danger,
                    },
                    UI.Label {
                        text = enemy.name,
                        fontSize = Theme.sizes.font_large,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = enemy.desc,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_secondary,
                        textAlign = "center", lineHeight = 1.5,
                    },
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = Theme.colors.divider,
                    },
                    -- 资源预览
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-around",
                        children = {
                            M._info_chip("🛡", "耐久", state.truck.durability .. "%"),
                            M._info_chip("⛽", "燃料", state.truck.fuel .. "%"),
                            M._info_chip("🔫", "弹药", tostring(combat.ammo_available)),
                            M._info_chip("💨", "烟雾弹", tostring(combat.smoke_available)),
                        },
                    },
                    F.actionBtn {
                        text = "迎战！",
                        variant = "primary",
                        height = 48,
                        onClick = function(self)
                            Ambush.start_combat(combat)
                            M._refresh_combat_view(state)
                        end,
                    },
                },
            },
        },
    }
end

-- ============================================================
-- ACTIVE 视图：战术选择
-- ============================================================

function M._refresh_combat_view(state)
    local root = M._build_combat_view(state)
    UI.SetRoot(root)
end

function M._build_combat_view(state)
    local enemy = combat.enemy
    local escapePct = math.min(1.0, combat.escape_progress / combat.escape_threshold)
    local threatPct = math.min(1.0, combat.threat / 100)

    local children = {}

    -- 战斗画面：优先显示上一回合战术动作图，否则按威胁等级显示
    local sceneImg
    if combat.last_round and combat.last_round.tactic_id then
        sceneImg = TACTIC_SCENE[combat.last_round.tactic_id]
    end
    if not sceneImg then
        local level = combat.threat >= 60 and "high" or (combat.threat >= 30 and "mid" or "low")
        sceneImg = THREAT_SCENE[level]
    end
    if sceneImg then
        table.insert(children, UI.Panel {
            width = "100%", height = 140,
            borderRadius = Theme.sizes.radius_small,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = "100%", height = "100%",
                    backgroundImage = sceneImg,
                    backgroundFit = "cover",
                },
                -- 底部渐变遮罩，让图片与下方内容自然过渡
                UI.Panel {
                    width = "100%", height = 40,
                    position = "absolute", left = 0, bottom = 0,
                    backgroundGradient = {
                        direction = "to-bottom",
                        stops = { { 0, 0, 0, 0 }, { 0, 0, 0, 180 } },
                    },
                },
                -- 标题栏叠加在画面上
                UI.Panel {
                    width = "100%",
                    position = "absolute", left = 0, bottom = 0,
                    paddingLeft = 10, paddingRight = 10, paddingBottom = 6,
                    flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = "⚔️ " .. enemy.name,
                            fontSize = Theme.sizes.font_large,
                            fontColor = Theme.colors.text_primary,
                        },
                        UI.Label {
                            text = "回合 " .. combat.round_current .. "/" .. combat.rounds_total,
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.text_secondary,
                        },
                    },
                },
            },
        })
    end

    -- 威胁条
    table.insert(children, M._status_bar("敌方威胁", threatPct,
        Theme.colors.danger, math.floor(combat.threat) .. "%"))

    -- 逃脱进度条
    table.insert(children, M._status_bar("脱离进度", escapePct,
        Theme.colors.success, math.floor(escapePct * 100) .. "%"))

    -- 货车耐久条
    local durPct = state.truck.durability / state.truck.durability_max
    table.insert(children, M._status_bar("货车耐久", durPct,
        durPct > 0.3 and Theme.colors.info or Theme.colors.danger,
        state.truck.durability .. "/" .. state.truck.durability_max))

    -- 上一回合叙事
    if combat.last_round then
        table.insert(children, UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = { 30, 28, 25, 200 },
            borderRadius = Theme.sizes.radius_small,
            children = {
                UI.Label {
                    text = combat.last_round.narration,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                    lineHeight = 1.4,
                },
            },
        })
    end

    -- 分隔
    table.insert(children, UI.Panel {
        width = "100%", height = 1, backgroundColor = Theme.colors.divider,
    })

    -- 战术按钮
    local tactics = Ambush.get_available_tactics(combat)
    for _, t in ipairs(tactics) do
        local label = t.tactic.icon .. " " .. t.tactic.name
        if t.reason then
            label = label .. "（" .. t.reason .. "）"
        end

        local tacticId = t.id
        table.insert(children, F.actionBtn {
            text = label,
            variant = t.available and "secondary" or "outline",
            height = 42,
            fontSize = Theme.sizes.font_normal,
            disabled = not t.available,
            onClick = function(self)
                if not t.available then return end
                if combat.phase ~= Ambush.Phase.ACTIVE then return end

                local result = Ambush.execute_round(state, combat, tacticId)

                if result.finished then
                    M._show_result_view(state)
                else
                    M._refresh_combat_view(state)
                end
            end,
        })
    end

    -- 资源提示
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-around", marginTop = 4,
        children = {
            M._mini_chip("🔫 " .. combat.ammo_available),
            M._mini_chip("💨 " .. combat.smoke_available),
            M._mini_chip("⛽ " .. state.truck.fuel),
        },
    })

    -- 背景图 + 遮罩 + 内容的三层结构
    local layers = {}
    if bgImage_ then
        table.insert(layers, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundImage = bgImage_,
            backgroundFit = "cover",
        })
        table.insert(layers, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundColor = { 0, 0, 0, 160 },
        })
    end
    table.insert(layers, UI.Panel {
        width = "100%", height = "100%",
        padding = Theme.sizes.padding,
        gap = 10,
        overflow = "scroll",
        children = children,
    })

    return UI.Panel {
        id = "ambushScreen",
        width = "100%", height = "100%",
        backgroundColor = bgImage_ and { 0, 0, 0, 255 } or { 20, 15, 12, 255 },
        children = layers,
    }
end

-- ============================================================
-- RESULT 视图：战斗结果
-- ============================================================

function M._show_result_view(state)
    local summary = CombatResult.finalize_ambush(state, combat)

    local resultColor = summary.outcome == "repelled" and Theme.colors.success
        or summary.outcome == "escaped" and Theme.colors.info
        or Theme.colors.danger

    local lineWidgets = {}
    for _, line in ipairs(summary.lines) do
        table.insert(lineWidgets, UI.Label {
            text = line,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            lineHeight = 1.4,
        })
    end

    -- 战斗回顾（逐回合记录）
    local reviewWidgets = {}
    if combat.round_log and #combat.round_log > 0 then
        table.insert(reviewWidgets, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Theme.colors.divider, marginTop = 4,
        })
        table.insert(reviewWidgets, UI.Label {
            text = "📋 战斗回顾",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_dim,
        })
        for i, round in ipairs(combat.round_log) do
            table.insert(reviewWidgets, UI.Panel {
                width = "100%", padding = 6,
                backgroundColor = { 30, 28, 25, 180 },
                borderRadius = Theme.sizes.radius_small,
                children = {
                    UI.Label {
                        text = "第" .. i .. "回合 — " .. round.tactic_name,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_dim,
                    },
                    UI.Label {
                        text = round.narration,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                        lineHeight = 1.3,
                    },
                },
            })
        end
    end

    -- 合并内容子组件
    local cardChildren = {
        UI.Label {
            text = summary.title,
            fontSize = Theme.sizes.font_title,
            fontColor = resultColor,
        },
        UI.Panel {
            width = "100%", gap = 6,
            children = lineWidgets,
        },
    }
    for _, w in ipairs(reviewWidgets) do
        table.insert(cardChildren, w)
    end
    table.insert(cardChildren, F.actionBtn {
        text = "继续",
        variant = "primary",
        height = 48, marginTop = 8,
        onClick = function(self)
            router.navigate("home")
        end,
    })

    local root = F.overlay {
        id = "ambushScreen",
        backgroundImage = bgImage_,
        contentWidth = "90%",
        children = {
            F.card {
                maxWidth = 420,
                padding = Theme.sizes.padding_large,
                borderWidth = 2, borderColor = resultColor,
                gap = 12, alignItems = "center",
                enterAnim = true,
                children = cardChildren,
            },
        },
    }
    UI.SetRoot(root)
end

-- ============================================================
-- 辅助 UI 组件
-- ============================================================

function M._info_chip(icon, label, value)
    return UI.Panel {
        alignItems = "center", gap = 2,
        children = {
            UI.Label { text = icon, fontSize = 18 },
            UI.Label { text = label, fontSize = Theme.sizes.font_tiny, fontColor = Theme.colors.text_dim },
            UI.Label { text = value, fontSize = Theme.sizes.font_small, fontColor = Theme.colors.text_primary },
        },
    }
end

function M._mini_chip(text)
    return UI.Label {
        text = text,
        fontSize = Theme.sizes.font_tiny,
        fontColor = Theme.colors.text_dim,
    }
end

function M._status_bar(label, pct, color, valueText)
    return UI.Panel {
        width = "100%", gap = 3,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = label,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = valueText,
                        fontSize = Theme.sizes.font_small,
                        fontColor = color,
                    },
                },
            },
            UI.Panel {
                width = "100%", height = 8,
                backgroundColor = Theme.colors.progress_bg,
                borderRadius = 4,
                children = {
                    UI.Panel {
                        width = math.floor(math.max(0, math.min(1, pct)) * 100) .. "%",
                        height = "100%",
                        backgroundColor = color,
                        borderRadius = 4,
                    },
                },
            },
        },
    }
end

function M.update(state, dt, r) end

return M

--- 资源点探索 UI
--- 显示房间描述、搜刮点列表、战斗交互、撤离
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local Explore      = require("combat/explore")
local CombatResult = require("combat/combat_result")
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local Flags        = require("core/flags")

--- 地形 → 路途背景映射（探索发生在行驶途中）
local REGION_BG = {
    urban  = "image/bg_generic_ruins_industrial_20260409080003.png",
    wild   = "image/bg_generic_road_20260409075956.png",
    canyon = "image/bg_generic_wilderness_20260409080002.png",
    forest = "image/bg_generic_wilderness_20260409080002.png",
}

local M = {}
---@type table
local router = nil
---@type table
local explore = nil
---@type string
local lastNarration = ""
---@type table|nil
local state_ = nil
---@type string|nil
local bgImage_ = nil

-- ============================================================
-- 气泡教程辅助
-- ============================================================

local function showExploreTutorialStep(parent, state, steps, index, onComplete)
    if index > #steps then
        Flags.set(state, "tutorial_explore_scavenge")
        if onComplete then onComplete() end
        return
    end
    local step = steps[index]
    SpeechBubble.show(parent, {
        portrait  = step.portrait,
        speaker   = step.speaker,
        text      = step.text,
        autoHide  = 0,
        onDismiss = function()
            showExploreTutorialStep(parent, state, steps, index + 1, onComplete)
        end,
    })
end

-- ============================================================
-- 页面创建
-- ============================================================

function M.create(state, params, r)
    router = r
    state_ = state
    local room_id = params and params.room_id or nil

    -- 解析路途背景
    local region = state.flow and state.flow.environment and state.flow.environment.region or "wild"
    bgImage_ = REGION_BG[region] or REGION_BG.wild

    explore = Explore.create(state, room_id)
    lastNarration = ""

    return M._build_intro_view(state)
end

-- ============================================================
-- INTRO 视图
-- ============================================================

function M._build_intro_view(state)
    local room = explore.room

    return F.overlay {
        id = "exploreScreen",
        backgroundImage = bgImage_,
        contentWidth = "90%",
        children = {
            F.card {
                maxWidth = 420,
                padding = Theme.sizes.padding_large,
                borderWidth = 2, borderColor = Theme.colors.warning,
                gap = 16, alignItems = "center",
                enterAnim = true,
                children = {
                    UI.Label {
                        text = "🔍 发现资源点",
                        fontSize = Theme.sizes.font_title,
                        fontColor = Theme.colors.warning,
                    },
                    UI.Label {
                        text = room.name,
                        fontSize = Theme.sizes.font_large,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = room.desc,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_secondary,
                        textAlign = "center", lineHeight = 1.5,
                    },
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = Theme.colors.divider,
                    },
                    -- 搜刮点预告
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-around",
                        children = {
                            M._info_chip("📦", "搜刮点", tostring(#explore.crates)),
                            M._info_chip("⚠️", "危险度", M._danger_text()),
                            M._info_chip("🔫", "弹药", tostring(explore.ammo_available)),
                        },
                    },
                    UI.Panel {
                        width = "100%", flexDirection = "row", gap = 10,
                        children = {
                            F.actionBtn {
                                text = "进入探索",
                                variant = "primary",
                                flexGrow = 1, height = 48,
                                onClick = function(self)
                                    Explore.start_explore(explore)
                                    M._refresh(state)

                                    -- 首次搜刮教程气泡
                                    local introSteps = Tutorial.get_explore_intro_steps(state)
                                    if introSteps then
                                        local root = UI.GetRoot()
                                        if root then
                                            showExploreTutorialStep(root, state, introSteps, 1)
                                        end
                                    end
                                end,
                            },
                            F.actionBtn {
                                text = "离开",
                                variant = "outline",
                                width = 80, height = 48,
                                onClick = function(self)
                                    router.navigate("home")
                                end,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================
-- 探索主视图（搜刮 + 行动）
-- ============================================================

function M._refresh(state)
    if explore.phase == Explore.Phase.RESULT then
        M._show_result_view(state)
        return
    end

    local root = M._build_explore_view(state)
    UI.SetRoot(root)
end

function M._build_explore_view(state)
    local children = {}

    -- 标题
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "🔍 " .. explore.room.name,
                fontSize = Theme.sizes.font_large,
                fontColor = Theme.colors.warning,
            },
            UI.Label {
                text = "体力 " .. math.max(0, explore.player_hp) .. "/" .. explore.player_hp_max,
                fontSize = Theme.sizes.font_small,
                fontColor = explore.player_hp > 20 and Theme.colors.success or Theme.colors.danger,
            },
        },
    })

    -- 体力条
    local hpPct = math.max(0, explore.player_hp / explore.player_hp_max)
    table.insert(children, UI.Panel {
        width = "100%", height = 6,
        backgroundColor = Theme.colors.progress_bg, borderRadius = 3,
        children = {
            UI.Panel {
                width = math.floor(hpPct * 100) .. "%", height = "100%",
                backgroundColor = hpPct > 0.4 and Theme.colors.success or Theme.colors.danger,
                borderRadius = 3,
            },
        },
    })

    -- 搜刮点状态
    table.insert(children, UI.Label {
        text = "搜刮点",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.text_secondary,
        marginTop = 4,
    })

    for i, crate in ipairs(explore.crates) do
        local status = crate.looted and "✅ 已搜索" or "📦 未搜索"
        local statusColor = crate.looted and Theme.colors.text_dim or Theme.colors.accent

        table.insert(children, F.card {
            width = "100%", padding = 8,
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = crate.name,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = crate.looted and Theme.colors.text_dim or Theme.colors.text_primary,
                },
                UI.Label {
                    text = status,
                    fontSize = Theme.sizes.font_small,
                    fontColor = statusColor,
                },
            },
        })
    end

    -- 叙事区
    if lastNarration ~= "" then
        table.insert(children, UI.Panel {
            width = "100%", padding = 10, marginTop = 4,
            backgroundColor = { 30, 32, 28, 200 },
            borderRadius = Theme.sizes.radius_small,
            children = {
                UI.Label {
                    text = lastNarration,
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

    -- 动作按钮
    local actions = Explore.get_actions(state, explore)
    for _, act in ipairs(actions) do
        local variant = "secondary"
        if act.id == "extract" then variant = "primary" end
        if act.id == "flee" then variant = "outline" end
        if act.id == "fight" then variant = "primary" end

        table.insert(children, F.actionBtn {
            text = act.icon .. " " .. act.name,
            variant = variant,
            height = 42,
            fontSize = Theme.sizes.font_normal,
            disabled = not act.available,
            onClick = function(self)
                if not act.available then return end
                local result = Explore.execute_action(state, explore, act.id)
                lastNarration = result.narration or ""
                M._refresh(state)
            end,
        })
    end

    -- 弹药提示
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-around", marginTop = 4,
        children = {
            UI.Label {
                text = "🔫 弹药 " .. explore.ammo_available,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_dim,
            },
            UI.Label {
                text = "🛡 耐久 " .. state.truck.durability,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_dim,
            },
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
        gap = 8,
        overflow = "scroll",
        children = children,
    })

    return UI.Panel {
        id = "exploreScreen",
        width = "100%", height = "100%",
        backgroundColor = bgImage_ and { 0, 0, 0, 255 } or { 18, 20, 15, 255 },
        children = layers,
    }
end

-- ============================================================
-- 结果视图
-- ============================================================

function M._show_result_view(state)
    local summary = CombatResult.finalize_explore(state, explore)

    local resultColor = summary.outcome == "success" and Theme.colors.success
        or summary.outcome == "fled" and Theme.colors.warning
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

    local root = F.overlay {
        id = "exploreScreen",
        backgroundImage = bgImage_,
        contentWidth = "90%",
        children = {
            F.card {
                maxWidth = 420,
                padding = Theme.sizes.padding_large,
                borderWidth = 2, borderColor = resultColor,
                gap = 12, alignItems = "center",
                enterAnim = true,
                children = {
                    UI.Label {
                        text = summary.title,
                        fontSize = Theme.sizes.font_title,
                        fontColor = resultColor,
                    },
                    UI.Panel {
                        width = "100%", gap = 6,
                        children = lineWidgets,
                    },
                    F.actionBtn {
                        text = "继续",
                        variant = "primary",
                        height = 48, marginTop = 8,
                        onClick = function(self)
                            router.navigate("home")
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(root)
end

-- ============================================================
-- 辅助组件
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

function M._danger_text()
    local chance = explore.room.hazard_chance or 0
    if chance >= 0.4 then return "高" end
    if chance >= 0.25 then return "中" end
    return "低"
end

function M.update(state, dt, r)
    SpeechBubble.update(dt)
end

return M

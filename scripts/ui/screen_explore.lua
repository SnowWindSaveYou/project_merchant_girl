--- 资源点探索 UI
--- 顶部：chibi_scene widget（探索模式纸娃娃场景）
--- 底部：房间描述、搜刮点列表、战斗交互、撤离
local UI            = require("urhox-libs/UI")
local Theme         = require("ui/theme")
local F             = require("ui/ui_factory")
local Explore       = require("combat/explore")
local CombatResult  = require("combat/combat_result")
local Tutorial      = require("narrative/tutorial")
local SpeechBubble  = require("ui/speech_bubble")
local Flags         = require("core/flags")
local SketchBorder  = require("ui/sketch_border")
local ChibiScene    = require("travel/chibi_scene")
local CombatRenderer = require("travel/combat_renderer")
local Environment   = require("travel/environment")
local AudioMgr      = require("ui/audio_manager")
                      require("travel/explore_mode")   -- 注册 explore 模式到 ChibiScene

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
local prevAudioScene_ = nil
--- 是否有战斗渲染器处于激活状态
local combatActive_ = false

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
-- 场景初始化 / 清理
-- ============================================================

local function initScene(state)
    -- 先把角色 zone 重置为行驶默认，然后 setMode 会通过 zoneMap 映射到 explore zone
    local chibis = ChibiScene.getChibis()
    if chibis[1] then
        chibis[1].zone = "cabin"
        chibis[1].x = 0.5; chibis[1].targetX = 0.5
        chibis[1].state = "idle"; chibis[1].stateTimer = 1
    end
    if chibis[2] then
        chibis[2].zone = "table"
        chibis[2].x = 0.5; chibis[2].targetX = 0.5
        chibis[2].state = "idle"; chibis[2].stateTimer = 2
    end

    ChibiScene.setMode("explore")
    ChibiScene.setState(state)
    -- 注意：不调用 setDriving(true)！
    -- setDriving 会强制把角色塞回 cabin/container（行驶 zone），
    -- 这些 zone 在 explore 模式中不存在，导致角色不渲染。
    -- 改用 setScrolling(true) 仅启用缓慢背景滚动。
    ChibiScene.setScrolling(true)
    if state.flow and state.flow.environment then
        ChibiScene.setEnvironment(Environment.get_current(state.flow.environment))
    end
    -- 根据房间 scene 类型切换探索背景
    if explore and explore.room and explore.room.scene then
        ChibiScene.setExploreBg(explore.room.scene)
    end
end

--- 箱子 icon → 贴图映射
local CRATE_IMAGES = {
    military = "image/crate_military_20260412060117.png",
    wooden   = "image/crate_wooden_20260412060116.png",
    cabinet  = "image/crate_cabinet_20260412060120.png",
    organic  = "image/crate_organic_20260412060118.png",
    scrap    = "image/crate_scrap_20260412060544.png",
}
local CRATE_IMAGE_DEFAULT = "image/chibi_box.png"

--- 根据 explore.crates 设置场景中的箱子可视化
local function syncExploreItems()
    if not explore then return end
    local items = {}
    -- 将箱子均匀分布在 ground_center ~ ground_right 区域 (x: 0.35 ~ 0.85)
    local count = #explore.crates
    for i, crate in ipairs(explore.crates) do
        local xNorm = 0.35 + (i - 1) * 0.50 / math.max(1, count - 1)
        if count == 1 then xNorm = 0.55 end  -- 单个箱子居中偏右
        items[i] = {
            id    = "crate_" .. i,
            image = CRATE_IMAGES[crate.icon] or CRATE_IMAGE_DEFAULT,
            xNorm = xNorm,
        }
    end
    ChibiScene.setExploreItems(items)
    -- 同步已搜刮状态
    for i, crate in ipairs(explore.crates) do
        if crate.looted then
            ChibiScene.markExploreItemLooted("crate_" .. i)
        end
    end
end

local function activateCombat(enemyName)
    if combatActive_ then return end
    CombatRenderer.activate(enemyName, { ground = true })
    ChibiScene.setCombatRenderer(CombatRenderer)
    combatActive_ = true
    -- 战斗 BGM
    prevAudioScene_ = AudioMgr.getScene()
    AudioMgr.setScene("combat", { fadeTime = 0.15 })
end

local function deactivateCombat()
    if not combatActive_ then return end
    CombatRenderer.deactivate()
    ChibiScene.clearCombatRenderer()
    combatActive_ = false
    AudioMgr.setScene(prevAudioScene_ or "travel")
end

-- ============================================================
-- 场景 widget 构建辅助
-- ============================================================

--- 创建顶部纸娃娃场景面板（与 screen_truck 统一：260px + SketchBorder + 水平内边距）
local function buildScenePanel()
    local sceneWidget = ChibiScene.createWidget({
        height = 260,
        borderRadius = Theme.sizes.radius,
    })
    SketchBorder.register(sceneWidget, "card")
    -- 用 padding 容器约束宽度，避免 width=100% + margin 溢出屏幕
    return UI.Panel {
        width = "100%",
        paddingLeft = Theme.sizes.padding,
        paddingRight = Theme.sizes.padding,
        paddingTop = Theme.sizes.padding,
        children = { sceneWidget },
    }
end

-- ============================================================
-- 页面创建
-- ============================================================

function M.create(state, params, r)
    router = r
    state_ = state
    local room_id = params and params.room_id or nil

    explore = Explore.create(state, room_id)
    lastNarration = ""
    combatActive_ = false

    -- 初始化纸娃娃探索场景
    initScene(state)
    syncExploreItems()

    return M._build_intro_view(state)
end

-- ============================================================
-- INTRO 视图
-- ============================================================

function M._build_intro_view(state)
    local room = explore.room

    return UI.Panel {
        id = "exploreScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            -- 顶部纸娃娃场景
            buildScenePanel(),
            -- 底部内容卡片
            UI.Panel {
                width = "100%", flexGrow = 1,
                padding = Theme.sizes.padding,
                justifyContent = "center", alignItems = "center",
                children = {
                    F.card {
                        maxWidth = 420, width = "100%",
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
                                            deactivateCombat()
                                            ChibiScene.clearExploreItems()
                                            ChibiScene.clearExploreBg()
                                            router.navigate("home")
                                        end,
                                    },
                                },
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
    -- 同步箱子搜刮状态到场景可视化
    syncExploreItems()

    if explore.phase == Explore.Phase.RESULT then
        deactivateCombat()
        ChibiScene.clearExploreItems()
        ChibiScene.clearExploreBg()
        M._show_result_view(state)
        return
    end

    -- 遭遇敌人 → 激活战斗渲染
    if (explore.phase == Explore.Phase.ENCOUNTER or explore.phase == Explore.Phase.FIGHTING)
        and not combatActive_ then
        local enemy = explore.enemies[explore.active_enemy]
        if enemy then
            activateCombat(enemy.name)
        end
    end

    -- 脱离战斗 → 关闭战斗渲染
    if explore.phase == Explore.Phase.EXPLORING and combatActive_ then
        deactivateCombat()
    end

    local root = M._build_explore_view(state)
    UI.SetRoot(root)
end

function M._build_explore_view(state)
    -- ── 顶栏标题 + 体力（场景上方独立行）──
    local hpPct = math.max(0, explore.player_hp / explore.player_hp_max)
    local titleBar = UI.Panel {
        width = "100%",
        paddingLeft = Theme.sizes.padding, paddingRight = Theme.sizes.padding,
        paddingTop = 6, paddingBottom = 4,
        gap = 4,
        children = {
            UI.Panel {
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
            },
            UI.Panel {
                width = "100%", height = 6,
                backgroundColor = Theme.colors.progress_bg, borderRadius = 3,
                children = {
                    UI.Panel {
                        width = math.floor(hpPct * 100) .. "%", height = "100%",
                        backgroundColor = hpPct > 0.4 and Theme.colors.success or Theme.colors.danger,
                        borderRadius = 3,
                    },
                },
            },
        },
    }

    -- ── 底部卡片内容 ──
    local children = {}

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
            backgroundColor = Theme.colors.bg_inset,
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
                -- 触发战斗视觉效果
                if combatActive_ and (act.id == "fight" or act.id == "flee") then
                    local result = Explore.execute_action(state, explore, act.id)
                    CombatRenderer.triggerEffect(act.id, result)
                    lastNarration = result.narration or ""
                    -- 打败敌人后 combat_renderer 自动过渡
                    M._refresh(state)
                else
                    local result = Explore.execute_action(state, explore, act.id)
                    lastNarration = result.narration or ""
                    M._refresh(state)
                end
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

    return UI.Panel {
        id = "exploreScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            -- 标题行（场景上方）
            titleBar,
            -- 纸娃娃场景
            buildScenePanel(),
            -- 底部可滚动卡片
            UI.Panel {
                width = "100%", flexGrow = 1, flexShrink = 1,
                padding = Theme.sizes.padding,
                children = {
                    F.card {
                        width = "100%",
                        padding = Theme.sizes.padding,
                        gap = 8,
                        flexGrow = 1, flexShrink = 1,
                        overflow = "scroll",
                        children = children,
                    },
                },
            },
        },
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

    local root = UI.Panel {
        id = "exploreScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            -- 顶部场景（和平状态）
            buildScenePanel(),
            -- 结果卡片
            UI.Panel {
                width = "100%", flexGrow = 1,
                padding = Theme.sizes.padding,
                justifyContent = "center", alignItems = "center",
                children = {
                    F.card {
                        maxWidth = 420, width = "100%",
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
    ChibiScene.update(dt)
    SpeechBubble.update(dt)
end

return M

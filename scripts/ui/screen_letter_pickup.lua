--- 信件领取页面（雪冬送信）
--- 分层布局：底层背景+雪冬立绘  |  上层内容Panel
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")
local LetterSystem = require("narrative/letter_system")
local SketchBorder = require("ui/sketch_border")
local Graph        = require("map/world_graph")

local M = {}
---@type table
local router = nil

-- 雪冬立绘
local XD_PORTRAIT = "image/portrait_xue_dong_20260412064247.png"

-- 雪冬的随机对话（开场）—— 害羞内向，说话小声，断断续续
local GREETINGS = {
    "那个……有你的信。路上没淋到雨，放心。",
    "嗯……追了好远。信都在，你、你数数看。",
    "……总算找到你们了。这些，给你的。",
    "有几封信……写信的人好像挺着急的。",
    "信比我重要……所以我跑快了一点。",
    "这次的信保存得很好……我用油纸包过了。",
    "别担心，都送到了……一封也没少。",
    "那个、那个……有人给你写信了。拿好。",
}

-- 雪冬的随机对话（交互时 / 领取信件时）
local INTERACT_LINES = {
    "这封……保存得还行，没被雨淋到。",
    "写信的人嘱咐我快点送……所以我跑了。",
    "这封信闻起来有股草药味……大概是孟回寄的。",
    "小心拿……信封有点旧了。",
    "送这封的路上差点被野狗追……不过信没事。",
    "好像写了好几遍才寄出来的……字迹压得很重。",
    "你拆开看看吧……写信的人，应该很认真。",
    "信能送到……就好。",
}

-- NPC chibi 头像（从 Theme 获取）

-- 模块级状态
local _greeting   = nil
local _bgImage    = nil

-- ============================================================
-- 页面入口
-- ============================================================
function M.create(state, params, r)
    router = r

    -- 每次进入页面随机选一句问候（不依赖 params，直接从 state 读取）
    if not _greeting then
        _greeting = GREETINGS[math.random(#GREETINGS)]
    end

    local loc = state.map and state.map.current_location
    if loc then
        local node = Graph.get_node(loc)
        _bgImage = node and node.bg or nil
    else
        _bgImage = nil
    end

    local pendingLetters = LetterSystem.get_pending_letters(state)

    if #pendingLetters == 0 then
        return M._buildEmpty(state)
    end

    return M._buildPickup(state, pendingLetters)
end

function M.update() end

-- ============================================================
-- 分层布局组装（共用）
-- ============================================================
local function buildLayered(bgImage, greeting, contentChildren)
    local layerChildren = {}

    -- 底层 1：背景图（全屏，与首页一致）
    if bgImage then
        table.insert(layerChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundImage = bgImage,
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
            F.icon { icon = "letter", size = 22 },
            UI.Label {
                text = "雪冬 · 邮递员",
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
            UI.Panel {
                width = "95%", height = "95%",
                position = "absolute", left = "27%", top = "3%",
                backgroundImage = XD_PORTRAIT,
                backgroundFit = "contain",
            },
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
                        text = "「" .. (greeting or GREETINGS[1]) .. "」",
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

    return UI.Panel {
        id = "letterPickupScreen",
        width = "100%", height = "100%",
        children = layerChildren,
    }
end

-- ============================================================
-- 有待领取信件
-- ============================================================
function M._buildPickup(state, pendingLetters)
    local contentChildren = {}

    -- 待领取信件标题
    table.insert(contentChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    F.icon { icon = "letter", size = 18 },
                    UI.Label {
                        text = "待领取信件",
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                        fontWeight = "bold",
                    },
                },
            },
            UI.Label {
                text = #pendingLetters .. " 封",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.accent,
            },
        },
    })

    -- 信件列表
    for idx, letter in ipairs(pendingLetters) do
        local chibiPath = Theme.npc_chibis[letter.sender]
        local letterCapture = letter

        table.insert(contentChildren, F.card {
            width = "100%", padding = 12,
            enterAnim = true, enterDelay = idx * 0.05,
            onClick = function(self)
                SoundMgr.play("click_soft")
                _greeting = INTERACT_LINES[math.random(#INTERACT_LINES)]
                local collected = LetterSystem.collect_one(state, letterCapture.id)
                if collected then
                    router.navigate("letter", {
                        letters = { collected },
                        state = state,
                        onFinish = function()
                            router.navigate("letter_pickup")
                        end,
                    })
                end
            end,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    alignItems = "center", gap = 10,
                    children = {
                        chibiPath
                            and F.icon { icon = chibiPath, size = 32, round = true }
                            or  F.icon { icon = "letter", size = 24 },
                        UI.Panel {
                            flexGrow = 1, flexShrink = 1, gap = 2,
                            children = {
                                UI.Label {
                                    text = letter.title or "（无题）",
                                    fontSize = Theme.sizes.font_normal,
                                    fontColor = Theme.colors.text_primary,
                                },
                                UI.Label {
                                    text = "来自 " .. (letter.sender_name or "未知"),
                                    fontSize = Theme.sizes.font_small,
                                    fontColor = Theme.colors.text_secondary,
                                },
                            },
                        },
                        UI.Label {
                            text = "领取 ›",
                            fontSize = Theme.sizes.font_small,
                            fontColor = Theme.colors.accent,
                        },
                    },
                },
            },
        })
    end

    -- 一键全部领取
    if #pendingLetters > 1 then
        table.insert(contentChildren, F.actionBtn {
            text = "全部领取（" .. #pendingLetters .. " 封）",
            icon = "letter", iconSize = 22,
            variant = "primary",
            height = 44,
            fontSize = Theme.sizes.font_normal,
            marginTop = 4,
            onClick = function(self)
                SoundMgr.play("click_soft")
                local letters = LetterSystem.collect_all(state)
                if letters and #letters > 0 then
                    router.navigate("letter", {
                        letters = letters,
                        state = state,
                        onFinish = function()
                            router.navigate("letter_pickup")
                        end,
                    })
                end
            end,
        })
    end

    return buildLayered(_bgImage, _greeting, contentChildren)
end

-- ============================================================
-- 空状态
-- ============================================================
function M._buildEmpty(state)
    local contentChildren = {
        UI.Label {
            text = "所有信件已领取",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_dim,
            marginTop = 8,
        },
    }

    local emptyGreeting = "信都给你了……下次有新的，我再送来。"
    return buildLayered(_bgImage, emptyGreeting, contentChildren)
end

return M

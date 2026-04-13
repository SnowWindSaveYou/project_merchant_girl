--- 信箱界面（已读信件存档）
--- 列表展示所有已读信件，点击可重新阅读
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")
local LetterSystem = require("narrative/letter_system")
local SketchBorder = require("ui/sketch_border")

local M = {}
---@type table
local router = nil

-- NPC 图标映射
local SENDER_ICONS = {
    shen_he    = "🌿",
    bai_shu    = "📖",
    zhao_miao  = "🌱",
    meng_hui   = "💊",
    xue_dong   = "📮",
    han_ce     = "🔧",
    wu_shiqi   = "⚙",
    ming_sha   = "📻",
    cheng_yuan = "🔩",
    su_mo      = "📋",
}

function M.create(state, params, r)
    router = r
    return M._build(state)
end

function M.update() end

function M._build(state)
    local readLetters = LetterSystem.get_read_letters(state)
    local sections = {}

    -- 标题栏
    table.insert(sections, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 8,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 6,
                children = {
                    UI.Label {
                        text = "📬",
                        fontSize = 20,
                    },
                    UI.Label {
                        text = "信箱",
                        fontSize = Theme.sizes.font_title,
                        fontColor = Theme.colors.text_primary,
                        fontWeight = "bold",
                    },
                },
            },
            UI.Button {
                text = "返回", width = 64, height = 32,
                fontSize = Theme.sizes.font_small,
                variant = "outline",
                onClick = function()
                    SoundMgr.play("close")
                    router.navigate("home")
                end,
            },
        },
    })

    -- 统计行
    local pendingCount = LetterSystem.pending_count(state)
    local readCount    = LetterSystem.read_count(state)
    local statText = "已收 " .. readCount .. " 封"
    if pendingCount > 0 then
        statText = statText .. "　待领 " .. pendingCount .. " 封"
    end
    table.insert(sections, UI.Label {
        text = statText,
        fontSize = Theme.sizes.font_small,
        fontColor = Theme.colors.text_dim,
        paddingBottom = 4,
    })

    -- 信件列表
    if #readLetters == 0 then
        table.insert(sections, F.card {
            width = "100%", padding = 20,
            children = {
                UI.Label {
                    text = "还没有收到过信件。\n在旅途中遇到雪冬，她会帮你带信。",
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                    width = "100%",
                    lineHeight = 1.5,
                },
            },
        })
    else
        -- 倒序显示（最新的在前）
        for i = #readLetters, 1, -1 do
            local letter = readLetters[i]
            local icon = SENDER_ICONS[letter.sender] or "✉"
            local letterCapture = letter

            local cardWidget = F.card {
                width = "100%", padding = 12,
                enterAnim = true, enterDelay = (#readLetters - i) * 0.03,
                onClick = function(self)
                    SoundMgr.play("click_soft")
                    router.navigate("letter", {
                        letters = { letterCapture },
                        onFinish = function()
                            router.navigate("mailbox")
                        end,
                    })
                end,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        alignItems = "center", gap = 10,
                        children = {
                            UI.Label {
                                text = icon,
                                fontSize = 22,
                            },
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1,
                                gap = 2,
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
                                text = "›",
                                fontSize = 18,
                                fontColor = Theme.colors.text_dim,
                            },
                        },
                    },
                },
            }
            table.insert(sections, cardWidget)
        end
    end

    return UI.Panel {
        id = "mailboxScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%",
                children = {
                    UI.ScrollView {
                        width = "100%", flexGrow = 1, flexShrink = 1,
                        children = {
                            UI.Panel {
                                width = "100%", padding = Theme.sizes.padding,
                                gap = 8,
                                children = sections,
                            },
                        },
                    },
                },
            },
        },
    }
end

return M

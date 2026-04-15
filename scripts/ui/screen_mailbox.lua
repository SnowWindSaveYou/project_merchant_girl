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

-- NPC chibi 头像（从 Theme 获取）

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
        width = "100%",
        flexDirection = "row", alignItems = "center", gap = 6,
        paddingBottom = 8,
        children = {
            F.icon { icon = "letter", size = 22 },
            UI.Label {
                text = "信箱",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.text_primary,
                fontWeight = "bold",
            },
        },
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
            local chibiPath = Theme.npc_chibis[letter.sender]
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
                            chibiPath
                                and F.icon { icon = chibiPath, size = 32, round = true }
                                or  F.icon { icon = "letter", size = 24 },
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
        backgroundImage = Theme.textures.notebook_bg,
        backgroundFit = "cover",
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
    }
end

return M

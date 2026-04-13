--- 任务日志页面
--- 展示已发现的任务（进行中 + 已完成），每条任务显示来源NPC、描述、线索
local UI       = require("urhox-libs/UI")
local Theme    = require("ui/theme")
local QuestLog = require("narrative/quest_log")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r

    local discovered = QuestLog.get_discovered(state)
    local activeList = {}
    local completedList = {}
    for _, item in ipairs(discovered) do
        if item.status == "active" then
            table.insert(activeList, item.quest)
        else
            table.insert(completedList, item.quest)
        end
    end

    local children = {}

    -- 标题
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "📜 任务日志",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = #activeList .. " 进行中 / " .. #completedList .. " 已完成",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
        },
    })

    -- 无任务提示
    if #discovered == 0 then
        table.insert(children, UI.Panel {
            width = "100%", padding = 24,
            alignItems = "center", justifyContent = "center",
            gap = 8,
            children = {
                UI.Label {
                    text = "暂无任务线索",
                    fontSize = Theme.sizes.font_large,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
                UI.Label {
                    text = "与各聚落的NPC交谈，了解他们的故事，\n任务线索会在这里显示。",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                    textAlign = "center",
                },
            },
        })
    end

    -- 进行中任务
    if #activeList > 0 then
        table.insert(children, UI.Label {
            text = "进行中",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.info,
            marginTop = 4,
        })
        for _, q in ipairs(activeList) do
            table.insert(children, createQuestCard(q, false))
        end
    end

    -- 已完成任务
    if #completedList > 0 then
        table.insert(children, UI.Label {
            text = "已完成",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.success,
            marginTop = 8,
        })
        for _, q in ipairs(completedList) do
            table.insert(children, createQuestCard(q, true))
        end
    end

    return UI.Panel {
        id = "questLogScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 8,
        overflow = "scroll",
        children = children,
    }
end

--- 创建单个任务卡片
---@param quest table 任务定义
---@param completed boolean 是否已完成
---@return table widget
function createQuestCard(quest, completed)
    local npcIcon = QuestLog.get_npc_icon(quest.npc_id)
    local npcName = QuestLog.get_npc_name(quest.npc_id)

    local cardChildren = {
        -- 标题行：任务名 + NPC
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = completed and "✅" or "🔸",
                            fontSize = 14,
                        },
                        UI.Label {
                            text = quest.title,
                            fontSize = Theme.sizes.font_normal,
                            fontColor = completed
                                and Theme.colors.text_dim
                                or  Theme.colors.text_primary,
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label {
                            text = npcIcon,
                            fontSize = 12,
                        },
                        UI.Label {
                            text = npcName,
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = Theme.colors.text_secondary,
                        },
                    },
                },
            },
        },

        -- 描述
        UI.Label {
            text = quest.desc,
            fontSize = Theme.sizes.font_small,
            fontColor = completed
                and Theme.colors.text_dim
                or  Theme.colors.text_secondary,
        },
    }

    -- 线索（仅进行中显示）
    if not completed and quest.hint and quest.hint ~= "" then
        table.insert(cardChildren, UI.Panel {
            width = "100%", flexDirection = "row",
            alignItems = "center", gap = 4,
            marginTop = 2,
            children = {
                UI.Label {
                    text = "💡",
                    fontSize = 11,
                },
                UI.Label {
                    text = quest.hint,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = Theme.colors.warning,
                    flexShrink = 1,
                },
            },
        })
    end

    local bgColor = completed
        and { 36, 38, 36, 200 }
        or  Theme.colors.bg_card
    local borderColor = completed
        and Theme.colors.border
        or  Theme.colors.info

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = bgColor,
        borderRadius = Theme.sizes.radius_small,
        borderWidth = 1, borderColor = borderColor,
        gap = 4,
        children = cardChildren,
    }
end

return M

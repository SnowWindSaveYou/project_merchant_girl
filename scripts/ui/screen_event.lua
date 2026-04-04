--- 事件弹窗
--- 显示随机事件描述和选项
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Flags = require("core/flags")
local EventExecutor = require("events/event_executor")
local EventPool = require("events/event_pool")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r
    local event = params and params.event
    if not event then
        router.navigate("home")
        return nil
    end

    -- 过滤出当前可见的选项
    local visible_choices = EventPool._visible_choices(event, state)

    -- 构建选项按钮列表
    local choiceChildren = {}
    for i, choice in ipairs(visible_choices) do
        table.insert(choiceChildren, UI.Button {
            text = choice.text,
            variant = i == 1 and "primary" or "secondary",
            width = "100%",
            height = 44,
            onClick = function(self)
                EventExecutor.apply(state, choice.ops)
                -- 处理选项附带的旗标变更
                if choice.set_flags then
                    for _, f in ipairs(choice.set_flags) do
                        Flags.set(state, f)
                    end
                end
                if choice.clear_flags then
                    for _, f in ipairs(choice.clear_flags) do
                        Flags.clear(state, f)
                    end
                end
                EventPool.set_cooldown(state, event.id)
                -- 链式事件：解锁后续事件
                if event.next_event_id then
                    Flags.set(state, "unlock_" .. event.next_event_id)
                end
                router.navigate("event_result", {
                    event  = event,
                    choice = choice,
                })
            end,
        })
    end

    -- 拼装弹窗内部子元素
    local cardChildren = {
        UI.Label {
            text = event.title,
            fontSize = Theme.sizes.font_title,
            fontColor = Theme.colors.text_primary,
        },
        UI.Label {
            text = event.description,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            lineHeight = 1.5,
        },
        UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Theme.colors.divider,
        },
    }
    for _, btn in ipairs(choiceChildren) do
        table.insert(cardChildren, btn)
    end

    return UI.Panel {
        id = "eventScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.Panel {
                width = "90%", maxWidth = 420,
                padding = Theme.sizes.padding_large,
                backgroundColor = Theme.colors.bg_card,
                borderRadius = Theme.sizes.radius_large,
                borderWidth = Theme.sizes.border,
                borderColor = Theme.colors.info,
                gap = 14,
                children = cardChildren,
            },
        },
    }
end

function M.update(state, dt, r) end

return M

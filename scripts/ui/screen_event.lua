--- 事件弹窗
--- 显示随机事件描述和选项
local UI = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F = require("ui/ui_factory")
local Flags = require("core/flags")
local EventExecutor = require("events/event_executor")
local EventPool = require("events/event_pool")
local SoundMgr = require("ui/sound_manager")
local Graph = require("map/world_graph")

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
        -- 前置检查：资源是否够用
        local canDo, lackReason = EventExecutor.check_requirements(state, choice.ops)
        local label = choice.text
        if not canDo then
            label = choice.text .. "（" .. lackReason .. "）"
        end
        table.insert(choiceChildren, F.actionBtn {
            text = label,
            variant = canDo and (i == 1 and "primary" or "secondary") or "secondary",
            disabled = not canDo,
            onClick = function(self)
                if not canDo then return end
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

    -- 解析背景图：事件自身 > 行驶中按地形 > 聚落 CG
    local REGION_BG = {
        urban  = "image/bg_generic_ruins_industrial_20260409080003.png",
        wild   = "image/bg_generic_road_20260409075956.png",
        canyon = "image/bg_generic_wilderness_20260409080002.png",
        forest = "image/bg_generic_wilderness_20260409080002.png",
    }
    local bgImage = event.background or nil
    if not bgImage then
        if state.flow and state.flow.phase == "travelling" then
            -- 行驶中：按当前地形区域选择路途背景
            local region = state.flow.environment and state.flow.environment.region or "wild"
            bgImage = REGION_BG[region] or REGION_BG.wild
        else
            -- 在聚落：使用聚落 CG
            local loc = state.map and state.map.current_location
            if loc then
                local node = Graph.get_node(loc)
                bgImage = node and node.bg or nil
            end
        end
    end

    return F.overlay {
        id = "eventScreen",
        backgroundImage = bgImage,
        children = {
            F.popupCard {
                padding = Theme.sizes.padding_large,
                borderWidth = Theme.sizes.border,
                borderColor = Theme.colors.info,
                gap = 14,
                enterAnim = true,
                children = cardChildren,
            },
        },
    }
end

function M.update(state, dt, r) end

return M

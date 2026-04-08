--- 篝火对话页面（使用通用 Gal 模块）
local Gal          = require("ui/gal_dialogue")
local Campfire     = require("narrative/campfire")
local Goods        = require("economy/goods")
local Graph        = require("map/world_graph")

local M = {}
---@type table
local router = nil

local session = {
    dialogue    = nil,
    consumed    = nil,
    step        = 0,
    result      = nil,
    showHistory = false,
}

-- ============================================================
-- 页面入口
-- ============================================================

-- 获取对话背景：dialogue.background > 当前聚落 node.bg > nil
local function resolve_background(state, dialogue)
    if dialogue and dialogue.background then
        return dialogue.background
    end
    local loc = state and state.map and state.map.current_location
    if loc then
        local node = Graph.get_node(loc)
        if node and node.bg then
            return node.bg
        end
    end
    return nil
end

function M.create(state, params, r)
    router = r
    params = params or {}

    if params.dialogue then
        session.dialogue    = params.dialogue
        session.consumed    = params.consumed
        session.step        = 1
        session.result      = nil
        session.showHistory = false
    end

    if params._continue then
        -- 保持 showHistory 状态
    end

    if params._toggle_history then
        session.showHistory = not session.showHistory
    end

    if params.show_result then
        session.result = params.result_data
        return Gal.createResultView({
            dialogue   = session.dialogue,
            result     = session.result,
            npc        = nil,
            background = resolve_background(state, session.dialogue),
            onClose    = function()
                session.dialogue = nil
                session.result   = nil
                router.navigate("home")
            end,
        })
    end

    if not session.dialogue then
        if router then router.navigate("home") end
        return nil
    end

    if session.showHistory then
        return Gal.createHistoryView({
            dialogue = session.dialogue,
            step     = session.step,
            npc      = nil,
            onBack   = function()
                router.navigate("campfire", { _toggle_history = true })
            end,
        })
    end

    -- 顶栏附加信息：消耗物品
    local topInfo = nil
    if session.consumed then
        local g = Goods.get(session.consumed)
        topInfo = "-1 " .. (g and g.name or session.consumed)
    end

    return Gal.createDialogueView({
        dialogue   = session.dialogue,
        step       = session.step,
        npc        = nil,  -- 篝火无 NPC，使用林砾 + 陶夏
        topInfo    = topInfo,
        background = resolve_background(state, session.dialogue),
        onAdvance  = function()
            session.step = session.step + 1
            router.navigate("campfire", { _continue = true })
        end,
        onChoice = function(i)
            local result = Campfire.apply_choice(state, session.dialogue, i)
            router.navigate("campfire", {
                show_result = true,
                result_data = result,
            })
        end,
        onHistory = function()
            router.navigate("campfire", { _toggle_history = true })
        end,
        onClose = function()
            session.dialogue = nil
            router.navigate("home")
        end,
    })
end

function M.update(state, dt, r) end

return M

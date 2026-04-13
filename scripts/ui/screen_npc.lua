--- NPC 对话页面（使用通用 Gal 模块）
local Gal        = require("ui/gal_dialogue")
local NpcManager = require("narrative/npc_manager")
local Campfire   = require("narrative/campfire")
local Graph      = require("map/world_graph")
local AudioMgr   = require("ui/audio_manager")


local M = {}
---@type table
local router = nil

local session = {
    npc_id      = nil,
    npc         = nil,
    dialogue    = nil,
    step        = 0,
    result      = nil,
    showHistory = false,
    return_to   = nil,
}

-- ============================================================
-- 页面入口
-- ============================================================

-- 获取对话背景：dialogue.background > 当前聚落 node.bg > nil
local function resolve_background(state, dialogue)
    if dialogue and dialogue.background then
        return dialogue.background
    end
    -- fallback：当前位置的聚落背景
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

    -- 新会话
    if params.dialogue then
        session.npc_id      = params.npc_id
        session.npc         = NpcManager.get_npc(params.npc_id)
        session.dialogue    = params.dialogue
        session.step        = 1
        session.result      = nil
        session.showHistory = false
        session.return_to   = params._return_to or nil

        -- 对话数据可指定 audioScene（campfire / settlement / travel / silent）
        -- NPC 对话发生在聚落，默认为 "settlement"
        local scene = params.dialogue.audioScene or "settlement"
        AudioMgr.setScene(scene)
    end

    if params._continue then
        -- 保持状态
    end

    if params._toggle_history then
        session.showHistory = not session.showHistory
    end

    -- 结果阶段
    if params.show_result then
        session.result = params.result_data

        local returnTarget = session.return_to
        return Gal.createResultView({
            dialogue   = session.dialogue,
            result     = session.result,
            npc        = session.npc,
            background = resolve_background(state, session.dialogue),
            onClose    = function()
                session.dialogue  = nil
                session.npc       = nil
                session.npc_id    = nil
                session.result    = nil
                session.return_to = nil
                router.navigate(returnTarget or "home")
            end,
        })
    end

    -- 无对话数据
    if not session.dialogue or not session.npc then
        if router then router.navigate("home") end
        return nil
    end

    -- 历史视图
    if session.showHistory then
        return Gal.createHistoryView({
            dialogue = session.dialogue,
            step     = session.step,
            npc      = session.npc,
            onBack   = function()
                router.navigate("npc", { _toggle_history = true })
            end,
        })
    end

    return Gal.createDialogueView({
        dialogue   = session.dialogue,
        step       = session.step,
        npc        = session.npc,
        background = resolve_background(state, session.dialogue),
        onAdvance  = function()
            session.step = session.step + 1
            router.navigate("npc", { _continue = true })
        end,
        onChoice = function(i)
            local ok, err = pcall(function()
                local result = NpcManager.apply_choice(state, session.dialogue, i)
                router.navigate("npc", {
                    show_result = true,
                    result_data = result,
                })
            end)
            if not ok then
                print("[NPC-UI] ERROR in choice: " .. tostring(err))
            end
        end,
        onHistory = function()
            router.navigate("npc", { _toggle_history = true })
        end,
        onClose = function()
            -- 跳过对话：设置所有选项共有的进度 flag，避免教程/主线卡住
            if session.dialogue and not session.result then
                Campfire.apply_skip(state, session.dialogue)
            end
            session.dialogue  = nil
            session.npc       = nil
            session.npc_id    = nil
            session.return_to = nil
            router.navigate("home")
        end,
    })
end

function M.update(state, dt, r)
    Gal.update(dt)
end

return M

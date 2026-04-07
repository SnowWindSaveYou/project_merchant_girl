--- NPC 对话页面（使用通用 Gal 模块）
local Gal        = require("ui/gal_dialogue")
local NpcManager = require("narrative/npc_manager")
local Goodwill   = require("settlement/goodwill")

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
}

-- ============================================================
-- 页面入口
-- ============================================================

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

        -- 好感度信息
        local extraInfo = {}
        if session.npc then
            local sett = state.settlements[session.npc.settlement]
            if sett then
                local gwInfo = Goodwill.get_info(sett.goodwill or 0)
                table.insert(extraInfo, {
                    text  = session.npc.name .. " 好感: " .. math.floor(sett.goodwill or 0) .. " (" .. gwInfo.name .. ")",
                    color = session.npc.color,
                })
            end
        end

        return Gal.createResultView({
            dialogue  = session.dialogue,
            result    = session.result,
            npc       = session.npc,
            extraInfo = extraInfo,
            onClose   = function()
                session.dialogue = nil
                session.npc      = nil
                session.npc_id   = nil
                session.result   = nil
                router.navigate("home")
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
        dialogue  = session.dialogue,
        step      = session.step,
        npc       = session.npc,
        onAdvance = function()
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
            session.dialogue = nil
            session.npc      = nil
            session.npc_id   = nil
            router.navigate("home")
        end,
    })
end

function M.update(state, dt, r) end

return M

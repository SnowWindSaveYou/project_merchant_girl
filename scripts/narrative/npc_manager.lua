--- NPC 管理器
--- NPC 元数据定义 + 拜访会话管理（条件检查、开启会话、执行选择）
local NpcDialoguePool = require("narrative/npc_dialogue_pool")
local EventExec       = require("events/event_executor")

local M = {}

-- ============================================================
-- NPC 元数据
-- ============================================================

---@type table<string, table>
M.NPC_DATA = {
    shen_he = {
        id         = "shen_he",
        name       = "沈禾",
        settlement = "greenhouse",
        title      = "温室社区领袖",
        icon       = "🌾",
        color      = { 108, 148,  96, 255 },
        bg         = {  38,  52,  38, 240 },
    },
    han_ce = {
        id         = "han_ce",
        name       = "韩策",
        settlement = "tower",
        title      = "北穹塔台领袖",
        icon       = "🔧",
        color      = { 112, 142, 168, 255 },
        bg         = {  32,  40,  54, 240 },
    },
    wu_shiqi = {
        id         = "wu_shiqi",
        name       = "伍拾七",
        settlement = "ruins_camp",
        title      = "废墟营地头目",
        icon       = "🔩",
        color      = { 168, 128,  82, 255 },
        bg         = {  48,  38,  30, 240 },
    },
    bai_shu = {
        id         = "bai_shu",
        name       = "白述",
        settlement = "bell_tower",
        title      = "钟楼书院领袖",
        icon       = "📖",
        color      = { 148, 128, 168, 255 },
        bg         = {  42,  36,  46, 240 },
    },
    -- 前哨站 NPC（Phase 11）
    zhao_miao = {
        id         = "zhao_miao",
        name       = "赵苗",
        settlement = "greenhouse_farm",
        title      = "外围农场管事",
        icon       = "🌱",
        color      = {  96, 138,  80, 255 },
        bg         = {  34,  48,  32, 240 },
    },
    cheng_yuan = {
        id         = "cheng_yuan",
        name       = "程远",
        settlement = "dome_outpost",
        title      = "穹顶哨站站长",
        icon       = "📡",
        color      = {  96, 126, 152, 255 },
        bg         = {  30,  36,  48, 240 },
    },
    a_xiu = {
        id         = "a_xiu",
        name       = "阿锈",
        settlement = "metro_camp",
        title      = "地铁营地机修头",
        icon       = "🚇",
        color      = { 152, 112,  72, 255 },
        bg         = {  44,  36,  28, 240 },
    },
    su_mo = {
        id         = "su_mo",
        name       = "苏墨",
        settlement = "old_church",
        title      = "旧教堂看守",
        icon       = "🕯",
        color      = { 132, 112, 148, 255 },
        bg         = {  38,  32,  42, 240 },
    },
    -- 流浪 NPC（不绑定聚落，位置由 wandering_npc 管理）
    meng_hui = {
        id         = "meng_hui",
        name       = "孟回",
        settlement = nil,  -- 流浪型
        wandering  = true,
        title      = "行脚医生",
        icon       = "💊",
        color      = { 128, 168, 128, 255 },
        bg         = {  32,  44,  36, 240 },
    },
    ming_sha = {
        id         = "ming_sha",
        name       = "鸣砂",
        settlement = nil,  -- 流浪型
        wandering  = true,
        title      = "独行商人",
        icon       = "🎒",
        color      = { 178, 148,  98, 255 },
        bg         = {  44,  38,  28, 240 },
    },
}

-- ============================================================
-- 查询
-- ============================================================

--- 根据聚落 ID 获取驻扎 NPC 数据
---@param settlement_id string
---@return table|nil npc
function M.get_npc_for_settlement(settlement_id)
    for _, npc in pairs(M.NPC_DATA) do
        if npc.settlement == settlement_id then
            return npc
        end
    end
    return nil
end

--- 根据 NPC ID 获取数据
---@param npc_id string
---@return table|nil
function M.get_npc(npc_id)
    return M.NPC_DATA[npc_id]
end

-- ============================================================
-- 条件检查
-- ============================================================

--- 检查是否可以拜访指定 NPC
---@param state table
---@param npc_id string
---@return boolean ok
---@return string|nil reason
function M.can_visit(state, npc_id)
    local npc = M.NPC_DATA[npc_id]
    if not npc then
        return false, "未知 NPC"
    end

    -- 流浪 NPC：通过 wandering_npc 模块检查位置
    if npc.wandering then
        local WanderingNpc = require("narrative/wandering_npc")
        local loc = WanderingNpc.get_location(state, npc_id)
        if loc ~= state.map.current_location then
            return false, "不在此处"
        end
    else
        -- 驻扎 NPC：必须在该 NPC 所在聚落
        if state.map.current_location ~= npc.settlement then
            return false, "不在该聚落"
        end
    end

    -- 必须有可用对话
    local pool = NpcDialoguePool.filter(state, npc_id)
    if #pool == 0 then
        return false, "暂时没有新话题"
    end

    return true, nil
end

-- ============================================================
-- 会话流程
-- ============================================================

--- 开启拜访会话：抽取对话
--- NPC 拜访不消耗资源（与篝火不同）
---@param state table
---@param npc_id string
---@return table|nil dialogue
function M.start_visit(state, npc_id)
    local ok, reason = M.can_visit(state, npc_id)
    if not ok then
        print("[NpcManager] Cannot visit " .. npc_id .. ": " .. (reason or "unknown"))
        return nil
    end

    -- 抽取对话
    local dialogue = NpcDialoguePool.pick(state, npc_id)
    if not dialogue then
        print("[NpcManager] No dialogue for " .. npc_id)
        return nil
    end

    -- 设置冷却
    NpcDialoguePool.set_cooldown(state, dialogue.id)

    -- 计数
    if not state.narrative then state.narrative = {} end
    if not state.narrative.npc_visit_count then
        state.narrative.npc_visit_count = {}
    end
    local vc = state.narrative.npc_visit_count
    vc[npc_id] = (vc[npc_id] or 0) + 1

    print("[NpcManager] Visit #" .. vc[npc_id] .. " to " .. npc_id .. ": " .. dialogue.id)
    return dialogue
end

--- 执行选择结果
---@param state table
---@param dialogue table 当前对话
---@param choice_index number 选择索引（1-based）
---@return table result { ops_log, memory, result_text }
function M.apply_choice(state, dialogue, choice_index)
    local choices = dialogue.choices or {}
    local choice = choices[choice_index]
    if not choice then
        print("[NpcManager] Invalid choice index: " .. tostring(choice_index))
        return { ops_log = {}, result_text = "" }
    end

    -- 执行 ops（复用 event_executor）
    local ops_log = EventExec.apply(state, choice.ops)

    -- 存储 memory
    local memory = choice.memory
    if memory then
        if not state.narrative then state.narrative = {} end
        if not state.narrative.memories then state.narrative.memories = {} end
        -- 避免重复
        local exists = false
        for _, m in ipairs(state.narrative.memories) do
            if m.id == memory.id then exists = true; break end
        end
        if not exists then
            table.insert(state.narrative.memories, {
                id    = memory.id,
                title = memory.title,
                desc  = memory.desc,
                time  = os.time(),
            })
            print("[NpcManager] Memory added: " .. memory.id)
        end
    end

    return {
        ops_log     = ops_log,
        memory      = memory,
        result_text = choice.result_text or "",
    }
end

return M

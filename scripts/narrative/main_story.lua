--- 主线章节状态机
--- 基于 flags + stats 的被动触发器，条件满足时解锁下一章节
local Flags    = require("core/flags")
local Goodwill = require("settlement/goodwill")
local Graph    = require("map/world_graph")
local Loader   = require("data_loader/loader")

local M = {}

-- 4 个主聚落 ID（用于"全部访问"判定）
local MAIN_SETTLEMENTS = { "tower", "greenhouse", "ruins_camp", "bell_tower" }

-- ============================================================
-- 配置加载
-- ============================================================

---@type table[]|nil
local chapters_ = nil

local function _load()
    if chapters_ then return end
    chapters_ = Loader.load("configs/story_chapters.json")
    if not chapters_ then
        print("[MainStory] WARN: story_chapters.json not found, using empty")
        chapters_ = {}
    end
end

-- ============================================================
-- 查询接口
-- ============================================================

--- 获取当前章节号 (0=序章 ~ 7=终章)
---@param state table
---@return number
function M.get_chapter(state)
    return state.narrative.chapter or 0
end

--- 获取章节信息
---@param ch number 章节号 (0~7)
---@return table|nil { id, chapter, name, subtitle, summary, ... }
function M.get_chapter_info(ch)
    _load()
    for _, def in ipairs(chapters_) do
        if def.chapter == ch then return def end
    end
    return nil
end

--- 获取当前章节的显示文本
---@param state table
---@return string name 如 "第一章"
---@return string subtitle 如 "熟悉的路"
function M.get_display(state)
    local ch = M.get_chapter(state)
    local info = M.get_chapter_info(ch)
    if info then
        return info.name, info.subtitle
    end
    return "序章", ""
end

-- ============================================================
-- 条件检查
-- ============================================================

--- 统计已访问的主聚落数
---@param state table
---@return number
local function count_visited_settlements(state)
    local n = 0
    for sid, sett in pairs(state.settlements) do
        if sett.visited then
            -- 只计算非前哨/非隐藏聚落
            local node = Graph.get_node(sid)
            if node and node.type == "settlement" then
                n = n + 1
            end
        end
    end
    return n
end

--- 检查 4 个主聚落是否全部访问过
---@param state table
---@return boolean
local function all_main_settlements_visited(state)
    for _, sid in ipairs(MAIN_SETTLEMENTS) do
        local sett = state.settlements[sid]
        if not sett or not sett.visited then return false end
    end
    return true
end

--- 统计好感达到指定等级的主聚落数
---@param state table
---@param level number 好感等级 (1/2/3)
---@return number
local function count_goodwill_at_level(state, level)
    local n = 0
    for _, sid in ipairs(MAIN_SETTLEMENTS) do
        local sett = state.settlements[sid]
        if sett then
            local lv = Goodwill.get_level(sett.goodwill or 0)
            if lv >= level then n = n + 1 end
        end
    end
    return n
end

--- 统计已发现的隐藏节点数
---@param state table
---@return number
local function count_hidden_nodes_found(state)
    local n = 0
    local nodes = Graph.get_all_nodes()
    if nodes then
        for nid, node in pairs(nodes) do
            if node.hidden then
                local known = state.map.known_nodes or {}
                if known[nid] then n = n + 1 end
            end
        end
    end
    return n
end

--- 检查某章节的推进条件是否满足
---@param state table
---@param cond table advance_conditions
---@return boolean
local function check_conditions(state, cond)
    if not cond then return false end

    -- flag 条件（单个 flag）
    if cond.flag then
        if not Flags.has(state, cond.flag) then return false end
    end

    -- required_flags（多个 flag 全部满足）
    if cond.required_flags then
        for _, f in ipairs(cond.required_flags) do
            if not Flags.has(state, f) then return false end
        end
    end

    -- 最小行程数
    if cond.min_trips then
        if (state.stats.total_trips or 0) < cond.min_trips then return false end
    end

    -- 最小已访问聚落数
    if cond.min_settlements_visited then
        if count_visited_settlements(state) < cond.min_settlements_visited then return false end
    end

    -- 4 个主聚落全部访问
    if cond.all_main_settlements_visited then
        if not all_main_settlements_visited(state) then return false end
    end

    -- 好感等级条件：至少 N 个主聚落达到 Lv X
    if cond.min_goodwill_level and cond.min_goodwill_count then
        if count_goodwill_at_level(state, cond.min_goodwill_level) < cond.min_goodwill_count then
            return false
        end
    end

    -- 隐藏节点发现数
    if cond.min_hidden_nodes_found then
        if count_hidden_nodes_found(state) < cond.min_hidden_nodes_found then return false end
    end

    return true
end

-- ============================================================
-- 章节推进
-- ============================================================

--- 检查并推进章节（每趟行程结束后调用）
---@param state table
---@return boolean advanced 是否发生了章节推进
---@return table|nil new_chapter_info 新章节信息（推进时返回）
function M.check_advance(state)
    _load()
    local cur = M.get_chapter(state)

    -- 终章不再推进
    if cur >= 7 then return false, nil end

    -- 查找当前章节定义
    local cur_def = M.get_chapter_info(cur)
    if not cur_def then return false, nil end

    -- 检查当前章节的推进条件
    if not check_conditions(state, cur_def.advance_conditions) then
        return false, nil
    end

    -- 条件满足，推进到下一章
    local next_ch = cur + 1
    state.narrative.chapter = next_ch

    -- 设置推进旗标
    if cur_def.on_advance_flags then
        for _, flag_id in ipairs(cur_def.on_advance_flags) do
            Flags.set(state, flag_id)
        end
    end

    local next_def = M.get_chapter_info(next_ch)
    print("[MainStory] Chapter advanced: " .. cur .. " → " .. next_ch
        .. " (" .. (next_def and next_def.subtitle or "?") .. ")")

    return true, next_def
end

-- ============================================================
-- 进度查询（UI 用）
-- ============================================================

--- 获取当前章节的进度提示（未满足的条件）
---@param state table
---@return table[] hints { { text, done } }
function M.get_progress_hints(state)
    _load()
    local cur = M.get_chapter(state)
    local def = M.get_chapter_info(cur)
    if not def or not def.advance_conditions then return {} end

    local cond = def.advance_conditions
    local hints = {}

    if cond.min_trips then
        local trips = state.stats.total_trips or 0
        table.insert(hints, {
            text = "完成 " .. cond.min_trips .. " 趟行程",
            done = trips >= cond.min_trips,
            progress = trips .. "/" .. cond.min_trips,
        })
    end

    if cond.min_settlements_visited then
        local visited = count_visited_settlements(state)
        table.insert(hints, {
            text = "访问 " .. cond.min_settlements_visited .. " 个聚落",
            done = visited >= cond.min_settlements_visited,
            progress = visited .. "/" .. cond.min_settlements_visited,
        })
    end

    if cond.all_main_settlements_visited then
        local all = all_main_settlements_visited(state)
        local visited = 0
        for _, sid in ipairs(MAIN_SETTLEMENTS) do
            local sett = state.settlements[sid]
            if sett and sett.visited then visited = visited + 1 end
        end
        table.insert(hints, {
            text = "访问全部主聚落",
            done = all,
            progress = visited .. "/4",
        })
    end

    if cond.min_goodwill_level and cond.min_goodwill_count then
        local count = count_goodwill_at_level(state, cond.min_goodwill_level)
        local lvName = Goodwill.LEVELS[cond.min_goodwill_level + 1]
        local lvLabel = lvName and lvName.name or ("Lv" .. cond.min_goodwill_level)
        table.insert(hints, {
            text = cond.min_goodwill_count .. " 个聚落达到「" .. lvLabel .. "」",
            done = count >= cond.min_goodwill_count,
            progress = count .. "/" .. cond.min_goodwill_count,
        })
    end

    if cond.min_hidden_nodes_found then
        local found = count_hidden_nodes_found(state)
        table.insert(hints, {
            text = "发现 " .. cond.min_hidden_nodes_found .. " 个隐藏地点",
            done = found >= cond.min_hidden_nodes_found,
            progress = found .. "/" .. cond.min_hidden_nodes_found,
        })
    end

    if cond.flag then
        table.insert(hints, {
            text = "完成关键剧情",
            done = Flags.has(state, cond.flag),
        })
    end

    if cond.required_flags then
        for _, f in ipairs(cond.required_flags) do
            table.insert(hints, {
                text = "完成前置剧情",
                done = Flags.has(state, f),
            })
        end
    end

    return hints
end

--- 获取三结局判定
---@param state table
---@return string ending_id "ending_c"|"ending_b"|"ending_a"
---@return string ending_name
function M.get_ending(state)
    local lv3_count = count_goodwill_at_level(state, 3)
    if lv3_count >= 4 then
        return "ending_c", "点亮信号"
    elseif lv3_count >= 1 then
        return "ending_b", "驻留守望"
    else
        return "ending_a", "继续行走"
    end
end

return M

--- 势力系统
--- 4 个势力，每个势力拥有 1 个首都 + 1 个前哨站
local M = {}

-- ============================================================
-- 势力定义
-- ============================================================
M.FACTIONS = {
    farm = {
        id   = "farm",
        name = "农耕派",
        icon = "🌾",
        capital     = "greenhouse",
        settlements = { "greenhouse", "greenhouse_farm" },
    },
    tech = {
        id   = "tech",
        name = "技术派",
        icon = "⚙",
        capital     = "tower",
        settlements = { "tower", "dome_outpost" },
    },
    scav = {
        id   = "scav",
        name = "拾荒帮",
        icon = "🔧",
        capital     = "ruins_camp",
        settlements = { "ruins_camp", "metro_camp" },
    },
    scholar = {
        id   = "scholar",
        name = "宗教团",
        icon = "📖",
        capital     = "bell_tower",
        settlements = { "bell_tower", "old_church" },
    },
}

-- ============================================================
-- 反查表：settlement_id → faction_id
-- ============================================================
M.SETTLEMENT_FACTION = {}
for fid, f in pairs(M.FACTIONS) do
    for _, sid in ipairs(f.settlements) do
        M.SETTLEMENT_FACTION[sid] = fid
    end
end

-- ============================================================
-- API
-- ============================================================

--- 获取聚落所属势力 id
---@param settlement_id string
---@return string|nil faction_id
function M.get_faction(settlement_id)
    return M.SETTLEMENT_FACTION[settlement_id]
end

--- 获取势力信息
---@param faction_id string
---@return table|nil
function M.get_faction_info(faction_id)
    return M.FACTIONS[faction_id]
end

--- 获取势力的首都 id
---@param faction_id string
---@return string|nil
function M.get_capital(faction_id)
    local f = M.FACTIONS[faction_id]
    return f and f.capital
end

--- 获取势力下所有聚落 id 列表
---@param faction_id string
---@return string[]
function M.get_faction_settlements(faction_id)
    local f = M.FACTIONS[faction_id]
    return f and f.settlements or {}
end

--- 判断是否是首都
---@param settlement_id string
---@return boolean
function M.is_capital(settlement_id)
    local fid = M.SETTLEMENT_FACTION[settlement_id]
    if not fid then return false end
    return M.FACTIONS[fid].capital == settlement_id
end

--- 获取同势力的其他聚落（排除自身）
---@param settlement_id string
---@return string[]
function M.get_siblings(settlement_id)
    local fid = M.SETTLEMENT_FACTION[settlement_id]
    if not fid then return {} end
    local result = {}
    for _, sid in ipairs(M.FACTIONS[fid].settlements) do
        if sid ~= settlement_id then
            table.insert(result, sid)
        end
    end
    return result
end

return M

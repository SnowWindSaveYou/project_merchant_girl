--- 温室·培育农场系统
--- 选种 → 收集原料 → 种下 → 等待(跑商趟数) → 收获
--- 数据存储在 state.settlements.greenhouse.farm
local DataLoader = require("data_loader/loader")
local Goodwill   = require("settlement/goodwill")
local Flags      = require("core/flags")

local M = {}

-- 最大同时种植槽数
M.MAX_SLOTS = 2

-- 懒加载作物数据
---@type table|nil
local _crops = nil

--- 加载作物配置
---@return table[]
local function _load()
    if not _crops then
        local data = DataLoader.load("configs/crops.json")
        _crops = data and data.crops or {}
    end
    return _crops
end

--- 获取作物定义（按 ID）
---@param crop_id string
---@return table|nil
function M.get_crop(crop_id)
    local crops = _load()
    for _, c in ipairs(crops) do
        if c.id == crop_id then return c end
    end
    return nil
end

--- 确保 farm 状态存在
---@param state table
local function _ensure(state)
    local sett = state.settlements.greenhouse
    if not sett then
        state.settlements.greenhouse = { goodwill = 10, visited = true, reputation = 100 }
        sett = state.settlements.greenhouse
    end
    if not sett.farm then
        sett.farm = {
            slots = {},       -- { [1] = { crop_id, planted_trip, trips_elapsed }, ... }
            harvested = {},   -- { [crop_id] = total_count } 累计收获统计
        }
    end
    return sett.farm
end

--- 获取可种植的作物列表（根据好感 + flag）
---@param state table
---@return table[]
function M.get_available_crops(state)
    local crops = _load()
    local sett = state.settlements.greenhouse
    local gw = sett and sett.goodwill or 0
    local result = {}
    for _, c in ipairs(crops) do
        local gwOk = gw >= (c.required_goodwill or 0)
        local flagOk = true
        if c.unlock_flag and c.unlock_flag ~= "" then
            flagOk = Flags.has(state, c.unlock_flag)
        end
        if gwOk and flagOk then
            table.insert(result, c)
        end
    end
    return result
end

--- 获取当前种植槽状态
---@param state table
---@return table[] slots
function M.get_slots(state)
    local farm = _ensure(state)
    return farm.slots
end

--- 种植
---@param state table
---@param slot_index number 1-based
---@param crop_id string
---@return boolean success, string|nil error
function M.plant(state, slot_index, crop_id)
    local farm = _ensure(state)
    if slot_index < 1 or slot_index > M.MAX_SLOTS then
        return false, "无效种植槽"
    end
    if farm.slots[slot_index] then
        return false, "该种植槽已被占用"
    end
    local crop = M.get_crop(crop_id)
    if not crop then
        return false, "未知作物"
    end

    -- 检查原料
    for _, mat in ipairs(crop.materials or {}) do
        local have = state.truck.cargo[mat.goods_id] or 0
        if have < mat.amount then
            return false, "缺少原料"
        end
    end

    -- 扣除原料
    for _, mat in ipairs(crop.materials or {}) do
        state.truck.cargo[mat.goods_id] = (state.truck.cargo[mat.goods_id] or 0) - mat.amount
    end

    farm.slots[slot_index] = {
        crop_id       = crop_id,
        planted_trip  = state.stats.total_trips,
        trips_elapsed = 0,
    }
    return true
end

--- 每次行程结束调用：推进生长
---@param state table
function M.advance_trip(state)
    local farm = _ensure(state)
    for i = 1, M.MAX_SLOTS do
        local slot = farm.slots[i]
        if slot then
            slot.trips_elapsed = slot.trips_elapsed + 1
        end
    end
end

--- 检查某个槽是否可收获
---@param state table
---@param slot_index number
---@return boolean
function M.can_harvest(state, slot_index)
    local farm = _ensure(state)
    local slot = farm.slots[slot_index]
    if not slot then return false end
    local crop = M.get_crop(slot.crop_id)
    if not crop then return false end
    return slot.trips_elapsed >= crop.growth_trips
end

--- 收获
---@param state table
---@param slot_index number
---@return boolean success, table|nil result { crop_name, yield_id, yield_amount }
function M.harvest(state, slot_index)
    local farm = _ensure(state)
    local slot = farm.slots[slot_index]
    if not slot then return false, nil end
    local crop = M.get_crop(slot.crop_id)
    if not crop then return false, nil end
    if slot.trips_elapsed < crop.growth_trips then
        return false, nil
    end

    -- 添加产出到货舱
    local yieldId = crop.yield_id
    local yieldAmt = crop.yield_amount
    state.truck.cargo[yieldId] = (state.truck.cargo[yieldId] or 0) + yieldAmt

    -- 统计
    farm.harvested[crop.id] = (farm.harvested[crop.id] or 0) + yieldAmt

    -- 清空种植槽
    farm.slots[slot_index] = nil

    return true, {
        crop_name    = crop.name,
        yield_id     = yieldId,
        yield_amount = yieldAmt,
    }
end

--- 获取收获统计
---@param state table
---@return table { [crop_id] = count }
function M.get_harvest_stats(state)
    local farm = _ensure(state)
    return farm.harvested or {}
end

return M

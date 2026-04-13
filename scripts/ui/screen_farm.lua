--- 温室·培育农场页面
--- 展示种植槽状态、可种植作物、收获操作
local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F     = require("ui/ui_factory")
local Farm  = require("settlement/farm")
local Goods = require("economy/goods")

local M = {}
---@type table
local router = nil

function M.create(state, params, r)
    router = r

    local slots = Farm.get_slots(state)
    local available = Farm.get_available_crops(state)

    local children = {}

    -- ── 标题栏 ──
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "🌱 培育农场",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = "种植槽 " .. Farm.MAX_SLOTS .. " 个",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
        },
    })

    -- ── 种植槽 ──
    for i = 1, Farm.MAX_SLOTS do
        table.insert(children, createSlotCard(state, i, slots[i], available))
    end

    -- ── 可种植作物列表 ──
    table.insert(children, UI.Label {
        text = "可种植作物",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
        marginTop = 8,
    })

    if #available == 0 then
        table.insert(children, UI.Label {
            text = "提升温室好感以解锁更多作物",
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_dim,
        })
    else
        for _, crop in ipairs(available) do
            table.insert(children, createCropInfo(state, crop))
        end
    end

    -- ── 收获统计 ──
    local stats = Farm.get_harvest_stats(state)
    local hasStats = false
    for _ in pairs(stats) do hasStats = true; break end
    if hasStats then
        table.insert(children, UI.Label {
            text = "收获记录",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.success,
            marginTop = 8,
        })
        for cropId, count in pairs(stats) do
            local crop = Farm.get_crop(cropId)
            local name = crop and crop.name or cropId
            table.insert(children, UI.Label {
                text = name .. " — 累计收获 " .. count .. " 份",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_secondary,
            })
        end
    end

    return UI.Panel {
        id = "farmScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 8,
        overflow = "scroll",
        children = children,
    }
end

--- 种植槽卡片
---@param state table
---@param index number
---@param slot table|nil
---@param available table[]
function createSlotCard(state, index, slot, available)
    if slot then
        -- 有作物正在生长
        local crop = Farm.get_crop(slot.crop_id)
        local name = crop and crop.name or slot.crop_id
        local needed = crop and crop.growth_trips or 0
        local elapsed = slot.trips_elapsed or 0
        local canHarvest = Farm.can_harvest(state, index)
        local progress = needed > 0 and math.min(1, elapsed / needed) or 1

        local slotChildren = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "🌿 " .. name,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = canHarvest and "可收获!" or (elapsed .. "/" .. needed .. " 趟"),
                        fontSize = Theme.sizes.font_small,
                        fontColor = canHarvest and Theme.colors.success or Theme.colors.text_secondary,
                    },
                },
            },
            UI.ProgressBar {
                value = progress,
                width = "100%", height = 8,
                variant = canHarvest and "success" or "info",
            },
        }

        if canHarvest then
            table.insert(slotChildren, F.actionBtn {
                text = "收获",
                variant = "primary",
                height = 36,
                fontSize = Theme.sizes.font_normal,
                onClick = function(self)
                    local ok, result = Farm.harvest(state, index)
                    if ok and result then
                        local g = Goods.get(result.yield_id)
                        local yName = g and g.name or result.yield_id
                        print("[Farm] Harvested: " .. result.crop_name
                            .. " -> " .. yName .. " x" .. result.yield_amount)
                    end
                    router.navigate("farm")
                end,
            })
        end

        return F.card {
            width = "100%", padding = 10,
            imageTint = canHarvest and { 0.6, 0.9, 0.6, 1.0 } or nil,
            borderWidth = 1,
            borderColor = canHarvest and Theme.colors.success or nil,
            gap = 6,
            children = slotChildren,
        }
    else
        -- 空槽：选择种植
        -- 找到有空槽可种的作物（按钮列表）
        local plantButtons = {}
        for _, crop in ipairs(available) do
            -- 检查原料是否充足
            local hasAll = true
            for _, mat in ipairs(crop.materials or {}) do
                local have = state.truck.cargo[mat.goods_id] or 0
                if have < mat.amount then hasAll = false; break end
            end
            local matDesc = ""
            if crop.materials and #crop.materials > 0 then
                local parts = {}
                for _, mat in ipairs(crop.materials) do
                    local g = Goods.get(mat.goods_id)
                    local gn = g and g.name or mat.goods_id
                    table.insert(parts, gn .. "x" .. mat.amount)
                end
                matDesc = " (" .. table.concat(parts, ", ") .. ")"
            end

            table.insert(plantButtons, F.actionBtn {
                text = hasAll
                    and ("种植 " .. crop.name .. matDesc)
                    or  (crop.name .. matDesc .. " [不足]"),
                variant = hasAll and "secondary" or "secondary",
                disabled = not hasAll,
                height = 32,
                fontSize = Theme.sizes.font_small,
                onClick = function(self)
                    if not hasAll then return end
                    local ok, err = Farm.plant(state, index, crop.id)
                    if ok then
                        print("[Farm] Planted: " .. crop.name .. " in slot " .. index)
                    else
                        print("[Farm] Failed: " .. (err or "unknown"))
                    end
                    router.navigate("farm")
                end,
            })
        end

        if #plantButtons == 0 then
            table.insert(plantButtons, UI.Label {
                text = "无可种植作物",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            })
        end

        return UI.Panel {
            width = "100%", padding = 10,
            backgroundColor = Theme.colors.bg_card,
            borderRadius = Theme.sizes.radius,
            borderWidth = 1, borderColor = Theme.colors.border,
            borderStyle = "dashed",
            gap = 6,
            children = {
                UI.Label {
                    text = "空地 #" .. index,
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.text_dim,
                },
                table.unpack(plantButtons),
            },
        }
    end
end

--- 作物信息卡（作物列表中展示）
---@param state table
---@param crop table
function createCropInfo(state, crop)
    local matParts = {}
    for _, mat in ipairs(crop.materials or {}) do
        local g = Goods.get(mat.goods_id)
        local gn = g and g.name or mat.goods_id
        table.insert(matParts, gn .. " x" .. mat.amount)
    end
    local matText = #matParts > 0 and table.concat(matParts, ", ") or "无需原料"

    local yieldGoods = Goods.get(crop.yield_id)
    local yieldName = yieldGoods and yieldGoods.name or crop.yield_id

    return F.card {
        width = "100%", padding = 8,
        gap = 2,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = crop.name,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = crop.growth_trips .. " 趟 → " .. yieldName .. " x" .. crop.yield_amount,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.success,
                    },
                },
            },
            UI.Label {
                text = "原料: " .. matText,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_dim,
            },
            UI.Label {
                text = crop.desc,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_secondary,
            },
        },
    }
end

function M.update(state, dt, r) end

return M

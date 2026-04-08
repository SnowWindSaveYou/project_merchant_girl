--- 钟楼书院·档案阅览页面
--- 按层级展示已解锁的档案短文，支持展开阅读
local UI       = require("urhox-libs/UI")
local Theme    = require("ui/theme")
local Archives = require("settlement/archives")

local M = {}
---@type table
local router = nil

-- 当前展开阅读的档案 ID
local _expandedId = nil

function M.create(state, params, r)
    router = r
    params = params or {}

    -- 支持从外部传入展开 ID（点击后重建页面）
    if params._expand_id ~= nil then
        _expandedId = params._expand_id
    end

    local read, total = Archives.get_progress(state)
    local groups = Archives.get_grouped(state)

    local children = {}

    -- ── 标题栏 ──
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "📖 档案阅览",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = read .. " / " .. total .. " 已读",
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.text_dim,
            },
        },
    })

    -- ── 分层展示 ──
    local tierOrder = {
        { key = "public",   label = "公开档案",   icon = "📂", color = Theme.colors.info },
        { key = "internal", label = "内部档案",   icon = "📁", color = Theme.colors.warning },
        { key = "sealed",   label = "密封档案",   icon = "🔒", color = Theme.colors.danger },
    }

    local hasAny = false
    for _, tier in ipairs(tierOrder) do
        local entries = groups[tier.key]
        if entries and #entries > 0 then
            hasAny = true
            -- 层级标题
            table.insert(children, UI.Label {
                text = tier.icon .. " " .. tier.label,
                fontSize = Theme.sizes.font_normal,
                fontColor = tier.color,
                marginTop = 8,
            })
            -- 档案卡片
            for _, entry in ipairs(entries) do
                table.insert(children, createArchiveCard(state, entry, tier))
            end
        end
    end

    -- 无内容提示
    if not hasAny then
        table.insert(children, UI.Panel {
            width = "100%", padding = 24,
            alignItems = "center", justifyContent = "center",
            gap = 8,
            children = {
                UI.Label {
                    text = "尚无可阅读的档案",
                    fontSize = Theme.sizes.font_large,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
                UI.Label {
                    text = "提升钟楼书院好感度以解锁更多档案。",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                    textAlign = "center",
                },
            },
        })
    end

    -- 锁定提示：显示下一层级需要多少好感
    local sett = state.settlements and state.settlements.bell_tower
    local gw = sett and sett.goodwill or 0
    local allEntries = Archives.get_all()
    local lockedCount = #allEntries - #Archives.get_available(state)
    if lockedCount > 0 then
        -- 找到下一个未解锁档案的好感需求
        local nextGw = nil
        for _, entry in ipairs(allEntries) do
            local req = entry.required_goodwill or 0
            if req > gw then
                if not nextGw or req < nextGw then
                    nextGw = req
                end
            end
        end
        local hintText = lockedCount .. " 份档案尚未解锁"
        if nextGw then
            hintText = hintText .. "（需好感 " .. nextGw .. "，当前 " .. math.floor(gw) .. "）"
        end
        table.insert(children, UI.Panel {
            width = "100%", padding = 10, marginTop = 4,
            backgroundColor = { 42, 38, 48, 200 },
            borderRadius = Theme.sizes.radius_small,
            alignItems = "center",
            children = {
                UI.Label {
                    text = hintText,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
            },
        })
    end

    return UI.Panel {
        id = "archivesScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 8,
        overflow = "scroll",
        children = children,
    }
end

--- 创建单条档案卡片
---@param state table
---@param entry table
---@param tier table
---@return table widget
function createArchiveCard(state, entry, tier)
    local isRead = Archives.is_read(state, entry.id)
    local isExpanded = (_expandedId == entry.id)

    -- 类别标签
    local CATEGORY_LABELS = {
        geography  = "地理",
        culture    = "文化",
        history    = "历史",
        economy    = "经济",
        faction    = "势力",
        technology = "科技",
        mystery    = "谜团",
    }
    local catLabel = CATEGORY_LABELS[entry.category] or entry.category or ""

    local cardChildren = {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 6,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = isRead and "✅" or "🔹",
                            fontSize = 12,
                        },
                        UI.Label {
                            text = entry.title,
                            fontSize = Theme.sizes.font_normal,
                            fontColor = isRead
                                and Theme.colors.text_secondary
                                or  Theme.colors.text_primary,
                        },
                    },
                },
                UI.Label {
                    text = catLabel,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = tier.color,
                },
            },
        },
    }

    -- 展开内容
    if isExpanded then
        table.insert(cardChildren, UI.Label {
            text = entry.text,
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_primary,
            marginTop = 6,
        })
    end

    -- 卡片背景色
    local bgColor = isExpanded
        and { 48, 44, 52, 240 }
        or  Theme.colors.bg_card
    local borderColor = isExpanded and tier.color or Theme.colors.border

    return UI.Panel {
        width = "100%", padding = 10,
        backgroundColor = bgColor,
        borderRadius = Theme.sizes.radius_small,
        borderWidth = 1, borderColor = borderColor,
        gap = 4,
        children = cardChildren,
        onClick = function(self)
            -- 点击展开/折叠
            if isExpanded then
                _expandedId = nil
            else
                _expandedId = entry.id
                -- 标记已读
                if not isRead then
                    Archives.mark_read(state, entry.id)
                end
            end
            router.navigate("archives", { _expand_id = _expandedId })
        end,
    }
end

function M.update(state, dt, r) end

return M

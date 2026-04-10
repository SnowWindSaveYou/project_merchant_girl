--- 闲逛场景页面
--- 事件卡片式 UI，展示 2-3 个聚落场景
local UI      = require("urhox-libs/UI")
local Theme   = require("ui/theme")
local Stroll  = require("narrative/stroll")
local Goods   = require("economy/goods")
local Graph   = require("map/world_graph")

local M = {}
---@type table
local router = nil

local session = {
    scenes   = {},      -- start() 返回的场景列表
    current  = 1,       -- 当前场景索引
    phase    = "scene", -- "scene" | "result" | "summary"
    results  = {},      -- 每个场景的选择结果
    consumed = nil,     -- 消耗的物品
}

-- ============================================================
-- 辅助
-- ============================================================

--- 解析 ops 日志为可读文本列表
---@param ops_log string[]
---@param settlement_name string|nil 当前聚落名称
---@return string[]
local function format_ops(ops_log, settlement_name)
    local lines = {}
    for _, op in ipairs(ops_log or {}) do
        local action, value = op:match("^([^:]+):(.+)$")
        if not action then goto continue end

        if action == "add_goodwill" then
            local amt = tonumber(value)
            local target_name = settlement_name
            if not amt then
                -- "add_goodwill:settlement:N" 格式
                local sid, n = value:match("^(.+):([%d%-]+)$")
                amt = tonumber(n)
                if sid then
                    target_name = Graph.get_node_name(sid) or sid
                end
            end
            if amt and amt ~= 0 then
                local prefix = target_name and (target_name .. "好感 ") or "好感 "
                table.insert(lines, prefix .. (amt > 0 and "+" or "") .. amt)
            end
        elseif action == "add_credits" or action == "add_credit" then
            local n = tonumber(value)
            if n and n ~= 0 then
                table.insert(lines, (n > 0 and "信用币 +" or "信用币 ") .. n)
            end
        elseif action == "add_goods" then
            local gid, cnt = value:match("^(.+):([%d%-]+)$")
            if gid then
                local g = Goods.get(gid)
                local name = g and g.name or gid
                local n = tonumber(cnt) or 0
                if n ~= 0 then
                    table.insert(lines, name .. (n > 0 and " +" or " ") .. n)
                end
            end
        elseif action == "consume_goods" or action == "lose_goods" then
            local gid, cnt = value:match("^(.+):(%d+)$")
            if gid then
                local g = Goods.get(gid)
                local name = g and g.name or gid
                table.insert(lines, name .. " -" .. (cnt or "1"))
            end
        elseif action == "add_relation" then
            local n = tonumber(value)
            if n and n ~= 0 then
                table.insert(lines, (n > 0 and "羁绊 +" or "羁绊 ") .. n)
            end
        end

        ::continue::
    end
    return lines
end

-- ============================================================
-- 场景卡片
-- ============================================================

local function createSceneView(state, scene, sceneIdx, totalScenes)
    local choices = scene.choices or {}
    local choiceChildren = {}

    for i, choice in ipairs(choices) do
        table.insert(choiceChildren, UI.Button {
            text = choice.text,
            variant = i == 1 and "primary" or "secondary",
            width = "100%", height = 44,
            onClick = function(self)
                local result = Stroll.apply_choice(state, scene, i)
                session.results[session.current] = {
                    scene_title = scene.title,
                    result_text = result.result_text,
                    ops_log     = result.ops_log,
                }
                session.phase = "result"
                router.navigate("stroll", { _continue = true })
            end,
        })
    end

    local cardChildren = {
        -- 进度提示
        UI.Label {
            text = "闲逛 " .. sceneIdx .. "/" .. totalScenes,
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_dim,
        },
        -- 标题
        UI.Label {
            text = scene.title or "未知场景",
            fontSize = Theme.sizes.font_title,
            fontColor = Theme.colors.text_primary,
        },
        -- 正文
        UI.Label {
            text = scene.text or "",
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            lineHeight = 1.6,
        },
        -- 分割线
        UI.Panel {
            width = "100%", height = 1,
            backgroundColor = Theme.colors.divider,
        },
    }
    for _, btn in ipairs(choiceChildren) do
        table.insert(cardChildren, btn)
    end

    return UI.Panel {
        id = "strollSceneView",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.ScrollView {
                width = "90%", maxWidth = 420,
                maxHeight = "85%",
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = Theme.sizes.padding_large,
                        backgroundColor = Theme.colors.bg_card,
                        borderRadius = Theme.sizes.radius_large,
                        borderWidth = Theme.sizes.border,
                        borderColor = Theme.colors.info,
                        gap = 12,
                        children = cardChildren,
                    },
                },
            },
        },
    }
end

-- ============================================================
-- 结果卡片
-- ============================================================

local function createResultView(state)
    local result = session.results[session.current]
    if not result then
        -- 异常回退：交由 M.create 重新路由到 summary
        session.phase = "summary"
        return nil
    end

    local cur_loc = state.map and state.map.current_location or nil
    local sname = cur_loc and Graph.get_node_name(cur_loc) or nil
    local opsLines = format_ops(result.ops_log, sname)
    local opsText = #opsLines > 0 and table.concat(opsLines, "  ·  ") or ""

    local isLast = session.current >= #session.scenes
    local btnText = isLast and "查看汇总" or "继续逛逛"

    local contentChildren = {
        UI.Label {
            text = result.scene_title or "",
            fontSize = Theme.sizes.font_large,
            fontColor = Theme.colors.text_primary,
        },
        UI.Label {
            text = result.result_text,
            fontSize = Theme.sizes.font_normal,
            fontColor = Theme.colors.text_secondary,
            lineHeight = 1.5,
        },
    }

    -- ops 效果
    if opsText ~= "" then
        table.insert(contentChildren, UI.Panel {
            width = "100%",
            padding = 8,
            backgroundColor = Theme.colors.bg_secondary,
            borderRadius = 6,
            children = {
                UI.Label {
                    text = opsText,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.accent,
                    textAlign = "center",
                },
            },
        })
    end

    table.insert(contentChildren, UI.Button {
        text = btnText,
        variant = "primary", width = "100%", height = 44, marginTop = 8,
        onClick = function(self)
            if isLast then
                session.phase = "summary"
            else
                session.current = session.current + 1
                session.phase = "scene"
            end
            router.navigate("stroll", { _continue = true })
        end,
    })

    return UI.Panel {
        id = "strollResultView",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.ScrollView {
                width = "90%", maxWidth = 420,
                maxHeight = "85%",
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = Theme.sizes.padding_large,
                        backgroundColor = Theme.colors.bg_card,
                        borderRadius = Theme.sizes.radius_large,
                        borderWidth = Theme.sizes.border,
                        borderColor = Theme.colors.border,
                        gap = 12, alignItems = "center",
                        children = contentChildren,
                    },
                },
            },
        },
    }
end

-- ============================================================
-- 汇总页
-- ============================================================

local function createSummaryView(state)
    local summaryChildren = {
        UI.Label {
            text = "闲逛结束",
            fontSize = Theme.sizes.font_title,
            fontColor = Theme.colors.text_primary,
        },
    }

    -- 消耗提示
    if session.consumed then
        local g = Goods.get(session.consumed)
        table.insert(summaryChildren, UI.Label {
            text = "消耗：1 " .. (g and g.name or session.consumed),
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.danger,
        })
    end

    -- 分割线
    table.insert(summaryChildren, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Theme.colors.divider,
    })

    -- 各场景摘要
    local cur_loc = state.map and state.map.current_location or nil
    local sname = cur_loc and Graph.get_node_name(cur_loc) or nil
    for i, result in ipairs(session.results) do
        local opsLines = format_ops(result.ops_log, sname)
        local opsText = #opsLines > 0 and table.concat(opsLines, "  ") or "无额外收获"

        table.insert(summaryChildren, UI.Panel {
            width = "100%", gap = 4,
            children = {
                UI.Label {
                    text = "📍 " .. (result.scene_title or ("场景 " .. i)),
                    fontSize = Theme.sizes.font_normal,
                    fontColor = Theme.colors.text_primary,
                },
                UI.Label {
                    text = opsText,
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                },
            },
        })
    end

    -- 分割线
    table.insert(summaryChildren, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Theme.colors.divider,
    })

    -- 返回按钮
    table.insert(summaryChildren, UI.Button {
        text = "返回聚落",
        variant = "primary", width = "100%", height = 44,
        onClick = function(self)
            session.scenes  = {}
            session.results = {}
            session.phase   = "scene"
            router.navigate("home")
        end,
    })

    return UI.Panel {
        id = "strollSummaryView",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_overlay,
        justifyContent = "center", alignItems = "center",
        children = {
            UI.ScrollView {
                width = "90%", maxWidth = 420,
                maxHeight = "85%",
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = Theme.sizes.padding_large,
                        backgroundColor = Theme.colors.bg_card,
                        borderRadius = Theme.sizes.radius_large,
                        borderWidth = Theme.sizes.border,
                        borderColor = Theme.colors.border,
                        gap = 12,
                        children = summaryChildren,
                    },
                },
            },
        },
    }
end

-- ============================================================
-- 页面入口
-- ============================================================

function M.create(state, params, r)
    router = r
    params = params or {}

    -- 初始化 session
    if params.scenes then
        session.scenes   = params.scenes
        session.consumed = params.consumed
        session.current  = 1
        session.phase    = "scene"
        session.results  = {}
    end

    -- 内部导航（保持 session 不变）
    if params._continue then
        -- phase 已在上一次 onClick 中更新
    end

    if not session.scenes or #session.scenes == 0 then
        router.navigate("home")
        return nil
    end

    if session.phase == "result" then
        local view = createResultView(state)
        if view then return view end
        -- createResultView 返回 nil 说明 phase 已切到 summary，fallthrough
    end
    if session.phase == "summary" then
        return createSummaryView(state)
    else
        local scene = session.scenes[session.current]
        if not scene then
            session.phase = "summary"
            return createSummaryView(state)
        end
        return createSceneView(state, scene, session.current, #session.scenes)
    end
end

function M.update(state, dt, r) end

return M

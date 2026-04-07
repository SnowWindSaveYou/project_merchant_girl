--- 通用 Gal (视觉小说) 对话 UI 模块
--- 用于篝火对话和 NPC 拜访，统一的立绘 + 底部对话框交互
--- 使用方法:
---   local Gal = require("ui/gal_dialogue")
---   local view = Gal.createDialogueView({ ... })
---   local view = Gal.createResultView({ ... })
---   local view = Gal.createHistoryView({ ... })

local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Factions = require("settlement/factions")

local M = {}

-- ============================================================
-- 立绘资源映射
-- ============================================================

--- 主角立绘
local PROTAGONIST_PORTRAITS = {
    linli = {
        name     = "林砾",
        color    = { 142, 178, 210, 255 },
        bgColor  = { 42, 52, 58, 240 },
        portrait = "image/linli_portrait_20260405231808.png",
    },
    taoxia = {
        name     = "陶夏",
        color    = { 218, 168, 102, 255 },
        bgColor  = { 58, 48, 36, 240 },
        portrait = "image/taoxia_portrait_20260405231808.png",
    },
}

--- NPC 独立立绘（势力领袖 + 流浪NPC）
local NPC_PORTRAITS = {
    shen_he   = "image/portrait_shen_he_20260406000120.png",
    han_ce    = "image/portrait_han_ce_20260406000106.png",
    wu_shiqi  = "image/portrait_wu_shiqi_20260406000058.png",
    bai_shu   = "image/portrait_bai_shu_20260406000056.png",
    meng_hui  = "image/portrait_meng_hui_20260406000106.png",
    ming_sha  = "image/portrait_ming_sha_20260406000227.png",
}

--- 势力通用立绘（非领袖 NPC 使用）
local FACTION_PORTRAITS = {
    farm    = "image/portrait_faction_farm_20260406000212.png",
    tech    = "image/portrait_faction_tech_20260406000259.png",
    scav    = "image/portrait_faction_scav_20260406000214.png",
    scholar = "image/portrait_faction_scholar_20260406000214.png",
}

-- ============================================================
-- 根据 NPC 信息获取立绘路径
-- ============================================================

--- 获取 NPC 的立绘路径
---@param npc table|nil  NPC 元数据 (来自 npc_manager)
---@return string portrait_path
local function get_npc_portrait(npc)
    if not npc then return FACTION_PORTRAITS.farm end

    -- 优先检查独立立绘
    if NPC_PORTRAITS[npc.id] then
        return NPC_PORTRAITS[npc.id]
    end

    -- 其次按势力使用通用立绘
    if npc.settlement then
        local fid = Factions.get_faction(npc.settlement)
        if fid and FACTION_PORTRAITS[fid] then
            return FACTION_PORTRAITS[fid]
        end
    end

    -- 流浪 NPC 无势力，降级到农耕派
    return FACTION_PORTRAITS.farm
end

-- ============================================================
-- 获取说话人显示配置
-- ============================================================

--- 获取说话人的名字、颜色、立绘
---@param speaker string  "linli"|"taoxia"|"npc"
---@param npc table|nil   当 speaker=="npc" 时使用
---@return table  { name, color, bgColor, portrait }
local function get_speaker_cfg(speaker, npc)
    if speaker == "npc" and npc then
        return {
            name     = npc.name or "???",
            color    = npc.color or { 180, 170, 150, 255 },
            bgColor  = npc.bg or { 45, 40, 35, 240 },
            portrait = get_npc_portrait(npc),
        }
    end
    return PROTAGONIST_PORTRAITS[speaker] or PROTAGONIST_PORTRAITS.linli
end

-- ============================================================
-- 公共 API: createDialogueView
-- ============================================================

--- 创建 Gal 模式对话视图
---@param opts table
---  opts.dialogue    table   当前对话数据 (steps, choices, title)
---  opts.step        number  当前步数 (1-based)
---  opts.npc         table|nil  NPC 元数据（NPC 对话时）
---  opts.topInfo     string|nil  顶栏附加信息（如 "消耗: -1 干粮"）
---  opts.onAdvance   function  点击推进的回调
---  opts.onChoice    function(i) 选择的回调
---  opts.onHistory   function  点击 LOG 的回调
---  opts.onClose     function  点击关闭的回调
---@return table UI element
function M.createDialogueView(opts)
    local d       = opts.dialogue
    local steps   = d.steps or {}
    local maxStep = #steps
    local curStep = math.min(opts.step or 1, maxStep)
    local allShown = curStep >= maxStep
    local npc     = opts.npc

    -- 当前说话人
    local curSpeakerKey = steps[curStep] and steps[curStep].speaker or "linli"
    local curCfg = get_speaker_cfg(curSpeakerKey, npc)
    local curText = steps[curStep] and steps[curStep].text or ""

    -- 确定左右两侧角色
    -- 篝火模式：左林砾 右陶夏
    -- NPC模式：左主角（最近说话的主角）右NPC
    local leftCfg, rightCfg, leftDim, rightDim

    if npc then
        -- NPC 模式：主角在左，NPC 在右
        local protagonistKey = (curSpeakerKey ~= "npc") and curSpeakerKey or "linli"
        leftCfg  = get_speaker_cfg(protagonistKey, nil)
        rightCfg = get_speaker_cfg("npc", npc)
        leftDim  = (curSpeakerKey == "npc")
        rightDim = (curSpeakerKey ~= "npc")
    else
        -- 篝火模式：林砾在左，陶夏在右
        leftCfg  = PROTAGONIST_PORTRAITS.linli
        rightCfg = PROTAGONIST_PORTRAITS.taoxia
        leftDim  = (curSpeakerKey ~= "linli")
        rightDim = (curSpeakerKey ~= "taoxia")
    end

    -- ── 操作区（仅在所有对话展示完毕后显示选项按钮）──
    local actionChildren = {}

    if allShown then
        local choices = d.choices or {}
        for i, choice in ipairs(choices) do
            table.insert(actionChildren, UI.Button {
                text = choice.text,
                variant = i == 1 and "primary" or "secondary",
                height = 36,
                flexGrow = 1,
                fontSize = 13,
                onClick = function(self)
                    if opts.onChoice then opts.onChoice(i) end
                end,
            })
        end
    end

    -- ── 顶栏 ──
    local topLeftChildren = {
        UI.Label {
            text = d.title or "",
            fontSize = 13,
            fontColor = { 200, 180, 140, 200 },
            flexShrink = 1,
        },
    }

    if opts.topInfo and opts.topInfo ~= "" then
        table.insert(topLeftChildren, UI.Label {
            text = opts.topInfo,
            fontSize = 11,
            fontColor = { 150, 140, 120, 180 },
            flexShrink = 1,
        })
    end

    -- ── 整页布局：立绘全屏底层，对话框半透明叠在前面 ──
    return UI.Panel {
        id = "galScreen",
        width = "100%", height = "100%",
        backgroundColor = { 18, 15, 12, 255 },
        children = {
            -- ▼ 立绘层（absolute 全屏背景，对话框自然遮挡下半身）
            -- 面板宽 95% → contain 按宽适配 → 人物很大
            -- 面板高 95% → 人物居中后自然落在屏幕中上部
            -- 对话框 (前景层) 的不透明背景覆盖下半身，无需 overflow:hidden
            UI.Panel {
                width = "100%", height = "100%",
                position = "absolute",
                left = 0, top = 0,
                children = {
                    -- 左侧立绘（偏左放置）
                    UI.Panel {
                        width = "95%", height = "95%",
                        backgroundImage = leftCfg.portrait,
                        backgroundFit = "contain",
                        imageTint = leftDim and { 80, 80, 80, 160 } or nil,
                        position = "absolute",
                        left = "-22%",
                        top = "3%",
                    },
                    -- 右侧立绘（偏右放置）
                    UI.Panel {
                        width = "95%", height = "95%",
                        backgroundImage = rightCfg.portrait,
                        backgroundFit = "contain",
                        imageTint = rightDim and { 80, 80, 80, 160 } or nil,
                        position = "absolute",
                        right = "-22%",
                        top = "3%",
                    },
                },
            },

            -- ▼ 前景 UI 层（normal flow，顶栏 + 弹性空白 + 底部对话框）
            -- 顶栏
            UI.Panel {
                width = "100%", height = 44,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingLeft = 16, paddingRight = 8,
                backgroundColor = { 22, 19, 16, 180 },
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 8, alignItems = "center",
                        flexShrink = 1,
                        children = topLeftChildren,
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 2,
                        children = {
                            UI.Button {
                                text = "LOG",
                                variant = "ghost",
                                width = 48, height = 32,
                                fontSize = 11,
                                onClick = function(self)
                                    if opts.onHistory then opts.onHistory() end
                                end,
                            },
                            UI.Button {
                                text = "X",
                                variant = "ghost",
                                width = 36, height = 32,
                                fontSize = 13,
                                onClick = function(self)
                                    if opts.onClose then opts.onClose() end
                                end,
                            },
                        },
                    },
                },
            },

            -- 空白区域（固定占 55%，让立绘在此区域透出）
            UI.Panel { height = "55%" },

            -- 底部对话框（占剩余 ~40% 空间，覆盖立绘下半身）
            -- 点击对话框即可推进对话（未读完时）
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                backgroundColor = { 15, 13, 10, 240 },
                borderTopWidth = 1,
                borderColor = { 80, 65, 40, 80 },
                paddingLeft = 20, paddingRight = 20,
                paddingTop = 16, paddingBottom = 20,
                gap = 8,
                onClick = (not allShown) and function(self)
                    if opts.onAdvance then opts.onAdvance() end
                end or nil,
                children = {
                    -- 说话人名字
                    UI.Panel {
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 2, paddingBottom = 2,
                        backgroundColor = curCfg.bgColor,
                        borderRadius = 4,
                        alignSelf = "flex-start",
                        children = {
                            UI.Label {
                                text = curCfg.name,
                                fontSize = 13,
                                fontColor = curCfg.color,
                            },
                        },
                    },
                    -- 对话文字
                    UI.Label {
                        text = curText,
                        fontSize = 15,
                        fontColor = { 225, 220, 210, 255 },
                        lineHeight = 1.7,
                        whiteSpace = "normal",
                    },
                    -- 操作区（仅在有选项时显示）
                    allShown and UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 8,
                        marginTop = 6,
                        children = actionChildren,
                    } or nil,
                },
            },
        },
    }
end

-- ============================================================
-- 公共 API: createHistoryView
-- ============================================================

--- 创建气泡式历史对话视图
---@param opts table
---  opts.dialogue    table   当前对话数据
---  opts.step        number  已展示步数
---  opts.npc         table|nil  NPC 元数据
---  opts.onBack      function  返回对话的回调
---@return table UI element
function M.createHistoryView(opts)
    local d       = opts.dialogue
    local steps   = d.steps or {}
    local curStep = math.min(opts.step or 1, #steps)
    local npc     = opts.npc

    local bubbles = {}

    for i = 1, curStep do
        local s   = steps[i]
        local cfg = get_speaker_cfg(s.speaker, npc)
        local isRight = (s.speaker ~= "npc" and s.speaker == "linli")

        table.insert(bubbles, UI.Panel {
            width = "100%",
            alignItems = isRight and "flex-end" or "flex-start",
            gap = 2,
            children = {
                UI.Label {
                    text = cfg.name,
                    fontSize = 11,
                    fontColor = cfg.color,
                    marginLeft = isRight and 0 or 4,
                    marginRight = isRight and 4 or 0,
                },
                UI.Panel {
                    maxWidth = "78%",
                    padding = 10,
                    backgroundColor = cfg.bgColor,
                    borderRadius = 8,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = s.text or "",
                            fontSize = 14,
                            fontColor = { 220, 215, 208, 255 },
                            lineHeight = 1.5,
                            whiteSpace = "normal",
                            flexShrink = 1,
                        },
                    },
                },
            },
        })
    end

    return UI.Panel {
        id = "galScreen",
        width = "100%", height = "100%",
        backgroundColor = { 18, 15, 12, 255 },
        children = {
            -- 顶栏
            UI.Panel {
                width = "100%", height = 44,
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingLeft = 16, paddingRight = 8,
                backgroundColor = { 22, 19, 16, 200 },
                children = {
                    UI.Label {
                        text = (d.title or "") .. " - LOG",
                        fontSize = 13,
                        fontColor = { 200, 180, 140, 200 },
                    },
                    UI.Button {
                        text = "返回",
                        variant = "ghost",
                        width = 56, height = 32,
                        fontSize = 12,
                        onClick = function(self)
                            if opts.onBack then opts.onBack() end
                        end,
                    },
                },
            },
            -- 气泡列表
            UI.ScrollView {
                width = "100%",
                flexGrow = 1, flexBasis = 0,
                padding = 12,
                gap = 12,
                showScrollbar = false,
                children = bubbles,
            },
        },
    }
end

-- ============================================================
-- 公共 API: createResultView
-- ============================================================

--- 创建结果展示视图
---@param opts table
---  opts.dialogue    table       对话数据
---  opts.result      table       结果数据 { result_text, memory, ops_log }
---  opts.npc         table|nil   NPC 元数据
---  opts.extraInfo   table|nil   额外信息行 { text, color }[]
---  opts.onClose     function    关闭回调
---@return table UI element
function M.createResultView(opts)
    local d      = opts.dialogue
    local result = opts.result or {}
    local npc    = opts.npc

    -- 确定立绘
    local leftCfg, rightCfg
    if npc then
        leftCfg  = PROTAGONIST_PORTRAITS.linli
        rightCfg = get_speaker_cfg("npc", npc)
    else
        leftCfg  = PROTAGONIST_PORTRAITS.linli
        rightCfg = PROTAGONIST_PORTRAITS.taoxia
    end

    -- 结果卡片内容
    local cardChildren = {}

    -- 标题
    table.insert(cardChildren, UI.Label {
        text = d and d.title or "",
        fontSize = 18,
        fontColor = { 255, 220, 160, 255 },
        textAlign = "center",
    })

    table.insert(cardChildren, UI.Panel {
        width = "80%", height = 1,
        backgroundColor = { 80, 65, 40, 80 },
    })

    -- 结果文字
    if result.result_text and result.result_text ~= "" then
        table.insert(cardChildren, UI.Label {
            text = result.result_text,
            fontSize = 14,
            fontColor = { 200, 195, 185, 255 },
            lineHeight = 1.7,
            textAlign = "center",
            whiteSpace = "normal",
            paddingLeft = 12, paddingRight = 12,
        })
    end

    -- 回忆碎片
    if result.memory then
        table.insert(cardChildren, UI.Panel {
            width = "90%", padding = 12,
            backgroundColor = { 40, 35, 28, 240 },
            borderRadius = 8,
            borderWidth = 1, borderColor = { 120, 100, 60, 80 },
            gap = 4, alignItems = "center",
            children = {
                UI.Label {
                    text = "获得回忆碎片",
                    fontSize = 11,
                    fontColor = { 218, 168, 102, 255 },
                },
                UI.Label {
                    text = result.memory.title,
                    fontSize = 15,
                    fontColor = { 230, 225, 218, 255 },
                    textAlign = "center",
                },
                UI.Label {
                    text = result.memory.desc,
                    fontSize = 12,
                    fontColor = { 170, 165, 155, 255 },
                    textAlign = "center",
                    whiteSpace = "normal",
                },
            },
        })
    end

    -- ops 效果摘要
    if result.ops_log and #result.ops_log > 0 then
        table.insert(cardChildren, UI.Label {
            text = table.concat(result.ops_log, "  "),
            fontSize = 11,
            fontColor = { 130, 125, 115, 255 },
            textAlign = "center",
            whiteSpace = "normal",
        })
    end

    -- 额外信息（如好感度、关系阶段等）
    if opts.extraInfo then
        for _, info in ipairs(opts.extraInfo) do
            table.insert(cardChildren, UI.Label {
                text = info.text,
                fontSize = 11,
                fontColor = info.color or { 218, 168, 102, 255 },
                textAlign = "center",
            })
        end
    end

    -- 返回按钮
    table.insert(cardChildren, UI.Button {
        text = "回到据点",
        variant = "primary",
        width = "80%", height = 40,
        marginTop = 8,
        onClick = function(self)
            if opts.onClose then opts.onClose() end
        end,
    })

    return UI.Panel {
        id = "galScreen",
        width = "100%", height = "100%",
        backgroundColor = { 18, 15, 12, 255 },
        justifyContent = "flex-end",
        children = {
            -- ▼ 立绘层（absolute 全屏背景）
            UI.Panel {
                width = "100%", height = "100%",
                position = "absolute",
                left = 0, top = 0,
                children = {
                    UI.Panel {
                        width = "95%", height = "95%",
                        backgroundImage = leftCfg.portrait,
                        backgroundFit = "contain",
                        position = "absolute",
                        left = "-22%",
                        top = "3%",
                    },
                    UI.Panel {
                        width = "95%", height = "95%",
                        backgroundImage = rightCfg.portrait,
                        backgroundFit = "contain",
                        position = "absolute",
                        right = "-22%",
                        top = "3%",
                    },
                },
            },

            -- ▼ 弹性空白
            UI.Panel { flexGrow = 1, flexBasis = 0 },

            -- ▼ 结果卡片（半透明叠在立绘前面）
            UI.Panel {
                width = "100%",
                backgroundColor = { 15, 13, 10, 200 },
                borderTopWidth = 1,
                borderColor = { 80, 65, 40, 80 },
                padding = 20,
                gap = 10,
                alignItems = "center",
                children = cardChildren,
            },
        },
    }
end

return M

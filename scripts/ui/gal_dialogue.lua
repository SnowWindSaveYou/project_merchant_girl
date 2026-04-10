--- 通用 Gal (视觉小说) 对话 UI 模块
--- 用于篝火对话和 NPC 拜访，统一的立绘 + 底部对话框交互
--- 使用方法:
---   local Gal = require("ui/gal_dialogue")
---   local view = Gal.createDialogueView({ ... })
---   local view = Gal.createResultView({ ... })
---   local view = Gal.createHistoryView({ ... })

local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")
local F     = require("ui/ui_factory")
local Factions = require("settlement/factions")

local NpcManager = require("narrative/npc_manager")

local M = {}

-- ============================================================
-- 立绘资源映射
-- ============================================================

--- 主角立绘（含表情差分）
local PROTAGONIST_PORTRAITS = {
    linli = {
        name     = "林砾",
        color    = { 142, 178, 210, 255 },
        bgColor  = { 42, 52, 58, 240 },
        portrait = "image/linli_portrait_20260405231808.png",
        expressions = {
            normal    = "image/linli_portrait_20260405231808.png",
            happy     = "image/linli_happy_v2_20260409082011.png",
            sad       = "image/linli_sad_20260409080555.png",
            surprised = "image/linli_surprised_20260409080550.png",
            angry     = "image/linli_angry_v2_20260409082114.png",
            thinking  = "image/linli_thinking_20260409080553.png",
        },
    },
    taoxia = {
        name     = "陶夏",
        color    = { 218, 168, 102, 255 },
        bgColor  = { 58, 48, 36, 240 },
        portrait = "image/taoxia_portrait_v3.png",
        expressions = {
            normal    = "image/taoxia_portrait_v3.png",
            happy     = "image/taoxia_happy_20260409080542.png",
            sad       = "image/taoxia_sad_20260409080556.png",
            surprised = "image/taoxia_surprised_20260409080548.png",
            angry     = "image/taoxia_angry_20260409080551.png",
            thinking  = "image/taoxia_thinking_20260409080547.png",
        },
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
    dao_yu    = "image/portrait_dao_yu_20260408072957.png",
    xie_ling  = "image/portrait_xie_ling_20260408073029.png",
    ji_wei     = "image/portrait_ji_wei_20260408124639.png",
    old_gan    = "image/portrait_old_gan_20260408124632.png",
    a_xiu      = "image/portrait_a_xiu_20260409120249.png",
    cheng_yuan = "image/portrait_cheng_yuan_20260409120343.png",
    su_mo      = "image/portrait_su_mo_20260409120418.png",
}

--- 势力通用立绘（非领袖 NPC 使用）
local FACTION_PORTRAITS = {
    farm    = "image/portrait_faction_farm_20260406000212.png",
    tech    = "image/portrait_faction_tech_20260406000259.png",
    scav    = "image/portrait_faction_scav_20260406000214.png",
    scholar = "image/portrait_faction_scholar_20260406000214.png",
}

-- ============================================================
-- 表情差分辅助
-- ============================================================

--- 获取主角指定表情的立绘路径
---@param key string  主角 key ("linli"|"taoxia")
---@param expression string|nil  表情 key ("happy"|"sad"|"surprised"|"angry"|"thinking"|nil)
---@return string portrait_path
local function get_expression_portrait(key, expression)
    local cfg = PROTAGONIST_PORTRAITS[key]
    if not cfg then return "" end
    if expression and cfg.expressions and cfg.expressions[expression] then
        return cfg.expressions[expression]
    end
    return cfg.portrait
end

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

--- 判断 speaker 是否为 NPC（"npc" 或具体 NPC ID）
local function is_npc_speaker(speaker)
    if speaker == "npc" then return true end
    if speaker == "narrator" then return false end
    if PROTAGONIST_PORTRAITS[speaker] then return false end
    -- 不是主角也不是旁白，检查是否是已注册的 NPC ID
    return NpcManager.get_npc(speaker) ~= nil
end

--- 获取说话人的名字、颜色、立绘
---@param speaker string  "linli"|"taoxia"|"npc"|"dao_yu"|"xie_ling"|...
---@param npc table|nil   当 speaker=="npc" 时使用的主 NPC
---@return table  { name, color, bgColor, portrait }
local function get_speaker_cfg(speaker, npc)
    -- "npc" → 使用传入的主 NPC 数据
    if speaker == "npc" and npc then
        return {
            name     = npc.name or "???",
            color    = npc.color or { 180, 170, 150, 255 },
            bgColor  = npc.bg or { 45, 40, 35, 240 },
            portrait = get_npc_portrait(npc),
        }
    end
    -- 主角直接返回
    if PROTAGONIST_PORTRAITS[speaker] then
        return PROTAGONIST_PORTRAITS[speaker]
    end
    -- 具体 NPC ID → 查 NpcManager
    local npcData = NpcManager.get_npc(speaker)
    if npcData then
        return {
            name     = npcData.name or "???",
            color    = npcData.color or { 180, 170, 150, 255 },
            bgColor  = npcData.bg or { 45, 40, 35, 240 },
            portrait = get_npc_portrait(npcData),
        }
    end
    -- 兜底
    return PROTAGONIST_PORTRAITS.linli
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
---  opts.background  string|nil  背景图路径（CG 场景）
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
    local curExpression = steps[curStep] and steps[curStep].expression or nil

    -- 确定左右两侧立绘（统一逻辑：NPC 拜访 / 主线剧情 / 纯主角篝火）
    local leftCfg, rightCfg, leftDim, rightDim
    local leftPortrait, rightPortrait  -- 实际显示的立绘路径（含表情差分）

    -- ── 统一立绘决策（不再区分 NPC 模式 / 篝火模式）──
    local curIsNpc = is_npc_speaker(curSpeakerKey)
    local curIsProtagonist = PROTAGONIST_PORTRAITS[curSpeakerKey] ~= nil

    -- 回溯查找当前步及之前最近出现的 NPC 说话者（用于"NPC 留在场上"效果）
    local recentNpcKey = nil
    for si = curStep, 1, -1 do
        local sp = steps[si] and steps[si].speaker
        if is_npc_speaker(sp) then
            recentNpcKey = sp
            break
        end
    end
    -- 场景中是否有 NPC 对手方（npc 参数 或 对话中出现过 NPC）
    local hasNpcCounterpart = (recentNpcKey ~= nil) or (npc ~= nil)

    if curIsNpc then
        -- ① NPC 说话：左侧回溯最近主角，右侧当前 NPC
        local lastProtagonist = "linli"
        for si = curStep - 1, 1, -1 do
            local prev = steps[si] and steps[si].speaker
            if PROTAGONIST_PORTRAITS[prev] then
                lastProtagonist = prev
                break
            end
        end
        leftCfg   = PROTAGONIST_PORTRAITS[lastProtagonist]
        rightCfg  = get_speaker_cfg(curSpeakerKey, npc)
        leftDim   = true
        rightDim  = false
        leftPortrait  = leftCfg.portrait
        rightPortrait = rightCfg.portrait

    elseif hasNpcCounterpart then
        -- ② 主角说话，场景中有 NPC：左侧主角，右侧 NPC（暗）
        leftCfg  = curIsProtagonist and PROTAGONIST_PORTRAITS[curSpeakerKey]
                                     or PROTAGONIST_PORTRAITS.linli
        rightCfg = recentNpcKey and get_speaker_cfg(recentNpcKey, npc)
                                 or get_speaker_cfg("npc", npc)
        leftDim   = not curIsProtagonist  -- 旁白时左侧也暗
        rightDim  = true
        leftPortrait  = curIsProtagonist
            and get_expression_portrait(curSpeakerKey, curExpression)
             or leftCfg.portrait
        rightPortrait = rightCfg.portrait

    else
        -- ③ 纯主角篝火：林砾固定左，陶夏固定右
        leftCfg  = PROTAGONIST_PORTRAITS.linli
        rightCfg = PROTAGONIST_PORTRAITS.taoxia
        leftDim  = (curSpeakerKey ~= "linli")
        rightDim = (curSpeakerKey ~= "taoxia")
        if curSpeakerKey == "linli" then
            leftPortrait  = get_expression_portrait("linli", curExpression)
            rightPortrait = rightCfg.portrait
        elseif curSpeakerKey == "taoxia" then
            leftPortrait  = leftCfg.portrait
            rightPortrait = get_expression_portrait("taoxia", curExpression)
        else
            leftPortrait  = leftCfg.portrait
            rightPortrait = rightCfg.portrait
        end
    end

    -- ── 操作区（仅在所有对话展示完毕后显示选项按钮）──
    local actionChildren = {}

    if allShown then
        local choices = d.choices or {}
        for i, choice in ipairs(choices) do
            table.insert(actionChildren, F.actionBtn {
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
    local bgImage = opts.background
    local galChildren = {}

    -- ▼ CG 背景层（有背景图时显示）
    if bgImage then
        table.insert(galChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute",
            left = 0, top = 0,
            backgroundImage = bgImage,
            backgroundFit = "cover",
        })
    end

    -- ▼ 立绘层（absolute 全屏背景，对话框自然遮挡下半身）
    -- 面板宽 95% → contain 按宽适配 → 人物很大
    -- 面板高 95% → 人物居中后自然落在屏幕中上部
    -- 对话框 (前景层) 的不透明背景覆盖下半身，无需 overflow:hidden
    table.insert(galChildren, UI.Panel {
        width = "100%", height = "100%",
        position = "absolute",
        left = 0, top = 0,
        children = {
            -- 左侧立绘（偏左放置，使用表情差分）
            UI.Panel {
                width = "95%", height = "95%",
                backgroundImage = leftPortrait,
                backgroundFit = "contain",
                imageTint = leftDim and { 80, 80, 80, 160 } or nil,
                position = "absolute",
                left = "-22%",
                top = "3%",
            },
            -- 右侧立绘（偏右放置，使用表情差分）
            UI.Panel {
                width = "95%", height = "95%",
                backgroundImage = rightPortrait,
                backgroundFit = "contain",
                imageTint = rightDim and { 80, 80, 80, 160 } or nil,
                position = "absolute",
                right = "-22%",
                top = "3%",
            },
        },
    })

    -- ▼ 前景 UI 层（normal flow，顶栏 + 弹性空白 + 底部对话框）
    -- 顶栏
    table.insert(galChildren, UI.Panel {
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
                    F.actionBtn {
                        text = "LOG",
                        variant = "ghost",
                        width = 48, height = 32,
                        fontSize = 11,
                        onClick = function(self)
                            if opts.onHistory then opts.onHistory() end
                        end,
                    },
                    F.actionBtn {
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
    })

    -- 空白区域（固定占 55%，让立绘在此区域透出）
    table.insert(galChildren, UI.Panel { height = "55%" })

    -- 底部对话框（占剩余 ~40% 空间，覆盖立绘下半身）
    -- 点击对话框即可推进对话（未读完时）
    local dialogueBoxChildren = {
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
    }
    -- 操作区（仅在有选项时显示）
    if allShown then
        table.insert(dialogueBoxChildren, UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            gap = 8,
            marginTop = 6,
            children = actionChildren,
        })
    end

    table.insert(galChildren, UI.Panel {
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
        children = dialogueBoxChildren,
    })

    return UI.Panel {
        id = "galScreen",
        width = "100%", height = "100%",
        backgroundColor = { 18, 15, 12, 255 },
        children = galChildren,
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
        local isRight = not is_npc_speaker(s.speaker) and s.speaker ~= "narrator"

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
                    width = "75%",
                    padding = 10,
                    backgroundColor = cfg.bgColor,
                    borderRadius = 8,
                    children = {
                        UI.Label {
                            text = s.text or "",
                            fontSize = 14,
                            fontColor = { 220, 215, 208, 255 },
                            lineHeight = 1.5,
                            whiteSpace = "normal",
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
                    F.actionBtn {
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

    -- 额外信息（仅限玩家可见的提示）
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
    table.insert(cardChildren, F.actionBtn {
        text = "回到据点",
        variant = "primary",
        width = "80%", height = 40,
        marginTop = 8,
        onClick = function(self)
            if opts.onClose then opts.onClose() end
        end,
    })

    local resultChildren = {}

    -- ▼ CG 背景层（有背景图时显示）
    local bgImage = opts.background
    if bgImage then
        table.insert(resultChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute",
            left = 0, top = 0,
            backgroundImage = bgImage,
            backgroundFit = "cover",
        })
    end

    -- ▼ 立绘层（absolute 全屏背景）
    table.insert(resultChildren, UI.Panel {
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
    })

    -- ▼ 弹性空白
    table.insert(resultChildren, UI.Panel { flexGrow = 1, flexBasis = 0 })

    -- ▼ 结果卡片（半透明叠在立绘前面）
    table.insert(resultChildren, UI.Panel {
        width = "100%",
        backgroundColor = { 15, 13, 10, 200 },
        borderTopWidth = 1,
        borderColor = { 80, 65, 40, 80 },
        padding = 20,
        gap = 10,
        alignItems = "center",
        children = cardChildren,
    })

    return UI.Panel {
        id = "galScreen",
        width = "100%", height = "100%",
        backgroundColor = { 18, 15, 12, 255 },
        justifyContent = "flex-end",
        children = resultChildren,
    }
end

return M

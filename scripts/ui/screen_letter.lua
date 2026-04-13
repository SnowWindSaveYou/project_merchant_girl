--- 信纸阅读界面
--- 全屏信纸风格，展示一封信的完整内容，支持翻页、附言
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local F            = require("ui/ui_factory")
local SoundMgr     = require("ui/sound_manager")
local LetterSystem = require("narrative/letter_system")
local SketchBorder = require("ui/sketch_border")
local Graph        = require("map/world_graph")

local M = {}
---@type table
local router = nil

-- 当前阅读状态（模块级，跨 refresh 保留）
local _letters   = {}   -- 待阅读信件队列
local _index     = 1    -- 当前阅读到第几封
local _onFinish  = nil  -- 全部读完的回调
local _bgImage   = nil  -- 背景图路径

-- 信纸配色
local PAPER_BG       = { 248, 242, 228, 245 }
local PAPER_BORDER   = { 198, 186, 162, 180 }
local TEXT_INK       = {  52,  48,  42, 255 }
local TEXT_DIM       = { 128, 118, 102, 255 }
local TEXT_PS        = { 108, 128, 148, 255 }  -- 附言蓝灰色

-- ============================================================
-- 页面入口
-- ============================================================

--- 创建信纸阅读页面
--- params.letters: table[] 信件配置数组
--- params.state: table 游戏状态（用于 apply_effects）
--- params.onFinish: function|nil 全部读完后的回调
function M.create(state, params, r)
    router = r

    -- 仅在真正导航进入时（有 params.letters）重置状态
    -- router.refresh() 时 params 可能为 nil，保留已有状态
    if params and params.letters then
        _letters  = params.letters
        _index    = 1
        _onFinish = params.onFinish or nil

        -- 取当前聚落背景图
        local loc = state.map and state.map.current_location
        if loc then
            local node = Graph.get_node(loc)
            _bgImage = node and node.bg or nil
        else
            _bgImage = nil
        end
    end

    if #_letters == 0 then
        if _onFinish then _onFinish() end
        return UI.Panel { width = "100%", height = "100%" }
    end

    return M._buildLetter(state)
end

function M.update() end

-- ============================================================
-- 构建单封信纸
-- ============================================================

function M._buildLetter(state)
    local letter = _letters[_index]
    if not letter then
        M._finish(state)
        return UI.Panel { width = "100%", height = "100%" }
    end

    local contentChildren = {}

    -- 标题
    table.insert(contentChildren, UI.Label {
        text = letter.title or "（无题）",
        fontSize = 20,
        fontColor = TEXT_INK,
        fontWeight = "bold",
        textAlign = "center",
        width = "100%",
        paddingBottom = 8,
    })

    -- 分隔线
    table.insert(contentChildren, UI.Panel {
        width = "60%", height = 1,
        backgroundColor = PAPER_BORDER,
        alignSelf = "center",
        marginBottom = 12,
    })

    -- 正文段落
    if letter.content then
        for _, paragraph in ipairs(letter.content) do
            if paragraph == "" then
                table.insert(contentChildren, UI.Panel {
                    width = "100%", height = 12,
                })
            else
                table.insert(contentChildren, UI.Label {
                    text = paragraph,
                    fontSize = 15,
                    fontColor = TEXT_INK,
                    lineHeight = 1.6,
                    width = "100%",
                })
            end
        end
    end

    -- 附言（雪冬便签）
    if letter.postscript then
        table.insert(contentChildren, UI.Panel {
            width = "100%", height = 1,
            backgroundColor = { 168, 188, 208, 120 },
            marginTop = 16, marginBottom = 8,
        })
        table.insert(contentChildren, UI.Label {
            text = "📮 雪冬附言：",
            fontSize = 12,
            fontColor = TEXT_PS,
            fontWeight = "bold",
        })
        table.insert(contentChildren, UI.Label {
            text = letter.postscript,
            fontSize = 13,
            fontColor = TEXT_PS,
            lineHeight = 1.5,
            width = "100%",
        })
    end

    -- 底部按钮
    local isLast = (_index >= #_letters)
    local btnText = isLast and "收好信件" or ("下一封（" .. _index .. "/" .. #_letters .. "）")

    table.insert(contentChildren, UI.Panel { width = "100%", height = 20 })

    table.insert(contentChildren, F.actionBtn {
        text = btnText,
        variant = "primary",
        height = 44,
        fontSize = Theme.sizes.font_normal,
        onClick = function(self)
            SoundMgr.play("click_soft")
            LetterSystem.apply_effects(state, letter)

            if isLast then
                M._finish(state)
            else
                _index = _index + 1
                if router then router.refresh() end
            end
        end,
    })

    -- 信件计数（多封时显示）
    local counterLabel = nil
    if #_letters > 1 then
        counterLabel = UI.Label {
            text = _index .. " / " .. #_letters,
            fontSize = 12,
            fontColor = TEXT_DIM,
            textAlign = "center",
            width = "100%",
            marginTop = 4,
        }
    end

    -- 来信提示
    local fromLabel = UI.Label {
        text = "📨 来自 " .. (letter.sender_name or "未知") .. " 的信",
        fontSize = 13,
        fontColor = { 220, 215, 205, 220 },
        textAlign = "center",
        width = "100%",
        paddingBottom = 8,
    }

    -- 信纸卡片
    local paperCard = F.card {
        width = "100%",
        maxHeight = "80%",
        backgroundColor = PAPER_BG,
        padding = 20,
        overflow = "scroll",
        children = contentChildren,
    }

    -- 用 F.overlay 提供背景图 + 暗色遮罩
    return F.overlay {
        id = "letterScreen",
        backgroundImage = _bgImage,
        children = {
            UI.Panel {
                width = "90%", maxWidth = 420,
                alignItems = "center",
                gap = 0,
                children = {
                    fromLabel,
                    paperCard,
                    counterLabel,
                },
            },
        },
    }
end

-- ============================================================
-- 完成阅读
-- ============================================================

function M._finish(state)
    local cb = _onFinish
    _letters  = {}
    _index    = 1
    _onFinish = nil
    _bgImage  = nil
    if cb then
        cb()
    elseif router then
        router.navigate("home")
    end
end

return M

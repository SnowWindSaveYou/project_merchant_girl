--- UI 组件工厂：少女终末旅行风格封装
--- 扁平色彩 + 细边框 + 微圆角 · 极简手绘感
--- 页面代码只需调用 F.card / F.actionBtn 即可获得统一风格的组件。
local UI       = require("urhox-libs/UI")
local Theme    = require("ui/theme")
local SoundMgr = require("ui/sound_manager")

local F = {}

-- ============================================================
-- 卡片 (card)
-- 扁平半透明背景 + 细边框 + 微圆角 · 少女终末旅行极简风
-- ============================================================
--- 创建卡片容器
--- props.enterAnim: true 时卡片以淡入+微移方式入场
--- props.enterDelay: 入场动画延迟(秒)，用于列表错开
--- props.backgroundImage: 可选，传入纹理路径时恢复为 9-slice 纹理模式
---@param props table 额外/覆盖属性（children 必传）
---@return table widget
function F.card(props)
    local p = props or {}
    local wantAnim = p.enterAnim and not F.skipEnterAnim
    local useTexture = p.backgroundImage ~= nil

    local panel = UI.Panel {
        id            = p.id or nil,
        width         = p.width or "100%",
        height        = p.height or nil,
        padding       = p.padding or Theme.sizes.padding_small,
        gap           = p.gap or 6,
        overflow      = p.overflow or nil,
        flexDirection = p.flexDirection or nil,
        flexGrow      = p.flexGrow or nil,
        flexShrink    = p.flexShrink or nil,
        flexWrap      = p.flexWrap or nil,
        alignItems    = p.alignItems or nil,
        justifyContent = p.justifyContent or nil,
        marginTop     = p.marginTop or nil,
        marginBottom  = p.marginBottom or nil,
        maxHeight     = p.maxHeight or nil,
        -- 扁平背景色（默认）
        backgroundColor = (not useTexture) and (p.backgroundColor or Theme.colors.bg_card) or nil,
        -- 9-slice 纹理（仅在显式传入 backgroundImage 时启用）
        backgroundImage = useTexture and p.backgroundImage or nil,
        backgroundFit   = useTexture and "sliced" or nil,
        backgroundSlice = useTexture and (p.backgroundSlice or Theme.textures.card_slice) or nil,
        imageTint       = p.imageTint or nil,
        -- 细边框 + 微圆角
        borderWidth     = p.borderWidth or 1,
        borderColor     = p.borderColor or Theme.colors.card_border,
        borderRadius    = p.borderRadius or Theme.sizes.radius,
        -- 入场动画初始态
        opacity    = wantAnim and 0 or nil,
        translateY = wantAnim and 8 or nil,
        transition = wantAnim and "opacity 0.3s easeOut, translateY 0.3s easeOut" or nil,
        -- onClick
        onClick         = p.onClick or nil,
        children        = p.children or {},
    }

    -- 延迟触发入场
    if wantAnim then
        local delay = p.enterDelay or 0
        F._pendingAnims = F._pendingAnims or {}
        table.insert(F._pendingAnims, { widget = panel, delay = delay })
    end

    return panel
end

--- 由外部每帧调用，驱动入场动画计时
function F.update(dt)
    if not F._pendingAnims then return end
    local remaining = {}
    for _, entry in ipairs(F._pendingAnims) do
        entry.delay = entry.delay - dt
        if entry.delay <= 0 then
            entry.widget:SetStyle({ opacity = 1, translateY = 0 })
        else
            table.insert(remaining, entry)
        end
    end
    if #remaining > 0 then
        F._pendingAnims = remaining
    else
        F._pendingAnims = nil
    end
end

-- ============================================================
-- 操作按钮 (actionBtn)
-- 扁平配色 + 细边框 + 按下反馈 + 点击音效
-- ============================================================
--- 创建扁平风格操作按钮
---@param props table { text, variant?, onClick, disabled?, width?, height?, fontSize?, ... }
---@return table widget
function F.actionBtn(props)
    local p = props or {}
    local variant = p.variant or "secondary"
    local disabled = p.disabled or false

    -- 扁平配色（按 variant 查表）
    local colors = disabled and Theme.btn_colors.disabled
        or Theme.btn_colors[variant]
        or Theme.btn_colors.secondary
    local bgColor      = colors.bg
    local pressedColor = colors.pressed or bgColor
    local textColor    = disabled and Theme.colors.text_dim
        or (p.fontColor or Theme.colors.text_primary)

    -- width="auto" → nil：让 Button 内部根据文本宽度自动计算（带 64px 最小值）
    -- Yoga 的 auto 不知道 NanoVG 文本宽度，会产生过窄按钮
    local btnWidth = p.width
    if btnWidth == "auto" then
        btnWidth = nil
    elseif btnWidth == nil then
        btnWidth = p.flexGrow and nil or "100%"
    end

    return UI.Button {
        id         = p.id or nil,
        text       = p.text or "",
        disabled   = disabled,
        width      = btnWidth,
        height     = p.height or 44,
        flexGrow   = p.flexGrow or nil,
        flexShrink = p.flexShrink or 1,
        alignSelf  = p.alignSelf or nil,
        fontSize   = p.fontSize or Theme.sizes.font_normal,
        fontColor  = textColor,
        -- 扁平背景 + 细边框 + 微圆角
        backgroundColor = bgColor,
        borderWidth     = p.borderWidth or 1,
        borderColor     = p.borderColor or Theme.colors.card_border,
        borderRadius    = p.borderRadius or Theme.sizes.radius,
        -- 外边距 / 内边距透传
        marginTop    = p.marginTop or nil,
        marginBottom = p.marginBottom or nil,
        marginLeft   = p.marginLeft or nil,
        marginRight  = p.marginRight or nil,
        paddingLeft  = p.paddingLeft or nil,
        paddingRight = p.paddingRight or nil,
        onClick = function(self)
            if disabled then return end
            SoundMgr.play(p.sound or "click")
            if p.onClick then p.onClick(self) end
        end,
    }
end

-- ============================================================
-- 遮罩层 (overlay)
-- 全屏半透明遮罩 + 点击拦截（防止穿透到下层 UI）
-- ============================================================
--- 创建模态遮罩层
--- props.onBackdropClick: 点击遮罩区域的回调（不传则静默拦截）
---@param props table { children, onBackdropClick?, backgroundColor?, id? }
---@return table widget
function F.overlay(props)
    local p = props or {}
    return UI.Panel {
        id     = p.id or nil,
        width  = "100%", height = "100%",
        backgroundColor    = p.backgroundColor or Theme.colors.bg_overlay,
        justifyContent     = "center",
        alignItems         = "center",
        -- 拦截所有点击，防止穿透到下层 UI
        onClick = function(self)
            if p.onBackdropClick then p.onBackdropClick(self) end
        end,
        children = {
            -- 内容容器：阻止内容区点击冒泡到遮罩
            UI.Panel {
                onClick    = function(self) end,
                alignItems = "center",
                width      = p.contentWidth or "100%",
                children   = p.children or {},
            },
        },
    }
end

-- ============================================================
-- 分割线 (divider)
-- ============================================================
function F.divider(props)
    local p = props or {}
    return UI.Panel {
        width  = p.width or "100%",
        height = p.height or 1,
        backgroundColor = p.backgroundColor or Theme.colors.divider,
        marginTop    = p.marginTop or 4,
        marginBottom = p.marginBottom or 4,
    }
end

-- ============================================================
-- 区块标题 (sectionTitle)
-- ============================================================
function F.sectionTitle(text, props)
    local p = props or {}
    return UI.Label {
        text      = text,
        fontSize  = p.fontSize or Theme.sizes.font_normal,
        fontColor = p.fontColor or Theme.colors.text_header,
        marginTop    = p.marginTop or 8,
        marginBottom = p.marginBottom or 4,
    }
end

-- ============================================================
-- 信息芯片 (infoChip) — 顶栏/卡片内的标签值对
-- ============================================================
function F.infoChip(label, value, valueColor, props)
    local p = props or {}
    return UI.Panel {
        flexDirection = "row", alignItems = "center",
        gap = p.gap or 4,
        children = {
            UI.Label {
                text = label,
                fontSize = p.labelSize or Theme.sizes.font_tiny,
                fontColor = p.labelColor or Theme.colors.text_dim,
            },
            UI.Label {
                id = p.valueId or nil,
                text = value,
                fontSize = p.valueSize or Theme.sizes.font_small,
                fontColor = valueColor or Theme.colors.text_primary,
            },
        },
    }
end

return F

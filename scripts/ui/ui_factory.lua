--- UI 组件工厂：少女终末旅行风格封装
--- 扁平色彩 + 细边框 + 微圆角 · 极简手绘感
--- 页面代码只需调用 F.card / F.actionBtn 即可获得统一风格的组件。
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local SoundMgr     = require("ui/sound_manager")
local SketchBorder = require("ui/sketch_border")

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
        -- 原生边框隐藏，由 SketchBorder 绘制手绘线条
        borderWidth     = p.borderWidth or 0,
        borderColor     = p.borderColor or nil,
        borderRadius    = p.borderRadius or Theme.sizes.radius,
        -- onClick
        onClick         = p.onClick or nil,
        children        = p.children or {},
    }

    -- 注册手绘边框（sketch=false 可关闭）
    if p.sketch ~= false then
        local skStyle = p.sketchStyle or "card"
        SketchBorder.register(panel, skStyle, p.sketchOverrides)
    end

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
            entry.widget:SetStyle({ translateY = 0 })
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

    local btn = UI.Button {
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
        -- 原生边框隐藏，由 SketchBorder 绘制手绘线条
        backgroundColor = bgColor,
        borderWidth     = p.borderWidth or 0,
        borderColor     = p.borderColor or nil,
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
            -- sound=false 跳过自动音效（由业务回调自行播放 coins/success 等）
            if p.sound ~= false then
                SoundMgr.play(p.sound or "click")
            end
            if p.onClick then p.onClick(self) end
        end,
    }

    -- 注册手绘边框（sketch=false 可关闭）
    -- highlight=true 时自动使用 accent_button 样式（金色墨水+呼吸+微光）
    if p.sketch ~= false then
        local skStyle = p.sketchStyle or (p.highlight and "accent_button" or "button")
        SketchBorder.register(btn, skStyle, p.sketchOverrides)
    end

    return btn
end

-- ============================================================
-- 遮罩层 (overlay)
-- 全屏半透明遮罩 + 点击拦截（防止穿透到下层 UI）
-- ============================================================
--- 创建模态遮罩层
--- props.onBackdropClick: 点击遮罩区域的回调（不传则静默拦截）
--- props.backgroundImage: 可选背景图路径，替代纯色遮罩，用 cover 铺满 + 渐变叠加
---@param props table { children, onBackdropClick?, backgroundColor?, backgroundImage?, id? }
---@return table widget
function F.overlay(props)
    local p = props or {}
    local hasBg = p.backgroundImage ~= nil

    local layerChildren = {}

    -- 层 1：背景图（全屏绝对定位 cover 铺满）
    if hasBg then
        table.insert(layerChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundImage = p.backgroundImage,
            backgroundFit = "cover",
        })
        -- 层 2：压暗遮罩（均匀半透明黑 + 底部渐变加深，保证卡片文字可读）
        table.insert(layerChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundColor = { 0, 0, 0, 160 },
        })
    end

    -- 层 3：内容容器（居中）
    table.insert(layerChildren, UI.Panel {
        width = "100%", height = "100%",
        justifyContent = "center",
        alignItems     = "center",
        -- 拦截所有点击，防止穿透到下层 UI
        onClick = function(self)
            if p.onBackdropClick then p.onBackdropClick(self) end
        end,
        children = {
            -- 内容区：阻止点击冒泡到遮罩
            UI.Panel {
                onClick    = function(self) end,
                alignItems = "center",
                width      = p.contentWidth or "100%",
                children   = p.children or {},
            },
        },
    })

    return UI.Panel {
        id     = p.id or nil,
        width  = "100%", height = "100%",
        backgroundColor = hasBg and { 0, 0, 0, 255 } or (p.backgroundColor or Theme.colors.bg_overlay),
        children = layerChildren,
    }
end

-- ============================================================
-- 弹窗卡片 (popupCard)
-- 外层固定装饰框 + 内层按需滚动
-- 解决旧模式（ScrollView > Card）装饰框跟随滚动 + 高度始终触发滚动的问题
-- ============================================================
--- 创建弹窗卡片：外层带 SketchBorder 装饰框，内层 ScrollView 仅在内容溢出时滚动
--- props.width / props.maxWidth: 弹窗宽度
--- props.maxHeight: 弹窗最大高度（默认 "85%"）
--- props.padding: 内容区内边距（默认 Theme.sizes.padding_large）
--- props.gap: 内容区间距（默认 10）
--- props.alignItems: 内容区对齐方式
--- props.enterAnim: 入场动画
--- props.enterDelay: 入场延迟
--- props.borderWidth / props.borderColor: 额外边框属性
--- props.sketchStyle / props.sketchOverrides: 手绘边框样式
--- props.children: 内容子组件列表
---@param props table
---@return table widget
function F.popupCard(props)
    local p = props or {}

    -- 外层壳：带背景色 + SketchBorder 装饰框，不滚动
    -- 使用 flexShrink=1 让外层在内容少时收缩到内容高度，多时撑到 maxHeight 停住
    local outerPanel = UI.Panel {
        id            = p.id or nil,
        width         = p.width or "90%",
        maxWidth      = p.maxWidth or 420,
        maxHeight     = p.maxHeight or "85%",
        backgroundColor = p.backgroundColor or Theme.colors.bg_card,
        borderWidth   = p.borderWidth or 0,
        borderColor   = p.borderColor or nil,
        borderRadius  = p.borderRadius or Theme.sizes.radius,
        flexShrink    = 1,
        children      = {
            -- 内层 ScrollView：仅在内容超出 maxHeight 时才出现滚动
            UI.ScrollView {
                width    = "100%",
                flexGrow = 1,
                children = {
                    -- 内容容器：承载真正的子组件
                    UI.Panel {
                        width         = "100%",
                        padding       = p.padding or Theme.sizes.padding_large,
                        gap           = p.gap or 10,
                        alignItems    = p.alignItems or nil,
                        flexDirection = p.flexDirection or nil,
                        children      = p.children or {},
                    },
                },
            },
        },
    }

    -- 注册手绘边框到外层（装饰框固定在滚动区域外）
    if p.sketch ~= false then
        local skStyle = p.sketchStyle or "card"
        SketchBorder.register(outerPanel, skStyle, p.sketchOverrides)
    end

    -- 入场动画
    if p.enterAnim and not F.skipEnterAnim then
        local delay = p.enterDelay or 0
        F._pendingAnims = F._pendingAnims or {}
        table.insert(F._pendingAnims, { widget = outerPanel, delay = delay })
    end

    return outerPanel
end

-- ============================================================
-- 分割线 (divider)
-- ============================================================
function F.divider(props)
    local p = props or {}
    local div = UI.Panel {
        width  = p.width or "100%",
        height = p.height or 1,
        backgroundColor = p.backgroundColor or Theme.colors.divider,
        marginTop    = p.marginTop or 4,
        marginBottom = p.marginBottom or 4,
    }

    -- 注册手绘分割线（sketch=false 可关闭）
    if p.sketch ~= false then
        SketchBorder.register(div, "divider", p.sketchOverrides)
    end

    return div
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

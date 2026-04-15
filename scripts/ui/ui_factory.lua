--- UI 组件工厂：少女终末旅行风格封装
--- 扁平色彩 + 细边框 + 微圆角 · 极简手绘感
--- 页面代码只需调用 F.card / F.actionBtn 即可获得统一风格的组件。
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local SoundMgr     = require("ui/sound_manager")
local SketchBorder = require("ui/sketch_border")

local F = {}

-- ============================================================
-- 工具：背景图随机裁切 (monkey-patch)
-- 让每个按钮显示纹理的不同区域，避免千篇一律
-- ============================================================
--- opts.breath: true 时启用呼吸缩放（高亮按钮用）
local function patchRandomBgCrop(widget, opts)
    opts = opts or {}
    local rx, ry = math.random(), math.random()
    -- 呼吸缩放状态
    local breathOn = opts.breath or false
    local breathPhase = math.random() * 6.28
    local breathTime = 0

    local _orig = widget.RenderFitImage
    function widget:RenderFitImage(nvg, imgHandle, imgW, imgH, l, fit, radius, tint)
        -- 仅对 cover 模式生效，其余走原逻辑
        if fit ~= "cover" then
            return _orig(self, nvg, imgHandle, imgW, imgH, l, fit, radius, tint)
        end

        -- 呼吸缩放（利用渲染回调每帧驱动，无需全局事件）
        if breathOn and not self._btnInteracting then
            breathTime = breathTime + 0.016  -- ~60fps 近似 dt
            local s = 1.0 + (math.sin(breathPhase + breathTime * 1.8) * 0.5 + 0.5) * 0.03  -- 平缓呼吸 ~17BPM
            self:SetStyle({ scale = s })
        end

        local drawX, drawY, drawW, drawH = l.x, l.y, l.w, l.h
        local imgRatio = imgW / imgH
        local boxRatio = l.w / l.h
        if imgRatio > boxRatio then
            drawH = l.h
            drawW = l.h * imgRatio
            drawX = l.x - (drawW - l.w) * rx   -- 随机水平偏移
            drawY = l.y
        else
            drawW = l.w
            drawH = l.w / imgRatio
            drawX = l.x
            drawY = l.y - (drawH - l.h) * ry   -- 随机垂直偏移
        end
        local imgPaint
        if tint then
            imgPaint = nvgImagePatternTinted(nvg, drawX, drawY, drawW, drawH, 0, imgHandle,
                nvgRGBA(tint[1], tint[2], tint[3], tint[4] or 255))
        else
            imgPaint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, imgHandle, 1)
        end
        nvgBeginPath(nvg)
        if radius > 0 then
            nvgRoundedRect(nvg, l.x, l.y, l.w, l.h, radius)
        else
            nvgRect(nvg, l.x, l.y, l.w, l.h)
        end
        nvgFillPaint(nvg, imgPaint)
        nvgFill(nvg)
    end
end

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
        -- 背景色（默认全透明，仅保留描边框；需要底色时显式传入 backgroundColor）
        backgroundColor = p.backgroundColor or { 0, 0, 0, 0 },
        -- 纹理背景（显式传入 backgroundImage 时启用，默认 9-slice，可用 backgroundFit 覆盖）
        backgroundImage = useTexture and p.backgroundImage or nil,
        backgroundFit   = useTexture and (p.backgroundFit or "sliced") or nil,
        backgroundSlice = useTexture and (p.backgroundFit == nil or p.backgroundFit == "sliced")
                            and (p.backgroundSlice or Theme.textures.card_slice) or nil,
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
--- 解析 icon 参数：支持 Theme.icons key 或直接图片路径
---@param iconVal string|nil
---@return string|nil imagePath
local function resolveIcon(iconVal)
    if not iconVal then return nil end
    -- 如果是 Theme.icons 中的 key（无斜杠、无后缀），查表
    if not string.find(iconVal, "[/\\.]") then
        return Theme.icons[iconVal] or nil
    end
    -- 否则视为直接图片路径
    return iconVal
end

-- ============================================================
-- 图标面板 (icon)
-- 白色阴影光晕加宽贴纸描边效果
-- ============================================================
--- 创建带白色外轮廓的图标面板
--- props.icon: Theme.icons key 或直接图片路径（必传）
--- props.size: 图标尺寸（默认 20）
--- props.round: 圆形裁剪（NPC chibi 用）
--- props.shadowBlur: 光晕模糊半径（默认 3）
--- props.shadowColor: 光晕颜色（默认白色）
---@param props table
---@return table widget
function F.icon(props)
    local p = props or {}
    local iconPath = resolveIcon(p.icon)
    if not iconPath then return UI.Panel { width = 0, height = 0 } end
    local sz = p.size or 20
    local round = p.round or false
    return UI.Panel {
        width  = sz, height = sz,
        borderRadius    = round and math.floor(sz / 2) or 0,
        backgroundImage = iconPath,
        backgroundFit   = "contain",
    }
end

--- 创建扁平风格操作按钮
--- props.icon:  图标 key（如 "campfire"）或图片路径，显示在文字左侧
--- props.iconSize: 图标尺寸（默认 20）
--- props.iconRound: true 时图标显示为圆形（NPC chibi 用）
---@param props table { text, icon?, iconSize?, iconRound?, variant?, onClick, disabled?, width?, height?, fontSize?, ... }
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

    -- 纹理背景：primary / highlight 使用红色羊皮纸，其余普通羊皮纸
    local wantTexture = p.backgroundImage ~= false
    local useRed = (variant == "primary") or p.highlight
    local defaultTex  = useRed and Theme.textures.parchment_red or Theme.textures.parchment
    local btnBgImage  = wantTexture and (p.backgroundImage or defaultTex) or nil

    -- 红色贴图按钮文字改白色以保证可读性
    if useRed and not p.fontColor then
        textColor = { 255, 250, 240, 255 }  -- 暖白
    end

    -- 解析图标
    local iconPath = resolveIcon(p.icon)
    local iconSz   = p.iconSize or 28
    local iconRound = p.iconRound or false

    local btn = UI.Button {
        id         = p.id or nil,
        text       = (not iconPath) and (p.text or "") or "",   -- 有图标时文字由子元素渲染
        disabled   = disabled,
        width      = btnWidth,
        height     = p.height or 44,
        flexGrow   = p.flexGrow or nil,
        flexShrink = p.flexShrink or 1,
        alignSelf  = p.alignSelf or nil,
        fontSize   = (not iconPath) and (p.fontSize or Theme.sizes.font_normal) or 1,
        textColor  = textColor,
        opacity    = disabled and 0.45 or 1.0,
        -- 纹理背景（cover 保持比例不拉伸）
        backgroundImage = btnBgImage,
        backgroundFit   = btnBgImage and "cover" or nil,
        -- 纯色背景作为纹理未加载时的 fallback
        backgroundColor = bgColor,
        borderWidth     = p.borderWidth or 0,
        borderColor     = p.borderColor or nil,
        borderRadius    = p.borderRadius or Theme.sizes.radius,
        -- 缩放交互（通过 OnEvent 注册，见下方 btn 创建后）
        scale      = 1.0,
        transition = "scale 0.15s easeOut",
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

    -- 有图标时：覆盖 Button 内部内容，用图标+文字行代替纯文字
    if iconPath then
        btn:ClearChildren()
        btn:AddChild(UI.Panel {
            width = "100%", height = "100%",
            flexDirection = "row", alignItems = "center", justifyContent = "center",
            gap = 6,
            children = {
                F.icon {
                    icon = p.icon,
                    size = iconSz,
                    round = iconRound,
                },
                UI.Label {
                    text = p.text or "",
                    fontSize = p.fontSize or Theme.sizes.font_normal,
                    fontColor = textColor,
                },
            },
        })
    end

    -- 背景纹理随机裁切 + 高亮呼吸缩放
    if btnBgImage then
        patchRandomBgCrop(btn, { breath = p.highlight and not disabled })
    end

    -- 缩放 + hover 交互（OnEvent 绕过 Button 内部覆写）
    if not disabled then
        btn:OnEvent("pointerdown", function()
            btn._btnInteracting = true
            btn:SetStyle({ scale = 0.93 })
        end)
        btn:OnEvent("pointerup", function()
            btn._btnInteracting = false
            btn:SetStyle({ scale = 1.0 })
        end)
        btn:OnEvent("pointerenter", function()
            btn._btnInteracting = true
            btn:SetStyle({ scale = 1.05 })
        end)
        btn:OnEvent("pointerleave", function()
            btn._btnInteracting = false
            btn:SetStyle({ scale = 1.0 })
        end)
    end


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
        -- 层 2：柔和遮罩（暖色半透明，降低与亮色主题的对比）
        table.insert(layerChildren, UI.Panel {
            width = "100%", height = "100%",
            position = "absolute", left = 0, top = 0,
            backgroundColor = { 120, 105, 80, 120 },
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
        backgroundColor = p.backgroundColor or { 215, 205, 185, 255 },
        backgroundImage = p.backgroundImage or Theme.textures.parchment,
        backgroundFit   = p.backgroundFit or "cover",
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

-- ============================================================
-- 羊皮纸风格 Modal (parchmentModal)
-- 统一弹窗外观：羊皮纸贴图背景 + 素描边框 + 深色标题
-- 用法：local modal = F.parchmentModal { size="sm", title="标题", ... }
-- ============================================================

-- 缓存 NanoVG 羊皮纸图片句柄（所有 parchmentModal 实例共享）
local _parchmentNvgImg = nil

--- 创建羊皮纸风格 Modal
--- 所有参数透传给 UI.Modal，额外支持：
---   props.texture: 自定义背景贴图路径（默认 Theme.textures.parchment）
---@param props table
---@return table modal
function F.parchmentModal(props)
    local p = props or {}
    local UiLib = require("urhox-libs/UI/Core/UI")

    local modal = UI.Modal {
        id             = p.id or nil,
        size           = p.size or "sm",
        title          = p.title or "",
        closeOnOverlay = p.closeOnOverlay ~= false,
        closeOnEscape  = p.closeOnEscape ~= false,
        showCloseButton = p.showCloseButton,
        onClose        = p.onClose or nil,
    }
    modal.borderRadius_ = p.borderRadius or Theme.sizes.radius

    local texturePath = p.texture or Theme.textures.parchment

    -- 覆写 RenderModalContent：羊皮纸背景 + 素描边框
    modal.RenderModalContent = function(self, nvg)
        local screenWidth  = UiLib.GetWidth() or 800
        local screenHeight = UiLib.GetHeight() or 600
        local borderRadius = self.borderRadius_
        local title        = self.title_
        local showCloseButton = self.showCloseButton_

        local headerHeight   = 56
        local footerHeight   = 64
        local contentPadding = 16

        local SIZE_PRESETS = {
            sm = { width = 320, maxHeight = 400 },
            md = { width = 480, maxHeight = 600 },
            lg = { width = 640, maxHeight = 720 },
            xl = { width = 800, maxHeight = 800 },
            fullscreen = { width = "90%", maxHeight = "90%" },
        }
        local sizePreset = SIZE_PRESETS[self.size_] or SIZE_PRESETS.md
        local modalWidth     = sizePreset.width
        local modalMaxHeight = sizePreset.maxHeight

        if type(modalWidth) == "string" and modalWidth:match("%%$") then
            modalWidth = screenWidth * tonumber(modalWidth:match("(%d+)")) / 100
        end
        if type(modalMaxHeight) == "string" and modalMaxHeight:match("%%$") then
            modalMaxHeight = screenHeight * tonumber(modalMaxHeight:match("(%d+)")) / 100
        end

        local alpha     = self.animProgress_
        local animScale = 0.9 + 0.1 * alpha

        -- 遮罩
        local ov = Theme.colors.bg_overlay
        nvgBeginPath(nvg)
        nvgRect(nvg, 0, 0, screenWidth, screenHeight)
        nvgFillColor(nvg, nvgRGBA(ov[1], ov[2], ov[3], math.floor((ov[4] or 160) * alpha)))
        nvgFill(nvg)

        -- 布局计算
        local contentAreaWidth = modalWidth - contentPadding * 2
        local modalHeight = self:CalculateContentHeight(contentAreaWidth)
                + (title and headerHeight or 0)
                + (self.footerWidget_ and footerHeight or 0)
        modalHeight = math.min(modalHeight, modalMaxHeight)

        local modalX = (screenWidth  - modalWidth  * animScale) / 2
        local modalY = (screenHeight - modalHeight * animScale) / 2

        nvgSave(nvg)
        nvgTranslate(nvg, screenWidth / 2, screenHeight / 2)
        nvgScale(nvg, animScale, animScale)
        nvgTranslate(nvg, -screenWidth / 2, -screenHeight / 2)

        -- 背景（羊皮纸贴图）
        if not _parchmentNvgImg then
            _parchmentNvgImg = nvgCreateImage(nvg, texturePath, 0)
        end
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, modalX, modalY, modalWidth, modalHeight, borderRadius)
        if _parchmentNvgImg and _parchmentNvgImg > 0 then
            local imgPaint = nvgImagePattern(nvg, modalX, modalY, modalWidth, modalHeight, 0, _parchmentNvgImg, alpha)
            nvgFillPaint(nvg, imgPaint)
        else
            local bg = Theme.colors.bg_card
            nvgFillColor(nvg, nvgRGBA(bg[1], bg[2], bg[3], math.floor(245 * alpha)))
        end
        nvgFill(nvg)

        self.modalLayout_ = { x = modalX, y = modalY, w = modalWidth, h = modalHeight }

        local contentY = modalY

        -- Header（使用游戏 Theme 深色文字，而非 UI 库默认白色）
        if title then
            contentY = F._renderParchmentHeader(nvg, self, modalX, modalY, modalWidth, title, showCloseButton, alpha)
        elseif showCloseButton then
            self:RenderCloseButton(nvg, modalX + modalWidth - 44, modalY + 8, alpha)
            contentY = modalY + 16
        end

        -- 内容区域
        local footerHeightActual = self.footerWidget_ and footerHeight or 0
        local contentHeight = modalHeight - (contentY - modalY) - footerHeightActual

        if #self.contentContainer_.children > 0 then
            YGNodeCalculateLayout(self.contentContainer_.node, contentAreaWidth, contentHeight, YGDirectionLTR)
            self.contentContainer_.renderOffsetX_ = modalX + contentPadding
            self.contentContainer_.renderOffsetY_ = contentY
            self.contentContainer_.renderWidth_   = contentAreaWidth
            self.contentContainer_.renderHeight_  = contentHeight

            nvgSave(nvg)
            nvgIntersectScissor(nvg, modalX + contentPadding, contentY, contentAreaWidth, contentHeight)
            UiLib.RenderWidgetSubtree(self.contentContainer_, nvg)
            nvgRestore(nvg)
        end

        -- Footer
        if self.footerWidget_ then
            self:RenderFooter(nvg, modalX, modalY + modalHeight - footerHeight, modalWidth, footerHeight, alpha)
        end

        -- 素描边框
        F._renderSketchBorder(nvg, modalX, modalY, modalWidth, modalHeight, alpha)

        nvgRestore(nvg)
    end

    return modal
end

--- 绘制羊皮纸风格的 Modal 标题（使用游戏 Theme 深色文字）
--- 替代 Modal:RenderHeader 的 UI 库白色文字
function F._renderParchmentHeader(nvg, modal, x, y, width, title, showCloseButton, alpha)
    local headerHeight = 56
    local titlePadding = 20
    local padding = 16

    -- 分隔线（使用游戏 Theme 墨线颜色）
    local ink = Theme.sketch.ink_color
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, x + padding, y + headerHeight)
    nvgLineTo(nvg, x + width - padding, y + headerHeight)
    nvgStrokeColor(nvg, nvgRGBA(ink[1], ink[2], ink[3], math.floor(100 * alpha)))
    nvgStrokeWidth(nvg, 1)
    nvgStroke(nvg)

    -- 标题文字（使用游戏 Theme 深色 text_header）
    local tc = Theme.colors.text_header
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, Theme.sizes.font_large or 18)
    nvgFillColor(nvg, nvgRGBA(tc[1], tc[2], tc[3], math.floor(255 * alpha)))
    nvgTextAlign(nvg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    nvgText(nvg, x + titlePadding, y + headerHeight / 2, title, nil)

    -- 关闭按钮
    if showCloseButton then
        modal:RenderCloseButton(nvg, x + width - 44, y + (headerHeight - 28) / 2, alpha)
    end

    return y + headerHeight + padding
end

--- 绘制素描边框（共享给所有 parchmentModal 实例）
function F._renderSketchBorder(nvg, x, y, w, h, alpha)
    local ink = Theme.sketch.ink_color

    local function sketchLine(x1, y1, x2, y2, seed)
        local segs = 16
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        if len < 1 then return end
        local nx, ny = -dy / len, dx / len
        nvgBeginPath(nvg)
        for i = 0, segs do
            local t = i / segs
            local jx = (math.sin(seed + i * 2.3) * 0.5) * 1.5
            local jy = (math.cos(seed + i * 3.1) * 0.5) * 1.5
            local px = x1 + dx * t + nx * jx
            local py = y1 + dy * t + ny * jy
            if i == 0 then
                nvgMoveTo(nvg, px, py)
            else
                nvgLineTo(nvg, px, py)
            end
        end
        nvgStrokeColor(nvg, nvgRGBA(ink[1], ink[2], ink[3], ink[4]))
        nvgStrokeWidth(nvg, 1.2)
        nvgLineCap(nvg, NVG_ROUND)
        nvgLineJoin(nvg, NVG_ROUND)
        nvgStroke(nvg)
    end

    local seed = 42
    sketchLine(x, y, x + w, y, seed + 1)
    sketchLine(x + w, y, x + w, y + h, seed + 2)
    sketchLine(x + w, y + h, x, y + h, seed + 3)
    sketchLine(x, y + h, x, y, seed + 4)

    -- 角落装饰
    local cornerLen = math.min(w, h) * 0.06
    nvgStrokeColor(nvg, nvgRGBA(ink[1], ink[2], ink[3], ink[4]))
    nvgStrokeWidth(nvg, 2.0)
    nvgLineCap(nvg, NVG_ROUND)
    local corners = {
        { x, y,         x + cornerLen, y,         x, y + cornerLen },
        { x + w, y,     x + w - cornerLen, y,     x + w, y + cornerLen },
        { x + w, y + h, x + w - cornerLen, y + h, x + w, y + h - cornerLen },
        { x, y + h,     x + cornerLen, y + h,     x, y + h - cornerLen },
    }
    for _, c in ipairs(corners) do
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, c[3], c[4])
        nvgLineTo(nvg, c[1], c[2])
        nvgLineTo(nvg, c[5], c[6])
        nvgStroke(nvg)
    end
end

return F

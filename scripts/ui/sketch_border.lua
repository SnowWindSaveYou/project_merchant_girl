--- 手绘素描边框渲染模块（Widget.Render 集成版）
--- 通过 monkey-patch Widget:Render() 将手绘线条融入 UI 渲染流水线
--- 自动跟随滚动、遵循 UI 层级，无需独立 NanoVG overlay
--- 灵感来源：少女终末旅行素描画风
local Theme = require("ui/theme")

local M = {}

-- 呼吸动画时间累加器
local _time = 0

-- seed 计数器（每次 register 递增，clear 时重置保证页面间一致性）
local _seedCounter = 1

-- ============================================================
-- 哈希 / 噪声（移植自 lineui.lua.md）
-- ============================================================

local function hash(n)
    local x = math.sin(n * 127.1 + 311.7) * 43758.5453
    return x - math.floor(x)
end

local function valueNoise(x)
    local i = math.floor(x)
    local f = x - i
    f = f * f * (3 - 2 * f)
    return hash(i) * (1 - f) + hash(i + 1) * f
end

-- ============================================================
-- 样式预设
-- ============================================================

M.styles = {
    --- 卡片边框：双层、呼吸、标准抖动
    card = {},
    --- 按钮边框：单层、更细、无呼吸
    button = {
        layers      = 1,
        baseWidth   = 1.0,
        breathAmp   = 0,
        breakChance = 0.25,
    },
    --- 分割线：单条水平线、高断裂率
    divider = {
        layers       = 1,
        baseWidth    = 1.0,
        breathAmp    = 0,
        breakChance  = 0.6,
        breakMaxGaps = 4,
    },
    --- 竖直分割线
    vdivider = {
        layers       = 1,
        baseWidth    = 1.0,
        breathAmp    = 0,
        breakChance  = 0.5,
        breakMaxGaps = 3,
    },
    --- 强调卡片：使用强调色墨水
    accent_card = {
        ink_color = Theme.sketch.ink_accent,
    },
    --- 危险卡片
    danger_card = {
        ink_color = Theme.sketch.ink_danger,
    },
}

-- ============================================================
-- 内部辅助
-- ============================================================

local function getParam(style, key)
    if style and style[key] ~= nil then
        return style[key]
    end
    return Theme.sketch[key]
end

local function jitterOffset(sk, seed, pos, time)
    local breathPhase = math.sin(time * getParam(sk, "breathSpeed") + seed * 0.7)
                        * getParam(sk, "breathAmp")
    local base = (valueNoise(pos * 3.0 + seed * 17.3) - 0.5) * 2.0
    return base * getParam(sk, "jitter") * (1.0 + breathPhase)
end

local function jitterScale(sk, len)
    local full = getParam(sk, "jitterFullLen")
    local minL = getParam(sk, "jitterMinLen")
    if len >= full then return 1.0 end
    if len <= minL then return 0.1 end
    return 0.1 + ((len - minL) / (full - minL)) * 0.9
end

-- ============================================================
-- 手绘直线（支持断裂 + 双层）
-- ============================================================

local function drawSketchLine(ctx, sk, x1, y1, x2, y2, seed, time)
    local segs = getParam(sk, "segments")
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end

    local nx = -dy / len
    local ny = dx / len
    local jScale = jitterScale(sk, len)

    -- 构建断口表
    local gaps = {}
    if len >= getParam(sk, "breakMinLen") then
        local maxGaps = getParam(sk, "breakMaxGaps")
        local chance  = getParam(sk, "breakChance")
        local gapMin  = getParam(sk, "breakGapMin")
        local gapMax  = getParam(sk, "breakGapMax")
        for g = 1, maxGaps do
            local gSeed = seed * 13.7 + g * 77.1
            if hash(gSeed) < chance then
                local center = hash(gSeed + 3.3) * 0.7 + 0.15
                local gapPx = gapMin + hash(gSeed + 5.7) * (gapMax - gapMin)
                local halfGap = (gapPx / len) * 0.5
                gaps[#gaps + 1] = { center - halfGap, center + halfGap }
            end
        end
    end

    local function inGap(t)
        for _, gap in ipairs(gaps) do
            if t >= gap[1] and t <= gap[2] then return true end
        end
        return false
    end

    local function strokeLayer(layerSeed, offsetPx, alpha)
        nvgBeginPath(ctx)
        local started = false

        for i = 0, segs do
            local t = i / segs
            local edgeFade = 1.0
            if t < 0.05 then
                edgeFade = t / 0.05
            elseif t > 0.95 then
                edgeFade = (1.0 - t) / 0.05
            end

            if inGap(t) then
                started = false
            else
                local jx = jitterOffset(sk, layerSeed + i, t, time) * jScale * edgeFade
                local jy = jitterOffset(sk, layerSeed + i + 500, t, time) * jScale * edgeFade
                local px = x1 + dx * t + nx * (jx + offsetPx)
                local py = y1 + dy * t + ny * (jy + offsetPx * 0.3)

                if not started then
                    nvgMoveTo(ctx, px, py)
                    started = true
                else
                    nvgLineTo(ctx, px, py)
                end
            end
        end

        local widthMod = 1.0 + (valueNoise(layerSeed * 5.1) - 0.5) * getParam(sk, "widthVar")
        local cc = getParam(sk, "ink_color") or Theme.sketch.ink_color
        nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], math.floor(alpha)))
        nvgStrokeWidth(ctx, getParam(sk, "baseWidth") * widthMod)
        nvgLineCap(ctx, NVG_ROUND)
        nvgLineJoin(ctx, NVG_ROUND)
        nvgStroke(ctx)
    end

    -- 第一层
    local cc = getParam(sk, "ink_color") or Theme.sketch.ink_color
    strokeLayer(seed, 0, cc[4])

    -- 第二层
    if getParam(sk, "layers") >= 2 then
        local off = getParam(sk, "layer2Offset") * ((hash(seed * 3.3) - 0.5) * 2)
        strokeLayer(seed + 7000, off, cc[4] * getParam(sk, "layer2Alpha"))
    end
end

-- ============================================================
-- 手绘矩形 / 分割线
-- ============================================================

local function drawSketchRect(ctx, sk, x, y, w, h, seed, time)
    drawSketchLine(ctx, sk, x, y, x + w, y, seed + 1, time)
    drawSketchLine(ctx, sk, x + w, y, x + w, y + h, seed + 2, time)
    drawSketchLine(ctx, sk, x + w, y + h, x, y + h, seed + 3, time)
    drawSketchLine(ctx, sk, x, y + h, x, y, seed + 4, time)

    -- 角落强调
    local cornerLen = getParam(sk, "cornerLen") or math.min(w, h) * 0.06
    local cw = getParam(sk, "baseWidth") * getParam(sk, "cornerEmphasis")
    local cc = getParam(sk, "ink_color") or Theme.sketch.ink_color
    nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], cc[4]))
    nvgStrokeWidth(ctx, cw)
    nvgLineCap(ctx, NVG_ROUND)

    local corners = {
        { x, y,         x + cornerLen, y,         x, y + cornerLen },
        { x + w, y,     x + w - cornerLen, y,     x + w, y + cornerLen },
        { x + w, y + h, x + w - cornerLen, y + h, x + w, y + h - cornerLen },
        { x, y + h,     x + cornerLen, y + h,     x, y + h - cornerLen },
    }
    for _, c in ipairs(corners) do
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, c[3], c[4])
        nvgLineTo(ctx, c[1], c[2])
        nvgLineTo(ctx, c[5], c[6])
        nvgStroke(ctx)
    end
end

local function drawSketchDivider(ctx, sk, x, y, w, seed, time)
    drawSketchLine(ctx, sk, x, y, x + w, y, seed, time)
end

local function drawSketchVDivider(ctx, sk, x, y, h, seed, time)
    drawSketchLine(ctx, sk, x, y, x, y + h, seed, time)
end

-- ============================================================
-- 公共 API
-- ============================================================

--- 初始化（保留接口兼容，不再需要独立 NanoVG 上下文）
function M.init()
    print("[SketchBorder] Initialized (widget-integrated mode)")
end

--- 注册一个 widget，使其获得手绘边框
--- 通过 monkey-patch widget:Render() 实现：
---   - 自动跟随 ScrollView 滚动（NVG 变换由 UI 框架管理）
---   - 自动被 ScrollView scissor 裁剪
---   - 层级与 widget 一致，不会遮挡弹窗 / 气泡
---@param widget table  UI widget
---@param styleName string|nil  样式预设名（card/button/divider/accent_card/danger_card）
---@param styleOverrides table|nil  额外参数覆盖
function M.register(widget, styleName, styleOverrides)
    if not widget then return end

    local preset = M.styles[styleName or "card"] or {}
    local merged = {}
    for k, v in pairs(preset) do merged[k] = v end
    if styleOverrides then
        for k, v in pairs(styleOverrides) do merged[k] = v end
    end

    _seedCounter = _seedCounter + 1
    local seed = _seedCounter * 31
    local drawMode = "rect"
    if styleName == "divider" then drawMode = "hdivider"
    elseif styleName == "vdivider" then drawMode = "vdivider"
    end

    -- 捕获原始 Render（可能来自 metatable / 父类）
    local originalRender = widget.Render

    -- 实例级覆盖：仅影响此 widget，不影响同类其它实例
    widget.Render = function(self, nvg)
        -- 先执行原始渲染（背景、边框等）
        if originalRender then
            originalRender(self, nvg)
        end

        -- 获取尺寸（Render 时 NVG 已 translate 到 widget 局部坐标）
        local layout = self:GetAbsoluteLayout()
        if not layout or layout.w <= 0 or layout.h <= 0 then return end

        nvgSave(nvg)
        if drawMode == "hdivider" then
            drawSketchDivider(nvg, merged, layout.x, layout.y + layout.h * 0.5, layout.w, seed, _time)
        elseif drawMode == "vdivider" then
            drawSketchVDivider(nvg, merged, layout.x + layout.w * 0.5, layout.y, layout.h, seed, _time)
        else
            drawSketchRect(nvg, merged, layout.x, layout.y, layout.w, layout.h, seed, _time)
        end
        nvgRestore(nvg)
    end
end

--- 重置 seed 计数器（页面切换/刷新时调用，保证同页面视觉一致性）
function M.clear()
    _seedCounter = 1
end

--- 推进呼吸动画时间
function M.update(dt)
    _time = _time + dt
end

return M

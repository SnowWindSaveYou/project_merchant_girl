-- ============================================================================
-- SketchDraw — 手绘漫画风格 NanoVG 绘制库
-- 用法：将此文件复制到 scripts/ 目录，然后 require
--
--   local Sketch = require "sketch-drawing-lib"
--   -- 使用内置预设
--   Sketch.drawRect(vg, x, y, w, h, seed, time, Sketch.PRESETS.DEFAULT)
--   -- 或自定义
--   local myStyle = Sketch.createStyle({ jitter = 2.0, color = {255,0,0,255} })
--   Sketch.drawLine(vg, x1, y1, x2, y2, seed, time, myStyle)
-- ============================================================================

local M = {}

-- ============================================================================
-- 噪声基础
-- ============================================================================

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

local function jitterOffset(seed, pos, time, sk)
    local breathPhase = math.sin(time * sk.breathSpeed + seed * 0.7) * sk.breathAmp
    local base = (valueNoise(pos * 3.0 + seed * 17.3) - 0.5) * 2.0
    return base * sk.jitter * (1.0 + breathPhase)
end

local function jitterScale(len, sk)
    if len >= sk.jitterFullLen then return 1.0 end
    if len <= sk.jitterMinLen  then return 0.1 end
    local t = (len - sk.jitterMinLen) / (sk.jitterFullLen - sk.jitterMinLen)
    return 0.1 + t * 0.9
end

-- ============================================================================
-- 默认参数（奶白底 + 黑色线条）
-- ============================================================================

local DEFAULTS = {
    jitter        = 1.4,
    jitterFullLen = 300,
    jitterMinLen  = 40,
    segments      = 24,
    breakMaxGaps  = 3,
    breakChance   = 0.55,
    breakMinLen   = 120,
    breakGapMin   = 2,
    breakGapMax   = 8,
    baseWidth     = 1.2,
    widthVar      = 0.3,
    layers        = 2,
    layer2Alpha   = 0.50,
    layer2Offset  = 0.50,
    breathSpeed   = 1.1,
    breathAmp     = 0.2,
    color         = { 45, 40, 35, 235 },
    cornerEmphasis = 1.1,
}

-- ============================================================================
-- 预设方案
-- ============================================================================

local function copyDefaults()
    local s = {}
    for k, v in pairs(DEFAULTS) do s[k] = v end
    s.color = { DEFAULTS.color[1], DEFAULTS.color[2], DEFAULTS.color[3], DEFAULTS.color[4] }
    return s
end

M.PRESETS = {}

-- 默认：奶白底 + 黑色墨线
M.PRESETS.DEFAULT = copyDefaults()

-- 粗犷有力：标题框、地图路径
local bold = copyDefaults()
bold.jitter         = 2.2
bold.segments       = 16
bold.baseWidth      = 1.6
bold.widthVar       = 0.4
bold.breakChance    = 0.30
bold.color          = { 45, 40, 35, 245 }
bold.cornerEmphasis = 1.3
M.PRESETS.BOLD = bold

-- 精细克制：装备槽、小图标框
local fine = copyDefaults()
fine.jitter         = 0.8
fine.segments       = 12
fine.baseWidth      = 1.0
fine.widthVar       = 0.15
fine.layers         = 1
fine.breakChance    = 0.40
fine.color          = { 60, 55, 45, 200 }
fine.cornerEmphasis = 1.0
M.PRESETS.FINE = fine

-- 完整无断裂：头像框、重要边框
local clean = copyDefaults()
clean.jitter         = 1.2
clean.breakChance    = 0.0
clean.cornerEmphasis = 1.3
clean.color          = { 45, 40, 35, 240 }
M.PRESETS.CLEAN = clean

-- 高断裂虚线：未知区域、锁定状态
local dashed = copyDefaults()
dashed.breakChance  = 0.65
dashed.breakMaxGaps = 5
dashed.breakGapMin  = 4
dashed.breakGapMax  = 12
dashed.breakMinLen  = 60
dashed.baseWidth    = 1.0
dashed.layers       = 1
dashed.color        = { 80, 75, 65, 160 }
M.PRESETS.DASHED = dashed

-- ============================================================================
-- createStyle
-- ============================================================================

function M.createStyle(overrides)
    local s = copyDefaults()
    if overrides then
        for k, v in pairs(overrides) do s[k] = v end
    end
    return s
end

-- ============================================================================
-- drawLine
-- ============================================================================

function M.drawLine(ctx, x1, y1, x2, y2, seed, time, sketch)
    local sk = sketch or M.PRESETS.DEFAULT
    local segs = sk.segments
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end

    local nx = -dy / len
    local ny = dx / len
    local jScale = jitterScale(len, sk)

    local gaps = {}
    if len >= sk.breakMinLen then
        for g = 1, sk.breakMaxGaps do
            local gSeed = seed * 13.7 + g * 77.1
            if hash(gSeed) < sk.breakChance then
                local center = hash(gSeed + 3.3) * 0.7 + 0.15
                local gapPx = sk.breakGapMin
                    + hash(gSeed + 5.7) * (sk.breakGapMax - sk.breakGapMin)
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
            if t < 0.05 then edgeFade = t / 0.05
            elseif t > 0.95 then edgeFade = (1.0 - t) / 0.05 end

            if inGap(t) then
                started = false
            else
                local jx = jitterOffset(layerSeed + i, t, time, sk) * jScale * edgeFade
                local jy = jitterOffset(layerSeed + i + 500, t, time, sk) * jScale * edgeFade
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
        local widthMod = 1.0 + (valueNoise(layerSeed * 5.1) - 0.5) * sk.widthVar
        local cc = sk.color
        nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], math.floor(alpha)))
        nvgStrokeWidth(ctx, sk.baseWidth * widthMod)
        nvgLineCap(ctx, NVG_ROUND)
        nvgLineJoin(ctx, NVG_ROUND)
        nvgStroke(ctx)
    end

    strokeLayer(seed, 0, sk.color[4])
    if sk.layers >= 2 then
        local off = sk.layer2Offset * ((hash(seed * 3.3) - 0.5) * 2)
        strokeLayer(seed + 7000, off, sk.color[4] * sk.layer2Alpha)
    end
end

-- ============================================================================
-- drawRect
-- ============================================================================

function M.drawRect(ctx, x, y, w, h, seed, time, sketch)
    local sk = sketch or M.PRESETS.DEFAULT
    M.drawLine(ctx, x, y, x + w, y, seed + 1, time, sk)
    M.drawLine(ctx, x + w, y, x + w, y + h, seed + 2, time, sk)
    M.drawLine(ctx, x + w, y + h, x, y + h, seed + 3, time, sk)
    M.drawLine(ctx, x, y + h, x, y, seed + 4, time, sk)

    local cornerLen = math.min(w, h) * 0.06
    local cw = sk.baseWidth * sk.cornerEmphasis
    local cc = sk.color
    nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], cc[4]))
    nvgStrokeWidth(ctx, cw)
    nvgLineCap(ctx, NVG_ROUND)

    local corners = {
        { x, y, x + cornerLen, y, x, y + cornerLen },
        { x + w, y, x + w - cornerLen, y, x + w, y + cornerLen },
        { x + w, y + h, x + w - cornerLen, y + h, x + w, y + h - cornerLen },
        { x, y + h, x + cornerLen, y + h, x, y + h - cornerLen },
    }
    for _, c in ipairs(corners) do
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, c[3], c[4])
        nvgLineTo(ctx, c[1], c[2])
        nvgLineTo(ctx, c[5], c[6])
        nvgStroke(ctx)
    end
end

-- ============================================================================
-- drawCircle
-- ============================================================================

function M.drawCircle(ctx, cx, cy, r, seed, time, sketch, segs)
    local sk = sketch or M.PRESETS.DEFAULT
    segs = segs or 16
    local jScale = jitterScale(2 * math.pi * r, sk)

    local function strokeCircleLayer(lSeed, offsetPx, alpha)
        nvgBeginPath(ctx)
        for i = 0, segs do
            local angle = (i / segs) * math.pi * 2
            local t = i / segs
            local jx = jitterOffset(lSeed + i, t, time, sk) * jScale
            local jy = jitterOffset(lSeed + i + 500, t, time, sk) * jScale
            local px = cx + (r + jx + offsetPx) * math.cos(angle)
            local py = cy + (r + jy + offsetPx) * math.sin(angle)
            if i == 0 then nvgMoveTo(ctx, px, py)
            else nvgLineTo(ctx, px, py) end
        end
        nvgClosePath(ctx)
        local cc = sk.color
        nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], math.floor(alpha)))
        nvgStrokeWidth(ctx, sk.baseWidth)
        nvgLineCap(ctx, NVG_ROUND)
        nvgStroke(ctx)
    end

    strokeCircleLayer(seed, 0, sk.color[4])
    if sk.layers >= 2 then
        strokeCircleLayer(seed + 7000, sk.layer2Offset,
            sk.color[4] * sk.layer2Alpha)
    end
end

-- ============================================================================
-- drawDivider
-- ============================================================================

function M.drawDivider(ctx, x, y, w, seed, time, sketch)
    M.drawLine(ctx, x, y, x + w, y, seed, time, sketch)
end

-- ============================================================================
-- drawPaperBg — 纸质感亮底背景
-- ============================================================================

function M.drawPaperBg(ctx, w, h, bgTop, bgBot)
    local t = bgTop or { 245, 240, 230 }
    local b = bgBot or { 235, 228, 215 }
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local bg = nvgLinearGradient(ctx, 0, 0, 0, h,
        nvgRGBA(t[1], t[2], t[3], 255),
        nvgRGBA(b[1], b[2], b[3], 255))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)
    local spotSeed = 42
    for i = 1, 30 do
        local sx = hash(spotSeed + i) * w
        local sy = hash(spotSeed + i + 100) * h
        local sr = hash(spotSeed + i + 200) * 60 + 20
        local sa = hash(spotSeed + i + 300) * 8 + 3
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, sr)
        nvgFillColor(ctx, nvgRGBA(200, 190, 170, math.floor(sa)))
        nvgFill(ctx)
    end
end

-- ============================================================================
-- drawDarkBg — 深色背景
-- ============================================================================

function M.drawDarkBg(ctx, w, h, bgTop, bgBot)
    local t = bgTop or { 42, 40, 36 }
    local b = bgBot or { 50, 48, 42 }
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local bg = nvgLinearGradient(ctx, 0, 0, 0, h,
        nvgRGBA(t[1], t[2], t[3], 255),
        nvgRGBA(b[1], b[2], b[3], 255))
    nvgFillPaint(ctx, bg)
    nvgFill(ctx)
    local spotSeed = 42
    for i = 1, 25 do
        local sx = hash(spotSeed + i) * w
        local sy = hash(spotSeed + i + 100) * h
        local sr = hash(spotSeed + i + 200) * 50 + 15
        local sa = hash(spotSeed + i + 300) * 10 + 5
        nvgBeginPath(ctx)
        nvgCircle(ctx, sx, sy, sr)
        nvgFillColor(ctx, nvgRGBA(25, 23, 20, math.floor(sa)))
        nvgFill(ctx)
    end
end

-- ============================================================================
-- drawCornerDecor — 页面角落装饰
-- ============================================================================

function M.drawCornerDecor(ctx, w, h, margin, color)
    margin = margin or 15
    local cc = color or { 160, 150, 130, 100 }
    local decoLen = math.min(w, h) * 0.08
    nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], cc[4]))
    nvgStrokeWidth(ctx, 1.2)
    nvgLineCap(ctx, NVG_ROUND)
    local pts = {
        { margin, margin + decoLen, margin, margin, margin + decoLen, margin },
        { w - margin - decoLen, margin, w - margin, margin, w - margin, margin + decoLen },
        { w - margin, h - margin - decoLen, w - margin, h - margin, w - margin - decoLen, h - margin },
        { margin + decoLen, h - margin, margin, h - margin, margin, h - margin - decoLen },
    }
    for _, p in ipairs(pts) do
        nvgBeginPath(ctx)
        nvgMoveTo(ctx, p[1], p[2])
        nvgLineTo(ctx, p[3], p[4])
        nvgLineTo(ctx, p[5], p[6])
        nvgStroke(ctx)
    end
end

M.hash = hash
M.valueNoise = valueNoise

return M

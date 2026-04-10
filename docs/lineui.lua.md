-- ============================================================================
-- 文游 UI 风格测试 - 手绘漫画风格边框
-- 特效: 抖动线条、断裂线条、双层叠线、粗细变化、呼吸感
-- 按 Tab 打开调参面板，数字键选参数，左右方向键调值
-- ============================================================================

require "LuaScripts/Utilities/Sample"

-- ============================================================================
-- 全局变量
-- ============================================================================
local vg = nil
local fontNormal = -1

-- 插图纹理
local illustImage = -1

-- 屏幕尺寸
local screenW = 0
local screenH = 0
local dpr = 1.0

-- 时间
local elapsedTime = 0

-- ============================================================================
-- 手绘线条配置（可实时调参）
-- ============================================================================
local SKETCH = {
    jitter        = 1.4,   -- 抖动幅度 px（长边）
    jitterFullLen = 300,   -- 长于此用完整 jitter
    jitterMinLen  = 40,    -- 短于此抖动降到 10%
    segments      = 24,    -- 线段细分数

    -- 断裂
    breakMaxGaps  = 3,     -- 每条长边最多几段断口
    breakChance   = 0.55,  -- 每段断口出现概率
    breakMinLen   = 120,   -- 短于此不断裂
    breakGapMin   = 2,     -- 断口最小像素
    breakGapMax   = 8,     -- 断口最大像素

    -- 线条
    baseWidth     = 1.2,   -- 基础线宽
    widthVar      = 0.3,   -- 粗细随机变化幅度

    -- 双层叠线
    layers        = 2,     -- 层数（1 或 2）
    layer2Alpha   = 0.50,  -- 第二层透明度（0~1）
    layer2Offset  = 0.50,  -- 第二层法向偏移 px

    -- 呼吸
    breathSpeed   = 1.1,
    breathAmp     = 0.2,

    -- 颜色
    color         = { 45, 40, 35, 235 },

    -- 角落
    cornerEmphasis = 1.1,
}

-- 调参面板
local tunerOpen = false
local tunerSelected = 1
local tunerParams = {
    -- { key, display name, min, max, step }
    { "jitter",        "抖动幅度",     0.0, 8.0,  0.2 },
    { "segments",      "细分数",       6,   40,   2   },
    { "breakChance",   "断口概率",     0.0, 1.0,  0.05 },
    { "breakGapMin",   "断口最小px",   1,   20,   1   },
    { "breakGapMax",   "断口最大px",   2,   30,   1   },
    { "baseWidth",     "线宽",         0.5, 4.0,  0.1 },
    { "widthVar",      "粗细变化",     0.0, 1.0,  0.05 },
    { "layers",        "叠线层数",     1,   2,    1   },
    { "layer2Alpha",   "第2层透明度",  0.1, 1.0,  0.05 },
    { "layer2Offset",  "第2层偏移px",  0.2, 3.0,  0.1 },
    { "breathSpeed",   "呼吸速度",     0.0, 2.0,  0.1 },
    { "breathAmp",     "呼吸幅度",     0.0, 1.0,  0.05 },
    { "cornerEmphasis","角落加粗",     1.0, 3.0,  0.1 },
}

-- 文游对话数据
local dialogues = {
    {
        name = "千都",
        text = "这里好安静啊……只能听到风吹过废墟的声音。",
        nameColor = { 180, 200, 220, 255 },
    },
    {
        name = "尤莉",
        text = "安静才好。安静的地方，一般都没有危险的东西。",
        nameColor = { 220, 190, 170, 255 },
    },
    {
        name = "千都",
        text = "话是这么说……但也不会有食物吧。",
        nameColor = { 180, 200, 220, 255 },
    },
    {
        name = "尤莉",
        text = "没事！只要 Kettenkrad 还能跑，我们就能到下一层去找。走吧！",
        nameColor = { 220, 190, 170, 255 },
    },
}
local currentDialogue = 1
local textProgress = 0
local textSpeed = 12
local textComplete = false

-- ============================================================================
-- 哈希 / 噪声
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

local function jitterOffset(seed, pos, time)
    local breathPhase = math.sin(time * SKETCH.breathSpeed + seed * 0.7) * SKETCH.breathAmp
    local base = (valueNoise(pos * 3.0 + seed * 17.3) - 0.5) * 2.0
    return base * SKETCH.jitter * (1.0 + breathPhase)
end

-- ============================================================================
-- 手绘线条
-- ============================================================================

local function jitterScale(len)
    if len >= SKETCH.jitterFullLen then return 1.0 end
    if len <= SKETCH.jitterMinLen then return 0.1 end
    local t = (len - SKETCH.jitterMinLen) / (SKETCH.jitterFullLen - SKETCH.jitterMinLen)
    return 0.1 + t * 0.9
end

--- 绘制一条手绘直线（支持双层）
local function drawSketchLine(ctx, x1, y1, x2, y2, seed, time)
    local segs = SKETCH.segments
    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end

    local nx = -dy / len
    local ny = dx / len
    local jScale = jitterScale(len)

    -- 构建断口表
    local gaps = {}
    if len >= SKETCH.breakMinLen then
        for g = 1, SKETCH.breakMaxGaps do
            local gSeed = seed * 13.7 + g * 77.1
            if hash(gSeed) < SKETCH.breakChance then
                local center = hash(gSeed + 3.3) * 0.7 + 0.15
                -- 随机浮动：在 min~max 之间
                local gapPx = SKETCH.breakGapMin
                    + hash(gSeed + 5.7) * (SKETCH.breakGapMax - SKETCH.breakGapMin)
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

    -- 绘制单层线条
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
                local jx = jitterOffset(layerSeed + i, t, time) * jScale * edgeFade
                local jy = jitterOffset(layerSeed + i + 500, t, time) * jScale * edgeFade

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

        local widthMod = 1.0 + (valueNoise(layerSeed * 5.1) - 0.5) * SKETCH.widthVar
        local cc = SKETCH.color
        nvgStrokeColor(ctx, nvgRGBA(cc[1], cc[2], cc[3], math.floor(alpha)))
        nvgStrokeWidth(ctx, SKETCH.baseWidth * widthMod)
        nvgLineCap(ctx, NVG_ROUND)
        nvgLineJoin(ctx, NVG_ROUND)
        nvgStroke(ctx)
    end

    -- 第一层：主线，满 alpha
    strokeLayer(seed, 0, SKETCH.color[4])

    -- 第二层：微偏移 + 淡化
    if SKETCH.layers >= 2 then
        local off = SKETCH.layer2Offset * ((hash(seed * 3.3) - 0.5) * 2)
        strokeLayer(seed + 7000, off, SKETCH.color[4] * SKETCH.layer2Alpha)
    end
end

--- 绘制手绘矩形边框
local function drawSketchRect(ctx, x, y, w, h, seed, time)
    drawSketchLine(ctx, x, y, x + w, y, seed + 1, time)
    drawSketchLine(ctx, x + w, y, x + w, y + h, seed + 2, time)
    drawSketchLine(ctx, x + w, y + h, x, y + h, seed + 3, time)
    drawSketchLine(ctx, x, y + h, x, y, seed + 4, time)

    -- 角落强调
    local cornerLen = math.min(w, h) * 0.06
    local cw = SKETCH.baseWidth * SKETCH.cornerEmphasis
    local cc = SKETCH.color
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

local function drawSketchDivider(ctx, x, y, w, seed, time)
    drawSketchLine(ctx, x, y, x + w, y, seed, time)
end

-- ============================================================================
-- 纹理加载
-- ============================================================================

local function loadIllustration()
    if vg == nil then return end
    illustImage = nvgCreateImage(vg, "image/shoujo_shuumatsu_20260410065153.png", 0)
    if illustImage == -1 then
        print("WARNING: Could not load illustration image")
    else
        print("Illustration loaded, imageId = " .. illustImage)
    end
end

-- ============================================================================
-- UI 绘制
-- ============================================================================

local function drawPaperBackground(ctx, w, h)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local bg = nvgLinearGradient(ctx, 0, 0, 0, h,
        nvgRGBA(245, 240, 230, 255),
        nvgRGBA(235, 228, 215, 255))
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

local function drawIllustration(ctx, x, y, w, h, time)
    nvgBeginPath(ctx)
    nvgRect(ctx, x, y, w, h)
    nvgFillColor(ctx, nvgRGBA(220, 215, 205, 255))
    nvgFill(ctx)

    if illustImage ~= -1 then
        local imgPaint = nvgImagePattern(ctx, x, y, w, h, 0, illustImage, 1.0)
        nvgBeginPath(ctx)
        nvgRect(ctx, x, y, w, h)
        nvgFillPaint(ctx, imgPaint)
        nvgFill(ctx)
    end

    drawSketchRect(ctx, x, y, w, h, 100, time)
end

local function drawDialogueBox(ctx, x, y, w, h, time)
    nvgBeginPath(ctx)
    nvgRect(ctx, x + 3, y + 3, w - 6, h - 6)
    nvgFillColor(ctx, nvgRGBA(250, 245, 235, 230))
    nvgFill(ctx)

    drawSketchRect(ctx, x, y, w, h, 200, time)

    local dlg = dialogues[currentDialogue]
    if not dlg then return end

    -- 角色名
    local nameW = 120
    local nameH = 32
    local nameX = x + 20
    local nameY = y - 16

    nvgBeginPath(ctx)
    nvgRect(ctx, nameX + 2, nameY + 2, nameW - 4, nameH - 4)
    nvgFillColor(ctx, nvgRGBA(250, 245, 235, 250))
    nvgFill(ctx)

    drawSketchRect(ctx, nameX, nameY, nameW, nameH, 300 + currentDialogue * 10, time)

    if fontNormal ~= -1 then
        nvgFontFaceId(ctx, fontNormal)
        nvgFontSize(ctx, 16)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(dlg.nameColor[1], dlg.nameColor[2], dlg.nameColor[3], dlg.nameColor[4]))
        nvgText(ctx, nameX + nameW / 2, nameY + nameH / 2, dlg.name, nil)
    end

    -- 对话文字（打字机）
    if fontNormal ~= -1 then
        local textX = x + 30
        local textY = y + 28
        local maxW = w - 60

        local fullText = dlg.text
        local displayLen = math.floor(textProgress)

        -- UTF-8 截取
        local displayText = ""
        local charCount = 0
        local i = 1
        while i <= #fullText and charCount < displayLen do
            local b = string.byte(fullText, i)
            local charLen = 1
            if b >= 0xF0 then charLen = 4
            elseif b >= 0xE0 then charLen = 3
            elseif b >= 0xC0 then charLen = 2
            end
            displayText = displayText .. string.sub(fullText, i, i + charLen - 1)
            charCount = charCount + 1
            i = i + charLen
        end

        nvgFontFaceId(ctx, fontNormal)
        nvgFontSize(ctx, 18)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, nvgRGBA(50, 45, 40, 240))
        nvgTextBox(ctx, textX, textY, maxW, displayText, nil)

        -- 继续提示三角
        if textComplete then
            local triX = x + w - 35
            local triY = y + h - 20
            local bounce = math.sin(elapsedTime * 3) * 3
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, triX, triY + bounce)
            nvgLineTo(ctx, triX + 8, triY + 8 + bounce)
            nvgLineTo(ctx, triX - 8, triY + 8 + bounce)
            nvgClosePath(ctx)
            nvgFillColor(ctx, nvgRGBA(50, 45, 40, 180))
            nvgFill(ctx)
        end
    end
end

local function drawPageDecoration(ctx, w, h)
    local decoLen = math.min(w, h) * 0.08
    local margin = 15
    nvgStrokeColor(ctx, nvgRGBA(160, 150, 130, 100))
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

local function drawTitle(ctx, w, time)
    if fontNormal == -1 then return end
    nvgFontFaceId(ctx, fontNormal)
    nvgFontSize(ctx, 14)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(140, 130, 115, 200))
    nvgText(ctx, w / 2, 25, "- 少女终末旅行 -", nil)
    drawSketchDivider(ctx, w / 2 - 80, 48, 160, 500, time)
end

local function drawBottomHint(ctx, w, h)
    if fontNormal == -1 then return end
    nvgFontFaceId(ctx, fontNormal)
    nvgFontSize(ctx, 12)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_BOTTOM)
    nvgFillColor(ctx, nvgRGBA(160, 150, 130, 180))
    local hint = tunerOpen
        and "Tab:关闭面板 | 1-9/0:选参数 | 左右:调值"
        or  "点击继续 | Tab:调参面板"
    nvgText(ctx, w / 2, h - 10, hint, nil)
end

local function drawScatterStrokes(ctx, w, h, time)
    local strokes = {
        { 0.05, 0.15, 0.08, 0.15, 600 },
        { 0.92, 0.12, 0.95, 0.13, 601 },
        { 0.03, 0.88, 0.06, 0.87, 602 },
        { 0.94, 0.92, 0.97, 0.91, 603 },
    }
    for _, s in ipairs(strokes) do
        drawSketchLine(ctx, s[1] * w, s[2] * h, s[3] * w, s[4] * h, s[5], time)
    end
end

-- ============================================================================
-- 调参面板绘制
-- ============================================================================

local function drawTunerPanel(ctx, w, h)
    if not tunerOpen then return end
    if fontNormal == -1 then return end

    local panelW = 260
    local lineH = 22
    local panelH = (#tunerParams + 1) * lineH + 16
    local px = w - panelW - 12
    local py = 12

    -- 面板背景
    nvgBeginPath(ctx)
    nvgRoundedRect(ctx, px, py, panelW, panelH, 6)
    nvgFillColor(ctx, nvgRGBA(20, 20, 15, 210))
    nvgFill(ctx)

    nvgFontFaceId(ctx, fontNormal)
    nvgFontSize(ctx, 13)
    nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)

    -- 标题
    nvgFillColor(ctx, nvgRGBA(255, 220, 120, 255))
    nvgText(ctx, px + 10, py + 6, "手绘参数调节 (Tab 关闭)", nil)

    for i, param in ipairs(tunerParams) do
        local y = py + 6 + i * lineH
        local key = param[1]
        local name = param[2]
        local val = SKETCH[key]
        local isSelected = (i == tunerSelected)

        -- 选中高亮
        if isSelected then
            nvgBeginPath(ctx)
            nvgRect(ctx, px + 2, y - 1, panelW - 4, lineH)
            nvgFillColor(ctx, nvgRGBA(80, 70, 40, 150))
            nvgFill(ctx)
        end

        -- 序号
        local numKey = i <= 9 and tostring(i) or "0"
        nvgFillColor(ctx, isSelected and nvgRGBA(255, 200, 80, 255) or nvgRGBA(120, 120, 100, 200))
        nvgText(ctx, px + 10, y, numKey .. ".", nil)

        -- 参数名
        nvgFillColor(ctx, isSelected and nvgRGBA(255, 255, 240, 255) or nvgRGBA(200, 200, 190, 220))
        nvgText(ctx, px + 30, y, name, nil)

        -- 参数值
        local valStr
        if val == math.floor(val) then
            valStr = string.format("%d", val)
        else
            valStr = string.format("%.2f", val)
        end

        nvgTextAlign(ctx, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        nvgFillColor(ctx, isSelected and nvgRGBA(120, 255, 120, 255) or nvgRGBA(180, 220, 180, 220))
        nvgText(ctx, px + panelW - 10, y, valStr, nil)
        nvgTextAlign(ctx, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    end
end

-- ============================================================================
-- 主渲染
-- ============================================================================

local function handleRender(eventType, eventData)
    if vg == nil then return end

    screenW = graphics:GetWidth()
    screenH = graphics:GetHeight()
    dpr = graphics:GetDPR()
    local logW = screenW / dpr
    local logH = screenH / dpr

    nvgBeginFrame(vg, screenW, screenH, dpr)

    drawPaperBackground(vg, logW, logH)
    drawPageDecoration(vg, logW, logH)
    drawTitle(vg, logW, elapsedTime)

    -- 布局
    local margin = 30
    local titleAreaH = 60
    local illustX = margin
    local illustY = titleAreaH
    local illustW = logW - margin * 2
    local illustH = logH * 0.50
    local dlgMargin = 25
    local dlgX = dlgMargin
    local dlgY = illustY + illustH + 18
    local dlgW = logW - dlgMargin * 2
    local dlgH = logH - dlgY - 35

    drawIllustration(vg, illustX, illustY, illustW, illustH, elapsedTime)
    drawDialogueBox(vg, dlgX, dlgY, dlgW, dlgH, elapsedTime)
    drawScatterStrokes(vg, logW, logH, elapsedTime)
    drawBottomHint(vg, logW, logH)

    -- 调参面板（最上层）
    drawTunerPanel(vg, logW, logH)

    nvgEndFrame(vg)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

local function countUtf8Chars(str)
    local count = 0
    local i = 1
    while i <= #str do
        local b = string.byte(str, i)
        if b >= 0xF0 then i = i + 4
        elseif b >= 0xE0 then i = i + 3
        elseif b >= 0xC0 then i = i + 2
        else i = i + 1 end
        count = count + 1
    end
    return count
end

local function handleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    elapsedTime = elapsedTime + dt

    if not textComplete then
        local dlg = dialogues[currentDialogue]
        if dlg then
            textProgress = textProgress + textSpeed * dt
            if textProgress >= countUtf8Chars(dlg.text) then
                textProgress = countUtf8Chars(dlg.text)
                textComplete = true
            end
        end
    end
end

local function advanceDialogue()
    if textComplete then
        currentDialogue = currentDialogue + 1
        if currentDialogue > #dialogues then currentDialogue = 1 end
        textProgress = 0
        textComplete = false
    else
        local dlg = dialogues[currentDialogue]
        if dlg then
            textProgress = countUtf8Chars(dlg.text)
            textComplete = true
        end
    end
end

local function handleMouseClick(eventType, eventData)
    local button = eventData["Button"]:GetInt()
    if button ~= MOUSEB_LEFT then return end
    if tunerOpen then return end  -- 面板开着时不推进对话
    advanceDialogue()
end

local function handleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- Tab 切换面板
    if key == KEY_TAB then
        tunerOpen = not tunerOpen
        return
    end

    -- 面板打开时处理调参
    if tunerOpen then
        -- 数字键选择参数: 1-9 对应 1-9, 0 对应 10
        if key >= KEY_1 and key <= KEY_9 then
            tunerSelected = key - KEY_1 + 1
            if tunerSelected > #tunerParams then tunerSelected = #tunerParams end
            return
        elseif key == KEY_0 then
            tunerSelected = 10
            if tunerSelected > #tunerParams then tunerSelected = #tunerParams end
            return
        end

        -- 上下键选择参数
        if key == KEY_UP then
            tunerSelected = tunerSelected - 1
            if tunerSelected < 1 then tunerSelected = #tunerParams end
            return
        elseif key == KEY_DOWN then
            tunerSelected = tunerSelected + 1
            if tunerSelected > #tunerParams then tunerSelected = 1 end
            return
        end

        -- 左右键调值
        if key == KEY_LEFT or key == KEY_RIGHT then
            local param = tunerParams[tunerSelected]
            if param then
                local pKey = param[1]
                local pMin = param[3]
                local pMax = param[4]
                local pStep = param[5]
                local dir = (key == KEY_RIGHT) and 1 or -1
                local newVal = SKETCH[pKey] + dir * pStep
                -- 钳制
                if newVal < pMin then newVal = pMin end
                if newVal > pMax then newVal = pMax end
                -- 整数参数保持整数
                if pStep == math.floor(pStep) then
                    newVal = math.floor(newVal + 0.5)
                end
                SKETCH[pKey] = newVal
            end
            return
        end

        return  -- 面板打开时吃掉其他按键
    end

    -- 面板关闭时，空格/回车推进对话
    if key == KEY_SPACE or key == KEY_RETURN then
        advanceDialogue()
    end
end

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    SampleStart()
    graphics.windowTitle = "手绘风格文游 UI 测试"

    vg = nvgCreate(1)
    if vg == nil then
        print("ERROR: Failed to create NanoVG context")
        return
    end

    fontNormal = nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
    if fontNormal == -1 then
        print("ERROR: Failed to load font")
    end

    loadIllustration()
    SampleInitMouseMode(MM_FREE)

    SubscribeToEvent(vg, "NanoVGRender", handleRender)
    SubscribeToEvent("Update", handleUpdate)
    SubscribeToEvent("MouseButtonDown", handleMouseClick)
    SubscribeToEvent("KeyDown", handleKeyDown)
    SubscribeToEvent("TouchEnd", handleMouseClick)

    print("=== 手绘风格文游 UI 测试 启动完成 ===")
    print("按 Tab 打开调参面板")
end

function Stop()
    if vg ~= nil then
        nvgDelete(vg)
        vg = nil
    end
end

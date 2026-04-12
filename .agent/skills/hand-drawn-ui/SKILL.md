---
name: hand-drawn-ui
description: |
  手绘漫画风格 UI 边框绘制系统（NanoVG）。提供完整的素描线条、矩形、圆形绘制函数和参数预设。
  默认配色：奶白色底 + 黑色线条。可根据场景切换为深色底 + 浅色线条。
  Use when: (1) 用户要求手绘/素描/漫画/manga 风格的 UI,
  (2) 用户要求"纸质感"、"手写感"、"涂鸦风"的界面,
  (3) 用户要求 NanoVG 绘制带抖动/不规则的边框,
  (4) hand-drawn UI, sketch style, manga style border
---

# 手绘漫画风 UI（SketchDraw）

## 快速开始

**1. 复制库文件到用户项目：**

```bash
cp references/sketch-drawing-lib.lua → scripts/sketch-drawing-lib.lua
```

**2. 在主文件中使用：**

```lua
local Sketch = require "sketch-drawing-lib"

function HandleNanoVGRender(eventType, eventData)
    nvgBeginFrame(vg, screenW, screenH, dpr)
    local logW, logH = screenW / dpr, screenH / dpr

    -- 纸质感背景
    Sketch.drawPaperBg(vg, logW, logH)

    -- 手绘矩形（使用默认预设）
    Sketch.drawRect(vg, 50, 50, 200, 120, 100, elapsedTime)

    -- 手绘矩形（粗犷预设）
    Sketch.drawRect(vg, 50, 200, 200, 80, 200, elapsedTime, Sketch.PRESETS.BOLD)

    -- 自定义风格
    local myStyle = Sketch.createStyle({
        jitter = 0.6, color = { 180, 50, 30, 220 }, layers = 1,
    })
    Sketch.drawCircle(vg, 300, 100, 40, 300, elapsedTime, myStyle)

    nvgEndFrame(vg)
end
```

---

## API 速查

| 函数 | 签名 | 说明 |
|------|------|------|
| `drawLine` | `(ctx, x1, y1, x2, y2, seed, time, sketch?)` | 手绘直线 |
| `drawRect` | `(ctx, x, y, w, h, seed, time, sketch?)` | 手绘矩形（含角落强调） |
| `drawCircle` | `(ctx, cx, cy, r, seed, time, sketch?, segs?)` | 手绘圆形 |
| `drawDivider` | `(ctx, x, y, w, seed, time, sketch?)` | 水平分割线 |
| `drawPaperBg` | `(ctx, w, h, bgTop?, bgBot?)` | 奶白纸质背景 |
| `drawDarkBg` | `(ctx, w, h, bgTop?, bgBot?)` | 深色背景 |
| `drawCornerDecor` | `(ctx, w, h, margin?, color?)` | 四角 L 形装饰 |
| `createStyle` | `(overrides?)` | 基于默认值创建自定义参数表 |

**通用参数说明：**
- `ctx`：NanoVG 上下文（`vg`）
- `seed`：整数随机种子，不同 seed 产生不同抖动形态，相同 seed 每帧形态一致
- `time`：当前时间（`elapsedTime`），驱动呼吸动画
- `sketch`：可选，SKETCH 参数表（nil 时使用 `PRESETS.DEFAULT`）

---

## SKETCH 参数表

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `jitter` | number | 1.4 | 抖动幅度 px（长边） |
| `jitterFullLen` | number | 300 | 长于此用完整 jitter |
| `jitterMinLen` | number | 40 | 短于此抖动降到 10% |
| `segments` | number | 24 | 线段细分数（越大越平滑） |
| `breakMaxGaps` | number | 3 | 每条长边最多断口数 |
| `breakChance` | number | 0.55 | 每段断口出现概率 (0~1) |
| `breakMinLen` | number | 120 | 短于此不断裂 |
| `breakGapMin` | number | 2 | 断口最小像素 |
| `breakGapMax` | number | 8 | 断口最大像素 |
| `baseWidth` | number | 1.2 | 基础线宽 |
| `widthVar` | number | 0.3 | 粗细随机变化幅度 (0~1) |
| `layers` | number | 2 | 层数（1 或 2，2 = 双层叠线） |
| `layer2Alpha` | number | 0.50 | 第二层透明度 |
| `layer2Offset` | number | 0.50 | 第二层法向偏移 px |
| `breathSpeed` | number | 1.1 | 呼吸动画速度 |
| `breathAmp` | number | 0.2 | 呼吸振幅 |
| `color` | {r,g,b,a} | {45,40,35,235} | 线条颜色 RGBA |
| `cornerEmphasis` | number | 1.1 | 角落加粗倍数（仅 drawRect） |

---

## 5 个内置预设

| 预设 | 适用场景 | 关键差异 |
|------|---------|---------|
| **DEFAULT** | 通用边框、对话框 | 标准参数，奶白底+黑线 |
| **BOLD** | 标题框、地图路径、强调元素 | jitter=2.2, baseWidth=1.6, 少断裂 |
| **FINE** | 装备槽、小图标、次要元素 | jitter=0.8, 单层, 精细 |
| **CLEAN** | 头像框、重要边框 | breakChance=0, 无断裂, 角落强调 |
| **DASHED** | 未知区域、锁定状态、虚线 | breakChance=0.65, 多断口, 淡色 |

**使用方式：**
```lua
Sketch.drawRect(vg, x, y, w, h, seed, time, Sketch.PRESETS.BOLD)
Sketch.drawCircle(vg, cx, cy, r, seed, time, Sketch.PRESETS.DASHED)
```

---

## 配色方案

### 方案 A：亮底（默认推荐）

奶白纸张 + 深色墨线，文艺清新感。

```lua
-- 背景
Sketch.drawPaperBg(vg, logW, logH)  -- 默认 (245,240,230) → (235,228,215)

-- 边框使用默认 color = {45, 40, 35, 235}（深墨色）
Sketch.drawRect(vg, x, y, w, h, seed, time)  -- 自动使用 DEFAULT 预设

-- 文字色：{50, 45, 40, 240}（正文）/ {140, 130, 115, 200}（副标题）
-- 填充色：{250, 245, 235, 230}（面板内底）
```

### 方案 B：暗底

深色背景 + 浅色线条，适合废土/暗黑/夜间风格。

```lua
-- 背景
Sketch.drawDarkBg(vg, logW, logH)  -- 默认 (42,40,36) → (50,48,42)

-- 需要创建浅色线条风格
local LIGHT_SKETCH = Sketch.createStyle({
    color = { 160, 148, 120, 160 },  -- 浅暖灰色
    baseWidth = 1.1,
    jitter = 1.6,
})
Sketch.drawRect(vg, x, y, w, h, seed, time, LIGHT_SKETCH)

-- 文字色：{220, 212, 195, 240}（正文）/ {140, 132, 115, 180}（副标题）
-- 填充色：{58, 54, 46, 230}（面板内底）
```

---

## 视觉层级指南

通过参数梯度建立 UI 层级（从强到弱）：

```
┌─────────────────────────────────────────────────────┐
│  层级1 - 主框架  │ BOLD / CLEAN │ 粗、少断、角落强调  │
│  层级2 - 内容框  │ DEFAULT      │ 标准参数            │
│  层级3 - 次要框  │ FINE         │ 细、单层、精细      │
│  层级4 - 装饰    │ DASHED       │ 多断、淡色          │
└─────────────────────────────────────────────────────┘
```

**示例：对话框场景**
```lua
-- 外框：完整无断裂
Sketch.drawRect(vg, boxX, boxY, boxW, boxH, 100, time, Sketch.PRESETS.CLEAN)

-- 角色名标签：默认
Sketch.drawRect(vg, nameX, nameY, nameW, nameH, 200, time)

-- 分割线：标准
Sketch.drawDivider(vg, divX, divY, divW, 300, time)

-- 装饰散线：虚线
Sketch.drawLine(vg, decoX1, decoY1, decoX2, decoY2, 400, time, Sketch.PRESETS.DASHED)
```

---

## 交互模式：按钮

手绘按钮需要 hitTest + 3 态视觉反馈：

```lua
local btnRects = {}  -- 每帧重建
local hoveredBtn = 0
local pressedBtn = 0

-- 在渲染中构建碰撞区并绘制
for i, btn in ipairs(buttons) do
    btnRects[i] = { x = bx, y = by, w = bw, h = bh }

    local isHover = (hoveredBtn == i)
    local isPress = (pressedBtn == i)

    -- 3 态填充色
    local fill = isPress  and { 220, 215, 195 }
              or isHover and { 245, 240, 225 }
              or              { 250, 245, 235 }

    -- 按下偏移（手感）
    local ox = isPress and 1 or 0
    local oy = isPress and 1 or 0

    nvgBeginPath(ctx)
    nvgRect(ctx, bx + ox, by + oy, bw, bh)
    nvgFillColor(ctx, nvgRGBA(fill[1], fill[2], fill[3], 230))
    nvgFill(ctx)
    Sketch.drawRect(ctx, bx + ox, by + oy, bw, bh, btn.seed, time)
end

-- hitTest（在 Update 中调用）
local function hitTest(mx, my)
    for i, r in ipairs(btnRects) do
        if mx >= r.x and mx <= r.x + r.w
        and my >= r.y and my <= r.y + r.h then
            return i
        end
    end
    return 0
end

-- ⚠️ 鼠标坐标需要 DPR 转换
local dpr = graphics:GetDPR()
local mx = input.mousePosition.x / dpr
local my = input.mousePosition.y / dpr
hoveredBtn = hitTest(mx, my)
```

---

## 常用装饰

```lua
-- 页面四角 L 形装饰
Sketch.drawCornerDecor(vg, logW, logH)

-- 散落的随机短线（氛围感）
local strokes = {
    { 0.05, 0.15, 0.08, 0.15 },
    { 0.92, 0.12, 0.95, 0.13 },
}
for i, s in ipairs(strokes) do
    Sketch.drawLine(vg, s[1]*logW, s[2]*logH, s[3]*logW, s[4]*logH, 600+i, time)
end
```

---

## 注意事项

1. **seed 必须稳定**：同一元素每帧用相同 seed，否则线条会剧烈抖动
2. **time 驱动呼吸**：传入累计时间即可，线条会自然微动
3. **短线自动抑制**：线长 < `jitterMinLen` 时抖动自动降到 10%，无需手动调整
4. **NanoVG 事件**：所有绘制必须在 `NanoVGRender` 事件回调中执行
5. **字体需先创建**：`nvgCreateFont` 只在 `Start()` 中调用一次

# 教程与气泡引导系统

> 状态：已实施 | 最后更新：2026-04-10

## 概述

游戏的教程引导分为两个层次：

| 层次 | 形式 | 驱动方式 | 典型场景 |
|------|------|---------|---------|
| **主线教程** | Flag 推导阶段 + 专属订单 + 到达拦截 | `Tutorial.get_phase()` | 新游戏开局引导 |
| **功能气泡** | SpeechBubble 多步对话 | Flag 一次性触发 | 首次打开某功能 |

两者共用同一套 Flag 系统（`core/flags.lua`）和头像常量。

---

## 文件结构

```
scripts/
  core/flags.lua            -- Flag 读写（set/has/clear）
  narrative/tutorial.lua     -- 教程逻辑中心（阶段推导、订单、气泡步骤）
  ui/speech_bubble.lua       -- 气泡 UI 组件（show/hide/update）
  ui/screen_shop.lua         -- 商店教程气泡集成
  ui/screen_truck.lua        -- 货车教程气泡集成
  ui/screen_explore.lua      -- 搜刮教程气泡集成
  ui/screen_map.lua          -- 自动计划教程气泡集成
  ui/shell_top.lua           -- 收音机教程气泡（pending 标记）
  ui/shell.lua               -- 收音机教程气泡（pending 消费 + SpeechBubble 驱动）
```

---

## 已实现的功能气泡教程

| Flag | 触发时机 | 步数 | 获取函数 | 集成位置 |
|------|---------|------|---------|---------|
| `tutorial_shop_intro` | 首次进入交易所 | 5 | `get_shop_tutorial_steps` | `screen_shop.lua` |
| `tutorial_truck_intro` | 首次进入货车页面 | 5 | `get_truck_intro_steps` | `screen_truck.lua` |
| `tutorial_radio_intro` | 首次打开收音机 | 5 | `get_radio_intro_steps` | `shell_top.lua` + `shell.lua` |
| `tutorial_auto_plan_intro` | 首次打开自动计划 | 7 | `get_auto_plan_intro_steps` | `screen_map.lua` |
| `tutorial_explore_scavenge` | 首次进入资源点搜刮 | 6 | `get_explore_intro_steps` | `screen_explore.lua` |

---

## 核心 API

### Flag 系统（`core/flags.lua`）

```lua
local Flags = require("core/flags")

Flags.set(state, "tutorial_xxx")       -- 标记已完成
Flags.has(state, "tutorial_xxx")       -- 检查是否已完成（返回 boolean）
Flags.clear(state, "tutorial_xxx")     -- 清除标记（调试用）
```

Flag 存储在 `state.flags` 表中，随存档持久化。

### SpeechBubble（`ui/speech_bubble.lua`）

```lua
local SpeechBubble = require("ui/speech_bubble")

-- 显示一个气泡（命令式）
SpeechBubble.show(parent, {
    portrait  = "image/linli_avatar.png",  -- 头像路径
    speaker   = "林砾",                     -- 说话者名字
    text      = "这是一段引导文本。",        -- 对话内容
    autoHide  = 0,                         -- 0 = 点击关闭；>0 = 自动消失秒数
    onDismiss = function() end,            -- 关闭后的回调
})

-- 隐藏当前气泡
SpeechBubble.hide()

-- 每帧驱动（必须在 update 中调用，否则 autoHide 不生效）
SpeechBubble.update(dt)

-- 检查是否正在显示
SpeechBubble.is_showing()
```

### 头像常量

```lua
local Tutorial = require("narrative/tutorial")

Tutorial.AVATAR_LINLI   -- "image/linli_avatar.png"
Tutorial.AVATAR_TAOXIA  -- "image/taoxia_avatar.png"
```

---

## 如何添加新的教程气泡

### 第一步：在 tutorial.lua 中添加步骤函数

在 `scripts/narrative/tutorial.lua` 中添加一个新函数，返回气泡步骤数组：

```lua
--- 获取 XXX 初次教程步骤
--- 返回 nil 表示不需要（已触发过）
---@param state table
---@return table[]|nil steps
function M.get_xxx_intro_steps(state)
    -- 用 flag 防止重复触发
    if Flags.has(state, "tutorial_xxx_intro") then return nil end

    return {
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "第一句台词。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "第二句台词。",
        },
        -- ... 更多步骤
    }
end
```

**命名规范**：
- 函数名：`get_xxx_intro_steps`
- Flag 名：`tutorial_xxx_intro`
- 两者的 `xxx` 部分保持一致

### 第二步：在目标页面集成触发

根据页面类型选择对应的集成模式。

#### 模式 A：普通页面（无 Shell 重建问题）

适用于：screen_shop、screen_truck、screen_explore 等独立页面。

```lua
-- 1. 文件头部引入
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local Flags        = require("core/flags")

-- 2. 添加气泡序列辅助函数
local function showXxxTutorialStep(parent, state, steps, index, onComplete)
    if index > #steps then
        Flags.set(state, "tutorial_xxx_intro")
        if onComplete then onComplete() end
        return
    end
    local step = steps[index]
    SpeechBubble.show(parent, {
        portrait  = step.portrait,
        speaker   = step.speaker,
        text      = step.text,
        autoHide  = 0,
        onDismiss = function()
            showXxxTutorialStep(parent, state, steps, index + 1, onComplete)
        end,
    })
end

-- 3. 在合适的时机触发（如按钮 onClick、页面 create 等）
local introSteps = Tutorial.get_xxx_intro_steps(state)
if introSteps then
    local root = UI.GetRoot()
    if root then
        showXxxTutorialStep(root, state, introSteps, 1)
    end
end

-- 4. 在 update 中驱动 SpeechBubble
function M.update(state, dt, r)
    SpeechBubble.update(dt)
end
```

**Flag 设置时机**：在最后一步 `onDismiss` 之后设置（即 `index > #steps` 时）。这样玩家中途退出不会被记为已读，下次还会触发。

#### 模式 B：Shell 页面中的功能（有重建问题）

适用于：收音机开关等会触发 Shell UI 重建的场景。

**问题**：Shell 重建会销毁气泡的父节点，导致气泡消失。

**解决**：使用 pending 模式——在触发处标记，在 shell.lua update 的 rebuild 检测之后消费。

```lua
-- shell_top.lua 中（触发处）：
onClick = function(self)
    -- ... 执行操作（如 Radio.set_on）...

    local steps = Tutorial.get_xxx_intro_steps(state)
    if steps then
        Flags.set(state, "tutorial_xxx_intro")
        -- 不直接 show，而是标记 pending
        M._pendingXxxTutorial = { state = state, steps = steps }
    end
end

-- shell.lua update 中（消费处，必须在 needRebuild return 之后）：
if needRebuild then
    -- ... 重置状态 ...
    return true     -- ← rebuild 帧提前返回，pending 数据存活
end

-- ↓ 放在 needRebuild 块之后，rebuild 完成的下一帧才执行
if ShellTop._pendingXxxTutorial then
    local pending = ShellTop._pendingXxxTutorial
    ShellTop._pendingXxxTutorial = nil
    ShellTop._showBubbleSequence(root, pending.state, pending.steps, 1)
end
```

**关键**：pending 检查必须在 `if needRebuild then return true end` 之后，否则同帧触发会被 rebuild 立刻销毁。

#### 模式 C：在操作之前拦截

适用于：自动计划等"先看教程再打开功能"的场景。

```lua
local introSteps = Tutorial.get_xxx_intro_steps(state)
if introSteps then
    local root = UI.GetRoot()
    if root then
        showXxxTutorialStep(root, state, introSteps, 1, function()
            -- 教程结束后再执行原本的操作
            actualOpenFunction()
        end)
        return  -- 拦截，不立即执行
    end
end

-- 正常执行（非首次，或获取不到 steps）
actualOpenFunction()
```

### 第三步：确认 SpeechBubble.update 已接入

检查目标页面的 `update` 函数中是否已调用 `SpeechBubble.update(dt)`。如果页面本身没有 update 或没有调用，需要添加。

对于 Shell 包裹的页面，`shell.lua` 的 update 已统一调用 `SpeechBubble.update(dt)`，无需在子页面重复调用——但如果页面不在 Shell 内（如 screen_explore），则需要在页面自己的 update 中调用。

---

## 气泡对话写作指南

### 角色分工

| 角色 | 性格 | 在教程中的职能 |
|------|------|--------------|
| **林砾** | 冷静、务实、知识丰富 | 讲解机制、说明规则、提醒风险 |
| **陶夏** | 活泼、好奇、感性 | 提问引出话题、总结要点、表达玩家的直觉反应 |

### 写作原则

1. **简短**：每步不超过 30 字，玩家在学习操作时没耐心读长文
2. **自然**：用对话口吻，不要像说明书。陶夏负责问"为什么"，林砾负责答
3. **实用**：讲清楚"做什么"和"不做什么会怎样"，少讲原理
4. **收尾明确**：最后一句通常由陶夏说，带有总结性质（"明白了！""记住了！"）
5. **步数控制**：5-7 步为宜，超过 7 步考虑是否信息过载

### 对话模板

```
步骤 1（林砾）：介绍功能是什么
步骤 2（陶夏）：表示好奇/追问
步骤 3（林砾）：解释核心操作
步骤 4（陶夏）：追问延伸问题
步骤 5（林砾）：补充注意事项/风险
步骤 6（陶夏）：总结/表态
```

---

## 主线教程系统（补充说明）

主线教程通过 `Tutorial.get_phase(state)` 推导当前阶段，用于控制专属订单生成和到达拦截。

### 阶段流程

```
NONE → SPAWN → TRAVEL_TO_GREENHOUSE → AT_GREENHOUSE → GREENHOUSE_FREE → EXPLORE → COMPLETE
```

### 关键 Flag

| Flag | 含义 |
|------|------|
| `tutorial_started` | 教程已开始（新游戏自动设置） |
| `tutorial_arrived_greenhouse` | 已到达温室社区 |
| `tutorial_campfire_done` | 篝火引导完成 |
| `tutorial_explore_guided` | 探索引导完成 |
| `tutorial_arrived_tower` | 已到达北穹塔台 |

### 与功能气泡的关系

主线教程和功能气泡是独立的。功能气泡只看自己的 flag（如 `tutorial_shop_intro`），不关心主线教程处于哪个阶段。玩家即使跳过了主线教程（旧存档），首次打开某功能时仍会看到对应的功能气泡。

# 移动端 Touch + Mouse 双触发陷阱

## 问题

收音机在手机上点击"开启"按钮无反应——实际是瞬间开了又关。

## 根因

UrhoX 引擎在移动端**同时发出 Touch 和模拟 Mouse 两套事件**：

```
用户手指点击按钮
  ├── TouchBegin  → UI PointerDown (pointerId=1)
  ├── MouseButtonDown → UI PointerDown (pointerId=0)   ← 引擎模拟
  ├── TouchEnd    → UI PointerUp (pointerId=1) → OnClick → toggle() → ON
  └── MouseButtonUp   → UI PointerUp (pointerId=0) → OnClick → toggle() → OFF  ← 引擎模拟
```

UI 框架对每个 pointerId 独立处理 press/release → click，因此同一次点击触发了**两次 OnClick**。`toggle()` 用 `r.on = not r.on` 翻转布尔值，两次翻转回到原值。

## 为什么桌面端没问题

桌面端只有 Mouse 事件（pointerId=0），不存在重复触发。

## 修复方案

**核心原则：onClick 回调必须是幂等的，不要用 toggle 翻转。**

用闭包捕获 UI 构建时的状态，调用幂等的 `set` 而非 `toggle`：

```lua
-- ❌ 错误：toggle 会被双触发翻转两次
onClick = function(self)
    Radio.toggle(state)
end

-- ✅ 正确：isOn 在面板创建时已捕获，两次调用传入同一个目标值
local isOn = Radio.is_on(state)
onClick = function(self)
    Radio.set_on(state, not isOn)  -- 幂等，第二次调用被跳过
end
```

`set_on` 实现中加入同值跳过：

```lua
function M.set_on(state, on)
    local r = state.flow.radio
    if not r then return end
    if r.on == on then return end   -- 同值跳过，防双触发
    r.on = on
    -- ...
end
```

## 规则

| 场景 | 做法 |
|------|------|
| UI 按钮切换布尔状态 | 用 `set(state, targetValue)` 而非 `toggle()` |
| 按钮触发一次性动作（导航、领取奖励） | 加 guard 标志位防重入，或在回调开头检查前置条件 |
| 需要保留 toggle 接口给非 UI 调用方 | `toggle()` 内部调用 `set_on(not current)`，`set_on` 做幂等保护 |

**自查**：在 UI 的 onClick 回调中搜索 toggle/flip 类调用：

```bash
grep -n "toggle\|= not " scripts/ui/*.lua
```

出现在 onClick 中的 toggle 调用都是潜在的双触发风险点。

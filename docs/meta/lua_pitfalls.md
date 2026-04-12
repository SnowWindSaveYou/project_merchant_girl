# Lua 全局函数名冲突陷阱

## 问题

篝火页面点击后黑屏，无任何报错。日志显示所有代码正常执行、UI.SetRoot 成功，但屏幕一片漆黑。

## 根因

`screen_campfire.lua` 和 `screen_npc.lua` 都定义了**同名的全局函数**：

```lua
-- screen_campfire.lua
function createDialogueView(state) ... end
function createResultView(state)   ... end

-- screen_npc.lua
function createDialogueView(state) ... end
function createResultView(state)   ... end
```

Lua 中不加 `local` 的函数是**全局函数**，存入 `_G` 表。两个模块被 `require` 加载后，后加载的覆盖先加载的同名函数。

结果：篝火页面调用 `createDialogueView(state)` 时，实际执行的是 NPC 页面的版本，该函数访问 NPC 的 `session`（值为 nil），构建出空 UI 树 → 黑屏。

## 为什么没有报错

- `pcall` 捕获不到：函数确实存在（只是来自错误的模块），不会报 nil 调用错误
- NPC 版的 `createDialogueView` 内部有 `if not d or not npc then return UI.Panel {} end` 兜底，返回了空面板
- 空面板是合法的 UI 节点，`UI.SetRoot` 正常完成，不报错
- 深色背景 + 空内容 = 视觉上的"黑屏"

## 修复

将模块内部函数改为 `local` 前向声明：

```lua
-- 在文件顶部、M.create 之前声明
local createDialogueView
local createResultView

function M.create(state, params, r)
    ...
    return createDialogueView(state)
end

-- 在 M.create 之后赋值
createDialogueView = function(state)
    ...
end

createResultView = function(state)
    ...
end
```

## 规则

**模块内部的辅助函数必须声明为 `local`**，只有以下情况允许全局：

| 场景 | 是否用 local |
|------|-------------|
| 模块内部辅助函数 | `local function foo()` 或 `local foo = function()` |
| 模块导出方法 | `function M.foo()` (挂在模块表上，不污染全局) |
| 引擎回调（Start/HandleUpdate 等） | 全局（引擎约定） |

**自查命令**：在 scripts/ 目录下检查可疑的全局函数定义：

```bash
grep -rn "^function [a-z]" scripts/
```

如果输出中同一函数名出现在多个文件中，就存在冲突风险。

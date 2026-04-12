# 变更文档（2026-04-06）

## 范围

本次变更修复篝火黑屏 Bug，将对话 UI 从聊天气泡样式重构为 Gal（视觉小说）模式，统一篝火与 NPC 对话体验，并为全部 NPC 生成少女终末旅行画风立绘。

---

## 一、篝火黑屏 Bug 修复

### 根因

`screen_campfire.lua` 和 `screen_npc.lua` 都定义了全局函数 `createDialogueView` 和 `createResultView`。Lua 全局函数写入 `_G` 表，后加载的模块会静默覆盖先加载的同名函数。当篝火调用 `createDialogueView()` 时，实际执行的是 NPC 模块的版本，该版本访问 NPC 的 `session` 数据（为 nil），返回空 Panel，导致黑屏。

### 修复方式

所有模块内部函数改为 `local` + 前向声明：

```lua
-- 修复前（全局污染）
function createDialogueView(state) ... end

-- 修复后（local 前向声明）
local createDialogueView
createDialogueView = function(state) ... end
```

### 受影响文件

- `scripts/ui/screen_campfire.lua` - 全局函数改 local
- `scripts/ui/screen_npc.lua` - 全局函数改 local

### 自查命令

```bash
grep -rn "^function [a-z]" scripts/
```

如果有输出，说明存在潜在的全局函数污染风险。

### 详细文档

见 `docs/lua_local_function_pitfall.md`

---

## 二、Gal 对话模块（核心新增）

### 新文件：`scripts/ui/gal_dialogue.lua`

通用视觉小说对话 UI 模块，同时服务于篝火对话和 NPC 拜访。

#### 三个公共 API

| API | 用途 | 视图 |
|-----|------|------|
| `Gal.createDialogueView(opts)` | 对话推进 | 立绘 + 底部半透明对话框 |
| `Gal.createHistoryView(opts)` | 历史记录 | 气泡式 ScrollView |
| `Gal.createResultView(opts)` | 结果展示 | 立绘 + 底部结果卡片 |

#### 参数规范

```lua
-- createDialogueView
{
    dialogue  = table,      -- 对话数据 { title, steps, choices }
    step      = number,     -- 当前步数 (1-based)
    npc       = table|nil,  -- NPC 元数据（篝火传 nil）
    topInfo   = string|nil, -- 顶栏附加信息
    onAdvance = function,   -- 推进回调
    onChoice  = function(i),-- 选择回调
    onHistory = function,   -- LOG 按钮回调
    onClose   = function,   -- 关闭回调
}

-- createHistoryView
{
    dialogue = table,
    step     = number,
    npc      = table|nil,
    onBack   = function,    -- 返回对话回调
}

-- createResultView
{
    dialogue  = table,
    result    = table,      -- { result_text, memory, ops_log }
    npc       = table|nil,
    extraInfo = table|nil,  -- { { text, color }, ... }
    onClose   = function,
}
```

#### 立绘选择逻辑

模块内部根据 `speaker` 和 `npc` 自动选择立绘：

1. `speaker == "linli"` 或 `"taoxia"` → 主角立绘（内置）
2. `speaker == "npc"` → 按优先级查找：
   - NPC 独立立绘（`NPC_PORTRAITS[npc.id]`）
   - 势力通用立绘（`FACTION_PORTRAITS[faction_id]`）
   - 降级到农耕派通用

#### 布局结构（视觉小说分层）

```
┌──────────────────────────────────┐
│ 顶栏 (半透明, z前景)              │
│  标题 + 消耗信息    [LOG] [X]    │
├──────────────────────────────────┤
│                                  │
│  ┌────┐              ┌────┐     │  ← 立绘层 (position:absolute)
│  │ 左 │              │ 右 │     │     bottom:0, 高度75%
│  │ 立 │              │ 立 │     │     说话方亮色，非说话方暗色
│  │ 绘 │              │ 绘 │     │
│ ┌┤    ├──────────────┤    ├┐    │
│ │└────┘              └────┘│    │  ← 对话框 (半透明, alpha=200)
│ │ [名字标签]                │    │     叠在立绘前面
│ │ 对话文字...               │    │
│ │ [推进/选择按钮]           │    │
│ └──────────────────────────┘    │
└──────────────────────────────────┘
```

关键点：
- 立绘层 `position = "absolute", bottom = 0` 作为全屏底层
- 顶栏 + 空白 Panel + 对话框为正常流布局，在前景层
- 对话框 `backgroundColor alpha = 200`，半透明可见立绘

---

## 三、页面重构

### `scripts/ui/screen_campfire.lua`（完全重写）

- 从 ~300 行重构为 ~100 行
- 仅保留 session 管理和业务回调逻辑
- UI 渲染全部委托给 `gal_dialogue.lua`
- 篝火模式：左林砾 右陶夏，`npc = nil`

### `scripts/ui/screen_npc.lua`（完全重写）

- 从 ~300 行重构为 ~120 行
- 同样委托给 `gal_dialogue.lua`
- NPC 模式：左主角 右NPC，`npc = session.npc`
- 结果页显示好感度信息

### 两页面对比

| 差异点 | screen_campfire | screen_npc |
|--------|----------------|------------|
| npc 参数 | `nil` | `session.npc` |
| 左立绘 | 林砾（固定） | 当前说话主角 |
| 右立绘 | 陶夏（固定） | NPC（自动选择立绘） |
| 顶栏信息 | 消耗物品 | 无 |
| 结果页额外信息 | 关系阶段 | NPC 好感度 |

---

## 四、立绘资源

### 生成参数

- 画风：少女终末旅行（简笔画、柔和线条）
- 尺寸：687x1024（2:3 比例）
- 透明背景

### 独立立绘（6张）

| NPC ID | 角色 | 身份 | 文件 |
|--------|------|------|------|
| shen_he | 沈禾 | 农耕派领袖 | `image/portrait_shen_he_20260406000120.png` |
| han_ce | 韩策 | 技术派领袖 | `image/portrait_han_ce_20260406000106.png` |
| wu_shiqi | 伍拾七 | 拾荒帮头目 | `image/portrait_wu_shiqi_20260406000058.png` |
| bai_shu | 白述 | 宗教团领袖 | `image/portrait_bai_shu_20260406000056.png` |
| meng_hui | 孟回 | 流浪医生 | `image/portrait_meng_hui_20260406000106.png` |
| ming_sha | 鸣砂 | 独行商人 | `image/portrait_ming_sha_20260406000227.png` |

### 势力通用立绘（4张）

| 势力 | 文件 |
|------|------|
| 农耕派 (farm) | `image/portrait_faction_farm_20260406000212.png` |
| 技术派 (tech) | `image/portrait_faction_tech_20260406000259.png` |
| 拾荒帮 (scav) | `image/portrait_faction_scav_20260406000214.png` |
| 宗教团 (scholar) | `image/portrait_faction_scholar_20260406000214.png` |

### 主角立绘（2张，上次 session 生成）

| 角色 | 文件 |
|------|------|
| 林砾 | `image/linli_portrait_20260405231808.png` |
| 陶夏 | `image/taoxia_portrait_20260405231808.png` |

### 新增 NPC 时如何添加立绘

1. 生成立绘图片，放入 `assets/image/`
2. 在 `gal_dialogue.lua` 的 `NPC_PORTRAITS` 表中添加映射：
   ```lua
   NPC_PORTRAITS = {
       new_npc_id = "image/portrait_new_npc_xxx.png",
   }
   ```
3. 如果是通用势力成员，无需额外操作，自动匹配 `FACTION_PORTRAITS`

---

## 五、其他清理

### 已删除

- `scripts/ui/screen_campfire.lua.bak`

### 已清理 debug 日志

- `scripts/ui/router.lua` - 移除 `[Router] navigate` 和 `[Router] SetRoot done` 打印
- `scripts/ui/screen_home.lua` - 篝火 onClick 移除 pcall 包装和调试打印

---

## 六、已知遗留

### 全局函数污染风险（低优先级）

以下文件仍有全局函数声明，目前无冲突，但建议后续改为 local：

```
screen_home.lua:     createSettlementView, createTravelView, createCargoSummary, ...
screen_truck.lua:    createVehicleCard, createCharacterSection, ...
screen_summary.lua:  createResultRow
screen_route_plan.lua: createStrategyBtn, createPathVisualization, ...
screen_quest_log.lua:  createQuestCard
screen_prepare.lua:  createDestGroup, createAvailableOrderCard
```

自查：`grep -rn "^function [a-z]" scripts/`

### 待验证

- Gal 布局在不同分辨率下的立绘显示效果
- ScrollView 历史气泡是否正常显示文字
- 半透明对话框与立绘的视觉叠加效果

---

## 七、架构决策记录

### 为什么提取通用 Gal 模块而不是各写各的？

1. 篝火和 NPC 对话的 UI 完全一致（用户明确要求"不搞特殊化"）
2. 立绘选择逻辑（独立/势力通用/降级）是全局的，不应在每个页面重复
3. 未来可能有更多对话场景（任务对话、回忆重放等），统一模块方便扩展

### 为什么立绘用 absolute 底层 + 前景层叠加？

经典视觉小说布局要求立绘在对话框"后面"（视觉上被对话框遮挡）。Yoga Flexbox 无 z-index，但 absolute 元素渲染在 normal flow 之前，所以：
- 立绘层 `position = "absolute"` → 先渲染（底层）
- 对话框正常流 → 后渲染（前景）
- 对话框半透明 → 立绘从对话框区域透出

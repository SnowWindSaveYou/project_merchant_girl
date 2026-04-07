# 对话系统 (Gal Dialogue System)

## 概览

视觉小说风格的对话系统，用于篝火对话和 NPC 拜访场景。采用立绘 + 底部对话框的经典 Gal Game 布局。

```
scripts/
├── ui/
│   ├── gal_dialogue.lua        # 核心 UI 模块（3 个公共视图）
│   ├── screen_campfire.lua     # 篝火对话页面（林砾 + 陶夏）
│   └── screen_npc.lua          # NPC 对话页面（主角 + NPC）
├── narrative/
│   ├── campfire.lua            # 篝火对话逻辑（关系值、选项结算）
│   ├── dialogue_pool.lua       # 篝火对话池（从 JSON 加载，按阶段筛选）
│   ├── npc_manager.lua         # NPC 对话逻辑（好感度、选项结算）
│   └── npc_dialogue_pool.lua   # NPC 对话池
└── configs/
    └── campfire_dialogues.json # 篝火对话数据
```

---

## 数据结构

### dialogue（对话数据）

```lua
{
    id    = "campfire_song_01",        -- 唯一 ID
    title = "收音机里的歌",             -- 对话标题（显示在顶栏）
    stage = "early",                   -- 关系阶段: "early"|"mid"|"late"

    steps = {                          -- 对话步骤（按顺序展示）
        { speaker = "taoxia", text = "你听，这首歌好好听..." },
        { speaker = "linli",  text = "嗯，是老歌了。" },
        { speaker = "taoxia", text = "以前妈妈也常哼这首。" },
    },

    choices = {                        -- 所有步骤展示完后出现的选项
        {
            text        = "陪她一起听",     -- 选项按钮文字
            result_text = "你们安静地听完了整首歌。",  -- 结果描述
            ops         = { ... },          -- 结算操作（加关系值等）
            memory      = {                 -- 可选：获得回忆碎片
                id    = "song_memory",
                title = "收音机的旋律",
                desc  = "那个夜晚的歌声...",
            },
        },
        {
            text        = "关掉收音机",
            result_text = "陶夏有些失落地沉默了。",
            ops         = { ... },
        },
    },
}
```

### speaker（说话人标识）

| 值 | 含义 | 立绘位置 |
|---|---|---|
| `"linli"` | 林砾（主角） | 篝火模式：左侧；NPC 模式：左侧 |
| `"taoxia"` | 陶夏（主角） | 篝火模式：右侧；NPC 模式：左侧 |
| `"npc"` | 当前 NPC | 右侧 |

当前说话人的立绘全亮，另一方立绘变暗（`imageTint` 压暗）。

---

## 核心模块: gal_dialogue.lua

### 引入

```lua
local Gal = require("ui/gal_dialogue")
```

### API 1: createDialogueView(opts)

主对话视图。全屏布局：立绘层（absolute）+ 前景层（顶栏 + 空白 + 对话框）。

**点击对话框推进对话**，所有步骤展示完后显示选项按钮。

```lua
Gal.createDialogueView({
    dialogue  = dialogue,           -- table: 对话数据
    step      = 1,                  -- number: 当前步数 (1-based)
    npc       = npc_metadata,       -- table|nil: NPC 元数据（NPC 对话时传入）
    topInfo   = "-1 干粮",          -- string|nil: 顶栏附加信息
    onAdvance = function() end,     -- function: 点击对话框推进回调
    onChoice  = function(i) end,    -- function(i): 选择第 i 个选项
    onHistory = function() end,     -- function: 点击 LOG 按钮
    onClose   = function() end,     -- function: 点击关闭
})
```

**布局结构**:
```
┌─────────────────────────────┐
│ [标题] [消耗信息]   [LOG] [X] │  ← 顶栏 44px
│                             │
│    ┌───┐         ┌───┐      │  ← 立绘层 (absolute, 全屏)
│    │左 │         │右 │      │     面板 95%x95%, contain 适配
│    │立 │         │立 │      │     左偏移 -22%, 右偏移 -22%
│    │绘 │         │绘 │      │
│    └───┘         └───┘      │
├─────────────────────────────┤  ← 空白占 55% 后开始对话框
│ [说话人名字]                  │
│ 对话文字...                   │  ← 点击此区域推进对话
│                             │
│ [选项A]  [选项B]  (读完才出现) │
└─────────────────────────────┘
```

### API 2: createHistoryView(opts)

气泡式对话历史（LOG 视图），在 ScrollView 中展示已读对话。

```lua
Gal.createHistoryView({
    dialogue = dialogue,           -- table: 对话数据
    step     = current_step,       -- number: 已展示步数
    npc      = npc_metadata,       -- table|nil
    onBack   = function() end,     -- function: 返回对话
})
```

### API 3: createResultView(opts)

结果展示视图。显示选择的结果文字、回忆碎片、操作日志等。

```lua
Gal.createResultView({
    dialogue  = dialogue,          -- table: 对话数据
    result    = {                  -- table: 结算结果
        result_text = "...",       --   结果描述
        memory      = { ... },    --   回忆碎片 (可选)
        ops_log     = { "+5 关系" },  -- 操作摘要
    },
    npc       = npc_metadata,      -- table|nil
    extraInfo = {                  -- table|nil: 额外信息行
        { text = "好感: 45 (熟识)", color = { 218, 168, 102, 255 } },
    },
    onClose   = function() end,    -- function: 关闭回调
})
```

---

## 页面层: screen_campfire / screen_npc

页面层管理对话会话状态（当前步数、历史切换、结果展示），调用 `gal_dialogue` 的三个 API 渲染 UI。

### session 状态

```lua
local session = {
    npc_id      = nil,       -- NPC ID (仅 screen_npc)
    npc         = nil,       -- NPC 元数据 (仅 screen_npc)
    dialogue    = nil,       -- 当前对话数据
    step        = 0,         -- 当前步数
    result      = nil,       -- 结算结果
    showHistory = false,     -- 是否显示 LOG
}
```

### 导航参数

通过 `router.navigate` 传递参数切换状态：

| 参数 | 用途 |
|---|---|
| `{ dialogue = d }` | 开始新对话 |
| `{ _continue = true }` | 推进对话（保持状态） |
| `{ _toggle_history = true }` | 切换 LOG 显示 |
| `{ show_result = true, result_data = r }` | 显示结算结果 |

### 典型流程

```
1. 外部触发 → navigate("npc", { dialogue = d, npc_id = "shen_he" })
2. 用户点击对话框 → onAdvance → step++ → navigate("npc", { _continue = true })
3. 重复步骤 2 直到所有 steps 展示完
4. 用户点选项 → onChoice(i) → apply_choice → navigate("npc", { show_result = true, ... })
5. 用户点"回到据点" → onClose → navigate("home")
```

---

## 立绘配置

配置文件: [`docs/configs/portraits.json`](configs/portraits.json)

所有立绘资源映射集中在一个 JSON 配置中，分三层：

```jsonc
{
    // 主角立绘（固定两位）
    "protagonists": {
        "linli": {
            "name": "林砾",
            "color": [142, 178, 210, 255],      // 名字颜色 RGBA
            "bgColor": [42, 52, 58, 240],       // 名字背景色 RGBA
            "portrait": "image/linli_portrait_20260405231808.png"
        },
        "taoxia": { ... }
    },

    // NPC 独立立绘（势力领袖等重要角色，按 npc.id 匹配）
    "npc_portraits": {
        "shen_he": "image/portrait_shen_he_20260406000120.png",
        ...
    },

    // 势力通用立绘（非领袖 NPC 兜底，按 faction_id 匹配）
    "faction_portraits": {
        "farm":    "image/portrait_faction_farm_20260406000212.png",
        "tech":    "image/portrait_faction_tech_20260406000259.png",
        "scav":    "image/portrait_faction_scav_20260406000214.png",
        "scholar": "image/portrait_faction_scholar_20260406000214.png"
    }
}
```

### 立绘匹配优先级

给定一个 NPC，按以下顺序查找立绘：

```
npc_portraits[npc.id]          ← 1. 有独立立绘？用它
    ↓ 没有
faction_portraits[faction_id]  ← 2. 所属势力有通用立绘？用它
    ↓ 没有
faction_portraits["farm"]      ← 3. 兜底：农耕派立绘
```

### 显示规则

| 模式 | 左侧 | 右侧 |
|---|---|---|
| 篝火 (`npc = nil`) | 林砾 | 陶夏 |
| NPC (`npc` 有值) | 当前主角 | NPC |

当前说话人全亮，另一方 `imageTint = { 80, 80, 80, 160 }` 压暗。

---

## 扩展指南

### 添加新 NPC 立绘

1. 把立绘图片放入 `assets/image/`
2. 在 `docs/configs/portraits.json` 的 `npc_portraits` 中添加：

```json
{
    "npc_portraits": {
        "new_npc_id": "image/portrait_new_npc.png"
    }
}
```

3. 同步更新 `gal_dialogue.lua` 中的 `NPC_PORTRAITS` 表

### 添加新势力通用立绘

1. 在 `docs/configs/portraits.json` 的 `faction_portraits` 中添加：

```json
{
    "faction_portraits": {
        "new_faction": "image/portrait_faction_new.png"
    }
}
```

2. 同步更新 `gal_dialogue.lua` 中的 `FACTION_PORTRAITS` 表

### 添加新对话

在 `scripts/configs/campfire_dialogues.json` 中添加新条目，格式参照上方数据结构。

### 更换主角立绘

修改 `docs/configs/portraits.json` 的 `protagonists` 中对应角色的 `portrait` 字段，同步更新 `gal_dialogue.lua`。

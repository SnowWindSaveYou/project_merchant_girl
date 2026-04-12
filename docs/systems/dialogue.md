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

## 数据来源

对话数据分布在两个 JSON 文件中，由 `dialogue_pool.lua` 统一加载：

| 文件 | 内容 | 备注 |
|------|------|------|
| `assets/configs/campfire_dialogues.json` | 日常篝火对话 | 关系养成、闲聊、随机话题 |
| `assets/configs/story_dialogues.json` | 主线 / 教程 / 到达剧情 | 加载时自动标记 `is_story = true` |

两个文件格式相同，合并到同一个对话池中筛选。

---

## 数据结构

### dialogue（对话数据）

完整字段说明：

```jsonc
{
    // ── 必填 ──
    "id": "SD_TUTORIAL_TOWER_ARRIVAL",  // 唯一 ID
    "title": "北穹塔台",                 // 对话标题（顶栏显示）
    "steps": [                           // 对话步骤（按顺序展示）
        { "speaker": "narrator", "text": "描述文字..." },
        { "speaker": "taoxia",  "text": "台词", "expression": "happy" },
        { "speaker": "linli",   "text": "台词", "expression": "thinking" }
    ],
    "choices": [                         // 所有步骤展示完后出现的选项
        {
            "text": "选项按钮文字",
            "result_text": "选择后的结果描述",
            "ops": ["add_relation_linli:2", "add_goodwill:tower:3"],
            "set_flags": ["tutorial_arrived_tower"],
            "memory": {                   // 可选：获得回忆碎片
                "id": "mem_tower_first",
                "title": "北穹塔台",
                "desc": "第一次到达塔台的记忆"
            }
        }
    ],

    // ── 筛选条件（篝火对话池使用）──
    "node_types": ["settlement"],        // 可触发的节点类型；["any"] = 不限
    "relation_stage": "early",           // 关系阶段: "early"|"mid"|"late"|"any"
    "required_flags": ["flag_a"],        // 必须已设置的 flag（全部满足）
    "forbidden_flags": ["flag_b"],       // 不能已设置的 flag（任一命中则排除）
    "min_trips": 3,                      // 最少完成行程数

    // ── 权重与冷却 ──
    "weight": 10,                        // 抽取权重（越高越优先）
    "cooldown": 5,                       // 抽中后冷却回合数

    // ── 分类标记 ──
    "type": "tutorial",                  // 对话类型标签（自由字符串）
    "chapter": 0,                        // 章节号
    "is_story": true,                    // 主线对话（story_dialogues.json 自动标记）
    "arrival_only": true,                // 🆕 到达拦截专用：不进入篝火对话池（见下方说明）

    // ── 演出控制 ──
    "audioScene": "settlement",          // 音频场景: campfire|settlement|travel|silent
    "background": "image/bg_tower.png"   // 自定义背景图（不设则用当前聚落 bg）
}
```

> **注意**：所有筛选条件字段都是可选的，不设则不做对应检查。

### speaker（说话人标识）

| 值 | 含义 | 立绘位置 |
|---|---|---|
| `"linli"` | 林砾（主角） | 篝火模式：左侧；NPC 模式：左侧 |
| `"taoxia"` | 陶夏（主角） | 篝火模式：右侧；NPC 模式：左侧 |
| `"npc"` | 当前 NPC | 右侧 |

当前说话人的立绘全亮，另一方立绘变暗（`imageTint` 压暗）。

---

## 到达拦截机制

### 问题背景

某些对话需要在「到达聚落的瞬间」触发（例如教程首次到达温室社区），而不是作为篝火闲聊出现。直接放进对话池会导致：

- 在中途经停站的篝火里提前出现（`node_types: ["any"]` + flag 已满足）
- 到达结算（订单交付、行程结束）先于叙事对话执行，时序错乱

### 架构设计

```
玩家到达节点
    ↓
checkArrivalIntercepts(state, node_id)     ← 遍历所有注册的拦截器
    ↓ 命中？
    ├── YES → 跳转篝火播放对话 → 延迟到达处理 → 对话结束后恢复
    └── NO  → 正常执行 Flow.handle_node_arrival()（交付/结算）
```

### 关键机制

**1. 拦截器注册**（`main.lua`）

```lua
-- 注册一个拦截器：接受 (state, node_id)，返回 action 或 nil
registerArrivalInterceptor(function(state, node_id)
    return Tutorial.on_arrival(state, node_id)
end)
```

拦截器按注册顺序依次检查，第一个返回非 nil 的结果即命中。

返回值格式：
```lua
{ type = "dialogue", dialogue = <dialogue_data> }
```

**2. 延迟到达处理**

命中拦截时，`handleNodeArrival` 会：
1. 更新 `current_location` 到目标节点（确保背景图正确）
2. 将原始 `arrivalInfo` 存入 `_deferred_arrival`
3. 跳转篝火页面播放对话

对话结束后，玩家回到常规页面（home 等），主循环检测到 `_deferred_arrival` 存在，恢复正常的到达处理流程（订单交付、行程结算）。

**3. `arrival_only` 字段**

标记了 `"arrival_only": true` 的对话会被 `DialoguePool.filter` 排除，**不会出现在篝火对话池中**。它们只能通过到达拦截器触发。

这解决了"到达对话在中途篝火提前出现"的问题。

### 筛选链完整顺序

`DialoguePool.filter` 依次检查以下条件（全部通过才入池）：

```
cooldown → node_type → relation_stage → required_flags → forbidden_flags → arrival_only → min_trips
```

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

### 添加新的日常对话

在 `assets/configs/campfire_dialogues.json` 中添加新条目，格式参照上方「数据结构」。

主线/教程对话则添加到 `assets/configs/story_dialogues.json`（加载时自动标记 `is_story = true`）。

### 添加到达触发对话

当需要在玩家到达某个节点时自动触发一段剧情（而非出现在篝火对话池中），按以下步骤操作：

**第 1 步：在 JSON 中定义对话**

在 `assets/configs/story_dialogues.json` 中添加对话，设置两个关键字段：

```jsonc
{
    "id": "SD_MY_ARRIVAL_DIALOGUE",
    "title": "到达某地",
    "arrival_only": true,           // ← 不进入篝火对话池
    "required_flags": ["my_precondition_flag"],
    "steps": [ ... ],
    "choices": [ ... ]
}
```

**第 2 步：编写拦截器函数**

在你的模块中编写一个 handler，签名为 `function(state, node_id) -> action|nil`：

```lua
-- my_module.lua
function MyModule.on_arrival(state, node_id)
    -- 检查条件：是否是目标节点、flag 是否满足等
    if node_id ~= "target_node" then return nil end
    if state.flags.already_triggered then return nil end

    -- 查找对话数据
    local dialogue = DialoguePool.find_by_id("SD_MY_ARRIVAL_DIALOGUE")
    if not dialogue then return nil end

    -- 返回拦截指令
    return { type = "dialogue", dialogue = dialogue }
end
```

**第 3 步：在 main.lua 中注册**

```lua
registerArrivalInterceptor(function(state, node_id)
    return MyModule.on_arrival(state, node_id)
end)
```

注册后，玩家每次到达节点时会自动检查。命中则先播放对话，对话结束后再执行订单交付和行程结算。

### 更换主角立绘

修改 `docs/configs/portraits.json` 的 `protagonists` 中对应角色的 `portrait` 字段，同步更新 `gal_dialogue.lua`。

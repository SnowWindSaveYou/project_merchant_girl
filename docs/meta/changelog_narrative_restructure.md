# 叙事架构重构变更文档（2026-04-13）

## 范围

将叙事系统从"教程驱动 + 篝火被动混池"重构为"故事主动驱动 + 三系统独立"。核心变更：新建 StoryDirector 模块主动弹出主线对话，教程缩减为温室阶段即结束，篝火仅管日常闲聊，配置文件按系统边界拆分。

---

## 一、问题背景

旧架构存在以下问题：

| 问题 | 根因 |
|------|------|
| 玩家跟着教程一路到塔台后无事可做 | 教程驱动叙事，教程结束 = 叙事结束 |
| 主线对话不会自动弹出，需手动点篝火 | 主线混在篝火被动抽取池中，没有主动触发机制 |
| 主线在随机事件中的部分容易被忽略 | `EventScheduler.queue_story_event()` API 已存在但从未被调用 |
| 玩家感受不到有故事在推进 | 无集中叙事调度，主线/教程/日常混在一起 |
| 配置文件混合多个系统的数据 | `story_dialogues.json` 同时包含 `main_story` 和 `tutorial` 类型 |

**设计原则**：教程应服务于故事，故事应主动推送，篝火只管日常，配置应反映系统边界。

---

## 二、架构变更

### 变更前

```
玩家操作 → Tutorial 驱动全程
              ↓ 接单 → 出发 → 温室 → 篝火 → 探索 → 塔台
                                          ↑
                        Campfire 被动抽取主线/日常混杂对话
                                          ↑
                        DialoguePool 从 2 个 JSON 加载，主线/教程混在同一文件
```

- Tutorial 驱动从出生点到塔台的完整流程
- 主线对话被动混入篝火池，靠权重随机抽取
- `story_events.json` 中的事件混入随机池，从未被强制推送
- `story_dialogues.json` 同时包含 `main_story` + `tutorial` 类型

### 变更后

```
Tutorial (温室即止)              StoryDirector (全程驱动)           Campfire (独立日常)
SPAWN → TRAVEL → AT_GREENHOUSE   ← prologue_done →                仅处理 daily/cooperation/
    ↓ COMPLETE                    主线对话自动弹出                    memory/philosophy 类型
教程系统退出                     故事事件强制推送                    跳过 main_story 和 tutorial
                                 到达/空闲均检查触发
       ↓                              ↓                              ↓
  tutorial_dialogues.json      story_dialogues.json          campfire_dialogues.json
  type: tutorial               type: main_story              type: daily/coop/mem/phil
  is_tutorial = true           is_story = true               无额外标记
```

三个系统各管各的配置、各管各的触发逻辑、互不依赖。

---

## 三、新增模块：StoryDirector

**文件**：`scripts/narrative/story_director.lua`（165 行）

叙事调度核心。不依赖 Campfire，直接从 DialoguePool 查找 `main_story` 对话并自动触发。

### 公共 API

| 方法 | 调用时机 | 返回值 |
|------|---------|--------|
| `on_node_arrival(state)` | 玩家到达节点后 | `{ type="story_dialogue", dialogue }` 或 `nil` |
| `on_trip_finish(state)` | 行程结束时 | `nil`（仅推送故事事件） |
| `check_home_auto_trigger(state)` | 主页每帧检查 | `{ type="story_dialogue", dialogue }` 或 `nil` |

### 核心逻辑

```lua
-- 查找待触发的 main_story 对话
function M.check_pending_story_dialogue(state)
    local pool = DialoguePool.filter(state, node.type)
    for _, d in ipairs(pool) do
        if d.is_story and d.type == "main_story" then
            return d
        end
    end
    return nil
end

-- 推送故事事件（激活了从未使用的 queue_story_event API）
function M.check_and_queue_story_events(state)
    for _, evt in ipairs(story_events_) do
        -- 条件首次满足 → 强制入队，记录到 _director_queued 防重
    end
end
```

### 设计要点

- 主线对话**不走篝火**，不消耗篝火资源/次数
- 查找逻辑用 `DialoguePool.filter()` + `d.type == "main_story"`，与 Campfire 完全解耦
- 故事事件通过 `EventScheduler.queue_story_event()` 强制推送，不再依赖随机池
- `_director_queued` 集合防止同一事件重复推送

### main.lua 集成

```lua
-- 1. 到达处理（handleNodeArrival 内，is_final=true 时）
local directorAction = StoryDirector.on_node_arrival(gameState)
if directorAction and directorAction.type == "story_dialogue" then
    Router.navigate("campfire", { dialogue = directorAction.dialogue, ... })
end

-- 2. 行程结束（handleTripFinish 内）
StoryDirector.on_trip_finish(gameState)

-- 3. 主页自动触发（HandleUpdate 内，非行驶状态 + 主页时）
local action = StoryDirector.check_home_auto_trigger(gameState)
if action and action.type == "story_dialogue" then
    Router.navigate("campfire", { dialogue = action.dialogue, ... })
end
```

---

## 四、重构模块：Tutorial

**文件**：`scripts/narrative/tutorial.lua`（653 行）

### 阶段精简

```
变更前：NONE → SPAWN → TRAVEL_TO_GREENHOUSE → AT_GREENHOUSE → GREENHOUSE_FREE → EXPLORE → TRAVEL_TO_TOWER → ...
变更后：NONE → SPAWN → TRAVEL_TO_GREENHOUSE → AT_GREENHOUSE → COMPLETE
```

| 阶段 | 含义 | 结束条件 |
|------|------|---------|
| `SPAWN` | 在出生点，引导接单去温室 | 接到温室订单 |
| `TRAVEL_TO_GREENHOUSE` | 前往温室途中 | 到达温室 |
| `AT_GREENHOUSE` | 在温室，引导使用交易所 | 使用交易所（`tutorial_shop_intro`） |
| `COMPLETE` | 教程完成 | — |

### 删除的功能

| 删除项 | 原因 |
|--------|------|
| `GREENHOUSE_FREE` 阶段 | 合并到 `AT_GREENHOUSE` |
| `EXPLORE` 阶段 | 探索引导改由 StoryDirector 通过主线对话推送 |
| `make_order_to_tower()` | 塔台订单不再由教程生成 |
| 塔台到达拦截 | 由 StoryDirector 处理 |
| `tutorial_campfire_done` flag | 不再需要篝火作为教程步骤 |
| Campfire 模块导入 | 教程不再依赖篝火 |

### 保留的功能

- 出生点气泡引导接单
- 温室到达拦截 + 交易所引导气泡
- 功能气泡教程（交易所、货车、电台、自动规划）
- 路线探索引导 (`get_route_explore_intro_steps`)
- 探索玩法引导 (`get_explore_intro_steps`)
- 升级对话

### COMPLETE 判定

```lua
-- 两个条件同时满足 = 教程完成
Flags.has(state, "tutorial_arrived_greenhouse")  -- 温室到达
    and Flags.has(state, "tutorial_shop_intro")   -- 交易所使用
```

---

## 五、修改模块：Campfire

**文件**：`scripts/narrative/campfire.lua`

### 变更点

篝火系统彻底脱离主线和教程对话，仅处理日常类话题。

**`has_story_topic()`**：

```lua
-- 变更前：只排除 main_story
if d.is_story and d.type ~= "main_story" then

-- 变更后：排除 main_story 和 tutorial
if d.is_story and d.type ~= "main_story" and d.type ~= "tutorial" then
```

**`start()` 对话抽取**：

```lua
-- 变更前：只跳过 main_story
if d.type ~= "main_story" then

-- 变更后：跳过 main_story 和 tutorial
if d.type ~= "main_story" and d.type ~= "tutorial" then
```

### 未变更

- `start_with_dialogue()` 仍支持外部强制指定对话 ID
- `can_start()` 资源检查逻辑不变
- `apply_choice()` / `apply_skip()` 结算逻辑不变

---

## 六、修改模块：DialoguePool

**文件**：`scripts/narrative/dialogue_pool.lua`

### 配置路径变更

```lua
-- 变更前（2 个配置）
local CONFIG_PATH       = "configs/campfire_dialogues.json"
local STORY_CONFIG_PATH = "configs/story_dialogues.json"

-- 变更后（3 个配置）
local CONFIG_PATH          = "configs/campfire_dialogues.json"
local STORY_CONFIG_PATH    = "configs/story_dialogues.json"
local TUTORIAL_CONFIG_PATH = "configs/tutorial_dialogues.json"
```

### 加载逻辑

三个配置文件合并到同一个池（`M._dialogues` + `M._by_id`），通过标记区分：

| 来源 | 标记 | 用途 |
|------|------|------|
| `campfire_dialogues.json` | 无额外标记 | 日常对话 |
| `story_dialogues.json` | `is_story = true` | StoryDirector 识别主线 |
| `tutorial_dialogues.json` | `is_tutorial = true` | Tutorial 识别教程 |

```lua
-- story config: raw.is_story = true
-- tutorial config: raw.is_tutorial = true
-- campfire config: 无额外标记
```

### filter() 不变

筛选逻辑（cooldown → node_type → relation_stage → required_flags → forbidden_flags → arrival_only → min_trips）未修改。下游模块（Campfire、StoryDirector）在 `filter()` 返回结果上自行按 `type`/`is_story`/`is_tutorial` 做二次过滤。

### `get()` 兼容

`DialoguePool.get("SD_TUTORIAL_GREENHOUSE_ARRIVAL")` 等精确查找仍可跨配置工作，因为所有对话都合并到 `_by_id` 表中。

---

## 七、配置文件拆分

### 变更前

```
story_dialogues.json (10 条)
├── main_story × 6:  SD_PROLOGUE_01/02, SD_CH1_01-04
├── main_story × 2:  SD_TUTORIAL_EXPLORE_HINT, SD_TUTORIAL_TOWER_ARRIVAL
└── tutorial × 2:    SD_TUTORIAL_FIRST_DEPARTURE, SD_TUTORIAL_GREENHOUSE_ARRIVAL

campfire_dialogues.json (14 条)
└── daily/cooperation/memory/philosophy × 14
```

### 变更后

```
story_dialogues.json (8 条) — StoryDirector 驱动
└── main_story × 8:  SD_PROLOGUE_01/02, SD_CH1_01-04,
                      SD_TUTORIAL_EXPLORE_HINT (ch1), SD_TUTORIAL_TOWER_ARRIVAL (ch2)

tutorial_dialogues.json (2 条) — Tutorial 驱动
└── tutorial × 2:    SD_TUTORIAL_FIRST_DEPARTURE, SD_TUTORIAL_GREENHOUSE_ARRIVAL

campfire_dialogues.json (14 条) — Campfire 驱动
└── daily/cooperation/memory/philosophy × 14
```

### 具体对话迁移

| 对话 ID | 旧位置 | 新位置 | 类型变更 |
|---------|--------|--------|---------|
| SD_TUTORIAL_FIRST_DEPARTURE | story_dialogues.json | **tutorial_dialogues.json** | `type: tutorial` 不变，移除 `is_story` |
| SD_TUTORIAL_GREENHOUSE_ARRIVAL | story_dialogues.json | **tutorial_dialogues.json** | `type: tutorial` 不变，移除 `is_story` |
| SD_TUTORIAL_EXPLORE_HINT | story_dialogues.json | story_dialogues.json | `type: tutorial` → `main_story`，`chapter: 0` → `1`，`required_flags` 改为 `ruins_market_intro` |
| SD_TUTORIAL_TOWER_ARRIVAL | story_dialogues.json | story_dialogues.json | `type: tutorial` → `main_story`，`chapter: 0` → `2`，`required_flags` 改为 `ch2_started` |
| SD_PROLOGUE_02 choices | story_dialogues.json | story_dialogues.json | 移除 `tutorial_campfire_done` flag |

### is_story / is_tutorial 标记规则

| 配置文件 | JSON 中 is_story | 加载器设置 |
|----------|-----------------|-----------|
| story_dialogues.json | **不在 JSON 中** | `raw.is_story = true` |
| tutorial_dialogues.json | **不在 JSON 中** | `raw.is_tutorial = true` |
| campfire_dialogues.json | 不在 | 无 |

JSON 数据中不再包含 `is_story` 字段，统一由加载器按来源设置，避免冗余和不一致。

---

## 八、页面层变更

### screen_home.lua

| 位置 | 变更前 | 变更后 |
|------|--------|--------|
| ~158 行 教程订单重生成检查 | `GREENHOUSE_FREE` / `EXPLORE` | 仅检查 `Phase.SPAWN` |
| ~227 行 出发战利提示 | `TRAVEL_TO_GREENHOUSE or EXPLORE` | `TRAVEL_TO_GREENHOUSE` |
| ~412 行 温室结算视图 | `GREENHOUSE_FREE` | `AT_GREENHOUSE` |

### screen_prepare.lua

| 位置 | 变更前 | 变更后 |
|------|--------|--------|
| ~261 行 教程入口对话 | `GREENHOUSE_FREE or EXPLORE` | `AT_GREENHOUSE` |

### screen_debug.lua

教程 flag 列表更新：

```
移除: tutorial_campfire_done, tutorial_explore_home_shown, tutorial_map_explore_shown
新增: tutorial_first_departure_done, tutorial_route_explore
```

### screen_map.lua

无需修改。仅引用 `Phase.SPAWN` 和 `Phase.TRAVEL_TO_GREENHOUSE`（均保留）。`get_bubble_config(state, "map")` 现返回 `nil`（EXPLORE 气泡已移除），框架已兜底处理。

---

## 九、Flag 链参考

### 教程链（tutorial_dialogues.json → tutorial.lua）

```
SD_PROLOGUE_01 (story)  ──set──→  tutorial_started
    ↓ required
SD_TUTORIAL_FIRST_DEPARTURE (tutorial)  ──set──→  tutorial_first_departure_done
    ↓ required (同 flag: tutorial_started)
SD_TUTORIAL_GREENHOUSE_ARRIVAL (tutorial)  ──set──→  tutorial_arrived_greenhouse
                                                    ──set──→  npc_shen_he_intro
    ↓ 代码设置
tutorial_shop_intro  ──→  Phase.COMPLETE
```

### 主线链（story_dialogues.json → StoryDirector）

```
SD_PROLOGUE_01  ──set──→  sd_prologue_01_done, tutorial_started, chose_safe_return / chose_go_forward
    ↓ required
SD_PROLOGUE_02  ──set──→  sd_prologue_02_done, prologue_done, motivation_duty / motivation_curiosity
    ↓ required
SD_CH1_01  ──set──→  sd_ch1_01_done
    ↓ required
SD_CH1_02  ──set──→  sd_ch1_02_done, ruins_market_intro
    ↓ required                          ↓ required
SD_CH1_03  ──set──→  sd_ch1_03_done    SD_TUTORIAL_EXPLORE_HINT  ──set──→  tutorial_explore_guided
    ↓ required
SD_CH1_04  ──set──→  sd_ch1_04_done, ch1_done, chose_go_further / chose_steady_first
    ↓ 代码设置
ch2_started  ──required──→  SD_TUTORIAL_TOWER_ARRIVAL  ──set──→  tutorial_arrived_tower, npc_han_ce_intro
```

### 代码设置的 flag

| flag | 设置位置 | 说明 |
|------|---------|------|
| `tutorial_shop_intro` | tutorial.lua 功能气泡教程 | 交易所使用后设置 |
| `ch2_started` | main.lua 章节推进 | 第 2 章开始时设置 |

---

## 十、受影响文件清单

| 文件 | 变更类型 |
|------|---------|
| `scripts/narrative/story_director.lua` | **新增** |
| `assets/configs/tutorial_dialogues.json` | **新增** |
| `scripts/narrative/tutorial.lua` | 重写 |
| `scripts/narrative/campfire.lua` | 修改（type 过滤） |
| `scripts/narrative/dialogue_pool.lua` | 修改（加载第三个配置） |
| `scripts/main.lua` | 修改（集成 StoryDirector） |
| `assets/configs/story_dialogues.json` | 修改（移除教程对话、移除 is_story 字段） |
| `scripts/ui/screen_home.lua` | 修改（阶段引用） |
| `scripts/ui/screen_prepare.lua` | 修改（阶段引用） |
| `scripts/ui/screen_debug.lua` | 修改（flag 列表） |
| `tools/story_tree.py` | 修改（支持 tutorial 类型） |

---

## 十一、架构决策记录

### 为什么新建 StoryDirector 而不是增强 Campfire？

1. Campfire 是「玩家主动点篝火」的被动系统，主线故事需要「到达即触发」的主动推送
2. 主线对话不应消耗篝火资源（食物/燃料）和篝火次数
3. StoryDirector 可在到达、行程结束、主页空闲等多个时机检查触发，Campfire 只在点击时检查
4. 关注点分离：Campfire 管日常社交，StoryDirector 管叙事推进

### 为什么教程在温室就结束？

1. 教程的职责是教会基础操作（接单、出发、到达、交易所），温室社区已经覆盖全部
2. 探索和塔台不是操作教学，而是故事推进，应由叙事系统驱动
3. 教程过长会喧宾夺主，让玩家以为是教程游戏而非故事游戏

### 为什么拆分配置文件？

1. 系统边界应在文件层面可见——改教程不需要碰主线配置，改主线不需要碰教程配置
2. 每个系统对数据的标记需求不同（`is_story` vs `is_tutorial`），来源文件是标记的自然依据
3. 避免类型混淆——`story_dialogues.json` 现在只包含 `main_story` 类型，`tutorial_dialogues.json` 只包含 `tutorial` 类型

### 为什么保留统一 DialoguePool 而不是拆成三个池？

1. `DialoguePool.get(id)` 精确查找被多处使用，拆池会破坏跨系统 ID 查找
2. `DialoguePool.filter()` 的 7 步筛选逻辑对三类对话完全通用
3. 下游模块通过 `type`/`is_story`/`is_tutorial` 做二次过滤已足够清晰
4. 合池加载 + 标记区分是「统一数据入口 + 独立业务过滤」的标准模式

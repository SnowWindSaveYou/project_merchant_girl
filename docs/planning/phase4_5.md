# Phase 4 & 5 开发计划

> 末世行商 - 主线章节引擎 + 聚落故事线实现方案
> 编写于 2026-04-08，防止上下文丢失

---

## 已完成的前置工作

| Phase | 内容 | 状态 |
|-------|------|------|
| 1 | 路景系统 (scenery.lua / scenery.json) | Done |
| 2 | 车内对话 +12 条、电台广播 +7 条 | Done |
| 3.0 | goodwill.lua 增加 archives/farm/intel/black_market 解锁 | Done |
| 3.1 | 档案馆系统 (bell_tower): archives.lua + screen_archives.lua + archives.json (13篇) | Done |
| 3.2 | 培育场系统 (greenhouse): farm.lua + screen_farm.lua + crops.json (5种作物) | Done |
| 3.3 | 情报站系统 (tower): intel.lua + screen_intel.lua | Done |
| 3.4 | 黑市系统 (ruins_camp): black_market.lua + screen_black_market.lua | Done |
| 3.5 | 集成: screen_home 入口按钮 + main.lua 存档兼容 + 行程钩子 + debug面板 | Done |

---

## Phase 4: 主线章节引擎 + 8 NPC

### 4.1 章节状态机 (`scripts/narrative/main_story.lua`)

**核心设计**: 基于 flags + stats 的被动触发器，不主动推进剧情，而是在条件满足时解锁下一章节内容。

```
模块职责:
- get_chapter(state) → 当前章节 (0=序章 ~ 7=终章)
- check_advance(state) → 检查是否满足进章条件
- get_chapter_info(ch) → { id, name, trigger_conditions, unlocks }
- get_active_events(state) → 当前章节可触发的剧情事件列表
```

**章节触发条件一览**:

| 章节 | 触发条件 | 核心 Flag |
|------|---------|-----------|
| 序章 | 游戏开始 | `prologue_done` (首次篝火后) |
| Ch.1 熟悉的路 | 序章完成 + >=5趟 + 访问>=2聚落 | `ch1_done` |
| Ch.2 四种声音 | Ch.1 + 4大聚落全访问 + >=12趟 | `ch2_done`, `linli_signal_revealed` |
| Ch.3 铁锁 | Ch.2 + >=20趟 + 任一好感>=Lv1 | `ch3_done`, `iron_lock_encountered` |
| Ch.4 裂痕与种子 | Ch.3 + >=30趟 + 任一好感>=Lv2 | `ch4_done`, `shuangqi_met` |
| Ch.5 静潮 | Ch.4 + >=40趟 + 2个好感>=Lv2 + `shuangqi_met` | `ch5_done`, `lu_chen_met` |
| Ch.6 地图的另一半 | Ch.5 + >=50趟 + 3个好感>=Lv2 + 地图碎片>=3 | `ch6_done` |
| 终章 云海之上 | Ch.6 + 玩家确认出发 | `ending_a/b/c` |

**实现步骤**:

1. 创建 `scripts/narrative/main_story.lua` — 章节状态机
2. 创建 `assets/configs/story_chapters.json` — 章节配置（触发条件、解锁内容、关键对话ID）
3. 在 `handleTripFinish()` 中调用 `MainStory.check_advance(state)` 检测进章
4. 在 `screen_home` 中显示章节进度提示（如有新章节解锁）
5. 存档兼容: `state.narrative.chapter = 0`, `state.narrative.chapter_flags = {}`

### 4.2 主线剧情事件 (`assets/configs/story_events.json`)

**设计**: 复用现有 event_pool / event_scheduler 框架，添加 `EVT_1xx` 系列主线事件。

- 每章 2-4 个剧情事件，总计约 20 个
- 事件通过 `required_flags` 控制出现时机
- 事件结果通过 `set_flags` 推进剧情
- 部分事件包含玩家选择（影响后续分支 flag）

**事件格式扩展**:
```json
{
  "id": "EVT_101",
  "pool": "main_story",
  "chapter": 1,
  "title": "路标被移动了",
  "required_flags": ["ch1_done"],
  "forbidden_flags": ["mention_moved_signs"],
  "choices": [
    { "text": "记录下来", "set_flags": ["mention_moved_signs"], "goodwill": {} },
    { "text": "不管了", "set_flags": ["mention_moved_signs"] }
  ]
}
```

**实现步骤**:

1. 扩展 `event_pool.lua` 支持 `pool: "main_story"` 过滤
2. 创建 `assets/configs/story_events.json` — 主线事件配置
3. 在 `event_scheduler.lua` 中增加主线事件优先触发逻辑
4. 事件结果处理器支持 `set_flags` 批量设置

### 4.3 主线对话系统 (`scripts/narrative/story_dialogue.lua`)

**设计**: 用于序章/章节关键场景的多轮对话演出，比普通 NPC 对话更丰富。

```
功能:
- 多轮对话（连续多条台词，带说话人切换）
- 分支选项（2-3 个选择，影响 flag）
- 特殊标记：旁白、内心独白、场景描写
- 篝火特殊对话（章节转折点）
```

**实现步骤**:

1. 创建 `assets/configs/story_dialogues.json` — 主线对话配置
2. 创建 `scripts/narrative/story_dialogue.lua` — 多轮对话状态机
3. 创建 `scripts/ui/screen_story_dialogue.lua` — 对话演出 UI
4. 扩展篝火系统 (`campfire.lua`) 支持主线关键对话触发

### 4.4 新 NPC 定义 (8 个角色)

**新增角色**:

| 角色 | 类型 | 首次出现 | 所属势力 |
|------|------|---------|---------|
| 江寒 (Jiang Han) | 铁锁领队 | Ch.3 | 铁锁商队 |
| 小毛 (Xiao Mao) | 铁锁机修 | Ch.3 | 铁锁商队 |
| 陆沉 (Lu Chen) | 静潮代表 | Ch.5 | 静潮社 |
| 霜七 (Shuangqi) | 静潮脱离者 | Ch.4 | 静潮社(脱离) |
| 季微 (Ji Wei) | 塔台技术员 | Ch.2 | 北穹塔台 |
| 老甘 (Old Gan) | 温室长者 | Ch.2 | 温室社区 |
| 刀鱼 (Dao Yu) | 废墟少女 | Ch.2 | 废墟营地 |
| 谢泠 (Xie Ling) | 钟楼抄录员 | Ch.2 | 钟楼书院 |

**实现步骤**:

1. 扩展 `assets/configs/npcs.json` 添加 8 个角色定义
2. 扩展 `assets/configs/npc_dialogues.json` 添加对话内容
   - 4 个聚落驻留 NPC (季微/老甘/刀鱼/谢泠): 各 5-8 组对话
   - 2 个流浪 NPC (孟辉增强/霜七): 各 3-5 组对话
   - 2 个主线剧情 NPC (江寒/陆沉): 各 3-4 组关键对话
3. 在 `npc_manager.lua` 中注册新角色
4. 流浪 NPC 出现逻辑: 孟辉已有、霜七在 Ch.4 后随机出现

### 4.5 势力系统 (`scripts/settlement/factions.lua` 扩展)

**新增势力**:

| 势力 | 定位 | 与玩家关系 |
|------|------|-----------|
| 铁锁商队 | 垄断竞争者 | 竞争→谈判→可能合作 |
| 静潮社 | 断联主义者 | 隐形阻碍→直面→和解 |

**实现步骤**:

1. 在 `factions.lua` 中添加铁锁/静潮势力定义
2. 添加势力好感度追踪（与聚落好感独立）
3. 铁锁关系影响: 经济压力事件、路费事件
4. 静潮关系影响: 路标消失事件、隧道封锁事件

### 4.6 三结局系统

```
结局判定逻辑（终章到达云海塔后）:
- 结局 C "点亮信号": 4大聚落全部 Lv3(90+) → 真结局
- 结局 B "驻留守望": 任一聚落 Lv3(90+) → 温暖结局
- 结局 A "继续行走": 默认 → 开放结局
```

**实现步骤**:

1. 在 `main_story.lua` 中添加 `get_ending(state)` 判定
2. 创建 `scripts/ui/screen_ending.lua` — 结局演出页面
3. 结局后进入 NG+ 或自由游玩模式

---

## Phase 5: 聚落故事线第一幕

### 5.1 故事线框架 (`scripts/narrative/settlement_story.lua`)

**设计**: 每个聚落 5 幕故事，与好感等级挂钩。Phase 5 仅实现第一幕。

```
模块职责:
- get_act(state, settlement_id) → 当前幕数 (0-5)
- check_act_advance(state, settlement_id) → 检查是否满足下一幕条件
- get_act_event(state, settlement_id) → 当前幕的事件 (nil = 已完成)
- complete_act(state, settlement_id) → 标记当前幕完成
```

**实现步骤**:

1. 创建 `scripts/narrative/settlement_story.lua` — 聚落故事状态机
2. 创建 `assets/configs/settlement_stories.json` — 故事配置

### 5.2 四个聚落的第一幕内容

#### 温室 Act 1: "沈荷的难题" (好感 Lv1)
- 沈荷展示失败的小麦实验
- 需要塔台的稀有肥料，韩策开价太高
- 玩家行动: 帮忙采购材料
- 完成奖励: 好感+5, 解锁培育场系统提示

#### 废墟 Act 1: "入场费" (好感 Lv1)
- 伍十七解释市场规矩
- 陶夏质疑卖家欺诈问题
- 完成奖励: 好感+5, 解锁黑市系统提示

#### 塔台 Act 1: "数据交换" (好感 Lv1)
- 韩策允许设立"信息交换区"
- "数据换数据，公平交易"
- 完成奖励: 好感+5, 解锁情报站系统提示

#### 钟楼 Act 1: "抄录员" (好感 Lv1)
- 白术展示档案室，谢泠手抄古籍
- "为什么不打印？" "打印要电和墨。我们有手和墨。而且——抄录的人会记住内容。机器不会。"
- 完成奖励: 好感+5, 解锁档案系统提示

**实现步骤**:

1. 为每个聚落创建 Act 1 事件配置 (4 个事件)
2. 每个事件包含 2-3 轮对话 + 1 个任务动作
3. 在 `screen_home` 聚落视图中显示故事进度指示
4. 任务完成后触发系统解锁提示

### 5.3 集成点

| 系统 | 集成方式 |
|------|---------|
| screen_home | 显示当前章节名/聚落故事进度 |
| handleTripFinish | 调用 MainStory.check_advance + SettlementStory.check_act_advance |
| event_scheduler | 主线事件优先级高于随机事件 |
| campfire | 章节转折对话注入 |
| radio/chatter | 内容随主线章节变化（flag 过滤已支持） |
| quest_log | 主线任务显示在任务日志中 |

---

## 文件清单预估

### Phase 4 新增文件

```
scripts/narrative/main_story.lua          # 章节状态机
scripts/narrative/story_dialogue.lua      # 多轮对话引擎
scripts/ui/screen_story_dialogue.lua      # 对话演出 UI
scripts/ui/screen_ending.lua              # 结局演出
assets/configs/story_chapters.json        # 章节配置
assets/configs/story_events.json          # 主线事件 (~20个)
assets/configs/story_dialogues.json       # 主线对话
```

### Phase 4 修改文件

```
assets/configs/npcs.json                  # +8 NPC
assets/configs/npc_dialogues.json         # +40 组对话
scripts/settlement/factions.lua           # +2 势力
scripts/narrative/npc_manager.lua         # 注册新角色
scripts/events/event_pool.lua             # 支持 main_story pool
scripts/events/event_scheduler.lua        # 主线优先触发
scripts/main.lua                          # 进章钩子 + 存档兼容
scripts/ui/screen_home.lua                # 章节提示 UI
scripts/core/state.lua                    # narrative.chapter 初始值
```

### Phase 5 新增文件

```
scripts/narrative/settlement_story.lua    # 聚落故事状态机
assets/configs/settlement_stories.json    # 故事配置 (4聚落 x 第1幕)
```

### Phase 5 修改文件

```
scripts/main.lua                          # 故事进度检查钩子
scripts/ui/screen_home.lua                # 故事进度 UI
```

---

## 实现优先级

```
Phase 4 建议拆分为子步骤:
  4.1 章节状态机 + 配置         (核心骨架)
  4.2 主线事件配置               (序章+Ch.1+Ch.2 先行)
  4.3 多轮对话系统               (演出能力)
  4.4 8个 NPC 注册 + 基础对话    (可分批: 聚落NPC先，势力NPC后)
  4.5 势力系统扩展               (Ch.3 前完成)
  4.6 三结局                     (最后实现)

Phase 5 可以在 4.1-4.3 完成后立即开始:
  5.1 聚落故事框架
  5.2 四个第一幕内容
  5.3 集成
```

---

## 技术约束与注意事项

1. **flag 系统已就绪**: `core/flags.lua` 的 `set/has/clear` 完全够用
2. **quest_log 已就绪**: 可直接添加主线任务条目
3. **chatter/radio 的 flag 过滤已支持**: 新内容只需在 JSON 中添加 `required_flags`
4. **event_pool 的 required_flags/forbidden_flags 已支持**: 主线事件可直接使用
5. **NPC 对话系统已就绪**: npc_manager + npc_dialogue_pool 可直接扩展
6. **好感度系统已就绪**: goodwill.lua 的 level/threshold 判断直接可用
7. **存档兼容模式已建立**: main.lua Start() 中的补丁模式可继续使用
8. **模块化已到位**: 所有新模块放 scripts/narrative/ 和 assets/configs/

---

*文档版本: v1.0*
*最后更新: 2026-04-08*

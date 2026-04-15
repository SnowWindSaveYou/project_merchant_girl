# 教程与主线叙事触发链

> 本文档描述玩家从进入游戏到第一章结束的完整强制/半强制流程，
> 供后续修改时快速查找触发条件和时序约束。

---

## 一、教程阶段机

教程有 5 个阶段，**完全由 flags 推导**，不存储独立变量。

| 阶段 | 条件 | 玩家可做的事 | 被锁的事 |
|------|------|-------------|---------|
| NONE | `tutorial_started` 未设置 | 无（新游戏不会停留此阶段） | — |
| SPAWN | `tutorial_started` 已设置，无教程订单、未到温室 | 只能「接取委托」 | 出发、NPC、交易所、篝火、地图其他节点 |
| TRAVEL_TO_GREENHOUSE | 有去温室的已接教程订单 | 行驶中、路面物资提示 | 地图点击非温室节点、探索未知区域 |
| AT_GREENHOUSE | `tutorial_arrived_greenhouse` 已设置，`tutorial_shop_intro` 未设置 | NPC拜访、交易所（高亮）、委托、篝火 | **出发按钮锁定** |
| COMPLETE | `tutorial_arrived_greenhouse` + `tutorial_shop_intro` 均已设置 | 全部 | 无 |

阶段推导代码：`scripts/narrative/tutorial.lua` `M.get_phase()`

---

## 二、强制对话链（按触发顺序）

### 2.1 序章对话

| # | 对话 ID | 标题 | 触发方式 | 触发条件 | 设置的 flags |
|---|---------|------|---------|---------|-------------|
| ① | SD_PROLOGUE_01 | 车坏了 | `main.lua Start()` 直接导航 | 新游戏（`sd_prologue_01_done` 未设置） | `sd_prologue_01_done`, `tutorial_started`, `chose_safe_return` 或 `chose_go_forward` |

**注意**：此对话中车**尚未起名**，不可使用"麻薯号"。

### 2.2 教程对话

| # | 对话 ID | 标题 | 触发方式 | 触发条件 | 设置的 flags |
|---|---------|------|---------|---------|-------------|
| ② | SD_TUTORIAL_FIRST_DEPARTURE | 麻薯号，出发 | `screen_map.lua tryTutorialDeparture()` | 教程阶段=TRAVEL_TO_GREENHOUSE 且 `tutorial_first_departure_done` 未设置 | `tutorial_first_departure_done` |
| ③ | SD_TUTORIAL_GREENHOUSE_ARRIVAL | 温室社区 | `tutorial.lua M.on_arrival()` 拦截 | 到达 greenhouse 节点 + `tutorial_started` 已设置 + `tutorial_arrived_greenhouse` 未设置 | `tutorial_arrived_greenhouse`, `npc_shen_he_intro` |

**关键时序约束**：
- ② 在玩家确认路线后、行驶开始前触发（`Flow.start_travel` 先执行，然后导航到 campfire）
- ③ 是到达拦截，**优先于 StoryDirector**（Tutorial.on_arrival 先执行，拦截后 StoryDirector 不执行）
- ② 是**车被命名"麻薯号"的场景**，之后才可以用"麻薯号"称呼

### 2.3 教程完成 → 序章收尾

| # | 对话 ID | 标题 | 触发方式 | 触发条件 | 设置的 flags |
|---|---------|------|---------|---------|-------------|
| — | 交易所教程气泡 | （6步功能教学） | 进入交易所自动触发 | `tutorial_shop_intro` 未设置 | `tutorial_shop_intro` |
| ④ | SD_PROLOGUE_02 | 第一晚 | `StoryDirector.check_home_auto_trigger()` | `sd_prologue_01_done` + `tutorial_arrived_greenhouse` + `min_trips≥2` + 首页 | `sd_prologue_02_done`, `prologue_done`, `motivation_duty` 或 `motivation_curiosity` |

**关键设计**：
- 交易所气泡是**非阻断式**教学，不锁操作，但必须完成才能让教程进入 COMPLETE
- PROLOGUE_02 需要 `tutorial_arrived_greenhouse`（而非 `tutorial_shop_intro`），因为后者是可选功能教学
- PROLOGUE_02 的 `min_trips: 2` 确保不在教程到达时与 GREENHOUSE_ARRIVAL 背靠背

### 2.4 第一章对话

| # | 对话 ID | 标题 | 触发方式 | 触发条件 | node_types | min_trips |
|---|---------|------|---------|---------|-----------|-----------|
| ⑤ | SD_CH1_01 | 第三趟 | 首页 StoryDirector | `prologue_done` | any | 2 |
| ⑥ | SD_CH1_02 | 外面的规矩 | 到达据点 StoryDirector | `sd_ch1_01_done` | settlement | 3 |
| ⑦ | SD_CH1_02B | 伍拾七的地图 | 到达据点 StoryDirector | `ruins_market_intro` | settlement | 4 |
| ⑧ | SD_TUTORIAL_EXPLORE_HINT | 未知的路 | 首页 StoryDirector | `sd_ch1_02b_done` | any | 5 |
| ⑨ | SD_CH1_03 | 画册 | 到达据点 StoryDirector | `sd_ch1_02b_done` | settlement | 5 |
| ⑩ | SD_CH1_03B | 沈禾的话 | 到达据点 StoryDirector | `sd_ch1_03_done` | settlement | 6 |
| ⑪ | SD_CH1_04 | 看油够不够 | 首页 StoryDirector | `sd_ch1_03b_done` | any | 7 |

**CH1_01 解锁废墟路线**：两个选择都包含 `unlock_route:crossroads` + `unlock_route:ruins_camp`，确保玩家可以去据点触发后续对话。

---

## 三、触发系统优先级

### 3.1 到达时的执行顺序

```
1. Tutorial.on_arrival()  ← 教程拦截，最高优先级
   ↳ 拦截时：设置 _deferred_arrival，导航 campfire，return
   ↳ 不拦截：继续 ↓

2. Flow.handle_node_arrival()  ← 正常到达处理（交货、标记已访问、生成订单）

3. StoryDirector.on_node_arrival()  ← 仅最终节点
   ↳ 命中时：设置 _deferred_trip_finish，导航 campfire，return
   ↳ 不命中：继续 ↓

4. handleTripFinish()  ← 行程结算
```

### 3.2 首页每帧检查

```
StoryDirector.check_home_auto_trigger()
  条件：curPage == "home" 且非行驶中
  过滤：排除 arrival_only 对话
  命中时：直接导航到 campfire
```

### 3.3 出发时检查

```
screen_map.lua tryTutorialDeparture()
  条件：教程阶段=TRAVEL_TO_GREENHOUSE 且首次出发未完成
  动作：先 Flow.start_travel()，再导航 campfire 播放对话
  注意：此时行驶已开始，对话在行驶中播放
```

---

## 四、UI 锁定详表

| 教程阶段 | 首页按钮 | 地图限制 | 悬浮按钮 |
|---------|---------|---------|---------|
| SPAWN | 只有「接取委托」（高亮） | 只能点击温室节点，探索被阻 | 无 |
| TRAVEL_TO_GREENHOUSE | 正常行驶页 | 只能点击温室节点，探索被阻 | 正常 |
| AT_GREENHOUSE | NPC + 交易所（高亮）+ 委托 + 篝火；**出发锁定** | 正常 | 正常 |
| COMPLETE | 全部 | 正常 | 全部 |

代码位置：`scripts/ui/screen_home.lua` 行 391-463，`scripts/ui/screen_map.lua` 行 1230-1519

---

## 五、Flag 流转图

```
游戏开始 (无 flags)
  │
  ▼
SD_PROLOGUE_01
  ├─ sd_prologue_01_done
  ├─ tutorial_started          ← 教程开始
  └─ chose_safe_return / chose_go_forward
  │
  ▼  (SPAWN: 接单 → 确认路线)
SD_TUTORIAL_FIRST_DEPARTURE
  └─ tutorial_first_departure_done
  │
  ▼  (TRAVEL_TO_GREENHOUSE: 行驶)
SD_TUTORIAL_GREENHOUSE_ARRIVAL
  ├─ tutorial_arrived_greenhouse  ← 进入 AT_GREENHOUSE
  └─ npc_shen_he_intro
  │
  ▼  (AT_GREENHOUSE: 交易所气泡)
tutorial_shop_intro               ← 进入 COMPLETE
  │
  ▼  (再跑1趟, min_trips=2)
SD_PROLOGUE_02
  ├─ sd_prologue_02_done
  ├─ prologue_done                ← 序章结束
  └─ motivation_duty / motivation_curiosity
  │
  ▼  (min_trips=2, 首页触发)
SD_CH1_01
  ├─ sd_ch1_01_done
  └─ unlock_route: crossroads + ruins_camp  ← 解锁废墟
  │
  ▼  (min_trips=3, 到达据点)
SD_CH1_02
  ├─ sd_ch1_02_done
  └─ ruins_market_intro
  │
  ▼  (min_trips=4, 到达据点)
SD_CH1_02B
  └─ sd_ch1_02b_done
  │
  ▼  (min_trips=5, 首页触发)
SD_TUTORIAL_EXPLORE_HINT
  └─ tutorial_explore_guided
  │
  ▼  (min_trips=5, 到达据点)
SD_CH1_03
  └─ sd_ch1_03_done
  │
  ▼  (min_trips=6, 到达据点)
SD_CH1_03B
  ├─ sd_ch1_03b_done
  └─ ch1_signal_hint
  │
  ▼  (min_trips=7, 首页触发)
SD_CH1_04
  ├─ sd_ch1_04_done
  └─ ch1_done                     ← 第一章结束
```

---

## 六、叙事时序约束

### 6.1 "麻薯号"命名时序

- **SD_PROLOGUE_01 之前/期间**：车**没有名字**，只能用"货车""车"等称呼
- **SD_TUTORIAL_FIRST_DEPARTURE**：陶夏起名"麻薯号" ← 起名场景
- **SD_TUTORIAL_FIRST_DEPARTURE 之后**：所有文本可以自由使用"麻薯号"

此约束影响范围：
- `story_dialogues.json` SD_PROLOGUE_01 旁白和 result_text
- `story_events.json` SEVT_001（序章事件，`forbidden_flags: ["tutorial_started"]`）
- `campfire_dialogues.json` 中 `required_flags` 不含 `tutorial_first_departure_done` 的对话

### 6.2 NPC 首次出场

| NPC | 首次出场对话 | 出场时设置的 flag |
|-----|------------|-----------------|
| 沈禾 | SD_TUTORIAL_GREENHOUSE_ARRIVAL | `npc_shen_he_intro` |
| 韩策 | SD_TUTORIAL_TOWER_ARRIVAL | `npc_han_ce_intro` |
| 伍拾七 | SD_CH1_02 | 无专门 intro flag |
| 刀鱼 | SD_CH1_03 | 无专门 intro flag |

在首次出场对话之前，不应有文本假设玩家已认识该 NPC。

### 6.3 地点首次到达

| 地点 | 首次到达对话 | 解锁方式 |
|-----|------------|---------|
| 温室社区 | SD_TUTORIAL_GREENHOUSE_ARRIVAL | 教程订单 |
| 废墟营地 | SD_CH1_02 | CH1_01 的 `unlock_route:ruins_camp` |
| 北穹塔台 | SD_TUTORIAL_TOWER_ARRIVAL | `ch2_started` flag |

在玩家首次到达某地点之前，对话不应假设玩家已到过该地。

---

## 七、配置文件分布

| 文件 | 内容 | 类型标记 |
|------|------|---------|
| `assets/configs/tutorial_dialogues.json` | 教程专属对话（②③） | 加载时自动设置 `is_tutorial=true` |
| `assets/configs/story_dialogues.json` | 主线对话（①④⑤-⑪） | 加载时自动设置 `is_story=true` |
| `assets/configs/campfire_dialogues.json` | 篝火日常对话 | 无额外标记 |
| `assets/configs/chatter.json` | 行驶中车内对话 | 独立系统 |
| `assets/configs/story_events.json` | 旅行事件 | 由 EventScheduler 管理 |

DialoguePool 加载顺序：campfire → story → tutorial（`scripts/narrative/dialogue_pool.lua`）

---

## 八、StoryDirector 与 Tutorial 的职责边界

| 职责 | StoryDirector | Tutorial |
|------|-------------|----------|
| 主线对话自动触发 | ✓（`type=="main_story"`） | ✗ |
| 教程对话触发 | ✗（跳过 `type=="tutorial"`） | ✓（`DialoguePool.get()` 直接 ID 查找） |
| 到达拦截 | 无拦截机制 | `on_arrival()` 拦截（优先于 StoryDirector） |
| 首页触发 | `check_home_auto_trigger()` | 无（首页由 StoryDirector 接管） |
| 出发拦截 | 无 | `screen_map.lua tryTutorialDeparture()` |
| UI 锁定 | 无 | 教程阶段控制 |

---

## 九、已知设计约束与风险

1. **CH1_02~03B 需要到达 settlement**：如果玩家不去废墟营地，这些对话不会触发。CH1_01 的 `unlock_route` 缓解了此问题。
2. **AT_GREENHOUSE 出发锁定**：玩家必须完成交易所教程才能离开温室。交易所按钮已加高亮引导。
3. **`tutorial_shop_intro` 是功能教学 flag**：设置条件是进入交易所并完成6步气泡，不应用作主线门控。
4. **PROLOGUE_02 的 `min_trips: 2`**：教程只跑了1趟，所以"第一晚"发生在教程后的第2趟。这是为了防止与 GREENHOUSE_ARRIVAL 背靠背。
5. **旧存档兼容**：`tutorial_started` 未设置的旧存档，`Tutorial.get_phase()` 返回 NONE，整个教程被跳过。

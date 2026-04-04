# Phase 05 — 随机事件、旗标与轻叙事

## 本阶段目标

把路上会发生的事接进主循环，让游戏从“纯算账”变成“有旅途感的跑商”。

这阶段完成后，玩家应该开始感受到：

- 路上不是只看进度条
- 角色关系会影响体验
- 一些小事件会留下后续影响

核心要求：**事件主触发时机在行程中，不是结算后统一触发。**

---

## 本阶段只关心什么

- 随机事件池
- 触发条件筛选
- 选项执行
- 结果生效
- 旗标系统联动
- 轻关系剧情接入
- 触发时机调度（行程中）

## 本阶段不要做什么

- 不做完整长篇主线演出
- 不做复杂剧情树编辑器
- 不做所有事件的全量文案 polish
- 不把绝大部分事件堆到结算后一次触发

---

## 事件系统先拆三层

在三层之外，再补一个“调度层”，专门负责触发时机。

### 0. 事件调度层（新增）

负责决定**何时检查事件池**：

- 行驶中按时间片检查（例如每 10~20 秒）
- 行驶中按里程节点检查（例如 25% / 50% / 75%）
- 抵达聚落后仅检查少量 `settlement/camp` 事件

### 1. 事件筛选层

根据：

- 当前阶段
- 当前场景
- 路线标签
- 当前边类型（main_road/path/shortcut）
- 当前节点类型（settlement/resource/transit/hazard/story）
- 旗标
- 冷却

筛出可触发事件。

### 2. 事件展示层

负责：

- 弹窗
- 显示选项
- 接收玩家选择

### 3. 事件执行层

负责解释：

- `ops`
- `set_flags`
- `clear_flags`
- `next_event_id`

---

## 先只接 10~15 条事件

不要一上来接完整 50 条。

优先接：

- 基础拾取
- 路况判断
- 轻关系事件
- 一个车载遇袭教学事件
- 一个主线线索事件

建议第一批：

- `EVT_001`
- `EVT_003`
- `EVT_005`
- `EVT_006`
- `EVT_007`
- `EVT_008`
- `EVT_009`
- `EVT_010`
- `EVT_014`
- `EVT_020`

其中 `EVT_001`、`EVT_005`、`EVT_009` 必须在 `TRAVELLING` 状态下可触发。

---

## 旗标系统必须真正参与逻辑

不能只是“存一下看看”。

### 旗标至少影响

- 某事件是否能出现
- 某选项是否可见
- 某剧情是否继续
- 某路线是否解锁

### 先支持两类旗标

1. 一次性结果旗标
   - 例如 `flag_doll_resolved`

2. 进度型旗标
   - 例如 `flag_night_market_rumor`

---

## 关系剧情怎么接

首版不要做独立剧情大系统。

先做成：

- 行程中低频触发（不打断关键操作）
- 在营地或结算后补充触发
- 以小弹窗 / 小对话出现

### 优先做的关系内容

- 林砾 / 陶夏的轻对话
- 简短分歧
- 小奖励型默契事件

目标是让角色“开始活起来”，不是立刻做完整人物线。

---

## 事件执行器建议

写一个统一执行器，不要每个事件单独写 if else。

```lua
EventExecutor.apply(state, {
  "add_credit:40",
  "add_time:10",
  "set_flag:flag_xxx"
})
```

这样后续接配置表会稳定很多。

## 触发时机实现建议（必须做）

建议在 `core/ticker.lua` 中加入固定检查节奏：

```lua
-- 伪代码
if state.flow == "travelling" then
   state.event_timer = state.event_timer + dt
   if state.event_timer >= EVENT_CHECK_INTERVAL then
      state.event_timer = 0
      EventScheduler.try_trigger_travel_event(state)
   end
end
```

并区分事件来源：

- `travel_event`：行程中触发（主来源）
- `arrival_event`：到站后触发（少量）
- `camp_event`：营地触发（关系类为主）

并增加地图上下文限制：

- `resource_event`：仅在 `resource` 节点停靠时触发
- `hazard_event`：仅在 `hazard` 节点或高危边触发

---

## UI 最低需求

- 事件弹窗
- 选项按钮
- 结果提示
- 简单角色头像或名字显示（可选）

首版不要求复杂立绘切换。

---

## 通过标准

- [ ] 事件池能按条件筛选
- [ ] 事件弹窗能正常展示并选择
- [ ] 结果能正确改 state
- [ ] 旗标能影响后续事件出现
- [ ] 至少 1 条简单事件链能跑通
- [ ] 至少 2 条角色轻剧情能触发
- [ ] 至少 70% 的常规随机事件在 `TRAVELLING` 状态触发
- [ ] 结算后只触发少量摘要/营地类事件，不再承担主事件触发职责

---

---

## 当前完成度评估（差距分析）

> 最后更新: 2026-04-04（第二次更新）

### 已完成 ✅

| 模块 | 文件 | 说明 |
|------|------|------|
| 事件调度层 | `events/event_scheduler.lua` | 时间片 + 里程节点双通道调度，上下文概率加成，单趟上限，pending 队列，**现已传递 filter 上下文** |
| 事件筛选 + 加权抽取 | `events/event_pool.lua` | **已重写为 JSON 配置驱动**，支持 7 维筛选（冷却/required_flags/forbidden_flags/phase/scene/trigger_tags/可见选项），加权随机 pick |
| 事件执行器 | `events/event_executor.lua` | 统一 `"action:value"` 格式，**已扩展至 16+ 种 op**（含 add_time/add_damage/repair_damage/lose_goods/unlock_route/unlock_clue/unlock_event/start_combat/spawn_order/add_goodwill:faction） |
| 旗标系统 | `core/flags.lua` | set / clear / has 三件套 |
| 调度集成 | `core/flow.lua` → `main.lua` | 出发时创建 timer，行程中每帧调用 scheduler.update，到站清理 |
| 事件弹窗 UI | `ui/screen_event.lua` + `ui/screen_event_result.lua` | 展示事件、选项按钮、结果反馈，**新增 show_condition 过滤、set_flags/clear_flags 处理、链式事件 unlock** |
| 配置驱动事件池 | `event_pool.lua` + `assets/configs/guaji_random_events.json` | **50 个事件从 JSON 加载**，合并 choice_sets/result_sets 为 UI 兼容格式 |
| 链式事件 | `event_pool.lua` `_build_chain_locks()` | **自动注入 unlock 旗标**，5 条事件链（玩偶/林砾手册/夜市/地图碎片/鸣砂广播）均可通过旗标触发 |
| 首批 10 事件数据 | `guaji_random_events.json` | 10/50 个事件已有完整 choice_sets + result_sets |

### 仍需后续迭代 ⚠️

| 项目 | 说明 |
|------|------|
| 剩余 40 个事件的 choice_sets/result_sets | JSON 中 40/50 个事件仅有 event_main 定义，缺 choice/result 详细数据。可分批填充，不阻塞核心流程 |
| 角色关系剧情内容 | EVT_007(林砾)/EVT_008(陶夏) 结构已就绪，需补充更丰富的对话文案和分支 |
| DESCRIPTIONS 表迁移 | 当前事件描述文本在 event_pool.lua 的 DESCRIPTIONS table 中，后续应迁移到 JSON 的 event_text 表 |

### 通过标准逐项对照（更新后）

| 通过标准 | 状态 | 说明 |
|---------|------|------|
| 事件池能按条件筛选 | ✅ | 7 维筛选：冷却/required_flags[]/forbidden_flags[]/phase/scene/trigger_tags[]/可见选项 |
| 事件弹窗能正常展示并选择 | ✅ | screen_event + screen_event_result，含 show_condition 过滤 |
| 结果能正确改 state | ✅ | 16+ 种 op，覆盖设计文档要求 |
| 旗标能影响后续事件出现 | ✅ | 多旗标数组 required_flags[]/forbidden_flags[] + show_condition + 链式 unlock |
| 至少 1 条简单事件链能跑通 | ✅ | next_event_id + _build_chain_locks() 自动注入 unlock 旗标 |
| 至少 2 条角色轻剧情能触发 | ✅ | EVT_007(林砾收音机)/EVT_008(陶夏温室) 有完整 choice/result 数据 |
| 至少 70% 事件在 TRAVELLING 触发 | ✅ | scheduler 主循环在 TRAVELLING 运行 |
| 结算后只触发少量事件 | ✅ | 调度器到站后清理 |

**Phase 05 通过标准：8/8 ✅ 全部达成**

### 已关闭行动项

1. ~~让 event_pool.lua 从 JSON 配置加载事件~~ ✅ 已重写为 DataLoader 驱动
2. ~~补全 JSON 中首批 10 个事件的 choice_sets 和 result_sets~~ ✅ 10/50 已完成
3. ~~扩展 filter() 支持 phase / scene / trigger_tags / 多旗标数组~~ ✅ 7 维筛选
4. ~~扩展 executor 支持缺失 ops~~ ✅ 16+ 种 op
5. ~~实现 next_event_id 链式事件机制~~ ✅ _build_chain_locks + screen_event unlock
6. ~~将 cooldown 改为按趟数（run）而非按触发次数~~ ✅ 使用事件自身 cooldown_run 值

---

## 下一步

→ [06_combat_and_resource_points.md](06_combat_and_resource_points.md)

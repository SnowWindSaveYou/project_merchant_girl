# Phase 01 — 核心循环落地

## 本阶段目标

先把游戏最小可运行主循环做出来，不碰复杂剧情、不碰完整战斗、不碰所有聚落内容。

这阶段只回答一件事：

**玩家能不能从“接单 → 路线规划 → 出发 → 行驶 → 到达 → 结算”完整跑通一趟。**

---

## 本阶段只关心什么

- 主循环状态切换
- 时间推进
- 路线行驶
- 到站结算
- 离线补偿接入点

## 本阶段不要做什么

- 不做完整随机事件池
- 不做完整战斗
- 不做复杂 UI 动画
- 不做剧情分支

## 本阶段关键原则（必须遵守）

- **接单与出发解耦**：接单只进入订单簿，不应自动触发行程
- **路线是独立决策**：玩家必须先选路线或站点序列，再确认出发
- **没有已规划路线时禁止出发**

---

## 输入

- 技术基础来自 [00_tech_stack.md](00_tech_stack.md)
- 使用 Lua + UrhoX + NanoVG
- 使用单账号主存档 + 本地缓存

---

## 输出

完成后，项目必须具备以下能力：

1. 进入游戏后能看到主界面
2. 能选择一个订单
3. 能进入路线规划并确认出发
4. 行驶过程中时间会推进
5. 到达终点后能完成一次基础结算
6. 退出重进后能恢复当前状态

---

## 状态机先定义清楚

建议先把主循环拆成明确状态，不要一开始就写散。

```lua
GameFlow = {
  IDLE = "idle",
  MAP = "map",
  PREPARE = "prepare",
  ROUTE_PLAN = "route_plan",
  TRAVELLING = "travelling",
  ARRIVAL = "arrival",
  SETTLEMENT = "settlement",
  SUMMARY = "summary",
}
```

### 状态说明

| 状态 | 含义 |
|------|------|
| `IDLE` | 初始空闲状态，等待玩家进入聚落或订单页 |
| `MAP` | 大地图浏览状态，查看已知节点、边和风险 |
| `PREPARE` | 管理订单簿、装货、查看可行目的地 |
| `ROUTE_PLAN` | 规划本次行程路线，确认站点顺序 |
| `TRAVELLING` | 行驶中，时间推进、距离减少 |
| `ARRIVAL` | 到站瞬间，准备结算 |
| `SETTLEMENT` | 展示聚落页、可继续接单 |
| `SUMMARY` | 展示收益、耗时、货损等摘要 |

---

## 先做一条最小路线

第一阶段只做：

- `greenhouse -> tower`
- `tower -> greenhouse`

路线配置先只保留：

```json
{
  "route_id": "route_greenhouse_tower",
  "from": "greenhouse",
  "to": "tower",
  "distance": 100,
  "danger_level": "low",
  "travel_time_sec": 120
}
```

运行时不要按真实物理位移做，直接按“剩余时间 / 剩余距离”推进即可。

---

## 代码拆分建议

### 1. `scripts/core/flow.lua`

负责状态切换：

- `enter_prepare()`
- `enter_map()`
- `enter_route_plan()`
- `confirm_route_and_depart(route_plan_id)`
- `update_travel(dt)`
- `arrive()`
- `finish_summary()`

### 2. `scripts/core/ticker.lua`

负责时间推进：

- 在线 `dt` 推进
- 离线秒数推进
- 统一给其他系统发“时间前进”结果

### 3. `scripts/map/travel.lua`

负责路线数据：

- 读取路线配置
- 初始化本次行驶数据
- 计算剩余时间、剩余距离、预计到达

---

## 开发顺序

### Step 1：先让 Flow 跑起来

实现最小接口：

```lua
Flow.start_travel(state, route_id, order_id)
Flow.update(state, dt)
Flow.finish_arrival(state)
```

要求：

- `TRAVELLING` 状态下每帧能减少剩余时间
- 剩余时间归零时自动切到 `ARRIVAL`

### Step 2：把订单和路线挂上

订单先只保留最小字段：

- `order_id`
- `from`
- `to`
- `reward`
- `cargo`

并明确两条规则：

1. 接单只改变 `OrderBook`，不改变 `GameFlow`
2. 只有 `confirm_route_and_depart()` 才能进入 `TRAVELLING`

### Step 3：做基础结算

到站后先只结算：

- 收入
- 耗时
- 是否到达

先不要做：

- 动态价格波动
- 货损
- 事件影响

### Step 4：接入离线补偿

离线恢复时不要直接跳过流程，而是：

1. 读取缓存状态
2. 计算离线秒数
3. 让 `ticker` 推进一次
4. 如果推进后到站，则直接弹出 `SUMMARY`

---

## UI 最小需求

本阶段 UI 只需要 3 个页面：

1. 主界面 / 行驶页
2. 大地图页（只显示已知节点）
3. 简单订单确认页
4. 简单路线规划页
5. 结算页

### 行驶页必须显示

- 当前路线
- 剩余时间
- 当前信用点
- 燃料
- 货车耐久
- 一个简单的进度条

---

## 通过标准

- [ ] 能从主界面接单，但不会自动出发
- [ ] 必须经过路线规划确认后才能开始行驶
- [ ] 行驶中进度条会正常变化
- [ ] 到站后会自动结算
- [ ] 结算后能回到聚落页
- [ ] 中途退出游戏再进，能恢复行驶进度
- [ ] 离线超过一段时间后，能直接推进到正确状态

---

## 常见错误

- 不要把“路线逻辑”和“UI 绘制”写在同一个文件里
- 不要让订单数据直接改 UI 状态
- 不要一开始就把随机事件混进主循环
- 不要用大量全局变量描述当前行驶状态
- 不要做成“接单按钮 = 直接出发按钮”

---

## 下一步

→ [02_data_and_save.md](02_data_and_save.md)

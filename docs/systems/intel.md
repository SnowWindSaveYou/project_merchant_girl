# 情报系统

> 北穹塔台·情报交换站 — 跑商收集路况数据，兑换影响玩法的情报

---

## 概述

情报系统是北穹塔台聚落的核心特色功能。玩家在跑商过程中自动积累**路况数据点**，到达塔台后可消耗数据点兑换各类情报。情报不仅提供文本信息，还会**实际影响玩法**：降低事件触发率、改善交易价格、制造限时商机、解锁隐藏地点。

---

## 数据流

```
跑商行程                    到达塔台
   │                          │
   ▼                          ▼
earn_route_data()          exchange()
（自动积累数据点）          （消耗数据点，生成情报）
   │                          │
   ▼                          ▼
state.settlements          active_intel[]
  .tower.intel               │
  .route_data              ┌──┴──────────────────────┐
                           │                          │
                     tick_intel()              玩法影响生效
                    （行程结束过期）          ┌───┼───┼───┐
                                             │   │   │   │
                                          安全 天气 价格 商机
                                           │   │   │   │
                                           ▼   ▼   ▼   ▼
                                        事件  捷径 定价 供需
                                        概率  危险 加成 注入
```

---

## 数据存储

所有情报数据存储在 `state.settlements.tower.intel` 下：

```lua
state.settlements.tower.intel = {
    route_data      = 0,    -- 累积路况数据点（货币）
    active_intel    = {},   -- 当前活跃情报列表
    total_exchanged = 0,    -- 累计交换次数（统计用）
}
```

### 活跃情报结构

```lua
-- 通用字段（所有类型）
{
    type       = "security",     -- 情报类型
    name       = "安全预警",      -- 显示名
    desc_text  = "东线公路...",   -- 描述文本
    trips_left = 2,              -- 剩余有效趟数
}

-- 商机情报额外字段
{
    type              = "tip",
    target_settlement = "bell_tower",  -- 目标聚落 ID
    target_goods      = "old_book",    -- 紧缺商品 ID
    ...
}

-- 价格情报额外字段
{
    type              = "price",
    target_settlement = "greenhouse",  -- 目标聚落 ID
    ...
}
```

---

## 情报类型

| 类型 | 名称 | 花费 | 持续 | 解锁条件 | 玩法效果 |
|------|------|------|------|----------|----------|
| `weather` | 天气预报 | 1 点 | 1 趟 | 好感 Lv1 | 捷径事件触发概率 -10% |
| `price` | 价格情报 | 2 点 | 1 趟 | 好感 Lv1 | 目标聚落买入 -8%、卖出 +8% |
| `security` | 安全预警 | 2 点 | 2 趟 | 好感 Lv2 | 所有事件触发概率 -15% |
| `tip` | 商机情报 | 3 点 | 1 趟 | 好感 Lv2 | 向目标聚落注入供需紧缺 (-30)，大幅拉高卖出价 |
| `location` | 位置情报 | 5 点 | 永久 | — | 解锁一个隐藏地图节点 |

---

## 数据点获取

每趟行程结束时由 `main.lua` 的 `handleTripFinish()` 自动调用：

```lua
Intel.earn_route_data(gameState, segCount, hadShortcut)
```

**计算规则**：
- 基础值 = `max(1, 路线段数)`
- 走了捷径 = 额外 +1
- 即每趟至少获得 1 点，长途多段路线获得更多

---

## 玩法影响详解

### 安全预警 → 事件调度器

**文件**: `events/event_scheduler.lua` `_try_pick()`

安全预警活跃时，事件触发概率直接降低 15%。基础概率 50%，叠加后降至约 35%。该减成在所有加成（捷径 +15%、危险区 +20%、疲劳 +10%）之后应用。

```
最终概率 = 基础50% + 上下文加成 + 技能加成 - 安全预警15%
```

### 天气预报 → 捷径危险缓解

**文件**: `events/event_scheduler.lua` `_try_pick()`

天气预报活跃且当前走捷径时，捷径的额外事件触发概率从 +15% 降至 +5%（减少 10%）。与安全预警可叠加。

```
走捷径时：50% + 15%(捷径) = 65% → 开启天气后：65% - 10% = 55%
同时开启安全预警：55% - 15% = 40%
```

### 价格情报 → 定价系统

**文件**: `economy/pricing.lua` `get_buy_price()` / `get_sell_price()`

价格情报记录了目标聚落 ID。在该聚落交易时：
- 买入价乘以 0.92（便宜 8%）
- 卖出价乘以 1.08（多赚 8%）

该修正在技能修正之后应用，与好感折扣、供需修正、技能加成共同生效。

**定价修正链**:
```
基础价 × 类目修正 × 好感折扣 × 供需修正 × 士气修正 × 技能修正 × 价格情报修正
```

### 商机情报 → 供需注入

**文件**: `settlement/intel.lua` `exchange()`（兑换时立即生效）

兑换商机情报时：
1. 随机选择一个聚落 + 商品组合（共 8 种预设组合）
2. 向目标聚落的 `supply_demand` 注入 -30（强烈供不应求）
3. 供需 -30 经定价系统换算后约等于卖出价 +30%

该供需值会随时间自然衰减（每趟行程 `decay_supply_demand()` 衰减 10%），所以商机是限时的。

**预设商机组合**:

| 聚落 | 紧缺商品 |
|------|---------|
| 钟楼书院 | 旧书 |
| 温室社区 | 净水 |
| 废墟营地 | 燃料芯 |
| 北穹塔台 | 电路板 |
| 温室社区 | 弹药 |
| 钟楼书院 | 废金属 |
| 废墟营地 | 罐头 |
| 北穹塔台 | 净水 |

### 位置情报 → 地图解锁

**文件**: `settlement/intel.lua` `exchange()`

兑换时从 `map_graph.json` 中筛选 `hidden: true` 且未被发现的节点，随机解锁一个。位置情报是一次性效果（duration=0），不存入活跃列表。

**当前隐藏节点**（3 个）:
- `underground_market` — 地下黑市
- `signal_bunker` — 信号掩体
- `old_archives` — 旧档案馆

---

## 地图情报图层

**文件**: `ui/screen_map.lua`

地图右上角有「📡 情报 ON/OFF」切换按钮，点击可开关情报图层显示。

### 显示内容

| 情报类型 | 地图表现 |
|---------|---------|
| 商机情报 | 目标聚落上显示脉冲光圈 + 💰 图标 + "急需XXX"红色标签 |
| 价格情报 | 目标聚落上显示 📊 图标 + "物价已掌握"金色标签 |
| 安全预警 | 切换按钮下方状态列表：🛡 安全预警(N趟) |
| 天气预报 | 切换按钮下方状态列表：🌤 天气预报(N趟) |

按钮右上角有红色角标显示当前活跃情报总数。

---

## 情报生命周期

```
兑换 exchange()
  │
  ├── 位置情报 → 立即生效（解锁节点），不存入活跃列表
  │
  └── 其他类型 → 存入 active_intel[]
                    │
                    ├── 玩法效果立即生效
                    │   - 安全预警/天气预报：事件调度器每次判定时检查
                    │   - 价格情报：每次计算交易价格时检查
                    │   - 商机情报：兑换时已注入供需（不依赖活跃状态）
                    │
                    └── 行程结束 tick_intel()
                          │
                          ├── trips_left -= 1
                          ├── trips_left > 0 → 保留
                          └── trips_left <= 0 → 移除
```

---

## API 参考

### 核心模块: `settlement/intel.lua`

| 函数 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `earn_route_data(state, segments, shortcut)` | state, number, boolean | — | 行程结束自动积累数据点 |
| `get_route_data(state)` | state | number | 获取当前数据点余额 |
| `get_available_types(state)` | state | table[] | 根据好感等级返回可兑换情报列表 |
| `exchange(state, intel_type)` | state, string | bool, string | 消耗数据点兑换情报 |
| `tick_intel(state)` | state | — | 行程结束过期处理 |
| `get_active_intel(state)` | state | table[] | 获取所有活跃情报 |
| `has_active(state, intel_type)` | state, string | boolean | 检查某类型是否有活跃情报 |
| `get_active_of_type(state, intel_type)` | state, string | table[] | 获取某类型的所有活跃情报 |
| `get_stats(state)` | state | number, number | 返回累计交换次数和数据点 |

### 集成点

| 文件 | 集成方式 | 说明 |
|------|---------|------|
| `main.lua:278-279` | `earn_route_data` + `tick_intel` | 行程结束时收集数据并过期 |
| `events/event_scheduler.lua:128-134` | `has_active("security"/"weather")` | 安全/天气情报降低事件概率 |
| `economy/pricing.lua:121-127,161-167` | `get_active_of_type("price")` | 价格情报影响买卖价 |
| `ui/screen_intel.lua` | 完整 UI | 情报交换站页面 |
| `ui/screen_map.lua` | 情报图层 | 地图上可视化情报 |
| `ui/screen_home.lua:445` | `get_route_data` | 首页显示数据点 |
| `ui/screen_debug.lua:397-423` | 统计显示 | 调试面板 |

---

## 设计备注

- 安全预警持续 2 趟是因为花费与天气预报相同（2 点），需要更长持续时间体现性价比差异
- 商机情报的供需注入在兑换瞬间完成，即使情报过期，供需效果仍在（只是会自然衰减 10%/趟）
- 位置情报花费最高（5 点），但效果永久，且隐藏节点通常有独特功能或稀有商品
- 好感 Lv1 解锁基础情报（天气/价格），Lv2 解锁高级情报（安全/商机），位置情报无好感限制但需在可兑换列表中手动判断（当前实现中位置情报不在 `get_available_types` 返回列表中，通过其他入口触发）

---

*最后更新: 2026-04-08*

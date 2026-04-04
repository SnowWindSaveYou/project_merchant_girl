# Phase 07 — 聚落、角色关系与长期成长

## 本阶段目标

把“为什么继续玩下去”这件事建立起来。

这阶段不再只是跑一趟赚钱，而是让玩家开始积累：

- 聚落关系
- 角色关系
- 货车成长
- 中长期目标

---

## 本阶段只关心什么

- 聚落好感
- 聚落功能解锁
- 角色关系成长
- 货车模块升级
- 长期目标投放

## 本阶段不要做什么

- 不做终局大剧情收束
- 不做全地图一次性开放

---

## 聚落系统先做功能，不先做内容量

每个聚落先必须具备 5 件事：

1. 身份差异
2. 商品差异
3. 订单差异
4. 好感奖励差异
5. **补给服务**（已实现基础版）

### 已实现：聚落补给服务

`screen_shop.lua` 已在商店页面顶部实现补给站功能：

| 服务 | 效果 | 费用 | 实现状态 |
|------|------|------|---------|
| **加油** | 燃料 +10 | 15 信用点 | ✅ 已实现 |
| **维修** | 耐久 +10 | 20 信用点 | ✅ 已实现 |
| **休整** | 清除所有负面状态 | 10 信用点 | ⬜ 待 Phase 06 负面状态系统实装 |

> 补给服务与货舱物品使用形成策略对比：聚落补给花钱方便，货舱物品（fuel_cell/metal_scrap）不花钱但占货位。

### 已实现：bell_tower 聚落数据

`state.lua` 中 4 个聚落均已注册（tower、greenhouse、ruins_camp、bell_tower），每个聚落包含 goodwill、visited、reputation 字段。

### 好感至少要影响

- 商品折扣
- 委托类型
- 剧情事件出现率
- 特殊功能解锁

### 好感等级解锁（待实现）

| 好感等级 | 阈值 | 解锁内容 |
|---------|------|---------|
| Lv1 | 30 | 专属商品购买权 |
| Lv2 | 60 | 休息区（剧情触发）+ 物价折扣 |
| Lv3 | 90 | 紧急呼叫权限 |

实现时在 `settlement/goodwill.lua` 中提供 `get_level(goodwill)` 函数，各系统按等级检查功能可用性。

---

## 角色关系系统

首版关系值只做一条总线，不要先拆太细。

### 关系值来源

- 一起完成跑商
- 关系事件选择
- 危险战斗后的互助
- 特定剧情节点

### 关系值作用

- 解锁对话
- 影响事件权重
- 解锁协同技能

---

## 货车成长系统

### 当前 state.lua 中已有的货车字段

```lua
truck = {
    fuel = 100, fuel_max = 100,
    durability = 80, durability_max = 100,
    cargo = {},         -- 货舱物品数组
    cargo_max = 8,      -- 货舱上限
    modules = {},       -- ⚠️ 已声明但未填充，当前未被任何代码读取
}
```

### 优先实现的 5 个模块

| 模块 | state 中的 key | 等级上限 | 升级成本 | 直接效果 | 被哪些系统使用 |
|------|---------------|---------|---------|---------|--------------|
| **引擎系统** | `engine` | Lv3 | 信用点 + circuit | Lv1: 速度+10% / Lv2: 燃耗-15% / Lv3: 两者 | flow.lua（行驶速度）、fuel 消耗计算 |
| **货舱扩容** | `cargo_bay` | Lv3 | 信用点 + metal_scrap | Lv1: 12格 / Lv2: 16格 / Lv3: 20格 | state.cargo_max、screen_cargo.lua |
| **探测雷达** | `radar` | Lv3 | 信用点 + circuit | Lv1: 隐藏点+15% / Lv2: 物价可视 / Lv3: 敌情预警 | 事件系统、地图系统、战斗系统 |
| **冷藏货柜** | `cold_storage` | Lv2 | 信用点 + metal_scrap | Lv1: 生鲜不腐坏 / Lv2: 接高价食品单 | 订单系统、货物保质计算 |
| **车顶机枪** | `turret` | Lv3 | 信用点 + ammo + metal_scrap | Lv1: 基础火力 / Lv2: +30%驱逐率 / Lv3: +50%保全率 | combat/ambush.lua |

### modules 数据结构建议

```lua
truck.modules = {
    engine       = { level = 0, max_level = 3 },
    cargo_bay    = { level = 0, max_level = 3 },
    radar        = { level = 0, max_level = 3 },
    cold_storage = { level = 0, max_level = 2 },
    turret       = { level = 0, max_level = 3 },
}
```

### 实现规则

- 每个模块**必须被至少一个系统读取**，否则等于没做
- 升级入口放在聚落商店（仅特定聚落可升级特定模块，如 turret 只能在 tower 或 ruins_camp 升级）
- 升级需要信用点 + 对应商品材料（从货舱扣除）
- 升级后立即生效，不需要等待

---

## 动态供需系统（本阶段新增）

### 背景

当前 `pricing.lua` 使用静态修正因子（如 tower 对 circuit 卖价 -0.15），物价固定不变。动态供需是让经济系统"活起来"的关键一步。

### 设计目标

- 每个聚落有独立**供需状态**（如"严重缺燃料" → 燃料收购价暴涨）
- 状态随时间和玩家行为动态变化：运来大量同类货物后供需趋于平衡，价格回落
- 升级探测雷达或通讯天线后可提前查看各聚落供需，实现信息套利

### 最小实现方案

```lua
-- 在 state.lua 的每个聚落中增加 supply_demand 字段
settlements = {
    tower = {
        goodwill = 0, visited = false, reputation = 100,
        supply_demand = {
            -- 正值 = 供过于求（价格低），负值 = 供不应求（价格高）
            circuit    =  20,  -- 技术派产出多，供大于求
            food_can   = -30,  -- 食物紧缺
            fuel_cell  = -10,
        },
    },
    -- ...
}
```

### 价格计算公式

```
实际价格 = 基础价格 × (1 + 静态修正) × (1 + 供需修正)
供需修正 = -supply_demand / 100    -- supply_demand=-30 → 修正+0.30（涨价30%）
```

### 供需变化规则

| 事件 | 供需变化 |
|------|---------|
| 玩家卖出 N 个商品 X | 聚落 X 的 supply_demand += N × 5 |
| 玩家买入 N 个商品 X | 聚落 X 的 supply_demand -= N × 3 |
| 时间流逝（每趟行程） | 所有供需值向 0 衰减 10% |
| 聚落特殊事件（干旱、故障） | 特定商品 supply_demand 大幅变化 |

### 信息可见性

| 雷达等级 | 可见信息 |
|---------|---------|
| 无雷达 | 只能看到当前聚落的供需 |
| Lv1 | 可看到已访问聚落的供需概况 |
| Lv2 | 可看到所有已知聚落的供需详情 + 价格预估 |
| Lv3 | 可看到供需趋势预测 |

### 文件建议

- 修改 `scripts/economy/pricing.lua` — 在 `get_price()` 中叠加供需修正
- 修改 `scripts/economy/pricing.lua` — 交易后调用供需更新函数
- 修改 `scripts/ui/screen_shop.lua` — 显示供需标签（紧缺/平衡/过剩）

---

## 中期目标投放

到这个阶段要开始明确告诉玩家：

- 去哪里能赚更多
- 什么聚落值得培养
- 哪条线索值得追
- 为什么要继续升级货车

### 典型目标

- 解锁北穹塔台高级通讯
- 追夜市传闻
- 找到隐藏商路入口
- 把货车升级到可跑危险区

---

## 文件建议

- `scripts/settlement/goodwill.lua`
- `scripts/settlement/unlock.lua`
- `scripts/character/relation.lua`
- `scripts/character/skills.lua`
- `scripts/truck/modules.lua`
- `scripts/truck/upgrade.lua`

---

## 通过标准

- [ ] 至少 4 个聚落功能差异成立
- [ ] 好感值能影响实际玩法结果
- [ ] 角色关系值能影响事件或技能
- [ ] 至少 5 个货车模块可升级并生效
- [ ] 玩家能明确看到中期成长目标

---

## 下一步

→ [08_integration_and_release.md](08_integration_and_release.md)

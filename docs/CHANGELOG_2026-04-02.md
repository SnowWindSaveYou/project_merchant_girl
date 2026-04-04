# 变更文档（2026-04-02）

## 范围

本次变更覆盖 `guaji_impl` 目录下的分阶段开发文档，目标是把实现路径从“线性接单即出发”修正为“地图节点网状探索 + 接单/路线解耦 + 行程中事件触发”的挂机网游流程。

---

## 关键变更摘要

### 1) 技术栈与工程基础修正
- 文档已明确基于 **UrhoX + Lua + NanoVG**。
- 存档策略改为：**单账号主存档 + 本地缓存**，不再强调多存档槽位。
- 新增 File API 与 clientCloud API 的职责划分与落地建议。

涉及文件：
- `00_tech_stack.md`

### 2) 主循环流程修正
- 明确“接单与出发解耦”。
- 加入 `MAP` 与 `ROUTE_PLAN` 状态。
- 强制要求：没有 `route_plan_id` 不可出发。

涉及文件：
- `01_core_loop.md`

### 3) 经济/路线系统重构为地图网状模型
- 新增大地图 Graph 模型：`Node + Edge`。
- 节点不再等同于聚落，新增 `resource/transit/hazard/story` 节点类型。
- 支持手动规划与自动规划（fastest/safest/balanced）。
- 接单后若目标节点已知，必须地图可视化高亮候选路线。
- 支持多订单并行持有、部分配送。

涉及文件：
- `04_economy_and_routes.md`

### 4) 行程事件触发时机修正
- 主事件触发从“结算后”迁移为“行程中（TRAVELLING）”。
- 新增事件调度层，按时间片/里程节点检查。
- 补充节点类型与边类型上下文筛选。

涉及文件：
- `05_events_and_narrative.md`

### 5) 战斗入口与地图节点联动
- 资源点探索战限定由 `resource` 节点进入。
- 非所有节点可进入探索战，增加节点状态约束（可探索/清空/刷新）。

涉及文件：
- `06_combat_and_resource_points.md`

### 6) 新增“途经自动交单”规则
- 路线途经多个订单目的地时自动提交订单。
- 定义了触发条件、执行顺序、冲突处理（deadline 优先、货物不足、超时）。

涉及文件：
- `04_economy_and_routes.md`

### 7) 新增“远方情报节点 + 雾区发现”规则
- 允许朝情报目标出发，即使途中存在未知区域。
- 雾区采用“延迟可知 + 步长发现 + 保底可达”机制。
- 对未知节点发现后的停靠/继续/改道进行规范。

涉及文件：
- `04_economy_and_routes.md`

### 8) 新增“离线发现节点”挂机规则
- 离线期间可发现节点，但不做实时交互。
- 使用预设自动策略（continue/safe/loot）推进。
- 上线后通过离线结算摘要回放发现与改道结果。
- 增加一致性约束（seed + step index 可重放）。

涉及文件：
- `04_economy_and_routes.md`

---

## 本次打包文件清单

- `00_tech_stack.md`
- `01_core_loop.md`
- `02_data_and_save.md`
- `03_ui_framework.md`
- `04_economy_and_routes.md`
- `05_events_and_narrative.md`
- `06_combat_and_resource_points.md`
- `07_settlement_and_progression.md`
- `08_integration_and_release.md`
- `CHANGELOG_2026-04-02.md`

---

## 备注

如果需要给程序组直接执行，可在下一步输出：
- 按文件的“函数级返工清单”
- 或“联调验收脚本（按状态与事件序列）”

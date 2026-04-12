# 《末世行商》随机事件配置表
### 程序 / 数值 / 文案共用版（配置导向）

---

## 一、文档目标

本文件不再以“文案展示稿”为主，而是以**可转 CSV / JSON / ScriptableObject / DataTable** 的结构来维护随机事件。

目标：

- 程序可以直接按字段做解析
- 数值可以直接调权重、冷却、奖励与风险
- 文案可以在不改结构的前提下替换描述文本
- 后续链式事件、条件事件、地区事件都能继续扩展

---

## 二、推荐数据结构

### 1. 主表字段

| 字段名 | 类型 | 说明 |
|------|------|------|
| `event_id` | string | 唯一 ID，格式如 `EVT_001` |
| `event_name` | string | 事件显示名 |
| `phase` | enum | `early / mid / late / all` |
| `pool` | enum | `road / trade / encounter / danger / bond / lore / special` |
| `scene` | enum | `drive / settlement / camp / resource_point / route_node / radio` |
| `weight` | int | 基础权重 |
| `cooldown_run` | int | 事件触发后，至少隔多少趟跑商才能再进池 |
| `trigger_tags` | string[] | 触发标签，如 `route_danger`, `cargo_food` |
| `required_flags` | string[] | 需要存在的状态旗标 |
| `forbidden_flags` | string[] | 不能存在的状态旗标 |
| `summary` | string | 给策划/程序看的简要摘要 |
| `choice_set_id` | string | 关联选项组 ID |
| `result_set_id` | string | 关联结果组 ID |
| `next_event_id` | string | 后续链式事件 ID，没有则留空 |
| `remark` | string | 补充说明 |

### 2. 选项组字段

| 字段名 | 类型 | 说明 |
|------|------|------|
| `choice_set_id` | string | 选项组 ID |
| `choice_id` | string | 选项 ID，如 `A / B / C` |
| `choice_text` | string | 前端显示文本 |
| `show_condition` | string[] | 满足后才显示的条件 |
| `result_key` | string | 指向结果配置 |

### 3. 结果字段推荐写法

统一采用“效果操作列表”思路，便于程序解释执行：

| 字段名 | 类型 | 说明 |
|------|------|------|
| `result_key` | string | 结果 ID |
| `ops` | string[] | 操作集合，如 `add_credit:40`, `add_time:10`, `add_goods:food:2` |
| `risk_desc` | string | 风险备注 |
| `reward_desc` | string | 收益备注 |
| `set_flags` | string[] | 写入旗标 |
| `clear_flags` | string[] | 移除旗标 |

---

## 三、枚举与标签规范

### 1. 事件池枚举 `pool`

- `road`：道路、天气、地形、路径判断
- `trade`：买卖、插单、价格波动、货损纠纷
- `encounter`：路遇 NPC、聚落居民、临时委托
- `danger`：掠夺者、故障、天气灾害、受损风险
- `bond`：双主角关系、日常互动、分歧事件
- `lore`：广播、档案、旧文明痕迹、主线碎片
- `special`：大型联动事件、终局前置、链式高价值事件

### 2. 场景枚举 `scene`

- `drive`：车辆行驶中
- `settlement`：聚落内或聚落边缘
- `camp`：夜晚营地 / 休息阶段
- `resource_point`：停车探索点
- `route_node`：特殊路段节点
- `radio`：无线电 / 被动播报

### 3. 常用触发标签 `trigger_tags`

- `route_safe`
- `route_normal`
- `route_danger`
- `route_black_market`
- `route_rain`
- `route_night`
- `route_winter`
- `route_summer`
- `arrive_settlement`
- `cargo_food`
- `cargo_culture`
- `cargo_fresh`
- `cargo_heavy`
- `has_radar`
- `has_weapon`
- `has_cold_storage`
- `goodwill_tower_2`
- `goodwill_greenhouse_2`
- `goodwill_academy_1`
- `taoxia_arc_mid`
- `linli_arc_mid`
- `high_reputation`
- `before_finale`

### 4. 常用结果操作 `ops`

- `add_credit:x`
- `add_fuel:x`
- `add_goods:type:count`
- `lose_goods:type:count`
- `add_goodwill:faction:value`
- `add_relation:value`
- `add_time:min`
- `add_damage:value`
- `repair_damage:value`
- `unlock_route:route_id`
- `unlock_clue:clue_id`
- `unlock_event:event_id`
- `set_flag:flag_id`
- `start_combat:combat_id`
- `spawn_order:order_id`

---

## 四、首版事件主配置表（50 条）

> 说明：为了保持表结构紧凑，选项与结果采用“概要编码 + 结果组 ID”写法；正式落库时可拆成三张表：`event_main`、`event_choice`、`event_result`。

| event_id | event_name | phase | pool | scene | weight | cooldown_run | trigger_tags | required_flags | forbidden_flags | choice_set_id | result_set_id | next_event_id | summary | remark |
|------|------|------|------|------|------:|------:|------|------|------|------|------|------|------|------|
| EVT_001 | 路边罐头箱 | early | road | route_node | 100 | 2 | route_safe | - | - | CH_EVT_001 | RS_EVT_001 |  | 基础拾取教学事件 | 小收益小风险 |
| EVT_002 | 油表误差 | early | danger | drive | 75 | 3 | route_safe | - | - | CH_EVT_002 | RS_EVT_002 |  | 燃料与故障判断 | 林砾倾向事件 |
| EVT_003 | 好心搭车人 | early | encounter | settlement | 80 | 2 | arrive_settlement | - | - | CH_EVT_003 | RS_EVT_003 |  | 居民温情与好感教学 | 前期低风险 |
| EVT_004 | 便宜得反常的电池 | early | trade | settlement | 70 | 3 | route_black_market | - | - | CH_EVT_004 | RS_EVT_004 |  | 黑市试货事件 | 价格判断 |
| EVT_005 | 路标被挪动了 | early | road | route_node | 85 | 2 | route_normal | - | - | CH_EVT_005 | RS_EVT_005 |  | 路线分叉判断 | 有雷达收益更稳 |
| EVT_006 | 窗边纸条 | early | bond | camp | 65 | 2 | route_normal | - | - | CH_EVT_006 | RS_EVT_006 |  | 轻关系增温 | 可提高后续剧情权重 |
| EVT_007 | 旧收音机杂音 | early | lore | radio | 60 | 2 | route_normal | - | - | CH_EVT_007 | RS_EVT_007 |  | 广播碎片事件 | 鸣砂前置氛围 |
| EVT_008 | 水泵紧急件 | early | trade | settlement | 80 | 2 | arrive_settlement | - | - | CH_EVT_008 | RS_EVT_008 |  | 插单与调度教学 | 温室前期核心事件 |
| EVT_009 | 小型掠夺试探 | early | danger | drive | 70 | 3 | route_danger | - | - | CH_EVT_009 | RS_EVT_009 |  | 车载迎击教学事件 | 可接战斗系统 |
| EVT_010 | 货箱里的玩偶 | early | bond | drive | 55 | 4 | cargo_food | - | flag_doll_resolved | CH_EVT_010 | RS_EVT_010 | EVT_023 | 玩偶链起点 | 关键链式事件 |
| EVT_011 | 塔台求购胶卷 | early | trade | settlement | 60 | 2 | cargo_culture | - | - | CH_EVT_011 | RS_EVT_011 |  | 文化品套利 | 塔台 / 书院抉择 |
| EVT_012 | 轮胎陷泥 | early | road | route_node | 78 | 2 | route_rain | - | - | CH_EVT_012 | RS_EVT_012 |  | 雨路通行事件 | 耐久与耗时权衡 |
| EVT_013 | 多给了一张票据 | early | encounter | settlement | 62 | 2 | arrive_settlement | - | - | CH_EVT_013 | RS_EVT_013 | EVT_020 | 小道德事件 | 可接票据线 |
| EVT_014 | 夜里没睡好 | early | bond | camp | 58 | 3 | route_normal | - | - | CH_EVT_014 | RS_EVT_014 |  | 疲劳与休息教学 | 状态系统入口 |
| EVT_015 | 便携灯泡坏了 | early | danger | drive | 66 | 3 | route_night | - | - | CH_EVT_015 | RS_EVT_015 |  | 夜路资源选择 | 电池消耗 |
| EVT_016 | 黑市假药 | mid | trade | settlement | 65 | 3 | route_black_market | - | - | CH_EVT_016 | RS_EVT_016 |  | 中期黑市骗局 | 好感可降低风险 |
| EVT_017 | 维修手册缺页 | mid | lore | resource_point | 45 | 4 | route_normal | linli_arc_mid | flag_manual_complete | CH_EVT_017 | RS_EVT_017 | EVT_040 | 林砾个人线节点 | 链式剧情 |
| EVT_018 | 失踪的送信员 | mid | encounter | route_node | 55 | 3 | route_normal | - | - | CH_EVT_018 | RS_EVT_018 |  | 救援 / 物资抉择 | 中期支线 |
| EVT_019 | 热浪中的生鲜 | mid | danger | drive | 72 | 3 | route_summer,cargo_fresh | - | - | CH_EVT_019 | RS_EVT_019 |  | 生鲜保鲜考验 | 冷藏模块联动 |
| EVT_020 | 夜市传闻 | mid | lore | settlement | 48 | 4 | arrive_settlement | taoxia_arc_mid | flag_night_market_found | CH_EVT_020 | RS_EVT_020 | EVT_039 | 陶夏个人线节点 | 夜市链 |
| EVT_021 | 误闯静默区 | mid | road | route_node | 52 | 3 | route_danger | - | - | CH_EVT_021 | RS_EVT_021 |  | 风险与隐藏收益 | 探索偏好 |
| EVT_022 | 塔台的秘密电报 | mid | lore | settlement | 40 | 5 | arrive_settlement | goodwill_tower_2 | - | CH_EVT_022 | RS_EVT_022 | EVT_033 | 韩策秘密线 | 主线中段前置 |
| EVT_023 | 围墙外的孩子们 | mid | encounter | settlement | 55 | 3 | arrive_settlement | - | - | CH_EVT_023 | RS_EVT_023 |  | 温柔型送礼事件 | 可承接玩偶链 |
| EVT_024 | 货舱异响 | mid | danger | drive | 70 | 3 | cargo_heavy | - | - | CH_EVT_024 | RS_EVT_024 |  | 高载重风险 | 单车经营感 |
| EVT_025 | 假地图与真入口 | mid | road | route_node | 46 | 4 | route_black_market | flag_map_fragments_2 | flag_lost_route_found | CH_EVT_025 | RS_EVT_025 | EVT_048 | 隐藏路线链节点 | 高价值支线 |
| EVT_026 | 钟声提前响起 | mid | lore | settlement | 44 | 4 | route_night | - | - | CH_EVT_026 | RS_EVT_026 |  | 书院神秘氛围 | 可挂额外剧情 |
| EVT_027 | 旧高速残桥 | mid | road | route_node | 63 | 3 | route_danger | - | - | CH_EVT_027 | RS_EVT_027 |  | 过桥风险计算 | 零件消耗点 |
| EVT_028 | 沈禾的加急口信 | mid | encounter | settlement | 58 | 4 | arrive_settlement | goodwill_greenhouse_2 | - | CH_EVT_028 | RS_EVT_028 |  | 价值观型委托 | 温室线关键选择 |
| EVT_029 | 陶夏的冲动交易 | mid | bond | settlement | 50 | 3 | route_black_market | - | - | CH_EVT_029 | RS_EVT_029 | EVT_020 | 陶夏直觉事件 | 小概率高回报 |
| EVT_030 | 林砾的过度保守 | mid | bond | route_node | 52 | 3 | route_danger | - | - | CH_EVT_030 | RS_EVT_030 |  | 双主角分歧事件 | 关系塑形 |
| EVT_031 | 黑雨将至 | late | danger | drive | 45 | 5 | route_danger | - | - | CH_EVT_031 | RS_EVT_031 |  | 后期天气灾害 | 强风险控制 |
| EVT_032 | 失控搬运机 | late | danger | resource_point | 48 | 4 | route_danger | - | - | CH_EVT_032 | RS_EVT_032 |  | 资源点战斗事件 | 可挂探索战 |
| EVT_033 | 鸣砂的特别播报 | late | special | radio | 28 | 6 | route_normal | flag_secret_telegram_done | flag_radio_target_done | CH_EVT_033 | RS_EVT_033 | EVT_034 | 后期主线引导 | 重要广播链 |
| EVT_034 | 高塔方向的光 | late | special | route_node | 26 | 6 | route_danger | flag_radio_target_done | flag_tower_beacon_seen | CH_EVT_034 | RS_EVT_034 | EVT_050 | 终局前氛围节点 | 高塔线 |
| EVT_035 | 伍拾七的旧账 | late | encounter | settlement | 36 | 5 | route_black_market | flag_57_goodwill_high | - | CH_EVT_035 | RS_EVT_035 |  | 黑市核心权限事件 | 后期个人线 |
| EVT_036 | 塔台断电 | late | special | settlement | 30 | 6 | arrive_settlement | high_reputation | flag_tower_blackout_done | CH_EVT_036 | RS_EVT_036 |  | 大型公共危机 | 联盟感建立 |
| EVT_037 | 书院失火档案 | late | lore | settlement | 32 | 5 | arrive_settlement | goodwill_academy_1 | flag_archive_fire_done | CH_EVT_037 | RS_EVT_037 |  | 核心档案抢救 | 世界观回报高 |
| EVT_038 | 温室疫病苗头 | late | danger | settlement | 34 | 5 | arrive_settlement | flag_greenhouse_arc_mid | - | CH_EVT_038 | RS_EVT_038 |  | 聚落危机处理 | 农业线高权重 |
| EVT_039 | 孟回的最后一张地图 | late | special | settlement | 24 | 6 | arrive_settlement | flag_night_market_found | flag_last_map_bought | CH_EVT_039 | RS_EVT_039 | EVT_048 | 隐藏终局捷径线 | 夜市链回收 |
| EVT_040 | 引擎的异常共振 | late | danger | drive | 42 | 5 | cargo_heavy | flag_manual_page_found | - | CH_EVT_040 | RS_EVT_040 |  | 货车寿命感事件 | 林砾线后段 |
| EVT_041 | 白述的试探 | mid | lore | settlement | 50 | 4 | arrive_settlement | goodwill_academy_1 | - | CH_EVT_041 | RS_EVT_041 |  | 价值观对话 | 可改结局权重 |
| EVT_042 | 车窗上的霜花 | early | bond | camp | 42 | 3 | route_winter | - | - | CH_EVT_042 | RS_EVT_042 |  | 纯氛围关系事件 | 冬季版贴贴 |
| EVT_043 | 路边旧广告牌 | early | lore | route_node | 48 | 2 | route_normal | - | - | CH_EVT_043 | RS_EVT_043 |  | 旧文明碎片 | 低强度世界观 |
| EVT_044 | 货损索赔 | mid | trade | settlement | 57 | 3 | arrive_settlement | - | - | CH_EVT_044 | RS_EVT_044 |  | 交付结算摩擦 | 议价与信誉联动 |
| EVT_045 | 暂时同行的护卫 | mid | encounter | route_node | 53 | 3 | route_danger | - | - | CH_EVT_045 | RS_EVT_045 |  | 花钱买稳妥 | 高风险路线缓冲 |
| EVT_046 | 齿团偷吃货物 | mid | bond | drive | 35 | 4 | route_normal | flag_pet_unlocked | - | CH_EVT_046 | RS_EVT_046 |  | 宠物轻事件 | DLC / 拓展可开 |
| EVT_047 | 聚落联合求援 | late | special | settlement | 25 | 6 | arrive_settlement | high_reputation,before_finale | flag_dual_help_done | CH_EVT_047 | RS_EVT_047 |  | 后期大型抉择 | 双聚落关系分流 |
| EVT_048 | 失落商路的起点 | late | special | route_node | 22 | 6 | route_danger | flag_hidden_route_ready | flag_lost_route_found | CH_EVT_048 | RS_EVT_048 | EVT_050 | 终局商路入口 | 高价值链 |
| EVT_049 | 她们想留下吗 | late | bond | camp | 24 | 6 | route_normal | before_finale | flag_end_talk_done | CH_EVT_049 | RS_EVT_049 |  | 结局倾向对话 | 关系终局分流 |
| EVT_050 | 云海高塔的门 | late | special | route_node | 15 | 99 | route_danger | flag_tower_beacon_seen,flag_lost_route_found | flag_final_gate_opened | CH_EVT_050 | RS_EVT_050 |  | 终局总开关事件 | 只触发一次 |

---

## 五、选项与结果写法示例

### 示例 A：`EVT_009` 小型掠夺试探

#### `event_choice`

| choice_set_id | choice_id | choice_text | show_condition | result_key |
|------|------|------|------|------|
| CH_EVT_009 | A | 加速甩开 | - | RES_EVT_009_A |
| CH_EVT_009 | B | 停车威慑 | has_weapon | RES_EVT_009_B |
| CH_EVT_009 | C | 绕路撤离 | - | RES_EVT_009_C |

#### `event_result`

| result_key | ops | reward_desc | risk_desc | set_flags | clear_flags |
|------|------|------|------|------|------|
| RES_EVT_009_A | add_fuel:-8,add_time:3 | 快速脱离 | 少量燃料损耗 | - | - |
| RES_EVT_009_B | start_combat:ambush_light,add_relation:1 | 若车顶机枪成型则能立威 | 若武装不足可能掉货 | set_flag:combat_intro_done | - |
| RES_EVT_009_C | add_time:10 | 最稳定 | 错过窗口 | - | - |

### 示例 B：`EVT_020` 夜市传闻

| choice_set_id | choice_id | choice_text | show_condition | result_key |
|------|------|------|------|------|
| CH_EVT_020 | A | 深入打听 | - | RES_EVT_020_A |
| CH_EVT_020 | B | 当作玩笑 | - | RES_EVT_020_B |
| CH_EVT_020 | C | 先记在账本里 | - | RES_EVT_020_C |

| result_key | ops | reward_desc | risk_desc | set_flags | clear_flags |
|------|------|------|------|------|------|
| RES_EVT_020_A | unlock_clue:night_market_1,set_flag:flag_night_market_rumor | 获得夜市线索 | 无直接收益 | set_flag:flag_night_market_rumor | - |
| RES_EVT_020_B | add_time:0 | 不影响当前节奏 | 错失支线推进 | - | - |
| RES_EVT_020_C | add_relation:1 | 延后推进但保留线索感 | 收益较慢 | set_flag:flag_night_market_note | - |

---

## 六、建议拆表方式

正式导表时建议拆成 4 张表：

### 1. `event_main`

- 放事件基础信息、权重、池子、冷却、触发条件、链路关系

### 2. `event_choice`

- 每个事件多行
- 用 `choice_set_id` 关联

### 3. `event_result`

- 每个结果一行
- `ops` 解析成实际效果数组

### 4. `event_text`

- 放正文描述、按钮文案、结果提示文案
- 方便本地化和后期文案修订

---

## 七、链式事件清单

| 链名 | 起点 | 中段 | 终点 | 说明 |
|------|------|------|------|------|
| 玩偶线 | EVT_010 | EVT_023 |  | 偏温情与聚落居民回馈 |
| 林砾手册线 | EVT_017 | EVT_040 |  | 林砾个人成长与货车生命感 |
| 夜市线 | EVT_020 | EVT_039 |  | 陶夏个人线与隐藏交易点 |
| 地图碎片线 | EVT_025 | EVT_048 | EVT_050 | 商路隐藏线与终局线路 |
| 鸣砂广播线 | EVT_022 | EVT_033 | EVT_034 | 主线广播导引 |

---

## 八、程序侧实现建议

- 权重计算顺序：`基础权重 -> 阶段过滤 -> 场景过滤 -> tag/flag 过滤 -> 动态修正`
- 动态修正来源：聚落好感、角色关系、车辆模块、季节、路线熟练度
- 同类事件去重：同一 `pool` 在连续 2 次跑商内尽量不重复
- 战斗挂接：`start_combat:ambush_light` 进入车载迎击；`start_combat:resource_small` 进入探索战
- 文本层和数值层分离：表内 `summary` 只给策划/程序，前端实际文本建议单独本地化

---

## 九、路点事件池系统（2026-04-11 新增）

### 9.1 背景

上方 §四 的 50 条设计事件主要面向行驶中/聚落场景。实际代码中，聚落事件由 `settlement_event_pool.lua` + `settlement_events.json` 承载，但**非聚落节点**（resource / hazard / transit / story）此前没有对应的事件系统——到达后只有篝火可用。

### 9.2 路点事件池（Waypoint Event Pool）

新增独立事件池，专门服务非聚落节点的到达事件。

| 属性 | 聚落事件池 | 路点事件池 |
|------|----------|----------|
| 代码 | `settlement_event_pool.lua` | `waypoint_event_pool.lua` |
| 配置 | `settlement_events.json` | `waypoint_events.json` |
| 触发概率 | 30% | 25% |
| 筛选维度 | `settlement` (string) | `node_types` (string[]) + 可选 `node_ids` (string[]) |
| 冷却存储 | `state._settlement_event_cooldowns` | `state._waypoint_event_cooldowns` |
| 触发结果 | `state.flow.pending_settlement_event` | `state.flow.pending_waypoint_event` |
| 冷却推进 | `finish_trip()` 中调用 | `finish_trip()` 中调用 |

### 9.3 当前事件清单（15 条）

| ID | 名称 | node_types | weight | cooldown | 核心选项 |
|----|------|-----------|--------|----------|---------|
| WPT_R01 | 拾荒者交易 | resource | 60 | 4 | 交换物资 / 交换情报 / 无视 |
| WPT_R02 | 设备故障 | resource | 50 | 5 | 花时间修理 / 拆零件带走 |
| WPT_R03 | 隐藏物资 | resource | 40 | 6 | 全部带走 / 留给后人（+林砾关系） |
| WPT_R04 | 竞争者 | resource | 45 | 5 | 各搜各的 / 合作平分 |
| WPT_R05 | 旧地图碎片 | resource | 35 | 7 | 研究地图 / 收藏 |
| WPT_H01 | 求救信号 | hazard | 55 | 4 | 前去救援（+20信用/+林砾关系） / 不去 |
| WPT_H02 | 恶劣天气 | hazard | 50 | 4 | 车里等 / 废墟躲避（+伤害+金属） |
| WPT_H03 | 变异巢穴 | hazard | 40 | 5 | 绕路 / 穿过搜刮（+伤害+药品） |
| WPT_H04 | 断路抉择 | hazard | 50 | 4 | 清理路障 / 走小路（+伤害） |
| WPT_H05 | 迷雾中的声音 | hazard | 35 | 6 | 循声查看（+电路/燃料） / 别管 |
| WPT_T01 | 过路商人 | transit | 60 | 4 | 买物资（-8信用） / 打听消息 / 无视 |
| WPT_T02 | 路标留言 | transit | 45 | 5 | 阅读（+5信用） / 也留一条（+林砾关系） |
| WPT_T03 | 废弃营地遗迹 | transit | 40 | 5 | 翻找物资 / 用篝火休息（-5疲劳） |
| WPT_S01 | 旧日信件 | story | 50 | 6 | 读给同伴（+双关系） / 收藏 |
| WPT_S02 | 广播残响 | story | 45 | 6 | 追溯信号源（+8信用） / 记录频率 |

### 9.4 ops 规范

路点事件使用与 `event_executor.lua` 一致的操作码：

```
add_goods:item_id:count     -- 获得物品（替代设计文档中的 add_cargo）
consume_goods:item_id:count -- 消耗物品（替代设计文档中的 remove_cargo）
add_damage:value            -- 货车受损（替代设计文档中的 add_truck_damage）
add_credits:value           -- 增减信用点
add_fatigue:value           -- 增减疲劳（注：executor 暂未实现，打印 Unknown 但不崩溃）
add_relation_linli:value    -- 林砾关系
add_relation_taoxia:value   -- 陶夏关系
```

### 9.5 与设计文档的对应关系

上方 §四 的 50 条 EVT 事件中，部分与路点事件池有功能重叠：

| 设计事件 | 路点替代 | 说明 |
|---------|---------|------|
| EVT_001 路边罐头箱 | WPT_R03 隐藏物资 | 类似的搜刮判断 |
| EVT_005 路标被挪动了 | WPT_T02 路标留言 | 路标交互 |
| EVT_007 旧收音机杂音 | WPT_S02 广播残响 | 广播碎片 |
| EVT_018 失踪的送信员 | WPT_H01 求救信号 | 救援抉择 |

后续可将设计事件逐步迁移到路点配置中，实现完整覆盖。

### 9.6 代码文件索引

| 文件 | 路径 | 说明 |
|------|------|------|
| 路点事件池逻辑 | `scripts/events/waypoint_event_pool.lua` | filter → pick → check_on_arrival → tick_cooldowns |
| 路点事件配置 | `assets/configs/waypoint_events.json` | 15 条事件定义 |
| 接入 - 流程控制 | `scripts/core/flow.lua` | handle_node_arrival + finish_trip |
| 接入 - 首页 UI | `scripts/ui/screen_home.lua` | 非聚落节点按钮区域 |

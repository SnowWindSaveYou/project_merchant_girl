# 《末世行商》地图节点总览

> 本文档整理自 `scripts/map/world_graph.lua`、`scripts/settlement/factions.lua`、`scripts/core/state.lua` 及各聚落专属系统模块。

---

## 一、节点统计

共 **40 个节点**，分布在 900x600 坐标空间内。

| 节点类型 | 英文标识 | 数量 | 说明 |
|---------|---------|------|------|
| 聚落 | settlement | 9 | 4 主聚落 + 4 前哨站 + 1 隐藏聚落，可交易/补给/剧情 |
| 中转站 | transit | 6 | 补给和路线分岔点 |
| 资源点 | resource | 6 | 可探索获取稀有物资 |
| 危险区 | hazard | 6 | 高风险高收益 |
| 故事节点 | story | 4 | 叙事触发点 |
| 边境探索 | frontier | 6 | 高危险环形探索链 |
| P4 预留 | transit | 3 | 为铁锁商队/静潮社预留 |
| 隐藏 | 混合 | 3 | 需特殊方式解锁 |

---

## 二、四大势力

| 势力 | ID | 图标 | 首都 | 前哨站 | 领地节点 | 核心产出 | 核心缺口 |
|------|-----|------|------|--------|---------|---------|---------|
| 农耕派 | farm | 🌾 | 温室社区 | 外围农场 | 灌溉水渠、蘑菇洞窟 | 罐头、种子、净水、草药 | 零件、燃料、农机工具 |
| 技术派 | tech | ⚙ | 北穹塔台 | 穹顶哨站 | 太阳能田、气象站废墟 | 电池、电路板、导航模组 | 食物、文化品、药品 |
| 拾荒帮 | scav | 🔧 | 废墟游民营地 | 地铁营地 | 废车场、下水道迷宫 | 稀有废品、地图碎片、旧物 | 食物、药品、能源 |
| 宗教团 | scholar | 📖 | 钟楼书院 | 旧教堂 | 碑林花园、印刷厂遗址 | 书籍、胶卷、旧唱片、艺术品 | 工业品、燃料、保存设备 |

---

## 三、全部节点一览

### 农耕派领地（SW 区域）— 4 节点

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| greenhouse | 温室社区 | settlement | (80,400) | 以旧生态穹顶为核心的农业聚落 |
| greenhouse_farm | 外围农场 | settlement | (120,530) | 温室社区南侧的露天耕地 |
| irrigation_canal | 灌溉水渠 | resource | (50,310) | 旧灌溉系统遗迹，可收集净水和管材 |
| mushroom_cave | 蘑菇洞窟 | resource | (30,480) | 温室西南的天然洞穴，生长夜光蘑菇 |

### 技术派领地（N 区域）— 4 节点

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| tower | 北穹塔台 | settlement | (500,80) | 建在旧防空观测塔群上的技术聚落 |
| dome_outpost | 穹顶哨站 | settlement | (380,140) | 塔台前沿观测站 |
| solar_field | 太阳能田 | resource | (600,50) | 灾前光伏阵列，残存可用面板 |
| weather_station | 气象站废墟 | hazard | (420,30) | 山顶废弃气象站，风暴频发 |

### 拾荒帮领地（S/SE 区域）— 4 节点

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| ruins_camp | 废墟游民营地 | settlement | (550,450) | 塌陷商场周边的流动型拾荒聚落 |
| metro_camp | 地铁营地 | settlement | (620,520) | 废弃地铁隧道内的拾荒者据点 |
| junkyard | 废车场 | resource | (480,530) | 锈蚀车辆堆积如山，金属和零件宝库 |
| sewer_maze | 下水道迷宫 | hazard | (590,560) | 错综复杂的旧排水系统，容易迷路 |

### 学者派领地（E 区域）— 4 节点

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| bell_tower | 钟楼书院 | settlement | (750,250) | 围绕旧钟楼建立的学者聚落 |
| old_church | 旧教堂 | settlement | (820,350) | 废弃教堂改造的分院 |
| stone_garden | 碑林花园 | story | (800,180) | 刻满灾前文字的石碑群落 |
| printing_ruins | 印刷厂遗址 | resource | (870,280) | 旧印刷厂，偶有完好纸张和墨水 |

### 中心走廊 — 6 节点

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| crossroads | 旧公路交叉口 | transit | (280,250) | 半废弃高速匝道，地图中心枢纽 |
| old_warehouse | 废弃仓库 | resource | (350,420) | 锈蚀铁皮仓库群 |
| signal_relay | 信号中继站 | story | (450,280) | 废弃通信中继站，偶有微弱信号 |
| dust_station | 沙尘驿站 | transit | (340,330) | 沙尘暴频发的中途补给点 |
| scrap_yard | 碎片场 | transit | (480,380) | 路旁堆满碎片的歇脚点 |
| overgrown_bridge | 藤桥 | transit | (560,300) | 藤蔓覆盖的旧立交桥 |

### 原有功能节点 — 6 节点

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| danger_pass | 塌陷高架 | hazard | (180,120) | 断裂高架桥段，温室↔塔台捷径 |
| dry_riverbed | 干涸河床 | transit | (650,400) | 干涸河道，东南区域枢纽 |
| radar_hill | 雷达山丘 | resource | (650,120) | 山顶废弃军用雷达站 |
| sunken_plaza | 沉降广场 | hazard | (400,500) | 地面塌陷凹地，变异生物出没 |
| hermit_cave | 隐士洞窟 | story | (150,520) | 隐居者洞穴，旧时代秘密 |
| wind_gap | 风口隘道 | hazard | (700,150) | 山间狭窄风口，强风区 |

### P4 预留节点 — 3 节点

| ID | 名称 | 类型 | 坐标 | 描述 | 特殊 |
|----|------|------|------|------|------|
| toll_gate | 旧收费站 | transit | (200,350) | 旧高速收费站遗迹 | — |
| old_logistics | 物流园废墟 | transit | (300,500) | 灾前快递分拣中心 | — |
| mist_valley | 雾谷 | transit | (150,250) | 终年弥漫浓雾的山谷 | explore_flag: mist_valley_accessible |

> `mist_valley` 需设置旗标 `mist_valley_accessible` 后才可探索，为 P4 铁锁商队/静潮社剧情入口。

### 边境探索链 — 6 节点

高危险高收益的环形探索链，沿地图边缘分布：

| ID | 名称 | 类型 | 坐标 | 描述 |
|----|------|------|------|------|
| dead_forest | 枯木林 | hazard | (50,150) | 辐射枯死的森林，地面覆盖灰烬 |
| toxic_marsh | 毒沼泽 | hazard | (30,350) | 有毒气体弥漫的低洼湿地 |
| military_bunker | 军事碉堡 | resource | (100,50) | 灾前军事工事，可能有武器弹药 |
| crater_rim | 弹坑边缘 | hazard | (350,30) | 巨大撞击坑边缘，地形极不稳定 |
| broadcast_tower | 广播塔废墟 | story | (750,50) | 旧广播塔，仍偶尔发出自动信号 |
| rust_bridge | 铁锈大桥 | hazard | (880,450) | 锈蚀殆尽的跨河大桥 |

### 隐藏节点 — 3 节点

不在探索面板中显示，需通过特殊方式解锁：

| ID | 名称 | 类型 | 坐标 | 解锁方式 |
|----|------|------|------|---------|
| underground_market | 地下黑市 | settlement | (560,580) | 伍拾七 NPC 对话 (好感50+) 或 位置情报 |
| signal_bunker | 信号掩体 | story | (720,100) | 白述 NPC 对话 (好感45+) 或 位置情报 |
| old_archives | 旧档案馆 | resource | (850,500) | 废墟营地聚落事件 (好感40+) 或 位置情报 |

---

## 四、主聚落详情（4 个）

### 1. 温室社区 (greenhouse)

| 属性 | 值 |
|------|-----|
| **势力** | 农耕派 (farm) 🌾 |
| **坐标** | (80, 400) |
| **描述** | 以旧生态穹顶为核心的农业聚落 |
| **领袖** | 沈禾 — 务实温和，优先保障所有人都有口粮 |
| **视觉特征** | 玻璃穹顶、潮湿管道、层架温室、手写作物牌 |
| **初始好感** | 10（已访问） |
| **开局可见** | 是 |

**专属系统 — 培育农场**（详见原文档）

**相邻节点（扩展后）**：
| 目标 | 路线类型 | 耗时 | 燃料 | 危险度 |
|------|---------|------|------|--------|
| 旧公路交叉口 | 主干道 | 50s | 8 | safe |
| 塌陷高架 | 捷径 | 25s | 6 | danger |
| 隐士洞窟 | 小径 | 40s | 7 | normal |
| 外围农场 | 小径 | 25s | 4 | safe |
| 灌溉水渠 | 小径 | 20s | 3 | safe |
| 蘑菇洞窟 | 小径 | 25s | 4 | safe |
| 旧收费站 | 主干道 | 30s | 5 | safe |
| 毒沼泽 | 小径 | 35s | 7 | danger |

### 2. 北穹塔台 (tower)

| 属性 | 值 |
|------|-----|
| **势力** | 技术派 (tech) ⚙ |
| **坐标** | (500, 80) |
| **描述** | 建在旧防空观测塔群上的技术聚落 |
| **领袖** | 韩策 — 前信号工程师，理性严苛 |
| **初始好感** | 0（未访问） |
| **开局可见** | 是 |

**专属系统 — 情报交换站**

| 情报类型 | 名称 | 数据消耗 | 有效期 | 用途 |
|---------|------|---------|--------|------|
| weather | 天气预报 | 1 | 1 趟 | 提前知道天气 |
| price | 价格情报 | 2 | 1 趟 | 目标聚落物价趋势 |
| security | 安全预警 | 2 | 2 趟 | 掠夺者活动信息 |
| tip | 商机情报 | 3 | 1 趟 | 某聚落紧急高价需求 |
| **location** | **位置情报** | **5** | **一次性** | **解锁一个隐藏节点** |

**相邻节点（扩展后）**：
| 目标 | 路线类型 | 耗时 | 燃料 | 危险度 |
|------|---------|------|------|--------|
| 旧公路交叉口 | 主干道 | 55s | 9 | safe |
| 塌陷高架 | 捷径 | 20s | 5 | danger |
| 穹顶哨站 | 主干道 | 25s | 4 | safe |
| 太阳能田 | 小径 | 20s | 3 | safe |
| 气象站废墟 | 小径 | 25s | 5 | normal |
| 雷达山丘 | 小径 | 30s | 5 | normal |
| 弹坑边缘 | 小径 | 35s | 7 | danger |

### 3. 废墟游民营地 (ruins_camp)

| 属性 | 值 |
|------|-----|
| **势力** | 拾荒帮 (scav) 🔧 |
| **坐标** | (550, 450) |
| **描述** | 塌陷商场周边的流动型拾荒聚落 |
| **领袖** | 伍拾七 — 嘴硬心细，用黑市规则维持脆弱秩序 |
| **初始好感** | 0（未访问） |
| **开局可见** | 否 |

**专属系统 — 黑市淘货 & 砍价博弈**（详见原文档）

**相邻节点（扩展后）**：
| 目标 | 路线类型 | 耗时 | 燃料 | 危险度 |
|------|---------|------|------|--------|
| 碎片场 | 主干道 | 30s | 5 | safe |
| 废弃仓库 | 小径 | 35s | 6 | normal |
| 干涸河床 | 主干道 | 30s | 5 | safe |
| 沉降广场 | 小径 | 25s | 5 | normal |
| 地铁营地 | 小径 | 20s | 3 | safe |
| 废车场 | 小径 | 20s | 3 | safe |
| 下水道迷宫 | 小径 | 25s | 4 | normal |

### 4. 钟楼书院 (bell_tower)

| 属性 | 值 |
|------|-----|
| **势力** | 宗教团 (scholar) 📖 |
| **坐标** | (750, 250) |
| **描述** | 围绕旧钟楼建立的学者聚落 |
| **领袖** | 白述 — 沉静神秘 |
| **初始好感** | 0（未访问） |
| **开局可见** | 否 |

**专属系统 — 档案阅览 & 文物修复**（详见原文档）

**相邻节点（扩展后）**：
| 目标 | 路线类型 | 耗时 | 燃料 | 危险度 |
|------|---------|------|------|--------|
| 藤桥 | 主干道 | 35s | 6 | normal |
| 旧教堂 | 主干道 | 20s | 3 | safe |
| 碑林花园 | 小径 | 15s | 2 | safe |
| 印刷厂遗址 | 小径 | 25s | 4 | normal |
| 干涸河床 | 小径 | 35s | 6 | normal |
| 风口隘道 | 小径 | 30s | 6 | normal |

---

## 五、节点解锁机制（5 种方式）

| 方式 | 触发 | 适用范围 |
|------|------|---------|
| **手动探索** | 在地图探索面板点击"探索" | 普通节点（默认） |
| **NPC 对话** | 好感达标后触发特定对话，ops 含 `unlock_route` | 隐藏节点（underground_market, signal_bunker） |
| **聚落事件** | 聚落好感达标后触发事件，ops 含 `unlock_route` | 隐藏节点（old_archives） |
| **情报交换** | 北穹塔台花费 5 路况数据购买"位置情报" | 随机解锁一个隐藏节点 |
| **条件探索** | 节点可见但锁定，需设置特定 flag 后才能前往 | P4 预留（mist_valley） |

### 隐藏节点解锁详情

| 节点 | 方式 1 | 方式 2 |
|------|--------|--------|
| underground_market | 伍拾七对话 `NPC_WU_005`（好感50+） | 塔台位置情报（随机） |
| signal_bunker | 白述对话 `NPC_BS_005`（好感45+） | 塔台位置情报（随机） |
| old_archives | 废墟营地事件 `SE_RUINS_003`（好感40+） | 塔台位置情报（随机） |

### explore_flag 机制

| 节点 | 旗标 | 解锁方式 |
|------|------|---------|
| mist_valley | `mist_valley_accessible` | P4 主线剧情设置 |

---

## 六、开局可见性

| 状态 | 节点 |
|------|------|
| **开局已知**（3 个） | 温室社区、北穹塔台、旧公路交叉口 |
| **需探索**（34 个） | 大部分节点通过普通探索发现 |
| **隐藏**（3 个） | underground_market, signal_bunker, old_archives |

---

## 七、路线类型说明

共约 **74 条边**（均为双向），分 3 种类型：

| 路线类型 | 英文 | 特点 |
|---------|------|------|
| 主干道 | main_road | 安全但慢，燃料消耗高 |
| 小径 | path | 速度和危险度平衡 |
| 捷径 | shortcut | 快但危险 |

危险度分级：`safe`（安全）→ `normal`（一般）→ `danger`（高危）

---

## 八、势力距离设计

各主聚落间最短路径 ≥3 跳，确保跑商有深度：

| 起点 → 终点 | 最短路径示例 | 跳数 |
|-------------|-------------|------|
| 温室社区 → 北穹塔台 | greenhouse → crossroads → tower | 2（主干道）或 greenhouse → danger_pass → tower（捷径） |
| 温室社区 → 废墟营地 | greenhouse → crossroads → scrap_yard → ruins_camp | 3 |
| 温室社区 → 钟楼书院 | greenhouse → crossroads → signal_relay → overgrown_bridge → bell_tower | 4 |
| 北穹塔台 → 废墟营地 | tower → signal_relay → scrap_yard → ruins_camp | 3 |
| 北穹塔台 → 钟楼书院 | tower → radar_hill → wind_gap → bell_tower | 3 |
| 废墟营地 → 钟楼书院 | ruins_camp → dry_riverbed → bell_tower | 2（较近，拾荒帮与学者互为邻居） |

---

## 九、边境探索链

6 个高危节点形成环形探索链，沿地图边缘分布：

```
military_bunker ─── dead_forest ─── crater_rim ─── broadcast_tower
       |                |                               |
 (连接 danger_pass)  (连接 toxic_marsh)           (连接 wind_gap)
                        |                               |
                  (连接 mushroom_cave)             rust_bridge
                                                        |
                                                 (连接 old_church)
```

边境链特点：
- 全部 danger 级别
- 高燃料消耗
- 稀有资源奖励
- 叙事线索散落
- 适合中后期有充足准备后探索

---

## 十、拓扑区域示意

```
                   军事碉堡  弹坑边缘──气象站废墟   广播塔废墟
                     |          |           |          |
                   枯木林   塌陷高架     太阳能田   铁锈大桥
                     |       /    \      /    \        |
                   毒沼泽  温室   雾谷  塔台   雷达山丘  旧教堂
                     |      |     |    |  \    |       |
                   蘑菇洞  灌溉  收费站 穹顶  风口隘道  碑林花园
                     |      |     |    |      |       |
                   外围农场  |   物流园 交叉口   藤桥    印刷厂
                     |       \    |    |  \    |    /
                   隐士洞窟    \  沙尘  信号  碎片场  钟楼书院
                              沉降广场    |     |      |
                                 |     仓库  废墟营地  干涸河床
                              废车场    |     |    \    |
                                 \   地铁营地 下水道  旧教堂
                                  \         |
                                  (地下黑市)    (信号掩体)  (旧档案馆)
                                   [隐藏]       [隐藏]      [隐藏]
```

---

## 十一、好感度洋葱结构

每个主聚落的内容随好感度分三层揭开：

| 层级 | 好感范围 | 开放内容 |
|------|---------|---------|
| 外层 | 0 - 30 | 交易、补给、基础对话 |
| 中层 | 30 - 60 | 内部冲突、隐藏问题、专属系统开放 |
| 内层 | 60 - 90 | 故事线高潮、系统完全体、与主线交汇 |

---

## 十二、核心配置文件索引

| 文件 | 路径 | 内容 |
|------|------|------|
| 地图节点/边定义 | `scripts/map/world_graph.lua` | 40 节点 + ~74 边 |
| 势力系统 | `scripts/settlement/factions.lua` | 4 势力 + 反查表 |
| 游戏初始状态 | `scripts/core/state.lua` | 9 聚落好感初始值 |
| 路线规划 | `scripts/map/route_planner.lua` | BFS/Dijkstra 寻路 |
| 地图 UI | `scripts/ui/screen_map.lua` | 地图渲染与交互 |
| 核心流程 | `scripts/core/flow.lua` | 探索/旅行/到达逻辑 |
| 事件执行器 | `scripts/events/event_executor.lua` | 16+ 种操作码 |
| 温室·农场 | `scripts/settlement/farm.lua` | 培育农场系统 |
| 废墟·黑市 | `scripts/settlement/black_market.lua` | 黑市淘货系统 |
| 塔台·情报 | `scripts/settlement/intel.lua` | 情报交换系统（含位置情报） |
| 书院·档案 | `scripts/settlement/archives.lua` | 档案阅览系统 |
| 好感度管理 | `scripts/settlement/goodwill.lua` | 好感度计算 |
| NPC 对话 | `assets/configs/npc_dialogues.json` | 含 unlock_route 对话 |
| 聚落事件 | `assets/configs/settlement_events.json` | 含 unlock_route 事件 |

---

---

## 十三、非聚落节点交互系统（2026-04-11 新增）

此前非聚落节点（resource/hazard/transit/story/frontier）到达后仅有篝火可用，体验单一。现已扩展为完整的交互系统。

### 13.1 探索房间映射

所有 resource 和部分 hazard 节点现已映射到独立的探索房间模板，到达时可点击"搜索附近"进入资源点探索：

| 节点 ID | 节点名称 | 类型 | 房间模板 | 主要产出 |
|---------|---------|------|---------|---------|
| irrigation_canal | 灌溉水渠 | resource | irrigation_tunnels | 水、食物 |
| mushroom_cave | 蘑菇洞窟 | resource | mushroom_grotto | 食物、药品 |
| solar_field | 太阳能田 | resource | solar_panels | 电路板、燃料 |
| junkyard | 废车场 | resource | junk_heap | 金属、电路板 |
| printing_ruins | 印刷厂遗址 | resource | print_shop | 旧书、电路板 |
| radar_hill | 雷达山丘 | resource | radar_station | 电路板、弹药 |
| old_warehouse | 废弃仓库 | resource | abandoned_warehouse | 食物、金属 |
| old_archives | 旧档案馆 | resource | logistics_depot | 混合物资 |
| military_bunker | 军事碉堡 | resource | bunker_interior | 弹药、烟雾弹（高危） |
| sewer_maze | 下水道迷宫 | hazard | sewer_depths | 药品、烟雾弹（高危） |
| sunken_plaza | 沉降广场 | hazard | crater_salvage | 燃料、金属（高危） |
| weather_station | 气象站废墟 | hazard | old_clinic | 药品（低危） |

详细房间模板参数见 `docs/combat_system.md` § 三 和 § 十。

### 13.2 路点事件池（Waypoint Event Pool）

类似聚落事件池，非聚落节点到达时有 **25%** 概率触发路点事件。

- **配置文件**：`assets/configs/waypoint_events.json`（15 个事件）
- **代码实现**：`scripts/events/waypoint_event_pool.lua`
- **接入点**：`flow.lua` → `handle_node_arrival()`、`screen_home.lua` → 非聚落 UI 按钮

**事件分类**：

| 类型 | 数量 | ID 前缀 | 示例 |
|------|------|---------|------|
| 资源型 | 5 | WPT_R | 拾荒者交易、设备故障、隐藏物资、竞争者、旧地图碎片 |
| 危险型 | 5 | WPT_H | 求救信号、恶劣天气、变异巢穴、断路抉择、迷雾中的声音 |
| 中转型 | 3 | WPT_T | 过路商人、路标留言、废弃营地遗迹 |
| 故事型 | 2 | WPT_S | 旧日信件、广播残响 |

**筛选机制**：每个事件配有 `node_types` 数组（可选 `node_ids`），到达时按当前节点类型过滤 → 权重抽取 → 独立冷却（`state._waypoint_event_cooldowns`）。

### 13.3 中转站快速休整

**仅 transit 节点**额外提供"短暂休整"按钮：

| 属性 | 值 |
|------|-----|
| 消耗 | 罐头 ×1 + 饮水 ×1 |
| 效果 | 修复货车耐久 5 点（不超上限） |
| 限制 | 每次到达限用一次（`state._visit_used.transit_rest`） |
| 不可用提示 | "已休整过" / "缺少食物" / "缺少饮水" |

### 13.4 故事节点首次到访提示

**story 节点**首次到达时，篝火按钮会高亮显示"此地似有故事"提示，引导玩家与同伴交谈。到访记录存储在 `state._visited_story_nodes[nodeId]`。

### 13.5 非聚落节点到达后交互总览

到达非聚落节点时，按顺序可能出现以下按钮：

| 按钮 | 条件 | 说明 |
|------|------|------|
| 搜索附近 | 节点在 NODE_EXPLORE_ROOM 映射中 | 进入探索房间 |
| 查看地图 | 始终可用 | 进入路线规划 |
| 路点事件 | `state.flow.pending_waypoint_event` 存在 | 触发随机事件 |
| 短暂休整 | transit 节点 + 有食物和水 + 未使用 | 消耗补给修复耐久 |
| 篝火 | 始终可用 | 与同伴互动（story 首访高亮） |

---

*文档版本: v3.0*
*更新日期: 2026-04-11*
*变更: v2→v3 新增 §十三 非聚落节点交互系统（探索房间映射、路点事件池、中转休整、故事首访提示）*
*数据来源: world_graph.lua, factions.lua, state.lua, intel.lua, npc_dialogues.json, settlement_events.json, waypoint_events.json, waypoint_event_pool.lua, combat_config.lua, screen_home.lua*

# 《末世行商》文档索引

> 最后更新：2026-04-12

---

## design/ — 游戏设计

策划视角的设计文档，描述游戏**是什么**。

| 文档 | 说明 |
|------|------|
| [core_design.md](design/core_design.md) | 核心设计文档（世界观、玩法循环、经济、战斗、升级系统） |
| [main_story.md](design/main_story.md) | 主线剧情设计（章节结构、角色弧光、关键事件） |
| [prologue_detail.md](design/prologue_detail.md) | **序章叙事设计 v3.0**（8 个教学窗口台词骨架、情感弧线、信号暗线） |
| [narrative_guidelines.md](design/narrative_guidelines.md) | 叙事撰写规范（文风、对话风格、禁忌） |
| [suspense_hooks.md](design/suspense_hooks.md) | 悬念钩子设计（三级钩子方法论、逐章审计、warming 机制） |
| [letter_system.md](design/letter_system.md) | 信件系统设计（雪冬角色、信件流、投递委托、跨通道整合） |
| [settlements.md](design/settlements.md) | 聚落深化设计（各聚落故事线、NPC 互动） |
| [random_events.md](design/random_events.md) | 随机事件配置表（事件池、触发条件、权重） |
| [road_feel.md](design/road_feel.md) | 公路感设计（路景文案、沉默时刻、旅途小事件） |
| [art_guidelines.md](design/art_guidelines.md) | 美术素材规范（画风约束、立绘 Prompt、生成参数） |

## characters/ — 角色档案

所有角色的详细设定。

| 文档 | 说明 |
|------|------|
| [README.md](characters/README.md) | 角色档案库总览 |
| [protagonists.md](characters/protagonists.md) | 主角档案（林砾、陶夏） |
| [faction_npcs.md](characters/faction_npcs.md) | 势力 NPC 档案 |
| [settlement_leaders.md](characters/settlement_leaders.md) | 聚落领袖档案 |
| [settlement_npcs.md](characters/settlement_npcs.md) | 聚落驻留 NPC 档案 |
| [wandering_npcs.md](characters/wandering_npcs.md) | 流浪 NPC 档案 |

## systems/ — 系统实现

技术视角的系统文档，描述各系统**怎么做**。

| 文档 | 说明 |
|------|------|
| [combat.md](systems/combat.md) | 战斗系统（战斗流程、伤害计算、敌人 AI） |
| [dialogue.md](systems/dialogue.md) | 对话系统（Gal 风格对话引擎、分支逻辑） |
| [intel.md](systems/intel.md) | 情报系统（情报收集、解锁、影响） |
| [stroll.md](systems/stroll.md) | 闲逛系统（聚落探索、NPC 互动、事件触发） |
| [driving_scene.md](systems/driving_scene.md) | 行驶视差场景（视差层、动画参数、性能优化） |
| [travel_chatter_radio.md](systems/travel_chatter_radio.md) | 车内对话 & 收音机（Chatter/Radio API、数据结构） |

## reference/ — 速查参考

纯数据型参考文档，适合快速查阅。

| 文档 | 说明 |
|------|------|
| [map_nodes.md](reference/map_nodes.md) | 地图节点总览（节点/边/路段数据） |

## planning/ — 开发计划

开发进度与待办事项。

| 文档 | 说明 |
|------|------|
| [phase4_5.md](planning/phase4_5.md) | Phase 4 & 5 开发计划 |
| [tutorial_impl.md](planning/tutorial_impl.md) | 教程引导系统（已实施） |
| [ui_beautification.md](planning/ui_beautification.md) | UI 废土风美化方案 |
| [backlog.md](planning/backlog.md) | 待开发功能清单 |

## impl_plan/ — 实现方案

早期阶段性实现方案存档。

| 文档 | 说明 |
|------|------|
| [00_tech_stack.md](impl_plan/00_tech_stack.md) | 技术选型与工程结构 |
| [06_combat_and_resource_points.md](impl_plan/06_combat_and_resource_points.md) | 车载迎击与资源点探索战 |
| [07_settlement_and_progression.md](impl_plan/07_settlement_and_progression.md) | 聚落、角色关系与长期成长 |
| [08_integration_and_release.md](impl_plan/08_integration_and_release.md) | 联调、性能、上线前准备 |

## instructions/ — 开发备忘

特定问题的解决方案和编码规范。

| 文档 | 说明 |
|------|------|
| [config_management.md](instructions/config_management.md) | 配置管理规则 |
| [audio_scene_guide.md](instructions/audio_scene_guide.md) | 对话 audioScene 选取指南 |
| [b2_committed_cargo.md](instructions/b2_committed_cargo.md) | B2 委托货物系统需求变更 |
| [mobile_touch_mouse_double_fire.md](instructions/mobile_touch_mouse_double_fire.md) | 移动端 Touch + Mouse 双触发陷阱 |
| [ui_scroll_preserve.md](instructions/ui_scroll_preserve.md) | UI 滚动位置保持规范 |

## meta/ — 项目元信息

项目维护相关。

| 文档 | 说明 |
|------|------|
| [changelog.md](meta/changelog.md) | 变更日志 |
| [git_lfs_setup.md](meta/git_lfs_setup.md) | Git LFS 资源拉取说明 |
| [lua_pitfalls.md](meta/lua_pitfalls.md) | Lua 全局函数名冲突陷阱 |

## configs/ — 数据配置

JSON 格式的游戏数据配置（非文档）。

| 文件 | 说明 |
|------|------|
| [guaji_random_events.json](configs/guaji_random_events.json) | 随机事件数据 |
| [portraits.json](configs/portraits.json) | 立绘路径映射 |

# 对话 audioScene 选取指南

## 什么是 audioScene

每段对话数据可以通过 `audioScene` 字段指定播放时的 BGM 和环境音氛围。进入对话时，音频管理器会自动切换到对应场景，带有 2.5 秒的交叉淡入淡出。

对话结束后返回正常游戏页面时，shell 会根据当前游戏阶段（行驶/聚落）自动恢复对应的音频场景，**不需要手动还原**。

---

## 可选场景

| audioScene | BGM 风格 | 环境音 | 适用情境 |
|-----------|---------|--------|---------|
| `"travel"` | Lo-fi 原声吉他，忧郁公路感 | 柴油引擎低鸣 + 荒野风声 | 在路上、车内、行驶途中发生的对话 |
| `"settlement"` | 温暖民谣/原声，安宁社区感 | 聚落人声嘈杂（远处敲打、说话） | 到达聚落、在聚落内与 NPC 交谈 |
| `"campfire"` | 极简指弹吉他，亲密私密感 | 篝火噼啪声 + 微弱风声 | 篝火夜话、深入交心、回忆往事 |
| `"silent"` | 无 BGM | 无环境音 | 需要完全安静的特殊剧情（如紧张时刻、重大转折前的沉默） |

---

## 怎么选

### 判断依据：**对话发生的物理场景 + 情绪氛围**

```
对话发生在哪里？
  │
  ├─ 货车上 / 公路旁 / 行驶途中
  │    └─ "travel"
  │
  ├─ 聚落内部 / 市场 / NPC 住所
  │    └─ "settlement"
  │
  ├─ 篝火旁 / 夜间停车休息 / 车厢内私聊
  │    └─ "campfire"
  │
  └─ 特殊紧张场景 / 需要纯静音
       └─ "silent"
```

### 快速参考

| 对话类型 | 推荐 audioScene | 说明 |
|---------|----------------|------|
| 序章（路上发现残骸） | `travel` | 行驶途中 |
| 序章（第一晚篝火） | `campfire` | 篝火夜话 |
| 到达新聚落的剧情 | `settlement` | 初次踏入聚落 |
| 日常篝火闲聊 | 不填（默认） | 篝火页面默认就是 `campfire` |
| NPC 任务对话 | 不填（默认） | NPC 页面默认就是 `settlement` |
| 路上的随感/讨论 | `travel` | 车内对话 |
| 看地图/计划路线 | `campfire` | 通常是停车后的安静时刻 |
| 收音机相关剧情 | `travel` | 在车上听广播 |
| 紧张对峙/遭遇危险 | `silent` | 制造紧张感 |

---

## 怎么写

在 JSON 对话数据中，和 `title`、`type` 同级添加 `audioScene` 字段：

```json
{
  "id": "SD_EXAMPLE_01",
  "title": "路边的发现",
  "type": "main_story",
  "audioScene": "travel",
  "chapter": 1,
  "steps": [ ... ],
  "choices": [ ... ]
}
```

### 可以不填吗？

可以。不填时会使用**页面默认值**：

| 对话页面 | 默认 audioScene |
|---------|----------------|
| 篝火页 (screen_campfire) | `"campfire"` |
| NPC 页 (screen_npc) | `"settlement"` |
| 闲逛页 (screen_stroll) | `"settlement"` |

所以日常篝火对话和普通 NPC 对话通常不需要填，只有**和默认氛围不同**时才需要显式指定。

### 典型需要填的场景

- 通过篝火页面播放的对话，但内容实际发生在路上 → 填 `"travel"`
- 教程/剧情强制触发的聚落到达对话 → 填 `"settlement"`（确保不会误播行驶 BGM）
- 任何需要安静的重要剧情节点 → 填 `"silent"`

---

## 现有对话的 audioScene 配置参考

| 对话 ID | 标题 | audioScene | 原因 |
|--------|------|-----------|------|
| SD_PROLOGUE_01 | 残骸 | `travel` | 公路上发现烧毁货车 |
| SD_PROLOGUE_02 | 第一晚 | `campfire` | 篝火旁的第一次深谈 |
| SD_CH1_01 | 第五趟 | `travel` | 行驶途中聊天 |
| SD_CH1_02 | 记账本 | `campfire` | 夜间整理货物 |
| SD_CH2_01 | 四个名字 | `campfire` | 停下来标注地图 |
| SD_CH2_02 | 收音机里的世界 | `travel` | 车上听广播 |
| SD_CH2_03 | 信任的重量 | `travel` | 路边看日落 |
| SD_TUTORIAL_FIRST_DEPARTURE | 麻薯号，出发 | `travel` | 准备出发 |
| SD_TUTORIAL_GREENHOUSE_ARRIVAL | 温室社区 | `settlement` | 到达聚落 |
| SD_TUTORIAL_CAMPFIRE_HINT | 穹顶的裂缝 | `campfire` | 篝火引导 |
| SD_TUTORIAL_EXPLORE_HINT | 未知的路 | `campfire` | 停下看地图 |
| SD_TUTORIAL_TOWER_ARRIVAL | 北穹塔台 | `settlement` | 到达聚落 |
| CF_001~CF_011 | 日常篝火对话 | （不填） | 默认 campfire |

---

## 将来扩展

如果需要新的音频场景（比如 `"danger"` 紧张战斗、`"rain"` 雨天行车），需要：

1. 生成对应的 BGM 和环境音素材
2. 在 `theme.lua` 的 `bgm` / `ambient` 表中注册资源路径
3. 在 `audio_manager.lua` 的 `SCENES` 表中添加场景定义
4. 之后就可以在对话数据中使用新的 audioScene 值了

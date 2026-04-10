# 角色档案库

> 《末世行商》全角色人设索引。  
> 写对话前先查对应角色档案，确保语气、信息权限、关系阶段一致。

---

## 快速索引

### 主角（2人）

| 角色 | 身份 | 说话核心特征 | 档案 |
|------|------|-------------|------|
| **陶夏** | 行商·驾驶员 | 活泼反问、吐槽、认真时语气变沉 | [protagonists.md](protagonists.md) |
| **林砾** | 行商·技术员 | 省略号开头、话少、冷幽默、技术话题时话变多 | [protagonists.md](protagonists.md) |

### 聚落领袖（4人）

| 角色 | 聚落 | 说话关键词 | 档案 |
|------|------|-----------|------|
| **沈禾** | 温室社区 greenhouse | "够不够"、"能用就行"、"别浪费" | [settlement_leaders.md](settlement_leaders.md) |
| **韩策** | 北穹塔台 tower | "数据"、"效率"、"不够稳定" | [settlement_leaders.md](settlement_leaders.md) |
| **伍拾七** | 废墟营地 ruins_camp | "我的地盘"、"信你一次"、"规矩" | [settlement_leaders.md](settlement_leaders.md) |
| **白述** | 钟楼书院 bell_tower | "档案里记载"、"旧时代"、"记住了就不会忘" | [settlement_leaders.md](settlement_leaders.md) |

### 聚落NPC（8人）

| 角色 | 聚落 | 身份 | 档案 |
|------|------|------|------|
| **赵苗** | 温室社区 | 外围站管理员 | [settlement_npcs.md](settlement_npcs.md) |
| **程远** | 北穹塔台 | 气象站技术员 | [settlement_npcs.md](settlement_npcs.md) |
| **阿锈** | 废墟营地 | 机械师 / 营地管理员 | [settlement_npcs.md](settlement_npcs.md) |
| **苏墨** | 钟楼书院 | 图书管理员 / 抄录员 | [settlement_npcs.md](settlement_npcs.md) |
| **季微（纪微）** | 温室社区 | 水循环工程师 | [settlement_npcs.md](settlement_npcs.md) |
| **老甘** | 废墟营地 | 夜市老板 | [settlement_npcs.md](settlement_npcs.md) |
| **刀鱼** | 废墟营地 | 情报贩子 | [settlement_npcs.md](settlement_npcs.md) |
| **谢令** | 钟楼书院 | 修复师 | [settlement_npcs.md](settlement_npcs.md) |

### 势力NPC（4人，Ch.3+出现）

| 角色 | 势力 | 身份 | 档案 |
|------|------|------|------|
| **姜寒** | 铁锁商队 | 队长 | [faction_npcs.md](faction_npcs.md) |
| **小铆** | 铁锁商队 | 机械师少女 | [faction_npcs.md](faction_npcs.md) |
| **陆沉** | 静潮社 | 创始人 | [faction_npcs.md](faction_npcs.md) |
| **霜期** | 静潮社 | 联络员 | [faction_npcs.md](faction_npcs.md) |

### 流浪NPC（2人 + 后期关键1人）

| 角色 | 身份 | 出现阶段 | 档案 |
|------|------|---------|------|
| **孟回** | 行脚医生 | 前期起 | [wandering_npcs.md](wandering_npcs.md) |
| **鸣砂** | 独行商人 / 电台播报员 | 前期(电台) / 中期(现身) | [wandering_npcs.md](wandering_npcs.md) |
| **祁岚** | 云海高塔看守者 | 后期 | [wandering_npcs.md](wandering_npcs.md) |

---

## 写对话前的检查清单

1. **查角色档案** → 确认说话方式、口头禅、禁忌
2. **查信息权限** → 该角色此时知道什么、不知道什么（见 `settlement_leaders.md` 信息权限表）
3. **查关系阶段** → 当前好感度对应哪个阶段（早期/中期/后期）
4. **查叙事指南** → `docs/guaji_narrative_guidelines.md` 中的红线和规范
5. **查主角互动模式** → `protagonists.md` 中的日常/严肃/分歧模式

---

## 角色出场时间线

```
Ch.1 序章    陶夏、林砾、沈禾（教学）
  │
Ch.1 前期    韩策、赵苗、程远、孟回
  │          鸣砂（仅电台声音）
  │
Ch.2 中期    伍拾七、白述、阿锈、苏墨
  │          季微、老甘、刀鱼、谢令
  │          鸣砂（现身）、孟回
  │          鸣砂广播提及"云海高塔"
  │
Ch.3 扩展    姜寒、小铆（铁锁商队）
  │          陆沉、霜期（静潮社）
  │
Ch.5 汇聚    静潮社激进派 vs 信号中继站
  │          小铆出走、霜期内部矛盾
  │
Ch.6 终局    祁岚（云海高塔）
  │          孟回"最后一张地图"
  │          鸣砂最终广播
  │
结局          四种结局分支
```

---

## 文件结构

```
docs/characters/
├── README.md               ← 你在这里
├── protagonists.md          # 主角档案（陶夏、林砾）
├── settlement_leaders.md    # 聚落领袖档案（沈禾、韩策、伍拾七、白述）
├── settlement_npcs.md       # 聚落NPC档案（赵苗、程远、阿锈、苏墨、季微、老甘、刀鱼、谢令）
├── faction_npcs.md          # 势力NPC档案（姜寒、小铆、陆沉、霜期）
└── wandering_npcs.md        # 流浪NPC档案（孟回、鸣砂、祁岚）
```

---

## 相关文档

| 文档 | 用途 |
|------|------|
| `docs/guaji_narrative_guidelines.md` | 叙事规范（信息权限、说话方式、红线） |
| `docs/guaji_main_story.md` | 主线剧情设计（章节结构、势力关系） |
| `docs/configs/portraits.json` | 立绘资源映射（角色ID→图片路径） |
| `assets/configs/npc_dialogues.json` | NPC对话数据（实际游戏中使用的台词） |
| `assets/configs/story_dialogues.json` | 主线对话数据 |
| `assets/configs/campfire_dialogues.json` | 篝火对话数据 |
| `assets/configs/radio_broadcasts.json` | 电台广播数据（鸣砂频道） |

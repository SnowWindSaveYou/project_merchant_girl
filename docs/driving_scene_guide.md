# 行驶视差场景 (driving_scene) 技术文档

> 记录车辆行驶视差动画的所有关键参数、图片分析数据和调试经验，防止上下文丢失。

---

## 1. 文件结构

```
scripts/travel/driving_scene.lua    # 视差场景 widget 组件
scripts/ui/screen_home.lua          # 集成处（createTravelView, update）
```

### 集成方式

```lua
-- screen_home.lua
local DrivingScene = require("travel/driving_scene")

-- 在 createTravelView() 中：
DrivingScene.createWidget({ height = 220, borderRadius = Theme.sizes.radius })

-- 在 M.update() 中：
DrivingScene.update(dt)
```

---

## 2. 素材清单与图片分析数据

### 2.1 卡车车身：`truck_home_clean.png`
- **尺寸**：1024×572
- **描述**：空卡车（无角色），面朝左
- **前轮拱位置**：中心 x=0.186, bottom_y=0.970, 跨度 x=0.125-0.310
- **后轮拱位置**：中心 x=0.771, bottom_y=0.970, 跨度 x=0.640-0.853
- **轮径/车高比**：~0.356

### 2.2 车轮：`wheel.png`
- **尺寸**：155×157（近正方形，宽高比 ~0.987）
- **描述**：从车身裁切的轮子图，用 nvgCircle 裁剪为圆形

### 2.3 天空背景：`parallax_sky_20260408180927.png`
- **尺寸**：1025×572
- **描述**：末世黄昏天空，不透明，拉伸填充（不平铺），speed=0
- **用法**：作为最底层背景，不滚动

### 2.4 远景剪影：`parallax_far_v2_20260408180625.png`
- **尺寸**：1025×572
- **透明率**：47.6%（v1 版本是 99.6%，太稀疏被替换）
- **内容行范围**：row 163-571（比例 0.285-0.998）
- **密集内容区域**：row 179-557（比例 0.313-0.974）
- **平均密度**：78.8%
- **描述**：废墟城市天际线剪影，深灰偏蓝色调

### 2.5 中景建筑：`parallax_mid_20260408172203.png`
- **尺寸**：1024×572
- **透明率**：42.6%
- **内容行范围**：row 148-512（比例 0.26-0.90）
- **描述**：废弃建筑、电线杆、水塔等

### 2.6 地面路面：`parallax_ground_20260408172153.png`
- **尺寸**：1024×572
- **透明率**：11.2%
- **内容行范围**：row 0-571（几乎全覆盖）
- **描述**：破损公路路面

### 2.7 近景杂物：`parallax_near_20260408172153.png`
- **尺寸**：1024×572
- **透明率**：97.7%
- **内容行范围**：row 107-234（比例 **0.19-0.41**，仅图片顶部窄带！）
- **⚠️ 关键**：内容只在图片上部 19%-41% 区域，下面全透明。定位时必须大幅下移才能让杂物落在地面上。

---

## 3. 当前参数配置

### 3.1 视差层定义 (LAYER_DEFS)

| 层 | 图片 | speed | yStart | yEnd | 说明 |
|----|------|-------|--------|------|------|
| 天空 | parallax_sky_*.png | 0.0 | 0.0 | 1.0 | 拉伸填充，不平铺 |
| 远景 | parallax_far_v2_*.png | 0.05 | 0.0 | 0.85 | 内容显示在 widget 25%-85% |
| 中景 | parallax_mid_*.png | 0.30 | 0.15 | 0.90 | 内容底约 82.5% |
| 地面 | parallax_ground_*.png | 1.0 | 0.68 | 1.0 | 路面 |
| 近景 | parallax_near_*.png | 0.60 | 0.68 | 1.30 | 内容在 80%-93%，叠在路面上 |

**绘制顺序**：天空 → 远景 → 中景 → 地面 → 近景（近景在路面之上）

### 3.2 卡车参数

```lua
-- 卡车高度占 widget 70%
local truckH = l.h * 0.70

-- 车轮相对位置（比例，相对卡车图片）
WHEEL_POSITIONS = {
    { rx = 0.20, ry = 0.85 },  -- 前轮
    { rx = 0.77, ry = 0.85 },  -- 后轮
}
WHEEL_SIZE_RATIO = 0.28        -- 轮径占车高比例

-- 路面定位
roadSurface = l.y + l.h * 0.88  -- 路面可行驶区域
-- 车辆Y = roadSurface - wheelCenterY - wheelRadius
```

### 3.3 车轮渲染

- **宽高比保持**：`drawW = wheelDiam * (155/157)`，避免拉伸
- **旋转方向**：逆时针（负角度），因为卡车面朝左行驶
- **旋转公式**：`angle = -(scrollOffset_ * 1.0) / (wheelR * 0.8)`
- **裁剪方式**：nvgCircle 圆形裁剪

### 3.4 Widget 配置

- **高度**：220px（从最初 160px 放大而来）
- **滚动速度**：SCROLL_SPEED = 50 像素/秒
- **路面颠簸**：`bounce = sin(offset * 0.07) * 1.5`

---

## 4. 层定位计算公式

图片内容在图片中的比例为 `contentRatio`，则在 widget 中的实际位置为：

```
widgetPos = yStart + contentRatio * (yEnd - yStart)
```

示例：近景内容在图片 19%-41%，yStart=0.68, yEnd=1.30
- 内容顶：0.68 + 0.19 * 0.62 = 0.80
- 内容底：0.68 + 0.41 * 0.62 = 0.93
→ 杂物横跨 widget 80%-93%，覆盖路面(88%)上下

---

## 5. 调试经验总结

### 5.1 已解决的问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 轮子太小 | WHEEL_SIZE_RATIO 太低 | 通过 PIL 分析像素数据得到真实比例 ~0.356，设为 0.28 |
| 轮子悬浮在车下方 | ry=0.97 是轮胎底部不是中心 | 改为 ry=0.85（轮心位置） |
| 卡车浮在路面上方 | roadSurface 值太高 | 逐步调到 0.88 |
| 轮子拉伸变形 | 用正方形绘制 155×157 图片 | 按实际宽高比 imgW/imgH 计算 drawW |
| 轮子旋转方向反 | 正角度=顺时针，但车朝左 | 取负角度 |
| 杂物飘在空中 | near 图内容在上部(19%-41%)，但层定位偏高 | yStart=0.68, yEnd=1.30 大幅下移 |
| 远景看不见 | v1 图 99.6% 透明，内容极稀疏 | 重新生成 v2 图（密度 78.8%） |
| 天空背景接缝 | 天空图平铺有明显重复 | speed=0 时改为拉伸填充而非平铺 |
| 中景与地面有空隙 | 中景 yEnd 和地面 yStart 没有重叠 | 调整使中景底部(0.825)覆盖到地面(0.68)之上 |

### 5.2 关键教训

1. **先分析图片再定位**：用 PIL/numpy 分析每张图片的实际内容分布区域（透明像素行扫描），不要凭感觉设参数
2. **near 图的陷阱**：内容可能只在图片顶部一小段（19%-41%），必须大幅下移才能对齐地面
3. **speed=0 的层用拉伸**：静态背景不需要平铺，拉伸填充避免接缝
4. **车轮图从车身裁切**：所以宽高比不是 1:1，需要 `aspect = imgW/imgH` 保持原始比例

---

## 6. 纸娃娃（Chibi）系统

### 6.1 概述

纸娃娃系统在卡车上显示 Q 版角色精灵，具有完整的 AI 行为、姿势差分、动画系统和点击交互。支持主角（林砾、陶夏）和 NPC 路人两类角色。

**渲染层序**（从底到顶）：
1. 驾驶室纸娃娃（卡车车体后方，只露出头部）
2. 卡车车体
3. 车厢内纸娃娃（桌/灶/床/货厢/机枪位区域）
4. 车外纸娃娃（停车时站在地面）

---

### 6.2 区域定义

卡车被划分为多个功能区域，每个区域的坐标为归一化值（相对卡车图片 1024×572）：

| 区域 | 变量名 | x | y | w | h | 说明 |
|------|--------|-------|-------|-------|-------|------|
| 驾驶室 | `cabin` | 0.193 | 0.294 | 0.106 | 0.376 | 林砾开车 |
| 饭桌 | `table` | 0.439 | 0.358 | 0.094 | 0.311 | 吃东西 |
| 灶台 | `stove` | 0.594 | 0.406 | 0.106 | 0.264 | 做饭 |
| 床铺 | `bed` | 0.714 | 0.406 | 0.191 | 0.177 | 睡觉 |
| 货厢 | `container` | 0.379 | 0.150 | 0.545 | 0.518 | 可行走的主活动区 |
| 机枪位 | `gun` | 0.396 | -0.10 | 0.366 | 0.228 | 战斗专用（车顶） |
| 雷达位 | `radar` | 0.763 | -0.10 | 0.190 | 0.226 | 装备挂载 |

**区域→姿势映射**：

| 区域 | 姿势 | 对应图片后缀 |
|------|------|------------|
| cabin | drive | `_drive_` |
| table | eat | `_eat_` |
| stove | cook | `_cook_` |
| bed | sleep | `_sleep_` |
| container / outside | default | 无后缀 |

---

### 6.3 角色素材

#### 主角（5 种姿势差分）

**林砾**：
| 姿势 | 文件 |
|------|------|
| 默认（站立） | `chibi_linli_20260409053601.png` |
| 驾驶 | `chibi_linli_drive_20260409070207.png` |
| 吃东西 | `chibi_linli_eat_20260409070212.png` |
| 做饭 | `chibi_linli_cook_20260409070159.png` |
| 睡觉 | `chibi_linli_sleep_20260409073014.png` |

**陶夏**：
| 姿势 | 文件 |
|------|------|
| 默认（站立） | `chibi_taoxia_20260409053853.png` |
| 驾驶 | `chibi_taoxia_drive_20260409070148.png` |
| 吃东西 | `chibi_taoxia_eat_20260409070156.png` |
| 做饭 | `chibi_taoxia_cook_20260409070214.png` |
| 睡觉 | `chibi_taoxia_sleep_20260409073033.png` |

#### 特殊 NPC（单一立绘）

| NPC ID | 文件 |
|--------|------|
| shen_he | `chibi_npc_shen_he_20260409101614.png` |
| han_ce | `chibi_npc_han_ce_20260409102702.png` |
| wu_shiqi | `chibi_npc_wu_shiqi_20260409102746.png` |
| bai_shu | `chibi_npc_bai_shu_20260409101846.png` |
| zhao_miao | `chibi_npc_zhao_miao_20260409101609.png` |
| ji_wei | `chibi_npc_ji_wei_20260409120514.png` |
| old_gan | `chibi_npc_old_gan_20260409120642.png` |
| dao_yu | `chibi_npc_dao_yu_20260409120745.png` |
| xie_ling | `chibi_npc_xie_ling_20260409120841.png` |
| meng_hui | `chibi_npc_meng_hui_20260409120916.png` |
| ming_sha | `chibi_npc_ming_sha_20260409121030.png` |
| a_xiu | `chibi_npc_a_xiu_20260409121138.png` |
| cheng_yuan | `chibi_npc_cheng_yuan_20260409121235.png` |
| su_mo | `chibi_npc_su_mo_20260409121902.png` |

#### 势力通用路人

| 势力 | 文件 |
|------|------|
| farm（农耕） | `chibi_npc_farmer_20260409100017.png` |
| tech（科技） | `chibi_npc_tech_20260409100016.png` |
| scav（拾荒） | `chibi_npc_scavenger_20260409100005.png` |
| scholar（学者） | `chibi_npc_monk_20260409100009.png` |

#### 额外路人池

通用随机路人，可出现在任意势力聚落：
- `chibi_npc_han_ce_20260409102125.png`
- `chibi_npc_wu_shiqi_20260409101613.png`
- `chibi_npc_a_xiu_20260409113139.png`

---

### 6.4 角色数据结构

每个纸娃娃角色（主角和 NPC）共用以下结构：

```lua
{
    id = "linli",              -- 角色 ID（主角用 "linli"/"taoxia"，NPC 用 npc_id）
    zone = "cabin",            -- 当前区域
    x = 0.5, targetX = 0.5,   -- 区域内归一化 x 坐标 (0~1)
    facing = 1,                -- 朝向：1=右, -1=左
    scaleX = 1,                -- 当前渲染缩放（纸片翻转动画用）
    state = "idle",            -- 状态机："idle" | "walk" | "turning"
    stateTimer = 0,            -- 当前状态剩余时间
    switchTimer = 25,          -- 下次切换区域倒计时（秒）
    flipTimer = 0,             -- 翻转动画计时器
    flipFrom = 1,              -- 翻转起始方向
    walkTime = 0,              -- 行走总时长（颠动相位）
    idleTime = 0,              -- idle 累计时间（呼吸动画相位）
    emote = nil,               -- 当前气泡表情（nil=无）
    emoteTimer = 0,            -- 表情显示计时
    emoteCD = 5~15,            -- 下次表情倒计时（秒）
    clickCD = 0,               -- 点击冷却（秒）
    clickBounce = 0,           -- 弹跳动画计时
    clickCombo = 0,            -- 连击次数 (0~3)
    clickComboTimer = 0,       -- 连击窗口计时

    -- NPC 专用字段
    npcImage = nil,            -- NPC 固定图片路径（主角无此字段）
}
```

---

### 6.5 AI 状态机

#### 状态流转

```
idle (站立呼吸)
  ↓ stateTimer 归零 → 选择新目标位置
  ↓
walk (朝 targetX 移动)
  ↓ 到达 targetX
  ↓
idle
  ↓ switchTimer 归零 → 切换区域
  ↓
turning (纸片翻转 → 新朝向)
  ↓ 翻转完成
  ↓
idle (新区域)
```

#### 区域切换规则

| 条件 | 可选区域 | 切换间隔 |
|------|---------|---------|
| 行驶中 | cabin, table, stove, bed, container | 20~40 秒 |
| 停车中 | 同上 + outside | 20~40 秒 |
| 战斗中 | 陶夏锁定 gun 位，林砾正常 | 不切换 |

**特殊规则**：
- 行驶中至少保证一人在 cabin（驾驶位）
- 固定姿势区域（table/stove/bed）停留 8~15 秒后返回 container
- NPC 路人只在 outside 区域活动

---

### 6.6 动画参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `CHIBI_H_RATIO` | 0.32 | 纸娃娃高度占卡车高度的比例 |
| `CHIBI_WALK_SPEED` | 0.10 | 移动速度（归一化/秒） |
| `WOBBLE_FREQ` | 2.2 Hz | 行走颠动频率 |
| `WOBBLE_PX` | 6.0 px | 行走颠动幅度 |
| `WALK_SQUASH_AMP` | 0.04 | 行走挤压拉伸幅度（±4%） |
| `WALK_LEAN_DEG` | 2.5° | 行走倾斜角度 |
| `FLIP_DURATION` | 0.25 秒 | 纸片翻转时长 |
| `BREATH_FREQ` | 0.6 Hz | idle 呼吸频率 |
| `BREATH_AMP` | 0.035 | idle 呼吸缩放幅度（±3.5%） |
| `IDLE_BOB_FREQ` | 0.8 Hz | idle 微浮动频率 |
| `IDLE_BOB_PX` | 2.5 px | idle 微浮动幅度 |
| `CLICK_BOUNCE_DUR` | 0.35 秒 | 点击弹跳持续时间 |
| `CLICK_BOUNCE_PX` | 10 px | 点击弹跳高度 |

**动画叠加顺序**：基础位置 → 行走颠动/idle 浮动 → 点击弹跳 → 纸片翻转缩放

---

### 6.7 气泡表情系统

每个角色定期弹出气泡表情，表情内容根据上下文变化：

| 表情池 | 内容 | 触发场景 |
|--------|------|---------|
| `EMOTES_IDLE` | 💤 ... ～♪ 😊 🤔 | 站立等待 |
| `EMOTES_WALK` | ♪ 🎵 ! → | 行走中 |
| `EMOTES_CABIN` | 🚗 👀 😤 ～♪ 🛣️ | 驾驶室 |
| 势力表情 (farm) | 🌾 🌱 ☀️ 💧 👋 ... | NPC 农耕势力 |
| 势力表情 (tech) | ⚙ 📡 🔋 💡 👋 ... | NPC 科技势力 |
| 势力表情 (scav) | 🔧 🔩 📦 🔪 👋 ... | NPC 拾荒势力 |
| 势力表情 (scholar) | 📖 🕯 ✍️ 🔔 👋 ... | NPC 学者势力 |

**时序参数**：
- 表情间隔：8~20 秒（随机）
- 显示时长：2.5 秒
- 淡入淡出：0.4 秒

---

### 6.8 点击交互系统

点击纸娃娃触发弹跳动画和对话气泡。

**机制**：
- 冷却时间：2.0 秒
- 连击窗口：4.0 秒内多次点击判定为连击
- 连击等级：3 级，台词逐级升级
- 碰撞检测：渲染时记录 `_hitX, _hitY, _hitW, _hitH`，命中检测加 4px padding

**主角点击台词**：

| 等级 | 林砾 | 陶夏 |
|------|------|------|
| 1 级 | "嗯？怎么了～"、"在看路呢"、"嘿嘿" | "嘿！"、"找我？"、"怎么啦" |
| 2 级 | "别戳啦～"、"好啦好啦" | "别闹～"、"好啦好啦" |
| 3 级 | "再戳不理你了！"、"哼！" | "哼！"、"讨厌啦！" |

**NPC 点击台词**（按势力分池）：
- farm: "你好～"、"今年收成还行"、"要买点粮食吗"...
- tech: "有何指教"、"别碰设备"、"系统运转正常"...
- scav: "买卖？"、"小心点"、"别多管闲事"...
- scholar: "你好"、"这很有趣"、"记录一下…"...

---

### 6.9 NPC 路人系统

停车时在卡车外自动生成 NPC 路人。

**生成规则**：
- 触发条件：`setDriving(false)` 时调用 `spawnNPCs()`
- 数量：2~3 个
- 位置：only outside 区域

**候选优先级**（高→低）：

| 优先级 | 类型 | 来源 |
|--------|------|------|
| 10 | 聚落驻扎 NPC | 当前节点的 `residents` 列表 |
| 8 | 流浪 NPC | 当前节点的 `wandering_npcs` 列表 |
| 3 | 势力通用路人 | `FACTION_GENERIC_CHIBI` 池 |
| 1 | 额外路人 | `EXTRA_PASSERBY` 池 |

**清除时机**：`setDriving(true)` 时清空 `npcs_` 数组。

---

### 6.10 战斗模式联动

#### 玩家侧

战斗开始（`setCombatRenderer` 调用）时：
1. 陶夏保存当前区域 → `_savedZone`
2. 陶夏移动到 `gun`（机枪位），朝向左方面对敌人
3. 陶夏 AI 锁定（`switchTimer = 9999`），不再自动切换区域
4. 林砾正常行为不变

战斗结束（`clearCombatRenderer` 调用）时：
1. 陶夏恢复到 `_savedZone`（默认 `container`）
2. 清除锁定状态

#### 战斗卡车贴图

战斗期间卡车使用外观版贴图（有装甲外壳），按耐久度切换受损等级：

| 等级 | 耐久度范围 | 文件 |
|------|-----------|------|
| pristine | > 70% | `edited_truck_home_exterior_v3_20260411053954.png` |
| light | 40%~70% | `edited_truck_damage_light_v3_20260411092433.png` |
| medium | 15%~40% | `edited_truck_damage_medium_v3_20260411092512.png` |
| heavy | < 15% | `edited_truck_damage_heavy_v4_20260411092816.png` |

实现方式：`drawTruck` 中查询 `combatRenderer_.getTruckImage()`，仅替换渲染图片，不影响 `computeTruckBounds` 的尺寸计算（所有战斗贴图尺寸与日常贴图一致）。

#### 敌方纸娃娃

敌方车辆也有纸娃娃系统，由 `driving_combat.lua` 管理：

```lua
ENEMY_VISUALS = {
    ambush_light = {
        vehicle = "enemy_vehicle_raider_*.png",
        chibis  = { "chibi_npc_scavenger_*.png" × 2 },
        wheels  = { ... },
        crewZone = { x=0.207, y=0.134, w=0.305, h=0.367 },
    },
    ambush_medium = {
        vehicle = "enemy_vehicle_armed_*.png",
        chibis  = { "chibi_npc_tech_*.png", "chibi_npc_scavenger_*.png" },
        crewZone = { x=0.469, y=0.070, w=0.383, h=0.245 },
    },
    ambush_heavy = {
        vehicle = "enemy_vehicle_armored_*.png",
        chibis  = { "chibi_npc_han_ce_*.png" × 2 },
        crewZone = { x=0.398, y=0.012, w=0.467, h=0.309 },
    },
}
```

敌方纸娃娃数据结构：
```lua
{
    image   = "image/chibi_npc_*.png",
    phase   = 0~10,       -- 动画相位（随机初始化，避免同步）
    facing  = 1,          -- 朝向
    xNorm   = 0.25~0.75,  -- crewZone 内归一化位置
}
```

仅有呼吸/颠动动画，无 AI 行为和点击交互。

---

### 6.11 关键函数索引

| 函数 | 位置 | 说明 |
|------|------|------|
| `getChibiImage(c)` | driving_scene.lua | 根据区域/姿势选择图片 |
| `updateChibis(dt)` | driving_scene.lua | 主角 AI 状态机 + 动画更新 |
| `drawSingleChibi(...)` | driving_scene.lua | 单个纸娃娃渲染（含所有动画叠加） |
| `spawnNPCs()` | driving_scene.lua | 停车时生成 NPC 路人 |
| `checkChibiInput()` | driving_scene.lua | 点击碰撞检测与交互 |
| `setCombatRenderer(r)` | driving_scene.lua | 进入战斗模式（陶夏上机枪） |
| `clearCombatRenderer()` | driving_scene.lua | 退出战斗模式（陶夏归位） |
| `setDriving(bool)` | driving_scene.lua | 切换行驶/停车状态（触发 NPC 生成/清除） |

---

## 7. 未来计划

- [ ] 车辆改装外观叠加（货架、装甲等）
- [ ] 不同环境主题切换（沙漠、雪地、废墟）
- [ ] widget 高度可能需要根据屏幕比例自适应
- [ ] 更多 NPC 纸娃娃差分姿势
- [ ] 纸娃娃情绪系统（与对话/事件联动）

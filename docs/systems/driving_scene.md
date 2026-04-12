# 纸娃娃场景系统 (Chibi Scene) 技术文档

> 记录视差场景 + 纸娃娃角色系统的架构、参数、素材与调试经验。
> 系统支持多种场景模式（行驶 driving、探索 explore 等），统一管理背景渲染、角色 AI 和战斗插槽。

---

## 1. 架构概览

### 1.1 模块拆分

系统原为单文件 `driving_scene.lua`，现拆分为四个模块：

| 模块 | 文件 | 职责 |
|------|------|------|
| **ChibiScene** | `scripts/travel/chibi_scene.lua` | 场景核心：Widget 渲染管线、模式管理、视差背景、卡车/地面绘制、战斗插槽、输入分发 |
| **ChibiRenderer** | `scripts/travel/chibi_renderer.lua` | 角色系统：绘制（动画叠加）、AI 状态机、表情气泡、点击交互、NPC 生成与管理 |
| **ExploreMode** | `scripts/travel/explore_mode.lua` | 探索模式配置：zone 定义、zoneMap 映射，自注册到 ChibiScene |
| **CombatRenderer** | `scripts/travel/combat_renderer.lua` | 战斗渲染：敌方载具/步行角色、弹道特效、受击闪白、屏幕震动 |

### 1.2 依赖关系

```
screen_home.lua / screen_explore.lua / screen_truck.lua
            │
            ▼
      ┌─────────────┐
      │  ChibiScene  │◀── ExploreMode (自注册 "explore" 模式)
      └──────┬───────┘
             │ 调用
     ┌───────┴───────┐
     ▼               ▼
ChibiRenderer   CombatRenderer
(角色 AI/绘制)   (战斗视觉)
```

### 1.3 集成方式

```lua
-- 引入
local ChibiScene = require("travel/chibi_scene")
require("travel/explore_mode")  -- 自动注册 explore 模式，无需保存返回值

-- 创建 Widget
local widget = ChibiScene.createWidget({ height = 260, borderRadius = 8 })

-- 切换模式
ChibiScene.setMode("driving")   -- 卡车行驶
ChibiScene.setMode("explore")   -- 步行探索

-- 每帧更新
ChibiScene.update(dt)
```

---

## 2. 场景模式

### 2.1 模式配置结构

每个模式由以下字段定义：

```lua
{
    zones        = { ... },   -- zone 定义表（归一化坐标）
    hasVehicle   = true/false, -- 是否有卡车
    outsideScale = 1.0,        -- 车外/地面角色缩放
    scrollSpeed  = 50,         -- 视差滚动速度（像素/秒）
    zoneMap      = { ... },    -- 模式切换时的 zone 重映射（旧zone→新zone）
}
```

### 2.2 行驶模式 (driving)

- **hasVehicle**: `true`
- **scrollSpeed**: 50 px/s
- **特点**: 显示卡车车体、车轮、装备（炮台/雷达）、视差背景滚动
- **zone**: 见 §3.1

### 2.3 探索模式 (explore)

- **hasVehicle**: `false`
- **scrollSpeed**: 8 px/s（缓慢漂移）
- **特点**: 无卡车，角色站在地面，支持探索物品（箱子等）
- **zone**: 见 §3.2
- **定义文件**: `scripts/travel/explore_mode.lua`

### 2.4 模式切换与 zone 重映射

调用 `setMode()` 时，若目标模式定义了 `zoneMap`，角色当前 zone 会自动映射到新模式对应的 zone。映射时触发 0.3 秒淡入过渡动画。

```lua
-- explore → driving 映射示例
zoneMap = {
    ground_left   = "cabin",
    ground_center = "container",
    ground_right  = "table",
}

-- driving → explore 映射
zoneMap = {
    cabin     = "ground_left",
    table     = "ground_right",
    container = "ground_center",
    stove     = "ground_center",
    bed       = "ground_right",
    gun       = "ground_left",
    radar     = "ground_right",
}
```

---

## 3. 区域 (Zone) 定义

### 3.1 行驶模式 Zone (DRIVING_ZONES)

归一化坐标，相对卡车图片 1024x572：

| 区域 | 变量名 | x | y | w | h | 说明 |
|------|--------|-------|-------|-------|-------|------|
| 驾驶室 | `cabin` | 0.193 | 0.294 | 0.106 | 0.376 | 林砾开车 |
| 饭桌 | `table` | 0.439 | 0.358 | 0.094 | 0.311 | 吃东西 |
| 灶台 | `stove` | 0.594 | 0.406 | 0.106 | 0.264 | 做饭 |
| 床铺 | `bed` | 0.714 | 0.406 | 0.191 | 0.177 | 睡觉 |
| 货厢 | `container` | 0.379 | 0.150 | 0.545 | 0.518 | 可行走主活动区 |
| 机枪位 | `gun` | 0.396 | -0.10 | 0.366 | 0.228 | 战斗专用（车顶） |
| 雷达位 | `radar` | 0.763 | -0.10 | 0.190 | 0.226 | 装备挂载 |

**区域 → 姿势映射**:

| 区域 | 姿势 | 对应图片后缀 |
|------|------|------------|
| cabin | drive | `_drive_` |
| table | eat | `_eat_` |
| stove | cook | `_cook_` |
| bed | sleep | `_sleep_` |
| container / outside | default | 无后缀 |

### 3.2 探索模式 Zone (EXPLORE_ZONES)

归一化坐标，相对 widget 宽高：

| 区域 | x | y | w | h | 说明 |
|------|-------|-------|-------|-------|------|
| ground_left | 0.05 | 0.55 | 0.25 | 0.40 | 画面左侧 |
| ground_center | 0.30 | 0.55 | 0.30 | 0.40 | 画面中部 |
| ground_right | 0.60 | 0.55 | 0.30 | 0.40 | 画面右侧 |

---

## 4. 素材清单

### 4.1 视差背景

| 层 | 图片 | 尺寸 | speed | yStart | yEnd | 说明 |
|----|------|------|-------|--------|------|------|
| 天空 | `parallax_sky_*.png` | 1025x572 | 0.0 | 0.0 | 1.0 | 拉伸填充，不平铺 |
| 远景 | `parallax_far_v2_*.png` | 1025x572 | 0.05 | 0.0 | 0.85 | 废墟天际线剪影 |
| 中景 | `parallax_mid_*.png` | 1024x572 | 0.30 | 0.15 | 0.90 | 废弃建筑（可按区域切换） |
| 地面 | `parallax_ground_*.png` | 1024x572 | 1.0 | 0.68 | 1.0 | 破损路面 |

**中景变体**（按地形区域切换）：

| 区域 | 文件 |
|------|------|
| urban | `parallax_mid_20260408172203.png` |
| wild | `parallax_mid_wild_*.png` |
| canyon | `parallax_mid_canyon_*.png` |
| forest | `parallax_mid_forest_*.png` |

**绘制顺序**：天空 → 时段色调 → 远景 → 中景 → 地面

### 4.2 卡车 & 车轮

| 素材 | 文件 | 尺寸 | 说明 |
|------|------|------|------|
| 卡车车身 | `truck_home_clean.png` | 1024x572 | 空卡车面朝左 |
| 车轮 | `wheel.png` | 155x157 | nvgCircle 圆形裁剪 |

**卡车参数**：

```lua
truckH = widgetH * 0.70            -- 卡车高度占 widget 70%
WHEEL_POSITIONS = {
    { rx = 0.20, ry = 0.85 },      -- 前轮（中心位置）
    { rx = 0.77, ry = 0.85 },      -- 后轮
}
WHEEL_SIZE_RATIO = 0.28             -- 轮径占车高比例
roadSurface = widgetY + widgetH * 0.88  -- 路面位置
bounce = sin(scrollOffset * 0.07) * 1.5  -- 路面颠簸
```

### 4.3 战斗卡车贴图（按受损等级）

| 等级 | 耐久度范围 | 文件 |
|------|-----------|------|
| pristine | > 70% | `edited_truck_home_exterior_v3_*.png` |
| light | 40%~70% | `edited_truck_damage_light_v3_*.png` |
| medium | 15%~40% | `edited_truck_damage_medium_v3_*.png` |
| heavy | < 15% | `edited_truck_damage_heavy_v4_*.png` |

### 4.4 聚落停泊场景图

停车在聚落时替换视差背景显示的静态场景：

| 聚落 ID | 文件 |
|---------|------|
| greenhouse | `scene_greenhouse_*.png` |
| greenhouse_farm | `scene_greenhouse_farm_*.png` |
| tower | `scene_tower_*.png` |
| dome_outpost | `scene_dome_outpost_*.png` |
| ruins_camp | `scene_ruins_camp_*.png` |
| metro_camp | `scene_metro_camp_*.png` |
| bell_tower | `scene_bell_tower_*.png` |
| old_church | `scene_old_church_*.png` |
| underground_market | `scene_underground_market_*.png` |

### 4.5 装备图片

| 模块 | Lv1 | Lv2 | Lv3 |
|------|-----|-----|-----|
| turret | `equip_turret_lv1_*.png` | `equip_turret_lv2_*.png` | `equip_turret_lv3_*.png` |
| radar | `equip_radar_lv1_*.png` | `equip_radar_lv2_*.png` | `equip_radar_lv3_*.png` |

---

## 5. 纸娃娃 (Chibi) 角色系统

> 由 `chibi_renderer.lua` 管理。

### 5.1 角色素材

#### 主角（5 种姿势差分）

**林砾 (linli)**:
| 姿势 | 文件 |
|------|------|
| 默认 | `chibi_linli_*.png` |
| 驾驶 | `chibi_linli_drive_*.png` |
| 吃东西 | `chibi_linli_eat_*.png` |
| 做饭 | `chibi_linli_cook_*.png` |
| 睡觉 | `chibi_linli_sleep_*.png` |

**陶夏 (taoxia)**:
| 姿势 | 文件 |
|------|------|
| 默认 | `chibi_taoxia_*.png` |
| 驾驶 | `chibi_taoxia_drive_*.png` |
| 吃东西 | `chibi_taoxia_eat_*.png` |
| 做饭 | `chibi_taoxia_cook_*.png` |
| 睡觉 | `chibi_taoxia_sleep_*.png` |

#### 特殊 NPC

| NPC ID | chibi 文件 |
|--------|-----------|
| shen_he, han_ce, wu_shiqi, bai_shu, zhao_miao | 各有独立 chibi |
| ji_wei, old_gan, dao_yu, xie_ling, meng_hui | 各有独立 chibi |
| ming_sha, a_xiu, cheng_yuan, su_mo | 各有独立 chibi |

#### 势力通用路人

| 势力 | chibi 文件 |
|------|-----------|
| farm | `chibi_npc_farmer_*.png` |
| tech | `chibi_npc_tech_*.png` |
| scav | `chibi_npc_scavenger_*.png` |
| scholar | `chibi_npc_monk_*.png` |

### 5.2 角色数据结构

每个纸娃娃（主角和 NPC）共用以下状态表：

```lua
{
    id = "linli",              -- 角色 ID
    zone = "cabin",            -- 当前区域
    x = 0.5, targetX = 0.5,   -- 区域内归一化 x (0~1)
    facing = 1,                -- 朝向：1=右, -1=左
    scaleX = 1,                -- 渲染缩放（翻转动画）
    state = "idle",            -- "idle" | "walk" | "turning"
    stateTimer = 0,            -- 当前状态剩余时间
    switchTimer = 25,          -- 下次切换区域倒计时
    flipTimer = 0,             -- 翻转动画计时
    flipFrom = 1,              -- 翻转起始方向
    walkTime = 0,              -- 行走时长（颠动相位）
    idleTime = 0,              -- idle 累计时间（呼吸相位）
    emote = nil,               -- 当前气泡表情
    emoteTimer = 0,            -- 表情计时
    emoteCD = 5~15,            -- 下次表情倒计时
    clickCD = 0,               -- 点击冷却
    clickBounce = 0,           -- 弹跳动画计时
    clickCombo = 0,            -- 连击次数 (0~3)
    clickComboTimer = 0,       -- 连击窗口计时
    -- 战斗锁定字段
    _combatLocked = false,     -- 战斗中是否锁定 AI
    _savedZone = nil,          -- 进入战斗前的 zone（战斗结束时恢复）
    -- 淡入过渡
    _zoneFadeIn = 0,           -- zone 切换淡入计时（>0 时角色半透明）
    -- NPC 专用
    npcImage = nil,            -- NPC 固定图片路径
    npcEmotes = nil,           -- NPC 专属表情池
    npcFaction = nil,          -- NPC 势力 ID
}
```

### 5.3 AI 状态机

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

**区域切换规则**:

| 条件 | 可选区域 | 切换间隔 |
|------|---------|---------|
| 行驶中 | cabin, table, stove, bed, container | 20~40 秒 |
| 停车中 | 同上 + outside | 20~40 秒 |
| 探索模式 | ground_left, ground_center, ground_right | 20~40 秒 |
| 战斗中 | **锁定不切换**（`_combatLocked = true`） | — |

**特殊规则**:
- 行驶中保证至少一人在 cabin（驾驶位）
- 固定姿势区域（table/stove/bed）停留 8~15 秒后返回 container
- NPC 路人只在 outside 区域活动（不切换 zone）
- zone 切换时触发 0.3 秒淡入过渡（`_zoneFadeIn`），角色从透明到不透明

### 5.4 动画参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `CHIBI_H_RATIO` | 0.32 | 纸娃娃高度占场景高度比例 |
| `CHIBI_WALK_SPEED` | 0.10 | 移动速度（归一化/秒） |
| `WOBBLE_FREQ` | 2.2 Hz | 行走颠动频率 |
| `WOBBLE_PX` | 6.0 px | 行走颠动幅度 |
| `WALK_SQUASH_AMP` | 0.04 | 行走挤压拉伸幅度 |
| `WALK_LEAN_DEG` | 2.5 deg | 行走倾斜角度 |
| `FLIP_DURATION` | 0.25 s | 纸片翻转时长 |
| `ZONE_FADE_DURATION` | 0.3 s | zone 切换淡入过渡时长 |
| `BREATH_FREQ` | 0.6 Hz | idle 呼吸频率 |
| `BREATH_AMP` | 0.035 | idle 呼吸缩放幅度 |
| `IDLE_BOB_FREQ` | 0.8 Hz | idle 微浮动频率 |
| `IDLE_BOB_PX` | 2.5 px | idle 微浮动幅度 |
| `CLICK_BOUNCE_DUR` | 0.35 s | 点击弹跳持续时间 |
| `CLICK_BOUNCE_PX` | 10 px | 点击弹跳高度 |

**动画叠加顺序**：基础位置 → 行走颠动/idle 浮动 → 点击弹跳 → 纸片翻转缩放 → zone 淡入 alpha

### 5.5 气泡表情系统

| 表情池 | 内容 | 触发场景 |
|--------|------|---------|
| `EMOTES_IDLE` | 💤 ... ~♪ 😊 🤔 | 站立等待 |
| `EMOTES_WALK` | ♪ 🎵 ! → | 行走中 |
| `EMOTES_CABIN` | 🚗 👀 😤 ~♪ 🛣️ | 驾驶室 |
| `EMOTES_TABLE` | 🍚 😋 🥢 好吃 🍜 | 饭桌 |
| `EMOTES_STOVE` | 🔥 🍳 好香 👨‍🍳 ♨️ | 灶台 |
| `EMOTES_BED` | 💤 😴 zzZ 😌 ... | 床铺 |
| `EMOTES_OUTSIDE` | 🌿 ☁️ 😌 🔍 | 车外/地面 |
| 势力 farm | 🌾 🌱 ☀️ 💧 👋 ... | NPC 农耕势力 |
| 势力 tech | ⚙ 📡 🔋 💡 👋 ... | NPC 科技势力 |
| 势力 scav | 🔧 🔩 📦 🔪 👋 ... | NPC 拾荒势力 |
| 势力 scholar | 📖 🕯 ✍️ 🔔 👋 ... | NPC 学者势力 |

**时序参数**: 间隔 8~20s，显示 2.5s，淡入淡出 0.4s

### 5.6 点击交互

- **冷却**: 2.0 秒
- **连击窗口**: 4.0 秒内多次点击 → 连击升级（最高 3 级）
- **碰撞检测**: 渲染时记录 `_hitX/_hitY/_hitW/_hitH`，点击检测加 4px padding

**主角台词** (3 级连击):

| 等级 | 林砾 | 陶夏 |
|------|------|------|
| 1 级 | "嗯？怎么了~"、"在看路呢" | "嗯"、"干嘛"、"…有事？" |
| 2 级 | "别戳啦~"、"好啦好啦" | "够了"、"别碰"、"烦" |
| 3 级 | "再戳不理你了！"、"哼！" | "再碰试试"、"…（怒）" |

### 5.7 NPC 路人系统

停车时自动生成 NPC 路人（2~3 个），出发时清除。

**候选优先级**:

| 优先级 | 类型 | 来源 |
|--------|------|------|
| 10 | 聚落驻扎 NPC | `NpcManager.get_npcs_for_settlement()` |
| 8 | 流浪 NPC | `WanderingNpc.get_wanderers_at()` |
| 3 | 势力通用路人 | `FACTION_GENERIC_CHIBI` 池 |
| 1 | 额外路人 | `EXTRA_PASSERBY` 池 |

---

## 6. 战斗模式联动

> 由 `chibi_scene.lua` 的 `setCombatRenderer()`/`clearCombatRenderer()` 管理，战斗渲染由 `combat_renderer.lua` 负责。

### 6.1 进入战斗 (`setCombatRenderer`)

1. **两个角色都被锁定** (`_combatLocked = true`)，保存各自当前 zone 到 `_savedZone`
2. 触发 0.3 秒淡入过渡
3. 按模式分配位置:
   - **行驶模式**: 陶夏 → `gun`（机枪位），林砾 → `cabin`（驾驶舱）
   - **探索模式**: 陶夏 → `ground_left` x=0.65（面朝右方敌人），林砾 → `ground_left` x=0.25（后方）
4. 两人 AI 锁定 (`stateTimer=999, switchTimer=9999`)

### 6.2 退出战斗 (`clearCombatRenderer`)

1. 解除锁定 (`_combatLocked = false`)
2. 恢复 `_savedZone`（若目标 zone 在当前模式不存在，回退到默认 zone）
3. 触发 0.3 秒淡入过渡
4. 重置 AI 计时器

### 6.3 战斗渲染模式 (combat_renderer.lua)

| 模式 | 场景 | 说明 |
|------|------|------|
| vehicle | 行驶中遇敌 | 敌方载具 + 车上船员 + 速度线 + 卡车偏移 |
| ground | 探索中遇敌 | 敌方步行立绘 + 简化震动 |

**敌方载具类型**:

| 类型 | 载具 | 船员 | 说明 |
|------|------|------|------|
| ambush_light | raider 轻卡 | scavenger x2 | 拾荒者 |
| ambush_medium | armed 武装车 | tech + scavenger | 科技混合 |
| ambush_heavy | armored 装甲车 | han_ce x2 | 重装 |

---

## 7. 渲染管线 (Widget:Render)

```
┌──────────────────────────────────────────────────────┐
│ 1. nvgSave + scissor                                 │
│ 2. 战斗抖动 (combatRenderer.getScreenShake)          │
│ 3. 背景层:                                           │
│    ├─ 聚落场景图 (如有)                               │
│    └─ 天空 → 时段色调 → 远景 → 中景 → 地面           │
│ 4. 掉落物 (行驶模式)                                  │
│ 5. 场景主体:                                          │
│    ├─ 行驶: computeTruckBounds → 驾驶舱角色           │
│    │         → 卡车 → 装备 → 车轮                     │
│    └─ 探索: computeGroundBounds                       │
│ 6. 战斗渲染层 (combatRenderer.render)                 │
│ 7. 探索物品 (箱子等)                                  │
│ 8. 角色绘制:                                          │
│    ├─ 行驶: 货厢角色 → 车外角色 + NPC                 │
│    └─ 探索: 地面角色 + NPC                            │
│ 9. 天气粒子                                           │
│ 10. 拾取浮字                                          │
│ 11. nvgRestore                                        │
└──────────────────────────────────────────────────────┘
```

---

## 8. 环境系统

### 8.1 时段色调 (TIME_TINTS)

| 时段 | 顶色 RGBA | 底色 RGBA |
|------|-----------|-----------|
| dawn | 255,140,60,70 | 255,190,120,30 |
| dusk | 200,80,30,90 | 220,140,60,40 |
| night | 15,15,50,180 | 25,25,70,100 |
| day | 无叠加 | — |

### 8.2 天气效果

| 天气 | 效果 |
|------|------|
| clear | 无 |
| cloudy | 顶部半透明暗层 |
| fog | 双层雾带（中部 + 底部） |
| rain | 25 条斜线粒子 |
| snow | 18 个雪花粒子（带漂移） |

---

## 9. 公共 API 速查

### ChibiScene (chibi_scene.lua)

| 函数 | 说明 |
|------|------|
| `createWidget(props)` | 创建场景 Widget |
| `update(dt)` | 每帧更新 |
| `setMode(name)` | 切换场景模式 ("driving" / "explore") |
| `getModeName()` | 获取当前模式名 |
| `registerMode(name, config)` | 注册自定义模式 |
| `setDriving(bool)` | 切换行驶/停车（触发 NPC 生成/清除，zone 调整） |
| `setScrolling(bool)` | 仅控制背景滚动开关，不触发 zone 重置 |
| `setEnvironment(env)` | 设置环境 { region, weather, timeOfDay } |
| `setSettlement(id)` / `clearSettlement()` | 聚落停泊场景图 |
| `setCombatRenderer(r)` | 进入战斗（锁定双角色） |
| `clearCombatRenderer()` | 退出战斗（恢复双角色） |
| `setDrops(drops)` / `setDropCallback(cb)` | 掉落物管理 |
| `setExploreItems(items)` / `markExploreItemLooted(id)` / `clearExploreItems()` | 探索物品管理 |
| `setChibiClickCallback(cb)` | 角色点击回调 |
| `setState(state)` | 设置游戏状态（装备显示用） |
| `getChibis()` | 获取主角数组 |
| `getSceneBounds()` | 获取场景 bounds |
| `reset()` | 重置全部状态 |

### ChibiRenderer (chibi_renderer.lua)

| 函数 | 说明 |
|------|------|
| `createChibi(id, zone, facing)` | 创建角色状态表 |
| `resetChibi(c, zone, x, facing, delay, switchT)` | 重置角色 |
| `getChibiImage(c)` | 获取角色当前姿势图片 |
| `drawSingleChibi(nvg, c, x, y, w, h)` | 绘制单个角色（含动画 + 表情 + 淡入） |
| `updateAll(dt, chibis, npcs, zoneDefs, isDriving, combatLocked)` | 更新所有角色 AI |
| `checkChibiInput(chibis, npcs, mx, my, cb)` | 点击检测 |
| `spawnNPCs(gameState)` | 生成 NPC 路人 |
| `clearNPCs()` / `getNPCs()` | NPC 管理 |

---

## 10. 调试经验

### 10.1 已解决的问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 轮子太小 | WHEEL_SIZE_RATIO 太低 | 分析像素数据得到真实比例，设为 0.28 |
| 轮子悬浮 | ry 是轮胎底部不是中心 | 改为 ry=0.85（轮心位置） |
| 轮子拉伸 | 用正方形绘制 155x157 图 | 按 imgW/imgH 宽高比计算 drawW |
| 轮子旋转方向反 | 正角度=顺时针 vs 车朝左 | 取负角度 |
| 杂物飘在空中 | near 图内容在上部(19%-41%) | yStart=0.68, yEnd=1.30 大幅下移 |
| 远景看不见 | v1 图 99.6% 透明 | 重新生成 v2 图（密度 78.8%） |
| 天空接缝 | 平铺有重复 | speed=0 改为拉伸填充 |
| 场景面板水平溢出 | `width="100%"` + margin 超出父容器 | 用 padding 容器包裹，不加 margin |
| 场景面板顶部溢出 | 无 paddingTop | 外层 Panel 加 `paddingTop` |
| 战斗时林砾闲逛 | `setCombatRenderer` 只处理陶夏 | 改为锁定双角色，用 `_combatLocked` 标记 |
| 探索模式战斗锁定失效 | 判断条件是 `zone == "gun"` | 改为 `_combatLocked` flag 判断 |
| 切换区域瞬移 | 直接 `c.zone = newZone; c.x = 0.5` | 添加 `_zoneFadeIn` 淡入过渡动画（0.3s） |

### 10.2 关键教训

1. **先分析图片再定位**: 用像素扫描确定内容分布区域，不要凭感觉设参数
2. **near 图陷阱**: 内容可能只在图片顶部窄带，需大幅下移
3. **speed=0 用拉伸**: 静态背景不平铺，避免接缝
4. **车轮比例**: 从车身裁切的轮图不是 1:1，需保持原始宽高比
5. **战斗锁定要双向**: `setCombatRenderer` 和 `clearCombatRenderer` 必须处理所有角色
6. **CSS 盒模型陷阱**: `width="100%"` + margin 会溢出，用 padding 容器替代
7. **zone 切换要过渡**: 避免瞬移，用淡入动画平滑切换

---

## 11. 未来计划

- [ ] 车辆改装外观叠加（货架、装甲等）
- [ ] 不同环境主题切换（沙漠、雪地等）
- [ ] widget 高度按屏幕比例自适应
- [ ] 更多 NPC 纸娃娃差分姿势
- [ ] 纸娃娃情绪系统（与对话/事件联动）
- [ ] 更多场景模式（据点防御、交易场景等）

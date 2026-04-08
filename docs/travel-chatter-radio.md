# 行驶中系统：车内日常对话 & 收音机

## 概览

两套行驶阶段的氛围系统，为挂机行程增添陪伴感和互动感。

**设计原则**：「有就多赚一点，没有也不亏」——奖励关注但不惩罚忽视，不需要动脑。

```
scripts/
├── travel/
│   ├── chatter.lua             # 车内日常对话逻辑
│   └── radio.lua               # 收音机/无线电逻辑
├── core/
│   └── flow.lua                # 生命周期管理（init / cleanup）
├── ui/
│   └── screen_home.lua         # UI 渲染 + 状态驱动
└── ...

assets/
└── configs/
    ├── chatter.json            # 对话数据池（18 条）
    └── radio_broadcasts.json   # 广播数据池（27 条）
```

> **配置加载**：JSON 配置存放在 `assets/configs/`，代码通过 `DataLoader.load("configs/xxx.json")` 加载（`assets/` 是引擎资源根目录）。

---

## 一、车内日常对话 (Chatter)

### 功能

行驶中定时弹出林砾/陶夏的短对话气泡，部分对话可点击回应获得关系加成。

### 时序参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 首次延迟 | 15-20s | 出发后等待一段时间再弹 |
| 后续间隔 | 25-40s | 两条对话之间的随机间隔 |
| 显示时长 | 8s（默认） | 每条对话可自定义 duration |
| 单趟上限 | 10 条 | 避免长途全是对话 |

### 数据结构 (chatter.json)

```jsonc
{
  "dialogues": [
    {
      "id": "CHAT_001",              // 唯一 ID
      "speaker": "taoxia",           // 说话人: "taoxia" | "linli"
      "text": "路上好安静啊……",       // 对话内容
      "weight": 50,                  // 抽取权重
      "duration": 8,                 // 显示秒数
      "edge_types": [],              // 路况过滤（空 = 不限）: "main_road"|"path"|"shortcut"
      "progress_range": [0, 1],      // 行程进度过滤: [最小, 最大]
      "required_flags": [],          // 需要的 flag（全满足才出现）
      "forbidden_flags": [],         // 禁止的 flag（有任意一个就不出现）
      "response": {                  // 可选回应（null = 无回应）
        "text": "现在只剩我们了。",    //   回应按钮文字
        "effect": {                  //   回应效果
          "relation_taoxia": 1,      //     关系值变化
          "relation_linli": 0,
          "set_flag": null           //     设置 flag
        }
      }
    }
  ]
}
```

### 筛选逻辑

每次定时器到期，从对话池中筛选候选：

1. **去重**：本趟已展示过的对话排除
2. **进度范围**：当前行程进度不在 `progress_range` 内的排除
3. **路况过滤**：`edge_types` 非空时，当前路段类型不匹配的排除
4. **flag 过滤**：`required_flags` 未全满足或 `forbidden_flags` 命中的排除
5. **加权随机**：从候选中按 `weight` 加权随机抽取一条

### API

```lua
local Chatter = require("travel/chatter")

-- 创建初始状态（出发时由 flow.lua 调用）
state.flow.chatter = Chatter.init()

-- 每帧驱动（由 screen_home.update 调用）
Chatter.update(state, dt, progress, segment)

-- 获取当前正在显示的对话（nil = 无）
local cur = Chatter.get_current(state)
-- cur = { id, speaker, text, response, duration, shown_time }

-- 玩家点击回应（应用 effect 后对话消失）
Chatter.respond(state)

-- 手动关闭当前对话
Chatter.dismiss(state)
```

---

## 二、收音机/无线电 (Radio)

### 功能

行驶中可开关的收音机，三个频道轮播不同广播内容，偶尔附带小奖励。

### 频道

| ID | 名称 | 内容风格 | 广播数 |
|----|------|---------|--------|
| `mingsha` | 鸣砂 | 正式播报、生存知识、路况提醒 | 10 |
| `settlement` | 聚落 | 民间八卦、聚落动态、人情味 | 9 |
| `mystery` | ??? | 神秘信号、密码片段、异常现象 | 8 |

### 时序参数

| 参数 | 值 | 说明 |
|------|-----|------|
| 开启后首条延迟 | 5s | 打开收音机后很快播第一条 |
| 轮换间隔 | 20-30s | 两条播报之间的随机间隔 |
| 切台延迟 | 2s | 切换频道后快速播新内容 |
| 显示时长 | 10s（默认） | 每条可自定义 duration |

### 数据结构 (radio_broadcasts.json)

```jsonc
{
  "broadcasts": {
    "mingsha": [
      {
        "id": "RADIO_MS_001",            // 唯一 ID
        "text": "这里是鸣砂，正在...",     // 播报内容
        "weight": 50,                    // 抽取权重
        "duration": 10,                  // 显示秒数
        "reward": null                   // 可选奖励（见下方）
      },
      {
        "id": "RADIO_MS_005",
        "text": "经过验证的情报：...",
        "weight": 45,
        "duration": 11,
        "reward": {                      // 可领取的奖励
          "type": "info",                //   类型: "credits"|"info"|"flag"
          "value": "greenhouse_water",   //   值（金额/flag名/情报名）
          "desc": "获得情报：温室净水充裕"  //   玩家提示文字
        }
      }
    ],
    "settlement": [ ... ],
    "mystery": [ ... ]
  }
}
```

### 奖励类型

| type | 效果 | 示例 |
|------|------|------|
| `credits` | 加金币 | `{ "type": "credits", "value": 15 }` |
| `info` | 情报提示（目前仅展示） | `{ "type": "info", "value": "trade_hint" }` |
| `flag` | 设置全局 flag | `{ "type": "flag", "value": "heard_mystery_signal" }` |

### API

```lua
local Radio = require("travel/radio")

-- 创建初始状态（出发时由 flow.lua 调用）
state.flow.radio = Radio.init()

-- 每帧驱动（由 screen_home.update 调用）
Radio.update(state, dt)

-- 开关收音机
Radio.toggle(state)

-- 切换频道
Radio.switch_channel(state, "settlement")

-- 查询状态
Radio.is_on(state)           -- boolean
Radio.get_channel(state)     -- string
Radio.get_current(state)     -- table|nil (当前播报)

-- 领取当前播报的奖励
local reward = Radio.claim_reward(state)
```

---

## 三、生命周期

### 初始化 (flow.lua)

在 `start_travel()` 和 `start_exploration()` 中：

```lua
state.flow.chatter = Chatter.init()
state.flow.radio   = Radio.init()
```

### 清理 (flow.lua)

在 `finish_trip()` 中：

```lua
state.flow.chatter = nil
state.flow.radio   = nil
```

### 兼容老存档 (screen_home.lua)

`M.create()` 中检测：如果行驶中但 `state.flow.chatter/radio` 为 nil（老存档中途加载），自动执行 late-init：

```lua
if isTravelling then
    if not state.flow.chatter then
        state.flow.chatter = Chatter.init()
    end
    if not state.flow.radio then
        state.flow.radio = Radio.init()
    end
end
```

---

## 四、UI 渲染 (screen_home.lua)

### 布局位置

行驶视图 `createTravelView()` 的子元素顺序：

```
1. 行驶进度卡片（路段 + 目的地 + 进度条）
2. ★ 车内对话气泡（有对话时显示，无则不占空间）
3. ★ 收音机面板（始终显示，可开关）
4. 活跃订单列表
5. 积压警告
6. 货舱概览
```

### 对话气泡 (createChatterBubble)

- 无对话时返回 `nil`，**不插入 contentChildren**，不占布局空间
- 有对话时显示：说话人名（带角色颜色）+ 内容 + 可选回应按钮
- 边框颜色按说话人区分：林砾蓝 `{80,140,200}`、陶夏橙 `{200,130,80}`

### 收音机面板 (createRadioPanel)

- 始终渲染，关闭状态下显示灰色底 + "开启"按钮
- 开启时显示：频道切换行（3 个按钮）+ 播报内容 + 可领取奖励按钮
- 背景色：开启时偏绿 `{28,36,28}`，关闭时灰色 `{36,36,36}`

### 状态变化检测

`M.update()` 中用模块级追踪变量检测 4 种状态变化，任一变化时调用 `r.navigate("home")` 重建 UI：

| 追踪变量 | 检测内容 |
|----------|---------|
| `_prevChatterId` | 对话出现 / 消失 / 切换 |
| `_prevRadioOn` | 收音机开 / 关 |
| `_prevRadioCh` | 频道切换 |
| `_prevBroadcastId` | 播报出现 / 消失 / 切换 |

**重要**：`M.create()` 中必须将追踪变量初始化为**当前真实状态**（不是 nil），否则 Lua 的 `nil ~= false` 会导致每帧误判为变化，触发无限重建循环。

---

## 五、扩展指南

### 添加新对话

编辑 `assets/configs/chatter.json`，在 `dialogues` 数组中添加新条目：

```json
{
  "id": "CHAT_NEW",
  "speaker": "taoxia",
  "text": "新的对话内容……",
  "weight": 50,
  "duration": 8,
  "edge_types": [],
  "progress_range": [0, 1],
  "required_flags": [],
  "forbidden_flags": [],
  "response": null
}
```

- `id` 必须全局唯一
- `response` 为 null 表示纯展示，不可回应
- `weight` 越大越容易被抽到

### 添加新广播

编辑 `assets/configs/radio_broadcasts.json`，在对应频道数组中添加：

```json
{
  "id": "RADIO_XX_NEW",
  "text": "新的播报内容……",
  "weight": 50,
  "duration": 10,
  "reward": null
}
```

### 添加新频道

1. 在 `radio.lua` 的 `M.CHANNELS` 和 `M.CHANNEL_NAMES` 中添加新频道
2. 在 `assets/configs/radio_broadcasts.json` 的 `broadcasts` 中添加对应键的数组
3. 无需修改 UI 代码（频道按钮基于 `CHANNELS` 自动生成）

### 调整时序

直接修改 `chatter.lua` / `radio.lua` 顶部的配置常量：

```lua
-- chatter.lua
M.FIRST_DELAY_MIN  = 15
M.FIRST_DELAY_MAX  = 20
M.INTERVAL_MIN     = 25
M.INTERVAL_MAX     = 40
M.DISPLAY_DURATION = 8
M.MAX_PER_TRIP     = 10

-- radio.lua
M.FIRST_DELAY      = 5
M.INTERVAL_MIN     = 20
M.INTERVAL_MAX     = 30
M.DISPLAY_DURATION = 10
```

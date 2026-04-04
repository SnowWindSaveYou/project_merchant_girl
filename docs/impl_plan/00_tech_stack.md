# Phase 00 — 技术选型与工程结构

## 技术栈确认

| 层 | 技术 | 说明 |
|------|------|------|
| **脚本语言** | Lua | 游戏逻辑、数据、事件、UI 全部用 Lua 写 |
| **引擎宿主** | UrhoX（C/C++） | 提供窗口、输入、音频、资源系统、文件 IO、Lua 绑定 |
| **图形渲染** | NanoVG | 所有 2D 画面（地图、UI、立绘框、HUD）通过 NanoVG 矢量接口绘制 |
| **配置格式** | JSON | 事件表、商品表、路线表等全部 JSON，运行时 Lua 读取 |
| **存档格式** | JSON（本地文件） | 玩家状态序列化为 JSON，写入本地磁盘 |

> NanoVG 是即时模式（immediate mode）矢量渲染库，每帧调用绘制接口。  
> 所有 UI 和场景元素都是「每帧主动绘制」，没有对象树或组件系统，需要自行管理绘制状态。
> 当前项目默认由 UrhoX 宿主负责应用生命周期、输入分发、资源加载、Lua VM 管理，以及 NanoVG 渲染上下文创建。

---

## 工程目录结构

```
/scripts                    Lua 脚本根目录
  /core                     核心循环（时间推进、离线补偿、路线调度）
  /economy                  贸易、商品、物价
  /settlement               聚落状态、好感
  /events                   事件系统（随机池、触发、链式）
  /combat                   战斗系统（车载迎击、探索战）
  /character                角色、技能、关系
  /map                      地图、路线、资源点
  /narrative                剧情事件、贴贴、回忆
  /ui                       所有 NanoVG 绘制逻辑（按界面拆文件）
  /save                     存档读写、离线时间补偿
  /data_loader              JSON 配置读取与缓存
  main.lua                  入口，初始化各模块、进入主循环

/data                       只读配置 JSON，不存玩家状态
  events/
    guaji_random_events.json
  settlements/
    settlements.json
  goods/
    goods.json
  routes/
    routes.json
  combat/
    combat_config.json

/save                       运行时生成，存放玩家存档
  cache_main.json

/assets                     美术资源（字体、图片、图标）
  fonts/
  images/
```

---

## 模块约定

Lua 里没有类，用 table + 返回 module 的方式组织：

```lua
-- 示例：scripts/economy/goods.lua
local M = {}

function M.get_buy_price(goods_id, settlement_id, state)
  -- ...
end

function M.get_sell_price(goods_id, settlement_id, state)
  -- ...
end

return M
```

调用方：

```lua
local Goods = require("economy/goods")
local price = Goods.get_buy_price("food_can", "greenhouse", state)
```

**约定：所有模块只接受 state 作为数据入参，不直接持有全局状态，便于测试和存档。**

---

## 全局游戏状态（GameState）

GameState 是一个普通 Lua table，所有子系统共用同一个实例：

```lua
-- scripts/core/state.lua
local M = {}

function M.new()
  return {
    timestamp   = os.time(),   -- 上次保存时的时间戳（秒）

    truck = {
      durability  = 100,
      fuel        = 80,
      cargo_slots = 8,
      modules     = {},        -- { engine = 1, radar = 0, ... }
    },

    economy = {
      credits     = 200,
      goods       = {},        -- { [goods_id] = count }
    },

    settlements = {
      -- [settlement_id] = { goodwill = 0, supply = {}, demand = {} }
    },

    character = {
      linli = { relation = 0, skills = {} },
      taoxia = { relation = 0, skills = {} },
    },

    map = {
      unlocked_routes   = {},
      unlocked_nodes    = {},
      current_route     = nil,
    },

    narrative = {
      story_flags   = {},   -- Set-like: { [flag_id] = true }
      memories      = {},
    },

    flags = {},              -- 全局旗标，{ [flag_id] = true }
  }
end

return M
```

---

## 旗标（Flag）系统

```lua
-- scripts/core/flags.lua
local M = {}

function M.set(state, flag_id)
  state.flags[flag_id] = true
end

function M.has(state, flag_id)
  return state.flags[flag_id] == true
end

function M.clear(state, flag_id)
  state.flags[flag_id] = nil
end

return M
```

旗标命名约定：`flag_{模块}_{描述}`，例如 `flag_doll_resolved`、`flag_night_market_found`。

---

## JSON 配置加载

UrhoX 宿主层应向 Lua 暴露一个 `engine.read_file(path)` 接口，返回文件内容字符串。  
Lua 层用 `cjson` 或引擎内置 JSON 解析：

```lua
-- scripts/data_loader/loader.lua
local json = require("cjson")   -- 或引擎提供的 json 模块名
local M = {}
local _cache = {}

function M.load(path)
  if _cache[path] then return _cache[path] end
  local raw = engine.read_file(path)
  assert(raw, "无法读取配置文件: " .. path)
  local data = json.decode(raw)
  _cache[path] = data
  return data
end

return M
```

**所有配置在用到时懒加载，加载后缓存，运行时不重复读取。**

---

## 存档方案

UrhoX 当前提供两套可用存档能力：

- **方案一：本地存档（File API）**
- **方案二：云存档（clientCloud API）**

首版建议不是二选一，而是：

- **本地存档负责完整快照**：保存整份 `GameState`
- **云存档负责长期账号同步**：保存关键资源、进度、槽位摘要，后续再扩成完整云快照

### 方案一：本地存档（File API）

形式：JSON 文件，存在设备本地，主要用于**缓存与断线恢复**。

```lua
local file = File("save/cache_main.json", FILE_WRITE)
file:WriteString(cjson.encode({ gold = 9999, level = 10 }))
file:Close()

local file = File("save/cache_main.json", FILE_READ)
local data = cjson.decode(file:ReadString())
file:Close()
```

特点：

- 引擎自动做项目隔离 + 用户隔离，脚本只需写相对路径
- 最适合保存完整状态快照，读写逻辑直观，调试成本低
- 适合作为云端数据的本地缓存层

缺点：

- **WASM 平台刷新页面后数据丢失**，不适合做长期唯一存档
- 数据跟设备走，不天然跨设备

推荐封装：

```lua
-- scripts/save/save_local.lua
local cjson = require("cjson")
local M = {}

local CACHE_PATH = "save/cache_main.json"

function M.save(state)
  state.timestamp = os.time()
  local file = File(CACHE_PATH, FILE_WRITE)
  file:WriteString(cjson.encode(state))
  file:Close()
end

function M.load()
  local file = File(CACHE_PATH, FILE_READ)
  if not file then return nil end
  local raw = file:ReadString()
  file:Close()
  return cjson.decode(raw)
end

return M
```

### 方案二：云存档（clientCloud API）

形式：服务端键值对存储，跟 TapTap 账号绑定。

```lua
clientCloud:SetInt("gold", 9999)
clientCloud:Set("inventory", { "sword", "shield" })

clientCloud:Get("gold", {
    ok = function(values, iscores)
        local gold = iscores.gold or 0
    end
})
```

特点：

- 数据跟账号走，换设备不丢
- 整数类型（`SetInt` / `Add`）天然适合资源累计和排行榜
- 支持增量操作，例如 `Add("gold", 100)`，很适合挂机资源增长

缺点：

- 是**异步回调风格**，不能按本地文件那样同步读写处理
- 更适合存“关键字段”或“同步摘要”，直接上来存整份复杂状态时要先设计字段分层
- 需要考虑网络失败、重试、登录状态和本地兜底

推荐封装：

```lua
-- scripts/save/save_cloud.lua
local M = {}

function M.push_summary(state)
  clientCloud:SetInt("credits", state.economy.credits or 0)
  clientCloud:SetInt("relation_linli", state.character.linli.relation or 0)
  clientCloud:SetInt("relation_taoxia", state.character.taoxia.relation or 0)
  clientCloud:Set("profile_meta", {
    timestamp = state.timestamp,
    current_route = state.map.current_route,
  })
end

function M.pull_summary(callback)
  clientCloud:Get("credits", {
    ok = function(values, iscores)
      callback({
        credits = iscores.credits or 0,
      })
    end,
    fail = function(err)
      callback(nil, err)
    end
  })
end

return M
```

### 首版落地建议

#### 第一阶段（必须做）

- 用 **File API** 完成本地缓存
- 跑通启动恢复、自动保存、断线恢复、离线补偿
- 不设计正式“多存档槽位”概念

#### 第二阶段（推荐做）

- 接入 **clientCloud** 做账号绑定的正式主存档
- 先不同步整份 `GameState`，优先同步：
  - 信用点
  - 主线阶段
  - 角色关系值
  - 账号主进度摘要
  - 最近一次云存档时间

#### 第三阶段（再考虑）

- 如果后续验证网络稳定、字段结构稳定，再把完整云快照做起来
- 完整云快照建议拆为：
  - `profile_state`
  - `profile_meta`
  - `profile_progress`

### 离线时间补偿

无论本地还是云存档，离线收益都应基于 `state.timestamp` 计算：

```lua
-- scripts/save/offline.lua
local M = {}

local MAX_OFFLINE_SEC = 8 * 3600

function M.apply(state)
  local now = os.time()
  local elapsed = math.min(now - state.timestamp, MAX_OFFLINE_SEC)
  return elapsed
end

return M
```

上线流程建议：

1. 优先读本地缓存
2. 如果用户已登录 TapTap，再拉云端摘要
3. 比较本地时间戳和云端时间戳，决定是否提示覆盖/同步
4. 完成离线补偿后，再进入主界面并弹出“离线结算”

---

## NanoVG 渲染约定

NanoVG 是**即时模式**，没有持久化渲染树。每帧调用流程：

```lua
-- 每帧由 UrhoX 宿主回调 game_frame(vg, dt)
function game_frame(vg, dt)
  nvg.BeginFrame(vg, screen_w, screen_h, pixel_ratio)

  -- 按当前 UI 状态分发绘制
  ui_router.draw(vg, dt, current_screen, state)

  nvg.EndFrame(vg)
end
```

**UI 模块约定：每个界面是一个独立的 Lua 文件，导出 `draw(vg, dt, state)` 函数。**

```lua
-- scripts/ui/screen_trade.lua
local M = {}

function M.draw(vg, dt, state)
  -- 调用 nvg.* 接口绘制贸易界面
end

function M.on_input(event, state)
  -- 处理点击/触摸事件
end

return M
```

NanoVG 常用接口：

| 接口 | 用途 |
|------|------|
| `nvg.BeginPath / ClosePath` | 矩形、圆角、图形轮廓 |
| `nvg.FillColor / StrokeColor` | 填充与描边颜色 |
| `nvg.RoundedRect` | 卡片、按钮背景 |
| `nvg.Text / TextAlign` | 文字渲染 |
| `nvg.Image / ImagePattern` | 立绘、图标贴图 |
| `nvg.Scissor` | 裁剪区域（滚动列表） |
| `nvg.Save / Restore` | 矩阵/状态压栈 |

> 立绘和图标通过 `nvg.CreateImage` 预加载为 image handle，绘制时用 `nvg.ImagePattern` 填充。  
> 字体通过 `nvg.CreateFont` 注册，后续用 `nvg.FontFace` 切换。

### UrhoX 宿主职责

- 创建主窗口、驱动主循环，并把每帧 `dt` 传给 Lua 层
- 初始化 Lua VM，注册 `engine.*` 桥接接口
- 初始化 NanoVG 上下文，并在合适的渲染阶段交给 Lua UI 层绘制
- 负责输入事件转发，例如鼠标、触摸、键盘、滚轮
- 负责文件系统挂载，保证 Lua 能访问 `/data`、`/save`、`/assets`
- 负责图片、字体等底层资源加载，必要时给 Lua 返回资源句柄或封装接口

---

## 本阶段完成标准

- [ ] 工程目录建立，各模块空 `.lua` 文件就绪
- [ ] 引擎宿主可正确回调 `game_frame(vg, dt)`
- [ ] `engine.read_file / write_file` 接口验证通过
- [ ] `State.new()` 可创建完整初始状态
- [ ] `SaveLocal.save / load` 往返序列化无数据丢失
- [ ] 已明确正式方案为“单账号主存档 + 本地缓存”
- [ ] `offline.apply` 能输出正确的秒数差
- [ ] NanoVG 能在窗口上绘制一个文字和一个圆角矩形（冒烟测试）
- [ ] `DataLoader.load("data/events/guaji_random_events.json")` 可返回正确 table

---

## 下一步

→ [01_core_loop.md](01_core_loop.md)

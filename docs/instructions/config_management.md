# 配置管理规则

> 本文件是项目级开发约定，所有参与开发的人类和 AI 必须遵守。

---

## 1. 核心原则：配置与代码分离

**所有游戏数据配置必须集中存放在 `docs/configs/` 目录**，代码层（`scripts/`）不得硬编码游戏数据。

```
docs/configs/          ← 唯一的配置数据存放位置
scripts/               ← 只写逻辑，从配置加载数据
```

### 什么算"游戏数据配置"

- 随机事件定义（事件池、选项、结果）
- 商品/物品定义（ID、名称、价格、属性）
- 聚落/NPC 数据（位置、服务、初始好感）
- 路线/地图节点定义
- 订单模板
- 战斗/遭遇参数
- 对话/剧情文本
- 数值平衡参数（权重、概率、冷却）

### 什么不算配置（留在代码中）

- UI 布局参数（间距、颜色、字号）
- 引擎/框架层常量（物理步长、渲染参数）
- 纯逻辑性的常量（状态机枚举、事件名字符串）

---

## 2. 文件格式

### 主格式：JSON

所有机器可读配置使用 **JSON** 格式（`.json`）：

```
docs/configs/
├── guaji_random_events.json     # 随机事件配置（已存在）
├── goods_catalog.json           # 商品目录（待创建）
├── settlements.json             # 聚落数据（待创建）
├── orders_templates.json        # 订单模板（待创建）
└── ...
```

**为什么选 JSON**：
- 引擎内置 `cjson` 可直接解析
- 结构化、可验证
- 版本控制友好
- 人类和 AI 均可编辑

### 辅助格式：Markdown

对于复杂配置，可保留一份 **Markdown 可读版**（`.md`）作为人类参考，但 **JSON 是权威数据源**：

```
docs/guaji_random_events.md      ← 人类参考文档（辅助）
docs/configs/guaji_random_events.json  ← 权威数据源（代码加载此文件）
```

当两者内容冲突时，**以 JSON 为准**，并及时同步 Markdown。

---

## 3. 代码加载配置的标准做法

### 加载模式

```lua
local cjson = require("cjson")

--- 从 docs/configs/ 读取 JSON 配置
local function load_config(filename)
    local file = File:new(filename, FILE_READ)
    if not file then
        print("[Config] Failed to load: " .. filename)
        return nil
    end
    local text = file:ReadString()
    file:Close()
    return cjson.decode(text)
end

-- 使用
local events_data = load_config("configs/guaji_random_events.json")
```

### 注意事项

- `docs/configs/` 目录在构建时会被打包为资源目录，路径前缀为 `configs/`
- 配置文件只在初始化时加载一次，不要每帧读取
- 加载失败时必须有 fallback 或明确报错，不要静默失败

---

## 4. 新增配置的流程

1. **在 `docs/configs/` 创建 JSON 文件**，定义好 schema（字段名、类型、枚举值）
2. **在对应的 impl_plan 文档中记录**该配置文件的用途和字段说明
3. **修改代码**从 JSON 加载数据，移除硬编码
4. **（可选）创建 Markdown 参考文档**供人类阅读

---

## 5. 现有违规项（待修复）

| 文件 | 问题 | 修复方案 |
|------|------|---------|
| `scripts/events/event_pool.lua` | 10 个事件硬编码，未从 JSON 加载 | 改为从 `configs/guaji_random_events.json` 加载 |
| `scripts/economy/goods.lua` | 商品数据硬编码（如有） | 提取到 `configs/goods_catalog.json` |
| `scripts/core/state.lua` | 聚落初始数据硬编码（如有） | 提取到 `configs/settlements.json` |

> 优先修复 `event_pool.lua`，因为已有完整的 JSON 配置文件。

---

## 6. 配置文件命名约定

```
docs/configs/{系统名}_{数据类型}.json
```

示例：
- `guaji_random_events.json` — 挂机系统·随机事件
- `guaji_goods_catalog.json` — 挂机系统·商品目录
- `guaji_settlements.json` — 挂机系统·聚落数据
- `guaji_order_templates.json` — 挂机系统·订单模板

---

## 7. 检查清单（每次涉及游戏数据时自查）

- [ ] 数据是否存放在 `docs/configs/` 中？
- [ ] 代码是否从配置加载，而非硬编码？
- [ ] JSON 配置是否有清晰的字段说明（在 impl_plan 或 JSON 注释中）？
- [ ] 如果修改了配置，Markdown 参考文档是否同步更新？

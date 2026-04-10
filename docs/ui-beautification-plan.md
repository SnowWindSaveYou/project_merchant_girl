# 末世行商 UI 废土风美化方案

## 设计方向

游戏美术参考《少女终末旅行》——柔和水彩手绘 + 动漫角色。UI 纹理采用**轻度工业感**（磨损金属板、风化铁皮），而非 Fallout 式重工业铆钉钢板。

**关键词**：磨损 · 风化 · 锈迹 · 低饱和 · 温暖的衰败感

**视觉参考**：
- [Post-Apocalyptic Game UI (Behance)](https://www.behance.net/gallery/217882183/Post-Apocalyptic-Game-UI-Design)
- [Frostpunk UI](https://interfaceingame.com/games/frostpunk/)
- [Synty Apocalypse HUD](https://syntystore.com/products/interface-apocalypse-hud)

---

## 一、视觉规范

### 1.1 边角：所有圆角 → 0（直角，工业感）

```lua
radius = 0; radius_small = 0; radius_large = 0
```

### 1.2 纹理层次

| UI 元素 | 纹理 | 方案 |
|---------|------|------|
| 卡片/面板 | 磨损金属板，边缘微锈 | 9-slice backgroundImage |
| 主按钮 | 旧铜色金属板，轻度氧化 | 9-slice + pressed 态 |
| 次按钮 | 暗枪灰金属板 | 9-slice + pressed 态 |
| 顶部状态栏 | 氧化金属条 | 9-slice |
| 底部导航栏 | 焊接钢板条 | 9-slice |
| 分割线 | 焊缝凹槽 | 2px 纹理条 |

### 1.3 配色微调（保留现有体系）

- danger: {168,62,52} -> {188,72,52}（纹理上更醒目）
- bg_card alpha: 240 -> 220（纹理更清晰）
- 新增 text_header: {228,218,198}（标题专用）
- 新增 glow_accent: {198,156,82,60}（脉冲辉光）

---

## 二、素材清单

### 2.1 纹理贴图（12 张，透明背景 9-slice）

| 名称 | 尺寸 | 用途 |
|------|------|------|
| ui_card_panel | 256x256 | 卡片面板，磨损枪灰金属 |
| ui_card_panel_glow | 256x256 | 选中态，淡铜边缘辉光 |
| ui_btn_primary | 256x64 | 主按钮，旧铜色金属板 |
| ui_btn_primary_pressed | 256x64 | 主按钮按下态 |
| ui_btn_secondary | 256x64 | 次按钮，暗灰金属 |
| ui_btn_secondary_pressed | 256x64 | 次按钮按下态 |
| ui_btn_danger | 256x64 | 危险按钮，锈红金属 |
| ui_btn_danger_pressed | 256x64 | 危险按钮按下态 |
| ui_topbar_bg | 256x64 | 顶栏氧化金属条 |
| ui_bottombar_bg | 256x80 | 底栏焊接钢板条 |
| ui_divider | 256x4 | 焊缝分割线 |
| ui_progress_track | 128x12 | 进度条金属凹槽 |

### 2.2 Tab 图标（5 张，64x64 透明，铜色线条画风）

| 名称 | 替换 | 描述 |
|------|------|------|
| icon_tab_home | emoji 首页 | 避难所/棚屋轮廓 |
| icon_tab_map | emoji 地图 | 折叠旧地图+指南针 |
| icon_tab_orders | emoji 委托 | 旧剪贴板+勾选列表 |
| icon_tab_cargo | emoji 货舱 | 木箱+金属捆扎带 |
| icon_tab_truck | emoji 货车 | 侧面货车，末世改装 |

### 2.3 音效（8 个）

| 名称 | 时长 | 描述 | 场景 |
|------|------|------|------|
| sfx_ui_click | 0.3s | 金属机械咔嗒 | 主按钮 |
| sfx_ui_click_soft | 0.2s | 柔和金属轻触 | Tab/次按钮 |
| sfx_ui_open | 0.6s | 金属面板滑开 | 弹窗/页面进入 |
| sfx_ui_close | 0.4s | 金属面板关闭 | 关闭弹窗 |
| sfx_ui_error | 0.4s | 短促警报蜂鸣 | 操作失败 |
| sfx_ui_success | 0.6s | 金属确认音 | 交易完成 |
| sfx_ui_coins | 0.5s | 硬币碰撞叮当 | 信用点变化 |
| sfx_ui_warning | 0.6s | 低沉轰鸣警告 | 燃料/耐久低值 |

---

## 三、动效规范

### 3.1 按钮交互
- 按下: scale 0.96, opacity 0.9 (0.1s easeOut) + 点击音
- 抬起: scale 1.0, opacity 1.0 (0.15s easeOutBack)

### 3.2 页面切换
- 进入: opacity 0->1, translateY 8->0 (0.2s easeOut)

### 3.3 卡片列表入场
- 每卡片 opacity 0->1, translateY 12->0 (0.25s easeOut)
- 卡片间延迟 50ms

### 3.4 特殊动效
- 信用点变化: 闪金 + scale 1.15->1.0 (0.3s easeOutBack)
- 低值警告: opacity 脉冲 1.0/0.4 (1.5s 循环)
- Tab 切换: 图标 scale 0.85->1.08->1.0 (0.3s easeOutBack)

---

## 四、实现计划

### 修改文件

| 文件 | 改动 |
|------|------|
| scripts/ui/theme.lua | radius->0, 新增 textures/icons/sounds 表, 微调配色 |
| scripts/ui/shell_bottom.lua | emoji->图标, 点击音, tab 动画 |
| scripts/ui/shell_top.lua | 顶栏纹理, 低值警告脉冲 |
| scripts/ui/shell.lua | 根容器背景纹理 |
| scripts/ui/router.lua | 页面切换淡入 + 导航音效 |
| 核心 screen_*.lua | 卡片纹理 (home/cargo/truck/shop) |

### 新建文件

| 文件 | 用途 |
|------|------|
| scripts/ui/sound_manager.lua | UI 音效管理模块 |
| scripts/ui/ui_factory.lua | 废土风组件工厂（带纹理 card/button/divider） |

### 分阶段

**Phase 1 - 基础设施**
1. theme.lua 改 radius + 新增路径表
2. 批量生成纹理贴图 (12张)
3. 批量生成 Tab 图标 (5张)
4. 批量生成音效 (8个)
5. 创建 sound_manager.lua

**Phase 2 - Shell 换肤**
6. shell_bottom.lua emoji->图标 + 音效 + 动画
7. shell_top.lua 纹理 + 警告脉冲
8. shell.lua 根容器纹理

**Phase 3 - 组件工厂 + 核心页面**
9. 创建 ui_factory.lua
10. 改造 screen_home / screen_cargo / screen_shop / screen_truck

**Phase 4 - 动效 + 音效集成**
11. router.lua 页面切换动画
12. 按钮 press/release 动效
13. 信用点闪金、低值预警脉冲
14. 各场景触发音效

**Phase 5 - 剩余页面 + 打磨**
15. 剩余 screen 统一应用
16. 视觉一致性审查
17. 纹理效果微调

### 验证
- 每 Phase 完成后 build + 预览
- 重点: 9-slice 拉伸、动效流畅度、音效时机

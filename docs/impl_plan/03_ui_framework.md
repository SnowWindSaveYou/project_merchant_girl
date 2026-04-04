# Phase 03 — UI 框架与 NanoVG 页面骨架

## 本阶段目标

先搭出稳定的 UI 绘制框架，让后面的贸易、地图、结算、事件界面都能在同一套规则下开发。

重点不是做漂亮，而是先把结构搭对。

---

## 本阶段只关心什么

- UI 路由
- 页面绘制分发
- 输入分发
- 字体、图片、图标加载
- 基础组件
- 分辨率适配

## 本阶段不要做什么

- 不做完整视觉 polish
- 不做复杂动画系统
- 不做剧情演出系统

---

## 先定 UI 基础架构

建议分四层：

1. `ui_router`：当前显示哪个页面
2. `ui_screen_*`：页面级绘制
3. `ui_widget_*`：基础组件
4. `ui_theme`：颜色、字体、间距、圆角

---

## 文件建议

- `scripts/ui/ui_router.lua`
- `scripts/ui/ui_theme.lua`
- `scripts/ui/ui_input.lua`
- `scripts/ui/ui_assets.lua`
- `scripts/ui/widgets/button.lua`
- `scripts/ui/widgets/panel.lua`
- `scripts/ui/widgets/progress_bar.lua`
- `scripts/ui/screen_home.lua`
- `scripts/ui/screen_prepare.lua`
- `scripts/ui/screen_summary.lua`

---

## 页面切换规则

不要让每个页面自己决定切到谁。

统一由 `ui_router` 控制：

```lua
UIRouter.set_screen("home")
UIRouter.set_screen("prepare", params)
UIRouter.set_screen("summary", result)
```

每个页面只做两件事：

- `draw(vg, dt, state, params)`
- `on_input(event, state, params)`

---

## 先做基础组件

首批只做以下组件：

- 按钮
- 面板
- 进度条
- 文本标签
- 简单列表项

### 判断标准

如果一个页面里同样的视觉块出现了两次，就该抽组件。

---

## NanoVG 资源管理

### 字体

统一在 `ui_assets.lua` 里注册：

- 主字体
- 数字字体
- 标题字体（如果有）

### 图片

统一在启动阶段预加载：

- UI 图标
- 立绘缩略图
- 聚落背景图

不要在 `draw()` 里临时加载图片。

---

## 输入分发

UrhoX 宿主把输入事件传给 Lua 后，先统一进 `ui_input.lua`。

建议流程：

1. 宿主收到输入
2. 转成统一 Lua 事件对象
3. 分发给当前页面
4. 页面再决定是否交给组件处理

### 统一事件格式

```lua
{
  type = "mouse_down",
  x = 100,
  y = 200,
  button = 1,
}
```

---

## 分辨率适配

首版不要一开始就做复杂自适应布局系统。

建议先定一个设计分辨率，例如：

- `1920 x 1080`

然后做简单的缩放层：

- 所有布局坐标先按设计分辨率写
- 根据实际窗口缩放
- 文本与点击区域同步缩放

如果一开始就全做自由布局，开发成本会明显失控。

---

## 本阶段至少要完成的页面

### 1. 首页 / 行驶中总览

必须显示：

- 当前路线
- 货车进度
- 信用点
- 燃料
- 耐久
- 底部导航按钮

### 2. 出发准备页

必须显示：

- 当前订单
- 路线信息
- 预计收益
- 出发按钮

### 3. 结算页

必须显示：

- 收入
- 耗时
- 货损（没有就先显示 0）
- 好感变化
- 继续下一程 / 返回聚落

---

## 通过标准

- [ ] 页面切换由统一 router 控制
- [ ] 按钮、面板、进度条组件可复用
- [ ] 字体和图片有统一加载入口
- [ ] 鼠标点击能正确分发到当前页面
- [ ] 三个基础页面都能绘制并响应输入
- [ ] 不同窗口尺寸下界面不严重错位

---

## 下一步

→ [04_economy_and_routes.md](04_economy_and_routes.md)

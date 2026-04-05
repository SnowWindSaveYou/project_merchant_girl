# UI 滚动位置保持规范

> 本文件是项目级开发约定，所有参与开发的人类和 AI 必须遵守。

---

## 1. 问题背景

页面内操作（如买入/卖出商品、使用物品、调整数值）后需要刷新 UI 来反映数据变化。
如果使用 `router.navigate("当前页面")` 进行自刷新，会**重建整个 UI 树并调用 `UI.SetRoot()`**，
导致滚动位置重置到顶部——用户滚动到列表中间点击按钮后被弹回顶部，体验很差。

---

## 2. 核心规则

### 规则 #1：页面内刷新必须用 `router.refresh()`

```lua
-- ❌ 错误：自导航会重置滚动位置
onClick = function(self)
    state.economy.credits = state.economy.credits - price
    router.navigate("shop")   -- 滚动位置丢失！
end

-- ✅ 正确：refresh() 保留滚动位置
onClick = function(self)
    state.economy.credits = state.economy.credits - price
    router.refresh()           -- 滚动位置保持不变
end
```

### 规则 #2：仅当跳转到不同页面时使用 `navigate()`

| 场景 | 方法 | 示例 |
|------|------|------|
| 页面内操作后刷新自身 | `router.refresh()` | 买入商品、使用物品、调整数值 |
| 跳转到另一个页面 | `router.navigate(name)` | 从首页进入交易所、从货舱跳到地图 |

### 规则 #3：`refresh()` 支持传参

```lua
-- 带参数刷新（等同于 navigate 的 params 参数）
router.refresh({ filter = "weapons" })
```

---

## 3. `router.refresh()` 工作原理

1. **保存**当前页面滚动容器的 `scrollX, scrollY`
2. **重建**页面内容（调用 `screen.create()`）
3. **替换** UI 树（调用 `UI.SetRoot()`）
4. **恢复**新页面滚动容器的 `scrollX, scrollY`

滚动容器的定位策略：
- Shell 页面：通过 `FindById("shellContent")` 找到内容区，取其第一个子节点
- 非 Shell 页面：直接取 root 节点

---

## 4. 检查清单

编写页面内按钮回调时自查：

- [ ] 操作后是否需要刷新当前页面？→ 使用 `router.refresh()`
- [ ] 操作后是否跳转到另一个页面？→ 使用 `router.navigate(name)`
- [ ] 确认没有在 onClick 中使用 `router.navigate("当前页面名")`

---

## 5. 受影响页面（已修复）

| 页面 | 文件 | 操作 | 修复前 | 修复后 |
|------|------|------|--------|--------|
| 交易所 | `screen_shop.lua` | 买入/卖出/加油/维修 | `navigate("shop")` | `refresh()` |
| 货舱 | `screen_cargo.lua` | 使用物品 | `navigate("cargo")` | `refresh()` |
| 调试面板 | `screen_debug.lua` | 所有数值调整 | `navigate("debug")` | `refresh()` |

---
name: coordinate-check
description: |
  UrhoX 坐标系与旋转方向验证工具。提供各轴旋转速查表、绕序规则、常见陷阱和自检清单。
  Use when: (1) 编写或修改涉及旋转、方向、坐标的代码,
  (2) 编写角色骨骼动画/pose 代码,
  (3) 使用 CustomGeometry 构建面片,
  (4) 编写 Gizmo 旋转拖拽交互,
  (5) 编写非角色物体的倒伏/倾斜效果,
  (6) 用户提到旋转方向不对/镜像/翻转,
  (7) coordinate, rotation, quaternion, CCW, winding order
---

# 坐标系与旋转方向验证

> 不要凭记忆猜测旋转方向，必须查本表确认。

## 基础

Y-up 左手坐标系：Y=上, X=右, Z=前。
`Quaternion(θ, axis)` 使用**右手定则**（坐标系是左手，但旋转和叉积都用右手定则）。
`Q1 * Q2` = 先应用 Q1，再在 Q1 结果上应用 Q2。

---

## 各轴旋转速查表

### 绕 FORWARD(Z) — 左右展开

肢体从 -Y（自然下垂）出发。**口诀：正角=右，负角=左。**

| 角度 | 方向 | 用法 |
|------|------|------|
| +90° | → 右(+X) | 右臂 T-Pose |
| -90° | ← 左(-X) | 左臂 T-Pose |
| +170° | 上偏右 | 右臂举手 |
| -170° | 上偏左 | 左臂举手 |

头部/躯干同理：正角=右倾，负角=左倾。
内收：左臂向右收=正角，右臂向左收=负角。

### 绕 RIGHT(X) — 前后摆动

**关键：起始方向决定符号含义！**

| 起始方向 | 正角 | 负角 |
|---------|------|------|
| 肢体悬垂(-Y) | 向后(-Z) | 向前(+Z) |
| 身体/头部/竖立物体(+Y) | 前倾/向前倒(+Z) | 后仰/向后倒(-Z) |

**弯膝=正角（小腿向后折），弯肘=负角（前臂向前收）。**

### 绕 UP(Y) — 水平转向

正角=右转（俯视顺时针），负角=左转。

---

## 常见陷阱

### 1. FORWARD 符号搞反（最高频）

```lua
-- ❌ 左臂指向了右边
leftArm.rotation = Quaternion(90, Vector3.FORWARD)
-- ✅ 左臂指向左边
leftArm.rotation = Quaternion(-90, Vector3.FORWARD)
```

### 2. 弯肘弯膝方向相反

```lua
elbowNode.rotation = Quaternion(-60, Vector3.RIGHT)  -- 肘：负角，前臂向前
kneeNode.rotation  = Quaternion(40, Vector3.RIGHT)    -- 膝：正角，小腿向后
```

### 3. 跨身动作

手臂刻意跨过身体中线时符号反向是正确的，需加注释说明意图。

---

## 非角色物体旋转

```lua
-- 柱子倒伏（+Y物体绕RIGHT正角=向前倒）
pillarNode.rotation = Quaternion(yaw, Vector3.UP)
    * Quaternion(85 + math.random() * 10, Vector3.RIGHT)

-- 断壁微倾（±4°，别写成 ±40°！）
wallNode.rotation = Quaternion(math.random() * 360, Vector3.UP)
    * Quaternion(math.random() * 8 - 4, Vector3.RIGHT)
    * Quaternion(math.random() * 8 - 4, Vector3.FORWARD)
```

---

## CustomGeometry 绕序

**正面判定：CCW（从面外看逆时针）。**

```lua
-- 朝+Z的面片（从+Z看逆时针）
geom:DefineVertex(Vector3(-0.5,  0.5, 0))  -- 左上
geom:DefineVertex(Vector3(-0.5, -0.5, 0))  -- 左下
geom:DefineVertex(Vector3( 0.5, -0.5, 0))  -- 右下
```

六面体速查：

| 面 | 法线 | CCW 顺序 |
|----|------|----------|
| 前(+Z) | +Z | 左下→右上→左上 |
| 后(-Z) | -Z | 右下→左上→右上 |
| 顶(+Y) | +Y | 后左→前左→前右 |
| 底(-Y) | -Y | 前左→后左→后右 |
| 右(+X) | +X | 前右→后上→前上 |
| 左(-X) | -X | 后左→前上→后上 |

**UV 翻转**：角色正面贴图需翻转 U（x=-0.5→U=1, x=+0.5→U=0），否则左右镜像。

**高度图地形**：从+Y俯视必须 CCW，`v00→v01→v10` ✅，`v00→v10→v01` ❌（面片不可见）。

---

## Gizmo 与编辑器

**旋转拖拽符号修正**：用 `camDir·axis` 点积判断，>0 时翻转 `deltaDegrees`。

**3D 覆层**：不要尝试修改深度测试（Lua 侧均不生效），用 NanoVG + `WorldToScreenPoint()` 投影。

---

## 自检清单

角色 Pose：
- [ ] 左臂 -90°(FORWARD)、右臂 +90°(FORWARD)
- [ ] 弯肘负角(RIGHT)、弯膝正角(RIGHT)
- [ ] 跨身动作符号反向已加注释

非角色物体：
- [ ] 竖立物体绕 RIGHT 正角=向前倒
- [ ] 组合顺序 `Q(yaw,UP)*Q(tilt,RIGHT)`
- [ ] 微倾 ±4°（非 ±40°）

CustomGeometry：
- [ ] 绕序从面外看 CCW
- [ ] 角色正面贴图 UV 已翻转

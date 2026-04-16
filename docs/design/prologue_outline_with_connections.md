# 序章与主线剧情连贯性设计

---

## 一、核心调性（波特风格）

- **驱动方式**：好奇心驱动，不是冲突驱动
- **玩家身份**：新手行商，刚完成货车的维修
- **调性**：日常感 + 探索欲 + 缓慢节奏
- **情感焦点**：林砾的信号是暗线，不主动揭示

---

## 二、单线流程（10-30句/段）

### 步骤1：在车厂（SPAWN）

```
陶夏："赵苗说那边好了，咱们送过去。"

林砾："……这次应该没问题了。上次化油器堵塞。"

陶夏："出发吧。"

林砾："嗯。先接单。去温室看看。"
```

- 领取罐头×2
- 触发 tutorial_order_1

---

### 步骤2：在路上

```
车窗外，废弃的灌溉水渠滑过。

陶夏："这条路……咱走了多少次了？"

林砾："……七次。"

陶夏："太熟了……不好玩。"

林砾："……安全不好吗。"

陶夏："不好。没什么可说的。"
```

- 到达 greenhouse
- 触发 AT_GREENHOUSE

---

### 步骤3：在温室

```
赵苗："谢了。嗯……对了。"

赵苗顿了顿："最近水渠那边有动静。
　你们回去时……算了，没什么。"

沈禾："路上小心。"
```

- 完成订单，信用+5
- 赵苗留下悬念

---

### 步骤4：返回发现

```
返回路上，林砾突然减速。

林砾："……前面。"

陶夏探头："哎？废墟的人？
　他们来这边干什么？"

远处水渠边，几个人影在翻找。

陶夏："……绕路？"
林砾："……会近一点。"
陶夏："那还说啥，走呗。"
```

- 触发发现事件

---

### 步骤5：水渠调查

```
林砾先下车："……走了。留下标记。"

搜索发现：
- 旧零件×1
- 几种标记：圆形、叉形、三角形

陶夏："这画的什么？"
林砾："……路标……或者记什么东西。"
林砾："……记下来。"
```

- 获得旧零件

---

### 步骤6：蘑菇洞

```
顺路到蘑菇洞，微弱的蓝色荧光。

林砾："……有人来过。"
林砾："……不止一次。"

深处有翻动痕迹。

陶夏："废墟的人？"
林砾："……可能是。"
林砾："……记下来。"
```

- 获得夜光蘑菇×2

---

### 步骤7：信号中继站

```
顺路到信号中继站，废弃的通信塔。

林砾检查："……大部分坏了。"
林砾："……但有人维护过。"

陶夏："他们在找什么？"
林砾："……信号。"

陶夏："什么信号？"
林砾："……不知道。但有人在监听什么。"

林砾蹲下检查接收器，记录频率刻度。

陶夏："你看得懂这些？"
林砾："……不懂。但记下来。"

林砾翻到本子另一页，已有之前的标记：
圆形、叉形、三角形。现在多了频率。西南方。

陶夏："西南方有什么？"
林砾："……不知道。但有人在听。断断续续的。像一首没唱完的歌。"
```

- 位置：signal_relay (120,350) - 温室附近
- 获得：信号频率记录
- 埋下：三年信号追踪暗线

---

### 步骤8：返回抉择

```
返回温室，天色已暗。

沈禾："拾荒帮……那边是有生意做。"

林砾："……要不然跑一趟？"
陶夏："跑呗？反正路认识了。"

沈禾："想去就去。注意安全。"
```

- 序章完成 flag: prologue_done

---

## 三、主角交互设定


---

## 四、伏笔与后续联动

| 线索 | 来源 | 后续对应 |
|------|------|----------|
| 林砾在记录信号频率 | 信号中继站对话 | Ch.2 林砾坦白 |
| 拾荒帮在找旧信号塔 | 水渠标记+信号中继站 | Ch.3 铁锁商队 |
| 西南方有信号源 | 信号中继站频率记录 | 韩策/白述档案 |
| 信号标记系统（圆形/叉形/三角形） | 水渠+蘑菇洞 | Ch.6 隐藏节点 |

---

## 五、与教程系统对接

### 教程阶段映射

| 教程阶段 | 触发条件 | 对应剧情 | 触发对话 |
|---------|---------|---------|---------|
| SPAWN | tutorial_started | 步骤1:在车厂 | SD_PROLOGUE_01 |
| TRAVEL_TO_GREENHOUSE | 有温室订单 | 出发命名 | SD_TUTORIAL_FIRST_DEPARTURE |
| AT_GREENHOUSE | tutorial_arrived_greenhouse | 步骤2-3:路上+温室 | SD_PROLOGUE_02/03 |
| RETURN_JOURNEY | tutorial_shop_intro | 步骤4-7:返程探索 | SD_PROLOGUE_04~06（节点到达） |
| EXPLORE_TO_RUINS | prologue_can_go_ruins | 步骤8:去废墟 | SD_TUTORIAL_RUINS_ARRIVAL |
| COMPLETE | tutorial_explore_done | 序章完成 | — |

### Flag 流转

```
SD_PROLOGUE_01 → tutorial_started
SD_TUTORIAL_FIRST_DEPARTURE → tutorial_first_departure_done
SD_TUTORIAL_GREENHOUSE_ARRIVAL → tutorial_arrived_greenhouse
tutorial_shop_intro（交易所教程）
SD_PROLOGUE_02 → sd_prologue_02_done
SD_PROLOGUE_03 → sd_prologue_03_done, found_ruins_traced
SD_PROLOGUE_04 → sd_prologue_04_done（到达 irrigation_canal）
SD_PROLOGUE_05 → sd_prologue_05_done（到达 mushroom_cave）
SD_PROLOGUE_06 → sd_prologue_06_done（到达 signal_relay）
SD_PROLOGUE_07 → prologue_can_go_ruins（返回 greenhouse_farm）
SD_TUTORIAL_RUINS_ARRIVAL → tutorial_explore_done, prologue_done
```

### 节点到达拦截配置

RETURN_JOURNEY 阶段通过 `Tutorial.on_arrival` 拦截特定节点：

| 节点 | 触发对话 | guard_flag |
|------|---------|-----------|
| irrigation_canal | SD_PROLOGUE_04 | sd_prologue_04_done |
| mushroom_cave | SD_PROLOGUE_05 | sd_prologue_05_done |
| signal_relay | SD_PROLOGUE_06 | sd_prologue_06_done |
| greenhouse_farm | SD_PROLOGUE_07 | prologue_can_go_ruins |

---

## 六、波特风格原则

1. **不解释**：拾荒帮在找什么？林砾不知道，只是"记下来"
2. **不追问**：陶夏问什么，林砾只说"不知道，但记下来"
3. **单向流程**：8个步骤，无分支选择
4. **日常感**：对话围绕"走了多少次"的闲聊
5. **沉默的观察者**：林砾自己发现、自己记录，不需要NPC解释

---

## 七、待确认

- [x] 教程阶段已重新设计匹配8步剧情
- [x] 隐士角色已移除，林砾自己记录信号
- [ ] 返程订单路线是否经过 irrigation_canal/mushroom_cave/signal_relay
- [ ] SD_PROLOGUE_04~06 的节点类型筛选是否正确


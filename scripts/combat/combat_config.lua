--- 战斗配置
--- 敌人定义、战术参数、战利品表
local M = {}

-- ============================================================
-- 车载迎击 —— 敌人模板
-- ============================================================

--- 敌人压迫等级决定每回合伤害和逃脱难度
M.AMBUSH_ENEMIES = {
    ambush_light = {
        name     = "散兵劫匪",
        desc     = "三五成群的废土流寇，装备简陋",
        threat   = 40,       -- 初始威胁值
        atk_min  = 3,        -- 每回合最低伤害
        atk_max  = 8,        -- 每回合最高伤害
        rounds   = 3,        -- 总决策回合数
        escape_threshold = 70,  -- 散兵容易甩脱（3回合×accelerate35=105>70）
        loot_on_repel = {    -- 击退后掉落（小概率）
            { id = "metal_scrap", count = 1, chance = 0.3 },
        },
    },
    ambush_medium = {
        name     = "武装车队",
        desc     = "改装皮卡加焊钢板，带小口径武器",
        threat   = 65,
        atk_min  = 6,
        atk_max  = 14,
        rounds   = 4,
        escape_threshold = 120, -- 武装车队难以甩脱（需组合战术）
        loot_on_repel = {
            { id = "ammo",        count = 1, chance = 0.25 },
            { id = "metal_scrap", count = 2, chance = 0.4 },
        },
    },
    ambush_heavy = {
        name     = "赏金猎人",
        desc     = "职业追猎者，装甲车加重武器",
        threat   = 85,
        atk_min  = 10,
        atk_max  = 20,
        rounds   = 4,
        escape_threshold = 120,
        loot_on_repel = {
            { id = "ammo",        count = 2, chance = 0.3 },
            { id = "circuit",     count = 1, chance = 0.2 },
        },
    },
}

-- ============================================================
-- 车载迎击 —— 战术定义
-- ============================================================

--- 四种基础战术，每种影响逃脱进度和受伤风险
M.TACTICS = {
    accelerate = {
        name       = "加速突破",
        icon       = "��",
        desc       = "全力加速，拉开距离",
        escape_add = 35,       -- 逃脱进度增加
        dmg_mult   = 1.2,      -- 受到伤害倍率（加速时防御下降）
        fuel_cost  = 3,        -- 额外油耗
        cooldown   = 0,
    },
    steady = {
        name       = "稳车射击",
        icon       = "🎯",
        desc       = "保持平稳让陶夏开火",
        escape_add = 20,
        dmg_mult   = 0.8,      -- 稳定行驶受伤略少
        fuel_cost  = 0,
        threat_reduce = 15,    -- 有弹药时降低威胁
        requires_ammo = true,
        no_ammo_desc = "无弹药，火力大幅削弱",
    },
    evade = {
        name       = "急转规避",
        icon       = "↩️",
        desc       = "急转弯躲避攻击",
        escape_add = 15,
        dmg_mult   = 0.3,      -- 大幅减伤
        fuel_cost  = 2,
        cooldown   = 0,
    },
    smoke = {
        name       = "烟幕撤离",
        icon       = "💨",
        desc       = "释放烟幕，立刻脱离",
        escape_add = 999,      -- 直接逃脱
        dmg_mult   = 0.0,      -- 本回合不受伤
        fuel_cost  = 0,
        requires_smoke = true,
        no_smoke_desc = "没有烟雾弹",
    },
}

-- 战术键顺序（UI展示用）
M.TACTIC_ORDER = { "accelerate", "steady", "evade", "smoke" }

-- ============================================================
-- 弹药效果
-- ============================================================

--- 有弹药时陶夏的火力加成
M.AMMO_FIREPOWER     = 12   -- 有弹药时每回合额外削减威胁
M.NO_AMMO_FIREPOWER  = 3    -- 无弹药时基础削减

-- ============================================================
-- 资源点探索 —— 房间模板
-- ============================================================

M.EXPLORE_ROOMS = {
    abandoned_warehouse = {
        name = "废弃仓库",
        desc = "灰尘遍布的铁皮仓库，角落堆满锈蚀货架",
        scene = "ruins",
        crates = {
            { name = "铁箱", icon = "military", loot = {
                { id = "metal_scrap", count = 2, chance = 0.8 },
                { id = "fuel_cell",   count = 1, chance = 0.4 },
            }},
            { name = "木箱", icon = "wooden", loot = {
                { id = "food_can", count = 2, chance = 0.7 },
                { id = "water",    count = 2, chance = 0.6 },
            }},
        },
        enemies = {
            { name = "变异鼠群", hp = 20, atk = 4, desc = "嘶嘶作响的变异老鼠" },
        },
        hazard_chance = 0.3,   -- 探索时遭遇危险概率
        hazard_dmg    = 5,     -- 危险事件伤害
    },
    old_clinic = {
        name = "旧诊所",
        desc = "药柜大多被翻空，但深处可能还有存货",
        scene = "ruins",
        crates = {
            { name = "药柜", icon = "cabinet", loot = {
                { id = "medicine", count = 1, chance = 0.6 },
                { id = "medicine", count = 1, chance = 0.3 },
            }},
            { name = "急救箱", icon = "cabinet", loot = {
                { id = "medicine", count = 1, chance = 0.5 },
                { id = "water",    count = 1, chance = 0.4 },
            }},
        },
        enemies = {
            { name = "流浪者", hp = 15, atk = 3, desc = "虚弱但警觉的流浪者" },
        },
        hazard_chance = 0.2,
        hazard_dmg    = 3,
    },
    military_outpost = {
        name = "军事哨站",
        desc = "半塌的混凝土掩体，弹孔密布的围墙",
        scene = "military",
        crates = {
            { name = "弹药箱", icon = "military", loot = {
                { id = "ammo",       count = 2, chance = 0.7 },
                { id = "smoke_bomb", count = 1, chance = 0.4 },
            }},
            { name = "储物柜", icon = "cabinet", loot = {
                { id = "circuit",     count = 1, chance = 0.5 },
                { id = "metal_scrap", count = 2, chance = 0.6 },
            }},
        },
        enemies = {
            { name = "残兵", hp = 30, atk = 8, desc = "装备残破但训练有素的士兵" },
            { name = "巡逻机器人", hp = 25, atk = 6, desc = "电力不足的自动哨兵" },
        },
        hazard_chance = 0.45,
        hazard_dmg    = 8,
    },
    radar_station = {
        name = "废弃雷达站",
        desc = "锈迹斑斑的信号塔矗立在高处，控制室的屏幕早已碎裂",
        scene = "military",
        crates = {
            { name = "信号柜", icon = "cabinet", loot = {
                { id = "circuit",   count = 2, chance = 0.7 },
                { id = "circuit",   count = 1, chance = 0.3 },
            }},
            { name = "工具箱", icon = "cabinet", loot = {
                { id = "metal_scrap", count = 2, chance = 0.6 },
                { id = "fuel_cell",   count = 1, chance = 0.35 },
            }},
        },
        enemies = {
            { name = "野狗群", hp = 18, atk = 5, desc = "占据废墟的凶猛野狗" },
        },
        hazard_chance = 0.35,
        hazard_dmg    = 6,
    },

    -- ── 资源节点探索房间 ──

    irrigation_tunnels = {
        name = "灌溉水渠",
        desc = "半淹没的混凝土渠道，苔藓覆盖的阀门还在滴水",
        scene = "underground",
        crates = {
            { name = "水阀间", icon = "organic", loot = {
                { id = "water",    count = 3, chance = 0.8 },
                { id = "water",    count = 2, chance = 0.4 },
            }},
            { name = "渠壁暗格", icon = "organic", loot = {
                { id = "food_can", count = 2, chance = 0.6 },
                { id = "medicine", count = 1, chance = 0.25 },
            }},
        },
        enemies = {
            { name = "水蛭群", hp = 14, atk = 3, desc = "暗水中蠕动的变异水蛭" },
        },
        hazard_chance = 0.25,
        hazard_dmg    = 4,
    },
    mushroom_grotto = {
        name = "蘑菇洞穴",
        desc = "潮湿的岩洞中发着微光，菌丝覆满墙壁",
        scene = "underground",
        crates = {
            { name = "菌床", icon = "organic", loot = {
                { id = "food_can", count = 3, chance = 0.85 },
                { id = "food_can", count = 2, chance = 0.4 },
            }},
            { name = "旧急救包", icon = "organic", loot = {
                { id = "medicine", count = 1, chance = 0.5 },
                { id = "water",    count = 1, chance = 0.35 },
            }},
        },
        enemies = {
            { name = "洞穴蜘蛛", hp = 16, atk = 4, desc = "在黑暗中结网的大型蜘蛛" },
        },
        hazard_chance = 0.2,
        hazard_dmg    = 3,
    },
    solar_panels = {
        name = "太阳能田",
        desc = "成排的光伏板在烈日下闪烁，控制箱散落田间",
        scene = "military",
        crates = {
            { name = "控制箱", icon = "cabinet", loot = {
                { id = "circuit",   count = 2, chance = 0.75 },
                { id = "circuit",   count = 1, chance = 0.35 },
            }},
            { name = "储电柜", icon = "cabinet", loot = {
                { id = "fuel_cell", count = 1, chance = 0.6 },
                { id = "metal_scrap", count = 1, chance = 0.4 },
            }},
        },
        enemies = {
            { name = "日灼蜥蜴", hp = 20, atk = 5, desc = "长期暴晒变异的巨型蜥蜴" },
        },
        hazard_chance = 0.3,
        hazard_dmg    = 5,
    },
    junk_heap = {
        name = "废品堆场",
        desc = "金属垃圾堆成小山，锈味刺鼻，偶有可用零件",
        scene = "ruins",
        crates = {
            { name = "废铁堆", icon = "scrap", loot = {
                { id = "metal_scrap", count = 3, chance = 0.85 },
                { id = "metal_scrap", count = 2, chance = 0.5 },
            }},
            { name = "旧电器", icon = "scrap", loot = {
                { id = "circuit",     count = 1, chance = 0.45 },
                { id = "fuel_cell",   count = 1, chance = 0.25 },
            }},
        },
        enemies = {
            { name = "拾荒犬", hp = 15, atk = 4, desc = "领地意识极强的流浪犬群" },
        },
        hazard_chance = 0.3,
        hazard_dmg    = 4,
    },
    print_shop = {
        name = "印刷厂遗址",
        desc = "油墨味弥漫的厂房，残破的印刷机积满灰尘",
        scene = "ruins",
        crates = {
            { name = "档案柜", icon = "cabinet", loot = {
                { id = "old_book",  count = 2, chance = 0.7 },
                { id = "old_book",  count = 1, chance = 0.4 },
            }},
            { name = "维修间", icon = "cabinet", loot = {
                { id = "circuit",     count = 1, chance = 0.5 },
                { id = "metal_scrap", count = 1, chance = 0.35 },
            }},
        },
        enemies = {
            { name = "纸巢虫", hp = 12, atk = 3, desc = "在纸堆中筑巢的变异虫群" },
        },
        hazard_chance = 0.2,
        hazard_dmg    = 3,
    },
    scrap_pit = {
        name = "废铁场",
        desc = "巨型液压机旁散落着被压扁的车壳，深处有未拆解的残骸",
        scene = "ruins",
        crates = {
            { name = "车壳残骸", icon = "scrap", loot = {
                { id = "metal_scrap", count = 2, chance = 0.8 },
                { id = "ammo",        count = 1, chance = 0.35 },
            }},
            { name = "工具房", icon = "cabinet", loot = {
                { id = "metal_scrap", count = 2, chance = 0.6 },
                { id = "fuel_cell",   count = 1, chance = 0.3 },
            }},
        },
        enemies = {
            { name = "铁锈蝎", hp = 22, atk = 6, desc = "金属碎片中进化的甲壳生物" },
        },
        hazard_chance = 0.35,
        hazard_dmg    = 6,
    },
    logistics_depot = {
        name = "旧物流中心",
        desc = "传送带锈死在原地，货架上残留着各类物资",
        scene = "military",
        crates = {
            { name = "货架A", icon = "wooden", loot = {
                { id = "food_can",    count = 1, chance = 0.5 },
                { id = "water",       count = 1, chance = 0.5 },
                { id = "medicine",    count = 1, chance = 0.3 },
            }},
            { name = "货架B", icon = "wooden", loot = {
                { id = "metal_scrap", count = 1, chance = 0.5 },
                { id = "circuit",     count = 1, chance = 0.4 },
                { id = "ammo",        count = 1, chance = 0.25 },
            }},
        },
        enemies = {
            { name = "流浪者团伙", hp = 18, atk = 5, desc = "占据仓库的小股流民" },
        },
        hazard_chance = 0.3,
        hazard_dmg    = 5,
    },

    -- ── 危险节点探索房间（高危高回报） ──

    sewer_depths = {
        name = "下水道深处",
        desc = "恶臭的地下通道，积水没过脚踝，墙壁渗着不明液体",
        scene = "underground",
        crates = {
            { name = "被冲来的箱子", icon = "wooden", loot = {
                { id = "medicine",    count = 2, chance = 0.6 },
                { id = "medicine",    count = 1, chance = 0.35 },
            }},
            { name = "密封桶", icon = "organic", loot = {
                { id = "water",       count = 2, chance = 0.5 },
                { id = "smoke_bomb",  count = 1, chance = 0.3 },
            }},
        },
        enemies = {
            { name = "污水巨蛙", hp = 28, atk = 7, desc = "在污水中变异的巨型蛙类" },
            { name = "管道鼠王", hp = 20, atk = 5, desc = "统领下水道的变异巨鼠" },
        },
        hazard_chance = 0.5,
        hazard_dmg    = 8,
    },
    bunker_interior = {
        name = "军事掩体内部",
        desc = "厚重的防爆门半开着，里面的武器架还没被完全搬空",
        scene = "military",
        crates = {
            { name = "弹药库", icon = "military", loot = {
                { id = "ammo",       count = 3, chance = 0.7 },
                { id = "smoke_bomb", count = 1, chance = 0.5 },
            }},
            { name = "军官储物柜", icon = "military", loot = {
                { id = "circuit",     count = 2, chance = 0.55 },
                { id = "medicine",    count = 1, chance = 0.4 },
            }},
        },
        enemies = {
            { name = "自动防御炮台", hp = 35, atk = 10, desc = "还在运转的自动火力系统" },
            { name = "巡逻机器人", hp = 25, atk = 7, desc = "电量将尽的自动哨兵" },
        },
        hazard_chance = 0.55,
        hazard_dmg    = 10,
    },
    crater_salvage = {
        name = "弹坑残骸",
        desc = "巨大的弹坑边缘，半埋的车辆和设备等待被拆解",
        scene = "ruins",
        crates = {
            { name = "半埋载具", icon = "scrap", loot = {
                { id = "fuel_cell",   count = 2, chance = 0.65 },
                { id = "metal_scrap", count = 2, chance = 0.7 },
            }},
            { name = "散落碎片", icon = "scrap", loot = {
                { id = "metal_scrap", count = 2, chance = 0.6 },
                { id = "circuit",     count = 1, chance = 0.3 },
            }},
        },
        enemies = {
            { name = "辐射獾", hp = 24, atk = 8, desc = "被辐射扭曲的凶猛獾类" },
        },
        hazard_chance = 0.45,
        hazard_dmg    = 7,
    },
}

-- 可探索房间列表（随机选择用）
M.EXPLORE_ROOM_IDS = {
    "abandoned_warehouse", "old_clinic", "military_outpost", "radar_station",
    "irrigation_tunnels", "mushroom_grotto", "solar_panels", "junk_heap",
    "print_shop", "scrap_pit", "logistics_depot",
    "sewer_depths", "bunker_interior", "crater_salvage",
}

-- ============================================================
-- 探索战 —— 战斗参数
-- ============================================================

M.EXPLORE_PLAYER_ATK = 12    -- 玩家攻击力（林砾近战）
M.EXPLORE_TAOXIA_ATK = 8     -- 陶夏辅助攻击（有弹药时）
M.EXPLORE_NO_AMMO_ATK = 2    -- 无弹药时陶夏攻击

-- ============================================================
-- 货物掉落（迎击失败/严重损伤时）
-- ============================================================

--- 当耐久降到一定比例，有概率掉落货物
M.CARGO_DROP_THRESHOLD = 30   -- 耐久低于此值开始掉货
M.CARGO_DROP_CHANCE    = 0.4  -- 每种货物的掉落概率
M.CARGO_DROP_MAX       = 2    -- 每种货物最多掉几个

return M

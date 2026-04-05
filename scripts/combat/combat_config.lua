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
        escape_threshold = 100, -- 逃脱进度阈值
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
        escape_threshold = 100,
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
        crates = {
            { name = "铁箱", loot = {
                { id = "metal_scrap", count = 2, chance = 0.8 },
                { id = "fuel_cell",   count = 1, chance = 0.4 },
            }},
            { name = "木箱", loot = {
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
        crates = {
            { name = "药柜", loot = {
                { id = "medicine", count = 1, chance = 0.6 },
                { id = "medicine", count = 1, chance = 0.3 },
            }},
            { name = "急救箱", loot = {
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
        crates = {
            { name = "弹药箱", loot = {
                { id = "ammo",       count = 2, chance = 0.7 },
                { id = "smoke_bomb", count = 1, chance = 0.4 },
            }},
            { name = "储物柜", loot = {
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
        crates = {
            { name = "信号柜", loot = {
                { id = "circuit",   count = 2, chance = 0.7 },
                { id = "circuit",   count = 1, chance = 0.3 },
            }},
            { name = "工具箱", loot = {
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
}

-- 可探索房间列表（随机选择用）
M.EXPLORE_ROOM_IDS = { "abandoned_warehouse", "old_clinic", "military_outpost", "radar_station" }

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

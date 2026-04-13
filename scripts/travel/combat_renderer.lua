--- 统一战斗渲染模块（原 driving_combat.lua）
--- 在 ChibiScene 渲染管线中绘制敌方角色和战术视觉效果
--- 支持两种模式：
---   vehicle（默认）：敌方载具 + 车上船员，速度线，卡车偏移
---   ground：敌方步行立绘，无载具/速度线，简化震动
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
local SoundMgr   = require("ui/sound_manager")

local M = {}

-- ═══════════════════════════════════════════════════════════════
-- 常量
-- ═══════════════════════════════════════════════════════════════

-- 敌方载具尺寸（相对于玩家卡车）
local ENEMY_SCALE     = 0.65   -- 敌车高度 = 玩家卡车 * 0.65
local ENEMY_CHIBI_H   = 0.30   -- 敌方纸娃娃高度比（相对敌车高度）

-- 战斗中玩家卡车偏右（归一化，正值=向右）
local COMBAT_TRUCK_OFFSET     = 0.12
-- 加速时卡车向左冲刺的偏移量
local ACCEL_TRUCK_PUSH_LEFT   = -0.15
-- 敌车基准归一化 X（相对画面左边缘）
local ENEMY_BASE_X            = 0.06
-- 加速时敌车被推到画面右侧的 X
local ENEMY_ACCEL_PUSHED_X    = 0.75

-- ground 模式敌方基准位置（敌人在左侧，主角在右侧——与行驶场景方向一致）
local GROUND_ENEMY_BASE_X     = 0.18   -- 敌人在画面左侧
local GROUND_ENEMY_ENTER_X    = -0.15  -- 入场起点（画面左侧外）
local GROUND_CHIBI_SCALE      = 2.0    -- 地面模式敌方角色放大

-- 动画参数
local BOB_FREQ        = 0.9
local BOB_PX          = 2.0
local BREATH_FREQ     = 0.5
local BREATH_AMP      = 0.03

-- 敌方徘徊参数（ground 模式）
local ENEMY_SWAY_RANGE  = 0.03   -- 归一化 x 徘徊幅度
local ENEMY_SWAY_SPEED  = 0.04   -- 归一化/秒
local ENEMY_SWAY_PAUSE_MIN = 0.6
local ENEMY_SWAY_PAUSE_MAX = 1.8

-- 近战冲锋参数
local MELEE_CHARGE_DURATION = 0.35  -- 冲到目标耗时
local MELEE_HIT_PAUSE       = 0.15  -- 命中停顿
local MELEE_RETREAT_DURATION = 0.40 -- 退回耗时

-- 车轮
local WHEEL_IMAGE       = "image/wheel.png"

-- ═══════════════════════════════════════════════════════════════
-- 敌人类型 → 视觉映射（vehicle 模式：载具 + 船员）
-- ═══════════════════════════════════════════════════════════════

local ENEMY_VISUALS = {
    ambush_light = {
        vehicle = "image/enemy_vehicle_raider_20260411070711.png",
        chibis  = {
            "image/chibi_npc_scavenger_20260409100005.png",
            "image/chibi_npc_scavenger_20260409100005.png",
        },
        wheels = {
            { rx = 0.313, ry = 0.765, size = 0.204 },
            { rx = 0.682, ry = 0.770, size = 0.204 },
        },
        crewZone = { x = 0.207, y = 0.134, w = 0.305, h = 0.367 },
    },
    ambush_medium = {
        vehicle = "image/enemy_vehicle_armed_20260411070718.png",
        chibis  = {
            "image/chibi_npc_tech_20260409100016.png",
            "image/chibi_npc_scavenger_20260409100005.png",
        },
        wheels = {
            { rx = 0.313, ry = 0.803, size = 0.227 },
            { rx = 0.729, ry = 0.803, size = 0.233 },
        },
        crewZone = { x = 0.469, y = 0.070, w = 0.383, h = 0.245 },
    },
    ambush_heavy = {
        vehicle = "image/enemy_vehicle_armored_20260411070730.png",
        chibis  = {
            "image/chibi_npc_han_ce_20260409102702.png",
            "image/chibi_npc_han_ce_20260409102702.png",
        },
        wheels = {
            { rx = 0.435, ry = 0.754, size = 0.277 },
        },
        crewZone = { x = 0.398, y = 0.012, w = 0.467, h = 0.309 },
    },
}

-- ═══════════════════════════════════════════════════════════════
-- 探索敌人 → 视觉映射（ground 模式：步行立绘，无载具）
-- ═══════════════════════════════════════════════════════════════

local EXPLORE_ENEMY_VISUALS = {
    -- 通用后备：explore.lua 中的敌人用 enemy name 匹配不到时使用
    _default = {
        chibi = "image/chibi_npc_scavenger_20260409100005.png",
    },
    -- ── 生物敌人（近战 melee）──
    ["变异鼠群"] = {
        chibi = "image/chibi_enemy_rat_swarm_20260412044725.png",
        melee = true,
    },
    ["洞穴蜘蛛"] = {
        chibi = "image/chibi_enemy_cave_spider_20260412044749.png",
        melee = true,
    },
    ["野狗群"] = {
        chibi = "image/chibi_enemy_wild_dogs_20260412044808.png",
        melee = true,
    },
    ["拾荒犬"] = {
        chibi = "image/chibi_enemy_wild_dogs_20260412044808.png",
        melee = true,
    },
    ["日灼蜥蜴"] = {
        chibi = "image/chibi_enemy_sun_lizard_20260412044738.png",
        melee = true,
    },
    ["水蛭群"] = {
        chibi = "image/chibi_enemy_leech_20260412044948.png",
        melee = true,
    },
    ["纸巢虫"] = {
        chibi = "image/chibi_enemy_paper_bug_20260412044916.png",
        melee = true,
    },
    ["铁锈蝎"] = {
        chibi = "image/chibi_enemy_rust_scorpion_20260412044731.png",
        melee = true,
    },
    ["污水巨蛙"] = {
        chibi = "image/chibi_enemy_giant_frog_20260412044923.png",
        melee = true,
    },
    ["管道鼠王"] = {
        chibi = "image/chibi_enemy_rat_king_20260412044913.png",
        melee = true,
    },
    ["辐射獾"] = {
        chibi = "image/chibi_enemy_rad_badger_20260412044934.png",
        melee = true,
    },
    -- ── 人形敌人（远程 ranged）──
    ["流浪者"] = {
        chibi = "image/chibi_npc_scavenger_20260409100005.png",
    },
    ["残兵"] = {
        chibi = "image/chibi_enemy_soldier_20260412052449.png",
    },
    ["流浪者团伙"] = {
        chibi = "image/chibi_enemy_vagrant_gang_20260412052449.png",
    },
    ["武装巡逻兵"] = {
        chibi = "image/chibi_npc_han_ce_20260409102702.png",
    },
    -- ── 机械敌人（远程 ranged）──
    ["巡逻机器人"] = {
        chibi = "image/chibi_enemy_patrol_bot_20260412045044.png",
    },
    ["自动防御炮台"] = {
        chibi = "image/chibi_enemy_turret_20260412045046.png",
    },
}

-- 战术 → 音效名映射
local TACTIC_SOUNDS = {
    accelerate = "combat_accelerate",
    steady     = "combat_gunfire",
    evade      = "combat_evade",
    smoke      = "combat_smoke",
    -- ground 模式
    fight      = "combat_gunfire",
    flee       = "combat_evade",
}

-- ═══════════════════════════════════════════════════════════════
-- 状态
-- ═══════════════════════════════════════════════════════════════

local active_       = false
local groundMode_   = false     -- true = 地面战斗（探索），false = 载具战斗（伏击）
local enemyId_      = nil
local visuals_      = nil
local timer_        = 0
local scrollRef_    = 0

-- 敌方纸娃娃
local enemyChibis_  = {}

-- 活跃效果
local activeEffect_ = nil

-- 敌车/敌人震动
local enemyShakeX_  = 0
local enemyShakeY_  = 0

-- 全局屏幕抖动（射击后坐力）
local screenShakeX_   = 0
local screenShakeY_   = 0
local screenShakeDecay_ = 12   -- 抖动衰减速度

-- 后坐力：射击时卡车短暂右移
local recoilOffset_   = 0
local RECOIL_KICK     = 0.04   -- 后坐力偏移量
local RECOIL_DECAY    = 6      -- 后坐力恢复速度

-- ── 敌方攻击系统 ──
local enemyAttack_      = nil
local isMelee_          = false   -- 当前敌人是否为近战类型
local ENEMY_ATK_DELAY   = 0.5
local ENEMY_ATK_DURATION = 0.9

-- ── ground 模式敌方徘徊 ──
local enemySwayCenter_  = GROUND_ENEMY_BASE_X
local enemySwayTarget_  = GROUND_ENEMY_BASE_X
local enemySwayPause_   = 1.0

-- 玩家卡车受击闪红
local truckFlashTimer_ = 0
local TRUCK_FLASH_DUR  = 0.35

-- 战斗卡车贴图（按受损程度切换）
local TRUCK_COMBAT_IMAGES = {
    pristine = "image/edited_truck_home_exterior_v3_20260411053954.png",
    light    = "image/edited_truck_damage_light_v3_20260411092433.png",
    medium   = "image/edited_truck_damage_medium_v3_20260411092512.png",
    heavy    = "image/edited_truck_damage_heavy_v4_20260411092816.png",
}
local truckDamageLevel_ = "pristine"

-- 速度倍率
local speedMult_       = 1.0
local speedMultTarget_ = 1.0

-- ── 卡车偏移系统 ──
local truckOffset_       = 0
local truckOffsetTarget_ = COMBAT_TRUCK_OFFSET

-- ── 敌车动态 X 位置（归一化）──
local enemyXNorm_       = ENEMY_BASE_X
local enemyXTarget_     = ENEMY_BASE_X

-- ── ground 模式：敌人入场动画 ──
local groundEnemyX_       = GROUND_ENEMY_ENTER_X
local groundEnemyXTarget_ = GROUND_ENEMY_BASE_X

-- 玩家效果粒子
local particles_      = {}
-- 敌方攻击粒子
local enemyParticles_ = {}

-- ═══════════════════════════════════════════════════════════════
-- 缓动辅助
-- ═══════════════════════════════════════════════════════════════

local function lerp(cur, target, dt, speed)
    local diff = target - cur
    if math.abs(diff) < 0.001 then return target end
    return cur + diff * math.min(1, dt * speed)
end

-- ═══════════════════════════════════════════════════════════════
-- API
-- ═══════════════════════════════════════════════════════════════

--- 激活战斗渲染
---@param enemy_id string 敌人 ID（vehicle 模式对应 ENEMY_VISUALS key，ground 模式对应敌人 name）
---@param opts table|nil { ground = bool }
function M.activate(enemy_id, opts)
    active_ = true
    groundMode_ = opts and opts.ground or false
    enemyId_ = enemy_id
    timer_ = 0
    scrollRef_ = 0
    enemyShakeX_ = 0
    enemyShakeY_ = 0
    screenShakeX_ = 0
    screenShakeY_ = 0
    recoilOffset_ = 0
    enemyAttack_ = nil
    truckFlashTimer_ = 0
    speedMult_ = 1.0
    speedMultTarget_ = 1.0
    truckOffset_ = 0
    truckOffsetTarget_ = groundMode_ and 0 or COMBAT_TRUCK_OFFSET
    enemyXNorm_ = ENEMY_BASE_X
    enemyXTarget_ = ENEMY_BASE_X
    truckDamageLevel_ = "pristine"
    activeEffect_ = nil
    particles_ = {}
    enemyParticles_ = {}
    enemyChibis_ = {}

    if groundMode_ then
        -- ── ground 模式：查找步行立绘 ──
        visuals_ = EXPLORE_ENEMY_VISUALS[enemy_id]
            or EXPLORE_ENEMY_VISUALS._default
        isMelee_ = visuals_.melee or false
        groundEnemyX_ = GROUND_ENEMY_ENTER_X   -- 从画面外入场
        groundEnemyXTarget_ = GROUND_ENEMY_BASE_X

        -- 敌方徘徊初始化
        enemySwayCenter_ = GROUND_ENEMY_BASE_X
        enemySwayTarget_ = GROUND_ENEMY_BASE_X
        enemySwayPause_  = 1.5 + math.random()

        -- 创建单个敌方纸娃娃
        table.insert(enemyChibis_, {
            image   = visuals_.chibi,
            phase   = math.random() * 10,
            facing  = 1,   -- 面向右侧（玩家方向，主角在右侧）
            xNorm   = 0.5,
        })
    else
        -- ── vehicle 模式：查找载具 + 船员 ──
        visuals_ = ENEMY_VISUALS[enemy_id] or ENEMY_VISUALS.ambush_light

        -- 预加载战斗卡车贴图
        for _, path in pairs(TRUCK_COMBAT_IMAGES) do
            ImageCache.Get(path)
        end

        for i, img in ipairs(visuals_.chibis) do
            table.insert(enemyChibis_, {
                image   = img,
                phase   = math.random() * 10,
                facing  = 1,
                xNorm   = 0.25 + (i - 1) * 0.35,
            })
        end
    end
end

--- 关闭战斗渲染
function M.deactivate()
    active_ = false
    groundMode_ = false
    isMelee_ = false
    enemyId_ = nil
    visuals_ = nil
    truckDamageLevel_ = "pristine"
    activeEffect_ = nil
    particles_ = {}
    enemyAttack_ = nil
    enemyParticles_ = {}
    enemyChibis_ = {}
    truckOffset_ = 0
    truckOffsetTarget_ = 0
    enemyXNorm_ = ENEMY_BASE_X
    enemyXTarget_ = ENEMY_BASE_X
    groundEnemyX_ = GROUND_ENEMY_ENTER_X
    groundEnemyXTarget_ = GROUND_ENEMY_BASE_X
    enemySwayCenter_ = GROUND_ENEMY_BASE_X
    enemySwayTarget_ = GROUND_ENEMY_BASE_X
    enemySwayPause_  = 1.0
end

--- 触发战术视觉效果
---@param tacticId string  "accelerate"|"steady"|"evade"|"smoke"|"fight"|"flee"
---@param result table     回合结果
function M.triggerEffect(tacticId, result)
    if not active_ then return end

    -- ══════════════════════════════════════════════
    -- 玩家侧：重置并开始自己的效果
    -- ══════════════════════════════════════════════

    -- 播放音效
    local sfx = TACTIC_SOUNDS[tacticId]
    if sfx then
        local gain = (tacticId == "steady" or tacticId == "fight") and 1.4 or 1.0
        SoundMgr.play(sfx, gain)
    end

    -- 后坐力 / 屏幕抖动
    if tacticId == "steady" or tacticId == "fight" then
        local shakeScale = groundMode_ and 0.6 or 1.0
        screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 8 * shakeScale
        screenShakeY_ = screenShakeY_ - (3 + math.random() * 4) * shakeScale
        if not groundMode_ then
            recoilOffset_ = recoilOffset_ + RECOIL_KICK
        end
    end

    -- 重置玩家视觉效果
    particles_ = {}

    if tacticId == "accelerate" and not groundMode_ then
        -- 加速（仅 vehicle 模式有意义）
        activeEffect_ = { type = "accelerate", timer = 0, duration = 1.8 }
        speedMultTarget_ = 3.0
        truckOffsetTarget_ = ACCEL_TRUCK_PUSH_LEFT
        enemyXTarget_ = ENEMY_ACCEL_PUSHED_X
        for i = 1, 15 do
            table.insert(particles_, {
                kind = "speedline",
                x = math.random() * 1.4,
                y = 0.15 + math.random() * 0.7,
                speed = 0.8 + math.random() * 0.8,
                len = 0.06 + math.random() * 0.10,
                alpha = 0.3 + math.random() * 0.5,
            })
        end

    elseif tacticId == "steady" or tacticId == "fight" then
        -- 射击 / 战斗攻击
        activeEffect_ = { type = "steady", timer = 0, duration = 1.2 }
        local burstCount = 4 + math.random(2)
        for i = 1, burstCount do
            table.insert(particles_, {
                kind     = "tracer",
                delay    = (i - 1) * 0.10,
                progress = 0,
                alpha    = 1.0,
                hit      = false,
                ySpread  = (math.random() - 0.5) * 0.15,
                xSpread  = (math.random() - 0.5) * 0.08,
                flashDone = false,
            })
        end

    elseif tacticId == "evade" or tacticId == "flee" then
        -- 闪避 / 逃跑
        activeEffect_ = { type = "evade", timer = 0, duration = 0.8 }
        for i = 1, 3 do
            table.insert(particles_, {
                kind = "miss_shot",
                x = -0.1,
                y = 0.15 + (i - 1) * 0.12,
                speed = 1.5 + math.random() * 0.5,
                alpha = 0.6,
            })
        end

    elseif tacticId == "smoke" and not groundMode_ then
        -- 烟雾弹（仅 vehicle 模式）
        activeEffect_ = { type = "smoke", timer = 0, duration = 1.5 }
        for i = 1, 15 do
            table.insert(particles_, {
                kind = "smoke",
                x = 0.3 + math.random() * 0.15,
                y = 0.3 + math.random() * 0.5,
                radius = 8 + math.random() * 20,
                growSpeed = 15 + math.random() * 25,
                driftX = -(0.2 + math.random() * 0.3),
                driftY = -(0.02 + math.random() * 0.06),
                alpha = 0.5 + math.random() * 0.3,
                delay = i * 0.06,
            })
        end
    end

    -- ══════════════════════════════════════════════
    -- 敌人侧：反击
    -- ══════════════════════════════════════════════
    local dmg = result and result.dmg_taken or 0

    if groundMode_ and isMelee_ then
        -- 近战冲锋攻击：冲到主角位置 → 短暂停顿 → 退回
        local totalDur = MELEE_CHARGE_DURATION + MELEE_HIT_PAUSE + MELEE_RETREAT_DURATION
        enemyAttack_ = {
            delay    = ENEMY_ATK_DELAY * 0.6,  -- 近战反应更快
            timer    = 0,
            duration = totalDur,
            dmg      = dmg,
            melee    = true,
            phase    = "waiting",  -- waiting → charge → hit → retreat → done
            tracers  = {},
            started  = false,
            done     = false,
        }
    else
        -- 远程射击弹道
        local tracerCount = 2 + math.random(2)
        enemyParticles_ = {}
        for i = 1, tracerCount do
            table.insert(enemyParticles_, {
                delay    = (i - 1) * 0.12,
                progress = 0,
                hit      = false,
                ySpread  = dmg > 0
                    and (math.random() - 0.5) * 0.15
                    or  (0.3 + math.random() * 0.4) * (math.random() < 0.5 and -1 or 1),
                xSpread  = (math.random() - 0.5) * 0.06,
            })
        end
        enemyAttack_ = {
            delay    = ENEMY_ATK_DELAY,
            timer    = 0,
            duration = ENEMY_ATK_DURATION,
            dmg      = dmg,
            melee    = false,
            tracers  = enemyParticles_,
            started  = false,
            done     = false,
        }
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 更新
-- ═══════════════════════════════════════════════════════════════

function M.update(dt)
    if not active_ then return end

    timer_ = timer_ + dt
    scrollRef_ = scrollRef_ + dt * 50 * speedMult_

    -- 纸娃娃动画
    for _, c in ipairs(enemyChibis_) do
        c.phase = c.phase + dt
    end

    -- 速度倍率缓动
    speedMult_ = lerp(speedMult_, speedMultTarget_, dt, 5)

    -- 模式分支更新
    if groundMode_ then
        -- ground 模式：敌人入场缓动
        groundEnemyX_ = lerp(groundEnemyX_, groundEnemyXTarget_, dt, 3)

        -- 敌方徘徊（非攻击冲锋时）
        local isCharging = enemyAttack_ and enemyAttack_.melee
            and enemyAttack_.started and not enemyAttack_.done
        if not isCharging then
            if enemySwayPause_ > 0 then
                enemySwayPause_ = enemySwayPause_ - dt
            else
                local dx = enemySwayTarget_ - groundEnemyXTarget_
                if math.abs(dx) < ENEMY_SWAY_SPEED * dt then
                    groundEnemyXTarget_ = enemySwayTarget_
                    -- 选新的徘徊目标
                    enemySwayTarget_ = enemySwayCenter_
                        + (math.random() * 2 - 1) * ENEMY_SWAY_RANGE
                    enemySwayPause_ = ENEMY_SWAY_PAUSE_MIN
                        + math.random() * (ENEMY_SWAY_PAUSE_MAX - ENEMY_SWAY_PAUSE_MIN)
                else
                    local dir = dx > 0 and 1 or -1
                    groundEnemyXTarget_ = groundEnemyXTarget_ + dir * ENEMY_SWAY_SPEED * dt
                end
            end
        end
    else
        -- vehicle 模式：卡车偏移 + 敌车位置缓动
        truckOffset_ = lerp(truckOffset_, truckOffsetTarget_, dt, 3)
        enemyXNorm_ = lerp(enemyXNorm_, enemyXTarget_, dt, 2.5)
    end

    -- 更新活跃效果
    if activeEffect_ then
        activeEffect_.timer = activeEffect_.timer + dt
        local t = activeEffect_.timer
        local d = activeEffect_.duration

        if activeEffect_.type == "accelerate" then
            if t >= d * 0.65 then
                speedMultTarget_ = 1.0
                truckOffsetTarget_ = COMBAT_TRUCK_OFFSET
                enemyXTarget_ = ENEMY_BASE_X
            end

        elseif activeEffect_.type == "steady" then
            for _, p in ipairs(particles_) do
                if p.kind == "tracer" then
                    local localT = t - (p.delay or 0)
                    if localT > 0 then
                        local flyTime = d * 0.18
                        p.progress = math.min(1.0, localT / flyTime)
                        if p.progress >= 1.0 and not p.hit then
                            p.hit = true
                            local shakeScale = groundMode_ and 0.5 or 1.0
                            enemyShakeX_ = enemyShakeX_ + (math.random() - 0.5) * 5 * shakeScale
                            enemyShakeY_ = enemyShakeY_ + (math.random() - 0.5) * 3 * shakeScale
                            screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 3 * shakeScale
                            screenShakeY_ = screenShakeY_ - math.random() * 2 * shakeScale
                        end
                    end
                    if not p.flashDone and t >= (p.delay or 0) then
                        p.flashDone = true
                        if not groundMode_ then
                            recoilOffset_ = recoilOffset_ + RECOIL_KICK * 0.5
                        end
                    end
                end
            end

        elseif activeEffect_.type == "evade" then
            for _, p in ipairs(particles_) do
                if p.kind == "miss_shot" then
                    p.x = p.x + p.speed * dt
                end
            end
        end

        -- 效果结束
        if t >= d then
            activeEffect_ = nil
            particles_ = {}
            speedMultTarget_ = 1.0
            if not groundMode_ then
                truckOffsetTarget_ = COMBAT_TRUCK_OFFSET
                enemyXTarget_ = ENEMY_BASE_X
            end
            enemyShakeX_ = 0
            enemyShakeY_ = 0
        end
    end

    -- 敌方震动衰减
    if enemyShakeX_ ~= 0 or enemyShakeY_ ~= 0 then
        enemyShakeX_ = enemyShakeX_ * (1 - dt * 8)
        enemyShakeY_ = enemyShakeY_ * (1 - dt * 8)
        if math.abs(enemyShakeX_) < 0.3 then enemyShakeX_ = 0 end
        if math.abs(enemyShakeY_) < 0.3 then enemyShakeY_ = 0 end
    end

    -- 全局屏幕抖动衰减
    if screenShakeX_ ~= 0 or screenShakeY_ ~= 0 then
        local shakePhase = timer_ * 45
        screenShakeX_ = screenShakeX_ * (1 - dt * screenShakeDecay_)
            + math.sin(shakePhase) * math.abs(screenShakeX_) * 0.3
        screenShakeY_ = screenShakeY_ * (1 - dt * screenShakeDecay_)
            + math.cos(shakePhase * 1.3) * math.abs(screenShakeY_) * 0.3
        if math.abs(screenShakeX_) < 0.2 then screenShakeX_ = 0 end
        if math.abs(screenShakeY_) < 0.2 then screenShakeY_ = 0 end
    end

    -- 后坐力衰减（仅 vehicle 模式有效）
    if recoilOffset_ ~= 0 then
        recoilOffset_ = recoilOffset_ * (1 - dt * RECOIL_DECAY)
        if math.abs(recoilOffset_) < 0.002 then recoilOffset_ = 0 end
    end

    -- ── 敌方攻击更新 ──
    if enemyAttack_ and not enemyAttack_.done then
        enemyAttack_.timer = enemyAttack_.timer + dt

        if not enemyAttack_.started then
            if enemyAttack_.timer >= enemyAttack_.delay then
                enemyAttack_.started = true
                enemyAttack_.timer = 0
                if enemyAttack_.melee then
                    enemyAttack_.phase = "charge"
                    SoundMgr.play("combat_evade", 0.8)  -- 冲锋音效
                else
                    SoundMgr.play("combat_gunfire", 0.6)
                end
            end
        elseif enemyAttack_.melee then
            -- ── 近战冲锋状态机 ──
            local t = enemyAttack_.timer
            if enemyAttack_.phase == "charge" then
                -- 冲锋阶段：敌人快速移动到主角附近
                local progress = math.min(1.0, t / MELEE_CHARGE_DURATION)
                -- 使用 ease-in 加速
                enemyAttack_.chargeProgress = progress * progress
                -- 驱动 groundEnemyXTarget_ 冲向玩家（陶侠在0.35，琳莉在0.75）
                local chargeTargetX = 0.58  -- 冲到两位主角之间
                groundEnemyXTarget_ = GROUND_ENEMY_BASE_X
                    + (chargeTargetX - GROUND_ENEMY_BASE_X) * enemyAttack_.chargeProgress
                if progress >= 1.0 then
                    enemyAttack_.phase = "hit"
                    enemyAttack_.timer = 0
                    -- 命中效果
                    if enemyAttack_.dmg > 0 then
                        truckFlashTimer_ = TRUCK_FLASH_DUR
                        screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 8
                        screenShakeY_ = screenShakeY_ + 5 + math.random() * 3
                        SoundMgr.play("combat_gunfire", 0.5)  -- 撞击音效
                    end
                end
            elseif enemyAttack_.phase == "hit" then
                -- 命中停顿
                local t2 = enemyAttack_.timer
                if t2 >= MELEE_HIT_PAUSE then
                    enemyAttack_.phase = "retreat"
                    enemyAttack_.timer = 0
                end
            elseif enemyAttack_.phase == "retreat" then
                -- 退回阶段
                local t2 = enemyAttack_.timer
                local progress = math.min(1.0, t2 / MELEE_RETREAT_DURATION)
                -- ease-out 减速退回
                local eased = 1.0 - (1.0 - progress) * (1.0 - progress)
                local chargeTargetX = 0.58
                groundEnemyXTarget_ = chargeTargetX
                    + (enemySwayCenter_ - chargeTargetX) * eased
                if progress >= 1.0 then
                    groundEnemyXTarget_ = enemySwayCenter_
                    enemyAttack_.done = true
                end
            end
        else
            -- ── 远程弹道攻击 ──
            local t = enemyAttack_.timer
            local d = enemyAttack_.duration
            local flyTime = d * 0.25

            for _, tr in ipairs(enemyAttack_.tracers) do
                local localT = t - (tr.delay or 0)
                if localT > 0 then
                    tr.progress = math.min(1.0, localT / flyTime)
                    if tr.progress >= 1.0 and not tr.hit then
                        tr.hit = true
                        if enemyAttack_.dmg > 0 then
                            truckFlashTimer_ = TRUCK_FLASH_DUR
                            local shakeScale = groundMode_ and 0.5 or 1.0
                            screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 10 * shakeScale
                            screenShakeY_ = screenShakeY_ + (4 + math.random() * 4) * shakeScale
                        end
                    end
                end
            end

            if t >= d then
                enemyAttack_.done = true
            end
        end
    end

    -- 卡车受击闪红衰减
    if truckFlashTimer_ > 0 then
        truckFlashTimer_ = truckFlashTimer_ - dt
        if truckFlashTimer_ < 0 then truckFlashTimer_ = 0 end
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 渲染
-- ═══════════════════════════════════════════════════════════════

---@param nvg userdata NanoVG context
---@param l table      { x, y, w, h } widget 绝对布局
---@param sb table     { x, y, w, h, bounce } 场景 bounds（vehicle=卡车, ground=地面区域）
function M.render(nvg, l, sb)
    if not active_ or not visuals_ then return end

    if groundMode_ then
        M._renderGround(nvg, l, sb)
    else
        M._renderVehicle(nvg, l, sb)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- ground 模式渲染（探索战斗：步行立绘）
-- ═══════════════════════════════════════════════════════════════

function M._renderGround(nvg, l, sb)
    local groundY = l.y + l.h * 0.88
    local chibiH = sb.h * 0.32 * GROUND_CHIBI_SCALE
    local chibiW = chibiH

    -- 敌方位置
    local enemyDrawX = l.x + groundEnemyX_ * l.w - chibiW / 2 + enemyShakeX_
    local enemyDrawY = groundY - chibiH + enemyShakeY_

    -- 命中闪红判定
    local hitFlash = false
    if activeEffect_ and activeEffect_.type == "steady" then
        local t = activeEffect_.timer
        local flyTime = activeEffect_.duration * 0.18
        for _, p in ipairs(particles_) do
            if p.kind == "tracer" and p.hit then
                local hitT = t - (p.delay or 0) - flyTime
                if hitT > 0 and hitT < 0.20 then
                    hitFlash = math.floor(t * 24) % 2 == 0
                    break
                end
            end
        end
    end

    -- 绘制敌方纸娃娃
    for _, c in ipairs(enemyChibis_) do
        local chibiImg = ImageCache.Get(c.image)
        if chibiImg ~= 0 then
            local scaleY = 1.0 + math.sin(c.phase * BREATH_FREQ * 2 * math.pi) * BREATH_AMP
            local bobY = -math.abs(math.sin(c.phase * BOB_FREQ * math.pi)) * BOB_PX
            local cx = enemyDrawX + chibiW / 2
            local cy = enemyDrawY + chibiH

            nvgSave(nvg)
            nvgTranslate(nvg, cx, cy + bobY)
            nvgScale(nvg, c.facing, scaleY)
            nvgTranslate(nvg, -cx, -cy - bobY)

            local paint = nvgImagePattern(nvg,
                enemyDrawX, enemyDrawY, chibiW, chibiH,
                0, chibiImg, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, enemyDrawX, enemyDrawY, chibiW, chibiH)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)

            if hitFlash then
                nvgBeginPath(nvg)
                nvgRect(nvg, enemyDrawX, enemyDrawY, chibiW, chibiH)
                nvgFillColor(nvg, nvgRGBA(255, 40, 40, 100))
                nvgFill(nvg)
            end
            nvgRestore(nvg)
        end
    end

    -- 构造虚拟 enemy bounds 供弹道计算
    local enemyBounds = {
        x = enemyDrawX, y = enemyDrawY,
        w = chibiW,     h = chibiH,
    }

    -- 战术视觉效果
    if activeEffect_ then
        M._renderEffect(nvg, l, sb, enemyBounds.x, enemyBounds.y, enemyBounds.w, enemyBounds.h)
    end

    -- 敌方反击弹道
    if enemyAttack_ and enemyAttack_.started and not enemyAttack_.done then
        M._renderEnemyAttack(nvg, l, sb, enemyBounds.x, enemyBounds.y, enemyBounds.w, enemyBounds.h)
    end

    -- 受击 vignette
    M._renderVignette(nvg, l)
end

-- ═══════════════════════════════════════════════════════════════
-- vehicle 模式渲染（伏击战斗：载具 + 船员）
-- ═══════════════════════════════════════════════════════════════

function M._renderVehicle(nvg, l, tb)
    if tb.w <= 0 then return end

    -- ── 计算敌车尺寸 ──
    local enemyH = tb.h * ENEMY_SCALE
    local vehicleImg = visuals_.vehicle
    local vHandle = ImageCache.Get(vehicleImg)
    local enemyW = enemyH * 1.8
    if vHandle ~= 0 then
        local imgW, imgH = ImageCache.GetSize(vehicleImg)
        if imgW > 0 and imgH > 0 then
            enemyW = enemyH * (imgW / imgH)
        end
    end

    -- ── 敌车位置 ──
    local roadSurface = l.y + l.h * 0.88
    local wheels = visuals_.wheels or {{ rx = 0.3, ry = 0.8, size = 0.2 }}
    local firstW = wheels[1]
    local wheelR = enemyH * firstW.size * 0.5
    local wheelCenterY = enemyH * firstW.ry
    local enemyX = l.x + l.w * enemyXNorm_ + enemyShakeX_
    local enemyY = roadSurface - wheelCenterY - wheelR + tb.bounce + enemyShakeY_

    -- ── 命中闪红 ──
    local hitFlash = false
    if activeEffect_ and activeEffect_.type == "steady" then
        local t = activeEffect_.timer
        local flyTime = activeEffect_.duration * 0.18
        for _, p in ipairs(particles_) do
            if p.kind == "tracer" and p.hit then
                local hitT = t - (p.delay or 0) - flyTime
                if hitT > 0 and hitT < 0.20 then
                    hitFlash = math.floor(t * 24) % 2 == 0
                    break
                end
            end
        end
    end

    -- ── 绘制敌方载具 ──
    if vHandle ~= 0 then
        nvgSave(nvg)
        local paint = nvgImagePattern(nvg,
            enemyX, enemyY, enemyW, enemyH,
            0, vHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, enemyX, enemyY, enemyW, enemyH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)

        if hitFlash then
            nvgBeginPath(nvg)
            nvgRect(nvg, enemyX, enemyY, enemyW, enemyH)
            nvgFillColor(nvg, nvgRGBA(255, 40, 40, 100))
            nvgFill(nvg)
        end
        nvgRestore(nvg)
    end

    -- ── 敌车车轮 ──
    local wheelHandle = ImageCache.Get(WHEEL_IMAGE)
    if wheelHandle ~= 0 then
        local wImgW, wImgH = ImageCache.GetSize(WHEEL_IMAGE)
        if wImgW > 0 and wImgH > 0 then
            local wAspect = wImgW / wImgH
            for _, wp in ipairs(wheels) do
                local wDiam = enemyH * wp.size
                local wR = wDiam / 2
                local drawW = wDiam * wAspect
                local drawH = wDiam
                local angle = -(scrollRef_ * 1.0) / (wR * 0.8)
                local cx = enemyX + enemyW * wp.rx
                local cy = enemyY + enemyH * wp.ry

                nvgSave(nvg)
                nvgTranslate(nvg, cx, cy)
                nvgRotate(nvg, angle)
                local paint = nvgImagePattern(nvg,
                    -drawW / 2, -drawH / 2, drawW, drawH,
                    0, wheelHandle, 1.0)
                nvgBeginPath(nvg)
                nvgCircle(nvg, 0, 0, wR)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)
                nvgRestore(nvg)
            end
        end
    end

    -- ── 敌方纸娃娃 ──
    local cz = visuals_.crewZone or { x = 0.2, y = 0.1, w = 0.4, h = 0.35 }
    for _, c in ipairs(enemyChibis_) do
        local chibiH = enemyH * cz.h * 0.85
        local chibiW = chibiH
        local chibiImg = ImageCache.Get(c.image)
        if chibiImg ~= 0 then
            local zoneX = enemyX + cz.x * enemyW
            local zoneW = cz.w * enemyW
            local zoneY = enemyY + cz.y * enemyH
            local zoneH = cz.h * enemyH
            local drawX = zoneX + c.xNorm * zoneW - chibiW / 2
            local drawY = zoneY + zoneH - chibiH

            local scaleY = 1.0 + math.sin(c.phase * BREATH_FREQ * 2 * math.pi) * BREATH_AMP
            local bobY = -math.abs(math.sin(c.phase * BOB_FREQ * math.pi)) * BOB_PX
            local cx = drawX + chibiW / 2
            local cy = drawY + chibiH

            nvgSave(nvg)
            nvgTranslate(nvg, cx, cy + bobY)
            nvgScale(nvg, c.facing, scaleY)
            nvgTranslate(nvg, -cx, -cy - bobY)

            local paint = nvgImagePattern(nvg,
                drawX, drawY, chibiW, chibiH,
                0, chibiImg, 1.0)
            nvgBeginPath(nvg)
            nvgRect(nvg, drawX, drawY, chibiW, chibiH)
            nvgFillPaint(nvg, paint)
            nvgFill(nvg)

            if hitFlash then
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, chibiW, chibiH)
                nvgFillColor(nvg, nvgRGBA(255, 40, 40, 80))
                nvgFill(nvg)
            end
            nvgRestore(nvg)
        end
    end

    -- ── 战术视觉效果 ──
    if activeEffect_ then
        M._renderEffect(nvg, l, tb, enemyX, enemyY, enemyW, enemyH)
    end

    -- ── 敌方反击弹道 ──
    if enemyAttack_ and enemyAttack_.started and not enemyAttack_.done then
        M._renderEnemyAttack(nvg, l, tb, enemyX, enemyY, enemyW, enemyH)
    end

    -- ── vignette ──
    M._renderVignette(nvg, l)
end

-- ═══════════════════════════════════════════════════════════════
-- 效果渲染（vehicle/ground 共用）
-- ═══════════════════════════════════════════════════════════════

function M._renderEffect(nvg, l, tb, ex, ey, ew, eh)
    local eff = activeEffect_
    if not eff then return end
    local t = eff.timer
    local d = eff.duration
    local progress = math.min(1.0, t / d)

    -- 全局淡出
    local fadeAlpha = 1.0
    if progress > 0.75 then
        fadeAlpha = (1.0 - progress) / 0.25
    end

    if eff.type == "accelerate" then
        -- 速度线（仅 vehicle 模式产生此效果）
        nvgSave(nvg)
        nvgStrokeWidth(nvg, 2)
        for _, p in ipairs(particles_) do
            if p.kind == "speedline" then
                local px = l.x + (p.x - t * p.speed * speedMult_ * 0.5) % 1.4 * l.w
                local py = l.y + p.y * l.h
                local lineLen = p.len * l.w * speedMult_ * 0.6
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, px, py)
                nvgLineTo(nvg, px + lineLen, py)
                nvgStrokeColor(nvg, nvgRGBA(255, 255, 255, math.floor(p.alpha * fadeAlpha * 255)))
                nvgStroke(nvg)
            end
        end
        nvgRestore(nvg)

    elseif eff.type == "steady" then
        -- 弹道渲染
        for _, p in ipairs(particles_) do
            if p.kind == "tracer" then
                local localT = t - (p.delay or 0)
                if localT <= 0 then goto continue_tracer end

                -- 弹道起点
                local startX, startY
                if groundMode_ then
                    -- ground 模式：弹道从玩家角色位置发出（主角在右侧）
                    startX = l.x + l.w * 0.75
                    startY = l.y + l.h * 0.70
                else
                    -- vehicle 模式：弹道从卡车枪口发出
                    local enemyCenterX = ex + ew * 0.5
                    local truckCenterX = tb.x + tb.w * 0.5
                    local shootFromRight = enemyCenterX > truckCenterX
                    startX = shootFromRight
                        and (tb.x + tb.w * 0.85)
                        or  (tb.x + tb.w * 0.15)
                    startY = tb.y + tb.h * 0.1
                end
                local endX = ex + ew * (0.5 + (p.xSpread or 0))
                local endY = ey + eh * (0.4 + (p.ySpread or 0))

                -- 弹道线 + 弹头
                if p.progress < 1.0 then
                    local curX = startX + (endX - startX) * p.progress
                    local curY = startY + (endY - startY) * p.progress
                    local tailPct = math.max(0, p.progress - 0.3)
                    local tailX = startX + (endX - startX) * tailPct
                    local tailY = startY + (endY - startY) * tailPct

                    nvgSave(nvg)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, tailX, tailY)
                    nvgLineTo(nvg, curX, curY)
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStrokeColor(nvg, nvgRGBA(255, 220, 80, math.floor(fadeAlpha * 180)))
                    nvgStroke(nvg)

                    nvgBeginPath(nvg)
                    nvgCircle(nvg, curX, curY, 2.5)
                    nvgFillColor(nvg, nvgRGBA(255, 240, 100, math.floor(fadeAlpha * 255)))
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end

                -- 炮口闪光
                if localT < 0.08 then
                    local flashAlpha = (1 - localT / 0.08) * fadeAlpha
                    nvgSave(nvg)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, startX, startY, 5 + localT * 50)
                    nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(flashAlpha * 220)))
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end

                -- 命中火花
                local flyTime = d * 0.18
                local hitT = localT - flyTime
                if p.hit and hitT > 0 and hitT < 0.25 then
                    local sparkT = hitT / 0.25
                    nvgSave(nvg)
                    for si = 1, 4 do
                        local angle = (si / 4) * math.pi * 2 + localT * 12
                        local dist = sparkT * 12
                        local sx = endX + math.cos(angle) * dist
                        local sy = endY + math.sin(angle) * dist
                        nvgBeginPath(nvg)
                        nvgCircle(nvg, sx, sy, 2 - sparkT * 1.5)
                        nvgFillColor(nvg, nvgRGBA(255, 180, 50, math.floor((1 - sparkT) * fadeAlpha * 255)))
                        nvgFill(nvg)
                    end
                    nvgRestore(nvg)
                end

                ::continue_tracer::
            end
        end

    elseif eff.type == "evade" then
        nvgSave(nvg)
        nvgStrokeWidth(nvg, 1.5)
        for _, p in ipairs(particles_) do
            if p.kind == "miss_shot" then
                local px = l.x + p.x * l.w
                local py = l.y + p.y * l.h
                if px < l.x + l.w * 1.2 then
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, px, py)
                    nvgLineTo(nvg, px + 20, py + 2)
                    nvgStrokeColor(nvg, nvgRGBA(200, 200, 200, math.floor(p.alpha * fadeAlpha * 255)))
                    nvgStroke(nvg)
                end
            end
        end
        nvgRestore(nvg)

    elseif eff.type == "smoke" then
        nvgSave(nvg)
        for _, p in ipairs(particles_) do
            if p.kind == "smoke" and t > p.delay then
                local elapsed = t - p.delay
                local px = l.x + (p.x + p.driftX * elapsed) * l.w
                local py = l.y + (p.y + p.driftY * elapsed) * l.h
                local r = p.radius + p.growSpeed * elapsed
                local alpha = p.alpha * fadeAlpha * math.max(0, 1 - elapsed / (d - p.delay))

                nvgBeginPath(nvg)
                nvgCircle(nvg, px, py, r)
                nvgFillColor(nvg, nvgRGBA(180, 180, 170, math.floor(alpha * 180)))
                nvgFill(nvg)
            end
        end
        nvgRestore(nvg)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 敌方攻击弹道渲染（vehicle/ground 共用）
-- ═══════════════════════════════════════════════════════════════

function M._renderEnemyAttack(nvg, l, tb, ex, ey, ew, eh)
    local atk = enemyAttack_
    if not atk then return end

    -- ── 近战冲锋渲染（ground 模式专用） ──
    if atk.melee then
        if not atk.started then return end
        local phase = atk.phase
        local t = atk.timer

        -- 目标位置（主角身前）
        local hitX = l.x + l.w * 0.72
        local hitY = l.y + l.h * 0.68

        -- 冲锋阶段：敌人身后拉出速度线
        if phase == "charge" then
            local progress = math.min(1.0, t / MELEE_CHARGE_DURATION)
            local alpha = math.floor(progress * 180)
            local enemyCX = ex + ew * 0.5
            local enemyCY = ey + eh * 0.5
            nvgSave(nvg)
            for i = 1, 4 do
                local yOff = (i - 2.5) * (eh * 0.15)
                local lineLen = progress * ew * 0.8
                local lineAlpha = math.floor((1.0 - (i - 1) / 4) * alpha * 0.6)
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, enemyCX - ew * 0.3, enemyCY + yOff)
                nvgLineTo(nvg, enemyCX - ew * 0.3 - lineLen, enemyCY + yOff)
                nvgStrokeWidth(nvg, 1.5 - i * 0.2)
                nvgStrokeColor(nvg, nvgRGBA(255, 220, 180, lineAlpha))
                nvgStroke(nvg)
            end
            nvgRestore(nvg)
        end

        -- 命中阶段：爪痕冲击效果
        if phase == "hit" then
            local hitProg = math.min(1.0, t / MELEE_HIT_PAUSE)
            nvgSave(nvg)
            -- 冲击波纹
            local waveR = hitProg * 30
            local waveAlpha = math.floor((1.0 - hitProg) * 200)
            nvgBeginPath(nvg)
            nvgCircle(nvg, hitX, hitY, waveR)
            nvgStrokeWidth(nvg, 2.5 - hitProg * 2)
            nvgStrokeColor(nvg, nvgRGBA(255, 200, 100, waveAlpha))
            nvgStroke(nvg)

            -- 爪痕斜线（三条）
            local slashAlpha = math.floor((1.0 - hitProg * 0.5) * 220)
            local slashLen = 12 + hitProg * 8
            for si = 1, 3 do
                local ox = (si - 2) * 8
                local oy = (si - 2) * 5
                nvgBeginPath(nvg)
                nvgMoveTo(nvg, hitX + ox - slashLen * 0.5, hitY + oy - slashLen * 0.4)
                nvgLineTo(nvg, hitX + ox + slashLen * 0.5, hitY + oy + slashLen * 0.4)
                nvgStrokeWidth(nvg, 2.5 - si * 0.3)
                nvgStrokeColor(nvg, nvgRGBA(255, 120, 40, slashAlpha))
                nvgStroke(nvg)
            end

            -- 碎屑粒子
            for si = 1, 6 do
                local angle = (si / 6) * math.pi * 2 + t * 8
                local dist = hitProg * 20
                local px = hitX + math.cos(angle) * dist
                local py = hitY + math.sin(angle) * dist
                local pAlpha = math.floor((1.0 - hitProg) * 200)
                local pr = 2.5 - hitProg * 2
                if pr > 0.3 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, px, py, pr)
                    nvgFillColor(nvg, nvgRGBA(255, 160, 60, pAlpha))
                    nvgFill(nvg)
                end
            end
            nvgRestore(nvg)
        end

        -- 退回阶段：残留痕迹淡出
        if phase == "retreat" then
            local retreatProg = math.min(1.0, t / MELEE_RETREAT_DURATION)
            local fadeA = math.floor((1.0 - retreatProg) * 120)
            if fadeA > 5 then
                nvgSave(nvg)
                -- 淡出爪痕
                local slashLen = 18
                for si = 1, 3 do
                    local ox = (si - 2) * 8
                    local oy = (si - 2) * 5
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, hitX + ox - slashLen * 0.5, hitY + oy - slashLen * 0.4)
                    nvgLineTo(nvg, hitX + ox + slashLen * 0.5, hitY + oy + slashLen * 0.4)
                    nvgStrokeWidth(nvg, 1.5)
                    nvgStrokeColor(nvg, nvgRGBA(255, 100, 30, fadeA))
                    nvgStroke(nvg)
                end
                nvgRestore(nvg)
            end
        end

        return  -- 近战不渲染弹道
    end

    -- ── 远程弹道渲染 ──
    local t = atk.timer
    local d = atk.duration
    local flyTime = d * 0.25

    local progress = math.min(1.0, t / d)
    local fadeAlpha = 1.0
    if progress > 0.80 then
        fadeAlpha = (1.0 - progress) / 0.20
    end

    for _, tr in ipairs(atk.tracers) do
        local localT = t - (tr.delay or 0)
        if localT <= 0 then goto continue_enemy_tracer end

        -- 起点：敌方射击位置
        local startX, startY
        if groundMode_ then
            startX = ex + ew * 0.7  -- 敌方角色中心偏右（敌人在左侧，朝右射击）
            startY = ey + eh * 0.4
        else
            local eCenterX = ex + ew * 0.5
            local tCenterX = tb.x + tb.w * 0.5
            local enemyShootRight = tCenterX > eCenterX
            startX = enemyShootRight
                and (ex + ew * 0.85)
                or  (ex + ew * 0.15)
            startY = ey + eh * 0.35
        end

        -- 终点：玩家位置（主角在右侧）
        local endX, endY
        if groundMode_ then
            endX = l.x + l.w * (0.75 + (tr.xSpread or 0))
            endY = l.y + l.h * (0.72 + (tr.ySpread or 0))
        else
            endX = tb.x + tb.w * (0.5 + (tr.xSpread or 0))
            endY = tb.y + tb.h * (0.4 + (tr.ySpread or 0))
        end

        -- 敌方弹道颜色
        local trR, trG, trB = 255, 120, 40

        -- 飞行中
        if tr.progress < 1.0 then
            local curX = startX + (endX - startX) * tr.progress
            local curY = startY + (endY - startY) * tr.progress
            local tailPct = math.max(0, tr.progress - 0.25)
            local tailX = startX + (endX - startX) * tailPct
            local tailY = startY + (endY - startY) * tailPct

            nvgSave(nvg)
            nvgBeginPath(nvg)
            nvgMoveTo(nvg, tailX, tailY)
            nvgLineTo(nvg, curX, curY)
            nvgStrokeWidth(nvg, 1.5)
            nvgStrokeColor(nvg, nvgRGBA(trR, trG, trB, math.floor(fadeAlpha * 160)))
            nvgStroke(nvg)

            nvgBeginPath(nvg)
            nvgCircle(nvg, curX, curY, 2.5)
            nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(fadeAlpha * 220)))
            nvgFill(nvg)
            nvgRestore(nvg)
        end

        -- 炮口闪光
        if localT < 0.06 then
            local flashAlpha = (1 - localT / 0.06) * fadeAlpha
            nvgSave(nvg)
            nvgBeginPath(nvg)
            nvgCircle(nvg, startX, startY, 4 + localT * 40)
            nvgFillColor(nvg, nvgRGBA(255, 160, 50, math.floor(flashAlpha * 200)))
            nvgFill(nvg)
            nvgRestore(nvg)
        end

        -- 命中火花
        if tr.hit and atk.dmg > 0 then
            local hitT = localT - flyTime
            if hitT > 0 and hitT < 0.20 then
                local sparkT = hitT / 0.20
                nvgSave(nvg)
                for si = 1, 5 do
                    local angle = (si / 5) * math.pi * 2 + localT * 10
                    local dist = sparkT * 15
                    local sx = endX + math.cos(angle) * dist
                    local sy = endY + math.sin(angle) * dist
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, sx, sy, 2.5 - sparkT * 2)
                    nvgFillColor(nvg, nvgRGBA(255, 100, 30, math.floor((1 - sparkT) * fadeAlpha * 255)))
                    nvgFill(nvg)
                end
                nvgRestore(nvg)
            end
        end

        -- 未命中拖尾
        if tr.hit and atk.dmg == 0 then
            local hitT = localT - flyTime
            if hitT > 0 and hitT < 0.15 then
                local extendT = hitT / 0.15
                local extAlpha = (1 - extendT) * fadeAlpha
                local dx = endX - startX
                local dy = endY - startY
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    local nx, ny = dx / len, dy / len
                    local extLen = extendT * 40
                    nvgSave(nvg)
                    nvgBeginPath(nvg)
                    nvgMoveTo(nvg, endX, endY)
                    nvgLineTo(nvg, endX + nx * extLen, endY + ny * extLen)
                    nvgStrokeWidth(nvg, 1)
                    nvgStrokeColor(nvg, nvgRGBA(trR, trG, trB, math.floor(extAlpha * 100)))
                    nvgStroke(nvg)
                    nvgRestore(nvg)
                end
            end
        end

        ::continue_enemy_tracer::
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 受击边缘 vignette（vehicle/ground 共用）
-- ═══════════════════════════════════════════════════════════════

function M._renderVignette(nvg, l)
    if truckFlashTimer_ <= 0 then return end
    local alpha = math.min(1.0, truckFlashTimer_ / TRUCK_FLASH_DUR) * 0.5
    local a8 = math.floor(alpha * 255)
    local edgeW = l.w * 0.12
    local edgeH = l.h * 0.15
    nvgSave(nvg)
    -- 左
    local paintL = nvgLinearGradient(nvg, l.x, l.y, l.x + edgeW, l.y,
        nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, edgeW, l.h)
    nvgFillPaint(nvg, paintL)
    nvgFill(nvg)
    -- 右
    local paintR = nvgLinearGradient(nvg, l.x + l.w, l.y, l.x + l.w - edgeW, l.y,
        nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x + l.w - edgeW, l.y, edgeW, l.h)
    nvgFillPaint(nvg, paintR)
    nvgFill(nvg)
    -- 上
    local paintT = nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + edgeH,
        nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, edgeH)
    nvgFillPaint(nvg, paintT)
    nvgFill(nvg)
    -- 下
    local paintB = nvgLinearGradient(nvg, l.x, l.y + l.h, l.x, l.y + l.h - edgeH,
        nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y + l.h - edgeH, l.w, edgeH)
    nvgFillPaint(nvg, paintB)
    nvgFill(nvg)
    nvgRestore(nvg)
end

-- ═══════════════════════════════════════════════════════════════
-- ChibiScene 查询接口
-- ═══════════════════════════════════════════════════════════════

--- 获取当前速度倍率
function M.getSpeedMultiplier()
    if not active_ then return 1.0 end
    return speedMult_
end

--- 获取玩家卡车水平偏移（归一化），含后坐力
function M.getTruckOffset()
    if not active_ then return 0 end
    if groundMode_ then return 0 end  -- ground 模式无卡车偏移
    return truckOffset_ + recoilOffset_
end

--- 获取全局屏幕抖动偏移（像素）
---@return number shakeX, number shakeY
function M.getScreenShake()
    if not active_ then return 0, 0 end
    return screenShakeX_, screenShakeY_
end

--- 获取卡车受击闪白 alpha（0~1）
---@return number
function M.getTruckFlash()
    if not active_ then return 0 end
    if groundMode_ then return 0 end  -- ground 模式不闪卡车
    if truckFlashTimer_ <= 0 then return 0 end
    local flashPhase = math.floor(truckFlashTimer_ * 20) % 2
    if flashPhase ~= 0 then return 0 end
    return math.min(1.0, truckFlashTimer_ / TRUCK_FLASH_DUR) * 0.6
end

--- 更新卡车受损等级
---@param durPct number 当前耐久百分比 (0~1)
function M.setTruckDamage(durPct)
    if groundMode_ then return end  -- ground 模式无卡车损伤贴图
    if durPct > 0.7 then
        truckDamageLevel_ = "pristine"
    elseif durPct > 0.4 then
        truckDamageLevel_ = "light"
    elseif durPct > 0.15 then
        truckDamageLevel_ = "medium"
    else
        truckDamageLevel_ = "heavy"
    end
end

--- 获取战斗中卡车贴图路径
---@return string|nil
function M.getTruckImage()
    if not active_ then return nil end
    if groundMode_ then return nil end
    return TRUCK_COMBAT_IMAGES[truckDamageLevel_] or TRUCK_COMBAT_IMAGES.pristine
end

--- 是否处于 ground 模式
---@return boolean
function M.isGroundMode()
    return groundMode_
end

return M

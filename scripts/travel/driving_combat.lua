--- 战斗场景渲染模块
--- 在 DrivingScene 渲染管线中绘制敌方载具、纸娃娃和战术视觉效果
--- 同时控制玩家卡车偏移、加速动画、敌车相对位置
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

-- 动画参数
local BOB_FREQ        = 0.9
local BOB_PX          = 2.0
local BREATH_FREQ     = 0.5
local BREATH_AMP      = 0.03

-- 车轮
local WHEEL_IMAGE       = "image/wheel.png"

-- ═══════════════════════════════════════════════════════════════
-- 敌人类型 → 视觉映射
-- ═══════════════════════════════════════════════════════════════

local ENEMY_VISUALS = {
    ambush_light = {
        vehicle = "image/enemy_vehicle_raider_20260411070711.png",
        chibis  = {
            "image/chibi_npc_scavenger_20260409100005.png",
            "image/chibi_npc_scavenger_20260409100005.png",
        },
        -- 轮胎中心（归一化）及半径比
        wheels = {
            { rx = 0.313, ry = 0.765, size = 0.204 },
            { rx = 0.682, ry = 0.770, size = 0.204 },
        },
        -- 站人区域（归一化 {x, y, w, h}）
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

-- 战术 → 音效名映射
local TACTIC_SOUNDS = {
    accelerate = "combat_accelerate",
    steady     = "combat_gunfire",
    evade      = "combat_evade",
    smoke      = "combat_smoke",
}

-- ═══════════════════════════════════════════════════════════════
-- 状态
-- ═══════════════════════════════════════════════════════════════

local active_       = false
local enemyId_      = nil
local visuals_      = nil
local timer_        = 0
local scrollRef_    = 0

-- 敌方纸娃娃
local enemyChibis_  = {}

-- 活跃效果
local activeEffect_ = nil

-- 敌车震动
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
local enemyAttack_      = nil   -- { delay, timer, duration, dmg, tracers={}, phase }
local ENEMY_ATK_DELAY   = 0.5   -- 玩家战术效果后等待时间（秒）
local ENEMY_ATK_DURATION = 0.9  -- 敌方攻击动画总时长

-- 玩家卡车受击闪红
local truckFlashTimer_ = 0      -- > 0 时卡车闪红
local TRUCK_FLASH_DUR  = 0.35   -- 闪红持续时间

-- 战斗卡车贴图（外观版，按受损程度切换）
local TRUCK_COMBAT_IMAGES = {
    pristine = "image/edited_truck_home_exterior_v3_20260411053954.png",
    light    = "image/edited_truck_damage_light_v3_20260411092433.png",
    medium   = "image/edited_truck_damage_medium_v3_20260411092512.png",
    heavy    = "image/edited_truck_damage_heavy_v4_20260411092816.png",
}
local truckDamageLevel_ = "pristine"  -- "pristine"|"light"|"medium"|"heavy"

-- 速度倍率
local speedMult_       = 1.0
local speedMultTarget_ = 1.0

-- ── 卡车偏移系统 ──
-- truckOffset_: 当前玩家卡车水平偏移（归一化），正值=右移
local truckOffset_       = 0
local truckOffsetTarget_ = COMBAT_TRUCK_OFFSET

-- ── 敌车动态 X 位置（归一化）──
-- 加速时被推到右边，然后缓慢回到基准位置
local enemyXNorm_       = ENEMY_BASE_X
local enemyXTarget_     = ENEMY_BASE_X

-- 玩家效果粒子（独立于敌方）
local particles_      = {}
-- 敌方攻击粒子（独立于玩家）
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
---@param enemy_id string
function M.activate(enemy_id)
    active_ = true
    enemyId_ = enemy_id
    visuals_ = ENEMY_VISUALS[enemy_id] or ENEMY_VISUALS.ambush_light
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
    truckOffset_ = 0               -- 从居中开始，缓动到偏右
    truckOffsetTarget_ = COMBAT_TRUCK_OFFSET
    enemyXNorm_ = ENEMY_BASE_X
    enemyXTarget_ = ENEMY_BASE_X
    truckDamageLevel_ = "pristine"
    activeEffect_ = nil
    particles_ = {}
    enemyParticles_ = {}

    -- 预加载所有战斗卡车贴图，避免切换时闪烁
    for _, path in pairs(TRUCK_COMBAT_IMAGES) do
        ImageCache.Get(path)
    end

    enemyChibis_ = {}
    for i, img in ipairs(visuals_.chibis) do
        table.insert(enemyChibis_, {
            image   = img,
            phase   = math.random() * 10,
            facing  = 1,
            xNorm   = 0.25 + (i - 1) * 0.35,
        })
    end
end

--- 关闭战斗渲染
function M.deactivate()
    active_ = false
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
end

--- 触发战术视觉效果
---@param tacticId string  "accelerate"|"steady"|"evade"|"smoke"
---@param result table     回合结果
function M.triggerEffect(tacticId, result)
    if not active_ then return end

    -- ══════════════════════════════════════════════
    -- 玩家侧：总是重置，重新开始自己的效果
    -- ══════════════════════════════════════════════

    -- 播放音效
    local sfx = TACTIC_SOUNDS[tacticId]
    if sfx then
        local gain = (tacticId == "steady") and 1.4 or 1.0
        SoundMgr.play(sfx, gain)
    end

    -- 后坐力 / 屏幕抖动
    if tacticId == "steady" then
        screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 8
        screenShakeY_ = screenShakeY_ - 3 - math.random() * 4
        recoilOffset_ = recoilOffset_ + RECOIL_KICK
    end

    -- 重置玩家视觉效果（每次点击都重新来一轮）
    particles_ = {}

    if tacticId == "accelerate" then
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

    elseif tacticId == "steady" then
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

    elseif tacticId == "evade" then
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

    elseif tacticId == "smoke" then
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
    -- 敌人侧：总是重置，立刻开始敌方反击
    -- （与玩家完全独立，同时进行）
    -- ══════════════════════════════════════════════
    local dmg = result and result.dmg_taken or 0
    local tracerCount = 2 + math.random(2)  -- 2~4 发
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
        delay    = ENEMY_ATK_DELAY,    -- 短延迟后敌人开火，不等玩家效果播完
        timer    = 0,
        duration = ENEMY_ATK_DURATION,
        dmg      = dmg,
        tracers  = enemyParticles_,
        started  = false,
        done     = false,
    }
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

    -- 卡车偏移缓动
    truckOffset_ = lerp(truckOffset_, truckOffsetTarget_, dt, 3)

    -- 敌车 X 位置缓动
    enemyXNorm_ = lerp(enemyXNorm_, enemyXTarget_, dt, 2.5)

    -- 更新活跃效果
    if activeEffect_ then
        activeEffect_.timer = activeEffect_.timer + dt
        local t = activeEffect_.timer
        local d = activeEffect_.duration

        if activeEffect_.type == "accelerate" then
            -- 阶段1 (0~40%): 加速冲刺，卡车左移，敌车右移
            -- 阶段2 (40~70%): 保持加速
            -- 阶段3 (70~100%): 减速恢复，卡车和敌车回到战斗位置
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
                        local flyTime = d * 0.18  -- 每发飞行时间
                        p.progress = math.min(1.0, localT / flyTime)
                        if p.progress >= 1.0 and not p.hit then
                            p.hit = true
                            -- 每发命中都追加敌车震动
                            enemyShakeX_ = enemyShakeX_ + (math.random() - 0.5) * 5
                            enemyShakeY_ = enemyShakeY_ + (math.random() - 0.5) * 3
                            -- 每发命中追加微弱屏幕抖动
                            screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 3
                            screenShakeY_ = screenShakeY_ - math.random() * 2
                        end
                    end
                    -- 每发开火时追加后坐力
                    if not p.flashDone and t >= (p.delay or 0) then
                        p.flashDone = true
                        recoilOffset_ = recoilOffset_ + RECOIL_KICK * 0.5
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
            truckOffsetTarget_ = COMBAT_TRUCK_OFFSET
            enemyXTarget_ = ENEMY_BASE_X
            enemyShakeX_ = 0
            enemyShakeY_ = 0
        end
    end

    -- 敌车震动衰减
    if enemyShakeX_ ~= 0 or enemyShakeY_ ~= 0 then
        enemyShakeX_ = enemyShakeX_ * (1 - dt * 8)
        enemyShakeY_ = enemyShakeY_ * (1 - dt * 8)
        if math.abs(enemyShakeX_) < 0.3 then enemyShakeX_ = 0 end
        if math.abs(enemyShakeY_) < 0.3 then enemyShakeY_ = 0 end
    end

    -- 全局屏幕抖动衰减（高频震荡 + 快速衰减）
    if screenShakeX_ ~= 0 or screenShakeY_ ~= 0 then
        -- 添加高频震荡，让抖动不只是单方向
        local shakePhase = timer_ * 45
        screenShakeX_ = screenShakeX_ * (1 - dt * screenShakeDecay_)
            + math.sin(shakePhase) * math.abs(screenShakeX_) * 0.3
        screenShakeY_ = screenShakeY_ * (1 - dt * screenShakeDecay_)
            + math.cos(shakePhase * 1.3) * math.abs(screenShakeY_) * 0.3
        if math.abs(screenShakeX_) < 0.2 then screenShakeX_ = 0 end
        if math.abs(screenShakeY_) < 0.2 then screenShakeY_ = 0 end
    end

    -- 后坐力衰减
    if recoilOffset_ ~= 0 then
        recoilOffset_ = recoilOffset_ * (1 - dt * RECOIL_DECAY)
        if math.abs(recoilOffset_) < 0.002 then recoilOffset_ = 0 end
    end

    -- ── 敌方攻击更新 ──
    if enemyAttack_ and not enemyAttack_.done then
        enemyAttack_.timer = enemyAttack_.timer + dt

        if not enemyAttack_.started then
            -- 等待延迟
            if enemyAttack_.timer >= enemyAttack_.delay then
                enemyAttack_.started = true
                enemyAttack_.timer = 0  -- 重置为攻击动画计时
                -- 播放敌方射击音效（用枪声，增益低一些表示远处）
                SoundMgr.play("combat_gunfire", 0.6)
            end
        else
            -- 攻击动画进行中
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
                            -- 命中：卡车闪红 + 屏幕抖动
                            truckFlashTimer_ = TRUCK_FLASH_DUR
                            screenShakeX_ = screenShakeX_ + (math.random() - 0.5) * 10
                            screenShakeY_ = screenShakeY_ + 4 + math.random() * 4
                        end
                    end
                end
            end

            -- 攻击动画结束
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
---@param tb table     { x, y, w, h, bounce } 玩家卡车边界
function M.render(nvg, l, tb)
    if not active_ or not visuals_ then return end
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

    -- ── 敌车位置（使用动态 enemyXNorm_）──
    -- 用第一个轮胎的配置来定位车辆（轮胎底边贴地）
    local roadSurface = l.y + l.h * 0.88
    local wheels = visuals_.wheels or {{ rx = 0.3, ry = 0.8, size = 0.2 }}
    local firstW = wheels[1]
    local wheelR = enemyH * firstW.size * 0.5
    local wheelCenterY = enemyH * firstW.ry
    local enemyX = l.x + l.w * enemyXNorm_ + enemyShakeX_
    local enemyY = roadSurface - wheelCenterY - wheelR + tb.bounce + enemyShakeY_

    -- ── 命中闪红（任意弹道命中时闪烁）──
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

    -- ── 敌车车轮（转速随 speedMult_ 联动，每辆车独立配置）──
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

    -- ── 敌方纸娃娃（基于 crewZone 定位）──
    local cz = visuals_.crewZone or { x = 0.2, y = 0.1, w = 0.4, h = 0.35 }
    for _, c in ipairs(enemyChibis_) do
        -- 纸娃娃高度 = crewZone 高度的 85%
        local chibiH = enemyH * cz.h * 0.85
        local chibiW = chibiH
        local chibiImg = ImageCache.Get(c.image)
        if chibiImg ~= 0 then
            -- 在 crewZone 内按 xNorm 分布
            local zoneX = enemyX + cz.x * enemyW
            local zoneW = cz.w * enemyW
            local zoneY = enemyY + cz.y * enemyH
            local zoneH = cz.h * enemyH
            local drawX = zoneX + c.xNorm * zoneW - chibiW / 2
            local drawY = zoneY + zoneH - chibiH  -- 脚踩在 crewZone 底部

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

    -- ── 受击屏幕边缘红色 vignette ──
    if truckFlashTimer_ > 0 then
        local alpha = math.min(1.0, truckFlashTimer_ / TRUCK_FLASH_DUR) * 0.5
        local a8 = math.floor(alpha * 255)
        local edgeW = l.w * 0.12  -- vignette 边缘宽度
        local edgeH = l.h * 0.15
        nvgSave(nvg)
        -- 左边缘
        local paintL = nvgLinearGradient(nvg, l.x, l.y, l.x + edgeW, l.y,
            nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, edgeW, l.h)
        nvgFillPaint(nvg, paintL)
        nvgFill(nvg)
        -- 右边缘
        local paintR = nvgLinearGradient(nvg, l.x + l.w, l.y, l.x + l.w - edgeW, l.y,
            nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x + l.w - edgeW, l.y, edgeW, l.h)
        nvgFillPaint(nvg, paintR)
        nvgFill(nvg)
        -- 上边缘
        local paintT = nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + edgeH,
            nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, edgeH)
        nvgFillPaint(nvg, paintT)
        nvgFill(nvg)
        -- 下边缘
        local paintB = nvgLinearGradient(nvg, l.x, l.y + l.h, l.x, l.y + l.h - edgeH,
            nvgRGBA(255, 20, 20, a8), nvgRGBA(255, 20, 20, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y + l.h - edgeH, l.w, edgeH)
        nvgFillPaint(nvg, paintB)
        nvgFill(nvg)
        nvgRestore(nvg)
    end
end

-- ═══════════════════════════════════════════════════════════════
-- 效果渲染
-- ═══════════════════════════════════════════════════════════════

function M._renderEffect(nvg, l, tb, ex, ey, ew, eh)
    local eff = activeEffect_
    if not eff then return end
    local t = eff.timer
    local d = eff.duration
    local progress = math.min(1.0, t / d)

    -- 全局淡出（最后 25% 时间淡出）
    local fadeAlpha = 1.0
    if progress > 0.75 then
        fadeAlpha = (1.0 - progress) / 0.25
    end

    if eff.type == "accelerate" then
        -- 速度线
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
        -- 每发弹道独立渲染
        for _, p in ipairs(particles_) do
            if p.kind == "tracer" then
                local localT = t - (p.delay or 0)
                if localT <= 0 then goto continue_tracer end

                -- 玩家弹道起点：卡车朝敌车一侧的枪口
                local enemyCenterX = ex + ew * 0.5
                local truckCenterX = tb.x + tb.w * 0.5
                local shootFromRight = enemyCenterX > truckCenterX
                local startX = shootFromRight
                    and (tb.x + tb.w * 0.85)
                    or  (tb.x + tb.w * 0.15)
                local startY = tb.y + tb.h * 0.1
                local endX = ex + ew * (0.5 + (p.xSpread or 0))
                local endY = ey + eh * (0.4 + (p.ySpread or 0))

                -- 弹道线 + 弹头
                if p.progress < 1.0 then
                    local curX = startX + (endX - startX) * p.progress
                    local curY = startY + (endY - startY) * p.progress
                    -- 弹道尾迹（短线段）
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

                -- 每发炮口闪光
                if localT < 0.08 then
                    local flashAlpha = (1 - localT / 0.08) * fadeAlpha
                    local fx = startX
                    local fy = startY
                    nvgSave(nvg)
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, fx, fy, 5 + localT * 50)
                    nvgFillColor(nvg, nvgRGBA(255, 220, 80, math.floor(flashAlpha * 220)))
                    nvgFill(nvg)
                    nvgRestore(nvg)
                end

                -- 每发命中火花
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
-- 敌方攻击弹道渲染
-- ═══════════════════════════════════════════════════════════════

function M._renderEnemyAttack(nvg, l, tb, ex, ey, ew, eh)
    local atk = enemyAttack_
    if not atk then return end
    local t = atk.timer
    local d = atk.duration
    local flyTime = d * 0.25

    -- 全局淡出（最后 20% 时间淡出）
    local progress = math.min(1.0, t / d)
    local fadeAlpha = 1.0
    if progress > 0.80 then
        fadeAlpha = (1.0 - progress) / 0.20
    end

    for _, tr in ipairs(atk.tracers) do
        local localT = t - (tr.delay or 0)
        if localT <= 0 then goto continue_enemy_tracer end

        -- 起点：敌车枪口位置
        -- 敌方弹道起点：敌车朝玩家卡车一侧的枪口
        local eCenterX = ex + ew * 0.5
        local tCenterX = tb.x + tb.w * 0.5
        local enemyShootRight = tCenterX > eCenterX
        local startX = enemyShootRight
            and (ex + ew * 0.85)
            or  (ex + ew * 0.15)
        local startY = ey + eh * 0.35
        -- 终点：玩家卡车（命中 → 车身中心；未命中 → 大偏移飞过）
        local endX = tb.x + tb.w * (0.5 + (tr.xSpread or 0))
        local endY = tb.y + tb.h * (0.4 + (tr.ySpread or 0))

        -- 弹道颜色：敌方用橙红色弹道，与玩家金黄色区分
        local trR, trG, trB = 255, 120, 40

        -- 飞行中的弹道线
        if tr.progress < 1.0 then
            local curX = startX + (endX - startX) * tr.progress
            local curY = startY + (endY - startY) * tr.progress
            -- 尾迹
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

            -- 弹头亮点
            nvgBeginPath(nvg)
            nvgCircle(nvg, curX, curY, 2.5)
            nvgFillColor(nvg, nvgRGBA(255, 200, 80, math.floor(fadeAlpha * 220)))
            nvgFill(nvg)
            nvgRestore(nvg)
        end

        -- 敌方炮口闪光
        if localT < 0.06 then
            local flashAlpha = (1 - localT / 0.06) * fadeAlpha
            nvgSave(nvg)
            nvgBeginPath(nvg)
            nvgCircle(nvg, startX, startY, 4 + localT * 40)
            nvgFillColor(nvg, nvgRGBA(255, 160, 50, math.floor(flashAlpha * 200)))
            nvgFill(nvg)
            nvgRestore(nvg)
        end

        -- 命中火花（只有 dmg > 0 时才有）
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

        -- 未命中拖尾（dmg == 0 时弹道飞过卡车后继续延伸）
        if tr.hit and atk.dmg == 0 then
            local hitT = localT - flyTime
            if hitT > 0 and hitT < 0.15 then
                local extendT = hitT / 0.15
                local extAlpha = (1 - extendT) * fadeAlpha
                -- 弹道继续延伸方向
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
-- DrivingScene 查询接口
-- ═══════════════════════════════════════════════════════════════

--- 获取当前速度倍率（供 DrivingScene 视差滚动 + 车轮转速）
function M.getSpeedMultiplier()
    if not active_ then return 1.0 end
    return speedMult_
end

--- 获取玩家卡车水平偏移（归一化，正值=右移），含后坐力
function M.getTruckOffset()
    if not active_ then return 0 end
    return truckOffset_ + recoilOffset_
end

--- 获取全局屏幕抖动偏移（像素）
---@return number shakeX, number shakeY
function M.getScreenShake()
    if not active_ then return 0, 0 end
    return screenShakeX_, screenShakeY_
end

--- 获取卡车受击闪白 alpha（0~1），由 driving_scene.drawTruck 使用
---@return number
function M.getTruckFlash()
    if not active_ then return 0 end
    if truckFlashTimer_ <= 0 then return 0 end
    local flashPhase = math.floor(truckFlashTimer_ * 20) % 2
    if flashPhase ~= 0 then return 0 end
    return math.min(1.0, truckFlashTimer_ / TRUCK_FLASH_DUR) * 0.6
end

--- 更新卡车受损等级（由 screen_ambush 每回合调用）
---@param durPct number 当前耐久百分比 (0~1)
function M.setTruckDamage(durPct)
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

--- 获取战斗中卡车贴图路径（供 driving_scene.drawTruck 使用）
---@return string|nil  战斗中返回外观贴图路径，非战斗返回 nil
function M.getTruckImage()
    if not active_ then return nil end
    return TRUCK_COMBAT_IMAGES[truckDamageLevel_] or TRUCK_COMBAT_IMAGES.pristine
end

return M

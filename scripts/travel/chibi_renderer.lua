--- 纸娃娃渲染与 AI 模块
--- 从 driving_scene.lua 提取的通用角色系统：绘制、动画、状态机、表情、点击互动、NPC 管理
---
--- 依赖由调用方（chibi_scene）提供 sceneBounds 和 zoneDefs，不直接引用卡车相关逻辑。

local ImageCache  = require("urhox-libs/UI/Core/ImageCache")
local NpcManager  = require("narrative/npc_manager")
local WanderingNpc = require("narrative/wandering_npc")
local Graph       = require("map/world_graph")
local Factions    = require("settlement/factions")

local M = {}

-- ============================================================
-- 纸娃娃图片 & 姿势
-- ============================================================

--- 纸娃娃图片（按姿势差分）
local CHIBI_IMAGES = {
    linli = {
        default = "image/chibi_linli_20260409053601.png",
        drive   = "image/chibi_linli_drive_20260409070207.png",
        eat     = "image/chibi_linli_eat_20260409070212.png",
        cook    = "image/chibi_linli_cook_20260409070159.png",
        sleep   = "image/chibi_linli_sleep_20260409073014.png",
        combat  = "image/chibi_linli_combat_20260412041408.png",
    },
    taoxia = {
        default = "image/chibi_taoxia_20260409053853.png",
        drive   = "image/chibi_taoxia_drive_20260409070148.png",
        eat     = "image/chibi_taoxia_eat_20260409070156.png",
        cook    = "image/chibi_taoxia_cook_20260409070214.png",
        sleep   = "image/chibi_taoxia_sleep_20260409073033.png",
        combat  = "image/chibi_taoxia_combat_20260412042631.png",
    },
}

--- 区域→姿势映射
local ZONE_POSE = {
    cabin     = "drive",
    table     = "eat",
    stove     = "cook",
    bed       = "sleep",
    container = "default",
    outside   = "default",
    -- 探索模式 zone
    ground_left   = "default",
    ground_right  = "default",
    ground_center = "default",
}

-- ============================================================
-- NPC 数据表
-- ============================================================

--- 特殊 NPC chibi 映射 (npc_id → chibi path)
local NPC_CHIBI_MAP = {
    shen_he    = "image/chibi_npc_shen_he_20260409101614.png",
    han_ce     = "image/chibi_npc_han_ce_20260409102702.png",
    wu_shiqi   = "image/chibi_npc_wu_shiqi_20260409102746.png",
    bai_shu    = "image/chibi_npc_bai_shu_20260409101846.png",
    zhao_miao  = "image/chibi_npc_zhao_miao_20260409101609.png",
    ji_wei     = "image/chibi_npc_ji_wei_20260409120514.png",
    old_gan    = "image/chibi_npc_old_gan_20260409120642.png",
    dao_yu     = "image/chibi_npc_dao_yu_20260409120745.png",
    xie_ling   = "image/chibi_npc_xie_ling_20260409120841.png",
    meng_hui   = "image/chibi_npc_meng_hui_20260409120916.png",
    ming_sha   = "image/chibi_npc_ming_sha_20260409121030.png",
    a_xiu      = "image/chibi_npc_a_xiu_20260409121138.png",
    cheng_yuan = "image/chibi_npc_cheng_yuan_20260409121235.png",
    su_mo      = "image/chibi_npc_su_mo_20260409121902.png",
}

--- 势力→通用路人 chibi
local FACTION_GENERIC_CHIBI = {
    farm    = "image/chibi_npc_farmer_20260409100017.png",
    tech    = "image/chibi_npc_tech_20260409100016.png",
    scav    = "image/chibi_npc_scavenger_20260409100005.png",
    scholar = "image/chibi_npc_monk_20260409100009.png",
}

--- 额外路人池
local EXTRA_PASSERBY = {
    "image/chibi_npc_han_ce_20260409102125.png",
    "image/chibi_npc_wu_shiqi_20260409101613.png",
    "image/chibi_npc_a_xiu_20260409113139.png",
}

--- 势力→气泡表情池
local FACTION_EMOTES = {
    farm    = { "🌾", "🌱", "☀️", "💧", "👋", "..." },
    tech    = { "⚙", "📡", "🔋", "💡", "👋", "..." },
    scav    = { "🔧", "🔩", "📦", "🔪", "👋", "..." },
    scholar = { "📖", "🕯", "✍️", "🔔", "👋", "..." },
}
local DEFAULT_EMOTES = { "👋", "...", "💬", "❓", "🎒" }

-- ============================================================
-- 动画参数
-- ============================================================

--- 纸娃娃高度占场景高度的比例
M.CHIBI_H_RATIO = 0.32
--- 移动速度（归一化/秒）
local CHIBI_WALK_SPEED = 0.10
--- 切换区域间隔范围（秒）
local CHIBI_ZONE_SWITCH_MIN = 20
local CHIBI_ZONE_SWITCH_MAX = 40
--- 行走动画参数
local WOBBLE_FREQ   = 2.2
local WOBBLE_PX     = 6.0
local WALK_SQUASH_AMP = 0.04
local WALK_LEAN_DEG   = 2.5
--- 纸片翻转转身时长
local FLIP_DURATION = 0.25
--- zone 切换淡入淡出时长
local ZONE_FADE_DURATION = 0.3
--- idle 呼吸缩放参数
local BREATH_FREQ   = 0.6
local BREATH_AMP    = 0.035
local IDLE_BOB_FREQ = 0.8
local IDLE_BOB_PX   = 2.5
--- 战斗徘徊参数
local COMBAT_SWAY_RANGE = 0.04   -- 归一化 x 徘徊幅度（±）
local COMBAT_SWAY_SPEED = 0.06   -- 归一化/秒，徘徊移动速度
local COMBAT_SWAY_PAUSE_MIN = 0.8  -- 到达目标后停顿最短时间
local COMBAT_SWAY_PAUSE_MAX = 2.0  -- 到达目标后停顿最长时间
--- 气泡表情配置
local EMOTE_INTERVAL_MIN = 8
local EMOTE_INTERVAL_MAX = 20
local EMOTE_DURATION     = 2.5
local EMOTE_FADE_TIME    = 0.4
--- 状态/区域表情池
local EMOTES_IDLE    = { "💤", "...", "～♪", "😊", "🤔" }
local EMOTES_WALK    = { "♪", "🎵", "!", "→" }
local EMOTES_CABIN   = { "🚗", "👀", "😤", "～♪", "🛣️" }
local EMOTES_TABLE   = { "🍚", "😋", "🥢", "好吃", "🍜" }
local EMOTES_STOVE   = { "🔥", "🍳", "好香", "👨‍🍳", "♨️" }
local EMOTES_BED     = { "💤", "😴", "zzZ", "😌", "..." }
local EMOTES_OUTSIDE = { "🌿", "☁️", "😌", "🔍" }

--- 固定区域停留时间
local FIXED_ZONE_DURATION_MIN = 8
local FIXED_ZONE_DURATION_MAX = 15

-- ============================================================
-- 点击互动配置
-- ============================================================

local CLICK_CD            = 2.0
local CLICK_BOUNCE_DUR    = 0.35
local CLICK_BOUNCE_PX     = 10
local CLICK_COMBO_WINDOW  = 4.0

--- 主角点击台词（连击等级 1/2/3）
local CLICK_LINES = {
    linli = {
        { "嗯？怎么了～", "在看路呢", "嘿嘿", "有什么事吗？", "你好呀～" },
        { "别戳啦～", "好啦好啦", "干嘛一直戳我" },
        { "再戳不理你了！", "哼！", "讨厌啦！" },
    },
    taoxia = {
        { "嗯", "干嘛", "…有事？", "看路", "别闹" },
        { "够了", "别碰", "烦" },
        { "再碰试试", "…（怒）", "走开" },
    },
}

--- NPC 点击台词（按势力）
local NPC_CLICK_LINES = {
    farm    = { "你好～", "今年收成还行", "要买点粮食吗", "路上注意安全" },
    tech    = { "有何指教", "别碰设备", "系统运转正常", "嗯…有意思" },
    scav    = { "想交易？", "有好货", "别挡道", "识相的" },
    scholar = { "你好", "这很有趣", "记录一下…", "请指教" },
}
local NPC_CLICK_LINES_DEFAULT = { "你好", "路上小心", "嗯？", "…", "有缘再见" }

-- ============================================================
-- 公共 API
-- ============================================================

--- 获取角色当前姿势图片
---@param c table 角色状态
---@return string 图片路径
function M.getChibiImage(c)
    if c.npcImage then return c.npcImage end
    local poses = CHIBI_IMAGES[c.id]
    if not poses then return "" end
    -- 战斗锁定时使用战斗姿态差分（如有）
    if c._combatLocked and poses.combat then
        return poses.combat
    end
    local pose = ZONE_POSE[c.zone] or "default"
    return poses[pose] or poses.default
end

--- 创建一个角色状态表
---@param id string 角色 id ("linli" / "taoxia")
---@param zone string 初始 zone
---@param facing number 初始朝向 (1=右, -1=左)
---@return table
function M.createChibi(id, zone, facing)
    return {
        id = id,
        zone = zone,
        x = 0.5, targetX = 0.5,
        facing = facing,
        scaleX = facing,
        state = "idle",
        stateTimer = 1 + math.random() * 2,
        switchTimer = 20 + math.random() * 15,
        flipTimer = 0,
        flipFrom = facing,
        walkTime = 0,
        idleTime = 0,
        emote = nil,
        emoteTimer = 0,
        emoteCD = 5 + math.random() * 10,
        clickCD = 0,
        clickBounce = 0,
        clickCombo = 0,
        clickComboTimer = 0,
        -- 战斗徘徊
        _combatSwayCenter = 0.5,
        _combatSwayTarget = 0.5,
        _combatSwayPause = 0,
    }
end

--- 重置角色状态
---@param c table 角色状态表
---@param zone string
---@param x number
---@param facing number
---@param delay number idle 延迟
---@param switchT number zone 切换倒计时
function M.resetChibi(c, zone, x, facing, delay, switchT)
    c.zone = zone
    c.x = x; c.targetX = x
    c.facing = facing; c.scaleX = facing
    c.state = "idle"; c.stateTimer = delay
    c.switchTimer = switchT
    c.flipTimer = 0; c.flipFrom = facing
    c.walkTime = 0; c.idleTime = 0
    c.emote = nil; c.emoteTimer = 0
    c.emoteCD = EMOTE_INTERVAL_MIN + math.random() * (EMOTE_INTERVAL_MAX - EMOTE_INTERVAL_MIN)
end

-- ── 内部辅助 ────────────────────────────────────────────────

--- 判断另一个角色是否在指定区域
local function otherInZone(chibis, chibiIdx, zoneName)
    local otherIdx = chibiIdx == 1 and 2 or 1
    if not chibis[otherIdx] then return false end
    return chibis[otherIdx].zone == zoneName
end

--- 启动纸片翻转动画
local function startFlip(c, newFacing)
    if c.facing == newFacing then return end
    c.state = "turning"
    c.flipTimer = 0
    c.flipFrom = c.facing
end

--- 可用区域列表
---@param chibiIdx number
---@param zoneDefs table zone 定义表
---@param isDriving boolean
---@return string[]
local function getAvailableZones(chibiIdx, zoneDefs, isDriving)
    -- 检查是否有卡车 zone（driving 模式的标志）
    local hasCabin = zoneDefs.cabin ~= nil

    if hasCabin then
        if isDriving then
            return { "container", "container", "container", "cabin", "table", "stove", "bed" }
        else
            return { "outside", "outside", "outside", "outside", "container", "container", "table", "stove", "bed" }
        end
    else
        -- 探索模式：在地面 zone 之间走动
        local zones = {}
        for name, _ in pairs(zoneDefs) do
            table.insert(zones, name)
        end
        return zones
    end
end

--- 根据 zone 判断是否为固定姿势区域（不走动）
local function isFixedZone(zoneName)
    return zoneName == "cabin" or zoneName == "table" or zoneName == "stove" or zoneName == "bed"
end

-- ============================================================
-- 绘制
-- ============================================================

--- 绘制单个纸娃娃（带颠动 + 纸片缩放 + 呼吸 + 气泡表情）
---@param nvg userdata
---@param c table 角色状态
---@param drawX number 目标 x
---@param drawY number 目标 y
---@param chibiW number
---@param chibiH number
function M.drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
    -- 记录渲染位置供点击检测使用
    c._hitX = drawX
    c._hitY = drawY
    c._hitW = chibiW
    c._hitH = chibiH

    -- zone 切换淡入效果
    local zoneFadeAlpha = 1.0
    if c._zoneFadeIn and c._zoneFadeIn > 0 then
        zoneFadeAlpha = 1.0 - c._zoneFadeIn / ZONE_FADE_DURATION
    end
    if zoneFadeAlpha <= 0.01 then return end  -- 完全透明时跳过绘制

    local imgPath = M.getChibiImage(c)
    local imgHandle = ImageCache.Get(imgPath)
    if imgHandle == 0 then return end

    local cx = drawX + chibiW / 2
    local cy = drawY + chibiH      -- 变换支点在脚底

    -- 上下位移动画
    local bobY = 0
    if c.state == "walk" and c.walkTime > 0 then
        bobY = -math.abs(math.sin(c.walkTime * WOBBLE_FREQ * math.pi)) * WOBBLE_PX
    elseif c.state == "idle" and c.idleTime > 0 then
        bobY = -math.abs(math.sin(c.idleTime * IDLE_BOB_FREQ * math.pi)) * IDLE_BOB_PX
    end
    -- 点击弹跳
    if c.clickBounce and c.clickBounce > 0 then
        local t = c.clickBounce / CLICK_BOUNCE_DUR
        bobY = bobY - math.sin(t * math.pi) * CLICK_BOUNCE_PX
    end

    -- 身体形变动画
    local scaleY = 1.0
    local leanRad = 0
    if c.state == "walk" and c.walkTime > 0 then
        local walkPhase = c.walkTime * WOBBLE_FREQ * 2 * math.pi
        scaleY = 1.0 + math.sin(walkPhase) * WALK_SQUASH_AMP
        leanRad = math.sin(walkPhase * 0.5) * math.rad(WALK_LEAN_DEG)
    elseif (c.state == "idle" or c.state == "turning") and c.idleTime > 0 then
        scaleY = 1.0 + math.sin(c.idleTime * BREATH_FREQ * 2 * math.pi) * BREATH_AMP
    end

    nvgSave(nvg)
    if zoneFadeAlpha < 1.0 then nvgGlobalAlpha(nvg, zoneFadeAlpha) end
    nvgTranslate(nvg, cx, cy + bobY)
    if leanRad ~= 0 then nvgRotate(nvg, leanRad) end
    nvgScale(nvg, c.scaleX, scaleY)
    nvgTranslate(nvg, -cx, -cy - bobY)

    local paint = nvgImagePattern(nvg,
        drawX, drawY, chibiW, chibiH,
        0, imgHandle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, drawX, drawY, chibiW, chibiH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)

    nvgRestore(nvg)

    -- ── 气泡表情 ──
    if c.emote then
        local alpha = 1.0
        if c.emoteTimer < EMOTE_FADE_TIME then
            alpha = c.emoteTimer / EMOTE_FADE_TIME
        elseif c.emoteTimer > EMOTE_DURATION - EMOTE_FADE_TIME then
            alpha = (EMOTE_DURATION - c.emoteTimer) / EMOTE_FADE_TIME
        end
        alpha = math.max(0, math.min(1, alpha))

        local floatUp = math.sin(c.emoteTimer * 1.5) * 2
        local bubbleX = drawX + chibiW / 2
        local bubbleY = drawY + bobY - 6 + floatUp

        nvgSave(nvg)
        nvgGlobalAlpha(nvg, alpha * zoneFadeAlpha)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tw = nvgTextBounds(nvg, 0, 0, c.emote)
        local padX = 8
        local bw = math.max(22, tw + padX * 2)
        local bh = 18
        nvgBeginPath(nvg)
        nvgRoundedRect(nvg, bubbleX - bw / 2, bubbleY - bh, bw, bh, 5)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
        nvgFill(nvg)
        -- 小三角尾巴
        nvgBeginPath(nvg)
        nvgMoveTo(nvg, bubbleX - 3, bubbleY)
        nvgLineTo(nvg, bubbleX + 3, bubbleY)
        nvgLineTo(nvg, bubbleX, bubbleY + 4)
        nvgClosePath(nvg)
        nvgFillColor(nvg, nvgRGBA(255, 255, 255, 200))
        nvgFill(nvg)
        -- 表情文字
        nvgFillColor(nvg, nvgRGBA(40, 40, 40, 255))
        nvgText(nvg, bubbleX, bubbleY - bh / 2, c.emote)
        nvgRestore(nvg)
    end
end

-- ============================================================
-- AI 状态机更新
-- ============================================================

--- 更新单个角色的 AI 和动画
---@param c table 角色状态
---@param ci number 角色索引（1 or 2）
---@param dt number 帧间隔
---@param chibis table 主角色数组
---@param zoneDefs table zone 定义表
---@param isDriving boolean
---@param combatLocked boolean 是否因战斗锁定
local function updateSingleChibi(c, ci, dt, chibis, zoneDefs, isDriving, combatLocked)
    -- zone 切换淡入计时
    if c._zoneFadeIn and c._zoneFadeIn > 0 then
        c._zoneFadeIn = c._zoneFadeIn - dt
        if c._zoneFadeIn < 0 then c._zoneFadeIn = 0 end
    end

    -- 战斗中锁定的角色：跳过 zone 切换和状态机
    -- 但在小范围内来回徘徊走位（facing 不变）
    if c._combatLocked then
        -- 初始化徘徊中心（仅首次）
        if c._combatSwayCenter == 0.5 and c.x ~= 0.5 then
            c._combatSwayCenter = c.x
            c._combatSwayTarget = c.x
            c._combatSwayPause = 1.0 + math.random() * 1.5
        end

        -- 停顿中：等待一会再选下一个目标
        if c._combatSwayPause > 0 then
            c._combatSwayPause = c._combatSwayPause - dt
            c.idleTime = c.idleTime + dt
            c.walkTime = 0
            c.state = "idle"
        else
            -- 移动到徘徊目标
            local dx = c._combatSwayTarget - c.x
            if math.abs(dx) < COMBAT_SWAY_SPEED * dt then
                c.x = c._combatSwayTarget
                c.walkTime = 0
                c.state = "idle"
                c.idleTime = 0
                -- 选新目标，在中心点 ± SWAY_RANGE 内随机
                c._combatSwayTarget = c._combatSwayCenter
                    + (math.random() * 2 - 1) * COMBAT_SWAY_RANGE
                c._combatSwayPause = COMBAT_SWAY_PAUSE_MIN
                    + math.random() * (COMBAT_SWAY_PAUSE_MAX - COMBAT_SWAY_PAUSE_MIN)
            else
                local dir = dx > 0 and 1 or -1
                c.x = c.x + dir * COMBAT_SWAY_SPEED * dt
                c.walkTime = c.walkTime + dt
                c.state = "walk"
                c.idleTime = 0
                -- facing / scaleX 保持不变（面向敌人）
            end
        end
        return
    end

    -- ── 翻转动画 ──
    if c.state == "turning" then
        c.flipTimer = c.flipTimer + dt
        local progress = math.min(1, c.flipTimer / FLIP_DURATION)
        c.scaleX = c.flipFrom * math.cos(progress * math.pi)
        if progress >= 0.5 and c.facing == c.flipFrom then
            c.facing = -c.flipFrom
        end
        if progress >= 1 then
            c.scaleX = c.facing
            c.state = "walk"
            c.walkTime = 0
        end
        return
    end

    -- ── 区域切换倒计时 ──
    c.switchTimer = c.switchTimer - dt
    if c.switchTimer <= 0 then
        c.switchTimer = CHIBI_ZONE_SWITCH_MIN
            + math.random() * (CHIBI_ZONE_SWITCH_MAX - CHIBI_ZONE_SWITCH_MIN)

        -- 行驶中：必须保证至少一人在驾驶舱
        if isDriving and c.zone == "cabin" and not otherInZone(chibis, ci, "cabin") then
            return
        end

        local zones = getAvailableZones(ci, zoneDefs, isDriving)
        local candidates = {}
        for _, z in ipairs(zones) do
            if z ~= c.zone then
                table.insert(candidates, z)
            end
        end
        if #candidates > 0 then
            local newZone = candidates[math.random(#candidates)]
            c.zone = newZone
            c.x = 0.5
            c.targetX = 0.5
            c.state = "idle"
            c.stateTimer = 1 + math.random() * 2
            c.walkTime = 0
            c._zoneFadeIn = ZONE_FADE_DURATION  -- 淡入过渡
            c.emote = nil  -- 清除气泡，避免残影
            if isFixedZone(newZone) then
                c.switchTimer = FIXED_ZONE_DURATION_MIN
                    + math.random() * (FIXED_ZONE_DURATION_MAX - FIXED_ZONE_DURATION_MIN)
            end
        end
    end

    -- ── 状态机：idle ↔ walk ──
    local fixed = isFixedZone(c.zone)

    if c.state == "idle" then
        c.stateTimer = c.stateTimer - dt
        c.idleTime = c.idleTime + dt
        c.walkTime = 0
        if c.stateTimer <= 0 then
            if fixed then
                c.stateTimer = 3 + math.random() * 5
            else
                if c.zone == "container" or c.zone == "outside"
                   or c.zone == "ground_left" or c.zone == "ground_right" or c.zone == "ground_center" then
                    c.targetX = 0.08 + math.random() * 0.84
                else
                    c.targetX = 0.2 + math.random() * 0.6
                end
                local newFacing = (c.targetX > c.x) and 1 or -1
                if newFacing ~= c.facing then
                    startFlip(c, newFacing)
                else
                    c.state = "walk"
                    c.walkTime = 0
                end
            end
        end
    elseif c.state == "walk" then
        local spd = CHIBI_WALK_SPEED
        if c.zone == "cabin" then spd = spd * 0.5 end
        c.walkTime = c.walkTime + dt
        local dx = c.targetX - c.x
        if math.abs(dx) < spd * dt then
            c.x = c.targetX
            c.state = "idle"
            c.stateTimer = 2 + math.random() * 4
            c.walkTime = 0
            c.idleTime = 0
        else
            local dir = dx > 0 and 1 or -1
            c.x = c.x + dir * spd * dt
            if dir ~= c.facing then startFlip(c, dir) end
        end
        c.scaleX = c.facing
    end

    -- ── 气泡表情 ──
    if c.emote then
        c.emoteTimer = c.emoteTimer + dt
        if c.emoteTimer >= EMOTE_DURATION then
            c.emote = nil
            c.emoteTimer = 0
            c.emoteCD = EMOTE_INTERVAL_MIN
                + math.random() * (EMOTE_INTERVAL_MAX - EMOTE_INTERVAL_MIN)
        end
    else
        c.emoteCD = c.emoteCD - dt
        if c.emoteCD <= 0 then
            local pool = EMOTES_IDLE
            if c.state == "walk" then
                pool = EMOTES_WALK
            elseif c.zone == "cabin" then
                pool = EMOTES_CABIN
            elseif c.zone == "table" then
                pool = EMOTES_TABLE
            elseif c.zone == "stove" then
                pool = EMOTES_STOVE
            elseif c.zone == "bed" then
                pool = EMOTES_BED
            elseif c.zone == "outside" or c.zone == "ground_left"
                   or c.zone == "ground_right" or c.zone == "ground_center" then
                pool = EMOTES_OUTSIDE
            end
            c.emote = pool[math.random(#pool)]
            c.emoteTimer = 0
        end
    end

    -- ── 点击互动计时 ──
    if c.clickCD > 0 then c.clickCD = c.clickCD - dt end
    if c.clickBounce > 0 then
        c.clickBounce = c.clickBounce - dt
        if c.clickBounce < 0 then c.clickBounce = 0 end
    end
    if c.clickComboTimer > 0 then
        c.clickComboTimer = c.clickComboTimer - dt
        if c.clickComboTimer <= 0 then c.clickCombo = 0 end
    end
end

--- 更新NPC角色（仅 outside/ground zone 走动）
---@param c table NPC 状态
---@param dt number
local function updateNPC(c, dt)
    -- 翻转动画
    if c.state == "turning" then
        c.flipTimer = c.flipTimer + dt
        local progress = math.min(1, c.flipTimer / FLIP_DURATION)
        c.scaleX = c.flipFrom * math.cos(progress * math.pi)
        if progress >= 0.5 and c.facing == c.flipFrom then
            c.facing = -c.flipFrom
        end
        if progress >= 1 then
            c.scaleX = c.facing
            c.state = "walk"
            c.walkTime = 0
        end
    elseif c.state == "idle" then
        c.stateTimer = c.stateTimer - dt
        c.idleTime = c.idleTime + dt
        c.walkTime = 0
        if c.stateTimer <= 0 then
            c.targetX = 0.05 + math.random() * 0.90
            local newFacing = (c.targetX > c.x) and 1 or -1
            if newFacing ~= c.facing then
                startFlip(c, newFacing)
            else
                c.state = "walk"
                c.walkTime = 0
            end
        end
    elseif c.state == "walk" then
        c.walkTime = c.walkTime + dt
        local dx = c.targetX - c.x
        if math.abs(dx) < CHIBI_WALK_SPEED * dt then
            c.x = c.targetX
            c.state = "idle"
            c.stateTimer = 2 + math.random() * 5
            c.walkTime = 0
            c.idleTime = 0
        else
            local dir = dx > 0 and 1 or -1
            c.x = c.x + dir * CHIBI_WALK_SPEED * dt
            if dir ~= c.facing then startFlip(c, dir) end
        end
        c.scaleX = c.facing
    end
    -- 气泡表情
    if c.emote then
        c.emoteTimer = c.emoteTimer + dt
        if c.emoteTimer >= EMOTE_DURATION then
            c.emote = nil; c.emoteTimer = 0
            c.emoteCD = EMOTE_INTERVAL_MIN + math.random() * (EMOTE_INTERVAL_MAX - EMOTE_INTERVAL_MIN)
        end
    else
        c.emoteCD = c.emoteCD - dt
        if c.emoteCD <= 0 then
            local pool = c.npcEmotes or DEFAULT_EMOTES
            c.emote = pool[math.random(#pool)]
            c.emoteTimer = 0
        end
    end
    -- 点击互动计时
    if c.clickCD > 0 then c.clickCD = c.clickCD - dt end
    if c.clickBounce > 0 then
        c.clickBounce = c.clickBounce - dt
        if c.clickBounce < 0 then c.clickBounce = 0 end
    end
    if c.clickComboTimer > 0 then
        c.clickComboTimer = c.clickComboTimer - dt
        if c.clickComboTimer <= 0 then c.clickCombo = 0 end
    end
end

--- 更新所有角色 AI（主角 + NPC）
---@param dt number
---@param chibis table 主角数组
---@param npcs table NPC 数组
---@param zoneDefs table zone 定义
---@param isDriving boolean
---@param combatLocked boolean
function M.updateAll(dt, chibis, npcs, zoneDefs, isDriving, combatLocked)
    for ci, c in ipairs(chibis) do
        updateSingleChibi(c, ci, dt, chibis, zoneDefs, isDriving, combatLocked)
    end
    for _, c in ipairs(npcs) do
        updateNPC(c, dt)
    end
end

-- ============================================================
-- 点击检测
-- ============================================================

--- 检测点击是否命中纸娃娃（主角 + NPC）
---@param chibis table 主角数组
---@param npcs table NPC 数组
---@param baseX number 点击位置 base x
---@param baseY number 点击位置 base y
---@param onChibiClick function|nil 回调
---@return boolean consumed 是否消费了点击
function M.checkChibiInput(chibis, npcs, baseX, baseY, onChibiClick)
    local targets = {}
    for _, c in ipairs(chibis) do
        table.insert(targets, { chibi = c, isNpc = false })
    end
    for _, c in ipairs(npcs) do
        table.insert(targets, { chibi = c, isNpc = true })
    end

    for _, entry in ipairs(targets) do
        local c = entry.chibi
        if c._hitW and c._hitW > 0 and c.clickCD <= 0 then
            local pad = 4
            if baseX >= c._hitX - pad and baseX <= c._hitX + c._hitW + pad
               and baseY >= c._hitY - pad and baseY <= c._hitY + c._hitH + pad then
                c.clickCD = CLICK_CD
                c.clickBounce = CLICK_BOUNCE_DUR

                -- 连击判定
                if c.clickComboTimer > 0 then
                    c.clickCombo = math.min(c.clickCombo + 1, 3)
                else
                    c.clickCombo = 1
                end
                c.clickComboTimer = CLICK_COMBO_WINDOW

                -- 选取台词
                local line
                if entry.isNpc then
                    local pool = (c.npcFaction and NPC_CLICK_LINES[c.npcFaction])
                                 or NPC_CLICK_LINES_DEFAULT
                    line = pool[math.random(#pool)]
                else
                    local charLines = CLICK_LINES[c.id]
                    if charLines then
                        local level = math.min(c.clickCombo, #charLines)
                        local pool = charLines[level]
                        line = pool[math.random(#pool)]
                    end
                end

                -- 覆盖当前表情气泡
                if line then
                    c.emote = line
                    c.emoteTimer = 0
                    c.emoteCD = EMOTE_INTERVAL_MAX
                end

                if onChibiClick then
                    onChibiClick(c, entry.isNpc)
                end
                return true
            end
        end
    end
    return false
end

-- ============================================================
-- NPC 管理
-- ============================================================

--- 当前 NPC 列表（模块级存储）
local npcs_ = {}

--- 创建 NPC 路人
---@param gameState table 游戏状态
function M.spawnNPCs(gameState)
    npcs_ = {}
    if not gameState then return end

    local currentLoc = gameState.map and gameState.map.current_location
    if not currentLoc then return end

    local node = Graph.get_node(currentLoc)
    if not node then return end

    local isSettlement = (node.type == "settlement")
    local factionId = isSettlement and Factions.get_faction(currentLoc) or nil
    local factionEmotes = (factionId and FACTION_EMOTES[factionId]) or DEFAULT_EMOTES

    local candidates = {}
    local usedImages = {}

    -- 流浪 NPC
    local wanderers = WanderingNpc.get_wanderers_at(gameState, currentLoc)
    for _, w in ipairs(wanderers) do
        if NPC_CHIBI_MAP[w.id] and not usedImages[NPC_CHIBI_MAP[w.id]] then
            table.insert(candidates, {
                id = w.id, image = NPC_CHIBI_MAP[w.id],
                priority = 8, emotes = DEFAULT_EMOTES, faction = nil,
            })
            usedImages[NPC_CHIBI_MAP[w.id]] = true
        end
    end

    if isSettlement then
        -- 驻扎 NPC
        local residents = NpcManager.get_npcs_for_settlement(currentLoc)
        for _, npc in ipairs(residents) do
            if NPC_CHIBI_MAP[npc.id] and not usedImages[NPC_CHIBI_MAP[npc.id]] then
                table.insert(candidates, {
                    id = npc.id, image = NPC_CHIBI_MAP[npc.id],
                    priority = 10, emotes = factionEmotes, faction = factionId,
                })
                usedImages[NPC_CHIBI_MAP[npc.id]] = true
            end
        end
        -- 通用路人
        if factionId and FACTION_GENERIC_CHIBI[factionId] then
            local genImg = FACTION_GENERIC_CHIBI[factionId]
            if not usedImages[genImg] then
                table.insert(candidates, {
                    id = "generic_" .. factionId, image = genImg,
                    priority = 3, emotes = factionEmotes, faction = factionId,
                })
                usedImages[genImg] = true
            end
        end
        -- 额外路人
        if #EXTRA_PASSERBY > 0 then
            local shuffled = {}
            for i = 1, #EXTRA_PASSERBY do shuffled[i] = EXTRA_PASSERBY[i] end
            for i = #shuffled, 2, -1 do
                local j = math.random(i)
                shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
            end
            for _, img in ipairs(shuffled) do
                if not usedImages[img] then
                    table.insert(candidates, {
                        id = "extra_passerby", image = img,
                        priority = 1, emotes = factionEmotes, faction = factionId,
                    })
                    usedImages[img] = true
                    break
                end
            end
        end
    end

    if #candidates == 0 then return end

    table.sort(candidates, function(a, b) return a.priority > b.priority end)
    local maxNPCs = math.min(#candidates, 2 + math.random(0, 1))

    for i = 1, maxNPCs do
        local c = candidates[i]
        local npc = {
            id = c.id,
            npcImage = c.image,
            npcEmotes = c.emotes,
            npcFaction = c.faction,
            zone = "outside",
            x = 0.15 + math.random() * 0.7,
            targetX = 0.5,
            facing = (math.random() > 0.5) and 1 or -1,
            scaleX = 1,
            state = "idle",
            stateTimer = 1 + math.random() * 3,
            switchTimer = 999,
            flipTimer = 0,
            flipFrom = 1,
            walkTime = 0,
            idleTime = math.random() * 5,
            emote = nil,
            emoteTimer = 0,
            emoteCD = 6 + math.random() * 15,
            clickCD = 0,
            clickBounce = 0,
            clickCombo = 0,
            clickComboTimer = 0,
        }
        npc.scaleX = npc.facing
        npc.flipFrom = npc.facing
        table.insert(npcs_, npc)
    end

    if #npcs_ > 0 then
        print("[ChibiRenderer] Spawned " .. #npcs_ .. " NPCs at " .. currentLoc
            .. " (faction=" .. (factionId or "none") .. ")")
    end
end

--- 清除 NPC 路人
function M.clearNPCs()
    npcs_ = {}
end

--- 获取当前 NPC 列表
---@return table[]
function M.getNPCs()
    return npcs_
end

return M

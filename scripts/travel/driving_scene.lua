--- 行驶视差场景组件
--- 在旅行首页显示卡车行驶动画：多层视差滚动背景 + 居中卡车 + 车轮旋转
--- 支持环境系统：区域中景切换 + 晨夜色调 + 天气粒子效果
---
--- 用法：
---   local DrivingScene = require("travel/driving_scene")
---   -- 在 createTravelView 中：
---   DrivingScene.createWidget({ height = 220 })
---   -- 在 update 中：
---   DrivingScene.update(dt)
---   -- 环境切换（segment 变化时）：
---   DrivingScene.setEnvironment({ region="farm", weather="rain", timeOfDay="dusk" })

local Widget     = require("urhox-libs/UI/Core/Widget")
local ImageCache = require("urhox-libs/UI/Core/ImageCache")
local RoadLoot   = require("travel/road_loot")
local Modules    = require("truck/modules")

local M = {}

-- ============================================================
-- 配置
-- ============================================================
local SCROLL_SPEED = 50   -- 基础滚动速度 (像素/秒)

-- ── 纸娃娃 & 装备配置 ──────────────────────────────────────
--- 区域定义（归一化坐标，相对卡车图片 1024×572）
local ZONES = {
    container = { x = 0.379, y = 0.150, w = 0.545, h = 0.518 },
    cabin     = { x = 0.194, y = 0.320, w = 0.106, h = 0.136 },
    gun       = { x = 0.396, y = -0.10,  w = 0.366, h = 0.228 },  -- 可超顶部
    radar     = { x = 0.763, y = -0.10,  w = 0.190, h = 0.226 },  -- 可超顶部
}

--- 纸娃娃图片
local CHIBI_IMAGES = {
    linli  = "image/chibi_linli_20260409053601.png",
    taoxia = "image/chibi_taoxia_20260409053853.png",
}

--- 装备图片（按等级）
local EQUIP_IMAGES = {
    turret = {
        [1] = "image/equip_turret_lv1_20260409053559.png",
        [2] = "image/equip_turret_lv2_20260409053556.png",
        [3] = "image/equip_turret_lv3_20260409053355.png",
    },
    radar = {
        [1] = "image/equip_radar_lv1_20260409053043.png",
        [2] = "image/equip_radar_lv2_20260409053232.png",
        [3] = "image/equip_radar_lv3_20260409053027.png",
    },
}

--- 纸娃娃高度占卡车高度的比例
local CHIBI_H_RATIO = 0.25
--- 纸娃娃移动速度（归一化/秒）
local CHIBI_WALK_SPEED = 0.12
--- 切换区域间隔范围（秒）
local CHIBI_ZONE_SWITCH_MIN = 20
local CHIBI_ZONE_SWITCH_MAX = 40

--- 区域 → 中景图片路径（按地形景观分类）
local MID_IMAGES = {
    urban   = "image/parallax_mid_20260408172203.png",          -- 城郊废墟（原有）
    wild    = "image/parallax_mid_wild_20260409030220.png",     -- 荒野
    canyon  = "image/parallax_mid_canyon_20260409030302.png",    -- 峡谷
    forest  = "image/parallax_mid_forest_20260409030347.png",   -- 枯木林
}

--- 视差层定义
--- speed: 相对滚动速度系数 (0~1, 1=最快/最近)
--- yStart/yEnd: 该层在 widget 高度中的纵向区间 (0=顶, 1=底)
local LAYER_DEFS = {
    -- [1] 天空背景：黄昏天空，不滚动，铺满整个 widget
    {
        image = "image/parallax_sky_20260408180927.png",
        speed = 0.0,
        yStart = 0.0, yEnd = 1.0,
    },
    -- [2] 远景：城市轮廓剪影（v2，内容在图片 29%-100%，密度78.8%）
    {
        image = "image/parallax_far_v2_20260408180625.png",
        speed = 0.05,
        yStart = 0.0, yEnd = 0.85,
    },
    -- [3] 中景：废弃建筑、电线杆（将根据区域动态切换）
    {
        image = "image/parallax_mid_20260408172203.png",
        speed = 0.30,
        yStart = 0.15, yEnd = 0.90,
    },
    -- [4] 地面：公路路面（填满底部）
    {
        image = "image/parallax_ground_20260408172153.png",
        speed = 1.0,
        yStart = 0.68, yEnd = 1.0,
    },
}

local TRUCK_IMAGE = "image/truck_home_clean.png"
local WHEEL_IMAGE = "image/wheel.png"

--- 车轮在卡车图片中的相对位置（比例，相对于卡车图片宽高）
local WHEEL_POSITIONS = {
    { rx = 0.20,  ry = 0.85 },  -- 前轮
    { rx = 0.77,  ry = 0.85 },  -- 后轮
}
--- 车轮直径占卡车高度的比例
local WHEEL_SIZE_RATIO = 0.28

-- ============================================================
-- 时段色调配置 (RGBA)
-- ============================================================
local TIME_TINTS = {
    dawn  = { top = { 255, 140,  60,  70 }, bottom = { 255, 190, 120,  30 } },
    -- day: 无叠加
    dusk  = { top = { 200,  80,  30,  90 }, bottom = { 220, 140,  60,  40 } },
    night = { top = {  15,  15,  50, 180 }, bottom = {  25,  25,  70, 100 } },
}

-- ============================================================
-- 天气粒子配置
-- ============================================================
local RAIN_COUNT = 25
local SNOW_COUNT = 18

-- ============================================================
-- 模块状态
-- ============================================================
local scrollOffset_ = 0

--- 当前环境状态
local currentEnv_ = {
    region    = "wild",
    weather   = "clear",
    timeOfDay = "day",
}

--- 天气粒子数组（预分配，避免每帧 GC）
---@type table[]
local weatherParticles_ = {}
local weatherParticlesInited_ = false

--- 掉落物数据（由外部 setDrops 设置）
---@type table[]
local activeDrops_ = {}

--- 上次渲染的 widget 布局（base pixels，用于 update 中输入检测）
---@type {x:number, y:number, w:number, h:number}|nil
local lastLayout_ = nil

--- 掉落物点击回调
local onDropClick_ = nil   -- function(drop) -> void

--- 拾取反馈队列 { text, x, y, timer, alpha }
---@type table[]
local pickupFeedbacks_ = {}

--- game state 引用（用于读取模块等级）
---@type table|nil
local gameState_ = nil

--- 卡车绘制位置缓存（每帧由 drawTruck 更新，供 chibi/equipment 复用）
local truckBounds_ = { x = 0, y = 0, w = 0, h = 0, bounce = 0 }

--- 纸娃娃角色状态
local chibis_ = {
    {
        id = "linli", image = CHIBI_IMAGES.linli,
        zone = "container",      -- "container" | "cabin"
        x = 0.35, targetX = 0.35, -- 在区域内的归一化 x (0~1)
        facing = 1,              -- 1=右, -1=左
        state = "idle",          -- "idle" | "walk"
        stateTimer = 0,          -- 当前状态剩余时间
        switchTimer = 25,        -- 切换区域倒计时
    },
    {
        id = "taoxia", image = CHIBI_IMAGES.taoxia,
        zone = "container",
        x = 0.65, targetX = 0.65,
        facing = -1,
        state = "idle",
        stateTimer = 1.5,
        switchTimer = 35,
    },
}

--- 自管理的图片缓存（需要 REPEATX 标记，ImageCache 不支持自定义 flags）
local imageCache_ = {}       -- path -> { handle, w, h }
local NVG_IMAGE_REPEATX = 2  -- NanoVG: NVG_IMAGE_REPEATX = 1<<1

--- 加载带水平重复标记的图片
---@param nvg userdata NanoVG context
---@param path string 图片资源路径
---@return table { handle:number, w:number, h:number }
local function loadTiledImage(nvg, path)
    if imageCache_[path] then
        return imageCache_[path]
    end
    local handle = nvgCreateImage(nvg, path, NVG_IMAGE_REPEATX)
    if handle and handle > 0 then
        local w, h = nvgImageSize(nvg, handle)
        imageCache_[path] = { handle = handle, w = w or 1, h = h or 1 }
    else
        imageCache_[path] = { handle = 0, w = 1, h = 1 }
    end
    return imageCache_[path]
end

-- ============================================================
-- 天气粒子初始化/重置
-- ============================================================

--- 初始化雨滴粒子
local function initRainParticles(w, h)
    weatherParticles_ = {}
    for i = 1, RAIN_COUNT do
        weatherParticles_[i] = {
            x = math.random() * w,
            y = math.random() * h,
            speed = 300 + math.random() * 200,   -- 下落速度
            len   = 8 + math.random() * 12,       -- 雨线长度
            alpha = 0.3 + math.random() * 0.4,    -- 透明度
        }
    end
    weatherParticlesInited_ = true
end

--- 初始化雪花粒子
local function initSnowParticles(w, h)
    weatherParticles_ = {}
    for i = 1, SNOW_COUNT do
        weatherParticles_[i] = {
            x = math.random() * w,
            y = math.random() * h,
            speed  = 20 + math.random() * 30,     -- 下落速度
            radius = 1.5 + math.random() * 2.5,   -- 雪花半径
            drift  = (math.random() - 0.5) * 20,  -- 水平漂移
            alpha  = 0.5 + math.random() * 0.4,
            phase  = math.random() * 6.28,         -- 正弦相位
        }
    end
    weatherParticlesInited_ = true
end

--- 重置粒子（天气切换时调用）
local function resetWeatherParticles()
    weatherParticles_ = {}
    weatherParticlesInited_ = false
end

-- ============================================================
-- 掉落物漂移计算（需在 Init/drawDrops 中使用，前置声明）
-- ============================================================

--- 计算掉落物因路面滚动产生的归一化 x 漂移量
---@param drop table
---@param widgetW number widget 宽度（像素）
---@return number driftNorm
local function calcDropDrift(drop, widgetW)
    if widgetW <= 0 then return 0 end
    local lt = drop.lifetime or 0
    -- 地面层向右滚动 → 掉落物也向右漂移
    return lt * RoadLoot.SCROLL_SPEED * RoadLoot.GROUND_SPEED / widgetW
end

-- ============================================================
-- DrivingSceneWidget
-- ============================================================

---@class DrivingSceneWidget : Widget
local DrivingSceneWidget = Widget:Extend("DrivingSceneWidget")

function DrivingSceneWidget:Init(props)
    props.width  = props.width  or "100%"
    props.height = props.height or 160
    -- 掉落物点击不使用 Widget onClick（滚动容器会拦截触摸事件）
    -- 改为在 M.update() 中直接轮询原始输入（见 checkDropInput）
    Widget.Init(self, props)
end

-- ── 主渲染 ──────────────────────────────────────────────────
function DrivingSceneWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    lastLayout_ = { x = l.x, y = l.y, w = l.w, h = l.h }

    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- 1) 天空（LAYER_DEFS[1]）
    self:drawLayer(nvg, l, LAYER_DEFS[1])

    -- 2) 时段色调叠加（天空之上、景物之下）
    self:drawTimeTint(nvg, l)

    -- 3) 远景（LAYER_DEFS[2]）
    self:drawLayer(nvg, l, LAYER_DEFS[2])

    -- 4) 中景（LAYER_DEFS[3]）
    self:drawLayer(nvg, l, LAYER_DEFS[3])

    -- 5) 地面（LAYER_DEFS[4]）
    self:drawLayer(nvg, l, LAYER_DEFS[4])

    -- 6) 天气效果（地面之上、卡车之下）
    self:drawWeather(nvg, l)

    -- 7) 路面掉落物
    self:drawDrops(nvg, l)

    -- 8) 计算卡车位置（供后续所有层使用）
    self:computeTruckBounds(l)

    -- 9) 驾驶舱纸娃娃（卡车后面，只露头）
    self:drawCabinChibis(nvg)

    -- 10) 卡车车身 + 车轮
    self:drawTruck(nvg)

    -- 11) 装备（炮塔/雷达，在车身之上）
    self:drawEquipment(nvg)

    -- 12) 货厢纸娃娃（在卡车上面）
    self:drawContainerChibis(nvg)

    -- 13) 拾取反馈浮字
    self:drawPickupFeedback(nvg, l)

    nvgRestore(nvg)
end

-- ── 单个视差层 ──────────────────────────────────────────────
function DrivingSceneWidget:drawLayer(nvg, l, def)
    local layerY = l.y + l.h * def.yStart
    local layerH = l.h * (def.yEnd - def.yStart)
    if layerH <= 1 then return end

    -- speed=0 的层（如天空）：拉伸填充，不平铺
    if def.speed == 0 then
        local imgHandle = ImageCache.Get(def.image)
        if imgHandle == 0 then return end
        local paint = nvgImagePattern(nvg,
            l.x, layerY,
            l.w, layerH,
            0, imgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, layerY, l.w, layerH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
        return
    end

    -- 滚动层：平铺 + 偏移
    local img = loadTiledImage(nvg, def.image)
    if img.handle == 0 then return end

    -- 按层高缩放图片，计算平铺宽度
    local scale  = layerH / img.h
    local tileW  = img.w * scale

    -- 若瓦片太窄，等比放大减少重复；多出的高度居中裁剪，scissor 自动处理溢出
    local patternH = layerH
    local patternY = layerY
    local minTileW = l.w * 0.65
    if tileW < minTileW then
        scale    = minTileW / img.w
        tileW    = minTileW
        patternH = img.h * scale
        patternY = layerY + (layerH - patternH) * 0.5  -- 垂直居中
    end

    -- 卡车面向左 → 背景向右滚动（offset 取正值）
    local offset = (scrollOffset_ * def.speed) % tileW

    -- nvgImagePattern + REPEATX 自动水平重复
    local paint = nvgImagePattern(nvg,
        l.x + offset, patternY,
        tileW, patternH,
        0, img.handle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, layerY, l.w, layerH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

-- ── 时段色调叠加 ────────────────────────────────────────────
function DrivingSceneWidget:drawTimeTint(nvg, l)
    local tint = TIME_TINTS[currentEnv_.timeOfDay]
    if not tint then return end  -- day 无叠加

    local t = tint.top
    local b = tint.bottom
    local topColor = nvgRGBA(t[1], t[2], t[3], t[4])
    local botColor = nvgRGBA(b[1], b[2], b[3], b[4])
    local grad = nvgLinearGradient(nvg,
        l.x, l.y, l.x, l.y + l.h, topColor, botColor)
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillPaint(nvg, grad)
    nvgFill(nvg)
end

-- ── 天气效果 ────────────────────────────────────────────────
function DrivingSceneWidget:drawWeather(nvg, l)
    local weather = currentEnv_.weather
    if weather == "clear" then return end

    if weather == "cloudy" then
        -- 顶部暗化渐变（阴天效果）
        local grad = nvgLinearGradient(nvg,
            l.x, l.y, l.x, l.y + l.h * 0.4,
            nvgRGBA(40, 40, 50, 100), nvgRGBA(40, 40, 50, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, l.h * 0.4)
        nvgFillPaint(nvg, grad)
        nvgFill(nvg)

    elseif weather == "fog" then
        -- 上层雾带：从透明 → 半透明雾色 → 透明（用两段渐变模拟）
        local fogMid = l.y + l.h * 0.45
        -- 上半段：透明 → 雾色
        local grad1a = nvgLinearGradient(nvg,
            l.x, l.y + l.h * 0.3, l.x, fogMid,
            nvgRGBA(180, 180, 190, 0), nvgRGBA(180, 180, 190, 80))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y + l.h * 0.3, l.w, fogMid - (l.y + l.h * 0.3))
        nvgFillPaint(nvg, grad1a)
        nvgFill(nvg)
        -- 下半段：雾色 → 透明
        local grad1b = nvgLinearGradient(nvg,
            l.x, fogMid, l.x, l.y + l.h * 0.6,
            nvgRGBA(180, 180, 190, 80), nvgRGBA(180, 180, 190, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, fogMid, l.w, l.y + l.h * 0.6 - fogMid)
        nvgFillPaint(nvg, grad1b)
        nvgFill(nvg)
        -- 下层雾（更浓）：透明 → 浓雾色
        local grad2 = nvgLinearGradient(nvg,
            l.x, l.y + l.h * 0.65, l.x, l.y + l.h * 0.85,
            nvgRGBA(160, 165, 170, 0), nvgRGBA(160, 165, 170, 110))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y + l.h * 0.65, l.w, l.h * 0.25)
        nvgFillPaint(nvg, grad2)
        nvgFill(nvg)

    elseif weather == "rain" then
        -- 雨滴斜线粒子
        if not weatherParticlesInited_ then
            initRainParticles(l.w, l.h)
        end
        nvgStrokeWidth(nvg, 1.0)
        for _, p in ipairs(weatherParticles_) do
            nvgBeginPath(nvg)
            local px = l.x + p.x
            local py = l.y + p.y
            nvgMoveTo(nvg, px, py)
            -- 斜线：向右下 (wind=0.3)
            nvgLineTo(nvg, px + p.len * 0.3, py + p.len)
            nvgStrokeColor(nvg, nvgRGBA(180, 200, 220, math.floor(255 * p.alpha)))
            nvgStroke(nvg)
        end

    elseif weather == "snow" then
        -- 雪花圆点粒子
        if not weatherParticlesInited_ then
            initSnowParticles(l.w, l.h)
        end
        for _, p in ipairs(weatherParticles_) do
            nvgBeginPath(nvg)
            nvgCircle(nvg, l.x + p.x, l.y + p.y, p.radius)
            nvgFillColor(nvg, nvgRGBA(230, 235, 240, math.floor(255 * p.alpha)))
            nvgFill(nvg)
        end
    end
end

-- ── 卡车位置计算（提前计算，供 chibi/equipment 复用）────────
function DrivingSceneWidget:computeTruckBounds(l)
    -- 确保图片已加载（GetSize 需要先 Get）
    local imgHandle = ImageCache.Get(TRUCK_IMAGE)
    if imgHandle == 0 then
        truckBounds_.w = 0
        return
    end
    local imgW, imgH = ImageCache.GetSize(TRUCK_IMAGE)
    if imgW == 0 or imgH == 0 then
        truckBounds_.w = 0
        return
    end
    local truckH = l.h * 0.70
    local truckScale = truckH / imgH
    local truckW = imgW * truckScale
    local truckX = l.x + (l.w - truckW) / 2
    local roadSurface = l.y + l.h * 0.88
    local wheelR = truckH * WHEEL_SIZE_RATIO * 0.5
    local wheelCenterY = truckH * 0.85
    local truckY = roadSurface - wheelCenterY - wheelR
    local bounce = math.sin(scrollOffset_ * 0.07) * 1.5
    truckY = truckY + bounce
    truckBounds_.x = truckX
    truckBounds_.y = truckY
    truckBounds_.w = truckW
    truckBounds_.h = truckH
    truckBounds_.bounce = bounce
end

-- ── 卡车 + 车轮 ─────────────────────────────────────────────
function DrivingSceneWidget:drawTruck(nvg)
    local tb = truckBounds_
    if tb.w <= 0 then return end
    local imgHandle = ImageCache.Get(TRUCK_IMAGE)
    if imgHandle == 0 then return end

    local paint = nvgImagePattern(nvg,
        tb.x, tb.y, tb.w, tb.h,
        0, imgHandle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, tb.x, tb.y, tb.w, tb.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)

    self:drawWheels(nvg, tb.x, tb.y, tb.w, tb.h)
end

-- ── 车轮旋转 ────────────────────────────────────────────────
function DrivingSceneWidget:drawWheels(nvg, truckX, truckY, truckW, truckH)
    local wheelHandle = ImageCache.Get(WHEEL_IMAGE)
    if wheelHandle == 0 then return end
    local imgW, imgH = ImageCache.GetSize(WHEEL_IMAGE)
    if imgW == 0 or imgH == 0 then return end

    local wheelDiam = truckH * WHEEL_SIZE_RATIO
    local wheelR    = wheelDiam / 2

    local aspect = imgW / imgH
    local drawW = wheelDiam * aspect
    local drawH = wheelDiam

    local angle = -(scrollOffset_ * 1.0) / (wheelR * 0.8)

    for _, wp in ipairs(WHEEL_POSITIONS) do
        local cx = truckX + truckW * wp.rx
        local cy = truckY + truckH * wp.ry

        nvgSave(nvg)
        nvgTranslate(nvg, cx, cy)
        nvgRotate(nvg, angle)

        local paint = nvgImagePattern(nvg,
            -drawW / 2, -drawH / 2,
            drawW, drawH,
            0, wheelHandle, 1.0)
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, wheelR)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)

        nvgRestore(nvg)
    end
end

-- ── 路面掉落物 ──────────────────────────────────────────────
function DrivingSceneWidget:drawDrops(nvg, l)
    if #activeDrops_ == 0 then return end
    local iconSize = RoadLoot.ICON_SIZE

    for _, drop in ipairs(activeDrops_) do
        if drop.alive then
            -- 计算漂移后的归一化 x
            local driftNorm = calcDropDrift(drop, l.w)
            local renderXNorm = drop.xNorm + driftNorm

            -- 超出右边界→标记过期并跳过
            if renderXNorm > 1.1 then
                drop.alive = false
                goto continue
            end
            -- 还没进入左边界也跳过
            if renderXNorm < -0.1 then goto continue end

            local imgHandle = ImageCache.Get(drop.icon)
            if imgHandle ~= 0 then
                local dx = l.x + renderXNorm * l.w - iconSize / 2
                local dy = l.y + drop.yNorm * l.h - iconSize / 2

                -- 上下微浮动（呼吸感）
                local bob = math.sin((drop.lifetime or 0) * 2.5) * 2
                dy = dy + bob

                -- 淡入（前 0.5s）/ 淡出（接近右边缘时渐隐）
                local alpha = 1.0
                local lt = drop.lifetime or 0
                if lt < 0.5 then
                    alpha = lt / 0.5
                elseif renderXNorm > 0.85 then
                    -- 从 0.85 到 1.1 渐隐
                    alpha = math.max(0, 1.0 - (renderXNorm - 0.85) / 0.25)
                end

                local paint = nvgImagePattern(nvg,
                    dx, dy, iconSize, iconSize,
                    0, imgHandle, alpha)
                nvgBeginPath(nvg)
                nvgRect(nvg, dx, dy, iconSize, iconSize)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)

                -- 微光圈效果
                if alpha > 0.3 then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, dx + iconSize / 2, dy + iconSize / 2, iconSize * 0.6)
                    nvgFillColor(nvg, nvgRGBA(255, 220, 120, math.floor(30 * alpha)))
                    nvgFill(nvg)
                end
            end

            ::continue::
        end
    end
end

-- ── 拾取反馈浮字 ────────────────────────────────────────────
function DrivingSceneWidget:drawPickupFeedback(nvg, l)
    if #pickupFeedbacks_ == 0 then return end

    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, fb in ipairs(pickupFeedbacks_) do
        local alpha = math.max(0, fb.alpha)
        local px = l.x + fb.x * l.w
        local py = l.y + fb.y * l.h - fb.timer * 30  -- 向上飘

        -- 文字阴影
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgText(nvg, px + 1, py + 1, fb.text)

        -- 文字本体（金色=货币/绿色=货物/红色=受阻）
        local r, g, b = 255, 220, 80
        if fb.reward_type == "cargo" then
            r, g, b = 120, 220, 140
        elseif fb.reward_type == "blocked" then
            r, g, b = 255, 90, 90
        end
        nvgFillColor(nvg, nvgRGBA(r, g, b, math.floor(255 * alpha)))
        nvgText(nvg, px, py, fb.text)
    end
end

-- ── 纸娃娃 AI 更新 ─────────────────────────────────────────
local function updateChibis(dt)
    for _, c in ipairs(chibis_) do
        -- 区域切换倒计时
        c.switchTimer = c.switchTimer - dt
        if c.switchTimer <= 0 then
            c.zone = (c.zone == "container") and "cabin" or "container"
            c.switchTimer = CHIBI_ZONE_SWITCH_MIN
                + math.random() * (CHIBI_ZONE_SWITCH_MAX - CHIBI_ZONE_SWITCH_MIN)
            c.x = 0.5
            c.targetX = 0.5
            c.state = "idle"
            c.stateTimer = 1 + math.random() * 2
        end

        -- 状态机：idle ↔ walk
        if c.state == "idle" then
            c.stateTimer = c.stateTimer - dt
            if c.stateTimer <= 0 then
                if c.zone == "container" then
                    c.targetX = 0.08 + math.random() * 0.84
                else
                    c.targetX = 0.2 + math.random() * 0.6
                end
                c.state = "walk"
                c.facing = (c.targetX > c.x) and 1 or -1
            end
        elseif c.state == "walk" then
            local spd = CHIBI_WALK_SPEED
            if c.zone == "cabin" then spd = spd * 0.5 end
            local dx = c.targetX - c.x
            if math.abs(dx) < spd * dt then
                c.x = c.targetX
                c.state = "idle"
                c.stateTimer = 2 + math.random() * 4
            else
                c.x = c.x + (dx > 0 and 1 or -1) * spd * dt
                c.facing = (dx > 0) and 1 or -1
            end
        end
    end
end

-- ── 绘制驾驶舱纸娃娃（在卡车后面，只露头）─────────────────
function DrivingSceneWidget:drawCabinChibis(nvg)
    local tb = truckBounds_
    if tb.w <= 0 then return end
    local zone = ZONES.cabin

    for _, c in ipairs(chibis_) do
        if c.zone == "cabin" then
            local imgHandle = ImageCache.Get(c.image)
            if imgHandle ~= 0 then
                local chibiH = tb.h * CHIBI_H_RATIO * 0.8
                local chibiW = chibiH

                local zoneX = tb.x + zone.x * tb.w
                local zoneY = tb.y + zone.y * tb.h
                local zoneW = zone.w * tb.w

                local drawX = zoneX + c.x * zoneW - chibiW / 2
                -- 头部对齐窗口中心（图片约 30% 处是头部）
                local drawY = zoneY - chibiH * 0.25

                nvgSave(nvg)
                local cx = drawX + chibiW / 2
                nvgTranslate(nvg, cx, 0)
                nvgScale(nvg, c.facing, 1)
                nvgTranslate(nvg, -cx, 0)

                local paint = nvgImagePattern(nvg,
                    drawX, drawY, chibiW, chibiH,
                    0, imgHandle, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, chibiW, chibiH)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)

                nvgRestore(nvg)
            end
        end
    end
end

-- ── 绘制货厢纸娃娃（在卡车上面）─────────────────────────────
function DrivingSceneWidget:drawContainerChibis(nvg)
    local tb = truckBounds_
    if tb.w <= 0 then return end
    local zone = ZONES.container

    for _, c in ipairs(chibis_) do
        if c.zone == "container" then
            local imgHandle = ImageCache.Get(c.image)
            if imgHandle ~= 0 then
                local chibiH = tb.h * CHIBI_H_RATIO
                local chibiW = chibiH

                local zoneX = tb.x + zone.x * tb.w
                local zoneY = tb.y + zone.y * tb.h
                local zoneW = zone.w * tb.w
                local zoneH = zone.h * tb.h

                local drawX = zoneX + c.x * zoneW - chibiW / 2
                local drawY = zoneY + zoneH - chibiH  -- 站在区域底部

                nvgSave(nvg)
                local cx = drawX + chibiW / 2
                nvgTranslate(nvg, cx, 0)
                nvgScale(nvg, c.facing, 1)
                nvgTranslate(nvg, -cx, 0)

                local paint = nvgImagePattern(nvg,
                    drawX, drawY, chibiW, chibiH,
                    0, imgHandle, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, drawX, drawY, chibiW, chibiH)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)

                nvgRestore(nvg)
            end
        end
    end
end

-- ── 绘制装备（炮塔/雷达）───────────────────────────────────
function DrivingSceneWidget:drawEquipment(nvg)
    if not gameState_ then return end
    local tb = truckBounds_
    if tb.w <= 0 then return end

    local function drawEquipAt(moduleId, zoneKey, imageTable)
        local lv = Modules.get_level(gameState_, moduleId)
        if lv <= 0 then return end
        local imgPath = imageTable[lv]
        if not imgPath then return end
        local imgHandle = ImageCache.Get(imgPath)
        if imgHandle == 0 then return end

        local zone = ZONES[zoneKey]
        local drawX = tb.x + zone.x * tb.w
        local drawY = tb.y + zone.y * tb.h
        local drawW = zone.w * tb.w
        local drawH = zone.h * tb.h

        local paint = nvgImagePattern(nvg,
            drawX, drawY, drawW, drawH,
            0, imgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, drawX, drawY, drawW, drawH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
    end

    drawEquipAt("turret", "gun",   EQUIP_IMAGES.turret)
    drawEquipAt("radar",  "radar", EQUIP_IMAGES.radar)
end

-- ============================================================
-- 天气粒子位置更新（每帧调用）
-- ============================================================
local function updateWeatherParticles(dt, w, h)
    local weather = currentEnv_.weather
    if weather == "rain" then
        for _, p in ipairs(weatherParticles_) do
            p.y = p.y + p.speed * dt
            p.x = p.x + p.speed * 0.3 * dt  -- 风向偏移
            -- 超出底部则循环到顶部
            if p.y > h then
                p.y = -p.len
                p.x = math.random() * w
            end
            if p.x > w then
                p.x = p.x - w
            end
        end
    elseif weather == "snow" then
        for _, p in ipairs(weatherParticles_) do
            p.y = p.y + p.speed * dt
            p.phase = p.phase + dt * 1.5
            p.x = p.x + (p.drift + math.sin(p.phase) * 10) * dt
            if p.y > h then
                p.y = -p.radius * 2
                p.x = math.random() * w
            end
            if p.x > w then p.x = p.x - w end
            if p.x < 0 then p.x = p.x + w end
        end
    end
end

-- ============================================================
-- 掉落物输入检测（绕过 UI 框架，直接轮询原始输入）
-- ============================================================

--- 计算 UI 缩放因子（匹配 UI.Scale.DPR_DENSITY_ADAPTIVE）
---@return number scale 物理像素 → base pixels 的换算因子
local function getUIScale()
    local dpr = graphics:GetDPR()
    local shortSide = math.min(graphics:GetWidth(), graphics:GetHeight()) / dpr
    local PC_REF = 720
    local densityFactor = math.sqrt(shortSide / PC_REF)
    densityFactor = math.max(0.625, math.min(densityFactor, 1.0))
    return dpr * densityFactor
end

--- 每帧检测触摸/鼠标点击是否命中掉落物
--- 不依赖 Widget onClick（滚动容器会在手机上拦截触摸事件）
local function checkDropInput()
    if not onDropClick_ then return end
    if #activeDrops_ == 0 then return end
    if not lastLayout_ then return end

    -- 检测本帧是否有点击/触摸
    local pressed = input:GetMouseButtonPress(MOUSEB_LEFT)
    if not pressed then return end

    -- 获取物理像素位置
    local mousePos = input:GetMousePosition()
    local physX, physY = mousePos.x, mousePos.y

    -- 物理像素 → base pixels（与 Widget 布局同一坐标系）
    local scale = getUIScale()
    local baseX = physX / scale
    local baseY = physY / scale

    -- 检查是否在 widget 区域内
    local l = lastLayout_
    if baseX < l.x or baseX > l.x + l.w then return end
    if baseY < l.y or baseY > l.y + l.h then return end

    -- 转为 widget 内归一化坐标
    local normX = (baseX - l.x) / l.w
    local normY = (baseY - l.y) / l.h

    -- 命中半径（base pixels），放大 1.5x 便于触屏操作
    local hitPx = RoadLoot.ICON_SIZE * 1.5

    for _, drop in ipairs(activeDrops_) do
        if drop.alive then
            local driftNorm = calcDropDrift(drop, l.w)
            local renderXNorm = drop.xNorm + driftNorm
            local ddxPx = (normX - renderXNorm) * l.w
            local ddyPx = (normY - drop.yNorm) * l.h
            if math.abs(ddxPx) < hitPx and math.abs(ddyPx) < hitPx then
                drop._renderXNorm = renderXNorm
                onDropClick_(drop)
                return
            end
        end
    end
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 每帧更新滚动 + 天气粒子 + 输入检测 + 拾取反馈（由 screen_home.update 调用）
---@param dt number 帧间隔
function M.update(dt)
    scrollOffset_ = scrollOffset_ + dt * SCROLL_SPEED
    -- 更新纸娃娃 AI
    updateChibis(dt)
    -- 更新天气粒子位置（使用上次渲染的 widget 尺寸估算）
    if weatherParticlesInited_ and #weatherParticles_ > 0 then
        updateWeatherParticles(dt, 400, 220)  -- 近似尺寸
    end
    -- 检测掉落物点击（绕过 UI 框架，直接读取原始输入）
    checkDropInput()
    -- 更新拾取反馈浮字（1.2s 后淡出消失）
    local FEEDBACK_DURATION = 1.2
    local expired = {}
    for i, fb in ipairs(pickupFeedbacks_) do
        fb.timer = fb.timer + dt
        fb.alpha = 1.0 - fb.timer / FEEDBACK_DURATION
        if fb.timer >= FEEDBACK_DURATION then
            table.insert(expired, i)
        end
    end
    for j = #expired, 1, -1 do
        table.remove(pickupFeedbacks_, expired[j])
    end
end

--- 设置环境（segment 切换时由 screen_home 调用）
---@param env table { region:string, weather:string, timeOfDay:string }
function M.setEnvironment(env)
    if not env then return end

    local changed = false

    -- 更新区域 → 替换中景图片
    if env.region and env.region ~= currentEnv_.region then
        currentEnv_.region = env.region
        local newMid = MID_IMAGES[env.region]
        if newMid then
            -- 替换 LAYER_DEFS[3] 的图片路径
            LAYER_DEFS[3].image = newMid
            -- 清除该路径的 tiled image 缓存，让下帧重新加载
            -- （不需要删除旧缓存，imageCache_ 保留多份无害）
        end
        changed = true
    end

    -- 更新天气
    if env.weather and env.weather ~= currentEnv_.weather then
        currentEnv_.weather = env.weather
        resetWeatherParticles()
        changed = true
    end

    -- 更新时段
    if env.timeOfDay then
        currentEnv_.timeOfDay = env.timeOfDay
    end

    if changed then
        print(string.format("[DrivingScene] ENV → region=%s weather=%s time=%s",
            currentEnv_.region, currentEnv_.weather, currentEnv_.timeOfDay))
    end
end

--- 创建行驶场景 Widget
---@param props? table 可选 Widget 属性 (height, backgroundColor 等)
---@return DrivingSceneWidget
function M.createWidget(props)
    return DrivingSceneWidget(props or {})
end

--- 设置当前可见的掉落物列表（由 screen_home 每帧传入）
---@param drops table[]
function M.setDrops(drops)
    activeDrops_ = drops or {}
end

--- 设置掉落物点击回调
---@param callback function(drop) 点击掉落物时调用
function M.setDropCallback(callback)
    onDropClick_ = callback
end

--- 添加拾取反馈浮字
---@param feedback table { reward_text, reward_type, x, y }
function M.addFeedback(feedback)
    if not feedback then return end
    table.insert(pickupFeedbacks_, {
        text        = feedback.reward_text or "",
        reward_type = feedback.reward_type or "credits",
        x           = feedback.x or 0.5,
        y           = feedback.y or 0.8,
        timer       = 0,
        alpha       = 1.0,
    })
end

--- 设置游戏状态引用（用于读取模块等级等）
---@param state table
function M.setState(state)
    gameState_ = state
end

--- 重置滚动位置（出发时调用）
function M.reset()
    scrollOffset_ = 0
    resetWeatherParticles()
    activeDrops_ = {}
    pickupFeedbacks_ = {}
    onDropClick_ = nil
    lastLayout_ = nil
    -- 重置纸娃娃状态
    chibis_[1].zone = "container"
    chibis_[1].x = 0.35
    chibis_[1].targetX = 0.35
    chibis_[1].state = "idle"
    chibis_[1].stateTimer = 0
    chibis_[1].switchTimer = 25
    chibis_[2].zone = "container"
    chibis_[2].x = 0.65
    chibis_[2].targetX = 0.65
    chibis_[2].state = "idle"
    chibis_[2].stateTimer = 1.5
    chibis_[2].switchTimer = 35
end

return M

--- 通用纸娃娃场景组件（原 driving_scene.lua）
--- 支持多种场景模式：行驶（driving）、探索（explore）等
--- 提供视差滚动背景 + 纸娃娃角色 + 战斗渲染器插槽
---
--- 用法：
---   local ChibiScene = require("travel/chibi_scene")
---   ChibiScene.setMode("driving")  -- 或 "explore"
---   ChibiScene.createWidget({ height = 220 })
---   ChibiScene.update(dt)

local Widget       = require("urhox-libs/UI/Core/Widget")
local ImageCache   = require("urhox-libs/UI/Core/ImageCache")
local RoadLoot     = require("travel/road_loot")
local Modules      = require("truck/modules")
local ChibiRenderer = require("travel/chibi_renderer")

local M = {}

-- ============================================================
-- 配置
-- ============================================================
local SCROLL_SPEED = 50

-- ── 行驶模式 zone 定义（归一化坐标，相对卡车图片 1024×572）──
local DRIVING_ZONES = {
    container = { x = 0.379, y = 0.150, w = 0.545, h = 0.518 },
    cabin     = { x = 0.193, y = 0.294, w = 0.106, h = 0.376 },
    table     = { x = 0.439, y = 0.358, w = 0.094, h = 0.311 },
    stove     = { x = 0.594, y = 0.406, w = 0.106, h = 0.264 },
    bed       = { x = 0.714, y = 0.406, w = 0.191, h = 0.177 },
    gun       = { x = 0.396, y = -0.10,  w = 0.366, h = 0.228 },
    radar     = { x = 0.763, y = -0.10,  w = 0.190, h = 0.226 },
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

-- ── 模式配置 ────────────────────────────────────────────────
local MODES = {
    driving = {
        zones = DRIVING_ZONES,
        hasVehicle = true,
        outsideScale = 1.2,
        scrollSpeed = SCROLL_SPEED,
        zoneMap = {
            ground_left   = "cabin",
            ground_center = "container",
            ground_right  = "table",
        },
    },
    -- explore 模式在 Step 4 (explore_mode.lua) 注入
}

--- 区域 → 中景图片路径
local MID_IMAGES = {
    urban   = "image/parallax_mid_20260408172203.png",
    wild    = "image/parallax_mid_wild_20260409030220.png",
    canyon  = "image/parallax_mid_canyon_20260409030302.png",
    forest  = "image/parallax_mid_forest_20260409030347.png",
}

--- 聚落停泊场景图
local SETTLEMENT_SCENE_IMAGES = {
    greenhouse         = "image/scene_greenhouse_20260411034417.png",
    greenhouse_farm    = "image/scene_greenhouse_farm_20260411034418.png",
    tower              = "image/scene_tower_20260411034419.png",
    dome_outpost       = "image/scene_dome_outpost_20260411034417.png",
    ruins_camp         = "image/scene_ruins_camp_20260411034423.png",
    metro_camp         = "image/scene_metro_camp_20260411034536.png",
    bell_tower         = "image/scene_bell_tower_20260411034537.png",
    old_church         = "image/scene_old_church_20260411034542.png",
    underground_market = "image/scene_underground_market_20260411034530.png",
}

local settlementSceneImage_ = nil

--- 视差层定义
local LAYER_DEFS = {
    { image = "image/parallax_sky_20260408180927.png",     speed = 0.0,  yStart = 0.0, yEnd = 1.0  },
    { image = "image/parallax_far_v2_20260408180625.png",  speed = 0.05, yStart = 0.0, yEnd = 0.85 },
    { image = "image/parallax_mid_20260408172203.png",     speed = 0.30, yStart = 0.15, yEnd = 0.90 },
    { image = "image/parallax_ground_20260408172153.png",  speed = 1.0,  yStart = 0.68, yEnd = 1.0  },
}

local TRUCK_IMAGE = "image/truck_home_clean.png"
local WHEEL_IMAGE = "image/wheel.png"

local WHEEL_POSITIONS = {
    { rx = 0.20,  ry = 0.85 },
    { rx = 0.77,  ry = 0.85 },
}
local WHEEL_SIZE_RATIO = 0.28

-- ============================================================
-- 时段色调
-- ============================================================
local TIME_TINTS = {
    dawn  = { top = { 255, 140,  60,  70 }, bottom = { 255, 190, 120,  30 } },
    dusk  = { top = { 200,  80,  30,  90 }, bottom = { 220, 140,  60,  40 } },
    night = { top = {  15,  15,  50, 180 }, bottom = {  25,  25,  70, 100 } },
}

-- ============================================================
-- 天气粒子
-- ============================================================
local RAIN_COUNT = 25
local SNOW_COUNT = 18

-- ============================================================
-- 模块状态
-- ============================================================
local scrollOffset_ = 0
local combatRenderer_ = nil
local currentMode_ = MODES.driving    -- 当前模式配置
local currentModeName_ = "driving"

local currentEnv_ = {
    region    = "wild",
    weather   = "clear",
    timeOfDay = "day",
}

local weatherParticles_ = {}
local weatherParticlesInited_ = false
local activeDrops_ = {}
---@type {x:number, y:number, w:number, h:number}|nil
local lastLayout_ = nil
local onDropClick_ = nil
local pickupFeedbacks_ = {}
---@type table|nil
local gameState_ = nil

--- 探索物品列表（箱子、感叹号标记等可视化元素）
--- { { id=string, image=string, xNorm=number, alive=boolean, looted=boolean, bobPhase=number } }
local exploreItems_ = {}

--- 场景 bounds 缓存（统一接口，行驶模式 = truckBounds，探索模式 = groundBounds）
local sceneBounds_ = { x = 0, y = 0, w = 0, h = 0, bounce = 0 }

local isDriving_ = true

--- 纸娃娃角色状态
local chibis_ = {
    ChibiRenderer.createChibi("linli",  "cabin",     1),
    ChibiRenderer.createChibi("taoxia", "table",    -1),
}
-- 初始化延迟
chibis_[1].stateTimer = 0
chibis_[1].switchTimer = 25
chibis_[2].stateTimer = 1.5
chibis_[2].switchTimer = 35

--- 点击回调和帧级状态
local onChibiClick_ = nil
local clickConsumed_ = false
local framePressed_  = false
local frameMX_       = 0
local frameMY_       = 0

-- ============================================================
-- 图片缓存（带 REPEATX）
-- ============================================================
local imageCache_ = {}
local NVG_IMAGE_REPEATX = 2

local function loadTiledImage(nvg, path)
    if imageCache_[path] then return imageCache_[path] end
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
-- 天气粒子
-- ============================================================
local function initRainParticles(w, h)
    weatherParticles_ = {}
    for i = 1, RAIN_COUNT do
        weatherParticles_[i] = {
            x = math.random() * w, y = math.random() * h,
            speed = 300 + math.random() * 200, len = 8 + math.random() * 12,
            alpha = 0.3 + math.random() * 0.4,
        }
    end
    weatherParticlesInited_ = true
end

local function initSnowParticles(w, h)
    weatherParticles_ = {}
    for i = 1, SNOW_COUNT do
        weatherParticles_[i] = {
            x = math.random() * w, y = math.random() * h,
            speed = 20 + math.random() * 30, radius = 1.5 + math.random() * 2.5,
            drift = (math.random() - 0.5) * 20, alpha = 0.5 + math.random() * 0.4,
            phase = math.random() * 6.28,
        }
    end
    weatherParticlesInited_ = true
end

local function resetWeatherParticles()
    weatherParticles_ = {}
    weatherParticlesInited_ = false
end

-- ============================================================
-- 掉落物漂移
-- ============================================================
local function calcDropDrift(drop, widgetW)
    if widgetW <= 0 then return 0 end
    if not drop._spawnScroll then drop._spawnScroll = scrollOffset_ end
    local pixelDrift = (scrollOffset_ - drop._spawnScroll) * RoadLoot.GROUND_SPEED
    return pixelDrift / widgetW
end

-- ============================================================
-- Widget
-- ============================================================
---@class ChibiSceneWidget : Widget
local ChibiSceneWidget = Widget:Extend("ChibiSceneWidget")

function ChibiSceneWidget:Init(props)
    props.width  = props.width  or "100%"
    props.height = props.height or 160
    Widget.Init(self, props)
end

-- ── 主渲染 ──────────────────────────────────────────────────
function ChibiSceneWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    lastLayout_ = { x = l.x, y = l.y, w = l.w, h = l.h }

    nvgSave(nvg)
    nvgIntersectScissor(nvg, l.x, l.y, l.w, l.h)

    -- 战斗抖动
    if combatRenderer_ then
        local sx, sy = combatRenderer_.getScreenShake()
        if sx ~= 0 or sy ~= 0 then nvgTranslate(nvg, sx, sy) end
    end

    -- 背景层
    if settlementSceneImage_ then
        self:drawSettlementScene(nvg, l)
    else
        self:drawLayer(nvg, l, LAYER_DEFS[1])
        self:drawTimeTint(nvg, l)
        self:drawLayer(nvg, l, LAYER_DEFS[2])
        self:drawLayer(nvg, l, LAYER_DEFS[3])
        self:drawLayer(nvg, l, LAYER_DEFS[4])
    end

    -- 掉落物（行驶模式）
    if currentMode_.hasVehicle then
        self:drawDrops(nvg, l)
    end

    -- 场景主体分支
    if currentMode_.hasVehicle then
        -- ── 行驶模式：卡车 + 车上角色 ──
        self:computeTruckBounds(l)
        self:drawCabinChibis(nvg)
        self:drawTruck(nvg)
        self:drawEquipment(nvg)
    else
        -- ── 非车辆模式（探索等）：计算地面 bounds ──
        self:computeGroundBounds(l)
    end

    -- 战斗渲染层
    if combatRenderer_ then
        combatRenderer_.render(nvg, l, sceneBounds_)
    end

    -- 探索物品（箱子等，绘制在角色下方）
    if not currentMode_.hasVehicle and #exploreItems_ > 0 then
        self:drawExploreItems(nvg, l)
    end

    -- 角色绘制
    if currentMode_.hasVehicle then
        self:drawContainerChibis(nvg)
        self:drawOutsideChibis(nvg, l)
    else
        self:drawGroundChibis(nvg, l)
    end

    -- 天气 + 浮字
    self:drawWeather(nvg, l)
    self:drawPickupFeedback(nvg, l)

    nvgRestore(nvg)
end

-- ── 聚落静态场景 ────────────────────────────────────────────
function ChibiSceneWidget:drawSettlementScene(nvg, l)
    local imgHandle = ImageCache.Get(settlementSceneImage_)
    if imgHandle == 0 then return end
    local paint = nvgImagePattern(nvg, l.x, l.y, l.w, l.h, 0, imgHandle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
    self:drawTimeTint(nvg, l)
end

-- ── 视差层 ──────────────────────────────────────────────────
function ChibiSceneWidget:drawLayer(nvg, l, def)
    local layerY = l.y + l.h * def.yStart
    local layerH = l.h * (def.yEnd - def.yStart)
    if layerH <= 1 then return end

    if def.speed == 0 then
        local imgHandle = ImageCache.Get(def.image)
        if imgHandle == 0 then return end
        local paint = nvgImagePattern(nvg, l.x, layerY, l.w, layerH, 0, imgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, layerY, l.w, layerH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
        return
    end

    local img = loadTiledImage(nvg, def.image)
    if img.handle == 0 then return end

    local scale  = layerH / img.h
    local tileW  = img.w * scale
    local patternH = layerH
    local patternY = layerY
    local minTileW = l.w * 0.65
    if tileW < minTileW then
        scale    = minTileW / img.w
        tileW    = minTileW
        patternH = img.h * scale
        patternY = layerY + (layerH - patternH) * 0.5
    end

    local offset = (scrollOffset_ * def.speed) % tileW
    local paint = nvgImagePattern(nvg, l.x + offset, patternY, tileW, patternH, 0, img.handle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, layerY, l.w, layerH)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

-- ── 时段色调 ────────────────────────────────────────────────
function ChibiSceneWidget:drawTimeTint(nvg, l)
    local tint = TIME_TINTS[currentEnv_.timeOfDay]
    if not tint then return end
    local t = tint.top
    local b = tint.bottom
    local grad = nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + l.h,
        nvgRGBA(t[1], t[2], t[3], t[4]), nvgRGBA(b[1], b[2], b[3], b[4]))
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillPaint(nvg, grad)
    nvgFill(nvg)
end

-- ── 天气 ────────────────────────────────────────────────────
function ChibiSceneWidget:drawWeather(nvg, l)
    local weather = currentEnv_.weather
    if weather == "clear" then return end

    if weather == "cloudy" then
        local grad = nvgLinearGradient(nvg, l.x, l.y, l.x, l.y + l.h * 0.4,
            nvgRGBA(40, 40, 50, 100), nvgRGBA(40, 40, 50, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, l.h * 0.4)
        nvgFillPaint(nvg, grad)
        nvgFill(nvg)
    elseif weather == "fog" then
        local fogMid = l.y + l.h * 0.45
        local grad1a = nvgLinearGradient(nvg, l.x, l.y + l.h * 0.3, l.x, fogMid,
            nvgRGBA(180, 180, 190, 0), nvgRGBA(180, 180, 190, 80))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y + l.h * 0.3, l.w, fogMid - (l.y + l.h * 0.3))
        nvgFillPaint(nvg, grad1a)
        nvgFill(nvg)
        local grad1b = nvgLinearGradient(nvg, l.x, fogMid, l.x, l.y + l.h * 0.6,
            nvgRGBA(180, 180, 190, 80), nvgRGBA(180, 180, 190, 0))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, fogMid, l.w, l.y + l.h * 0.6 - fogMid)
        nvgFillPaint(nvg, grad1b)
        nvgFill(nvg)
        local grad2 = nvgLinearGradient(nvg, l.x, l.y + l.h * 0.65, l.x, l.y + l.h * 0.85,
            nvgRGBA(160, 165, 170, 0), nvgRGBA(160, 165, 170, 110))
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y + l.h * 0.65, l.w, l.h * 0.25)
        nvgFillPaint(nvg, grad2)
        nvgFill(nvg)
    elseif weather == "rain" then
        if not weatherParticlesInited_ then initRainParticles(l.w, l.h) end
        nvgStrokeWidth(nvg, 1.0)
        for _, p in ipairs(weatherParticles_) do
            nvgBeginPath(nvg)
            local px = l.x + p.x
            local py = l.y + p.y
            nvgMoveTo(nvg, px, py)
            nvgLineTo(nvg, px + p.len * 0.3, py + p.len)
            nvgStrokeColor(nvg, nvgRGBA(180, 200, 220, math.floor(255 * p.alpha)))
            nvgStroke(nvg)
        end
    elseif weather == "snow" then
        if not weatherParticlesInited_ then initSnowParticles(l.w, l.h) end
        for _, p in ipairs(weatherParticles_) do
            nvgBeginPath(nvg)
            nvgCircle(nvg, l.x + p.x, l.y + p.y, p.radius)
            nvgFillColor(nvg, nvgRGBA(230, 235, 240, math.floor(255 * p.alpha)))
            nvgFill(nvg)
        end
    end
end

-- ============================================================
-- 卡车（行驶模式专用）
-- ============================================================

function ChibiSceneWidget:computeTruckBounds(l)
    local imgHandle = ImageCache.Get(TRUCK_IMAGE)
    if imgHandle == 0 then sceneBounds_.w = 0; return end
    local imgW, imgH = ImageCache.GetSize(TRUCK_IMAGE)
    if imgW == 0 or imgH == 0 then sceneBounds_.w = 0; return end

    local truckH = l.h * 0.70
    local truckScale = truckH / imgH
    local truckW = imgW * truckScale
    local xOffset = 0
    if combatRenderer_ then xOffset = combatRenderer_.getTruckOffset() end
    local truckX = l.x + (l.w - truckW) / 2 + xOffset * l.w
    local roadSurface = l.y + l.h * 0.88
    local wheelR = truckH * WHEEL_SIZE_RATIO * 0.5
    local wheelCenterY = truckH * 0.85
    local truckY = roadSurface - wheelCenterY - wheelR
    local bounce = math.sin(scrollOffset_ * 0.07) * 1.5
    truckY = truckY + bounce

    sceneBounds_.x = truckX
    sceneBounds_.y = truckY
    sceneBounds_.w = truckW
    sceneBounds_.h = truckH
    sceneBounds_.bounce = bounce
end

function ChibiSceneWidget:drawTruck(nvg)
    local tb = sceneBounds_
    if tb.w <= 0 then return end
    local truckImg = TRUCK_IMAGE
    if combatRenderer_ and combatRenderer_.getTruckImage then
        truckImg = combatRenderer_.getTruckImage() or TRUCK_IMAGE
    end
    local imgHandle = ImageCache.Get(truckImg)
    if imgHandle == 0 then return end

    local paint = nvgImagePattern(nvg, tb.x, tb.y, tb.w, tb.h, 0, imgHandle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, tb.x, tb.y, tb.w, tb.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)

    -- 受击闪白
    if combatRenderer_ and combatRenderer_.getTruckFlash then
        local flashA = combatRenderer_.getTruckFlash()
        if flashA > 0 then
            nvgSave(nvg)
            nvgGlobalCompositeBlendFunc(nvg, NVG_ONE, NVG_ONE)
            local fp = nvgImagePattern(nvg, tb.x, tb.y, tb.w, tb.h, 0, imgHandle, flashA)
            nvgBeginPath(nvg)
            nvgRect(nvg, tb.x, tb.y, tb.w, tb.h)
            nvgFillPaint(nvg, fp)
            nvgFill(nvg)
            nvgRestore(nvg)
        end
    end

    self:drawWheels(nvg, tb.x, tb.y, tb.w, tb.h)
end

function ChibiSceneWidget:drawWheels(nvg, truckX, truckY, truckW, truckH)
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
        local paint = nvgImagePattern(nvg, -drawW / 2, -drawH / 2, drawW, drawH, 0, wheelHandle, 1.0)
        nvgBeginPath(nvg)
        nvgCircle(nvg, 0, 0, wheelR)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
        nvgRestore(nvg)
    end
end

function ChibiSceneWidget:drawEquipment(nvg)
    if not gameState_ then return end
    local tb = sceneBounds_
    if tb.w <= 0 then return end

    local function drawEquipAt(moduleId, zoneKey, imageTable)
        local lv = Modules.get_level(gameState_, moduleId)
        if lv <= 0 then return end
        local imgPath = imageTable[lv]
        if not imgPath then return end
        local imgHandle = ImageCache.Get(imgPath)
        if imgHandle == 0 then return end
        local zone = DRIVING_ZONES[zoneKey]
        local drawX = tb.x + zone.x * tb.w
        local drawY = tb.y + zone.y * tb.h
        local drawW = zone.w * tb.w
        local drawH = zone.h * tb.h
        local paint = nvgImagePattern(nvg, drawX, drawY, drawW, drawH, 0, imgHandle, 1.0)
        nvgBeginPath(nvg)
        nvgRect(nvg, drawX, drawY, drawW, drawH)
        nvgFillPaint(nvg, paint)
        nvgFill(nvg)
    end

    drawEquipAt("turret", "gun",   EQUIP_IMAGES.turret)
    drawEquipAt("radar",  "radar", EQUIP_IMAGES.radar)
end

-- ============================================================
-- 掉落物
-- ============================================================
function ChibiSceneWidget:drawDrops(nvg, l)
    if #activeDrops_ == 0 then return end
    local iconSize = RoadLoot.ICON_SIZE

    for _, drop in ipairs(activeDrops_) do
        if drop.alive then
            local driftNorm = calcDropDrift(drop, l.w)
            local renderXNorm = drop.xNorm + driftNorm
            if renderXNorm > 1.1 then drop.alive = false; goto continue end
            if renderXNorm < -0.1 then goto continue end

            local imgHandle = ImageCache.Get(drop.icon)
            if imgHandle ~= 0 then
                local dx = l.x + renderXNorm * l.w - iconSize / 2
                local dy = l.y + drop.yNorm * l.h - iconSize / 2
                local bob = math.sin((drop.lifetime or 0) * 2.5) * 2
                dy = dy + bob

                local alpha = 1.0
                local lt = drop.lifetime or 0
                if lt < 0.5 then alpha = lt / 0.5
                elseif renderXNorm > 0.85 then alpha = math.max(0, 1.0 - (renderXNorm - 0.85) / 0.25)
                end

                local paint = nvgImagePattern(nvg, dx, dy, iconSize, iconSize, 0, imgHandle, alpha)
                nvgBeginPath(nvg)
                nvgRect(nvg, dx, dy, iconSize, iconSize)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)

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

-- ============================================================
-- 拾取反馈浮字
-- ============================================================
function ChibiSceneWidget:drawPickupFeedback(nvg, l)
    if #pickupFeedbacks_ == 0 then return end
    nvgFontFace(nvg, "sans")
    nvgFontSize(nvg, 14)
    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    for _, fb in ipairs(pickupFeedbacks_) do
        local alpha = math.max(0, fb.alpha)
        local px = l.x + fb.x * l.w
        local py = l.y + fb.y * l.h - fb.timer * 30
        nvgFillColor(nvg, nvgRGBA(0, 0, 0, math.floor(180 * alpha)))
        nvgText(nvg, px + 1, py + 1, fb.text)
        local r, g, b = 255, 220, 80
        if fb.reward_type == "cargo" then r, g, b = 120, 220, 140
        elseif fb.reward_type == "blocked" then r, g, b = 255, 90, 90
        end
        nvgFillColor(nvg, nvgRGBA(r, g, b, math.floor(255 * alpha)))
        nvgText(nvg, px, py, fb.text)
    end
end

-- ============================================================
-- 纸娃娃绘制（行驶模式：驾驶舱、货厢、车外）
-- ============================================================

function ChibiSceneWidget:drawCabinChibis(nvg)
    local tb = sceneBounds_
    if tb.w <= 0 then return end
    local zone = DRIVING_ZONES.cabin

    for _, c in ipairs(chibis_) do
        if c.zone == "cabin" then
            local chibiH = tb.h * ChibiRenderer.CHIBI_H_RATIO * 0.7
            local chibiW = chibiH
            local zoneX = tb.x + zone.x * tb.w
            local zoneY = tb.y + zone.y * tb.h
            local zoneW = zone.w * tb.w
            local drawX = zoneX + c.x * zoneW - chibiW / 2
            local drawY = zoneY + chibiH * 0.25
            ChibiRenderer.drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
        end
    end
end

function ChibiSceneWidget:drawContainerChibis(nvg)
    local tb = sceneBounds_
    if tb.w <= 0 then return end

    for _, c in ipairs(chibis_) do
        local zone = DRIVING_ZONES[c.zone]
        if zone and (c.zone == "container" or c.zone == "table"
                  or c.zone == "stove" or c.zone == "bed"
                  or c.zone == "gun") then
            local sizeRatio = ChibiRenderer.CHIBI_H_RATIO
            if c.zone == "bed" then sizeRatio = ChibiRenderer.CHIBI_H_RATIO * 0.75 end
            local chibiH = tb.h * sizeRatio
            local chibiW = chibiH
            local zoneX = tb.x + zone.x * tb.w
            local zoneY = tb.y + zone.y * tb.h
            local zoneW = zone.w * tb.w
            local zoneH = zone.h * tb.h
            local drawX = zoneX + c.x * zoneW - chibiW / 2
            local drawY = zoneY + zoneH - chibiH
            ChibiRenderer.drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
        end
    end
end

function ChibiSceneWidget:drawOutsideChibis(nvg, l)
    local tb = sceneBounds_
    if tb.w <= 0 then return end

    local outsideH = tb.h * ChibiRenderer.CHIBI_H_RATIO * (currentMode_.outsideScale or 1.2)
    local outsideW = outsideH
    local groundY = l.y + l.h * 0.88

    local areaX = tb.x - tb.w * 0.15
    local areaW = tb.w * 0.5

    for _, c in ipairs(chibis_) do
        if c.zone == "outside" then
            local drawX = areaX + c.x * areaW - outsideW / 2
            local drawY = groundY - outsideH
            ChibiRenderer.drawSingleChibi(nvg, c, drawX, drawY, outsideW, outsideH)
        end
    end

    -- NPC 路人
    local npcs = ChibiRenderer.getNPCs()
    local npcAreaX = tb.x - tb.w * 0.25
    local npcAreaW = tb.w * 1.5

    for _, c in ipairs(npcs) do
        local drawX = npcAreaX + c.x * npcAreaW - outsideW / 2
        local drawY = groundY - outsideH
        ChibiRenderer.drawSingleChibi(nvg, c, drawX, drawY, outsideW, outsideH)
    end
end

-- ============================================================
-- 纸娃娃绘制（非车辆模式：地面角色）
-- ============================================================

--- 计算地面 bounds（探索模式等无卡车模式使用）
function ChibiSceneWidget:computeGroundBounds(l)
    -- 地面区域 = widget 下半部分
    sceneBounds_.x = l.x
    sceneBounds_.y = l.y + l.h * 0.5
    sceneBounds_.w = l.w
    sceneBounds_.h = l.h * 0.5
    sceneBounds_.bounce = 0
end

--- 绘制探索物品（箱子/容器等，站在地面上）
function ChibiSceneWidget:drawExploreItems(nvg, l)
    local sb = sceneBounds_
    if sb.w <= 0 then return end

    local groundY = l.y + l.h * 0.88
    local itemH = sb.h * ChibiRenderer.CHIBI_H_RATIO * (currentMode_.outsideScale or 1.0) * 1.4
    local itemW = itemH

    for _, item in ipairs(exploreItems_) do
        if item.alive then
            local imgHandle = ImageCache.Get(item.image)
            if imgHandle ~= 0 then
                local dx = l.x + item.xNorm * l.w - itemW / 2
                local dy = groundY - itemH
                -- 上下微浮动画
                local bob = math.sin((item.bobPhase or 0) * 1.8) * 2
                dy = dy + bob

                -- 已搜刮的物品半透明
                local alpha = item.looted and 0.3 or 1.0

                nvgSave(nvg)
                nvgGlobalAlpha(nvg, alpha)

                local paint = nvgImagePattern(nvg, dx, dy, itemW, itemH, 0, imgHandle, 1.0)
                nvgBeginPath(nvg)
                nvgRect(nvg, dx, dy, itemW, itemH)
                nvgFillPaint(nvg, paint)
                nvgFill(nvg)

                -- 未搜刮：底部发光提示
                if not item.looted then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, dx + itemW / 2, groundY - 2, itemW * 0.4)
                    nvgFillColor(nvg, nvgRGBA(255, 220, 120, 35))
                    nvgFill(nvg)
                end

                -- 已搜刮：打勾标记
                if item.looted then
                    nvgFontFace(nvg, "sans")
                    nvgFontSize(nvg, 14)
                    nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
                    nvgFillColor(nvg, nvgRGBA(100, 220, 100, 200))
                    nvgText(nvg, dx + itemW / 2, dy + itemH / 2, "✓")
                end

                nvgRestore(nvg)
            end
        end
    end
end

--- 绘制地面模式的角色（主角 + NPC，都站在地面上）
function ChibiSceneWidget:drawGroundChibis(nvg, l)
    local sb = sceneBounds_
    if sb.w <= 0 then return end

    local groundY = l.y + l.h * 0.88
    local chibiH = sb.h * ChibiRenderer.CHIBI_H_RATIO * (currentMode_.outsideScale or 1.0) * 2
    local chibiW = chibiH
    local zoneDefs = currentMode_.zones or {}

    -- 主角
    for _, c in ipairs(chibis_) do
        local zone = zoneDefs[c.zone]
        if zone then
            local zoneX = l.x + zone.x * l.w
            local zoneW = zone.w * l.w
            local drawX = zoneX + c.x * zoneW - chibiW / 2
            local drawY = groundY - chibiH
            ChibiRenderer.drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
        end
    end

    -- NPC
    local npcs = ChibiRenderer.getNPCs()
    for _, c in ipairs(npcs) do
        local drawX = l.x + c.x * l.w - chibiW / 2
        local drawY = groundY - chibiH
        ChibiRenderer.drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
    end
end

-- ============================================================
-- 天气粒子更新
-- ============================================================
local function updateWeatherParticles(dt, w, h)
    local weather = currentEnv_.weather
    if weather == "rain" then
        for _, p in ipairs(weatherParticles_) do
            p.y = p.y + p.speed * dt
            p.x = p.x + p.speed * 0.3 * dt
            if p.y > h then p.y = -p.len; p.x = math.random() * w end
            if p.x > w then p.x = p.x - w end
        end
    elseif weather == "snow" then
        for _, p in ipairs(weatherParticles_) do
            p.y = p.y + p.speed * dt
            p.phase = p.phase + dt * 1.5
            p.x = p.x + (p.drift + math.sin(p.phase) * 10) * dt
            if p.y > h then p.y = -p.radius * 2; p.x = math.random() * w end
            if p.x > w then p.x = p.x - w end
            if p.x < 0 then p.x = p.x + w end
        end
    end
end

-- ============================================================
-- 输入检测
-- ============================================================

local function getUIScale()
    local dpr = graphics:GetDPR()
    local shortSide = math.min(graphics:GetWidth(), graphics:GetHeight()) / dpr
    local PC_REF = 720
    local densityFactor = math.sqrt(shortSide / PC_REF)
    densityFactor = math.max(0.625, math.min(densityFactor, 1.0))
    return dpr * densityFactor
end

local function checkDropInput()
    local pressed = input:GetMouseButtonPress(MOUSEB_LEFT)
    if pressed then
        framePressed_ = true
        local mousePos = input:GetMousePosition()
        local scale = getUIScale()
        frameMX_ = mousePos.x / scale
        frameMY_ = mousePos.y / scale
    end

    if not onDropClick_ then return end
    if #activeDrops_ == 0 then return end
    if not lastLayout_ then return end
    if not framePressed_ then return end

    local baseX = frameMX_
    local baseY = frameMY_
    local l = lastLayout_
    if baseX < l.x or baseX > l.x + l.w then return end
    if baseY < l.y or baseY > l.y + l.h then return end

    local normX = (baseX - l.x) / l.w
    local normY = (baseY - l.y) / l.h
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
                clickConsumed_ = true
                return
            end
        end
    end
end

local function checkChibiInput()
    if clickConsumed_ then return end
    if not lastLayout_ then return end
    if not framePressed_ then return end
    local npcs = ChibiRenderer.getNPCs()
    if ChibiRenderer.checkChibiInput(chibis_, npcs, frameMX_, frameMY_, onChibiClick_) then
        clickConsumed_ = true
    end
end

-- ============================================================
-- 公共接口
-- ============================================================

--- 设置场景模式
---@param modeName string "driving" | "explore"
function M.setMode(modeName)
    local mode = MODES[modeName]
    if mode then
        currentMode_ = mode
        currentModeName_ = modeName
        -- 按 zoneMap 重映射角色区域（如 cabin→ground_left），并触发淡入过渡
        if mode.zoneMap then
            for _, c in ipairs(chibis_) do
                local mapped = mode.zoneMap[c.zone]
                if mapped and mapped ~= c.zone then
                    c.zone = mapped
                    c._zoneFadeIn = 0.3  -- 淡入过渡
                    c.emote = nil
                end
            end
        end
        print("[ChibiScene] mode → " .. modeName)
    else
        print("[ChibiScene] WARNING: unknown mode '" .. tostring(modeName) .. "', keeping " .. currentModeName_)
    end
end

--- 获取当前模式名称
---@return string
function M.getModeName()
    return currentModeName_
end

--- 注册模式配置（供 explore_mode.lua 等外部模块注册）
---@param name string
---@param config table
function M.registerMode(name, config)
    MODES[name] = config
end

--- 每帧更新
---@param dt number
function M.update(dt)
    if combatRenderer_ then combatRenderer_.update(dt) end

    -- 滚动
    if isDriving_ then
        local speedMult = 1.0
        if combatRenderer_ then speedMult = combatRenderer_.getSpeedMultiplier() end
        local scrollSpd = currentMode_.scrollSpeed or SCROLL_SPEED
        scrollOffset_ = scrollOffset_ + dt * scrollSpd * speedMult
    end

    -- 纸娃娃 AI
    local zoneDefs = currentMode_.zones or DRIVING_ZONES
    local npcs = ChibiRenderer.getNPCs()
    local combatLocked = combatRenderer_ ~= nil
    ChibiRenderer.updateAll(dt, chibis_, npcs, zoneDefs, isDriving_, combatLocked)

    -- 天气粒子
    if weatherParticlesInited_ and #weatherParticles_ > 0 then
        updateWeatherParticles(dt, 400, 220)
    end

    -- 探索物品动画
    for _, item in ipairs(exploreItems_) do
        item.bobPhase = (item.bobPhase or 0) + dt
    end

    -- 输入
    clickConsumed_ = false
    framePressed_ = false
    if currentMode_.hasVehicle then
        checkDropInput()
    end
    checkChibiInput()

    -- 拾取浮字
    local FEEDBACK_DURATION = 1.2
    local expired = {}
    for i, fb in ipairs(pickupFeedbacks_) do
        fb.timer = fb.timer + dt
        fb.alpha = 1.0 - fb.timer / FEEDBACK_DURATION
        if fb.timer >= FEEDBACK_DURATION then table.insert(expired, i) end
    end
    for j = #expired, 1, -1 do table.remove(pickupFeedbacks_, expired[j]) end
end

--- 设置环境
---@param env table { region, weather, timeOfDay }
function M.setEnvironment(env)
    if not env then return end
    local changed = false

    if env.region and env.region ~= currentEnv_.region then
        currentEnv_.region = env.region
        if not settlementSceneImage_ then
            local newMid = MID_IMAGES[env.region]
            if newMid then LAYER_DEFS[3].image = newMid end
        end
        changed = true
    end

    if env.weather and env.weather ~= currentEnv_.weather then
        currentEnv_.weather = env.weather
        resetWeatherParticles()
        changed = true
    end

    if env.timeOfDay then currentEnv_.timeOfDay = env.timeOfDay end

    if changed then
        print(string.format("[ChibiScene] ENV → region=%s weather=%s time=%s",
            currentEnv_.region, currentEnv_.weather, currentEnv_.timeOfDay))
    end
end

function M.createWidget(props)
    return ChibiSceneWidget(props or {})
end

function M.setDrops(drops) activeDrops_ = drops or {} end
function M.setDropCallback(callback) onDropClick_ = callback end
function M.setChibiClickCallback(callback) onChibiClick_ = callback end

--- 设置探索物品列表（箱子/容器的可视化）
---@param items table[] { { id=string, image=string, xNorm=number } }
function M.setExploreItems(items)
    exploreItems_ = {}
    for i, item in ipairs(items or {}) do
        exploreItems_[i] = {
            id       = item.id,
            image    = item.image,
            xNorm    = item.xNorm,
            alive    = true,
            looted   = false,
            bobPhase = math.random() * 6.28,  -- 随机初始相位，错开浮动节奏
        }
    end
end

--- 标记指定探索物品为已搜刮
---@param itemId string
function M.markExploreItemLooted(itemId)
    for _, item in ipairs(exploreItems_) do
        if item.id == itemId then
            item.looted = true
            return
        end
    end
end

--- 清空探索物品
function M.clearExploreItems()
    exploreItems_ = {}
end

function M.setSettlement(settlementId)
    local img = settlementId and SETTLEMENT_SCENE_IMAGES[settlementId] or nil
    if img then
        settlementSceneImage_ = img
        print("[ChibiScene] settlement scene → " .. settlementId)
    end
end

function M.clearSettlement()
    if not settlementSceneImage_ then return end
    settlementSceneImage_ = nil
    print("[ChibiScene] settlement scene cleared → region=" .. tostring(currentEnv_.region))
end

function M.addFeedback(feedback)
    if not feedback then return end
    table.insert(pickupFeedbacks_, {
        text = feedback.reward_text or "", reward_type = feedback.reward_type or "credits",
        x = feedback.x or 0.5, y = feedback.y or 0.8, timer = 0, alpha = 1.0,
    })
end

function M.setState(state) gameState_ = state end

function M.setDriving(driving)
    if isDriving_ == driving then return end
    isDriving_ = driving
    if driving then
        ChibiRenderer.clearNPCs()
        local anyInCabin = false
        for _, c in ipairs(chibis_) do
            if c.zone == "cabin" then anyInCabin = true; break end
        end
        if not anyInCabin then
            chibis_[1].zone = "cabin"
            chibis_[1].x = 0.5; chibis_[1].targetX = 0.5
            chibis_[1].state = "idle"; chibis_[1].stateTimer = 2
        end
        for _, c in ipairs(chibis_) do
            if c.zone == "outside" then
                c.zone = "container"; c.x = 0.5; c.targetX = 0.5
                c.state = "idle"; c.stateTimer = 1
            end
        end
    else
        ChibiRenderer.spawnNPCs(gameState_)
    end
end

--- 仅控制背景滚动开关，不触发角色 zone 重置
--- 适用于 explore 等非行驶模式需要缓慢滚动的场景
---@param scrolling boolean
function M.setScrolling(scrolling)
    isDriving_ = scrolling
end

function M.reset()
    scrollOffset_ = 0
    resetWeatherParticles()
    activeDrops_ = {}
    exploreItems_ = {}
    pickupFeedbacks_ = {}
    onDropClick_ = nil
    lastLayout_ = nil
    ChibiRenderer.resetChibi(chibis_[1], "cabin",     0.5,  1, 0,   25)
    ChibiRenderer.resetChibi(chibis_[2], "container", 0.3, -1, 1.5, 20)
end

--- 注入战斗渲染模块
---@param renderer table
function M.setCombatRenderer(renderer)
    combatRenderer_ = renderer

    -- 锁定两个角色进入战斗状态，带淡入过渡
    for _, c in ipairs(chibis_) do
        c._savedZone = c.zone
        c._combatLocked = true
        c._zoneFadeIn = 0.3
        c.emote = nil
    end

    local linli  = chibis_[1]
    local taoxia = chibis_[2]

    if currentMode_.hasVehicle then
        -- 行驶模式：陶侠上炮台，琳莉留驾驶舱
        taoxia.zone = "gun"
        linli.zone  = "cabin"
    else
        -- 探索模式：主角在右侧（与其他场景一致：从右往左移动）
        -- 陶侠在右侧前方（面朝敌人/左侧），琳莉在右侧后方
        taoxia.zone = "ground_right"
        taoxia.x = 0.35; taoxia.targetX = 0.35
        linli.zone  = "ground_right"
        linli.x = 0.75; linli.targetX = 0.75
    end

    -- 陶侠面朝敌人（左侧），锁定 idle
    taoxia.facing = -1; taoxia.scaleX = -1
    taoxia.state = "idle"; taoxia.stateTimer = 999
    taoxia.switchTimer = 9999; taoxia.walkTime = 0

    -- 琳莉也面朝敌人（左侧），锁定 idle
    linli.facing = -1; linli.scaleX = -1
    linli.state = "idle"; linli.stateTimer = 999
    linli.switchTimer = 9999; linli.walkTime = 0
end

function M.clearCombatRenderer()
    combatRenderer_ = nil
    local zoneDefs = currentMode_.zones or DRIVING_ZONES

    for _, c in ipairs(chibis_) do
        c._combatLocked = false
        local restoreZone = c._savedZone
        if restoreZone then
            if not zoneDefs[restoreZone] then
                restoreZone = currentMode_.hasVehicle and "container" or "ground_right"
            end
        else
            restoreZone = currentMode_.hasVehicle and "container" or "ground_right"
        end
        c._savedZone = nil
        c.zone = restoreZone
        c.x = 0.5; c.targetX = 0.5
        c.state = "idle"; c.stateTimer = 2 + math.random() * 2
        c.switchTimer = 10 + math.random() * 10
        c._zoneFadeIn = 0.3  -- 淡入过渡
        c.emote = nil
    end
end

--- 获取主角数组（供外部模块读取角色状态）
---@return table[]
function M.getChibis()
    return chibis_
end

--- 获取 sceneBounds（供外部模块定位）
---@return table
function M.getSceneBounds()
    return sceneBounds_
end

return M

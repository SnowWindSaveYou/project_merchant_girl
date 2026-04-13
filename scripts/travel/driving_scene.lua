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

local Widget      = require("urhox-libs/UI/Core/Widget")
local ImageCache  = require("urhox-libs/UI/Core/ImageCache")
local RoadLoot    = require("travel/road_loot")
local Modules     = require("truck/modules")
local Graph       = require("map/world_graph")
local Factions    = require("settlement/factions")
local NpcManager  = require("narrative/npc_manager")
local WanderingNpc = require("narrative/wandering_npc")

local M = {}

-- ============================================================
-- 配置
-- ============================================================
local SCROLL_SPEED = 50   -- 基础滚动速度 (像素/秒)

-- ── 纸娃娃 & 装备配置 ──────────────────────────────────────
--- 区域定义（归一化坐标，相对卡车图片 1024×572）
--- 从 truck_locations_2.png 色块标注提取
local ZONES = {
    -- 车厢整体（用于 outside→container 切换后的默认落点）
    container = { x = 0.379, y = 0.150, w = 0.545, h = 0.518 },
    -- 驾驶舱（cyan 标注区域，修正：比旧值大幅下移）
    cabin     = { x = 0.193, y = 0.294, w = 0.106, h = 0.376 },
    -- 饭桌（green 标注区域）
    table     = { x = 0.439, y = 0.358, w = 0.094, h = 0.311 },
    -- 灶台（magenta 标注区域）
    stove     = { x = 0.594, y = 0.406, w = 0.106, h = 0.264 },
    -- 床铺（blue 标注区域）
    bed       = { x = 0.714, y = 0.406, w = 0.191, h = 0.177 },
    -- 装备挂载区
    gun       = { x = 0.396, y = -0.10,  w = 0.366, h = 0.228 },
    radar     = { x = 0.763, y = -0.10,  w = 0.190, h = 0.226 },
}

--- 纸娃娃图片（按姿势差分）
local CHIBI_IMAGES = {
    linli = {
        default = "image/chibi_linli_20260409053601.png",
        drive   = "image/chibi_linli_drive_20260409070207.png",
        eat     = "image/chibi_linli_eat_20260409070212.png",
        cook    = "image/chibi_linli_cook_20260409070159.png",
        sleep   = "image/chibi_linli_sleep_20260409073014.png",
    },
    taoxia = {
        default = "image/chibi_taoxia_20260409053853.png",
        drive   = "image/chibi_taoxia_drive_20260409070148.png",
        eat     = "image/chibi_taoxia_eat_20260409070156.png",
        cook    = "image/chibi_taoxia_cook_20260409070214.png",
        sleep   = "image/chibi_taoxia_sleep_20260409073033.png",
    },
}

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

--- 额外路人池（可作为任意势力的随机路人）
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

--- 区域→姿势映射
local ZONE_POSE = {
    cabin     = "drive",
    table     = "eat",
    stove     = "cook",
    bed       = "sleep",
    container = "default",
    outside   = "default",
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
local CHIBI_H_RATIO = 0.32
--- 纸娃娃移动速度（归一化/秒）
local CHIBI_WALK_SPEED = 0.10
--- 切换区域间隔范围（秒）
local CHIBI_ZONE_SWITCH_MIN = 20
local CHIBI_ZONE_SWITCH_MAX = 40
--- 行走动画参数
local WOBBLE_FREQ   = 2.2   -- 颠动频率 (Hz)
local WOBBLE_PX     = 6.0   -- 颠动幅度 (像素，上下位移)
local WALK_SQUASH_AMP = 0.04  -- 走路挤压拉伸幅度 (±4%)
local WALK_LEAN_DEG   = 2.5   -- 走路左右倾斜角度 (度)
--- 纸片翻转转身时长（秒）
local FLIP_DURATION = 0.25
--- idle 呼吸缩放参数
local BREATH_FREQ   = 0.6   -- 呼吸频率 (Hz)
local BREATH_AMP    = 0.035 -- 呼吸缩放幅度 (±3.5%)
local IDLE_BOB_FREQ = 0.8   -- idle 轻微浮动频率 (Hz)
local IDLE_BOB_PX   = 2.5   -- idle 浮动幅度 (像素)
--- 气泡表情配置
local EMOTE_INTERVAL_MIN = 8    -- 最短间隔（秒）
local EMOTE_INTERVAL_MAX = 20   -- 最长间隔（秒）
local EMOTE_DURATION     = 2.5  -- 气泡显示时长（秒）
local EMOTE_FADE_TIME    = 0.4  -- 淡入淡出时间（秒）
--- 不同状态/区域的表情池
local EMOTES_IDLE    = { "💤", "...", "～♪", "😊", "🤔" }
local EMOTES_WALK    = { "♪", "🎵", "!", "→" }
local EMOTES_CABIN   = { "🚗", "👀", "😤", "～♪", "🛣️" }
local EMOTES_TABLE   = { "🍚", "😋", "🥢", "好吃", "🍜" }
local EMOTES_STOVE   = { "🔥", "🍳", "好香", "👨‍🍳", "♨️" }
local EMOTES_BED     = { "💤", "😴", "zzZ", "😌", "..." }
local EMOTES_OUTSIDE = { "🌿", "☁️", "😌", "🔍" }

--- ── 点击互动配置 ────────────────────────────────────────────
local CLICK_CD            = 2.0   -- 点击冷却（秒）
local CLICK_BOUNCE_DUR    = 0.35  -- 弹跳持续时间（秒）
local CLICK_BOUNCE_PX     = 10    -- 弹跳高度（像素）
local CLICK_COMBO_WINDOW  = 4.0   -- 连击判定窗口（秒）

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

--- 点击回调（由 screen_home 设置，用于播放音效）
local onChibiClick_ = nil
--- 点击消费标记（同一帧内 drop 和 chibi 互斥）
local clickConsumed_ = false
local framePressed_  = false   -- 本帧是否有鼠标按下（缓存，避免多次 GetMouseButtonPress）
local frameMX_       = 0       -- 本帧鼠标 base 坐标 X
local frameMY_       = 0       -- 本帧鼠标 base 坐标 Y

--- 区域 → 中景图片路径（按地形景观分类，行驶中使用）
local MID_IMAGES = {
    urban   = "image/parallax_mid_20260408172203.png",          -- 城郊废墟（原有）
    wild    = "image/parallax_mid_wild_20260409030220.png",     -- 荒野
    canyon  = "image/parallax_mid_canyon_20260409030302.png",    -- 峡谷
    forest  = "image/parallax_mid_forest_20260409030347.png",   -- 枯木林
}

--- 聚落 → 停泊场景完整背景图（停车时替代所有视差层）
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

--- 当前聚落静态场景图（停泊时由 screen_home 设置，非 nil 时跳过视差层）
local settlementSceneImage_ = nil

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
local combatRenderer_ = nil   -- 战斗渲染模块（由 screen_ambush 注入）

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

--- 是否处于行驶状态
local isDriving_ = true

--- 获取角色当前姿势图片
---@param c table 角色状态
---@return string 图片路径
local function getChibiImage(c)
    -- NPC 路人使用固定图片
    if c.npcImage then return c.npcImage end
    local poses = CHIBI_IMAGES[c.id]
    if not poses then return "" end
    local pose = ZONE_POSE[c.zone] or "default"
    return poses[pose] or poses.default
end

--- 纸娃娃角色状态
local chibis_ = {
    {
        id = "linli",
        zone = "cabin",           -- "cabin"|"table"|"stove"|"bed"|"container"|"outside"
        x = 0.5, targetX = 0.5,   -- 在区域内的归一化 x (0~1)
        facing = 1,               -- 1=右, -1=左
        scaleX = 1,               -- 当前渲染缩放（用于纸片翻转）
        state = "idle",           -- "idle" | "walk" | "turning"
        stateTimer = 0,           -- 当前状态剩余时间
        switchTimer = 25,         -- 切换区域倒计时
        flipTimer = 0,            -- 翻转动画计时器
        flipFrom = 1,             -- 翻转起始方向
        walkTime = 0,             -- 行走总时长（用于颠动相位）
        idleTime = 0,             -- idle 累计时间（用于呼吸动画）
        emote = nil,              -- 当前表情文字 (nil=无)
        emoteTimer = 0,           -- 表情显示计时
        emoteCD = 5 + math.random() * 10, -- 下次表情倒计时
        clickCD = 0,              -- 点击冷却
        clickBounce = 0,          -- 弹跳动画计时
        clickCombo = 0,           -- 连击次数
        clickComboTimer = 0,      -- 连击窗口计时
    },
    {
        id = "taoxia",
        zone = "table",           -- 初始在饭桌
        x = 0.5, targetX = 0.5,
        facing = -1,
        scaleX = -1,
        state = "idle",
        stateTimer = 1.5,
        switchTimer = 35,
        flipTimer = 0,
        flipFrom = -1,
        walkTime = 0,
        idleTime = 0,
        emote = nil,
        emoteTimer = 0,
        emoteCD = 8 + math.random() * 12,
        clickCD = 0,
        clickBounce = 0,
        clickCombo = 0,
        clickComboTimer = 0,
    },
}

--- 聚落路人 NPC 纸娃娃（停车时出现，行驶时清除）
local npcs_ = {}  -- 动态数组，和 chibis_ 同结构但只在 outside 区域

--- 创建 NPC 路人（感知聚落类型/势力/驻扎&流浪 NPC）
local function spawnNPCs()
    npcs_ = {}
    if not gameState_ then return end

    local currentLoc = gameState_.map and gameState_.map.current_location
    if not currentLoc then return end

    -- 1. 获取当前节点
    local node = Graph.get_node(currentLoc)
    if not node then return end

    -- 2. 判断节点类型和势力
    local isSettlement = (node.type == "settlement")
    local factionId = isSettlement and Factions.get_faction(currentLoc) or nil
    local factionEmotes = (factionId and FACTION_EMOTES[factionId]) or DEFAULT_EMOTES

    -- 3. 收集候选 NPC（按优先级）
    local candidates = {}
    local usedImages = {}  -- 去重

    -- 3a. 流浪 NPC（任何节点都可能出现）
    local wanderers = WanderingNpc.get_wanderers_at(gameState_, currentLoc)
    for _, w in ipairs(wanderers) do
        if NPC_CHIBI_MAP[w.id] and not usedImages[NPC_CHIBI_MAP[w.id]] then
            table.insert(candidates, {
                id      = w.id,
                image   = NPC_CHIBI_MAP[w.id],
                priority = 8,
                emotes  = DEFAULT_EMOTES,
                faction = nil,  -- 流浪 NPC 无势力
            })
            usedImages[NPC_CHIBI_MAP[w.id]] = true
        end
    end

    -- 以下仅聚落节点
    if isSettlement then
        -- 3b. 驻扎特殊 NPC（该聚落的居民）
        local residents = NpcManager.get_npcs_for_settlement(currentLoc)
        for _, npc in ipairs(residents) do
            if NPC_CHIBI_MAP[npc.id] and not usedImages[NPC_CHIBI_MAP[npc.id]] then
                table.insert(candidates, {
                    id      = npc.id,
                    image   = NPC_CHIBI_MAP[npc.id],
                    priority = 10,
                    emotes  = factionEmotes,
                    faction = factionId,
                })
                usedImages[NPC_CHIBI_MAP[npc.id]] = true
            end
        end

        -- 3c. 势力通用路人（补充人气）
        if factionId and FACTION_GENERIC_CHIBI[factionId] then
            local genImg = FACTION_GENERIC_CHIBI[factionId]
            if not usedImages[genImg] then
                table.insert(candidates, {
                    id      = "generic_" .. factionId,
                    image   = genImg,
                    priority = 3,
                    emotes  = factionEmotes,
                    faction = factionId,
                })
                usedImages[genImg] = true
            end
        end

        -- 3d. 额外路人池（随机选一个）
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
                        id      = "extra_passerby",
                        image   = img,
                        priority = 1,
                        emotes  = factionEmotes,
                        faction = factionId,
                    })
                    usedImages[img] = true
                    break
                end
            end
        end
    end

    -- 非聚落且无流浪 NPC → 不生成
    if #candidates == 0 then return end

    -- 5. 按优先级排序，取 2~3 个
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
            switchTimer = 999, -- NPC 不切换区域
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
        print("[DrivingScene] Spawned " .. #npcs_ .. " NPCs at " .. currentLoc
            .. " (faction=" .. (factionId or "none") .. ")")
    end
end

--- 清除 NPC 路人
local function clearNPCs()
    npcs_ = {}
end

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
--- 直接使用 scrollOffset_ 差值，与地面层完全同步
---@param drop table
---@param widgetW number widget 宽度（像素）
---@return number driftNorm
local function calcDropDrift(drop, widgetW)
    if widgetW <= 0 then return 0 end
    -- 首次渲染时记录出生偏移量
    if not drop._spawnScroll then
        drop._spawnScroll = scrollOffset_
    end
    -- 地面层偏移 = scrollOffset_ * 1.0（speed=1.0），掉落物跟随
    local pixelDrift = (scrollOffset_ - drop._spawnScroll) * RoadLoot.GROUND_SPEED
    return pixelDrift / widgetW
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

    -- 战斗抖动：整体 translate 偏移
    if combatRenderer_ then
        local sx, sy = combatRenderer_.getScreenShake()
        if sx ~= 0 or sy ~= 0 then
            nvgTranslate(nvg, sx, sy)
        end
    end

    -- 聚落静态场景模式：停泊时用完整场景图替代所有视差层
    if settlementSceneImage_ then
        self:drawSettlementScene(nvg, l)
    else
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
    end

    -- 6) 路面掉落物
    self:drawDrops(nvg, l)

    -- 7) 计算卡车位置（供后续所有层使用）
    self:computeTruckBounds(l)

    -- 8) 驾驶舱纸娃娃（卡车后面，只露头）
    self:drawCabinChibis(nvg)

    -- 9) 卡车车身 + 车轮
    self:drawTruck(nvg)

    -- 10) 装备（炮塔/雷达，在车身之上）
    self:drawEquipment(nvg)

    -- 10.5) 战斗渲染层（敌方载具/纸娃娃/效果）
    if combatRenderer_ then
        combatRenderer_.render(nvg, l, truckBounds_)
    end

    -- 11) 货厢纸娃娃（在卡车上面）
    self:drawContainerChibis(nvg)

    -- 12) 车外纸娃娃（停泊时）
    self:drawOutsideChibis(nvg, l)

    -- 13) 天气效果（最上层，雨雪覆盖所有物体）
    self:drawWeather(nvg, l)

    -- 14) 拾取反馈浮字
    self:drawPickupFeedback(nvg, l)

    nvgRestore(nvg)
end

-- ── 聚落静态场景（停泊时替代所有视差层） ────────────────────
function DrivingSceneWidget:drawSettlementScene(nvg, l)
    local imgHandle = ImageCache.Get(settlementSceneImage_)
    if imgHandle == 0 then return end
    -- 场景图铺满整个 widget
    local paint = nvgImagePattern(nvg,
        l.x, l.y,
        l.w, l.h,
        0, imgHandle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, l.x, l.y, l.w, l.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
    -- 叠加时段色调
    self:drawTimeTint(nvg, l)
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
    -- 战斗模块可提供水平偏移（归一化 0~1，正值=向右）
    local xOffset = 0
    if combatRenderer_ then
        xOffset = combatRenderer_.getTruckOffset()
    end
    local truckX = l.x + (l.w - truckW) / 2 + xOffset * l.w
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
    -- 战斗时用外观贴图，非战斗用日常贴图
    local truckImg = TRUCK_IMAGE
    if combatRenderer_ and combatRenderer_.getTruckImage then
        truckImg = combatRenderer_.getTruckImage() or TRUCK_IMAGE
    end
    local imgHandle = ImageCache.Get(truckImg)
    if imgHandle == 0 then return end

    local paint = nvgImagePattern(nvg,
        tb.x, tb.y, tb.w, tb.h,
        0, imgHandle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, tb.x, tb.y, tb.w, tb.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)

    -- ── 受击闪白：用 additive blend 再画一遍卡车图片 ──
    if combatRenderer_ and combatRenderer_.getTruckFlash then
        local flashA = combatRenderer_.getTruckFlash()
        if flashA > 0 then
            nvgSave(nvg)
            nvgGlobalCompositeBlendFunc(nvg, NVG_ONE, NVG_ONE)
            local fp = nvgImagePattern(nvg,
                tb.x, tb.y, tb.w, tb.h,
                0, imgHandle, flashA)
            nvgBeginPath(nvg)
            nvgRect(nvg, tb.x, tb.y, tb.w, tb.h)
            nvgFillPaint(nvg, fp)
            nvgFill(nvg)
            nvgRestore(nvg)
        end
    end

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

-- ── 纸娃娃辅助 ─────────────────────────────────────────────

--- 判断另一个角色是否在指定区域
local function otherInZone(chibiIdx, zoneName)
    local otherIdx = chibiIdx == 1 and 2 or 1
    return chibis_[otherIdx].zone == zoneName
end

--- 启动纸片翻转动画
local function startFlip(c, newFacing)
    if c.facing == newFacing then return end
    c.state = "turning"
    c.flipTimer = 0
    c.flipFrom = c.facing
end

--- 可用区域列表（行驶/停泊不同）
--- container 是主要走动区域，其余为固定姿势区域（偶尔去做事）
local FIXED_ZONE_DURATION_MIN = 8   -- 固定区域停留最短时间（秒）
local FIXED_ZONE_DURATION_MAX = 15  -- 固定区域停留最长时间（秒）

local function getAvailableZones(chibiIdx)
    if isDriving_ then
        -- 行驶：container 为主，偶尔去固定区域做事
        return { "container", "container", "container", "cabin", "table", "stove", "bed" }
    else
        -- 停车：车外为主，其次车内，不去驾驶室
        return { "outside", "outside", "outside", "outside", "container", "container", "table", "stove", "bed" }
    end
end

-- ── 纸娃娃 AI 更新 ─────────────────────────────────────────
local function updateChibis(dt)
    for ci, c in ipairs(chibis_) do
        -- ── 战斗中陶夏锁定在 gun 区域，跳过 AI ──
        if combatRenderer_ and c.zone == "gun" then
            goto continue
        end

        -- ── 翻转动画 ──
        if c.state == "turning" then
            c.flipTimer = c.flipTimer + dt
            local progress = math.min(1, c.flipTimer / FLIP_DURATION)
            -- cos 从 1→0→-1：前半程压扁，后半程展开到反方向
            c.scaleX = c.flipFrom * math.cos(progress * math.pi)
            if progress >= 0.5 and c.facing == c.flipFrom then
                c.facing = -c.flipFrom
            end
            if progress >= 1 then
                c.scaleX = c.facing
                c.state = "walk"
                c.walkTime = 0
            end
            goto continue
        end

        -- ── 区域切换倒计时 ──
        c.switchTimer = c.switchTimer - dt
        if c.switchTimer <= 0 then
            c.switchTimer = CHIBI_ZONE_SWITCH_MIN
                + math.random() * (CHIBI_ZONE_SWITCH_MAX - CHIBI_ZONE_SWITCH_MIN)

            -- 行驶中：必须保证至少一人在驾驶舱
            if isDriving_ and c.zone == "cabin" and not otherInZone(ci, "cabin") then
                -- 自己是唯一在驾驶舱的，不能离开
                goto continue
            end

            -- 选一个不同的区域
            local zones = getAvailableZones(ci)
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
                -- 固定区域停留时间短，container 正常间隔
                local isFixed = (newZone == "cabin" or newZone == "table" or newZone == "stove" or newZone == "bed")
                if isFixed then
                    c.switchTimer = FIXED_ZONE_DURATION_MIN
                        + math.random() * (FIXED_ZONE_DURATION_MAX - FIXED_ZONE_DURATION_MIN)
                end
            end
        end

        -- ── 状态机：idle ↔ walk ──
        -- 固定姿势区域不走动（table/stove/bed），只在 idle 中呼吸
        local isFixedZone = (c.zone == "cabin" or c.zone == "table" or c.zone == "stove" or c.zone == "bed")

        if c.state == "idle" then
            c.stateTimer = c.stateTimer - dt
            c.idleTime = c.idleTime + dt
            c.walkTime = 0
            if c.stateTimer <= 0 then
                if isFixedZone then
                    -- 固定区域：重新进入 idle，不走动
                    c.stateTimer = 3 + math.random() * 5
                else
                    -- 选择目标位置
                    if c.zone == "container" or c.zone == "outside" then
                        c.targetX = 0.08 + math.random() * 0.84
                    else -- cabin
                        c.targetX = 0.2 + math.random() * 0.6
                    end
                    -- 判断是否需要转身
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
                -- 行走中方向改变时触发翻转
                if dir ~= c.facing then
                    startFlip(c, dir)
                end
            end
            -- 更新缩放为当前朝向（非翻转期间）
            c.scaleX = c.facing
        end

        -- ── 气泡表情更新 ──
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
                -- 根据当前状态/区域选择表情池
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
                elseif c.zone == "outside" then
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

        ::continue::
    end

    -- ── NPC 路人更新（仅 outside 走动，不切换区域）──
    for _, c in ipairs(npcs_) do
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
end

--- 绘制单个纸娃娃（带颠动 + 纸片缩放 + 呼吸 + 气泡表情）
---@param nvg userdata
---@param c table 角色状态
---@param drawX number 目标 x
---@param drawY number 目标 y
---@param chibiW number
---@param chibiH number
local function drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
    -- 记录渲染位置供点击检测使用
    c._hitX = drawX
    c._hitY = drawY
    c._hitW = chibiW
    c._hitH = chibiH

    local imgPath = getChibiImage(c)
    local imgHandle = ImageCache.Get(imgPath)
    if imgHandle == 0 then return end

    local cx = drawX + chibiW / 2
    local cy = drawY + chibiH      -- 变换支点在脚底

    -- 上下位移动画
    local bobY = 0
    if c.state == "walk" and c.walkTime > 0 then
        -- 行走颠动（较快频率，较大幅度）
        bobY = -math.abs(math.sin(c.walkTime * WOBBLE_FREQ * math.pi)) * WOBBLE_PX
    elseif c.state == "idle" and c.idleTime > 0 then
        -- idle 轻微浮动（缓慢，柔和）
        bobY = -math.abs(math.sin(c.idleTime * IDLE_BOB_FREQ * math.pi)) * IDLE_BOB_PX
    end
    -- 点击弹跳（叠加在其他动画之上）
    if c.clickBounce and c.clickBounce > 0 then
        local t = c.clickBounce / CLICK_BOUNCE_DUR
        bobY = bobY - math.sin(t * math.pi) * CLICK_BOUNCE_PX
    end

    -- 身体形变动画
    local scaleY = 1.0
    local leanRad = 0  -- 左右倾斜弧度
    if c.state == "walk" and c.walkTime > 0 then
        -- 走路：纵向挤压拉伸（模拟脚步着地/弹起）
        local walkPhase = c.walkTime * WOBBLE_FREQ * 2 * math.pi
        scaleY = 1.0 + math.sin(walkPhase) * WALK_SQUASH_AMP
        -- 走路：左右倾斜摇摆（模拟重心转移）
        leanRad = math.sin(walkPhase * 0.5) * math.rad(WALK_LEAN_DEG)
    elseif (c.state == "idle" or c.state == "turning") and c.idleTime > 0 then
        -- idle：呼吸缩放
        scaleY = 1.0 + math.sin(c.idleTime * BREATH_FREQ * 2 * math.pi) * BREATH_AMP
    end

    nvgSave(nvg)
    nvgTranslate(nvg, cx, cy + bobY)

    -- 走路倾斜（绕脚底支点旋转）
    if leanRad ~= 0 then
        nvgRotate(nvg, leanRad)
    end
    -- 纸片翻转缩放 + 身体形变
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
        -- 淡入淡出
        local alpha = 1.0
        if c.emoteTimer < EMOTE_FADE_TIME then
            alpha = c.emoteTimer / EMOTE_FADE_TIME
        elseif c.emoteTimer > EMOTE_DURATION - EMOTE_FADE_TIME then
            alpha = (EMOTE_DURATION - c.emoteTimer) / EMOTE_FADE_TIME
        end
        alpha = math.max(0, math.min(1, alpha))

        -- 气泡位置：头顶上方，轻微上浮
        local floatUp = math.sin(c.emoteTimer * 1.5) * 2
        local bubbleX = drawX + chibiW / 2
        local bubbleY = drawY + bobY - 6 + floatUp

        -- 测量文字宽度以动态计算气泡尺寸
        nvgSave(nvg)
        nvgGlobalAlpha(nvg, alpha)
        nvgFontFace(nvg, "sans")
        nvgFontSize(nvg, 11)
        nvgTextAlign(nvg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        local tw = nvgTextBounds(nvg, 0, 0, c.emote)
        local padX, padH = 8, 6
        local bw = math.max(22, tw + padX * 2)
        local bh = 18
        -- 气泡背景（圆角矩形）
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

-- ── 绘制驾驶舱纸娃娃（在卡车后面，只露头）─────────────────
function DrivingSceneWidget:drawCabinChibis(nvg)
    local tb = truckBounds_
    if tb.w <= 0 then return end
    local zone = ZONES.cabin

    for _, c in ipairs(chibis_) do
        if c.zone == "cabin" then
            local chibiH = tb.h * CHIBI_H_RATIO * 0.7
            local chibiW = chibiH

            local zoneX = tb.x + zone.x * tb.w
            local zoneY = tb.y + zone.y * tb.h
            local zoneW = zone.w * tb.w

            local drawX = zoneX + c.x * zoneW - chibiW / 2
            local drawY = zoneY + chibiH * 0.25

            drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
        end
    end
end

-- ── 绘制货厢纸娃娃（在卡车上面：table/stove/bed/container/gun）──
function DrivingSceneWidget:drawContainerChibis(nvg)
    local tb = truckBounds_
    if tb.w <= 0 then return end

    for _, c in ipairs(chibis_) do
        -- 车厢内的子区域都在这里绘制（含战斗时的 gun 区域）
        local zone = ZONES[c.zone]
        if zone and (c.zone == "container" or c.zone == "table"
                  or c.zone == "stove" or c.zone == "bed"
                  or c.zone == "gun") then
            -- 固定姿势区域（table/stove/bed）角色稍小一点更自然
            local sizeRatio = CHIBI_H_RATIO
            if c.zone == "bed" then sizeRatio = CHIBI_H_RATIO * 0.75 end

            local chibiH = tb.h * sizeRatio
            local chibiW = chibiH

            local zoneX = tb.x + zone.x * tb.w
            local zoneY = tb.y + zone.y * tb.h
            local zoneW = zone.w * tb.w
            local zoneH = zone.h * tb.h

            local drawX = zoneX + c.x * zoneW - chibiW / 2
            local drawY = zoneY + zoneH - chibiH

            drawSingleChibi(nvg, c, drawX, drawY, chibiW, chibiH)
        end
    end
end

-- ── 绘制车外纸娃娃（停泊时可在地面活动）─────────────────────
function DrivingSceneWidget:drawOutsideChibis(nvg, l)
    local tb = truckBounds_
    if tb.w <= 0 then return end

    -- 车外角色距镜头更近 → 统一比车上角色大（近大远小）
    local outsideH = tb.h * CHIBI_H_RATIO * 1.2
    local outsideW = outsideH
    local groundY = l.y + l.h * 0.88

    -- 主角在卡车前方地面活动（卡车左侧 + 右侧各留空间）
    local areaX = tb.x - tb.w * 0.15
    local areaW = tb.w * 0.5

    for _, c in ipairs(chibis_) do
        if c.zone == "outside" then
            local drawX = areaX + c.x * areaW - outsideW / 2
            local drawY = groundY - outsideH
            drawSingleChibi(nvg, c, drawX, drawY, outsideW, outsideH)
        end
    end

    -- NPC 路人（以卡车为中心向两侧扩展，覆盖更宽范围）
    local npcAreaX = tb.x - tb.w * 0.25
    local npcAreaW = tb.w * 1.5

    for _, c in ipairs(npcs_) do
        local drawX = npcAreaX + c.x * npcAreaW - outsideW / 2
        local drawY = groundY - outsideH
        drawSingleChibi(nvg, c, drawX, drawY, outsideW, outsideH)
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
    -- 查询本帧点击状态并缓存（供 checkChibiInput 复用）
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
                clickConsumed_ = true
                return
            end
        end
    end
end

-- ============================================================
-- 纸娃娃点击检测
-- ============================================================

--- 检测本帧点击是否命中纸娃娃（主角 + NPC）
local function checkChibiInput()
    if clickConsumed_ then return end
    if not lastLayout_ then return end
    if not framePressed_ then return end

    local baseX = frameMX_
    local baseY = frameMY_
    -- 合并主角和 NPC 到统一列表
    local targets = {}
    for _, c in ipairs(chibis_) do
        table.insert(targets, { chibi = c, isNpc = false })
    end
    for _, c in ipairs(npcs_) do
        table.insert(targets, { chibi = c, isNpc = true })
    end

    for _, entry in ipairs(targets) do
        local c = entry.chibi
        if c._hitW and c._hitW > 0 and c.clickCD <= 0 then
            local pad = 4
            if baseX >= c._hitX - pad and baseX <= c._hitX + c._hitW + pad
               and baseY >= c._hitY - pad and baseY <= c._hitY + c._hitH + pad then
                -- 命中！
                clickConsumed_ = true
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

                -- 回调（用于播放音效）
                if onChibiClick_ then
                    onChibiClick_(c, entry.isNpc)
                end

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
    -- 战斗渲染模块更新（粒子、特效等）
    if combatRenderer_ then
        combatRenderer_.update(dt)
    end
    -- 行驶中才滚动背景（战斗模块可加速滚动）
    if isDriving_ then
        local speedMult = 1.0
        if combatRenderer_ then
            speedMult = combatRenderer_.getSpeedMultiplier()
        end
        scrollOffset_ = scrollOffset_ + dt * SCROLL_SPEED * speedMult
    end
    -- 更新纸娃娃 AI（行驶/停泊都运行）
    updateChibis(dt)
    -- 更新天气粒子位置（使用上次渲染的 widget 尺寸估算）
    if weatherParticlesInited_ and #weatherParticles_ > 0 then
        updateWeatherParticles(dt, 400, 220)  -- 近似尺寸
    end
    -- 重置点击消费标记和帧级按键缓存
    clickConsumed_ = false
    framePressed_ = false
    -- 检测掉落物点击（内部查询 GetMouseButtonPress 并缓存结果）
    checkDropInput()
    -- 检测纸娃娃点击（掉落物优先，未消费才检测纸娃娃）
    checkChibiInput()
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

    -- 更新区域 → 替换中景图片（聚落覆盖优先）
    if env.region and env.region ~= currentEnv_.region then
        currentEnv_.region = env.region
        if not settlementSceneImage_ then
            local newMid = MID_IMAGES[env.region]
            if newMid then
                LAYER_DEFS[3].image = newMid
            end
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

--- 设置纸娃娃点击回调
---@param callback function(chibi, isNpc) 点击纸娃娃时调用
function M.setChibiClickCallback(callback)
    onChibiClick_ = callback
end

--- 设置当前停泊聚落（切换为静态场景图，替代所有视差层）
---@param settlementId string 聚落 id（如 "greenhouse"、"bell_tower"）
function M.setSettlement(settlementId)
    local img = settlementId and SETTLEMENT_SCENE_IMAGES[settlementId] or nil
    if img then
        settlementSceneImage_ = img
        print("[DrivingScene] settlement scene → " .. settlementId)
    end
end

--- 清除聚落场景覆盖，恢复正常视差层渲染
function M.clearSettlement()
    if not settlementSceneImage_ then return end
    settlementSceneImage_ = nil
    print("[DrivingScene] settlement scene cleared → region=" .. tostring(currentEnv_.region))
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

--- 设置行驶/停泊模式
---@param driving boolean
function M.setDriving(driving)
    if isDriving_ == driving then return end
    isDriving_ = driving
    if driving then
        -- 开始行驶：清除 NPC 路人
        clearNPCs()
        -- 确保至少一人在驾驶舱
        local anyInCabin = false
        for _, c in ipairs(chibis_) do
            if c.zone == "cabin" then anyInCabin = true; break end
        end
        if not anyInCabin then
            chibis_[1].zone = "cabin"
            chibis_[1].x = 0.5
            chibis_[1].targetX = 0.5
            chibis_[1].state = "idle"
            chibis_[1].stateTimer = 2
        end
        -- 把 outside 的角色拉回车厢内
        for _, c in ipairs(chibis_) do
            if c.zone == "outside" then
                c.zone = "container"
                c.x = 0.5
                c.targetX = 0.5
                c.state = "idle"
                c.stateTimer = 1
            end
        end
    else
        -- 停车：根据当前聚落生成 NPC 路人
        spawnNPCs()
    end
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
    local function resetChibi(c, zone, x, facing, delay, switchT)
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
    resetChibi(chibis_[1], "cabin",     0.5,  1, 0,   25)
    resetChibi(chibis_[2], "container", 0.3, -1, 1.5, 20)
end

--- 注入战斗渲染模块（由 screen_ambush 在战斗开始时调用）
---@param renderer table  driving_combat 模块
function M.setCombatRenderer(renderer)
    combatRenderer_ = renderer
    -- 陶夏上机枪位
    local taoxia = chibis_[2]
    taoxia._savedZone = taoxia.zone   -- 记住战前区域
    taoxia.zone = "gun"
    taoxia.x = 0.5; taoxia.targetX = 0.5
    taoxia.facing = -1; taoxia.scaleX = -1  -- 面朝左方（面向敌人）
    taoxia.state = "idle"; taoxia.stateTimer = 999
    taoxia.switchTimer = 9999  -- 防止 AI 切换区域
    taoxia.walkTime = 0
end

--- 移除战斗渲染模块（战斗结束时调用）
function M.clearCombatRenderer()
    combatRenderer_ = nil
    -- 陶夏回到战前区域
    local taoxia = chibis_[2]
    local restoreZone = taoxia._savedZone or "container"
    taoxia._savedZone = nil
    taoxia.zone = restoreZone
    taoxia.x = 0.5; taoxia.targetX = 0.5
    taoxia.facing = -1; taoxia.scaleX = -1
    taoxia.state = "idle"; taoxia.stateTimer = 2
    taoxia.switchTimer = 10 + math.random() * 10
end

return M

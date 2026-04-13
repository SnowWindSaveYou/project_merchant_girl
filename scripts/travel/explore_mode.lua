--- 探索模式配置
--- 注册 "explore" 模式到 chibi_scene，定义地面 zone、滚动参数等
---
--- 用法：
---   require("travel/explore_mode")  -- 自动注册，无需保存返回值
---   ChibiScene.setMode("explore")

local ChibiScene = require("travel/chibi_scene")

-- ============================================================
-- 探索模式 zone 定义（归一化坐标，相对 widget 宽高）
-- ============================================================
-- 主角站在画面左侧 1/4，敌人从右侧进入
local EXPLORE_ZONES = {
    ground_left = {
        x = 0.05,  y = 0.55,
        w = 0.25,  h = 0.40,
    },
    ground_center = {
        x = 0.30,  y = 0.55,
        w = 0.30,  h = 0.40,
    },
    ground_right = {
        x = 0.60,  y = 0.55,
        w = 0.30,  h = 0.40,
    },
}

-- ============================================================
-- 注册模式
-- ============================================================
ChibiScene.registerMode("explore", {
    zones        = EXPLORE_ZONES,
    hasVehicle   = false,
    outsideScale = 1.0,
    scrollSpeed  = 8,       -- 缓慢漂移，营造废墟探索氛围
    zoneMap = {
        cabin     = "ground_left",
        table     = "ground_right",
        container = "ground_center",
        stove     = "ground_center",
        bed       = "ground_right",
        gun       = "ground_left",
        radar     = "ground_right",
    },
})

return EXPLORE_ZONES

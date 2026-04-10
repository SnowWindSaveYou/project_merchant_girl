--- UI 主题：末世行商配色方案
--- 设计原则：低对比度 · 米白 / 铁灰 / 锈红 · 末世废土感
local M = {}

-- ============================================================
-- 末世废土调色板
-- ============================================================
M.colors = {
    -- 背景层次（暗灰-铁灰系）
    bg_primary   = { 32, 30, 28, 255 },   -- 深铁灰（主背景）
    bg_secondary = { 42, 40, 37, 255 },   -- 暖灰（次背景/顶栏）
    bg_card      = { 52, 48, 44, 220 },   -- 暖深灰（卡片）
    bg_overlay   = { 15, 14, 12, 180 },   -- 遮罩层

    -- 强调色
    accent     = { 198, 156, 82, 255 },   -- 旧铜金（贸易/货币）
    accent_dim = { 198, 156, 82, 100 },
    danger     = { 188, 72, 52, 255 },     -- 锈红（危险/伤害）
    success    = { 108, 148, 96, 255 },    -- 暗绿（收益/安全）
    info       = { 112, 142, 168, 255 },   -- 灰蓝（信息/导航）
    warning    = { 188, 148, 68, 255 },    -- 暗金（警告）

    -- 文字（低对比度米白系）
    text_primary   = { 215, 208, 195, 255 },  -- 米白
    text_secondary = { 158, 152, 140, 255 },  -- 灰褐
    text_dim       = { 108, 102, 92, 255 },   -- 暗灰
    text_accent    = { 198, 156, 82, 255 },   -- 旧铜金

    -- UI 元素
    border       = { 72, 68, 60, 180 },    -- 暗铁灰边框
    divider      = { 62, 58, 52, 150 },
    progress_bg  = { 48, 44, 40, 255 },
    progress_fill = { 108, 148, 96, 255 }, -- 暗绿

    -- 按钮
    btn_primary  = { 92, 110, 128, 255 },  -- 钢蓝灰
    btn_danger   = { 138, 52, 42, 255 },   -- 暗锈红

    -- 地图专用（亮色背景适配）
    map_bg        = { 28, 26, 24, 255 },   -- 地图底色（被背景图覆盖）
    map_grid      = { 60, 55, 48, 50 },    -- 网格线（淡灰棕）
    map_road      = { 68, 62, 52, 220 },   -- 主干道（深棕灰）
    map_path      = { 88, 80, 68, 180 },   -- 小径（棕灰）
    map_shortcut  = { 148, 48, 38, 200 },  -- 捷径（深锈红）
    map_node      = { 158, 118, 52, 255 }, -- 节点默认（深铜金）
    map_current   = { 68, 128, 58, 255 },  -- 当前位置（深绿）
    map_dest      = { 178, 128, 32, 255 }, -- 订单目标（深金）
    map_unknown   = { 120, 115, 105, 100 },-- 未知节点（灰棕）
    map_fog       = { 180, 170, 155, 160 },-- 迷雾（浅灰棕）

    -- 地图 UI 元素衬底
    map_node_fill     = { 245, 240, 230, 230 },  -- 节点底圆（米白半透明）
    map_label_bg      = { 245, 240, 230, 200 },  -- 标签衬底（米白半透明）
    map_label_text    = { 42, 38, 32, 220 },      -- 标签文字（深棕灰）
    map_edge_label_bg = { 245, 240, 230, 210 },  -- 边标注衬底
    map_legend_bg     = { 245, 240, 230, 220 },  -- 图例衬底

    -- 路线可视化
    map_route_fastest  = { 42, 128, 188, 220 },  -- 深蓝
    map_route_safest   = { 58, 138, 52, 220 },   -- 深绿
    map_route_balanced = { 168, 128, 42, 220 },  -- 深金
    map_route_manual   = { 138, 88, 178, 220 },  -- 深紫
    map_waypoint       = { 138, 88, 178, 255 },  -- 途经点
    map_route_glow     = { 0, 0, 0, 30 },        -- 发光底色（暗色半透明）

    -- 旅行中路线
    map_route_active   = { 32, 148, 128, 230 },  -- 深青绿（剩余路线）
    map_route_done     = { 160, 150, 135, 120 },  -- 灰棕（已走过）
    map_truck          = { 218, 168, 32, 255 },   -- 深金（卡车位置）

    -- 情报图层
    intel_security = { 52, 120, 180, 200 },   -- 蓝色盾牌（安全预警）
    intel_weather  = { 88, 168, 200, 200 },   -- 天蓝（天气预报）
    intel_price    = { 178, 138, 42, 200 },   -- 金色（价格情报）
    intel_tip      = { 200, 68, 48, 220 },    -- 红色（商机情报）
    intel_toggle_bg = { 52, 48, 44, 200 },    -- 按钮背景
    intel_toggle_active = { 82, 148, 108, 220 }, -- 按钮激活
}

M.sizes = {
    font_title  = 22,
    font_large  = 18,
    font_normal = 14,
    font_small  = 12,
    font_tiny   = 10,

    padding       = 16,
    padding_small = 8,
    padding_large = 24,

    radius       = 2,
    radius_small = 1,
    radius_large = 4,

    border = 1,
}

-- 新增：UI 美化扩展
M.colors.text_header  = { 228, 218, 198, 255 }  -- 区块标题（更暖更亮）
M.colors.glow_accent  = { 198, 156, 82, 60 }    -- 强调色辉光（脉冲动效）
M.colors.card_border  = { 78, 72, 64, 140 }     -- 卡片边框（比 border 稍亮，手绘线条感）

-- 手绘线条风格参数（少女终末旅行素描感）
M.sketch = {
    -- 墨色：暖褐粉笔质感，半透明
    ink_color     = { 185, 175, 155, 170 },
    ink_color_dim = { 145, 138, 125, 100 },
    ink_accent    = { 198, 156, 82, 180 },
    ink_danger    = { 188, 92, 72, 160 },
    -- 线条参数
    baseWidth     = 1.4,
    widthVar      = 0.25,
    jitter        = 1.2,
    jitterFullLen = 300,
    jitterMinLen  = 40,
    segments      = 24,
    -- 断裂
    breakChance   = 0.45,
    breakMaxGaps  = 3,
    breakMinLen   = 120,
    breakGapMin   = 2,
    breakGapMax   = 7,
    -- 双层叠线
    layers        = 2,
    layer2Alpha   = 0.35,
    layer2Offset  = 0.5,
    -- 呼吸动画
    breathSpeed   = 0.8,
    breathAmp     = 0.15,
    -- 角落强化
    cornerEmphasis = 1.1,
    cornerLen      = 6,
}

-- 纹理贴图路径（卡片 9-slice 备用）
M.textures = {
    card_slice = { 16, 16, 16, 16 },
}

-- 按钮扁平配色（程序化 UI，无纹理）
M.btn_colors = {
    primary = {
        bg      = { 78, 98, 118, 255 },     -- 钢蓝灰
        pressed = { 58, 78, 98, 255 },
    },
    secondary = {
        bg      = { 62, 58, 52, 255 },      -- 暖灰
        pressed = { 50, 46, 40, 255 },
    },
    danger = {
        bg      = { 128, 52, 42, 255 },     -- 暗锈红
        pressed = { 108, 42, 32, 255 },
    },
    disabled = {
        bg      = { 46, 43, 39, 180 },      -- 禁用灰
    },
}

-- Tab 导航图标路径
M.icons = {
    tab_home   = "image/icon_tab_home.png",
    tab_map    = "image/icon_tab_map.png",
    tab_orders = "image/icon_tab_orders.png",
    tab_cargo  = "image/icon_tab_cargo.png",
    tab_truck  = "image/icon_tab_truck.png",
}

-- UI 音效路径
M.sounds = {
    click      = "audio/sfx/sfx_ui_click.ogg",
    click_soft = "audio/sfx/sfx_ui_click_soft.ogg",
    open       = "audio/sfx/sfx_ui_open.ogg",
    close      = "audio/sfx/sfx_ui_close.ogg",
    error      = "audio/sfx/sfx_ui_error.ogg",
    success    = "audio/sfx/sfx_ui_success.ogg",
    coins      = "audio/sfx/sfx_ui_coins.ogg",
    warning    = "audio/sfx/sfx_ui_warning.ogg",
}

return M

--- UI 主题：末世行商配色方案
--- 设计原则：手绘素描风 · 泛黄旧纸 · 炭笔墨线 · 少女终末旅行感
local M = {}

-- ============================================================
-- 主题切换标记（改为 false 可恢复暗色废土主题）
-- ============================================================
local LIGHT_THEME = false

-- ============================================================
-- 暗色废土调色板（原版）
-- ============================================================
local DARK = {}
DARK.colors = {
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

    -- 地图专用
    map_bg        = { 28, 26, 24, 255 },
    map_grid      = { 60, 55, 48, 50 },
    map_road      = { 68, 62, 52, 220 },
    map_path      = { 88, 80, 68, 180 },
    map_shortcut  = { 148, 48, 38, 200 },
    map_node      = { 158, 118, 52, 255 },
    map_current   = { 68, 128, 58, 255 },
    map_dest      = { 178, 128, 32, 255 },
    map_unknown   = { 120, 115, 105, 100 },
    map_fog       = { 180, 170, 155, 160 },
    map_node_fill     = { 245, 240, 230, 230 },
    map_label_bg      = { 245, 240, 230, 200 },
    map_label_text    = { 42, 38, 32, 220 },
    map_edge_label_bg = { 245, 240, 230, 210 },
    map_legend_bg     = { 245, 240, 230, 220 },
    map_route_fastest  = { 42, 128, 188, 220 },
    map_route_safest   = { 58, 138, 52, 220 },
    map_route_balanced = { 168, 128, 42, 220 },
    map_route_manual   = { 138, 88, 178, 220 },
    map_waypoint       = { 138, 88, 178, 255 },
    map_route_glow     = { 0, 0, 0, 30 },
    map_route_active   = { 32, 148, 128, 230 },
    map_route_done     = { 160, 150, 135, 120 },
    map_truck          = { 218, 168, 32, 255 },
    intel_security     = { 52, 120, 180, 200 },
    intel_weather      = { 88, 168, 200, 200 },
    intel_price        = { 178, 138, 42, 200 },
    intel_tip          = { 200, 68, 48, 220 },
    intel_toggle_bg    = { 52, 48, 44, 200 },
    intel_toggle_active = { 82, 148, 108, 220 },

    -- 对话系统
    dialogue_bg      = { 15, 13, 10, 180 },    -- 对话框底色（半透明）
    dialogue_text    = { 225, 220, 210, 255 },  -- 对话正文
    dialogue_topbar  = { 22, 19, 16, 120 },     -- 对话顶栏
    dialogue_title   = { 200, 180, 140, 200 },  -- 对话顶栏标题
    dialogue_info    = { 150, 140, 120, 180 },  -- 对话顶栏副信息
    dialogue_root    = { 18, 15, 12, 255 },     -- 对话全屏根底色
    dialogue_dim     = { 80, 80, 80, 160 },     -- 立绘暗化色
    history_bubble_text = { 220, 215, 208, 255 }, -- LOG 气泡文字

    -- 收音机
    radio_on_bg     = { 28, 36, 28, 230 },      -- 收音机开启背景
    radio_off_bg    = { 36, 36, 36, 180 },       -- 收音机关闭背景
    radio_on_border = { 60, 100, 60, 120 },      -- 收音机开启边线
    radio_off_border = { 50, 50, 50, 100 },      -- 收音机关闭边线

    -- 行驶中
    travel_strip_bg     = { 22, 36, 48, 240 },   -- 行驶进度条底色
    travel_strip_border = { 50, 80, 100, 120 },   -- 行驶进度条边线
    chatter_bubble_bg   = { 32, 38, 48, 230 },    -- 车内闲聊气泡底色

    -- 首页
    home_overlay       = { 0, 0, 0, 140 },        -- 据点信息面板半透明底
    home_title         = { 255, 255, 255, 230 },   -- 据点名（叠在CG上）
    home_desc          = { 255, 255, 255, 160 },   -- 据点描述
    home_label_dim     = { 255, 255, 255, 120 },   -- 据点类型标签
    home_float_btn_bg  = { 30, 34, 40, 200 },      -- 悬浮按钮底色
    home_root_fallback = { 16, 18, 20, 255 },      -- 首页根背景（无CG时）
    home_lower_tint    = { 16, 18, 20, 200 },      -- 下方按钮区底色
    home_gradient_mid  = { 0, 0, 0, 60 },           -- 渐变遮罩中段
    home_gradient_bot  = { 16, 18, 20, 140 },       -- 渐变遮罩底部
    home_popup_overlay = { 0, 0, 0, 160 },           -- 弹窗遮罩
    home_travel_tint   = { 28, 42, 58, 240 },        -- 行驶进度卡底色
    home_backlog_danger  = { 72, 28, 28, 220 },      -- 积压警告（严重）
    home_backlog_warning = { 64, 54, 20, 220 },      -- 积压警告（普通）

    -- 扩展
    text_header  = { 228, 218, 198, 255 },
    glow_accent  = { 198, 156, 82, 60 },
    card_border  = { 78, 72, 64, 140 },
}
DARK.sketch = {
    ink_color     = { 185, 175, 155, 170 },
    ink_color_dim = { 145, 138, 125, 100 },
    ink_accent    = { 198, 156, 82, 180 },
    ink_danger    = { 188, 92, 72, 160 },
    baseWidth     = 1.4,
    widthVar      = 0.25,
    jitter        = 1.2,
    jitterFullLen = 300,
    jitterMinLen  = 40,
    segments      = 24,
    breakChance   = 0.45,
    breakMaxGaps  = 3,
    breakMinLen   = 120,
    breakGapMin   = 2,
    breakGapMax   = 7,
    layers        = 2,
    layer2Alpha   = 0.35,
    layer2Offset  = 0.5,
    breathSpeed   = 0.8,
    breathAmp     = 0.15,
    cornerEmphasis = 1.1,
    cornerLen      = 6,
}
DARK.btn_colors = {
    primary = {
        bg      = { 78, 98, 118, 255 },
        pressed = { 58, 78, 98, 255 },
    },
    secondary = {
        bg      = { 62, 58, 52, 255 },
        pressed = { 50, 46, 40, 255 },
    },
    danger = {
        bg      = { 128, 52, 42, 255 },
        pressed = { 108, 42, 32, 255 },
    },
    disabled = {
        bg      = { 46, 43, 39, 180 },
    },
}

-- ============================================================
-- 淡色手绘主题（泛黄旧纸 + 炭笔素描）
-- 设计参考：
--   纸底：自然日照下的牛皮纸/速写本纸张，偏暖米黄
--   墨线：2B-4B 铅笔的炭灰色，有深浅变化
--   着色：水彩淡涂般的低饱和暖色，不抢墨线视觉
-- ============================================================
local LIGHT = {}
LIGHT.colors = {
    -- 背景层次（旧纸色系：从浅牛皮纸到泛黄速写纸）
    bg_primary   = { 235, 228, 215, 255 },   -- 速写本纸白（主背景）
    bg_secondary = { 225, 218, 202, 255 },   -- 微黄牛皮纸（次背景/分区）
    bg_card      = { 242, 236, 224, 235 },   -- 干净纸面（卡片）
    bg_overlay   = { 210, 200, 185, 160 },   -- 半透明旧纸遮罩

    -- 强调色（在浅底上需加深以保持对比度）
    accent     = { 158, 118, 48, 255 },    -- 深铜褐（贸易/货币）
    accent_dim = { 158, 118, 48, 80 },
    danger     = { 168, 58, 42, 255 },      -- 砖红（危险/伤害）
    success    = { 72, 118, 62, 255 },      -- 橄榄绿（收益/安全）
    info       = { 68, 108, 148, 255 },     -- 靛蓝（信息/导航）
    warning    = { 172, 128, 38, 255 },     -- 赭黄（警告）

    -- 文字（炭灰系，低纯黑感，保持手绘温度）
    text_primary   = { 52, 48, 42, 255 },     -- 炭灰（主文字）
    text_secondary = { 98, 92, 82, 255 },     -- 中灰褐（次文字）
    text_dim       = { 148, 140, 128, 255 },  -- 淡灰（辅助/禁用）
    text_accent    = { 158, 118, 48, 255 },   -- 深铜褐

    -- UI 元素
    border       = { 178, 168, 152, 150 },   -- 铅笔淡灰
    divider      = { 192, 182, 168, 120 },
    progress_bg  = { 215, 208, 195, 255 },   -- 浅纸色
    progress_fill = { 72, 118, 62, 255 },    -- 橄榄绿

    -- 按钮
    btn_primary  = { 88, 112, 138, 255 },    -- 蓝灰墨水
    btn_danger   = { 158, 52, 38, 255 },     -- 砖红

    -- 地图专用（浅底自然适配，微调即可）
    map_bg        = { 235, 228, 215, 255 },
    map_grid      = { 192, 182, 168, 60 },
    map_road      = { 128, 118, 102, 200 },
    map_path      = { 152, 142, 128, 160 },
    map_shortcut  = { 168, 58, 42, 180 },
    map_node      = { 138, 102, 42, 255 },
    map_current   = { 58, 118, 52, 255 },
    map_dest      = { 168, 118, 28, 255 },
    map_unknown   = { 178, 170, 158, 120 },
    map_fog       = { 220, 212, 198, 180 },
    map_node_fill     = { 252, 248, 240, 230 },
    map_label_bg      = { 248, 242, 232, 210 },
    map_label_text    = { 52, 48, 42, 220 },
    map_edge_label_bg = { 248, 242, 232, 210 },
    map_legend_bg     = { 245, 240, 228, 230 },
    map_route_fastest  = { 42, 118, 178, 200 },
    map_route_safest   = { 52, 128, 48, 200 },
    map_route_balanced = { 158, 118, 38, 200 },
    map_route_manual   = { 128, 78, 168, 200 },
    map_waypoint       = { 128, 78, 168, 255 },
    map_route_glow     = { 255, 255, 255, 40 },
    map_route_active   = { 28, 138, 118, 210 },
    map_route_done     = { 188, 178, 165, 120 },
    map_truck          = { 198, 148, 28, 255 },
    intel_security     = { 48, 108, 168, 200 },
    intel_weather      = { 78, 148, 185, 200 },
    intel_price        = { 168, 128, 38, 200 },
    intel_tip          = { 188, 62, 42, 200 },
    intel_toggle_bg    = { 225, 218, 202, 220 },
    intel_toggle_active = { 72, 138, 98, 200 },

    -- 对话系统（淡色：旧纸底 + 炭笔文字）
    dialogue_bg      = { 235, 228, 215, 200 },    -- 对话框底色（半透明旧纸）
    dialogue_text    = { 52, 48, 42, 255 },        -- 对话正文（炭灰）
    dialogue_topbar  = { 225, 218, 202, 160 },     -- 对话顶栏
    dialogue_title   = { 98, 82, 52, 220 },        -- 对话顶栏标题（深褐）
    dialogue_info    = { 128, 118, 102, 200 },     -- 对话顶栏副信息
    dialogue_root    = { 235, 228, 215, 255 },     -- 对话全屏根底色
    dialogue_dim     = { 180, 175, 168, 140 },     -- 立绘暗化色（浅底温和灰）
    history_bubble_text = { 52, 48, 42, 255 },     -- LOG 气泡文字

    -- 收音机（淡绿纸底 / 灰纸底）
    radio_on_bg     = { 222, 232, 218, 230 },      -- 淡绿旧纸
    radio_off_bg    = { 225, 220, 210, 180 },       -- 灰纸
    radio_on_border = { 128, 168, 128, 120 },       -- 淡绿边线
    radio_off_border = { 192, 185, 172, 100 },      -- 灰纸边线

    -- 行驶中（淡蓝旧纸底）
    travel_strip_bg     = { 215, 225, 235, 240 },   -- 淡蓝纸底
    travel_strip_border = { 148, 172, 195, 120 },    -- 蓝灰边线
    chatter_bubble_bg   = { 228, 232, 238, 230 },    -- 浅蓝灰纸底

    -- 首页（叠在CG上的半透明层）
    home_overlay       = { 235, 228, 215, 180 },     -- 旧纸半透明底
    home_title         = { 42, 38, 32, 230 },         -- 据点名（深炭色）
    home_desc          = { 62, 58, 48, 180 },          -- 据点描述
    home_label_dim     = { 98, 92, 82, 160 },          -- 据点类型标签
    home_float_btn_bg  = { 242, 236, 224, 220 },       -- 悬浮按钮底色（纸面）
    home_root_fallback = { 242, 236, 224, 255 },       -- 首页根背景（无CG时）
    home_lower_tint    = { 235, 228, 215, 200 },       -- 下方按钮区底色
    home_gradient_mid  = { 235, 228, 215, 60 },         -- 渐变遮罩中段
    home_gradient_bot  = { 235, 228, 215, 160 },        -- 渐变遮罩底部
    home_popup_overlay = { 62, 58, 48, 140 },            -- 弹窗遮罩
    home_travel_tint   = { 215, 225, 235, 240 },         -- 行驶进度卡底色
    home_backlog_danger  = { 220, 180, 178, 220 },       -- 积压警告（严重）
    home_backlog_warning = { 225, 215, 178, 220 },       -- 积压警告（普通）

    -- 扩展
    text_header  = { 42, 38, 32, 255 },
    glow_accent  = { 158, 118, 48, 50 },
    card_border  = { 168, 158, 142, 120 },
}
LIGHT.sketch = {
    -- 炭笔墨色：深灰棕，在浅纸上清晰但不刺眼
    ink_color     = { 82, 75, 65, 185 },
    ink_color_dim = { 118, 110, 98, 120 },
    ink_accent    = { 148, 108, 42, 195 },
    ink_danger    = { 168, 68, 48, 175 },
    -- 线条参数（同暗色，略微加粗以在浅底上更明显）
    baseWidth     = 1.5,
    widthVar      = 0.28,
    jitter        = 1.2,
    jitterFullLen = 300,
    jitterMinLen  = 40,
    segments      = 24,
    breakChance   = 0.45,
    breakMaxGaps  = 3,
    breakMinLen   = 120,
    breakGapMin   = 2,
    breakGapMax   = 7,
    layers        = 2,
    layer2Alpha   = 0.30,
    layer2Offset  = 0.6,
    breathSpeed   = 0.8,
    breathAmp     = 0.15,
    cornerEmphasis = 1.15,
    cornerLen      = 6,
}
LIGHT.btn_colors = {
    primary = {
        bg      = { 82, 105, 132, 255 },    -- 蓝灰墨水
        pressed = { 62, 85, 112, 255 },
    },
    secondary = {
        bg      = { 205, 198, 185, 255 },   -- 暖灰纸色
        pressed = { 188, 180, 168, 255 },
    },
    danger = {
        bg      = { 158, 52, 38, 255 },     -- 砖红
        pressed = { 138, 42, 28, 255 },
    },
    disabled = {
        bg      = { 215, 208, 198, 180 },   -- 浅纸灰
    },
}

-- ============================================================
-- 根据标记选择主题
-- ============================================================
local chosen = LIGHT_THEME and LIGHT or DARK

M.colors = chosen.colors
M.sketch = chosen.sketch
M.btn_colors = chosen.btn_colors

-- ============================================================
-- 尺寸（与主题无关，两套共用）
-- ============================================================
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

-- ============================================================
-- 纹理贴图路径（卡片 9-slice 备用）
-- ============================================================
M.textures = {
    card_slice = { 16, 16, 16, 16 },
}

-- ============================================================
-- 角色头像（气泡对话共用，教程 / chatter / 引导等场景复用）
-- ============================================================
M.avatars = {
    linli  = "image/linli_avatar.png",
    taoxia = "image/taoxia_avatar.png",
}

-- ============================================================
-- Tab 导航图标路径
-- ============================================================
M.icons = {
    tab_home   = "image/icon_tab_home.png",
    tab_map    = "image/icon_tab_map.png",
    tab_orders = "image/icon_tab_orders.png",
    tab_cargo  = "image/icon_tab_cargo.png",
    tab_truck  = "image/icon_tab_truck.png",
}

-- ============================================================
-- UI 音效路径
-- ============================================================
M.sounds = {
    click      = "audio/sfx_ui_click.ogg",
    click_soft = "audio/sfx_ui_click_soft.ogg",
    open       = "audio/sfx_ui_open.ogg",
    close      = "audio/sfx_ui_close.ogg",
    error      = "audio/sfx_ui_error.ogg",
    success    = "audio/sfx_ui_success.ogg",
    coins      = "audio/sfx_ui_coins.ogg",
    warning    = "audio/sfx_ui_warning.ogg",
    depart     = "audio/sfx_ui_depart.ogg",
    event      = "audio/sfx_ui_event.ogg",
    bubble_pop = "audio/sfx/sfx_ui_bubble_pop.ogg",
    pickup     = "audio/sfx/sfx_pickup_item.ogg",
    combat_accelerate = "audio/sfx/sfx_combat_accelerate.ogg",
    combat_gunfire    = "audio/sfx/sfx_combat_gunfire.ogg",
    combat_evade      = "audio/sfx/sfx_combat_evade.ogg",
    combat_smoke      = "audio/sfx/sfx_combat_smoke.ogg",
}

-- ============================================================
-- BGM 路径（循环播放的背景音乐）
-- ============================================================
M.bgm = {
    bgm_travel     = "audio/bgm_travel.ogg",
    bgm_settlement = "audio/bgm_settlement.ogg",
    bgm_campfire   = "audio/bgm_campfire.ogg",
    bgm_combat     = "audio/bgm_combat.ogg",
}

-- ============================================================
-- 环境音层路径（循环播放的氛围音效）
-- ============================================================
M.ambient = {
    engine       = "audio/sfx/amb_engine_loop.ogg",
    wind         = "audio/sfx/amb_wind_loop.ogg",
    settlement   = "audio/sfx/amb_settlement_general.ogg",
    campfire     = "audio/sfx/amb_campfire.ogg",
    radio_static = "audio/sfx/amb_radio_static.ogg",
    radio_voice  = "audio/sfx/amb_radio_voice.ogg",
}

return M

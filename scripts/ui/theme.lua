--- UI 主题：末世行商配色方案
--- 设计原则：手绘素描风 · 泛黄旧纸 · 炭笔墨线 · 少女终末旅行感
local M = {}

-- ============================================================
-- 主题切换标记
--   "dark"       → 暗色废土（原版）
--   "light"      → 淡色手绘（旧纸）
--   "watercolor" → 废土水彩（暖沙漠调）
--   "concrete"   → 混凝土废墟（冷灰蓝 · 军绿 · 高架桥下）
-- ============================================================
local ACTIVE_THEME = "concrete"

-- 兼容旧标记（如果其他地方引用了 LIGHT_THEME，保留语义）
local LIGHT_THEME = (ACTIVE_THEME == "light")

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
    chatter_linli_name  = { 80, 140, 200, 255 },   -- 闲聊：林砾名字色
    chatter_taoxia_name = { 200, 130, 80, 255 },    -- 闲聊：陶夏名字色

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

    -- 语义色（全局统一管理）
    radio_wave            = { 80, 170, 90, 255 },      -- 收音机波形
    float_gain            = { 120, 220, 140, 255 },     -- 飘字：获得
    float_loss            = { 255, 150, 100, 255 },     -- 飘字：消耗
    dialogue_linli_accent = { 142, 178, 210, 255 },     -- 林砾名字色
    dialogue_linli_bg     = { 42, 52, 58, 240 },        -- 林砾对话底色
    dialogue_taoxia_bg    = { 58, 48, 36, 240 },        -- 陶夏对话底色
    bg_inset              = { 30, 32, 28, 200 },        -- 卡片内嵌面板
    bg_intel_hint         = { 32, 40, 54, 220 },        -- 情报说明面板（蓝调）
    bg_intel_active       = { 28, 42, 38, 220 },        -- 已激活情报（绿调）
    border_rare           = { 168, 128, 82, 120 },      -- 稀有物品边框（金）
    bg_error              = { 60, 30, 30, 200 },        -- 错误/危险面板（红调）
    sketch_glow           = { 240, 220, 170 },          -- 素描边框辉光
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
    chatter_linli_name  = { 42, 98, 165, 255 },      -- 闲聊：林砾名字色（深蓝）
    chatter_taoxia_name = { 168, 95, 38, 255 },       -- 闲聊：陶夏名字色（深橙）

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

    -- 语义色
    radio_wave            = { 52, 138, 68, 255 },
    float_gain            = { 52, 148, 68, 255 },
    float_loss            = { 195, 82, 52, 255 },
    dialogue_linli_accent = { 58, 108, 158, 255 },
    dialogue_linli_bg     = { 215, 225, 235, 240 },
    dialogue_taoxia_bg    = { 235, 225, 212, 240 },
    bg_inset              = { 218, 212, 198, 200 },
    bg_intel_hint         = { 212, 222, 238, 220 },
    bg_intel_active       = { 215, 232, 222, 220 },
    border_rare           = { 158, 118, 48, 120 },
    bg_error              = { 238, 212, 210, 200 },
    sketch_glow           = { 178, 148, 82 },
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
-- 废土水彩调色板（从概念图取色：暖沙漠 · 锈褐卡车 · 水彩天空）
-- 整体比 DARK 更暖更柔，比 LIGHT 更沉稳
-- 回退方式：将 ACTIVE_THEME 改为 "dark" 或 "light"
-- ============================================================
local WATERCOLOR = {}
WATERCOLOR.colors = {
    -- 背景层次（沙漠暖褐系 —— 取自天空/地面/远景）
    bg_primary   = { 48, 42, 36, 255 },    -- 深暖褐（主背景，取自地面阴影）
    bg_secondary = { 58, 50, 42, 255 },    -- 暖棕灰（次背景，取自废墟暗部）
    bg_card      = { 68, 58, 48, 220 },    -- 暖土褐（卡片，取自卡车车身暗部）
    bg_overlay   = { 32, 28, 22, 180 },    -- 深褐遮罩

    -- 强调色（取自卡车内饰/太阳花/锈迹）
    accent     = { 215, 175, 95, 255 },    -- 沙金色（太阳花/暖光提取）
    accent_dim = { 215, 175, 95, 90 },
    danger     = { 172, 82, 58, 255 },     -- 赭红（锈迹/砖墙提取）
    success    = { 98, 128, 78, 255 },     -- 灰橄榄绿（远景植被）
    info       = { 132, 158, 178, 255 },   -- 天空灰蓝（云层远景）
    warning    = { 195, 152, 72, 255 },    -- 暖铜金（锈迹金属）

    -- 文字（奶白-沙灰系，取自云朵/天空高光）
    text_primary   = { 232, 222, 205, 255 },  -- 奶白（云朵色）
    text_secondary = { 178, 165, 145, 255 },  -- 沙灰（远景建筑）
    text_dim       = { 118, 108, 92, 255 },   -- 暖灰（地面灰调）
    text_accent    = { 215, 175, 95, 255 },   -- 沙金

    -- UI 元素
    border       = { 88, 78, 65, 170 },    -- 暖棕边框（卡车木纹）
    divider      = { 75, 65, 52, 140 },
    progress_bg  = { 55, 48, 40, 255 },
    progress_fill = { 98, 128, 78, 255 },  -- 橄榄绿

    -- 按钮（取自卡车车身/天空色调）
    btn_primary  = { 108, 105, 88, 255 },  -- 橄榄灰绿（卡车车身）
    btn_danger   = { 148, 62, 45, 255 },   -- 深赭红

    -- 地图专用（沙漠地图质感）
    map_bg        = { 42, 38, 32, 255 },
    map_grid      = { 72, 65, 52, 50 },
    map_road      = { 88, 78, 62, 220 },
    map_path      = { 108, 95, 75, 180 },
    map_shortcut  = { 162, 58, 42, 200 },
    map_node      = { 178, 138, 68, 255 },
    map_current   = { 82, 128, 65, 255 },
    map_dest      = { 205, 155, 45, 255 },
    map_unknown   = { 132, 122, 108, 100 },
    map_fog       = { 195, 182, 162, 155 },
    map_node_fill     = { 242, 235, 222, 225 },
    map_label_bg      = { 242, 235, 222, 200 },
    map_label_text    = { 52, 45, 35, 220 },
    map_edge_label_bg = { 242, 235, 222, 210 },
    map_legend_bg     = { 240, 232, 218, 220 },
    map_route_fastest  = { 72, 138, 192, 215 },
    map_route_safest   = { 68, 138, 58, 215 },
    map_route_balanced = { 185, 142, 52, 215 },
    map_route_manual   = { 148, 98, 172, 215 },
    map_waypoint       = { 148, 98, 172, 255 },
    map_route_glow     = { 0, 0, 0, 25 },
    map_route_active   = { 42, 152, 128, 225 },
    map_route_done     = { 168, 155, 138, 115 },
    map_truck          = { 225, 185, 55, 255 },
    intel_security     = { 62, 128, 182, 200 },
    intel_weather      = { 108, 168, 195, 200 },
    intel_price        = { 195, 152, 52, 200 },
    intel_tip          = { 195, 72, 52, 215 },
    intel_toggle_bg    = { 62, 55, 45, 200 },
    intel_toggle_active = { 88, 148, 105, 215 },

    -- 对话系统（暖褐半透明底）
    dialogue_bg      = { 28, 24, 18, 175 },    -- 深暖褐半透明
    dialogue_text    = { 235, 228, 215, 255 },  -- 暖白
    dialogue_topbar  = { 35, 30, 24, 120 },     -- 深褐顶栏
    dialogue_title   = { 215, 192, 148, 200 },  -- 沙金标题
    dialogue_info    = { 162, 148, 125, 180 },  -- 暖灰副信息
    dialogue_root    = { 32, 28, 22, 255 },     -- 深暖褐根底
    dialogue_dim     = { 85, 78, 68, 155 },     -- 暗化色
    history_bubble_text = { 228, 222, 212, 255 },

    -- 收音机（暖绿/暖灰底）
    radio_on_bg     = { 38, 42, 35, 225 },
    radio_off_bg    = { 45, 42, 38, 175 },
    radio_on_border = { 72, 108, 65, 115 },
    radio_off_border = { 62, 58, 52, 95 },

    -- 行驶中（沙漠天空色调）
    travel_strip_bg     = { 38, 45, 55, 235 },
    travel_strip_border = { 68, 92, 115, 115 },
    chatter_bubble_bg   = { 45, 48, 55, 225 },
    chatter_linli_name  = { 85, 148, 208, 255 },   -- 闲聊：林砾名字色（暖蓝）
    chatter_taoxia_name = { 205, 138, 85, 255 },    -- 闲聊：陶夏名字色（暖橙）

    -- 首页（概念图整体色调）
    home_overlay       = { 0, 0, 0, 130 },
    home_title         = { 248, 242, 228, 230 },   -- 暖白标题
    home_desc          = { 232, 222, 205, 160 },
    home_label_dim     = { 215, 205, 188, 120 },
    home_float_btn_bg  = { 48, 42, 36, 195 },
    home_root_fallback = { 35, 30, 25, 255 },
    home_lower_tint    = { 35, 30, 25, 195 },
    home_gradient_mid  = { 0, 0, 0, 55 },
    home_gradient_bot  = { 35, 30, 25, 135 },
    home_popup_overlay = { 0, 0, 0, 155 },
    home_travel_tint   = { 42, 48, 58, 235 },
    home_backlog_danger  = { 82, 35, 28, 215 },
    home_backlog_warning = { 75, 62, 28, 215 },

    -- 扩展
    text_header  = { 238, 228, 208, 255 },
    glow_accent  = { 215, 175, 95, 55 },
    card_border  = { 95, 82, 65, 135 },

    -- 语义色
    radio_wave            = { 88, 158, 82, 255 },
    float_gain            = { 108, 205, 125, 255 },
    float_loss            = { 235, 138, 88, 255 },
    dialogue_linli_accent = { 132, 172, 205, 255 },
    dialogue_linli_bg     = { 38, 48, 55, 238 },
    dialogue_taoxia_bg    = { 55, 45, 32, 238 },
    bg_inset              = { 42, 40, 35, 195 },
    bg_intel_hint         = { 38, 48, 62, 218 },
    bg_intel_active       = { 35, 50, 42, 218 },
    border_rare           = { 195, 152, 72, 118 },
    bg_error              = { 72, 35, 28, 198 },
    sketch_glow           = { 235, 212, 155 },
}
WATERCOLOR.sketch = {
    -- 墨线偏暖棕，比 DARK 的冷灰更贴合水彩画感
    ink_color     = { 172, 155, 128, 165 },
    ink_color_dim = { 138, 125, 105, 95 },
    ink_accent    = { 205, 165, 82, 175 },
    ink_danger    = { 172, 85, 62, 155 },
    baseWidth     = 1.4,
    widthVar      = 0.28,
    jitter        = 1.3,
    jitterFullLen = 300,
    jitterMinLen  = 40,
    segments      = 24,
    breakChance   = 0.48,
    breakMaxGaps  = 3,
    breakMinLen   = 120,
    breakGapMin   = 2,
    breakGapMax   = 7,
    layers        = 2,
    layer2Alpha   = 0.32,
    layer2Offset  = 0.5,
    breathSpeed   = 0.75,
    breathAmp     = 0.16,
    cornerEmphasis = 1.12,
    cornerLen      = 6,
}
WATERCOLOR.btn_colors = {
    primary = {
        bg      = { 98, 95, 78, 255 },     -- 橄榄灰绿
        pressed = { 78, 75, 62, 255 },
    },
    secondary = {
        bg      = { 72, 65, 55, 255 },     -- 暖深褐
        pressed = { 58, 52, 42, 255 },
    },
    danger = {
        bg      = { 148, 58, 42, 255 },    -- 赭红
        pressed = { 125, 48, 35, 255 },
    },
    disabled = {
        bg      = { 55, 50, 42, 175 },
    },
}

-- ============================================================
-- 混凝土废墟调色板（从高架桥场景取色：冷灰蓝 · 军绿 · 钢铁锈棕）
-- 整体冷调工业感，比 DARK 更偏蓝灰，比 WATERCOLOR 更冷
-- 回退方式：将 ACTIVE_THEME 改为 "dark" / "watercolor" / "light"
-- ============================================================
local CONCRETE = {}
CONCRETE.colors = {
    -- 背景层次（全透明，由 shellRoot 羊皮纸纹理统一承载底色）
    bg_primary   = { 0, 0, 0, 0 },        -- 透明（shellRoot 纹理透出）
    bg_secondary = { 0, 0, 0, 0 },        -- 透明
    bg_card      = { 0, 0, 0, 0 },        -- 透明（卡片仅保留描边框）
    bg_overlay   = { 120, 105, 80, 120 },   -- 暖褐半透明遮罩（弹窗用）

    -- 强调色（锈棕 + 军绿 + 天空蓝）
    accent     = { 178, 142, 82, 255 },    -- 锈铜棕（钢筋锈迹/栏杆）
    accent_dim = { 178, 142, 82, 88 },
    danger     = { 175, 68, 55, 255 },     -- 铁锈红（警示/腐蚀）
    success    = { 78, 108, 62, 255 },     -- 军装橄榄绿（角色服装）
    info       = { 118, 165, 205, 255 },   -- 天空蓝（云层间隙）
    warning    = { 185, 148, 65, 255 },    -- 暗锈金

    -- 文字（黑色系，搭配羊皮纸贴图底）
    text_primary   = { 35, 32, 28, 255 },     -- 近黑（主文字）
    text_secondary = { 68, 65, 60, 255 },     -- 深灰（次文字）
    text_dim       = { 120, 118, 115, 255 },  -- 中灰（辅助/禁用）
    text_accent    = { 158, 118, 48, 255 },   -- 深铜褐（强调）

    -- UI 元素（牛皮纸底适配）
    border       = { 145, 132, 110, 160 },   -- 暖褐边线（铅笔色）
    divider      = { 165, 152, 130, 120 },   -- 淡暖褐分割线
    progress_bg  = { 185, 175, 155, 140 },   -- 浅旧纸色（进度条底）
    progress_fill = { 78, 108, 62, 255 },    -- 橄榄绿（保持）

    -- 按钮（牛皮纸上可见的暖色调）
    btn_primary  = { 108, 95, 68, 255 },     -- 暖棕褐（皮革色）
    btn_danger   = { 168, 62, 48, 255 },     -- 砖锈红

    -- 地图专用（冷调废墟地图）
    map_bg        = { 35, 37, 40, 255 },
    map_grid      = { 65, 63, 58, 48 },
    map_road      = { 78, 76, 70, 218 },
    map_path      = { 98, 95, 88, 178 },
    map_shortcut  = { 165, 55, 42, 198 },
    map_node      = { 168, 132, 72, 255 },
    map_current   = { 72, 118, 58, 255 },
    map_dest      = { 195, 155, 48, 255 },
    map_unknown   = { 125, 122, 115, 98 },
    map_fog       = { 178, 175, 168, 148 },
    map_node_fill     = { 238, 238, 235, 222 },
    map_label_bg      = { 238, 238, 235, 198 },
    map_label_text    = { 42, 42, 40, 218 },
    map_edge_label_bg = { 238, 238, 235, 208 },
    map_legend_bg     = { 235, 235, 232, 218 },
    map_route_fastest  = { 82, 148, 198, 212 },
    map_route_safest   = { 62, 132, 55, 212 },
    map_route_balanced = { 178, 138, 48, 212 },
    map_route_manual   = { 142, 92, 168, 212 },
    map_waypoint       = { 142, 92, 168, 255 },
    map_route_glow     = { 0, 0, 0, 28 },
    map_route_active   = { 38, 148, 132, 222 },
    map_route_done     = { 155, 152, 142, 112 },
    map_truck          = { 215, 178, 48, 255 },
    intel_security     = { 58, 125, 178, 198 },
    intel_weather      = { 98, 162, 198, 198 },
    intel_price        = { 185, 148, 48, 198 },
    intel_tip          = { 188, 68, 48, 212 },
    intel_toggle_bg    = { 195, 185, 165, 180 },   -- 旧纸色
    intel_toggle_active = { 82, 138, 98, 212 },

    -- 对话系统（暖色羊皮纸适配）
    dialogue_bg      = { 235, 225, 205, 210 },  -- 暖纸半透明
    dialogue_text    = { 45, 40, 32, 255 },     -- 深褐（亮底可读）
    dialogue_topbar  = { 215, 205, 185, 160 },  -- 暖纸顶栏
    dialogue_title   = { 140, 105, 55, 230 },   -- 深铜褐标题
    dialogue_info    = { 120, 110, 90, 200 },   -- 暖灰副信息
    dialogue_root    = { 225, 215, 195, 255 },  -- 暖纸不透明根底
    dialogue_dim     = { 185, 175, 158, 140 },  -- 暖色柔和暗化
    history_bubble_text = { 55, 48, 38, 255 },  -- 深褐气泡文字

    -- 收音机（牛皮纸底 · 透明融入）
    radio_on_bg     = { 0, 0, 0, 0 },              -- 透明
    radio_off_bg    = { 0, 0, 0, 0 },              -- 透明
    radio_on_border = { 78, 118, 72, 120 },         -- 淡绿线
    radio_off_border = { 155, 142, 120, 100 },      -- 暖灰线

    -- 行驶中（牛皮纸底 · 半透明暖色调）
    travel_strip_bg     = { 180, 168, 145, 200 },   -- 旧纸底
    travel_strip_border = { 145, 130, 108, 120 },    -- 暖褐边
    chatter_bubble_bg   = { 195, 185, 165, 220 },   -- 浅旧纸泡
    chatter_linli_name  = { 42, 98, 158, 255 },     -- 闲聊：林砾名字色（深蓝）
    chatter_taoxia_name = { 168, 98, 42, 255 },      -- 闲聊：陶夏名字色（深橙）

    -- 首页（牛皮纸底适配）
    home_overlay       = { 245, 238, 220, 160 },      -- 暖白半透明（亮色主题适配）
    home_title         = { 55, 48, 38, 240 },          -- CG 上深褐字（亮底适配）
    home_desc          = { 85, 75, 60, 200 },           -- CG 上描述（深暖灰）
    home_label_dim     = { 120, 110, 95, 180 },         -- CG 上标签（中灰暖色）
    home_float_btn_bg  = { 205, 195, 175, 210 },      -- 旧纸色浮钮
    home_root_fallback = { 215, 205, 185, 255 },       -- 牛皮纸色 fallback
    home_lower_tint    = { 0, 0, 0, 0 },               -- 透明（纹理穿透）
    home_gradient_mid  = { 200, 190, 170, 60 },         -- 牛皮纸渐变中
    home_gradient_bot  = { 195, 185, 165, 140 },        -- 牛皮纸渐变底
    home_popup_overlay = { 120, 105, 80, 120 },          -- 暖褐弹窗遮罩
    home_travel_tint   = { 190, 180, 160, 210 },        -- 旧纸色行驶卡
    home_backlog_danger  = { 210, 160, 150, 210 },      -- 旧纸+锈红调
    home_backlog_warning = { 210, 200, 160, 210 },      -- 旧纸+暗金调

    -- 扩展
    text_header  = { 35, 32, 28, 255 },      -- 近黑（标题）
    glow_accent  = { 178, 142, 82, 40 },
    card_border  = { 155, 142, 120, 130 },   -- 暖褐卡片边

    -- 语义色
    radio_wave            = { 72, 155, 82, 255 },
    float_gain            = { 98, 198, 118, 255 },
    float_loss            = { 225, 135, 88, 255 },
    dialogue_linli_accent = { 118, 165, 205, 255 },
    dialogue_linli_bg     = { 35, 45, 52, 238 },
    dialogue_taoxia_bg    = { 52, 45, 35, 238 },
    bg_inset              = { 0, 0, 0, 0 },
    bg_intel_hint         = { 195, 205, 218, 200 },   -- 旧纸+蓝调（淡蓝羊皮纸）
    bg_intel_active       = { 195, 215, 200, 200 },   -- 旧纸+绿调（淡绿羊皮纸）
    border_rare           = { 178, 142, 82, 118 },
    bg_error              = { 218, 185, 180, 200 },   -- 旧纸+红调（淡红羊皮纸）
    sketch_glow           = { 215, 198, 155 },
}
CONCRETE.sketch = {
    -- 墨线改为灰黑色，搭配羊皮纸贴图
    ink_color     = { 55, 52, 48, 200 },
    ink_color_dim = { 75, 72, 68, 130 },
    ink_accent    = { 168, 135, 75, 178 },
    ink_danger    = { 165, 72, 55, 158 },
    baseWidth     = 1.5,
    widthVar      = 0.22,
    jitter        = 1.0,         -- 略少抖动，更工业感
    jitterFullLen = 300,
    jitterMinLen  = 40,
    segments      = 26,
    breakChance   = 0.40,
    breakMaxGaps  = 3,
    breakMinLen   = 120,
    breakGapMin   = 2,
    breakGapMax   = 6,
    layers        = 2,
    layer2Alpha   = 0.30,
    layer2Offset  = 0.4,
    breathSpeed   = 0.7,
    breathAmp     = 0.12,        -- 略少呼吸，更稳重
    cornerEmphasis = 1.15,
    cornerLen      = 6,
}
CONCRETE.btn_colors = {
    primary = {
        bg      = { 108, 95, 68, 255 },     -- 暖棕褐（皮革色，与 btn_primary 一致）
        pressed = { 88, 78, 55, 255 },
    },
    secondary = {
        bg      = { 175, 165, 145, 255 },   -- 暖灰旧纸（浅色底上可见）
        pressed = { 155, 145, 128, 255 },
    },
    danger = {
        bg      = { 168, 62, 48, 255 },     -- 砖锈红（与 btn_danger 一致）
        pressed = { 145, 52, 38, 255 },
    },
    disabled = {
        bg      = { 185, 178, 165, 150 },   -- 浅旧纸灰（半透明）
    },
}

-- ============================================================
-- 根据标记选择主题
-- ============================================================
local THEMES = {
    dark = DARK, light = LIGHT,
    watercolor = WATERCOLOR, concrete = CONCRETE,
}
local chosen = THEMES[ACTIVE_THEME] or DARK

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
    card_slice  = { 16, 16, 16, 16 },
    topbar      = "image/复古羊皮纸topbar.png",
    topbar_flip = "image/复古羊皮纸topbar_flip.png",
    notebook_bg = "image/复古羊皮本子背景2.png",
    parchment   = "image/羊皮纸纹理.png",
    parchment_red = "image/复古红色羊皮纸材质.png",
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
    tab_home   = "image/手绘首页图标v2_20260414163723.png",
    tab_map    = "image/手绘地图图标v2_20260414163729.png",
    tab_orders = "image/手绘卷轴图标v2_20260415033637.png",
    tab_cargo  = "image/手绘货仓图标v2_20260414163732.png",
    tab_truck  = "image/手绘货车图标v2_20260414163733.png",
    settings   = "image/手绘设置图标v2_20260414163742.png",
    credits    = "image/手绘钱币图标v2_20260414163752.png",
    fuel       = "image/手绘燃料图标v2_20260414163734.png",
    durability = "image/手绘耐久图标v2_20260414163745.png",
    radio      = "image/手绘收音机图标_20260414141316.png",
    radio_on   = "image/edited_手绘收音机打开图标v2_20260415034033.png",
    lock       = "image/手绘锁图标_20260414175223.png",
    exchange   = "image/手绘交易所图标_20260414175211.png",
    target     = "image/手绘目标图标_20260414175216.png",
    question   = "image/手绘问号图标_20260414175220.png",
    -- 地图节点类型
    map_settlement = "image/手绘聚落图标_20260414175219.png",
    map_resource   = "image/手绘资源点图标_20260414175226.png",
    map_transit    = "image/手绘中转站图标_20260414175224.png",
    map_hazard     = "image/手绘危险区图标_20260414175227.png",
    map_story      = "image/手绘遗迹图标_20260414175301.png",
    -- 通用图标
    location   = "image/手绘位置图标_20260414180326.png",
    walking    = "image/手绘步行图标_20260414180324.png",
    hint       = "image/手绘提示图标_20260414180315.png",
    shield     = "image/手绘盾牌图标_20260414180325.png",
    weather    = "image/手绘天气图标_20260414180327.png",
    clock      = "image/手绘时钟图标_20260414180332.png",
    -- 通用操作图标
    cross      = "image/手绘叉号图标_20260415034300.png",
    check      = "image/手绘对勾图标_20260415034302.png",
    -- 首页操作图标
    scroll     = "image/手绘卷轴图标v2_20260415033637.png",
    book       = "image/手绘书本图标v2_20260415033653.png",
    campfire   = "image/手绘篝火图标v2_20260415033641.png",
    lightning  = "image/手绘闪电图标v2_20260415033644.png",
    letter     = "image/手绘信封图标v2_20260415033744.png",
    tent       = "image/手绘帐篷图标v2_20260415033635.png",
    search     = "image/手绘搜索图标v2_20260415033630.png",
}

-- ============================================================
-- NPC Chibi 头像路径（拜访按钮 / 对话用）
-- ============================================================
M.npc_chibis = {
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
    xue_dong   = "image/chibi_npc_xue_dong_20260412064256.png",
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

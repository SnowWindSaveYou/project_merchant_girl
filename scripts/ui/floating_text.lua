--- 全局飘字模块
--- 任何物品增减时在屏幕上方中央显示浮动通知
--- 独立 NanoVG 上下文，覆盖在所有 UI 之上
local Goods = require("economy/goods")
local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")

local M = {}

-- NanoVG 上下文
local _nvgCtx   = nil
local _nvgFont  = nil
local _inited   = false

-- 活跃飘字列表
local _entries = {}

-- 配置
local DURATION    = 1.5    -- 持续时间（秒）
local FLOAT_SPEED = 35     -- 向上飘动速度（逻辑像素/秒）
local FONT_SIZE   = 15
local START_Y_PCT = 0.15   -- 起始 Y 位置（屏幕高度百分比）
local STACK_GAP   = 22     -- 多条飘字垂直间距

--- 初始化 NanoVG 上下文（仅调用一次）
function M.init()
    if _inited then return end
    _inited = true

    _nvgCtx = nvgCreate(1)
    if not _nvgCtx then
        print("[FloatingText] WARNING: Failed to create NanoVG context")
        return
    end

    -- 渲染顺序：在 UI(999990) 和 Shell ticker(999991) 之上
    nvgSetRenderOrder(_nvgCtx, 999992)

    -- 创建字体（只调一次）
    _nvgFont = nvgCreateFont(_nvgCtx, "float", "Fonts/MiSans-Regular.ttf")

    -- 订阅渲染事件
    SubscribeToEvent(_nvgCtx, "NanoVGRender", "HandleFloatingTextRender")
end

--- 显示一条飘字
---@param text string 显示文本（如 "+2 罐头食品"）
---@param color_type string "gain"|"loss"|"info"
function M.show(text, color_type)
    if not _nvgCtx then return end
    table.insert(_entries, {
        text   = text,
        ctype  = color_type or "info",
        timer  = 0,
        alpha  = 1.0,
        offset = 0,
    })
end

--- 每帧更新
---@param dt number
function M.update(dt)
    local i = 1
    while i <= #_entries do
        local e = _entries[i]
        e.timer  = e.timer + dt
        e.alpha  = 1.0 - (e.timer / DURATION)
        e.offset = e.timer * FLOAT_SPEED
        if e.alpha <= 0 then
            table.remove(_entries, i)
        else
            i = i + 1
        end
    end
end

--- NanoVG 渲染回调（全局函数）
function HandleFloatingTextRender(eventType, eventData)
    if not _nvgCtx or #_entries == 0 then return end

    local uiScale = UI.GetScale()
    local W = graphics:GetWidth()
    local H = graphics:GetHeight()
    local logW = W / uiScale
    local logH = H / uiScale

    nvgBeginFrame(_nvgCtx, logW, logH, uiScale)

    nvgFontFace(_nvgCtx, "float")
    nvgFontSize(_nvgCtx, FONT_SIZE)
    nvgTextAlign(_nvgCtx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)

    local baseY = logH * START_Y_PCT

    for idx, e in ipairs(_entries) do
        local alpha = math.max(0, e.alpha)
        local px = logW * 0.5
        local py = baseY - e.offset + (idx - 1) * STACK_GAP

        -- 颜色：绿色=获得 / 橙红=消耗 / 米白=信息
        local _c = Theme.colors.text_primary
        if e.ctype == "gain" then
            _c = Theme.colors.float_gain
        elseif e.ctype == "loss" then
            _c = Theme.colors.float_loss
        end
        local r, g, b = _c[1], _c[2], _c[3]

        -- 文字阴影
        nvgFillColor(_nvgCtx, nvgRGBA(0, 0, 0, math.floor(160 * alpha)))
        nvgText(_nvgCtx, px + 1, py + 1, e.text)

        -- 文字本体
        nvgFillColor(_nvgCtx, nvgRGBA(r, g, b, math.floor(255 * alpha)))
        nvgText(_nvgCtx, px, py, e.text)
    end

    nvgEndFrame(_nvgCtx)
end

-- ============================================================
-- 便捷通知接口
-- ============================================================

--- 物品变化通知
---@param goods_id string
---@param delta number 正=获得，负=消耗
function M.notify_item(goods_id, delta)
    if delta == 0 then return end
    local g = Goods.get(goods_id)
    local name = g and g.name or goods_id
    local sign = delta > 0 and "+" or ""
    local text = sign .. delta .. " " .. name
    local ctype = delta > 0 and "gain" or "loss"
    M.show(text, ctype)
end

--- 货币变化通知
---@param delta number
function M.notify_credits(delta)
    if delta == 0 then return end
    local sign = delta > 0 and "+" or ""
    local text = sign .. delta .. " 信用币"
    local ctype = delta > 0 and "gain" or "loss"
    M.show(text, ctype)
end

return M

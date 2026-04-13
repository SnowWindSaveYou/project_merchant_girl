--- Shell 组装器
--- 统一管理全局顶部状态栏 + 底部导航栏，包裹各页面内容
local UI           = require("urhox-libs/UI")
local ShellTop     = require("ui/shell_top")
local ShellBottom  = require("ui/shell_bottom")
local Theme        = require("ui/theme")
local CargoUtils   = require("economy/cargo_utils")
local Flow         = require("core/flow")
local RoutePlanner = require("map/route_planner")
local Graph        = require("map/world_graph")
local Radio        = require("travel/radio")
local SpeechBubble = require("ui/speech_bubble")
local AudioMgr     = require("ui/audio_manager")

local M = {}

-- 收音机状态追踪（用于检测变化触发顶栏重建）
local _prevRadioOn     = nil
local _prevRadioCh     = nil
local _prevBroadcastId = nil

-- 收音机滚动字幕状态（NanoVG 像素级平滑滚动）
-- 文字从右侧平滑进入，向左滚动，最终从左侧平滑消失
local _radioScrollOffset     = 0       -- 当前像素偏移（持续增长）
local _radioScrollSpeed      = 45      -- 滚动速度（base pixels / 秒）
local _radioScrollBroadcastId = nil    -- 当前滚动对应的播报 ID
local _radioScrollFullText   = ""      -- 完整播报文本
local _radioScrollTextWidth  = nil     -- 文本像素宽度（NanoVG 测量后缓存）
local _radioScrollDraining   = false   -- 广播到期，正在让文字自然滚完
local _radioScrollPauseTimer = 0       -- 一轮结束后暂停计时
local _radioScrollPaused     = false   -- 是否在暂停中
local _radioTickerActive     = false   -- ticker 是否活跃（控制 NanoVG 渲染）

-- NanoVG 渲染上下文（独立于 UI 系统）
local _radioNvgCtx    = nil
local _radioNvgFont   = nil
local _radioNvgInited = false
local _radioAnimTime  = 0  -- 电波动画时间累加器

--- 初始化收音机 ticker 的 NanoVG 上下文（仅调用一次）
local function _initRadioNvg()
    if _radioNvgInited then return end
    _radioNvgInited = true

    _radioNvgCtx = nvgCreate(1)
    if not _radioNvgCtx then
        print("[Shell] WARNING: Failed to create NanoVG context for radio ticker")
        return
    end

    -- 渲染顺序在 UI 系统之后（UI = 999990）
    nvgSetRenderOrder(_radioNvgCtx, 999991)

    -- 创建字体（只调一次）
    _radioNvgFont = nvgCreateFont(_radioNvgCtx, "radio", "Fonts/MiSans-Regular.ttf")

    -- 订阅 NanoVGRender 事件
    SubscribeToEvent(_radioNvgCtx, "NanoVGRender", "HandleRadioTickerRender")
end

--- NanoVG 渲染回调 - 平滑绘制收音机滚动字幕
--- 全局函数，通过闭包访问文件局部变量
function HandleRadioTickerRender(eventType, eventData)
    if not _radioTickerActive or _radioScrollFullText == "" then return end
    if not _radioNvgCtx then return end

    local root = UI.GetRoot()
    if not root then return end

    local textArea = root:FindById("shellRadioTextArea")
    if not textArea then return end

    local layout = textArea:GetAbsoluteLayout()
    if not layout or layout.w <= 0 then return end

    local uiScale = UI.GetScale()
    local W = graphics:GetWidth()
    local H = graphics:GetHeight()

    nvgBeginFrame(_radioNvgCtx, W / uiScale, H / uiScale, uiScale)
    nvgSave(_radioNvgCtx)

    -- 裁剪区域：仅在文本区域内绘制
    nvgScissor(_radioNvgCtx, layout.x, layout.y, layout.w, layout.h)

    -- ── 电波信号动态背景（不规则波形） ──
    local cx, cy, cw, ch = layout.x, layout.y, layout.w, layout.h
    local midY = cy + ch * 0.5
    local t = _radioAnimTime

    -- 伪随机哈希函数（输入种子 → 0~1 噪声值）
    local function noise(s)
        local v = math.sin(s * 127.1 + 311.7) * 43758.5453
        return v - math.floor(v)
    end

    -- 绘制 2 层不规则信号波形
    local sigLayers = {
        { speed = 1.8, baseAmp = ch * 0.30, seed = 0,    alpha = 28, width = 1.2 },
        { speed = 2.6, baseAmp = ch * 0.20, seed = 50.7, alpha = 18, width = 0.8 },
    }
    for _, sl in ipairs(sigLayers) do
        nvgBeginPath(_radioNvgCtx)
        local step = 2
        local prevY = midY
        for px = 0, math.floor(cw), step do
            local x = cx + px
            -- 多频叠加 + 噪声调制振幅 → 不规则尖峰/平静交替
            local ns = noise(px * 0.07 + t * sl.speed + sl.seed)
            local ampMod = ns * ns  -- 平方让大部分区域安静，偶尔出尖峰
            local sig = math.sin(px * 0.12 + t * sl.speed * 1.3)
                       + math.sin(px * 0.23 + t * sl.speed * 0.7 + 1.7) * 0.6
                       + math.sin(px * 0.41 + t * sl.speed * 2.1 + 3.2) * 0.3
            local y = midY + sig * sl.baseAmp * ampMod
            -- 限制在区域内
            y = math.max(cy + 2, math.min(cy + ch - 2, y))
            if px == 0 then
                nvgMoveTo(_radioNvgCtx, x, y)
            else
                nvgLineTo(_radioNvgCtx, x, y)
            end
            prevY = y
        end
        local _rw = Theme.colors.radio_wave
        nvgStrokeColor(_radioNvgCtx, nvgRGBA(_rw[1], _rw[2], _rw[3], sl.alpha))
        nvgStrokeWidth(_radioNvgCtx, sl.width)
        nvgStroke(_radioNvgCtx)
    end

    -- ── 文字绘制 ──
    nvgFontFace(_radioNvgCtx, "radio")
    nvgFontSize(_radioNvgCtx, 13)
    local _tp = Theme.colors.text_primary
    nvgFillColor(_radioNvgCtx, nvgRGBA(_tp[1], _tp[2], _tp[3], _tp[4]))
    nvgTextAlign(_radioNvgCtx, NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)

    -- 测量文本宽度（首次渲染时缓存）
    if not _radioScrollTextWidth then
        local advance = nvgTextBounds(_radioNvgCtx, 0, 0, _radioScrollFullText)
        _radioScrollTextWidth = advance or 100
    end

    -- 文字位置：从右边缘进入，向左滚动
    local textX = layout.x + layout.w - _radioScrollOffset
    local textY = layout.y + layout.h / 2

    nvgText(_radioNvgCtx, textX, textY, _radioScrollFullText)

    nvgRestore(_radioNvgCtx)
    nvgEndFrame(_radioNvgCtx)
end

--- 需要 Shell 包裹的页面
local SHELLED = {
    home         = true,
    map          = true,
    orders       = true,
    cargo        = true,
    shop         = true,
    route_plan   = true,
    truck        = true,
    quest_log    = true,
    archives     = true,
    farm         = true,
    intel        = true,
    black_market = true,
}

--- 页面名 → 底栏高亮 tab 映射
local SCREEN_TO_TAB = {
    home         = "home",
    map          = "map",
    orders       = "orders",
    cargo        = "cargo",
    shop         = "home",        -- 交易所从据点进入，属于首页 tab
    route_plan   = "orders",      -- 路线规划是委托流程的延续
    truck        = "truck",
    quest_log    = "home",        -- 任务日志从首页进入
    archives     = "home",        -- 聚落子功能均从首页进入
    farm         = "home",
    intel        = "home",
    black_market = "home",
}

--- 判断页面是否需要 Shell 包裹
---@param screenName string
---@return boolean
function M.is_shelled(screenName)
    return SHELLED[screenName] == true
end

--- 用 Shell 包裹页面内容
---@param state table
---@param content table 页面 create() 返回的 widget
---@param screenName string
---@param router table
---@return table 完整 Shell widget 树
function M.create(state, content, screenName, router)
    local activeTab = SCREEN_TO_TAB[screenName] or "home"

    return UI.Panel {
        id = "shellRoot",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        children = {
            UI.SafeAreaView {
                width = "100%", height = "100%",
                children = {
                    ShellTop.create(state),
                    UI.Panel {
                        id = "shellContent",
                        width = "100%", flexGrow = 1, flexShrink = 1,
                        children = { content },
                    },
                    ShellBottom.create(state, activeTab, screenName, router),
                },
            },
        },
    }
end

--- 每帧更新顶栏数值
---@param state table
---@param dt number
---@return boolean needRebuild 是否需要重建 Shell（收音机状态变化等）
function M.update(state, dt)
    local root = UI.GetRoot()
    if not root then return false end

    -- 驱动全局气泡（收音机教程等）
    SpeechBubble.update(dt)

    -- ── BGM + 环境音：根据游戏阶段自动切换音频场景 ──
    -- （AudioMgr.update 已移至 router.lua 全局驱动，此处只负责设置场景）
    local phase = Flow.get_phase(state)
    local audioScene = (phase == Flow.Phase.TRAVELLING) and "travel" or "settlement"
    AudioMgr.setScene(audioScene)

    -- 确保 radio 状态存在（兼容旧存档 & 据点阶段）
    if not state.flow.radio then
        state.flow.radio = Radio.init()
    end
    -- 全局驱动收音机逻辑
    Radio.update(state, dt)

    local creditsLbl = root:FindById("shellCredits")
    if creditsLbl then creditsLbl:SetText("$ " .. tostring(state.economy.credits)) end

    local fuelPct = math.floor(state.truck.fuel)
    local fuelLbl = root:FindById("shellFuelVal")
    if fuelLbl then
        fuelLbl:SetText(fuelPct .. "%")
        fuelLbl:SetFontColor(fuelPct > 30 and Theme.colors.text_secondary or Theme.colors.danger)
    end

    local durPct = math.floor(state.truck.durability)
    local durLbl = root:FindById("shellDurVal")
    if durLbl then
        durLbl:SetText(durPct .. "%")
        durLbl:SetFontColor(durPct > 30 and Theme.colors.text_secondary or Theme.colors.danger)
    end

    local cargoUsed = CargoUtils.get_cargo_used(state)
    local hasShortage = CargoUtils.has_any_shortage(state)
    local cargoLbl = root:FindById("shellCargoVal")
    if cargoLbl then
        cargoLbl:SetText(cargoUsed .. "/" .. state.truck.cargo_slots)
        cargoLbl:SetFontColor(hasShortage and Theme.colors.danger or Theme.colors.text_secondary)
    end

    -- 旅行进度条实时更新
    local isTravelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING
    local travelStrip = root:FindById("shellTravelStrip")
    if isTravelling and travelStrip then
        local plan = state.flow.route_plan
        if plan then
            local progress = RoutePlanner.get_progress(plan)
            local seg = RoutePlanner.get_current_segment(plan)

            local bar = root:FindById("shellTravelProgress")
            if bar then bar:SetValue(progress) end

            -- 剩余时间
            local remaining = 0
            if seg then
                remaining = math.max(0, seg.time_sec - (plan.segment_elapsed or 0))
                for i = (plan.segment_index or 0) + 1, #plan.segments do
                    remaining = remaining + plan.segments[i].time_sec
                end
            end
            local timeLbl = root:FindById("shellTravelTime")
            if timeLbl then
                timeLbl:SetText(string.format("%d:%02d",
                    math.floor(remaining / 60),
                    math.floor(remaining % 60)))
            end
        end
    end

    -- ── 收音机状态变化检测 + NanoVG 像素级平滑滚动（全阶段生效） ──
    _initRadioNvg()  -- 确保 NanoVG 上下文已初始化

    local radioOn = Radio.is_on(state)
    local radioCh = Radio.get_channel(state)
    local curBroadcast = Radio.get_current(state)
    local broadcastId  = curBroadcast and curBroadcast.id or nil

    -- 收音机音频跟随状态：底噪跟开关，模糊人声跟播报
    AudioMgr.setRadioNoise(radioOn)
    AudioMgr.setRadioVoice(radioOn and curBroadcast ~= nil)

    local needRebuild = false
    if radioOn ~= _prevRadioOn then needRebuild = true end
    if radioCh ~= _prevRadioCh then needRebuild = true end
    if broadcastId ~= _prevBroadcastId then
        if broadcastId == nil and _radioScrollFullText ~= "" then
            -- 广播到期但 ticker 还有内容，不立即重建，进入 draining 模式
            _radioScrollDraining = true
        else
            needRebuild = true
        end
    end

    _prevRadioOn     = radioOn
    _prevRadioCh     = radioCh
    _prevBroadcastId = broadcastId

    if needRebuild then
        -- 重置滚动状态
        _radioScrollOffset      = 0
        _radioScrollTextWidth   = nil   -- 等首帧渲染时再测量
        _radioScrollPauseTimer  = 0
        _radioScrollPaused      = false
        _radioScrollDraining    = false
        _radioScrollBroadcastId = broadcastId

        if curBroadcast then
            _radioScrollFullText = curBroadcast.text or ""
            _radioTickerActive   = true
        else
            _radioScrollFullText = ""
            _radioTickerActive   = false
        end
        return true
    end

    -- 收音机教程气泡：pending → 等 shell 重建完成后的首帧再触发
    -- 必须在 needRebuild 之后，确保 UI root 已稳定
    if ShellTop._pendingRadioTutorial then
        local pending = ShellTop._pendingRadioTutorial
        ShellTop._pendingRadioTutorial = nil
        ShellTop._showBubbleSequence(root, pending.state, pending.steps, 1)
    end

    -- ── NanoVG 像素级平滑 ticker 驱动 ──
    local shouldAnimate = (radioOn and curBroadcast and _radioScrollFullText ~= "")
                       or (_radioScrollDraining and _radioScrollFullText ~= "")
    _radioTickerActive = shouldAnimate

    if shouldAnimate then
        -- 暂停阶段（一轮滚完后短暂停留再重新循环）
        if _radioScrollPaused then
            if _radioScrollDraining then
                -- draining 模式下滚完一轮就结束，触发重建
                _radioScrollDraining   = false
                _radioScrollFullText   = ""
                _radioScrollPaused     = false
                _radioTickerActive     = false
                _prevBroadcastId       = nil
                return true
            end
            _radioScrollPauseTimer = _radioScrollPauseTimer + dt
            if _radioScrollPauseTimer >= 1.5 then
                -- 重新开始一轮
                _radioScrollPaused     = false
                _radioScrollPauseTimer = 0
                _radioScrollOffset     = 0
            end
            return false
        end

        -- 推进像素偏移 & 动画时间
        _radioScrollOffset = _radioScrollOffset + _radioScrollSpeed * dt
        _radioAnimTime = _radioAnimTime + dt

        -- 判断一轮是否结束：文本完全滚出左侧
        -- 需要知道容器宽度和文本宽度
        if _radioScrollTextWidth then
            local textArea = root:FindById("shellRadioTextArea")
            local containerW = 0
            if textArea then
                local layout = textArea:GetAbsoluteLayout()
                if layout then containerW = layout.w end
            end
            -- 文字起始位置: containerW - offset
            -- 文字结束位置: containerW - offset + textWidth
            -- 当文字结束位置 <= 0 时，整段文字已完全消失
            if containerW > 0 and (_radioScrollOffset >= containerW + _radioScrollTextWidth) then
                _radioScrollPaused     = true
                _radioScrollPauseTimer = 0
            end
        end
    end

    return false
end

return M

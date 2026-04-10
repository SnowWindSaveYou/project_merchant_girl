--- 气泡对话组件
--- 用于非对话场景内的引导提示，带角色头像
--- 可复用的绝对定位气泡，支持自动消失和点击关闭
local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")

local M = {}

-- 当前显示的气泡引用（用于隐藏）
M._current = nil
M._timer   = 0
M._autoHide = 0
M._onDismiss = nil

--- 显示气泡对话
--- @param parent table UI 父容器（通常是页面根 Panel）
--- @param config table 配置项：
---   portrait: string  头像资源路径
---   speaker:  string  说话者名字
---   text:     string  对话文本
---   position: table   { x = "50%", y = "70%" } 气泡位置
---                     -- [Layout] 位置参数可能需要随 UI 重构调整
---   autoHide: number  自动消失秒数（0 = 手动关闭）
---   onDismiss: function  关闭时的回调
function M.show(parent, config)
    -- 先隐藏已有气泡
    M.hide()

    local portrait  = config.portrait or ""
    local speaker   = config.speaker or ""
    local text      = config.text or ""
    local pos       = config.position or { x = "50%", y = "70%" }
    local autoHide  = config.autoHide or 0
    M._autoHide  = autoHide
    M._timer     = 0
    M._onDismiss = config.onDismiss

    -- [Layout] 气泡整体容器 —— 绝对定位覆盖层
    -- 位置参数可能需要随 UI 重构调整
    local bubbleOverlay = UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", left = 0, top = 0,
        justifyContent = "flex-end",
        alignItems = "center",
        paddingBottom = 80,  -- [Layout] 底部留白，避免遮挡操作按钮
        onClick = function(self)
            M.hide()
        end,
        children = {
            -- 气泡卡片
            UI.Panel {
                width = "90%", maxWidth = 400,
                flexDirection = "row",
                alignItems = "flex-start",
                backgroundColor = { 28, 26, 24, 230 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = Theme.colors.accent_dim,
                padding = 12,
                gap = 10,
                children = {
                    -- 头像
                    UI.Panel {
                        width = 48, height = 48,
                        borderRadius = 24,
                        backgroundImage = portrait,
                        backgroundFit = "cover",
                        flexShrink = 0,
                    },
                    -- 文字区域
                    UI.Panel {
                        flex = 1,
                        flexShrink = 1,
                        children = {
                            -- 说话者名字
                            UI.Label {
                                text = speaker,
                                fontSize = 13,
                                color = Theme.colors.accent,
                                marginBottom = 4,
                            },
                            -- 对话内容
                            UI.Label {
                                text = text,
                                fontSize = 15,
                                color = Theme.colors.text_primary,
                                lineHeight = 1.4,
                            },
                            -- 关闭提示
                            UI.Label {
                                text = autoHide > 0 and "" or "点击任意处关闭",
                                fontSize = 11,
                                color = Theme.colors.text_dim,
                                marginTop = 6,
                            },
                        },
                    },
                },
            },
        },
    }

    M._current = bubbleOverlay
    parent:AddChild(bubbleOverlay)
end

--- 隐藏当前气泡
function M.hide()
    if M._current then
        M._current:Remove()
        M._current = nil
        if M._onDismiss then
            local cb = M._onDismiss
            M._onDismiss = nil
            cb()
        end
    end
    M._timer = 0
    M._autoHide = 0
end

--- 更新计时器（在 Update 事件中调用）
--- @param dt number 帧间隔
function M.update(dt)
    if M._current and M._autoHide > 0 then
        M._timer = M._timer + dt
        if M._timer >= M._autoHide then
            M.hide()
        end
    end
end

--- 当前是否有气泡显示
--- @return boolean
function M.is_showing()
    return M._current ~= nil
end

-- ============================================================
-- 声明式 API（用于 UI 树构建，嵌入 screen 的 rootChildren）
-- ============================================================

--- 创建气泡 UI 组件（声明式，直接返回 Panel 供嵌入 UI 树）
--- @param config table 同 show() 的 config
--- @return table widget 可直接嵌入 rootChildren 的 UI.Panel
function M.createWidget(config)
    local portrait  = config.portrait or ""
    local speaker   = config.speaker or ""
    local text      = config.text or ""
    local autoHide  = config.autoHide or 0

    local onDismiss = config.onDismiss

    -- [Layout] 气泡覆盖层 —— 绝对定位，位置可能需要随 UI 重构调整
    return UI.Panel {
        width = "100%", height = "100%",
        position = "absolute", left = 0, top = 0,
        justifyContent = "flex-end",
        alignItems = "center",
        paddingBottom = 80,  -- [Layout] 底部留白，避免遮挡操作按钮
        onClick = function(self)
            self:Remove()
            if onDismiss then onDismiss() end
        end,
        children = {
            -- 气泡卡片
            UI.Panel {
                width = "90%", maxWidth = 400,
                flexDirection = "row",
                alignItems = "flex-start",
                backgroundColor = { 28, 26, 24, 230 },
                borderRadius = 12,
                borderWidth = 1,
                borderColor = Theme.colors.accent,
                padding = 12,
                gap = 10,
                children = {
                    -- 头像
                    UI.Panel {
                        width = 48, height = 48,
                        borderRadius = 24,
                        backgroundImage = portrait,
                        backgroundFit = "cover",
                        flexShrink = 0,
                    },
                    -- 文字区域
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = speaker,
                                fontSize = 13,
                                fontColor = Theme.colors.accent,
                                marginBottom = 4,
                            },
                            UI.Label {
                                text = text,
                                fontSize = 15,
                                fontColor = Theme.colors.text_primary,
                            },
                            autoHide <= 0 and UI.Label {
                                text = "点击任意处继续",
                                fontSize = 11,
                                fontColor = Theme.colors.text_dim,
                                marginTop = 6,
                            } or nil,
                        },
                    },
                },
            },
        },
    }
end

return M

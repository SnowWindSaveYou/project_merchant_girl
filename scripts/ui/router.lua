--- UI 页面路由器
--- 统一控制页面切换，自动用 Shell 包裹常规页面
local UI    = require("urhox-libs/UI")
local Shell = require("ui/shell")

local M = {}

local screens = {}
local currentName = nil
local currentScreen = nil
local gameState = nil

function M.init(state)
    gameState = state
end

--- 注册一个页面模块
function M.register(name, screenModule)
    screens[name] = screenModule
end

--- 切换到指定页面
function M.navigate(name, params)
    print("[Router] navigate -> " .. name)
    currentName = name
    currentScreen = screens[name]
    if not currentScreen then
        print("[Router] Screen not found: " .. name)
        return
    end

    local content = currentScreen.create(gameState, params, M)
    if not content then return end

    if Shell.is_shelled(name) then
        local shell = Shell.create(gameState, content, name, M)
        UI.SetRoot(shell)
    else
        -- 全屏页面：event, event_result, summary
        UI.SetRoot(content)
    end
end

--- 获取当前页面名称
function M.current()
    return currentName
end

--- 每帧更新当前页面
function M.update(dt)
    -- 刷新 Shell 顶栏数值
    if Shell.is_shelled(currentName) then
        Shell.update(gameState, dt)
    end

    -- 页面自身更新
    if currentScreen and currentScreen.update then
        currentScreen.update(gameState, dt, M)
    end
end

--- 获取游戏状态引用
function M.get_state()
    return gameState
end

return M

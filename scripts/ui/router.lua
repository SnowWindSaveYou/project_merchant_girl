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
    currentName = name
    currentScreen = screens[name]
    if not currentScreen then
        print("[Router] Screen not found: " .. name)
        return
    end

    local ok, content = pcall(currentScreen.create, gameState, params, M)
    if not ok then
        print("[Router] ERROR: screen '" .. name .. "' create crashed: " .. tostring(content))
        return
    end
    if not content then return end

    if Shell.is_shelled(name) then
        local shell = Shell.create(gameState, content, name, M)
        UI.SetRoot(shell)
    else
        UI.SetRoot(content)
    end
end

--- 刷新当前页面（保留滚动位置）
--- 用于页面内操作后需要更新 UI 但不应重置滚动的场景
--- 如：交易所买入/卖出、货舱使用物品等
function M.refresh(params)
    if not currentName or not currentScreen then return end

    -- 1. 保存当前滚动位置
    local savedScrollX, savedScrollY = 0, 0
    local root = UI.GetRoot()
    if root then
        local shellContent = root:FindById("shellContent")
        if shellContent then
            -- Shell 包裹的页面：内容区在 shellContent 的第一个子节点
            local pageRoot = shellContent.children_ and shellContent.children_[1]
            if pageRoot and pageRoot.GetScroll then
                savedScrollX, savedScrollY = pageRoot:GetScroll()
            end
        elseif root.GetScroll then
            -- 非 Shell 页面：root 本身可能是滚动容器
            savedScrollX, savedScrollY = root:GetScroll()
        end
    end

    -- 2. 重建页面内容
    local content = currentScreen.create(gameState, params, M)
    if not content then return end

    -- 3. 替换 UI 并恢复滚动
    if Shell.is_shelled(currentName) then
        local shell = Shell.create(gameState, content, currentName, M)
        UI.SetRoot(shell)
        -- 恢复滚动位置
        local newRoot = UI.GetRoot()
        if newRoot then
            local newShellContent = newRoot:FindById("shellContent")
            if newShellContent then
                local newPageRoot = newShellContent.children_ and newShellContent.children_[1]
                if newPageRoot and newPageRoot.SetScroll then
                    newPageRoot:SetScroll(savedScrollX, savedScrollY)
                end
            end
        end
    else
        UI.SetRoot(content)
        if content.SetScroll then
            content:SetScroll(savedScrollX, savedScrollY)
        end
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

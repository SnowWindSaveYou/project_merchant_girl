--- UI 页面路由器
--- 统一控制页面切换，自动用 Shell 包裹常规页面
local UI           = require("urhox-libs/UI")
local Shell        = require("ui/shell")
local SoundMgr     = require("ui/sound_manager")
local F            = require("ui/ui_factory")
local SketchBorder = require("ui/sketch_border")

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
    -- 同页面导航 → 转为 refresh（保留滚动位置、抑制入场动画）
    if currentName == name then
        M.refresh(params)
        return
    end

    local prevName = currentName
    currentName = name
    currentScreen = screens[name]
    if not currentScreen then
        print("[Router] Screen not found: " .. name)
        return
    end

    -- 页面切换音效
    if prevName then
        SoundMgr.play("open")
    end

    -- 清空旧页面的手绘边框注册表（新页面 create 会重新注册）
    SketchBorder.clear()

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

--- 递归遍历 widget 树，收集所有 ScrollView 的滚动位置
--- 通过 GetScroll 方法存在性识别 ScrollView（overflow="scroll" 的 Panel 会被自动升级）
--- 使用深度优先遍历的顺序索引作为 key（无需每个容器都有 id）
local function collectScrollPositions(widget, list)
    if not widget then return end
    if widget.GetScroll then
        local sx, sy = widget:GetScroll()
        list[#list + 1] = { sx, sy }
    end
    if widget.children then
        for _, child in ipairs(widget.children) do
            collectScrollPositions(child, list)
        end
    end
end

--- 递归遍历新 widget 树，按深度优先顺序恢复滚动位置
--- 使用 SetScrollDirect 绕过布局依赖的钳制（UI.SetRoot 后 layout 尚未计算，
--- 若用 SetScroll 则 contentHeight_=0 导致 maxScrollY=0 → 滚动被钳制到 0）
local function applyScrollPositions(widget, list, idx)
    if not widget then return idx end
    if widget.SetScrollDirect or widget.SetScroll then
        if idx <= #list then
            local pos = list[idx]
            if widget.SetScrollDirect then
                widget:SetScrollDirect(pos[1], pos[2])
            else
                widget:SetScroll(pos[1], pos[2])
            end
        end
        idx = idx + 1
    end
    if widget.children then
        for _, child in ipairs(widget.children) do
            idx = applyScrollPositions(child, list, idx)
        end
    end
    return idx
end

--- 刷新当前页面（保留滚动位置）
--- 用于页面内操作后需要更新 UI 但不应重置滚动的场景
--- 如：交易所买入/卖出、货舱使用物品等
function M.refresh(params)
    if not currentName or not currentScreen then return end

    -- 1. 遍历整棵 UI 树，按深度优先顺序收集所有滚动位置
    local scrollList = {}
    local root = UI.GetRoot()
    if root then
        collectScrollPositions(root, scrollList)
    end

    -- 2. 重建页面内容（抑制入场动画，清理旧动画队列 + 手绘边框注册表）
    F._pendingAnims = nil
    F.skipEnterAnim = true
    SketchBorder.clear()
    local ok, content = pcall(currentScreen.create, gameState, params, M)
    F.skipEnterAnim = nil
    if not ok then
        print("[Router] ERROR: refresh crashed: " .. tostring(content))
        return
    end
    if not content then return end

    -- 3. 替换 UI
    if Shell.is_shelled(currentName) then
        local shell = Shell.create(gameState, content, currentName, M)
        UI.SetRoot(shell)
    else
        UI.SetRoot(content)
    end

    -- 4. 按同样的深度优先顺序恢复滚动位置
    local newRoot = UI.GetRoot()
    if newRoot and #scrollList > 0 then
        applyScrollPositions(newRoot, scrollList, 1)
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
        local needRebuild = Shell.update(gameState, dt)
        if needRebuild then
            M.refresh()
            return
        end
    end

    -- 页面自身更新
    if currentScreen and currentScreen.update then
        currentScreen.update(gameState, dt, M)
    end

    -- 驱动 F.card 入场动画
    F.update(dt)

    -- 推进手绘边框呼吸动画时间
    SketchBorder.update(dt)
end

--- 获取游戏状态引用
function M.get_state()
    return gameState
end

return M

--- audio_manager.lua
--- 统一 BGM + 环境音管理器
--- 通过「场景」概念驱动：每个场景定义一首 BGM 和若干环境音层
--- 场景切换时自动交叉淡入淡出，无需外部逐帧管理音量
---
--- 用法:
---   local AudioMgr = require("ui.audio_manager")
---   AudioMgr.setScene("travel")      -- 行驶场景（引擎+风 + 行路BGM）
---   AudioMgr.setScene("settlement")  -- 聚落场景（聚落氛围 + 安宁BGM）
---   AudioMgr.update(dt)              -- 每帧调用，驱动淡入淡出

local Theme = require("ui.theme")

local M = {}

-- ── 配置 ──────────────────────────────────────────────
local FADE_TIME = 2.5  -- 交叉淡入淡出秒数

--- 场景定义 { bgm = "track_key", ambient = { layer_key = targetGain, ... } }
--- targetGain 是该层在 _ambientVolume=1 时的相对音量
local SCENES = {
    travel = {
        bgm     = "bgm_travel",
        ambient = { engine = 0.40, wind = 0.25 },
    },
    settlement = {
        bgm     = "bgm_settlement",
        ambient = { settlement = 0.30 },
    },
    campfire = {
        bgm     = "bgm_campfire",
        ambient = { campfire = 0.40, wind = 0.12 },
    },
    silent = {
        bgm     = nil,
        ambient = {},
    },
}

-- ── 内部状态 ──────────────────────────────────────────
local _initialized = false
local _currentScene = nil

-- BGM —— 双 SoundSource 交叉淡入淡出
---@type Node
local _bgmNode = nil
---@type SoundSource
local _bgmA = nil          -- 当前正在播放 / 淡入中
---@type SoundSource
local _bgmB = nil          -- 正在淡出的旧曲
local _bgmCurrentKey = nil -- 当前 BGM 资源 key（与 Theme.bgm 对应）
local _bgmFadeTimer  = 0   -- >0 时正在过渡
local _bgmVolume     = 0.45 -- BGM 基础音量

-- Ambient —— 多层独立 SoundSource，各自淡入淡出
---@type Node
local _ambientNode = nil
--- { [layerKey] = { source:SoundSource, cur:number, target:number } }
local _ambientLayers  = {}
local _ambientVolume  = 0.55 -- 环境音基础音量

-- 资源缓存
local _soundCache = {}

-- ── 工具函数 ─────────────────────────────────────────

--- 加载并缓存 Sound 资源，自动标记为循环
---@param path string
---@return Sound|nil
local function getSound(path)
    if _soundCache[path] then return _soundCache[path] end
    local snd = cache:GetResource("Sound", path)
    if snd then
        snd.looped = true
        _soundCache[path] = snd
    else
        log:Write(LOG_WARNING, "[AudioMgr] Failed to load: " .. path)
    end
    return snd
end

--- 延迟初始化节点和组件
local function ensureInit()
    if _initialized then return end
    _initialized = true

    local sc = scene_ or Scene()
    _bgmNode     = sc:CreateChild("_AudioBGM")
    _ambientNode = sc:CreateChild("_AudioAmbient")

    _bgmA = _bgmNode:CreateComponent("SoundSource")
    _bgmA.soundType = "Music"
    _bgmA.gain = 0

    _bgmB = _bgmNode:CreateComponent("SoundSource")
    _bgmB.soundType = "Music"
    _bgmB.gain = 0
end

--- 获取或创建环境音层
---@param key string
---@return table { source, cur, target }
local function getLayer(key)
    if _ambientLayers[key] then return _ambientLayers[key] end

    local src = _ambientNode:CreateComponent("SoundSource")
    src.soundType = "Ambient"
    src.gain = 0

    local layer = { source = src, cur = 0, target = 0 }
    _ambientLayers[key] = layer
    return layer
end

-- ── 公共 API ─────────────────────────────────────────

--- 切换到指定场景（travel / settlement / campfire / silent）
--- 如果场景名与当前相同，不做任何事
---@param sceneName string
function M.setScene(sceneName)
    if _currentScene == sceneName then return end
    local def = SCENES[sceneName]
    if not def then
        log:Write(LOG_WARNING, "[AudioMgr] Unknown scene: " .. tostring(sceneName))
        return
    end
    ensureInit()
    _currentScene = sceneName

    -- ── BGM 交叉淡入淡出 ──
    local newKey = def.bgm
    if newKey ~= _bgmCurrentKey then
        -- 把 A（当前）交换到 B（淡出），新曲放 A（淡入）
        _bgmA, _bgmB = _bgmB, _bgmA

        if newKey then
            local path = Theme.bgm and Theme.bgm[newKey]
            if path then
                local snd = getSound(path)
                if snd then
                    _bgmA:Play(snd, snd.frequency, 0)
                end
            end
        else
            _bgmA:Stop()
        end

        _bgmCurrentKey = newKey
        _bgmFadeTimer  = FADE_TIME
    end

    -- ── 环境音层目标 ──
    -- 先把所有层的目标置 0
    for _, layer in pairs(_ambientLayers) do
        layer.target = 0
    end
    -- 激活该场景需要的层
    for layerKey, gain in pairs(def.ambient) do
        local layer = getLayer(layerKey)
        layer.target = gain
        -- 如果该层未在播放，启动它
        if not layer.source:IsPlaying() then
            local path = Theme.ambient and Theme.ambient[layerKey]
            if path then
                local snd = getSound(path)
                if snd then
                    layer.source:Play(snd, snd.frequency, 0)
                end
            end
        end
    end
end

--- 每帧调用，驱动所有淡入淡出
---@param dt number
function M.update(dt)
    if not _initialized then return end

    -- ── BGM 淡入淡出 ──
    if _bgmFadeTimer > 0 then
        _bgmFadeTimer = math.max(0, _bgmFadeTimer - dt)
        local t = 1.0 - (_bgmFadeTimer / FADE_TIME)  -- 0→1

        -- A 淡入
        if _bgmA:IsPlaying() then
            _bgmA.gain = t * _bgmVolume
        end
        -- B 淡出
        if _bgmB:IsPlaying() then
            _bgmB.gain = (1 - t) * _bgmVolume
            if t >= 1.0 then
                _bgmB:Stop()
                _bgmB.gain = 0
            end
        end
    end

    -- ── 环境音层平滑过渡 ──
    local fadeSpeed = 1.0 / FADE_TIME
    for _, layer in pairs(_ambientLayers) do
        local goal = layer.target * _ambientVolume
        local cur  = layer.cur
        if math.abs(cur - goal) > 0.001 then
            if cur < goal then
                cur = math.min(goal, cur + fadeSpeed * _ambientVolume * dt)
            else
                cur = math.max(goal, cur - fadeSpeed * _ambientVolume * dt)
            end
            layer.cur = cur
            layer.source.gain = cur
        end
        -- 已完全静音且目标为 0 → 停止播放以释放资源
        if layer.target == 0 and cur < 0.001 and layer.source:IsPlaying() then
            layer.source:Stop()
            layer.cur = 0
            layer.source.gain = 0
        end
    end
end

--- 设置 BGM 基础音量 (0~1)
---@param vol number
function M.setBgmVolume(vol)
    _bgmVolume = math.max(0, math.min(1, vol))
end

--- 设置环境音基础音量 (0~1)
---@param vol number
function M.setAmbientVolume(vol)
    _ambientVolume = math.max(0, math.min(1, vol))
end

--- 获取当前场景名
---@return string|nil
function M.getScene()
    return _currentScene
end

-- ── 收音机音频（独立于场景，由收音机开关 + 播报状态控制）────
-- 两层：底噪（radio开就有） + 模糊女声播报（有文本播报时才有）

--- { [key] = { source:SoundSource, cur:number, target:number } }
local _radioLayers = {}
local _radioGains  = {
    radio_static = 0.10,  -- 底噪：衬底级别
    radio_voice  = 0.14,  -- 模糊女声：比底噪稍响但仍是氛围
}

--- 确保收音机音频层已创建
local function ensureRadioLayer(key)
    if _radioLayers[key] then return _radioLayers[key] end
    ensureInit()
    local src = _ambientNode:CreateComponent("SoundSource")
    src.soundType = "Ambient"
    src.gain = 0
    local layer = { source = src, cur = 0, target = 0 }
    _radioLayers[key] = layer
    return layer
end

--- 内部：设置某一收音机层的开关
local function setRadioLayerEnabled(key, enabled)
    local layer = ensureRadioLayer(key)
    local newTarget = enabled and (_radioGains[key] or 0.10) or 0
    if layer.target == newTarget then return end
    layer.target = newTarget

    if enabled and not layer.source:IsPlaying() then
        local path = Theme.ambient and Theme.ambient[key]
        if path then
            local snd = getSound(path)
            if snd then
                layer.source:Play(snd, snd.frequency, 0)
            end
        end
    end
end

--- 设置收音机底噪开关（收音机开 → 开，收音机关 → 关）
---@param enabled boolean
function M.setRadioNoise(enabled)
    setRadioLayerEnabled("radio_static", enabled)
    -- 收音机关闭时，播报人声也一起关
    if not enabled then
        setRadioLayerEnabled("radio_voice", false)
    end
end

--- 设置收音机播报人声开关（有广播文本 → 开，无广播 → 关）
---@param enabled boolean
function M.setRadioVoice(enabled)
    setRadioLayerEnabled("radio_voice", enabled)
end

--- 内部：驱动所有收音机层的淡入淡出
local function updateRadioLayers(dt)
    local fadeSpeed = 1.0 / FADE_TIME
    for key, layer in pairs(_radioLayers) do
        local baseGain = _radioGains[key] or 0.10
        local goal = layer.target
        local cur  = layer.cur
        if math.abs(cur - goal) > 0.001 then
            if cur < goal then
                cur = math.min(goal, cur + fadeSpeed * baseGain * dt)
            else
                cur = math.max(goal, cur - fadeSpeed * baseGain * dt)
            end
            layer.cur = cur
            layer.source.gain = cur
        end
        if goal == 0 and cur < 0.001 and layer.source:IsPlaying() then
            layer.source:Stop()
            layer.cur = 0
            layer.source.gain = 0
        end
    end
end

-- 把收音机层驱动挂入 update
local _origUpdate = M.update
function M.update(dt)
    _origUpdate(dt)
    updateRadioLayers(dt)
end

return M

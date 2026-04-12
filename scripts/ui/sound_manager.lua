--- sound_manager.lua
--- 集中式 UI 音效播放管理器
--- 用法:
---   local SoundMgr = require("ui.sound_manager")
---   SoundMgr.play("click")      -- 播放按钮点击音
---   SoundMgr.play("coins")      -- 播放金币音效
---   SoundMgr.setVolume(0.5)     -- 设置 UI 音效总音量

local Theme = require("ui.theme")

local M = {}

--- 已缓存的 Sound 资源 { [name] = Sound }
---@type table<string, Sound>
local soundCache = {}

--- 用于播放 UI 音效的节点和组件（延迟创建）
---@type Node
local soundNode = nil
---@type SoundSource
local soundSource = nil

--- 多通道支持：额外的 SoundSource 池，用于并发播放
local NUM_EXTRA_CHANNELS = 3
---@type SoundSource[]
local extraSources = {}
local nextChannel = 1

--- UI 音效音量 (0~1)
local masterVolume = 0.7

--- 需要随机化的音效及其 pitch 抖动范围（半音比例）
--- pitch 1.0 = 原始音调；范围 ±0.08 约 ±1.3 半音，听感自然不突兀
local RANDOMIZE = {
    click      = { pitchRange = 0.08, gainRange = 0.06 },
    click_soft = { pitchRange = 0.05, gainRange = 0.04 },
    coins      = { pitchRange = 0.06, gainRange = 0.05 },
    open       = { pitchRange = 0.03, gainRange = 0.03 },
    close      = { pitchRange = 0.03, gainRange = 0.03 },
    depart     = { pitchRange = 0.04, gainRange = 0.05 },
    event      = { pitchRange = 0.05, gainRange = 0.04 },
    bubble_pop = { pitchRange = 0.10, gainRange = 0.05 },
    pickup     = { pitchRange = 0.10, gainRange = 0.06 },
}

--- 确保播放组件已初始化
local function ensureInit()
    if soundNode then return end
    -- 从全局 scene_ 创建节点；如果 scene_ 不存在则用一个空 Scene
    local sc = scene_ or Scene()
    soundNode = sc:CreateChild("UISoundNode")
    soundSource = soundNode:CreateComponent("SoundSource")
    soundSource.soundType = "Effect"
    soundSource.gain = masterVolume
    -- 创建额外通道，支持多音效并发
    for i = 1, NUM_EXTRA_CHANNELS do
        local src = soundNode:CreateComponent("SoundSource")
        src.soundType = "Effect"
        src.gain = masterVolume
        extraSources[i] = src
    end
end

--- 获取或缓存 Sound 资源
---@param name string 音效名称（对应 Theme.sounds 表中的 key）
---@return Sound|nil
local function getSound(name)
    if soundCache[name] then
        return soundCache[name]
    end
    local path = Theme.sounds[name]
    if not path then
        log:Write(LOG_WARNING, "[SoundMgr] Unknown sound: " .. tostring(name))
        return nil
    end
    local snd = cache:GetResource("Sound", path)
    if snd then
        soundCache[name] = snd
    else
        log:Write(LOG_WARNING, "[SoundMgr] Failed to load: " .. path)
    end
    return snd
end

--- 播放指定名称的 UI 音效
--- 对配置了 RANDOMIZE 的音效自动施加 pitch/gain 微抖动，避免重复感
---@param name string 音效名称（click / click_soft / open / close / error / success / coins / warning）
---@param gain? number 可选音量覆盖 (0~1)
function M.play(name, gain)
    ensureInit()
    local snd = getSound(name)
    if not snd then return end

    -- 选择空闲通道；如果都在播放则轮询下一个
    local src = soundSource
    if soundSource:IsPlaying() then
        -- 找一个空闲的额外通道
        local found = false
        for i = 1, NUM_EXTRA_CHANNELS do
            if not extraSources[i]:IsPlaying() then
                src = extraSources[i]
                found = true
                break
            end
        end
        if not found then
            -- 全部占用，轮询覆盖最旧的通道
            src = extraSources[nextChannel]
            nextChannel = (nextChannel % NUM_EXTRA_CHANNELS) + 1
        end
    end

    local baseGain = gain or masterVolume
    local rand = RANDOMIZE[name]
    if rand then
        -- 随机 pitch：以原始采样频率为基准上下浮动
        local baseFreq = snd.frequency  -- 原始采样率（如 44100）
        local pitchMul = 1.0 + (math.random() * 2 - 1) * rand.pitchRange
        local freq = baseFreq * pitchMul
        -- 随机 gain 微调
        local gAdj = 1.0 + (math.random() * 2 - 1) * rand.gainRange
        local g = math.max(0.05, math.min(1.0, baseGain * gAdj))
        src:Play(snd, freq, g)
    else
        src:Play(snd, snd.frequency, baseGain)
    end
end

--- 设置 UI 音效总音量
---@param vol number 0~1
function M.setVolume(vol)
    masterVolume = math.max(0, math.min(1, vol))
    if soundSource then
        soundSource.gain = masterVolume
        for i = 1, NUM_EXTRA_CHANNELS do
            if extraSources[i] then
                extraSources[i].gain = masterVolume
            end
        end
    end
end

--- 获取当前音量
---@return number
function M.getVolume()
    return masterVolume
end

--- 预加载所有 UI 音效（可选，在 Start 阶段调用减少首次播放延迟）
function M.preload()
    ensureInit()
    for name, _ in pairs(Theme.sounds) do
        getSound(name)
    end
end

return M

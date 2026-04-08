--- 随机事件池（配置驱动版）
--- 从 JSON 加载事件数据，合并 choice_sets/result_sets 为 UI 兼容格式
--- 支持 phase/scene/trigger_tags/多 flag 的扩展筛选
local Flags      = require("core/flags")
local DataLoader = require("data_loader/loader")

local M = {}

local CONFIG_PATH       = "configs/guaji_random_events.json"
local STORY_CONFIG_PATH = "configs/story_events.json"

-- ============================================================
-- 玩家可见描述文本（首批事件，后续迁移到 JSON 的 event_text 表）
-- ============================================================
local DESCRIPTIONS = {
    EVT_001 = "路边发现一个被遗弃的补给箱，看起来还完好。",
    EVT_003 = "一个疲惫的旅人在聚落边向你招手，希望搭一段路。",
    EVT_005 = "前方路标似乎被人挪动过，指向与记忆中不同的方向。",
    EVT_006 = "夜里醒来，发现窗边留着一张旧纸条。",
    EVT_007 = "车载收音机突然冒出断断续续的杂音，似乎夹着人声。",
    EVT_008 = "温室方面发来紧急消息，急需一批水泵配件。",
    EVT_009 = "后方扬起烟尘，几辆破旧摩托正在靠近。",
    EVT_010 = "整理货箱时，在角落发现了一个脏兮兮的布偶。",
    EVT_014 = "一夜翻来覆去没睡好，早上起来浑身酸痛。",
    EVT_020 = "聚落酒馆里有人小声议论着夜市的传闻。",
    EVT_032 = "前方一台失控的工业搬运机横冲直撞，机械臂不停挥舞，周围散落着被砸烂的货箱。",
    EVT_051 = "几辆焊着钢板的改装皮卡横在路中央，车上站着持枪的武装人员，示意你停车。",
    EVT_053 = "辐射雾中隐约可见数道车灯，一伙掠夺者从两侧包抄过来，切断了退路。",
    EVT_054 = "路边一栋半塌的建筑引起了陶夏的注意——里面可能还有没被搜刮干净的物资。",
    EVT_055 = "夜幕中突然传来摩托引擎的轰鸣，几束手电光从后方快速逼近。",
    EVT_056 = "林砾发现后视镜中一直跟着一辆装甲改装车，对方明显有备而来——是赏金猎人。",
    -- 主线剧情事件
    SEVT_001 = "货车发动的一瞬间，陶夏把车窗摇下来，风灌进来。林砾在副驾调整着后视镜。一切都是新的。",
    SEVT_002 = "第一次在野外过夜。篝火映着两张年轻的脸，远处什么都看不见。",
    SEVT_003 = "陶夏趴在方向盘上看地图，用笔圈了好几个没去过的地方。",
    SEVT_004 = "路面上有一道深深的车辙印，已经长了草。不是你们留下的。",
    SEVT_005 = "收拾营地时，一本翻开的笔记本从林砾的包里滑出来。",
    SEVT_006 = "收音机里突然传出一段断断续续的求助信号，来自温室社区。",
    SEVT_007 = "风吹过来几张泛黄的书页，上面的字迹工整得不像是末世的产物。",
    SEVT_008 = "深夜赶路时，远方地平线上有一盏灯在有节奏地闪烁。",
    SEVT_009 = "废墟方向升起了一缕炊烟，在灰色的天空下格外显眼。",
    SEVT_010 = "篝火旁，陶夏掰着手指数你们去过的地方。四个聚落，四种活法。",
}

-- ============================================================
-- 内部数据
-- ============================================================
M.EVENTS        = {}   -- array of UI-compatible event tables
M._events_by_id = {}   -- event_id -> event
M._choice_sets  = {}   -- choice_set_id -> [choice...]
M._result_sets  = {}   -- result_set_id -> [result...]
M._chains       = {}   -- chain definitions
M._loaded       = false

-- ============================================================
-- 配置加载
-- ============================================================

--- 从 JSON 加载事件配置（懒加载，只执行一次）
function M._load_config()
    if M._loaded then return end
    M._loaded = true

    local data = DataLoader.load(CONFIG_PATH)
    if not data then
        print("[EventPool] Config not found, no events available")
        return
    end

    M._choice_sets = data.choice_sets or {}
    M._result_sets = data.result_sets or {}
    M._chains      = data.chains or {}

    M.EVENTS = {}
    M._events_by_id = {}

    for _, raw in ipairs(data.events or {}) do
        local evt = M._build_event(raw)
        table.insert(M.EVENTS, evt)
        M._events_by_id[evt.id] = evt
    end

    -- 分析链式事件：标记非起点事件需要解锁 flag
    M._build_chain_locks()

    print("[EventPool] Loaded " .. #M.EVENTS .. " events from config")

    -- 加载主线剧情事件（合并到同一个池中）
    M._load_story_events()
end

--- 加载主线剧情事件，合并到事件池
function M._load_story_events()
    local data = DataLoader.load(STORY_CONFIG_PATH)
    if not data then
        print("[EventPool] Story events config not found, skipping")
        return
    end

    -- 合并 choice_sets / result_sets
    for k, v in pairs(data.choice_sets or {}) do
        M._choice_sets[k] = v
    end
    for k, v in pairs(data.result_sets or {}) do
        M._result_sets[k] = v
    end

    local count = 0
    for _, raw in ipairs(data.events or {}) do
        local evt = M._build_event(raw)
        evt.is_story = true  -- 标记为主线事件
        evt.chapter  = raw.chapter
        table.insert(M.EVENTS, evt)
        M._events_by_id[evt.id] = evt
        count = count + 1
    end

    if count > 0 then
        -- 重新分析链式事件（主线事件也可能有链）
        M._build_chain_locks()
        print("[EventPool] Loaded " .. count .. " story events")
    end
end

--- 将 JSON 原始数据转换为 UI 兼容的事件表
---@param raw table JSON 中的 event 对象
---@return table
function M._build_event(raw)
    local evt = {
        id              = raw.event_id,
        title           = raw.event_name,
        description     = DESCRIPTIONS[raw.event_id] or raw.summary or "",
        pool            = raw.pool,
        weight          = raw.weight or 50,
        -- 扩展筛选字段
        phase           = raw.phase,
        scene           = raw.scene,
        cooldown_run    = raw.cooldown_run or 2,
        trigger_tags    = raw.trigger_tags or {},
        required_flags  = raw.required_flags or {},
        forbidden_flags = raw.forbidden_flags or {},
        next_event_id   = raw.next_event_id,
        summary         = raw.summary,
    }

    -- 合并 choice_sets + result_sets 为 choices 数组
    evt.choices = {}
    local cs = M._choice_sets[raw.choice_set_id]
    if cs then
        -- 构建 result_key -> result 的查找表
        local rs_map = {}
        local rs = M._result_sets[raw.result_set_id]
        if rs then
            for _, r in ipairs(rs) do
                rs_map[r.result_key] = r
            end
        end

        for _, c in ipairs(cs) do
            local result = rs_map[c.result_key] or {}
            table.insert(evt.choices, {
                choice_id      = c.choice_id,
                text           = c.choice_text,
                show_condition = c.show_condition or {},
                ops            = result.ops or {},
                result_text    = result.reward_desc or "",
                risk_desc      = result.risk_desc or "",
                set_flags      = result.set_flags or {},
                clear_flags    = result.clear_flags or {},
            })
        end
    end

    return evt
end

--- 分析链式事件关系，为非起点事件添加解锁 flag 需求
--- 例如 EVT_010 → EVT_023：EVT_023 的 required_flags 会自动加入 "unlock_EVT_023"
function M._build_chain_locks()
    -- 收集所有被 next_event_id 指向的事件 ID
    local chained_targets = {}
    for _, evt in ipairs(M.EVENTS) do
        if evt.next_event_id then
            chained_targets[evt.next_event_id] = true
        end
    end

    -- 为被指向的事件添加 required_flags
    for target_id, _ in pairs(chained_targets) do
        local target = M._events_by_id[target_id]
        if target then
            local unlock_flag = "unlock_" .. target_id
            -- 避免重复添加
            local already = false
            for _, f in ipairs(target.required_flags or {}) do
                if f == unlock_flag then already = true; break end
            end
            if not already then
                if not target.required_flags then target.required_flags = {} end
                table.insert(target.required_flags, unlock_flag)
            end
        end
    end
end

-- ============================================================
-- 筛选与抽取
-- ============================================================

--- 按条件筛选可用事件
---@param state table 游戏状态
---@param context table|nil { scene, active_tags, phase }
---@return table[] 可用事件列表
function M.filter(state, context)
    M._load_config()

    local available = {}
    local cooldowns = state._event_cooldowns or {}
    local ctx = context or {}

    for _, evt in ipairs(M.EVENTS) do
        local ok = true

        -- 1. 冷却检查
        if (cooldowns["cd_" .. evt.id] or 0) > 0 then
            ok = false
        end

        -- 2. required_flags: 全部必须存在
        if ok and evt.required_flags then
            for _, flag in ipairs(evt.required_flags) do
                if not Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        -- 3. forbidden_flags: 任一存在则排除
        if ok and evt.forbidden_flags then
            for _, flag in ipairs(evt.forbidden_flags) do
                if Flags.has(state, flag) then
                    ok = false
                    break
                end
            end
        end

        -- 4. phase 过滤（"all" 始终通过）
        if ok and ctx.phase and evt.phase and evt.phase ~= "all" then
            if evt.phase ~= ctx.phase then
                ok = false
            end
        end

        -- 5. scene 过滤（行驶中兼容多种场景）
        if ok and ctx.scene and evt.scene then
            if evt.scene ~= ctx.scene then
                -- drive 场景兼容：行驶途中也可触发路边/营地/收音机事件
                local drive_compat = {
                    route_node = true, camp = true, radio = true,
                }
                if ctx.scene ~= "drive" or not drive_compat[evt.scene] then
                    ok = false
                end
            end
        end

        -- 6. trigger_tags: 事件有标签要求时，至少一个活跃标签匹配
        if ok and evt.trigger_tags and #evt.trigger_tags > 0 and ctx.active_tags then
            local tag_match = false
            for _, tag in ipairs(evt.trigger_tags) do
                for _, active in ipairs(ctx.active_tags) do
                    if tag == active then
                        tag_match = true
                        break
                    end
                end
                if tag_match then break end
            end
            if not tag_match then ok = false end
        end

        -- 7. 检查是否有可见选项（show_condition 过滤后）
        if ok then
            local visible = M._visible_choices(evt, state)
            if #visible == 0 then ok = false end
        end

        if ok then
            table.insert(available, evt)
        end
    end

    return available
end

--- 过滤出当前可见的选项
---@param evt table
---@param state table
---@return table[]
function M._visible_choices(evt, state)
    local visible = {}
    for _, choice in ipairs(evt.choices or {}) do
        local show = true
        if choice.show_condition and #choice.show_condition > 0 then
            for _, cond in ipairs(choice.show_condition) do
                if not Flags.has(state, cond) and not M._check_module_condition(state, cond) then
                    show = false
                    break
                end
            end
        end
        if show then
            table.insert(visible, choice)
        end
    end
    return visible
end

--- 检查车辆模块等非旗标条件
---@param state table
---@param cond string
---@return boolean
function M._check_module_condition(state, cond)
    local modules = state.truck and state.truck.modules or {}
    if cond == "has_radar"        then return (modules.radar or 0) > 0 end
    if cond == "has_weapon"       then return (modules.turret or 0) > 0 end
    if cond == "has_cold_storage" then return (modules.cold_storage or 0) > 0 end
    return false
end

--- 获取关系值等级（用于事件权重调整）
---@param state table
---@return number 0~3
local function get_relation_tier(state)
    local r = 0
    if state.character then
        r = math.max(
            state.character.linli  and state.character.linli.relation  or 0,
            state.character.taoxia and state.character.taoxia.relation or 0
        )
    end
    if r >= 30 then return 3 end
    if r >= 15 then return 2 end
    if r >= 5  then return 1 end
    return 0
end

--- 加权随机选择一个事件
--- 关系值影响：高关系 → bond 事件权重提升, danger 降低
---@param state table
---@param context table|nil
---@return table|nil
function M.pick(state, context)
    local pool = M.filter(state, context)
    if #pool == 0 then return nil end

    local rel_tier = get_relation_tier(state)

    local tw = 0
    local weights = {}
    for i, e in ipairs(pool) do
        local w = e.weight or 1
        -- 关系值调整事件权重
        if rel_tier >= 1 then
            if e.pool == "bond" then
                w = w * (1 + rel_tier * 0.3)  -- bond 事件权重 +30%/60%/90%
            elseif e.pool == "danger" and rel_tier >= 2 then
                w = w * 0.8                    -- danger 事件权重 -20%（团队默契高）
            end
        end
        weights[i] = w
        tw = tw + w
    end

    local roll = math.random() * tw
    local acc = 0
    for i, e in ipairs(pool) do
        acc = acc + weights[i]
        if roll <= acc then return e end
    end
    return pool[#pool]
end

--- 按 ID 获取事件
---@param id string
---@return table|nil
function M.get(id)
    M._load_config()
    return M._events_by_id[id]
end

-- ============================================================
-- 冷却管理
-- ============================================================

--- 设置事件冷却（使用事件自身的 cooldown_run 值）
function M.set_cooldown(state, event_id, turns)
    if not state._event_cooldowns then state._event_cooldowns = {} end
    local evt = M._events_by_id[event_id]
    local cd = turns or (evt and evt.cooldown_run) or 3
    state._event_cooldowns["cd_" .. event_id] = cd
end

--- 所有冷却递减 1
function M.tick_cooldowns(state)
    if not state._event_cooldowns then return end
    for k, v in pairs(state._event_cooldowns) do
        if v > 0 then state._event_cooldowns[k] = v - 1 end
    end
end

return M

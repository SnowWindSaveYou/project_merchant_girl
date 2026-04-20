--- 新手教程引导系统（数据驱动）
--- 所有阶段定义集中在 PHASE_DEFS 表中，新增阶段只需加一个条目。
--- 旧存档无 tutorial_started flag 时整个教程跳过。
local Flags        = require("core/flags")
local DialoguePool = require("narrative/dialogue_pool")
local Graph        = require("map/world_graph")
local Theme        = require("ui/theme")

local M = {}

-- ============================================================
-- 气泡头像（引用 Theme.avatars，各模块共用）
-- ============================================================
M.AVATAR_LINLI  = Theme.avatars.linli
M.AVATAR_TAOXIA = Theme.avatars.taoxia

-- ============================================================
-- 教程阶段常量（向后兼容，其他文件仍可用 Tutorial.Phase.SPAWN 等）
-- ============================================================
M.Phase = {
    NONE                = "none",
    SPAWN               = "spawn",
    TRAVEL_TO_GREENHOUSE = "travel_to_greenhouse",
    AT_GREENHOUSE       = "at_greenhouse",
    RETURN_JOURNEY      = "return_journey",  -- 返程探索阶段（步骤4-7）
    EXPLORE_TO_RUINS    = "explore_to_ruins", -- 去废墟（剧情驱动的探索）
    COMPLETE            = "complete",
}

-- ============================================================
-- 教程订单工厂（PHASE_DEFS 中的 order.make 引用）
-- ============================================================

--- 检查 order_book 中是否已接取指定目的地的教程订单
---@param state table
---@param dest string 目的地 node_id
---@return boolean
local function has_accepted_tutorial_order_to(state, dest)
    local book = state.economy and state.economy.order_book or {}
    for _, o in ipairs(book) do
        if o.is_tutorial and o.to == dest
            and (o.status == "accepted" or o.status == "loaded") then
            return true
        end
    end
    return false
end

--- 生成温室农场→温室社区的教程订单
local function make_order_to_greenhouse()
    return {
        order_id     = "tutorial_order_1",
        from         = "greenhouse_farm",
        to           = "greenhouse",
        from_name    = Graph.get_node_name("greenhouse_farm") or "外围农场",
        to_name      = Graph.get_node_name("greenhouse") or "温室社区",
        goods_id     = "food_can",
        goods_name   = "罐头食品",
        count        = 2,
        base_reward  = 50,
        deadline_sec = 9999,
        risk_level   = "low",
        status       = "available",
        accepted_at  = nil,
        description  = "运送罐头食品 ×2 到温室社区",
        is_tutorial  = true,
    }
end

--- 生成温室社区→废墟营地的教程订单
local function make_order_to_ruins()
    return {
        order_id     = "tutorial_order_2",
        from         = "greenhouse",
        to           = "ruins_camp",
        from_name    = Graph.get_node_name("greenhouse") or "温室社区",
        to_name      = Graph.get_node_name("ruins_camp") or "废墟游民营地",
        goods_id     = "medicine",
        goods_name   = "基础药品",
        count        = 1,
        base_reward  = 80,
        deadline_sec = 9999,
        risk_level   = "low",
        status       = "available",
        accepted_at  = nil,
        description  = "运送基础药品 ×1 到废墟游民营地",
        is_tutorial  = true,
    }
end

--- 生成温室社区→外围农场的返程教程订单（序章探索用）
local function make_order_return_to_farm()
    return {
        order_id     = "tutorial_order_return",
        from         = "greenhouse",
        to           = "greenhouse_farm",
        from_name    = Graph.get_node_name("greenhouse") or "温室社区",
        to_name      = Graph.get_node_name("greenhouse_farm") or "外围农场",
        goods_id     = "vegetables",
        goods_name   = "新鲜蔬菜",
        count        = 3,
        base_reward  = 40,
        deadline_sec = 9999,
        risk_level   = "low",
        status       = "available",
        accepted_at  = nil,
        description  = "运送新鲜蔬菜 ×3 返回外围农场",
        is_tutorial  = true,
    }
end

-- ============================================================
-- 阶段定义表（按时间顺序，新增阶段只需在此处插入条目）
--
-- 每个条目可包含：
--   id              : string  阶段 ID（与 M.Phase 常量对应）
--   check(state)    : 返回 true 表示该阶段的前置条件已满足
--   completion_flag : string|nil  该阶段完成时设置的 flag
--   home_buttons    : string[]|nil  首页按钮白名单
--                     可选值: "npc", "orders", "shop", "map", "campfire"
--   highlight(state): 返回 { btn_name = true } 表示高亮按钮
--   hide_departure  : boolean  首页是否隐藏出发按钮
--   block_map       : boolean  地图是否禁止点击非当前/非目标节点
--   block_explore   : boolean  地图是否禁止探索未知区域
--   order           : { node, make, condition? }  教程订单配置
--   on_arrival      : { [node_id] = dialogue_id }  到达拦截配置
--   bubbles         : { [screen] = config|function(state) }  气泡配置
-- ============================================================

---@type table[]
M.PHASE_DEFS = {
    -- ① SPAWN：在车厂（外围农场），引导接单去温室社区
    {
        id = "spawn",
        check = function(_state)
            return true  -- fallback：tutorial_started 已设时的默认阶段
        end,
        home_buttons   = { "orders" },
        highlight      = function(_state) return { orders = true } end,
        hide_departure = true,
        block_map      = true,
        block_explore  = true,
        order = {
            node = "greenhouse_farm",
            make = make_order_to_greenhouse,
        },
        bubbles = {
            home = {
                portrait = M.AVATAR_LINLI,
                speaker  = "林砾",
                text     = "这里是外围农场。先接个单，去温室社区看看。",
                position = { x = "50%", y = "65%" },
                autoHide = 0,
            },
        },
    },

    -- ② TRAVEL_TO_GREENHOUSE：正在前往温室社区
    {
        id = "travel_to_greenhouse",
        check = function(state)
            local book = state.economy and state.economy.order_book or {}
            for _, o in ipairs(book) do
                if o.is_tutorial and o.to == "greenhouse"
                    and (o.status == "accepted" or o.status == "loaded") then
                    return true
                end
            end
            return false
        end,
        block_map     = true,
        block_explore = true,
        -- 行驶中不在首页，无需 home_buttons/bubbles
    },

    -- ③ AT_GREENHOUSE：抵达温室社区，引导使用交易所
    {
        id = "at_greenhouse",
        check = function(state)
            return Flags.has(state, "tutorial_arrived_greenhouse")
        end,
        completion_flag = "tutorial_shop_intro",
        home_buttons    = { "npc", "shop", "orders", "campfire" },
        highlight       = function(_state) return { shop = true } end,
        hide_departure  = true,
        on_arrival = {
            greenhouse = { dialogue = "SD_TUTORIAL_GREENHOUSE_ARRIVAL", guard_flag = "tutorial_arrived_greenhouse" },
        },
        bubbles = {
            home = {
                portrait = M.AVATAR_TAOXIA,
                speaker  = "陶夏",
                text     = "先去交易所看看——看看有什么货和单子！",
                position = { x = "50%", y = "65%" },
                autoHide = 0,
            },
        },
    },

    -- ④ RETURN_JOURNEY：返程探索阶段
    -- 玩家接返程订单，到达特定节点触发 SD_PROLOGUE_04~06（水渠、蘑菇洞、信号中继站）
    -- 完成后回到农场，触发 SD_PROLOGUE_07，沈禾提示废墟有生意
    -- 04/05/06 由 StoryDirector 在到达对应节点时自动触发（node_ids 限定）
    {
        id = "return_journey",
        check = function(state)
            return Flags.has(state, "tutorial_shop_intro")
        end,
        completion_flag = "prologue_can_go_ruins",  -- SD_PROLOGUE_07 完成后设置
        home_buttons    = { "npc", "orders", "shop", "map", "campfire" },
        highlight = function(state)
            -- 如果已接返程订单，高亮地图；否则高亮订单
            return has_accepted_tutorial_order_to(state, "greenhouse_farm")
                and { map = true } or { orders = true }
        end,
        hide_departure = true,
        -- 接返程订单时解锁周边探索节点
        discover_nodes = { "irrigation_canal", "mushroom_cave", "signal_relay" },
        -- 探索边界：07完成前阻止进入外围节点
        blocked_nodes = {
            "danger_pass", "crossroads", "old_warehouse", "sunken_plaza", "junkyard",
        },
        order = {
            node      = "greenhouse",
            make      = make_order_return_to_farm,
            condition = function(state)
                return not has_accepted_tutorial_order_to(state, "greenhouse_farm")
            end,
        },
        on_arrival = {
            -- 回到农场时触发序章完结对话（需要 04/05/06 全部完成）
            greenhouse_farm = { dialogue = "SD_PROLOGUE_07", guard_flag = "prologue_can_go_ruins" },
        },
        bubbles = {
            home = function(state)
                if not has_accepted_tutorial_order_to(state, "greenhouse_farm") then
                    -- 还没接返程订单：引导去接单
                    return {
                        {
                            portrait = M.AVATAR_LINLI,
                            speaker  = "林砾",
                            text     = "……有一批新鲜蔬菜要送回农场。沈禾姐托的。",
                        },
                        {
                            portrait = M.AVATAR_TAOXIA,
                            speaker  = "陶夏",
                            text     = "好嘞，正好回去的路上还能看看周围有什么。",
                        },
                        {
                            portrait = M.AVATAR_LINLI,
                            speaker  = "林砾",
                            text     = "……先去接委托吧。",
                        },
                    }
                end
                -- 已接单但还没探索完周边
                local done04 = Flags.has(state, "sd_prologue_04_done")
                local done05 = Flags.has(state, "sd_prologue_05_done")
                local done06 = Flags.has(state, "sd_prologue_06_done")
                local all_explored = done04 and done05 and done06
                if not all_explored then
                    -- 根据剩余数量和具体地点动态生成提示
                    local missing = {}
                    if not done04 then table.insert(missing, "水渠") end
                    if not done05 then table.insert(missing, "蘑菇洞") end
                    if not done06 then table.insert(missing, "信号站") end
                    local n = #missing
                    local placesStr = table.concat(missing, "、")
                    -- 根据剩余数量调整语气
                    local taoxiaLine, linliLine
                    if n == 1 then
                        taoxiaLine = "就差" .. placesStr .. "没去了吧？快去看看！"
                        linliLine  = "……嗯。去完就可以回农场了。"
                    else
                        taoxiaLine = "地图上还有几个没去过的地方呢，要不顺路看看？"
                        linliLine  = "……" .. placesStr .. "还没去过。回去之前，顺路看看。"
                    end
                    return {
                        {
                            portrait = M.AVATAR_TAOXIA,
                            speaker  = "陶夏",
                            text     = taoxiaLine,
                        },
                        {
                            portrait = M.AVATAR_LINLI,
                            speaker  = "林砾",
                            text     = linliLine,
                        },
                    }
                end
                -- 全部探索完，该回农场了
                return {
                    {
                        portrait = M.AVATAR_TAOXIA,
                        speaker  = "陶夏",
                        text     = "周围都逛了一圈了——收获不少呢。",
                    },
                    {
                        portrait = M.AVATAR_LINLI,
                        speaker  = "林砾",
                        text     = "……嗯。该回农场了。趁天还没黑，赶紧出发。",
                    },
                }
            end,
            map = function(state)
                -- 已接单且还没全部探索时，在地图上提示
                if has_accepted_tutorial_order_to(state, "greenhouse_farm")
                    and not (Flags.has(state, "sd_prologue_04_done")
                        and Flags.has(state, "sd_prologue_05_done")
                        and Flags.has(state, "sd_prologue_06_done")) then
                    return {
                        {
                            portrait = M.AVATAR_LINLI,
                            speaker  = "林砾",
                            text     = "……地图上有几个标记点。顺路看看，不急着回去。",
                        },
                    }
                end
                return nil
            end,
        },
    },

    -- ⑤ EXPLORE_TO_RUINS：去废墟营地（剧情驱动）
    -- SD_PROLOGUE_07 中沈禾提到废墟有生意，玩家有充分理由去探索
    {
        id = "explore_to_ruins",
        check = function(state)
            return Flags.has(state, "prologue_can_go_ruins")
        end,
        completion_flag = "tutorial_explore_done",
        home_buttons    = { "npc", "orders", "shop", "map", "campfire" },
        highlight = function(state)
            return has_accepted_tutorial_order_to(state, "ruins_camp")
                and { map = true } or { orders = true }
        end,
        hide_departure = true,
        order = {
            node      = "greenhouse",
            make      = make_order_to_ruins,
            condition = function(state)
                return not has_accepted_tutorial_order_to(state, "ruins_camp")
            end,
        },
        on_arrival = {
            ruins_camp = { dialogue = "SD_TUTORIAL_RUINS_ARRIVAL", guard_flag = "tutorial_explore_done" },
        },
        bubbles = {
            home = function(state)
                if not has_accepted_tutorial_order_to(state, "ruins_camp") then
                    return {
                        portrait = M.AVATAR_TAOXIA,
                        speaker  = "陶夏",
                        text     = "沈禾姐说废墟那边有生意做，去看看！",
                        position = { x = "50%", y = "65%" },
                        autoHide = 0,
                    }
                else
                    return {
                        portrait = M.AVATAR_LINLI,
                        speaker  = "林砾",
                        text     = "……去地图看看。得先探索未知区域，打通前往废墟营地的路。",
                        position = { x = "50%", y = "65%" },
                        autoHide = 0,
                    }
                end
            end,
            map = {
                portrait = M.AVATAR_TAOXIA,
                speaker  = "陶夏",
                text     = "看到那些问号了吗？点一下试试——说不定能发现新的路！",
                position = { x = "50%", y = "85%" },
                autoHide = 0,
            },
        },
    },

    -- ↑ 未来新增阶段在此处插入 ↑
}

-- ============================================================
-- 不属于阶段推进、但调试跳过需要设置的功能教学 flags
-- ============================================================
M.EXTRA_FLAGS = {
    "tutorial_first_departure_done",
    "tutorial_truck_intro",
    "tutorial_radio_intro",
    "tutorial_auto_plan_intro",
    "tutorial_explore_scavenge",
    "tutorial_route_explore",
    "tutorial_arrived_tower",
    -- 序章相关 flags
    "sd_prologue_01_done",
    "sd_prologue_02_done",
    "sd_prologue_03_done",
    "sd_prologue_04_done",
    "sd_prologue_05_done",
    "sd_prologue_06_done",
    "found_ruins_traced",
    "prologue_can_go_ruins",
}

-- ============================================================
-- 阶段推导（从 PHASE_DEFS 表自动推导）
-- ============================================================

--- 根据 flags 推导当前教程阶段
--- 返回 (phaseId, phaseDef|nil)
--- phaseDef 为 PHASE_DEFS 中的条目，NONE/COMPLETE 时为 nil
---@param state table
---@return string phase, table|nil phaseDef
function M.get_phase(state)
    -- 旧存档或教程从未开始
    if not Flags.has(state, "tutorial_started") then
        return M.Phase.NONE, nil
    end

    -- 最后阶段的 completion_flag 已设 → 教程完成
    local lastDef = M.PHASE_DEFS[#M.PHASE_DEFS]
    if lastDef and lastDef.completion_flag
        and Flags.has(state, lastDef.completion_flag) then
        return M.Phase.COMPLETE, nil
    end

    -- 从最后一个阶段向前检查，第一个 check() 为 true 的就是当前阶段
    for i = #M.PHASE_DEFS, 1, -1 do
        local def = M.PHASE_DEFS[i]
        if def.check(state) then
            return def.id, def
        end
    end

    -- 不应到达此处，但防御性返回
    return M.Phase.SPAWN, M.PHASE_DEFS[1]
end

--- 教程是否已完成（或从未开始）
---@param state table
---@return boolean
function M.is_complete(state)
    local phase = M.get_phase(state)
    return phase == M.Phase.NONE or phase == M.Phase.COMPLETE
end

-- ============================================================
-- 自动派生：调试用 flag 列表
-- ============================================================

--- 获取跳过教程需要设置的全部 flags（供 screen_debug 使用）
---@return string[]
function M.get_all_flags()
    local flags = { "tutorial_started" }
    -- 从阶段定义中收集 completion_flag
    for _, def in ipairs(M.PHASE_DEFS) do
        if def.completion_flag then
            table.insert(flags, def.completion_flag)
        end
    end
    -- 功能教学 flags
    for _, f in ipairs(M.EXTRA_FLAGS) do
        table.insert(flags, f)
    end
    return flags
end

-- ============================================================
-- 教程订单（从 phaseDef.order 读取）
-- ============================================================

--- 获取教程专属订单（替代正常订单生成）
--- 返回 nil 表示不干预，由正常逻辑生成订单
---@param state table
---@param node_id string 当前到达的聚落
---@return table[]|nil orders
function M.get_tutorial_orders(state, node_id)
    local _phase, def = M.get_phase(state)
    if not def or not def.order then return nil end

    local ord = def.order
    if ord.node ~= node_id then return nil end
    if ord.condition and not ord.condition(state) then return nil end

    -- 阶段级节点发现（幂等，可重复调用）
    if def.discover_nodes and state.map.known_nodes then
        for _, nid in ipairs(def.discover_nodes) do
            if not state.map.known_nodes[nid] then
                state.map.known_nodes[nid] = true
                print("[Tutorial] Discovered exploration node: " .. nid)
            end
        end
    end

    return { ord.make() }
end

-- ============================================================
-- 到达拦截（从 phaseDef.on_arrival 读取）
-- ============================================================

--- 节点到达时的教程拦截
--- 返回拦截指令或 nil（不干预）
--- 注意：此函数在 Flow.handle_node_arrival **之前**调用（main.lua handleNodeArrival），
---       若返回拦截，到达处理（交付/结算）会被延迟到对话结束后执行
---@param state table
---@param node_id string
---@return table|nil action  { type = "dialogue", dialogue = DialogueData }
function M.on_arrival(state, node_id)
    if not Flags.has(state, "tutorial_started") then return nil end

    -- 从当前阶段及之前所有未完成阶段的 on_arrival 中查找匹配
    -- （主要处理当前阶段，但也兼容跨阶段到达）
    for _, def in ipairs(M.PHASE_DEFS) do
        if def.on_arrival and def.on_arrival[node_id] then
            local entry = def.on_arrival[node_id]
            -- 支持两种格式：
            --   旧格式（字符串）: node_id = "DIALOGUE_ID"
            --   新格式（表）:     node_id = { dialogue = "DIALOGUE_ID", guard_flag = "flag_name" }
            local dialogueId, guardFlag
            if type(entry) == "table" then
                dialogueId = entry.dialogue
                guardFlag  = entry.guard_flag
            else
                dialogueId = entry
                guardFlag  = nil
            end

            -- 用 guard_flag 判断是否已播放过；无 guard_flag 时回退到 completion_flag
            local flag = guardFlag or def.completion_flag
            if not flag or not Flags.has(state, flag) then
                local dialogue = DialoguePool.get(dialogueId)
                if dialogue then
                    -- 检查对话自身的 required_flags / forbidden_flags
                    -- 防止玩家以非预期顺序到达节点时跳序播放对话
                    local flags_ok = true
                    if dialogue.required_flags then
                        for _, rf in ipairs(dialogue.required_flags) do
                            if not Flags.has(state, rf) then
                                flags_ok = false
                                break
                            end
                        end
                    end
                    if flags_ok and dialogue.forbidden_flags then
                        for _, ff in ipairs(dialogue.forbidden_flags) do
                            if Flags.has(state, ff) then
                                flags_ok = false
                                break
                            end
                        end
                    end
                    if flags_ok then
                        return { type = "dialogue", dialogue = dialogue }
                    end
                end
            end
        end
    end

    return nil
end

-- ============================================================
-- 气泡配置（从 phaseDef.bubbles 读取）
-- ============================================================

--- 获取当前应显示的引导气泡配置
--- 返回 nil 表示不显示气泡
--- 返回值可能是单条 config 或多步数组 config[]
---@param state table
---@param screen string  当前屏幕名 ("home" | "map")
---@return table|table[]|nil config  单条 { portrait, speaker, text } 或多步数组
function M.get_bubble_config(state, screen)
    local _phase, def = M.get_phase(state)
    if not def or not def.bubbles then return nil end

    local entry = def.bubbles[screen]
    if not entry then return nil end

    -- 支持静态表或动态函数
    if type(entry) == "function" then
        return entry(state)
    end
    return entry
end

-- ============================================================
-- 交易所教程对话序列（多步气泡）
-- ============================================================

--- 获取交易所教程对话序列（多步气泡）
--- 返回 nil 表示不需要教程
---@param state table
---@return table[]|nil steps  气泡配置数组
function M.get_shop_tutorial_steps(state)
    -- 条件：第一次进交易所
    if Flags.has(state, "tutorial_shop_intro") then return nil end

    return {
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "哦——这就是交易所？东西还挺多的！",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……先加油。出发前油箱不满的话，我会睡不着。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "好好好……那买货呢？怎么挑？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……看供需标签。标「需求」的，到了别的聚落能卖高价。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "低买高卖嘛，懂懂懂——那委托要的货呢？能顺手卖了吗？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……你敢卖试试。",
        },
    }
end

-- ============================================================
-- 货车初访气泡对话（SpeechBubble 形式，玩家可看到车）
-- ============================================================

--- 获取货车初访气泡步骤（首次进入货车页面时触发）
--- 返回 nil 表示不需要
---@param state table
---@return table[]|nil steps  气泡配置数组
function M.get_truck_intro_steps(state)
    if Flags.has(state, "tutorial_truck_intro") then return nil end

    return {
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "让我看看我们的车——嗯，有点破，但是很有味道嘛！",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……底盘还行。引擎要大修，货舱太小，雷达是坏的。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "就不能说点好听的吗？那怎么办？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……攒钱，攒材料，找能改装的聚落。一个一个来。",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "引擎、货舱、雷达、冷藏、炮塔……都能升。慢慢攒吧。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "你说到炮塔的时候是不是眼睛亮了一下？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……没有。",
        },
    }
end

-- ============================================================
-- 收音机初次打开气泡对话
-- ============================================================

--- 获取收音机初次打开的气泡步骤
--- 返回 nil 表示不需要
---@param state table
---@return table[]|nil steps
function M.get_radio_intro_steps(state)
    if Flags.has(state, "tutorial_radio_intro") then return nil end

    return {
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "嗯？有声音了！收音机能用！",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……废土广播。各聚落的供需、路况，这里都有。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "还能换台？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "嗯。不同频道报不同的东西。听到有用的可以领取记下来。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "那岂不是相当于随身情报站——等下你在笑什么？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……没。就是修了很久，能收到信号还挺高兴的。",
        },
    }
end

-- ============================================================
-- 自动计划初次打开气泡对话
-- ============================================================

--- 获取自动计划初次打开的气泡步骤
--- 返回 nil 表示不需要
---@param state table
---@return table[]|nil steps
function M.get_auto_plan_intro_steps(state)
    if Flags.has(state, "tutorial_auto_plan_intro") then return nil end

    return {
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……油量低于三成时自动停靠，路过有单子的聚落顺便接……嗯，这样排比较好……",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "你嘟嘟囔囔在算什么呢？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……行程计划。设好规则，路上就不用每件事都手动操心。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "所以它会自己判断什么时候该加油、该接单？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "嗯。到了目的地还能按路线自动返程。不过……只是辅助，关键时候还是得自己判断。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "你排计划的时候感觉特别开心是我的错觉吗？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……把事情安排得整整齐齐的，有什么不好。",
        },
    }
end

-- ============================================================
-- 路线探索教程气泡（首次尝试探索未知区域时触发）
-- ============================================================

--- 获取路线探索教程气泡步骤
--- 返回 nil 表示不需要
---@param state table
---@return table[]|nil steps
function M.get_route_explore_intro_steps(state)
    if Flags.has(state, "tutorial_route_explore") then return nil end

    return {
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……这条路没有标记。得先探索才能通过。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "探索？怎么探索？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "在地图上选相邻的未知区域，点击「探索」打通道路。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "听起来不难嘛！",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……别大意。有些废墟下面是空的。",
        },
    }
end

-- ============================================================
-- 资源点搜刮初次教程气泡
-- ============================================================

--- 获取资源点搜刮初次教程步骤
--- 返回 nil 表示不需要
---@param state table
---@return table[]|nil steps
function M.get_explore_intro_steps(state)
    if Flags.has(state, "tutorial_explore_scavenge") then return nil end

    return {
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "到了！这地方……到处都是搜刮点，从哪儿开始好？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……随便哪个都行。点一下就开始搜。但动静大了会招东西过来。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "招……什么东西？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……野兽、流浪机器人、路匪，看地方。遇上了可以打，也可以跑——跑的话东西会丢一半。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "子弹不够怎么办？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……近战。疼是疼了点，但不至于没法打。体力见底之前记得撤。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "你好像对这种地方特别熟？来过很多次？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……以前一个人搜刮的时候，没人帮忙望风，得记住每个角落。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "现在有我了！你搜，我望风！",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……嗯。那确实方便多了。走吧。",
        },
    }
end

-- ============================================================
-- 货车升级故事链
-- 每次升级触发一段 gal 对话，以畅想/成长为基调
-- ============================================================

local UPGRADE_DIALOGUES = {
    -- ── 引擎系统 ──
    engine_1 = {
        title = "引擎改装",
        steps = {
            { speaker = "taoxia", text = "引擎调好了！感觉车子轻快了不少！", expression = "happy" },
            { speaker = "linli", text = "转速稳定了，高速巡航时噪音也小了。" },
            { speaker = "taoxia", text = "以后赶路能省不少时间吧？", expression = "happy" },
            { speaker = "linli", text = "省时间意味着省油。挺好的。", expression = "thinking" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "引擎的嗡鸣声变得更加平稳了。" } },
    },
    engine_2 = {
        title = "涡轮增压",
        steps = {
            { speaker = "linli", text = "涡轮加装完成。动力提升明显，而且燃耗反而降了。" },
            { speaker = "taoxia", text = "怎么做到的？", expression = "surprised" },
            { speaker = "linli", text = "涡轮回收废气能量，等于用排气再做一次功。效率自然高。", expression = "thinking" },
            { speaker = "taoxia", text = "听起来好厉害……以后可以跑更远的路线了！", expression = "happy" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "涡轮低沉的呼啸声让人安心。远方的路，不再那么遥不可及。" } },
    },
    engine_3 = {
        title = "混合动力核心",
        steps = {
            { speaker = "narrator", text = "引擎舱发出柔和的蓝光。混合动力核心安装完毕。" },
            { speaker = "taoxia", text = "这……这是灾前的军用技术吧？！", expression = "surprised" },
            { speaker = "linli", text = "改良过了。能在电池和燃油之间自动切换，效率最大化。", expression = "thinking" },
            { speaker = "taoxia", text = "感觉我们的车已经是废土上最快的了！", expression = "happy" },
            { speaker = "linli", text = "最快不敢说。但至少……不会被轻易追上了。" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "引擎升级到了极限。这辆货车，已经脱胎换骨。" } },
    },

    -- ── 货舱扩容 ──
    cargo_bay_1 = {
        title = "货舱改造",
        steps = {
            { speaker = "taoxia", text = "货舱扩了！能装更多东西了！", expression = "happy" },
            { speaker = "linli", text = "多了四个格位。以后可以带更多种类的货物。" },
            { speaker = "taoxia", text = "这样就能同时接好几个聚落的单子了吧？", expression = "happy" },
            { speaker = "linli", text = "理论上可以。不过别贪多——重量也会增加油耗。", expression = "thinking" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "货舱宽敞了不少。两个人盘算着下一趟的运货计划。" } },
    },
    cargo_bay_2 = {
        title = "模块化货架",
        steps = {
            { speaker = "linli", text = "模块化货架装好了。每样货物都有专用卡槽，不会互相挤压。" },
            { speaker = "taoxia", text = "之前那瓶酱油就是被挤碎的……", expression = "sad" },
            { speaker = "linli", text = "以后不会了。而且取货也更方便——到了聚落直接抽出来就行。" },
            { speaker = "taoxia", text = "效率翻倍！我们越来越像正经行商了！", expression = "happy" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "整齐的货架让人赏心悦目。专业感，是一点一点攒出来的。" } },
    },
    cargo_bay_3 = {
        title = "全尺寸货舱",
        steps = {
            { speaker = "narrator", text = "货车后半部经过彻底改造，货舱容量达到了极限。" },
            { speaker = "taoxia", text = "二十个格位！感觉都能开杂货铺了！", expression = "happy" },
            { speaker = "linli", text = "容量大了，责任也大了。得更仔细地规划每一趟的货物。", expression = "thinking" },
            { speaker = "taoxia", text = "嗯！争取把每个格子都塞满有价值的东西！", expression = "happy" },
            { speaker = "linli", text = "……别真塞满。留点余量应急。", expression = "angry" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "巨大的货舱是行商实力的象征。两个人，一辆车，载着四个聚落的希望。" } },
    },

    -- ── 探测雷达 ──
    radar_1 = {
        title = "基础雷达",
        steps = {
            { speaker = "taoxia", text = "雷达装上了！屏幕上开始有信号了！", expression = "happy" },
            { speaker = "linli", text = "这个能探测路边的隐藏资源点。以前全靠肉眼找，现在轻松多了。", expression = "thinking" },
            { speaker = "taoxia", text = "所以那些老行商说的'废土有眼'，就是指这个？", expression = "surprised" },
            { speaker = "linli", text = "差不多吧。信息就是生存的本钱。" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "雷达屏幕闪烁着微弱的光点。废土上的秘密，正在被一点点揭开。" } },
    },
    radar_2 = {
        title = "市场数据链",
        steps = {
            { speaker = "linli", text = "雷达升级了。现在能接收各聚落的实时供需数据。" },
            { speaker = "taoxia", text = "等等——这意味着我们出发前就能知道哪里缺什么？！", expression = "surprised" },
            { speaker = "linli", text = "对。低买高卖不再靠猜了。", expression = "happy" },
            { speaker = "taoxia", text = "这简直是作弊！我喜欢！", expression = "happy" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "供需数据在屏幕上实时更新。信息差，才是行商最大的利润来源。" } },
    },
    radar_3 = {
        title = "全域预警网",
        steps = {
            { speaker = "narrator", text = "雷达天线展开到最大范围。信号覆盖了整个已知区域。" },
            { speaker = "taoxia", text = "画面上……有红色标记在移动？", expression = "surprised" },
            { speaker = "linli", text = "敌情预警。能提前探测到路匪的大致方位。", expression = "thinking" },
            { speaker = "taoxia", text = "这也太强了！再也不用担心被偷袭了！", expression = "happy" },
            { speaker = "linli", text = "只是预警，不是无敌。遇到了还是要靠自己判断。" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "全域预警让每一趟旅程都多了一份安心。知己知彼，行商无忧。" } },
    },

    -- ── 冷藏货柜 ──
    cold_storage_1 = {
        title = "冷藏系统",
        steps = {
            { speaker = "taoxia", text = "冷藏柜终于装好了！以后生鲜不怕坏了！", expression = "happy" },
            { speaker = "linli", text = "温室社区的新鲜蔬果很受欢迎。以前没法运，现在可以了。", expression = "thinking" },
            { speaker = "taoxia", text = "如果能把沈荷种的番茄运到塔台……价格肯定很好！", expression = "happy" },
            { speaker = "linli", text = "嗯。新的商路，就从这里开始。" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "冷藏柜嗡嗡运转。新鲜食物，在废土上是最珍贵的货物之一。" } },
    },
    cold_storage_2 = {
        title = "高级保鲜",
        steps = {
            { speaker = "linli", text = "保鲜技术升级了。现在可以接高价的食品订单。" },
            { speaker = "taoxia", text = "高价食品单……是那种给聚落领导人送的特供？", expression = "surprised" },
            { speaker = "linli", text = "不光是。有些是聚落之间互赠的礼品物资。运费自然也高。", expression = "thinking" },
            { speaker = "taoxia", text = "感觉我们从送货的变成了外交官！", expression = "happy" },
            { speaker = "linli", text = "……别想太多。做好本分就行。", expression = "thinking" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "高级保鲜系统让货车多了一份特殊能力。有些委托，只有你们能完成。" } },
    },

    -- ── 车顶机枪 ──
    turret_1 = {
        title = "基础火力",
        steps = {
            { speaker = "taoxia", text = "机枪装好了……虽然看起来有点旧。", expression = "thinking" },
            { speaker = "linli", text = "够用了。废土上最重要的不是武器多好，而是让对方知道你不是好欺负的。", expression = "thinking" },
            { speaker = "taoxia", text = "威慑比实际开火更重要？", expression = "surprised" },
            { speaker = "linli", text = "对。大部分路匪看到有武装的车会自动绕道。" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "车顶的机枪在阳光下泛着冷光。行走在废土上，实力是最好的通行证。" } },
    },
    turret_2 = {
        title = "火力强化",
        steps = {
            { speaker = "linli", text = "火力提升了三成。弹链供弹也改成了自动的。" },
            { speaker = "taoxia", text = "我试了一下——后坐力比之前小了好多！", expression = "happy" },
            { speaker = "linli", text = "驱逐效率也更高了。遇到小股路匪基本一轮就能吓退。", expression = "thinking" },
            { speaker = "taoxia", text = "希望永远用不到……但有它在，心里踏实。", expression = "thinking" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "火力的提升带来了更多的安全感。路上的威胁，不再那么可怕了。" } },
    },
    turret_3 = {
        title = "要塞火力",
        steps = {
            { speaker = "narrator", text = "改装完毕。车顶炮塔焕然一新，金属表面的涂装在夕阳下闪闪发亮。" },
            { speaker = "taoxia", text = "这火力……感觉能打下一架飞机！", expression = "happy" },
            { speaker = "linli", text = "废土上没有飞机。但——确实够强了。", expression = "happy" },
            { speaker = "taoxia", text = "你笑了！你居然笑了！", expression = "surprised" },
            { speaker = "linli", text = "……有吗？", expression = "thinking" },
            { speaker = "taoxia", text = "有！我要记下来——林砾因为火力升级笑了！", expression = "happy" },
        },
        choices = { { text = "继续。", ops = {}, result_text = "全副武装的货车驶上公路。在这片废土上，她们已经无所畏惧。" } },
    },
}

--- 获取升级对话数据
---@param module_id string  模块 ID（engine/cargo_bay/radar/cold_storage/turret）
---@param new_level number  升级后的新等级
---@return table|nil dialogue  对话数据（含 title/steps/choices），nil 表示无对应对话
function M.get_upgrade_dialogue(module_id, new_level)
    local key = module_id .. "_" .. new_level
    return UPGRADE_DIALOGUES[key]
end

-- ============================================================
-- 探索边界（blocked_nodes 限定移动范围）
-- ============================================================

--- 被阻止节点的气泡对话（随机选取一组）
local BLOCKED_NODE_BUBBLES = {
    {
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "前面的路好像不太好走……到处都是碎石和歪倒的路牌。",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……这片区域还没探过，不知道什么情况。先把附近逛完再说。",
        },
    },
    {
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……再往前就出温室辖区了。现在过去不安全。",
        },
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "好吧，那先把手边的事做完。",
        },
    },
    {
        {
            portrait = M.AVATAR_TAOXIA,
            speaker  = "陶夏",
            text     = "那边看起来好远啊——走过去天都要黑了吧？",
        },
        {
            portrait = M.AVATAR_LINLI,
            speaker  = "林砾",
            text     = "……嗯。先把附近的地方看完。远处的路，以后总会走到的。",
        },
    },
}

--- 检查某个节点是否被当前教程阶段阻止
---@param state table
---@param node_id string
---@return boolean blocked
function M.is_node_blocked(state, node_id)
    if not Flags.has(state, "tutorial_started") then return false end
    local _phase, def = M.get_phase(state)
    if not def or not def.blocked_nodes then return false end
    for _, bid in ipairs(def.blocked_nodes) do
        if bid == node_id then return true end
    end
    return false
end

--- 获取边界阻止时的气泡对话步骤（随机选取一组）
---@return table[] steps  多步气泡配置数组
function M.get_blocked_node_bubbles()
    return BLOCKED_NODE_BUBBLES[math.random(#BLOCKED_NODE_BUBBLES)]
end

return M

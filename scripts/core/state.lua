--- 全局游戏状态（GameState）
--- 所有子系统共用同一个实例，通过参数传递，不使用全局变量
local M = {}

--- 创建一个全新的初始游戏状态
---@return table state
function M.new()
    return {
        meta = {
            save_version = 2,
            created_at = os.time(),
        },
        timestamp = os.time(),

        -- 流程状态
        flow = {
            phase = "idle",
            -- idle / map / prepare / route_plan / travelling / arrival / settlement / summary
            route_plan   = nil,  -- 当前路线规划（由 route_planner 生成）
            event_timer  = nil,  -- 行程中事件调度器状态
        },

        -- 货车
        truck = {
            durability     = 100,
            durability_max = 100,
            fuel           = 80,
            fuel_max       = 100,
            cargo_slots    = 8,
            cargo          = {}, -- { [goods_id] = count }
            committed      = {}, -- { [goods_id] = count } 委托货物追踪
            modules = {
                engine       = 1,
                cargo_bay    = 0,
                radar        = 0,
                cold_storage = 0,
                turret       = 0,
            },
        },

        -- 经济
        economy = {
            credits      = 200,
            order_book   = {},  -- 订单簿（OrderBook），多订单并持
        },

        -- 聚落
        settlements = {
            tower            = { goodwill = 0,  visited = false, reputation = 100 },
            greenhouse       = { goodwill = 10, visited = true,  reputation = 100 },
            ruins_camp       = { goodwill = 0,  visited = false, reputation = 100 },
            bell_tower       = { goodwill = 0,  visited = false, reputation = 100 },
            -- 前哨站（Phase 11）
            greenhouse_farm  = { goodwill = 5,  visited = false, reputation = 100 },
            dome_outpost     = { goodwill = 0,  visited = false, reputation = 100 },
            metro_camp       = { goodwill = 0,  visited = false, reputation = 100 },
            old_church       = { goodwill = 0,  visited = false, reputation = 100 },
            -- 隐藏聚落（通过 unlock_route 解锁后才可到达）
            underground_market = { goodwill = 0, visited = false, reputation = 100 },
        },

        -- 角色
        character = {
            linli  = { relation = 0, status = {}, skills = {} },
            taoxia = { relation = 0, status = {}, skills = {} },
            synergy_skills = {},  -- { synergy_repair = true, ... }
        },

        -- 地图
        map = {
            current_location = "greenhouse",
            known_nodes = {
                greenhouse = true,
                tower      = true,
                crossroads = true,
            },
            -- 当前聚落可接订单缓存（到达时生成，接完即空，同次停留不刷新）
            available_orders = {},
            -- 未来扩展：known_edges, fog discoveries 等
        },

        -- 叙事
        narrative = {
            chapter            = 0,   -- 主线章节 (0=序章 ~ 7=终章)
            chapter_flags      = {},  -- 章节专属旗标 { prologue_done = true, ... }
            story_flags        = {},
            memories           = {},
            campfire_cooldowns = {},  -- { ["CF_001"] = 2 }
            campfire_count     = 0,   -- 累计篝火次数
            npc_cooldowns      = {},  -- { ["NPC_001"] = 2 }
            npc_visit_count    = {},  -- { ["shen_he"] = 3 }
        },

        -- 自动计划设置
        auto_plan = {
            refuel_threshold = 30,   -- 油量低于此百分比时经过聚落自动补充（0=关闭）
            auto_accept_orders = false, -- 经过聚落是否自动接取顺路单
        },

        -- 全局旗标
        flags = {},

        -- 事件冷却
        _event_cooldowns = {},

        -- 统计
        stats = {
            total_trips         = 0,
            total_earnings      = 0,
            total_distance      = 0,
            play_time           = 0,
            consecutive_expires = 0,  -- 连续超时订单计数（交付成功时重置）
            -- 埋点计数器
            trades_completed    = 0,  -- 完成交易（交付订单）次数
            combats_fought      = 0,  -- 战斗次数
            combats_repelled    = 0,  -- 击退追兵次数
            explorations_done   = 0,  -- 探索次数
            modules_upgraded    = 0,  -- 模块升级次数
            events_triggered    = 0,  -- 随机事件触发次数
            goods_traded_volume = 0,  -- 货物交易总量（件）
        },
    }
end

return M

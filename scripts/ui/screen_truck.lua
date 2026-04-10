--- 货车状态页
--- 模块升级 · 角色状态 · 聚落好感 · 成长目标
local UI           = require("urhox-libs/UI")
local Theme        = require("ui/theme")
local Modules      = require("truck/modules")
local Goodwill     = require("settlement/goodwill")
local ItemUse      = require("economy/item_use")
local Goods        = require("economy/goods")
local Graph        = require("map/world_graph")
local Skills       = require("character/skills")
local Flow         = require("core/flow")
local DrivingScene = require("travel/driving_scene")
local Tutorial     = require("narrative/tutorial")
local SpeechBubble = require("ui/speech_bubble")
local Flags        = require("core/flags")

local M = {}
---@type table
local router = nil
--- 是否已初始化过 DrivingScene 状态（避免重复 setState）
local drivingSceneInited_ = false

-- 聚落中文名
local SETT_NAMES = {
    greenhouse = "温室社区", tower = "北穹塔台",
    ruins_camp = "废墟游民营地", bell_tower = "钟楼书院",
}

-- ============================================================
-- 页面创建
-- ============================================================
function M.create(state, params, r)
    router = r

    -- 初次进入货车页面：标记待触发的气泡对话（延迟到 update 首帧）
    local introSteps = Tutorial.get_truck_intro_steps(state)
    M._pendingIntro = introSteps and state or nil
    M._introSteps   = introSteps

    local location = state.map.current_location
    local children = {}

    -- ── 货车视图（行驶场景 / 静态展示）──
    local isTravelling = (Flow.get_phase(state) == Flow.Phase.TRAVELLING)
    DrivingScene.setState(state)
    DrivingScene.setDriving(isTravelling)
    drivingSceneInited_ = true

    table.insert(children, DrivingScene.createWidget({
        height = 260,
        borderRadius = Theme.sizes.radius,
    }))

    -- ── 标题 ──
    table.insert(children, UI.Label {
        text = "🚚 货车状态",
        fontSize = Theme.sizes.font_title,
        fontColor = Theme.colors.text_primary,
    })

    -- ── 基础状态 ──
    table.insert(children, createVehicleCard(state))

    -- ── 角色状态 ──
    table.insert(children, createCharacterSection(state))

    -- ── 模块升级 ──
    table.insert(children, createModulesSection(state, location))

    -- ── 聚落好感 ──
    table.insert(children, createGoodwillSection(state))

    -- ── 技能 ──
    table.insert(children, createSkillsSection(state))

    -- ── 成长目标 ──
    table.insert(children, createGoalsSection(state))

    local rootPanel = UI.Panel {
        id = "truckScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 10,
        overflow = "scroll",
        children = children,
    }
    M._rootPanel = rootPanel
    return rootPanel
end

--- 逐步展示教程气泡序列
local function showTruckTutorialStep(parent, state, steps, index)
    if index > #steps then
        -- 全部播完，设置 flag
        Flags.set(state, "tutorial_truck_intro")
        return
    end
    local step = steps[index]
    SpeechBubble.show(parent, {
        portrait  = step.portrait,
        speaker   = step.speaker,
        text      = step.text,
        autoHide  = 0,
        onDismiss = function()
            showTruckTutorialStep(parent, state, steps, index + 1)
        end,
    })
end

function M.update(state, dt, r)
    -- 首帧触发货车初访气泡对话
    if M._pendingIntro and M._rootPanel then
        local tutState = M._pendingIntro
        local steps    = M._introSteps
        M._pendingIntro = nil
        M._introSteps   = nil
        if steps then
            showTruckTutorialStep(M._rootPanel, tutState, steps, 1)
        end
    end

    SpeechBubble.update(dt)

    -- 驱动行驶场景动画（纸娃娃 AI + 滚动 + 天气粒子）
    if drivingSceneInited_ then
        DrivingScene.update(dt)
    end
end

--- 货舱使用量
local function cargoCount(state)
    local n = 0
    for _, v in pairs(state.truck.cargo) do n = n + v end
    return n
end

-- ============================================================
-- 基础状态卡片
-- ============================================================
function createVehicleCard(state)
    local fuelPct = math.floor(state.truck.fuel / state.truck.fuel_max * 100)
    local duraPct = math.floor(state.truck.durability / state.truck.durability_max * 100)

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 8,
        children = {
            -- 燃料
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "燃料",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.ProgressBar {
                            value = state.truck.fuel / state.truck.fuel_max,
                            width = 100, height = 6,
                            variant = fuelPct < 25 and "danger" or fuelPct < 50 and "warning" or "success",
                        },
                        UI.Label {
                            text = math.floor(state.truck.fuel) .. "/" .. state.truck.fuel_max,
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = Theme.colors.text_dim,
                            width = 50, textAlign = "right",
                        },
                    }},
                },
            },
            -- 耐久
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "耐久",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.ProgressBar {
                            value = state.truck.durability / state.truck.durability_max,
                            width = 100, height = 6,
                            variant = duraPct < 25 and "danger" or duraPct < 50 and "warning" or "success",
                        },
                        UI.Label {
                            text = math.floor(state.truck.durability) .. "/" .. state.truck.durability_max,
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = Theme.colors.text_dim,
                            width = 50, textAlign = "right",
                        },
                    }},
                },
            },
            -- 仓位
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "仓位",
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_secondary,
                    },
                    UI.Label {
                        text = cargoCount(state) .. " / " .. state.truck.cargo_slots,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_primary,
                    },
                },
            },
        },
    }
end

-- ============================================================
-- 角色状态区
-- ============================================================
function createCharacterSection(state)
    local rows = {}
    for _, cid in ipairs({ "linli", "taoxia" }) do
        local char = state.character[cid]
        local cName = cid == "linli" and "林砾" or "陶夏"
        local statuses = char and char.status or {}

        local statusText = "良好"
        local statusColor = Theme.colors.success
        if #statuses > 0 then
            local names = {}
            for _, sid in ipairs(statuses) do
                local def = ItemUse.STATUS_DEFS[sid]
                table.insert(names, def and def.name or sid)
            end
            statusText = table.concat(names, " · ")
            statusColor = Theme.colors.danger
        end

        table.insert(rows, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel { flexDirection = "row", gap = 6, alignItems = "center", children = {
                    UI.Label {
                        text = cName,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Label {
                        text = "关系 " .. math.floor(char and char.relation or 0),
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.info,
                    },
                }},
                UI.Label {
                    text = statusText,
                    fontSize = Theme.sizes.font_small,
                    fontColor = statusColor,
                },
            },
        })
    end

    table.insert(rows, 1, UI.Label {
        text = "角色",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 6,
        children = rows,
    }
end

-- ============================================================
-- 模块升级区
-- ============================================================
function createModulesSection(state, location)
    local rows = {}
    for _, mid in ipairs(Modules.ORDER) do
        local def = Modules.DEFS[mid]
        local lv = Modules.get_level(state, mid)
        local isMaxed = lv >= def.max_level
        local canUp, reason = Modules.can_upgrade(state, mid)
        local atRightPlace = def.upgrade_at[location]

        -- 当前效果
        local effDesc = ""
        if lv > 0 then
            local eff = def.effects[lv]
            effDesc = eff and eff.desc or ""
        end

        -- 下一级信息
        local nextDesc, costText = "", ""
        if not isMaxed then
            local nextEff = def.effects[lv + 1]
            nextDesc = nextEff and nextEff.desc or ""
            local cost = def.costs[lv + 1]
            if cost then
                local parts = { "$" .. cost.credits }
                for mat_id, need in pairs(cost.materials) do
                    local matG = Goods.get(mat_id)
                    local matName = matG and matG.name or mat_id
                    local have = state.truck.cargo[mat_id] or 0
                    local marker = have >= need and "" or "!"
                    table.insert(parts, matName .. marker .. " x" .. need)
                end
                costText = table.concat(parts, " + ")
            end
        end

        -- 可升级聚落名
        local atNames = {}
        for sid in pairs(def.upgrade_at) do
            local sn = SETT_NAMES[sid] or sid
            table.insert(atNames, sn)
        end

        local cardChildren = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = def.name .. "  Lv" .. lv .. (isMaxed and " (MAX)" or ""),
                        fontSize = Theme.sizes.font_normal,
                        fontColor = isMaxed and Theme.colors.success or Theme.colors.text_primary,
                    },
                },
            },
        }

        -- 当前效果
        if lv > 0 and effDesc ~= "" then
            table.insert(cardChildren, UI.Label {
                text = "当前: " .. effDesc,
                fontSize = Theme.sizes.font_tiny,
                fontColor = Theme.colors.text_dim,
            })
        end

        if not isMaxed then
            -- 下一级效果
            table.insert(cardChildren, UI.Label {
                text = "下一级: " .. nextDesc,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.info,
            })
            -- 费用
            table.insert(cardChildren, UI.Label {
                text = "费用: " .. costText,
                fontSize = Theme.sizes.font_tiny,
                fontColor = canUp and Theme.colors.text_secondary or Theme.colors.text_dim,
            })
            -- 可升级地点
            table.insert(cardChildren, UI.Label {
                text = "地点: " .. table.concat(atNames, " / "),
                fontSize = Theme.sizes.font_tiny,
                fontColor = atRightPlace and Theme.colors.success or Theme.colors.text_dim,
            })

            -- 升级按钮（仅在正确聚落时显示）
            if atRightPlace then
                table.insert(cardChildren, UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "flex-end",
                    marginTop = 2,
                    children = {
                        UI.Button {
                            text = canUp and "升级" or (reason or "无法升级"),
                            variant = canUp and "primary" or "secondary",
                            height = 30, paddingLeft = 16, paddingRight = 16,
                            disabled = not canUp,
                            onClick = function(self)
                                local ok, err = Modules.upgrade(state, mid)
                                if ok then
                                    local newLv = Modules.get_level(state, mid)
                                    local dialogue = Tutorial.get_upgrade_dialogue(mid, newLv)
                                    if dialogue then
                                        router.navigate("campfire", {
                                            dialogue = dialogue,
                                            consumed = false,
                                            returnTo = "truck",
                                        })
                                    else
                                        router.refresh()
                                    end
                                end
                            end,
                        },
                    },
                })
            end
        end

        table.insert(rows, UI.Panel {
            width = "100%", padding = 10, gap = 4,
            backgroundColor = Theme.colors.bg_secondary,
            borderRadius = Theme.sizes.radius_small,
            children = cardChildren,
        })
    end

    table.insert(rows, 1, UI.Label {
        text = "模块升级",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 8,
        children = rows,
    }
end

-- ============================================================
-- 聚落好感区
-- ============================================================
function createGoodwillSection(state)
    local rows = {}
    local settlements = { "greenhouse", "tower", "ruins_camp", "bell_tower" }

    for _, sid in ipairs(settlements) do
        local sett = state.settlements[sid]
        local gw = sett and sett.goodwill or 0
        local info = Goodwill.get_info(gw)

        local barColor = info.level >= 3 and Theme.colors.success
            or info.level >= 2 and Theme.colors.info
            or info.level >= 1 and Theme.colors.accent
            or Theme.colors.text_dim

        local nextTh = info.next_threshold or 100
        local progress = math.min(1, gw / nextTh)

        table.insert(rows, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel { gap = 1, flexShrink = 1, children = {
                    UI.Label {
                        text = (SETT_NAMES[sid] or sid),
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.text_primary,
                    },
                    UI.Panel { flexDirection = "row", gap = 4, alignItems = "center", children = {
                        UI.Label {
                            text = info.name .. " (Lv" .. info.level .. ")",
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = barColor,
                        },
                        UI.Label {
                            text = math.floor(gw) .. (info.next_threshold and ("/" .. info.next_threshold) or ""),
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = Theme.colors.text_dim,
                        },
                    }},
                }},
                UI.ProgressBar {
                    value = progress,
                    width = 80, height = 6,
                    variant = info.level >= 2 and "success" or info.level >= 1 and "info" or "default",
                },
            },
        })
    end

    table.insert(rows, 1, UI.Label {
        text = "聚落好感",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 6,
        children = rows,
    }
end

-- ============================================================
-- 技能区
-- ============================================================
function createSkillsSection(state)
    local all = Skills.get_all(state)
    local rows = {}

    -- 标题
    table.insert(rows, UI.Label {
        text = "技能",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    -- ── 个人技能 ──
    for _, cid in ipairs({ "linli", "taoxia" }) do
        local cName = cid == "linli" and "林砾" or "陶夏"
        table.insert(rows, UI.Label {
            text = cName,
            fontSize = Theme.sizes.font_small,
            fontColor = Theme.colors.text_secondary,
            marginTop = 4,
        })

        for _, sk in ipairs(all.personal[cid]) do
            local progressText
            if sk.unlocked then
                progressText = "已解锁"
            else
                progressText = sk.unlock_desc .. "  (" .. math.floor(sk.current) .. "/" .. sk.need .. ")"
            end

            table.insert(rows, UI.Panel {
                width = "100%", padding = 8, gap = 2,
                backgroundColor = sk.unlocked and Theme.colors.bg_secondary or Theme.colors.bg_primary,
                borderRadius = Theme.sizes.radius_small,
                children = {
                    -- 名称行
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Label {
                                text = sk.icon .. " " .. sk.name,
                                fontSize = Theme.sizes.font_small,
                                fontColor = sk.unlocked and Theme.colors.text_primary or Theme.colors.text_dim,
                            },
                            UI.Label {
                                text = sk.unlocked and "✅" or "🔒",
                                fontSize = Theme.sizes.font_small,
                            },
                        },
                    },
                    -- 描述
                    UI.Label {
                        text = sk.desc,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = sk.unlocked and Theme.colors.text_secondary or Theme.colors.text_dim,
                    },
                    -- 进度
                    sk.unlocked and nil or UI.Panel {
                        width = "100%", flexDirection = "row",
                        alignItems = "center", gap = 6, marginTop = 2,
                        children = {
                            UI.ProgressBar {
                                value = math.min(1, sk.current / math.max(1, sk.need)),
                                width = 80, height = 4,
                                variant = "info",
                            },
                            UI.Label {
                                text = progressText,
                                fontSize = Theme.sizes.font_tiny,
                                fontColor = Theme.colors.text_dim,
                            },
                        },
                    },
                },
            })
        end
    end

    -- ── 协同技能 ──
    table.insert(rows, UI.Label {
        text = "协同技能",
        fontSize = Theme.sizes.font_small,
        fontColor = Theme.colors.text_secondary,
        marginTop = 6,
    })

    for _, sk in ipairs(all.synergy) do
        local progressText
        if sk.unlocked then
            progressText = "已解锁"
        else
            progressText = "双方关系 ≥ " .. sk.relation_req .. "  (当前 " .. math.floor(sk.relation_cur) .. ")"
        end

        table.insert(rows, UI.Panel {
            width = "100%", padding = 8, gap = 2,
            backgroundColor = sk.unlocked and Theme.colors.bg_secondary or Theme.colors.bg_primary,
            borderRadius = Theme.sizes.radius_small,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = sk.icon .. " " .. sk.name,
                            fontSize = Theme.sizes.font_small,
                            fontColor = sk.unlocked and Theme.colors.text_primary or Theme.colors.text_dim,
                        },
                        UI.Label {
                            text = sk.unlocked and "✅" or "🔒",
                            fontSize = Theme.sizes.font_small,
                        },
                    },
                },
                UI.Label {
                    text = sk.desc,
                    fontSize = Theme.sizes.font_tiny,
                    fontColor = sk.unlocked and Theme.colors.text_secondary or Theme.colors.text_dim,
                },
                sk.unlocked and nil or UI.Panel {
                    width = "100%", flexDirection = "row",
                    alignItems = "center", gap = 6, marginTop = 2,
                    children = {
                        UI.ProgressBar {
                            value = math.min(1, sk.relation_cur / math.max(1, sk.relation_req)),
                            width = 80, height = 4,
                            variant = "info",
                        },
                        UI.Label {
                            text = progressText,
                            fontSize = Theme.sizes.font_tiny,
                            fontColor = Theme.colors.text_dim,
                        },
                    },
                },
            },
        })
    end

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 6,
        children = rows,
    }
end

-- ============================================================
-- 成长目标区
-- ============================================================
function createGoalsSection(state)
    local items = {}

    -- 模块总进度
    local totalLv, maxLv = 0, 0
    for _, mid in ipairs(Modules.ORDER) do
        totalLv = totalLv + Modules.get_level(state, mid)
        maxLv   = maxLv + Modules.DEFS[mid].max_level
    end

    -- 好感总进度
    local totalGwLv = 0
    for _, sid in ipairs({ "greenhouse", "tower", "ruins_camp", "bell_tower" }) do
        local sett = state.settlements[sid]
        totalGwLv = totalGwLv + Goodwill.get_level(sett and sett.goodwill or 0)
    end

    local trips = state.stats and state.stats.total_trips or 0

    local goals = {
        { label = "模块升级", value = totalLv .. "/" .. maxLv, done = totalLv >= maxLv },
        { label = "好感总计", value = "Lv " .. totalGwLv .. "/12", done = totalGwLv >= 12 },
        { label = "完成行程", value = trips .. " 趟", done = false },
    }

    for _, g in ipairs(goals) do
        table.insert(items, UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label {
                    text = (g.done and "✅ " or "⬜ ") .. g.label,
                    fontSize = Theme.sizes.font_small,
                    fontColor = g.done and Theme.colors.success or Theme.colors.text_secondary,
                },
                UI.Label {
                    text = g.value,
                    fontSize = Theme.sizes.font_small,
                    fontColor = g.done and Theme.colors.success or Theme.colors.text_primary,
                },
            },
        })
    end

    table.insert(items, 1, UI.Label {
        text = "成长目标",
        fontSize = Theme.sizes.font_normal,
        fontColor = Theme.colors.info,
    })

    return UI.Panel {
        width = "100%", padding = 12,
        backgroundColor = Theme.colors.bg_card,
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.border,
        gap = 6,
        children = items,
    }
end

return M

--- 废墟营地·黑市淘货页面
--- 随机商品 + 3 回合砍价博弈 UI
local UI          = require("urhox-libs/UI")
local Theme       = require("ui/theme")
local F           = require("ui/ui_factory")
local BlackMarket = require("settlement/black_market")
local Goods       = require("economy/goods")
local SoundMgr    = require("ui/sound_manager")

local M = {}
---@type table
local router = nil

-- 砍价会话状态
local _haggleState = nil  -- { item_index, round, ask_price, last_result, counter_price }

function M.create(state, params, r)
    router = r
    params = params or {}

    -- 刷新货架（首次进入时）
    BlackMarket.refresh(state)

    -- 处理砍价继续
    if params._haggle then
        _haggleState = params._haggle
    end

    local items   = BlackMarket.get_items(state)
    local credits = state.economy.credits

    local children = {}

    -- ── 标题栏 ──
    table.insert(children, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "🏚 黑市淘货",
                fontSize = Theme.sizes.font_title,
                fontColor = Theme.colors.text_primary,
            },
            UI.Label {
                text = "$" .. credits,
                fontSize = Theme.sizes.font_small,
                fontColor = Theme.colors.accent,
            },
        },
    })

    -- ── 砍价界面（如果正在砍价） ──
    if _haggleState then
        table.insert(children, createHaggleView(state, _haggleState))
        -- 只显示砍价，不显示商品列表
        return UI.Panel {
            id = "blackMarketScreen",
            width = "100%", height = "100%",
            backgroundColor = Theme.colors.bg_primary,
            padding = Theme.sizes.padding, gap = 8,
            overflow = "scroll",
            children = children,
        }
    end

    -- ── 商品列表 ──
    local hasUnsold = false
    for i, item in ipairs(items) do
        if not item.sold then
            hasUnsold = true
            table.insert(children, createItemCard(state, i, item))
        end
    end

    if not hasUnsold then
        table.insert(children, UI.Panel {
            width = "100%", padding = 24,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "今天的货都卖完了",
                    fontSize = Theme.sizes.font_large,
                    fontColor = Theme.colors.text_dim,
                    textAlign = "center",
                },
                UI.Label {
                    text = "下趟来时再看看。",
                    fontSize = Theme.sizes.font_small,
                    fontColor = Theme.colors.text_secondary,
                    textAlign = "center",
                },
            },
        })
    end

    -- ── 统计 ──
    local trades, saved = BlackMarket.get_stats(state)
    if trades > 0 then
        table.insert(children, UI.Label {
            text = "累计 " .. trades .. " 笔交易，砍价共省 $" .. saved,
            fontSize = Theme.sizes.font_tiny,
            fontColor = Theme.colors.text_dim,
            marginTop = 8,
            textAlign = "center",
        })
    end

    return UI.Panel {
        id = "blackMarketScreen",
        width = "100%", height = "100%",
        backgroundColor = Theme.colors.bg_primary,
        padding = Theme.sizes.padding, gap = 8,
        overflow = "scroll",
        children = children,
    }
end

--- 商品卡片
function createItemCard(state, index, item)
    -- 品质描述（模糊化）
    local qualityDesc
    if item.quality >= 1.2 then
        qualityDesc = "成色不错"
    elseif item.quality >= 0.9 then
        qualityDesc = "看起来还行"
    elseif item.quality >= 0.7 then
        qualityDesc = "有些磨损"
    else
        qualityDesc = "品相堪忧"
    end

    return F.card {
        width = "100%", padding = 10,
        borderWidth = 1, borderColor = { 168, 128, 82, 120 },
        gap = 4,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = item.label,
                        fontSize = Theme.sizes.font_normal,
                        fontColor = Theme.colors.text_primary,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = qualityDesc,
                        fontSize = Theme.sizes.font_tiny,
                        fontColor = Theme.colors.text_secondary,
                    },
                },
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label {
                        text = "开价 $" .. item.ask_price,
                        fontSize = Theme.sizes.font_small,
                        fontColor = Theme.colors.accent,
                    },
                    F.actionBtn {
                        text = "砍价",
                        variant = "secondary",
                        width = "auto",
                        height = 30,
                        fontSize = Theme.sizes.font_small,
                        onClick = function(self)
                            _haggleState = {
                                item_index    = index,
                                round         = 1,
                                ask_price     = item.ask_price,
                                last_result   = nil,
                                counter_price = nil,
                            }
                            router.navigate("black_market", { _haggle = _haggleState })
                        end,
                    },
                },
            },
        },
    }
end

--- 砍价界面
function createHaggleView(state, hs)
    local items = BlackMarket.get_items(state)
    local item  = items[hs.item_index]
    if not item then
        _haggleState = nil
        return UI.Label { text = "商品已下架", fontSize = 14, fontColor = Theme.colors.text_dim }
    end

    local currentAsk = hs.counter_price or hs.ask_price
    local haggleChildren = {}

    -- 商品信息
    table.insert(haggleChildren, UI.Label {
        text = item.label,
        fontSize = Theme.sizes.font_large,
        fontColor = Theme.colors.text_primary,
    })

    -- 当前报价
    table.insert(haggleChildren, UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        children = {
            UI.Label {
                text = "卖家报价",
                fontSize = Theme.sizes.font_normal,
                fontColor = Theme.colors.text_secondary,
            },
            UI.Label {
                text = "$" .. currentAsk,
                fontSize = Theme.sizes.font_large,
                fontColor = Theme.colors.accent,
            },
        },
    })

    -- 上一回合结果
    if hs.last_result then
        local resultTexts = {
            angry   = "卖家怒了：\"你是来砸场子的？\"",
            counter = "卖家犹豫了一下：\"这个价吧……\"",
        }
        local resultText = resultTexts[hs.last_result] or ""
        if resultText ~= "" then
            table.insert(haggleChildren, UI.Label {
                text = resultText,
                fontSize = Theme.sizes.font_small,
                fontColor = hs.last_result == "angry"
                    and Theme.colors.danger or Theme.colors.warning,
            })
        end
    end

    -- 回合提示
    table.insert(haggleChildren, UI.Label {
        text = "第 " .. hs.round .. " / 3 回合",
        fontSize = Theme.sizes.font_tiny,
        fontColor = Theme.colors.text_dim,
        textAlign = "center",
    })

    -- 操作按钮
    -- 接受当前价格
    table.insert(haggleChildren, F.actionBtn {
        text = "接受 $" .. currentAsk,
        variant = "primary",
        height = 36,
        fontSize = Theme.sizes.font_normal,
        disabled = state.economy.credits < currentAsk,
        sound = false,
        onClick = function(self)
            local ok, result = BlackMarket.buy(state, hs.item_index, currentAsk)
            _haggleState = nil
            if ok then
                SoundMgr.play("coins")
                print("[BlackMarket] Bought: " .. result.label .. " for $" .. result.price)
            end
            router.navigate("black_market")
        end,
    })

    -- 还价（预设几个档位）
    if hs.round < 3 then
        local offerLevels = { 0.6, 0.75, 0.85 }
        local offerBtns = {}
        for _, pct in ipairs(offerLevels) do
            local offerPrice = math.floor(currentAsk * pct + 0.5)
            table.insert(offerBtns, F.actionBtn {
                text = "$" .. offerPrice,
                variant = "secondary",
                height = 32, flexGrow = 1,
                fontSize = Theme.sizes.font_small,
                sound = false,
                onClick = function(self)
                    local result, counterP, gwDelta =
                        BlackMarket.haggle(state, hs.item_index, offerPrice)

                    if result == "accept" then
                        -- 卖家直接接受
                        local ok, bResult = BlackMarket.buy(state, hs.item_index, offerPrice)
                        _haggleState = nil
                        if ok then
                            SoundMgr.play("coins")
                            print("[BlackMarket] Deal at $" .. bResult.price)
                        end
                        router.navigate("black_market")
                    elseif result == "angry" then
                        SoundMgr.play("click")
                        -- 好感下降，回合推进
                        if gwDelta then
                            local sett = state.settlements.ruins_camp
                            sett.goodwill = math.max(0, (sett.goodwill or 0) + gwDelta)
                        end
                        hs.round = hs.round + 1
                        hs.last_result = "angry"
                        if hs.round > 3 then
                            _haggleState = nil
                            router.navigate("black_market")
                        else
                            router.navigate("black_market", { _haggle = hs })
                        end
                    elseif result == "counter" then
                        SoundMgr.play("click")
                        hs.round = hs.round + 1
                        hs.last_result = "counter"
                        hs.counter_price = counterP
                        if hs.round > 3 then
                            -- 最后一轮：以还价成交或放弃
                            hs.last_result = "final"
                        end
                        router.navigate("black_market", { _haggle = hs })
                    else
                        _haggleState = nil
                        router.navigate("black_market")
                    end
                end,
            })
        end
        table.insert(haggleChildren, UI.Panel {
            width = "100%", flexDirection = "row", gap = 6,
            children = offerBtns,
        })
    end

    -- 放弃
    table.insert(haggleChildren, F.actionBtn {
        text = "算了，不买了",
        variant = "secondary",
        height = 32,
        fontSize = Theme.sizes.font_small,
        onClick = function(self)
            _haggleState = nil
            router.navigate("black_market")
        end,
    })

    return UI.Panel {
        width = "100%", padding = 14,
        backgroundColor = { 48, 38, 30, 240 },
        borderRadius = Theme.sizes.radius,
        borderWidth = 1, borderColor = Theme.colors.accent,
        gap = 8,
        children = haggleChildren,
    }
end

function M.update(state, dt, r) end

return M

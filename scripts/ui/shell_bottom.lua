--- 全局底部导航栏
--- 4 个固定 tab：首页 / 地图 / 委托 / 货舱
local UI    = require("urhox-libs/UI")
local Theme = require("ui/theme")
local Flow  = require("core/flow")

local M = {}

local TABS = {
    { id = "home",   icon = "🏠", label = "首页"  },
    { id = "map",    icon = "🗺",  label = "地图"  },
    { id = "orders", icon = "📋", label = "委托"  },
    { id = "cargo",  icon = "📦", label = "货舱"  },
    { id = "truck",  icon = "🚚", label = "货车"  },
}

--- 创建底部导航栏
---@param state table
---@param activeTab string 当前高亮的 tab id
---@param screenName string 当前页面名称（用于判断是否真正在该页面）
---@param router table
---@return table widget
function M.create(state, activeTab, screenName, router)
    local tabChildren = {}
    for _, tab in ipairs(TABS) do
        local isActive = (tab.id == activeTab)
        local color = isActive and Theme.colors.accent or Theme.colors.text_dim

        table.insert(tabChildren, UI.Panel {
            flexGrow = 1, alignItems = "center",
            justifyContent = "center",
            paddingTop = 6, paddingBottom = 6, gap = 2,
            onClick = function(self)
                -- 只有当前页面确实是该 tab 本身时才跳过
                -- shop 映射到 home tab，但点击 home 仍应导航回首页
                if tab.id == screenName then return end

                local ok, err = pcall(function()
                    -- 旅行中：只切换显示页面，不修改 flow.phase
                    -- 否则会把 TRAVELLING 改成 IDLE/MAP/PREPARE，导致旅行中断
                    local travelling = Flow.get_phase(state) == Flow.Phase.TRAVELLING

                    if tab.id == "home" then
                        if not travelling then
                            Flow.back_to_idle(state)
                        end
                        router.navigate("home")
                    elseif tab.id == "map" then
                        if not travelling then
                            Flow.enter_map(state)
                        end
                        router.navigate("map")
                    elseif tab.id == "orders" then
                        if not travelling then
                            Flow.enter_prepare(state)
                        end
                        router.navigate("orders")
                    elseif tab.id == "cargo" then
                        router.navigate("cargo")
                    elseif tab.id == "truck" then
                        router.navigate("truck")
                    end
                end)
                if not ok then
                    print("[ShellBottom] ERROR in tab '" .. tab.id .. "' onClick: " .. tostring(err))
                end
            end,
            children = {
                UI.Label {
                    text = tab.icon, fontSize = 18,
                    fontColor = color,
                    textAlign = "center",
                },
                UI.Label {
                    text = tab.label, fontSize = 10,
                    fontColor = color,
                    textAlign = "center",
                },
            },
        })
    end

    return UI.Panel {
        id = "shellBottomBar",
        width = "100%", height = 56,
        flexDirection = "row", alignItems = "center",
        backgroundColor = Theme.colors.bg_secondary,
        borderTopWidth = 1, borderColor = Theme.colors.border,
        children = tabChildren,
    }
end

return M

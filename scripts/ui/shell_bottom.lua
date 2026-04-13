--- 全局底部导航栏
--- 5 个固定 tab：首页 / 地图 / 委托 / 货舱 / 货车
local UI       = require("urhox-libs/UI")
local Theme    = require("ui/theme")
local Flow     = require("core/flow")
local SoundMgr = require("ui/sound_manager")

local SketchBorder = require("ui/sketch_border")

local M = {}

local TABS = {
    { id = "home",   iconKey = "tab_home",   label = "首页"  },
    { id = "map",    iconKey = "tab_map",    label = "地图"  },
    { id = "orders", iconKey = "tab_orders", label = "委托"  },
    { id = "cargo",  iconKey = "tab_cargo",  label = "货舱"  },
    { id = "truck",  iconKey = "tab_truck",  label = "货车"  },
}

--- 创建底部导航栏
---@param state table
---@param activeTab string 当前高亮的 tab id
---@param screenName string 当前页面名称（用于判断是否真正在该页面）
---@param router table
---@return table widget
function M.create(state, activeTab, screenName, router)
    local tabChildren = {}
    for i, tab in ipairs(TABS) do
        -- 在 tab 之间插入竖直分割线（第 2 个起）
        if i > 1 then
            local vdiv = UI.Panel {
                width = 1, height = "60%", alignSelf = "center",
            }
            SketchBorder.register(vdiv, "vdivider")
            table.insert(tabChildren, vdiv)
        end

        local isActive = (tab.id == activeTab)
        local tint = isActive
            and Theme.colors.accent
            or  Theme.colors.text_dim

        table.insert(tabChildren, UI.Panel {
            flexGrow = 1, alignItems = "center",
            justifyContent = "center",
            paddingTop = 6, paddingBottom = 6, gap = 2,
            onClick = function(self)
                -- 只有当前页面确实是该 tab 本身时才跳过
                -- shop 映射到 home tab，但点击 home 仍应导航回首页
                if tab.id == screenName then return end

                SoundMgr.play("click_soft")

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
                -- 图标：用 Panel + backgroundImage 代替 emoji Label
                UI.Panel {
                    width = 22, height = 22,
                    backgroundImage = Theme.icons[tab.iconKey],
                    backgroundFit = "contain",
                    imageTint = tint,
                },
                UI.Label {
                    text = tab.label, fontSize = 10,
                    fontColor = tint,
                    textAlign = "center",
                },
            },
        })
    end

    local bar = UI.Panel {
        id = "shellBottomBar",
        width = "100%", height = 56,
        flexDirection = "row", alignItems = "center",
        backgroundColor = Theme.colors.bg_secondary,
        children = tabChildren,
    }
    SketchBorder.register(bar, "card")
    return bar
end

return M

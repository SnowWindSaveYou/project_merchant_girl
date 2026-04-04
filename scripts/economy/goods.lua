--- 商品定义
--- 4 大类 10 种商品，每种有基础价格和堆叠上限
local M = {}

M.CATEGORIES = {
    survival   = { name = "生存物资", color = { 82, 178, 120, 255 } },
    industrial = { name = "工业品",   color = { 92, 152, 208, 255 } },
    cultural   = { name = "文化品",   color = { 218, 165, 82, 255 } },
    military   = { name = "战备物资", color = { 192, 72, 72, 255 } },
}

M.ALL = {
    { id = "food_can",    name = "罐头食品", category = "survival",   base_price = 15, stack_limit = 20 },
    { id = "water",       name = "净水",     category = "survival",   base_price = 10, stack_limit = 30 },
    { id = "medicine",    name = "医疗包",   category = "survival",   base_price = 35, stack_limit = 10 },
    { id = "circuit",     name = "电路板",   category = "industrial", base_price = 40, stack_limit = 10 },
    { id = "fuel_cell",   name = "燃料芯",   category = "industrial", base_price = 50, stack_limit = 8  },
    { id = "metal_scrap", name = "废金属",   category = "industrial", base_price = 12, stack_limit = 25 },
    { id = "old_book",    name = "旧书",     category = "cultural",   base_price = 25, stack_limit = 15 },
    { id = "music_disc",  name = "唱片",     category = "cultural",   base_price = 30, stack_limit = 10 },
    { id = "ammo",        name = "弹药链",   category = "military",   base_price = 45, stack_limit = 8  },
    { id = "smoke_bomb",  name = "烟雾弹",   category = "military",   base_price = 35, stack_limit = 5  },
}

M.BY_ID = {}
for _, g in ipairs(M.ALL) do
    M.BY_ID[g.id] = g
end

function M.get(id)
    return M.BY_ID[id]
end

return M

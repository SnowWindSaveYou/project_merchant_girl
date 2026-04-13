--- 功能解锁首次剧情
--- 玩家首次进入已解锁的聚落子功能时播放的介绍性对话
--- 格式与 npc_dialogues.json 对话兼容，复用 NpcManager.apply_choice
local M = {}

M.dialogues = {
    -- ══════════════════════════════════════════
    -- 档案阅览（钟楼书院 · 白述）
    -- ══════════════════════════════════════════
    archives = {
        id       = "UNLOCK_ARCHIVES",
        npc_id   = "bai_shu",
        extra_npc = "xie_ling",
        title    = "抄写员",
        flag     = "unlock_seen_archives",
        steps    = {
            { speaker = "narrator",  text = "白述带你参观书院的档案室。谢令在角落里抄写——用手，一个字一个字。" },
            { speaker = "taoxia",    text = "为什么不用打印？" },
            { speaker = "xie_ling",  text = "打印机需要电和墨盒……我们有手和墨水。" },
            { speaker = "narrator",  text = "谢令抬起头，手指上全是墨渍，有些不好意思地把手往围裙上擦了擦。" },
            { speaker = "xie_ling",  text = "而且、抄写的时候会记住内容的。打印机不会记住。" },
            { speaker = "taoxia",    text = "你都记住了？" },
            { speaker = "xie_ling",  text = "大……大部分。有些地方的描述我没见过实物，不太确定写的是什么意思。" },
            { speaker = "narrator",  text = "她的眼神里闪过一丝好奇。" },
            { speaker = "xie_ling",  text = "你、你们是跑商的对吧？外面的聚落……真的和档案里写的一样吗？" },
            { speaker = "npc",       text = "好了，别缠着客人问了。" },
            { speaker = "narrator",  text = "白述笑着摇摇头，但语气里没有责备。" },
        },
        choices  = {
            {
                text        = "下次来的时候给你讲讲外面的事",
                ops         = { "add_goodwill:bell_tower:4", "set_flag:unlock_seen_archives" },
                result_text = "谢令眨了眨眼，嘴角忍不住翘起来，又赶紧低下头假装继续抄写。白述递给你一份索引册：「档案对行商会有帮助。」",
            },
            {
                text        = "这些档案……我也可以看吗？",
                ops         = { "add_goodwill:bell_tower:2", "set_flag:unlock_seen_archives" },
                result_text = "白述递给你一份索引册。「当然。有些记录可能对行商有帮助。」谢令在旁边小声补充：「索引是按地区分的，找起来比较方便……」",
            },
        },
    },

    -- ══════════════════════════════════════════
    -- 培育农场（温室社区 · 沈禾）
    -- ══════════════════════════════════════════
    farm = {
        id       = "UNLOCK_FARM",
        npc_id   = "shen_he",
        title    = "沈禾的难题",
        flag     = "unlock_seen_farm",
        steps    = {
            { speaker = "narrator", text = "沈禾把你叫到育种棚里。一排培养皿，全是枯萎的苗。" },
            { speaker = "npc",      text = "这是灾前的小麦种子。老甘从农学院带出来的，一直舍不得用。理论上能种活，但已经失败了四次。" },
            { speaker = "taoxia",   text = "需要什么特殊条件吗？" },
            { speaker = "npc",      text = "需要一种微量元素肥料。配方我有，但原料只有塔台那边有。韩策开价太高了。" },
            { speaker = "npc",      text = "如果你跑商的时候能帮忙留意……我可以分一块苗圃给你们用。" },
        },
        choices  = {
            {
                text        = "没问题，我们帮你留意",
                ops         = { "add_goodwill:greenhouse:5", "set_flag:unlock_seen_farm" },
                result_text = "沈禾眼里多了些光。她腾出一块育种区域，挂上了你的名字。",
            },
            {
                text        = "苗圃倒是可以试试",
                ops         = { "add_goodwill:greenhouse:2", "set_flag:unlock_seen_farm" },
                result_text = "沈禾指了指角落的空地。「那块就归你了。种什么都行。」",
            },
        },
    },

    -- ══════════════════════════════════════════
    -- 情报站（北穹塔台 · 韩策）
    -- ══════════════════════════════════════════
    intel = {
        id       = "UNLOCK_INTEL",
        npc_id   = "han_ce",
        title    = "数据交换",
        flag     = "unlock_seen_intel",
        steps    = {
            { speaker = "narrator", text = "韩策允许你进入塔台的「信息交换区」——用你跑商途中收集的路况数据，换取塔台的天气预报。" },
            { speaker = "npc",      text = "数据换数据。你给我路况，我给你天气。公平交易。" },
            { speaker = "taoxia",   text = "不能直接告诉我们吗？" },
            { speaker = "npc",      text = "没有免费的信息。免费的信息最危险。" },
            { speaker = "narrator", text = "韩策转过身，屏幕上密密麻麻的数据流一闪而过。" },
        },
        choices  = {
            {
                text        = "成交。公平交易",
                ops         = { "add_goodwill:tower:4", "set_flag:unlock_seen_intel" },
                result_text = "韩策嘴角微微上扬。「识时务。我喜欢跟聪明人做生意。」",
            },
            {
                text        = "……那就换吧",
                ops         = { "add_goodwill:tower:1", "set_flag:unlock_seen_intel" },
                result_text = "韩策点了点头，递过一个数据终端。态度公事公办。",
            },
        },
    },

    -- ══════════════════════════════════════════
    -- 黑市（废墟营地 · 伍拾七）
    -- ══════════════════════════════════════════
    black_market = {
        id       = "UNLOCK_BLACK_MARKET",
        npc_id   = "wu_shiqi",
        extra_npc = "dao_yu",
        title    = "入场费",
        flag     = "unlock_seen_black_market",
        steps    = {
            { speaker = "narrator", text = "第一次进入营地内部市场，伍拾七拦住了你。" },
            { speaker = "npc",      text = "里面的规矩很简单：不偷、不抢、不赖账。违反任何一条，永远别来。" },
            { speaker = "taoxia",   text = "那如果卖家骗人呢？" },
            { speaker = "narrator", text = "伍拾七笑了。" },
            { speaker = "npc",      text = "那就看你眼力。" },
            { speaker = "narrator", text = "一个晒得黑黑的女孩从旁边的摊子后面探出头来。" },
            { speaker = "dao_yu",   text = "老大！让我带她们逛逛嘛！我认识这里每一个摊位！" },
            { speaker = "npc",      text = "……去吧。别把人家带沟里。" },
            { speaker = "dao_yu",   text = "嘿嘿，放心！" },
            { speaker = "narrator", text = "刀鱼跳下来，挎包里叮叮当当响——里面塞满了收集来的小玩意。" },
            { speaker = "dao_yu",   text = "走走走！我跟你说，东边那几个摊东西不错，西边那个秃头的你别买，他的罐头过期了自己还不承认。" },
        },
        choices  = {
            {
                text        = "好啊，带路吧小向导",
                ops         = { "add_goodwill:ruins_camp:5", "set_flag:unlock_seen_black_market" },
                result_text = "刀鱼得意地挺了挺胸，一路上嘴就没停过。伍拾七看着她的背影，摇了摇头——但嘴角带着笑。",
            },
            {
                text        = "我自己先看看",
                ops         = { "add_goodwill:ruins_camp:2", "set_flag:unlock_seen_black_market" },
                result_text = "刀鱼有点失望地「哦」了一声，但还是跟在后面，时不时小声提醒你哪个摊位靠谱。",
            },
        },
    },
}

--- 获取指定功能的解锁对话
---@param feature string "archives"|"farm"|"intel"|"black_market"
---@return table|nil dialogue
function M.get(feature)
    return M.dialogues[feature]
end

return M

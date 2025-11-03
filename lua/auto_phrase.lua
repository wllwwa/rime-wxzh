-- 用于万象拼音的次翻译器自动自造词管理工具
local utf8 = require("utf8")

-- comment table
local comment_cache_table = {}
local memory = nil
local NON_CHINESE_PATTERN = "[%w%p]"

local function is_chinese_only(text)
    if not text or text == "" then
        return false
    end

    if text:match(NON_CHINESE_PATTERN) then
        return false
    end

    for _, cp in utf8.codes(text) do
        -- 常用汉字区 + 扩展 A/B/C/D/E/F/G
        if
            not ((cp >= 0x4E00 and cp <= 0x9FFF) or -- CJK Unified Ideographs
                (cp >= 0x3400 and cp <= 0x4DBF) or -- CJK Ext-A
                (cp >= 0x20000 and cp <= 0x2EBEF) or -- CJK Ext-B~G（需 5.3+ 支持大码点）
                false)
         then
            return false
        end
    end
    return true
end

-- cache comment before filter
local function get_comment_cache(input, env)
    for cand in input:iter() do
        local comment = cand.comment
        local comment_text = cand.text

        if comment_text and comment_text ~= "" and comment and comment ~= "" then
            comment_cache_table[comment_text] = comment
        end

        yield(cand)
    end
end

local function commit_handler(ctx, env)
    if not ctx or not ctx.composition then
        comment_cache_table = {}
        return
    end

    local segments = ctx.composition:toSegmentation():get_segments()
    local segments_count = #segments
    local commit_text = ctx:get_commit_text()

    -- 检查是否符合最小造词单元要求
    if segments_count <= 1 or utf8.len(commit_text) <= 1 then
        comment_cache_table = {}
        return
    end

    -- 检查是否符合造词内容要求
    if not is_chinese_only(commit_text) or comment_cache_table[commit_text] then
        comment_cache_table = {}
        return
    end

    local preedits_table = {}
    local config = env.engine.schema.config
    local delimiter = config:get_string("speller/delimiter") or " '"
    local escaped_delimiter = utf8.char(utf8.codepoint(delimiter)):gsub("(%W)", "%%%1")

    for i = 1, segments_count do
        local seg = segments[i]
        local cand = seg:get_selected_candidate()

        if cand then
            local cand_text = cand.text
            local preedit = comment_cache_table[cand_text]

            if preedit and preedit ~= "" then
                for part in preedit:gmatch("[^" .. escaped_delimiter .. "]+") do
                    table.insert(preedits_table, part)
                end
            end
        end
    end

    local memory = Memory(env.engine, env.engine.schema, "add_user_dict")
    local dictEntry = DictEntry()

    dictEntry.text = commit_text
    dictEntry.weight = 1
    dictEntry.custom_code = table.concat(preedits_table, " ") .. " "

    memory:update_userdict(dictEntry, 1, "")

    log.info(string.format("[advanced_userdb] 自动造词：[%s]，编码：[%s]", dictEntry.text, dictEntry.custom_code))

    comment_cache_table = {}
end

local function init(env)
    env.engine.context.commit_notifier:connect(
        function(ctx)
            commit_handler(ctx, env)
        end
    )
end

return {init = init, func = get_comment_cache}

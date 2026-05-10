-- quick_add_word.lua
-- 快捷造词：造词模式打开时，将输入内容重定向追加到私有词库末尾

local qaw = {} -- Quick Add Word
local DICT_PATH = "C:/Users/wguos/AppData/Roaming/Rime/yuhao/yuhao.private.dict.yaml"

qaw.text = ""


-- 判断是否为汉字（CJK 统一表意文字基本区）
local function is_hanzi(ch)
   if not ch or ch == "" then return false end
   local b1 = ch:byte(1)
   return b1 and b1 >= 0xE4 and b1 <= 0xE9
end

-- 判断是否为字母（ASCII 或全角）
local function is_letter(ch)
   if not ch or ch == "" then return false end
   local b1 = ch:byte(1)
   if not b1 then return false end
   
   -- ASCII 字母 A-Z, a-z
   if (b1 >= 65 and b1 <= 90) or (b1 >= 97 and b1 <= 122) then
       return true
   end
   
   -- 全角字母（U+FF21~FF3A, U+FF41~FF5A）：EF BC XX / EF BD XX
   if b1 == 0xEF then
       local b2 = ch:byte(2)
       if b2 == 0xBC then
           local b3 = ch:byte(3)
           return b3 and ((b3 >= 0xA1 and b3 <= 0xBA) or (b3 >= 0x81 and b3 <= 0x9A))
       elseif b2 == 0xBD then
           local b3 = ch:byte(3)
           return b3 and ((b3 >= 0x81 and b3 <= 0x9A) or (b3 >= 0xA1 and b3 <= 0xBA))
       end
   end
   
   return false
end

-- 获取第一个 UTF-8 字符及其长度
local function utf8_first(s)
   if not s or s == "" then return nil, 0 end
   
   local b1 = s:byte(1)
   local len
   
   if b1 < 0x80 then
       len = 1
   elseif b1 < 0xC0 then
       return nil, 0
   elseif b1 < 0xE0 then
       len = 2
   elseif b1 < 0xF0 then
       len = 3
   else
       len = 4
   end
   
   if #s < len then return nil, 0 end
   return s:sub(1, len), len
end

-- 主函数：只保留汉字和字母
local function keep_hanzi_letters(s)
   if not s then return "" end
   
   local result = {}
   local i = 1
   
   while i <= #s do
       local ch, len = utf8_first(s:sub(i))
       if not ch then
           i = i + 1
       else
           if is_hanzi(ch) or is_letter(ch) then
               table.insert(result, ch)
           end
           i = i + len
       end
   end
   
   return table.concat(result)
end


-- 读取文件，删除连续空行并去重（保留首次出现的行）
local function deduplicate_and_clean(filepath)
   local f = io.open(filepath, "r")
   if not f then return nil, "cannot open: " .. filepath end
   
   local lines = {}
   local seen = {}
   
   for line in f:lines() do
       -- 去重：只保留第一次出现的行
       if not seen[line] then
           seen[line] = true
           table.insert(lines, line)
       end
   end
   f:close()
   
   -- 删除连续空行（两个及以上换行合并为一个）
   -- 先标记空行位置，再构建结果
   local result = {}
   local prev_empty = false
   
   for _, line in ipairs(lines) do
       local is_empty = line:match("^%s*$") ~= nil
       
       if is_empty then
           if not prev_empty then
               table.insert(result, "")
           end
           prev_empty = true
       else
           table.insert(result, line)
           prev_empty = false
       end
   end
   
   -- 写回文件
   f = io.open(filepath, "w")
   if not f then return nil, "cannot write: " .. filepath end
   f:write(table.concat(result, "\n"))
   -- 确保文件末尾有换行
   if #result > 0 then
       f:write("\n")
   end
   f:close()
   
   return true
end


function qaw.init(env)
    local engine = env.engine
    local context = engine.context
    local dict_path = DICT_PATH
    env.dict_path = dict_path

    -- 如果q_add_word在打开状态，监听每个输入的字，准备写入用户词典末尾
    env.notifier = context.commit_notifier:connect(function(ctx)
        if not ctx:get_option("q_add_word") then
            return
        end

        local text = ctx:get_commit_text()

        if text then
          qaw.text = qaw.text .. text
        end
    end)

    -- 在q_add_word被关闭时，添加一个换行
    env.option_notifier = context.option_update_notifier:connect(function(ctx, name)
        if name ~= "q_add_word" then
            return
        end

        local is_on = ctx:get_option("q_add_word") or false

        if is_on then return end
        -- Just turned off: append newline to add the word

        qaw.text = keep_hanzi_letters(qaw.text)

        local file = io.open(env.dict_path, "a")
        if file then
            file:write(qaw.text .. "\n")
            file:close()
        else
            log.error("Failed to open dictionary: " .. env.dict_path)
            return
        end

        qaw.text = ""
        
        local ok, err = deduplicate_and_clean(env.dict_path)
        if not ok then
            log.error("deduplicate failed: " .. (err or "unknown"))
        end
    end)
end

function qaw.fini(env)
    if env.notifier then
        env.notifier:disconnect()
    end

    if env.option_notifier then
        env.option_notifier:disconnect()
    end
end

function qaw.func(key, env)
    return 2  -- kNoop
end

return qaw
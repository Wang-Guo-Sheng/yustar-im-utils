-- cycle_select.lua
-- works with cycle_select_filter.lua
-- Delete false input when user made a typo
-- This is useful when user commited a long word by mistake and need to press backspace multiple times 
-- Since librime does not process backspace or any real keyevents itself,
-- this script use external keycode senders: rime-lua-sendKeyCode or replaceCommit
-- sendKeyCode.press_key(<virtual keycode>, <repeat times>) send a keycode for given times
-- replaceCommit.replace(<number of backspaces>, <text to commit>) replace a typo with given text string 
-- both are modified from qiuyue0/rime-lua-sendKeyCode
-- 
-- 自动删除一整个打错的词。
-- 修改INPUT_PUSH在两种模式中选择：
-- 为true时删除时自动弹出上一个词的编码，可以直接重新选词
-- 为false时删除后不弹出编码，再次按下则自动上屏上一个词的第二候选
--  第三次按下再次删除，再按下时自动上屏第三候选，依此类推

local INPUT_PUSH = false  -- True: re-push input code; False: cycle-select candidates

local ccsel = {}
local kNoop = 2
local utf8_pattern = "[%z\1-\127\194-\244][\128-\191]*"

ccsel.shared = {
  last = {core = "",
    suffix = "",
    len = 0,
    index = 1,
  }, -- 记录上一个输入的词
  next_input = "",  -- 记录当前词编码
  last_input = "",  -- 上一个词的编码
  cands = {},  -- 当前或刚上屏的词的候选列表
  last_cands = {},  -- 上一个词的候选列表
  is_replaying = false,     -- 等待外部库处理
  allow_delete = true,  -- 可退格，防止删掉更早前的词
  repeat_press = 0,  -- 修改次数
  over_repeat = false,  -- INPUT_PUSH模式每次上屏后按下两次以上时，不再执行
  pending_punct = "",  -- 记录上屏的中文标点
}

local loader = package.loadlib("C:\\Users\\wguos\\AppData\\Roaming\\luarocks\\lib\\lua\\5.1\\replaceCommit.dll", "luaopen_replaceCommit")
local replaceCommit = loader()
loader = package.loadlib("C:\\Users\\wguos\\AppData\\Roaming\\luarocks\\lib\\lua\\5.1\\sendKeyCode.dll", "luaopen_sendKeyCode")
local sendKeyCode = loader()

function ccsel.utf8len(s)
    local len = 0
    for i = 1, #s do
        local c = s:byte(i)
        -- 统计 UTF-8 字符的首字节（不是 10xxxxxx 的）
        if c < 0x80 or c >= 0xC0 then
            len = len + 1
        end
    end
    return len
end

local function utf8charbytes(s, i)
    local c = string.byte(s, i)
    if c < 0x80 then return 1
    elseif c < 0xC0 then return 1  -- invalid continuation
    elseif c < 0xE0 then return 2
    elseif c < 0xF0 then return 3
    else return 4 end
end

local function utf8sub(s, i, j)
    j = j or i
    local pos = 1
    local charpos = 1
    local result = {}
    while pos <= #s do
        local bytes = utf8charbytes(s, pos)
        if charpos >= i and charpos <= j then
            table.insert(result, string.sub(s, pos, pos + bytes - 1))
        end
        if charpos > j then break end
        pos = pos + bytes
        charpos = charpos + 1
    end
    return table.concat(result)
end


-- 判断是否为汉字（支持单个字符或字符串）
local function is_hanzi(ch)
    if not ch or ch == "" then
        return false
    end
    
    -- 获取首字节
    local byte = string.byte(ch)
    
    -- 汉字在 UTF-8 中通常以 0xE4~0xE9 开头（3字节编码）
    -- 覆盖绝大多数常用汉字（CJK 统一表意文字基本区）
    return byte >= 0xE4 and byte <= 0xE9
end

-- 简单拆分：末尾非汉字作为 suffix
local function split_text(text)
    local len = ccsel.utf8len(text)
    if not len then return text, "" end

    local i = len
    while i > 0 do
      local ch = utf8sub(text, i, i)
      if is_hanzi(ch) then
        break
      end
      i = i - 1
    end

    if i == len then
      return text, ""
    else
      return utf8sub(text, 1, i), utf8sub(text, i + 1)
    end
end

-- 保存词
function ccsel.store_text(text, index)
    local core, suffix = split_text(text)
    local shr = ccsel.shared

    shr.last = {
      core = core,
      suffix = suffix,
      len = ccsel.utf8len(text),
      index = index
    }

    log.info(text .. " is captured as " .. core )
end

-- 深拷贝（用于保存上一个候选列表）
local function copy_table(t)
    local copy = {}
    for i, v in ipairs(t) do
        copy[i] = v
    end
    return copy
end

-- =========================
-- init：注册 commit_notifier
-- =========================
function ccsel.init(env)
  local context = env.engine.context
  local config = env.engine.schema.config
  local alphabet = config:get_string("speller/alphabet")
  
  -- when commit, store commit length and other info to env
  -- 保存刚刚上屏的词的信息
  context.commit_notifier:connect(function(ctx)
    local shr = ccsel.shared
    shr.repeat_press = 0
    shr.over_repeat = false
    if shr.is_replaying then
      return
    end
    log.info("commit capturing")

    local text = ctx:get_commit_text()
    if not text or text == "" then
      return
    end

    if shr.pending_punct ~= "" then
      shr.is_replaying = true
      -- 删除上一个词
      replaceCommit.replace(0, shr.pending_punct)
      shr.is_replaying = false
      shr.last.suffix = shr.pending_punct
      shr.pending_punct = ""
    end

    ccsel.store_text(text, 1)
    shr.allow_delete = true

    shr.last_cands = copy_table(shr.cands)
    shr.last_input = shr.next_input
  end)

  -- when toggle ccsel, do the delete-replace cycle
  env.option_notifier = context.option_update_notifier:connect(function(ctx, name)
    local shr = ccsel.shared
    if name ~= "cycle_select" then return end
    if shr.over_repeat then return end
    if INPUT_PUSH and (shr.repeat_press > 2) then
      shr.repeat_press = 0
      shr.over_repeat = true
      return
    end
    shr.repeat_press = shr.repeat_press + 1

    -- 如果是在输入中按下的：
    if ctx:is_composing() then
      -- 舍弃新的输入
      ctx:clear()
      -- 记录状态，等待再按一次
      shr.allow_delete = true
      -- 恢复使用上一组候选词
      -- last 本身并未更新，所以不用恢复
      shr.cands = copy_table(shr.last_cands)
      -- return --取消注释则第一次按下只清除输入框
    end

    -- 一般地，在没有输入框时按下，
    local last = shr.last
    if not last then 
      log.error("cycle: nil last") 
      return 
    end

    local last_input = shr.last_input
    local cands = shr.cands

    if #cands == 0 then
      log.warning("cycle: empty cands")
      return 
    end

    log.info("cycle running")

    -- 按第一下时，删除上一个词
    if shr.allow_delete then
      if not INPUT_PUSH or shr.repeat_press < 2 then
        -- 防止触发 notifier
        shr.is_replaying = true
        -- 删除上一个词
        replaceCommit.replace(last.len, "")
        shr.is_replaying = false
      elseif shr.repeat_press < 3 then
        ctx:clear()
        return
      end
      shr.allow_delete = false
      -- 同时把上一个词的编码恢复到输入框
      if INPUT_PUSH then
        for ch in last_input:gmatch(utf8_pattern) do
            -- The '1, true' ensures characters like '.' or '-' don't break the search
            if string.find(alphabet, ch, 1, true) then  -- 排除标点上屏时input末尾的中文标点
                sendKeyCode.press_key(ch, 1)  -- 恢复输入框
            end
        end
        -- 保存标点，等候用户选词
        if last.suffix ~= "" then
          shr.pending_punct = last.suffix
        end
      end
      return
    end

    -- 更新状态
    shr.allow_delete = true
    log.info("commited new candidate")
    
    -- 如果没有选词，直接按第二下
    if INPUT_PUSH then
      -- 清除输入框，彻底删除之
      ctx:clear()
      return
    end

    -- 在循环选词模式下，反复按下时
    -- 每按两下，自动上屏下一个候选
    -- （奇数次删除，偶数次上屏，方便改错）
    local index = last.index + 1
    if index > #cands then
      index = 1
    end

    local new_core = cands[index]
    local new_text = new_core .. (last.suffix or "")

    shr.is_replaying = true
    -- 输入新的候选词
    replaceCommit.replace(0, new_text)
    shr.is_replaying = false

    ccsel.store_text(new_text, index)
  end)
end

function ccsel.fini(env)
    if env.notifier then
        env.notifier:disconnect()
    end

    if env.option_notifier then
        env.option_notifier:disconnect()
    end
end

function ccsel.func(key, env)
    return kNoop
end

return ccsel

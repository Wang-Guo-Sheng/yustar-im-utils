-- cycle_select_filter.lua
-- works with cycle_select.lua

-- =========================
-- filter：缓存候选
-- =========================
local ccsel = require("yuhao.cycle_select")
local shr = ccsel.shared

function ccsel_filter(input, env)
  if not input then 
    for cand in input:iter() do yield(cand) end
    return
  end

  local context = env.engine.context
  local input_str = context.input

  shr.next_input = input_str

  local i = 1
  for cand in input:iter() do
    shr.cands[i] = cand.text
    i = i + 1
    yield(cand)
  end

  shr.allow_delete = true
  log.info("stored candidates")
end

return ccsel_filter
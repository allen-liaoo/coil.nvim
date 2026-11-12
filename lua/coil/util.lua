local uv = vim.uv or vim.loop
local M = {}

---Wrap `fn` so it only runs once calls stop arriving for `ms` milliseconds
---@param ms integer
---@param fn fun()
---@return fun() debounced
---@return fun() cancel
M.debounce = function(ms, fn)
  local timer = assert(uv.new_timer())
  local function debounced()
    if timer:is_closing() then
      return
    end
    timer:stop()
    timer:start(ms, 0, vim.schedule_wrap(fn))
  end
  local function cancel()
    timer:stop()
    if not timer:is_closing() then
      timer:close()
    end
  end
  return debounced, cancel
end

---Set window-local options (like :setlocal, so they don't leak into later splits)
---@param winid integer
---@param options table<string, any>
M.set_win_options = function(winid, options)
  for name, value in pairs(options) do
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = winid })
  end
end

return M

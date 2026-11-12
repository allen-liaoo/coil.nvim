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

---Set options for a window whose buffer coil swaps (a pane). Like `:set` in that window rather
---than `:setlocal`: a `:setlocal` value only holds for the buffer shown at the time, so it would be
---lost at the next swap. Windows later split off this one inherit the values.
---Global-local options (e.g. 'winbar') are the exception: they only hold until the next swap.
---@param winid integer
---@param options table<string, any>
M.set_win_options = function(winid, options)
  for name, value in pairs(options) do
    vim.api.nvim_set_option_value(name, value, { win = winid })
  end
end

return M

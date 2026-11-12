-- Opening things outside the column view: files go to the editing window (where :Coil was run).
local bridge = require("coil.oil_bridge")
local M = {}

---@alias coil.OpenHow nil|"vsplit"|"split"|"tab"

---The window to open files in: the origin window if it still exists outside the view, otherwise
---the current window of any other tab
---@param view coil.View
---@return nil|integer
local function editing_window(view)
  local origin = view.origin.win
  if vim.api.nvim_win_is_valid(origin) and vim.api.nvim_win_get_tabpage(origin) ~= view.tab then
    return origin
  end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if tab ~= view.tab then
      return vim.api.nvim_tabpage_get_win(tab)
    end
  end
end

---Show `bufnr` in the editing tab and switch there. The column view stays open.
---@param view coil.View
---@param bufnr integer
---@param how coil.OpenHow
M.in_editing_tab = function(view, bufnr, how)
  local winid = editing_window(view)
  if winid then
    vim.api.nvim_set_current_win(winid)
  end
  if not winid or how == "tab" then
    vim.cmd.tabnew()
    -- Wipe the empty buffer tabnew created once the file replaces it
    vim.bo.bufhidden = "wipe"
  end

  local cmd = (how == "vsplit" or how == "split") and "sbuffer" or "buffer"
  local ok, err = pcall(vim.cmd, {
    cmd = cmd,
    args = { bufnr },
    mods = { vertical = how == "vsplit" },
  })
  -- Ignore swapfile warnings, like oil does
  if not ok and err and not err:match("^Vim:E325:") then
    vim.notify("[coil] " .. err, vim.log.levels.ERROR)
  end
  view.origin = { tab = vim.api.nvim_get_current_tabpage(), win = vim.api.nvim_get_current_win() }
end

---Something other than an oil directory ended up in the middle pane (e.g. `:edit file`). Move it
---to the editing tab and put the last directory back.
---@param view coil.View
---@param bufnr integer The buffer that landed in the middle pane
---@param restore_buf? integer The oil buffer the middle pane showed before
M.redirect_from_middle = function(view, bufnr, restore_buf)
  local middle = view.panes.current
  if restore_buf and vim.api.nvim_buf_is_valid(restore_buf) then
    vim.api.nvim_win_set_buf(middle, restore_buf)
  else
    vim.api.nvim_win_call(middle, function()
      bridge.open_dir((bridge.url_for_path(nil)))
    end)
  end
  M.in_editing_tab(view, bufnr, nil)
end

return M

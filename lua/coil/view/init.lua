-- The column view: a dedicated tab with parent | current | preview panes.
local bridge = require("coil.oil_bridge")
local config = require("coil.config")
local layout = require("coil.view.layout")
local state = require("coil.view.state")
local sync = require("coil.view.sync")
local M = {}

---Stop everything the view started (autocmds, timers)
---@param view coil.View
local function teardown(view)
  for _, fn in ipairs(view.cleanup) do
    pcall(fn)
  end
  view.cleanup = {}
  pcall(vim.api.nvim_del_augroup_by_id, view.group)
end

---Close a tabpage. A tab can't be closed while it is the only one, so open a spare first.
---@param tab integer
local function close_tab(tab)
  if not vim.api.nvim_tabpage_is_valid(tab) then
    return
  end
  if #vim.api.nvim_list_tabpages() == 1 then
    vim.cmd.tabnew()
  end
  local ok, err = pcall(vim.cmd.tabclose, vim.api.nvim_tabpage_get_number(tab))
  if not ok then
    vim.notify("[coil] Could not close the column view: " .. err, vim.log.levels.ERROR)
  end
end

---Close the column view and return to the window it was opened from
M.close = function()
  local view = state.get()
  if not view then
    return
  end
  state.clear()
  teardown(view)
  close_tab(view.tab)
  if vim.api.nvim_win_is_valid(view.origin.win) then
    vim.api.nvim_set_current_win(view.origin.win)
  end
end

---@param view coil.View
local function attach_autocmds(view)
  local pane_ids = {}
  for _, winid in pairs(view.panes) do
    table.insert(pane_ids, tostring(winid))
  end

  vim.api.nvim_create_autocmd("VimResized", {
    group = view.group,
    callback = function()
      layout.reflow(view.panes, config.get().ratio)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = view.group,
    pattern = pane_ids,
    desc = "Closing any pane closes the whole column view",
    callback = function()
      -- Closing windows inside WinClosed is not allowed, so defer
      vim.schedule(function()
        if state.get() == view then
          M.close()
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = view.group,
    callback = function()
      if not vim.api.nvim_tabpage_is_valid(view.tab) then
        if state.get() == nil or state.get() == view then
          state.clear()
        end
        teardown(view)
      end
    end,
  })
end

---Open the column view on `dir`, or switch to it if it is already open
---@param dir? string A path or oil URL; nil means the current buffer's directory
M.open = function(dir)
  local view = state.get()
  if view then
    vim.api.nvim_set_current_tabpage(view.tab)
    vim.api.nvim_set_current_win(view.panes.current)
    if dir then
      bridge.open_dir((bridge.url_for_path(dir)))
    end
    return
  end

  -- Resolve the directory while the original buffer is still current
  local url, focus_name = bridge.url_for_path(dir)
  local origin = { tab = vim.api.nvim_get_current_tabpage(), win = vim.api.nvim_get_current_win() }

  vim.cmd.tabnew()
  -- Wipe the empty buffer tabnew created once oil replaces it
  vim.bo.bufhidden = "wipe"
  local current = vim.api.nvim_get_current_win()
  -- Create the side panes before oil sets its window options on the middle one,
  -- so they don't inherit them
  local panes = layout.open(current)

  ---@type coil.View
  view = {
    tab = vim.api.nvim_get_current_tabpage(),
    panes = panes,
    origin = origin,
    group = vim.api.nvim_create_augroup("CoilView", { clear = true }),
    cleanup = {},
  }
  state.set(view)
  attach_autocmds(view)
  -- Attached before oil opens, so the first BufWinEnter in the middle pane fills the side panes
  table.insert(view.cleanup, sync.attach(view))

  bridge.open_dir(url, focus_name)
  layout.reflow(panes, config.get().ratio)
end

---@return boolean
M.is_open = function()
  return state.get() ~= nil
end

return M

-- The column view: a dedicated tab with parent | current | preview panes. Several can be open,
-- one per tab.| current | preview panes.
local bridge = require("coil.oil_bridge")
local config = require("coil.config")
local keys = require("coil.view.keys")
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

---Close a column view (default: the current tab's, otherwise the one used most recently) and
---return to the window it was opened from
---@param view? coil.View
M.close = function(view)
  view = view or state.get() or state.last()
  if not view or not state.is_open(view) then
    return
  end
  state.remove(view)
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
        M.close(view)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = view.group,
    desc = "Remember the column view used most recently",
    callback = function()
      if vim.api.nvim_get_current_tabpage() == view.tab then
        state.touch(view)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabClosed", {
    group = view.group,
    callback = function()
      if not vim.api.nvim_tabpage_is_valid(view.tab) then
        state.remove(view)
        teardown(view)
      end
    end,
  })
end

---Fill the side panes and wrap keys once the middle buffer is ready. Normally autocmds (the middle
---pane's BufWinEnter, TabEnter) do this, but they don't fire when :Coil runs inside another,
---non-nested autocmd, e.g. `autocmd VimEnter * Coil`.
---@param view coil.View
local function sync_when_ready(view)
  local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
  bridge.on_ready(bufnr, function()
    if state.is_open(view) and vim.api.nvim_win_get_buf(view.panes.current) == bufnr then
      sync.all(view)
      keys.wrap_buffer(bufnr)
    end
  end)
end

---Switch to `view`, optionally moving it to `dir`
---@param view coil.View
---@param dir? string
local function show(view, dir)
  vim.api.nvim_set_current_tabpage(view.tab)
  vim.api.nvim_set_current_win(view.panes.current)
  state.touch(view)
  if dir then
    bridge.open_dir((bridge.url_for_path(dir)))
  end
  sync_when_ready(view)
end

---Open a new column view on `dir` in a new tab
---@param dir? string A path or oil URL; nil means the current buffer's directory
local function open_tab(dir)
  -- Resolve the directory while the original buffer is still current
  local url, focus_name = bridge.url_for_path(dir)
  local here = state.get()
  -- From a column view, files keep opening where that view opens them
  local origin = here and vim.deepcopy(here.origin)
    or { tab = vim.api.nvim_get_current_tabpage(), win = vim.api.nvim_get_current_win() }

  vim.cmd.tabnew()
  -- Wipe the empty buffer tabnew created once oil replaces it
  vim.bo.bufhidden = "wipe"
  local current = vim.api.nvim_get_current_win()
  -- Create the side panes before oil sets its window options on the middle one,
  -- so they don't inherit them
  local panes = layout.open(current)
  local tab = vim.api.nvim_get_current_tabpage()

  ---@type coil.View
  local view = {
    tab = tab,
    panes = panes,
    origin = origin,
    group = vim.api.nvim_create_augroup("CoilView" .. tab, { clear = true }),
    cleanup = {},
  }
  state.add(view)
  attach_autocmds(view)
  -- Attached before oil opens, so the first BufWinEnter in the middle pane fills the side panes
  table.insert(view.cleanup, sync.attach(view))
  table.insert(view.cleanup, keys.attach(view))

  bridge.open_dir(url, focus_name)
  layout.reflow(panes, config.get().ratio)
  sync_when_ready(view)
end

---Open the column view on `dirs`, one tab per directory. The first goes to the current tab's
---view if there is one, otherwise to the view used most recently, or a new one if none is open;
---each further directory opens another view in a new tab. Focus ends on the first.
---@param dirs? string|string[] Paths or oil URLs; nil (or none) means the current buffer's directory
M.open = function(dirs)
  if type(dirs) ~= "table" then
    dirs = { dirs }
  end
  local first = state.get() or state.last()
  if first then
    show(first, dirs[1])
  else
    open_tab(dirs[1])
    first = assert(state.get())
  end
  if #dirs > 1 then
    for i = 2, #dirs do
      open_tab(dirs[i])
    end
    show(first, nil)
  end
end

---@return boolean
M.is_open = function()
  return state.last() ~= nil
end

return M

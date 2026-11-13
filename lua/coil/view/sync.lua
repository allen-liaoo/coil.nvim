-- Keeps the side panes in step with the middle pane, whose buffer is the source of truth:
-- the parent pane lists its parent directory, the preview pane shows the entry under its cursor.
local bridge = require("coil.oil_bridge")
local config = require("coil.config")
local listing = require("coil.view.listing")
local open = require("coil.view.open")
local preview = require("coil.preview")
local util = require("coil.util")
local M = {}

---@class (exact) coil.SyncState
---@field parent_gen integer Bumped per parent listing; older listings are dropped
---@field preview_url? string What the preview pane shows
---@field last_dir_buf? integer The last oil directory in the middle pane
---@field signature? string oil's listing settings at the last parent refresh
---@field watched table<integer, boolean> Middle buffers whose changes are watched

-- Per-view sync bookkeeping, keyed by the view's tab
---@type table<integer, coil.SyncState>
local sync_state = {}

---@param view coil.View
local function state_of(view)
  sync_state[view.tab] = sync_state[view.tab] or { parent_gen = 0, watched = {} }
  return sync_state[view.tab]
end

---@param view coil.View
---@return nil|integer bufnr The middle pane's buffer, if it is an oil directory
local function middle_oil_buffer(view)
  if not vim.api.nvim_win_is_valid(view.panes.current) then
    return nil
  end
  local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
  return bridge.is_oil_dir(bufnr) and bufnr or nil
end

-- 'winbar' is a global-local option: a window's own value only lasts until its buffer changes,
-- and setting the global value would title every window. So each pane's title is remembered
-- here and re-applied whenever a buffer enters the pane (see the BufWinEnter autocmd).
---@type table<integer, string> winid -> winbar
local titles = {}

---@param winid integer
local function apply_title(winid)
  if titles[winid] and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_set_option_value("winbar", titles[winid], { scope = "local", win = winid })
  end
end

---Show `text` as the pane's title line
---@param winid integer
---@param text string
local function set_winbar(winid, text)
  if not config.get().winbar then
    return
  end
  -- Keep a title line even when empty, so the three panes' rows stay aligned
  local escaped = text:gsub("%%", "%%%%")
  titles[winid] = " " .. escaped
  apply_title(winid)
end

---Name the view's tab after the middle directory. Uses the tab variable `tabname`, which tab lines
---such as lualine's `tabs` component show instead of the focused buffer's name (for an oil
---directory that name would be empty, and the preview pane's buffer has none).
---@param view coil.View
---@param url string
local function set_tab_title(view, url)
  if config.get().tab_title and vim.api.nvim_tabpage_is_valid(view.tab) then
    vim.t[view.tab].tabname = bridge.display_path(url)
  end
end

---Refresh the side panes when oil's listing settings change (`gs`, `g.`, `oil.set_sort()`, ...).
---oil applies those by re-rendering its buffers and fires no event, so watch the middle buffer's
---lines and compare oil's settings with the ones the side panes were drawn with.
---@param view coil.View
---@param bufnr integer
local function watch_listing_settings(view, bufnr)
  local st = state_of(view)
  if st.watched[bufnr] then
    return
  end
  st.watched[bufnr] = true
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      if sync_state[view.tab] ~= st then
        -- The view is gone: stop watching
        return true
      end
      if st.signature and bridge.listing_signature() ~= st.signature then
        st.signature = bridge.listing_signature()
        vim.schedule(function()
          if sync_state[view.tab] == st then
            M.all(view)
          end
        end)
      end
    end,
    on_detach = function()
      st.watched[bufnr] = nil
    end,
  })
end

---List the middle directory's parent into the parent pane
---@param view coil.View
M.parent = function(view)
  local st = state_of(view)
  st.parent_gen = st.parent_gen + 1
  local gen = st.parent_gen
  local winid = view.panes.parent
  st.signature = bridge.listing_signature()

  local bufnr = middle_oil_buffer(view)
  local parent_url, name
  if bufnr then
    watch_listing_settings(view, bufnr)
    local url = vim.api.nvim_buf_get_name(bufnr)
    set_tab_title(view, url)
    set_winbar(view.panes.current, bridge.display_path(url))
    parent_url, name = bridge.parent_of(url)
  end
  set_winbar(winid, parent_url and bridge.display_path(parent_url) or "")
  if not parent_url then
    -- At the root, or the middle pane isn't showing a directory
    preview.clear(winid)
    -- Swaps made from inside an autocmd don't fire BufWinEnter, so re-title explicitly
    return apply_title(winid)
  end

  bridge.list_dir(parent_url, function(err, entries)
    if st.parent_gen ~= gen or not vim.api.nvim_win_is_valid(winid) then
      return
    end
    if err then
      preview.clear(winid, { "Cannot list " .. parent_url, err })
    else
      listing.show(winid, entries or {}, name, parent_url)
    end
    apply_title(winid)
    -- Always list the directory we're in, even if it is hidden, so it can be highlighted
  end, { bufnr = bufnr, always_show = name })
end

---Preview the entry under the middle pane's cursor
---@param view coil.View
---@param force? boolean Re-render even if the cursor is on the same entry as last time
M.preview = function(view, force)
  local st = state_of(view)
  local winid = view.panes.preview
  local target = middle_oil_buffer(view) and bridge.cursor_target(view.panes.current)
  local url = target and target.url
  if url == st.preview_url and not force then
    return
  end
  st.preview_url = url
  if target then
    set_winbar(winid, target.is_dir and (target.name .. "/") or target.name)
    preview.show(winid, target, { list_dir = bridge.list_dir })
    preview.prefetch(winid, bridge.targets_near(view.panes.current, preview.prefetch_distance()))
  else
    set_winbar(winid, "")
    preview.clear(winid)
  end
  -- Covers synchronous placements; directory listings land later and are re-titled by BufWinEnter
  apply_title(winid)
end

---@param view coil.View
M.all = function(view)
  M.parent(view)
  M.preview(view, true)
end

---Register the autocmds that drive syncing. They live in the view's group.
---@param view coil.View
---@return fun() detach
M.attach = function(view)
  local is_middle = function()
    return vim.api.nvim_get_current_win() == view.panes.current
  end

  local debounced_preview, cancel = util.debounce(config.get().debounce_ms, function()
    M.preview(view)
  end)

  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = view.group,
    desc = "Re-title a pane after a buffer swap; sync when the middle pane changed directory",
    callback = function(args)
      apply_title(vim.api.nvim_get_current_win())
      if not is_middle() then
        return
      end
      local st = state_of(view)
      local bufnr = middle_oil_buffer(view)
      if bufnr then
        st.last_dir_buf = bufnr
        bridge.on_ready(bufnr, function()
          M.all(view)
        end)
      elseif vim.fn.isdirectory(vim.api.nvim_buf_get_name(args.buf)) == 0 then
        -- A file (or anything else) landed in the middle pane: move it to the editing tab.
        -- A plain directory path is left alone; oil is about to turn it into an oil buffer.
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            open.redirect_from_middle(view, args.buf, st.last_dir_buf)
          end
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = view.group,
    callback = function()
      -- Visual mode means editing, not browsing; skip to avoid flicker
      if is_middle() and not vim.fn.mode():match("^[vV\22]") then
        debounced_preview()
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = view.group,
    pattern = "OilMutationComplete",
    desc = "Files changed on disk",
    callback = function()
      M.all(view)
    end,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = view.group,
    desc = "Files may have changed while away",
    callback = function()
      if vim.api.nvim_get_current_tabpage() == view.tab then
        M.all(view)
      end
    end,
  })

  return function()
    cancel()
    sync_state[view.tab] = nil
    for _, winid in pairs(view.panes) do
      titles[winid] = nil
    end
  end
end

return M

-- Keeps the side panes in step with the middle pane, whose buffer is the source of truth:
-- the parent pane lists its parent directory, the preview pane shows the entry under its cursor.
local bridge = require("coil.oil_bridge")
local config = require("coil.config")
local listing = require("coil.view.listing")
local open = require("coil.view.open")
local preview = require("coil.preview")
local util = require("coil.util")
local M = {}

-- Per-view sync bookkeeping, keyed by the view's tab
---@type table<integer, {parent_gen: integer, preview_url?: string, last_dir_buf?: integer}>
local sync_state = {}

---@param view coil.View
local function state_of(view)
  sync_state[view.tab] = sync_state[view.tab] or { parent_gen = 0 }
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

---List the middle directory's parent into the parent pane
---@param view coil.View
M.parent = function(view)
  local st = state_of(view)
  st.parent_gen = st.parent_gen + 1
  local gen = st.parent_gen
  local winid = view.panes.parent

  local bufnr = middle_oil_buffer(view)
  local parent_url, name
  if bufnr then
    parent_url, name = bridge.parent_of(vim.api.nvim_buf_get_name(bufnr))
  end
  if not parent_url then
    -- At the root, or the middle pane isn't showing a directory
    return preview.clear(winid)
  end

  bridge.list_dir(parent_url, function(err, entries)
    if st.parent_gen ~= gen or not vim.api.nvim_win_is_valid(winid) then
      return
    end
    if err then
      preview.clear(winid, { "Cannot list " .. parent_url, err })
    else
      listing.show(winid, entries or {}, name)
    end
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
    preview.show(winid, target, { list_dir = bridge.list_dir })
  else
    preview.clear(winid)
  end
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
    desc = "Middle pane changed directory",
    callback = function(args)
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
  end
end

return M

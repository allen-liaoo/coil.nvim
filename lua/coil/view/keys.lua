-- Keymaps for the column view. Neovim has no window-local keymaps, so coil wraps keys in the oil
-- buffers it shows: in the middle pane a wrapper runs the coil action, and anywhere else it runs
-- whatever the key did before (oil's mapping, a global mapping, or Vim's built-in key).
local bridge = require("coil.oil_bridge")
local config = require("coil.config")
local open = require("coil.view.open")
local state = require("coil.view.state")
local sync = require("coil.view.sync")
local M = {}

local DESC_PREFIX = "coil: "

---@param view coil.View
---@param how coil.OpenHow
local function select_entry(view, how)
  bridge.select(function(bufnr, is_dir)
    if is_dir and how == nil then
      -- Directories open in place; the middle pane's BufWinEnter re-syncs the side panes
      vim.api.nvim_win_set_buf(view.panes.current, bufnr)
    else
      open.in_editing_tab(view, bufnr, how)
    end
  end)
end

---@type table<string, fun(view: coil.View)>
M.actions = {
  go_in = function(view)
    select_entry(view, nil)
  end,
  go_out = function()
    bridge.open_parent()
  end,
  open = function(view)
    select_entry(view, nil)
  end,
  open_vsplit = function(view)
    select_entry(view, "vsplit")
  end,
  open_split = function(view)
    select_entry(view, "split")
  end,
  open_tab = function(view)
    select_entry(view, "tab")
  end,
  focus_preview = function(view)
    vim.api.nvim_set_current_win(view.panes.preview)
  end,
  toggle_hidden = function(view)
    bridge.toggle_hidden()
    sync.all(view)
  end,
  close = function()
    require("coil.view").close()
  end,
}

---Run what `lhs` did before coil wrapped it
---@param lhs string
---@param original table maparg() dict of the previous mapping ({} if there was none)
local function fallback(lhs, original)
  if vim.tbl_isempty(original) then
    -- No mapping: Vim's built-in key, keeping any count (e.g. 5L)
    local count = vim.v.count > 0 and tostring(vim.v.count) or ""
    vim.api.nvim_feedkeys(count .. vim.keycode(lhs), "n", false)
    return
  end
  local keys
  if original.callback then
    keys = original.callback()
    if original.expr ~= 1 then
      return
    end
  elseif original.expr == 1 then
    keys = vim.api.nvim_eval(original.rhs)
  else
    keys = original.rhs
  end
  if type(keys) == "string" and keys ~= "" then
    vim.api.nvim_feedkeys(vim.keycode(keys), original.noremap == 1 and "n" or "m", false)
  end
end

---Wrap coil's keys in an oil buffer. Safe to call repeatedly: keys that are already wrapped are
---skipped, and keys oil re-mapped (e.g. after reloading the buffer) are wrapped again.
---@param bufnr integer
M.wrap_buffer = function(bufnr)
  for action, lhs in pairs(config.get().keymaps) do
    if lhs and M.actions[action] then
      local original = vim.api.nvim_buf_call(bufnr, function()
        return vim.fn.maparg(lhs, "n", false, true)
      end)
      if not vim.startswith(original.desc or "", DESC_PREFIX) then
        vim.keymap.set("n", lhs, function()
          local view = state.get()
          if view and vim.api.nvim_get_current_win() == view.panes.current then
            M.actions[action](view)
          else
            fallback(lhs, original)
          end
        end, {
          buffer = bufnr,
          nowait = true,
          desc = DESC_PREFIX .. action .. " (column view only)",
        })
      end
    end
  end
end

---Keys in the preview pane's buffers, which coil creates, so no wrapping is needed
---@param view coil.View
---@param bufnr integer
local function map_preview_buffer(view, bufnr)
  local keymaps = config.get().keymaps
  if keymaps.focus_preview then
    vim.keymap.set("n", keymaps.focus_preview, function()
      vim.api.nvim_set_current_win(view.panes.current)
    end, { buffer = bufnr, nowait = true, desc = DESC_PREFIX .. "back to the middle pane" })
  end
  if keymaps.close then
    vim.keymap.set("n", keymaps.close, M.actions.close, {
      buffer = bufnr,
      nowait = true,
      desc = DESC_PREFIX .. "close",
    })
  end
end

---@param view coil.View
M.attach = function(view)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = view.group,
    desc = "Wrap coil keys in buffers shown in the middle and preview panes",
    callback = function(args)
      local winid = vim.api.nvim_get_current_win()
      if winid == view.panes.current and bridge.is_oil_dir(args.buf) then
        -- oil sets its own keymaps once the listing is ready, so wrap after that
        bridge.on_ready(args.buf, function()
          M.wrap_buffer(args.buf)
        end)
      elseif winid == view.panes.preview then
        map_preview_buffer(view, args.buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = view.group,
    desc = "Preview pane keys; the parent pane is display-only",
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      if winid == view.panes.preview then
        -- Covers buffers placed before these autocmds existed
        return map_preview_buffer(view, vim.api.nvim_get_current_buf())
      elseif winid ~= view.panes.parent then
        return
      end
      vim.schedule(function()
        -- Coil itself may briefly enter the pane (e.g. to scroll it); only bounce real visits
        if
          vim.api.nvim_get_current_win() == view.panes.parent
          and vim.api.nvim_win_is_valid(view.panes.current)
        then
          vim.api.nvim_set_current_win(view.panes.current)
          vim.api.nvim_echo(
            { { "[coil] The parent pane is display-only", "WarningMsg" } },
            false,
            {}
          )
        end
      end)
    end,
  })
end

return M

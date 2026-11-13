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
    bridge.toggle_hidden(view.panes.current)
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

-- Actions also wrapped in visual mode, where oil opens every selected entry. Without the wrap,
-- oil would open the selection in splits of the middle pane. (L and H stay Vim motions there.)
local VISUAL_ACTIONS = { open = true, open_vsplit = true, open_split = true, open_tab = true }

---Wrap coil's keys in an oil buffer. Safe to call repeatedly: keys that are already wrapped are
---skipped, and keys oil re-mapped (e.g. after reloading the buffer) are wrapped again.
---@param bufnr integer
M.wrap_buffer = function(bufnr)
  for action, lhs in pairs(config.get().keymaps) do
    if lhs and M.actions[action] then
      for _, mode in ipairs(VISUAL_ACTIONS[action] and { "n", "x" } or { "n" }) do
        local original = vim.api.nvim_buf_call(bufnr, function()
          return vim.fn.maparg(lhs, mode, false, true)
        end)
        if not vim.startswith(original.desc or "", DESC_PREFIX) then
          vim.keymap.set(mode, lhs, function()
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

local LEFT_MOUSE = vim.keycode("<LeftMouse>")
local click_ns = vim.api.nvim_create_namespace("coil_click")

---The listing entry at a mouse position, if it is in the parent pane or a directory preview
---@param view coil.View
---@param mouse {winid: integer, winrow: integer, line: integer} As from getmousepos()
---@return nil|string dir_url The listed directory
---@return nil|string name The clicked entry
M.clicked_entry = function(view, mouse)
  local winid = mouse.winid
  if winid ~= view.panes.parent and winid ~= view.panes.preview then
    return nil
  end
  if not vim.api.nvim_win_is_valid(winid) or mouse.line < 1 then
    return nil
  end
  local bufnr = vim.api.nvim_win_get_buf(winid)
  -- Only listings record the directory they list; text previews and messages don't
  local dir_url = vim.b[bufnr].coil_dir_url
  if not dir_url then
    return nil
  end
  -- Only accept a click on a row that shows `line` (not the empty rows below the text)
  local top = vim.api.nvim_win_call(winid, function()
    return vim.fn.line("w0")
  end)
  local winbar = vim.api.nvim_get_option_value("winbar", { win = winid }) ~= "" and 1 or 0
  if mouse.line ~= top + mouse.winrow - 1 - winbar then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, mouse.line - 1, mouse.line, false)[1]
  if not line or line == "" then
    return nil
  end
  -- Directories are listed as "name/"
  return dir_url, (line:gsub("/$", ""))
end

---Move the middle pane to the clicked entry's directory, with the cursor on the entry
---@param view coil.View
---@param mouse {winid: integer, winrow: integer, line: integer} As from getmousepos()
---@return boolean jumped
M.jump_to_click = function(view, mouse)
  local dir_url, name = M.clicked_entry(view, mouse)
  if not dir_url then
    return false
  end
  vim.api.nvim_set_current_win(view.panes.current)
  bridge.open_dir(dir_url, name)
  return true
end

---@param view coil.View
---@return fun() detach
M.attach = function(view)
  -- Mouse mappings are looked up in the buffer focused *before* the click, so a mapping in the
  -- parent pane's buffer would never run. Watch for clicks instead and act on where they landed.
  vim.on_key(function(key)
    if key == LEFT_MOUSE then
      vim.schedule(function()
        if state.get() == view then
          M.jump_to_click(view, vim.fn.getmousepos())
        end
      end)
    end
  end, click_ns)

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
  vim.api.nvim_create_autocmd("User", {
    group = view.group,
    pattern = "OilEnter",
    desc = "Re-wrap coil keys after oil reloads the middle buffer",
    callback = function(args)
      -- A reload (<C-l>, :edit, :Coil on the same directory) re-runs oil's buffer setup, which sets
      -- oil's keymaps again over coil's wrappers. OilEnter fires after that, every time.
      local bufnr = args.data and args.data.buf
      if
        bufnr
        and vim.api.nvim_win_is_valid(view.panes.current)
        and vim.api.nvim_win_get_buf(view.panes.current) == bufnr
      then
        M.wrap_buffer(bufnr)
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

  return function()
    vim.on_key(nil, click_ns)
  end
end

return M

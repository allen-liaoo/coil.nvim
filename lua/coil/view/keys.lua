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
    elseif how == nil and open.externally(bufnr) then
      -- Opened in another program. (Split and tab keys always open in the editor.)
      return
    else
      open.in_editing_tab(view, bufnr, how)
    end
  end)
end

---@param view coil.View
local function close()
  require("coil.view").close()
end

---coil's own keys (the `keymaps` option)
---@type table<string, fun(view: coil.View)>
M.actions = {
  go_in = function(view)
    select_entry(view, nil)
  end,
  go_out = function()
    bridge.open_parent()
  end,
  close = close,
  quit = function()
    vim.cmd("confirm qall")
  end,
}

---What an oil action does instead in the middle pane, if coil changes it
---@param keymap coil.OilKeymap
---@return nil|string name For the mapping's description
---@return nil|fun(view: coil.View) run
---@return boolean? visual Also in visual mode, where oil opens every selected entry
local function override(keymap)
  local action, opts = keymap.action, keymap.opts
  local how
  if action == "select" then
    how = (opts.vertical and "vsplit") or (opts.horizontal and "split") or (opts.tab and "tab")
  elseif action == "select_vsplit" or action == "select_split" or action == "select_tab" then
    how = action:sub(#"select_" + 1)
  elseif action == "preview" then
    return "jump into the preview pane",
      function(view)
        vim.api.nvim_set_current_win(view.panes.preview)
      end
  elseif action == "toggle_hidden" then
    return "toggle hidden files in every pane",
      function(view)
        bridge.toggle_hidden(view.panes.current)
        sync.all(view)
      end
  elseif action == "close" then
    return "close the column view", close
  else
    return nil
  end
  -- Without the wrap, oil would open files (and the selection) in splits of the middle pane
  return how and ("open in a " .. how .. " in the editing tab") or "open",
    function(view)
      select_entry(view, how)
    end,
    true
end

---Whether a keymap's configured mode includes `mode` ("n" or "x")
---@param configured string|string[]|nil
---@param mode string
---@return boolean
local function covers(configured, mode)
  if configured == nil or configured == "" then
    return true
  elseif type(configured) == "table" then
    for _, m in ipairs(configured) do
      if covers(m, mode) then
        return true
      end
    end
    return false
  end
  return configured == mode or (mode == "x" and configured == "v")
end

---@class (exact) coil.KeyBinding
---@field lhs string
---@field modes string[]
---@field name string
---@field run fun(view: coil.View)

---Every key coil handles in the middle pane: its own, then oil's that it changes. A key in both
---gets coil's own action.
---@return coil.KeyBinding[]
local function bindings()
  local list = {}
  for action, lhs in pairs(config.get().keymaps) do
    if lhs and M.actions[action] then
      table.insert(list, { lhs = lhs, modes = { "n" }, name = action, run = M.actions[action] })
    end
  end
  for _, keymap in ipairs(bridge.oil_keymaps()) do
    local name, run, visual = override(keymap)
    if run then
      local modes = {}
      if covers(keymap.mode, "n") then
        table.insert(modes, "n")
      end
      if visual and covers(keymap.mode, "x") then
        table.insert(modes, "x")
      end
      table.insert(list, { lhs = keymap.lhs, modes = modes, name = name, run = run })
    end
  end
  return list
end

---The keys oil's config maps to `action`
---@param action string
---@return string[]
local function oil_keys(action)
  local keys = {}
  for _, keymap in ipairs(bridge.oil_keymaps()) do
    if keymap.action == action then
      table.insert(keys, keymap.lhs)
    end
  end
  return keys
end

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
  for _, binding in ipairs(bindings()) do
    for _, mode in ipairs(binding.modes) do
      local original = vim.api.nvim_buf_call(bufnr, function()
        return vim.fn.maparg(binding.lhs, mode, false, true)
      end)
      if not vim.startswith(original.desc or "", DESC_PREFIX) then
        vim.keymap.set(mode, binding.lhs, function()
          local view = state.get()
          if view and vim.api.nvim_get_current_win() == view.panes.current then
            binding.run(view)
          else
            fallback(binding.lhs, original)
          end
        end, {
          buffer = bufnr,
          nowait = true,
          desc = DESC_PREFIX .. binding.name .. " (column view only)",
        })
      end
    end
  end
end

---Keys in the preview pane's buffers, which coil creates, so no wrapping is needed: oil's preview
---keys go back to the middle pane, and the close keys (coil's and oil's) close the view
---@param view coil.View
---@param bufnr integer
local function map_preview_buffer(view, bufnr)
  for _, lhs in ipairs(oil_keys("preview")) do
    vim.keymap.set("n", lhs, function()
      vim.api.nvim_set_current_win(view.panes.current)
    end, { buffer = bufnr, nowait = true, desc = DESC_PREFIX .. "back to the middle pane" })
  end
  local close_keys = oil_keys("close")
  local keymaps = config.get().keymaps
  if keymaps.close then
    table.insert(close_keys, keymaps.close)
  end
  for _, lhs in ipairs(close_keys) do
    vim.keymap.set("n", lhs, close, {
      buffer = bufnr,
      nowait = true,
      desc = DESC_PREFIX .. "close",
    })
  end
  if keymaps.quit then
    vim.keymap.set("n", keymaps.quit, M.actions.quit, {
      buffer = bufnr,
      nowait = true,
      desc = DESC_PREFIX .. "quit",
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
        if state.is_open(view) then
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

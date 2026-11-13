-- Opening things outside the column view: files go to the editing window (where :Coil was run), or
-- elsewhere when the options say so (`open_external`, `edit_here`).
local bridge = require("coil.oil_bridge")
local config = require("coil.config")
local state = require("coil.view.state")
local M = {}

---@alias coil.OpenHow nil|"vsplit"|"split"|"tab"

---The window to open files in: the origin window if it still exists outside every column view,
---otherwise the current window of a tab that isn't a column view
---@param view coil.View
---@return nil|integer
local function editing_window(view)
  local origin = view.origin.win
  if vim.api.nvim_win_is_valid(origin) and not state.get(vim.api.nvim_win_get_tabpage(origin)) then
    return origin
  end
  for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
    if not state.get(tab) then
      return vim.api.nvim_tabpage_get_win(tab)
    end
  end
end

-- The kinds of file `open_external` hands to another program
local EXTERNAL_KINDS = {
  image = true,
  video = true,
  audio = true,
  pdf = true,
  archive = true,
  binary = true,
}

-- The kinds of file the system's text editor opens with `edit_here = false`
local TEXT_KINDS = { text = true, too_large = true }

---@param path string
---@return boolean opened
local function open_external(path)
  local _, err = vim.ui.open(path)
  if err then
    vim.notify(string.format("[coil] Can't open %s: %s", path, err), vim.log.levels.ERROR)
  end
  return true
end

---@param path string
---@return boolean opened False when there's no system text editor, or it failed to start
local function open_in_editor(path)
  local editor = require("coil.editor").find()
  if not editor then
    return false
  end
  if require("coil.editor").open(editor, path) then
    return true
  end
  vim.notify(
    string.format("[coil] Couldn't start %s; opening %s here", editor.name, path),
    vim.log.levels.WARN
  )
  return false
end

---Open a file outside this Neovim if the options say so: with `open_external`, files that aren't
---text in the system's default program; with `edit_here = false`, text files in the system's
---text editor
---@param bufnr integer The file's buffer from oil's select (not loaded unless already open)
---@return boolean opened Whether it was opened elsewhere
M.elsewhere = function(bufnr)
  local options = config.get()
  if not options.open_external and options.edit_here then
    return false
  end
  local name = vim.api.nvim_buf_get_name(bufnr)
  -- oil gives local files as plain paths; remote ones keep their oil URL and stay here
  local path = name:match("^[%w-]+://") and bridge.local_path(name) or name
  if not path then
    return false
  end
  local kind = require("coil.preview").kind({
    name = vim.fs.basename(path),
    url = name,
    path = path,
    is_dir = false,
  })
  local opened = false
  if options.open_external and EXTERNAL_KINDS[kind] then
    opened = open_external(path)
  elseif not options.edit_here and TEXT_KINDS[kind] then
    opened = open_in_editor(path)
  end
  -- oil added a buffer for the file; drop it unless the file was already open
  if opened and vim.fn.bufloaded(bufnr) == 0 then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  return opened
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

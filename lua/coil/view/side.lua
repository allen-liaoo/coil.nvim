-- Oil buffers in the side panes: the parent pane, and the preview pane when it previews a directory.
-- They are oil's own buffers, so oil's hidden-file rules, highlights and redraws apply to them. They
-- show only each entry's icon and name, though oil's columns are global and one buffer serves a
-- directory everywhere: the other columns are hidden in the pane's window only, by a conceal match.
-- The panes can't be entered while they show one (see keys.lua), so they are never edited.
local bridge = require("coil.oil_bridge")
local M = {}

M.set_highlights = function()
  vim.api.nvim_set_hl(0, "CoilParentSelected", { link = "Visual", default = true })
end

---@class (exact) coil.SideShown
---@field bufnr integer The oil buffer the window shows
---@field selected? string The entry to keep the cursor (and cursorline) on

---What each side window shows, by window
---@type table<integer, coil.SideShown>
local shown = {}
---The conceal match coil added to each side window
---@type table<integer, integer>
local matches = {}
---Oil buffers whose redraws are watched
---@type table<integer, boolean>
local watched = {}

---@param winid integer
local function clear_match(winid)
  if matches[winid] then
    pcall(vim.fn.matchdelete, matches[winid], winid)
    matches[winid] = nil
  end
end

---Hide everything but icons and names, and put the cursor on the selected entry
---@param winid integer
local function redraw(winid)
  local s = shown[winid]
  if
    not s
    or not vim.api.nvim_win_is_valid(winid)
    or vim.api.nvim_win_get_buf(winid) ~= s.bufnr
    or not vim.b[s.bufnr].oil_ready
  then
    return
  end
  clear_match(winid)
  local positions = bridge.column_positions(s.bufnr)
  if #positions > 0 then
    matches[winid] = vim.fn.matchaddpos("Conceal", positions, 10, -1, {
      window = winid,
      conceal = "",
    })
  end
  -- oil sets these for its windows; set them again in case a user's oil win_options don't
  vim.wo[winid].conceallevel = 3
  vim.wo[winid].concealcursor = "nvic"

  local lnum = s.selected and bridge.line_of(s.bufnr, s.selected)
  vim.wo[winid].cursorline = lnum ~= nil
  vim.api.nvim_win_set_cursor(winid, { lnum or 1, 0 })
  if lnum then
    vim.api.nvim_win_call(winid, function()
      vim.cmd("normal! zz")
    end)
  end
end

---Redraw every side window showing `bufnr`
---@param bufnr integer
local function redraw_buffer(bufnr)
  for winid, s in pairs(shown) do
    if s.bufnr == bufnr then
      redraw(winid)
    end
  end
end

---Buffers whose lines oil changed, waiting for redraw_changed
---@type table<integer, boolean>
local changed = {}

---After oil redraws a side pane's buffer: redraw its side windows, and fire the TextChanged
---Neovim fires only for the current buffer, which a side pane's never is. Extensions redecorate
---oil buffers on it (oil-git-status puts back the signs the new lines lost), as they would in an
---ordinary window.
---@param bufnr integer
local function redraw_changed(bufnr)
  changed[bufnr] = nil
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  redraw_buffer(bufnr)
  if bufnr ~= vim.api.nvim_get_current_buf() then
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr, modeline = false })
  end
end

---Redraw the side windows showing `bufnr` whenever oil redraws it (hidden files, sort, files
---changed). Stops watching once no side window shows it.
---@param bufnr integer
local function watch(bufnr)
  if watched[bufnr] then
    return
  end
  watched[bufnr] = true
  vim.api.nvim_buf_attach(bufnr, false, {
    -- Runs inside oil's own nvim_buf_set_lines, so do nothing here that could fail: an error
    -- would abort oil's render. Redraw once oil is done.
    on_lines = function()
      for _, s in pairs(shown) do
        if s.bufnr == bufnr then
          -- One redraw for however many line changes a render makes
          if not changed[bufnr] then
            changed[bufnr] = true
            vim.schedule(function()
              redraw_changed(bufnr)
            end)
          end
          return
        end
      end
      -- No side window shows it any more
      watched[bufnr] = nil
      return true
    end,
    on_detach = function()
      watched[bufnr] = nil
    end,
  })
end

---Show directory `url` in side window `winid` as an oil buffer with only icons and names
---@param winid integer
---@param url string A directory URL, with its trailing slash
---@param selected? string Keep the cursor, highlighted, on this entry (the parent pane)
---@return boolean ok
M.show_dir = function(winid, url, selected)
  M.set_highlights()
  local existing = vim.fn.bufnr(url)
  local was_ready = existing ~= -1 and vim.b[existing].oil_ready == true
  local bufnr = bridge.show_dir_in(winid, url)
  if not bufnr then
    M.release(winid)
    return false
  end
  if not (shown[winid] and shown[winid].bufnr == bufnr) then
    clear_match(winid)
  end
  shown[winid] = { bufnr = bufnr, selected = selected }
  watch(bufnr)
  if was_ready then
    -- Listed earlier: list it again, as the old name lists did every time (the redraw follows)
    bridge.refresh_dir(bufnr)
  end
  bridge.on_ready(bufnr, function()
    redraw(winid)
  end)
  return true
end

---Whether `winid` shows one of these oil buffers
---@param winid integer
---@return boolean
M.shows_dir = function(winid)
  local s = shown[winid]
  return s ~= nil
    and vim.api.nvim_win_is_valid(winid)
    and vim.api.nvim_win_get_buf(winid) == s.bufnr
end

---Forget `winid`'s oil buffer before something else goes in: its conceal match and cursorline
---would apply to whatever the window shows next, and so would oil's window options (such as a
---sign column for git status signs, which a text preview doesn't need)
---@param winid integer
M.release = function(winid)
  clear_match(winid)
  shown[winid] = nil
  if vim.api.nvim_win_is_valid(winid) then
    vim.wo[winid].cursorline = false
    vim.wo[winid].conceallevel = 0
    vim.wo[winid].signcolumn = "no"
  end
end

return M

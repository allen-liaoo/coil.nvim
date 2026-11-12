-- Scratch buffers for previews, and swapping them into windows.
local M = {}

local ns = vim.api.nvim_create_namespace("coil_preview")

M.ns = ns

---Create a read-only scratch buffer that is wiped as soon as it is hidden
---@param lines string[]
---@return integer bufnr
M.scratch = function(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].modified = false
  vim.b[bufnr].coil_preview = true
  return bufnr
end

---A scratch buffer showing a short dimmed message
---@param lines string[]
---@return integer bufnr
M.message = function(lines)
  local bufnr = M.scratch(lines)
  for i = 0, #lines - 1 do
    vim.api.nvim_buf_set_extmark(bufnr, ns, i, 0, { line_hl_group = "Comment" })
  end
  return bufnr
end

---Show a buffer in a window, even if the window has 'winfixbuf' set. Never moves focus.
---@param winid integer
---@param bufnr integer
---@return boolean ok
M.set_win_buf = function(winid, bufnr)
  if not vim.api.nvim_win_is_valid(winid) or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  -- Swapping a window's buffer runs BufEnter inside that window. When the window's tab is in the
  -- background, a BufEnter handler (oil's global one does this) can leave that tab remembering
  -- the swapped window as its focused one, so the user returns to the tab in the wrong window.
  local tab = vim.api.nvim_win_get_tabpage(winid)
  local tab_win = vim.api.nvim_tabpage_get_win(tab)

  local opt = { scope = "local", win = winid }
  local fixed = vim.api.nvim_get_option_value("winfixbuf", opt)
  if fixed then
    vim.api.nvim_set_option_value("winfixbuf", false, opt)
  end
  local ok = pcall(vim.api.nvim_win_set_buf, winid, bufnr)
  if fixed then
    vim.api.nvim_set_option_value("winfixbuf", true, opt)
  end

  if
    vim.api.nvim_tabpage_is_valid(tab)
    and vim.api.nvim_win_is_valid(tab_win)
    and vim.api.nvim_tabpage_get_win(tab) ~= tab_win
  then
    vim.api.nvim_tabpage_set_win(tab, tab_win)
  end
  return ok
end

---Delete a preview buffer that never made it into a window
---@param bufnr integer
M.discard = function(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) and vim.fn.bufwinid(bufnr) == -1 then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

return M

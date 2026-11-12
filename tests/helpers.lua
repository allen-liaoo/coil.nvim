local M = {}

---@return string
M.tmpdir = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  -- Resolve symlinks (e.g. /tmp on macOS) so paths match what oil reports
  return assert((vim.uv or vim.loop).fs_realpath(dir))
end

---@param path string
---@param lines string[]
M.write = function(path, lines)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  vim.fn.writefile(lines, path)
end

---@param path string
---@param data string
M.write_bytes = function(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

---@param cond fun(): boolean
---@param ms? integer
---@return boolean
M.wait = function(cond, ms)
  return vim.wait(ms or 3000, cond, 10)
end

M.setup_oil = function()
  require("oil").setup({ default_file_explorer = false })
end

---Open oil on `dir` in the current window and wait for the listing
---@param dir string
---@return integer bufnr
M.open_oil = function(dir)
  require("oil").open(dir)
  local bufnr = vim.api.nvim_get_current_buf()
  assert(M.wait(function()
    return vim.b[bufnr].oil_ready == true
  end))
  return bufnr
end

---Put the cursor of `winid` on the line whose text contains `text`
---@param winid integer
---@param text string
M.cursor_to = function(winid, text)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:find(text, 1, true) then
      vim.api.nvim_win_set_cursor(winid, { i, 0 })
      return
    end
  end
  error(string.format("No line containing %q", text))
end

---@param winid integer
---@return string[]
M.win_lines = function(winid)
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(winid), 0, -1, false)
end

---Start each test in a fresh tab with a single window
M.reset_tab = function()
  vim.cmd.tabnew()
  vim.cmd("silent! tabonly!")
end

return M

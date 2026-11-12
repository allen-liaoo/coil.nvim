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

---Wait until a window shows exactly `expected`, then assert it
---@param winid integer
---@param expected string[]
M.wait_lines = function(winid, expected)
  M.wait(function()
    return vim.deep_equal(expected, M.win_lines(winid))
  end)
  assert.same(expected, M.win_lines(winid))
end

---Run :Coil on `dir` and wait for the middle pane's listing
---@param dir string
---@return coil.View
M.open_view = function(dir)
  vim.cmd("Coil " .. dir)
  local view = assert(require("coil.view.state").get())
  local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
  assert(M.wait(function()
    return vim.b[bufnr].oil_ready == true
  end))
  return view
end

---Line numbers (1-based) carrying the parent pane's selection highlight
---@param winid integer
---@return integer[]
M.selected_lines = function(winid)
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local ns = vim.api.nvim_create_namespace("coil_listing")
  local ret = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    if mark[4].line_hl_group == "CoilParentSelected" then
      table.insert(ret, mark[2] + 1)
    end
  end
  return ret
end

---Type keys as the user would, running mappings
---@param keys string
M.press = function(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

---Start each test in a fresh tab with a single window
M.reset_tab = function()
  vim.cmd.tabnew()
  vim.cmd("silent! tabonly!")
end

return M

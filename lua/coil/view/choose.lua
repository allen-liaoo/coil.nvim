-- Choosing files for another program (`coil --chooser-file <path>`, g:coil_chooser_file), like
-- yazi's --chooser-file: opening a file in the middle pane writes its path to the file, one per
-- line, and quits. A visual selection chooses every selected entry, directories included.
local bridge = require("coil.oil_bridge")
local M = {}

---The file chosen paths are written to, when coil is choosing
---@return nil|string
M.file = function()
  local file = vim.g.coil_chooser_file
  return type(file) == "string" and file ~= "" and file or nil
end

---Quit once the paths are written. A field, so tests can replace it.
M.quit = function()
  vim.cmd("confirm qall")
end

---@param paths string[]
local function finish(paths)
  local file = assert(M.file())
  local ok, err = pcall(vim.fn.writefile, paths, file)
  if not ok then
    return vim.notify("[coil] Can't write the chosen paths: " .. err, vim.log.levels.ERROR)
  end
  M.quit()
end

local function remote()
  vim.notify("[coil] Only local files can be chosen", vim.log.levels.WARN)
end

---Choose the file oil's select gave
---@param bufnr integer The file's buffer (not loaded unless already open)
M.buffer = function(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  -- oil gives local files as plain paths; remote ones keep their oil URL
  local path = name:match("^[%w-]+://") and bridge.local_path(name) or name
  if vim.fn.bufloaded(bufnr) == 0 then
    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end
  if not path then
    return remote()
  end
  finish({ path })
end

---Whether a key runs in visual mode
---@return boolean
M.visual = function()
  return vim.tbl_contains({ "v", "V", "\22" }, vim.fn.mode())
end

---Choose the entries of the visual selection in the current (middle) pane
M.selection = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local first, last = vim.fn.line("v"), vim.fn.line(".")
  if first > last then
    first, last = last, first
  end
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  local dir = bridge.local_path(vim.api.nvim_buf_get_name(bufnr))
  if not dir then
    return remote()
  end
  local paths = {}
  for lnum = first, last do
    local name = bridge.name_on_line(bufnr, lnum)
    if name then
      table.insert(paths, vim.fs.joinpath(dir, name))
    end
  end
  if #paths > 0 then
    finish(paths)
  end
end

return M

-- Text files: the first lines in a scratch buffer, highlighted without running FileType autocmds
-- (so no ftplugins or LSP clients attach to a preview).
local buffer = require("coil.preview.buffer")
local M = {}

---@param bufnr integer
---@param path string
---@param lines string[]
local function highlight(bufnr, path, lines)
  local ft = vim.filetype.match({ filename = path, contents = lines })
  if not ft or ft == "" then
    return
  end
  local lang = vim.treesitter.language.get_lang(ft)
  if not lang or not pcall(vim.treesitter.start, bufnr, lang) then
    vim.bo[bufnr].syntax = ft
  end
end

---@param path string
---@param opts coil.PreviewOpts
---@return integer bufnr
M.render = function(path, opts)
  local ok, lines = pcall(vim.fn.readfile, path, "", opts.max_lines)
  if not ok then
    return buffer.message({ "Cannot read file: " .. tostring(lines) })
  end
  local bufnr = buffer.scratch(lines)
  highlight(bufnr, path, lines)
  return bufnr
end

return M

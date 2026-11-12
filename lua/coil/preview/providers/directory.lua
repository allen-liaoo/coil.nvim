-- Directory listings as plain names (not oil buffers).
local buffer = require("coil.preview.buffer")
local M = {}

---@class (exact) coil.ListEntry
---@field name string
---@field type string Entry type as reported by the lister ("file", "directory", "link", ...)
---@field is_dir boolean True for directories and links to directories

M.set_highlights = function()
  vim.api.nvim_set_hl(0, "CoilDir", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "CoilLink", { link = "Constant", default = true })
end

---@param entry coil.ListEntry
---@return string
M.display_name = function(entry)
  return entry.is_dir and (entry.name .. "/") or entry.name
end

---Fill a buffer's lines with entry names and highlight them
---@param bufnr integer
---@param entries coil.ListEntry[]
M.fill = function(bufnr, entries)
  M.set_highlights()
  local lines = {}
  for _, entry in ipairs(entries) do
    table.insert(lines, M.display_name(entry))
  end
  local modifiable = vim.bo[bufnr].modifiable
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = modifiable
  vim.api.nvim_buf_clear_namespace(bufnr, buffer.ns, 0, -1)
  for i, entry in ipairs(entries) do
    local hl = entry.is_dir and "CoilDir" or (entry.type == "link" and "CoilLink") or nil
    if hl then
      vim.api.nvim_buf_set_extmark(bufnr, buffer.ns, i - 1, 0, {
        end_col = #lines[i],
        hl_group = hl,
      })
    end
  end
end

---@param entries coil.ListEntry[]
---@return integer bufnr
M.render = function(entries)
  if vim.tbl_isempty(entries) then
    return buffer.message({ "(empty directory)" })
  end
  local bufnr = buffer.scratch({})
  M.fill(bufnr, entries)
  return bufnr
end

return M

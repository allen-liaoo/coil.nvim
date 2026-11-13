-- The parent pane: a plain read-only list of names with the current directory highlighted.
local buffer = require("coil.preview.buffer")
local directory = require("coil.preview.providers.directory")
local M = {}

local ns = vim.api.nvim_create_namespace("coil_listing")

M.set_highlights = function()
  vim.api.nvim_set_hl(0, "CoilParentSelected", { link = "Visual", default = true })
end

---Show `entries` in `winid`, highlighting and scrolling to the entry called `selected`
---@param winid integer
---@param entries coil.ListEntry[]
---@param selected? string
---@param dir_url? string The listed directory, recorded as b:coil_dir_url so clicks can find it
M.show = function(winid, entries, selected, dir_url)
  if vim.tbl_isempty(entries) then
    buffer.set_win_buf(winid, buffer.message({ "(empty directory)" }))
    return
  end
  M.set_highlights()
  local bufnr = buffer.scratch({})
  directory.fill(bufnr, entries)
  vim.b[bufnr].coil_dir_url = dir_url

  local lnum
  for i, entry in ipairs(entries) do
    if entry.name == selected then
      lnum = i
      break
    end
  end
  if lnum then
    vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
      line_hl_group = "CoilParentSelected",
      priority = 50,
    })
  end

  if not buffer.set_win_buf(winid, bufnr) then
    return buffer.discard(bufnr)
  end
  if lnum then
    vim.api.nvim_win_set_cursor(winid, { lnum, 0 })
    vim.api.nvim_win_call(winid, function()
      vim.cmd("normal! zz")
    end)
  end
end

return M

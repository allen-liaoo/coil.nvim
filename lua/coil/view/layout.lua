-- Creates and sizes the three pane windows. Everything else in coil only deals with the window
-- IDs this returns, so a floating-window layout could replace this module later.
local buffer = require("coil.preview.buffer")
local util = require("coil.util")
local M = {}

-- Options shared by the two read-only side panes
local side_options = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  wrap = false,
  -- Stop :edit and friends from replacing the pane's buffer; coil swaps buffers itself
  winfixbuf = true,
}

---@type table<coil.PaneRole, table<string, any>>
local pane_options = {
  parent = vim.tbl_extend("force", side_options, { winfixwidth = true }),
  -- oil applies its own window options to the middle pane
  current = { winfixwidth = true },
  -- The preview pane absorbs width changes, so it has no winfixwidth
  preview = side_options,
}

---Split `total` columns between the three panes by `ratio`, leaving room for the two separators
---@param total integer Columns available to the panes, including separators
---@param ratio integer[]
---@return integer[] widths Parent, current and preview widths
M.compute_widths = function(total, ratio)
  local available = math.max(total - 2, 3)
  local sum = ratio[1] + ratio[2] + ratio[3]
  local parent = math.max(math.floor(available * ratio[1] / sum), 1)
  local current = math.max(math.floor(available * ratio[2] / sum), 1)
  return { parent, current, math.max(available - parent - current, 1) }
end

---Create the parent and preview panes on either side of `current`
---@param current integer The window that becomes the middle pane
---@return coil.Panes
M.open = function(current)
  local parent = vim.api.nvim_open_win(buffer.message({}), false, { split = "left", win = current })
  local preview =
    vim.api.nvim_open_win(buffer.message({}), false, { split = "right", win = current })
  ---@type coil.Panes
  local panes = { parent = parent, current = current, preview = preview }
  for role, winid in pairs(panes) do
    util.set_win_options(winid, pane_options[role])
    vim.w[winid].coil_pane = role
  end
  return panes
end

---Re-apply the width ratio. Uses the panes' combined width, so windows the user opened beside
---them keep their size.
---@param panes coil.Panes
---@param ratio integer[]
M.reflow = function(panes, ratio)
  local total = 2
  for _, winid in pairs(panes) do
    if not vim.api.nvim_win_is_valid(winid) then
      return
    end
    total = total + vim.api.nvim_win_get_width(winid)
  end
  local widths = M.compute_widths(total, ratio)
  vim.api.nvim_win_set_width(panes.parent, widths[1])
  vim.api.nvim_win_set_width(panes.current, widths[2])
end

return M

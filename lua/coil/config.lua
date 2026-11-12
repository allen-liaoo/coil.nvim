local M = {}

---@class (exact) coil.Config
---@field ratio integer[] Relative widths of the parent, current and preview panes
---@field debounce_ms integer Wait this long after the cursor stops before updating the preview
---@field preview table Options for the preview module (see coil.PreviewOpts)
---@field keymaps table<string, string|false> Keys for coil actions in the middle pane (false disables)

---@type coil.Config
local defaults = {
  ratio = { 1, 4, 3 },
  debounce_ms = 30,
  preview = {},
  -- Active in the column view's middle pane only. Anywhere else these keys keep their usual
  -- meaning: oil's mapping if it has one, otherwise Vim's built-in key.
  keymaps = {
    go_in = "L", -- Enter a directory; files open in the editing tab
    go_out = "H", -- Go to the parent directory
    open = "<CR>", -- Same as go_in
    open_vsplit = "<C-s>", -- Open in a vertical split in the editing tab
    open_split = "<C-h>", -- Open in a horizontal split in the editing tab
    open_tab = "<C-t>", -- Open in a new tab
    focus_preview = "<C-p>", -- Jump into the preview pane (press again there to come back)
    toggle_hidden = "g.", -- Toggle hidden files, refreshing every pane
    close = "q", -- Close the column view
  },
}

---@type coil.Config
local config = vim.deepcopy(defaults)

---@param opts? table
M.setup = function(opts)
  local new = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  local ratio = new.ratio
  local valid = type(ratio) == "table" and #ratio == 3
  for _, r in ipairs(valid and ratio or {}) do
    valid = valid and type(r) == "number" and r > 0
  end
  if not valid then
    error("[coil] ratio must be a list of three positive numbers, got " .. vim.inspect(ratio))
  end
  config = new
end

---@return coil.Config
M.get = function()
  return config
end

return M

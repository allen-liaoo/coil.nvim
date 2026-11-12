local M = {}

---@class (exact) coil.Config
---@field ratio integer[] Relative widths of the parent, current and preview panes
---@field preview table Options for the preview module (see coil.PreviewOpts)

---@type coil.Config
local defaults = {
  ratio = { 1, 4, 3 },
  preview = {},
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

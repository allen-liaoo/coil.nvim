local M = {}

---@class (exact) coil.Config
---@field ratio integer[] Relative widths of the parent, current and preview panes
---@field debounce_ms integer Wait this long after the cursor stops before updating the preview
---@field winbar boolean Show each pane's path in a title line (winbar)
---@field tab_title boolean Name the column view's tab after the current directory (t:tabname)
---@field preview table Options for the preview module (see coil.PreviewOpts)
---@field keymaps table<string, string|false> Keys for coil actions in the middle pane (false disables)

---@type coil.Config
local defaults = {
  ratio = { 1, 4, 3 },
  debounce_ms = 30,
  winbar = false,
  -- Sets the tab variable `tabname`, which tab lines such as lualine's `tabs` component show
  tab_title = true,
  preview = {},
  -- coil's own keys, in the column view's middle pane only. Anywhere else these keys keep their
  -- usual meaning: oil's mapping if it has one, otherwise Vim's built-in key. oil's keys
  -- (select and its split and tab variants, preview, toggle hidden, close) are configured in oil;
  -- coil changes what they do in the middle pane.
  keymaps = {
    go_in = "L", -- Enter a directory; files open in the editing tab
    go_out = "H", -- Go to the parent directory
    close = "q", -- Close the column view (also in the preview pane)
  },
}

---@type coil.Config
local config = vim.deepcopy(defaults)

---@param msg string
local function fail(msg, ...)
  error("[coil] " .. string.format(msg, ...), 0)
end

---Type errors are fatal; unknown keys (likely typos) only warn
---@param new coil.Config
---@param opts table What the user passed
local function validate(new, opts)
  local ratio = new.ratio
  local valid = type(ratio) == "table" and #ratio == 3
  for _, r in ipairs(valid and ratio or {}) do
    valid = valid and type(r) == "number" and r > 0
  end
  if not valid then
    fail("ratio must be a list of three positive numbers, got %s", vim.inspect(ratio))
  end
  if type(new.debounce_ms) ~= "number" or new.debounce_ms < 0 then
    fail("debounce_ms must be a non-negative number, got %s", vim.inspect(new.debounce_ms))
  end
  if type(new.winbar) ~= "boolean" then
    fail("winbar must be true or false, got %s", vim.inspect(new.winbar))
  end
  if type(new.tab_title) ~= "boolean" then
    fail("tab_title must be true or false, got %s", vim.inspect(new.tab_title))
  end
  if type(new.preview) ~= "table" then
    fail("preview must be a table, got %s", vim.inspect(new.preview))
  end
  if type(new.keymaps) ~= "table" then
    fail("keymaps must be a table, got %s", vim.inspect(new.keymaps))
  end
  for action, lhs in pairs(new.keymaps) do
    if lhs ~= false and (type(lhs) ~= "string" or lhs == "") then
      fail("keymaps.%s must be a key (string) or false, got %s", action, vim.inspect(lhs))
    end
  end

  local unknown = {}
  for key in pairs(opts) do
    if defaults[key] == nil then
      table.insert(unknown, key)
    end
  end
  for action in pairs(type(opts.keymaps) == "table" and opts.keymaps or {}) do
    if defaults.keymaps[action] == nil then
      table.insert(unknown, "keymaps." .. action)
    end
  end
  if not vim.tbl_isempty(unknown) then
    table.sort(unknown)
    vim.notify(
      "[coil] Unknown setup option(s), ignored: " .. table.concat(unknown, ", "),
      vim.log.levels.WARN
    )
  end
end

---@param opts? table
M.setup = function(opts)
  opts = opts or {}
  local new = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts)
  validate(new, opts)
  config = new
end

---@return coil.Config
M.get = function()
  return config
end

return M

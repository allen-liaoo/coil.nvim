local M = {}

---@class (exact) coil.Config
---@field ratio integer[] Relative widths of the parent, current and preview panes
---@field debounce_ms integer Wait this long after the cursor stops before updating the preview
---@field winbar boolean Show each pane's path in a title line (winbar)
---@field tab_title boolean Name the column view's tab after the current directory (t:tabname)
---@field preview table Options for the preview module (see coil.PreviewOpts)
---@field keymaps table<string, string|false> Keys for coil actions in the middle pane (false disables)
---@field standalone table Options that replace the others when Neovim runs as a file manager

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
    quit = false, -- Quit Neovim, asking about unsaved changes (also in the preview pane)
  },
  -- Merged over the options above when Neovim was started as a file manager (g:coil_standalone,
  -- set with `nvim --cmd "let g:coil_standalone = 1"`). Takes any option except itself.
  standalone = {
    keymaps = { close = false, quit = "q" },
  },
}

---Whether Neovim was started as a file manager
---@return boolean
M.standalone = function()
  local value = vim.g.coil_standalone
  return value ~= nil and value ~= false and value ~= 0
end

---The options in effect: in standalone mode, with the `standalone` options merged over the rest
---@param new coil.Config
---@return coil.Config
local function resolve(new)
  if not M.standalone() then
    return new
  end
  local ret = vim.tbl_deep_extend("force", new, new.standalone)
  ret.standalone = new.standalone
  return ret
end

---@type coil.Config
local config = resolve(vim.deepcopy(defaults))

---@param msg string
local function fail(msg, ...)
  error("[coil] " .. string.format(msg, ...), 0)
end

---Check the options' types. `prefix` names where they came from in error messages.
---@param new table
---@param prefix string
local function check_types(new, prefix)
  local ratio = new.ratio
  local valid = type(ratio) == "table" and #ratio == 3
  for _, r in ipairs(valid and ratio or {}) do
    valid = valid and type(r) == "number" and r > 0
  end
  if not valid then
    fail("%sratio must be a list of three positive numbers, got %s", prefix, vim.inspect(ratio))
  end
  if type(new.debounce_ms) ~= "number" or new.debounce_ms < 0 then
    fail(
      "%sdebounce_ms must be a non-negative number, got %s",
      prefix,
      vim.inspect(new.debounce_ms)
    )
  end
  if type(new.winbar) ~= "boolean" then
    fail("%swinbar must be true or false, got %s", prefix, vim.inspect(new.winbar))
  end
  if type(new.tab_title) ~= "boolean" then
    fail("%stab_title must be true or false, got %s", prefix, vim.inspect(new.tab_title))
  end
  if type(new.preview) ~= "table" then
    fail("%spreview must be a table, got %s", prefix, vim.inspect(new.preview))
  end
  if type(new.keymaps) ~= "table" then
    fail("%skeymaps must be a table, got %s", prefix, vim.inspect(new.keymaps))
  end
  for action, lhs in pairs(new.keymaps) do
    if lhs ~= false and (type(lhs) ~= "string" or lhs == "") then
      fail("%skeymaps.%s must be a key (string) or false, got %s", prefix, action, vim.inspect(lhs))
    end
  end
end

---Option names in `opts` that coil doesn't have
---@param opts table
---@param prefix string
---@param unknown string[] Appended to
local function find_unknown(opts, prefix, unknown)
  for key in pairs(opts) do
    if defaults[key] == nil or (prefix ~= "" and key == "standalone") then
      table.insert(unknown, prefix .. key)
    end
  end
  for action in pairs(type(opts.keymaps) == "table" and opts.keymaps or {}) do
    if defaults.keymaps[action] == nil then
      table.insert(unknown, prefix .. "keymaps." .. action)
    end
  end
end

---Type errors are fatal; unknown keys (likely typos) only warn. The standalone options are
---checked in either mode, so mistakes show up before Neovim is started as a file manager.
---@param new coil.Config
---@param opts table What the user passed
local function validate(new, opts)
  check_types(new, "")
  if type(new.standalone) ~= "table" then
    fail("standalone must be a table, got %s", vim.inspect(new.standalone))
  end
  check_types(vim.tbl_deep_extend("force", new, new.standalone), "standalone.")

  local unknown = {}
  find_unknown(opts, "", unknown)
  if type(opts.standalone) == "table" then
    find_unknown(opts.standalone, "standalone.", unknown)
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
  config = resolve(new)
end

---@return coil.Config
M.get = function()
  return config
end

return M

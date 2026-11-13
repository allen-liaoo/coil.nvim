-- The standalone `coil` command's init (nix/coil.nix): set up oil, coil and image.nvim with the
-- build's defaults and the user's config file. Not used when coil is a plugin in your own Neovim.
local M = {}

---Options for each plugin's setup(), as the build ships them. The config file's returned table is
---merged into these.
---@type table<string, table>
M.defaults = {
  oil = {
    -- Deleting a line and saving moves the file to the trash, which oil's trash view (g\)
    -- can restore from
    delete_to_trash = true,
    -- Permissions, size and modification time next to each name
    columns = { "icon", "permissions", "size", "mtime" },
  },
  -- coil's own standalone defaults apply (q quits)
  coil = {},
  image = {},
  -- mini.icons, for oil's icon column
  icons = {},
}

---The config file: init.lua in the build's config directory (~/.config/coil with the build's
---NVIM_APPNAME)
---@return string
M.config_path = function()
  return vim.fn.stdpath("config") .. "/init.lua"
end

---@param msg string
local function warn(msg)
  vim.schedule(function()
    vim.notify("[coil] " .. msg, vim.log.levels.WARN)
  end)
end

---Run the config file, if there is one. It is plain Lua (options, keymaps, ...) and may return
---a table of setup options: `{ oil = {...}, coil = {...}, image = {...}, icons = {...} }`, where
---`image = false` leaves image.nvim off and `icons = false` mini.icons. Errors are reported, and
---the defaults are used instead.
---@param path string
---@return table options
M.load_config = function(path)
  if vim.fn.filereadable(path) == 0 then
    return {}
  end
  local ok, result = pcall(dofile, path)
  if not ok then
    warn(string.format("Error in %s, using the defaults: %s", path, result))
    return {}
  end
  if result == nil then
    return {}
  elseif type(result) ~= "table" then
    warn(string.format("%s should return a table (or nothing), got %s", path, type(result)))
    return {}
  end
  return result
end

---@param t any
---@return boolean
local function is_nonempty_list(t)
  return type(t) == "table" and vim.islist(t) and next(t) ~= nil
end

---`over` on top of `base`. Key/value tables merge; lists (such as oil's `columns`) and everything
---else replace what was there.
---@param base table
---@param over table
---@return table
local function merge(base, over)
  local ret = vim.deepcopy(base)
  for key, value in pairs(over) do
    local current = ret[key]
    if
      type(value) == "table"
      and type(current) == "table"
      and not is_nonempty_list(value)
      and not is_nonempty_list(current)
    then
      ret[key] = merge(current, value)
    else
      ret[key] = vim.deepcopy(value)
    end
  end
  return ret
end

---Each plugin's setup() options: the defaults with the config file's on top. false (image,
---icons) means not set up at all.
---@param user table What the config file returned
---@return table<string, table|false>
M.options = function(user)
  local ret = {}
  for name, defaults in pairs(M.defaults) do
    local value = user[name]
    if value == false then
      ret[name] = false
    elseif type(value) == "table" then
      ret[name] = merge(defaults, value)
    else
      ret[name] = vim.deepcopy(defaults)
    end
  end
  return ret
end

---The build's colour scheme, one bundled with Neovim. The default one draws keywords, types and
---numbers in the normal text colour, so syntax-highlighted previews look almost plain.
M.colorscheme = "habamax"

---Everything the standalone build's init does. Opening the column view and --cwd-file are
---standalone mode's (coil.standalone), as in any Neovim started as a file manager.
M.start = function()
  -- The launcher sets it too; this keeps a bare run of the build's Neovim a file manager
  vim.g.coil_standalone = 1
  -- Before the config file, so a colorscheme it sets wins
  vim.cmd.colorscheme(M.colorscheme)
  local options = M.options(M.load_config(M.config_path()))
  if options.icons then
    require("mini.icons").setup(options.icons)
  end
  require("oil").setup(options.oil)
  require("coil").setup(options.coil)
  if options.image then
    require("image").setup(options.image)
  end
end

return M

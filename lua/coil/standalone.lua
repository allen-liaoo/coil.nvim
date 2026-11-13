-- Startup for the standalone `coil` command (nix/coil.nix): set up oil, coil and image.nvim with
-- the build's defaults and the user's config file, then open the column view for the command
-- line. Not used when coil is a plugin in someone's own Neovim.
local M = {}

---Options for each plugin's setup(), as the build ships them. The config file's returned table is
---merged into these.
---@type table<string, table>
M.defaults = {
  oil = {
    -- Deleting a line and saving moves the file to the trash, which oil's trash view (g\)
    -- can restore from
    delete_to_trash = true,
  },
  coil = {},
  image = {},
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
---a table of setup options: `{ oil = {...}, coil = {...}, image = {...} }`, where `image = false`
---leaves image.nvim off. Errors are reported, and the defaults are used instead.
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

---Each plugin's setup() options: the defaults with the config file's on top. false (for image)
---means not set up at all.
---@param user table What the config file returned
---@return table<string, table|false>
M.options = function(user)
  local ret = {}
  for name, defaults in pairs(M.defaults) do
    local value = user[name]
    if value == false then
      ret[name] = false
    elseif type(value) == "table" then
      ret[name] = vim.tbl_deep_extend("force", vim.deepcopy(defaults), value)
    else
      ret[name] = vim.deepcopy(defaults)
    end
  end
  return ret
end

---@param arg string
---@return boolean
local function is_dir(arg)
  -- By now oil may have turned a directory argument into an oil URL ("oil:///path/")
  return vim.fn.isdirectory(arg) == 1 or (arg:match("^[%w-]+://") ~= nil and vim.endswith(arg, "/"))
end

---What the command line opens in the column view: the current directory without arguments, the
---arguments when they are all directories, otherwise nothing (Neovim opens them as usual)
---@param args string[]
---@return nil|string[]
M.dirs_for = function(args)
  if #args == 0 then
    return { vim.fn.getcwd() }
  elseif vim.iter(args):all(is_dir) then
    return args
  end
end

---Open the column view for the command line. The views are the only tabs: the tab Neovim started
---with (empty, or showing the first directory argument as an oil buffer) is closed, and files
---open in a new tab.
---@param args string[]
M.open_args = function(args)
  local dirs = M.dirs_for(args)
  if not dirs then
    return
  end
  local start_tab = vim.api.nvim_get_current_tabpage()
  local start_bufs = vim.api.nvim_list_bufs()
  require("coil").open(dirs)
  if vim.api.nvim_tabpage_is_valid(start_tab) and #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(start_tab))
  end
  vim.cmd("silent! %argdelete")
  -- The start buffers no window shows any more (the views open their own)
  for _, bufnr in ipairs(start_bufs) do
    if vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) == 0 then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

---Everything the standalone build's init does
M.start = function()
  local options = M.options(M.load_config(M.config_path()))
  require("oil").setup(options.oil)
  require("coil").setup(options.coil)
  if options.image then
    require("image").setup(options.image)
  end
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    -- Let the autocmds coil and oil rely on (BufReadCmd, BufWinEnter, ...) fire from here
    nested = true,
    callback = function()
      M.open_args(vim.fn.argv())
    end,
  })
end

return M

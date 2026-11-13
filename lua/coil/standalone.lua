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
    -- Permissions, size and modification time next to each name
    columns = { "icon", "permissions", "size", "mtime" },
  },
  coil = {
    -- q quits, like other terminal file managers (oil's close key still closes one view)
    keymaps = { close = false, quit = "q" },
  },
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

-- The local directory last shown in a column view's middle pane
---@type nil|string
local last_dir = nil

---Keep track of the directory each column view's middle pane shows
M.track_dir = function()
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = vim.api.nvim_create_augroup("CoilStandaloneDir", {}),
    pattern = "oil://*",
    callback = function(args)
      local _, role = require("coil.view.state").find(vim.api.nvim_get_current_win())
      if role == "current" then
        last_dir = require("coil.oil_bridge").local_path(args.match) or last_dir
      end
    end,
  })
end

---The directory to cd to on exit: the current tab's view's, otherwise the one used last, otherwise
---the last one any view showed
---@return nil|string
M.exit_dir = function()
  local state = require("coil.view.state")
  local view = state.get() or state.last()
  if view then
    local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
    local path = require("coil.oil_bridge").local_path(name)
    if path then
      return path
    end
  end
  return last_dir
end

---With `--cwd-file <path>` (passed in as $COIL_CWD_FILE by bin/coil), write the directory to cd to
---on exit to that file, for a shell function to cd there
---@param cwd_file string
M.write_cwd_on_exit = function(cwd_file)
  M.track_dir()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      local dir = M.exit_dir()
      if dir then
        -- Without the trailing slash (except for /) or newline, as yazi writes it
        local path = dir:match("^(.-)/*$")
        vim.fn.writefile({ path ~= "" and path or "/" }, cwd_file, "b")
      end
    end,
  })
end

---Everything the standalone build's init does
M.start = function()
  local options = M.options(M.load_config(M.config_path()))
  if options.icons then
    require("mini.icons").setup(options.icons)
  end
  require("oil").setup(options.oil)
  require("coil").setup(options.coil)
  if options.image then
    require("image").setup(options.image)
  end
  local cwd_file = vim.env.COIL_CWD_FILE
  if cwd_file and cwd_file ~= "" then
    M.write_cwd_on_exit(cwd_file)
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

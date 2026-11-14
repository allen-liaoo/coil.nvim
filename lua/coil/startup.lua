-- Internal. Startup in standalone mode, when Neovim was started as a file manager
-- (`nvim --cmd "let g:coil_standalone = 1"`): open the column view for the command line's
-- directories, and on exit write the last directory to g:coil_cwd_file, if it's set.
-- plugin/coil.lua calls init() in that mode.
local M = {}

---@param arg string
---@return boolean
local function is_url(arg)
  return arg:match("^[%w-]+://") ~= nil
end

---What the command line opens in the column view: the current directory without arguments, the
---arguments when they are all directories, otherwise nothing (Neovim opens them as usual).
---A URL is a directory when it ends in a slash, as oil names them; one without (typed by hand, as
---in `oil-ssh://host//path`) is first given to oil's adapter, which over SSH means waiting for the
---host. Without such URLs `cb` is called right away.
---@param args string[]
---@param cb fun(dirs?: string[])
M.dirs_for = function(args, cb)
  if #args == 0 then
    return cb({ vim.fn.getcwd() })
  end
  ---@param arg string
  ---@return boolean
  local function is_dir(arg)
    -- By now oil may have turned a directory argument into an oil URL ("oil:///path/")
    return vim.fn.isdirectory(arg) == 1 or (is_url(arg) and vim.endswith(arg, "/"))
  end
  -- A plain file argument settles it without asking any host
  if not vim.iter(args):all(function(arg)
    return is_dir(arg) or is_url(arg)
  end) then
    return cb(nil)
  end
  require("coil.oil_bridge").normalize_urls(args, function(dirs)
    cb(vim.iter(dirs):all(is_dir) and dirs or nil)
  end)
end

---@param dirs string[]
---@param start_tab integer
local function open_dirs(dirs, start_tab)
  local start_bufs = vim.api.nvim_list_bufs()
  require("coil").open(dirs)
  if vim.api.nvim_tabpage_is_valid(start_tab) and #vim.api.nvim_list_tabpages() > 1 then
    vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(start_tab))
  end
  vim.cmd("silent! %argdelete")
  -- The start buffers no window shows any more (the views open their own). Only listed ones:
  -- plugins keep unlisted buffers of their own, such as oil's SSH login terminal.
  for _, bufnr in ipairs(start_bufs) do
    if
      vim.api.nvim_buf_is_valid(bufnr)
      and vim.bo[bufnr].buflisted
      and #vim.fn.win_findbuf(bufnr) == 0
    then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end
end

---Open the column view for the command line. The views are the only tabs: the tab Neovim started
---with (empty, or showing the first directory argument as an oil buffer) is closed, and files
---open in a new tab.
---@param args string[]
M.open_args = function(args)
  local start_tab = vim.api.nvim_get_current_tabpage()
  M.dirs_for(args, function(dirs)
    if dirs then
      open_dirs(dirs, start_tab)
    end
  end)
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

---On exit, write the directory to cd to to g:coil_cwd_file, for a shell function to cd there.
---Read at exit, so it can be set any time before (usually `--cmd "let g:coil_cwd_file = '…'"`).
M.write_cwd_on_exit = function()
  M.track_dir()
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      local cwd_file = vim.g.coil_cwd_file
      local dir = M.exit_dir()
      if type(cwd_file) == "string" and cwd_file ~= "" and dir then
        -- Without the trailing slash (except for /) or newline
        local path = dir:match("^(.-)/*$")
        vim.fn.writefile({ path ~= "" and path or "/" }, cwd_file, "b")
      end
    end,
  })
end

---Set up standalone mode. Only does anything during startup: coil loaded later (lazily, after
---VimEnter) has missed the command line.
M.init = function()
  if vim.v.vim_did_enter == 1 then
    return
  end
  M.write_cwd_on_exit()
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    -- Let the autocmds coil and oil rely on (BufReadCmd, BufWinEnter, ...) fire from here
    nested = true,
    callback = function()
      M.open_args(vim.fn.argv() --[[@as string[] ]])
    end,
  })
end

return M

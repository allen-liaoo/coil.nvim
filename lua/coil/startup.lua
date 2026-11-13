-- Internal. Startup in standalone mode, when Neovim was started as a file manager (bin/coil, or
-- `nvim --cmd "let g:coil_standalone = 1"`): open the column view for the command line's
-- directories, and with $COIL_CWD_FILE write the last directory on exit. plugin/coil.lua calls
-- init() in that mode.
local M = {}

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

---Write the directory to cd to on exit to `cwd_file`, for a shell function to cd there
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

---Set up standalone mode. Only does anything during startup: coil loaded later (lazily, after
---VimEnter) has missed the command line.
M.init = function()
  if vim.v.vim_did_enter == 1 then
    return
  end
  -- Read once and cleared, so Neovims started from this one (:terminal) don't inherit it
  local cwd_file = vim.env.COIL_CWD_FILE
  vim.env.COIL_CWD_FILE = nil
  if cwd_file and cwd_file ~= "" then
    M.write_cwd_on_exit(cwd_file)
  end
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

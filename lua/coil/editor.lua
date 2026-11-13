-- Internal. The system's text editor, for `edit_here = false`: XDG's default application for
-- text/plain, otherwise $VISUAL or $EDITOR.
local M = {}

---@class (exact) coil.Editor
---@field argv fun(path: string): string[] The command that opens `path`
---@field terminal boolean Runs in a terminal (otherwise it's a GUI program, started detached)
---@field name string For messages

---A .desktop file's string value without its escapes (\s, \n, \t, \r, \\)
---@param s string
---@return string
local function unescape(s)
  return (
    s:gsub("\\(.)", function(c)
      return ({ s = " ", n = "\n", t = "\t", r = "\r", ["\\"] = "\\" })[c] or ("\\" .. c)
    end)
  )
end

---Split a .desktop file's Exec value into arguments: double quotes group, and inside them a
---backslash escapes the next character
---@param exec string
---@return string[]
M.split_exec = function(exec)
  local args, current, quoted = {}, nil, false
  local i = 1
  while i <= #exec do
    local c = exec:sub(i, i)
    if quoted then
      if c == "\\" and i < #exec then
        i = i + 1
        current = current .. exec:sub(i, i)
      elseif c == '"' then
        quoted = false
      else
        current = current .. c
      end
    elseif c == '"' then
      quoted = true
      current = current or ""
    elseif c == " " or c == "\t" then
      if current then
        table.insert(args, current)
        current = nil
      end
    else
      current = (current or "") .. c
    end
    i = i + 1
  end
  if current then
    table.insert(args, current)
  end
  return args
end

---The command a .desktop file's Exec value runs for `path`. Field codes for files and URLs
---(%f, %F, %u, %U) become the path, %% a percent sign, and the rest (%i, %c, %k) are dropped. With
---no file field code, the path goes last.
---@param exec string
---@param path string
---@return string[]
M.exec_argv = function(exec, path)
  local argv, placed = {}, false
  for _, arg in ipairs(M.split_exec(exec)) do
    local expanded = arg:gsub("%%(.)", function(code)
      if code:match("[fFuU]") then
        placed = true
        return path
      elseif code == "%" then
        return "%"
      end
      return ""
    end)
    if expanded ~= "" then
      table.insert(argv, expanded)
    end
  end
  if not placed then
    table.insert(argv, path)
  end
  return argv
end

---Where a desktop file ID's file can be: in the applications directory of each XDG data directory,
---with each "-" in the ID possibly standing for a subdirectory ("kde-foo.desktop" in kde/)
---@param id string
---@return string[]
local function desktop_file_candidates(id)
  local home = vim.env.XDG_DATA_HOME
  if not home or home == "" then
    home = vim.fn.expand("~/.local/share")
  end
  local dirs = { home }
  local data_dirs = vim.env.XDG_DATA_DIRS
  if not data_dirs or data_dirs == "" then
    data_dirs = "/usr/local/share:/usr/share"
  end
  vim.list_extend(dirs, vim.split(data_dirs, ":", { trimempty = true }))

  local names = { id }
  local rest = id
  local prefix = ""
  while true do
    local head, tail = rest:match("^([^-]+)%-(.+)$")
    if not head then
      break
    end
    prefix = prefix .. head .. "/"
    table.insert(names, prefix .. tail)
    rest = tail
  end

  local ret = {}
  for _, dir in ipairs(dirs) do
    for _, name in ipairs(names) do
      table.insert(ret, dir .. "/applications/" .. name)
    end
  end
  return ret
end

---The [Desktop Entry] group of a .desktop file
---@param path string
---@return nil|table<string, string>
M.read_desktop_file = function(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local entry, in_group = {}, false
  for _, line in ipairs(lines) do
    local group = line:match("^%[(.*)%]%s*$")
    if group then
      in_group = group == "Desktop Entry"
    elseif in_group then
      local key, value = line:match("^([%w%-]+)%s*=%s*(.*)$")
      if key then
        entry[key] = value
      end
    end
  end
  return entry
end

---XDG's default application for text/plain, as a desktop file ID ("nvim.desktop")
---@return nil|string
local function xdg_default_id()
  if vim.fn.executable("xdg-mime") == 0 then
    return nil
  end
  local ok, result = pcall(function()
    return vim.system({ "xdg-mime", "query", "default", "text/plain" }, { text = true }):wait(2000)
  end)
  if not ok or result.code ~= 0 then
    return nil
  end
  local id = vim.trim(result.stdout or "")
  return id ~= "" and id or nil
end

---XDG's default text editor
---@return nil|coil.Editor
local function xdg_editor()
  local id = xdg_default_id()
  if not id then
    return nil
  end
  for _, file in ipairs(desktop_file_candidates(id)) do
    local entry = vim.fn.filereadable(file) == 1 and M.read_desktop_file(file)
    if entry and entry.Exec and entry.Hidden ~= "true" then
      local exec = unescape(entry.Exec)
      return {
        name = id,
        terminal = entry.Terminal == "true",
        argv = function(path)
          return M.exec_argv(exec, path)
        end,
      }
    end
  end
end

---$VISUAL, otherwise $EDITOR. A shell command, which may have arguments ("code --wait"); it runs
---through sh with the path as its last argument, as git runs it.
---@return nil|coil.Editor
local function env_editor()
  for _, name in ipairs({ "VISUAL", "EDITOR" }) do
    local cmd = vim.env[name]
    if cmd and vim.trim(cmd) ~= "" then
      return {
        name = "$" .. name,
        terminal = true,
        argv = function(path)
          return { "sh", "-c", cmd .. ' "$@"', "sh", path }
        end,
      }
    end
  end
end

---The system's text editor: XDG's default for text/plain, otherwise $VISUAL or $EDITOR
---@return nil|coil.Editor
M.find = function()
  return xdg_editor() or env_editor()
end

-- Neovim's own state, which it exports to every process it starts: $NVIM (this Neovim's server,
-- which nested Neovims and plugins react to), its log file, runtime files and init file. An editor
-- gets none of it, so a Neovim editor starts as it would from a shell.
local NEOVIM_ENV = { "NVIM", "NVIM_LOG_FILE", "MYVIMRC", "VIM", "VIMRUNTIME" }

---`argv` run with the environment an editor gets: without Neovim's own state (through `env -u`,
---since Neovim adds $NVIM to every job's environment), and with g:coil_editor_env, which the Nix
---`coil` sets to give editors back the user's NVIM_APPNAME
---@param argv string[]
---@return string[]
M.clean_env = function(argv)
  local ret = { "env" }
  for _, name in ipairs(NEOVIM_ENV) do
    vim.list_extend(ret, { "-u", name })
  end
  local extra = vim.g.coil_editor_env
  if type(extra) == "table" then
    local names = vim.tbl_keys(extra)
    table.sort(names)
    for _, name in ipairs(names) do
      table.insert(ret, name .. "=" .. tostring(extra[name]))
    end
  end
  return vim.list_extend(ret, argv)
end

---`argv` in a new terminal window: with xdg-terminal-exec (the XDG way to start one), otherwise
---$TERMINAL -e. Nil when there's neither.
---@param argv string[]
---@return nil|string[]
local function in_terminal_window(argv)
  if vim.fn.executable("xdg-terminal-exec") == 1 then
    return vim.list_extend({ "xdg-terminal-exec" }, argv)
  end
  local terminal = vim.env.TERMINAL
  if terminal and terminal ~= "" and vim.fn.executable(terminal) == 1 then
    return vim.list_extend({ terminal, "-e" }, argv)
  end
end

---@param argv string[]
---@return boolean ok
local function start_detached(argv)
  local ok, job = pcall(vim.fn.jobstart, argv, { detach = true })
  return ok and job > 0
end

---Run `argv` in a terminal in a new tab of this Neovim, closed when it exits. Only when there's no
---way to open a terminal window: keys pass through this Neovim's terminal mappings first.
---@param argv string[]
---@return boolean ok
local function in_tab(argv)
  vim.cmd.tabnew()
  local bufnr = vim.api.nvim_get_current_buf()
  local opts = {
    on_exit = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end)
    end,
  }
  local ok, job
  if vim.fn.has("nvim-0.11") == 1 then
    opts.term = true
    ok, job = pcall(vim.fn.jobstart, argv, opts)
  else
    ok, job = pcall(vim.fn.termopen, argv, opts)
  end
  if not ok or job <= 0 then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    return false
  end
  vim.cmd.startinsert()
  return true
end

---Open `path` with `editor`, as its own program: a GUI editor in the background, a terminal editor
---in a new terminal window (or, without a way to open one, in a terminal tab here)
---@param editor coil.Editor
---@param path string
---@return boolean ok
M.open = function(editor, path)
  local argv = editor.argv(path)
  if not editor.terminal then
    return start_detached(M.clean_env(argv))
  end
  local window = in_terminal_window(argv)
  if window then
    -- The terminal emulator gets the clean environment too, and passes it on
    return start_detached(M.clean_env(window))
  end
  return in_tab(M.clean_env(argv))
end

return M

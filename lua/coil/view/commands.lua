-- Commands typed in the middle pane. One that opens something (:Oil, :edit with a name, :buffer,
-- :split, ...) runs in the editing window instead, decided before it runs: the middle pane only
-- moves with coil's and oil's keys, and plain oil stays one command away. Anything else (:w, :edit
-- on its own, :Coil, :s, ...) runs in the middle pane as usual.
local bridge = require("coil.oil_bridge")
local open = require("coil.view.open")
local M = {}

---How a command that opens something is re-run in the editing window:
---  "arg"     only when it names what to open (without, it acts on the middle pane: :edit reloads)
---  "as_is"   always, as typed (what it opens doesn't depend on the middle pane: :enew, :tabnew)
---  "current" always; without a name it opens the middle pane's directory (:split, :vsplit)
---@alias coil.OpenerKind "arg"|"as_is"|"current"

---@type table<string, coil.OpenerKind>
local openers = {
  edit = "arg",
  view = "arg",
  visual = "arg",
  find = "arg",
  buffer = "arg",
  drop = "arg",
  enew = "as_is",
  new = "as_is",
  vnew = "as_is",
  tabnew = "as_is",
  tabedit = "as_is",
  tabfind = "arg",
  split = "current",
  vsplit = "current",
  sview = "current",
  sfind = "arg",
  sbuffer = "arg",
}

---Expand `%`, `#`, `<cfile>` and the like where the command was typed: in the editing window
---they would name other files
---@param args string[]
---@return string[]
local function expand(args)
  return vim.tbl_map(function(arg)
    local ok, expanded = pcall(vim.fn.expandcmd, arg)
    return ok and expanded or arg
  end, args)
end

---The command to run in the editing window instead, if `line` opens something
---@param line string The typed command line
---@param middle_url string The middle pane's directory
---@return nil|vim.api.keyset.cmd cmd
---@return nil|{url: string, name: string} focus Put oil's cursor on this entry first
local function redirected(line, middle_url)
  local ok, cmd = pcall(vim.api.nvim_parse_cmd, line, {})
  -- `cmd | cmd2` runs as typed: only the first would move
  if not ok or not cmd.cmd or (cmd.nextcmd or "") ~= "" then
    return nil
  end
  local args = expand(cmd.args or {})
  local focus
  if cmd.cmd == "Oil" then
    -- `:Oil [--float] [--preview] [dir]`. Without a directory, oil opens the parent of the
    -- current one with the cursor on it; name them, as the editing window's buffer is another
    if not vim.iter(args):any(function(arg)
      return not vim.startswith(arg, "--")
    end) then
      local parent, name = bridge.parent_of(middle_url)
      table.insert(args, parent or middle_url)
      focus = parent and name and { url = parent, name = name } or nil
    end
  else
    local kind = openers[cmd.cmd]
    if not kind or (kind == "arg" and #args == 0) then
      return nil
    elseif kind == "current" and #args == 0 then
      args = { middle_url }
    end
  end
  cmd.args = args
  -- Already expanded
  cmd.magic = { file = false, bar = false }
  return cmd, focus
end

---@param view coil.View
---@return fun() detach
M.attach = function(view)
  local id = vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = view.group,
    pattern = ":",
    desc = "Run commands that open something, typed in the middle pane, in the editing window",
    callback = function()
      local middle = view.panes.current
      if
        vim.v.event.abort
        or vim.v.event.cmdlevel ~= 1
        or vim.api.nvim_get_current_win() ~= middle
        or not bridge.is_oil_dir(vim.api.nvim_win_get_buf(middle))
      then
        return
      end
      local line = vim.fn.getcmdline()
      local cmd, focus =
        redirected(line, vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(middle)))
      if not cmd then
        return
      end
      -- Cancel it here and run it there. (vim.v.event is a copy, so set it the Vimscript way.)
      -- Aborting leaves it out of the history, so add it back.
      vim.cmd("let v:event.abort = v:true")
      vim.fn.histadd(":", line)
      local function run()
        if focus then
          bridge.focus_entry(focus.url, focus.name)
        end
        local ok, err = pcall(vim.api.nvim_cmd, cmd, {})
        if not ok then
          return vim.notify((tostring(err):gsub("^Vim[^:]*:", "")), vim.log.levels.ERROR)
        end
        if focus then
          -- oil places the cursor only when it renders the buffer, and the parent pane may have
          -- rendered this one already
          local winid, bufnr = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
          bridge.on_ready(bufnr, function()
            local lnum = bridge.line_of(bufnr, focus.name)
            if
              lnum
              and vim.api.nvim_win_is_valid(winid)
              and vim.api.nvim_win_get_buf(winid) == bufnr
            then
              vim.api.nvim_win_set_cursor(winid, { lnum, 0 })
            end
          end)
        end
      end
      vim.schedule(function()
        -- Closed in the meantime: run it wherever we are now
        if require("coil.view.state").is_open(view) then
          open.in_editing_window(view, run)
        else
          run()
        end
      end)
    end,
  })
  return function()
    pcall(vim.api.nvim_del_autocmd, id)
  end
end

return M

local h = require("tests.helpers")
local uv = vim.uv or vim.loop

describe("the termfilechooser wrapper (bin/coil-termfilechooser)", function()
  local dir, wrapper, log

  before_each(function()
    dir = h.tmpdir()
    log = dir .. "/log"
    -- A copy next to a stand-in for coil, as in bin/: writes its arguments to the log, then
    -- chooses $CHOOSE and quits in $QUIT_IN, if set
    vim.fn.mkdir(dir .. "/bin")
    wrapper = dir .. "/bin/coil-termfilechooser"
    vim.fn.writefile(vim.fn.readfile("bin/coil-termfilechooser"), wrapper)
    h.write(dir .. "/bin/coil", {
      "#!/usr/bin/env bash",
      'printf "coil=%s\\n" "$@" >> "$LOG"',
      "while [ $# -gt 0 ]; do",
      '  case "$1" in',
      '    --chooser-file) [ -z "${CHOOSE-}" ] || printf "%s\\n" "$CHOOSE" > "$2"; shift 2 ;;',
      '    --cwd-file) [ -z "${QUIT_IN-}" ] || printf "%s" "$QUIT_IN" > "$2"; shift 2 ;;',
      "    *) shift ;;",
      "  esac",
      "done",
    })
    -- A stand-in for the terminal: logs its own arguments, then runs the command after them
    h.write(dir .. "/term", {
      "#!/usr/bin/env bash",
      'printf "term=%s\\n" "$1" "$2" >> "$LOG"',
      "shift 2",
      'exec "$@"',
    })
    for _, file in ipairs({ wrapper, dir .. "/bin/coil", dir .. "/term" }) do
      vim.fn.setfperm(file, "rwxr-xr-x")
    end
  end)

  ---@param args string[] The portal's: multiple, directory, save, path, out
  ---@param env? table<string, string>
  ---@param cmd? string The wrapper to run
  ---@return string[] log
  local function run(args, env, cmd)
    env = vim.tbl_extend("force", {
      LOG = log,
      TERMCMD = dir .. '/term --title "Terminal Filechooser"',
    }, env or {})
    local result = vim.system(vim.list_extend({ cmd or wrapper }, args), { env = env }):wait(5000)
    assert.equals(0, result.code, result.stderr)
    return vim.fn.readfile(log)
  end

  ---@return nil|string
  local function out()
    return vim.fn.filereadable(dir .. "/out") == 1
        and table.concat(vim.fn.readfile(dir .. "/out", "b"), "\n")
      or nil
  end

  it("runs coil in TERMCMD to choose files", function()
    local path = dir .. '/it\'s a "dir"'
    assert.same({
      "term=--title",
      "term=Terminal Filechooser",
      "coil=--chooser-file",
      "coil=" .. dir .. "/out",
      "coil=" .. path,
    }, run({ "1", "0", "0", path, dir .. "/out" }, { CHOOSE = "/a/b" }))
    assert.equals("/a/b\n", out())
  end)

  it("chooses a directory: the one coil quits in, unless entries were chosen", function()
    local args = { "0", "1", "0", dir, dir .. "/out" }
    assert.same({
      "term=--title",
      "term=Terminal Filechooser",
      "coil=--chooser-file",
      "coil=" .. dir .. "/out",
      "coil=--cwd-file",
      "coil=" .. dir .. "/out.1",
      "coil=" .. dir,
    }, run(args, { QUIT_IN = "/quit/here" }))
    assert.equals("/quit/here", out())
    assert.is_nil(uv.fs_stat(dir .. "/out.1"))

    vim.fn.delete(log)
    run(args, { QUIT_IN = "/quit/here", CHOOSE = "/chosen" })
    assert.equals("/chosen\n", out())
    assert.is_nil(uv.fs_stat(dir .. "/out.1"))
  end)

  it("finds coil through a link to it", function()
    local link = dir .. "/config/coil-termfilechooser"
    vim.fn.mkdir(dir .. "/config")
    assert(uv.fs_symlink(wrapper, link))
    run({ "0", "0", "1", dir .. "/new.txt", dir .. "/out" }, { CHOOSE = dir .. "/new.txt" }, link)
    assert.equals(dir .. "/new.txt\n", out())
  end)

  describe("without TERMCMD", function()
    local args, path

    before_each(function()
      args = { "0", "0", "0", dir, dir .. "/out" }
      -- Only the tools the wrapper needs, and the stand-in terminals
      vim.fn.mkdir(dir .. "/terms")
      local dirs = { dir .. "/terms" }
      for _, tool in ipairs({ "bash", "sh", "readlink", "dirname" }) do
        table.insert(dirs, vim.fn.fnamemodify(vim.fn.exepath(tool), ":h"))
      end
      path = table.concat(dirs, ":")
    end)

    ---A terminal named `name` that logs its name and runs its command (after -e, if given)
    ---@param name string
    local function terminal(name)
      local file = dir .. "/terms/" .. name
      h.write(file, {
        "#!/usr/bin/env bash",
        string.format('echo "via=%s $1" >> "$LOG"', name),
        '[ "$1" != -e ] || shift',
        'exec "$@"',
      })
      vim.fn.setfperm(file, "rwxr-xr-x")
    end

    it("runs coil with xdg-terminal-exec", function()
      terminal("xdg-terminal-exec")
      local log_lines = run(args, { TERMCMD = "", TERMINAL = "myterm", PATH = path, CHOOSE = "/a" })
      assert.equals("via=xdg-terminal-exec " .. dir .. "/bin/coil", log_lines[1])
      assert.equals("/a\n", out())
    end)

    it("runs coil with $TERMINAL -e otherwise", function()
      terminal("myterm")
      local log_lines = run(args, { TERMCMD = "", TERMINAL = "myterm", PATH = path, CHOOSE = "/a" })
      assert.equals("via=myterm -e", log_lines[1])
      assert.equals("/a\n", out())
    end)

    it("says to set TERMCMD without either", function()
      local env = { LOG = log, TERMCMD = "", TERMINAL = "", PATH = path }
      local result = vim.system(vim.list_extend({ wrapper }, args), { env = env }):wait(5000)
      assert.equals(1, result.code)
      assert.truthy(result.stderr:find("set TERMCMD to the terminal to run coil in", 1, true))
    end)
  end)
end)

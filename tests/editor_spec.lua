local coil = require("coil")
local editor = require("coil.editor")
local h = require("tests.helpers")

describe("the system's text editor", function()
  local dir, saved

  ---Put an executable script in the stub directory
  ---@param name string
  ---@param lines string[]
  local function script(name, lines)
    local path = dir .. "/bin/" .. name
    h.write(path, vim.list_extend({ "#!/bin/sh" }, lines))
    vim.fn.setfperm(path, "rwxr-xr-x")
    return path
  end

  ---xdg-mime answering `id` for text/plain (nil: no default)
  ---@param id? string
  local function xdg_default(id)
    script("xdg-mime", id and { "echo " .. id } or { "exit 4" })
  end

  ---A desktop file in the stub XDG data directory
  ---@param name string Its path under applications/
  ---@param lines string[]
  local function desktop_file(name, lines)
    h.write(dir .. "/share/applications/" .. name, lines)
  end

  ---An editor that writes its arguments, $NVIM_APPNAME and $NVIM to `out`
  ---@return string path, string out
  local function recorder()
    local out = dir .. "/editor-out"
    return script("record", {
      string.format('printf "%%s\\n" "$@" > "%s"', out),
      string.format('echo "appname=${NVIM_APPNAME-unset} nvim=${NVIM-unset}" >> "%s"', out),
    }),
      out
  end

  ---@param out string
  ---@return string[]
  local function wait_output(out)
    assert.is_true(h.wait(function()
      return vim.fn.filereadable(out) == 1 and #vim.fn.readfile(out) > 0
    end, 5000))
    return vim.fn.readfile(out)
  end

  before_each(function()
    dir = h.tmpdir()
    vim.fn.mkdir(dir .. "/bin", "p")
    saved = {
      PATH = vim.env.PATH,
      XDG_DATA_HOME = vim.env.XDG_DATA_HOME,
      XDG_DATA_DIRS = vim.env.XDG_DATA_DIRS,
      VISUAL = vim.env.VISUAL,
      EDITOR = vim.env.EDITOR,
      TERMINAL = vim.env.TERMINAL,
    }
    -- Only the stubs and the basics: no real xdg-terminal-exec or terminal emulator
    vim.env.PATH = table.concat({
      dir .. "/bin",
      vim.fs.dirname(vim.fn.exepath("env")),
      vim.fs.dirname(vim.fn.exepath("sh")),
    }, ":")
    vim.env.TERMINAL = nil
    vim.env.XDG_DATA_HOME = dir .. "/share"
    vim.env.XDG_DATA_DIRS = dir .. "/none"
    vim.env.VISUAL = nil
    vim.env.EDITOR = nil
    xdg_default(nil)
  end)

  after_each(function()
    for name, value in pairs(saved) do
      vim.env[name] = value
    end
    vim.g.coil_editor_env = nil
  end)

  describe("desktop files", function()
    it("splits Exec into arguments", function()
      assert.same({ "a", 'b "c" d', "e" }, editor.split_exec('a "b \\"c\\" d"  e'))
    end)

    it("puts the path where the field codes are", function()
      local p = "/tmp/it's a file.txt"
      assert.same({ "nvim", p }, editor.exec_argv("nvim %F", p))
      assert.same(
        { "/opt/My Editor/ed", "--new-window", p },
        editor.exec_argv('"/opt/My Editor/ed" --new-window %u', p)
      )
      assert.same({ "ed", "--file=" .. p, "100%" }, editor.exec_argv("ed %i --file=%f 100%%", p))
      -- No field code: the path goes last
      assert.same({ "gedit", p }, editor.exec_argv("gedit", p))
    end)
  end)

  describe("finding it", function()
    it("prefers XDG's default for text/plain over $VISUAL and $EDITOR", function()
      vim.env.VISUAL = "vi"
      xdg_default("test-editor.desktop")
      -- A "-" in the ID can stand for a subdirectory
      desktop_file("test/editor.desktop", {
        "[Desktop Entry]",
        "Exec=myeditor --flag %f",
        "Terminal=true",
        "[Desktop Action new]",
        "Exec=wrong",
      })
      local found = assert(editor.find())
      assert.equals("test-editor.desktop", found.name)
      assert.is_true(found.terminal)
      assert.same({ "myeditor", "--flag", "/x" }, found.argv("/x"))
    end)

    it("falls back to $VISUAL, then $EDITOR, then nothing", function()
      assert.is_nil(editor.find())
      vim.env.EDITOR = "nano"
      assert.equals("$EDITOR", assert(editor.find()).name)
      vim.env.VISUAL = "hx"
      local found = assert(editor.find())
      assert.equals("$VISUAL", found.name)
      assert.is_true(found.terminal)
      -- Through sh, with the path as an argument rather than in the command
      assert.same({ "sh", "-c", 'hx "$@"', "sh", "/x" }, found.argv("/x"))
    end)
  end)

  it("starts editors without Neovim's own environment, plus g:coil_editor_env", function()
    vim.g.coil_editor_env = { NVIM_APPNAME = "" }
    assert.same({
      "env",
      "-u",
      "NVIM",
      "-u",
      "NVIM_LOG_FILE",
      "-u",
      "MYVIMRC",
      "-u",
      "VIM",
      "-u",
      "VIMRUNTIME",
      "NVIM_APPNAME=",
      "ed",
    }, editor.clean_env({ "ed" }))
  end)

  describe("from the column view, with edit_here = false", function()
    local proj, origin_tab

    before_each(function()
      pcall(coil.close)
      h.reset_tab()
      h.setup_oil()
      coil.setup({ edit_here = false })
      proj = dir .. "/proj"
      h.write(proj .. "/notes.txt", { "hello" })
      origin_tab = vim.api.nvim_get_current_tabpage()
    end)

    after_each(function()
      pcall(coil.close)
      coil.setup()
    end)

    ---@return coil.View
    local function select_notes()
      local view = h.open_view(proj)
      h.cursor_to(view.panes.current, "notes.txt")
      h.press("L")
      return view
    end

    it("opens a terminal editor in a new terminal window, with xdg-terminal-exec", function()
      local cmd, out = recorder()
      script("xdg-terminal-exec", { 'exec "$@"' })
      vim.env.EDITOR = cmd
      local view = select_notes()
      assert.same({ proj .. "/notes.txt", "appname=unset nvim=unset" }, wait_output(out))
      -- Not in this Neovim: still the view and the editing tab
      assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
      assert.equals(2, #vim.api.nvim_list_tabpages())
      assert.equals(-1, vim.fn.bufnr(proj .. "/notes.txt"))
    end)

    it("uses $TERMINAL -e without xdg-terminal-exec", function()
      local cmd, out = recorder()
      vim.env.TERMINAL = script("term", { '[ "$1" = -e ] && shift', 'exec "$@"' })
      xdg_default("tui.desktop")
      desktop_file("tui.desktop", { "[Desktop Entry]", "Exec=" .. cmd .. " %F", "Terminal=true" })
      select_notes()
      assert.same({ proj .. "/notes.txt", "appname=unset nvim=unset" }, wait_output(out))
      assert.equals(2, #vim.api.nvim_list_tabpages())
    end)

    it("runs it in a tab here, closed when it exits, with no way to open a window", function()
      local cmd, out = recorder()
      vim.env.EDITOR = cmd
      local view = select_notes()
      assert.same({ proj .. "/notes.txt", "appname=unset nvim=unset" }, wait_output(out))
      assert.is_true(h.wait(function()
        return #vim.api.nvim_list_tabpages() == 2
      end))
      assert.is_true(vim.tbl_contains(vim.api.nvim_list_tabpages(), view.tab))
      assert.is_true(vim.tbl_contains(vim.api.nvim_list_tabpages(), origin_tab))
    end)

    it("starts a GUI editor in the background", function()
      local cmd, out = recorder()
      xdg_default("gui.desktop")
      desktop_file("gui.desktop", { "[Desktop Entry]", "Exec=" .. cmd .. " %F" })
      local view = select_notes()
      assert.same({ proj .. "/notes.txt", "appname=unset nvim=unset" }, wait_output(out))
      assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
      -- No terminal tab: still the view and the editing tab
      assert.equals(2, #vim.api.nvim_list_tabpages())
    end)

    it("gives the editor the environment in g:coil_editor_env", function()
      local cmd, out = recorder()
      vim.env.EDITOR = cmd
      vim.g.coil_editor_env = { NVIM_APPNAME = "mine" }
      select_notes()
      assert.same({ proj .. "/notes.txt", "appname=mine nvim=unset" }, wait_output(out))
    end)

    it("opens text files here when there's no system editor", function()
      select_notes()
      assert.is_true(h.wait(function()
        return vim.api.nvim_buf_get_name(0) == proj .. "/notes.txt"
      end))
      assert.equals(origin_tab, vim.api.nvim_get_current_tabpage())
    end)
  end)
end)

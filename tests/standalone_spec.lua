local coil = require("coil")
local h = require("tests.helpers")
local startup = require("coil.startup")
local state = require("coil.view.state")

describe("standalone startup", function()
  local dir

  before_each(function()
    dir = h.tmpdir()
  end)

  describe("the command line", function()
    before_each(function()
      startup.track_dir()
      for _ = 1, 5 do
        pcall(coil.close)
      end
      h.reset_tab()
      h.setup_oil()
      coil.setup()
      vim.fn.mkdir(dir .. "/one")
      vim.fn.mkdir(dir .. "/two")
      h.write(dir .. "/file.txt", { "" })
    end)

    after_each(function()
      vim.g.coil_cwd_file = nil
      vim.g.coil_chooser_file = nil
      for _ = 1, 5 do
        pcall(coil.close)
      end
    end)

    ---@param args string[]
    ---@return nil|string[]
    local function dirs_for(args)
      local result, called = nil, false
      startup.dirs_for(args, function(dirs)
        result, called = dirs, true
      end)
      assert.is_true(h.wait(function()
        return called
      end))
      return result
    end

    it("opens the current directory, all-directory arguments, or nothing", function()
      assert.same({ vim.fn.getcwd() }, dirs_for({}))
      local dirs = { dir .. "/one", "oil://" .. dir .. "/two/" }
      assert.same(dirs, dirs_for(dirs))
      assert.is_nil(dirs_for({ dir .. "/one", dir .. "/file.txt" }))
    end)

    it("asks oil about URLs without a trailing slash", function()
      assert.same(
        { dir .. "/one", "oil://" .. dir .. "/two/" },
        dirs_for({ dir .. "/one", "oil://" .. dir .. "/two" })
      )
      assert.is_nil(dirs_for({ dir .. "/one", "oil://" .. dir .. "/file.txt" }))
      -- Not oil's: Neovim opens it as usual
      assert.is_nil(dirs_for({ "https://example.com/a" }))
    end)

    it("opens the view once a URL argument turns out to be a directory", function()
      startup.open_args({ "oil://" .. dir .. "/two" })
      assert.is_true(h.wait(function()
        return state.get() ~= nil
      end))
      local view = assert(state.get())
      assert.equals(
        "oil://" .. dir .. "/two/",
        vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
      )
    end)

    it("when choosing, opens a file argument's directory with the cursor on it", function()
      vim.g.coil_chooser_file = dir .. "/chosen"
      h.write(dir .. "/one/a.txt", { "" })
      h.write(dir .. "/one/b.txt", { "" })
      startup.open_args({ dir .. "/one/b.txt" })
      assert.is_true(h.wait(function()
        local view = state.get()
        if not view then
          return false
        end
        local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
        local entry = vim.b[bufnr].oil_ready
          and require("oil").get_entry_on_line(
            bufnr,
            vim.api.nvim_win_get_cursor(view.panes.current)[1]
          )
        return vim.api.nvim_buf_get_name(bufnr) == "oil://" .. dir .. "/one/"
          and entry
          and entry.name == "b.txt"
      end))
    end)

    it("when choosing, opens a new file's directory (a save dialog's suggestion)", function()
      vim.g.coil_chooser_file = dir .. "/chosen"
      startup.open_args({ dir .. "/two/new.txt" })
      assert.is_true(h.wait(function()
        local view = state.get()
        return view ~= nil
          and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
            == "oil://" .. dir .. "/two/"
      end))
    end)

    it("writes the column view's directory to g:coil_cwd_file on exit", function()
      local cwd_file = dir .. "/cwd"
      vim.g.coil_cwd_file = cwd_file
      startup.write_cwd_on_exit()
      h.open_view(dir .. "/one")
      vim.api.nvim_exec_autocmds("VimLeavePre", {})
      -- No trailing slash or newline
      assert.equals(dir .. "/one", table.concat(vim.fn.readfile(cwd_file, "b"), "\n"))
    end)

    it("writes no g:coil_cwd_file when quitting with the cancel key", function()
      local cwd_file = dir .. "/cwd"
      vim.g.coil_cwd_file = cwd_file
      startup.write_cwd_on_exit()
      h.open_view(dir .. "/one")
      local cmd = vim.cmd
      ---@diagnostic disable-next-line: assign-type-mismatch
      vim.cmd = function(c)
        assert.equals("confirm qall", c)
        vim.api.nvim_exec_autocmds("VimLeavePre", {})
      end
      startup.quit_without_cwd()
      vim.cmd = cmd
      assert.equals(0, vim.fn.filereadable(cwd_file))
      -- Called off (the prompt was cancelled): a later quit writes it again
      vim.api.nvim_exec_autocmds("VimLeavePre", {})
      assert.equals(dir .. "/one", table.concat(vim.fn.readfile(cwd_file, "b"), "\n"))
    end)

    it("remembers the last directory after the views are closed", function()
      local view = h.open_view(dir)
      h.cursor_to(view.panes.current, "two/")
      h.press("L")
      assert.is_true(h.wait(function()
        return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
          == "oil://" .. dir .. "/two/"
      end))
      coil.close()
      assert.equals(dir .. "/two/", startup.exit_dir())
    end)

    it("starts with only the column views", function()
      local start_buf = vim.api.nvim_get_current_buf()
      -- A plugin's own hidden buffer, like oil's SSH login terminal
      local plugin_buf = vim.api.nvim_create_buf(false, true)
      startup.open_args({ dir .. "/one", dir .. "/two" })
      assert.equals(2, #vim.api.nvim_list_tabpages())
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        assert.truthy(state.get(tab))
      end
      assert.is_false(vim.api.nvim_buf_is_valid(start_buf))
      assert.is_true(vim.api.nvim_buf_is_valid(plugin_buf))
      vim.api.nvim_buf_delete(plugin_buf, { force = true })
    end)
  end)
end)

describe("standalone mode", function()
  local dir

  before_each(function()
    dir = h.tmpdir()
    vim.fn.mkdir(dir .. "/one")
    vim.fn.mkdir(dir .. "/two")
  end)

  ---Start a Neovim with coil and oil set up, as from a shell, and report what it showed
  ---@param flags string[] Neovim's options
  ---@param args string[] File arguments
  ---@param quit? string The command the child quits with (default: qa!)
  ---@return table report, string cwd_file
  local function run(flags, args, quit)
    local out = dir .. "/report.json"
    local cwd_file = dir .. "/cwd"
    local cmd = { vim.v.progpath, "--headless", "--clean" }
    vim.list_extend(cmd, flags)
    -- As a cd-on-exit shell function passes it
    vim.list_extend(cmd, { "--cmd", string.format("let g:coil_cwd_file = '%s'", cwd_file) })
    vim.list_extend(cmd, { "-u", "tests/fixtures/standalone_init.lua", "--" })
    vim.list_extend(cmd, args)
    local result =
      vim.system(cmd, { env = { COIL_TEST_OUT = out, COIL_TEST_QUIT = quit } }):wait(20000)
    assert.equals(quit == "cq" and 1 or 0, result.code, result.stderr)
    return vim.json.decode(table.concat(vim.fn.readfile(out), "\n")), cwd_file
  end

  it("starts as a file manager with g:coil_standalone", function()
    local report, cwd_file = run(
      { "--cmd", "let g:coil_standalone = 1" },
      { dir .. "/one", dir .. "/two" }
    )
    -- Only the column views, one per directory
    assert.same({ "oil://" .. dir .. "/one/", "oil://" .. dir .. "/two/" }, report.tabs)
    assert.equals("actions.quit", report.quit)
    assert.equals(dir .. "/one", table.concat(vim.fn.readfile(cwd_file, "b"), "\n"))
  end)

  it("writes no g:coil_cwd_file when exiting with an error code (:cq)", function()
    local _, cwd_file = run({ "--cmd", "let g:coil_standalone = 1" }, { dir .. "/one" }, "cq")
    assert.equals(0, vim.fn.filereadable(cwd_file))
  end)

  it("leaves a plain Neovim alone", function()
    local report, cwd_file = run({}, { dir .. "/one" })
    assert.same({ vim.NIL }, report.tabs)
    assert.equals("actions.close", report.quit)
    assert.equals(0, vim.fn.filereadable(cwd_file))
  end)
end)

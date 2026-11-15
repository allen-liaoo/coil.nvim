local coil = require("coil")
local h = require("tests.helpers")
local state = require("coil.view.state")

describe("column view keys", function()
  local root, proj, origin_tab, origin_win

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup()
    root = h.tmpdir()
    proj = root .. "/proj"
    h.write(proj .. "/a.txt", { "hello" })
    h.write(proj .. "/sub/inner.txt", { "inner" })
    h.write(proj .. "/.dot", { "" })
    h.write(root .. "/.rootdot", { "" })
    origin_tab = vim.api.nvim_get_current_tabpage()
    origin_win = vim.api.nvim_get_current_win()
  end)

  ---@param view coil.View
  ---@return string
  local function middle_name(view)
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
  end

  ---@param view coil.View
  local function assert_view_intact(view)
    assert.is_true(state.is_open(view))
    assert.equals(3, #vim.api.nvim_tabpage_list_wins(view.tab))
  end

  it("L enters a directory in the middle pane", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "sub/")
    h.press("L")
    assert.is_true(h.wait(function()
      return middle_name(view) == "oil://" .. proj .. "/sub/"
    end))
    assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
    assert_view_intact(view)
  end)

  it("L leaves a file alone: only <CR> opens it", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("L")
    vim.wait(100)
    assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
    assert.equals("oil://" .. proj .. "/", middle_name(view))
    assert_view_intact(view)
    -- No buffer left behind for it
    assert.equals(-1, vim.fn.bufnr(proj .. "/a.txt"))
  end)

  it("H goes to the parent directory with the cursor on where we came from", function()
    local view = h.open_view(proj .. "/sub")
    h.press("H")
    assert.is_true(h.wait(function()
      local entry = require("oil").get_cursor_entry()
      return middle_name(view) == "oil://" .. proj .. "/" and entry ~= nil and entry.name == "sub"
    end))
  end)

  it("<CR> on a file opens it in the editing window and keeps the view", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<CR>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == origin_win
    end))
    assert.equals(proj .. "/a.txt", vim.api.nvim_buf_get_name(0))
    assert_view_intact(view)
  end)

  it("<C-s> opens a file in a vertical split in the editing tab", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<C-s>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_tabpage() == origin_tab
    end))
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(origin_tab))
    assert.same(
      { "row", { { "leaf", vim.api.nvim_get_current_win() }, { "leaf", origin_win } } },
      vim.fn.winlayout()
    )
    assert.equals(proj .. "/a.txt", vim.api.nvim_buf_get_name(0))
    assert_view_intact(view)
  end)

  it("<C-h> opens a file in a horizontal split in the editing tab", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<C-h>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_tabpage() == origin_tab
    end))
    assert.equals("col", vim.fn.winlayout()[1])
    assert.equals(proj .. "/a.txt", vim.api.nvim_buf_get_name(0))
    assert_view_intact(view)
  end)

  it("<C-t> opens a file in a new tab", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<C-t>")
    assert.is_true(h.wait(function()
      return #vim.api.nvim_list_tabpages() == 3
    end))
    assert.equals(proj .. "/a.txt", vim.api.nvim_buf_get_name(0))
    assert_view_intact(view)
  end)

  it("files opened later go to the window the previous file opened in", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<C-s>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_tabpage() == origin_tab
    end))
    local split_win = vim.api.nvim_get_current_win()
    vim.cmd("Coil")
    h.cursor_to(view.panes.current, "sub/")
    h.press("L")
    assert.is_true(h.wait(function()
      local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
      return middle_name(view) == "oil://" .. proj .. "/sub/" and vim.b[bufnr].oil_ready == true
    end))
    h.cursor_to(view.panes.current, "inner.txt")
    h.press("<CR>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == split_win
    end))
    assert.equals(proj .. "/sub/inner.txt", vim.api.nvim_buf_get_name(0))
  end)

  it("keeps oil's and Vim's meaning for the keys outside the column view", function()
    local view = h.open_view(proj)
    -- The same oil buffer, now shown in an ordinary window in the editing tab
    vim.api.nvim_set_current_win(origin_win)
    h.open_oil(proj)
    assert.equals(vim.api.nvim_win_get_buf(view.panes.current), vim.api.nvim_get_current_buf())
    assert.truthy(vim.fn.maparg("L", "n", false, true).desc:match("^coil: "))

    -- L: Vim's built-in "cursor to the bottom of the window"
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    h.press("L")
    assert.equals(vim.api.nvim_buf_line_count(0), vim.api.nvim_win_get_cursor(0)[1])

    -- <C-s>: oil's own "open in a vertical split", in this tab
    h.cursor_to(0, "a.txt")
    h.press("<C-s>")
    assert.is_true(h.wait(function()
      return #vim.api.nvim_tabpage_list_wins(origin_tab) == 2
    end))
    assert.equals(origin_tab, vim.api.nvim_get_current_tabpage())
    assert_view_intact(view)
  end)

  ---Run `reload`, wait for oil to finish reloading the middle buffer (its OilEnter), then check
  ---that <C-s> there is coil's wrapper again
  ---@param view coil.View
  ---@param reload fun()
  local function reload_middle(view, reload)
    local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
    local reloaded = false
    -- The side panes' oil buffers fire it too
    vim.api.nvim_create_autocmd("User", {
      pattern = "OilEnter",
      callback = function(args)
        if args.data and args.data.buf == bufnr then
          reloaded = true
          return true
        end
      end,
    })
    reload()
    assert.is_true(h.wait(function()
      return reloaded
    end))
    local m = vim.api.nvim_buf_call(bufnr, function()
      return vim.fn.maparg("<C-s>", "n", false, true)
    end)
    assert.truthy((m.desc or ""):match("^coil: "), vim.inspect(m.desc))
  end

  for _, reload in ipairs({
    {
      name = "<C-l> (refresh)",
      run = function()
        h.press("<C-l>")
      end,
    },
    {
      name = ":edit",
      run = function()
        vim.cmd.edit()
      end,
    },
    {
      name = ":Coil on the same directory",
      run = function()
        vim.cmd("Coil " .. proj)
      end,
    },
  }) do
    it(
      "keeps split keys in the editing tab after " .. reload.name .. " reloads the middle",
      function()
        local view = h.open_view(proj)
        reload_middle(view, reload.run)
        h.cursor_to(view.panes.current, "a.txt")
        h.press("<C-s>")
        assert.is_true(h.wait(function()
          return #vim.api.nvim_tabpage_list_wins(origin_tab) == 2
        end))
        assert_view_intact(view)
      end
    )
  end

  it("opens a visual selection in the editing tab, not in the middle pane", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("V<C-s>")
    assert.is_true(h.wait(function()
      return #vim.api.nvim_tabpage_list_wins(origin_tab) == 2
    end))
    assert.equals(proj .. "/a.txt", vim.api.nvim_buf_get_name(0))
    assert_view_intact(view)
  end)

  it("bounces focus from the parent pane back to the middle", function()
    local view = h.open_view(proj)
    vim.api.nvim_set_current_win(view.panes.parent)
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == view.panes.current
    end))
  end)

  ---Put the middle pane's cursor on `name` and wait for the preview pane to show it
  ---@param view coil.View
  ---@param name string
  ---@param first_line string What the preview shows on its first line
  local function preview_entry(view, name, first_line)
    h.cursor_to(view.panes.current, name)
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    assert.is_true(h.wait(function()
      return h.win_lines(view.panes.preview)[1] == first_line
    end))
  end

  it("<C-p> jumps into the preview pane and back", function()
    local view = h.open_view(proj)
    preview_entry(view, "a.txt", "hello")
    h.press("<C-p>")
    assert.equals(view.panes.preview, vim.api.nvim_get_current_win())
    h.press("<C-p>")
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
  end)

  it("bounces back from a directory preview, which is display-only", function()
    local view = h.open_view(proj)
    preview_entry(view, "sub/", "inner.txt")
    vim.api.nvim_set_current_win(view.panes.preview)
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == view.panes.current
    end))
  end)

  it("L puts the cursor on the first entry's name in a directory the preview showed", function()
    -- An editable column before the name, where oil's default constrain_cursor would stop
    h.setup_oil({ columns = { "icon", "permissions" } })
    local view = h.open_view(proj)
    -- The preview pane renders sub/, so oil doesn't render it again when it moves to the middle
    preview_entry(view, "sub/", "inner.txt")
    h.press("L")
    assert.is_true(h.wait(function()
      return middle_name(view) == "oil://" .. proj .. "/sub/"
    end))
    local line =
      vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(view.panes.current), 0, 1, true)[1]
    assert.same({ 1, line:find("inner.txt", 1, true) - 1 }, vim.api.nvim_win_get_cursor(0))
  end)

  it("q closes the view from the middle or the preview pane", function()
    h.open_view(proj)
    h.press("q")
    assert.is_nil(state.last())

    local view = h.open_view(proj)
    preview_entry(view, "a.txt", "hello")
    h.press("<C-p>")
    h.press("q")
    assert.is_nil(state.last())
  end)

  it("g. keeps the cursor on the same entry", function()
    local view = h.open_view(proj)
    local function cursor_name()
      return (require("oil").get_cursor_entry() or {}).name
    end
    local function shows_dot()
      for _, line in ipairs(h.win_lines(view.panes.current)) do
        if vim.endswith(line, " .dot") then
          return true
        end
      end
      return false
    end

    -- Showing hidden files inserts ../ and .dot above a.txt
    h.cursor_to(view.panes.current, "a.txt")
    h.press("g.")
    assert.is_true(h.wait(function()
      return shows_dot() and cursor_name() == "a.txt"
    end))

    -- Hiding them while on .dot moves to the nearest entry that stays visible
    h.cursor_to(view.panes.current, ".dot")
    h.press("g.")
    assert.is_true(h.wait(function()
      return not shows_dot() and cursor_name() == "a.txt"
    end))
  end)

  it("g. toggles hidden files in every pane", function()
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/" })
    h.press("g.")
    -- oil lists ../ too while hidden files are shown
    h.wait_lines(view.panes.parent, { "../", "proj/", ".rootdot" })
    -- The middle pane is oil's own buffer, so just look for the newly shown file
    assert.is_true(h.wait(function()
      for _, line in ipairs(h.win_lines(view.panes.current)) do
        if vim.endswith(line, " .dot") then
          return true
        end
      end
      return false
    end))
  end)

  it("moves a file edited in the middle pane to the editing window", function()
    local view = h.open_view(proj)
    local dir_buf = vim.api.nvim_win_get_buf(view.panes.current)
    vim.cmd.edit(proj .. "/a.txt")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == origin_win
    end))
    assert.equals(proj .. "/a.txt", vim.api.nvim_buf_get_name(0))
    assert.equals(dir_buf, vim.api.nvim_win_get_buf(view.panes.current))
    assert_view_intact(view)
  end)
end)

describe("oil's keymaps in the column view", function()
  local proj, origin_tab

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    -- Keys moved away from oil's defaults: coil follows them
    h.setup_oil({
      keymaps = {
        ["<C-s>"] = false,
        ["<C-v>"] = { "actions.select", opts = { vertical = true } },
        ["<C-p>"] = false,
        ["gp"] = "actions.preview",
        ["<C-c>"] = false,
        ["gq"] = { "actions.close", mode = "n" },
      },
    })
    coil.setup()
    proj = h.tmpdir()
    h.write(proj .. "/a.txt", { "hello" })
    origin_tab = vim.api.nvim_get_current_tabpage()
  end)

  after_each(function()
    pcall(coil.close)
    h.setup_oil()
  end)

  it("opens in a split of the editing tab with oil's key for it", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<C-v>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_tabpage() == origin_tab
    end))
    assert.equals(2, #vim.api.nvim_tabpage_list_wins(origin_tab))
    assert.equals(3, #vim.api.nvim_tabpage_list_wins(view.tab))
  end)

  it("doesn't take over keys oil no longer maps", function()
    local view = h.open_view(proj)
    local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
    local desc = vim.api.nvim_buf_call(bufnr, function()
      return vim.fn.maparg("<C-s>", "n", false, true).desc
    end)
    assert.is_nil(desc)
  end)

  it("jumps into the preview pane and back with oil's preview key", function()
    local view = h.open_view(proj)
    h.press("gp")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == view.panes.preview
    end))
    h.press("gp")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == view.panes.current
    end))
  end)

  it("closes the view with oil's close key", function()
    h.open_view(proj)
    h.press("gq")
    assert.is_true(h.wait(function()
      return state.last() == nil
    end))
  end)
end)

describe("the quit key", function()
  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup({ keymaps = { quit = "Q" } })
  end)

  after_each(function()
    pcall(coil.close)
    coil.setup()
  end)

  it("quits Neovim, asking about unsaved changes, from the middle or the preview pane", function()
    local view = h.open_view(h.tmpdir())
    local cmd = vim.cmd
    local ran = {}
    ---@diagnostic disable-next-line: assign-type-mismatch
    vim.cmd = function(c)
      if c == "confirm qall" then
        table.insert(ran, c)
      else
        cmd(c)
      end
    end
    h.press("Q")
    vim.wait(50)
    vim.api.nvim_set_current_win(view.panes.preview)
    h.press("Q")
    vim.wait(50)
    vim.cmd = cmd
    assert.same({ "confirm qall", "confirm qall" }, ran)
  end)
end)

describe("the cancel key", function()
  local startup = require("coil.startup")
  local quit_without_cwd

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup({ keymaps = { cancel = "Q" } })
    quit_without_cwd = startup.quit_without_cwd
  end)

  after_each(function()
    startup.quit_without_cwd = quit_without_cwd
    pcall(coil.close)
    coil.setup()
  end)

  it("quits without the cd-on-exit directory, from the middle or the preview pane", function()
    local view = h.open_view(h.tmpdir())
    local calls = 0
    startup.quit_without_cwd = function()
      calls = calls + 1
    end
    h.press("Q")
    vim.wait(50)
    vim.api.nvim_set_current_win(view.panes.preview)
    h.press("Q")
    vim.wait(50)
    assert.equals(2, calls)
  end)
end)

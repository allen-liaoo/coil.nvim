-- With oil-git-status.nvim, the third-party oil extension coil is tested with: its signs show in
-- the side panes too, because they are oil buffers.
local coil = require("coil")
local h = require("tests.helpers")

describe("oil-git-status in the column view", function()
  local root

  ---@param args string[]
  local function git(args)
    local result = vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait()
    assert.equals(0, result.code, result.stderr)
  end

  -- Once for the file (plenary's busted has no setup()): its autocmds are global
  local path = os.getenv("COIL_OIL_GIT_STATUS_PATH")
  assert(path, "COIL_OIL_GIT_STATUS_PATH is not set; run tests inside `nix develop`")
  vim.opt.runtimepath:append(path)
  -- It needs two sign columns, and reads oil's config when it is set up
  h.setup_oil({ win_options = { signcolumn = "yes:2" } })
  require("oil-git-status").setup()

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil({ win_options = { signcolumn = "yes:2" } })
    coil.setup()
    root = h.tmpdir()
    h.write(root .. "/proj/a.txt", { "a" })
    h.write(root .. "/proj/sub/inner.txt", { "inner" })
    h.write(root .. "/other.txt", { "other" })
    git({ "init", "-q" })
    git({ "add", "." })
    git({ "-c", "user.name=coil", "-c", "user.email=coil@test", "commit", "-q", "-m", "init" })
    -- Changed in the parent pane's directory, new in the previewed one
    h.write(root .. "/other.txt", { "changed" })
    h.write(root .. "/proj/sub/new.txt", { "new" })
  end)

  ---The signs oil-git-status put on the line showing `name` in `winid`'s buffer
  ---@param winid integer
  ---@param name string
  ---@return nil|string signs Index and working-tree signs, e.g. " M"
  local function signs(winid, name)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local ns = vim.api.nvim_get_namespaces()["oil-git-status"]
    local lnum = require("coil.oil_bridge").line_of(bufnr, name)
    if not ns or not lnum then
      return nil
    end
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { lnum - 1, 0 }, { lnum - 1, -1 }, {
      details = true,
    })
    -- Index sign first (higher priority)
    table.sort(marks, function(a, b)
      return a[4].priority > b[4].priority
    end)
    local text = ""
    for _, mark in ipairs(marks) do
      text = text .. vim.trim(mark[4].sign_text or "")
    end
    return text
  end

  it("shows git status signs in the parent pane and a directory preview", function()
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "sub/")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    h.wait_lines(view.panes.preview, { "inner.txt", "new.txt" })

    -- other.txt changed in the work tree; new.txt untracked
    assert.is_true(h.wait(function()
      return signs(view.panes.parent, "other.txt") == "M"
    end))
    assert.is_true(h.wait(function()
      return signs(view.panes.preview, "new.txt") == "??"
    end))
    -- With room for them in both side panes, from oil's window options
    assert.equals("yes:2", vim.wo[view.panes.parent].signcolumn)
    assert.equals("yes:2", vim.wo[view.panes.preview].signcolumn)
  end)

  it("keeps the signs in the side panes when oil redraws them", function()
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "sub/")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    h.wait_lines(view.panes.preview, { "inner.txt", "new.txt" })
    assert.is_true(h.wait(function()
      return signs(view.panes.parent, "other.txt") == "M"
        and signs(view.panes.preview, "new.txt") == "??"
    end))
    -- Showing hidden files redraws every oil buffer, which drops their signs
    h.press("g.")
    h.wait_lines(view.panes.parent, { "../", ".git/", "proj/", "other.txt" })
    assert.is_true(h.wait(function()
      return signs(view.panes.parent, "other.txt") == "M"
        and signs(view.panes.preview, "new.txt") == "??"
    end))
    -- Re-showing the same directory lists it again
    require("coil.view.sync").all(view)
    vim.wait(300)
    assert.equals("M", signs(view.panes.parent, "other.txt"))
    h.press("g.")
  end)

  it("drops the sign column when the preview pane goes back to a file", function()
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "sub/")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    h.wait_lines(view.panes.preview, { "inner.txt", "new.txt" })
    h.cursor_to(view.panes.current, "a.txt")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    h.wait_lines(view.panes.preview, { "a" })
    assert.equals("no", vim.wo[view.panes.preview].signcolumn)
  end)
end)

local coil = require("coil")
local h = require("tests.helpers")
local keys = require("coil.view.keys")

describe("clicking in the side panes", function()
  local root, proj

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup()
    root = h.tmpdir()
    proj = root .. "/proj"
    h.write(proj .. "/a.txt", { "hello" })
    h.write(proj .. "/sub/inner.txt", { "inner" })
    h.write(root .. "/other.txt", { "" })
    vim.fn.mkdir(root .. "/zdir")
  end)

  ---A click on `line` of a pane showing its buffer from the top, as getmousepos() reports it
  ---@param winid integer
  ---@param line integer
  local function click(winid, line)
    return { winid = winid, winrow = line, line = line }
  end

  ---Wait until the middle pane shows `url` with the cursor on `name`
  ---@param view coil.View
  ---@param url string
  ---@param name string
  local function wait_middle(view, url, name)
    assert.is_true(h.wait(function()
      local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
      local entry = vim.api.nvim_get_current_win() == view.panes.current
        and require("oil").get_cursor_entry()
      return vim.api.nvim_buf_get_name(bufnr) == url
        and vim.b[bufnr].oil_ready == true
        and entry
        and entry.name == name
    end))
  end

  it("jumps to a directory clicked in the parent pane", function()
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    assert.is_true(keys.jump_to_click(view, click(view.panes.parent, 2)))
    wait_middle(view, "oil://" .. root .. "/", "zdir")
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
  end)

  it("jumps to a file clicked in the parent pane", function()
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    assert.is_true(keys.jump_to_click(view, click(view.panes.parent, 3)))
    wait_middle(view, "oil://" .. root .. "/", "other.txt")
    -- The middle pane moved up a level: the parent pane now highlights that directory's name
    local root_name = vim.fn.fnamemodify(root, ":t")
    assert.is_true(h.wait(function()
      local selected = h.selected_lines(view.panes.parent)
      return #selected == 1 and h.win_lines(view.panes.parent)[selected[1]] == root_name .. "/"
    end))
  end)

  it("jumps into a directory preview's entry", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "sub/")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    h.wait_lines(view.panes.preview, { "inner.txt" })
    assert.is_true(keys.jump_to_click(view, click(view.panes.preview, 1)))
    wait_middle(view, "oil://" .. proj .. "/sub/", "inner.txt")
  end)

  it("ignores clicks that aren't on a listing entry", function()
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    -- Below the last entry: getmousepos() can report the last line for the empty rows
    assert.is_false(keys.jump_to_click(view, { winid = view.panes.parent, winrow = 6, line = 3 }))
    -- In the middle pane, which handles its own clicks
    assert.is_false(keys.jump_to_click(view, click(view.panes.current, 1)))
    -- On a text preview
    h.cursor_to(view.panes.current, "a.txt")
    vim.api.nvim_exec_autocmds("CursorMoved", {})
    h.wait_lines(view.panes.preview, { "hello" })
    assert.is_false(keys.jump_to_click(view, click(view.panes.preview, 1)))
  end)
end)

local coil = require("coil")
local h = require("tests.helpers")
local layout = require("coil.view.layout")
local state = require("coil.view.state")

describe("column view", function()
  local dir

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup()
    dir = h.tmpdir()
    h.write(dir .. "/a.txt", { "a" })
    vim.fn.mkdir(dir .. "/sub")
  end)

  ---@return coil.View
  local function open_view(arg)
    vim.cmd("Coil " .. (arg or ""))
    local view = assert(state.get())
    local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
    assert(h.wait(function()
      return vim.b[bufnr].oil_ready == true
    end))
    return view
  end

  ---@param view coil.View
  ---@return integer[]
  local function widths(view)
    return {
      vim.api.nvim_win_get_width(view.panes.parent),
      vim.api.nvim_win_get_width(view.panes.current),
      vim.api.nvim_win_get_width(view.panes.preview),
    }
  end

  it("opens a new tab with parent, current and preview panes", function()
    local origin_tab = vim.api.nvim_get_current_tabpage()
    local view = open_view(dir)

    assert.equals(2, #vim.api.nvim_list_tabpages())
    assert.not_equals(origin_tab, view.tab)
    assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
    assert.same({
      "row",
      {
        { "leaf", view.panes.parent },
        { "leaf", view.panes.current },
        { "leaf", view.panes.preview },
      },
    }, vim.fn.winlayout())
    assert.equals(
      "oil://" .. dir .. "/",
      vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
    )
    for role, winid in pairs(view.panes) do
      assert.equals(role, vim.w[winid].coil_pane)
      assert.equals(role, state.role_of(winid))
    end
    assert.is_true(vim.wo[view.panes.parent].winfixbuf)
    assert.is_true(vim.wo[view.panes.preview].winfixbuf)
    assert.is_false(vim.wo[view.panes.current].winfixbuf)
  end)

  it("sizes the panes by ratio", function()
    local view = open_view(dir)
    assert.same(layout.compute_widths(vim.o.columns, { 1, 4, 3 }), widths(view))
  end)

  it("re-applies the ratio when the terminal is resized", function()
    local view = open_view(dir)
    vim.o.columns = 120
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.same(layout.compute_widths(120, { 1, 4, 3 }), widths(view))
    vim.o.columns = 80
  end)

  it("uses the configured ratio", function()
    coil.setup({ ratio = { 1, 1, 1 } })
    local view = open_view(dir)
    assert.same(layout.compute_widths(vim.o.columns, { 1, 1, 1 }), widths(view))
  end)

  it("rejects an invalid ratio", function()
    assert.has_error(function()
      coil.setup({ ratio = { 1, 2 } })
    end)
    assert.has_error(function()
      coil.setup({ ratio = { 1, 0, 1 } })
    end)
  end)

  it("opens on the current file's directory with the cursor on that file", function()
    vim.cmd.edit(dir .. "/a.txt")
    open_view()
    assert.is_true(h.wait(function()
      local entry = require("oil").get_cursor_entry()
      return entry ~= nil and entry.name == "a.txt"
    end))
  end)

  it("switches to the open view instead of opening a second one", function()
    local view = open_view(dir)
    vim.cmd.tabprevious()
    vim.cmd("Coil")
    assert.equals(2, #vim.api.nvim_list_tabpages())
    assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
  end)

  it("navigates the open view when given a directory", function()
    local view = open_view(dir)
    vim.cmd("Coil " .. dir .. "/sub")
    assert.is_true(h.wait(function()
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
      return name == "oil://" .. dir .. "/sub/"
    end))
  end)

  it(":CoilClose closes the tab and returns to the origin window", function()
    local origin_win = vim.api.nvim_get_current_win()
    local view = open_view(dir)
    vim.cmd("CoilClose")
    assert.is_nil(state.get())
    assert.is_false(vim.api.nvim_tabpage_is_valid(view.tab))
    assert.equals(1, #vim.api.nvim_list_tabpages())
    assert.equals(origin_win, vim.api.nvim_get_current_win())
  end)

  it("closing any pane closes the whole view", function()
    local view = open_view(dir)
    vim.api.nvim_win_close(view.panes.preview, true)
    assert.is_true(h.wait(function()
      return state.get() == nil
    end))
    assert.is_false(vim.api.nvim_tabpage_is_valid(view.tab))
    assert.equals(1, #vim.api.nvim_list_tabpages())
  end)

  it(
    "keeps focus in the middle pane when side panes update while the tab is in the background",
    function()
      local view = open_view(dir)
      vim.cmd.tabprevious()
      -- What a late preview or parent listing does while the user is in another tab
      local buffer = require("coil.preview.buffer")
      buffer.set_win_buf(view.panes.preview, buffer.scratch({ "late preview" }))
      buffer.set_win_buf(view.panes.parent, buffer.scratch({ "late listing" }))
      vim.api.nvim_set_current_tabpage(view.tab)
      assert.equals(view.panes.current, vim.api.nvim_get_current_win())
    end
  )

  it("forgets the view when its tab is closed directly", function()
    local view = open_view(dir)
    vim.cmd.tabclose()
    assert.is_nil(state.get())
    assert.is_false(vim.api.nvim_tabpage_is_valid(view.tab))
  end)

  it("closes cleanly when the view is the only tab", function()
    open_view(dir)
    vim.cmd.tabonly()
    vim.cmd("CoilClose")
    assert.is_nil(state.get())
    assert.equals(1, #vim.api.nvim_list_tabpages())
    assert.is_nil(vim.w.coil_pane)
  end)
end)

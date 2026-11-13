local coil = require("coil")
local h = require("tests.helpers")
local state = require("coil.view.state")

describe("several directories in tabs", function()
  local root, editing_win

  before_each(function()
    for _ = 1, 5 do
      pcall(coil.close)
    end
    h.reset_tab()
    h.setup_oil()
    coil.setup()
    root = h.tmpdir()
    h.write(root .. "/one/a.txt", { "a" })
    h.write(root .. "/one/sub/inner.txt", { "inner" })
    h.write(root .. "/two/b.txt", { "b" })
    h.write(root .. "/three/c.txt", { "c" })
    editing_win = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    for _ = 1, 5 do
      pcall(coil.close)
    end
  end)

  ---The directory shown in a view's middle pane, once oil has listed it
  ---@param view coil.View
  ---@return string
  local function middle(view)
    local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
    h.wait(function()
      return vim.b[bufnr].oil_ready == true
    end)
    return vim.api.nvim_buf_get_name(bufnr)
  end

  ---The open views, in tab order
  ---@return coil.View[]
  local function views()
    local list = state.all()
    table.sort(list, function(a, b)
      return vim.api.nvim_tabpage_get_number(a.tab) < vim.api.nvim_tabpage_get_number(b.tab)
    end)
    return list
  end

  ---@param ... string Directory names under root
  ---@return string[]
  local function urls(...)
    return vim.tbl_map(function(name)
      return "oil://" .. root .. "/" .. name .. "/"
    end, { ... })
  end

  ---@return string[]
  local function middles()
    return vim.tbl_map(middle, views())
  end

  it(":Coil with several directories opens one tab each, focused on the first", function()
    vim.cmd(string.format("Coil %s/one %s/two %s/three", root, root, root))
    assert.is_true(h.wait(function()
      return vim.deep_equal(urls("one", "two", "three"), middles())
    end))
    for _, view in ipairs(views()) do
      assert.equals(3, #vim.api.nvim_tabpage_list_wins(view.tab))
    end
    local first = views()[1]
    assert.equals(first.tab, vim.api.nvim_get_current_tabpage())
    assert.equals(first.panes.current, vim.api.nvim_get_current_win())
  end)

  it("in a column view, the first directory moves that view and the rest open new tabs", function()
    local view = h.open_view(root .. "/one")
    vim.cmd(string.format("Coil %s/two %s/three", root, root))
    assert.is_true(h.wait(function()
      return vim.deep_equal(urls("two", "three"), middles())
    end))
    assert.equals(view, views()[1])
  end)

  it(":Coil from elsewhere switches to the view used last", function()
    vim.cmd(string.format("Coil %s/one %s/two", root, root))
    local second = views()[2]
    vim.api.nvim_set_current_tabpage(second.tab)
    vim.api.nvim_set_current_win(editing_win)
    vim.cmd("Coil")
    assert.equals(second.tab, vim.api.nvim_get_current_tabpage())
    assert.equals(second.panes.current, vim.api.nvim_get_current_win())
  end)

  it("keys act on the view they're pressed in, even when both show the same directory", function()
    vim.cmd(string.format("Coil %s/one %s/one", root, root))
    local first, second = unpack(views())
    vim.api.nvim_set_current_tabpage(second.tab)
    middle(second)
    h.cursor_to(second.panes.current, "sub/")
    h.press("L")
    assert.is_true(h.wait(function()
      return middle(second) == "oil://" .. root .. "/one/sub/"
    end))
    assert.equals("oil://" .. root .. "/one/", middle(first))
  end)

  it("opens files in the editing window, never in another view's tab", function()
    vim.cmd(string.format("Coil %s/one %s/two", root, root))
    local second = views()[2]
    vim.api.nvim_set_current_tabpage(second.tab)
    middle(second)
    h.cursor_to(second.panes.current, "b.txt")
    h.press("<CR>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_win() == editing_win
    end))
    assert.equals(root .. "/two/b.txt", vim.api.nvim_buf_get_name(0))
  end)

  it(":CoilClose closes only the current tab's view", function()
    vim.cmd(string.format("Coil %s/one %s/two", root, root))
    local first, second = unpack(views())
    vim.api.nvim_set_current_tabpage(second.tab)
    vim.cmd("CoilClose")
    assert.is_false(state.is_open(second))
    assert.is_true(state.is_open(first))
    assert.equals(3, #vim.api.nvim_tabpage_list_wins(first.tab))
    -- From a tab that isn't a view: the one used most recently
    vim.cmd("CoilClose")
    assert.is_nil(state.last())
  end)
end)

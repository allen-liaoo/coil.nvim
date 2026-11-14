local coil = require("coil")
local h = require("tests.helpers")
local state = require("coil.view.state")

describe("commands typed in the middle pane", function()
  local dir, origin_win, view

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup()
    dir = h.tmpdir()
    h.write(dir .. "/a.txt", { "a" })
    vim.fn.mkdir(dir .. "/sub")
    origin_win = vim.api.nvim_get_current_win()
    view = h.open_view(dir)
  end)

  ---Type `cmd` on the command line, as a person would (vim.cmd never leaves a command line)
  ---@param cmd string
  local function type_cmd(cmd)
    h.press(":" .. cmd .. "<CR>")
  end

  ---@param win integer
  ---@return string
  local function name_in(win)
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
  end

  ---Wait until the editing window shows `name`, then check the column view didn't move
  ---@param name string
  local function assert_opened_in_editing_window(name)
    assert.is_true(h.wait(function()
      return name_in(origin_win) == name
    end))
    assert.equals(origin_win, vim.api.nvim_get_current_win())
    assert.equals("oil://" .. dir .. "/", name_in(view.panes.current))
    assert.equals(3, #vim.api.nvim_tabpage_list_wins(view.tab))
  end

  it("open other directories in plain oil in the editing window", function()
    type_cmd("Oil " .. dir .. "/sub")
    assert_opened_in_editing_window("oil://" .. dir .. "/sub/")
  end)

  it("open the middle pane's own directory there too", function()
    type_cmd("Oil " .. dir)
    assert_opened_in_editing_window("oil://" .. dir .. "/")
    vim.api.nvim_set_current_win(view.panes.current)
    vim.api.nvim_win_set_buf(origin_win, vim.api.nvim_create_buf(true, false))
    -- An oil URL: the tests set oil up without default_file_explorer, so oil leaves plain
    -- directory paths alone
    type_cmd("edit oil://" .. dir .. "/")
    assert_opened_in_editing_window("oil://" .. dir .. "/")
  end)

  it("open files in the editing window", function()
    type_cmd("edit " .. dir .. "/a.txt")
    assert_opened_in_editing_window(dir .. "/a.txt")
  end)

  it(":Oil on its own opens the parent, with the cursor on the directory", function()
    type_cmd("Oil")
    assert_opened_in_editing_window("oil://" .. vim.fs.dirname(dir) .. "/")
    assert.is_true(h.wait(function()
      local entry = require("oil").get_cursor_entry()
      return entry ~= nil and entry.name == vim.fs.basename(dir)
    end))
  end)

  it("expand % where they were typed", function()
    type_cmd("edit %")
    assert_opened_in_editing_window("oil://" .. dir .. "/")
  end)

  it("split the editing window, not the column view", function()
    local editing_tab = vim.api.nvim_win_get_tabpage(origin_win)
    type_cmd("vsplit")
    assert.is_true(h.wait(function()
      return #vim.api.nvim_tabpage_list_wins(editing_tab) == 2
    end))
    assert.equals(editing_tab, vim.api.nvim_get_current_tabpage())
    assert.equals("oil://" .. dir .. "/", name_in(vim.api.nvim_get_current_win()))
    assert.equals(3, #vim.api.nvim_tabpage_list_wins(view.tab))
  end)

  it("stay in the history", function()
    type_cmd("edit " .. dir .. "/a.txt")
    assert_opened_in_editing_window(dir .. "/a.txt")
    assert.equals("edit " .. dir .. "/a.txt", vim.fn.histget(":", -1))
  end)

  it("that open nothing run in the middle pane", function()
    type_cmd("edit")
    type_cmd("setlocal number")
    vim.wait(50)
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
    assert.equals("oil://" .. dir .. "/", name_in(view.panes.current))
    assert.is_true(vim.wo[view.panes.current].number)
  end)

  it(":Coil moves the column view", function()
    type_cmd("Coil " .. dir .. "/sub")
    assert.is_true(h.wait(function()
      return name_in(view.panes.current) == "oil://" .. dir .. "/sub/"
    end))
    assert.equals(view.panes.current, vim.api.nvim_get_current_win())
    assert.truthy(state.get())
  end)

  it("typed elsewhere run as usual", function()
    vim.api.nvim_set_current_win(origin_win)
    type_cmd("edit " .. dir .. "/a.txt")
    assert.equals(dir .. "/a.txt", name_in(origin_win))
    assert.equals("oil://" .. dir .. "/", name_in(view.panes.current))
  end)
end)

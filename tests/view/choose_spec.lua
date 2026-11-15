local choose = require("coil.view.choose")
local coil = require("coil")
local h = require("tests.helpers")

describe("choosing files (g:coil_chooser_file)", function()
  local root, chooser_file, quits, quit

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup()
    root = h.tmpdir()
    h.write(root .. "/proj/a.txt", { "a" })
    h.write(root .. "/proj/b.txt", { "b" })
    h.write(root .. "/proj/sub/inner.txt", { "inner" })
    chooser_file = root .. "/chosen"
    vim.g.coil_chooser_file = chooser_file
    quits = 0
    quit = choose.quit
    choose.quit = function()
      quits = quits + 1
    end
  end)

  after_each(function()
    vim.g.coil_chooser_file = nil
    choose.quit = quit
    pcall(coil.close)
  end)

  ---@return nil|string[]
  local function chosen()
    if vim.fn.filereadable(chooser_file) == 0 then
      return nil
    end
    return vim.fn.readfile(chooser_file)
  end

  ---@param view coil.View
  ---@return string
  local function middle_name(view)
    return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
  end

  for _, key in ipairs({ "<CR>", "<C-s>" }) do
    it(key .. " writes the file under the cursor and quits", function()
      local view = h.open_view(root .. "/proj")
      h.cursor_to(view.panes.current, "b.txt")
      h.press(key)
      assert.is_true(h.wait(function()
        return quits == 1
      end))
      assert.same({ root .. "/proj/b.txt" }, chosen())
      -- Nothing was opened
      assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
      assert.equals(0, vim.fn.bufloaded(root .. "/proj/b.txt"))
    end)
  end

  it("L doesn't choose a file", function()
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "b.txt")
    h.press("L")
    vim.wait(100)
    assert.equals(0, quits)
    assert.is_nil(chosen())
  end)

  it("enters a directory under the cursor", function()
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "sub/")
    h.press("<CR>")
    assert.is_true(h.wait(function()
      return middle_name(view) == "oil://" .. root .. "/proj/sub/"
    end))
    assert.equals(0, quits)
    assert.is_nil(chosen())
  end)

  it("writes every entry of a visual selection, directories included", function()
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "sub/")
    h.press("VG<CR>")
    assert.is_true(h.wait(function()
      return quits == 1
    end))
    assert.same({ root .. "/proj/sub", root .. "/proj/a.txt", root .. "/proj/b.txt" }, chosen())
    assert.equals("n", vim.fn.mode())
  end)

  it("opens files as usual without a chooser file", function()
    vim.g.coil_chooser_file = nil
    local view = h.open_view(root .. "/proj")
    h.cursor_to(view.panes.current, "a.txt")
    h.press("<CR>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_buf_get_name(0) == root .. "/proj/a.txt"
    end))
    assert.equals(0, quits)
  end)
end)

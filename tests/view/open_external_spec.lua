local coil = require("coil")
local h = require("tests.helpers")
local state = require("coil.view.state")

describe("open_external", function()
  local proj, origin_tab, opened, ui_open

  before_each(function()
    pcall(coil.close)
    h.reset_tab()
    h.setup_oil()
    coil.setup({ open_external = true })
    proj = h.tmpdir() .. "/proj"
    h.write(proj .. "/notes.txt", { "hello" })
    -- Not text by its name, and by its contents
    h.write(proj .. "/photo.png", { "not really a png" })
    h.write_bytes(proj .. "/data.bin", "\0\1\2")
    origin_tab = vim.api.nvim_get_current_tabpage()
    opened = {}
    ui_open = vim.ui.open
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.open = function(path)
      table.insert(opened, path)
      return nil, nil
    end
  end)

  after_each(function()
    vim.ui.open = ui_open
    pcall(coil.close)
    coil.setup()
  end)

  ---@param path string
  ---@return boolean
  local function has_buffer(path)
    return vim.fn.bufnr(path) ~= -1
  end

  it("opens files that aren't text in another program", function()
    local view = h.open_view(proj)
    for _, case in ipairs({ { "photo.png", "L" }, { "data.bin", "<CR>" } }) do
      local name, key = case[1], case[2]
      h.cursor_to(view.panes.current, name)
      h.press(key)
      assert.is_true(h.wait(function()
        return opened[#opened] == proj .. "/" .. name
      end))
      -- Not in the editor, and no buffer left behind
      assert.equals(view.tab, vim.api.nvim_get_current_tabpage())
      assert.is_false(has_buffer(proj .. "/" .. name))
    end
    assert.is_true(state.is_open(view))
  end)

  it("opens text files in the editor", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "notes.txt")
    h.press("L")
    assert.is_true(h.wait(function()
      return vim.api.nvim_get_current_tabpage() == origin_tab
    end))
    assert.equals(proj .. "/notes.txt", vim.api.nvim_buf_get_name(0))
    assert.same({}, opened)
  end)

  it("still opens anything in the editor with the split and tab keys", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "photo.png")
    h.press("<C-s>")
    assert.is_true(h.wait(function()
      return vim.api.nvim_buf_get_name(0) == proj .. "/photo.png"
    end))
    assert.same({}, opened)
  end)

  it("sorts a visual selection: other programs for some files, the editor for the rest", function()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "data.bin")
    -- data.bin, notes.txt, photo.png
    h.press("VG<CR>")
    assert.is_true(h.wait(function()
      return #opened == 2 and has_buffer(proj .. "/notes.txt")
    end))
    table.sort(opened)
    assert.same({ proj .. "/data.bin", proj .. "/photo.png" }, opened)
  end)

  it("is off by default, except in standalone mode", function()
    coil.setup()
    local view = h.open_view(proj)
    h.cursor_to(view.panes.current, "photo.png")
    h.press("L")
    assert.is_true(h.wait(function()
      return vim.api.nvim_buf_get_name(0) == proj .. "/photo.png"
    end))
    assert.same({}, opened)

    vim.g.coil_standalone = 1
    coil.setup()
    vim.g.coil_standalone = nil
    assert.is_true(require("coil.config").get().open_external)
  end)
end)

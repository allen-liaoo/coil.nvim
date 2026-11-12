local coil = require("coil")
local h = require("tests.helpers")
local state = require("coil.view.state")

describe("pane sync", function()
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
    h.write(root .. "/.rootdot", { "" })
    h.write(root .. "/.hidden_dir/f.txt", { "" })
    vim.fn.mkdir(root .. "/zdir")
  end)

  ---Move the middle pane's cursor and fire CursorMoved as the UI would
  ---@param view coil.View
  ---@param text string
  local function move_to(view, text)
    h.cursor_to(view.panes.current, text)
    vim.api.nvim_exec_autocmds("CursorMoved", {})
  end

  it("lists the parent directory and highlights the current one", function()
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    assert.same({ 1 }, h.selected_lines(view.panes.parent))
    assert.equals(1, vim.api.nvim_win_get_cursor(view.panes.parent)[1])
    assert.is_false(vim.bo[vim.api.nvim_win_get_buf(view.panes.parent)].modifiable)
  end)

  it("lists the current directory in the parent pane even when it is hidden", function()
    local view = h.open_view(root .. "/.hidden_dir")
    h.wait_lines(view.panes.parent, { ".hidden_dir/", "proj/", "zdir/", "other.txt" })
    assert.same({ 1 }, h.selected_lines(view.panes.parent))
  end)

  it("previews the entry under the middle pane's cursor", function()
    local view = h.open_view(proj)
    move_to(view, "a.txt")
    h.wait_lines(view.panes.preview, { "hello" })
    move_to(view, "sub/")
    h.wait_lines(view.panes.preview, { "inner.txt" })
  end)

  it("follows the middle pane into a subdirectory", function()
    local view = h.open_view(proj)
    require("coil.oil_bridge").open_dir("oil://" .. proj .. "/sub/")
    h.wait_lines(view.panes.parent, { "sub/", "a.txt" })
    assert.same({ 1 }, h.selected_lines(view.panes.parent))
    h.wait_lines(view.panes.preview, { "inner" })
  end)

  it("follows oil's own parent navigation", function()
    local view = h.open_view(proj .. "/sub")
    require("oil").open()
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    -- oil puts the cursor back on the directory we came from
    h.wait_lines(view.panes.preview, { "inner.txt" })
  end)

  it("leaves the parent pane empty at the root", function()
    local view = h.open_view(proj)
    require("coil.oil_bridge").open_dir("oil:///")
    h.wait_lines(view.panes.parent, { "" })
    assert.same({}, h.selected_lines(view.panes.parent))
  end)

  it("refreshes the panes after oil writes changes", function()
    local view = h.open_view(proj)
    move_to(view, "sub/")
    h.wait_lines(view.panes.preview, { "inner.txt" })

    local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { "sub/new.txt" })
    local saved = false
    require("oil").save({ confirm = false }, function(err)
      saved = err or true
    end)
    assert(h.wait(function()
      return saved ~= false
    end))
    assert.is_true(saved)
    h.wait_lines(view.panes.preview, { "inner.txt", "new.txt" })
  end)

  it("stops syncing once the view is closed", function()
    local view = h.open_view(proj)
    coil.close()
    assert.is_nil(state.get())
    -- The view's autocmd group (sync's autocmds included) is deleted outright
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = view.group }))
  end)
end)

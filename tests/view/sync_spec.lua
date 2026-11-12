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

  it("greys out a hidden current directory in the parent pane", function()
    local view = h.open_view(root .. "/.hidden_dir")
    h.wait_lines(view.panes.parent, { ".hidden_dir/", "proj/", "zdir/", "other.txt" })
    local hl = h.line_highlights(view.panes.parent)
    assert.equals("CoilDirHidden", hl[".hidden_dir/"])
    assert.equals("CoilDir", hl["proj/"])
  end)

  ---@param winid integer
  ---@return string
  local function winbar(winid)
    return vim.api.nvim_get_option_value("winbar", { scope = "local", win = winid })
  end

  it("titles each pane with its path when winbar is on", function()
    coil.setup({ winbar = true })
    local view = h.open_view(proj)
    move_to(view, "a.txt")
    h.wait_lines(view.panes.preview, { "hello" })
    assert.equals(" " .. vim.fn.fnamemodify(proj .. "/", ":~"), winbar(view.panes.current))
    assert.equals(" " .. vim.fn.fnamemodify(root .. "/", ":~"), winbar(view.panes.parent))
    assert.equals(" a.txt", winbar(view.panes.preview))

    move_to(view, "sub/")
    h.wait_lines(view.panes.preview, { "inner.txt" })
    assert.equals(" sub/", winbar(view.panes.preview))

    -- At the root the parent title is blank but kept, so the panes' rows stay aligned
    require("coil.oil_bridge").open_dir("oil:///")
    h.wait_lines(view.panes.parent, { "" })
    assert.equals(" ", winbar(view.panes.parent))
    assert.equals(" /", winbar(view.panes.current))
  end)

  it("keeps side pane options and titles after their buffers change", function()
    coil.setup({ winbar = true })
    -- A config like the user's, with line numbers on everywhere
    vim.o.number = true
    local view = h.open_view(proj)
    move_to(view, "a.txt")
    h.wait_lines(view.panes.preview, { "hello" })
    move_to(view, "sub/")
    h.wait_lines(view.panes.preview, { "inner.txt" })
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    vim.o.number = false

    for _, winid in ipairs({ view.panes.parent, view.panes.preview }) do
      assert.is_false(vim.wo[winid].number)
      assert.is_false(vim.wo[winid].wrap)
      assert.equals("no", vim.wo[winid].signcolumn)
      assert.is_true(vim.wo[winid].winfixbuf)
    end
    assert.equals(" " .. vim.fn.fnamemodify(root .. "/", ":~"), winbar(view.panes.parent))
    assert.equals(" sub/", winbar(view.panes.preview))
  end)

  it("escapes % in titles", function()
    coil.setup({ winbar = true })
    vim.fn.mkdir(root .. "/50%")
    -- Through the API: on the :Coil command line, % expands to the current file (like :edit)
    coil.open(root .. "/50%")
    local view = assert(state.get())
    assert.is_true(h.wait(function()
      return winbar(view.panes.current):find("50%%", 1, true) ~= nil
    end))
  end)

  it("shows no pane titles by default", function()
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    for _, winid in pairs(view.panes) do
      assert.equals("", winbar(winid))
    end
  end)

  it("names the tab after the current directory", function()
    local view = h.open_view(proj)
    assert.equals(vim.fn.fnamemodify(proj .. "/", ":~"), vim.t[view.tab].tabname)
    require("coil.oil_bridge").open_dir("oil://" .. proj .. "/sub/")
    assert.is_true(h.wait(function()
      return vim.t[view.tab].tabname == vim.fn.fnamemodify(proj .. "/sub/", ":~")
    end))
    -- Other tabs are left alone
    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      if tab ~= view.tab then
        assert.is_nil(vim.t[tab].tabname)
      end
    end
  end)

  it("leaves the tab name alone when tab_title is off", function()
    coil.setup({ tab_title = false })
    local view = h.open_view(proj)
    h.wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    assert.is_nil(vim.t[view.tab].tabname)
  end)
end)

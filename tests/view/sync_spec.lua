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
    vim.fn.mkdir(root .. "/zdir")
  end)

  ---@param dir string
  ---@return coil.View
  local function open_view(dir)
    vim.cmd("Coil " .. dir)
    local view = assert(state.get())
    local bufnr = vim.api.nvim_win_get_buf(view.panes.current)
    assert(h.wait(function()
      return vim.b[bufnr].oil_ready == true
    end))
    return view
  end

  ---@param winid integer
  ---@param expected string[]
  local function wait_lines(winid, expected)
    local ok = h.wait(function()
      return vim.deep_equal(expected, h.win_lines(winid))
    end)
    assert.same(expected, h.win_lines(winid))
    return ok
  end

  ---Line numbers (1-based) carrying the parent-selection highlight in a window's buffer
  ---@param winid integer
  ---@return integer[]
  local function selected_lines(winid)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local ns = vim.api.nvim_create_namespace("coil_listing")
    local ret = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      if mark[4].line_hl_group == "CoilParentSelected" then
        table.insert(ret, mark[2] + 1)
      end
    end
    return ret
  end

  ---Move the middle pane's cursor and fire CursorMoved as the UI would
  ---@param view coil.View
  ---@param text string
  local function move_to(view, text)
    h.cursor_to(view.panes.current, text)
    vim.api.nvim_exec_autocmds("CursorMoved", {})
  end

  it("lists the parent directory and highlights the current one", function()
    local view = open_view(proj)
    wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    assert.same({ 1 }, selected_lines(view.panes.parent))
    assert.equals(1, vim.api.nvim_win_get_cursor(view.panes.parent)[1])
    assert.is_false(vim.bo[vim.api.nvim_win_get_buf(view.panes.parent)].modifiable)
  end)

  it("previews the entry under the middle pane's cursor", function()
    local view = open_view(proj)
    move_to(view, "a.txt")
    wait_lines(view.panes.preview, { "hello" })
    move_to(view, "sub/")
    wait_lines(view.panes.preview, { "inner.txt" })
  end)

  it("follows the middle pane into a subdirectory", function()
    local view = open_view(proj)
    require("coil.oil_bridge").open_dir("oil://" .. proj .. "/sub/")
    wait_lines(view.panes.parent, { "sub/", "a.txt" })
    assert.same({ 1 }, selected_lines(view.panes.parent))
    wait_lines(view.panes.preview, { "inner" })
  end)

  it("follows oil's own parent navigation", function()
    local view = open_view(proj .. "/sub")
    require("oil").open()
    wait_lines(view.panes.parent, { "proj/", "zdir/", "other.txt" })
    -- oil puts the cursor back on the directory we came from
    wait_lines(view.panes.preview, { "inner.txt" })
  end)

  it("leaves the parent pane empty at the root", function()
    local view = open_view(proj)
    require("coil.oil_bridge").open_dir("oil:///")
    wait_lines(view.panes.parent, { "" })
    assert.same({}, selected_lines(view.panes.parent))
  end)

  it("refreshes the panes after oil writes changes", function()
    local view = open_view(proj)
    move_to(view, "sub/")
    wait_lines(view.panes.preview, { "inner.txt" })

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
    wait_lines(view.panes.preview, { "inner.txt", "new.txt" })
  end)

  it("stops syncing once the view is closed", function()
    local view = open_view(proj)
    coil.close()
    assert.is_nil(state.get())
    -- The view's autocmd group (sync's autocmds included) is deleted outright
    assert.is_false(pcall(vim.api.nvim_get_autocmds, { group = view.group }))
  end)
end)

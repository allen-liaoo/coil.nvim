local h = require("tests.helpers")
local preview = require("coil.preview")

describe("preview.show", function()
  local dir, win

  before_each(function()
    h.reset_tab()
    preview.setup()
    dir = h.tmpdir()
    win = vim.api.nvim_get_current_win()
  end)

  ---@param name string
  ---@return coil.PreviewTarget
  local function target(name)
    local path = dir .. "/" .. name
    return { name = name, url = path, path = path, is_dir = false }
  end

  it("shows text in a read-only scratch buffer without setting filetype", function()
    h.write(dir .. "/a.lua", { "local x = 1", "return x" })
    preview.show(win, target("a.lua"))
    local bufnr = vim.api.nvim_win_get_buf(win)
    assert.same({ "local x = 1", "return x" }, h.win_lines(win))
    assert.is_false(vim.bo[bufnr].modifiable)
    assert.equals("nofile", vim.bo[bufnr].buftype)
    assert.equals("", vim.bo[bufnr].filetype)
  end)

  it("reads at most max_lines lines", function()
    h.write(dir .. "/long.txt", { "1", "2", "3", "4", "5" })
    preview.show(win, target("long.txt"), { max_lines = 2 })
    assert.same({ "1", "2" }, h.win_lines(win))
  end)

  it("shows a card for binary files: name, rule, aligned rows and a note", function()
    h.write_bytes(dir .. "/blob.dat", "ab\0cd")
    preview.show(win, target("blob.dat"))
    local lines = h.win_lines(win)
    assert.equals("blob.dat", lines[1])
    -- A rule as wide as the widest row, up to 60 columns
    assert.equals(string.rep("─", math.min(vim.fn.strdisplaywidth(lines[7]), 60)), lines[2])
    assert.equals("Kind         Binary file", lines[3])
    assert.equals("Size         5 (5 bytes)", lines[4])
    assert.truthy(lines[5]:match("^Modified     %d%d%d%d%-%d%d%-%d%d %d%d:%d%d$"))
    assert.truthy(lines[6]:match("^Permissions  [rwx-]+$"))
    assert.equals("Location     " .. vim.fn.fnamemodify(dir .. "/blob.dat", ":~"), lines[7])
    assert.equals("", lines[8])
    assert.equals("No text preview for binary files.", lines[9])
    -- Its own filetype, so markdown plugins leave it alone
    assert.equals("coil_card", vim.bo[vim.api.nvim_win_get_buf(win)].filetype)
  end)

  it("highlights the card itself", function()
    h.write_bytes(dir .. "/blob.dat", "ab\0cd")
    preview.show(win, target("blob.dat"))
    local bufnr = vim.api.nvim_win_get_buf(win)
    local ns = vim.api.nvim_get_namespaces()["coil_card"]
    local found = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      local row, col, details = mark[2], mark[3], mark[4]
      local text = vim.api.nvim_buf_get_text(bufnr, row, col, row, details.end_col, {})[1]
      found[details.hl_group .. ":" .. text] = true
    end
    assert.is_true(found["CoilCardTitle:blob.dat"])
    assert.is_true(found["CoilCardLabel:Kind"])
    assert.is_true(found["CoilCardValue:Binary file"])
    assert.is_true(found["CoilCardNote:No text preview for binary files."])
    assert.equals(1, vim.fn.hlexists("CoilCardRule"))
  end)

  it("wipes the previous preview buffer", function()
    h.write(dir .. "/a.txt", { "a" })
    h.write(dir .. "/b.txt", { "b" })
    preview.show(win, target("a.txt"))
    local first = vim.api.nvim_win_get_buf(win)
    preview.show(win, target("b.txt"))
    assert.is_false(vim.api.nvim_buf_is_valid(first))
  end)

  it("works in windows with winfixbuf set", function()
    h.write(dir .. "/a.txt", { "a" })
    vim.api.nvim_set_option_value("winfixbuf", true, { scope = "local", win = win })
    preview.show(win, target("a.txt"))
    assert.same({ "a" }, h.win_lines(win))
    assert.is_true(vim.wo[win].winfixbuf)
  end)

  it("lists directories through the injected lister", function()
    local function list_dir(_, cb)
      cb(nil, {
        { name = "sub", type = "directory", is_dir = true },
        { name = "a.txt", type = "file", is_dir = false },
      })
    end
    preview.show(win, { name = "d", url = "oil:///d/", is_dir = true }, { list_dir = list_dir })
    assert.same({ "sub/", "a.txt" }, h.win_lines(win))
  end)

  it("drops directory results that arrive after a newer preview", function()
    local pending
    local function slow_list_dir(_, cb)
      pending = cb
    end
    h.write(dir .. "/a.txt", { "newer" })
    preview.show(
      win,
      { name = "d", url = "oil:///d/", is_dir = true },
      { list_dir = slow_list_dir }
    )
    preview.show(win, target("a.txt"))
    pending(nil, { { name = "stale", type = "file", is_dir = false } })
    assert.same({ "newer" }, h.win_lines(win))
  end)

  it("explains entries that are not saved yet", function()
    preview.show(win, { name = "new", url = "oil:///new", is_dir = false, unsaved = true })
    assert.equals("Not saved yet", h.win_lines(win)[1])
  end)

  it("greys out hidden entries in directory listings", function()
    local function list_dir(_, cb)
      cb(nil, {
        { name = ".git", type = "directory", is_dir = true, is_hidden = true },
        { name = "sub", type = "directory", is_dir = true },
        { name = ".dot", type = "file", is_dir = false, is_hidden = true },
        { name = "a.txt", type = "file", is_dir = false },
      })
    end
    preview.show(win, { name = "d", url = "oil:///d/", is_dir = true }, { list_dir = list_dir })
    assert.same({
      [".git/"] = "CoilDirHidden",
      ["sub/"] = "CoilDir",
      [".dot"] = "CoilFileHidden",
    }, h.line_highlights(win))
  end)
end)

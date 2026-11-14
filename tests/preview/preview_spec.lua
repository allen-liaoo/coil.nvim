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

  it("says when a text file is empty", function()
    h.write_bytes(dir .. "/empty.txt", "")
    preview.show(win, target("empty.txt"))
    assert.same({ "(empty file)" }, h.win_lines(win))
    -- A file with one empty line isn't empty
    h.write(dir .. "/blank.txt", { "" })
    preview.show(win, target("blank.txt"))
    assert.same({ "" }, h.win_lines(win))
  end)

  it("reads at most max_lines lines", function()
    h.write(dir .. "/long.txt", { "1", "2", "3", "4", "5" })
    preview.show(win, target("long.txt"), { max_lines = 2 })
    assert.same({ "1", "2" }, h.win_lines(win))
  end)

  it("says why files without text or a picture have no preview", function()
    h.write_bytes(dir .. "/blob.dat", "ab\0cd")
    h.write(dir .. "/song.mp3", { "" })
    h.write(dir .. "/a.zip", { "" })
    h.write(dir .. "/big.txt", { "too big" })
    vim.fn.system({ "mkfifo", dir .. "/pipe" })
    local cases = {
      { target("blob.dat"), "No preview for binary files" },
      { target("song.mp3"), "No preview for audio files" },
      { target("a.zip"), "No preview for archives" },
      { target("big.txt"), "Larger than 4, so the text isn't shown", { max_bytes = 4 } },
      { target("pipe"), "Not a regular file (fifo)" },
      { target("missing.txt"), "^Cannot read this file: " },
      {
        { name = "r.txt", url = "oil-ssh://host/r.txt", is_dir = false },
        "No preview: coil can't download files from here",
      },
    }
    for _, case in ipairs(cases) do
      preview.show(win, case[1], case[3])
      local lines = h.win_lines(win)
      assert.equals(1, #lines, case[2])
      local pattern = case[2]:sub(1, 1) == "^" and case[2] or "^" .. vim.pesc(case[2]) .. "$"
      assert.truthy(lines[1]:find(pattern), lines[1])
      -- Dimmed
      local bufnr = vim.api.nvim_win_get_buf(win)
      local ns = vim.api.nvim_get_namespaces()["coil_preview"]
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
      assert.equals("Comment", marks[1] and marks[1][4].line_hl_group)
    end
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

local h = require("tests.helpers")

describe(":help coil", function()
  it("builds help tags, and every link names one of them or one of Neovim's", function()
    local dir = h.tmpdir()
    vim.fn.mkdir(dir .. "/doc", "p")
    vim.fn.writefile(vim.fn.readfile("doc/coil.txt"), dir .. "/doc/coil.txt")
    -- Fails on duplicate tags
    vim.cmd.helptags(vim.fn.fnameescape(dir .. "/doc"))

    local tags = {}
    for _, line in ipairs(vim.fn.readfile(dir .. "/doc/tags")) do
      tags[line:match("^[^\t]+")] = true
    end
    for _, tag in ipairs({ "coil", "coil-keys", "coil-options", ":Coil", "coil-standalone" }) do
      assert.is_true(tags[tag], tag)
    end
    local text = table.concat(vim.fn.readfile("doc/coil.txt"), "\n")
    for link in text:gmatch("|([^|%s]+)|") do
      assert.is_true(tags[link] or #vim.fn.getcompletion(link, "help") > 0, link)
    end
  end)
end)

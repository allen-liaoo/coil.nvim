local config = require("coil.config")

describe("config", function()
  local notifications

  before_each(function()
    notifications = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
    config.setup()
  end)

  it("uses the defaults without options", function()
    assert.same({ 1, 4, 3 }, config.get().ratio)
    assert.equals(30, config.get().debounce_ms)
    assert.is_false(config.get().winbar)
    assert.is_true(config.get().tab_title)
    assert.equals("actions.go_in", config.get().keymaps.L)
  end)

  it("merges keymaps, keeping the ones not mentioned", function()
    local fn = function() end
    config.setup({ keymaps = { l = "actions.go_in", q = false, gf = fn } })
    local keymaps = config.get().keymaps
    assert.equals("actions.go_in", keymaps.l)
    assert.equals("actions.go_in", keymaps.L)
    assert.is_false(keymaps.q)
    assert.equals(fn, keymaps.gf)
    assert.equals("actions.go_out", keymaps.H)
  end)

  it("rejects options of the wrong type with a clear message", function()
    for _, case in ipairs({
      { opts = { ratio = { 1, 2 } }, match = "ratio" },
      { opts = { ratio = { 1, 0, 1 } }, match = "ratio" },
      { opts = { debounce_ms = -1 }, match = "debounce_ms" },
      { opts = { debounce_ms = "fast" }, match = "debounce_ms" },
      { opts = { winbar = "yes" }, match = "winbar" },
      { opts = { tab_title = 1 }, match = "tab_title" },
      { opts = { open_external = "yes" }, match = "open_external" },
      { opts = { edit_here = 1 }, match = "edit_here" },
      { opts = { preview = false }, match = "preview" },
      { opts = { keymaps = { L = 1 } }, match = 'keymaps["L"]' },
      { opts = { keymaps = { L = "actions.go_inn" } }, match = "cancel, close, down, go_in" },
      { opts = { keymaps = { L = { "actions.go_in", mode = "i" } } }, match = "mode must be" },
      { opts = { keymaps = { L = { "actions.go_in", opts = 1 } } }, match = "opts must be" },
      { opts = { keymaps = { L = { desc = "no rhs" } } }, match = 'keymaps["L"]' },
      { opts = { keymaps = { "actions.go_in" } }, match = "keymaps must have keys" },
    }) do
      local ok, err = pcall(config.setup, case.opts)
      assert.is_false(ok, vim.inspect(case.opts))
      assert.truthy(err:find(case.match, 1, true), err)
    end
  end)

  it("keeps the previous config when setup fails", function()
    config.setup({ ratio = { 2, 2, 2 } })
    pcall(config.setup, { ratio = "wide" })
    assert.same({ 2, 2, 2 }, config.get().ratio)
  end)

  it("warns about unknown options instead of failing", function()
    config.setup({ ratoi = { 1, 1, 1 }, winbr = true })
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.WARN, notifications[1].level)
    assert.truthy(notifications[1].msg:find("ratoi, winbr", 1, true))
  end)

  describe("standalone mode", function()
    after_each(function()
      vim.g.coil_standalone = nil
      config.setup()
    end)

    it("is off unless g:coil_standalone is set", function()
      assert.is_false(config.standalone())
      assert.is_false(require("coil").standalone())
      for _, value in ipairs({ 0, false }) do
        vim.g.coil_standalone = value
        assert.is_false(config.standalone())
      end
      for _, value in ipairs({ 1, true }) do
        vim.g.coil_standalone = value
        assert.is_true(config.standalone())
      end
    end)

    it("ignores the standalone options otherwise", function()
      config.setup({ standalone = { ratio = { 1, 1, 1 } } })
      assert.same({ 1, 4, 3 }, config.get().ratio)
      assert.equals("actions.close", config.get().keymaps.q)
      assert.is_nil(config.get().keymaps.Q)
    end)

    it("merges the standalone options over the rest", function()
      vim.g.coil_standalone = 1
      config.setup({
        winbar = true,
        keymaps = { l = "actions.go_in" },
        standalone = { ratio = { 1, 1, 1 }, keymaps = { h = "actions.go_out" } },
      })
      local c = config.get()
      assert.same({ 1, 1, 1 }, c.ratio)
      assert.is_true(c.winbar)
      -- From the options, from the standalone options, and the standalone defaults
      assert.same({
        L = "actions.go_in",
        ["<Right>"] = "actions.go_in",
        H = "actions.go_out",
        ["<Left>"] = "actions.go_out",
        j = "actions.down",
        ["<Down>"] = "actions.down",
        k = "actions.up",
        ["<Up>"] = "actions.up",
        l = "actions.go_in",
        h = "actions.go_out",
        q = "actions.quit",
        Q = "actions.cancel",
      }, c.keymaps)
    end)

    it("lets the options you set win over coil's standalone defaults", function()
      vim.g.coil_standalone = 1
      config.setup({ keymaps = { q = "actions.close" } })
      assert.equals("actions.close", config.get().keymaps.q)
      config.setup({
        keymaps = { q = "actions.close" },
        standalone = { keymaps = { q = "actions.quit" } },
      })
      assert.equals("actions.quit", config.get().keymaps.q)
    end)

    it("checks the standalone options in either mode", function()
      for _, case in ipairs({
        { opts = { standalone = false }, match = "standalone must be a table" },
        { opts = { standalone = { ratio = { 1 } } }, match = "standalone.ratio" },
        { opts = { standalone = { keymaps = { q = 1 } } }, match = 'standalone.keymaps["q"]' },
      }) do
        local ok, err = pcall(config.setup, case.opts)
        assert.is_false(ok, vim.inspect(case.opts))
        assert.truthy(err:find(case.match, 1, true), err)
      end
      config.setup({ standalone = { winbr = true, standalone = {} } })
      assert.truthy(notifications[1].msg:find("standalone.standalone, standalone.winbr", 1, true))
    end)
  end)
end)

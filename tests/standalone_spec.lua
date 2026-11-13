local coil = require("coil")
local h = require("tests.helpers")
local standalone = require("coil.standalone")
local state = require("coil.view.state")

describe("standalone startup", function()
  local dir, notifications, notify

  before_each(function()
    dir = h.tmpdir()
    notifications = {}
    notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = notify
  end)

  ---Write a config file and load it
  ---@param lines string[]
  ---@return table
  local function load(lines)
    local path = dir .. "/init.lua"
    h.write(path, lines)
    local result = standalone.load_config(path)
    -- Warnings are scheduled
    vim.wait(20)
    return result
  end

  describe("the config file", function()
    it("is optional", function()
      assert.same({}, standalone.load_config(dir .. "/missing.lua"))
    end)

    it("runs as Lua and may return setup options", function()
      local options = standalone.options(load({
        "vim.g.coil_test_config_ran = true",
        "return { oil = { delete_to_trash = false }, coil = { ratio = { 1, 2, 3 } } }",
      }))
      assert.is_true(vim.g.coil_test_config_ran)
      assert.is_false(options.oil.delete_to_trash)
      assert.same({ 1, 2, 3 }, options.coil.ratio)
      -- Not mentioned: the build's defaults
      assert.same(standalone.defaults.image, options.image)
    end)

    it("merges into the build's defaults", function()
      local defaults = standalone.defaults
      standalone.defaults = { oil = { a = 1, nested = { b = 2 } }, coil = {}, image = {} }
      local options = standalone.options(load({ "return { oil = { nested = { c = 3 } } }" }))
      standalone.defaults = defaults
      assert.same({ a = 1, nested = { b = 2, c = 3 } }, options.oil)
    end)

    it("deletes to the trash unless told otherwise", function()
      assert.is_true(standalone.options({}).oil.delete_to_trash)
      assert.is_false(standalone.options({ oil = { delete_to_trash = false } }).oil.delete_to_trash)
    end)

    it("quits with q instead of closing one view", function()
      assert.same({ close = false, quit = "q" }, standalone.options({}).coil.keymaps)
    end)

    it("shows entry details, and lists in the config file replace the defaults'", function()
      assert.same({ "icon", "permissions", "size", "mtime" }, standalone.options({}).oil.columns)
      assert.same({ "icon" }, standalone.options({ oil = { columns = { "icon" } } }).oil.columns)
    end)

    it("can turn image.nvim off", function()
      assert.is_false(standalone.options(load({ "return { image = false }" })).image)
    end)

    it("can turn mini.icons off", function()
      assert.same({}, standalone.options({}).icons)
      assert.is_false(standalone.options({ icons = false }).icons)
    end)

    it("reports errors and falls back to the defaults", function()
      assert.same({}, load({ "error('oops')" }))
      assert.equals(1, #notifications)
      assert.truthy(notifications[1].msg:find("oops", 1, true))
      assert.same({}, load({ "return 42" }))
      assert.truthy(notifications[2].msg:find("should return a table", 1, true))
    end)
  end)

  describe("the command line", function()
    before_each(function()
      standalone.track_dir()
      for _ = 1, 5 do
        pcall(coil.close)
      end
      h.reset_tab()
      h.setup_oil()
      coil.setup()
      vim.fn.mkdir(dir .. "/one")
      vim.fn.mkdir(dir .. "/two")
      h.write(dir .. "/file.txt", { "" })
    end)

    after_each(function()
      for _ = 1, 5 do
        pcall(coil.close)
      end
    end)

    it("opens the current directory, all-directory arguments, or nothing", function()
      assert.same({ vim.fn.getcwd() }, standalone.dirs_for({}))
      local dirs = { dir .. "/one", "oil://" .. dir .. "/two/" }
      assert.same(dirs, standalone.dirs_for(dirs))
      assert.is_nil(standalone.dirs_for({ dir .. "/one", dir .. "/file.txt" }))
    end)

    it("writes the column view's directory to the --cwd-file on exit", function()
      local cwd_file = dir .. "/cwd"
      standalone.write_cwd_on_exit(cwd_file)
      h.open_view(dir .. "/one")
      vim.api.nvim_exec_autocmds("VimLeavePre", {})
      -- No trailing slash or newline
      assert.equals(dir .. "/one", table.concat(vim.fn.readfile(cwd_file, "b"), "\n"))
    end)

    it("remembers the last directory after the views are closed", function()
      local view = h.open_view(dir)
      h.cursor_to(view.panes.current, "two/")
      h.press("L")
      assert.is_true(h.wait(function()
        return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
          == "oil://" .. dir .. "/two/"
      end))
      coil.close()
      assert.equals(dir .. "/two/", standalone.exit_dir())
    end)

    it("starts with only the column views", function()
      local start_buf = vim.api.nvim_get_current_buf()
      standalone.open_args({ dir .. "/one", dir .. "/two" })
      assert.equals(2, #vim.api.nvim_list_tabpages())
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        assert.truthy(state.get(tab))
      end
      assert.is_false(vim.api.nvim_buf_is_valid(start_buf))
    end)
  end)
end)

-- Init for a child Neovim in the standalone mode tests: coil and oil set up as in a user's config.
-- Once startup is done, writes what it shows to $COIL_TEST_OUT as JSON and quits.
dofile("tests/minimal_init.lua")
require("oil").setup()
require("coil").setup()

vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.defer_fn(function()
      local state = require("coil.view.state")
      local tabs = {}
      for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local view = state.get(tab)
        table.insert(
          tabs,
          view and vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(view.panes.current))
            or vim.NIL
        )
      end
      local report = {
        tabs = tabs,
        quit = require("coil.config").get().keymaps.quit,
        cwd_file = vim.g.coil_cwd_file or vim.NIL,
        cwd_file_env = vim.env.COIL_CWD_FILE or vim.NIL,
        editor_env = vim.g.coil_editor_env or vim.NIL,
        user_appname_env = vim.env.COIL_USER_NVIM_APPNAME or vim.NIL,
      }
      vim.fn.writefile({ vim.json.encode(report) }, vim.env.COIL_TEST_OUT)
      vim.cmd("qa!")
    end, 500)
  end,
})

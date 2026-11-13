# `coil`: a standalone file manager in the terminal. It is a bare Neovim with coil.nvim, oil.nvim
# and image.nvim that opens the column view on startup, installed as `bin/coil` only, so it never
# clashes with your own Neovim. For adding coil to your own Neovim, use ./coil-nvim.nix instead.
#
#   pkgs.callPackage ./nix/coil.nix { }
#
# Uses nixpkgs' oil.nvim unless `oil-nvim` is given.
{
  lib,
  callPackage,
  runCommandLocal,
  vimPlugins,
  neovim-unwrapped,
  wrapNeovimUnstable,
  imagemagick,
  oil-nvim ? vimPlugins.oil-nvim,
  coil-nvim ? callPackage ./coil-nvim.nix { },
}:
let
  nvim = wrapNeovimUnstable neovim-unwrapped {
    plugins = [
      coil-nvim
      oil-nvim
      vimPlugins.image-nvim
    ];
    wrapperArgs = [
      # Keep away from the user's own Neovim config, state and shada
      "--set-default"
      "NVIM_APPNAME"
      "coil-nvim"
      # image.nvim converts and resizes images with ImageMagick. Appended, so an ImageMagick
      # already on PATH is used first
      "--suffix"
      "PATH"
      ":"
      "${lib.makeBinPath [ imagemagick ]}"
    ];
    luaRcContent = ''
      require("oil").setup()
      require("coil").setup()
      require("image").setup()

      -- No arguments: open the column view on the current directory.
      -- Directory arguments: open the column view on each, one tab per directory.
      -- Either way the column views are the only tabs; files open in a new tab.
      -- Anything else (a file among the arguments) opens as usual.
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        -- Let the autocmds coil and oil rely on (BufReadCmd, BufWinEnter, ...) fire from here
        nested = true,
        callback = function()
          local args = vim.fn.argv()
          ---@param arg string
          local function is_dir(arg)
            -- By now oil may have turned a directory argument into an oil URL ("oil:///path/")
            return vim.fn.isdirectory(arg) == 1 or (arg:match("^[%w-]+://") ~= nil and vim.endswith(arg, "/"))
          end
          local dirs
          if #args == 0 then
            dirs = { vim.fn.getcwd() }
          elseif vim.iter(args):all(is_dir) then
            dirs = args
          else
            return
          end

          -- The tab Neovim started with: empty, or showing the first directory argument as an
          -- oil buffer. The column views replace it.
          local start_tab = vim.api.nvim_get_current_tabpage()
          local start_bufs = vim.api.nvim_list_bufs()
          require("coil").open(dirs)
          if vim.api.nvim_tabpage_is_valid(start_tab) and #vim.api.nvim_list_tabpages() > 1 then
            vim.cmd.tabclose(vim.api.nvim_tabpage_get_number(start_tab))
          end
          vim.cmd("silent! %argdelete")
          -- The start buffers no window shows any more (the views open their own)
          for _, bufnr in ipairs(start_bufs) do
            if vim.api.nvim_buf_is_valid(bufnr) and #vim.fn.win_findbuf(bufnr) == 0 then
              pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
          end
        end,
      })
    '';
  };
in
# Only bin/coil: the wrapped Neovim's own bin/nvim and share/ would collide with the user's Neovim
# when installed into the same profile
runCommandLocal "coil-${coil-nvim.version}"
  {
    passthru = {
      inherit coil-nvim oil-nvim nvim;
    };
    meta = {
      description = "Terminal file manager built on Neovim, oil.nvim and coil.nvim";
      inherit (coil-nvim.meta) homepage license;
      inherit (nvim.meta) platforms;
      mainProgram = "coil";
    };
  }
  ''
    mkdir -p $out/bin
    ln -s ${lib.getExe nvim} $out/bin/coil
  ''

# `coil`: a standalone file manager in the terminal. It is a bare Neovim with coil.nvim and
# oil.nvim that opens the column view on startup, installed as `bin/coil` only, so it never
# clashes with your own Neovim. For adding coil to your own Neovim, use ./coil-nvim.nix instead.
#
#   pkgs.callPackage ./nix/coil.nix { }
#
# The flake passes the oil.nvim commit coil is tested against; standalone, nixpkgs' oil.nvim is
# used.
{
  lib,
  callPackage,
  runCommandLocal,
  vimPlugins,
  neovim-unwrapped,
  wrapNeovimUnstable,
  oil-nvim ? vimPlugins.oil-nvim,
  coil-nvim ? callPackage ./coil-nvim.nix { inherit oil-nvim; },
}:
let
  nvim = wrapNeovimUnstable neovim-unwrapped {
    plugins = [
      coil-nvim
      oil-nvim
    ];
    # Keep away from the user's own Neovim config, state and shada
    wrapperArgs = [
      "--set-default"
      "NVIM_APPNAME"
      "coil-nvim"
    ];
    luaRcContent = ''
      require("oil").setup()
      require("coil").setup()

      -- No arguments: open the column view on the current directory.
      -- One directory argument: open it on that directory. Files open as usual.
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          local args = vim.fn.argv()
          -- By now oil has turned a directory argument into an oil URL ("oil:///path/")
          local is_dir = #args == 1
            and (vim.fn.isdirectory(args[1]) == 1 or (args[1]:match("^[%w-]+://") and vim.endswith(args[1], "/")))
          if #args == 0 then
            require("coil").open(vim.fn.getcwd())
          elseif is_dir then
            require("coil").open(args[1])
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

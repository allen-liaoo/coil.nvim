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
      # Keep away from the user's own Neovim config, state and shada; the config file is
      # ~/.config/coil/init.lua
      "--set-default"
      "NVIM_APPNAME"
      "coil"
      # image.nvim converts and resizes images with ImageMagick. Appended, so an ImageMagick
      # already on PATH is used first
      "--suffix"
      "PATH"
      ":"
      "${lib.makeBinPath [ imagemagick ]}"
    ];
    # Defaults, the optional ~/.config/coil/init.lua, and opening the column view for the command
    # line: see lua/coil/standalone.lua
    luaRcContent = ''
      require("coil.standalone").start()
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

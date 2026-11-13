# `coil`: a standalone file manager in the terminal. It is a Neovim with coil.nvim, oil.nvim,
# image.nvim and mini.icons that opens the column view on startup, installed as `bin/coil` only,
# so it never clashes with your own Neovim. For adding coil to your own Neovim, use
# ./coil-nvim.nix instead.
#
#   pkgs.callPackage ./nix/coil.nix { }
#
# Uses nixpkgs' oil.nvim unless `oil-nvim` is given.
{
  lib,
  callPackage,
  runCommandLocal,
  runtimeShell,
  vimPlugins,
  neovim-unwrapped,
  wrapNeovimUnstable,
  imagemagick,
  ffmpeg-headless,
  poppler-utils,
  oil-nvim ? vimPlugins.oil-nvim,
  coil-nvim ? callPackage ./coil-nvim.nix { },
}:
let
  nvim = wrapNeovimUnstable neovim-unwrapped {
    plugins = [
      coil-nvim
      oil-nvim
      vimPlugins.image-nvim
      # Icons in oil's icon column
      vimPlugins.mini-icons
    ];
    wrapperArgs = [
      # Keep away from the user's own Neovim config, state and shada; the config file is
      # ~/.config/coil/init.lua
      "--set-default"
      "NVIM_APPNAME"
      "coil"
      # Thumbnails for previews: ImageMagick for images (image.nvim uses it too), ffmpeg for video
      # frames, poppler for PDF pages. Appended, so versions already on PATH are used first
      "--suffix"
      "PATH"
      ":"
      "${lib.makeBinPath [
        imagemagick
        ffmpeg-headless
        poppler-utils
      ]}"
    ];
    # The build's defaults and the optional ~/.config/coil/init.lua (lua/coil/standalone/build.lua).
    # It turns on coil's standalone mode, which opens the column view for the command line
    luaRcContent = ''
      require("coil.standalone.build").start()
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
    # The repo's launcher (bin/coil), running this build's Neovim
    mkdir -p $out/bin
    substitute ${../bin/coil} $out/bin/coil \
      --replace-fail '#!/usr/bin/env bash' '#!${runtimeShell}' \
      --replace-fail 'nvim_program="''${COIL_NVIM_PROGRAM:-nvim}"' 'nvim_program="${lib.getExe nvim}"'
    chmod +x $out/bin/coil
  ''

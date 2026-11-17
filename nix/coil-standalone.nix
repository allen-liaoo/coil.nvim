# `coil`: coil.nvim as a terminal file manager, for people who don't use Neovim themselves. It is
# a Neovim with coil.nvim, oil.nvim, image.nvim and mini.icons, started in coil's standalone mode by
# the plugin's own ../bin/coil (through ./coil-cli.nix). It installs only `bin/coil`, so it never
# clashes with a Neovim of your own. The file picker is ./coil-termfilechooser.nix. To add coil to
# your own Neovim, use ./coil-nvim.nix instead.
#
#   pkgs.callPackage ./nix/coil-standalone.nix { }
#
# Uses nixpkgs' oil.nvim unless `oil-nvim` is given.
{
  lib,
  callPackage,
  vimPlugins,
  vimUtils,
  neovim-unwrapped,
  wrapNeovimUnstable,
  imagemagick,
  ffmpeg-headless,
  poppler-utils,
  oil-nvim ? vimPlugins.oil-nvim,
  coil-nvim ? callPackage ./coil-nvim.nix { },
}:
let
  # Sets up the bundled plugins that ~/.config/coil/init.lua doesn't (./defaults)
  coil-defaults = vimUtils.buildVimPlugin {
    pname = "coil-defaults";
    inherit (coil-nvim) version;
    src = ./defaults;
  };
  nvim = wrapNeovimUnstable neovim-unwrapped {
    plugins = [
      coil-nvim
      oil-nvim
      vimPlugins.image-nvim
      # Icons in oil's icon column
      vimPlugins.mini-icons
      # Git status signs next to each entry, in every pane
      vimPlugins.oil-git-status-nvim
      coil-defaults
    ];
    # No init of its own: Neovim reads ~/.config/coil/init.lua (the `coil` app name below), a
    # config like any other
    wrapRc = false;
    wrapperArgs = [
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
  };
in
# The bundled Neovim, run as its own Neovim app
callPackage ./coil-cli.nix {
  inherit nvim;
  appname = "coil";
  inherit (coil-nvim) version;
}

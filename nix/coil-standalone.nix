# `coil`: coil.nvim as a terminal file manager, for people who don't use Neovim themselves. It is
# a Neovim with coil.nvim, oil.nvim, image.nvim (patched), oil-git-status.nvim,
# oil-lsp-diagnostics.nvim (patched) and mini.icons, started in coil's
# standalone mode by the plugin's own ../bin/coil (through ./coil-cli.nix). It installs only
# `bin/coil`, so it never clashes with a Neovim of your own. The file picker is
# ./coil-termfilechooser.nix. To add coil to your own Neovim, use ./coil-nvim.nix instead.
#
#   pkgs.callPackage ./nix/coil-standalone.nix { }
#
# Uses nixpkgs' oil.nvim unless `oil-nvim` is given.
{
  lib,
  callPackage,
  fetchpatch,
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
    version = lib.fileContents ../VERSION;
    src = ./defaults;
  };
  # Plugin fixes from nvimx (https://github.com/allen-liaoo/nvimx), at a pinned commit
  nvimxPatch =
    path: hash:
    fetchpatch {
      url = "https://raw.githubusercontent.com/allen-liaoo/nvimx/69babcf827022c6a70b16545f50328f99ff5d34d/nvimx/plugins/patches/${path}";
      inherit hash;
    };
  image-nvim = vimPlugins.image-nvim.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (nvimxPatch "image/0001-fix-kitty-place-unicode-placeholders-in-the-right-co.patch" "sha256-ygUXTxIRIZdecvwcg3qTAm6JYfQoI43Y7mcl1+QQmy8=")
      (nvimxPatch "image/0002-fix-kitty-draw-unicode-placeholders-without-Neovim-s.patch" "sha256-JHXFiiIHOizi+6Jc6UKyhQtbaqAwxE2c9ugaDmP0BBQ=")
    ];
  });
  oil-lsp-diagnostics-nvim = vimPlugins.oil-lsp-diagnostics-nvim.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      (nvimxPatch "oil-lsp-diagnostics/0001-fix-skip-oil-buffers-that-aren-t-local-directories.patch" "sha256-4wRF9BEHjs5YWTxKTSsSbwaPr4nQCnr4c5O4nGIz7l0=")
      (nvimxPatch "oil-lsp-diagnostics/0002-fix-draw-the-marks-again-after-oil-redraws-a-buffer.patch" "sha256-8YTdviAKvwWSUKg5X2lh0IZwM8DWlc7IdYnri3FsX6M=")
    ];
  });
  nvim = wrapNeovimUnstable neovim-unwrapped {
    plugins = [
      coil-nvim
      oil-nvim
      image-nvim
      # Icons in oil's icon column
      vimPlugins.mini-icons
      # Git status signs next to each entry, in every pane
      vimPlugins.oil-git-status-nvim
      # LSP diagnostics counts next to each entry, in every pane
      oil-lsp-diagnostics-nvim
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
}

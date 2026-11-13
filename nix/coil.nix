# `coil`: coil.nvim as a terminal file manager, for people who don't use Neovim themselves. It is
# a Neovim with coil.nvim, oil.nvim, image.nvim and mini.icons, started in coil's standalone mode by
# ./coil.sh, installed as `bin/coil` only, so it never clashes with a Neovim of your own. To add
# coil to your own Neovim, use ./coil-nvim.nix instead.
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
  defaults = vimUtils.buildVimPlugin {
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
      defaults
    ];
    # No init of its own: Neovim reads ~/.config/coil/init.lua (see NVIM_APPNAME), a config like
    # any other
    wrapRc = false;
    wrapperArgs = [
      # Keep away from the user's own Neovim config, state and shada
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
    substitute ${./coil.sh} $out/bin/coil \
      --replace-fail '@shell@' '${runtimeShell}' \
      --replace-fail '@nvim@' '${lib.getExe nvim}'
    chmod +x $out/bin/coil
  ''

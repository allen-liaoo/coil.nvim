# `coil`: a standalone file manager in the terminal. It is a Neovim with coil.nvim, oil.nvim,
# image.nvim, mini.icons and Tree-sitter grammars that opens the column view on startup, installed
# as `bin/coil` only, so it never clashes with your own Neovim. For adding coil to your own Neovim,
# use ./coil-nvim.nix instead.
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
  ffmpeg-headless,
  poppler-utils,
  oil-nvim ? vimPlugins.oil-nvim,
  coil-nvim ? callPackage ./coil-nvim.nix { },
}:
let
  # Highlighting for text previews, beyond the few grammars Neovim ships with
  treesitter = vimPlugins.nvim-treesitter.withPlugins (
    p: with p; [
      bash
      c
      cpp
      css
      csv
      diff
      dockerfile
      git_config
      gitcommit
      gitignore
      go
      html
      ini
      java
      javascript
      json
      kotlin
      make
      nix
      php
      python
      ruby
      rust
      sql
      toml
      tsx
      typescript
      xml
      yaml
      zig
    ]
  );
  nvim = wrapNeovimUnstable neovim-unwrapped {
    plugins = [
      coil-nvim
      oil-nvim
      vimPlugins.image-nvim
      # Icons in oil's icon column
      vimPlugins.mini-icons
      treesitter
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

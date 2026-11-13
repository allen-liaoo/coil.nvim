# coil.nvim as a nixvim plugin module: `plugins.coil`, like nixvim's own plugin modules.
#
#   imports = [ inputs.coil-nvim.nixvimModules.default ];
#   plugins.coil = {
#     enable = true;
#     images.enable = true;
#     settings = { ratio = [ 1 3 4 ]; };
#   };
#
# Takes coil.nvim's flake packages (`packages.<system>`), so `plugins.coil.package` defaults to this
# flake's build of the plugin: coil isn't in nixpkgs.
packages:
{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    (lib.nixvim.plugins.mkNeovimPlugin {
      name = "coil";
      url = "https://github.com/allen-liaoo/coil.nvim";
      description = "Column view (parent | current | preview) with file previews for oil.nvim.";
      maintainers = [ ];

      package = lib.mkOption {
        type = lib.types.package;
        default = packages.${pkgs.stdenv.hostPlatform.system}.coil-nvim;
        defaultText = lib.literalMD "coil.nvim, from coil.nvim's flake";
        description = "The coil.nvim package to use.";
      };

      # The common options. Everything else in coil's setup() (keymaps, preview, standalone, ...)
      # goes in `settings` as well; see coil's README.
      settingsOptions = with lib.nixvim.defaultNullOpts; {
        ratio = mkListOf lib.types.ints.positive [
          1
          4
          3
        ] "Relative widths of the parent, current and preview panes.";
        debounce_ms = mkUnsignedInt 30 "Wait this long (ms) after the cursor stops before updating the preview.";
        tab_title = mkBool true "Name the column view's tab after the current directory (`t:tabname`).";
        winbar = mkBool false "Show each pane's path in a title line (winbar) above it.";
        open_external = mkBool false ''
          With `L` or `<CR>`, open files that aren't text (images, videos, audio, PDFs, archives,
          other binary files) in the system's default program instead of Neovim.
        '';
        edit_here = mkBool true ''
          With `L` or `<CR>`, open text files in this Neovim. When false, they open in the system's
          text editor: XDG's default for text/plain, otherwise `$VISUAL` or `$EDITOR`.
        '';
      };

      settingsExample = {
        ratio = [
          1
          3
          4
        ];
        keymaps = {
          go_in = "l";
          go_out = "h";
        };
        preview.thumbnail_cache_mb = 500;
        standalone.edit_here = true;
      };

      extraOptions = {
        images.enable = lib.mkEnableOption ''
          images, video frames and PDF pages in the preview: sets up image.nvim (which draws them)
          and adds ImageMagick, ffmpeg and poppler's pdftoppm (which make the thumbnails)
        '';
      };

      extraConfig =
        cfg:
        lib.mkMerge [
          {
            # coil works on oil's buffers, so oil has to be set up
            plugins.oil.enable = lib.mkDefault true;
          }
          (lib.mkIf cfg.images.enable {
            plugins.image.enable = lib.mkDefault true;
            # image.nvim and coil's thumbnails use ImageMagick; nixvim's image module only adds it
            # for the sixel backend
            dependencies.imagemagick.enable = lib.mkDefault true;
            # Video frames (ffmpeg) and PDF pages (pdftoppm)
            extraPackages = [
              pkgs.ffmpeg-headless
              pkgs.poppler-utils
            ];
          })
        ];
    })
  ];
}

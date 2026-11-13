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
      description = "Column view with file previews for oil.nvim.";
      maintainers = [ ];

      package = lib.mkOption {
        type = lib.types.package;
        default = packages.${pkgs.stdenv.hostPlatform.system}.coil-nvim;
        defaultText = lib.literalMD "coil.nvim, from coil.nvim's flake";
        description = "The coil.nvim package to use.";
      };

      # `settings` is passed to require("coil").setup() as it is, without options of its own here:
      # coil's README documents them, so there's no second copy to keep up to date
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
            # For tmux (the README has these too): kitty's default, cursor-based method lands images
            # at the cursor there, and images show only in the active tmux window
            plugins.image.settings = {
              kitty_method = lib.mkDefault "unicode-placeholders";
              tmux_show_only_in_active_window = lib.mkDefault true;
            };
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

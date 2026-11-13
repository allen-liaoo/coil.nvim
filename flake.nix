{
  description = "coil.nvim: column view and file preview for oil.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nvimx = {
      url = "github:allen-liaoo/nvimx";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nvimx,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        system: pkgs: {
          default = pkgs.mkShell {
            packages = [
              pkgs.gnumake
              pkgs.lua-language-server
              pkgs.stylua
              # image.nvim converts and resizes images with ImageMagick
              pkgs.imagemagick
              # Video frames and PDF pages for previews
              pkgs.ffmpeg-headless
              pkgs.poppler-utils
              (nvimx.makeNvimxWithModule system {
                nvimx.preset.lua.enable = true;
              })
            ];

            # Neovim is exposed through COIL_NVIM instead of PATH so the shell does not
            # shadow your own configured `nvim`. Tests run this clean, unconfigured build.
            COIL_NVIM = "${pkgs.neovim-unwrapped}/bin/nvim";
            COIL_OIL_PATH = "${pkgs.vimPlugins.oil-nvim}";
            COIL_PLENARY_PATH = "${pkgs.vimPlugins.plenary-nvim}";
            # Optional dependency, for drawing images in previews
            COIL_IMAGE_PATH = "${pkgs.vimPlugins.image-nvim}";
          };
        }
      );

      packages = forAllSystems (
        system: pkgs:
        let
          # The plugin, for adding to your own Neovim next to oil.nvim
          coil-nvim = pkgs.callPackage ./nix/coil-nvim.nix {
            version = "0-unstable-${self.shortRev or self.dirtyShortRev or "dirty"}";
          };
          # The standalone file manager: `coil [dir]`, with nixpkgs' oil.nvim
          coil = pkgs.callPackage ./nix/coil.nix { inherit coil-nvim; };
        in
        {
          default = coil;
          inherit coil coil-nvim;
        }
      );

      apps = forAllSystems (
        system: _: {
          default = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${system}.default;
            meta.description = "Terminal file manager built on Neovim, oil.nvim and coil.nvim";
          };
        }
      );

      formatter = forAllSystems (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}

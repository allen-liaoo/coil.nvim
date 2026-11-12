{
  description = "coil.nvim: column view and file preview for oil.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    oil-nvim = {
      url = "github:stevearc/oil.nvim/d3733d933833a0e59b813ecec99341527adf0c28";
      flake = false;
    };
    nvimx = {
      url = "github:allen-liaoo/nvimx";
      inputs.nixpkgs.follows = "nixpkgs";
    };  
  };

  outputs =
    { nixpkgs, oil-nvim, nvimx, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (
        system: pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.gnumake
            pkgs.lua-language-server
            pkgs.stylua
            (nvimx.makeNvimxWithModule system {
              nvimx.preset.lua.enable = true;
            })
          ];

          # Neovim is exposed through COIL_NVIM instead of PATH so the shell does not
          # shadow your own configured `nvim`. Tests run this clean, unconfigured build.
          COIL_NVIM = "${pkgs.neovim-unwrapped}/bin/nvim";
          COIL_OIL_PATH = "${oil-nvim}";
          COIL_PLENARY_PATH = "${pkgs.vimPlugins.plenary-nvim}";
        };
        }
      );

      formatter = forAllSystems (_: pkgs: pkgs.nixfmt-rfc-style);
    };
}

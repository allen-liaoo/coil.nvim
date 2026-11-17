{
  description = "coil.nvim: column view and file preview for oil.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixvim,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system nixpkgs.legacyPackages.${system});
      coilPackages = pkgs: rec {
        # nvim plugin
        coil-nvim = pkgs.callPackage ./nix/coil-nvim.nix {
          version = "0-unstable-${self.shortRev or self.dirtyShortRev or "dirty"}";
        };
        # standalone coil from your neovim, given with `.override { nvim = ...; }`
        coil-cli = pkgs.callPackage ./nix/coil-cli.nix { inherit (coil-nvim) version; };
        # the file picker wrapper for your coil-cli: in the overlay, callPackage fills in
        # pkgs.coil-cli, so it follows an overlay of yours that overrides coil-cli. Or
        # `.override { coil-cli = ...; }`
        coil-filechooser = pkgs.callPackage ./nix/coil-termfilechooser.nix { };
        # Distributed standalone file manager
        coil-standalone = pkgs.callPackage ./nix/coil-standalone.nix { inherit coil-nvim; };
        # the file picker wrapper for xdg-desktop-portal-termfilechooser, running the standalone coil
        coil-standalone-filechooser = pkgs.callPackage ./nix/coil-termfilechooser.nix {
          coil-cli = coil-standalone;
        };
      };
    in
    {
      # Without coil-cli and coil-filechooser, which have nothing to run until given it
      packages = forAllSystems (
        system: pkgs:
        let
          coil = removeAttrs (coilPackages pkgs) [
            "coil-cli"
            "coil-filechooser"
          ];
        in
        coil // { default = coil.coil-nvim; }
      );

      legacyPackages = forAllSystems (_: coilPackages);

      overlays.default =
        final: prev:
        let
          coil = coilPackages final;
        in
        removeAttrs coil [ "coil-nvim" ]
        // {
          vimPlugins = prev.vimPlugins.extend (_: _: { inherit (coil) coil-nvim; });
        };

      nixvimModules = rec {
        coil = import ./nix/nixvim.nix self.packages;
        default = coil;
      };

      apps = forAllSystems (
        system: _: {
          default = {
            type = "app";
            program = nixpkgs.lib.getExe self.packages.${system}.coil-standalone;
            meta.description = "Standalone coil.nvim";
          };
        }
      );

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
            ];

            # Neovim is exposed through COIL_TEST_NVIM instead of PATH so the shell does not
            # shadow your own configured `nvim`. Tests run this clean, unconfigured build.
            COIL_TEST_NVIM = "${pkgs.neovim-unwrapped}/bin/nvim";
            COIL_OIL_PATH = "${pkgs.vimPlugins.oil-nvim}";
            COIL_PLENARY_PATH = "${pkgs.vimPlugins.plenary-nvim}";
            # Optional dependency, for drawing images in previews
            COIL_IMAGE_PATH = "${pkgs.vimPlugins.image-nvim}";
            # Third-party oil extension coil is tested with: git status signs, in every pane
            COIL_OIL_GIT_STATUS_PATH = "${pkgs.vimPlugins.oil-git-status-nvim}";
          };
        }
      );

      formatter = forAllSystems (_: pkgs: pkgs.nixfmt-rfc-style);

      # The nixvim module, in a nixvim that starts headless without errors (nixvim from nvimx)
      checks = forAllSystems (
        system: pkgs:
        let
          nixvimCheck =
            name: module:
            nixvim.lib.${system}.check.mkTestDerivationFromNixvimModule {
              inherit name pkgs;
              module = {
                imports = [ self.nixvimModules.default ];
              }
              // module;
            };
          nixvimWithCoil = nixvim.legacyPackages.${system}.makeNixvimWithModule {
            inherit pkgs;
            module = {
              imports = [ self.nixvimModules.default ];
              plugins.coil.enable = true;
            };
          };
          inherit (nixvimWithCoil.config.plugins.coil) cli termfilechooser;
          # A Neovim of your own with coil, as Home Manager's programs.neovim builds one, given to the
          # overlay's coil-cli
          withOverlay = pkgs.extend self.overlays.default;
          ownNvim = withOverlay.wrapNeovimUnstable withOverlay.neovim-unwrapped {
            plugins = [
              withOverlay.vimPlugins.coil-nvim
              withOverlay.vimPlugins.oil-nvim
            ];
          };
          ownCoil = withOverlay.coil-cli.override { nvim = ownNvim; };
          # The same, without the overlay
          legacy = self.legacyPackages.${system};
          legacyCoil = legacy.coil-cli.override { nvim = ownNvim; };
          # `coil` runs `nvim`, with coil in it, and `picker` runs that `coil`
          cliCheck =
            name: nvim: coil: picker:
            pkgs.runCommandLocal name { } ''
              coil=${nixpkgs.lib.getExe coil}
              $coil --version
              grep -qF "COIL_NVIM='${nixpkgs.lib.getExe nvim}'" $coil
              HOME=$TMPDIR $coil --headless \
                -c 'lua if not pcall(require, "coil") then vim.cmd.cquit() end' -c qa
              # A stand-in terminal, which logs the command it would run
              cat >term <<'EOF'
              #!${pkgs.runtimeShell}
              printf '%s\n' "$@" >"$LOG"
              EOF
              chmod +x term
              LOG=$PWD/log TERMCMD=$PWD/term \
                ${nixpkgs.lib.getExe picker} 0 0 0 "$PWD" "$PWD/out"
              grep -qxF "$coil" log
              touch $out
            '';
        in
        {
          nixvim-module = nixvimCheck "coil-nixvim-module" {
            plugins.coil = {
              enable = true;
              settings = {
                ratio = [
                  1
                  3
                  4
                ];
                keymaps.go_in = "l";
              };
            };
          };
          nixvim-module-images = nixvimCheck "coil-nixvim-module-images" {
            # image.nvim needs a real terminal at startup, so this one only builds (as nixvim's own
            # image.nvim tests do)
            test.runNvim = false;
            plugins.coil = {
              enable = true;
              images.enable = true;
            };
          };
          # The module's `coil` runs nixvim's Neovim, and its file picker runs that `coil`
          nixvim-cli = cliCheck "coil-nixvim-cli" nixvimWithCoil cli.package termfilechooser.package;
          # The overlay's, given a Neovim of your own
          overlay-cli = cliCheck "coil-overlay-cli" ownNvim ownCoil (
            withOverlay.coil-filechooser.override { coil-cli = ownCoil; }
          );
          # legacyPackages', given the same Neovim
          legacy-cli = cliCheck "coil-legacy-cli" ownNvim legacyCoil (
            legacy.coil-filechooser.override { coil-cli = legacyCoil; }
          );
        }
      );
    };
}

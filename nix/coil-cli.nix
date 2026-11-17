# The `coil` command (../bin/coil), running a given Neovim instead of the `nvim` on PATH. The
# standalone `coil` (./coil-standalone.nix) and nixvim's `plugins.coil.cli.package` (./nixvim.nix)
# are built with it.
#
#   pkgs.callPackage ./nix/coil-cli.nix { nvim = <a Neovim with coil.nvim and oil.nvim>; }
#
# `appname`, if given, is the NVIM_APPNAME that Neovim runs as (COIL_APPNAME in ../bin/coil).
{
  lib,
  runCommandLocal,
  runtimeShell,
  makeWrapper,
  nvim, # required
  appname ? null,
  version ? "0-unstable",
}:
# Only coil's command: a Neovim's own bin/nvim and share/ would collide with the user's Neovim when
# installed into the same profile
runCommandLocal "coil-${version}"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      inherit nvim version;
    };
    meta = {
      description = "Terminal file manager built on Neovim, oil.nvim and coil.nvim";
      homepage = "https://github.com/allen-liaoo/coil.nvim";
      license = lib.licenses.mit;
      # A bash script. (nixvim's Neovim has no platforms of its own.)
      platforms = lib.platforms.unix;
      mainProgram = "coil";
    };
  }
  ''
    mkdir -p $out/bin
    substitute ${../bin/coil} $out/bin/coil \
      --replace-fail '#!/usr/bin/env bash' '#!${runtimeShell}' \
      --replace-fail 'version=0-unstable' 'version=${version}'
    chmod +x $out/bin/coil
    wrapProgram $out/bin/coil \
      --set COIL_NVIM '${lib.getExe nvim}' ${
        lib.optionalString (appname != null) "--set COIL_APPNAME ${lib.escapeShellArg appname}"
      }
  ''

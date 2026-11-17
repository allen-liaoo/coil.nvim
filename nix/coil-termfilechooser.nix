# `coil-termfilechooser`: a `coil` command as the file picker of xdg-desktop-portal-termfilechooser
# (../bin/coil-termfilechooser), running that `coil` by its store path, so the portal finds it
# whatever its `PATH`. It installs only the picker, not `coil`.
#
#   pkgs.callPackage ./nix/coil-termfilechooser.nix { coil-cli = <a coil-cli package>; }
#
# `coil-cli` is the `coil` it runs: any ./coil-cli.nix package, such as ./coil-standalone.nix (the
# flake's default) or nixvim's `plugins.coil.cli.package`.
{
  lib,
  runCommandLocal,
  runtimeShell,
  runtimeShellPackage,
  coreutils,
  makeWrapper,
  coil-cli,
}:
runCommandLocal "coil-termfilechooser-${coil-cli.version}"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      inherit coil-cli;
      inherit (coil-cli) version;
    };
    meta = {
      description = "coil as the file picker of xdg-desktop-portal-termfilechooser";
      inherit (coil-cli.meta) homepage license platforms;
      mainProgram = "coil-termfilechooser";
    };
  }
  ''
    mkdir -p $out/bin
    substitute ${../bin/coil-termfilechooser} $out/bin/coil-termfilechooser \
      --replace-fail '#!/usr/bin/env bash' '#!${runtimeShell}' \
      --replace-fail 'coil="$(dirname "$(readlink -f "$0")")/coil"' 'coil=${lib.getExe coil-cli}'
    chmod +x $out/bin/coil-termfilechooser
    # The script's own tools (sh, rm, cat), for a portal with an empty PATH. Appended, so the
    # terminal and tools on the portal's PATH come first
    wrapProgram $out/bin/coil-termfilechooser \
      --suffix PATH : ${
        lib.makeBinPath [
          runtimeShellPackage
          coreutils
        ]
      }
  ''

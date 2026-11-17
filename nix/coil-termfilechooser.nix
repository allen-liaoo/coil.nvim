# `coil-termfilechooser`: a `coil` command as the file picker of xdg-desktop-portal-termfilechooser
# (../bin/coil-termfilechooser), running that `coil` by its store path, so the portal finds it
# whatever its `PATH`. It installs only the picker, not `coil`.
#
#   pkgs.callPackage ./nix/coil-termfilechooser.nix { }
#
# Runs the standalone `coil` (./coil-standalone.nix) unless `coil` is given: any ./coil-cli.nix
# package.
{
  lib,
  callPackage,
  runCommandLocal,
  runtimeShell,
  runtimeShellPackage,
  coreutils,
  makeWrapper,
  coil ? callPackage ./coil-standalone.nix { },
}:
runCommandLocal "coil-termfilechooser-${coil.version}"
  {
    nativeBuildInputs = [ makeWrapper ];
    passthru = {
      inherit coil;
      inherit (coil) version;
    };
    meta = {
      description = "coil as the file picker of xdg-desktop-portal-termfilechooser";
      inherit (coil.meta) homepage license platforms;
      mainProgram = "coil-termfilechooser";
    };
  }
  ''
    mkdir -p $out/bin
    substitute ${../bin/coil-termfilechooser} $out/bin/coil-termfilechooser \
      --replace-fail '#!/usr/bin/env bash' '#!${runtimeShell}' \
      --replace-fail 'coil="$(dirname "$(readlink -f "$0")")/coil"' 'coil=${lib.getExe coil}'
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

# coil.nvim as a Neovim plugin, for adding to your own Neovim (Home Manager, nixvim, ...).
#
#   pkgs.callPackage ./nix/coil-nvim.nix { }
#
# oil.nvim is not a dependency: add it yourself, as you would without coil (Home Manager, nixvim
# and others have their own oil.nvim modules), so there is only one oil.nvim to configure.
#
# Without ../bin: its `coil` would run whatever `nvim` is on PATH. ./coil-cli.nix makes a `coil`
# that runs a given Neovim, as nixvim's `plugins.coil.cli.package` does with nixvim's.
{
  lib,
  vimUtils,
  version ? "0-unstable",
}:
vimUtils.buildVimPlugin {
  pname = "coil.nvim";
  inherit version;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../lua
      ../doc/coil.txt
      ../plugin
      ../LICENSE
    ];
  };
  meta = {
    description = "Column view and file preview for oil.nvim";
    homepage = "https://github.com/allen-liaoo/coil.nvim";
    license = lib.licenses.mit;
  };
}

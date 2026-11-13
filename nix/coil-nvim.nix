# coil.nvim as a Neovim plugin, for adding to your own Neovim (Home Manager, nixvim, ...).
#
#   pkgs.callPackage ./nix/coil-nvim.nix { }
#
# oil.nvim is not a dependency: add it yourself, as you would without coil (Home Manager, nixvim
# and others have their own oil.nvim modules), so there is only one oil.nvim to configure.
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
      ../plugin
      ../LICENSE
    ];
  };
  meta = {
    description = "Yazi-style column view and file preview for oil.nvim";
    homepage = "https://github.com/allen-liaoo/coil.nvim";
    license = lib.licenses.mit;
  };
}

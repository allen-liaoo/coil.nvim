# coil.nvim as a Neovim plugin, for adding to your own Neovim (Home Manager, nixvim, ...).
#
#   pkgs.callPackage ./nix/coil-nvim.nix { }
#
# Brings oil.nvim along as a dependency. The flake passes the oil.nvim commit coil is tested
# against; standalone, nixpkgs' oil.nvim is used.
{
  lib,
  vimUtils,
  vimPlugins,
  oil-nvim ? vimPlugins.oil-nvim,
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
  dependencies = [ oil-nvim ];
  meta = {
    description = "Yazi-style column view and file preview for oil.nvim";
    homepage = "https://github.com/allen-liaoo/coil.nvim";
    license = lib.licenses.mit;
  };
}

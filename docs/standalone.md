# Standalone coil and the Nix packages

coil can be used as a plugin in your own Neovim, or as a standalone terminal file manager, the
`coil` command. The flake provides both.

| Flake output | What it is | Defined in |
|---|---|---|
| `packages.default`, `packages.coil` | The `coil` command | `nix/coil.nix` |
| `packages.coil-nvim` | The plugin, for adding to your own Neovim | `nix/coil-nvim.nix` |
| `packages.oil-nvim` | The oil.nvim commit coil is tested against, built as a plugin | `flake.nix` |
| `apps.default` | Runs `coil`, so `nix run github:allen-liaoo/coil.nvim` works | `flake.nix` |
| `devShells.default` | The development shell | `flake.nix` (see [Development](development.md)) |

Both package files are plain `callPackage` files. With no arguments they use nixpkgs' oil.nvim:

```nix
pkgs.callPackage ./nix/coil-nvim.nix { }   # the plugin
pkgs.callPackage ./nix/coil.nix { }        # the coil command
```

The flake passes them its pinned oil.nvim instead, and a version built from the git revision.

## The plugin: `nix/coil-nvim.nix`

A `vimUtils.buildVimPlugin` of the repository's `lua/`, `plugin/` and `LICENSE`. oil.nvim is a
dependency, so adding the plugin brings oil along. Arguments: `oil-nvim` (defaults to
`vimPlugins.oil-nvim`) and `version`.

## The command: `nix/coil.nix`

A bare Neovim (`wrapNeovimUnstable` over `neovim-unwrapped`) with coil, oil.nvim and image.nvim.
Arguments: `oil-nvim` and `coil-nvim` (defaults to building `./coil-nvim.nix` with that oil).

- **Only `bin/coil` is installed.** It links to the wrapped Neovim. The wrapped Neovim's own
  `bin/nvim` and `share/` are left out, so installing `coil` into a profile next to your own
  Neovim can't collide. The full wrapped Neovim is available as `passthru.nvim`.
- **It's isolated from your Neovim.** The wrapper sets `NVIM_APPNAME=coil-nvim`, so coil keeps its
  own state and history. It loads its own generated init, not your config.
- **Images.** image.nvim comes from nixpkgs, and ImageMagick is appended to `PATH` (so an
  ImageMagick already on `PATH` wins). The init calls `require("image").setup()` (kitty backend).
  Terminals that don't speak the kitty graphics protocol mostly ignore it.
- **Startup.** The init sets up oil and coil with defaults, then a nested `VimEnter` autocommand
  decides what to open:

  | Started as | Opens |
  |---|---|
  | `coil` | The column view on the current directory |
  | `coil some/dir` | The column view on that directory (by then oil has turned the argument into an `oil:///…/` URL, which counts as a directory too) |
  | `coil dir1 dir2` | A column view per directory, one tab each |
  | `coil oil-ssh://host//path/` | The column view on the remote directory. A URL ending in `/` is a directory, as oil names them; without the slash, coil asks oil's adapter first (for SSH, a round trip to the host), so the view appears once the host answers |
  | `coil file`, or any argument that isn't a directory | Neovim as usual |

  The autocommand is `nested` so that oil's and coil's own autocommands fire from it (see
  [Neovim windows](neovim-windows.md#autocommands-inside-autocommands)).
- **Files open in coil's first tab,** the editing tab, while the column view keeps its own tab.
  `q`/`:CoilClose` closes the column view and leaves the editor open; `:qa` quits.
- **Metadata:** `meta.mainProgram = "coil"`, plus coil's description, homepage and MIT license.

Making `coil` behave more like a dedicated file manager is on the [TODO](todo.md#standalone-coil)
list: `q` quitting, cd on exit, opening non-text files in other programs, a picker mode and more.

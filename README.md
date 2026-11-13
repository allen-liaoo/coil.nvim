# coil.nvim

A column view with file previews for [oil.nvim](https://github.com/stevearc/oil.nvim), in your
Neovim or as a terminal file manager.

## Try it

With [Nix](https://nixos.org/download) (flakes enabled):

```sh
nix run github:allen-liaoo/coil.nvim               # the current directory
nix run github:allen-liaoo/coil.nvim -- ~/some/dir  # a given directory
```

Without flakes enabled, add `--extra-experimental-features 'nix-command flakes'` after `nix`.

## Requirements

- Neovim 0.10 or newer (developed and tested on 0.12)
- [oil.nvim](https://github.com/stevearc/oil.nvim). coil uses some of oil's internals and is
  tested against [v2.16.0](https://github.com/stevearc/oil.nvim/releases/tag/v2.16.0) (the version
  in nixpkgs) and later commits.
- Optional, for images in the preview: [image.nvim](https://github.com/3rd/image.nvim), set up
  with its own `setup()` (coil doesn't set it up for you), and a terminal it can draw in. Videos
  also need [ffmpeg](https://ffmpeg.org), and PDFs [poppler](https://poppler.freedesktop.org)'s
  `pdftoppm`.

## Installation

Set up oil.nvim as usual, then coil. `require("coil").setup()` is optional; call it to change
the defaults.

### lazy.nvim

```lua
{
  "allen-liaoo/coil.nvim",
  dependencies = {
    "stevearc/oil.nvim",
    -- Optional, for images. `opts = {}` runs its setup()
    { "3rd/image.nvim", opts = {} },
  },
  opts = {}, -- see Options
}
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  "https://github.com/stevearc/oil.nvim",
  "https://github.com/allen-liaoo/coil.nvim",
})
require("oil").setup()
require("coil").setup()
```

### Nix

The flake has the plugin as `packages.<system>.coil-nvim` (`nix/coil-nvim.nix` without flakes).
It doesn't bring oil.nvim along: add oil.nvim the way you normally would.

```nix
# Home Manager
programs.neovim.plugins = [
  {
    plugin = pkgs.vimPlugins.oil-nvim;
    type = "lua";
    config = ''require("oil").setup()'';
  }
  {
    plugin = inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.coil-nvim;
    type = "lua";
    config = ''require("coil").setup()'';
  }
];
```

```nix
# nixvim, with its own oil module
{ pkgs, inputs, ... }:
{
  plugins.oil.enable = true;
  extraPlugins = [ inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.coil-nvim ];
  extraConfigLua = ''require("coil").setup()'';
}
```

## Usage

| Command | Does |
|---|---|
| `:Coil [dir...]` | Open the column view on each directory, one tab each (default: the current buffer's directory) |
| `:CoilClose` | Close the column view |
| `:CoilPreview` | In a plain oil window, toggle a preview split that follows the cursor |
| `:CoilClearCache` | Delete the cached image thumbnails |

The middle pane is an oil buffer, and oil's keys work there as usual. coil adds its own, set
with the `keymaps` option:

| Key | Does |
|---|---|
| `L` | Enter a directory, or open a file in your editing tab |
| `H` | Go to the parent directory |
| `q` | Close the column view |
| (none) | Quit Neovim, asking about unsaved changes (`keymaps.quit`) |

## Options

The defaults:

```lua
require("coil").setup({
  -- Relative widths of the parent, current and preview panes
  ratio = { 1, 4, 3 },
  -- Wait this long (ms) after the cursor stops before updating the preview
  debounce_ms = 30,
  -- Name the column view's tab after the current directory. Sets the tab variable `tabname`,
  -- which tab lines such as lualine's `tabs` component show.
  tab_title = true,
  -- Show each pane's path in a title line (winbar) above it
  winbar = false,
  -- coil's own keys in the middle pane; set one to false to disable it. oil's keys are set in
  -- oil's `keymaps`.
  keymaps = {
    go_in = "L", -- Enter a directory; files open in the editing tab
    go_out = "H", -- Go to the parent directory
    close = "q", -- Close the column view (also in the preview pane)
    quit = false, -- Quit Neovim, asking about unsaved changes (also in the preview pane)
  },
  preview = {
    -- Text files larger than this get an info card instead
    max_bytes = 2 * 1024 * 1024,
    -- Read at most this many lines of a text file
    max_lines = 1000,
    -- Bytes read to tell binary from text
    sniff_bytes = 8192,
    -- Wait this long (ms) before showing "Loading..." for a slow directory
    loading_delay_ms = 100,
    -- Draw images (and video frames, PDF pages) with image.nvim when it is installed and set up
    images = true,
    -- Wait this long (ms) after the cursor stops on an image before working on it
    image_delay_ms = 100,
    -- Images are drawn from thumbnails that fit {width, height} pixels (only read by setup())
    thumbnail_size = { 600, 900 },
    -- In the column view, also make thumbnails for images this many entries from the cursor
    prefetch = 2,
    -- Size limit of the thumbnail cache, in MiB; the least recently used go first (false: none)
    thumbnail_cache_mb = 200,
  },
  -- Options for when Neovim is started as a file manager (see below). Takes any option except
  -- itself. These defaults give way to the options you set; your own `standalone` options win
  -- over everything.
  standalone = {
    keymaps = { close = false, quit = "q" },
  },
})
```

Options with the wrong type raise an error naming the option; unknown options only warn. Hidden
files and sorting follow oil's `view_options`.

### Highlights

| Group | Default link | Used for |
|---|---|---|
| `CoilParentSelected` | `Visual` | The current directory in the parent pane |
| `CoilDir`, `CoilLink` | `OilDir`, `OilLink` | Directories and symlinks in the side panes |
| `CoilDirHidden`, `CoilFileHidden`, `CoilLinkHidden` | `OilDirHidden`, `OilFileHidden`, `OilLinkHidden` | Hidden entries in the side panes |
| `CoilCardTitle`, `CoilCardRule` | `Title`, `WinSeparator` | An info card's file name, and the line under it |
| `CoilCardLabel`, `CoilCardValue` | `Identifier`, `Normal` | Its rows |
| `CoilCardNote` | `Comment` | Its notes |

### Lua API

```lua
require("coil").open(dir)            -- like :Coil; a path or oil URL, nil for the current buffer's
require("coil").open({ dir1, dir2 }) -- like :Coil dir1 dir2
require("coil").close()              -- like :CoilClose
require("coil").standalone()         -- whether Neovim was started as a file manager
```

## As a file manager

`coil [dir...]` starts Neovim as a file manager: only the column views, one tab per directory,
and `q` quits. Your shell can also `cd` to the last directory on exit (see
[Shell integration](docs/shell-integration.md)).

### With your own Neovim

Add an alias to your shell's config:

```sh
alias coil='nvim --cmd "let g:coil_standalone = 1"'
```

That starts your Neovim, with your config, plugins and colour scheme, in coil's standalone mode,
which turns on coil's `standalone` options. Your config can check it with
`require("coil").standalone()`, even while it loads:

```lua
require("oil").setup({ delete_to_trash = require("coil").standalone() })
```

- **Don't lazy-load coil then:** it opens the column view during startup. With lazy.nvim,
  `lazy = not vim.g.coil_standalone`.
- **Start screens and session restore run at startup too.** Turn them off the same way, for
  example `enabled = not vim.g.coil_standalone`.
- **For a separate config,** history and state, run it as another Neovim app:
  `NVIM_APPNAME=coil coil` reads `~/.config/coil/init.lua` (which then has to install and set
  up oil.nvim and coil itself).

### Without Neovim

The flake's default package is a ready-made `coil`: Neovim with coil, oil.nvim, image.nvim and
mini.icons, plus ImageMagick, ffmpeg and poppler for previews. It installs only `bin/coil`, so it
doesn't clash with a Neovim of your own.

```sh
nix profile install github:allen-liaoo/coil.nvim
```

```nix
# Home Manager (nix/coil.nix without flakes)
home.packages = [ inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default ];
```

It runs as its own Neovim app (`NVIM_APPNAME=coil`), so its config is `~/.config/coil/init.lua`,
an ordinary Neovim config. After that runs, `coil` sets up any bundled plugin it didn't:

- **oil.nvim** with `delete_to_trash = true` (oil's trash view, `g\`, restores files) and the
  permissions, size and modification time columns
- **image.nvim** and **mini.icons** with their defaults
- **the `habamax` colour scheme**, if none is set

Set one up yourself and your options are used as they are:

```lua
-- ~/.config/coil/init.lua
require("oil").setup({ view_options = { show_hidden = true } })
require("coil").setup({ ratio = { 1, 3, 4 } }) -- see Options
vim.cmd.colorscheme("retrobox")
```

Images need a terminal that speaks the kitty graphics protocol (kitty, Ghostty, WezTerm).

## Development

```sh
nix develop      # or `direnv allow`
make test        # headless test suite
make dev         # your editor with this working copy of coil loaded
make dev-clean   # the same in a clean Neovim
make fmt         # format with stylua
```

## License

MIT

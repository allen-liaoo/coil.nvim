# coil.nvim

A yazi-style column view and file preview for [oil.nvim](https://github.com/stevearc/oil.nvim).

```
┌──────────┬────────────────────────┬───────────────────┐
│ parent   │ current                │ preview           │
│  home/   │   Documents/           │ # notes.md        │
│ >me/     │ > notes.md             │                   │
│  srv/    │   todo.txt             │ Some text from    │
│          │                        │ the file...       │
└──────────┴────────────────────────┴───────────────────┘
```

`:Coil` opens a tab with three panes. The **middle pane is a normal oil buffer**, so everything
oil does still works there: rename a file by editing its name, delete a line, paste a line from
another directory, then `:w`. The **parent pane** shows the directory above, with the one you're
in highlighted. The **preview pane** follows your cursor: text files, directory listings, and an
info card for everything else.

Outside the column view, oil behaves exactly as before.

You can use coil in two ways:

- **As a plugin** in your own Neovim: add it next to oil.nvim and run `:Coil` (see
  [Installation](#installation)).
- **As a standalone terminal file manager**, like yazi or ranger: the `coil` command opens the
  column view straight away, and files you open are edited in the same program (see
  [Standalone file manager](#standalone-file-manager)).

## Try it

With [Nix](https://nixos.org/download) (flakes enabled):

```sh
nix run github:allen-liaoo/coil.nvim               # column view on the current directory
nix run github:allen-liaoo/coil.nvim -- ~/some/dir  # ...or on a given directory
```

This runs the standalone `coil` file manager without installing anything. Without flakes
enabled, add `--extra-experimental-features 'nix-command flakes'` after `nix`.

## Requirements

- Neovim 0.10 or newer (developed and tested on 0.12)
- Optional: [image.nvim](https://github.com/3rd/image.nvim), set up with its `setup()`, to draw
  images in the preview, plus [ffmpeg](https://ffmpeg.org) for video frames and
  [poppler](https://poppler.freedesktop.org)'s `pdftoppm` for PDF pages (see [Images](#images))
- [oil.nvim](https://github.com/stevearc/oil.nvim). coil uses some of oil's internals and is
  tested against [v2.16.0](https://github.com/stevearc/oil.nvim/releases/tag/v2.16.0) (the version
  in nixpkgs) and later commits; much newer or older versions of oil may need changes.

## Installation (as Neovim Plugin)

Set up oil.nvim as usual, then coil. `require("coil").setup()` is optional; call it to change
the defaults.

### lazy.nvim

```lua
{
  "allen-liaoo/coil.nvim",
  dependencies = {
    "stevearc/oil.nvim",
    -- Optional, to draw images in the preview. `opts = {}` runs its setup(), which coil needs
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

The flake exposes the plugin as `packages.<system>.coil-nvim` (the default package is the
standalone `coil` command). The plugin doesn't bring oil.nvim along: add oil.nvim the way you
normally would (nixpkgs' `vimPlugins.oil-nvim`, or your Neovim setup's oil module).

Without flakes, both are plain `callPackage` files: `nix/coil-nvim.nix` (the plugin) and
`nix/coil.nix` (the standalone command, with nixpkgs' oil.nvim).

```nix
# flake.nix
inputs.coil-nvim.url = "github:allen-liaoo/coil.nvim";
```

Home Manager:

```nix
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

nixvim, with its own oil module:

```nix
{ pkgs, inputs, ... }:
{
  plugins.oil.enable = true;
  extraPlugins = [ inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.coil-nvim ];
  extraConfigLua = ''require("coil").setup()'';
}
```

## Quick start

| Command | Does |
|---|---|
| `:Coil [dir...]` | Open the column view on `dir`, or on the current buffer's directory (with the cursor on the file you were editing). In a column view's tab, that view moves to `dir`; elsewhere, coil switches to the view you used last. With several directories, each further one opens in a column view of its own tab, like yazi's tabs; focus stays on the first. |
| `:CoilClose` | Close the current tab's column view (elsewhere, the one used last) and return to the window you came from. |
| `:CoilPreview` | In any ordinary oil window: toggle a preview split that follows the cursor. |
| `:CoilClearCache` | Delete the cached image thumbnails (see [Images](#images)). |

Keys in the column view's **middle pane**:

coil's own keys (set with the `keymaps` option):

| Key | Does |
|---|---|
| `L` | Enter a directory. On a file, open it in your editing tab. |
| `H` | Go to the parent directory. |
| `q` | Close the column view (also works in the preview pane). |

oil's keys, which coil changes in the middle pane. They are whatever you map these oil actions to
in oil's `keymaps`; oil's defaults are shown:

| oil action | Default | In the middle pane |
|---|---|---|
| `actions.select` | `<CR>` | Like `L`. Also works on a visual selection. |
| `actions.select` with `vertical` / `horizontal` / `tab` | `<C-s>` / `<C-h>` / `<C-t>` | Open in a vertical split / horizontal split / new tab in your editing tab. Also works on a visual selection. |
| `actions.preview` | `<C-p>` | Jump into the preview pane. Press it there to come back. |
| `actions.toggle_hidden` | `g.` | Toggle hidden files in every pane, keeping the cursor on the same entry. |
| `actions.close` | `<C-c>` | Close the column view (also in the preview pane). |

All of oil's other keys work as usual in the middle pane, for example `-` for the parent
directory and `<C-l>` to refresh. In any other window, coil's keys keep their normal meaning:
oil's mapping in oil buffers, otherwise Vim's own key.

How the column view behaves:

- **Files open in your editing tab:** the window you ran `:Coil` from, then wherever the last
  file opened. The column view stays open in its tab, so you can switch back with `:Coil` or
  your usual tab keys.
- **Editing works like oil.** `:w` in any oil buffer saves the changes in all of them, and the
  side panes refresh afterwards.
- **The parent pane is display-only.** Moving into it puts you back in the middle pane.
- **Click an entry to jump to it.** Clicking an entry in the parent pane, or in a directory
  preview, moves the middle pane to that entry's directory with the cursor on it.
- **The preview pane is read-only,** but you can move into it to scroll or copy text.
- **Closing any pane,** or the tab, closes the whole view.
- **The tab is named after the current directory** (see `tab_title`), which tab lines like
  lualine's `tabs` component display.
- **Several column views can be open,** one per tab (`:Coil dir1 dir2`). Switch between them
  with your usual tab keys (`gt`, `gT`). Each has its own directory, and files from any of them
  open in your editing tab, never in another view's tab.

### Previews

| Entry | Preview |
|---|---|
| Directory | Its entries, sorted and filtered like oil (hidden entries greyed out when shown) |
| Text file | The first lines, syntax-highlighted |
| Image | An info card (with the image's dimensions) and the image drawn below it by [image.nvim](https://github.com/3rd/image.nvim) (see [Images](#images)). Without image.nvim, the card alone. |
| Video | An info card and a frame from 10% into the video, drawn below it (needs image.nvim and ffmpeg) |
| PDF | An info card and the first page, drawn below it (needs image.nvim and poppler's `pdftoppm`) |
| Anything else (binary, audio, archive, very large files) | An info card: kind, size, modified time, permissions, location |

Info cards are laid out and highlighted by coil (filetype `coil_card`), so markdown plugins leave
them alone, and they look the same whether or not the preview has focus.

Files on remote oil adapters (SSH, S3) show a card for now; remote directories are listed
normally.

### Images

With [image.nvim](https://github.com/3rd/image.nvim) installed and set up, coil draws images in the
preview, filling the space below the info card. It does the same for videos (a frame 10% of the
way in, made with `ffmpeg`) and PDFs (the first page, made with `pdftoppm`) when those tools are
installed; otherwise their cards say what to install. coil calls image.nvim directly, so image.nvim's
markdown integration isn't needed.

**coil doesn't set image.nvim up for you.** Call its `setup()` yourself, before or after coil's;
until it has run, coil shows image cards without the image:

```lua
require("image").setup() -- with lazy.nvim, `opts = {}` in image.nvim's spec does this
```

image.nvim needs ImageMagick (`magick` or `convert` on `PATH`) and a terminal it can draw in: for
its default backend, one that speaks the kitty graphics protocol (kitty, Ghostty, WezTerm). See
its README for other backends and options.

- **Images are drawn from thumbnails.** coil shrinks each image to fit `preview.thumbnail_size`
  (600×900 by default) with ImageMagick, in the background, and keeps the thumbnail in
  `stdpath("cache")/coil/thumbnails`, so Neovim keeps responding and an image you've seen comes
  back at once. The card says "Loading image..." until the thumbnail is ready. coil also makes a
  copy at the exact size image.nvim will draw it at, so image.nvim doesn't have to resize it.
  (Left to itself, image.nvim converts and resizes the full-size image while Neovim waits, which
  takes seconds for a large photo.)
- Work on an image starts once the cursor has rested on it for `preview.image_delay_ms`, so
  scrolling past images doesn't start a thumbnail for each.
- In the column view, thumbnails are also made for the images up to `preview.prefetch` entries
  above and below the cursor (2 by default), so they're ready when you get there.
- The cache is kept under `preview.thumbnail_cache_mb` (200 MiB by default) by deleting the
  thumbnails used longest ago. `:CoilClearCache` empties it.
- The image is redrawn when the pane is resized or scrolled and when you come back to the tab,
  and removed when the preview changes.
- Without ImageMagick's command-line tools (if image.nvim uses its `magick_rock` processor),
  image.nvim gets the original file.
- Videos and PDFs go through the same thumbnails, cache and prefetching as images.
- Set `preview.images = false` to show cards without pictures.

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
  -- coil's own keys in the middle pane; set one to false to disable it. oil's keys (select,
  -- preview, toggle hidden, close) are set in oil's `keymaps`; see Quick start
  keymaps = {
    go_in = "L", -- Enter a directory; files open in the editing tab
    go_out = "H", -- Go to the parent directory
    close = "q", -- Close the column view (also in the preview pane)
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
})
```

Options with the wrong type raise an error naming the option. Unknown options only produce a
warning.

Hidden files, sorting and other listing behaviour follow your oil.nvim settings
(`view_options`).

### Highlights

| Group | Default link | Used for |
|---|---|---|
| `CoilParentSelected` | `Visual` | The current directory in the parent pane |
| `CoilDir` | `OilDir` (or `Directory`) | Directories in the side panes |
| `CoilLink` | `OilLink` (or `Constant`) | Symlinks in the side panes |
| `CoilDirHidden`, `CoilFileHidden`, `CoilLinkHidden` | `OilDirHidden`, `OilFileHidden`, `OilLinkHidden` (or `Comment`) | Hidden entries in the side panes |
| `CoilCardTitle` | `Title` | An info card's file name |
| `CoilCardRule` | `WinSeparator` | The line under it |
| `CoilCardLabel`, `CoilCardValue` | `Identifier`, `Normal` | Its rows (`Size`, `3.3M`, ...) |
| `CoilCardNote` | `Comment` | Its notes, and "Loading image..." |

### Lua API

```lua
require("coil").open(dir)  -- like :Coil; dir is a path or an oil URL, nil for the current buffer's
require("coil").open({ dir1, dir2 }) -- like :Coil dir1 dir2: one tab per directory
require("coil").close()    -- like :CoilClose
```

## Standalone file manager

The flake's default package is a `coil` command: a Neovim with coil, oil.nvim, image.nvim,
mini.icons (icons in oil's listing), Tree-sitter grammars for highlighting text previews, and
ImageMagick, ffmpeg and poppler for image, video and PDF previews. It opens the column view as
soon as it starts.

```sh
nix profile install github:allen-liaoo/coil.nvim   # or add it to home.packages / environment.systemPackages

coil                         # browse the current directory
coil ~/Downloads             # browse a directory
coil ~/Downloads ~/Pictures  # one tab per directory
coil notes.md                # anything that isn't all directories opens as in Neovim
```

```nix
# Home Manager
home.packages = [ inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default ];
```

Things to know:

- **It installs only `bin/coil`,** so it sits next to your own Neovim without clashing.
- **It doesn't read your Neovim config.** It runs as its own Neovim app (`NVIM_APPNAME=coil`),
  so its history and state are kept apart from yours too. It has a config file of its own; see
  [Configuring the standalone command](#configuring-the-standalone-command).
- **Deleting files moves them to the trash.** Delete a line and save, and the file goes to the
  trash rather than being removed; oil's trash view (`g\`) shows it and can restore it. Set
  `oil = { delete_to_trash = false }` in the [config file](#configuring-the-standalone-command)
  to delete for good.
- **Images are drawn with the kitty graphics protocol** (kitty, Ghostty, WezTerm). In other
  terminals, image previews show the info card alone.
- **It starts with only the column views,** one tab per directory. Opening a file edits it in a
  new tab, and the next files open next to it; the column views stay open in their tabs. `q` or
  `:CoilClose` closes a column view; `:qa` quits.

### Configuring the standalone command

`coil` runs `~/.config/coil/init.lua` (`$XDG_CONFIG_HOME/coil/init.lua`) if it exists. It's
plain Lua, run before anything is set up, so it can set options and keymaps. It can also return
setup options for oil.nvim, coil and image.nvim, which are merged into the build's own:

```lua
-- ~/.config/coil/init.lua
vim.o.number = true

return {
  oil = { view_options = { show_hidden = true } }, -- oil.nvim's setup() options
  coil = { ratio = { 1, 3, 4 } }, -- coil's (see Options)
  image = false, -- image.nvim's, or false to leave image previews off
  icons = {}, -- mini.icons', or false to leave icons off
}
```

If the file has an error, `coil` says so and starts with its defaults.

Without Nix, you can get close with your own Neovim and a shell function:

```sh
coil() { nvim +"Coil ${1:-.}"; }
```


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

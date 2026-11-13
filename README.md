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
in highlighted. The **preview pane** follows your cursor: text files, directory listings, and a
metadata card for everything else.

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
  images in the preview (see [Images](#images))
- [oil.nvim](https://github.com/stevearc/oil.nvim). coil uses some of oil's internals and is
  tested against commit [`d3733d9`](https://github.com/stevearc/oil.nvim/tree/d3733d933833a0e59b813ecec99341527adf0c28);
  much newer or older versions of oil may need changes.

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
standalone `coil` command). The plugin brings the oil.nvim commit it's tested against as a
dependency, so don't add a second oil plugin.

Without flakes, both are plain `callPackage` files, using nixpkgs' oil.nvim by default:
`nix/coil-nvim.nix` (the plugin) and `nix/coil.nix` (the standalone command).

```nix
# flake.nix
inputs.coil-nvim.url = "github:allen-liaoo/coil.nvim";
```

Home Manager:

```nix
programs.neovim.plugins = [
  {
    plugin = inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.coil-nvim;
    type = "lua";
    config = ''
      require("oil").setup()
      require("coil").setup()
    '';
  }
];
```

nixvim, using coil's oil.nvim for nixvim's oil module:

```nix
{ pkgs, inputs, ... }:
let
  coil = inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  plugins.oil = {
    enable = true;
    package = coil.oil-nvim;
  };
  extraPlugins = [ coil.coil-nvim ];
  extraConfigLua = ''require("coil").setup()'';
}
```

## Quick start

| Command | Does |
|---|---|
| `:Coil [dir]` | Open the column view on `dir`, or on the current buffer's directory (with the cursor on the file you were editing). If the view is already open, switch to it. |
| `:CoilClose` | Close the column view and return to the window you came from. |
| `:CoilPreview` | In any ordinary oil window: toggle a preview split that follows the cursor. |

Keys in the column view's **middle pane**:

| Key | Does |
|---|---|
| `L`, `<CR>` | Enter a directory. On a file, open it in your editing tab. |
| `H` | Go to the parent directory. |
| `<C-s>` / `<C-h>` / `<C-t>` | Open in a vertical split / horizontal split / new tab in your editing tab. Also works on a visual selection. |
| `<C-p>` | Jump into the preview pane. Press it there to come back. |
| `g.` | Toggle hidden files in every pane, keeping the cursor on the same entry. |
| `q` | Close the column view (also works in the preview pane). |

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

### Previews

| Entry | Preview |
|---|---|
| Directory | Its entries, sorted and filtered like oil (hidden entries greyed out when shown) |
| Text file | The first lines, syntax-highlighted |
| Image | A metadata card with the image drawn below it by [image.nvim](https://github.com/3rd/image.nvim) (see [Images](#images)). Without image.nvim, the card embeds the image as `![name](/path)` for another markdown image plugin, such as [snacks.nvim](https://github.com/folke/snacks.nvim), to draw. |
| Anything else (binary, video, PDF, archive, very large files) | A markdown card: kind, size, modified time, permissions, location |

Files on remote oil adapters (SSH, S3) show a card for now; remote directories are listed
normally.

### Images

With [image.nvim](https://github.com/3rd/image.nvim) installed and set up, coil draws images in the
preview, filling the space below the metadata card. coil calls image.nvim directly, so image.nvim's
markdown integration isn't needed.

**coil doesn't set image.nvim up for you.** Call its `setup()` yourself, before or after coil's;
until it has run, coil shows image cards without the image:

```lua
require("image").setup() -- with lazy.nvim, `opts = {}` in image.nvim's spec does this
```

image.nvim needs ImageMagick (`magick` or `convert` on `PATH`) and a terminal it can draw in: for
its default backend, one that speaks the kitty graphics protocol (kitty, Ghostty, WezTerm), and
inside tmux, `set -g allow-passthrough on`. See its README for other backends and options.

- The image is drawn once the cursor has rested on the file for `preview.image_delay_ms`, because
  image.nvim converts and resizes images while Neovim waits.
- It's redrawn when the pane is resized or scrolled and when you come back to the tab, and removed
  when the preview changes.
- Set `preview.images = false` to get the `![](path)` card instead.

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
  -- Keys in the middle pane; set one to false to disable it
  keymaps = {
    go_in = "L", -- Enter a directory; files open in the editing tab
    go_out = "H", -- Go to the parent directory
    open = "<CR>", -- Same as go_in
    open_vsplit = "<C-s>", -- Open in a vertical split in the editing tab
    open_split = "<C-h>", -- Open in a horizontal split in the editing tab
    open_tab = "<C-t>", -- Open in a new tab
    focus_preview = "<C-p>", -- Jump into the preview pane (press again there to come back)
    toggle_hidden = "g.", -- Toggle hidden files, refreshing every pane
    close = "q", -- Close the column view
  },
  preview = {
    -- Text files larger than this get a metadata card instead
    max_bytes = 2 * 1024 * 1024,
    -- Read at most this many lines of a text file
    max_lines = 1000,
    -- Bytes read to tell binary from text
    sniff_bytes = 8192,
    -- Filetype of metadata cards (markdown, so image plugins can draw embedded images)
    card_filetype = "markdown",
    -- Wait this long (ms) before showing "Loading..." for a slow directory
    loading_delay_ms = 100,
    -- Draw images with image.nvim when it is installed and set up
    images = true,
    -- Wait this long (ms) after the cursor stops on an image before drawing it
    image_delay_ms = 100,
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

### Lua API

```lua
require("coil").open(dir)  -- like :Coil; dir is a path or an oil URL, nil for the current buffer's
require("coil").close()    -- like :CoilClose
```

## Standalone file manager

The flake's default package is a `coil` command: a bare Neovim with coil, oil.nvim and
image.nvim (plus ImageMagick), which opens the column view as soon as it starts.

```sh
nix profile install github:allen-liaoo/coil.nvim   # or add it to home.packages / environment.systemPackages

coil              # browse the current directory
coil ~/Downloads  # browse a directory
coil notes.md     # anything that isn't a single directory opens as in Neovim
```

```nix
# Home Manager
home.packages = [ inputs.coil-nvim.packages.${pkgs.stdenv.hostPlatform.system}.default ];
```

Things to know:

- **It installs only `bin/coil`,** so it sits next to your own Neovim without clashing.
- **It doesn't read your Neovim config.** It runs as its own Neovim app
  (`NVIM_APPNAME=coil-nvim`), so its history and state are kept apart from yours too.
- **Images are drawn with the kitty graphics protocol** (kitty, Ghostty, WezTerm). Inside tmux
  this needs `set -g allow-passthrough on`. In other terminals, image previews show the metadata
  card alone.
- **Opening a file edits it in coil's first tab.** The column view stays open in its own tab.
  `q` or `:CoilClose` closes the column view and leaves you in the editor; `:qa` quits.

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

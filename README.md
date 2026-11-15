# coil.nvim

A column view with file previews for [oil.nvim](https://github.com/stevearc/oil.nvim), in your Neovim or as a terminal file manager.

## Try it

With [Nix](https://nixos.org/download) (flakes enabled):

```sh
nix run github:allen-liaoo/coil.nvim               # the current directory
nix run github:allen-liaoo/coil.nvim -- ~/some/dir  # a given directory
```

## Requirements

- Neovim 0.10 or newer (developed and tested on 0.12)
- [oil.nvim](https://github.com/stevearc/oil.nvim). coil uses some of oil's internals.
- For images in the preview (optional): [image.nvim](https://github.com/3rd/image.nvim). Install [ImageMagick](https://github.com/ImageMagick/ImageMagick), and use a terminal it can draw in.
    Video thumbnails need [ffmpeg](https://ffmpeg.org), and PDFs need [poppler](https://poppler.freedesktop.org)'s `pdftoppm`.
- For previews of remote files: what oil uses for them, `scp` for SSH and the `aws` CLI for S3.
    Previews never ask for a password, so SSH hosts need key or agent authentication (or an open
    `ControlMaster` connection); otherwise the preview says why it can't download the file.
- For git status (optional): supports [oil-git-status.nvim](https://github.com/refractalize/oil-git-status.nvim).
    The side panes are oil buffers, so its signs show in all three panes.

`:checkhealth coil` checks these, and the [`coil` command](#bring-your-own-neovim) on your `PATH`.

<details>
<summary>Tmux Setup</summary>
If you are using tmux, image.nvim need this setup:

```lua
require("image").setup({
  -- The default, cursor-based kitty method puts images at the cursor in tmux
  kitty_method = "unicode-placeholders",
  -- Show images only in the active tmux window
  tmux_show_only_in_active_window = true,
})
```
Tmux needs this config:
```tmux
set -gq allow-passthrough on
set -g visual-activity off
set -g focus-events on
```
</details>

## Installation (As Neovim Plugin)

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
-- require("image").setup()
require("coil").setup()
```

### Nix

The flake has the plugin as `packages.<system>.coil-nvim` (`nix/coil-nvim.nix` without flakes).
It doesn't bring oil.nvim along: add oil.nvim the way you normally would.

For [nixvim](https://github.com/nix-community/nixvim), the flake has a module,
`nixvimModules.default`, with `plugins.coil` like nixvim's own plugins. 

## As Standalone File Manager

You can either use your neovim + coil.nvim as a standalone file manager, or use our (nix) distributed `coil` binary.
Standalone coil differs from coil-as-a-plugin: everything opens in system's default programs, `q` quits neovim,
and you can setup [shell integration](docs/shell-integration.md) so it will automatically `cd` to the last directory on exit.

Once setup:
```sh
coil [dir1] [dir2] ...
```

`coil --help` lists its options:

- `--cwd-file <path>`: on exit, write the last directory to `<path>`, for a shell function to
  `cd` there ([shell integration](docs/shell-integration.md)).
- `--chooser-file <path>`: pick files for another program. Opening a file writes its path to
  `<path>` and quits; a visual selection picks all its entries, directories included. One path
  per line. Directories still open as usual, and quitting without picking writes nothing. A file
  argument opens its directory with the cursor on it, so a save dialog can suggest a file name.

### Bring Your Own Neovim

The plugin comes with a `coil` command, `bin/coil`. Run `:CoilInstallCli` to put it on your
`PATH`: it links `~/.local/bin/coil` (or `:CoilInstallCli <dir>` for `<dir>/coil`) to the
plugin's copy, so updating the plugin updates the command too. A link of your own works the same:

```sh
# With lazy.nvim's default install directory
ln -s ~/.local/share/nvim/lazy/coil.nvim/bin/coil ~/.local/bin/coil
```

It starts your Neovim (`nvim`, or `$COIL_NVIM`), with your config, plugins and colour scheme, in
coil's standalone mode, which turns on coil's `standalone` options. `coil --help` lists its
options. Without the command, `nvim --cmd "let g:coil_standalone = 1"` starts the same mode.

Your config can check the mode with
`require("coil").standalone()`, even while it loads:

```lua
require("oil").setup({
  delete_to_trash = require("coil").standalone(),
  watch_for_changes = true,
})
```

- **Don't lazy-load coil:** If using lazy.nvim,
  `lazy = not vim.g.coil_standalone`.
- **For a separate config,** history and state, run it as another Neovim app:
  `COIL_APPNAME=coil coil` makes it read `~/.config/coil/init.lua` (which then has to install and
  set up oil.nvim and coil itself). Editors coil starts still get your own `NVIM_APPNAME`.

### Without Neovim

The flake's default package is a `coil` binary: Neovim with coil, plus all its plugin and binary dependencies necessary for preview. It installs only coil's commands
(`bin/coil`), so it doesn't clash
with a Neovim of your own.

```sh
nix profile install github:allen-liaoo/coil.nvim
```

It runs as its own Neovim app (`NVIM_APPNAME=coil`), so its config is `~/.config/coil/init.lua`,
an ordinary Neovim config. After that runs, `coil` sets up any bundled plugin it didn't:

```lua
-- ~/.config/coil/init.lua
require("oil").setup({ view_options = { show_hidden = true } })
require("coil").setup({ ratio = { 1, 3, 4 } }) -- see Options
vim.cmd.colorscheme("retrobox")
```

### As your system's file picker

On Linux, [xdg-desktop-portal-termfilechooser](https://github.com/hunkyburrito/xdg-desktop-portal-termfilechooser)
makes apps' open and save dialogs run a terminal file manager. coil comes with a wrapper for it,
`bin/coil-termfilechooser`, next to `bin/coil` (in the plugin and in the Nix `coil`). Set it as the
portal's `cmd` in `~/.config/xdg-desktop-portal-termfilechooser/config`:

```ini
[filechooser]
cmd=/path/to/coil.nvim/bin/coil-termfilechooser
default_dir=$HOME
open_mode=suggested
save_mode=suggested
; The terminal to run coil in, with any options it takes. Without it: xdg-terminal-exec, else
; $TERMINAL -e
; env=TERMCMD=<terminal> <options>
; Any of coil's own settings, such as the Neovim to run
; env=COIL_NVIM=nvim
```

Then restart the portal (`systemctl --user restart xdg-desktop-portal-termfilechooser`). In the
dialog, choose files as with `--chooser-file`. A save dialog starts on the suggested file: choose
it, or another file. To choose a directory, choose it in a visual selection, or quit inside it.

## Usage

| Command | Does |
|---|---|
| `:Coil [dir...]` | Open the column view on each directory, one tab each (default: the current buffer's directory) |
| `:CoilClose` | Close the column view |
| `:CoilPreview` | In a plain oil window, toggle a preview split that follows the cursor |
| `:CoilClearCache` | Delete the cached image thumbnails |
| `:CoilInstallCli [dir]` | Link the [`coil` command](#bring-your-own-neovim) into `~/.local/bin` (or `dir`) |

The middle pane is an oil buffer, and oil's keys work there as usual, except some behaviors are changed.
coil adds its own keymaps, set with the `keymaps` option:

| Key | Does |
|---|---|
| `L` | Enter a directory, or open a file in your editing tab |
| `H` | Go to the parent directory |
| `q` | Close the column view |
| (none) | Quit Neovim, asking about unsaved changes (`keymaps.quit`) |

Commands typed in the middle pane that open something, such as `:Oil`, `:edit file`, `:buffer` or
`:vsplit`, run in your editing tab instead, so plain oil is always one command away, even for the
directory the middle pane shows. `:Coil dir` moves the column view, `:edit` on its own reloads the
middle pane, and other commands (`:w`, `:s`, ...) run there as usual.


## Options

```lua
require("coil").setup({
  -- Relative widths of the parent, current and preview panes
  ratio = { 1, 4, 3 },
  -- Wait this long (ms) after the cursor stops before updating the preview
  debounce_ms = 30,
  -- Name the column view's tab after the current directory. Sets the tab variable `tabname`,
  -- which tab lines such as lualine's `tabs` component show.
  tab_title = true,
  -- Open files that aren't text (images, videos, audio, PDFs, archives, other
  -- binary files) in the system's default program instead of the editor. Local files only; the
  -- split and tab keys still open them in the editor.
  open_external = false,
  -- Open text files in this Neovim. When false, they open in the system's text
  -- editor: XDG's default for text/plain, otherwise $VISUAL or $EDITOR, otherwise here. Editors
  -- that need a terminal open in a new terminal window (xdg-terminal-exec or $TERMINAL). Local
  -- files only; the split and tab keys still open them here.
  edit_here = true,
  -- Show each pane's path in a title line (winbar) above it
  winbar = false,
  -- coil's own keys in the middle pane; set one to false to disable it. Coil make change oil's keymap
  -- behaviors when you're using coil's panes (as opposed to ordinary oil buffers)
  keymaps = {
    go_in = "L", -- Enter a directory; files open in the editing tab
    go_out = "H", -- Go to the parent directory
    close = "q", -- Close the column view (also in the preview pane)
    quit = false, -- Quit Neovim, asking about unsaved changes (also in the preview pane)
  },
  preview = {
    -- Text files larger than this get no text preview
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
    -- Remote files (SSH, S3) are downloaded for a preview. Wait this long (ms) after the cursor
    -- stops on one before downloading it
    remote_delay_ms = 200,
    -- Remote images, videos and PDFs larger than this aren't downloaded (other files: max_bytes)
    remote_max_bytes = 20 * 1024 * 1024,
    -- Size limit of the downloaded copies, in MiB (false: none). They are deleted when Neovim exits.
    remote_cache_mb = 100,
  },
  -- Options for when Neovim is started as a file manager (see below). Takes any option except
  -- itself. These defaults give way to the options you set; your own `standalone` options win
  -- over everything.
  standalone = {
    open_external = true,
    edit_here = false,
    keymaps = { close = false, quit = "q" },
  },
})
```

<!-- ### Highlights -->
<!-- coil uses these highlights: -->
<!---->
<!-- | Group | Default link | Used for | -->
<!-- |---|---|---| -->
<!-- | `CoilParentSelected` | `Visual` | The current directory in the parent pane | -->
<!-- | `CoilDir`, `CoilLink` | `OilDir`, `OilLink` | Directories and symlinks in the side panes | -->
<!-- | `CoilDirHidden`, `CoilFileHidden`, `CoilLinkHidden` | `OilDirHidden`, `OilFileHidden`, `OilLinkHidden` | Hidden entries in the side panes | -->
<!---->
<!-- ### Lua API -->
<!---->
<!-- ```lua -->
<!-- require("coil").open(dir)            -- like :Coil; a path or oil URL, nil for the current buffer's -->
<!-- require("coil").open({ dir1, dir2 }) -- like :Coil dir1 dir2 -->
<!-- require("coil").close()              -- like :CoilClose -->
<!-- require("coil").standalone()         -- whether Neovim was started as a file manager -->
<!-- ``` -->

## Development

```sh
nix develop                         # or `direnv allow`
make test                           # headless test suite
make dev                            # your editor with this working copy of coil loaded
make dev-clean                      # the same in a clean Neovim
make dev-standalone ARGS="~/a ~/b"  # your editor as a file manager, with this working copy
make dev-standalone-clean           # the same in a clean Neovim
nix run .                           # the Nix coil from this working copy (files known to git)
make fmt                            # format with stylua
```

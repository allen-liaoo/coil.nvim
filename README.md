# coil.nvim

Column view with file previews for [oil.nvim](https://github.com/stevearc/oil.nvim), in your Neovim or as a terminal file manager.

![coil-nvim](https://github.com/user-attachments/assets/41a8f2af-3c78-440b-9443-e136d56e3453)

## Try it

With [Nix](https://nixos.org/download) (flakes enabled):

```sh
nix run github:allen-liaoo/coil.nvim               # the current directory
nix run github:allen-liaoo/coil.nvim -- ~/some/dir  # a given directory
```

## Requirements

- Neovim 0.10 or newer (developed and tested on 0.12)
- [oil.nvim](https://github.com/stevearc/oil.nvim). coil uses some of oil's internals.
- For images in the preview (optional): [image.nvim](https://github.com/3rd/image.nvim) (requires [ImageMagick](https://github.com/ImageMagick/ImageMagick)).
    Video thumbnails need [ffmpeg](https://ffmpeg.org), and PDFs need [poppler](https://poppler.freedesktop.org)'s `pdftoppm`.
- For previews of remote files: `scp` for SSH and the `aws` CLI for S3 (same requirements as oil).
- For git status (optional): supports [oil-git-status.nvim](https://github.com/refractalize/oil-git-status.nvim).

<details>
<summary>Preview Under Tmux</summary>
If you are using tmux, image.nvim need this setup:

```lua
require("image").setup({
-- The default, cursor-based kitty method puts images at the cursor in tmux
kitty_method = "unicode-placeholders",
-- Show images only in the active tmux window
tmux_show_only_in_active_window = true,
})
```
</details>

## As Neovim Plugin

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

## As Standalone File Manager

You can use your neovim + coil.nvim as a standalone file manager.
Standalone coil differs from coil-as-a-plugin: everything opens in system's default programs, `q` quits neovim,
and you can setup [shell integration](doc/shell-integration.md) so it will automatically `cd` to the last directory on exit.
```
Usage: coil [options] [directory...]

Opens the directories (the current one by default) in coil's column view.

Options:
  --cwd-file <path>      On exit, write the last directory to <path>
  --chooser-file <path>  Choose files instead of opening them: write their paths to <path>, one
                         per line, and quit. A visual selection chooses all its entries.
  -h, --help             Show this help and exit
  -v, --version          Show coil's version and exit

Other arguments go to Neovim. After --, all arguments are file names.
```

The `coil` binary comes with the plugin in `bin/coil` (different for [Nix](#nix) users). Run `:CoilInstallCli` to put it on your
`~/.local/bin/coil`. It starts your Neovim (`nvim`, or `$COIL_NVIM`), with your config in
coil's standalone mode, which turns on coil's `standalone` options. 

Your config can check the mode with `require("coil").standalone()`, 
which you can choose to conditionally enable behavior only in standalone mode:
```lua
require("oil").setup({
  delete_to_trash = require("coil").standalone(),
  watch_for_changes = true,
})
```

- **Don't lazy-load coil:** If using lazy.nvim,
  `lazy = not vim.g.coil_standalone`.
- **For a separate config,** history and state, run it as another Neovim app:
  `COIL_APPNAME=coil` makes it read `~/.config/coil/init.lua` (which then has to install and
  set up oil.nvim and coil itself).

### As System's File Chooser

On Linux, [xdg-desktop-portal-termfilechooser](https://github.com/hunkyburrito/xdg-desktop-portal-termfilechooser)
makes apps' open and save dialogs run a terminal file manager. coil comes with a wrapper for it,
`bin/coil-termfilechooser`, which runs the `coil` next to it (different for [Nix](#nix) users).
Set it as the portal's `cmd` in `~/.config/xdg-desktop-portal-termfilechooser/config`:

```ini
[filechooser]
cmd=/path/to/coil.nvim/bin/coil-termfilechooser
default_dir=$HOME
open_mode=suggested
save_mode=suggested
; Set TERMCMD to set the terminal to run coil in, with any options it takes. 
; Otherwise it falls back to xdg-terminal-exec, else $TERMINAL -e. 
; env=TERMCMD='<terminal> <options>'
; Any of coil's own settings, such as the Neovim to run
; env=COIL_NVIM=nvim
```

To choose a file, open it. To choose a directory, open it during a visual selection, or quit inside it.
`Q` (or `:cq`) cancels without choosing any file/directory. 

## Usage

| Command | Does |
|---|---|
| `:Coil [dir...]` | Open the column view on each directory, one tab each (default: the current buffer's directory) |
| `:CoilClose` | Close the column view |
| `:CoilPreview` | In a plain oil window, toggle a preview split that follows the cursor |
| `:CoilClearCache` | Delete the cached image thumbnails |
| `:CoilInstallCli [dir]` | Link the [`coil` command](#as-standalone-file-manager) into `~/.local/bin` (or `dir`) |

The middle pane is an oil buffer, and oil's keys work there as usual, except some behaviors are changed (i.e. `<C-h>` opens horizontal split in the editor tab, not the tab showing coil).
coil adds its own keys, set with the `keymaps` option the way oil's `keymaps` is set. Their
defaults differ in [standalone mode](#as-standalone-file-manager); "none" means no key until you
map one:

| Action | Plugin | Standalone | Does |
|---|---|---|---|
| `actions.go_in` | `L`, `<Right>` | `L`, `<Right>` | Enter a directory |
| `actions.go_out` | `H`, `<Left>` | `H`, `<Left>` | Go to the parent directory |
| `actions.down` | `j`, `<Down>` | `j`, `<Down>` | Move down, from the last entry to the first (also in visual mode) |
| `actions.up` | `k`, `<Up>` | `k`, `<Up>` | Move up, from the first entry to the last (also in visual mode) |
| `actions.close` | `q` | none | Close coil tab (the column view) |
| `actions.quit` | none | `q` | Quit Neovim, asking about unsaved changes |
| `actions.cancel` | none | `Q` | Quit like `quit`, but write nothing to `--cwd-file` or `--chooser-file`. |

A key maps to an action, a function, keys to type (such as `"<Cmd>...<CR>"`), or a table with one
of those (first item or `callback`) and `mode`, `desc` or `opts` (passed to a function); `false`
removes a default. Keys are for normal mode unless `mode` says otherwise (`"n"`, `"x"`, `"v"` or
`""`, or a list).

Commands typed in the middle pane that open something, such as `:Oil`, `:edit file`, `:buffer` or
`:vsplit`, run in your editing tab instead, so plain oil is always one command away, even for the
directory the middle pane shows. `:Coil dir` moves the column view, `:edit` on its own reloads the
middle pane, and other commands (`:w`, `:s`, ...) run there as usual.

See also: [Lua API](doc/api.md), [highlight groups](doc/highlights.md), and `:help coil` inside Neovim.

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
  -- coil's keys in the middle pane, set like oil's `keymaps` (see Usage). The close, quit and
  -- cancel keys work in the preview pane too.
  keymaps = {
    ["L"] = "actions.go_in",
    ["<Right>"] = "actions.go_in",
    ["H"] = "actions.go_out",
    ["<Left>"] = "actions.go_out",
    ["j"] = "actions.down",
    ["<Down>"] = "actions.down",
    ["k"] = "actions.up",
    ["<Up>"] = "actions.up",
    ["q"] = "actions.close",
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
    keymaps = { ["q"] = "actions.quit", ["Q"] = "actions.cancel" },
  },
})
```

## Nix

The flake has:

| Output | What it is |
|---|---|
| `packages.<system>.coil-nvim` (also `default`) | The plugin. Install oil.nvim (and image.nvim, for images) yourself, as you would without coil |
| `packages.<system>.coil-standalone` | The [standalone `coil`](#standalone-coil): a bare Neovim with coil and everything its previews use |
| `packages.<system>.coil-standalone-filechooser` | The [file chooser](#as-systems-file-chooser) wrapper, running `coil-standalone` |
| `nixvimModules.default` | [`plugins.coil` for nixvim](#nixvim) |
| `overlays.default` | The packages above in `pkgs` (the plugin as `vimPlugins.coil-nvim`), plus `coil-cli` and `coil-filechooser`, for [a `coil` running your own Neovim](#with-the-overlay) |

Without flakes, `nix/` has the packages for `callPackage`, such as
`pkgs.callPackage ./nix/coil-nvim.nix { }`.

The Nix plugin has no `bin/`, since its `coil` would run whatever `nvim` is on `PATH`, so
`:CoilInstallCli` doesn't apply.

### Building Your Neovim
Use the overlay:
- `vimPlugins.coil-nvim` is the plugin derivation.
- `coil-cli` makes a standalone coil that runs your neovim: `pkgs.coil-cli.override { nvim = <your Neovim>; }`. 
    `coil-cli` needs a Neovim with coil in it, so it has no default: building it without `nvim`
    fails with a message saying to pass one. That's also why it's in the overlay and
`legacyPackages`, but not in `packages`.
- `coil-filechooser` runs the `coil-cli`.

```nix
# Home Manager
{ config, pkgs, inputs, ... }:
{
  nixpkgs.overlays = [ inputs.coil-nvim.overlays.default ];
  programs.neovim = {
    enable = true;
    plugins = [
      pkgs.vimPlugins.coil-nvim
      {
        plugin = pkgs.vimPlugins.oil-nvim;
        type = "lua";
        config = ''require("oil").setup()'';
      }
    ];
  };
  home.packages = [
    (pkgs.coil-cli.override { nvim = config.programs.neovim.finalPackage; })
    pkgs.coil-filechooser
  ];
}
```

Without the overlay, the same packages are in `legacyPackages.<system>`, with the plugin as
`coil-nvim`:

```nix
let
  coil = inputs.coil-nvim.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.neovim.plugins = [ coil.coil-nvim ];
  home.packages = [ (coil.coil-cli.override { nvim = config.programs.neovim.finalPackage; }) ];
}
```

### nixvim

```nix
{
  imports = [ inputs.coil-nvim.nixvimModules.default ];
  plugins.coil = {
    enable = true;
    # image.nvim, and the tools that make image, video and PDF thumbnails
    images.enable = true;
    # Passed to require("coil").setup(), see Options
    settings.ratio = [ 1 3 4 ];
  };
}
```

`enable = true` also sets up oil.nvim (`plugins.oil.enable`). The module builds the `coil` command and the
file chooser for this nixvim's Neovim, as read-only packages for you to install:

- `plugins.coil.cli.package`: `coil`, running this nixvim's Neovim with its config
- `plugins.coil.termfilechooser.package`: the [file chooser](#as-systems-file-chooser), running
  that `coil`. Set its `bin/coil-termfilechooser` as the portal's `cmd`; installing
  `plugins.coil.cli.package` isn't needed for it.

### Standalone coil

`packages.<system>.coil-standalone` is a bare Neovim along with: coil, oil.nvim, image.nvim,
mini.icons, oil-git-status.nvim, and the tools previews use (ImageMagick, ffmpeg, pdftoppm). It
installs only `coil`, so it doesn't clash with a Neovim of your own.

```sh
nix profile install github:allen-liaoo/coil.nvim#coil-standalone
```

It runs as its own Neovim app (`NVIM_APPNAME=coil`), so its config is `~/.config/coil/init.lua`,
an ordinary Neovim config. After that runs, `coil` sets up any bundled plugin it didn't:

```lua
-- ~/.config/coil/init.lua
require("oil").setup({ view_options = { show_hidden = true } })
require("coil").setup({ ratio = { 1, 3, 4 } }) -- see Options
vim.cmd.colorscheme("retrobox")
```

For the [file chooser](#as-systems-file-chooser), `packages.<system>.coil-standalone-filechooser` runs this standalone coil. Set its `bin/coil-termfilechooser` as the portal's
`cmd`.

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

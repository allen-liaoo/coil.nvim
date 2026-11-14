# TODO

## General

- [x] **Side panes follow a sort change.** coil notices when oil re-renders the middle buffer with
  different listing settings (`gs`, hidden files, `oil.set_sort()`) and refreshes the side panes,
  fetching what a size or time sort needs.
- [x] **Click to jump.** Clicking an entry in the parent pane or in a directory preview moves the
  middle pane to that entry's directory, with the cursor on the entry.
- [x] **Image previews.** With image.nvim installed and set up, the preview draws images from
  thumbnails made in the background and cached on disk. The standalone build includes image.nvim
  and ImageMagick.
- [x] **Video and PDF thumbnails.** A frame 10% into a video (ffprobe and ffmpeg) or a PDF's first
  page (pdftoppm), drawn through the same thumbnail cache. Without the tool, the preview says
  what to install.
- [x] **Remote file previews** (SSH, S3). The file is downloaded in the background (scp,
  `aws s3 cp`) once the cursor rests on it, within a size limit taken from oil's listing, then
  previewed like a local file. Copies live in Neovim's temporary folder. The trash has none.
~~- [ ] **Floating-window version of the column view.** `view/layout.lua` is the only module that
  knows the panes are splits. A floating version needs geometry on resize, its own keys to move
  between panes, and hiding and restoring when a file opens in the editing tab.~~
- [x] Packaging: Make coil-nvim not depend on oil nvim in nix, but require user to have oil nvim. Remove coil-nvim oil flake dependency, and just use nixpkgs's oilnvim
- [x] Refactor: make sure no coil config or logic duplicates oil's. For instance, keep keymaps (open in splits) config that oil has in oil. Coil should only change the behavior of it in coil's buffer.
- [x] **Several directories in tabs**, like yazi's tabs: `:Coil dir1 dir2 ...` and `coil dir1 dir2 ...`
  open a column view per directory, one tab each.
- [x] **Delete to trash by default.** oil defaults to `delete_to_trash = false`, so deleting a line
and saving removes files permanently. The standalone build should send them to the trash; oil's
trash view (`g\`) can restore them.
- [x] **No file details in the preview.** A file's preview is its text or a picture of it
  (filling the pane), and anything else gets one dimmed line saying why. The info cards are gone;
  oil's columns show file details.
- [ ] Test with git integration 3rd party extension(s). Challenge: Show git integration in parent/child folder? perhaps change them to oil buffers?
- [ ] **`:help coil` docs**, a vimdoc version of the README.

## Standalone coil

These concern the `coil` command (`nix/coil.nix`). Most are standalone-mode behaviour, so they
should be options set by the standalone build, not changes forced on people using coil as a plugin.

- [x] **Config file.** The build loads its own generated init and ignores user config. Load an
optional `~/.config/coil/init.lua` for customising it.
- [x] **A fuller standalone build:** an icon provider (mini.icons or nvim-web-devicons), more
Tree-sitter grammars, and ffmpeg and poppler for video and PDF previews (left out for now: with
their dependencies they add about 300 MB and 150 MB). image.nvim and ImageMagick are included.
- [x] **Entry details.** Turn on oil's `permissions`, `size` and `mtime` columns in the standalone
build (oil's default is the icon column only).
- [x] **`q` quits.** `q`/`:CoilClose` closes the column view and leaves an empty editor open. In
  the standalone build it should quit, prompting if edited buffers have unsaved changes.
- [x] **cd on exit.** A `--cwd-file <path>` argument that writes the middle pane's last directory on
  exit, plus a documented shell function (like yazi's `y`) that `cd`s there (link to the doc in readme, dont write directly in readme).
- [x] **Your own Neovim as a file manager.** Standalone mode (`g:coil_standalone`, set with
  `--cmd`) in any Neovim, with a `standalone` option for mode-specific settings, and
  `g:coil_cwd_file` for cd on exit. The Nix build uses the same mode; only its launcher has
  `--cwd-file`.
- [x] **Open non-text files in other programs.** `<CR>`/`L` on a file the preview classifies as not
  text (image, video, PDF, archive, binary) should open it with oil's `actions.open_external`, which
  uses `vim.ui.open` (xdg-open / open / explorer). Text files keep opening in the editor. Limits:
  `open_external` only works for local files (`oil.get_current_dir()` is nil for SSH and S3), and it
  needs the system opener installed. Dont consider: configurable opener rules by extension or MIME type.
- [x] **Notice outside changes.** The standalone build turns on oil's `watch_for_changes`. The side
  panes are oil buffers, so oil's file watchers redraw them like any oil buffer, in any build that
  turns it on (local directories only).
- [ ] **Picker mode.** A `--chooser-file <path>` argument that writes the picked path(s), including
  a visual selection, and exits, so other programs can use coil as a file picker.
- [ ] **Other arguments:** `--hidden`, `--ratio`, `--help`, `--version`. Today `coil [dir]` opens the
  column view and anything else is passed to Neovim.

## Bugs

- [ ] **Images one column too far left with kitty placeholders.** With
  `kitty_method = "unicode-placeholders"`, image.nvim draws every image one column left of where
  it means to, covering the separator left of the preview. Its renderer passes a 0-based column;
  the normal kitty method adds 1 (`kitty/init.lua`, `move_cursor(x + 1, y + 1, true)`), but
  `write_placeholder` doesn't (`kitty/helpers.lua`, `move_cursor(x, y + i + 1)`). coil can't
  shift the image itself: the anchor line is empty and `screenpos` clamps to its end. Plan: patch
  image.nvim in the Nix builds (`nix/coil.nix`, the nixvim module) and send the fix upstream,
  along with resetting attributes before the placeholders (coil works around that one today).
- [x] Something is drawn below the preview, causing background of terminal to leak through the neovim background. It happens when it isn't a text preview or a text preview with short enough text.

## Known gaps
- SSH and S3 directories are listed through oil's adapters, but haven't been tested against a real
  host.
- Neovim's built-in tab line doesn't show the `tab_title` name; tab line plugins that read the
  `tabname` tab variable (such as lualine's `tabs` component) do.

# TODO

## General

- [x] **Side panes follow a sort change.** coil notices when oil re-renders the middle buffer with
  different listing settings (`gs`, hidden files, `oil.set_sort()`) and refreshes the side panes,
  fetching what a size or time sort needs.
- [x] **Click to jump.** Clicking an entry in the parent pane or in a directory preview moves the
  middle pane to that entry's directory, with the cursor on the entry.
- [x] **Image previews.** With image.nvim installed and set up, the preview draws images below the
  info card, from thumbnails made in the background and cached on disk. The standalone build
  includes image.nvim and ImageMagick.
- [x] **Video and PDF thumbnails.** A frame 10% into a video (ffprobe and ffmpeg) or a PDF's first
  page (pdftoppm), drawn below the info card through the same thumbnail cache. Without the tool,
  the card says what to install.
- [ ] **Remote file previews** (SSH, S3). These show a "not supported yet" card. They need an
  asynchronous download (scp, `aws s3 cp`) to a temporary file with a size limit, then the normal
  text or card preview.
~~- [ ] **Floating-window version of the column view.** `view/layout.lua` is the only module that
  knows the panes are splits. A floating version needs geometry on resize, its own keys to move
  between panes, and hiding and restoring when a file opens in the editing tab.~~
- [x] Packaging: Make coil-nvim not depend on oil nvim in nix, but require user to have oil nvim. Remove coil-nvim oil flake dependency, and just use nixpkgs's oilnvim
- [x] Refactor: make sure no coil config or logic duplicates oil's. For instance, keep keymaps (open in splits) config that oil has in oil. Coil should only change the behavior of it in coil's buffer.
- [x] **Several directories in tabs**, like yazi's tabs: `:Coil dir1 dir2 ...` and `coil dir1 dir2 ...`
  open a column view per directory, one tab each.
- [ ] **Delete to trash by default.** oil defaults to `delete_to_trash = false`, so deleting a line
and saving removes files permanently. The standalone build should send them to the trash; oil's
trash view (`g\`) can restore them.
- [ ] **`:help coil` docs**, a vimdoc version of the README.

## Standalone coil

These concern the `coil` command (`nix/coil.nix`). Most are standalone-mode behaviour, so they
should be options set by the standalone build, not changes forced on people using coil as a plugin.

- [ ] **Config file.** The build loads its own generated init and ignores user config. Load an
optional `~/.config/coil/init.lua` for customising it.
- [ ] **A fuller standalone build:** an icon provider (mini.icons or nvim-web-devicons), more
Tree-sitter grammars, and ffmpeg and poppler for video and PDF previews (left out for now: with
their dependencies they add about 300 MB and 150 MB). image.nvim and ImageMagick are included.
- [ ] **Entry details.** Turn on oil's `permissions`, `size` and `mtime` columns in the standalone
build (oil's default is the icon column only).
- [ ] **`q` quits.** `q`/`:CoilClose` closes the column view and leaves an empty editor open. In
  the standalone build it should quit, prompting if edited buffers have unsaved changes.
- [ ] **cd on exit.** A `--cwd-file <path>` argument that writes the middle pane's last directory on
  exit, plus a documented shell function (like yazi's `y`) that `cd`s there (link to the doc in readme, dont write directly in readme).
- [ ] **Open non-text files in other programs.** `<CR>`/`L` on a file the preview classifies as not
  text (image, video, PDF, archive, binary) should open it with oil's `actions.open_external`, which
  uses `vim.ui.open` (xdg-open / open / explorer). Text files keep opening in the editor. Limits:
  `open_external` only works for local files (`oil.get_current_dir()` is nil for SSH and S3), and it
  needs the system opener installed. Later: configurable opener rules by extension or MIME type.
- [ ] **Notice outside changes.** Turn on oil's `watch_for_changes` in the standalone build, and make
  sure the side panes refresh too; today they refresh on navigation, saving and returning to the tab.
- [ ] **Picker mode.** A `--chooser-file <path>` argument that writes the picked path(s), including
  a visual selection, and exits, so other programs can use coil as a file picker.
- [ ] **Other arguments:** `--hidden`, `--ratio`, `--help`, `--version`. Today `coil [dir]` opens the
  column view and anything else is passed to Neovim.

## Known gaps
- SSH and S3 directories are listed through oil's adapters, but haven't been tested against a real
  host.
- Neovim's built-in tab line doesn't show the `tab_title` name; tab line plugins that read the
  `tabname` tab variable (such as lualine's `tabs` component) do.

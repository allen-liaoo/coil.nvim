# Preview

`preview/` shows a target in any window and knows nothing about oil or panes. A file's preview is
its text or a picture of it (images, video frames, PDF pages), and nothing else; any other file
gets one dimmed line saying why. File details are oil's columns' job.

## Design rules

- **Newest preview wins.** Each window has a generation counter bumped by every `show`/`clear`;
  asynchronous work (listings, thumbnails, downloads) checks it before touching the window.
- **Preview buffers are scratch and wiped when replaced.** They work in `winfixbuf` windows and
  never move focus, background tabs included (see [Neovim](neovim.md)).
- **Classification never runs external tools** (no `file(1)`): stat, extension, size, then a NUL
  byte in the first `sniff_bytes`. Fifos, sockets and devices are never opened (reading a fifo
  can hang). Extensions decide media kinds whatever the size, so a large video still gets a frame.
- **Text previews don't set `filetype`**, so no ftplugins run and no language servers attach.
  Highlighting comes from Tree-sitter when a parser exists, otherwise the filetype's regex syntax
  file (which covers nearly every language; Neovim ships few Tree-sitter parsers, and the
  standalone build dropped nvim-treesitter's grammars to save 40 MB).

## Pictures

`preview/image.lua` is the only module that talks to image.nvim. coil calls it directly instead
of embedding `![](path)` for image.nvim's markdown integration, so coil decides the size, when to
draw (after the cursor rests), and when to remove it.

- **image.nvim is optional.** "Set up?" is checked through `:ImageReport`, which its `setup()`
  defines; image.nvim has no public check, and `from_file` throws until setup has run. coil never
  calls image.nvim's `setup()`: it is global (markdown images too) and not meant to run twice. The
  Nix build and the nixvim module set it up.
- **Where it goes.** image.nvim draws an image *below* its anchor line, so a picture's buffer has
  one line (showing "Loading thumbnail..." until drawn) and the picture starts on the pane's second
  row. Starting on the first row would mean giving image.nvim screen coordinates instead of the
  window, so coil would have to clear images on leaving the tab, and image.nvim would stop hiding
  them under floating windows. The height is the rows *below* the anchor's screen row
  (`screenpos`, which counts wrapped lines and the winbar); counting the anchor made pictures one
  row too tall and image.nvim cropped them with ImageMagick while Neovim waited. Fewer than three
  rows: no image, and the line says the window is too small. image.nvim's
  `max_*_window_percentage` caps (half the height by default) are lifted per image.
- **Keeping it right.** image.nvim clears images when their tab is left and keeps the geometry it
  was given, so coil redraws on `TabEnter`, `WinResized`, `VimResized` and `WinScrolled`.

### kitty unicode placeholders

In tmux, image.nvim's default cursor-based kitty method puts images at the cursor: its cursor moves
go to tmux's own screen while the passthrough image command reaches kitty straight away, before
kitty's cursor moved (and positions are pane-relative). With `kitty_method =
"unicode-placeholders"` the image is drawn by ordinary characters, which tmux places itself. The
Nix build and nixvim module set it; the README tells everyone else.

Placeholders are characters image.nvim writes straight to the terminal (U+10EEEE plus two
diacritics per cell; the foreground colour is the image id), outside Neovim's screen model. What
follows from that, all of it image.nvim bugs that coil doesn't work around. None was reported
upstream as of 2026-11-18; the maintainer's nvimx patches the first two in its image.nvim
(`kitty/helpers.lua`'s `write_placeholder`).

- **One column too far left.** image.nvim passes a 0-based column where the terminal wants
  1-based: its normal kitty path adds 1, `write_placeholder` doesn't. The picture covers the
  separator left of the preview. coil can't shift it (the anchor line is empty and `screenpos`
  clamps to its end).
- **Attributes leak in.** They take whatever attributes Neovim's last drawn cell left on, and
  kitty draws those over the image (vim-illuminate's underline on the word under the cursor became
  a line across every row). The fix resets attributes before the placeholders, in
  `write_placeholder` so that image.nvim's own redraws on scroll get it too.
- **They outlive the image.** Clearing deletes kitty's placement (`a=d,d=i`), but Neovim only
  redraws cells whose contents it thinks changed, so placeholder cells stay wherever the next
  preview has no new text, and kitty shows their background there. A reset alone gives them the
  terminal's background, which shows through below short previews, so the fix also sets the image
  window's (NormalNC's when unfocused, else Normal's; none when the colour scheme has none).
- **`restore_cursor` without a save.** The placeholder path ends with `ESC[u` but never sent
  `ESC[s`. Neovim positions absolutely right after, so no effect was found, but it's a suspect if
  text ever lands in the wrong place after an image.
- **Under tmux, image.nvim writes deletes to the current tmux pane's tty**, not stdout. A test or
  repro that inherits `$TMUX` sends them to whatever pane you're in.

## Thumbnails

image.nvim on its own converts any non-PNG to a full-size PNG while Neovim waits (about 13 s,
frozen, for a 4000×3000 JPEG), then scales it, again while Neovim waits. So
`preview/thumbnail.lua` makes a small PNG in the background with ImageMagick and draws that.
Measured on that JPEG: first view after 1.7 s, revisits 0.16 s (mostly `image_delay_ms`), Neovim
never stalled more than 34 ms.

- **600×900, `>` (only shrink)**, like yazi's default. JPEGs are read as `photo.jpg[1200x1800>]`
  so libjpeg skips detail (0.36 s instead of 0.6 s on 12 MP). `-define jpeg:size` would do the
  same but enlarges small JPEGs (a 50×60 came out 100×120). The size hint can't be combined with
  the `[0]` frame selector that other formats need (otherwise ImageMagick writes one file per
  frame), so only JPEGs get it.
- **Copies at the drawn size.** Even from a cached thumbnail, a new image took about 1 s: image.nvim
  scales any image whose width differs from what it will draw, synchronously, mostly PNG
  compression. coil predicts that size with image.nvim's own `image/utils/term` (cell size) and
  `image/utils/math` (`adjust_to_aspect_ratio`) and makes `<thumb>-WxH.png` in the background with
  light compression. These are internals, used through `pcall`; if they change or the prediction
  misses, image.nvim scales as before. Measured: a prefetched photo draws after 158 ms, 3 ms of it
  the draw (was 937 ms). With fractional cell sizes there is no prediction: image.nvim compares
  widths exactly and would scale anyway.
- **Video:** `ffprobe` for the duration, then one `ffmpeg` frame 10% in (seeking before `-i`; 0.12 s
  for both on a 20 s 1080p clip), which skips black intros. ffmpeg only, not ffmpegthumbnailer:
  anyone with video tools has ffmpeg. **PDF:** `pdftoppm`, first page 600 px wide (0.03 s). A
  missing tool is named on the preview line, only when image.nvim is set up.
- **Cache:** `stdpath("cache")/coil/thumbnails/<sha256 of path, size, mtime, thumbnail size>.png`,
  so a changed file gets a new name and stale thumbnails are never shown. Written to
  `<name>.png.<pid>.tmp` (pdftoppm: `….tmp.png`) and renamed, because several Neovims share the cache. At most two jobs; the
  requested file jumps the queue, and a new prefetch drops the previous prefetch's unstarted files.
- **Size limit:** least recently used first, tracked by resetting the file's mtime when drawn
  (atime is useless under `noatime`/`relatime`). Cleanup lists the folder each time it runs, so
  several Neovims sharing the cache stay correct, and goes down to 80% so it doesn't run on every
  new file. Temporary files older than an hour are from killed jobs; younger ones may be another
  Neovim's.
- **Prefetch:** the view passes entries within `prefetch` lines of the cursor, nearest first, with
  copies sized from an estimate of the pane (`image.estimated_fitter`). Remote files are skipped:
  that would mean downloads.

## Remote files

A target without a local path (SSH, S3) is previewed from a downloaded copy (`preview/remote.lua`,
with the `fetch` the caller passes; for coil, `bridge.fetcher`).

- **Nothing is downloaded that couldn't be shown.** Extension and the size from oil's listing
  rule out audio, archives, undrawable pictures and anything over the limits before any transfer.
- **Only where the cursor rests:** the download starts `remote_delay_ms` after the preview shows
  the file, a redraw of the same file joins the running download, and moving on stops it.
- **Never prompts:** `scp -C -o BatchMode=yes` (plus oil's `extra_scp_args`), `aws s3 cp` (plus
  `extra_s3_args`). Hosts need key or agent auth, or an open ControlMaster. Tested against a local
  sshd: text, names with spaces, binary detection, size limit, cached revisits, scp errors.
- **Copies keep the file's name** (filetype detection and thumbnails work as for local files), in
  Neovim's temporary folder, one per URL, size and mtime, so revisits are instant and changed files
  are fetched again.

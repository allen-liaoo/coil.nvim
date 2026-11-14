# Preview

`lua/coil/preview/` shows a preview of a file or directory in any window. It knows nothing about
oil or the column view. Directory listing is passed in as a function, so the module works on its
own. The column view's preview pane and `:CoilPreview` both use it.

## API

```lua
local preview = require("coil.preview")

preview.setup(opts)               -- module defaults (coil passes its `preview` options)
preview.show(win, target, opts)   -- preview `target` in window `win`
preview.clear(win, lines)         -- show an empty buffer, or a short message
```

A **target** describes what to preview:

| Field | Meaning |
|---|---|
| `name` | Display name |
| `url` | Where it lives: an oil URL or a plain path |
| `path` | Local filesystem path; absent for remote targets |
| `is_dir` | Whether it is a directory (or a link to one) |
| `unsaved` | The entry only exists in an unsaved oil buffer |

Options (`preview` in coil's setup):

| Option | Default | Meaning |
|---|---|---|
| `max_bytes` | 2 MiB | Text files larger than this get no text preview |
| `max_lines` | 1000 | Read at most this many lines of a text file |
| `sniff_bytes` | 8192 | Bytes read to tell binary from text |
| `loading_delay_ms` | 100 | Wait this long before showing "Loading..." for a directory |
| `images` | `true` | Draw images with image.nvim when it is installed and set up |
| `image_delay_ms` | 100 | Wait this long after an image's preview is shown before working on the image |
| `thumbnail_size` | `{ 600, 900 }` | Images are drawn from thumbnails that fit this many pixels (read by `setup()` only) |
| `prefetch` | 2 | `prefetch()` prepares images up to this many entries from the cursor (0 for none) |
| `thumbnail_cache_mb` | 200 | Size limit of the thumbnail cache (read by `setup()` only; `false` for none) |
| `list_dir` | none | `fun(url, cb)` that lists a directory; coil passes `oil_bridge.list_dir` |

## Choosing a preview

`classify.lua` decides from the file itself, without external tools such as `file(1)`:

1. No local path: **remote**.
2. Can't `stat` it: **unreadable**.
3. A directory: **directory**. Any other non-regular file (fifo, socket, device): **special**.
   These are never opened, because reading a fifo could hang.
4. A known extension: **image**, **video**, **audio**, **pdf** or **archive**, whatever the size.
5. Larger than `max_bytes`: **too large**.
6. A NUL byte in the first `sniff_bytes`: **binary**. Otherwise **text**.

| Kind | Preview |
|---|---|
| directory | The entries, as plain names (`name/` for directories), coloured like oil, hidden entries greyed out |
| text | The first `max_lines` lines |
| image, video, pdf | A picture, drawn with image.nvim |
| everything else | One dimmed line saying why there is no preview |

### Text

The file's first lines go into a read-only scratch buffer. Highlighting comes from Tree-sitter when
a parser exists for the detected filetype, otherwise from the legacy syntax file. The buffer's
`'filetype'` is deliberately not set, so no ftplugins run and no language servers attach to a
preview. An empty file shows a dimmed "(empty file)".

### Pictures

With image.nvim available (installed, and its `setup()` has run) and `images = true`, an image,
video or PDF gets a buffer with one empty line, and `preview/image.lua` draws a picture of it from
the row below that line to the bottom of the window (see [Drawing images](#drawing-images)). The
line itself shows "Loading thumbnail..." until then. There are no file details: the middle pane's oil
columns show those.

### Messages

Every other file gets one dimmed line saying why there is no preview:

| Kind | Message |
|---|---|
| binary, audio | No preview for binary files (audio files) |
| archive | No preview for archives |
| too large | Larger than 2.0M, so the text isn't shown |
| special | Not a regular file (fifo) |
| unreadable | Cannot read this file: <error> |
| remote | Previews of remote files are not supported yet |
| image, video, pdf with no picture | Image previews are off; Set up image.nvim to see the image; Install poppler (pdftoppm) to see the first page |

### Drawing images

`preview/image.lua` is the only module that talks to image.nvim, through its public API
(`from_file`, then `render` and `clear` on the image).

- **Is image.nvim set up?** image.nvim has no public check, and `from_file` throws until `setup()`
  has run. `setup()` defines `:ImageReport`, so coil checks for that command.
- **What is drawn: a thumbnail** from `preview/thumbnail.lua`, not the original. image.nvim
  converts any non-PNG image to a full-size PNG while Neovim waits (seconds for a large photo),
  then shrinks it, again while Neovim waits. A thumbnail is already a small PNG, so image.nvim
  skips the conversion and its shrinking step is quick (about 0.1 s, and cached for the session).
  Without ImageMagick on `PATH`, image.nvim gets the original.
- **When:** `image_delay_ms` after the preview is shown, and only if it hasn't moved on. Then
  the thumbnail is fetched (straight away from the cache, otherwise made in the background), and
  drawn if the preview still shows the same file. Until then the first line shows a dimmed
  "Loading thumbnail...", cached or not; if ImageMagick fails, it shows "No preview: <error>".
  With fewer than three rows below that line, no image is drawn and the line says "Window too
  small for the thumbnail" until the window grows.
- **Where:** the image is tied to the preview window and its buffer, anchored at the buffer's
  only line. image.nvim draws an image below its anchor line, so the picture starts on the next
  row. Width is the window's text width; height runs from the row below that line's screen row
  (`screenpos()`, which accounts for wrapped lines and a winbar) to the window's last row.
  image.nvim's own `max_*_window_percentage` caps are lifted for the image (its default caps
  height at half the window), and it keeps the image's aspect ratio inside that box. Fewer than
  three rows: no image.
- **Keeping it right:** image.nvim clears images when their tab is left and keeps the geometry it
  was given on resize. coil redraws its images with fresh geometry on `TabEnter`, `WinResized`,
  `VimResized` and `WinScrolled`.
- **Removing it:** every new preview in a window (and `clear`) removes that window's image first,
  and wiping the preview buffer removes it too.

### Directories

The module calls the `list_dir` it was given. "Loading..." appears only if the listing takes
longer than `loading_delay_ms`, which avoids flicker for fast local directories.
`providers/directory.lua` also draws the column view's parent pane.

Highlight groups:

| Group | Links to |
|---|---|
| `CoilDir`, `CoilLink` | `OilDir`, `OilLink` when oil is loaded; otherwise `Directory`, `Constant` |
| `CoilDirHidden`, `CoilFileHidden`, `CoilLinkHidden` | oil's `Oil*Hidden` groups when oil is loaded; otherwise `Comment` |

All are defined with `default = true`, so colours you set for them are kept.

## Behaviour

- **Newest preview wins.** Each window has a generation counter that every `show`/`clear` bumps.
  An asynchronous directory listing that finishes after a newer preview was requested is dropped.
- **Preview buffers are scratch buffers:** `buftype=nofile`, no swap file, not modifiable. They are
  wiped as soon as they are replaced.
- **It works in windows with `'winfixbuf'`,** and never moves focus, including in background tabs
  (see [Neovim windows](neovim-windows.md)).

## `:CoilPreview`

`split_preview.lua` uses the module on its own. In any ordinary oil window, `:CoilPreview` toggles
a split on the right that follows that window's cursor (debounced, skipped in visual mode). It
follows the oil window into other directories, and closes when either window closes.

### Thumbnails

`preview/thumbnail.lua` makes thumbnails with ImageMagick (`magick`, or `convert` for version 6)
and keeps them on disk.

- **Where:** `stdpath("cache")/coil/thumbnails/<sha256>.png`, where the hash covers the file's
  path, size, modification time and the thumbnail size. A changed file gets a new name, so a stale
  thumbnail is never shown, and thumbnails survive restarts.
- **The command:** `magick <src> -auto-orient -thumbnail '600x900>' png:<tmp>`, run with
  `vim.system` so Neovim keeps responding. `>` only shrinks. JPEGs are read as
  `photo.jpg[1200x1800>]`, which lets the decoder skip detail the thumbnail can't show (0.36 s instead
  of 0.6 s on a 12-megapixel photo). `-define jpeg:size` would do the same
  but enlarges small JPEGs. Other formats are read as `file[0]`, the first frame of an animation
  or the first page of a TIFF; otherwise ImageMagick writes one file per frame.
- **Writing:** to `<name>.png.<pid>.tmp`, renamed when complete, so no Neovim sharing the cache
  reads a half-written file. A failed run removes the temporary file.
- **Jobs:** at most two at a time. A request for a thumbnail that is already being made waits for
  that job. `get()` puts its file at the front of the queue; `prefetch()` adds files at the back
  and drops the previous prefetch's files that haven't started.
- **Copies at the drawn size:** `get(path, stat, cb, fit)` and `prefetch(files, fit)` take a
  function that maps a thumbnail's size to the exact size image.nvim will draw it at
  (`image.fitter`, which uses image.nvim's cell-size and aspect-ratio helpers). coil then makes
  `<thumbnail>-WxH.png` with `-scale WxH!` and light PNG compression, in the background, so
  image.nvim doesn't scale the image while Neovim waits. Without a prediction, the thumbnail
  itself is used.
- **Prefetch:** in the column view, `sync.lua` passes the entries within `prefetch` lines of the
  cursor (nearest first) to `preview.prefetch()`, which, after `image_delay_ms`, queues the
  images among them, with copies sized to fill the window (`image.estimated_fitter`).
- **Size limit:** see [the cache's limit](#the-caches-size-limit).

### The cache's size limit

- Drawing a cached file resets its modification time, which records when it was last used.
- After each new file, coil adds its size to a running total (from one listing of the folder the
  first time). Past `thumbnail_cache_mb`, it lists the folder again and deletes the files used
  longest ago until the cache is at 80% of the limit.
- Temporary files older than an hour are left over from killed jobs and are deleted then too.
- `:CoilClearCache` (`thumbnail.clear_cache()`) deletes every thumbnail, except temporary files
  that may still be being written.

### Videos and PDFs

`thumbnail.lua` has one "maker" per kind (`thumbnail.kind_of(path)`, from the extension):

| Kind | Tools | Command |
|---|---|---|
| image | `magick` or `convert` | `src[0]` (or `photo.jpg[1200x1800>]`) `-auto-orient -thumbnail '600x900>'` |
| video | `ffprobe`, `ffmpeg` | duration, then `ffmpeg -ss <10%> -i src -frames:v 1 -vf scale='min(600,iw)':'min(900,ih)':force_original_aspect_ratio=decrease` |
| pdf | `pdftoppm` | `-png -singlefile -f 1 -l 1 -scale-to-x 600 -scale-to-y -1` (writes `<tmp>.png`) |

The queue, cache, size limit, prefetch and exact-size copies are shared. `preview/init.lua`'s
`show_picture` handles all three kinds; when `thumbnail.available(kind)` is false for a video or
PDF, the preview names the tool to install (`thumbnail.tool_name(kind)`).

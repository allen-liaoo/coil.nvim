# oil.nvim

coil builds on oil rather than replacing it, and goes through `oil_bridge.lua` for everything,
because it leans on oil internals and oil's adapter API is documented as unstable. The dev shell
and the Nix builds use nixpkgs' `vimPlugins.oil-nvim` (2.16.0 when this was written); nothing pins
a commit.

## Internals coil depends on

When oil updates, these are what can break. Public `oil.*` API (`open`, `select`,
`get_entry_on_line`, `get_buffer_parent_url`, `toggle_hidden`, `get_url_for_path`) is safer.

| Internal | Used for |
|---|---|
| `oil.load_oil_buffer` | Loading a directory buffer when `BufReadCmd` can't fire, or in a window that isn't current |
| `oil.view.render_buffer_async(buf, {refetch = true})` | Listing a buffer oil already has again |
| `oil.view.set_last_cursor` | Putting the cursor on an entry at oil's next render (`H`, clicks, `g.`, `:Oil` from the middle pane) |
| `oil.view.should_display` | oil's hidden-file rules for `:CoilPreview`'s name lists |
| `oil.mutator.parser.parse_line`, `oil.columns.get_supported_columns` | Byte ranges of each column on a line: what side panes conceal, and where the name starts |
| `oil.columns` `create_sort_value_factory` / `get_sort_value` | Rebuilding oil's private sort comparator for name lists |
| `oil.util.run_after_load`, `is_oil_bufnr`, `get_adapter`, `parse_url`, `url_escape` | Waiting for listings, buffer checks, URLs |
| `oil.config` (`keymaps`, `view_options`, `adapters`, `extra_scp_args`, `extra_s3_args`, `get_adapter_by_scheme`) | Reading the user's oil setup |
| adapter `list`, `normalize_url`, `parse_url` | Name lists, resolving URLs and links, building download commands |
| entry `meta` (`size`, `link_stat`, `iso_modified_date`, `date`) | Remote files' size and mtime without downloading |

## oil behaviours coil handles

| oil does | coil |
|---|---|
| Places the cursor only when it renders a buffer (on the name, or on `set_last_cursor`'s entry, whatever `constrain_cursor` says) | A buffer a side pane already rendered isn't rendered again, so coil places the cursor itself: `cursor_to_name` after a directory enters the middle pane, and once the buffer is ready for `:Oil` typed there |
| Resolves a link (`normalize_url`, `fs_realpath` for files) when it loads its buffer, renaming the buffer, or swapping in the target's buffer if one exists | See [Links and winfixbuf](#links-and-winfixbuf) |
| Keeps one buffer per directory, and shows a hidden buffer's old listing when it comes back | Side panes share buffers with middle panes (hence per-window conceal and no editing); a directory shown again is re-listed |
| Sets its keymaps again on every buffer setup (reloads included), then fires `User OilEnter` | Keys are re-wrapped on `OilEnter` |
| Applies sort and hidden-file changes by re-rendering, with no event | Watched through the middle buffer's lines and `listing_signature()` |
| `select` can't say whether a buffer is a directory, and remote files have oil URLs too | Directory buffers are the ones whose names end in `/`, as oil names them |
| `select({handle_buffer_callback})` hands over the buffer instead of opening it | coil uses it for every open, keeping oil's URL normalization and its refusal to enter a directory typed but not saved |
| `toggle_hidden` keeps the line number | coil sets the last cursor to the entry first |
| `is_oil_bufnr` returns `true` for loaded buffers but the adapter name (`"files"`) for unloaded ones | Tested for truthiness |
| Loads directories from `BufReadCmd`, which doesn't fire inside a non-nested autocmd | The bridge loads them ([Neovim](neovim.md#autocmds-inside-autocmds)) |
| Its global `BufEnter` handler, run during a swap in a background tab, moves that tab's remembered window | Restored after each swap ([Neovim](neovim.md#background-tabs-remember-the-wrong-window)) |
| `get_buffer_parent_url` returns the URL itself at the root | `parent_of` returns nothing; the parent pane stays empty |
| Its preview (`actions.preview`) opens a `previewwindow` split, which its global handlers close or update | coil's preview pane never sets `previewwindow`; oil's preview key means "jump to the preview pane" in the middle pane |
| A URL without its trailing slash (`oil-ssh://host//dir`) looks like a file until oil has resolved it | `:Coil` and standalone startup ask the adapter first (for SSH, a round trip to the host) |
| Turns a directory argument into an `oil:///…/` buffer before `VimEnter` | Startup accepts oil URLs as directories |
| Creates unlisted buffers of its own while loading (the SSH login terminal) | Startup deletes only *listed* start buffers; deleting that terminal broke the connection ("Invalid buffer id") |
| `oil.setup()` doesn't undo `set_sort()` or a hidden toggle (they change its default `view_options` in place) | Tests reset both in `setup_oil` |

## Links and winfixbuf

When oil loads a link's buffer and the target directory already has a buffer (shown in a pane or
tab, or loaded before), oil swaps the target's buffer into every window showing the link, from a
`vim.schedule` callback (`oil/util.lua`, `rename_buffer`). In a window with `winfixbuf` that fails
with E1513, and the window keeps the dead link buffer on "Loading" until something re-syncs. So
side panes never get a link's URL: `bridge.resolve_dir` normalizes a link target through the
adapter first and the pane shows the target's buffer directly. Non-link directories skip the
asynchronous hop. The middle pane has no `winfixbuf` and goes through `oil.select`, which
normalizes too.

## Name lists (`:CoilPreview` only)

`bridge.list_dir` lists through the adapter directly (`adapter.list(url, columns, cb)`), so local,
SSH, S3 and trash directories all work, without touching oil's cache (oil's own buffers are
unaffected). It requests only the columns the sort needs, so local listings `stat` entries only
when sorting by size or mtime. Results stream in batches until the adapter is done, and callbacks
are moved onto the main loop, since adapters may call back from libuv. It sorts like oil by
rebuilding oil's comparator from `view_options.sort`, so a preview has the order you'll see after
entering. `opts.always_show` keeps one named entry even when hidden; it was for the old
name-list parent pane's current directory, and nothing passes it now. A missing directory lists as empty, as in oil.

## Plain oil is unchanged

Outside a view's middle pane coil changes nothing: `:Oil`, floating oil, `nvim some/dir` and every
oil key behave as usual, and oil's `:w` still saves every modified oil buffer, in and out of views.

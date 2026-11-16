# Highlights

coil links these groups by default (`default = true`), so colours you set for them win.

| Group | Default link | Used for |
|---|---|---|
| `CoilParentSelected` | `Visual` | The current directory in the parent pane |
| `CoilDir` | `OilDir` (else `Directory`) | Directories in `:CoilPreview`'s directory listings |
| `CoilLink` | `OilLink` (else `Constant`) | Links in `:CoilPreview`'s directory listings |
| `CoilDirHidden` | `OilDirHidden` (else `Comment`) | Hidden directories in `:CoilPreview`'s directory listings |
| `CoilFileHidden` | `OilFileHidden` (else `Comment`) | Hidden files in `:CoilPreview`'s directory listings |
| `CoilLinkHidden` | `OilLinkHidden` (else `Comment`) | Hidden links in `:CoilPreview`'s directory listings |

The column view's side panes are oil buffers, so they use oil's own highlights.

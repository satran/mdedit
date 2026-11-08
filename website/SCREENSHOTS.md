# Screenshots

Taken from the sample folder `~/mdtest/Sample/Demo Notes` (its `Showcase Guide.md` says where each feature lives), as window captures (⇧⌘4, Space, click) so the shadow is in the picture. Each one exists in `-light` and `-dark`; the page picks by the visitor's colour scheme. Sizes are at 2x.

| Files | Size | Shown |
|---|---|---|
| `mdedit-light/dark.png` (hero) | 2930 × 1946 | `Recipes/Sourdough Bread.md`, binder, Outline with linked mentions |
| `feature-templates-editor-*.png` | 2252 × 1946 | `Pages/Dashboard.html` as code |
| `feature-templates-preview-*.png` | 2252 × 1946 | the same file, Preview on |
| `feature-agent-review-*.png` | 2932 × 1946 | `Reference/Agent Review Draft.md` with the Review tab |
| `feature-focus-*.png` | 2252 × 1946 | `Reference/A Walk Along the Coast.md`, typewriter and distraction free |
| `feature-fuzzy-find-*.png` | 2252 × 1946 | ⇧⌘O with `sou` typed |

The `width` and `height` attributes in `index.html` match these sizes. If a retake has another size, change them on that `<img>`.

`og.png` (1200 × 628) is a crop of `mdedit-light.png` (window interior, no shadow).

The PNGs are about 1 MB each (12 MB in all). Running them through `pngquant` or exporting as WebP would roughly halve that.

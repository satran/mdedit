# MDEdit: build plan

A native macOS Markdown editor/viewer in SwiftUI. Two columns: a **binder** (folder tree, Scrivener style) and a **writing pane** with Write and View modes. Styling follows Things: flat, quiet, no glass/vibrancy.

## 1. What the design (`plan/design.html`) specifies

Six screens: Write, Write (dark), View, Binder, Distraction-free, Settings.

**Window**
- 1280×820 default. Hidden title bar, traffic lights sit in the binder's top 52pt. Binder is 272pt wide and resizable. Header 52pt, footer 40pt.
- Solid colours only (no `.ultraThinMaterial`, no `NSVisualEffectView`). Dark mode is a full second palette.

**Binder**
- Search field (30pt, rounded 8) above a tree. Rows are 28pt, indent 16pt per level, chevron then icon then label, selected row filled.
- Top-level folders are semibold, with an 8pt gap between top-level groups. Footer: `+ New Document`, New Folder, Options.
- Design shows icon kinds: doc, blank doc, stack (folder that is also a document), folder, pdf, web, warn/flag. Italic rows mark a state (unread or draft, to confirm).
- Light: bg `#F4F5F7`, border `#E2E5E9`, text `#2B2E33`, muted `#686E76`, field `#E7E9ED`, selection `#DFE5EE`.
- Dark: bg `#25262A`, border `#34363B`, text `#DFE1E5`, muted `#9BA1A9`, field `#303237`, selection `#3A404A`.

**Writing pane**
- Header: breadcrumb (`Draft › A love letter… › DORA…`), Write | View segmented control, outline toggle.
- Footer: `132 words · 1 min read`, then Focus, Typewriter and Export buttons. In View mode: Print and Export.
- **Write**: IBM Plex Mono 16pt, line height 1.75, 640pt column, centred. Markdown stays in the text but is quiet (`#B4BAC2`). Block markers (`#`, `##`, `>`, `-`) **hang in the left margin** so the text edge stays flush. Headings are bold and larger, quotes italic, inline code on a chip, links `#2F6FDB`, caret `#3478F6`.
- **View**: Source Serif 4 18pt, line height 1.65, 640pt. H1 36pt bold, blockquote with a left rule, markers gone.
- **Focus**: full-screen, one column of 72ch, everything except the current paragraph dimmed, text fades out at the top, typewriter scrolling, `Esc` to exit, status line (`Typewriter · 72 characters · 151 words`).
- **Settings**: Editor (font from IBM Plex Mono, JetBrains Mono, SF Mono, Menlo or Source Serif 4; size stepper; line width Narrow, Medium, Wide or Custom 40–160ch, with a live preview), Viewer (font from Source Serif 4, Literata, New York, Inter or SF Pro; size). I only saw the first two sections of the Settings screen; I'll read the rest when I build it.

## 2. What I take from Dobby's `MarkdownTextEditor.swift`

Reuse the approach, not the dependency (no DobbyKit/DobbyCore):

| Piece | Use |
|---|---|
| `ThingsTextView: NSTextView` with `restyle()` re-applying attributes on every edit | Keep. Notes are small. |
| `MarkdownSyntax.analyze` (regex line analyser → spans and hanging lines) | Port into a local `MarkdownSyntax`, extend (see §5). |
| `ListMarker`, continue list on Return, Tab/Shift-Tab nesting, Backspace un-nest | Port as is. |
| ⌘B, ⌘I, ⌘E, ⌘K, ⇧⌘H wrap and toggle | Port. |
| Click a checkbox to tick it, ⌘-click a link | Port. |
| Hanging indent for wrapped list lines | Port, and generalise into the margin-hanging markers (§4). |
| `EditorController` bridging toolbar and menu commands to the text view | Keep. |
| `Markdown.parse` → blocks → `MarkdownView` | Do **not** port; View mode gets a proper GFM parser (§6). |

Dobby's markers sit inline and dimmed. The design hangs block markers in the margin, so this is the main thing that changes.

## 3. Architecture

Xcode project generated from `project.yml` with XcodeGen (macOS 14+, Swift 5 language mode), **App Sandbox on**. `make app` generates the project, builds with `xcodebuild` and puts `MDEdit.app` in `build/`. Also `make test`, `make run`, `make project`.

```
project.yml  Makefile  MDEdit.entitlements
Sources/MDEdit/
  MDEditApp.swift          App, WindowGroup, Settings scene, commands
  Model/
    Workspace.swift          @Observable: root folder, tree, selection, open document
    BinderNode.swift         tree node (folder/doc), sorting, filtering
    FolderWatcher.swift      FSEvents wrapper
    Document.swift           load/save, dirty state, debounce autosave
    WikiIndex.swift          name → URL index, link resolution, backlinks
    Preferences.swift        @AppStorage-backed fonts, size, width
  Syntax/
    MarkdownSyntax.swift     live-styling analyser (ported, extended)
    ListMarker.swift
  Editor/
    MarkdownTextEditor.swift NSViewRepresentable
    EditorTextView.swift     NSTextView subclass (style, keys, clicks, typewriter, focus dim)
    WikiLinkCompleter.swift  [[ autocomplete popover
  Viewer/
    MarkdownDocument.swift   swift-markdown → block tree
    ViewerView.swift         SwiftUI renderer
  UI/
    RootView.swift           HSplitView-style two columns
    BinderView.swift, BinderRow.swift, BinderFooter.swift
    DetailHeader.swift, DetailFooter.swift, FocusView.swift
    SettingsView.swift
    Theme.swift              Palette (light/dark), metrics
  Resources/Fonts/           IBM Plex Mono, Source Serif 4 (OFL), registered at launch
Tests/MDEditTests/
```

Dependencies: [`apple/swift-markdown`](https://github.com/swiftlang/swift-markdown) (cmark-gfm underneath: tables, task lists, strikethrough, autolinks). Nothing else.

**State flow**: `Workspace` (root URL, tree, selected node) → `Document` (text, dirty) → editor/viewer. `Preferences` is global. Two columns use a custom `HStack` with a draggable divider rather than `NavigationSplitView`, because `NavigationSplitView` adds sidebar material and its own toolbar chrome that fight the flat Things look.

## 4. The editor, in detail

- **Text system**: TextKit 1 `NSTextView` (as in Dobby). Accessing `layoutManager` is how Dobby does hit testing and typewriter geometry; TextKit 2 is not worth the risk for v1.
- **Hanging markers**: the text container is `column width + gutter` wide. Body paragraphs get `firstLineHeadIndent = headIndent = gutter`. Headings, quotes and list items get `firstLineHeadIndent = gutter − width(prefix)` so the `# `, `> ` or `- ` sits in the margin and the text starts at the column edge. Wrapped list lines get `headIndent = gutter`. Mono fonts make the prefix width exact; for the proportional option (Source Serif 4) it is measured from the attributed prefix, like Dobby does.
- **Centred column**: the text view is full pane width; left/right `textContainerInset` is computed from the pane width and the "line width" setting (N characters × advance of `0`).
- **Inline styling**: bold, italic, strike, highlight, code, links, plus new: wiki links, GFM autolinks, table rows (mono-aligned and dim pipes), footnote-style refs left plain.
- **Typewriter mode**: after each selection change, scroll so the caret line's rect is at the vertical centre of the clip view.
- **Focus mode**: dim all paragraphs except the one containing the caret (foreground alpha), fade the top via a mask on the scroll view, hide binder and chrome, 72ch column, `Esc` exits. Implemented as a flag on the same editor, not a second editor.
- **Find**: system find bar (`usesFindBar`), as in Dobby.
- **Spelling**: system spelling, quotes/dashes substitution off.
- **Undo**: system undo; programmatic loads of a file clear the undo stack.

## 5. Wiki links (Obsidian-style)

Syntax supported in v1: `[[Note]]`, `[[Note|alias]]`, `[[Note#Heading]]`, `[[folder/Note]]`.

- **Index**: `WikiIndex` maps lowercased filename (without extension) to URLs across the whole opened folder, rebuilt incrementally from `FolderWatcher`. Resolution order: exact relative path, then same-folder match, then shortest path (Obsidian's rule). Ambiguities resolve to the nearest.
- **Editor**: `[[` `]]` dimmed, target in link colour. Resolved links and unresolved links look different (unresolved: dashed or faint underline).
- **Interaction**: ⌘-click (or plain click in View mode) opens the note in the binder. Clicking an unresolved link offers to create the note in the current folder.
- **Autocomplete**: typing `[[` opens a small popover of matching notes (arrow keys, Return inserts `Name]]`). `#` after the name completes headings of the target.
- **View mode**: rendered as a link with an internal `mdedit://note/...` URL, intercepted by the viewer's `openURL` handler.
- **Backlinks**: computed from the index; shown in a "Linked mentions" section in the outline panel (v1.1, see §9).
- **Out of scope for v1**: `![[embeds]]`, rename-updates-links, block references `[[Note#^id]]`.

## 6. GFM in View mode

- Parse with swift-markdown. Wiki links are handled by pre-tokenising `[[...]]` into placeholder inline nodes before parsing (swift-markdown has no extension hook) or by post-processing the `Text` nodes. I'll use the post-processing approach so code spans and fenced blocks stay untouched.
- Supported: headings, paragraphs, emphasis, strong, strikethrough, inline code, fenced code (monospace, no highlighting in v1), blockquotes, ordered/unordered/nested lists, task lists, tables (with column alignment), thematic breaks, links and autolinks, images (local relative paths and http), hard breaks, HTML blocks shown as plain text.
- Renderer is SwiftUI `VStack` of block views, inline runs as `AttributedString` (fonts and colours from `Preferences`), selection enabled. Tables via `Grid`.
- Very long documents: render in a `LazyVStack`.

## 7. Binder and folders

- **Open folder**: `File ▸ Open Folder…` (⇧⌘O) with `NSOpenPanel`; remembered across launches (security-scoped bookmark). On first launch show an empty state with an "Open Folder" button.
- **Tree**: folders then files, natural-sorted; shows `.md` and `.markdown` files only and hides dotfiles. Other file types are hidden in v1 (the design's PDF and web rows imply Scrivener-style research items; I'll treat these as later).
- **Live updates**: FSEvents watcher updates the tree and the wiki index; if the open file changes on disk and is clean, reload; if dirty, keep mine and show a small "changed on disk" banner.
- **Operations**: new document (⌘N, in the selected folder), new folder (⇧⌘N), rename (Return or double-click), Move to Trash (⌘⌫, undoable via Finder), drag and drop to move between folders, Reveal in Finder, search filters the tree by filename and shows matches' ancestors (full-text search: v1.1).
- **Persisted UI state**: expanded folders, last selection, binder width, view mode.
- **Order**: the filesystem has no manual order, so v1 sorts alphabetically. Scrivener-style manual ordering could be a hidden `.binder-order.json` later.

## 8. Chrome and platform details

- `WindowGroup` with `.windowStyle(.hiddenTitleBar)` and `.windowToolbarStyle(.unified)` removed; the header/footer are our own SwiftUI views so the layout matches the design exactly.
- Menu bar commands: Open Folder, New Document/Folder, Write/View toggle (⌘1 Write, ⌘2 View, since ⌘E is code), Focus mode (⌃⌘F), Typewriter, Export, Find, formatting commands.
- Export: HTML, PDF (via print of the viewer), and Copy as Markdown. Print from View mode.
- Fonts bundled and registered with `CTFontManagerRegisterFontsForURL`; falls back to SF Mono / New York if missing.
- Autosave: 0.8s debounce plus on focus loss, switching documents and quitting; atomic write.
- Accessibility: all icon buttons labelled, VoiceOver reads the binder as an outline, Dynamic-type-like scaling via the font size setting, honours Reduce Motion.

## 9. Milestones

Each ends with a runnable app and unit tests where logic exists.

| # | Milestone | Done when |
|---|---|---|
| M0 | Skeleton | Package builds, `make-app.sh` produces a launchable app, empty two-column window with hidden title bar, light/dark `Palette`. |
| M1 | Folder and binder | Open a folder, tree renders per design, expand/collapse, selection, search filter, FSEvents refresh, persisted expansion. |
| M2 | Document load/save | Selecting a file shows its text in a plain `NSTextView`, edit and autosave round-trips safely, external-change handling. |
| M3 | Live editor | Ported `MarkdownSyntax` + `ThingsTextView`, hanging markers, centred column, list continuation, shortcuts, checkboxes. Matches the Write screen (light and dark). |
| M4 | Viewer | swift-markdown renderer with full GFM, Write/View switch, Source Serif styling. Matches the View screen. |
| M5 | Wiki links | Index, editor styling, ⌘-click, autocomplete, View-mode links, create-on-click. |
| M6 | Focus, typewriter, footer | Word count and read time, typewriter scroll, focus dimming, full-screen focus screen. |
| M7 | Settings | Editor and viewer font, size, line width, live preview, applied immediately everywhere. |
| M8 | Binder operations and polish | New/rename/trash/move/drag, outline panel (headings + backlinks), export/print, app icon, empty states, accessibility pass. |

I'd build M0 through M4 first (a usable viewer/editor), then stop for your feedback before M5 onward.

## 10. Testing and verification

- **Unit tests** (Swift Testing): `MarkdownSyntax` spans for each construct, `ListMarker`, wiki-link parsing and resolution, tree building and sorting, word count and read time, GFM block tree for a corpus (tables, task lists, nested lists, fences).
- **Fixture folder** `Fixtures/Sample/` with nested folders, wiki links (resolved, unresolved, ambiguous), a table, task lists and code, used by tests and manual runs.
- **Visual check**: run the app and compare screenshots against the six design screens (light, dark, view, focus, settings, binder) at 1280×820.
- Build with `swift build`; no warnings in my code.

## 11. Risks

1. **Hanging markers in `NSTextView`** via negative first-line indent math is fiddly with wrapping and font changes; fallback is dimmed inline markers exactly like Dobby.
2. **SwiftUI `NSViewRepresentable` text view** re-entrancy (update ↔ delegate) was solved in Dobby; I'll keep the same guards.
3. **swift-markdown has no wiki-link or GFM-footnote support**; handled by post-processing, footnotes deferred.
4. **Fonts**: bundling IBM Plex Mono and Source Serif 4 requires including OFL fonts in the repo; falls back if absent.
5. **Large folders**: tree and index build off the main thread, watcher debounced.

## 12. Decisions I made (tell me if any are wrong)

- **Sandboxed** Xcode project (XcodeGen `project.yml`, entitlements: user-selected read/write, app-scoped bookmarks), plus a `make app` target. The opened folder is remembered with a security-scoped bookmark.
- Only `.md`/`.markdown` files appear in the binder in v1.
- Alphabetical order, folders first, no manual ordering in v1.
- Wiki-link embeds, rename-refactoring and full-text search are after v1.
- The design's "stack" (folder that is also a document) and italic rows are not modelled in v1; folders are folders and files are files.
- Name: **MDEdit** (placeholder).

## 13. Status

M0–M8 are built. IBM Plex Mono and Source Serif 4 ship in the app (OFL, `Sources/MDEdit/Resources/Fonts`). Not done: full-text search, embeds `![[…]]`, heading completion after `[[Note#`, rename-updates-links, manual binder ordering.

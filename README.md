# MDEdit

A native macOS Markdown editor and reader, written in SwiftUI + AppKit. It opens a **folder** as a project (the *binder*, a tree like Scrivener's), edits notes in a live-styled monospaced **Write** mode, and shows them typeset in a serif or sans **View** mode. Wiki links (`[[Note]]`), GitHub-flavoured Markdown, front matter as a properties table, formatting shortcuts, a command palette, and several windows (one folder each).

The notes are plain `.md` / `.txt` files on disk. **The app is meant to hold important documents, so stability, speed and safety come before features.** Read [Rules for changes](#rules-for-changes) before editing.

This file is written for coding agents. Everything you need to build, run, test and change the app is here or linked from here.

---

## Quick start

```bash
brew install xcodegen          # once; the Xcode project is generated, never edited by hand
make app                       # build/MDEdit.app  (Release, ad hoc signed)
make run                       # build and open it
make test                      # the whole suite (~2 minutes); exit status is non-zero on any failure
make test T=DropTests          # one test class;  T=DropTests/testSomething  one test
make audit                     # static checks on entitlements and risky APIs (needs `make app` first)
make check                     # app + test + audit: run before trusting a change
make coverage                  # per-file line coverage of the last test run
```

- macOS 14+, Xcode with the macOS SDK, Swift 5 language mode. One SPM dependency: `swift-markdown` (cmark-gfm), fetched by Xcode on first build.
- `project.yml` (XcodeGen) is the source of truth for targets, entitlements, Info.plist keys and the scheme. `make` regenerates `MDEdit.xcodeproj` first, so a **new file under `Sources/` or `Tests/` is picked up automatically**. `MDEdit.xcodeproj/` and `Sources/MDEdit/Info.plist` are generated and git-ignored.
- Logs: `build/test.log` (full xcodebuild output), `build/TestResults.xcresult` (open in Xcode for failures and coverage).

**Do not run two `xcodebuild` / `make` commands at the same time in one checkout**: they lock `build/DerivedData` ("database is locked") or fight over `build/TestResults.xcresult`. Parallel agents must each work in their own git worktree (each has its own `build/`).

---

## What it does

| Area | What |
|---|---|
| Binder | Folder tree of the opened folder; folders first, natural order; `.md/.markdown/.txt` open as notes, other files show with their extension and preview in Quick Look (Space); search; rename (double click / ⌥⌘R), move (drag), copy in (drop from Finder), trash; ↑↓←→ keyboard navigation; folder name shown beside the traffic lights; Back (‹ in the header, ⌘[) returns to the previous note and Forward (⌘]) undoes it; 100 deep, skipping notes that were deleted |
| Write mode | Live-styled Markdown in IBM Plex Mono 17 pt, 1.65 line height, 72-character column; markers (`#`, `>`, `-`) hang in a 72 pt left gutter; code blocks as one tinted band; front matter in three quiet shades; image / file drops become links |
| View mode | Typeset reading templates: **Serif** (Literata 20 px) and **Sans** (Inter 18 px), switch in the footer; configurable line width; real punctuation (curly quotes, dashes, ellipses) in the viewer only; front matter as a Properties card; local images centred; links open through `LinkPolicy` |
| Wiki links | `[[Note]]`, `[[Note\|alias]]`, `[[Note#Heading]]`, `[[folder/Note]]`; nearest-folder resolution; completion after `[[`; backlinks and outline in the right panel |
| Formatting | Format menu + shortcuts: bold ⌘B, italic ⌘I, link ⌘K, code ⌘E, headings ⌥⌘1–6, lists, task, quote, code block, rule (all toggle) |
| Modes | Typewriter (caret line stays centred), Distraction free (full screen or in-window, setting), Outline panel |
| Windows | One window per folder (no tabs); File ▸ Open Recent; "New Window with This Folder" |
| Command palette | ⇧⌘P: every menu command, built from the same list as the menus |
| Export | HTML (sanitised), Print / PDF, Copy as Markdown |
| Settings | Theme (auto/light/dark), editor font/size/width, heading sizes, viewer template/size/width, remote pictures (off by default), status bar, distraction-free behaviour |

Original design intent is in `plan/PLAN.md` (historical: some details have moved on) and `plan/design.html`. The current typography spec is the "Type specs" board of the design file; its numbers live in `Viewer/ViewerStyle.swift` and the editor styling code and are locked by `TypographyTests`.

---

## Architecture

```
Sources/MDEdit/
  MDEditApp.swift          App entry: WindowGroup(for: UUID) — one Workspace per window; AppCommands; Settings scene
  Model/                   Observable state and file logic (no views)
    Workspace.swift        THE per-window model: opened folder, tree, selection, mode, panels, rename/move/trash,
                           drops, wiki open, backlinks, keyboard navigation, window layout toggles
    DocumentStore.swift    The open file: load/save, encodings, outside-change detection, autosave, recovery copy
    BinderNode.swift       Folder scan -> tree (symlink-safe, depth-capped); rows for the binder
    WikiLink.swift         [[ ]] parsing, WikiIndex (name -> files, nearest-folder resolution)
    LinkPolicy.swift       What a clicked link may do (web/mail only; files only inside the folder; programs revealed, never run)
    SafeHTML.swift         Markdown -> HTML renderer that escapes everything (see Security)
    Exporter.swift         HTML page, print (JS-off WKWebView), copy
    Preferences.swift      User settings (UserDefaults); viewerStyle derived from them
    RecentFolders.swift    Open Recent list with security-scoped bookmarks
    AppEnvironment.swift   Redirects settings to a scratch domain while tests run
    Fonts.swift            Registers bundled TTFs; family lookup
    FolderWatcher.swift    FSEvents -> debounced reload
    Outline.swift, QuickView.swift
  Syntax/                  Pure text logic, no UI
    MarkdownSyntax.swift   Line/inline analyser for the editor (spans, hanging-marker lines)
    MarkdownLimits.swift   Clamps nesting/line length BEFORE any parser runs (stack-overflow guard)
    FrontMatter.swift, ListMarker.swift
  Editor/                  Write mode (TextKit 1)
    EditorTextView.swift   NSTextView subclass: styling (restyle()), hanging markers, drawing (code bands, caret),
                           typewriter, drops, Shift-Return, mouse
    MarkdownTextEditor.swift       NSViewRepresentable + Coordinator (Return/Tab/Backspace list behaviour, selection), EditorBridge
    MarkdownFormatting.swift       PURE format transformations (text + selection -> edit); EditorFormatting.swift applies them
  Viewer/                  View mode (SwiftUI)
    ViewerParser.swift     swift-markdown -> [VBlock]; smart punctuation; splits images out of paragraphs
    ViewerStyle.swift      Every viewer size/space/colour per template (type specs)
    ViewerView.swift       BlockList/BlockView/TableBlock/ImageBlock/PropertiesBlock, link-cursor modifier
  UI/                      RootView, BinderView, DetailView (header/footer), FocusView, OutlineView, SettingsView,
                           Commands.swift (the ONE command list), FormatCommands.swift, Theme.swift (Palette, Metrics, TrafficLights)
  Resources/               Fonts (IBM Plex Mono, Source Serif 4, Literata, Inter + OFL licences), Assets.xcassets
Tests/MDEditTests/         See Testing
Fixtures/Sample/           Small sample notes
scripts/                   test.sh, audit.sh, release.sh, new-test.sh (+ template)
plan/                      PLAN.md, design.html, bugs/bugs.md, features/features.md
```

Key ideas:

- **One `Workspace` per window**, created in `WindowRoot` and shared with menus via `.focusedSceneObject`. Per-window state is keyed by a window id in `UserDefaults` (`folderBookmark.<uuid>`, `lastFile.<uuid>`); `id == nil` is the original single-window state.
- **One command list.** `makeCommands(...)` in `UI/Commands.swift` returns `[Cmd]` (id, title, shortcut, enabled, action). `AppCommands` builds the **menu bar** from it and `PaletteView` builds the **command palette** from it. Add a command once; it appears in both. `AppFeatureTests` fails if two commands share a shortcut or use a system one.
- **Editor = TextKit 1.** `EditorTextView.restyle()` re-styles the whole text on every edit (notes are short; hostile/huge input is capped). Markers hang by giving list/heading lines a negative first-line indent into a 72 pt gutter. Code bands and inline-code chips are **drawn** in `drawBackground`, not set as text backgrounds.
- **Pure logic is separated and tested directly**: `MarkdownFormatting`, `MarkdownSyntax`, `LinkPolicy`, `ViewerStyle`, `SafeHTML`. Prefer adding logic there over inside views.
- **Viewer** is SwiftUI `Text` blocks; selection is enabled, which makes macOS draw an I-beam over links, so `LinkCursor` hit-tests links with TextKit and sets the pointing hand.
- **Sandbox + security-scoped bookmarks.** The opened folder is reached through a bookmark (`NSOpenPanel` pick, or Open Recent). Anything that creates a bookmark from a URL must have **access open** (`startAccessingSecurityScopedResource`) — or reuse the saved bookmark data (see `Workspace.openRecent`).
- Settings live in `Preferences` (`UserDefaults`); `AppEnvironment.defaults` is the scratch domain used under XCTest so a test run never touches your real folders, recents or preferences.

---

## Shell commands (⌘R)

Off until enabled in Settings → Shell. `Model/ShellRunner.swift` is the only place that starts a program (`posix_spawn`, own process group, no inherited files, killed with its whole group when done), plus `ShellEnvironment` (clean env + `MD_*`, `KEY=value` extras) and `ShellOutput.clean` (strips escapes/bidi/NUL). `Model/Workspace+Shell.swift` is the flow: save the note, selection (or whole note) to stdin, run off the main thread, apply the output as one undo step (insert / replace / new file / panel) only if the note is unchanged. Saved scripts live in `<folder>/.mdedit/scripts` and need approval of their exact text; history is `<folder>/.mdedit/history` (0600, hidden from the binder). Tests: `ShellRunnerTests` (security), `ShellCommandTests` (feature). Plan and decisions: `plan/features/shell-scripting.md`.

## Testing — read `TESTING.md`

About 320 tests, ~100 s. `make test` must pass before any change is called done. Layout:

| Folder | Purpose |
|---|---|
| `Features/` | One test per user-visible feature (formatting, typewriter, typography numbers, Open Recent, editor behaviour, **EditorWindowTests**) |
| `Safety/` | Files are never changed unless the user changed them; fuzzing; hostile input must not hang or crash |
| `Security/` | Link policy, exported-HTML escaping, entitlements |
| `Performance/` | Loose time budgets that catch order-of-magnitude slowdowns |
| top level | Original per-area suites (syntax, binder, viewer, workspace, drop, keyboard navigation, snapshot renders) |

Helpers in `Tests/MDEditTests/Support/TestSupport.swift`: `Scratch` (temp folder with files), `makeWorkspace(open:)`, `isolatedDefaults()`, `within(seconds) { }`, `SeededRNG`. New feature? `scripts/new-test.sh Name [Features|Safety|Security|Performance]` scaffolds a test file with the four tests every feature needs (normal use, hostile input, failure halfway, speed).

**Testing editor behaviour: use a real window and real events.** Tests that call methods directly passed while the app was still wrong (Shift-Return reaches a text view as a plain Return; typewriter scrolling only misbehaves inside a real scroll view). `EditorWindowTests` builds an offscreen `NSWindow` with a real `NSScrollView` + `EditorTextView`, sends `NSEvent` key events with `window.sendEvent`, runs the run loop with `settle()`, and even samples rendered pixels. Copy its `make(...)` helper. Harness gotchas that cost hours:

- `NSTextView.delegate` is **not retained**: keep the `Coordinator` alive in the test (`coordinators` array) or you get a crash at autorelease-pool pop.
- Set `window.isReleasedWhenClosed = false` for windows created in code.
- The editor draws **no background**: a pixel with nothing behind it has alpha 0, not white.
- Prove a new regression test fails without the fix (revert the fix, run, restore) before trusting it.
- The test process is the sandboxed app itself (it hosts the tests): it cannot reproduce sandbox refusals for folders outside the container.

---

## Rules for changes

1. **Files are sacred.** Never write to a file the user did not change. All saving goes through `DocumentStore` (keeps encoding/BOM/symlink/permissions/Finder tags, refuses to overwrite an outside change, saves on close/quit/switch, makes an `(unsaved changes)` copy on conflict). Files that are not text or > 10 MB are shown as an error and never written.
2. **Treat every note, file name, link and dropped file as hostile.** File names go through `Workspace.cleanName`; links through `LinkPolicy.decide`; exported HTML through `SafeHTML` (swift-markdown's own `HTMLFormatter` does **not** escape anything — never use it); Markdown goes through `MarkdownLimits.clamp` before parsing.
3. **Nothing recursive or quadratic without a limit.** Scans stop at `BinderNode.maxDepth`; inline styling skips lines over `MarkdownSyntax.maxInlineLength`; parsers have time budgets in `HostileInputTests`.
4. **No new entitlement.** Exactly four are allowed (sandbox, user-selected read-write, app-scope bookmarks, network client); `make audit` and `ProjectPolicyTests` fail otherwise. Release builds must not carry `get-task-allow` (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: false`). There is no URL scheme and no AppleScript. The only external programs are the shell commands a person types (⌘R), and only `Model/ShellRunner.swift` may start one (`make audit` checks): sandboxed, clean environment, own process group, timeout, output cap, never from note content.
5. **Add the test first for a bug**, and one for each new feature (`scripts/new-test.sh`). Add commands to `Commands.swift`, not to individual views.
6. **Don't edit generated things**: `MDEdit.xcodeproj`, `Info.plist`. Change `project.yml`.
7. **Match the surrounding code**: comment density, naming, idiom. Comments explain *why*. Keep views thin and logic in `Model/` / `Syntax/` / `Editor/Markdown*`.
8. **Type specs are numbers, not taste.** If you change a size, spacing or colour, update `TypographyTests` in the same change and say why.

---

## Gotchas (learned the hard way)

- **Shift-Return** arrives as `insertNewline:` (same as Return). `EditorTextView.keyDown` intercepts Shift/Enter and calls `Coordinator.softBreak` (plain new line + the line's existing indentation only).
- **Typewriter mode** changes the text view's top/bottom padding to half the pane; a text view only *grows* by itself, so `fitToContent()` resizes it explicitly and `typewriterChanged()` keeps the caret's screen position when turning it off.
- **Closing the command palette** returns the keyboard to the editor (`Workspace.paletteVisible` didSet) — otherwise the caret disappears.
- `NSTextView.drawBackground` is where bands/chips are drawn; `needsDisplay` is set at the end of `restyle()`.
- **Window buttons**: `TrafficLights` repositions the three buttons after every window update (AppKit resets them on appearance change).
- `swift-markdown`'s `Document(parsing:)` enables smart punctuation by default; the viewer passes `.disableSmartOpts` and applies its own `SmartPunctuation` so code, URLs and front matter are untouched.
- `Preferences`, `RecentFolders` and `Workspace` take a `defaults:` parameter; in tests use `isolatedDefaults()` / `makeWorkspace()`. `AppEnvironment.isTesting` is true when XCTest hosts the app and redirects the shared defaults.
- Never run tests or builds concurrently in one checkout (see Quick start). When the hostile-input tests print NUL bytes, `build/test.log` is "binary": use `grep -a`.
- Fonts: Literata and Inter are variable TTFs; weights come from the weight axis. If a family is not bundled the viewer falls back to the system serif/sans.
- Entitlement-sensitive code cannot be unit tested; say so in your report and ask for a manual check.

---

## Working method (used for the current backlog)

- Bugs and features are listed as `- [ ]` tasks in `plan/bugs/bugs.md` and `plan/features/features.md`. Fix → test → commit → tick `- [x]` → rebuild (`make app`).
- Parallel work: one agent per task, each in its own git worktree/branch (`isolation: "worktree"`); agents run only their own test classes (`scripts/test.sh ClassName`); the coordinator merges, runs the **full** suite and `make audit`, then rebuilds. Remove merged worktrees/branches afterwards.
- Commits: one logical change each, message explains the why; follow the attribution trailer your harness specifies.
- When a result cannot be verified headlessly (look, hover, real key routing, sandbox), say so plainly and ask the user to check it in `build/MDEdit.app`.

---

## Where to look first

| If you are changing… | Start at |
|---|---|
| How a note looks while writing | `Editor/EditorTextView.swift` (`restyle`), `Syntax/MarkdownSyntax.swift`, `UI/Theme.swift` (`Palette`) |
| How a note looks in View mode | `Viewer/ViewerStyle.swift`, `Viewer/ViewerView.swift`, `Viewer/ViewerParser.swift` |
| A key or menu command | `UI/Commands.swift` (menu + palette), `Editor/MarkdownTextEditor.swift` (Return/Tab/Backspace), `Editor/MarkdownFormatting.swift` |
| Opening, saving, conflicts | `Model/DocumentStore.swift` |
| The binder, files, drops | `Model/Workspace.swift`, `Model/BinderNode.swift`, `UI/BinderView.swift` |
| Windows, recents, bookmarks | `MDEditApp.swift`, `Model/Workspace.swift`, `Model/RecentFolders.swift` |
| Anything touching untrusted input | `Model/LinkPolicy.swift`, `Model/SafeHTML.swift`, `Syntax/MarkdownLimits.swift`, `Security/` tests |

## Icon

The icon is `icons/AppIcon.appiconset` (with the 1024 px PNG, SVG and `.icns` beside it). `make app` copies the set into the asset catalog, so change the icon in `icons/` only.

## Releasing

`make release` audits the app and writes `build/MDEdit-<version>.dmg` (version from `MARKETING_VERSION` in `project.yml`; bump it, and `CURRENT_PROJECT_VERSION`, first).

| Command | Result | Runs on |
| --- | --- | --- |
| `make release` | ad hoc signed | your own Macs; on another Mac the first launch needs right-click ▸ Open (or `xattr -dr com.apple.quarantine /Applications/MDEdit.app`) |
| `make release SIGN="Developer ID Application: Name (TEAMID)" NOTARY=profile` | signed, notarised, stapled | any Mac, no warning (needs the paid Apple Developer Program; make the profile once with `xcrun notarytool store-credentials profile`) |

The Mac App Store is a separate path: an "Apple Distribution" certificate, an app record in App Store Connect, a signed `.pkg` (`productbuild`) uploaded with Transporter. The app is already sandboxed with only the entitlements the store allows.

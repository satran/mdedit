# Testing MDEdit

MDEdit holds important documents, so the rule is: **a change is not done until `make check` passes.**

```bash
make test                  # the whole suite (about 1–2 minutes). Exits non-zero on any failure.
make test T=DropTests      # one class;  T=DropTests/testBinderDrop...  one test
make audit                 # static checks on the privileges and risky APIs (needs `make app` first)
make check                 # build + test + audit: run this before you trust a change
make coverage              # per-file line coverage of the last test run
```

Output is a short list of failures and the totals. The full log is `build/test.log`; open
`build/TestResults.xcresult` in Xcode for results and coverage by line.

## What is tested, and where

| Folder | Question it answers | Examples |
|---|---|---|
| `Tests/MDEditTests/Features` | Does every feature do what it should? | recent folders, windows, preferences, palette, outline, search, backlinks, wiki links, viewer |
| top level (`SyntaxTests`, `BinderTests`, `WorkspaceTests`, `DropTests`, `KeyboardNavTests`, `FrontMatterTests`, `ViewerTests`, `CommandTests`, `SnapshotTests`) | The original per-area suites | Markdown styling, binder tree, rename/move, drag and drop, arrow keys, front matter |
| `Safety` | Is a file ever changed when it should not be, or an edit lost? | encodings, BOM, symlinks, outside changes, closing mid-autosave, read-only folders, odd file names, folder loops, random action fuzzing |
| `Security` | Can a malicious note or file do harm? | links (`javascript:`, `file:`, programs, `..`), exported HTML and print (script, handlers, CSP), entitlements, no URL scheme |
| `Safety/HostileInputTests` | Can text built to hang or crash the parsers do so? | 100,000 nested quotes, quadratic regexes, NUL bytes, 2 MB lines, random soup |
| `Performance` | Is it still fast? | 3,000-note folder, 400 KB note styling, export, backlinks over 1,000 notes |

`make test` runs the app itself as the test host, with its settings redirected to a scratch domain
(`AppEnvironment`), so a test run never reads or changes your real folders, recent list or preferences.

## Adding a test when you add a feature

```bash
scripts/new-test.sh Bookmarks             # Tests/MDEditTests/Features/BookmarksTests.swift
scripts/new-test.sh Importer Safety       # or Safety / Security / Performance
```

The template has four tests to fill in — normal use, hostile input, failure halfway, speed. Helpers in
`Tests/MDEditTests/Support/TestSupport.swift`:

* `Scratch(["Notes/One.md": "text", "pic.png": Data(...)])` – a temp folder with files; `s.path("…")`, `s.read("…")`, `s.exists("…")`; `s.remove()` in `tearDown`.
* `makeWorkspace(open: s.url)` – a `Workspace` on isolated settings and recents. Never use `Workspace()` on the real defaults.
* `isolatedDefaults()` – an in-memory `UserDefaults` for `Preferences`, `RecentFolders`.
* `within(seconds, "label") { … }` – fails if the block is slow. Budgets are loose; they catch order-of-magnitude slowdowns.
* `SeededRNG(seed:)` – repeatable randomness for fuzz tests; print the seed in the failure message.

New file in the project? `make test` runs `xcodegen` first, so a new test file is picked up automatically.

## Rules that every new feature should follow

1. **Treat every note, file name and dropped file as hostile.** Never build a path from text without `Workspace.cleanName`; never open a link without `LinkPolicy.decide`; never put note text in HTML without going through `Exporter.safeHTML`.
2. **Never write to a file the user did not change.** Anything that saves goes through `DocumentStore` (it keeps encodings, symlinks, and refuses to overwrite an outside change).
3. **Nothing recursive without a limit.** Parsing goes through `MarkdownLimits.clamp`; folder scans stop at `BinderNode.maxDepth`; inline styling stops at `MarkdownSyntax.maxInlineLength`.
4. **No new entitlement without a reason.** `make audit` and `ProjectPolicyTests` fail on any entitlement outside the expected five (the fifth, `network.server`, is for agent access and only `Agents/MCPServer.swift` may listen, on loopback).
5. **Add the test for the bug before fixing the bug.**

## Known gaps (not covered by automated tests)

* Real mouse and keyboard interaction, drag and drop from Finder, Quick Look, the print panel, window animation and the traffic-light placement: these need a person. A short manual check before a release: open a folder, type in a note, switch notes, rename, drag a file in, toggle every panel, switch theme, quit while typing and reopen.
* The first launch after a macOS update (sandbox access to a previously opened folder).

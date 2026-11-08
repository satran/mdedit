# 003 · HTML files, and a web-view preview for Markdown

Status: built. See "As built" at the end for where it differs from the plan.

## Goal

1. Open `.html` / `.htm` files from the binder and show them, with no editor.
2. Render the Markdown preview in the same web view, so there is one renderer to support. This also makes custom CSS for the preview possible.

`ViewerView`, `ViewerParser` and `ViewerStyle` (about 800 lines of SwiftUI layout) go away. Their look moves into a stylesheet.

## Decisions

| Question | Decision |
|---|---|
| Renderer | One `WKWebView` for Markdown preview and HTML files. |
| JavaScript | Off, for both. |
| Remote images and stylesheets | Blocked by default. Settings option "Load remote images and stylesheets" turns them on (global, off by default). |
| Eye button | Always shown. Disabled (dimmed, not clickable) on an HTML file. |
| HTML editing | None. Read-only. |
| Custom CSS | A `preview.css` the user controls; applies to the Markdown preview only. See below. |

## How it fits together

### 1. File types

- `BinderNode.htmlExtensions = ["html", "htm"]`; `documentExtensions` includes them, so they list in the binder, the palette and `[[links]]`, and `select` opens them.
- HTML files keep their extension in the binder (`about.html`), so they are not mistaken for notes.
- `Workspace.isHTML` (the open document's extension) drives the rest.
- Not registered in `project.yml` as a document type, so MDEdit is not offered as the default HTML opener.

### 2. Mode follows the file

- Opening an HTML file sets `mode = .view`.
- With an HTML file open: Write (⌘1), Preview toggle (⇧⌘E), the eye button and Run Shell Command (⌘R) are disabled. The eye button stays visible.
- The editor is never created for HTML, so nothing can write to the file.

### 3. `PreviewWebView` (new, replaces `ViewerView`)

An `NSViewRepresentable` around `WKWebView`.

- **Markdown**: `SafeHTML` output (already escapes everything and blocks unsafe link schemes) wrapped in a page: `Exporter.html` is the starting point and becomes `PreviewPage.html(markdown:…)`, shared by the preview, HTML export and print. Loaded with `loadHTMLString(_, baseURL: noteFolder)` so relative images resolve.
- **HTML file**: `loadFileURL(_, allowingReadAccessTo: rootURL)`, so relative CSS and images next to it work, and nothing outside the opened folder is readable.
- Reloads on text change (Markdown) or on disk change (HTML: reuse the `checkDisk` / folder watcher; bump a version counter). Keeps scroll position across reloads.
- Dark mode: `color-scheme` plus the palette as CSS variables, updated when the appearance changes.

### 4. Locking it down

- `allowsContentJavaScript = false`.
- Navigation delegate: only the initial load is allowed. A link click is cancelled and handed to `LinkPolicy.decide` (same actions as today: wiki, web, select note, open file, reveal).
- A `WKContentRuleList` blocks every `http(s)` subresource (images, stylesheets, fonts, frames, media) unless the setting is on. `file:` and `data:` stay allowed. Rules are recompiled when the setting changes and the page reloads.
- Markdown pages also get the existing CSP meta tag and `no-referrer`. The tag follows the setting (`img-src` / `style-src` allow `https:` only when it is on).
- No new entitlement. `network.client` is already granted; the audit still enforces the four.
- HTML files can contain `<meta http-equiv=refresh>` and forms: refresh navigation is cancelled by the same delegate; form submits are cancelled.

### 5. Custom CSS

Keep it simple and visible:

- File: `<opened folder>/.mdedit/preview.css` (the folder already holds scripts and history and is hidden from the binder). Loaded after the built-in stylesheet, so it can override anything.
- Settings ▸ Viewer gets "Custom stylesheet: Reveal / Create" which writes a commented starter file listing the CSS variables and class names, then reveals it.
- Injected as a `<style>` in the generated page (no file URL needed, so no extra read access). Size capped (e.g. 256 KB). Edits to it are picked up by the existing folder watcher.
- Applies to Markdown only. HTML files are shown as authored.
- A global stylesheet (one for every folder) is left for later; per-folder matches how the app already stores per-folder things.

### 6. What the old viewer did that the stylesheet or page builder must cover

Ported into `PreviewPage` / CSS (each has tests today in `ViewerTests`, `ViewerImageTests`, `ViewerSpacingTests`, `TypographyTests`):

- Serif (Literata) / Sans (Inter) templates, size, width in characters, the spec's sizes, line heights and collapsing margins. The two templates become two CSS blocks driven by variables from `Preferences`. Fonts: the bundled fonts are made available to the web view with `@font-face` pointing at the bundle (needs a check that a `file:` font loads under the sandbox, or inline `data:` fonts as a fallback).
- Smart punctuation (`SmartPunctuation`), applied to text nodes in the Markdown before rendering, never to code or link targets. Kept as Swift code.
- `[[wiki links]]` and bare web addresses become links (today in `ViewerParser`): move to a pre-pass on the AST that feeds `SafeHTML`. Wiki links use the existing `WikiLink` URL form, so `LinkPolicy` is unchanged.
- Front-matter properties table (`PropertiesBlock`): `Exporter.propertiesHTML` already does this for export; reused.
- Task lists, tables (hairlines, tracked small-caps headers), blockquotes, code on a chip, hanging list markers: CSS.
- Images: relative paths resolve against the note's folder; the old decode-size guard (`ImageBlock`) becomes `max-width: 100%` plus the content rule list. A huge-bitmap guard is lost; WebKit decodes in its own process, which is the safer place for it.
- Link cursor and text selection: native in a web view, so `LinkCursor` and `FlowLayout` are deleted.
- Typewriter / focus mode are editor features and unaffected.

### 7. Everything else that touches HTML files

- Footer: no Serif/Sans switch for HTML; word count from the visible text (tags stripped in Swift, no JavaScript).
- Find ▸ This file: disabled for HTML. Find ▸ Folder: searches HTML files as text, but their results cannot be replaced in this version (matches in HTML are skipped by Replace).
- Outline panel: empty for HTML (headings could be read from `<h1>`–`<h6>` later).
- Export, Print, Copy Markdown: disabled for HTML.
- Back/Forward, breadcrumb, recents, drag-to-link: work as they do now.
- Manual: a short "HTML files" section and the custom CSS section; README rows.

### 8. Settings

Settings ▸ Viewer gains:

- "Load remote images and stylesheets" toggle (`Preferences.loadRemote`, default off), with a one-line note that it lets pages contact the web.
- "Custom stylesheet" row (see 5).
- The existing live preview in Settings (`viewerPreview`, drawn with SwiftUI fonts) is replaced by a small web view using the same page builder, so it cannot drift from the real preview.

## Order of work

1. `PreviewPage` builder + CSS, `PreviewWebView` with the lock-down, and Markdown rendering through it. Switch `DetailView` over. Delete the SwiftUI viewer. Port tests to assert on the generated HTML/CSS and on a real web view where layout matters.
2. HTML file type: extensions, mode forcing, disabled commands and eye button, file loading, reload on change.
3. Settings: remote content toggle, content rules, CSP follows it.
4. Custom CSS: file, starter, watcher reload, Settings row.
5. Manual, README, audit.

Steps 1 and 2 are separate commits.

## Tests

- Classification of `.html`/`.htm`; opening one sets view mode; Write, eye, shell, export are disabled; the eye button still exists.
- JavaScript is off: a fixture whose `<script>` would change the DOM leaves it unchanged (checked by snapshotting the text, since JavaScript cannot be used to read it).
- Remote content: a local test server (or a `http://127.0.0.1` URL) is never contacted while the setting is off, and is contacted when it is on. A `file:` image and a relative stylesheet always load.
- Navigation: link clicks, meta refresh and form submits never navigate the web view; links reach `LinkPolicy`.
- Read access: an HTML file that references `../outside.png` outside the opened folder does not load it.
- Markdown parity: smart punctuation, wiki links, bare URLs, front matter, task lists, tables, images — as generated HTML.
- Custom CSS: applied after the built-in sheet; size cap; missing file ignored; a change reloads the preview.
- Hostile input: the existing `ExportSecurityTests` and `HostileInputTests` keep passing against the shared page builder.
- Pixel checks for the spec sizes where they exist today (`TypographyTests`, `ViewerSpacingTests`), redone against the web view.
- `make audit` unchanged (four entitlements).

## Risks and open points

- **Look parity.** The SwiftUI viewer was tuned to the type specs; matching it in CSS needs a side-by-side pass. Mitigation: keep the old viewer until the web version matches, then delete it in the same commit that switches over.
- **Fonts in the sandbox.** Bundled `.ttf` through `@font-face` from a `loadHTMLString` page may be blocked; fallback is inline `data:` URLs.
- **Performance.** Large notes re-render the whole page on each change. The preview only updates while visible, and `PerformanceTests` gets a web-view case. Reload is debounced.
- **Content rule list is asynchronous to compile.** The page must not load until it is installed; handled by compiling at startup and on setting change.
- **WebKit view and tests.** Layout-dependent tests need a hosted window; the harness already does this for panel pixel tests.
- **HTML with relative links to other HTML files.** They open in the same pane through `LinkPolicy.selectNote`, so Back works.

## As built

Differences from the plan above:

- **`ViewerStyle` stays.** It is the one place the type-spec numbers live; `PreviewPage.css` is generated from it, so `TypographyTests` still lock the numbers. Only `ViewerView` and `ViewerParser` were deleted. The small SwiftUI preview in Settings keeps using its font helpers.
- **A custom URL scheme instead of `loadFileURL`.** Pages, pictures, stylesheets and fonts load through `mdedit-file://`, served by `PreviewFiles`. This is how "only the opened folder" is enforced for Markdown and HTML alike (WebKit does not let a string-loaded page read `file:` URLs), and how the bundled fonts reach the page without `data:` URLs. HTML files are served with a `Content-Security-Policy` header as well.
- **Export and Print keep their own simple page** (`Exporter.html`), not the preview page: it must be standalone.
- **HTML files are not notes.** They are left out of `BinderNode.files`, so they are not in wiki links, the outline's backlinks, Find in Folder or Replace. Opening Find from a page switches to the Folder scope.
- **Settings:** the existing "Remote pictures" switch now also covers stylesheets and fonts (same stored key, so the old choice is kept). The custom stylesheet is made from **View ▸ Edit Preview Stylesheet…**, since Settings has no open folder to work in.
- **Properties card** has no per-key icons.
- **Reloading a page** follows its own text; changes to a page's stylesheets or pictures need reopening it.

Checked against a real HTTP server on `127.0.0.1`: with remote content off, a Markdown image, a page's `<img>` and its stylesheet made no request; with it on they all did.

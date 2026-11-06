# Templates for HTML previews

*   **Author:** Satyajit Ranjeev
*   **Status:** Built (steps 1 to 4; see "As built"). Built on plan 007 (built): `ConfirmPrompt` (a plain two-button alert, extended in item 12 below) and `ContentHash`
*   **Date:** 2026-11-06

--------------------------------------------------------------------------------

## Overview

MDEdit shows HTML files in a locked-down web view, but the pages are static: a file shows only what is written in it. This design adds a template system for HTML files. A template is an HTML file that contains template tags. The app fills in the tags and shows the result in the preview. The tags can list the files under a folder and read parts of those files (the text under a heading), so a page can be an index or summary generated from the notes in the opened folder.

The template language is a small subset of Django's, with the same look (`{{ value }}`, `{% for %}`, `{% if %}`) and a few read-only tags of our own. The parser and the evaluator are written in this repository, with no new dependency. The evaluator counts every step it takes, so a render ends at its step budget, at a 2 second clock, at the output cap, on a cancel or when the document changes; one exception is described under "Why a render ends". The rendered page is a view only: rendering never writes, renames or deletes anything, and the design blocks network requests on its own (with the limits stated under Goals).

## The Problem

A person who keeps notes in a folder wants pages that are built from those notes: an index of a project folder, the latest entries from a journal, the "Summary" section of every note in a directory. Today the only way is to write the page by hand and keep it up to date, or to run a script outside the app.

The obvious fix, a template engine, is also the risky one. A template engine reads files, and templates come from many places: written by the person, written by an agent, or downloaded. A template that can run code, write files or reach the network can damage the notes or send them somewhere. The person's stated priority is that previewing a page must not be able to harm their files, so the design starts from the assumption that every template is hostile and is judged on what a hostile template cannot do.

## Goals

*   Render an HTML template that lists the files under a folder and reads parts of those files (a heading's section) into the page, newest first if the template asks.
*   A template cannot change anything on disk: the language has no tag, filter or path that writes, renames, deletes or runs a program, and the engine's source has no such call. The grammar is the guarantee: there is no construct that writes. `make audit` is a tripwire over the source for the names of write, process and network APIs, and each rule has a test. The app also holds `files.user-selected.read-write` and `network.client`, so the sandbox is not a second line of defence for this engine; every containment layer here is application code.
*   A template can read only inside the opened folder, after symlinks are resolved, and never hidden files or non-note files (including a visible name that links to a hidden file), using one shared path check (`SafePath`) that the agent tools use too. The pictures and styles of a rendered page cannot read hidden files either.
*   A render ends. Every step is counted against a budget, and the evaluator also stops at a 2 second clock, at the output cap, when the person presses Cancel and when the document changes. A template over one of the hard limits shows an error page; a `files` list over its length is cut, and a single read that cannot be done leaves that one result empty (see Limits). Nothing in the language can make a loop longer than a list the app supplied. A single read blocked in the operating system cannot be interrupted: the preview shows the timeout error within the clock and the window refuses a new render until that read returns.
*   A rendered page makes no network request on its own (images, stylesheets, fonts, frames, `ping`, forms, meta refresh), even when "Remote pictures and styles" is on in Settings. Resource loads are blocked by the header and a rule list (layers 1 and 2). Connection hints (`dns-prefetch`, `preconnect`) are not resource loads, and nobody knows whether the header and the list stop them in this WebKit; the app does not rely on that and refuses to show a page that contains a tag able to open a connection (layer 3, a deny-list). So the goal is met as far as these three layers and their tests go; a click on a web or mail link is the one request the person starts, and it asks first. See "Delivery and containment".
*   A template file renders only when the person presses Render, and the very first Render in the app shows a one-time warning that a rendered page can read every note in the folder. After that Render just renders; an edited template does not ask again.
*   Template rendering lives in the existing preview, with JavaScript off.

## Non-Goals

*   Editing templates in the app. HTML files stay read-only in MDEdit; templates are edited elsewhere, and when the file changes on disk the plain file reloads and the person presses Render again.
*   Saving or exporting rendered output. The feature does not write the rendered page anywhere.
*   Writing, creating or modifying notes from a template.
*   Running JavaScript in the page, in the template or in the preview.
*   Templates for Markdown notes. This design covers HTML files only.
*   A general programming language: no arithmetic, no ranges, no recursion, no way to build a list in a template, no `include` or `extends`, and no user-defined tags or filters.
*   Trusting any template. There is no "trusted template" mode that lifts the caps or the no-network rule.
*   Compatibility with Django or Stencil (a Swift template library that an earlier draft used, see Alternatives D and E) templates beyond the subset below. A template written for either may fail with a syntax error here, by design.

## Open Questions

No design question is open. Settled in the body: a file is a template when it is an `.html` or `.htm` file whose text contains `{%` or `{{`; templates are edited outside the app; the output is never saved; the parts of a file a template can read are a heading's section and a file's title.

One measurement is open: the limit values (see Limits). The performance tests in step 2 settle it.

**Related plans.** Plan 003 (built) added HTML files and the preview this feature extends. Plan 005 (built, the Review tab committed separately) added the agent tools and `AgentTools.resolve`, whose path check item 1 extracts. Plan 007 (built) removed shell commands and moved `ConfirmPrompt` and `ContentHash` out of the shell files.

--------------------------------------------------------------------------------

## Technical Plan (Architecture)

### How a template becomes a page

A template is an `.html` or `.htm` file. Today such a file opens in the preview exactly as written (JavaScript off, remote loads blocked unless Settings allows them). That does not change. What is new is a second path that the person starts with the **Render** button, and that path runs in this order:

```text
template.html (disk), read once as one string
   |  1. parse   size, tokens, nesting, every tag and filter name checked against the grammar
   v        any failure -> error page with the line, nothing runs and nothing is asked
   |  2. first Render in the app?  a one-time warning (the answer is kept in the app settings)
   v        yes -> warning sheet, then Render; no -> straight on
   |  3. evaluate  background task, step budget, 2 s clock, cancel flag
   |        tags: files / section -> SafePath -> read-only file reads, counted
   v        any hard limit or timeout -> error page; cancel -> the plain file, as before
   |  4. output string (at most 2 MB), held in memory, then scanned by TemplateOutputGuard:
   v        a tag able to open a connection (see "Delivery and containment") -> error page
   |  5. delivered by PreviewFiles as an in-memory page at a fixed address at the opened
   v        folder's root, with a Content-Security-Policy HEADER (PreviewPage.csp(loadRemote: false)),
            under a template rule list that blocks every http(s) request of any type
WKWebView (JavaScript off, link clicks go to the template link sheet)
```

Nothing in steps 1 to 5 writes to the folder. The grammar's tags are the only way a template reaches the disk, and they only read (`make audit` is a tripwire over the source, not a proof). Settings are written only in step 2, to the app's own settings.

### The template language

The syntax looks like Django's, and the parser accepts exactly the grammar below and nothing else. Anything outside it is a syntax error with a line number: that is how the language stays closed, with no list of names to keep up to date.

**A complete example.** This template lists the notes in `journal/` and shows each note's "Summary" section as formatted text:

```text
<h1>Journal</h1>
{% files "journal" as items %}
{% for f in items %}
  <h2><a href="{{ f.path|urlencode }}">{{ f.title }}</a> <small>{{ f.modified }}</small></h2>
  {% section f.path "Summary" as text %}
  {{ text|markdown }}
{% empty %}
  <p>No notes yet.</p>
{% endfor %}
```

**The grammar.** In the tag forms below, `path`, `folder` and `heading` are each a quoted literal or a variable.

| Construct | Form | Meaning |
|---|---|---|
| Text | anything outside `{% %}`, `{{ }}`, `{# #}` | Copied as written. It is the template author's own HTML and is not changed. |
| Comment | `{# … #}` | Dropped. |
| Print | `{{ operand }}` or `{{ operand\|filter\|filter:arg }}` | Prints the value, HTML-escaped (see "Values and escaping"). |
| Loop | `{% for x in name %}…{% empty %}…{% endfor %}` | Runs the body once per item of the list variable `name`; `{% empty %}` runs when the list is empty or `name` is not set. `name` is a variable, never a call or a range, and any other type is an error naming it. Nesting at most 2 deep. |
| Condition | `{% if cond %}…{% else %}…{% endif %}` | `cond` is two operands joined by `==` or `!=`, or one operand alone (true by the Truth rule below). Operands of different types are never equal; text compares by exact characters. |
| List a folder | `{% files folder [sort "name"\|"modified"] [reverse] [limit N] as items %}` | Sets `items` to a list; the clauses come in this order. See below. |
| Read a section | `{% section path heading as text %}` | Sets `text`; see below. |
| Read a note's meta | `{% meta path as m %}` | Sets `m` to the note's meta block as a record; see below. |

*   **`meta`**: the note's meta block, the `key: value` lines between `---` lines at the top of the note, read by `FrontMatter.parse` as the View's properties card is: text (quoted or not), `[a, b]` or `- a` lists, and `true`/`false`. `m.title` is the text; a list is a list of text; `true` is the text "true" and `false` is empty (so `{% if m.draft %}` works); a missing key, or a note without a block, is empty. Only the top `metaBytes` (16 KB) of the note are read, so a long note still gives its meta. Failures set `m` to an empty record and `m_error` to `not available`, `not text`, `unreadable` or `read budget used`. Values print escaped like any text, and can name a folder: `{% meta "cfg.md" as m %}{% files m.folder as items %}`.
*   **Names and spacing.** A name is `[A-Za-z_][A-Za-z0-9_]*`; a dotted name looks up a key in a record and is an empty value when the key is missing. The words `for`, `in`, `empty`, `endfor`, `if`, `else`, `endif`, `files`, `section`, `as`, `sort`, `reverse` and `limit` cannot be names, and a name given to `as` cannot end in `_error`. Inside `{% %}` and `{{ }}` any spaces or tabs may separate parts, but not a line break. A `{{`, `{%` or `{#` with no closing `}}`, `%}` or `#}` is a syntax error at its line.
*   **Scope.** All names live in one table for the render. `for x in items` sets `x` on each pass and restores the earlier value of `x` (or removes it) after `endfor`. A read tag sets its `as` name and its `<name>_error` name, replacing any earlier value; inside a loop that happens on each pass.
*   **Truth.** In `if`, empty, `0`, empty text and an empty list are false; everything else (a record and any markup included) is true.
*   **Operands.** A variable (`name`, `f.path`, dotted, no calls), a string in double quotes (`\"` and `\\` are the only escapes) or a whole number of at most 9 digits. A variable that is not set is empty. An operand of the wrong type for a tag or filter is an error naming the variable (`TemplateError.type`).
*   **Filters.** Exactly these. `default:"text"`: when the value is empty or is empty text, use the text; any other value is returned unchanged. `urlencode`: text only; percent-encodes every character except letters, digits, `-._~` and `/` (`/` stays so a relative path stays a path), for use in a link address, since HTML escaping alone does not make a path with `#`, `?` or `%` safe in `href`. `markdown`: text only (empty gives empty); turns text into HTML, see below.
*   **The read tags.** Each tag runs once when reached and stores its result in the named variable; later `{{ }}` and `{% for %}` read variables only. The `<name>_error` variable is empty when the tag worked and otherwise one of: `not available` (the path is refused by `SafePath`, or missing), `too large`, `not text`, `unreadable`, `read budget used`. A failed `files` gives an empty list and a failed `section` empty text. A `limit` or a `path` variable of the wrong type is a `TemplateError.type`.
    *   `files`: the folder is relative to the opened folder, and `""` is the opened folder itself. Not recursive. Only notes (`.md`, `.markdown`, `.txt`) and folders are listed; HTML files, hidden entries, packages and other files are left out.
    *   `files` order: `sort "name"` (the default) is natural order (`localizedStandardCompare`), folders first as in the binder; `sort "modified"` orders by the full modification time, equal times by name; `reverse` flips whichever order. `limit N` (a whole number or a variable) keeps the first N entries after sorting: 0 gives an empty list and more than 100 is 100. Without `limit` the list is cut at 100 silently.
    *   `files` item fields: `name` (the file or folder name, with its extension), `path` (relative to the opened folder), `kind` (`"note"` or `"folder"`), `title` (for a note the first heading, read from its first 4 KB, else the name without extension; for a folder its name), `modified` (`yyyy-MM-dd` in the current time zone) and `size` (bytes; 0 for a folder).
    *   `section`: the text under the first heading whose title matches exactly (after trimming, and after removing closing `#` marks), from the line after the heading up to the next heading of the same or a higher level. Headings are ATX headings (`## Title`) as `Outline.headings` reads them; a missing heading gives empty text. A note over 64 KB is not read (`too large`): that is a limit of this version.
*   **`markdown`.** Parses with `Document(parsing: MarkdownLimits.clamp(text), options: [.disableSmartOpts])` and renders with `SafeHTML.render(_, preview: false)`, which escapes everything and blocks unsafe link schemes. It is the only way text becomes markup: `files` and `section` only ever return text and records, never markup. Its cost is charged by the length of its input. **Known limitation:** a relative picture or link inside text from a note resolves against the opened folder, not against the note's folder; a note in a subfolder with `![](pic.png)` shows a broken picture in an index. The manual says so.

**Values and escaping.** A value is one of: text, number, list, record (a dictionary of values), markup (the result of `markdown`) or empty. No other type exists in the engine, so nothing in a template can reach a Swift property or method: there is no lookup by reflection. `{{ }}` prints text with `&`, `<`, `>`, `"` and `'` escaped, prints markup as it is, prints numbers as digits, prints empty as nothing, and refuses to print a list or a record (an error naming the variable). Text from files and file names is raw until it is printed, and printing is the one place it is escaped. There is no "safe" or "raw" marker for authors. Attributes in a template must be written in quotes (`href="{{ f.path|urlencode }}"`): escaping cannot make an unquoted attribute safe, and the manual will say so.

**Why a render ends.**
*   Evaluation is a walk over a tree that the parser built; the only recursion is into child nodes, and nesting is capped at parse time.
*   The only repetition is `{% for %}` over a list value, and every list comes from `files` (at most 100 items). No construct creates a list or a number out of template data, so a loop cannot be made longer than the app's own list.
*   Every node visited and every loop pass calls one `charge()`, which counts a step, and every 1,024 steps it checks the clock and the cancel flag. Reaching the step budget, the clock or the cancel flag ends the render. A source call (a read or a listing) charges and checks as well, so a cancel is seen within 1,024 steps or at the next source call. `markdown` charges one step per 256 characters of input, and a read one step per 256 bytes.
*   The one thing a step count cannot interrupt is a single call into the operating system or into swift-markdown. A read is capped at 64 KB, so the input to `markdown` is at most 64 KB; `MarkdownLimits.clamp` bounds nesting and line length, and a new test in `TemplateLimitTests` runs `markdown` on a 64 KB hostile note. A read that blocks in the operating system, for example on a stalled network volume, cannot be interrupted. The clock fires from a separate timer, not from the blocked task: the timer sets the cancel flag and the render state `failed(timeout)`, and the preview shows the timeout error within the clock. The blocked task is kept as the window's one in-flight evaluation until it returns, and its late result is discarded; Render stays disabled and the banner says "Waiting for a blocked file read" until then, so blocked reads cannot pile up. Only that task is held up; the app is not.
*   A missed `charge()` would let a loop run to the end of its bounded list (at most 100 by 100 passes) and could not be cancelled until then; it is a long run, not a hang. A test runs every node type under a tiny budget.

**Where it runs.** On a background task (not the main thread), one in-flight evaluation per window. While it runs, the banner shows a spinner and a **Cancel** button and the preview keeps showing the plain file; a second Render cannot be started. Cancel, or changing the document, sets the cancel flag. After a cancel the state is `cancelled`: the preview shows the plain file and the banner offers Render again. A result that arrives for a document that is no longer open, or from a task whose state is already final, is dropped.

### The path check

`AgentTools.resolve` already makes a relative path safe: no leading `/` or `~`, no `..`, no hidden parts, the extension must be a note, symlinks resolved and the result must stay inside the folder. It is extracted into one shared function (`SafePath`) that the agent tools and the template tags both call, so there is one rule to test. For templates it also accepts a folder (for `files`) and refuses packages and non-regular files. Reads use the file on disk only; an unsaved buffer is not visible to a template.

**A deliberate hardening.** Today the hidden-part check looks at the path as written, so `visible.md` that links to `.secret/x.md` or `.mdedit/y.md` inside the folder passes. `SafePath` also refuses a result whose path below the resolved root has a component starting with ".". This changes the agent tools too (they could read such a file before); the plan 005 tests must pass unchanged, and item 3 adds the case.

### Limits

All limits are constants in one place (`TemplateLimits`) and each has a test that exceeds it by one. KB and MB are 1,024 and 1,048,576 bytes. The numbers are starting values; the performance tests in step 2 set them from measurements. **Success criterion:** a 100-note index with one `section` per note renders in under 200 ms on a flat 120-note test folder, and the worst-case template (two nested loops over 100 items with a full-size body) ends with a page or the limit error within the clock plus 500 ms (scheduling grace). A miss is a defect to fix in the engine or its step costs, not a reason to raise a limit.

| Limit | Starting value | When passed |
|---|---|---|
| Template size | 64 KB (bytes) | error page |
| Nodes in a template (text nodes included) | 2,000 | error page |
| `for` nesting depth | 2 | error page |
| Nesting depth of all blocks together | 10 | error page |
| Whole number | 9 digits | error page |
| Items in a `files` list | 100 | list cut |
| Bytes per `section` read | 64 KB | that read is empty, `too large` |
| Bytes read from the top of a note for `meta` | 16 KB | none (a prefix is enough) |
| Bytes read from disk in one render | 8 MB | later reads are empty, `read budget used` |
| First bytes read for a `title` | 4 KB | none (a prefix is enough) |
| Directory entries read in one render | 10,000 | error page |
| Steps in one render | 200,000 | error page |
| Output size | 2 MB | error page |
| Wall-clock time | 2 s | error page |


The parser checks the first five before anything runs. Everything else is counted in the evaluator. Passing a hard limit (the "error page" rows) ends the render and no partial page is shown. The exceptions keep an ordinary folder from failing the whole page: a `files` list is cut, and a read that cannot be done leaves that one result empty and sets its `_error` variable, so one large, unreadable or hostile note does not stop the page rendering. Details:

*   Bytes are charged for what is read from disk. A note is checked by size first, and a note over the per-read cap is not read at all. A listing and a file read are cached for the length of one render, so a `files` call in an inner loop does not scan the directory again; a cache hit costs the steps again but no bytes.
*   An index of 100 notes costs at most 400 KB for titles, and 100 sections of 64 KB cost 6.25 MB, together inside the 8 MB budget. Each such section costs 256 read steps and 256 `markdown` steps, so 100 of them cost about 51,000 of the 200,000 steps.
*   The output cap is checked on every append, after escaping, so memory for the page stays under the cap plus one append. Memory elsewhere is bounded by the 8 MB read budget, the 100-item lists and the size of `markdown` output.

### The first-Render warning

A file that is a template shows the banner. On **Render** the file is read once as one string and parsed; if parsing fails, the error page shows and nothing is asked. The very first time anyone presses Render in the app, a small sheet says: "A rendered page can read every note in this folder and show it on screen. It cannot change anything, and it makes no network request on its own. You are asked this once." with Render / Cancel. Cancel renders nothing and the sheet comes back next time. After Render, the answer is kept in the app's settings (`templateWarned`), not in any folder, and no later Render asks, whatever the file or folder.

This replaces the first design, which asked once per version of each file (a SHA-256 of the text, kept per folder). The author chose the single warning: the Render click is the consent, and the warning is for the first-time user. The cost is that an edited or received template renders on a click without a new warning; the containment layers below are what limit it.

### Delivery and containment

Three layers keep a rendered page from reaching another host on its own. Layers 1 and 2 stop resource loads; layer 3 stops tags that can open a connection, which are not resource loads. Each blocks on its own.

*   **Layer 1, header.** `PreviewPage.csp(loadRemote: false)` (not `headerCSP`) is sent as a response header: `default-src 'none'; script-src 'none'; img-src mdedit-file: data:; style-src 'unsafe-inline' mdedit-file:; font-src mdedit-file: data:; media-src mdedit-file:; form-action 'none'; base-uri 'none'`. Local pictures, styles (inline too), fonts and media load; frames, scripts and everything remote do not. `headerCSP` has `form-action 'none'`, `script-src`, `object-src` and `connect-src`, but no `default-src` and no `base-uri`, so it is not used for template pages. A header cannot be changed by the page, unlike a `<meta>` tag. `PreviewRequest.Source` gets a case for a rendered template; the request forces `loadRemote` off whatever `Preferences.loadRemoteImages` says.
*   **Layer 2, rule list.** A second content rule list, `PreviewRules.template`, used only for template pages, blocks every `http` and `https` request whatever its type (the rule omits `resource-type`, which matches every type). The existing list blocks only some resource types, so it is not enough here. `PreviewController.show` applies the template list for template pages in all cases, does not read `Preferences.loadRemoteImages` for them, and always waits for the list to be compiled before loading (today it skips that wait when remote loads are on, which would let a template page load before its list exists). **It fails closed:** `PreviewRules.whenReady` today marks itself ready even when compilation failed and the list is nil. For a template page, a nil list means the page is not loaded and an error page shows; a test simulates a compile failure. A test also checks that an ordinary `mdedit-file` page still loads under the list.
*   **Layer 3, output guard.** `dns-prefetch` and `preconnect` open a connection to a host named in the page, so a hostname built from note text (`href="//{{ text }}.example"` over a note whose text is letters, digits and dashes) would leak it, and HTML escaping does not stop those characters. Whether the header or the rule list stops a connection hint in this WebKit is not known, and the 127.0.0.1 tests cannot see a DNS lookup, so the app does not depend on either. After rendering, `TemplateOutputGuard` (item 16) reads the output as tags and fails the render with an error page that names the tag when it finds a tag outside a short allow-list. It rejects `<object>`, `<embed>`, `<iframe>`, `<frame>`, `<applet>` and `<base>`; a `ping` attribute on `<a>` or `<area>`; any `formaction` attribute; a `<meta>` with `http-equiv`; and every `<link>` except one whose `rel` is exactly `stylesheet` and whose `href` is relative. Details of "relative" and of how tags are read are in item 23. Text printed with `{{ }}` is escaped, and `markdown` output contains only `SafeHTML`'s own tags, so the scan sees the template author's tags plus those. The guard is a deny-list over tag names, so it is a defence in depth, not a proof.
*   **Hidden files and the page address.** The rendered page is held in memory and served at one fixed address at the root of the opened folder, `PreviewPage.templateAddress` (`mdedit-file://local<root>/.mdedit-template.html`). `PreviewFiles` checks this address before any file lookup, so the page always wins over a real file of that name, and the entry is cleared when the render is replaced, cancelled or the document changes. For template pages `PreviewFiles.allows` also refuses any request whose path below the opened folder has a component starting with "." (today it only tests the folder prefix, so hidden files such as `.mdedit/preview.css` are served). A page therefore cannot load a hidden file by `<img>` or `<link>`. A test puts a real file of the same name in the folder and another under `.mdedit`.
*   **Relative paths and links.** `PreviewRequest.noteFolder` is the opened folder for a template page. A path written in a template, `f.path` and relative pictures and styles all mean "relative to the opened folder", whatever folder the template file is in, and a click on `<a href="{{ f.path|urlencode }}">` resolves through `LinkPolicy` against the same folder.
*   **A click on a web or mail link asks first.** Forms, meta refresh and new windows are handled by `PreviewController` as for any page. `DetailView.openLink` hands every click on a rendered template page to `Workspace.openTemplateLink(_:)` (item 19), which runs `LinkPolicy.decide` with the opened folder as base. A result of `.openWeb` (`http`, `https` and `mailto`) does not go straight to the system: a sheet titled "Open this address?" shows the complete address in a scrolling view, with the query part (from the first `?`) on its own line, the text "This address may contain text from your notes" (for `mailto`: "This opens your mail program with this draft; the address and the text after `?` may contain text from your notes"), and **Open** / **Cancel**, with Cancel as the default button (Return) and Escape also cancelling. Only Open calls `NSWorkspace`. Links inside `markdown` output reach the same handler. Other results (notes, local files, reveal) follow `LinkPolicy` as for any page. The sheet is the only protection against a click: a person can still press Open on an address that carries note text, and the plan accepts that. `ConfirmPrompt` today cannot do this (its action button is the default and it has no scrolling view); item 12 extends it. Tests answer the sheet through a `templateConfirm` closure and observe the open through an `openAddress` closure, so a test can prove nothing else reaches `NSWorkspace` from a template page.
*   **Tests (items 16, 17 and 25).** The server-count tests load the string straight into the preview (`PreviewRequest` with the template source), bypassing the guard, so layers 1 and 2 are tested alone. A local server on `127.0.0.1` counts requests, and each vector is first run with the layers off as a positive control (the server must see it), then with them on (zero requests after a 1 second settle). The vectors are `<img>`, a remote `<link rel=stylesheet>`, CSS `url()` and `@import`, `<iframe>`, `<form action>` (submitted through `evaluateJavaScript` in the client content world, which works with page JavaScript off) and `<a ping>` (clicked the same way). `<meta http-equiv=refresh>`, `<base>`, `formaction`, `dns-prefetch`, `preconnect` and `prefetch` are asserted at the guard (the render fails). A one-time manual check with a hostname under the author's control, with the lookup seen at a resolver or with `nettop`, records whether WebKit sends a lookup for a connection hint when only layers 1 and 2 are on. It is a follow-up that the author owns after step 3, not a gate; the result cannot change the design (layer 3 stays) and goes in the "As built" section of this plan.
*   A failure (syntax, type, limit, timeout, unsafe output) shows a plain error page with the message and the template line where there is one. It never shows a partial page.

### When the Render button appears

An `.html` or `.htm` file whose text contains `{%` or `{{` gets a banner above the preview: "This page uses template tags." and **Render**. The file is shown as plain HTML until the person presses Render, whether or not it was approved before. Files with neither string show no banner. A page that merely contains `{{` for another system (Vue, Handlebars) gets the banner and nothing else changes; nothing renders without a click.

### Reloading

The rendered page depends on the template and on the files it read, and it is not rendered again by itself. A render starts only when the person presses Render, so a folder change, an autosave or a reopened file never starts one. If the template file changes on disk while a rendered page shows, the plain file reloads and the state returns to the banner with Render. The warning is shown only on the very first Render in the app; no later Render asks. Opening a file always starts at the banner, not at a rendered page. **Show source** returns to the banner state.

### Unchanged

These do not change: the binder's behaviour (its one-directory step moves into `BinderNode.entries`, item 7, and the binder tests pass unchanged), the editor, Markdown notes, the agent server's protocol, the build (no new target, no new dependency) and the app's five entitlements. What changes: the agent tools' path check moves into the shared `SafePath`, with the deliberate hardening above (a visible name linking to a hidden file is now refused; the plan 005 tests must still pass), and the audit gains a check on the engine's source (item 11).

## Alternatives Considered

### Chosen design: a Django-style subset, our own parser and evaluator, in the app

*   **Pros**: the grammar is closed and deny-by-default, so there is no list of names to keep up to date; every step is counted, so the run time is bounded without a second process; no dependency; the printing rule is ours, so escaping cannot be forgotten.
*   **Cons**: we own every parsing edge case, and the language is as complete as we write it (an estimate of 600 to 900 lines plus tests); a missed `charge()` would let a bounded loop run long, and a cancel is seen only inside `charge()`.
*   **Why chosen**: it is the only option here that gives loops and conditions, a fixed set of read-only tags, and a bound on run time that the code itself enforces. 

### Alternative A: an embedded script interpreter (JavaScriptCore with host functions)

Templates compile to a script that runs in a JavaScriptCore context with no globals except `listFiles`, `readLines` and `readSection`.

*   **Pros**: the full power of a programming language for filtering, sorting and layout. A bare JavaScriptCore context has no file, network or process access.
*   **Cons**: a template is code, so the safe surface is the whole host-function set plus a general language, which is harder to audit than a fixed grammar. JavaScriptCore's time-limit hook is not public API, so there is no supported way to stop a running script from inside the app (not checked against a spike).
*   **Reason for Rejection**: the audit and test surface of a general language is larger than that of a fixed grammar, and a script cannot be stopped from inside the app.

### Alternative B: HTML with a small set of directive tags

Plain HTML with elements such as `<md-list dir="notes">` and `<md-include src="a.md" lines="1-10">` that Swift expands.

*   **Pros**: still valid HTML, easy to read, and the smallest attack surface because there is no expression language.
*   **Cons**: needs an HTML parser. No fields, conditions or sorting, so a per-file layout forces new directives until it becomes a template language written in tag syntax.
*   **Reason for Rejection**: without loops and conditions it cannot lay out one block per note, which is the use case, and adding them turns it into a template language written in tag syntax.

### Alternative C: a Mustache-style language, hand-written or from a package

A logic-less language (`{{#section}}`) with sections but no loops over computed data, written in the repository or taken from a Mustache package such as GRMustache.swift.

*   **Pros**: the hand-written version has no dependency and only the syntax we allow. The package version has parsing and escaping already written and filters that take arguments.
*   **Cons**: standard Mustache has no function arguments, so `files "folder"` needs filters or a custom dialect. It has no `else` for a missing value beyond inverted sections, and no `for … empty`.
*   **Reason for Rejection**: the read tags take arguments, which Mustache cannot express without a custom dialect, and at that point the syntax is no closer to a known language than the chosen one.

### Alternative D: the Stencil package in the app, with a guard, shadowed built-ins and metered tags

Stencil runs in the app process. A guard reads its tokens and refuses unlisted names; our own extension, placed first, shadows its built-in tags and filters; our tags charge a budget.

*   **Pros**: less code to write, a Django-compatible syntax.
*   **Cons**: the spike (Appendix) found that Stencil's built-in tags and filters cannot be removed, only shadowed; that it never escapes output; that `for` accepts range expressions; that it reads Swift properties by reflection; and that work inside Stencil cannot be metered or interrupted (a nested template inside the caps ran 8 seconds). Each of these needs a rule outside Stencil, and the guard and the engine must agree.
*   **Reason for Rejection**: the list of things to fence in is longer than the grammar we need, and a parser that rejects everything outside a closed grammar needs no list of names kept in step with a general engine. The spike behind this is not in the repository; its numbers are in the Appendix.

### Alternative E: Stencil in a killable helper process

Stencil runs in a separate command-line program that the app starts and kills at the clock.

*   **Pros**: any render, including work inside Stencil, can be stopped by killing the process. The spike confirmed this works under the sandbox when the helper is signed with `app-sandbox` and `inherit`.
*   **Cons**: a second build target to sign and embed; the helper holds the app's file and network permissions (the spike showed it can write in the container and reach the network), so its safety still rests on an audit of its source; there is no kernel memory limit on macOS (`RLIMIT_AS` and `RLIMIT_DATA` fail) and the app cannot read the child's memory in the sandbox, so the helper needs its own watchdog thread. Plan 007 has removed `ShellRunner` and with it the audit's exception for starting programs, so a helper would need a new process-spawn exception, which the app does not have today.
*   **Reason for Rejection**: it needs a second target, a watchdog, signing and a new spawn exception, all to bound a run time that a metered engine bounds without a process.

### Alternative F: narrower read scope (own folder, or only named paths)

Reading only the template's own folder and below, or only paths written as fixed strings and shown at confirmation.

*   **Pros**: a received template reaches less. With fixed paths, the confirmation can list exactly what will be read.
*   **Cons**: a shared template in `templates/` could not read notes elsewhere. Fixed paths rule out previewing each file in a listing loop, the common case.
*   **Reason for Rejection**: both break the main use, an index over a folder that is not the template's own. The cost accepted: a received template can read every note, and the template-only header, rules and output scan keep it on screen, apart from a link the person chooses to open.

### Alternative G: only the author supplies templates

Templates from the author only, with no support for a template that arrives in a received folder or a download.

*   **Pros**: the narrowest source of templates; no hostile-template case to defend.
*   **Cons**: a received folder or a download can contain a template whether or not the app supports it, and the person can open it. (Agents cannot write `.html` through the Review tab: `AgentTools` accepts only `.md`, `.markdown` and `.txt`.)
*   **Reason for Rejection**: the defences are needed anyway for a file the person opens, so limiting the supplier only removes the use.

### Alternative H: render automatically, or ask on every open

Render when the file has tags, or only on an explicit action each time.

*   **Pros**: automatic needs no click; explicit-each-time never needs a stored answer.
*   **Cons**: automatic lets a downloaded file read the folder when it is merely viewed; explicit-each-time shows a sheet on every Render.
*   **Reason for Rejection**: the chosen mix, a Render click and a one-time warning on the first Render in the app, avoids both. See Decision 5.

### Alternative I: the web view's own JavaScript with a read-only file handler

The page runs scripts that call a handler returning folder listings and file parts.

*   **Pros**: no template language to write; full scripting for layout.
*   **Cons**: it turns JavaScript on in the preview, which plan 003 keeps off in every page so a hostile page cannot run code next to the notes, and a script can send what it read to any host the page can reach.
*   **Reason for Rejection**: it gives up the one rule (JavaScript off) that the containment layers rely on.

### Alternative J: an outside generator over the folder

A script or program outside the app writes the HTML.

*   **Pros**: any language; no engine in the app.
*   **Cons**: that is the situation today (Problem); it writes files, and the person must run it.
*   **Reason for Rejection**: it does not meet the goal of a page generated inside the preview without writing anything.

## Detailed Implementation Plan

Work in four steps. Each step is its own commit and ends with `make check` green. No step adds a target, a dependency or an entitlement, so `project.yml` is not touched (XcodeGen picks up new files under `Sources/MDEdit`). Items are numbered in the order they are built.

*   **Step 1, shared path check:** items 1 to 3.
*   **Step 2, engine:** items 4 to 11. The evaluator does not call the output guard yet, so step 2 tests do not expect it.
*   **Step 3, trust and delivery:** items 12 to 17. Nothing here needs `Workspace`: the sheet, the trust record, the page delivery and the output guard are tested on their own.
*   **Step 4, interface and docs:** items 18 to 25. The tests that need `Workspace` (render, the sheets, link clicks) are item 25.

### Target Files to Create/Modify

#### 1. `Sources/MDEdit/Model/SafePath.swift` (Create)

*   **Type / Scope**: Pure logic, shared by the agent tools and the templates.
*   **Proposed Changes**: Move the body of `AgentTools.resolve` here as `SafePath.resolve(_ path: String, in root: URL, kind: Kind) -> Result<URL, Failure>`. `Kind` is `.note` (the extension must be in `BinderNode.documentExtensions`; the result must be a regular file) or `.folder` (no extension check; the result must be a directory and not a package, which covers `.app` and `.bundle`; the root itself, addressed as `""`, is allowed). Rules common to both: no leading `/` or `~`, no `..`, no hidden part in the written path, symlinks resolved, and the result inside the resolved root, where "inside" is the resolved root itself or a path under it (the current prefix test alone would refuse the root). New: after resolving, no component of the path below the resolved root may start with "." (the hardening in "The path check"). `struct Failure: Error, Equatable { let code: String; let message: String }` with the codes and messages the agent tools return today: `outside_folder` ("Use a path relative to the folder." for an absolute or `~` path, "The path leaves the folder." for `..` or a link out) and `not_a_note` ("Hidden files are not available.", "Only .md, .markdown and .txt notes are available.", "No such note."); for `.folder` the last two become "No such folder." The new post-resolve rule uses "Hidden files are not available.". `SafePath.relative(_ url: URL, in root: URL) -> String?` returns the path below the resolved root, `""` for the root, nil outside it. `AgentTools.resolve` maps `Failure` to `PathError(code:message:)` one to one.

#### 2. `Sources/MDEdit/Agents/AgentTools.swift` (Modify)

*   **Type / Scope**: Existing agent tools.
*   **Proposed Changes**: `AgentTools.resolve` calls `SafePath.resolve(_, in:, kind: .note)` and maps the failure. `AgentTools.relative` keeps its optional signature and returns nil for the root by mapping `""` to nil. Remove the duplicated body. `Proposal.propose` also calls `AgentTools.resolve`, so the wrapper stays. The plan 005 tests (`AgentToolsTests`, `ProposalTests`, `ProposalSafetyTests`, `AgentProtocolTests`) must pass unchanged.

#### 3. `Tests/MDEditTests/Safety/SafePathTests.swift` (Create)

*   **Type / Scope**: Unit tests.
*   **Proposed Changes**: Every rule of item 1 directly: traversal, absolute and `~` paths, hidden parts, a symlink out of the folder, a symlink inside, **a visible name that links to a hidden file or folder inside the folder (refused, with the message above)**, non-note extensions (HTML included), packages, non-regular files, the root as `""` for `.folder` (and refused for `.note`), the root passing the inside test, and the codes and messages equal to what `AgentTools` returned before the change.

#### 4. `Sources/MDEdit/Templates/TemplateLimits.swift` (Create)

*   **Type / Scope**: Constants.
*   **Proposed Changes**: `struct TemplateLimits` with a `static let standard` holding the values of the Limits table (template bytes, nodes, nesting, digits, list length, bytes per read, bytes per render, title bytes, entries per render, steps, output bytes, clock seconds). It is passed to the parser, the evaluator and the sources, so a test builds a copy with one value changed and can exceed each limit by one.

#### 5. `Sources/MDEdit/Templates/TemplateValue.swift` (Create)

*   **Type / Scope**: Types.
*   **Proposed Changes**: `enum Value: Equatable` (`text(String)`, `number(Int)`, `list([Value])`, `record([String: Value])`, `markup(String)`, `empty`) and the printing rule. `enum TemplateError: Error, Equatable` with the cases `syntax`, `type`, `limit`, `timeout`, `cancelled` and `unsafe(tag:)`, each with a message and an optional template line (`unsafe` carries the line in the rendered output). `final class CancelFlag` (a lock-guarded Bool with `cancel()` and `isCancelled`). No other type can enter the engine.

#### 6. `Sources/MDEdit/Templates/TemplateParser.swift` (Create)

*   **Type / Scope**: Tokenizer, grammar check and tree.
*   **Proposed Changes**: `TemplateParser.parse(_ text: String, limits: TemplateLimits) -> Result<[Node], TemplateError>`. `indirect enum Node` has the cases `text`, `print` (an operand and its filters), `forLoop` (variable, source name, body, empty body), `ifElse` (condition, body, else body), `files` (folder operand, sort, reverse, limit, name) and `section` (path, heading, name), each with its template line; comments are dropped by the tokenizer. It checks the size, node, nesting and digit limits, accepts exactly the grammar in "The template language" and rejects everything else with the line number. A recursive-descent parser with an explicit depth counter, so deeply nested input fails at the limit and cannot overflow the stack.

#### 7. `Sources/MDEdit/Model/BinderNode.swift` (Modify) and `Tests/MDEditTests/BinderTests.swift` (Modify)

*   **Type / Scope**: The one-directory listing the binder and `files` share.
*   **Proposed Changes**: Add `static func entries(of url: URL, fileManager: FileManager = .default) -> (nodes: [BinderNode], rawCount: Int)`: one level only, skipping hidden entries, packages and symlinks to folders, keeping symlinks to files, folders (unexpanded, no children) first and then files, each in natural order; `rawCount` is the number of entries the directory returned before any were skipped, so a cap can count them. `scan` calls `entries` and recurses into the folder nodes; its result does not change. Tests: `entries` lists one level, `rawCount` counts hidden entries, a symlink to a folder is skipped, and the existing scan tests pass unchanged.

#### 8. `Sources/MDEdit/Templates/TemplateSources.swift` (Create)

*   **Type / Scope**: The only code in `Templates/` that touches the disk during a render (with `SafePath`). Read-only.
*   **Proposed Changes**: `protocol TemplateSource` with `meta(_ path: String, budget: Budget) throws -> (meta: Value, error: String)`, and `list(_ folder: String, sort: FilesSort, reverse: Bool, limit: Int?, budget: Budget) throws -> (items: [Value], error: String)` and `section(_ path: String, _ heading: String, budget: Budget) throws -> (text: String, error: String)`, throwing only the hard errors (cancel, the entry limit). `TemplateSources` is the disk implementation; a test supplies a stub (for example one that sleeps). `list` uses `BinderNode.entries(of:)` for one level and counts `rawCount` against the 10,000-entry limit; keeps notes and folders only; passes each entry through `SafePath.resolve` with kind `.note` or `.folder` and leaves out one that fails (so a symlink to a note outside the folder shows no `title`, `size` or `modified`); sorts and limits as in "The read tags". `title` reads the first 4 KB and reuses `AgentTools.cut(_:bytes:)` to end on a whole character, then takes the first heading from `Outline.headings(in:)`; failure falls back to the file name. `modified` is `yyyy-MM-dd` in the current time zone and sorting uses the full date. `section` resolves the path, checks the size before reading, charges the budget, and returns the text with `Outline.headings` (closing `#` marks removed before comparing). A read that cannot be done returns empty with the reason from the table in "The read tags" (`not available`, `too large`, `not text`, `unreadable`, `read budget used`). Listings and reads are cached per render; a hit charges steps but no bytes. Costs: one step per entry listed, one per 256 bytes read. No write, delete, move, process or network API appears; the audit enforces the listed names (item 11).

#### 9. `Sources/MDEdit/Templates/TemplateEvaluator.swift` (Create)

*   **Type / Scope**: Evaluator and entry point.
*   **Proposed Changes**: `TemplateEvaluator.render(text: String, root: URL, cancel: CancelFlag, limits: TemplateLimits = .standard, source: TemplateSource? = nil) async -> Result<String, TemplateError>` (a nil source means `TemplateSources` for `root`). It parses, then walks the tree on a background task with a `Budget` class (steps, deadline, output bytes, the cancel flag) whose `charge()` is called for every node and loop pass and checks the clock and the cancel flag every 1,024 steps. Implements printing and escaping, the conditions, the filters (`markdown` charged by input length: one step per 256 characters) and the loop. The output buffer refuses an append that would pass the cap. Runtime type errors are `TemplateError.type`. The output guard is called last in item 16.

#### 10. Engine tests (Create)

*   **Type / Scope**: Test classes: `Tests/MDEditTests/Security/TemplateSecurityTests.swift`, `Tests/MDEditTests/Safety/TemplateLimitTests.swift`, `Tests/MDEditTests/Safety/TemplateFuzzTests.swift`, `Tests/MDEditTests/Features/TemplateTests.swift`, `Tests/MDEditTests/Performance/TemplatePerformanceTests.swift`. Also `Tests/MDEditTests/Support/TestSupport.swift` (Modify): add an async variant of `within`, since `within` takes a synchronous closure and `render` is async.
*   **Proposed Changes**:
    *   *Security*: a corpus of hostile templates; each must fail with a syntax or type error, give an empty list or empty text with `_error` set to `not available`, or print only escaped text: paths with `..`, absolute paths, `~`, a symlink out of the folder, a visible name that links to a hidden file, hidden files and `.mdedit`, package folders; every Django tag and filter outside the grammar (`include`, `extends`, `block`, `now`, `filter`, `ifnot`, `break`, `1...n` ranges, method calls, `|safe`, `|lower`); note text containing `<script>`, `<img src="https://…">`, `javascript:` links and `{% %}` markers (printed escaped or inert); the `markdown` filter on hostile Markdown. A SHA-256 of every file and the folder listing before and after the whole corpus must be identical, which is the "cannot harm your files" test.
    *   *Limits*: one test per row of the Limits table that exceeds it by one, using a `TemplateLimits` copy, expecting the stated outcome (error page, cut list, or an empty read with its `_error`); the step budget ends a template of maximum size under a tiny budget; the clock ends a template under a tiny clock; a stub source that sleeps is cut at the clock; cancelling a running render returns `cancelled`; output past the cap errors; **every node type is run under a tiny budget and ends with the limit error (this shows the paths the tests reach call `charge()`, not that none is missed)**; `markdown` over a 64 KB hostile note ends within the clock.
    *   *Fuzz*: random soup of template tokens, deep nesting and long runs, in the style of `HostileInputTests`: every input returns a page or an error within the clock, never a crash.
    *   *Features*: `files` lists in a stable order and not recursively; `sort` by name and by modified, `reverse`, `limit` (also from a variable, over 100, zero), 101 notes list the first 100; a symlinked child pointing outside the folder is left out; HTML files are not listed; `section` (to the next same-or-higher heading, last section, missing heading, duplicate heading, closing `#` marks, a note over 64 KB gives `too large`); `for` with `empty`, over an unset variable and over a non-list; `if/else` with `==` and `!=` and a single operand; every filter, and a wrong-typed operand is a `type` error; printing a list or record is an error; an unset variable is empty; escaping in text and attributes; `urlencode` of a name with `#`, `?`, `%` and spaces; the worked example renders as expected.
    *   *Performance*: the success criterion in Limits, on a flat 120-note folder: the worked example over 100 notes renders in under 200 ms, and the worst-case template ends with a page or the limit error within the clock plus 500 ms. The bounds follow `TESTING.md`'s loose budgets; if a bound is missed, the engine or its step costs are fixed.

#### 11. `scripts/audit-templates.sh` and `scripts/audit-templates-selftest.sh` (Create), `scripts/audit.sh` (Modify)

*   **Type / Scope**: Static policy checks, run by `make audit`. `audit-templates.sh [dir]` (default `Sources/MDEdit`) holds the template checks; `audit-templates-selftest.sh` copies `Templates/` and `SafePath.swift` to a temporary folder, plants each violation and expects `audit-templates.sh` to fail; `audit.sh` calls both and fails if either fails. Both are committed executable. The self-test is a shell script, not a unit test, because the sandboxed test host is not known to be able to read the repository or start a process.
*   **Proposed Changes**: Two rules, in addition to the existing rule that forbids starting programs in all of `Sources`. (1) In every file under `Templates/` and in `SafePath.swift`, fail on names of write, delete, move, copy, link, attribute-change, coordination, stream, low-level file, process, network and workspace APIs (the script holds the exact list and the matcher; names that could sit inside another word use the `(^|[^.A-Za-z_])` guard the existing `system(` rule uses). (2) File access is allowed only in `Templates/TemplateSources.swift` and `SafePath.swift`: any other file under `Templates/` that mentions `FileManager`, `Data(contentsOf`, `String(contentsOf`, `FileHandle` or `contentsOfDirectory` fails. The rules catch the listed names; they are not a proof that the engine cannot write, and the plan does not claim that. The self-test plants a `removeItem` in `TemplateParser.swift`, a `FileManager` mention in `TemplateValue.swift` and a `removeItem` in `TemplateSources.swift`, and expects each to fail. The `openAddress` line in `audit.sh` is added with item 18.

#### 12. `Sources/MDEdit/Model/ConfirmPrompt.swift` (Modify)

*   **Type / Scope**: The shared confirmation alert from plan 007.
*   **Proposed Changes**: Add `static func makeAlert(_ title: String, _ detail: String, _ button: String, scrollingText: String? = nil, cancelIsDefault: Bool = false) -> NSAlert`, and change `ask` to `static func ask(_ title: String, _ detail: String, _ button: String, scrollingText: String? = nil, cancelIsDefault: Bool = false) -> Bool`, which runs `makeAlert`. `scrollingText` becomes an accessory view: a read-only, selectable, monospaced text view in a scroll view (about 480 by 220 points). With `cancelIsDefault`, the Cancel button takes the Return key and the action button has no key equivalent; Escape still cancels, as `NSAlert` does for a button titled "Cancel". The existing three-argument calls behave as before.
*   **Tests** (`Tests/MDEditTests/Features/ConfirmPromptTests.swift`, Create): the default call has the action button first and as default; with `cancelIsDefault` the Cancel button has the Return key equivalent and the action button none; with `scrollingText` the accessory view holds the full text (a 64 KB string included) and is not editable.

#### 13. `Sources/MDEdit/Templates/TemplateTrust.swift` (Create)

*   **Type / Scope**: Approval records.
*   **Proposed Changes**: `TemplateTrust.hasBeenWarned(defaults:) -> Bool` and `markWarned(defaults:)`, one Bool under `templateWarned` in the app's settings. (The first design kept a hash per file and folder; see "The first-Render warning".)
*   **Tests** (`Tests/MDEditTests/Features/TemplateTrustTests.swift`, Create): the warning is shown until it has been answered; the answer is kept in settings and nothing is written into a folder.

#### 14. `Sources/MDEdit/Preview/PreviewWebView.swift` (Modify) and `Tests/MDEditTests/Features/PreviewTests.swift` (Modify)

*   **Type / Scope**: Preview request, scheme handler, controller, rule lists.
*   **Proposed Changes**:
    *   `PreviewRequest.Source` gets `.template(rendered: String)`; update every exhaustive switch (`identity`, `key`, `load`). The identity is `"template:" + root path`; the key includes the rendered text.
    *   `PreviewFiles` holds `templatePage: String?` and `refuseHidden: Bool`. In `webView(_:start:)` the address `PreviewPage.templateAddress(root:)` is answered from `templatePage` (`Content-Type: text/html; charset=utf-8`, header `csp(loadRemote: false)`) before any file lookup. With `refuseHidden`, `allows` also refuses a path whose part below the opened folder has a component starting with ".". The controller sets and clears both with the source.
    *   `PreviewRules` becomes an instance with `init(identifier:json:)`; the current list is `PreviewRules.shared` (identifier `in.ranjeev.mdedit.noremote`, with its JSON as `PreviewRules.noRemoteJSON`, which `PreviewTests` uses), and `PreviewRules.template` has the identifier `in.ranjeev.mdedit.template` and the JSON `[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]`. `apply(rules:)` takes the list to use (or none) instead of a Bool.
    *   In `PreviewController.show`, for a template source: use `PreviewRules.template`, ignore `loadRemote` (`PreviewFiles.loadRemote` is false), always go through `whenReady` before loading (the `if r.options.loadRemote { go() }` shortcut must not apply), and fail closed: if the list is nil after the wait, do not load and show `errorPage`.
    *   `PreviewTests.swift` is updated for the renamed static JSON and the instance `shared`.

#### 15. `Sources/MDEdit/Preview/PreviewPage.swift` (Modify)

*   **Type / Scope**: Page building.
*   **Proposed Changes**: Add `static func errorPage(title: String, message: String, line: Int?) -> String`, a small page in the same style, with every dynamic string HTML-escaped; the `line` is omitted when nil. Add `static func templateAddress(root: URL) -> URL`, the fixed `mdedit-file://local<root>/.mdedit-template.html`. The existing CSP functions are unchanged. `DetailView` (item 21) maps each `TemplateError` case to a title.

#### 16. `Sources/MDEdit/Templates/TemplateOutputGuard.swift` (Create) and `TemplateEvaluator.swift` (Modify)

*   **Type / Scope**: Pure logic, called by the evaluator entry point after the output is complete.
*   **Proposed Changes**: `TemplateOutputGuard.check(_ html: String) -> TemplateError?` implements layer 3. It reads the output as tags: `<` followed by a name, then attributes up to the closing `>`, where `/` and whitespace separate attributes, quotes may hold a `>`, and a tag name is the letters up to whitespace, `/` or `>` (so `<a` does not match `<abbr`). Comments are skipped, and the contents of `<script>`, `<style>`, `<textarea>` and `<title>` are not read as tags. Attribute values are decoded for numeric character references (`&#47;`, `&#x2f;`) and the named ones `&amp; &lt; &gt; &quot; &apos; &sol; &bsol; &colon;` before checking; any other named reference in a `rel` or `href` fails the tag. It returns `.unsafe(tag:)` with the line in the rendered output for: `<object>`, `<embed>`, `<iframe>`, `<frame>`, `<applet>`, `<base>`; `ping` on `<a>` or `<area>`; any `formaction` attribute; `<meta>` with `http-equiv` (a `<meta charset>` or `name` passes); and every `<link>` except one whose `rel` tokens are exactly `stylesheet` and whose `href` is relative. "Relative" means, after decoding and removing whitespace and control characters, no scheme (no ":" before the first "/", "?" or "#") and not starting with "/", "\" or "//". A `<link>` with no `rel`, or an `href` that cannot be decoded, fails. The evaluator entry point (item 9) calls the guard after the output cap check; step 2 tests do not expect it. The file is under `Templates/` and so under the audit rules.
*   **Tests** (`Tests/MDEditTests/Security/TemplateOutputGuardTests.swift`, Create): `dns-prefetch`, `preconnect`, `prefetch`, `preload`, `modulepreload`, `//host` and `https://host` hrefs, `<meta http-equiv>`, `<base>`, `<object>`, `<embed>`, `<iframe>`, `<a ping>` and `<area ping>`, `formaction`, each with odd case, line breaks inside the tag, single quotes, no quotes, `<link/rel=...>`, entity-encoded `rel` and `href` (`&#100;ns-prefetch`, `&#47;&#47;host`), a leading tab, `\\host` and `/\host`, `>` inside a quoted value, multi-token `rel` (`stylesheet preload`), no `rel`; a hostname built from note text (`href="//{{ text }}.example"` over a note whose text is `abc-def`) fails the render; a hint inside a comment or in `<style>` text passes; a relative stylesheet link, `<meta charset>`, `<abbr>` and an ordinary `<a href>` pass; note text containing `<link rel=preconnect href=//x>` is printed escaped and passes.

#### 17. `Tests/MDEditTests/Features/TemplatePreviewTests.swift` (Create)

*   **Type / Scope**: Preview integration tests, with a real `PreviewController`. Also creates `Tests/MDEditTests/Support/LocalHTTPServer.swift` (a small server on `127.0.0.1` and a random port, built on `NWListener` in the test target, which the audit does not scan; it answers 200 and exposes `requestCount`; `Support/RawHTTPClient.swift` is a client and does not overlap) and `Tests/MDEditTests/Support/PreviewTestHelpers.swift` (the `wait`, `js`, `controller` and `request` helpers that `PreviewTests` has as private functions, moved so both classes use them).
*   **Proposed Changes**: A rendered page is served with `PreviewPage.csp(loadRemote: false)` as its header, at `templateAddress`, also when the template file is in a subfolder; a real file with the same name in the folder does not shadow it, and a file under `.mdedit` cannot be loaded by `<img>` or `<link>` from the page while it can still be loaded by an ordinary HTML page; the template rule list is applied even when `Preferences.loadRemoteImages` is true; with `loadRemote` true and a fresh `PreviewRules.template` not yet compiled, the page does not load until the list is ready and its first request never reaches the server; a compile failure (a list with invalid JSON) shows `errorPage` and does not load the page; an ordinary `mdedit-file` page loads under the list; each resource vector under "Delivery and containment", with its positive control; a relative image inside the folder loads (also from a template in a subfolder) and one outside does not; `errorPage` escapes `<script>` in the title, the message and a tag name.

#### 18. `Sources/MDEdit/Model/Workspace.swift` (Modify)

*   **Type / Scope**: Window model.
*   **Proposed Changes**: Add `@Published var templateState: TemplateState` with the cases `.notTemplate`, `.needsRender`, `.rendering`, `.rendered(String)`, `.cancelled` and `.failed(TemplateError)`, and `@Published var renderBusy: Bool` (true while the window's task is in flight, including after a timeout, so the banner can say it is waiting for a blocked read). Add the in-flight task with its `CancelFlag`; `var templateConfirm: (_ title: String, _ detail: String, _ button: String, _ scrollingText: String?, _ cancelIsDefault: Bool) -> Bool = { ConfirmPrompt.ask($0, $1, $2, scrollingText: $3, cancelIsDefault: $4) }`; `var openExternal: (URL) -> Void = { NSWorkspace.shared.open($0) }`; and `var templateSource: TemplateSource?` and `var templateLimits = TemplateLimits.standard`, so tests can use a stub and a tiny clock. `resetTemplateState()` is called from `select(_:recording:)` and `open(_:restoring:)` after the document is loaded, and when `document.checkDisk()` reloads a changed file. State changes:

    | From | Event | To |
    |---|---|---|
    | any | a document is opened, or the open file reloads from disk | `.needsRender` for an HTML file with `{%` or `{{`, else `.notTemplate`; a running task is cancelled |
    | `.needsRender`, `.cancelled`, `.failed` | Render pressed, `renderBusy` false, the file parses | `.rendering` (after the one-time warning, on the first Render in the app) |
    | `.needsRender` | the one-time warning is declined | `.needsRender` |
    | `.rendering` | the task returns a page | `.rendered(html)` |
    | `.rendering` | the task returns an error | `.failed(error)` |
    | `.rendering` | Cancel pressed | `.cancelled` |
    | `.rendering` | the clock timer fires | `.failed(.timeout)`; `renderBusy` stays true until the task returns |
    | `.rendered`, `.failed` | Show source pressed | `.needsRender` |
    | any | a result arrives for another document, or the state is already final | the result is dropped |

#### 19. `Sources/MDEdit/Model/Workspace+Templates.swift` (Create)

*   **Type / Scope**: Template actions on the window model.
*   **Proposed Changes**: `isTemplateCandidate` (the open file is `.html` or `.htm` and its text contains `{%` or `{{`). `render()`: refuse when `renderBusy`; read the file once as UTF-8 (a failure is `.failed`); parse (with the meta block set aside); if the app has not warned yet, ask through `templateConfirm` with the sentence from "The first-Render warning" and no scrolling text, and on yes `TemplateTrust.markWarned`; then set `.rendering`, start the evaluator on a background task, and start the clock timer. `cancelRender()` sets the flag and the state `.cancelled`. `openTemplateLink(_ url: URL)` runs `LinkPolicy.decide` with the opened folder as base and, for `.openWeb`, asks through `templateConfirm` ("Open this address?", the complete address as the scrolling text with the part from the first `?` on its own line, `cancelIsDefault: true`) and calls `openAddress` only on Open; other results are handled as `DetailView.openLink` handles them now (it delegates here). There is no automatic re-render.

#### 20. `Sources/MDEdit/UI/TemplateBanner.swift` (Create)

*   **Type / Scope**: SwiftUI view.
*   **Proposed Changes**: A bar above the preview built like the changed-on-disk bar (`DetailView.bar(_:actions:)`, extracted to a shared view if it cannot take a spinner as it is), with `Palette.binderBg`, `Palette.binderBorder`, `Palette.strongText` and `Palette.segmentText`. `.needsRender`: "This page uses template tags." with **Render**. `.rendering`: a spinner and **Cancel**; while `renderBusy` stays true after a timeout, "Waiting for a blocked file read" with Render disabled. `.cancelled`: "Render cancelled" with **Render**. `.rendered`: "Rendered from template" with **Show source**. `.failed`: the message and **Show source**.

#### 21. `Sources/MDEdit/UI/DetailView.swift` (Modify)

*   **Type / Scope**: Preview area.
*   **Proposed Changes**: `openLink` calls `ws.openTemplateLink(url)` when `templateState` is `.rendered`, and is unchanged otherwise. Show `TemplateBanner` above `PreviewWebView` when `templateState` is not `.notTemplate`. In `previewRequest`: `.rendered(html)` gives `.template(rendered: html)` with `noteFolder` set to the opened folder; `.failed(error)` gives `.template(rendered: PreviewPage.errorPage(title:message:line:))`, with a title per error case; every other state gives today's request (so a cancelled render shows the plain file).

#### 22. `Sources/MDEdit/Resources/Manual.md` (Modify) and `Tests/MDEditTests/Features/HelpTests.swift` (Modify)

*   **Type / Scope**: In-app manual.
*   **Proposed Changes**: Under `## HTML files`, add a `### Templates` subsection before `## Printing and exporting`: the grammar and the worked example; that attributes must be quoted; that paths in a template are relative to the opened folder, not to the template file; that the Render confirmation shows the whole template and asks again after an edit; that a template can read every note in the folder but cannot change anything, and that the design blocks network requests on its own (even with remote pictures on); that a click on a web or mail link asks first with the full address; that a page with a tag able to open a connection (anything but a relative stylesheet link among `<link>`, `<base>`, `<iframe>`, `<object>`, `<embed>`, `<meta http-equiv>`, `ping`, `formaction`) is refused; that pictures and links inside text from a note resolve against the opened folder; the limits (notes over 64 KB are not read by `section`); that templates read notes as saved on disk, not unsaved edits; and that hidden files are never read. The sentence "nothing outside the open folder can be read, and scripts never run" stays true and is not changed. `HelpTests` gets one assertion that `HelpManual.source` contains "Templates"; its other checks need no change because the new heading is a subsection of an existing page.

#### 23. `README.md` and `TESTING.md` (Modify)

*   **Type / Scope**: Project documentation.
*   **Proposed Changes**: README.md: after the `Preview/` line of the source tree add `Templates/` ("Template engine for HTML files: parser, evaluator, read-only sources, output guard") and mention `Model/SafePath.swift`; after the "HTML files" row of the features table add a row for HTML templates (explicit Render, whole-folder read, read-only, no network on its own, a click asks first); the one-dependency sentence stays true; rule 2 of the rules list ("Treat every note, file name, link and dropped file as hostile") gains "template text and the files a template reads". TESTING.md: extend the folder table: `Security` gains "hostile templates, the output guard", `Safety` gains "template limits and fuzz, `SafePath`", `Features` gains "template tags, trust, preview delivery", `Performance` gains "template render times"; rule 1 ("Treat every note, file name, link and dropped file as hostile") gains the same words; add the template audit rules to the line about `make audit`. Quote the lines as they stand when editing, since line numbers move.

#### 24. `Tests/MDEditTests/Features/TemplateBannerTests.swift` (Create)

*   **Type / Scope**: Hosted view test. `SnapshotTests.render` returns nothing and cannot set `templateState`, so the banner gets its own test in the style of `ReviewPanelTests`.
*   **Proposed Changes**: Build a workspace with `makeWorkspace(open:)`, set `templateState` to each of `.needsRender`, `.rendering` (also with `renderBusy` true), `.cancelled`, `.rendered` and `.failed(...)`, put `TemplateBanner` in an `NSHostingView` and draw it with `bitmapImageRepForCachingDisplay` as `SnapshotTests` does. For each state assert the bar is taller than zero, a pixel inside it equals `Palette.binderBg` in light and in dark, and the expected button titles are in the accessibility tree.

#### 25. `Tests/MDEditTests/Features/TemplateRenderTests.swift` (Create) and `scripts/audit.sh` (Modify)

*   **Type / Scope**: Tests with a real `Workspace`, in step 4 because they need items 18 to 21. `audit.sh` lists the `openAddress` default closure as the vetted new call to `NSWorkspace.shared.open(` by extending the `grep -v` filter on the `REVIEW:` line.
*   **Proposed Changes**:
    *   *Warning*: a syntax error asks nothing; the first Render in the app asks once, with the sentence and no template text; Render, an edit, another page or another folder do not ask again; declining renders nothing, writes nothing and asks again next time.
    *   *Lifecycle*: while a render runs a second Render does not start; Cancel gives `.cancelled` and the preview shows the plain file; changing the document drops the running render and its late result; with a stub source that sleeps and a tiny clock, the state is `.failed(.timeout)` on time, `renderBusy` stays true and Render stays disabled until the stub returns, then Render works again; saving or editing other files never starts a render; Show source returns to `.needsRender`.
    *   *Links*, with the template in a subfolder: a link to `f.path` selects the right note; `http`, `https` and `mailto` (including `mailto:x?body=` with note text) each ask first with the full address, Cancel is the default, Cancel opens nothing, Open calls `openAddress` once with that URL; no other scheme reaches `openAddress`; a link inside `markdown` output behaves the same; a `file:` link and a link outside the folder are ignored as `LinkPolicy` says.
    *   *Guard*: a render that fails the output guard shows the error page.

### Verification Plan

*   **Compilation/Build**: `make app`.
*   **Unit Tests**: `scripts/test.sh` with the classes of the step while working: step 1 `SafePathTests AgentToolsTests ProposalTests ProposalSafetyTests AgentProtocolTests`; step 2 adds `BinderTests TemplateSecurityTests TemplateLimitTests TemplateFuzzTests TemplateTests TemplatePerformanceTests`; step 3 adds `ConfirmPromptTests TemplateTrustTests TemplateOutputGuardTests TemplatePreviewTests PreviewTests`; step 4 adds `TemplateBannerTests TemplateRenderTests HelpTests ProjectPolicyTests`. `make test` for the whole suite.
*   **Static Analysis & Linting**: `make audit` passes with the new Templates rules, its self-test and the same five entitlements.
*   **Test Coverage Requirement**: every limit has a test that exceeds it; every file under `Sources/MDEdit/Templates/` has line coverage from the template test classes (`make coverage`, read by hand because it prints only the top of the report).
*   **E2E/Integration**: after step 4, `make check`, then by hand in the built app: open a folder with a template that lists notes and reads a section; press Render and read the one-time warning; edit the template and see the banner come back (Render then needs no warning); add `<img src="https://example.com/x.png">` to the template with remote pictures turned on and confirm nothing loads (the local-server test is the real check); click a web link and a mail link and read the sheets; confirm a SHA-256 listing of the folder before and after is unchanged.
*   **Follow-up owned by the author, not a gate**: with a hostname under their control, put `<link rel="dns-prefetch" href="//name.example">` in a page loaded with layers 1 and 2 only and watch for a lookup (resolver log or `nettop`), then write the result in the "As built" section of this plan.

--------------------------------------------------------------------------------

## Safety Rules

These are not choices; every part of the design is judged against them.

1. The template code can only read. The grammar has no write, delete, run or network construct, and the audit checks the engine's source for the names of such APIs (a tripwire, not a proof).
2. Every path goes through `SafePath`, the same check as the agent tools: inside the opened folder, symlinks resolved first, hidden files (also through a link) and non-note extensions refused. The page's own pictures and styles cannot read hidden files either.
3. Hard limits: the "error page" rows of the Limits table, and the clock and the cancel flag. A render that reaches one stops with an error; a `files` list is cut to 100 entries and a read that cannot be done leaves that one result empty (see Limits).
4. Output is shown only in the existing locked-down web view. It is never saved.
5. Text read from files is escaped when it is printed. The only way text becomes markup is the `markdown` filter, which uses `SafeHTML`. There is no raw or safe marker.
6. A rendered template page makes no network request on its own, even when "Remote pictures and styles" is on in Settings (the no-network goal). A template can read your notes, and an `<img src="https://host/?q=…">`, a CSS `url()`, an `<iframe>`, a `<link rel=prefetch>` or an `<a ping>` would send what it read to that host. Template pages therefore always get the template header, the rule list and the output guard described in "Delivery and containment". A click on a web or mail link is the one request a person starts, and it asks first with the full address.

## Risks & Mitigations

| Risk | Impact | Mitigation | Residual |
|---|---|---|---|
| A connection hint (`dns-prefetch`, `preconnect`) leaks text through a hostname | Note text sent to another host with no click | Layer 3: the output guard fails the render on any tag outside a short allow-list; tested at the guard; the WebKit behaviour is recorded by a follow-up check | The guard is a deny-list over tag names |
| A click on a web or mail link carries note text | Note text sent when the person presses Open | A sheet with the full address, Cancel as the default | Accepted: a person can press Open |
| Approval lets a received template read every note, and the person approves without reading (consent fatigue) | Note content shown on screen and in the next web or mail sheet | The sheet shows the whole template and says it can read every note; reads stay on screen; no network request on its own | Accepted (Alternative F) |
| A read blocks in the operating system | One blocked task, a timeout error | Timer-driven timeout sets the cancel flag; one in-flight evaluation per window; Render disabled until it returns; the late result is discarded | The task stays until the read returns |
| A slow template under the limits | A 2 s wait | Step budget, clock, Cancel button | Up to 2 s per Render |
| A received or edited template renders without a new warning | A template renders on a click | The Render click is the consent; the first-ever Render warns once; the containment layers limit what a template can do | Accepted: the author chose one warning (Decision 5) |
| Extracting `SafePath` changes the agent tools' behaviour | Plan 005 tests fail or paths become allowed | The move keeps codes and messages; the one change is the hidden-target refusal, stated as a hardening; the plan 005 tests must pass unchanged | A visible name linking to a hidden file is now refused for agents too |
| A hidden file in the folder is loaded by the page's own pictures or styles | Hidden content shown | `allows` refuses hidden parts for template pages, tested | None known |
| A missed `charge()` lets a loop run to the end of its bounded list | A long run, not a hang; it cannot be cancelled until it returns | A test runs every node type under a tiny budget; fuzz tests | The app stays responsive; the task runs until it returns; Render stays disabled |
| Pictures and links inside text from a note resolve against the opened folder | A broken picture or link in an index | Documented in the manual | Accepted for this version |

## Decisions

| # | Question | Decision | Cost accepted |
|---|---|---|---|
| 1 | Kind of template system | A Django-style subset with loops and app-provided read-only tags | More surface than a logic-less language; the closed grammar and the limits carry the safety |
| 2 | Who implements the engine | Our own parser and evaluator in this repository, no new dependency (reversed on 2026-11-06 from the Stencil package, after the spike) | We own every parsing edge case, and the language is only as complete as we write it (an estimate of 600 to 900 lines plus tests) |
| 3 | Run-time limit | A step budget, a 2 s clock and a cancel flag charged by the evaluator itself; the render runs on a background task in the app; a timer reports a blocked read | A missed `charge()` gives a long, bounded run that cannot be cancelled; a read blocked in the operating system cannot be interrupted |
| 4 | Who supplies templates | Any template file | A received template is treated as hostile |
| 5 | When a template renders | A Render click each time; the very first Render in the app shows a one-time warning (kept in the app's settings) | A received or edited template renders on a click without a new warning |
| 6 | How far a template can read | The whole opened folder | A received template can read every note; the header, rule list and output guard keep what it reads on screen, apart from a link the person chooses to open |
| 7 | A click on a web or mail link on a rendered page | Ask first, showing the full address, with Cancel as the default | A person can still press Open on an address that carries note text |
| 8 | Size of v1 | `files` (with `sort`, `reverse`, `limit`), `section`, `for/empty`, `if/else` with `==`/`!=`, filters `markdown`, `urlencode`, `default`. Left out until a template needs them: line ranges, front-matter fields, recursive listing, `elif`, `and`/`or`/`not`, the `lower`, `upper` and `join` filters; no re-render on folder change | A template needing those waits; the deny-by-default grammar means adding later breaks nothing |
| 9 | Hidden files in a rendered page | `allows` refuses hidden parts for template pages; `SafePath` refuses a visible name linking to a hidden file | A template page cannot use pictures or styles from a hidden folder such as `.mdedit` |
| 10 | Stylesheets in templates | A relative `<link rel="stylesheet">` is allowed; every other `<link` is refused | A template cannot use a `<link>` for anything else |
| 11 | Scope kept | The link-click sheet, the blocked-read timer and state, the `_error` variables, the least-recently-used trust record and the per-render cache stay in this version | More machinery to build and test than the minimum |

Alternatives to each are in "Alternatives Considered".

--------------------------------------------------------------------------------

## As built

Where the code differs from the plan above, or the plan left a choice:

*   **`Workspace.openAddress`**, not `openExternal`: `Workspace` already has `openExternal(_:)`, which opens a folder dropped on the app, and the first version of the link sheet called that by mistake. `TemplateRenderTests` caught it.
*   **`InfoBar`** (`UI/InfoBar.swift`) is the bar `DetailView` used for "changed on disk", extracted and shared with `TemplateBanner`. Its colour is `Palette.chip`, not `binderBg`. `TemplateBanner.content(_:busy:)` holds the text and buttons per state so a test can read them. The dark-mode pixel check is loose (the hosting view blends the bar lighter than the palette value); the light check is exact.
*   **`default`** treats empty text like an empty value. **`section`** trims blank lines around its text. An unset `limit` variable is a type error.
*   **Step costs:** one step per 256 bytes read and per 256 characters given to `markdown`, so 100 sections of 64 KB cost about 51,000 of the 200,000 steps.
*   **The clock** is checked every 1,024 steps and at each source call, so a short template with a slow source can finish after its clock; the window's timer reports the timeout (`failed(.timeout)`) on time and drops that late result.
*   **Tests:** the header (layer 1) alone already blocks every resource vector, so layer 2 has its own test in a bare web view without a header; breaking the rule list on purpose fails that test. An iframe has no positive control in the real preview because the controller already cancels web subframes. `waitFor`, `pageJS` and `letPageSettle` are the shared helpers (the names `wait` and `settle` were taken by other test classes). `LocalHTTPServer` counts every accepted connection.
*   **Not done:** the follow-up check of whether WebKit sends a DNS lookup for `dns-prefetch` or `preconnect` with only layers 1 and 2 on. Layer 3 refuses such a tag whatever the answer is.
*   **Behaviour change outside templates:** `SafePath` refuses a visible name that links to a hidden file inside the folder, so the agent tools refuse it too.

## Changed after first use

*   **One warning, not one per file.** The first Render in the app shows a short sheet (the sentence only, no template text); nothing asks after that, also not after an edit or in another folder. This replaced the hash per file and folder, which is gone (`TemplateTrust` is now one flag).
*   **A smaller link sheet.** The address is in a 380 by 54 point scrolling box and the line above it is one short sentence, so the dialog is small. Cancel is still the default and the whole address is still shown, with the query on its own line.
*   **Meta is a note's, not the template's.** `{% meta path as m %}` reads the properties block of a note (cap `metaBytes`, 16 KB, read from the top). A first version put a meta block in the template file itself; that was a misunderstanding and is removed.

## Appendix: what the spike found (2026-11-05)

Run in a scratch package with Stencil 0.15.1 and in a scratch sandboxed app with embedded helpers; none of this code is in the repository. It is the evidence for rejecting Alternatives D and E.

*   Stencil can list a template's tokens before rendering, but `Environment.init` always adds its default tags and filters, which are internal and cannot be removed. Placing our own extension first shadows them (first match wins), and each shadowed name failed with our error.
*   Stencil does not escape `{{ }}`. `for` accepts range expressions (`1...5`, `1...n`). Stencil reads Swift struct and `NSObject` properties by reflection from a template (`{{ o.hidden }}`). A tag cannot set a variable in an empty context. Comments are `{# #}`; there is no `{% comment %}`. Filters are `uppercase`, `lowercase`, `default`, `join` and others; there is no `upper`, `lower` or `truncate`.
*   Pure Stencil, depth 2, release build: 50 items and 154 tokens took 1.0 s; 100 items and 154 tokens, 4.0 s; 100 items and 304 tokens, 8.2 s. Depth 1: 100 items and 62 tokens, 0.03 s. Memory was about 2.4 times the output size. So caps alone do not bound the run time.
*   An embedded helper signed with exactly `app-sandbox` and `inherit` starts from a sandboxed app via `posix_spawn`, reads in its container, cannot read `~/Documents`, but can write in the container and reach the network. With `app-sandbox` alone it aborts at launch. `SIGKILL` and `RLIMIT_CPU` stop it; `RLIMIT_AS` and `RLIMIT_DATA` fail; the parent's `proc_pid_rusage` on the child is refused (`EPERM`); a watchdog thread inside the helper that reads its own `phys_footprint` stopped a growing helper at 256 MB in 0.35 s.
*   Compiling `SafeHTML.swift` outside the app target fails because it calls `PreviewText` (in `PreviewPage.swift`, which imports AppKit). This does not matter for the in-app engine, where the `markdown` filter calls `SafeHTML` directly.

--------------------------------------------------------------------------------

*Drafted with EGM*

# 008 · HTML, JSON and YAML files in the editor, with a preview for each

*   **Author:** Satyajit Ranjeev
*   **Status:** Built
*   **Date:** 2026-11-06
*   **Builds on:** plan 003 (HTML files), plan 005 (agent access), plan 006 (templates)

## What changed and why

HTML files used to open in the preview only, with Write blocked, and templates showed a Render bar. The person asked for a simpler model: **every code file opens in the editor, as code; the eye button previews it.** A file that was previewed and has not changed since opens in the preview next time. JSON and YAML files join HTML in this. Agents treat these files like notes.

## The model

*   **Files.** `BinderNode.codeExtensions` = HTML (`html`, `htm`), JSON (`json`) and YAML (`yaml`, `yml`). They `opensInApp`, but they are not notes: the wiki index, Find in Folder, the outline and backlinks, Print and Export still work on notes only. `Workspace.codeKind` says which kind the open file is.
*   **Modes.** There is no forced preview any more. `syncModeToFile` opens a code file in the preview if `TemplateTrust.wasRendered` has its exact text for this folder and path (for a template, after the one-time warning), and in the editor otherwise. Setting the mode to `.view` calls `enterPreview()`; leaving it calls `leavePreview()`. The note after a code file gets back the mode the reader was in.
*   **Previews.**
    *   HTML without tags: the page, as before (`PreviewRequest.html`).
    *   HTML with tags (`{%` or `{{`): rendered by the template engine from the editor's text, saved first. The one-time warning is asked on the first preview in the app; declining returns to the editor. While it renders the page is blank with a bar and **Cancel** (back to the editor); a failure shows the error page; a blocked read keeps Preview refused until it returns.
    *   JSON: `CodePreview.markdown(json:)`, pretty-printed with sorted keys in a code block whose fence cannot be closed by the data.
    *   YAML: `CodePreview.markdown(yaml:)`, a table of dotted key paths and values, built from `YAMLReader`.
    Both are Markdown, drawn by the same page as a note, so everything in the file is escaped by the renderer.
*   **The record.** `TemplateTrust.markRendered` stores a SHA-256 of the text per folder and path (200 files, 50 folders) in the app's settings whenever a code file is previewed. An edit makes the file open in the editor again.
*   **The editor.** `EditorTextView.code` (a `CodeKind?`) switches it to code: a monospace font, no gutter, a 110-character column, colours from `CodeSyntax` (tags, strings, keys, numbers, template tags, comments; none above 300,000 characters), no Markdown analysis, no wiki completion, no spell checking or autocorrection, Return keeps the indent, Tab indents by two spaces. Markdown notes are unchanged.
*   **Agents.** `SafePath.Kind.editable` = notes plus code files. `read_note` and `propose_edit` use it, so a suggestion for an HTML, JSON or YAML file appears in the Review tab and applies as one undoable edit, like a note. Templates still read notes with `.note`, so `section`, `meta` and `tasks` are unchanged. The earlier refusal ("HTML pages are read-only") is gone.
*   **YAML in templates.** `{% data %}` now reads YAML with `YAMLReader` (nested), not only the flat subset.

## Safety

Nothing about rendering changed: the template engine, the one-time warning, the containment layers and the output guard are as in plan 006. What is new is that the app saves HTML, JSON and YAML you edit (through `DocumentStore`, with its encoding and outside-change checks), and that an agent suggestion for such a file needs the same acceptance as one for a note. `YAMLReader` is bounded (20,000 lines, 20 levels, 5,000 entries); the previews cap the file at 1 MB.

## Tests

`CodeFilesTests` (kinds, binder, links, the YAML reader and table, JSON preview, escaping, colours, the code editor, agents and `SafePath.editable`), `TemplateRenderTests` (opening in the editor, preview renders, the one-time warning, reopening, lifecycle), `TemplateBannerTests`, and updated `PreviewTests`, `RightPanelTests`, `SafePathTests`, `ProposalSafetyTests` and `AgentToolsTests`.

## Not done

Syntax checking of any kind, folding, line numbers, indentation guides, a JSON tree view, a YAML schema, and editing of other file types.

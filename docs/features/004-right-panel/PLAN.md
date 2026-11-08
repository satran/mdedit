# 004 · One right panel for Outline and Find, Share in the toolbar

Status: built; the panel can also be dragged wider or narrower (280 to 560 points, remembered). One width for both tabs was confirmed. The mockup is `design.html` in this folder (open it in a browser; it follows the system's light and dark).

## What changes

1. The outline and Find & Replace share **one right-hand panel**. Two icons at the top of the panel choose between them.
2. The **Share (export) icon moves** from the footer to the top toolbar. A separate Print button was dropped: Print is in the share menu and on ⌘P.

## Toolbar

Before: `[binder] [back]  breadcrumb  [eye] [new window] [find] [outline]`

After: `[binder] │ [back]  breadcrumb  [eye] [print] [share] [new window] │ [panel]`

- **Share** (`square.and.arrow.up`): the same menu as the footer has now: Export as HTML…, Copy as Markdown, Print….
- **Panel toggle** (`sidebar.right`): opens and closes the right panel. It is blue while the panel is open, as the outline button is today.
- The **magnifier button goes**. Find is reached with ⌘F (and ⌥⌘F, ⇧⌘F, Edit ▸ Find) and from the panel's tabs. It is one of the two things the panel is for, so it would be a duplicate.
- Thin dividers set the two panel toggles apart, one after the binder toggle and one before the panel toggle, so the toolbar is symmetric. The toggles act on the window; everything between them acts on the note.
- **HTML pages:** preview and share are dimmed and disabled, not hidden, the way the eye button already is. (Export and Print are off for pages today.)
- **Footer:** keeps the word count on the left, and distraction free and typewriter on the right in Write mode. In View mode the right side is empty. The share icon leaves it, and print is no longer a button (it is in the share menu and on ⌘P).
- **Width:** the toolbar gains two icons (about 64 pt). The window's minimum width goes up a little (488 → 520 with the binder hidden), so the breadcrumb keeps room. The breadcrumb already truncates.

## The panel

One panel, one fixed width: **361 pt including its divider** (the width Find has today).

```
┌───────────────────────────────┐
│ [≣ outline][🔍 find]  Outline  │  52 pt, level with the toolbar
├───────────────────────────────┤
│ the tab's content              │
```

- The tab switch is the same segmented control the app uses elsewhere (two icon segments, the chosen one raised). Icons: `list.bullet.indent` for Outline and `magnifyingglass` for Find. Each has a tooltip with its shortcut and an accessibility label; the chosen one carries the selected trait.
- A title next to the switch names the tab ("Outline", "Find & Replace"). Find's own title row and its ✕ are removed; Esc and the toolbar toggle close the panel.
- **Outline tab:** unchanged content: Headings, then Linked mentions. For an HTML page it shows "No headings" as it does now.
- **Find tab:** unchanged content: scope switch, fields, options, results. On a page, "This file" stays unavailable and the scope is Folder.
- Switching tabs never resizes the window. That also makes the panel's slide animation simpler: one width in, one width out.

### Why one width

The outline is 241 pt today and Find 361 pt, so going from one to the other resized the window by 120 pt. With one width the cost is that opening only the outline takes 120 pt more than before; the outline text has room to breathe, but a narrow window feels it. The alternative is a width per tab (the window resizes by 120 pt when you switch, with the slide animation we have). I recommend the single width. It is the one decision to confirm.

## Behaviour

| Action | Result |
|---|---|
| Toolbar toggle, panel closed | Opens on the tab used last (Outline the first time). |
| Toolbar toggle, panel open | Closes. |
| ⌥⌘O | Panel closed: open on Outline. On Find: switch to Outline. On Outline: close. |
| ⌘F, ⌥⌘F, ⇧⌘F | Open on Find (scope and field as now), or switch to it. The selected text becomes the query, as now. |
| Esc in the Find tab | Goes back to where you were: closed if the panel was closed when Find opened, otherwise Outline. This is how it works now ("the outline comes back as it was"). |
| Click a tab icon | Switches. Leaving Find clears the match marks in the note; coming back brings the query and marks back. |
| Window in full screen | Panel opens without the resize, as now. |

The choice (open or closed, and the tab) is remembered across launches, like the outline's open state is today. The old "outline open" setting is read once as "open on Outline".

## Model

- `Workspace.panel: RightPanel?` replaces the pair `outlineVisible` and `findVisible` (`nil` is closed); `RightPanel` is `.outline` or `.find`. `outlineVisible` and `findVisible` stay as computed read-only properties for the views and tests during the change.
- `Workspace.lastPanel` remembers the tab for the toggle; `panelBeforeFind` remembers where Esc goes.
- `rightPanelWidth` is `panel == nil ? 0 : 361`.
- `slidePanel(.right)` (built for the smooth animation) keeps working: a tab switch changes no width, so it does not animate the window; open and close hold the leaving panel until the window has shrunk, as now.
- `DetailView` shows one `RightPanelView` that holds the tab switch and the chosen content; `OutlineView` and `FindPanel` lose their own titles.

## Tests

- Opening and closing resizes the window by 361 pt and the writing column keeps its place (extends `PanelSlideTests`); switching tabs changes the window by nothing.
- The state table above: toggle, ⌥⌘O, ⌘F, Esc, remembered tab, old "outline open" setting migrated.
- Find marks cleared on leaving the tab and restored on return.
- Toolbar: share exists and is dimmed and disabled for an HTML page; the footer no longer has it; the magnifier is gone (checked by rendering the toolbar and looking at it).
- The minimum window width is enough for the toolbar (a pixel check at the minimum).
- Existing: `FindReplaceTests` (panel widths), `FindPanelTests`, `CommandTests` and the snapshot tests are updated for the single width and the tab switch.
- `make audit` unchanged.

## Order of work

1. State and behaviour: `RightPanel`, one width, tab switch, shortcuts, persistence; panel view with the tab switch. Tests.
2. Toolbar: share moves up, the magnifier goes, minimum width, footer cleaned up. Tests.
3. Manual, README, and the design board in `docs/design.html` is not edited (it is a packed file); this folder's `design.html` is the reference.

Steps 1 and 2 can be separate commits.

## Open points

- Single width (recommended) or a width per tab.
- Should the toolbar toggle open on the last tab (recommended) or always on Outline?

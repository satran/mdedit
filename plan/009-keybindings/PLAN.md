# 009 · Keyboard shortcuts that can be guessed

*   **Status:** Agreed and built.
*   **Date:** 2026-11-06

## The rules

1.  **Keep what every Mac app does.** ⌘N, ⌘O, ⌘P, ⌘F, ⌘G, ⌘B, ⌘I, ⌘K, ⌘[ ⌘], ⌘, and ⌘? stay as they are.
2.  **Letters mean something.** Where a shortcut has a letter, it is the first letter of the thing it does (**B**ullets, **N**umbered, **T**asks, **C**ode, **S**idebar). The old list keys (⇧⌘7, ⇧⌘8) came from Google Docs and have no connection to the word "list".
3.  **The modifier says how big the thing is.**
    *   ⌘ and ⇧⌘: a word or a phrase (bold, italic, link, inline code, strikethrough, highlight).
    *   ⌥⌘: a whole paragraph (headings, lists, tasks, code block, rule).
    *   ⌃⌘: how the window behaves (typewriter, new window).
4.  **A symbol that is typed in Markdown can be the key.** `>` is the quote (⇧⌘.) and `-` is the rule (⌥⌘-). These two stay, because the character is the clue.
5.  **No clashes with the system.** Each proposed key was checked against the standard macOS shortcuts (below).

## The agreed mapping

**Format**

| Function | Was | Now |
|---|---|---|
| Bold, Italic, Link | ⌘B, ⌘I, ⌘K | same |
| Inline code | ⌘E | ⇧⌘C |
| Strikethrough, Highlight | ⇧⌘X, ⇧⌘H | same |
| Heading 1 to 6 | ⌥⌘1 to 6 | ⌘1 to 6 |
| Body text | ⌥⌘0 | ⌘0 |
| Bulleted list | ⇧⌘8 | ⇧⌘L |
| Numbered list | ⇧⌘7 | ⇧⌘N |
| Task list | ⇧⌘T | same |
| Quote | ⇧⌘. | same |
| Code block | ⌥⌘K | ⌥⌘C |
| Horizontal rule | ⌥⌘- | same |

**View and modes**

| Function | Was | Now |
|---|---|---|
| Write | ⌘1 | ⌃⌘W |
| View | ⌘2 | ⌃⌘V |
| Preview | ⇧⌘E | ⌘E |
| Binder | ⌘/ | ⇧⌘B |
| Side panel | none | ⌘\\ |
| Outline | ⌥⌘O | same |
| Status bar | ⌥⌘B | ⌃⌘S |
| Search binder | ⇧⌘B | ⌥⌘S |
| Distraction free | ⌃⌘F | ⇧⌘D |
| Typewriter | ⌃⌘T | same |
| Command palette | ⇧⌘P | same |

**File and find**

| Function | Was | Now |
|---|---|---|
| New folder | ⇧⌘N | ⌥⇧⌘N |
| Go to File (new, fuzzy finder) | none | ⇧⌘O |
| All others (new document, new window, open, rename, print, back, forward, find, replace, find in folder, next, previous, settings, help) | | same |

No shortcut (palette only): Move to Trash, Export as HTML, Copy as Markdown, Edit Preview Stylesheet, Trusted Addresses, Reveal in Finder, Collapse All Folders, New Window with This Folder.

## Checked against macOS

*   ⌥⌘B, ⌥⌘N, ⌥⌘C, ⌥⌘T, ⌥⌘S, ⇧⌘C, ⇧⌘D, ⌘E and ⌃⌘N are not used by a standard macOS menu in a text app. In Safari ⌥⌘B is Bookmarks, in Finder ⌥⌘S is the sidebar (the same meaning), in TextEdit ⌥⌘C is Copy Style and ⌘E is "use selection for find"; MDEdit has none of those commands.
*   ⌥⌘Q (the first letter of Quote) is avoided because it is "Quit and Keep Windows". ⌥⌘H is avoided because it is "Hide Others".
*   ⌥⌘T is Hide Toolbar in the Finder; MDEdit has no toolbar menu item, so it is free.

## What implementing it touches

*   `UI/FormatCommands.swift` (the format keys and its header comment) and `UI/Commands.swift` (new window, preview, binder, status bar, distraction free).
*   The manual's shortcut page is generated from the command list, so it follows by itself. `HelpTests` checks the keys written in `Resources/Manual.md`; the lines that name keys there (for example the binder and preview keys) need the same edit.
*   Tests that assert a key: `CommandTests` and any test that reads a shortcut string. The README's feature table and `docs/` mention a few keys.
*   Settings has no key editor today. Letting people choose their own keys is a separate piece of work.

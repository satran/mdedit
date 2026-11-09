# MDEdit Manual

## Getting started

MDEdit edits plain Markdown notes that live in an ordinary folder. There is no database and no import: open a folder and its notes are the files in it.

1. Choose **File ▸ Open Folder…** (⌘O) and pick the folder that holds your notes.
2. The **binder** on the left shows the folder as a tree. Click a note to open it in a tab.
3. Start typing. Changes are saved automatically a moment after you stop typing, and when you switch notes, close the window or quit.

MDEdit opens the folder you chose last time when you start it. **File ▸ Open Recent** lists the folders you used before. **New Window with This Folder** opens the same folder in a second window, and **New Window** (⌥⌘N) lets you pick another folder.

Notes are files ending in `.md`, `.markdown` or `.txt`. In the binder and the tabs, notes, web pages, JSON and YAML files show without their extension, since their icon says what they are. Files with the plain page icon, such as pictures and PDFs, keep it. Other files in the folder appear in the binder too, so you can see and move them, but they are not edited.

## The window

- **Binder** (left): the folder tree, with a search box at the top. Show or hide it with the sidebar button at the top left, or ⇧⌘B.
- **Editor or viewer** (centre): the open note. The path above it shows where the note is. The row at the bottom shows the word count and reading time, and holds the distraction-free and typewriter buttons. The toolbar at the top has the share button.
- **Side panel** (right, optional): show or hide it with the button at the top right. Icons in the bottom row of the panel switch between its tabs: the **Outline**, which lists the headings of the note and the notes that link to it (⌥⌘O) and **Find and replace** (⌘F). With agent access on there is a third tab, **Review**. The panel keeps its place and width when you switch, and you can drag its left edge to make it wider or narrower.
- The **status bar** at the bottom can be hidden with ⌃⌘S.

## Working with notes and folders

**New note.** File ▸ New Document (⌘N) creates `Untitled.md` in the selected folder and lets you name it straight away. **New Folder** (⇧⌘N) makes a folder the same way.

**Rename.** Double-click a name in the binder, or press ⌥⌘R with it selected. Press Return to accept and Esc to cancel.

**Move.** Drag a note or folder onto another folder. A name already taken is never overwritten.

**Copy in.** Drag files from Finder onto a folder in the binder to copy them into it.

**Trash.** File ▸ Move to Trash moves the selected item to the Trash. It is not deleted for good, so you can still get it back from there.

**Go to File.** ⇧⌘O opens a box over the note. Type a few letters of a file's name or path, in order but not next to each other (`mtg` finds `Notes/Meeting.md`), and press Return. Several words match in any order. Up and Down choose, Esc closes. With nothing typed it lists the notes you opened last.

**Search.** Type in the search box (⌥⌘S jumps there). To search inside the notes, use Find and Replace below. The binder narrows to the files and folders whose name contains what you typed, with the folders that hold them. Clear the box to see the whole tree again.

**The binder is used with the mouse.** Click a note to open it, a folder to open or close it, and a file MDEdit cannot edit, such as a picture or a PDF, to preview it. The arrow keys do not move through the binder, so typing while you rename a file never changes the selection.

**Changes outside MDEdit.** If you edit a note in another app, MDEdit notices and shows the new text. If a note was changed on disk while you also had unsaved changes, a bar appears with **Keep mine** and **Reload**.

## Tabs

Every note you open becomes a tab in the **Open** section at the top of the binder, above the folder tree. Click a note in the tree to open it in a new tab, or click a tab to go back to it. Clicking a note that is already open just switches to it.

- **Close** a tab with the × on its row, or press ⌘W. Closing a tab never touches the file. The note next to it opens in its place. On the last tab, ⌘W closes the window.
- **Reorder** tabs by dragging them.
- **Right-click** a tab for Close Others, Close Tabs Below and Reveal in Finder.
- **Move between tabs** with ⇧⌘[ and ⇧⌘] (View menu). ⌥⌘T brings back the tab you closed last.
- When two tabs have the same name, each gets a small grey tag after it: the folder, or just enough of the path to tell them apart (`A/Notes` and `B/Notes`). Two files with the same name and icon in one folder (`Plan.md` and `Plan.txt`) are tagged with their extension.
- An orange mark on a tab means the file changed on disk while it was open.

Notes save as you type, so a tab has no unsaved state. The Open section shows up to eight tabs and then scrolls. The tabs are remembered per window and come back when you reopen it. They are kept up to date when you rename, move or delete a note.

## Back and Forward

MDEdit remembers the notes you opened, like a browser does. **View ▸ Back to Previous Note** (⌘[) returns to the note you were in before, and **Forward to Next Note** (⌘]) undoes a Back. The ‹ button at the top left of the note does the same as Back.

The back and forward side buttons of a mouse do the same.

The trail keeps your last 100 notes, skips notes that have been deleted or renamed, and starts again when you open another folder. Opening a different note after going back clears Forward.

## Writing

The **Write** view is a plain-text editor that styles Markdown as you type, in a monospaced font. The marks you type (`#`, `>`, `-`, `**`) stay visible but quiet, so what you see is exactly what is in the file.

### Formatting

Use the **Format** menu or the shortcuts. Each one toggles: use it again to take the formatting off.

| To make | Type | Shortcut |
| --- | --- | --- |
| Bold | `**text**` | ⌘B |
| Italic | `*text*` | ⌘I |
| Strikethrough | `~~text~~` | ⇧⌘X |
| Highlight | `==text==` | ⇧⌘H |
| Inline code | `` `code` `` | ⇧⌘C |
| Link | `[text](address)` | ⌘K |
| Heading 1–6 | `# ` to `###### ` | ⌘1 to ⌘6 |
| Body text | | ⌘0 |
| Bulleted list | `- item` | ⇧⌘L |
| Numbered list | `1. item` | ⇧⌘N |
| Task list | `- [ ] task` | ⇧⌘T |

With text selected, a shortcut wraps the selection. With nothing selected, it applies to the word or line the caret is in. Pressing Return inside a list continues the list; pressing Return on an empty item ends it.

### Links between notes

Type `[[` to link to another note. A list of your notes appears and narrows as you type; ↑ ↓ choose and Return inserts the link.

- `[[Note]]` links to the note called Note, wherever it is in the folder. When two notes share a name, the one nearest to the current note wins.
- `[[Note|shown text]]` shows different text for the link.
- `[[Note#Heading]]` links to a heading inside the note.
- `[[folder/Note]]` names the folder, to pick between notes of the same name.

Click a link in the **View** to follow it. If the note does not exist, MDEdit offers to create it next to the current note. The outline panel lists **backlinks**: the notes that link to this one.

### Pictures and files

Drag a picture or file from Finder into the editor and MDEdit writes a Markdown link or image for it at the caret. Pictures are shown in the View. Pictures from the web are not loaded unless you turn that on in Settings, because loading one tells its server that you opened the note.

### Front matter

A block of `key: value` lines between `---` lines at the very top of a note is *front matter*. In the editor it is set in quiet colours, and in the View it becomes a small **Properties** card.

### Typewriter mode and distraction free

- **Typewriter mode** (⌃⌘T, or the button in the bottom row) keeps the line you are typing in the middle of the window.
- **Distraction free** (⇧⌘D) hides everything except the note. Settings decides whether it uses the full screen or just fills the window. Press Esc or the same shortcut to leave.

## Find and replace

⌘F opens the side panel on its **Find and replace** tab (or click the magnifying-glass icon in the bottom row of the panel). Press Esc to go back to where the panel was: the outline, or closed. The panel has two scopes, chosen at the top.

### This file

- Type in **Find**. Every match is marked in the note, the one you are on in a stronger yellow, and the panel lists them with their line numbers. The count shows where you are (“2 of 5”).
- Return or ⌘G goes to the next match, ⇧⌘G to the previous one. The ▲ ▼ buttons do the same. Clicking a line in the list selects that match in the note.
- Type in **Replace with**. **Replace** changes the current match and moves on; **Replace all** changes every match. Either is a single Undo (⌘Z) step.
- ⌘F also takes the selected text as the thing to find.
- In the View, matches are counted but not marked; Replace switches to Write first.

### Folder

⇧⌘F, or the **Folder** button, searches every note in the opened folder.

- **Search in** limits it to the whole project or just this note's folder (and the folders below it).
- Results are grouped by note, with the folder beside the name and the number of matches. Click the arrow to open or close a note's group, or use **Expand all**. Click a match to open it in the editor.
- Each match shows what it would become: the old text struck through in red, the new text in green.
- Every match and every note has a **checkbox**. Untick what you want to keep, then press **Replace N in M files**. A match you left unticked is never touched.
- The note you have open changes in the editor, and the others on disk. **⌘Z undoes the whole replace**, including the other files, as long as they have not been edited since. If a note changed after the search, MDEdit skips it and says so.

### The options

| Button | Meaning |
| --- | --- |
| **Aa** | Match case. |
| **ab** | Whole word: “cat” does not match “concat”. |
| **.\*** | Regular expression. In the replacement, `$1`, `$2` … stand for the groups you captured. |
| **Preserve case** | The replacement follows the case of what it replaces: “time” gives “failed”, “Time” gives “Failed”, “TIME” gives “FAILED”. |

An invalid pattern is shown in the field instead of searching. Very large results are cut off at 5,000 matches a note and 20,000 in all (the count then shows a +), and a pattern that takes too long is stopped.

## Viewing

**View ▸ View** (⌃⌘V) shows the note typeset like a printed page, in a sans face (Inter unless you pick another under **Settings ▸ Viewer ▸ Font**). **Write** (⌘1) returns to editing, and ⇧⌘E toggles between the two.

The View uses curly quotes, proper dashes and ellipses, shows tables, task lists, quotes and code blocks, and sets local pictures centred. Links open as follows: another note opens in MDEdit, a web address opens in your browser, and a local file opens in its own app. Nothing runs from a note.

### Pictures and styles from the web

A picture or stylesheet on the web tells its server that you opened the note, so the View does not load them. Turn on **Settings ▸ Viewer ▸ Remote pictures and styles** to allow it. Scripts never run, in a note or in an HTML file.

### Your own stylesheet

**View ▸ Edit Preview Stylesheet…** creates `.mdedit/preview.css` in the open folder and shows it in Finder. Whatever you write there is added after the built-in styling, so it can change fonts, colours, spacing and the width of the page. The starter file lists the colour variables. It applies to the View of notes in that folder, not to HTML files.

## HTML, JSON and YAML files

HTML files (`.html`, `.htm`), JSON files (`.json`) and YAML files (`.yaml`, `.yml`) in the folder appear in the binder and open in the editor, shown as code: a monospace font, colours for tags, keys and strings, and none of the Markdown behaviour (no lists, no wiki links, no spell checking). You can edit and save them like a note, search them with **Find**, and undo.

Press the eye button (**Preview**, ⌘E) to see the result:

- **HTML** is shown as a page, as a browser would show it. Pictures and stylesheets next to the file work; nothing outside the open folder can be read, and scripts never run. Links to other pages and notes in the folder open in MDEdit, and web addresses open in your browser. If the file has template tags, the preview renders it (see Templates below).
- **JSON** is shown as pretty-printed JSON with the keys in order. A file that is not valid JSON says so and shows its text.
- **YAML** is shown as a table of keys and values. Nested keys are joined with dots (`db.host`), and a list of maps has a row per field (`items[1].name`). It reads the common parts of YAML (mappings, lists, plain and quoted values, block text); anything else shows the text instead.

A file you have previewed opens in the preview next time, as long as its text has not changed since; after an edit it opens in the editor again. These files are not notes: they are not part of wiki links, the outline, backlinks or Find in Folder, and Print and Export are for notes. Agents can read them and suggest edits to them in the Review tab, as for a note.

### Templates

An HTML file that contains `{%` or `{{` is a template. It opens in the editor as code. Press **Preview** (the eye button) and the page is filled in from the notes in the open folder; press it again to go back to the source. The first time you preview a template in MDEdit it warns you once (below). A template is not rendered when a note changes. A template you have already previewed opens in the preview, rendered, as soon as you open it, as long as its text has not changed since; after you edit it, it opens in the editor again. While a page renders there is a bar with **Cancel**.

The first time you preview a template in MDEdit, it warns you once: a rendered page can read every note in the folder and show it on screen. It cannot change anything, and it does not make a network request on its own, even if remote pictures are on in Settings. After that Preview just renders. A link to a web or mail address on a rendered page asks you first and shows the whole address, which can contain text from your notes, unless you listed that host with **Trusted Addresses for Templates…** in the command palette (one host per line, `example.com` or `*.example.com`, https only, for this folder). Hidden files are never read.

A small example, an index of the notes in `journal` with each note's Summary:

```
<h1>Journal</h1>
{% files "journal" sort "modified" reverse limit 10 as items %}
{% for f in items %}
  {% meta f.path as m %}
  <h2><a href="{{ f.path|urlencode }}">{{ f.title }}</a> {{ f.modified }}</h2>
  <p>{{ m.author|default:"unknown" }}</p>
  {% section f.path "Summary" as text %}
  {{ text|markdown:f.folder }}
{% empty %}
  <p>No notes yet.</p>
{% endfor %}
```

- `{{ value }}` prints a value; text is escaped. Write attributes in quotes: `href="{{ f.path|urlencode }}"`. Filters: `default:"text"`, `urlencode`, `markdown` (formatted HTML; `[[wiki links]]` become links to the notes; `markdown:folder` makes relative links and pictures relative to that folder), `length`, `days_until`, `days_since`, `date:"EEE d MMM"`, `week`.
- `today` is today's date and `now` the time (`2026-11-06`, `2026-11-06 14:30`). Dates are text, so `t.attrs.due < today` works. `{% if t.attrs.due|days_until < 0 %}` is true for a date in the past.
- `{% for x in list %}…{% empty %}…{% endfor %}` and `{% if a == b and not c %}…{% elif …%}…{% else %}…{% endif %}`. Comparisons: `== != < <= > >= in`. Loops nest 3 deep, all blocks together 10.
- `{% files "folder" [recursive] [pages] [match "2026-*.md"] [sort "name"|"modified"] [reverse] [limit N] as items %}` lists notes and folders (`recursive`: every level, files only; `pages`: also `.html` files). Each item has `name`, `path`, `folder`, `ext`, `kind`, `title`, `modified` and `size`. At most 500 items.
- `{% section "path" "Heading" as text %}` reads the text under a heading of a note. A note over 64 KB is not read.
- `{% meta "path" as m %}` reads a note's properties block (the `key: value` lines between `---` lines at the top): `{{ m.title }}`, `{% for t in m.tags %}…{% endfor %}`, `{% if m.draft %}`. `true` is the text true and `false` is empty. Only the top of the note is read.
- `{% tasks "path" as ts %}` reads the `- [ ]` and `- [x]` lines of a note: `t.done`, `t.text`, `t.line`, `t.is_sub`, `t.attrs.due` (from `@due(2026-11-10)`) and `t.context` (the lines under it).
- `{% data "path.json" as d %}` reads a JSON file (or a flat YAML one) from a visible folder.
- `{% sort list by "key" desc as x %}`, `{% where list key == value as x %}` and `{% groupby list by "key" as g %}` make views of a list. Missing values sort last.
- `{% include "page.html" with name=value %}` runs another page of the folder here.
- A link on the page to itself with a query, `<a href="?due=overdue">`, renders it again with `query.due`.
- If a file cannot be read, the result is empty and `<name>_error` says why (`not available`, `too large`, `not text`, `unreadable`, `read budget used`).
- Braces inside an HTML comment, or between `{% verbatim %}` and `{% endverbatim %}`, are copied as they are.
- Paths mean "relative to the open folder", wherever the template file is. A picture or link inside text from a note is relative to the open folder too, unless you use `markdown:f.folder`.
- Templates read the notes as saved on disk, not unsaved edits. The language has no other tags: anything else is a syntax error with a line number.
- A page that contains a tag able to open a connection (anything but a relative stylesheet among `<link>`, and `<base>`, `<iframe>`, `<object>`, `<embed>`, `<meta http-equiv>`, `ping` or `formaction`) is not shown.
- A render stops at 2 seconds, 200,000 steps, 2 MB of output, or when you press **Cancel**.

## Printing and exporting

- **Print… / PDF** (⌘P, or in the share menu) prints the note as it looks in the View. Choose **PDF** in the bottom left of the print panel to save a PDF.
- **Export as HTML…** (in the share menu in the toolbar) saves a standalone web page. Scripts and unsafe markup are stripped from it.
- **Copy as Markdown** copies the note's text.

## Agent access

An agent such as Claude Code can look at what you are editing and **suggest** changes. It is off until you turn it on in **Settings ▸ Agents**. Nothing an agent sends changes a note until you press **Accept**.

**Connecting Claude Code.** Turn on Agent access, then press **Copy command** and paste it in a terminal. It looks like this (with your own token):

```
claude mcp add --transport http mdedit http://127.0.0.1:47821/mcp --header "Authorization: Bearer <token>"
```

The command contains the token, so it also lands in your shell history. **Regenerate** makes a new token and signs every agent out. An agent that has the token can read every note in the folder that is open.

**What an agent can do.** It can ask which note is open, what is selected and whether there are unsaved changes; read a note (the text on screen if the note is open with unsaved changes); and suggest replacing one passage with another.

**The Review tab.** While Agent access is on, the side panel gets a fourth tab, with the checklist icon in its bottom row. Each suggestion is a card with the agent's reason and the lines removed and added. When one is waiting, the status bar says "1 suggestion"; click it to open the tab. The panel never opens by itself.

- **Click a card** to open its note and see the passage that would be replaced, tinted red behind the text.
- **Accept** makes the change as one step of Undo (⌘Z). **Reject** drops the suggestion.
- If you change the passage by hand, the card dims and says "Changed since proposed". It can only be dismissed, and it comes back to normal if the text matches again.
- Suggestions are not kept: quitting, closing the window, or turning Agent access off forgets them.

## Settings

Open them with **MDEdit ▸ Settings…** (⌘,).

- **Appearance:** light, dark, or follow the system.
- **Editor:** the font and size, the line width in characters, larger heading sizes, and whether distraction free uses the full screen.
- **Viewer:** the font, the text size, the line width, and whether remote pictures and stylesheets are loaded.
- **Agents:** the on/off switch, the port, and the token (Copy command, Regenerate). Off by default.

## The command palette

⇧⌘P opens a list of every command in the menus. Type to narrow it, ↑ ↓ to choose, Return to run, Esc to close. It also holds a few commands that are not in a menu, such as Reveal Folder in Finder and Collapse All Folders.

## Your files and privacy

- Notes are saved as ordinary files, in the folder you chose. Nothing else is stored in that folder except `.mdedit`, which holds `preview.css` if you make one. Older versions kept saved scripts and command history in `.mdedit/scripts` and `.mdedit/history`; they are no longer used and you can delete them.
- MDEdit works inside the macOS App Sandbox. It can only open the folders you pick, and it keeps access to them with a bookmark so you do not have to choose them again.
- Nothing is sent anywhere. The only network use is a picture on the web, and only if you allow it in Settings. When agent access is switched on (off by default), the app also accepts connections from programs on your own Mac, and from nowhere else.
- If a note was changed elsewhere while you had unsaved edits, MDEdit saves your edits to a copy beside it rather than losing them.

## Troubleshooting

**A note does not appear in the binder.** Only the opened folder is shown. Files that start with a dot are hidden. Use **Reveal Folder in Finder** (in the command palette) to check the files are there.

**A shortcut does nothing.** Some shortcuts only work while a note is open, or only in Write view. A greyed menu item is not available right now.

**The first launch is blocked on another Mac.** If the app was not notarised, macOS asks you to confirm: right-click the app and choose Open once.

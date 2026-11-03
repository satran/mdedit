# MDEdit Manual

## Getting started

MDEdit edits plain Markdown notes that live in an ordinary folder. There is no database and no import: open a folder and its notes are the files in it.

1. Choose **File ▸ Open Folder…** (⌘O) and pick the folder that holds your notes.
2. The **binder** on the left shows the folder as a tree. Click a note to open it.
3. Start typing. Changes are saved automatically a moment after you stop typing, and when you switch notes, close the window or quit.

MDEdit opens the folder you chose last time when you start it. **File ▸ Open Recent** lists the folders you used before. **New Window with This Folder** opens the same folder in a second window, and **New Window** (⌥⌘N) lets you pick another folder.

Notes are files ending in `.md`, `.markdown` or `.txt`. Other files in the folder appear in the binder too, so you can see and move them, but they are not edited.

## The window

- **Binder** (left): the folder tree, with a search box at the top. Show or hide it with the sidebar button at the top left, or ⌘/.
- **Editor or viewer** (centre): the open note. The path above it shows where the note is. The row at the bottom shows the word count and reading time, and holds the distraction-free, typewriter and export buttons.
- **Outline** (right, optional): the headings of the note, and the notes that link to it. Show or hide it with the button at the top right, or ⌥⌘O. The magnifying-glass button next to it opens find and replace in the same place.
- The **status bar** at the bottom can be hidden with ⌥⌘B.

## Working with notes and folders

**New note.** File ▸ New Document (⌘N) creates `Untitled.md` in the selected folder and lets you name it straight away. **New Folder** (⇧⌘N) makes a folder the same way.

**Rename.** Double-click a name in the binder, or press ⌥⌘R with it selected. Press Return to accept and Esc to cancel.

**Move.** Drag a note or folder onto another folder. A name already taken is never overwritten.

**Copy in.** Drag files from Finder onto a folder in the binder to copy them into it.

**Trash.** File ▸ Move to Trash moves the selected item to the Trash. It is not deleted for good, so you can still get it back from there.

**Search.** Type in the search box (⇧⌘B jumps there). To search inside the notes, use Find and Replace below. The binder narrows to the files and folders whose name contains what you typed, with the folders that hold them. Clear the box to see the whole tree again.

**Keyboard in the binder.** ↑ and ↓ move through the rows, and notes open as you pass them. → opens a folder, ← closes it or steps up to its parent. Space previews a file that MDEdit cannot edit, such as a picture or a PDF.

**Changes outside MDEdit.** If you edit a note in another app, MDEdit notices and shows the new text. If a note was changed on disk while you also had unsaved changes, a bar appears with **Keep mine** and **Reload**.

## Back and Forward

MDEdit remembers the notes you opened, like a browser does. **View ▸ Back to Previous Note** (⌘[) returns to the note you were in before, and **Forward to Next Note** (⌘]) undoes a Back. The ‹ button at the top left of the note does the same as Back.

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
| Inline code | `` `code` `` | ⌘E |
| Link | `[text](address)` | ⌘K |
| Heading 1–6 | `# ` to `###### ` | ⌥⌘1 to ⌥⌘6 |
| Body text | | ⌥⌘0 |
| Bulleted list | `- item` | ⇧⌘8 |
| Numbered list | `1. item` | ⇧⌘7 |
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
- **Distraction free** (⌃⌘F) hides everything except the note. Settings decides whether it uses the full screen or just fills the window. Press Esc or the same shortcut to leave.

## Find and replace

The **magnifying-glass button** in the header, or ⌘F, opens the find and replace panel on the right, in the place of the outline. Close it with ✕ or Esc, and the outline comes back as it was. The panel has two scopes, chosen at the top.

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

**View ▸ View** (⌘2) shows the note typeset like a printed page, in a **Serif** (Literata) or **Sans** (Inter) template. Switch between them with the buttons at the bottom left. **Write** (⌘1) returns to editing, and ⇧⌘E toggles between the two.

The View uses curly quotes, proper dashes and ellipses, shows tables, task lists, quotes and code blocks, and sets local pictures centred. Links open as follows: another note opens in MDEdit, a web address opens in your browser, and a local file opens in its own app. Nothing runs from a note.

### Pictures and styles from the web

A picture or stylesheet on the web tells its server that you opened the note, so the View does not load them. Turn on **Settings ▸ Viewer ▸ Remote pictures and styles** to allow it. Scripts never run, in a note or in an HTML file.

### Your own stylesheet

**View ▸ Edit Preview Stylesheet…** creates `.mdedit/preview.css` in the open folder and shows it in Finder. Whatever you write there is added after the built-in styling, so it can change fonts, colours, spacing and the width of the page. The starter file lists the colour variables. It applies to the View of notes in that folder, not to HTML files.

## HTML files

HTML files (`.html`, `.htm`) in the folder appear in the binder with a globe icon and open as a page, as a browser would show them, with no editor. Pictures and stylesheets next to the file work; nothing outside the open folder can be read, and scripts never run. Links to other pages and notes in the folder open in MDEdit, and web addresses open in your browser.

For a page, **Write**, **Find** in the file, **Print**, **Export** and **Run Shell Command** are unavailable and the eye button is dimmed. Pages are not part of wiki links, the outline or Find in Folder. Reopen the page to see changes to its stylesheets or pictures; changes to the page itself show on their own.

## Printing and exporting

- **Print… / PDF** (⌘P) prints the note as it looks in the View. Choose **PDF** in the bottom left of the print panel to save a PDF.
- **Export as HTML…** saves a standalone web page. Scripts and unsafe markup are stripped from it.
- **Copy as Markdown** copies the note's text.

## Running shell commands

This is off until you turn it on in **Settings ▸ Shell ▸ Run shell commands**.

Press ⌘R in the editor, type a command, choose where the output goes, and press Return. The selected text, or the whole note if nothing is selected, is sent to the command as its standard input, as in Vim's `!`. The note is saved first.

### Where the output goes

| Choice | What happens |
| --- | --- |
| Insert | The output is added at the caret. |
| Replace | The output replaces the selection, or the whole note if nothing is selected. |
| New File | The output goes into a new note called `Output <name>` next to the current one, and it opens. |
| Panel | The output is only shown in a small panel. Use this for commands that just do something, like `git add .`. |

Tab in the box cycles through the four choices. Every insert or replace is **one step of Undo** (⌘Z). If the command fails (a non-zero exit), the note is left alone and the error is shown in the panel. Esc cancels a running command or closes the box.

### What a command can use

Each command starts in the opened folder and knows these variables:

- `MD_WORKING_DIR`: the opened folder.
- `MD_FILE_PATH`: the open note.
- `MD_FILE_LINE` and `MD_FILE_COLUMN`: where the caret is, counting from 1.
- `MD_FILE_SELECTION`: the selected text, when it is under 64 KB (the full selection always arrives on standard input).

Only a short, safe environment is passed on. Add your own `KEY=value` lines in Settings ▸ Shell.

### Saved scripts and history

Files in `.mdedit/scripts` inside your folder are listed first when you open the box, followed by your recent commands. ↑ and ↓ choose from the list. The **first time** a script runs, and again whenever it changes, MDEdit shows its text and asks you to approve it. Recent commands are kept in `.mdedit/history` (the number is set in Settings, and 0 turns history off). That file holds whatever you type, so keep secrets out of commands.

### Safety

Commands run inside the same sandbox as MDEdit: they can read and change the folder you opened and nothing else. A command is stopped after the time limit set in Settings (30 seconds by default), and anything over 5 MB of output is cut off.

## Settings

Open them with **MDEdit ▸ Settings…** (⌘,).

- **Appearance:** light, dark, or follow the system.
- **Editor:** the font and size, the line width in characters, larger heading sizes, and whether distraction free uses the full screen.
- **Viewer:** the Serif or Sans template, the text size, the line width, and whether remote pictures and stylesheets are loaded.
- **Shell:** the on/off switch, the shell program (`/bin/sh` by default), the search path, the time limit, how much history to keep, and extra environment variables.

## The command palette

⇧⌘P opens a list of every command in the menus. Type to narrow it, ↑ ↓ to choose, Return to run, Esc to close. It also holds a few commands that are not in a menu, such as Reveal Folder in Finder and Collapse All Folders.

## Your files and privacy

- Notes are saved as ordinary files, in the folder you chose. Nothing else is stored in that folder except `.mdedit` if you use shell commands.
- MDEdit works inside the macOS App Sandbox. It can only open the folders you pick, and it keeps access to them with a bookmark so you do not have to choose them again.
- Nothing is sent anywhere. The only network use is a picture on the web, and only if you allow it in Settings.
- If a note was changed elsewhere while you had unsaved edits, MDEdit saves your edits to a copy beside it rather than losing them.

## Troubleshooting

**A note does not appear in the binder.** Only the opened folder is shown. Files that start with a dot are hidden. Use **Reveal Folder in Finder** (in the command palette) to check the files are there.

**⌘R says shell commands are off.** Turn them on in Settings ▸ Shell.

**A shell command cannot find a program or a file.** Commands run in a sandbox with a short PATH. Use full paths, or set the search path in Settings ▸ Shell. Files outside the opened folder cannot be read.

**A shortcut does nothing.** Some shortcuts only work while a note is open, or only in Write view. A greyed menu item is not available right now.

**The first launch is blocked on another Mac.** If the app was not notarised, macOS asks you to confirm: right-click the app and choose Open once.

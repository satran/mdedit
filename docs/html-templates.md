# HTML templates in MDEdit: a guide for agents

MDEdit can fill an HTML file in from the notes in the folder it has open. You write an ordinary `.html` file with a few template tags; the person presses **Render** and sees a page built from their notes (an index, a task list, a summary of every note, today's agenda). This file tells you how to write one that works the first time, and how to test it yourself.

You write the template as a file on disk, in the person's opened folder. (The Review tab only accepts `.md`, `.markdown` and `.txt`, so it cannot carry an HTML file.) You can **test it yourself with the `render_template` tool** (see "Testing a template"); the person still presses Render in the app.

## How it works

- A file is a template when its extension is `.html` or `.htm` **and** its text contains `{%` or `{{`. MDEdit then shows a bar, "This page uses template tags.", with a **Render** button. Until Render is pressed the file is shown as plain HTML. Nothing renders by itself, not when a note changes and not when the file is edited; the person presses Render again.
- The first time anyone presses Render in the app, a sheet warns once that a rendered page can read every note in the folder. After that it just renders.
- Rendering only **reads**. A template cannot write, rename or delete anything, run a program, run JavaScript or make a network request.
- Everything is read from the opened folder, as saved on disk (unsaved edits in the editor are not seen).
- A link on the rendered page that points at the page itself with a query (`<a href="?due=overdue">`) renders it again with those values in `query` (see "Query"). That is the way to make a page interactive without JavaScript.

## The language

It looks like Django templates, and it is a small subset. Anything outside what is listed here is a **syntax error with a line number**. There are no arithmetic, no ranges, no method calls, no macros (use `include` with values), no `lower`, `upper`, `join` or `safe` filters.

### Printing a value

```
{{ value }}
{{ value|filter }}
{{ value|filter|filter:argument }}
```

Text is HTML-escaped when printed, so note text can never become markup. Numbers print as digits and an empty value prints nothing. A list or a record cannot be printed (that is an error naming the variable).

| Filter | Does |
|---|---|
| `default:x` | Uses `x` (a quoted text, a number or a variable) when the value is empty or is empty text; otherwise leaves the value alone. |
| `urlencode` | Percent-encodes everything except letters, digits, `-._~` and `/`. Use it for every address you build from a value: `href="{{ f.path\|urlencode }}"`. Text only. |
| `markdown` | Turns Markdown text into safe HTML; the only way text becomes markup. Text only. `[[Note]]` and `[[Note\|alias]]` become links to the note's file (plain text when no such note exists; code is left alone). `markdown:folder` makes relative links and pictures in the text relative to that folder, e.g. `{{ text\|markdown:f.folder }}`; a link that would leave the opened folder loses its target. |
| `length` | The number of characters of text, items of a list or keys of a record (0 when empty). |
| `days_until` / `days_since` | Whole calendar days from today to the date / from the date to today (negative when it is the other way round). Empty when the value is not a date. |
| `date:"pattern"` | A date shown with an ICU pattern: `{{ t.attrs.due\|date:"EEE d MMM" }}` is `Mon 2 Nov`. Only letters, digits, spaces and `- / . , :`, up to 40 characters. Empty when the value is not a date. |
| `week` | The ISO week of a date as `2026-W45`, so weeks compare across years. |

**Always write attributes in double quotes**: `href="{{ f.path|urlencode }}"`. Escaping cannot make an unquoted attribute safe.

### Values, names and dates

- A value is text, a number, a list, a record (a set of key/value pairs), markup (the result of `markdown`) or empty.
- A name is `[A-Za-z_][A-Za-z0-9_]*`. `f.path` looks up a key in a record; a missing key is empty. No calls.
- Literals: `"text in double quotes"` (only `\"` and `\\` are escapes) and whole numbers of at most 9 digits, negative ones too (no `true`/`false`).
- An unset variable is empty. Names that cannot be used for your own variables: `for in empty endfor if elif else endif and or not files section meta tasks data include sort where groupby verbatim endverbatim as reverse limit recursive pages match with today now query`. A name given to `as` cannot end in `_error`.
- **`today`** is the date of the render, `2026-11-06`; **`now`** is `2026-11-06 14:30`; both in the person's time zone. A date is text in the form `2026-11-06` (a time may follow: `2026-11-06 14:30`).
- A tag or `{{ }}` cannot span a line break. `{# a comment #}` can. An HTML comment `<!-- ... -->` is copied to the page as it is, **braces inside it are not run**. To write braces as text, use `{% verbatim %}{{ like this }}{% endverbatim %}`.

### Conditions and loops

```
{% for x in items %}...{% empty %}shown when the list is empty or not set{% endfor %}

{% if a == b %}...{% elif c %}...{% else %}...{% endif %}
```

A condition is values joined by `==`, `!=`, `<`, `<=`, `>`, `>=`, `in`, and `and`, `or`, `not` (`not` binds tightest, then `and`, then `or`; no brackets). A value may carry filters: `{% if t.attrs.due|days_until < 0 and not t.done %}`.

- `==` and `!=` compare any two values; different types are never equal; an empty value and empty text are the same. So `t.done == ""` is true for a task that is not done.
- `<`, `<=`, `>`, `>=` compare two numbers or two texts (dates `yyyy-MM-dd` compare correctly as text: `t.attrs.due < today`). Anything else, an empty value included, is false.
- `a in b`: `b` is a text (`a` is a non-empty part of it), a list (`a` is one of its items) or a record (`a` is one of its keys).
- A single value is true unless it is empty, `0`, empty text or an empty list.
- `for` only loops over a list variable. **Nesting limits:** loops 3 deep; all blocks (`for`, `if`) together 10 deep; 4,000 template parts in all; 64 KB of template. The loop variable is restored after `endfor`.

### Reading the folder

All paths are relative to the **opened folder** (the folder the person opened in MDEdit), not to the template file. `""` is the opened folder itself. A path can be a quoted text or a variable.

**`files`** lists a folder:

```
{% files "journal" as items %}
{% files "journal" sort "modified" reverse limit 10 as items %}
{% files "vaults/x" recursive match "2026-11-06-*.md" as notes %}
{% files "reports" pages as pages %}
```

Clauses come in this order: `recursive`, `pages`, `match pattern`, `sort`, `reverse`, `limit`, `as`.

- Not recursive (the default): one level, notes (`.md`, `.markdown`, `.txt`) and folders. `recursive`: every level below, to 12 deep, **files only**.
- `pages` also lists `.html` and `.htm` files, as kind `page` (their title is the page's `<title>`). Without it HTML files are left out.
- `match` is a pattern for the file name: `*` is any run of characters, `?` is one character, case ignored. At most 100 characters.
- `sort "name"` (the default): folders first, then by natural order (in a recursive list, by path). `sort "modified"`: oldest first. `reverse` flips either. `limit` is a number or a variable; at most 500 items, which is also the most you get without it.
- Hidden entries, packages and links that leave the folder are left out.

Each item is a record: `name` (with extension), `path` (relative to the opened folder), `folder` (the folder part of `path`, `""` at the top), `ext` (lower case), `kind` (`"note"`, `"folder"` or `"page"`), `title` (a note's first heading, else its name without extension; a page's `<title>`; a folder's name), `modified` (`yyyy-MM-dd`, local time) and `size` (bytes, 0 for a folder).

**`section`** reads the text under a heading of a note:

```
{% section f.path "Summary" as text %}
{{ text|markdown }}
```

From the line after the first heading whose title matches exactly (closing `#` marks ignored), up to the next heading of the same or a higher level, blank lines trimmed. A missing heading gives empty text and no error. A note over 64 KB is not read.

**`meta`** reads a note's properties block, the `key: value` lines between `---` lines at the top of the note:

```
{% meta f.path as m %}
{{ m.author|default:"unknown" }}  {% for t in m.tags %}#{{ t }} {% endfor %}  {% if m.draft %}DRAFT{% endif %}
```

Text, `[a, b]` or `- a` lists, and `true`/`false` are understood. `true` is the text "true" and `false` is empty, so `{% if m.draft %}` works. A missing key is empty. Only the top 16 KB of the note is read.

**`tasks`** reads the task lines of a note (`- [ ] text`, `- [x] text`, also with `*` or `+`; lines inside a code fence and the properties block are skipped):

```
{% tasks "agenda/tasks.md" as ts %}
{% for t in ts %}{{ t.text }} {{ t.attrs.due }}{% endfor %}
```

Each task is a record: `done` (`"true"` or empty), `text` (the line without its attributes), `raw` (the whole line after the box), `line` (the line number in the file), `indent`, `is_sub` (`"true"` when indented), `attrs` (a record of the `@name(value)` attributes: `@due(2026-11-10)` is `t.attrs.due`) and `context` (the lines directly below the task that are indented deeper and are not tasks, up to a blank line, joined with newlines; empty when there are none). Up to 500 tasks, from a note of up to 256 KB. Sub-tasks are records of their own, in file order.

**`data`** reads a JSON or YAML file (`.json`, `.yaml`, `.yml`) from a visible folder:

```
{% data "agenda/data/2026-11-06.json" as day %}
{% for e in day.events %}{{ e.time }} {{ e.title }}{% endfor %}
```

JSON is read in full: objects are records, arrays are lists, strings are text, whole numbers are numbers, `true` is the text "true", `false` and `null` are empty, other numbers are their text. YAML is only the same small subset as a note's properties block (flat `key: value`, `[a, b]`, `- a`, `true`/`false`): use JSON for anything nested. Up to 256 KB, 50,000 values and 12 levels.

**Errors from the read tags.** `files`, `section`, `meta`, `tasks` and `data` never stop the page for one bad file. They set an empty result and a variable named after yours plus `_error` (`items_error`, `text_error`, `m_error`, `ts_error`, `day_error`): empty when it worked, otherwise one of `not available` (the path is refused or missing), `too large`, `not text`, `unreadable`, `read budget used`. Test it with `{% if text_error %}`.

### Lists as views

These make a new list from a list; they never make one longer.

```
{% sort ts by "attrs.due" as byDate %}
{% sort ts by "attrs.priority" "attrs.due" desc missing first as x %}
{% where ts done == "" as open %}
{% where ts attrs.due < today as late %}
{% where ts not done as open %}
{% where ts is_sub as subs %}
{% groupby open by "attrs.priority" as groups %}
{% for g in groups %}{{ g.key|default:"no priority" }} ({{ g.count }}): {% for t in g.items %}{{ t.text }}; {% endfor %}{% endfor %}
```

- `sort list by "key" ...`: keys are quoted dotted paths into each item (`"attrs.due"`); up to 4; each may be followed by `desc` (or `asc`). Numbers sort before texts; texts in natural order. **Missing values (absent, empty or empty text) go last** unless you write `missing first`. The sort is stable.
- `where list key`, `where list not key`, `where list key OP value`: keep the items for which the value at `key` (a bare dotted path, no quotes) is true, not true, or compares as given (`==`, `!=`, `<`, `<=`, `>`, `>=`, `in`). The value may be a literal, a variable or carry filters.
- `groupby list by "key"` gives a list of groups in order of first appearance; each is a record with `key` (empty text when the item has no value), `items` and `count`. Sort the groups afterwards with `sort groups by "key"`.

### Include

```
{% include "templates/_task-row.html" %}
{% include "templates/_task-row.html" with t=item showdate=true_or_any_value %}
```

Runs another `.html` or `.htm` file of the opened folder (a visible one) in the same place, and sees the variables of the caller. `with name=value` (up to 8) sets names for the length of the include; a value is a literal, a variable or carries filters. Includes nest 3 deep and at most 50 run in one render. A missing or unreadable file is an error naming it; an error inside an included file names the file.

### Query

A link on the page to the page itself with a query renders it again with those values: `<a href="?due=overdue&priority=A">Overdue, priority A</a>`. In the template the values are `query.due`, `query.priority`; a missing one is empty, so `{{ query.due|default:"all" }}` works. A click on `<a href="?">` clears them. Values are text, up to 20 keys of plain names and 256 characters each, escaped like any text. Pressing **Show source**, or opening another file, forgets them. Each click is one render (up to 2 seconds).

## What is blocked, and why a render can fail

A template is treated as hostile, so these are enforced, not suggestions:

- **Reads only inside the opened folder.** Absolute paths, `~`, `..`, links that leave the folder, hidden files and folders (`.mdedit`, `.git`) and a visible name that links to a hidden file are all refused (`not available`). The page's own pictures and stylesheets cannot read hidden files either. `data` and `include` follow the same rules as notes.
- **No network.** Remote images, stylesheets, fonts, frames and scripts never load, even if the person allowed remote pictures in Settings. After rendering, MDEdit also **refuses to show a page** that contains: `<iframe>`, `<frame>`, `<frameset>`, `<object>`, `<embed>`, `<applet>`, `<base>`, `<meta http-equiv>`, a `ping` attribute, a `formaction` attribute, or any `<link>` other than a relative stylesheet (`<link rel="stylesheet" href="style.css">`). So no `preconnect`, `dns-prefetch`, `prefetch`, `preload` or `icon` links. `<meta charset>` and `<meta name="viewport">` are fine.
- **No JavaScript.** Scripts never run. Do not add `<script>`.
- **Forms do nothing.** Do not rely on `<form>`; use links with queries.
- **Links:** a link to a note in the folder opens it in MDEdit. A link to a web or mail address asks the person first and shows the whole address (it may carry text from their notes), **unless the person has listed that host as trusted** for this folder (command palette: "Trusted Addresses for Templates…"; https only; a template cannot change the list). `javascript:`, `data:` and other schemes do nothing.
- **Limits** (a render stops with an error page): 2 s; 200,000 steps; 2 MB of output; 10,000 directory entries read; 8 MB read from disk; 500 items per list. A note over its cap, or a read after the 8 MB budget, gives an empty result with `_error`, not a failed page.

## Writing a good template

1. Put your CSS in a `<style>` element or link a stylesheet in the folder with a **relative** path (`<link rel="stylesheet" href="css/style.css">`). Inline styles work. Remote fonts do not.
2. Link to notes with `href="{{ f.path|urlencode }}"`. Paths mean the opened folder wherever the template file lives. A link to another page of the folder works the same way.
3. Pictures work from the folder with relative paths (`<img src="img/logo.png">`). For pictures and links *inside text from a note*, use `markdown:f.folder` so they are relative to the note's own folder.
4. Show folders only if you want them: `{% if f.kind == "note" %}`. Listing `""` includes top-level folders.
5. Keep loops simple. A double loop over 500 items with `section` inside can hit the step budget; sort, filter and group first, then loop once.
6. Handle emptiness: use `{% empty %}` and `default:"..."`.
7. To put literal braces on the page, use `{% verbatim %}` or an HTML comment.

## Testing a template

The **`render_template`** tool (Agents on in Settings, a folder open in the front window) renders a template with the same engine, limits and output checks as the Render button, and returns the page or the error. Arguments: `path` (the `.html` file, relative to the folder), `query` (optional, `due=overdue&priority=A`) and `today` (optional, `2026-11-06`, to render as if it were that day). The result is `{"ok": true, "html": "...", "bytes": n, "truncated": false}` (the page is cut at 300 KB for you), or `{"ok": false, "error": {"title", "message", "line"}}` with the line counted from the top of the file. It reads the file as saved on disk, writes nothing and opens nothing. There is no command-line renderer: the app starts no program and has no URL scheme.

Re-read the tags against this guide before you ask: every read tag has `as name`, every block is closed, attributes are quoted, filters are from the table. "Page not shown" means the output held a refused tag. "Waiting for a blocked file read" is a stuck disk read; wait or cancel.

## Examples

A journal index, newest first, with each note's Summary:

```html
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Journal</title>
<style>
  body { font: 16px -apple-system, sans-serif; max-width: 40em; margin: 2em auto; line-height: 1.5; }
  .meta { color: #888; font-size: 13px; }
</style>
</head>
<body>
<h1>Journal</h1>
{% files "journal" sort "modified" reverse limit 10 as items %}
{% for f in items %}
  {% if f.kind == "note" %}
  <article>
    <h2><a href="{{ f.path|urlencode }}">{{ f.title }}</a></h2>
    <p class="meta">{{ f.modified|date:"EEE d MMM" }}</p>
    {% section f.path "Summary" as summary %}
    {% if summary %}{{ summary|markdown:f.folder }}{% endif %}
  </article>
  {% endif %}
{% empty %}
  <p>No entries yet.</p>
{% endfor %}
</body>
</html>
```

An agenda of open tasks with filters in the URL:

```html
<p>
  <a href="?">All</a> · <a href="?due=overdue">Overdue</a> · <a href="?due=today">Today</a> · <a href="?priority=A">Priority A</a>
</p>
{% tasks "agenda/tasks.md" as ts %}
{% where ts done == "" as open %}
{% if query.due == "overdue" %}{% where open attrs.due < today as open %}{% endif %}
{% if query.due == "today" %}{% where open attrs.due == today as open %}{% endif %}
{% if query.priority %}{% where open attrs.priority == query.priority as open %}{% endif %}
{% sort open by "attrs.priority" "attrs.due" as open %}
<h2>{{ open|length }} open</h2>
<ul>
{% for t in open %}
  <li>
    {{ t.text }}
    {% if t.attrs.due %}
      <small>{{ t.attrs.due|date:"EEE d MMM" }}{% if t.attrs.due|days_until < 0 %} · {{ t.attrs.due|days_since }}d late{% endif %}</small>
    {% endif %}
  </li>
{% empty %}
  <li>Nothing to do.</li>
{% endfor %}
</ul>
```

The day's agenda from a data file, with today's meeting notes:

```html
{% data "agenda/data/day.json" as day %}
<h1>{{ today|date:"EEEE d MMMM" }}</h1>
{% for e in day.events %}<p>{{ e.time }} {{ e.title }}</p>{% endfor %}
{% files "meetings" recursive match "2026-11-06-*.md" as notes %}
{% for n in notes %}<a href="{{ n.path|urlencode }}">{{ n.title }}</a> {% endfor %}
```

Drafts and tags from each note's properties block:

```html
{% files "notes" as items %}
<ul>
{% for f in items %}
  {% if f.kind == "note" %}
    {% meta f.path as m %}
    <li>
      <a href="{{ f.path|urlencode }}">{{ f.title }}</a>
      {% if m.draft %}<strong>draft</strong>{% endif %}
      {% for t in m.tags %}<small>#{{ t }}</small> {% endfor %}
    </li>
  {% endif %}
{% endfor %}
</ul>
```

A working sample is in `plan/006-html-templates/example/`. The full design and the reasons for each rule are in `plan/006-html-templates/PLAN.md`.

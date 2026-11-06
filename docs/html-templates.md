# HTML templates in MDEdit: a guide for agents

MDEdit can fill an HTML file in from the notes in the folder it has open. You write an ordinary `.html` file with a few template tags; the person presses **Render** and sees a page built from their notes (an index, a summary of every note, a list of drafts). This file tells you how to write one that works the first time.

You write the template as a file on disk, in the person's opened folder. (The Review tab only accepts `.md`, `.markdown` and `.txt`, so it cannot carry an HTML file.) You cannot render it yourself: the person does that in the app. Errors appear in a bar above the page with a line number, so write carefully and keep templates small.

## How it works

- A file is a template when its extension is `.html` or `.htm` **and** its text contains `{%` or `{{`. MDEdit then shows a bar, "This page uses template tags.", with a **Render** button. Until Render is pressed the file is shown as plain HTML. Nothing renders by itself, not when a note changes and not when the file is edited; the person presses Render again.
- The first time anyone presses Render in the app, a sheet warns once that a rendered page can read every note in the folder. After that it just renders.
- Rendering only **reads**. A template cannot write, rename or delete anything, run a program, run JavaScript or make a network request.
- Everything is read from the opened folder, as saved on disk (unsaved edits in the editor are not seen).

## The language

It looks like Django templates, and it is a small subset. Anything outside what is listed here is a **syntax error with a line number**. There is no `elif`, `and`, `or`, `not`, `include`, `extends`, `block`, `now`, no arithmetic, no ranges, no method calls and no `lower`, `upper`, `join` or `safe` filters.

### Printing a value

```
{{ value }}
{{ value|filter }}
{{ value|filter|filter:"argument" }}
```

Text is HTML-escaped when printed, so note text can never become markup. Numbers print as digits and an empty value prints nothing. A list or a record cannot be printed (that is an error naming the variable).

Filters (exactly these three):

| Filter | Does |
|---|---|
| `default:"text"` | Uses the text when the value is empty or is empty text; otherwise leaves the value alone. |
| `urlencode` | Percent-encodes everything except letters, digits, `-._~` and `/`. Use it for every address you build from a value: `href="{{ f.path\|urlencode }}"`. Text only. |
| `markdown` | Turns Markdown text into safe HTML. This is the only way text becomes markup. Text only. |

**Always write attributes in double quotes**: `href="{{ f.path|urlencode }}"`. Escaping cannot make an unquoted attribute safe.

### Values and names

- A value is text, a number, a list, a record (a set of key/value pairs), markup (the result of `markdown`) or empty.
- A name is `[A-Za-z_][A-Za-z0-9_]*`. `f.path` looks up a key in a record; a missing key is empty. No calls.
- Literals: `"text in double quotes"` (only `\"` and `\\` are escapes) and whole numbers of at most 9 digits (no negatives, no `true`/`false`).
- An unset variable is empty. Reserved words that cannot be names: `for in empty endfor if else endif files section meta as sort reverse limit`.
- A name given to `as` cannot end in `_error`.
- A tag or `{{ }}` cannot span a line break. `{# a comment #}` can.

### Loops and conditions

```
{% for x in items %}
  ...
{% empty %}
  shown when the list is empty or not set
{% endfor %}

{% if a == b %}...{% else %}...{% endif %}
{% if a != b %}...{% endif %}
{% if value %}...{% endif %}
```

- `for` only loops over a list variable (never a call or a range). Loops nest at most 2 deep, all blocks together at most 10. The loop variable is restored after `endfor`.
- `if` takes one value, or two values joined by `==` or `!=`. A value is false when it is empty, `0`, empty text or an empty list; everything else is true. Values of different types are never equal.

### Reading the folder

All paths are relative to the **opened folder** (the folder the person opened in MDEdit), not to the template file. `""` is the opened folder itself.

**`files`** lists a folder, one level, not recursive:

```
{% files "journal" as items %}
{% files "journal" sort "modified" reverse limit 10 as items %}
```

Clauses come in this order: `sort`, `reverse`, `limit`, `as`. `sort` is `"name"` (the default: folders first, then notes, natural order) or `"modified"` (oldest first; add `reverse` for newest first). `limit` is a whole number (or a number variable), at most 100; without it you still get at most 100. Only notes (`.md`, `.markdown`, `.txt`) and folders are listed; HTML files, hidden entries and packages are left out.

Each item is a record:

| Field | Value |
|---|---|
| `name` | File or folder name, with extension |
| `path` | Path relative to the opened folder (use it for links and for `section`/`meta`) |
| `kind` | `"note"` or `"folder"` |
| `title` | A note's first heading (else its name without extension); a folder's name |
| `modified` | `yyyy-MM-dd`, local time |
| `size` | Bytes (0 for a folder) |

**`section`** reads the text under a heading of a note:

```
{% section f.path "Summary" as text %}
{{ text|markdown }}
```

It returns the text from the line after the first heading whose title matches exactly (closing `#` marks ignored), up to the next heading of the same or a higher level, with blank lines trimmed. A missing heading gives empty text and no error. A note over 64 KB is not read.

**`meta`** reads a note's properties block, the `key: value` lines between `---` lines at the top of the note:

```
{% meta f.path as m %}
{{ m.author|default:"unknown" }}
{% for t in m.tags %}#{{ t }} {% endfor %}
{% if m.draft %}DRAFT{% endif %}
```

Text, `[a, b]` or `- a` lists, and `true`/`false` are understood. A list is a list of text. `true` is the text "true" and `false` is empty, so `{% if m.draft %}` works. A missing key, or a note without a block, is empty. Only the top 16 KB of the note is read. Values can drive other tags: `{% meta "config.md" as c %}{% files c.folder as items %}`.

### Errors from the read tags

`files`, `section` and `meta` never stop the page for one bad note. They set an empty result and a variable named after yours plus `_error` (`items_error`, `text_error`, `m_error`): empty when it worked, otherwise one of `not available` (the path is refused or missing), `too large`, `not text`, `unreadable`, `read budget used`. Test it with `{% if text_error %}`.

## What is blocked, and why a render can fail

A template is treated as hostile, so these are enforced, not suggestions:

- **Reads only inside the opened folder.** Absolute paths, `~`, `..`, links that leave the folder, hidden files and folders (`.mdedit`, `.git`) and a visible name that links to a hidden file are all refused (`not available`). The page's own pictures and stylesheets cannot read hidden files either.
- **No network.** Remote images, stylesheets, fonts, frames and scripts never load, even if the person allowed remote pictures in Settings. After rendering, MDEdit also **refuses to show a page** that contains: `<iframe>`, `<frame>`, `<frameset>`, `<object>`, `<embed>`, `<applet>`, `<base>`, `<meta http-equiv>`, a `ping` attribute, a `formaction` attribute, or any `<link>` other than a relative stylesheet (`<link rel="stylesheet" href="style.css">`). So no `preconnect`, `dns-prefetch`, `prefetch`, `preload` or `icon` links. `<meta charset>` and `<meta name="viewport">` are fine.
- **No JavaScript.** Scripts never run. Do not add `<script>`.
- **Forms do nothing.** Do not rely on `<form>`.
- **Links:** a link to a note in the folder opens it in MDEdit. A link to a web or mail address asks the person first and shows the whole address; it may carry text from their notes. `javascript:`, `data:` and other schemes do nothing.
- **Limits** (a render stops with an error page): template 64 KB; 2,000 template parts; 200,000 steps; 2 s; 2 MB of output; 10,000 directory entries read; 8 MB read from disk; at most 100 items per list. A `section` note over 64 KB and a read after the 8 MB budget give an empty result with `_error`, not a failed page.

## Writing a good template

1. Put your CSS in a `<style>` element or link a stylesheet in the folder with a **relative** path (`<link rel="stylesheet" href="css/style.css">`). Inline styles work. Remote fonts do not.
2. Link to notes with `href="{{ f.path|urlencode }}"`. Paths mean the opened folder wherever the template file lives.
3. Pictures work from the folder with relative paths (`<img src="img/logo.png">`). A picture or link *inside text from a note* (shown with `markdown`) resolves against the opened folder too, not that note's own folder, so a note in a subfolder may show a broken picture.
4. Show folders only if you want them: `{% if f.kind == "note" %}`. Listing `""` includes top-level folders.
5. Keep loops simple. Two nested `for` is the limit, and a double loop over 100 items with `section` inside can hit the step budget.
6. Handle emptiness: use `{% empty %}` and `default:"..."`.
7. Do not put `{{` or `{%` in the page for another purpose (Vue, Handlebars): they will be parsed and fail. Write them as plain text another way, for example `&#123;&#123;`.

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
    <p class="meta">{{ f.modified }}</p>
    {% section f.path "Summary" as summary %}
    {% if summary %}{{ summary|markdown }}{% endif %}
  </article>
  {% endif %}
{% empty %}
  <p>No entries yet.</p>
{% endfor %}
</body>
</html>
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

## Checking your work

- Re-read the tags against this guide: every tag has `as name`, every block is closed, attributes are quoted, no filter other than `default`, `urlencode` and `markdown`.
- Ask the person to press Render. A syntax or type error shows in the bar and on the page with the line number (counted from the top of the file). "Page not shown" means the output held a refused tag. "Waiting for a blocked file read" is a stuck disk read; wait or cancel.
- A working sample is in `plan/006-html-templates/example/`. The full design and the reasons for each rule are in `plan/006-html-templates/PLAN.md`.

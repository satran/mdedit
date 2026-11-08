# MDEdit website

One static page, no build step and no JavaScript. Open `index.html`, or serve the folder (`python3 -m http.server`) to see it with its images.

*   **Publish:** upload this folder as it is (GitHub Pages from `/website`, Netlify, any static host). The site must be served from the root of its domain, because the page links to `/img/...` and `/favicon.ico`.
*   **The domain:** `https://mdedit.ranjeev.in/` is written in `index.html` (canonical, `og:url`, `og:image`, the structured data), `sitemap.xml`, `robots.txt` and `llms.txt`. Change it in those five places if the site lives elsewhere.
*   **The download button:** it points at `https://github.com/satran/mdedit/releases/latest/download/MDEdit.dmg`. `make release` writes that fixed name next to the versioned one (`build/MDEdit.dmg`); attach it to each GitHub release and the button always gets the newest build.
*   **Screenshots:** `img/mdedit-light.png` and `img/mdedit-dark.png` are renders of the real window (1600 px wide); `img/og.png` is the 1200 by 628 share image cut from the light one. Replace them when the look changes.
*   **The text:** the questions at the bottom are also in the structured data at the top of `index.html`. Keep the two in step when you edit one.

# mdzip-pandoc

A [Pandoc](https://pandoc.org) reader and writer for **MDZip** (`.mdz`) files: Markdown documents packaged with their images in one ZIP archive. With it, Pandoc converts an `.mdz` to Word, EPUB, PDF, HTML and every other format it writes, and packages any document it reads as an `.mdz`.

```sh
pandoc -f mdz.lua guide.mdz -o guide.docx          # .mdz to Word
pandoc -f mdz.lua guide.mdz -s --embed-resources -o guide.html
pandoc notes.md -t mdz.lua -o notes.mdz             # Markdown and its images to .mdz
pandoc report.docx -t mdz.lua -o report.mdz         # Word to .mdz, images included
```

It's one Lua file, `mdz.lua`, used as a Pandoc [custom reader and writer](https://pandoc.org/custom-readers.html). It needs Pandoc 3 and the [mdzip-core-lua](https://github.com/mdzip-project/mdzip-core-lua) library.

## Setup

1. Put `mdz.lua` somewhere, and pass its path to `-f` or `-t` (or copy it into Pandoc's data directory under `custom/`).
2. Make mdzip-core-lua's `src` folder findable, in one of these ways:
   - set `MDZIP_LUA_PATH` to it, for example `MDZIP_LUA_PATH=/path/to/mdzip-core-lua/src`;
   - put the `mdzip-core-lua` folder next to `mdz.lua`, or next to the folder `mdz.lua` is in.

Tested with Pandoc 3.13 (Lua 5.4).

## Reading an `.mdz`

- Pandoc converts the archive's **entry point**, the main document the archive names (or `index.md`). Links to the archive's other documents stay links.
- In a **project-mode** archive, a collection of separate documents, only the entry point is converted, with a warning naming how many documents were left out. To convert another one, unpack it first or use the MDZip tools.
- **Images** are read from inside the archive, never from the web or from files next to the archive, and go into Pandoc's media bag. So Word, EPUB and PDF output include them, and HTML does with `--embed-resources` (or `--extract-media`). This covers Markdown images and `<img>` tags in raw HTML, including ones in a document in a subfolder.
- The archive's **manifest** fills in metadata the document doesn't set itself: `title`, `author`, `lang`, `description` and `keywords`.
- A damaged or invalid archive stops Pandoc with the MDZip error code, for example `ERR_ENTRYPOINT_MISSING` or `ERR_ZIP_INVALID`.

The Markdown is read as Pandoc's Markdown by default, which understands the most syntax. Add a switch to the format to change it:

| Switch | Effect |
|---|---|
| `-f mdz.lua+gfm` | Read GitHub-Flavored Markdown |
| `-f mdz.lua+commonmark` | Read CommonMark with Pandoc's extensions (`commonmark_x`) |
| `-f mdz.lua-raw_html` | Drop raw HTML |

Raw HTML in the archive passes through to HTML output, as it does with Pandoc's own Markdown reader. For an `.mdz` from someone you don't trust, use `-raw_html` or sanitize the HTML output: it can contain scripts.

## Writing an `.mdz`

- The document becomes `index.md`, in GitHub-Flavored Markdown by default (`-t mdz.lua+pandoc` writes Pandoc's Markdown, `+commonmark` CommonMark).
- Every image Pandoc can find is packaged under `images/`, keeping its file name, and the document's links are rewritten to match. That includes images on disk, images Pandoc read out of a Word or EPUB file, and `data:` URIs. An image used twice is stored once; two different images with the same name get `-2`, `-3` and so on.
- Web images (`https:`) stay links. An image that can't be found stays as written, with a warning.
- The manifest records the title, the first author, `lang`, `description` and `keywords` from the document's metadata. The title is also added as a heading when the document has no level-1 heading, since Markdown output doesn't keep metadata.
- Pandoc has to write to a file: use `-o name.mdz`.

The result passes `mdz validate`.

## GitHub Action

The repository is also a GitHub Action. It installs Pandoc (unless the runner already has it), downloads mdzip-core-lua and runs `mdz.lua`, on one file or a whole folder. For example, to turn an `.mdz` into a web page:

```yaml
- uses: actions/checkout@v5
- uses: mdzip-project/mdzip-pandoc@v0
  with:
    input: docs/guide.mdz
    output: site/guide.html
    args: --standalone --embed-resources
```

Or a folder of `.mdz` pages into a website, each page put into your own [Pandoc template](https://pandoc.org/MANUAL.html#templates):

```yaml
- uses: mdzip-project/mdzip-pandoc@v0
  with:
    input: pages
    output: _site
    args: --standalone --embed-resources --template=site/template.html --css=site/style.css
```

[mdzip-pages-example](https://github.com/mdzip-project/mdzip-pages-example) is a whole site built this way and published on GitHub Pages, with a sitemap, canonical addresses and Open Graph tags. Its [template](https://github.com/mdzip-project/mdzip-pages-example/blob/main/site/template.html) shows how to use `page-url`. With `--embed-resources`, mark the canonical link `data-external="1"`, or Pandoc tries to download the page and embed it.

| Input | Default | What it does |
|---|---|---|
| `input` | | The file to convert. An `.mdz` is read with `mdz.lua`; any other file Pandoc reads (`.md`, `.docx`, ...) can be packaged as an `.mdz`. Or a folder: every `.mdz` in it and its subfolders is converted. |
| `output` | | The file to write. Its extension picks the format: `.html`, `.docx`, `.epub`, `.pdf` (needs a PDF engine on the runner), or `.mdz`. When `input` is a folder, the folder to write to, with the same subfolders. Missing folders are created. |
| `extension` | `html` | When `input` is a folder, the format to convert each `.mdz` to, as a file extension (`html`, `docx`, `epub`, ...). |
| `site-url` | | When a folder is converted to HTML: the address it's published at, such as `https://you.github.io/repo/`. The action then writes `sitemap.xml` (each page's address, with its last-changed date when there's git history) and `robots.txt`, and gives each page `page-url` (its full address) and `site-url` for its template. A top-level `404.mdz` is left out of the sitemap and gets no `page-url`. |
| `images` | `files` | For HTML made from an `.mdz`: `files` writes each picture once to an `images/` folder (next to the page, or at the top of `output` for a folder), named by its contents, and points the pages at it. `embed` leaves pictures to Pandoc: add `--embed-resources` to build them into each page. |
| `args` | | Extra Pandoc options, such as `--standalone --embed-resources` for self-contained HTML pages, `--template`, `--css` or `--toc`. They're split on spaces, so a value can't contain one. |
| `pandoc-version` | | Pandoc to install, 3.0 or later. Empty uses the runner's Pandoc if it has one, otherwise installs 3.13, the version this is tested with. |
| `core-lua-version` | `v0.1.0` | The mdzip-core-lua release to use. |

The `output` output is the path written. One of `input` and `output` must be an `.mdz`.

In HTML output, links between `.mdz` files become links between the pages made from them: `guide.mdz#install` becomes `guide.html#install`. The action does this with [`mdz-links.lua`](mdz-links.lua), a Pandoc filter you can also use on its own (`--lua-filter mdz-links.lua`). Links in raw HTML (`<a href="...">`) aren't changed.

Pictures in HTML output are files, not built into the page: [`mdz-images.lua`](mdz-images.lua), another filter, writes each picture from the archive to `images/<hash>.<ext>` and points the page at it. A picture used on several pages is stored once, and browsers download it once. It covers Markdown images and the `<img align="...">` tags MDZip Studio writes, which Pandoc's own `--extract-media` leaves pointing at the old place. It marks the tags `data-external="1"`, so `--embed-resources` still builds the style sheet into each page but leaves the pictures as files. On its own: `pandoc -f mdz.lua --lua-filter mdz-images.lua guide.mdz -s -o site/guide.html` writes `site/images/`.

Pandoc is installed with the official [`pandoc/actions/setup`](https://github.com/pandoc/actions), whose Linux install is x64 only; on a runner it doesn't support, install Pandoc in an earlier step. To check archives before converting them, add [setup-mdz](https://github.com/mdzip-project/setup-mdz) and run `mdz validate`.

## Development

To try it by hand, follow the test script in [TESTING.md](TESTING.md). The automated tests:

```sh
PANDOC=pandoc pandoc lua tests/run.lua
```

The tests run real `pandoc` commands with `mdz.lua` and check the results with mdzip-core-lua: reading (metadata, images into Word and HTML, raw HTML images, switches, the spec's fixture archives and their error codes), writing (images, metadata, `mdz validate`), Word to `.mdz`, and an `.mdz` to `.mdz` round trip. They expect mdzip-core-lua next to this repository (`../mdzip-core-lua`), or `MDZIP_LUA_PATH`.

## What's left to do

- Bundle mdzip-core-lua into a release download, so `mdz.lua` works without a separate checkout. For now it uses a local copy.
- CI for the Lua tests (the GitHub Action has its own test workflow).
- Converting a document other than the entry point (an option naming it), and project-mode archives as a whole.
- Packaging local Markdown files the document links to, not only images.

## License

Apache License 2.0. See [LICENSE](LICENSE).

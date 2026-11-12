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

The repository is also a GitHub Action that converts one file in a workflow. It installs Pandoc (unless the runner already has it), downloads mdzip-core-lua and runs `mdz.lua`. For example, to turn an `.mdz` into a web page:

```yaml
- uses: actions/checkout@v5
- uses: mdzip-project/mdzip-pandoc@v0
  with:
    input: docs/guide.mdz
    output: site/guide.html
    args: --standalone --embed-resources
```

| Input | Default | What it does |
|---|---|---|
| `input` | | The file to convert. An `.mdz` is read with `mdz.lua`; any other file Pandoc reads (`.md`, `.docx`, ...) can be packaged as an `.mdz`. |
| `output` | | The file to write. Its extension picks the format: `.html`, `.docx`, `.epub`, `.pdf` (needs a PDF engine on the runner), or `.mdz`. Missing folders are created. |
| `args` | | Extra Pandoc options, such as `--standalone --embed-resources` for one self-contained HTML file, `--toc`, or `--extract-media=site/media` to keep images as separate files. |
| `pandoc-version` | | Pandoc to install, 3.0 or later. Empty uses the runner's Pandoc if it has one, otherwise installs 3.13, the version this is tested with. |
| `core-lua-version` | `v0.1.0` | The mdzip-core-lua release to use. |

The `output` output is the path written. One of `input` and `output` must be an `.mdz`. Pandoc is installed with the official [`pandoc/actions/setup`](https://github.com/pandoc/actions), whose Linux install is x64 only; on a runner it doesn't support, install Pandoc in an earlier step. To check an archive before converting it, add [setup-mdz](https://github.com/mdzip-project/setup-mdz) and run `mdz validate`.

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

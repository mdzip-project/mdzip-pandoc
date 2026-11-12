# Changelog

## [0.2.0] - 2026-11-12

- GitHub Action: `input` can be a folder. Every `.mdz` in it and its
  subfolders is converted into `output`, keeping the subfolders, to the
  format named by the new `extension` input (`html` by default).
- `mdz-links.lua`, a Pandoc filter: in HTML output, links to other `.mdz`
  files point to the pages made from them (`guide.mdz#install` becomes
  `guide.html#install`). The action applies it whenever it reads an `.mdz`.

## [0.1.0] - 2026-11-12

First version: `mdz.lua`, a Pandoc 3 custom reader and writer on mdzip-core-lua.

- Reading converts the entry point, loads its images (Markdown and raw HTML)
  from the archive into the media bag, and fills in metadata from the manifest.
  Project-mode archives convert their entry point with a warning. Errors carry
  MDZip error codes. Switches: `+gfm`, `+commonmark`, `-raw_html`.
- Writing packages the document as `index.md` (GFM by default; `+pandoc`,
  `+commonmark`) with every image Pandoc can find under `images/`, and records
  title, author, language, description and keywords in the manifest.
- Writing without `-o` stops with a message instead of printing the ZIP to
  the terminal.
- GitHub Action (`action.yml`): converts one file to or from `.mdz` in a
  workflow. Installs Pandoc if needed (official `pandoc/actions/setup`),
  downloads a pinned mdzip-core-lua release, and runs `mdz.lua`.

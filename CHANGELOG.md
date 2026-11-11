# Changelog

## [Unreleased] - 0.1.0

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

# Test script: mdzip-pandoc

> **Testing before a release?** The release download doesn't exist yet. Ask
> for the `release-download` file from the latest
> [Tests run](https://github.com/mdzip-project/mdzip-pandoc/actions/workflows/tests.yml)
> (it's a ZIP holding the ZIP), or, in a copy of this repository with
> mdzip-core-lua next to it, run `pandoc lua tools/bundle.lua`, which writes
> it to `dist/`. Then follow the setup from step 4.

This walks you through trying mdzip-pandoc by hand. It takes about 30
minutes. You'll type commands into a terminal, but you don't need to write
code.

[Pandoc](https://pandoc.org) converts documents between formats. mdzip-pandoc
adds MDZip (`.mdz`), a Markdown document packaged with its images in one ZIP
file, and does two jobs:

- **Reading:** turns an `.mdz` into Word, HTML, EPUB and the other formats
  Pandoc writes, with the pictures included.
- **Writing:** packages a Markdown or Word file, and the pictures it uses, as
  an `.mdz`.

Work through the tests in order. Tick each box when you see what the
**Expected** line describes. When you see something else, write down what
happened (see [Reporting problems](#reporting-problems)).

## Setup

1. Install Pandoc 3.0 or newer from
   [pandoc.org/installing](https://pandoc.org/installing.html). On Windows,
   `winget install JohnMacFarlane.Pandoc` works too; on a Mac with Homebrew,
   `brew install pandoc`.
2. Make an empty folder to work in, and open a terminal there (PowerShell on
   Windows, Terminal on a Mac).
3. Download the converter: open the
   [latest release](https://github.com/mdzip-project/mdzip-pandoc/releases/latest)
   and, under **Assets**, download `mdzip-pandoc-<version>.zip` (for example
   `mdzip-pandoc-0.6.0.zip`). Don't use the **Source code** downloads: they
   don't include the library the converter needs.
4. Unzip it into your folder, and rename the unzipped folder to exactly
   `mdzip-pandoc`, removing the version number. Inside it you should see
   `mdz.lua` and a folder called `mdzip-core-lua`, the library it uses to read
   and write `.mdz` files. Leave that folder where it is.
5. Download the four sample files into your folder:

   - [demo-single.mdz](https://mdzip.org/assets/demo-single.mdz): one document
     and one image
   - [demo-project.mdz](https://mdzip.org/assets/demo-project.mdz): several
     documents (index, format, tools)
   - [grid-tables.mdz](https://github.com/mdzip-project/mdzip-pandoc/raw/main/examples/grid-tables.mdz):
     a document with a table, carrying its own Word styles
   - [field-guide.mdz](https://github.com/mdzip-project/mdzip-spec/raw/main/examples/samples/field-guide.mdz):
     a short guide split over four files, a contents page and three chapters

6. Find a Word file (`.docx`) that **contains pictures** and copy it into your
   folder. Any of your own will do. The tests call it `report.docx`; use your
   own file name instead.

Your folder now holds `mdzip-pandoc`, the four sample files and your Word
file. Run every command from this folder.

On Windows you can type the commands as shown: Pandoc accepts `/` in paths.

## Part 1: Reading `.mdz` files

### 1.0 The download

Open the `mdzip-pandoc` folder.

- [ ] **Expected:** `mdz.lua`, `mdz-images.lua`, `mdz-links.lua`,
  `README.md`, `CHANGELOG.md`, `LICENSE` and a `mdzip-core-lua` folder.
- [ ] **Expected:** `mdzip-core-lua` holds `LICENSE`, `VERSION` (which names
  the library's version, such as `mdzip-core-lua 0.1.0`) and `src/mdzip` with
  about 16 `.lua` files.
- [ ] **Expected:** the top of `CHANGELOG.md` names the same version as the
  file you downloaded.

### 1.1 Pandoc is installed

```sh
pandoc --version
```

- [ ] **Expected:** the first line is `pandoc 3.` followed by more numbers.

### 1.2 The converter finds its library

```sh
pandoc -f mdzip-pandoc/mdz.lua demo-single.mdz -t gfm
```

- [ ] **Expected:** the sample document as Markdown, starting with
  `# Single-Document Sample`, with an image link to `images/specimen.png`.
- [ ] **Expected:** no error. You didn't install anything besides Pandoc: the
  library comes in the download. If you see `mdz.lua needs the mdzip-core-lua
  library`, check that the `mdzip-core-lua` folder is still inside
  `mdzip-pandoc` (setup step 4).

### 1.3 `.mdz` to Word

```sh
pandoc -f mdzip-pandoc/mdz.lua demo-single.mdz -o single.docx
```

- [ ] **Expected:** a new `single.docx` file and no messages.
- [ ] **Expected:** opened in Word (or LibreOffice, or Google Docs), it shows
  the document's text and its picture.
- [ ] **Optional:** in Word, **File > Info** shows the title
  `Single-Document Sample`. It comes from the archive's manifest.

### 1.4 `.mdz` to a web page

```sh
pandoc -f mdzip-pandoc/mdz.lua demo-single.mdz -s --embed-resources -o single.html
```

- [ ] **Expected:** a new `single.html`. Opened in a browser, it shows the
  text and the picture, and the browser tab reads `Single-Document Sample`.
- [ ] **Expected:** the page still shows its picture after you move
  `single.html` to another folder. `--embed-resources` puts the picture inside
  the page.

### 1.5 `.mdz` to an e-book (optional)

```sh
pandoc -f mdzip-pandoc/mdz.lua demo-single.mdz -o single.epub
```

- [ ] **Expected:** a new `single.epub`. Opened in an e-book reader (Apple
  Books, Calibre, or your browser with an EPUB add-on), it shows the text and
  the picture.

### 1.6 A file with several documents

```sh
pandoc -f mdzip-pandoc/mdz.lua demo-project.mdz -s --embed-resources -o project.html
```

- [ ] **Expected:** a warning ending in `converting only its entry point,
  index.md (2 other documents left out)`. This is how it should behave: the
  converter turns one document into one output file.
- [ ] **Expected:** `project.html` opens in a browser and shows the index
  document.

### 1.7 A file that isn't an `.mdz`

Make a file that only pretends to be one:

```sh
echo hello > broken.mdz
pandoc -f mdzip-pandoc/mdz.lua broken.mdz -o broken.docx
```

- [ ] **Expected:** an error containing `ERR_ZIP_INVALID`, and no
  `broken.docx`.

### 1.8 A document split over several files

```sh
pandoc -f mdzip-pandoc/mdz.lua field-guide.mdz -o guide-first.docx
```

- [ ] **Expected:** a warning ending in `of 4 documents; add +combine to
  include the ones it links to`.
- [ ] **Expected:** `guide-first.docx` holds only the contents page, "Brewing
  Coffee at Home".

### 1.9 All of it in one Word file

```sh
pandoc -f mdzip-pandoc/mdz.lua+combine field-guide.mdz -o guide.docx
```

- [ ] **Expected:** no messages, except possibly one about converting
  `ratio.svg` (Word needs an extra tool for SVG pictures; that's Pandoc, not
  this converter).
- [ ] **Expected:** opened in Word, `guide.docx` holds the contents page and
  then the chapters in the contents' order: "Choosing beans", "Grinding",
  "Café au lait".
- [ ] **Expected:** the cover picture shows on the first page.
- [ ] **Expected:** Ctrl+click (Cmd+click on a Mac) the contents' "Grinding"
  link: Word jumps to the Grinding chapter inside the same file. The "roast
  levels" link jumps to the Roast levels heading, and each chapter's "Back to
  the contents" link jumps back to the start.

### 1.10 Each chapter on a new page

```sh
pandoc -f mdzip-pandoc/mdz.lua+combine+pagebreaks field-guide.mdz -o guide-pages.docx
```

- [ ] **Expected:** in Word, each chapter starts at the top of a new page. In
  `guide.docx` from 1.9 they follow straight on.

### 1.11 Several files to other formats (optional)

```sh
pandoc -f mdzip-pandoc/mdz.lua+combine field-guide.mdz -s --embed-resources -o guide.html
pandoc -f mdzip-pandoc/mdz.lua+combine field-guide.mdz -o guide.epub
```

- [ ] **Expected:** `guide.html` opens in a browser as one long page with
  all four parts, and its links jump around within the page.
- [ ] **Expected:** `guide.epub` opens in an e-book reader with all four
  parts, each as its own chapter.

And one that shouldn't combine:

```sh
pandoc -f mdzip-pandoc/mdz.lua+combine demo-project.mdz -o project.docx
```

- [ ] **Expected:** a warning ending in `+combine applies only to
  document-mode archives`, and `project.docx` holds only the index document.
  `demo-project.mdz` is a set of separate documents, not one split up.

### 1.12 Word styles that come with the file

```sh
pandoc -f mdzip-pandoc/mdz.lua grid-tables.mdz -o grid-plain.docx
pandoc -f mdzip-pandoc/mdz.lua grid-tables.mdz -t mdzip-pandoc/docx.lua -o grid.docx
```

- [ ] **Expected:** both commands finish with no messages.
- [ ] **Expected:** in `grid-plain.docx`, the table has only a line under its
  header row.
- [ ] **Expected:** in `grid.docx`, the table has grid lines around every
  cell and a light grey header row. The styles came from inside the `.mdz`.

### 1.13 Your own Word template (optional)

If you have a Word template (`.dotx`) or a styled Word file, try your styles
in place of the ones in `grid-tables.mdz`:

```sh
pandoc -f mdzip-pandoc/mdz.lua grid-tables.mdz -t mdzip-pandoc/docx.lua --reference-doc my-template.dotx -o mine.docx
```

- [ ] **Expected:** `mine.docx` opens in Word with your template's fonts,
  headings and table style, and without the grid lines: a reference
  document on the command line wins over the one in the file.

## Part 2: Making `.mdz` files

### 2.1 Get a Markdown file with a picture

This turns the sample back into a plain Markdown file, with its picture saved
next to it:

```sh
pandoc -f mdzip-pandoc/mdz.lua demo-single.mdz -t gfm --extract-media=. -o sample.md
```

- [ ] **Expected:** a new `sample.md`, and an `images` folder holding
  `specimen.png`.

### 2.2 Markdown to `.mdz`

```sh
pandoc sample.md -t mdzip-pandoc/mdz.lua -o sample.mdz
```

- [ ] **Expected:** a new `sample.mdz` file and no messages.

### 2.3 Look inside it

Make a copy of `sample.mdz`, rename the copy to `sample.zip`, and open it like
any ZIP file.

- [ ] **Expected:** `manifest.json`, `index.md`, and an `images` folder
  holding `specimen.png`.

### 2.4 Open it in an MDZip viewer

Open `sample.mdz` in the [online editor](https://mdzip.org/editor.html), or in
MDZip Studio or VS Code if you have them.

- [ ] **Expected:** the document displays with its picture in place.

### 2.5 A title of your own

```sh
pandoc sample.md -t mdzip-pandoc/mdz.lua --metadata title="My Test Notes" -o titled.mdz
```

- [ ] **Expected:** opened in a viewer as in 2.4, the document's title shows
  as "My Test Notes".

### 2.6 Word to `.mdz`

```sh
pandoc report.docx -t mdzip-pandoc/mdz.lua -o report.mdz
```

- [ ] **Expected:** a new `report.mdz` file.
- [ ] **Expected:** looking inside it as in 2.3, the `images` folder holds the
  pictures from your Word file.
- [ ] **Expected:** opened in a viewer as in 2.4, the text and pictures
  appear. Some Word layout (columns, text boxes, fonts) doesn't carry over to
  Markdown, which is expected.

### 2.7 A missing picture

Rename the `images` folder from 2.1 to `images-away`, then run the command from
2.2 again:

```sh
pandoc sample.md -t mdzip-pandoc/mdz.lua -o sample-missing.mdz
```

- [ ] **Expected:** a warning ending in `image not found, left as a link:
  ./images/specimen.png`. The file is still made, without the picture.

Rename `images-away` back to `images` afterwards.

### 2.8 Forgetting the output file

```sh
pandoc sample.md -t mdzip-pandoc/mdz.lua
```

- [ ] **Expected:** an error saying it `needs an output file: add -o
  name.mdz`. No jumble of strange characters in the terminal.

### 2.9 Check a file with the `mdz` tool (optional)

If you have the [`mdz` command-line tool](https://github.com/mdzip-project/mdzip-cli):

```sh
mdz validate sample.mdz
mdz validate report.mdz
```

- [ ] **Expected:** each one says the file is valid.

## Part 3: Your own files (optional)

Try other files you have: a long Word document, a Markdown file with pictures,
an EPUB, a web page saved from a browser. And try your own `.mdz` files the
other way, into Word or HTML.

- [ ] **Expected:** every conversion finishes, and the result opens with its
  pictures.

## Reporting problems

For each failed check, note:

- the test number (for example, 2.6)
- the exact command you ran
- what you expected and what you saw, with any error text copied in full
- your operating system and Pandoc version (`pandoc --version`)
- the file you used, if you can share it

Post your results in
[Test reports](https://github.com/orgs/mdzip-project/discussions/categories/test-reports)
(a free GitHub account is needed). A report where everything passed is useful
too.

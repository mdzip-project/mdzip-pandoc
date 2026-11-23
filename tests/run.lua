-- End-to-end tests: run real pandoc commands with mdz.lua and check the
-- results with mdzip-core-lua.
--
--   pandoc lua tests/run.lua          (from the repository root)
--
-- PANDOC names the pandoc executable (default "pandoc"); MDZIP_LUA_PATH the
-- core's src folder (default ../mdzip-core-lua/src). MDZ, if set or on PATH,
-- is the mdz CLI used to validate written archives.

local core_src = os.getenv("MDZIP_LUA_PATH") or "../mdzip-core-lua/src"
package.path = core_src .. "/?.lua;" .. core_src .. "/?/init.lua;" .. package.path
local mdzip = require("mdzip")
local zip = require("mdzip.zip")

local PANDOC = os.getenv("PANDOC") or "pandoc"
local MDZ = os.getenv("MDZ") or "mdz"
local FIX = core_src .. "/../tests/fixtures/"
local windows = package.config:sub(1, 1) == "\\"

local passed, failed = 0, {}
local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok   " .. name)
  else failed[#failed + 1] = name .. ": " .. tostring(err); print("FAIL " .. name) end
end
local function eq(a, b, what) if a ~= b then error((what or "") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function has(s, needle, what) if not tostring(s):find(needle, 1, true) then error((what or "") .. ": missing " .. needle .. " in:\n" .. tostring(s), 2) end end
local function lacks(s, needle, what) if tostring(s):find(needle, 1, true) then error((what or "") .. ": unexpected " .. needle, 2) end end

local function q(s) return '"' .. s .. '"' end

-- Run a command; returns ok, combined output. `document`: MDZ_DOCUMENT for it.
local function run(args, document)
  local cmd = q(PANDOC) .. " " .. args .. " 2>&1"
  if document then
    cmd = (windows and ('set "MDZ_DOCUMENT=' .. document .. '" && ') or ("MDZ_DOCUMENT='" .. document .. "' ")) .. cmd
  end
  if windows then cmd = '"' .. cmd .. '"' end -- cmd.exe strips one outer pair of quotes
  local p = assert(io.popen(cmd, "r"))
  local out = p:read("a")
  local ok = p:close()
  return ok == true, out
end
local function pandoc_ok(args, document)
  local ok, out = run(args, document)
  if not ok then error("pandoc " .. args .. " failed:\n" .. out, 2) end
  return out
end

local function read_file(path)
  local fh = assert(io.open(path, "rb")); local d = fh:read("a"); fh:close(); return d
end
local function write_file(path, data)
  local fh = assert(io.open(path, "wb")); fh:write(data); fh:close()
end

-- A valid 1x1 PNG.
local PNG = "\137PNG\r\n\26\n\0\0\0\rIHDR\0\0\0\1\0\0\0\1\8\6\0\0\0\31\21\196\137"
  .. "\0\0\0\rIDATx\218c\248\15\4\0\9\251\3\253\227U\242\156\0\0\0\0IEND\174B`\130"

local function zip_names(bytes)
  local names = {}
  for _, e in ipairs(zip.read(bytes)) do names[#names + 1] = e.name end
  return table.concat(names, "\n")
end

local function mdz_validate(path)
  local cmd = q(MDZ) .. " validate " .. q(path) .. " 2>&1"
  if windows then cmd = '"' .. cmd .. '"' end
  local p = io.popen(cmd, "r")
  if not p then return nil end
  local out = p:read("a")
  local ok = p:close()
  if out:find("not recognized") or out:find("not found") then return nil end
  return ok == true, out
end

pandoc.system.with_temporary_directory("mdz-lua-tests", function(tmp)
  local function t(name) return tmp .. "/" .. name end

  -- An archive with a subfolder document, images and raw HTML.
  local sample = assert(mdzip.create({
    files = {
      { path = "index.md", text = "# Sample\n\nIntro.\n\n![Pixel](images/pixel.png)\n\nSee [the chapter](docs/chapter.md).\n" },
      { path = "docs/chapter.md", text = "# Chapter\n\n<img src=\"../images/pixel.png\" alt=\"Pixel\" align=\"right\">\n\nText.\n" },
      { path = "images/pixel.png", data = PNG },
    },
    title = "Sample archive",
    manifest = { author = { name = "Ada" }, language = "en", keywords = { "test" } },
  }))
  write_file(t("sample.mdz"), sample)
  local chapter = assert(mdzip.create({
    files = {
      { path = "docs/chapter.md", text = "# Chapter\n\n<img src=\"../images/pixel.png\" alt=\"Pixel\" align=\"right\">\n\nText.\n" },
      { path = "images/pixel.png", data = PNG },
    },
    entry_point = "docs/chapter.md",
  }))
  write_file(t("chapter.mdz"), chapter)

  -- Reading

  check("read: manifest metadata fills in title, author, lang", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("sample.mdz")) .. " -t markdown -s")
    has(out, "title: Sample archive")
    has(out, "author: Ada")
    has(out, "lang: en")
    has(out, "# Sample")
    has(out, "(images/pixel.png)")
    has(out, "(docs/chapter.md)", "links to other documents stay links")
  end)

  check("read: a first heading that is the title isn't shown twice; a different one stays", function()
    write_file(t("titled.mdz"), assert(mdzip.create({
      files = { { path = "index.md", text = "# Trip  Notes\n\nWe left early.\n\n# Day one\n\nRain.\n" } },
      title = "Trip Notes",
    })))
    local html = pandoc_ok("-f mdz.lua " .. q(t("titled.mdz")) .. " -t html -s")
    has(html, '<h1 class="title">Trip Notes</h1>')
    lacks(html, 'id="trip-notes"', "the heading repeating the title")
    has(html, "Day one", "later headings")
    -- sample.mdz: "# Sample" isn't its title ("Sample archive"); both stay.
    has(pandoc_ok("-f mdz.lua " .. q(t("sample.mdz")) .. " -t html -s"), 'id="sample"')

    -- Word -> .mdz -> Word: a title block comes back once, as a title block.
    write_file(t("report.md"), "---\ntitle: Quarterly Report\n---\n\n## Summary\n\nSales rose.\n")
    pandoc_ok("-f markdown " .. q(t("report.md")) .. " -o " .. q(t("report.docx")))
    pandoc_ok(q(t("report.docx")) .. " -t mdz.lua -o " .. q(t("report.mdz")))
    pandoc_ok("-f mdz.lua " .. q(t("report.mdz")) .. " -o " .. q(t("report-again.docx")))
    local xml = ""
    for _, e in ipairs(pandoc.zip.Archive(read_file(t("report-again.docx"))).entries) do
      if e.path == "word/document.xml" then xml = e:contents() end
    end
    local _, count = xml:gsub("Quarterly Report", "")
    if count ~= 1 then error("the title once expected, got " .. count) end
    has(xml, '<w:pStyle w:val="Title" />')
  end)

  check("read: images reach Word output through the media bag", function()
    pandoc_ok("-f mdz.lua " .. q(t("sample.mdz")) .. " -o " .. q(t("sample.docx")))
    has(zip_names(read_file(t("sample.docx"))), "word/media/", "docx media")
  end)

  check("read: images embed in standalone HTML", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("sample.mdz")) .. " -t html --embed-resources -s")
    has(out, "data:image/png;base64,")
  end)

  check("read: raw HTML images in a subfolder entry point are resolved", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("chapter.mdz")) .. " -t html")
    has(out, 'src="images/pixel.png"')
    has(out, 'align="right"', "raw HTML kept")
    local embedded = pandoc_ok("-f mdz.lua " .. q(t("chapter.mdz")) .. " -t html --embed-resources -s")
    has(embedded, "data:image/png;base64,")
  end)

  local covered = assert(mdzip.create({
    files = {
      { path = "index.md", text = "# Covered\n\nText.\n" },
      { path = "images/cover.png", data = PNG },
    },
    title = "Covered",
    manifest = { cover = "./images/cover.png" },
  }))
  write_file(t("covered.mdz"), covered)

  check("read: manifest cover becomes the cover metadata", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("covered.mdz")) .. " -t markdown -s")
    has(out, "cover: images/cover.png")
    -- Not cover-image, which would send the EPUB writer looking on disk.
    pandoc_ok("-f mdz.lua " .. q(t("covered.mdz")) .. " -o " .. q(t("covered.epub")))
  end)

  check("read: a missing cover is ignored with a warning", function()
    -- Built by hand: the core won't write an archive whose cover is missing.
    local function item(name, content)
      local method, compressed, crc, size = zip.pack_content(name, content)
      local mtime, mdate = zip.dos_time(os.time())
      return { name = name, method = method, compressed = compressed, crc = crc, usize = size, mtime = mtime, mdate = mdate }
    end
    write_file(t("nocover.mdz"), zip.write({
      item("index.md", "# No cover\n"),
      item("manifest.json", '{"spec":{"version":"1.2.0"},"mode":"document","entryPoint":"index.md","cover":"images/gone.png"}'),
    }))
    local out = pandoc_ok("-f mdz.lua " .. q(t("nocover.mdz")) .. " -t markdown -s")
    lacks(out, "cover:")
    has(out, "images/gone.png", "warning names the file")
  end)

  check("mdz-images.lua: the cover is published with a full address", function()
    write_file(t("cover.tpl"), "[$cover$] [$cover-url$]\n")
    pandoc_ok("-f mdz.lua --lua-filter mdz-images.lua " .. q(t("covered.mdz"))
      .. " -M page-url=https://example.org/docs/page.html --template=" .. q(t("cover.tpl"))
      .. " -o " .. q(t("site/page.html")))
    local out = read_file(t("site/page.html"))
    local name = out:match("%[images/(%x+%.png)%]")
    assert(name, "cover points to images/<hash>.png:\n" .. out)
    has(out, "[https://example.org/docs/images/" .. name .. "]")
    eq(read_file(t("site/images/" .. name)), PNG)
  end)

  -- A document split over several files: the entry point links to b first,
  -- then a; b links to c; d is linked from nowhere. Every file has a
  -- "notes" heading, and a's and c's images are relative to a subfolder.
  local book = assert(mdzip.create({
    files = {
      { path = "index.md", text = "# Book\n\n## Notes\n\n[B](part-b.md), [A's notes](ch/part-a.md#notes), [here](#notes).\n" },
      { path = "ch/part-a.md", text = "# Part A\n\n## Notes\n\n![Pixel](../images/pixel.png)\n\n[Back](../index.md) [self](#notes)\n" },
      { path = "part-b.md", text = "# Part B\n\n## Notes\n\nOn to [C](ch/part-c.md).\n" },
      { path = "ch/part-c.md", text = "# Part C\n\n<img src=\"../images/pixel.png\" alt=\"Pixel\">\n" },
      { path = "part-d.md", text = "# Part D\n\nNobody links here.\n" },
      { path = "images/pixel.png", data = PNG },
    },
    title = "Book",
  }))
  write_file(t("book.mdz"), book)

  check("read: without +combine, says how to include the other documents", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("book.mdz")) .. " -t html")
    has(out, "add +combine")
    lacks(out, "Part B")
  end)

  check("read: +combine follows links depth-first and leaves out orphans", function()
    local out = pandoc_ok("-f mdz.lua+combine " .. q(t("book.mdz")) .. " -t html")
    local b, c, a = out:find("Part B", 1, true), out:find("Part C", 1, true), out:find("Part A", 1, true)
    assert(b and c and a and b < c and c < a, "order index, B, C (linked from B), A:\n" .. out)
    lacks(out, "Nobody links here")
    has(out, "part-d.md", "warning names the orphan")
    has(out, "add +orphans")
  end)

  check("read: +combine turns links between documents into internal links", function()
    local out = pandoc_ok("-f mdz.lua+combine " .. q(t("book.mdz")) .. " -t html")
    has(out, 'id="index"', "each document is wrapped")
    has(out, 'id="ch-part-a"')
    has(out, 'href="#part-b"', "link to a whole document")
    has(out, 'href="#ch-part-a--notes"', "link to a heading in another document")
    has(out, 'href="#notes"', "the entry point's own identifiers keep their names")
    has(out, 'id="ch-part-a--notes"', "other documents' identifiers get a prefix")
    has(out, 'href="#index"', "link back to the entry point")
    assert(not out:find('href="[^"]*%.md[#"]'), "no links to .md files left:\n" .. out)
  end)

  check("read: +combine resolves images against each document", function()
    local out = pandoc_ok("-f mdz.lua+combine " .. q(t("book.mdz")) .. " -t html --embed-resources -s")
    lacks(out, "image not in the archive")
    local _, n = out:gsub("data:image/png;base64,", "")
    eq(n >= 2, true, "both images embedded (" .. n .. ")")
  end)

  check("read: +orphans adds documents nothing links to, at the end", function()
    local out = pandoc_ok("-f mdz.lua+combine+orphans " .. q(t("book.mdz")) .. " -t html")
    local a, d = out:find("Part A", 1, true), out:find("Nobody links here", 1, true)
    assert(a and d and a < d, "orphan last:\n" .. out)
    lacks(out, "add +orphans")
  end)

  check("read: +pagebreaks puts page breaks between documents in Word", function()
    pandoc_ok("-f mdz.lua+combine+pagebreaks " .. q(t("book.mdz")) .. " -o " .. q(t("book.docx")))
    local bytes, xml = read_file(t("book.docx")), nil
    for _, e in ipairs(zip.read(bytes)) do
      if e.name == "word/document.xml" then xml = zip.extract(bytes, e) end
    end
    assert(xml, "document.xml")
    local _, n = xml:gsub('w:type="page"', "")
    eq(n, 3, "breaks before the 2nd, 3rd and 4th documents")
    local plain = pandoc_ok("-f mdz.lua+combine " .. q(t("book.mdz")) .. " -t html")
    lacks(plain, "break-after", "no breaks without +pagebreaks")
  end)

  -- A project: separate documents. Home links to Other; Lone is linked from
  -- nowhere. Each has a "notes" heading.
  write_file(t("project.mdz"), assert(mdzip.create({
    files = {
      { path = "index.md", text = "# Home\n\n## Notes\n\n[Other](other.md)\n" },
      { path = "other.md", text = "# Other\n\n## Notes\n\n[Home](index.md#notes)\n" },
      { path = "notes/lone.md", text = "---\ntitle: Lone's own title\n---\n\n# Lone\n\nNobody links here.\n" },
    },
    mode = "project",
    title = "Team Notes",
  })))

  check("read: a project converts its entry point and says how to get the rest", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("project.mdz")) .. " -t html")
    has(out, "project-mode archive; converting only its entry point, index.md (2 other documents left out")
    has(out, "MDZ_DOCUMENT")
    lacks(out, "<h1 id=\"other\"")
  end)

  check("read: +combine collects a project's documents, each a part of its own", function()
    local out = pandoc_ok("-f mdz.lua+combine " .. q(t("project.mdz")) .. " -t html -s")
    local home, other, lone = out:find("Home</h1>", 1, true), out:find("Other</h1>", 1, true), out:find("Nobody links here", 1, true)
    assert(home and other and lone and home < other and other < lone, "every document, linked ones first:\n" .. out)
    has(out, 'class="mdz-document"', "each document is its own part")
    has(out, 'id="notes-lone"')
    has(out, 'href="#notes"', "links between documents work inside the collection")
    has(out, "<title>Team Notes</title>", "the collection takes the manifest's title")
    lacks(out, "Lone's own title", "not a document's own")
    lacks(out, "WARNING")
  end)

  check("read: MDZ_DOCUMENT converts another document", function()
    local out = pandoc_ok("-f mdz.lua " .. q(t("project.mdz")) .. " -t html", "notes/lone.md")
    has(out, "Nobody links here")
    lacks(out, "Home</h1>")
    lacks(out, "WARNING", "no warning: you chose it")
    -- by a relative path with backslashes, too, in a document-mode archive
    out = pandoc_ok("-f mdz.lua " .. q(t("book.mdz")) .. " -t html", ".\\ch\\part-a.md")
    has(out, "Part A</h1>")
    lacks(out, "Part B")
  end)

  check("read: MDZ_DOCUMENT starts +combine from that document", function()
    local out = pandoc_ok("-f mdz.lua+combine " .. q(t("book.mdz")) .. " -t html", "part-b.md")
    local b, c = out:find("Part B", 1, true), out:find("Part C", 1, true)
    assert(b and c and b < c, "part B, then C (linked from B):\n" .. out)
    lacks(out, "<h1 id=\"book\"")
  end)

  check("read: MDZ_DOCUMENT naming no document fails and lists them", function()
    local ok, out = run("-f mdz.lua " .. q(t("project.mdz")) .. " -t html", "missing.md")
    eq(ok, false, "fails")
    has(out, "MDZ_DOCUMENT names missing.md")
    has(out, "notes/lone.md")
  end)

  -- A reference document with a marker in its styles, inside an archive.
  local function word_part(path, part)
    local bytes = read_file(path)
    for _, e in ipairs(zip.read(bytes)) do
      if e.name == part then return zip.extract(bytes, e) end
    end
    return ""
  end
  local function styled_reference(content_type)
    local default = pandoc.pipe(PANDOC, { "--print-default-data-file", "reference.docx" }, "")
    local entries = {}
    for _, e in ipairs(pandoc.zip.Archive(default).entries) do
      local data = e:contents()
      if e.path == "word/styles.xml" then data = data:gsub('w:val="Table" />', 'w:val="MarkerTable" />', 1) end
      if e.path == "[Content_Types].xml" and content_type then data = data:gsub("document%.main%+xml", content_type) end
      entries[#entries + 1] = pandoc.zip.Entry(e.path, data)
    end
    return pandoc.zip.Archive(entries):bytestring()
  end
  local TABLE = "# Styled\n\n| a | b |\n|---|---|\n| 1 | 2 |\n"
  for _, case in ipairs({ { "styled.mdz", "styles/reference.docx" }, { "styled-dotx.mdz", "styles/house.dotx", "template.main+xml" } }) do
    write_file(t(case[1]), assert(mdzip.create({
      files = { { path = "index.md", text = TABLE }, { path = case[2], data = styled_reference(case[3]) } },
      manifest = { pandoc = { referenceDoc = case[2] } },
    })))
  end

  check("docx.lua: uses the reference document the .mdz names", function()
    pandoc_ok("-f mdz.lua " .. q(t("styled.mdz")) .. " -t docx.lua -o " .. q(t("styled.docx")))
    has(word_part(t("styled.docx"), "word/styles.xml"), "MarkerTable")
    lacks(word_part(t("styled.docx"), "docProps/custom.xml"), "mdz-reference-doc", "no leftover property")
    pandoc_ok("-f mdz.lua " .. q(t("styled.mdz")) .. " -o " .. q(t("plain.docx")))
    lacks(word_part(t("plain.docx"), "word/styles.xml"), "MarkerTable", "Pandoc's own writer ignores it")
  end)

  check("docx.lua: a Word template (.dotx) works and gives a .docx", function()
    pandoc_ok("-f mdz.lua " .. q(t("styled-dotx.mdz")) .. " -t docx.lua -o " .. q(t("from-dotx.docx")))
    has(word_part(t("from-dotx.docx"), "word/styles.xml"), "MarkerTable")
    has(word_part(t("from-dotx.docx"), "[Content_Types].xml"), "document.main+xml")
  end)

  check("docx.lua: --reference-doc on the command line wins", function()
    local own = pandoc.pipe(PANDOC, { "--print-default-data-file", "reference.docx" }, "")
    write_file(t("own.docx"), own)
    pandoc_ok("-f mdz.lua " .. q(t("styled.mdz")) .. " -t docx.lua --reference-doc " .. q(t("own.docx")) .. " -o " .. q(t("own-out.docx")))
    lacks(word_part(t("own-out.docx"), "word/styles.xml"), "MarkerTable")
  end)

  check("docx.lua: works on any input, and on an .mdz without a reference document", function()
    pandoc_ok("-f mdz.lua " .. q(t("sample.mdz")) .. " -t docx.lua -o " .. q(t("sample-w.docx")))
    has(zip_names(read_file(t("sample-w.docx"))), "word/media/", "images still reach Word")
    write_file(t("plain.md"), TABLE)
    pandoc_ok(q(t("plain.md")) .. " -t docx.lua -o " .. q(t("plain-w.docx")))
  end)

  check("read: a referenceDoc that isn't in the archive is ignored with a warning", function()
    write_file(t("noref.mdz"), assert(mdzip.create({
      files = { { path = "index.md", text = TABLE } },
      manifest = { pandoc = { referenceDoc = "styles/gone.docx" } },
    })))
    local out = pandoc_ok("-f mdz.lua " .. q(t("noref.mdz")) .. " -t docx.lua -o " .. q(t("noref.docx")))
    has(out, "styles/gone.docx")
  end)

  check("read: -raw_html drops raw HTML (hostile-content.mdz)", function()
    local with = pandoc_ok("-f mdz.lua " .. q(FIX .. "hostile-content.mdz") .. " -t html")
    has(with, "<script", "raw HTML passes through by default, as with Pandoc's own readers")
    -- Pandoc's CommonMark and GFM readers ignore -raw_html; mdz.lua removes it itself.
    for _, fmt in ipairs({ "mdz.lua-raw_html", "mdz.lua+gfm-raw_html", "mdz.lua+pandoc-raw_html" }) do
      local without = pandoc_ok("-f " .. fmt .. " " .. q(FIX .. "hostile-content.mdz") .. " -t html")
      lacks(without, "<script", fmt)
      lacks(without, "<svg", fmt)
      assert(not without:find("onerror=\"", 1, true) and not without:find("onload=\"", 1, true), fmt .. ": event handler kept")
      assert(not without:find('href="javascript:', 1, true), fmt .. ": javascript: link kept")
    end
  end)

  check("read: a table written as HTML (block content in cells) reaches Word, images and all", function()
    -- What the GFM writer makes of a Word layout table: Word output drops raw HTML.
    write_file(t("html-table.mdz"), assert(mdzip.create({ files = {
      { path = "index.md", text = '<table>\n<tbody>\n<tr>\n<td><h1 id="pitch">The Pitch</h1>\n<p>(consumer)</p></td>\n'
        .. '<td><ol type="1">\n<li><p>Reminder</p></li>\n</ol>\n<p><img src="images/x.png" /></p></td>\n</tr>\n</tbody>\n</table>\n' },
      { path = "images/x.png", data = PNG },
    } })))
    pandoc_ok("-f mdz.lua " .. q(t("html-table.mdz")) .. " -t docx.lua -o " .. q(t("html-table.docx")))
    local body = word_part(t("html-table.docx"), "word/document.xml")
    has(body, "<w:tbl>")
    has(body, "The Pitch")
    has(body, "Reminder")
    has(zip_names(read_file(t("html-table.docx"))), "word/media/", "the picture in the cell")
    -- HTML output gets a table too, and -raw_html still drops it.
    has(pandoc_ok("-f mdz.lua " .. q(t("html-table.mdz")) .. " -t html"), "The Pitch")
    lacks(pandoc_ok("-f mdz.lua-raw_html " .. q(t("html-table.mdz")) .. " -t html"), "The Pitch")
  end)

  check("read: a sized picture, a figure and formatting written as HTML reach Word", function()
    write_file(t("html-bits.mdz"), assert(mdzip.create({ files = {
      { path = "index.md", text = 'Plain <u>under</u> x<sup>2</sup> H<sub>2</sub>O <span class="mark">hi</span> '
        .. '<span class="smallcaps">sc</span> <del>gone</del> <span class="other">kept</span> <u>unclosed\n\n'
        .. '<img src="images/x.png" style="width:2in;height:1in" alt="block" />\n\n'
        .. 'Text <img src="images/x.png" style="width:1in" alt="inline" /> more.\n\n'
        .. '<figure><img src="images/x.png" alt="fig" /><figcaption>Figure 1: Sales</figcaption></figure>\n' },
      { path = "images/x.png", data = PNG },
    } })))
    local native = pandoc_ok("-f mdz.lua " .. q(t("html-bits.mdz")) .. " -t native")
    for _, el in ipairs({ "Underline", "Superscript", "Subscript", '"mark"', "SmallCaps", "Strikeout", "Figure" }) do
      has(native, el)
    end
    has(native, '( "width" , "2in" )', "the size from the style")
    has(native, '<span class=\\"other\\">', "a span with other attributes stays HTML")
    has(native, '"<u>"', "a tag with no closing one stays HTML")
    pandoc_ok("-f mdz.lua " .. q(t("html-bits.mdz")) .. " -t docx.lua -o " .. q(t("html-bits.docx")))
    local body = word_part(t("html-bits.docx"), "word/document.xml")
    local _, pictures = body:gsub("<w:drawing>", "")
    eq(pictures, 3, "pictures in Word")
    has(body, "w:vertAlign")
    has(body, "w:highlight")
    has(body, "Figure 1: Sales")
    has(body, 'cx="1828800"', "2in wide")
    -- -raw_html still drops them all.
    local stripped = pandoc_ok("-f mdz.lua-raw_html " .. q(t("html-bits.mdz")) .. " -t native")
    lacks(stripped, "Underline")
    lacks(stripped, "Image")
  end)

  check("read: -raw_html also drops event-handler attributes and script links", function()
    write_file(t("attrs.mdz"), assert(mdzip.create({ files = { { path = "index.md", text =
      '# Hi {#hi onclick="x()"}\n\n[a](javascript:alert(1)) [b]( JavaScript:alert(2)) [ok](https://example.com)\n\n'
      .. '[span]{onmouseover="y()"} <span onclick="z()">tag</span>\n' } } })))
    for _, fmt in ipairs({ "mdz.lua-raw_html", "mdz.lua+pandoc-raw_html" }) do
      local out = pandoc_ok("-f " .. fmt .. " " .. q(t("attrs.mdz")) .. " -t html")
      assert(not out:lower():find("on%a+=\""), fmt .. ": event handler kept\n" .. out)
      assert(not out:lower():find("javascript:", 1, true), fmt .. ": javascript: link kept\n" .. out)
      has(out, 'id="hi"', fmt .. ": other attributes stay")
      has(out, 'href="https://example.com"', fmt .. ": ordinary links stay")
      has(out, "tag", fmt .. ": text inside dropped tags stays")
    end
  end)

  check("read: Markdown is read as CommonMark (commonmark_x), as editors do", function()
    write_file(t("flavor.mdz"), assert(mdzip.create({ files = {
      { path = "index.md", text = "Intro text.\n- one\n- two\n### Next\n\n![A photo](images/x.png)\n\nSee [the guide](#agentsmd).\n\n## AGENTS.md\n\nUse @mdzip/core-js.\n" },
      { path = "images/x.png", data = PNG },
    } })))
    local out = pandoc_ok("-f mdz.lua " .. q(t("flavor.mdz")) .. " -t html")
    has(out, "<li>one</li>", "a list right after a paragraph")
    has(out, '<h3 id="next">', "a heading right after a list")
    lacks(out, "<figure", "no caption made from alt text")
    has(out, 'id="agentsmd"', "editor-style heading identifiers")
    lacks(out, 'class="citation"', "@names are not citations")
    local pd = pandoc_ok("-f mdz.lua+pandoc " .. q(t("flavor.mdz")) .. " -t html")
    has(pd, "<figure", "+pandoc reads Pandoc's Markdown")
    has(pd, 'class="citation"', "+pandoc reads Pandoc's Markdown")
  end)

  check("read: +gfm uses GitHub-Flavored Markdown", function()
    write_file(t("gfm.mdz"), assert(mdzip.create({ files = { { path = "index.md", text = "~~gone~~ and www.example.com\n" } } })))
    local out = pandoc_ok("-f mdz.lua+gfm " .. q(t("gfm.mdz")) .. " -t html")
    has(out, "<del>gone</del>")
    has(out, 'href="http://www.example.com"', "gfm autolinks")
  end)

  check("read: spec fixtures", function()
    has(pandoc_ok("-f mdz.lua " .. q(FIX .. "minimal.mdz") .. " -t plain"), "")
    has(pandoc_ok("-f mdz.lua " .. q(FIX .. "line-endings-crlf.mdz") .. " -t plain"), "")
    local out = pandoc_ok("-f mdz.lua " .. q(FIX .. "project-mode.mdz") .. " -t plain")
    has(out, "project-mode archive; converting only its entry point, index.md", "warning")
  end)

  check("read: errors carry the spec's codes", function()
    for file, code in pairs({
      ["invalid-bad-entrypoint.mdz"] = "ERR_ENTRYPOINT_MISSING",
      ["unsupported-compression.mdz"] = "ERR_ZIP_INVALID",
      ["limit-high-ratio.mdz"] = "ERR_LIMIT_EXCEEDED",
    }) do
      local ok, out = run("-f mdz.lua " .. q(FIX .. file) .. " -t plain")
      eq(ok, false, file .. " should fail")
      has(out, code, file)
    end
  end)

  -- Writing

  write_file(t("pixel.png"), PNG)
  os.execute((windows and "mkdir " or "mkdir -p ") .. q(t("other")))
  write_file(t("other/pixel.png"), PNG)
  write_file(t("doc.md"), table.concat({
    "---", "title: Written by Pandoc", "author: [Ada Lovelace, Charles Babbage]", "lang: en-GB",
    "keywords: [one, two]", "---", "",
    "Some text.", "", "![Local](" .. t("pixel.png") .. ")", "",
    "![Same name, other folder](" .. t("other/pixel.png") .. ")", "",
    "![Again](" .. t("pixel.png") .. ")", "",
    "![Remote](https://example.com/logo.png)", "",
    "![Missing](" .. t("nope.png") .. ")", "",
  }, "\n"))

  check("write: packages images and records metadata", function()
    local out = pandoc_ok(q(t("doc.md")) .. " -t mdz.lua -o " .. q(t("doc.mdz")))
    has(out, "image not found, left as a link", "warning for the missing image")
    local a = assert(mdzip.open(read_file(t("doc.mdz"))))
    local report = a:validate()
    eq(report.valid, true, "valid")
    eq(#report.warnings, 0, "no warnings")
    local m = assert(a:manifest())
    eq(m.title, "Written by Pandoc")
    eq(m.author.name, "Ada Lovelace")
    eq(m.language, "en-GB")
    eq(m.keywords[2], "two")
    has(m.producer.application.name, "mdz.lua")
    eq(assert(a:entry_point()), "index.md")
    eq(assert(a:read("images/pixel.png")), PNG)
    eq(a:has("images/pixel-2.png"), true, "same file name from another folder gets its own path")
    local md = assert(a:read_text("index.md"))
    has(md, "# Written by Pandoc", "title shown as a heading")
    has(md, "(images/pixel.png)")
    has(md, "(images/pixel-2.png)")
    has(md, "https://example.com/logo.png", "web image left as a link")
    has(md, "nope.png", "missing image left as written")
    local images = 0
    for _, f in ipairs(a:files()) do if f:find("^images/") then images = images + 1 end end
    eq(images, 2, "the same image used twice is stored once")
  end)

  check("write: archives pass mdz validate", function()
    local ok, out = mdz_validate(t("doc.mdz"))
    if ok == nil then print("     (mdz CLI not found; skipped)"); return end
    eq(ok, true, out)
    has(out, "valid")
  end)

  check("write: without -o, stops instead of printing the ZIP", function()
    local ok, out = run(q(t("doc.md")) .. " -t mdz.lua")
    eq(ok, false, "exit status")
    has(out, "add -o name.mdz")
    lacks(out, "PK\3\4", "ZIP bytes")
  end)

  check("write: Word to .mdz takes images from the media bag", function()
    pandoc_ok(q(t("doc.md")) .. " -o " .. q(t("doc.docx")))
    pandoc_ok(q(t("doc.docx")) .. " -t mdz.lua -o " .. q(t("from-docx.mdz")))
    local a = assert(mdzip.open(read_file(t("from-docx.mdz"))))
    local images = 0
    for _, f in ipairs(a:files()) do if f:find("^images/") then images = images + 1 end end
    eq(images >= 1, true, "images packaged (" .. images .. ")")
    eq(a:validate().valid, true)
  end)

  check("write: a picture sharing a run with another drawing isn't lost, and a heading of pictures is a paragraph", function()
    -- A logo on a banner: Word puts both drawings in one run, in a heading,
    -- and Pandoc's Word reader keeps only the first.
    write_file(t("logo.png"), PNG)
    write_file(t("logo.md"), "# ![logo](" .. t("logo.png") .. ")\n\nText.\n")
    pandoc_ok("-f markdown " .. q(t("logo.md")) .. " -o " .. q(t("logo-one.docx")))
    local entries = {}
    for _, e in ipairs(pandoc.zip.Archive(read_file(t("logo-one.docx"))).entries) do
      local contents = e:contents()
      if e.path == "word/document.xml" then
        local drawing = contents:match("<w:drawing>.-</w:drawing>")
        contents = contents:gsub("<w:drawing>.-</w:drawing>", function(d) return d .. d end, 1)
        assert(drawing, "a drawing to copy")
      end
      entries[#entries + 1] = pandoc.zip.Entry(e.path, contents)
    end
    write_file(t("logo-two.docx"), pandoc.zip.Archive(entries):bytestring())
    pandoc_ok(q(t("logo-two.docx")) .. " -t mdz.lua -o " .. q(t("logo.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("logo.mdz")))):read_text("index.md"))
    local _, count = md:gsub("!%[logo%]", "")
    if count ~= 2 then error("both pictures expected, got " .. count .. ":\n" .. md) end
    lacks(md, "# !", "a heading of pictures")
    has(md, "Text.")
  end)

  check("write: a picture drawn on a shape keeps the shape's fill behind it (+image_sizes)", function()
    -- A white logo on a blue banner: Pandoc keeps the logo, not the banner.
    write_file(t("logo.png"), PNG)
    write_file(t("banner.md"), "![logo](" .. t("logo.png") .. ")\n\nText.\n")
    pandoc_ok("-f markdown " .. q(t("banner.md")) .. " -o " .. q(t("banner-plain.docx")))
    local shape = '<mc:AlternateContent><mc:Choice Requires="wps"><w:drawing><wp:anchor><a:graphic><a:graphicData>'
      .. '<wps:wsp><wps:spPr><a:gradFill><a:gsLst><a:gs pos="0"><a:srgbClr val="0082c9"/></a:gs>'
      .. '<a:gs pos="100000"><a:srgbClr val="1cafff"/></a:gs></a:gsLst><a:lin ang="20280000" scaled="0"/></a:gradFill>'
      .. '</wps:spPr></wps:wsp></a:graphicData></a:graphic></wp:anchor></w:drawing></mc:Choice>'
      .. '<mc:Fallback/></mc:AlternateContent>'
    local entries = {}
    for _, e in ipairs(pandoc.zip.Archive(read_file(t("banner-plain.docx"))).entries) do
      local contents = e:contents()
      if e.path == "word/document.xml" then
        contents = contents:gsub("<w:drawing>", function(d) return shape .. d end, 1)
        contents = contents:gsub("<w:document ", '<w:document xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
          .. 'xmlns:wps="http://schemas.microsoft.com/office/word/2010/wordprocessingShape" ', 1)
      end
      entries[#entries + 1] = pandoc.zip.Entry(e.path, contents)
    end
    write_file(t("banner.docx"), pandoc.zip.Archive(entries):bytestring())
    pandoc_ok(q(t("banner.docx")) .. " -t mdz.lua+image_sizes -o " .. q(t("banner.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("banner.mdz")))):read_text("index.md"))
    has(md, '<div class="mdz-backdrop"')
    has(md, "linear-gradient(68deg, #0082C9 0%, #1CAFFF 100%)")
    has(md, "logo")
    -- Plain Markdown by default: no backdrop.
    pandoc_ok(q(t("banner.docx")) .. " -t mdz.lua -o " .. q(t("banner-md.mdz")))
    lacks(assert(assert(mdzip.open(read_file(t("banner-md.mdz")))):read_text("index.md")), "mdz-backdrop", "a backdrop")
  end)

  check("write: +notes says where the document came from and what didn't come across", function()
    -- The banner document, with a comment, tracked changes, a PAGE field and a
    -- footer added.
    local W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'
    local entries = {}
    for _, e in ipairs(pandoc.zip.Archive(read_file(t("banner.docx"))).entries) do
      local contents = e:contents()
      if e.path == "word/document.xml" then
        contents = contents:gsub("</w:body>", '<w:p><w:ins w:id="1" w:author="A"><w:r><w:t>new</w:t></w:r></w:ins>'
          .. '<w:del w:id="2" w:author="A"><w:r><w:delText>old</w:delText></w:r></w:del>'
          .. '<w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>'
          .. '<w:r><w:instrText> HYPERLINK "https://example.com" </w:instrText></w:r></w:p></w:body>', 1)
      elseif e.path == "word/comments.xml" then -- Pandoc writes an empty one
        contents = "<w:comments " .. W .. '><w:comment w:id="0" w:author="A"/></w:comments>'
      end
      entries[#entries + 1] = pandoc.zip.Entry(e.path, contents)
    end
    entries[#entries + 1] = pandoc.zip.Entry("word/footer1.xml", "<w:ftr " .. W .. "><w:p><w:r><w:t>Company</w:t></w:r></w:p></w:ftr>")
    write_file(t("Report.docx"), pandoc.zip.Archive(entries):bytestring())

    pandoc_ok(q(t("Report.docx")) .. " -t mdz.lua+image_sizes+notes -o " .. q(t("report-notes.mdz")))
    local a = assert(mdzip.open(read_file(t("report-notes.mdz"))))
    local notes = assert(a:read_text("sources/conversion-notes.md"))
    has(notes, "**Original:** `Report.docx` (Word document, ")
    lacks(notes, tmp, "the folder it was in")
    has(notes, "**SHA-1:** `" .. pandoc.utils.sha1(read_file(t("Report.docx"))) .. "`")
    has(notes, "mdz.lua " .. read_file("mdz.lua"):match('VERSION = "([^"]+)"'))
    has(notes, "`+image_sizes`")
    has(notes, "**Comments:** 1 comment")
    has(notes, "1 insertion and 1 deletion")
    has(notes, "**Shapes:** 1 shape")
    has(notes, "1 picture drawn on one keeps its colour")
    has(notes, "**Fields** (PAGE)")
    has(notes, "**Headers and footers:** 1 header or footer with text")
    has(notes, "`images/`: 1 picture.")
    lacks(a:read_text("index.md"), "Conversion notes", "the notes aren't in the document")

    -- Off by default; and from Markdown, no Word section.
    pandoc_ok(q(t("Report.docx")) .. " -t mdz.lua -o " .. q(t("report-plain.mdz")))
    lacks(zip_names(read_file(t("report-plain.mdz"))), "conversion-notes", "notes without +notes")
    pandoc_ok(q(t("banner.md")) .. " -t mdz.lua+notes -o " .. q(t("md-notes.mdz")))
    local md_notes = assert(assert(mdzip.open(read_file(t("md-notes.mdz")))):read_text("sources/conversion-notes.md"))
    has(md_notes, "(Markdown, ")
    lacks(md_notes, "## What didn't come across", "a Word section")
  end)

  check("write: an older Word picture (VML) keeps the size the document shows it at", function()
    -- A Word file whose picture is <w:pict><v:shape style="width:72pt;..."> instead
    -- of DrawingML: Pandoc's Word reader gives it no size.
    write_file(t("big.png"), PNG)
    write_file(t("vml.md"), "![](" .. t("big.png") .. ")\n")
    pandoc_ok("-f markdown " .. q(t("vml.md")) .. " -o " .. q(t("drawing.docx")))
    local archive = pandoc.zip.Archive(read_file(t("drawing.docx")))
    local entries = {}
    for _, e in ipairs(archive.entries) do
      local contents = e:contents()
      if e.path == "word/document.xml" then
        local id = contents:match('r:embed="([^"]+)"')
        contents = contents:gsub("<w:drawing>.-</w:drawing>", '<w:pict><v:shape id="p1" style="width:72pt;height:36pt">'
          .. '<v:imagedata r:id="' .. id .. '"/></v:shape></w:pict>', 1)
        contents = contents:gsub("<w:document ", '<w:document xmlns:v="urn:schemas-microsoft-com:vml" ', 1)
      end
      entries[#entries + 1] = pandoc.zip.Entry(e.path, contents)
    end
    write_file(t("vml.docx"), pandoc.zip.Archive(entries):bytestring())
    pandoc_ok(q(t("vml.docx")) .. " -t mdz.lua+image_sizes -o " .. q(t("vml.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("vml.mdz")))):read_text("index.md"))
    has(md, "width:1in;height:0.5in")
  end)

  check("write: table_look keeps Word's cell shading and unusual table lines; docx.lua puts them back", function()
    -- Three tables in Word: two with black lines (the usual look), one with
    -- blue lines; a cell of the first shaded with Word's 20% pattern.
    write_file(t("looks.md"), "| A | B |\n|---|---|\n| 1 | 2 |\n\nText.\n\n| C | D |\n|---|---|\n| 3 | 4 |\n\nMore.\n\n| E | F |\n|---|---|\n| 5 | 6 |\n")
    pandoc_ok("-f markdown " .. q(t("looks.md")) .. " -o " .. q(t("looks-plain.docx")))
    local function borders(colour)
      local parts = {}
      for _, edge in ipairs({ "top", "left", "bottom", "right", "insideH", "insideV" }) do
        parts[#parts + 1] = "<w:" .. edge .. ' w:val="single" w:sz="4" w:space="0" w:color="' .. colour .. '"/>'
      end
      return "<w:tblBorders>" .. table.concat(parts) .. "</w:tblBorders>"
    end
    local entries = {}
    for _, e in ipairs(pandoc.zip.Archive(read_file(t("looks-plain.docx"))).entries) do
      local contents = e:contents()
      if e.path == "word/document.xml" then
        local n = 0
        contents = contents:gsub("<w:tblPr>", function()
          n = n + 1
          return "<w:tblPr>" .. borders(n == 3 and "8EAADB" or "000000")
        end)
        contents = contents:gsub("<w:tc>%s*<w:tcPr%s*/>", '<w:tc><w:tcPr><w:shd w:val="pct20" w:color="auto" w:fill="FFFFFF"/></w:tcPr>', 1)
      end
      entries[#entries + 1] = pandoc.zip.Entry(e.path, contents)
    end
    write_file(t("looks.docx"), pandoc.zip.Archive(entries):bytestring())

    pandoc_ok(q(t("looks.docx")) .. " -t mdz.lua+table_look -o " .. q(t("looks.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("looks.mdz")))):read_text("index.md"))
    has(md, "background-color:#CCCCCC", "the shaded cell")
    has(md, 'data-word-borders="top:single/4/8EAADB', "the blue table's lines")
    lacks(md, "000000", "the usual lines are the reference document's business")
    has(md, "| C   | D   |", "a table with the usual look stays Markdown")

    pandoc_ok("-f mdz.lua " .. q(t("looks.mdz")) .. " -t docx.lua -o " .. q(t("looks-out.docx")))
    local body = word_part(t("looks-out.docx"), "word/document.xml")
    has(body, 'w:fill="CCCCCC"')
    has(body, 'w:color="8EAADB"')

    pandoc_ok(q(t("looks.docx")) .. " -t mdz.lua -o " .. q(t("looks-off.mdz")))
    md = assert(assert(mdzip.open(read_file(t("looks-off.mdz")))):read_text("index.md"))
    lacks(md, "<table", "without table_look: Markdown tables")
  end)

  check("write: plain Markdown by default; +html_tables, +image_sizes and +html_formatting keep HTML", function()
    write_file(t("pic.png"), PNG)
    write_file(t("rich.html"), '<p><img src="' .. t("pic.png") .. '" width="200" alt="pic"> <u>under</u> x<sup>2</sup></p>'
      .. '<table><tr><td colspan="2"><h2>Wide</h2><p>two</p></td></tr><tr><td><ul><li>a</li><li>b</li></ul></td><td>c</td></tr></table>')
    pandoc_ok(q(t("rich.html")) .. " -t mdz.lua+html_tables+image_sizes+html_formatting -o " .. q(t("rich.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("rich.mdz")))):read_text("index.md"))
    has(md, "<table", "+html_tables")
    has(md, "<img", "+image_sizes")
    has(md, "<u>", "+html_formatting")
    pandoc_ok(q(t("rich.html")) .. " -t mdz.lua -o " .. q(t("rich-plain.mdz")))
    md = assert(assert(mdzip.open(read_file(t("rich-plain.mdz")))):read_text("index.md"))
    lacks(md, "<")
    has(md, "![pic](images/")
    has(md, "under x2")
    has(md, "| **Wide** two |")
    has(md, "| a; b")
  end)

  check("write: a srcset points into the archive, or goes if one of its pictures is missing (EPUB)", function()
    write_file(t("pic.png"), PNG)
    local pic = t("pic.png"):gsub("\\", "/")
    local gone = t("gone.png"):gsub("\\", "/")
    local function image(alt, set)
      return 'Image ("",[],[("srcset","' .. set .. '")]) [Str "' .. alt .. '"] ("' .. pic .. '","")'
    end
    write_file(t("srcset.native"), "[Para [" .. image("kept", pic .. " 1x, " .. pic .. " 2x") .. "]"
      .. ", Para [" .. image("dropped", pic .. " 1x, " .. gone .. " 2x") .. "]"
      .. ', RawBlock (Format "html") "<img src=\\"' .. pic .. '\\" srcset=\\"' .. gone .. ' 2x\\" alt=\\"raw\\">"]')
    local out = pandoc_ok("-f native " .. q(t("srcset.native")) .. " -t mdz.lua -o " .. q(t("srcset.mdz")))
    local archive = assert(mdzip.open(read_file(t("srcset.mdz"))))
    local md = assert(archive:read_text("index.md"))
    has(md, 'srcset="images/pic.png 1x, images/pic.png 2x"', "every picture found: srcset rewritten")
    lacks(md, "gone.png", "a missing picture: srcset dropped, src shown")
    has(md, '<img src="images/pic.png" alt="raw"', "raw HTML: srcset dropped too")
    lacks(out, "gone.png", "no warning for a srcset picture")
    has(zip_names(read_file(t("srcset.mdz"))), "images/pic.png")
  end)

  check("write: a link inside a link (a Word table of contents) keeps the inner one's text", function()
    write_file(t("toc.native"), '[Para [Link ("",[],[]) [Str "Intro", Space, Link ("",[],[]) [Str "2"] ("#intro","")] ("#intro","")]]')
    pandoc_ok("-f native " .. q(t("toc.native")) .. " -t mdz.lua -o " .. q(t("toc.mdz")))
    has(assert(assert(mdzip.open(read_file(t("toc.mdz")))):read_text("index.md")), "[Intro 2](#intro)")
  end)

  check("write: a captioned picture keeps its caption, as a paragraph under it", function()
    write_file(t("pic.png"), PNG)
    write_file(t("fig.md"), "![](" .. t("pic.png") .. ")\n\nBefore.\n\n![Figure 1: Sales](" .. t("pic.png") .. ")\n\nAfter.\n")
    pandoc_ok("-f markdown " .. q(t("fig.md")) .. " -t mdz.lua -o " .. q(t("fig.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("fig.mdz")))):read_text("index.md"))
    lacks(md, "<figure", "no HTML figure")
    has(md, "\n\nFigure 1: Sales\n", "the caption")
  end)

  check("write: +pandoc writes Pandoc's Markdown", function()
    pandoc_ok(q(t("doc.md")) .. " -t mdz.lua+pandoc -o " .. q(t("doc-pandoc.mdz")))
    local md = assert(assert(mdzip.open(read_file(t("doc-pandoc.mdz")))):read_text("index.md"))
    has(md, "![Local](images/pixel.png)")
  end)

  check("round trip: .mdz to .mdz keeps text, images and title", function()
    pandoc_ok("-f mdz.lua " .. q(t("sample.mdz")) .. " -t mdz.lua -o " .. q(t("again.mdz")))
    local a = assert(mdzip.open(read_file(t("again.mdz"))))
    eq(assert(a:read("images/pixel.png")), PNG)
    eq(assert(a:manifest()).title, "Sample archive")
    has(assert(a:read_text("index.md")), "Intro.")
    eq(a:validate().valid, true)
  end)
end)

print(string.format("\n%d passed, %d failed", passed, #failed))
for _, f in ipairs(failed) do print("\n" .. f) end
os.exit(#failed == 0 and 0 or 1)

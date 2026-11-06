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

-- Run a command; returns ok, combined output.
local function run(args)
  local cmd = q(PANDOC) .. " " .. args .. " 2>&1"
  if windows then cmd = '"' .. cmd .. '"' end -- cmd.exe strips one outer pair of quotes
  local p = assert(io.popen(cmd, "r"))
  local out = p:read("a")
  local ok = p:close()
  return ok == true, out
end
local function pandoc_ok(args)
  local ok, out = run(args)
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

  check("read: -raw_html drops raw HTML (hostile-content.mdz)", function()
    local with = pandoc_ok("-f mdz.lua " .. q(FIX .. "hostile-content.mdz") .. " -t html")
    has(with, "<script", "raw HTML passes through by default, as with Pandoc's own Markdown")
    local without = pandoc_ok("-f mdz.lua-raw_html " .. q(FIX .. "hostile-content.mdz") .. " -t html")
    lacks(without, "<script")
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

  check("write: Word to .mdz takes images from the media bag", function()
    pandoc_ok(q(t("doc.md")) .. " -o " .. q(t("doc.docx")))
    pandoc_ok(q(t("doc.docx")) .. " -t mdz.lua -o " .. q(t("from-docx.mdz")))
    local a = assert(mdzip.open(read_file(t("from-docx.mdz"))))
    local images = 0
    for _, f in ipairs(a:files()) do if f:find("^images/") then images = images + 1 end end
    eq(images >= 1, true, "images packaged (" .. images .. ")")
    eq(a:validate().valid, true)
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

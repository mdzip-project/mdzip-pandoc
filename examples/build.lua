-- Build the example archive: examples/grid-tables.mdz, a document with a
-- Word reference document inside it whose tables have grid lines.
--
--   pandoc lua examples/build.lua [core-dir]
--
-- Run from the repository root. core-dir is an mdzip-core-lua checkout
-- (default ../mdzip-core-lua). The reference document is Pandoc's own, with
-- borders and a grey header row added to its Table style.

local core = (arg[1] or "../mdzip-core-lua") .. "/src"
package.path = core .. "/?.lua;" .. core .. "/?/init.lua;" .. package.path
local mdzip = require("mdzip")

local function read(path)
  local fh = assert(io.open(path, "rb")); local d = fh:read("a"); fh:close(); return d
end
local function write(path, data)
  local fh = assert(io.open(path, "wb")); fh:write(data); fh:close()
end

-- Pandoc's default reference.docx, with grid lines in the Table style.
local default = pandoc.pipe("pandoc", { "--print-default-data-file", "reference.docx" }, "")
local archive = pandoc.zip.Archive(default)
local BORDERS = [[
      <w:tblBorders>
        <w:top w:val="single" w:sz="4" w:space="0" w:color="808080" />
        <w:left w:val="single" w:sz="4" w:space="0" w:color="808080" />
        <w:bottom w:val="single" w:sz="4" w:space="0" w:color="808080" />
        <w:right w:val="single" w:sz="4" w:space="0" w:color="808080" />
        <w:insideH w:val="single" w:sz="4" w:space="0" w:color="808080" />
        <w:insideV w:val="single" w:sz="4" w:space="0" w:color="808080" />
      </w:tblBorders>
]]
local HEADER = '<w:shd w:val="clear" w:color="auto" w:fill="E6E6E6" />'
local entries = {}
for _, e in ipairs(archive.entries) do
  local data = e:contents()
  if e.path == "word/styles.xml" then
    -- Insert text after the first `after` that follows the Table style's start.
    local function insert_after(after, text)
      local style = assert(data:find('w:styleId="Table"', 1, true), "no Table style in reference.docx")
      local _, stop = data:find(after, style, true)
      assert(stop, "no " .. after .. " in the Table style")
      data = data:sub(1, stop) .. text .. data:sub(stop + 1)
    end
    -- Borders go after tblInd, as the schema orders tblPr's children.
    insert_after('<w:tblInd w:w="0" w:type="dxa" />', "\n" .. BORDERS)
    -- The header row's shading goes after its bottom border (tcPr order).
    insert_after("</w:tcBorders>", "\n        " .. HEADER)
  end
  entries[#entries + 1] = pandoc.zip.Entry(e.path, data)
end
local reference = pandoc.zip.Archive(entries):bytestring()
write("examples/grid-tables/styles/reference.docx", reference)

local mdz = assert(mdzip.create({
  files = {
    { path = "index.md", text = read("examples/grid-tables/index.md") },
    { path = "styles/reference.docx", data = reference },
  },
  title = "Grid tables",
  manifest = { pandoc = { referenceDoc = "styles/reference.docx" } },
}))
write("examples/grid-tables.mdz", mdz)
print("examples/grid-tables.mdz")

--[[
docx.lua: Pandoc's Word writer, with the reference document an .mdz carries.

  pandoc -f mdz.lua guide.mdz -t docx.lua -o guide.docx

An .mdz can name a Word reference document in its manifest, an mdzip-pandoc
field outside the MDZip spec:

  "pandoc": { "referenceDoc": "styles/reference.docx" }

mdz.lua reads it into the media bag, but only the writer can use it, so this
writer passes it to Pandoc's own Word writer as --reference-doc would. Word's
styles (tables, headings, fonts, page size) then come from it. A Word template
(.dotx) works too. --reference-doc on the command line still wins.

Everything else is Pandoc's Word writer unchanged. Input that doesn't come
from an .mdz with a reference document is written with Pandoc's default one.
]]

local KEY = "mdz-reference-doc"

local function warn(message)
  if pandoc.log and pandoc.log.warn then pandoc.log.warn(message)
  else io.stderr:write("[WARNING] docx.lua: ", message, "\n") end
end

-- Pandoc's own Word writer: its extensions are this writer's.
Extensions = pandoc.format.extensions("docx")

function ByteStringWriter(doc, opts)
  local out_file = PANDOC_STATE.output_file
  if out_file == nil or out_file == "-" then
    error("docx.lua writes a Word file, so it needs an output file: add -o name.docx", 0)
  end

  local name = doc.meta[KEY] and pandoc.utils.stringify(doc.meta[KEY]) or nil
  -- Not a document property: Pandoc writes unknown metadata into the file.
  doc.meta[KEY] = nil
  local format = { format = "docx", extensions = opts.extensions }

  if name == nil or (opts.reference_doc and opts.reference_doc ~= "") then
    return pandoc.write(doc, format, opts)
  end
  local _, bytes = pandoc.mediabag.lookup(name)
  if not bytes then
    warn("reference document not found in the media bag; using Pandoc's: " .. name)
    return pandoc.write(doc, format, opts)
  end

  return pandoc.system.with_temporary_directory("mdz-docx", function(dir)
    -- Pandoc reads a .dotx as it does a .docx, and writes a .docx either way.
    local path = dir .. "/reference" .. (name:match("%.%w+$") or ".docx")
    local fh = assert(io.open(path, "wb"))
    fh:write(bytes)
    fh:close()
    opts.reference_doc = path
    return pandoc.write(doc, format, opts)
  end)
end

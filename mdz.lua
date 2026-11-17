--[[
mdz.lua: a Pandoc custom reader and writer for MDZip (.mdz) files.

  pandoc -f mdz.lua guide.mdz -o guide.docx      read an .mdz
  pandoc notes.md -t mdz.lua -o notes.mdz         write an .mdz

Reading converts the archive's entry point (spec 5.5). Its images come from
inside the archive and go into Pandoc's media bag, so Word, EPUB and HTML
output (with --embed-resources) include them. Writing packages the document
as index.md plus every image it uses, under images/.

Switches (add to the format, as in -f mdz.lua+gfm):
  gfm            read or write GitHub-Flavored Markdown
  commonmark     read or write CommonMark with Pandoc's extensions (commonmark_x)
  pandoc         write Pandoc's Markdown (reading uses it by default)
  raw_html       keep raw HTML from the archive (on by default; -raw_html drops it)
  combine        read the entry point and the documents it links to, as one
                 document (document-mode archives)
  orphans        with combine, add the documents nothing links to as well
  pagebreaks     with combine, start each document on a new page

Needs mdzip-core-lua (https://github.com/mdzip-project/mdzip-core-lua): set
MDZIP_LUA_PATH to its src folder, or keep it next to this file.
]]

local VERSION = "0.6.0"
local URL = "https://github.com/mdzip-project/mdzip-pandoc"

Extensions = {
  gfm = false,
  commonmark = false,
  pandoc = false,
  raw_html = true,
  combine = false,
  orphans = false,
  pagebreaks = false,
}

---------------------------------------------------------------------------
-- Finding the core library

local script_dir = (PANDOC_SCRIPT_FILE or ""):match("^(.*)[/\\]") or "."
local search = { script_dir .. "/../mdzip-core-lua/src", script_dir .. "/mdzip-core-lua/src" }
local env_dir = os.getenv("MDZIP_LUA_PATH")
if env_dir and env_dir ~= "" then search[#search + 1] = env_dir end -- added last, so searched first
for _, dir in ipairs(search) do
  package.path = dir .. "/?.lua;" .. dir .. "/?/init.lua;" .. package.path
end
local found, mdzip = pcall(require, "mdzip")
if not found then
  error("mdz.lua needs the mdzip-core-lua library. Set MDZIP_LUA_PATH to its src folder, "
    .. "or put a mdzip-core-lua folder next to mdz.lua.\n" .. tostring(mdzip), 0)
end

local stringify = pandoc.utils.stringify

local function warn(message)
  if pandoc.log and pandoc.log.warn then pandoc.log.warn(message)
  else io.stderr:write("[WARNING] mdz.lua: ", message, "\n") end
end

local function fail(err)
  error("mdz.lua: " .. tostring(err), 0)
end

local MIME = {
  png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", gif = "image/gif",
  svg = "image/svg+xml", webp = "image/webp", avif = "image/avif", bmp = "image/bmp",
  tif = "image/tiff", tiff = "image/tiff", ico = "image/x-icon", pdf = "application/pdf",
}
local function mime_of(path)
  local ext = path:match("%.([^./]+)$")
  return ext and MIME[ext:lower()] or nil
end

-- Rewrite the src of <img> tags in raw HTML. fn(src) returns the new src or nil.
local function rewrite_html_img(html, fn)
  return (html:gsub("(<[Ii][Mm][Gg]%f[%s/>][^>]*)", function(tag)
    return (tag:gsub("([%s][Ss][Rr][Cc]%s*=%s*)([\"'])(.-)%2", function(pre, quote, src)
      local new = fn(src)
      if new then return pre .. quote .. new .. quote end
      return nil
    end))
  end))
end

---------------------------------------------------------------------------
-- Reading

local function reader_format(opts)
  local ext = opts.extensions
  local fmt = "markdown"
  if ext:includes("gfm") then fmt = "gfm"
  elseif ext:includes("commonmark") then fmt = "commonmark_x" end
  if not ext:includes("raw_html") then fmt = fmt .. "-raw_html" end
  return fmt
end

-- +combine: the entry point and the documents it links to, as one document
-- (spec 5.7.2 allows a single output from them). Documents come in the order
-- links to them first appear, depth-first from the entry point, each once.
-- Each is wrapped in a Div whose id comes from its path (docs/setup.md ->
-- docs-setup); identifiers in documents other than the entry point get that
-- prefix (docs-setup--install), and links between documents become links
-- inside the result. +orphans adds documents nothing links to, by path;
-- +pagebreaks starts each document after the first on a new page.

local PAGEBREAK = {
  { "openxml", '<w:p><w:r><w:br w:type="page"/></w:r></w:p>' },
  { "latex", "\\newpage{}" },
  { "html", '<div style="break-after: page"></div>' },
}

local function each_identifier(fn)
  local function f(el)
    if el.identifier and el.identifier ~= "" then return fn(el) end
  end
  return { Header = f, Div = f, Span = f, CodeBlock = f, Code = f, Link = f, Image = f, Table = f, Figure = f }
end

local function combine_documents(archive, entry, read_doc, ext)
  local is_doc = {}
  for _, d in ipairs(archive:documents()) do is_doc[d] = true end

  local order, parsed = {}, {}
  local function visit(path)
    if parsed[path] then return end
    parsed[path] = read_doc(path)
    order[#order + 1] = path
    local targets = {}
    parsed[path]:walk({
      Link = function(l)
        local r = archive:resolve_link(path, l.target)
        if r.kind == "internal" and is_doc[r.entry] then targets[#targets + 1] = r.entry end
      end,
    })
    for _, t in ipairs(targets) do visit(t) end
  end
  visit(entry)

  local left = {}
  for _, d in ipairs(archive:documents()) do
    if not parsed[d] then left[#left + 1] = d end
  end
  table.sort(left)
  if #left > 0 then
    if ext:includes("orphans") then
      for _, d in ipairs(left) do visit(d) end
    else
      warn(#left .. " document" .. (#left == 1 and "" or "s") .. " nothing links to left out (add +orphans to include "
        .. (#left == 1 and "it" or "them") .. "): " .. table.concat(left, ", "))
    end
  end

  -- Prefixes, kept clear of the entry point's own identifiers.
  local used, prefix = {}, {}
  parsed[entry]:walk(each_identifier(function(el) used[el.identifier] = true end))
  for _, path in ipairs(order) do
    -- Letters (any script), digits, _ and . stay; everything else becomes -.
    local chars = {}
    for _, c in utf8.codes((path:gsub("%.[^./]+$", ""))) do
      local ch = utf8.char(c)
      chars[#chars + 1] = (c >= 128 or ch:match("[%w_.]")) and ch or "-"
    end
    local p = pandoc.text.lower(table.concat(chars)):gsub("%-%-+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if p == "" then p = "document" end
    local base, n = p, 2
    while used[p] do p = base .. "-" .. n; n = n + 1 end
    used[p] = true
    prefix[path] = p
  end

  local function anchor(target, fragment)
    if fragment == nil or fragment == "" then return "#" .. prefix[target] end
    if target == entry then return "#" .. fragment end
    return "#" .. prefix[target] .. "--" .. fragment
  end

  local blocks = pandoc.Blocks({})
  for i, path in ipairs(order) do
    local d = parsed[path]:walk({
      Link = function(l)
        local r = archive:resolve_link(path, l.target)
        if r.kind == "internal" and prefix[r.entry] then
          l.target = anchor(r.entry, r.fragment)
          return l
        end
      end,
    })
    if path ~= entry then
      local pre = prefix[path] .. "--"
      d = d:walk(each_identifier(function(el) el.identifier = pre .. el.identifier; return el end))
    end
    if i > 1 and ext:includes("pagebreaks") then
      for _, pb in ipairs(PAGEBREAK) do blocks:insert(pandoc.RawBlock(pb[1], pb[2])) end
    end
    blocks:insert(pandoc.Div(d.blocks, pandoc.Attr(prefix[path], { "mdz-document" }, { path = path })))
  end
  return pandoc.Pandoc(blocks, parsed[entry].meta)
end

function ByteStringReader(input, opts)
  local archive, err = mdzip.open(input)
  if not archive then fail(err) end
  local entry, eerr = archive:entry_point()
  if not entry then fail(eerr) end
  local mode, merr = archive:mode()
  if not mode then fail(merr) end
  local ext = opts.extensions
  local combine = ext:includes("combine")
  local others = #archive:documents() - 1
  if mode == "project" then
    warn("this is a project-mode archive; converting only its entry point, " .. entry
      .. (others > 0 and (" (" .. others .. " other document" .. (others == 1 and "" or "s") .. " left out)") or "")
      .. (combine and "; +combine applies only to document-mode archives" or ""))
    combine = false
  elseif others > 0 and not combine then
    warn("converting only the entry point, " .. entry .. ", of " .. (others + 1)
      .. " documents; add +combine to include the ones it links to")
  end
  local fmt = reader_format(opts)

  -- Images: resolve against the document they're in, load from the archive
  -- into the media bag under their archive path, and point the document at it.
  local loaded = {}
  local function load(from, src)
    local r = archive:resolve_link(from, src)
    if r.kind ~= "internal" then
      if r.kind == "unresolved" then warn("image not in the archive: " .. src) end
      return nil
    end
    if not loaded[r.entry] then
      local bytes, rerr = archive:read(r.entry)
      if not bytes then warn("can't read " .. r.entry .. ": " .. tostring(rerr)); return nil end
      pandoc.mediabag.insert(r.entry, mime_of(r.entry), bytes)
      loaded[r.entry] = true
    end
    return r.entry
  end
  local function read_doc(path)
    local text, terr = archive:read_text(path)
    if not text then fail(terr) end
    local function here(src) return load(path, src) end
    return pandoc.read(text, fmt, opts):walk({
      Image = function(img)
        local found = here(img.src)
        if found then img.src = found; return img end
      end,
      RawInline = function(raw)
        if raw.format == "html" then raw.text = rewrite_html_img(raw.text, here); return raw end
      end,
      RawBlock = function(raw)
        if raw.format == "html" then raw.text = rewrite_html_img(raw.text, here); return raw end
      end,
    })
  end

  local doc
  if combine then
    doc = combine_documents(archive, entry, read_doc, ext)
  else
    doc = read_doc(entry)
  end

  -- Manifest metadata fills in what the document doesn't say itself.
  local m = archive:manifest()
  if m then
    local meta = doc.meta
    if meta.title == nil and archive:title() then meta.title = archive:title() end
    if meta.author == nil and type(m.author) == "table" and type(m.author.name) == "string" then
      meta.author = m.author.name
    end
    if meta.lang == nil and type(m.language) == "string" then meta.lang = m.language end
    if meta.description == nil and type(m.description) == "string" then meta.description = m.description end
    if meta.keywords == nil and mdzip.json.is_array(m.keywords) then
      local kw = {}
      for i = 1, #m.keywords do if type(m.keywords[i]) == "string" then kw[#kw + 1] = m.keywords[i] end end
      if #kw > 0 then meta.keywords = kw end
    end
    -- The manifest's cover picture goes into the media bag and metadata as
    -- "cover", for a web page's preview picture (og:image) once mdz-images.lua
    -- publishes it. (Not cover-image: Pandoc's EPUB writer reads that from
    -- disk, where this picture isn't.)
    if meta.cover == nil and type(m.cover) == "string" then
      local cover = m.cover:gsub("^%./", "", 1)
      local name = cover ~= "" and archive:find(cover) or nil
      local bytes = name and archive:read(name)
      if bytes then
        if not loaded[name] then pandoc.mediabag.insert(name, mime_of(name), bytes); loaded[name] = true end
        meta.cover = name
      else
        warn("manifest cover names a file that is not in the archive; ignored: " .. m.cover)
      end
    end
    -- Export hints for Pandoc (an mdzip-pandoc field, not part of the spec):
    -- "pandoc": { "referenceDoc": "styles/reference.docx" }. The reference
    -- document goes into the media bag, and docx.lua passes it to Pandoc's
    -- Word writer; a reader can't set writer options itself.
    if type(m.pandoc) == "table" and type(m.pandoc.referenceDoc) == "string" then
      local ref = m.pandoc.referenceDoc:gsub("^%./", "", 1)
      local name = ref ~= "" and archive:find(ref) or nil
      local bytes = name and archive:read(name)
      if bytes and name:lower():match("%.do[ct]x$") then
        pandoc.mediabag.insert(name, "application/vnd.openxmlformats-officedocument.wordprocessingml.document", bytes)
        meta["mdz-reference-doc"] = name
      else
        warn("manifest pandoc.referenceDoc must name a .docx or .dotx file in the archive; ignored: "
          .. m.pandoc.referenceDoc)
      end
    end
    doc.meta = meta
  end
  return doc
end

---------------------------------------------------------------------------
-- Writing

local function writer_format(opts)
  local ext = opts.extensions
  if ext:includes("pandoc") then return "markdown" end
  if ext:includes("commonmark") then return "commonmark_x" end
  return "gfm"
end

-- A safe archive name for an image: its file name under images/, with
-- characters the spec doesn't allow in entry names replaced.
local function image_name(src)
  local name = src:gsub("[?#].*$", ""):match("([^/\\]+)$") or "image"
  name = name:gsub('[%c\\:%*%?"<>|]', "_")
  if name == "" or name == "." or name == ".." then name = "image" end
  if not name:find("%.[^.]+$") then name = name .. ".bin" end
  return name
end

function ByteStringWriter(doc, opts)
  -- Without -o Pandoc prints the result, and a ZIP is unreadable in a terminal.
  local out_file = PANDOC_STATE.output_file
  if out_file == nil or out_file == "-" then
    error("mdz.lua writes a ZIP archive, so it needs an output file: add -o name.mdz", 0)
  end
  local files = {}
  local by_src, used = {}, {}
  local missing = {}

  local function package(src)
    if by_src[src] ~= nil then return by_src[src] or nil end
    -- A URL scheme (two or more letters, so C:\ isn't one), other than data:.
    if src:match("^[a-zA-Z][a-zA-Z0-9+.-]+:") and not src:match("^data:") then
      by_src[src] = false -- web images stay links (spec 9.2)
      return nil
    end
    local mt, contents = pandoc.mediabag.lookup(src)
    if not contents then
      local ok, fetched_mt, data = pcall(pandoc.mediabag.fetch, src)
      if ok then mt, contents = fetched_mt, data end
    end
    if not contents then
      by_src[src] = false
      missing[#missing + 1] = src
      return nil
    end
    local name
    if src:match("^data:") then
      local ext = ({ ["image/svg+xml"] = "svg", ["image/jpeg"] = "jpg" })[mt or ""]
        or (mt and mt:match("/(%w+)")) or "bin"
      name = "image." .. ext
    else
      name = image_name(src)
    end
    local base, ext = name:match("^(.*)(%.[^.]+)$")
    local candidate, n = "images/" .. name, 1
    while used[candidate] do n = n + 1; candidate = "images/" .. base .. "-" .. n .. ext end
    used[candidate] = true
    by_src[src] = candidate
    files[#files + 1] = { path = candidate, data = contents }
    return candidate
  end

  doc = doc:walk({
    Image = function(img)
      local path = package(img.src)
      if path then img.src = path; return img end
    end,
    RawInline = function(raw)
      if raw.format == "html" then raw.text = rewrite_html_img(raw.text, package); return raw end
    end,
    RawBlock = function(raw)
      if raw.format == "html" then raw.text = rewrite_html_img(raw.text, package); return raw end
    end,
  })
  for _, src in ipairs(missing) do warn("image not found, left as a link: " .. src) end

  local meta = doc.meta
  local title = meta.title and stringify(meta.title) or nil
  if title == "" then title = nil end

  -- The title lives in metadata, which Markdown output drops; keep it visible
  -- as a heading when the document has no level-1 heading of its own.
  if title then
    local has_h1 = false
    for _, b in ipairs(doc.blocks) do
      if b.t == "Header" and b.level == 1 then has_h1 = true; break end
    end
    if not has_h1 then doc.blocks:insert(1, pandoc.Header(1, pandoc.Str(title))) end
  end

  -- GFM and CommonMark have no figures, so Pandoc would write <figure> HTML.
  -- A figure holding just an image becomes a plain image paragraph instead.
  local format = writer_format(opts)
  if format ~= "markdown" then
    doc = doc:walk({
      Figure = function(fig)
        local blocks = fig.content
        if #blocks == 1 and (blocks[1].t == "Plain" or blocks[1].t == "Para") then
          local inlines = blocks[1].content
          local only_images = #inlines > 0
          for _, il in ipairs(inlines) do
            if il.t ~= "Image" and il.t ~= "Space" and il.t ~= "SoftBreak" then only_images = false end
          end
          if only_images then return pandoc.Para(inlines) end
        end
      end,
    })
  end

  local markdown = pandoc.write(doc, format, pandoc.WriterOptions({
    wrap_text = opts.wrap_text, columns = opts.columns,
  }))
  if markdown:sub(-1) ~= "\n" then markdown = markdown .. "\n" end
  table.insert(files, 1, { path = "index.md", text = markdown })

  local extra = {}
  local author = meta.author
  if author then
    local first = author
    if pandoc.utils.type(author) == "List" then first = author[1] end
    local name = first and stringify(first) or ""
    if name ~= "" then extra.author = { name = name } end
  end
  local lang = meta.lang and stringify(meta.lang) or ""
  if lang ~= "" then
    -- BCP 47 shape, as the core checks it: letter-led first subtag, then
    -- "-"-separated alphanumeric subtags of 1 to 8 characters.
    local ok = lang:match("^%a") ~= nil
    for part in (lang .. "-"):gmatch("([^-]*)%-") do
      if #part < 1 or #part > 8 or not part:match("^%w+$") then ok = false end
    end
    if ok then extra.language = lang
    else warn("lang '" .. lang .. "' isn't a language tag; not recorded") end
  end
  local description = meta.description and stringify(meta.description) or ""
  if description ~= "" then extra.description = description end
  if meta.keywords then
    local kw = {}
    local list = pandoc.utils.type(meta.keywords) == "List" and meta.keywords or { meta.keywords }
    for _, k in ipairs(list) do local s = stringify(k); if s ~= "" then kw[#kw + 1] = s end end
    if #kw > 0 then extra.keywords = kw end
  end

  local bytes, err = mdzip.create({
    files = files,
    title = title,
    entry_point = "index.md",
    application = { name = "mdz.lua for Pandoc " .. tostring(PANDOC_VERSION), version = VERSION, url = URL },
    manifest = next(extra) and extra or nil,
  })
  if not bytes then fail(err) end
  return bytes
end

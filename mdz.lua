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

Needs mdzip-core-lua (https://github.com/mdzip-project/mdzip-core-lua): set
MDZIP_LUA_PATH to its src folder, or keep it next to this file.
]]

local VERSION = "0.1.0"
local URL = "https://github.com/mdzip-project/mdzip-pandoc"

Extensions = {
  gfm = false,
  commonmark = false,
  pandoc = false,
  raw_html = true,
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

function ByteStringReader(input, opts)
  local archive, err = mdzip.open(input)
  if not archive then fail(err) end
  local entry, eerr = archive:entry_point()
  if not entry then fail(eerr) end
  local mode, merr = archive:mode()
  if not mode then fail(merr) end
  if mode == "project" then
    local others = #archive:documents() - 1
    warn("this is a project-mode archive; converting only its entry point, " .. entry
      .. (others > 0 and (" (" .. others .. " other document" .. (others == 1 and "" or "s") .. " left out)") or ""))
  end
  local text, terr = archive:read_text(entry)
  if not text then fail(terr) end

  local doc = pandoc.read(text, reader_format(opts), opts)

  -- Images: resolve against the entry point, load from the archive into the
  -- media bag under their archive path, and point the document at it.
  local loaded = {}
  local function load(src)
    local r = archive:resolve_link(entry, src)
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
  doc = doc:walk({
    Image = function(img)
      local path = load(img.src)
      if path then img.src = path; return img end
    end,
    RawInline = function(raw)
      if raw.format == "html" then raw.text = rewrite_html_img(raw.text, load); return raw end
    end,
    RawBlock = function(raw)
      if raw.format == "html" then raw.text = rewrite_html_img(raw.text, load); return raw end
    end,
  })

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

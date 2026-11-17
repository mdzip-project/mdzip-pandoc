-- Build the release download: mdz.lua, docx.lua, the filters and mdzip-core-lua in one
-- ZIP, so mdz.lua works without a separate checkout of the core.
--
--   pandoc lua tools/bundle.lua [core-dir] [out-dir]
--
-- core-dir is an mdzip-core-lua checkout (default ../mdzip-core-lua); out-dir
-- is where the ZIP goes (default dist). Run from the repository root. Prints
-- the ZIP's path.
--
-- The ZIP holds one folder, mdzip-pandoc-<version>/, with mdz.lua and
-- mdzip-core-lua/src next to each other: one of the places mdz.lua looks.

local core_dir = arg[1] or "../mdzip-core-lua"
local out_dir = arg[2] or "dist"

local function read(path)
  local fh = assert(io.open(path, "rb"))
  local data = fh:read("a")
  fh:close()
  return data
end

local version = read("mdz.lua"):match('local VERSION = "([^"]+)"')
assert(version, "no VERSION in mdz.lua")
local core_version = read(core_dir .. "/src/mdzip/version.lua"):match('"(%d+%.%d+%.%d+[^"]*)"')
assert(core_version, "no version in " .. core_dir .. "/src/mdzip/version.lua")

local top = "mdzip-pandoc-" .. version .. "/"
local entries = {}
local function add(name, path)
  entries[#entries + 1] = pandoc.zip.Entry(top .. name, read(path))
end

for _, f in ipairs({ "mdz.lua", "docx.lua", "mdz-links.lua", "mdz-images.lua", "README.md", "CHANGELOG.md", "LICENSE" }) do
  add(f, f)
end

local core_files = pandoc.system.list_directory(core_dir .. "/src/mdzip")
table.sort(core_files)
local count = 0
for _, f in ipairs(core_files) do
  if f:match("%.lua$") then
    add("mdzip-core-lua/src/mdzip/" .. f, core_dir .. "/src/mdzip/" .. f)
    count = count + 1
  end
end
assert(count > 0, "no .lua files in " .. core_dir .. "/src/mdzip")
add("mdzip-core-lua/LICENSE", core_dir .. "/LICENSE")
entries[#entries + 1] = pandoc.zip.Entry(top .. "mdzip-core-lua/VERSION", "mdzip-core-lua " .. core_version .. "\n")

pandoc.system.make_directory(out_dir, true)
local out = out_dir .. "/mdzip-pandoc-" .. version .. ".zip"
local fh = assert(io.open(out, "wb"))
fh:write(pandoc.zip.Archive(entries):bytestring())
fh:close()
io.stderr:write(string.format("mdz.lua %s with mdzip-core-lua %s (%d files)\n", version, core_version, #entries))
print(out)

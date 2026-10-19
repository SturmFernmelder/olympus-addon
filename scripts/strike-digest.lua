-- The chat warnings' list (Olympus/ChatStrikes.lua's ChatStrikes.LIST) from a plain list of words:
--   luajit scripts/strike-digest.lua <path>
-- <path>: one word a line ("#" starts a comment), kept outside this repository (a path inside it is
-- refused: the plain words never go into GitHub or the CurseForge package). Each word is read as
-- the addon reads a typed word (ChatStrikes.Canon: case, accents, look-alike letters, 0 3 4 5 7) and
-- is refused when it is one of tests/fixtures/strike-clean.txt (common English and Portuguese words,
-- the game's names and places, words that hold or resemble an insult). Prints the table to paste
-- over ChatStrikes.LIST: each key the digest ChatStrikes.Digest makes, each value the form's length.
-- A plural or another spelling is a word of its own: list it too.
local ROOT = (arg and arg[0] or ""):match("^(.*)scripts[/\\]strike%-digest%.lua$") or "./"
if ROOT == "" then ROOT = "./" end

local function Fail(why)
	io.stderr:write("strike-digest: " .. why .. "\n")
	os.exit(1)
end

-- A directory as the system resolves it (links followed), or nil.
local function Real(dir)
	if dir:find('["`$\\]') then return nil end
	local p = io.popen('cd "' .. dir .. '" 2>/dev/null && pwd -P')
	local out = p and p:read("*l")
	if p then p:close() end
	return out ~= nil and out ~= "" and out or nil
end

local path = arg and arg[1]
if type(path) ~= "string" or path == "" then Fail("usage: luajit scripts/strike-digest.lua <path to a plain list outside this repository>") end
local root = Real(ROOT)
local dir, file = path:match("^(.*)[/\\]([^/\\]+)$")
if not dir then dir, file = ".", path end
if dir == "" then dir = "/" end
local real = Real(dir)
if not root or not real then Fail("cannot resolve " .. path) end
local full = (real == "/" and "" or real) .. "/" .. file
if full == root or full:sub(1, #root + 1) == root .. "/" then Fail("refused: the plain list must stay outside this repository") end

-- The addon's own reading of a word and its digest: Sign.lua and ChatStrikes.lua, loaded as the
-- game loads them (nothing else of the addon: ChatStrikes reads plain words without it).
local ns = { L = {}, On = function() end }
assert(loadfile(ROOT .. "Olympus/Sign.lua"))("Olympus", ns)
assert(loadfile(ROOT .. "Olympus/ChatStrikes.lua"))("Olympus", ns)
local S = ns.ChatStrikes

local function Lines(file)
	local out = {}
	local f = io.open(file, "rb")
	if not f then return nil end
	local n = 0
	for line in f:lines() do
		n = n + 1
		line = line:gsub("#.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then out[#out + 1] = { n = n, word = line } end
	end
	f:close()
	return out
end

local clean = {}
for _, l in ipairs(assert(Lines(ROOT .. "tests/fixtures/strike-clean.txt"), "tests/fixtures/strike-clean.txt")) do
	local form = S.Canon(l.word)
	if form then clean[form] = true end
end

local words = Lines(path)
if not words then Fail("cannot read " .. path) end
local list, count = {}, 0
for _, l in ipairs(words) do
	local form, why = S.Canon(l.word)
	if not form then Fail(("line %d: not one word of letters (%s)"):format(l.n, tostring(why))) end
	if clean[form] then Fail(("line %d: a word of tests/fixtures/strike-clean.txt"):format(l.n)) end
	local d = S.Digest(form)
	if not list[d] then list[d], count = #form, count + 1 end
end
if count == 0 then Fail("no word in " .. path) end

local keys = {}
for d in pairs(list) do keys[#keys + 1] = d end
table.sort(keys)
io.write("S.LIST = {\n")
for _, d in ipairs(keys) do io.write(('\t["%s"] = %d,\n'):format(d, list[d])) end
io.write("}\n")

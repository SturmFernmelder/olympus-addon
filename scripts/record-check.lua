-- Record mode's files, checked offline (docs/RECORD-FORMAT.md): every session's hash chain, and
-- each guild's checkpoints compared across the witnesses' files. The Companion's verifier is the
-- full tool; this one needs only LuaJIT, for the author to look at the files the day they arrive.
--
--   luajit scripts/record-check.lua FILE...   each FILE a witness's SavedVariables\Olympus.lua
--
-- The files are read as data, never run: a small reader of the table syntax the game writes
-- (strings, numbers, true/false/nil, tables, "-- [n]" comments). It uses Olympus/Sign.lua's
-- SHA-256 and Olympus/Record.lua's format functions as they are. Exit 1 when a chain breaks or
-- two copies of one session differ. Each witness counts once per slot (one file, one character or
-- one BattleTag hash is one witness), and every reading shows how long after its slot it was read.
-- Loaded with "--module" first, it returns its functions instead (tests/record.lua).

local MODULE = ... == "--module"
local ROOT = ((arg and arg[0] or ""):match("^(.*)scripts[/\\]record%-check%.lua$")) or "./"
local M = {}

---------------------------------------------------------------------------
-- The reader: name = value statements, the values the game writes.
---------------------------------------------------------------------------

local ESC = { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'", ["\n"] = "\n" }

function M.Parse(text)
	local pos, n = 1, #text
	local function Fail(why) error(("record-check: %s at byte %d"):format(why, pos), 0) end
	local function Skip()
		while pos <= n do
			local c = text:sub(pos, pos)
			if c:find("^%s") then
				pos = pos + 1
			elseif text:sub(pos, pos + 1) == "--" then
				local e = text:find("\n", pos, true)
				pos = e and e + 1 or n + 1
			else
				return
			end
		end
	end
	local Value
	local function String(q)
		pos = pos + 1
		local out = {}
		while true do
			if pos > n then Fail("an unfinished string") end
			local c = text:sub(pos, pos)
			if c == q then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local e = text:sub(pos + 1, pos + 1)
				local d = text:match("^%d%d?%d?", pos + 1)
				if d then
					out[#out + 1] = string.char(tonumber(d) % 256)
					pos = pos + 1 + #d
				elseif ESC[e] then
					out[#out + 1] = ESC[e]
					pos = pos + 2
				else
					Fail("an unknown escape")
				end
			elseif c == "\n" then
				Fail("a line break in a string")
			else
				local e = text:find('[\\\n' .. q .. ']', pos)
				if not e then Fail("an unfinished string") end
				out[#out + 1] = text:sub(pos, e - 1)
				pos = e
			end
		end
	end
	local function Table()
		pos = pos + 1
		local t, k = {}, 1
		while true do
			Skip()
			local c = text:sub(pos, pos)
			if c == "}" then
				pos = pos + 1
				return t
			end
			if c == "[" then
				pos = pos + 1
				Skip()
				local key = Value()
				Skip()
				if text:sub(pos, pos) ~= "]" then Fail("a key with no ]") end
				pos = pos + 1
				Skip()
				if text:sub(pos, pos) ~= "=" then Fail("a key with no =") end
				pos = pos + 1
				Skip()
				t[key] = Value()
			else
				local name = text:match("^[%a_][%w_]*%s*=", pos)
				if name and not text:match("^[%a_][%w_]*%s*==", pos) then
					pos = pos + #name
					Skip()
					t[name:match("^[%a_][%w_]*")] = Value()
				else
					t[k] = Value()
					k = k + 1
				end
			end
			Skip()
			c = text:sub(pos, pos)
			if c == "," or c == ";" then pos = pos + 1 elseif c ~= "}" then Fail("a field with no , or }") end
		end
	end
	Value = function()
		Skip()
		local c = text:sub(pos, pos)
		if c == "{" then return Table() end
		if c == '"' or c == "'" then return String(c) end
		for word, v in pairs({ ["true"] = true, ["false"] = false, ["nil"] = M.NIL }) do
			if text:sub(pos, pos + #word - 1) == word and not text:sub(pos + #word, pos + #word):find("^[%w_]") then
				pos = pos + #word
				return v
			end
		end
		local num = text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
		if num and num ~= "" and num ~= "-" and tonumber(num) then
			pos = pos + #num
			return tonumber(num)
		end
		Fail("a value the game never writes")
	end
	local out = {}
	while true do
		Skip()
		if pos > n then return out end
		local name = text:match("^([%a_][%w_]*)%s*=", pos)
		if not name then Fail("a statement that is no name = value") end
		pos = pos + #text:match("^[%a_][%w_]*%s*=", pos)
		local v = Value()
		out[name] = v ~= M.NIL and v or nil
	end
end
M.NIL = setmetatable({}, { __tostring = function() return "nil" end })

---------------------------------------------------------------------------
-- The checks
---------------------------------------------------------------------------

function M.Load()
	local ns = { L = setmetatable({}, { __index = function(_, k) return k end }), On = function() end }
	_G.bit = _G.bit or require("bit")
	assert(loadfile(ROOT .. "Olympus/Sign.lua"))("Olympus", ns)
	assert(loadfile(ROOT .. "Olympus/Record.lua"))("Olympus", ns)
	return ns.Record
end

-- A reading counts toward the figure at one instant only this many seconds after its slot at most
-- (docs/RECORD-FORMAT.md, section 8, step 8); a later one is listed apart, with how late it was.
M.BOUND = 30

-- Each session of a parsed file: { id, char, guild, tag, file, ok, head, n, why, at, lines, text,
-- checkpoints = { ... } }. A checkpoint: { guild, kind, slot, at, late, total, online, rows,
-- rowsOnline, members, onlineSet } with the sets as sorted "name|GUID" lists and late = at - slot.
function M.Sessions(R, db, file)
	local out = {}
	if type(db) ~= "table" or db.format ~= R.FORMAT or db.version ~= R.VERSION then return out, "no OlympusRecordDB of format 1" end
	for _, s in ipairs(type(db.sessions) == "table" and db.sessions or {}) do
		local ok, a, b = R.Verify(s)
		local lines = type(s) == "table" and type(s.lines) == "table" and s.lines or {}
		local text = {}
		for i, line in ipairs(lines) do text[i] = tostring(line) end
		local e = { id = type(s) == "table" and s.id or nil, char = type(s) == "table" and s.char or nil,
			start = type(s) == "table" and s.start or nil, file = file, ok = ok, head = ok and a or nil, n = ok and b or nil,
			at = not ok and a or nil, why = not ok and b or nil, checkpoints = {}, lines = #lines,
			-- (the copy as stored, to compare with the same session in another file)
			text = table.concat(text, "\n") .. "\0" .. tostring(type(s) == "table" and s.n) .. "\0" .. tostring(type(s) == "table" and s.head) }
		local dict = {}
		for _, line in ipairs(lines) do
			local f = R.Split(line)
			if f[1] == "S" then
				e.guild, e.tag = f[6], f[14] ~= "" and f[14] or nil
			elseif f[1] == "M" then
				dict[tonumber(f[2])] = f[3] .. "|" .. f[4]
			elseif f[1] == "C" then
				local function Names(hex)
					local set = R.Unbitmap(hex) or {}
					local names = {}
					for i in pairs(set) do names[#names + 1] = dict[i] or ("?" .. i) end
					table.sort(names)
					return names
				end
				local slot, at = tonumber(f[3]), tonumber(f[4])
				e.checkpoints[#e.checkpoints + 1] = { guild = f[5], kind = f[2], slot = slot, at = at,
					late = slot and at and at - slot or nil, total = tonumber(f[6]), online = tonumber(f[7]), rows = tonumber(f[8]),
					rowsOnline = tonumber(f[9]), members = Names(f[10]), onlineSet = Names(f[11]) }
			end
		end
		out[#out + 1] = e
	end
	return out
end

-- The sessions of all files, each id once: { kept, conflicts }. Copies of one id must be identical
-- (the same lines, n and head) whatever the files' order; when any differs, no copy of that id is
-- kept, and conflicts lists it with every file that holds it.
function M.Dedupe(entries)
	local byId, order = {}, {}
	for _, e in ipairs(entries) do
		local key = e.id or ("\0no id " .. #order)
		if not byId[key] then
			byId[key] = { e }
			order[#order + 1] = key
		else
			table.insert(byId[key], e)
		end
	end
	local kept, conflicts = {}, {}
	for _, key in ipairs(order) do
		local copies, same = byId[key], true
		for i = 2, #copies do
			if copies[i].text ~= copies[1].text then same = false end
		end
		if same then
			kept[#kept + 1] = copies[1]
		else
			local files = {}
			for _, c in ipairs(copies) do files[#files + 1] = tostring(c.file) end
			conflicts[#conflicts + 1] = { id = key, files = files }
		end
	end
	return kept, conflicts
end

-- Who is one witness (section 8, step 7): the sessions of one file (one WoW account), of one
-- character, or with one BattleTag hash (S field 14). Each session's witness, as the name of the
-- first session's character in its group.
local function Witnesses(sessions)
	local parent = {}
	local function Find(x)
		while parent[x] and parent[x] ~= x do x = parent[x] end
		return x
	end
	local function Join(a, b)
		parent[a] = parent[a] or a
		parent[b] = parent[b] or b
		local ra, rb = Find(a), Find(b)
		if ra ~= rb then parent[rb] = ra end
	end
	for i, e in ipairs(sessions) do
		local me = "s" .. i
		parent[me] = parent[me] or me
		if e.file then Join("file:" .. e.file, me) end
		if e.char then Join("char:" .. e.char, me) end
		if e.tag then Join("tag:" .. e.tag, me) end
	end
	local out = {}
	for i in ipairs(sessions) do out[i] = Find("s" .. i) end
	return out
end

local function Same(a, b)
	return a.total == b.total and table.concat(a.members, "\n") == table.concat(b.members, "\n")
		and table.concat(a.onlineSet, "\n") == table.concat(b.onlineSet, "\n")
end

-- The witnesses' quarter-hour checkpoints, per guild and slot: { guild, slot, seen = { {who, c} },
-- late = { {who, c} }, agree }. Each witness counts once: its reading nearest the slot. seen holds
-- the readings at most M.BOUND seconds after the slot (one instant), late the later ones; agree:
-- the same total, members and online members across seen.
function M.Compare(sessions, bound)
	bound = bound or M.BOUND
	local witness = Witnesses(sessions)
	local groups, order = {}, {}
	for i, e in ipairs(sessions) do
		if e.ok then
			for _, c in ipairs(e.checkpoints) do
				if c.kind == "Q" then
					local key = c.guild:lower() .. "\0" .. c.slot
					local g = groups[key]
					if not g then
						g = { guild = c.guild, slot = c.slot, by = {}, list = {} }
						groups[key], order[#order + 1] = g, key
					end
					local w = witness[i]
					local had = g.by[w]
					if not had then
						had = { who = e.char, c = c, readings = 1 }
						g.by[w] = had
						g.list[#g.list + 1] = had
					else
						had.readings = had.readings + 1
						if (c.late or math.huge) < (had.c.late or math.huge) then had.who, had.c = e.char, c end
					end
				end
			end
		end
	end
	local out = {}
	for _, key in ipairs(order) do
		local g = groups[key]
		g.seen, g.late = {}, {}
		for _, s in ipairs(g.list) do
			if s.c.late and s.c.late <= bound then g.seen[#g.seen + 1] = s else g.late[#g.late + 1] = s end
		end
		g.agree = true
		for i = 2, #g.seen do
			if not Same(g.seen[i].c, g.seen[1].c) then g.agree = false end
		end
		g.by, g.list = nil, nil
		out[#out + 1] = g
	end
	table.sort(out, function(a, b)
		if a.slot ~= b.slot then return a.slot < b.slot end
		return a.guild < b.guild
	end)
	return out
end

if MODULE then return M end

local R = M.Load()
local entries, broken = {}, 0
if not arg[1] then
	io.stderr:write("usage: luajit scripts/record-check.lua FILE...\n")
	os.exit(2)
end
for _, path in ipairs(arg) do
	local file = assert(io.open(path, "rb"))
	local text = file:read("*a")
	file:close()
	local ok, parsed = pcall(M.Parse, text)
	if not ok then
		print(("%s: %s"):format(path, tostring(parsed)))
		broken = broken + 1
	else
		local sessions, why = M.Sessions(R, parsed.OlympusRecordDB, path)
		print(("%s: %d session(s)%s"):format(path, #sessions, why and (" (" .. why .. ")") or ""))
		for _, e in ipairs(sessions) do
			local when = os.date("!%Y-%m-%d %H:%M UTC", tonumber(e.start) or 0)
			if e.ok then
				print(("  %s  %s  <%s>  %s: %d lines, %d checkpoints, chain OK, head %s"):format(tostring(e.id), tostring(e.char),
					tostring(e.guild), when, e.n, #e.checkpoints, e.head))
			else
				broken = broken + 1
				print(("  %s  %s: chain BROKEN at line %s (%s)"):format(tostring(e.id), tostring(e.char), tostring(e.at), tostring(e.why)))
			end
			entries[#entries + 1] = e
		end
	end
end
-- The same session in two files (one day's file and the next's) must be the same in both.
local kept, conflicts = M.Dedupe(entries)
for _, c in ipairs(conflicts) do
	print(("%s: the copies differ (%s): left out of the counts"):format(tostring(c.id), table.concat(c.files, ", ")))
	broken = broken + 1
end
print(("Checkpoints by guild and quarter hour (each witness once, its reading nearest the slot: total / online members, read +N s after the slot; one instant: +%d s at most):"):format(M.BOUND))
local function Part(s)
	return ("%s %d/%d +%ds%s"):format(tostring(s.who), s.c.total or -1, #s.c.onlineSet, s.c.late or -1,
		s.readings > 1 and (" (%d readings)"):format(s.readings) or "")
end
for _, g in ipairs(M.Compare(kept)) do
	local parts, lateParts, worst = {}, {}, nil
	for _, s in ipairs(g.seen) do
		parts[#parts + 1] = Part(s)
		if not worst or s.c.late > worst then worst = s.c.late end
	end
	for _, s in ipairs(g.late) do lateParts[#lateParts + 1] = Part(s) end
	print(("  %s  <%s>  %d witness(es)%s%s: %s"):format(os.date("!%Y-%m-%d %H:%M", g.slot), g.guild, #g.seen,
		#g.seen > 1 and (g.agree and ", agree" or ", DISAGREE") or "", worst and (", latest +%ds"):format(worst) or "",
		#parts > 0 and table.concat(parts, "; ") or "-"))
	if #lateParts > 0 then
		print(("      read more than %d s after the slot, not one instant: %s"):format(M.BOUND, table.concat(lateParts, "; ")))
	end
end
os.exit(broken > 0 and 1 or 0)

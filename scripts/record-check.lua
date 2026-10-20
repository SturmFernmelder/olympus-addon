-- Record mode's files, checked offline (docs/RECORD-FORMAT.md): every session's hash chain, and
-- each guild's checkpoints compared across the witnesses' files. The Companion's verifier is the
-- full tool; this one needs only LuaJIT, for the author to look at the files the day they arrive.
--
--   luajit scripts/record-check.lua FILE...   each FILE a witness's SavedVariables\Olympus.lua
--
-- The files are read as data, never run: a small reader of the table syntax the game writes
-- (strings, numbers, true/false/nil, tables, "-- [n]" comments). The chains and the lines are
-- checked and read by Olympus/Record.lua's Record.VerifyFile, and the copies of one session
-- compared by its Record.Dedupe (with Olympus/Sign.lua's SHA-256): the same code as the recorder's
-- and the Companion's, none of its own. Exit 1 when a chain breaks or two copies of one session
-- differ. Each witness counts once per slot (one file, one character or
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
	local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
	_G.bit = _G.bit or require("bit")
	assert(loadfile(ROOT .. "Olympus/Sign.lua"))("Olympus", ns)
	assert(loadfile(ROOT .. "Olympus/Record.lua"))("Olympus", ns)
	M.R = ns.Record
	return ns.Record
end

-- A reading counts toward the figure at one instant only this many seconds after its slot at most
-- (docs/RECORD-FORMAT.md, section 8, step 8); a later one is listed apart, with how late it was.
M.BOUND = 30

-- Each session of a parsed file, as Record.VerifyFile reads it: { id, char, guild, tag, file, ok,
-- head, n, at, why, lines, copy, checkpoints = { ... } }; then why the file is refused, if it is, and
-- how many exact repeats of a session in it were left out. A checkpoint: { guild, kind, slot, at,
-- late, total, online, rows, rowsOnline, members, onlineSet } with the sets as sorted "name|GUID"
-- lists and late = at - slot.
function M.Sessions(R, db, file)
	local out = {}
	local result = R.VerifyFile(db, nil) -- (nil: the SHA-256 of R's own namespace, Olympus/Sign.lua's)
	for _, v in ipairs(result.sessions) do
		local e = { id = v.id, char = v.character, start = v.start, guild = v.guild, tag = v.battleTagHash, file = file,
			ok = v.ok, head = v.ok and v.lastHash or nil, n = v.ok and v.records or nil, at = v.brokenAt, why = v.why,
			lines = v.records, copy = v.copy, checkpoints = {} }
		for _, o in ipairs(v.observations) do
			if o.kind == "C" then
				local sets = o.checkpoint ~= nil and v.roster[o.checkpoint] or {}
				e.checkpoints[#e.checkpoints + 1] = { guild = tostring(o.guild), kind = type(o.checkpoint) == "number" and "Q" or "M",
					slot = o.slot, at = o.readAt, late = o.slot and o.readAt and o.readAt - o.slot or nil, total = o.total,
					online = o.online, rows = o.rows, rowsOnline = o.rowsOnline, members = sets.presentKeys or {},
					onlineSet = sets.onlineKeys or {} }
			end
		end
		out[#out + 1] = e
	end
	return out, result.why, result.duplicates
end

-- The sessions of all files, each id once (Record.Dedupe): { kept, conflicts }. Copies of one id
-- must be the same copy (the same lines, marks, n and head) whatever the files' order; when any
-- differs, no copy of that id is kept, and conflicts lists it with every file that holds it.
function M.Dedupe(entries)
	local R = M.R or M.Load()
	local kept, found = R.Dedupe(entries)
	local conflicts = {}
	for _, g in ipairs(found) do
		local files = {}
		for _, c in ipairs(g.copies) do files[#files + 1] = tostring(c.file) end
		conflicts[#conflicts + 1] = { id = g.id, files = files }
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
		local sessions, why, repeats = M.Sessions(R, parsed.OlympusRecordDB, path)
		print(("%s: %d session(s)%s%s"):format(path, #sessions, (repeats or 0) > 0 and (", %d exact repeat(s) left out"):format(repeats) or "",
			why and (" (" .. why .. ")") or ""))
		for _, e in ipairs(sessions) do
			local when = os.date("!%Y-%m-%d %H:%M UTC", tonumber(e.start) or 0)
			if e.ok then
				print(("  %s  %s  <%s>  %s: %d lines, %d checkpoints, chain OK, head %s"):format(tostring(e.id), tostring(e.char),
					tostring(e.guild), when, e.n, #e.checkpoints, e.head))
			else
				broken = broken + 1
				print(("  %s  %s: %s"):format(tostring(e.id), tostring(e.char), e.at and ("chain BROKEN, " .. tostring(e.why)) or tostring(e.why)))
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

-- Record mode's files, checked offline (docs/RECORD-FORMAT.md): every session's hash chain, and
-- each guild's checkpoints compared across the witnesses' files. The Companion's verifier is the
-- full tool; this one needs only LuaJIT, for the author to look at the files the day they arrive.
--
--   luajit scripts/record-check.lua FILE...   each FILE a witness's SavedVariables\Olympus.lua
--
-- The files are read as data, never run: a small reader of the table syntax the game writes
-- (strings, numbers, true/false/nil, tables, "-- [n]" comments). It uses Olympus/Sign.lua's
-- SHA-256 and Olympus/Record.lua's format functions as they are. Exit 1 when a chain breaks.
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

-- Each session of a parsed file: { id, char, guild, ok, head, n, why, at, checkpoints = { ... } }.
-- A checkpoint: { guild, kind, slot, at, total, online, rows, rowsOnline, members, onlineSet } with
-- the sets as sorted "name|GUID" lists.
function M.Sessions(R, db)
	local out = {}
	if type(db) ~= "table" or db.format ~= R.FORMAT or db.version ~= R.VERSION then return out, "no OlympusRecordDB of format 1" end
	for _, s in ipairs(type(db.sessions) == "table" and db.sessions or {}) do
		local ok, a, b = R.Verify(s)
		local e = { id = s.id, char = s.char, start = s.start, ok = ok, head = ok and a or nil, n = ok and b or nil,
			at = not ok and a or nil, why = not ok and b or nil, checkpoints = {}, lines = type(s.lines) == "table" and #s.lines or 0 }
		local dict = {}
		for _, line in ipairs(type(s.lines) == "table" and s.lines or {}) do
			local f = R.Split(line)
			if f[1] == "S" then
				e.guild = f[6]
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
				e.checkpoints[#e.checkpoints + 1] = { guild = f[5], kind = f[2], slot = tonumber(f[3]), at = tonumber(f[4]),
					total = tonumber(f[6]), online = tonumber(f[7]), rows = tonumber(f[8]), rowsOnline = tonumber(f[9]),
					members = Names(f[10]), onlineSet = Names(f[11]) }
			end
		end
		out[#out + 1] = e
	end
	return out
end

-- The witnesses' quarter-hour checkpoints, per guild and slot: { key, guild, slot, seen = { {who,
-- c} }, agree } (agree: the same total, the same members and the same online members).
function M.Compare(sessions)
	local groups, order = {}, {}
	for _, e in ipairs(sessions) do
		if e.ok then
			for _, c in ipairs(e.checkpoints) do
				if c.kind == "Q" then
					local key = c.guild:lower() .. "\0" .. c.slot
					local g = groups[key]
					if not g then
						g = { guild = c.guild, slot = c.slot, seen = {} }
						groups[key], order[#order + 1] = g, key
					end
					g.seen[#g.seen + 1] = { who = e.char, c = c }
				end
			end
		end
	end
	local out = {}
	for _, key in ipairs(order) do
		local g = groups[key]
		local first = g.seen[1].c
		g.agree = true
		for i = 2, #g.seen do
			local c = g.seen[i].c
			if c.total ~= first.total or table.concat(c.members, "\n") ~= table.concat(first.members, "\n")
				or table.concat(c.onlineSet, "\n") ~= table.concat(first.onlineSet, "\n") then g.agree = false end
		end
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
local all, broken, seenIds = {}, 0, {}
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
		local sessions, why = M.Sessions(R, parsed.OlympusRecordDB)
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
			-- The same session in two files (one day's file and the next's) must be the same up to the shorter.
			local prev = e.id and seenIds[e.id]
			if prev and prev.head ~= e.head and prev.n == e.n then
				print(("  %s: the same session differs from %s's"):format(tostring(e.id), prev.path))
				broken = broken + 1
			end
			if e.id and not prev then
				e.path = path
				seenIds[e.id] = e
				all[#all + 1] = e
			end
		end
	end
end
print("Checkpoints by guild and quarter hour (witnesses: total / online members):")
for _, g in ipairs(M.Compare(all)) do
	local parts = {}
	for _, s in ipairs(g.seen) do parts[#parts + 1] = ("%s %d/%d"):format(tostring(s.who), s.c.total or -1, #s.c.onlineSet) end
	print(("  %s  <%s>  %d witness(es)%s: %s"):format(os.date("!%Y-%m-%d %H:%M", g.slot), g.guild, #g.seen,
		#g.seen > 1 and (g.agree and ", agree" or ", DISAGREE") or "", table.concat(parts, "; ")))
end
os.exit(broken > 0 and 1 or 0)

-- Guinness record attempt: the evidence pack from the witnesses' Olympus.lua files.
--
--   luajit scripts/record-verify.lua <out-dir> <witness Olympus.lua> [<witness Olympus.lua> ...]
--
-- docs/RECORD-FORMAT.md, section 8. Steps 1 to 7 (reading the files as data, every session's hash
-- chain, copies of one session, who is one witness, the checkpoints per guild and quarter hour) are
-- scripts/record-check.lua's own functions, loaded as a module, so the two tools never disagree.
-- This adds step 8 (the figure at each quarter hour), step 9 (manual marks) and the files a
-- reviewer keeps. In <out-dir>:
--   manifest.csv     one line per file: name, size, SHA-256, sessions, why a file was refused
--   witnesses.csv    one line per session: witness, character, guild, BattleTag hash, start,
--                    lines, head, chain verdict, copies
--   checkpoints.csv  one line per guild and quarter hour: each witness's reading and how late,
--                    agreement, the conservative online count, readings too late for one instant
--   figures.csv      one line per quarter hour: the witnessed figure, the reporters' claims kept
--                    apart, and the largest at - slot used
--   claims.csv       the census reports (E lines) for guilds no witness read at that instant
--   marks.csv        manual marks, grouped where witnesses marked within MARK_WINDOW seconds
--   summary.txt      the totals and every problem, in plain words
-- Exit 1 when a file is refused, a chain breaks or two copies of one session differ.
local ROOT = os.getenv("OLYMPUS_ROOT") or (arg and arg[0] or ""):match("^(.*)scripts[/\\]record%-verify%.lua$") or "./"
if ROOT ~= "" and not ROOT:find("[/\\]$") then ROOT = ROOT .. "/" end

local function Fail(message)
	io.stderr:write("record-verify: ", message, "\n")
	os.exit(2)
end

local outDir = arg[1]
if not outDir or not arg[2] then
	Fail("usage: luajit scripts/record-verify.lua <out-dir> <witness Olympus.lua> [...]")
end

local checkChunk = loadfile(ROOT .. "scripts/record-check.lua")
if not checkChunk then Fail("scripts/record-check.lua is not in " .. ROOT .. " (set OLYMPUS_ROOT to the record branch)") end
-- (record-check finds its root from arg[0]; give it its own path while it loads)
local self0 = arg[0]
arg[0] = ROOT .. "scripts/record-check.lua"
local Check = checkChunk("--module")
local R = Check.Load()
arg[0] = self0
local ns = { L = setmetatable({}, { __index = function(_, k) return k end }) }
assert(loadfile(ROOT .. "Olympus/Sign.lua"))("Olympus", ns)
local SHA256 = ns.Sign.SHA256

local BOUND = Check.BOUND -- seconds after a slot that still count as one instant
local MARK_WINDOW = 10    -- manual marks this close together are compared

local function Csv(value)
	value = tostring(value == nil and "" or value)
	if value:find('[,"\n]') then value = '"' .. value:gsub('"', '""') .. '"' end
	return value
end

local function WriteCsv(path, header, rows)
	local file = assert(io.open(path, "wb"))
	file:write(table.concat(header, ","), "\n")
	for _, row in ipairs(rows) do
		local cells = {}
		for i, key in ipairs(header) do cells[i] = Csv(row[key]) end
		file:write(table.concat(cells, ","), "\n")
	end
	file:close()
end

local function Utc(t) return t and os.date("!%Y-%m-%d %H:%M:%S", t) or "" end

os.execute(("mkdir -p %q"):format(outDir))

-- Steps 1 and 2: each file read as data, each session's chain.
local manifest, problems, entries = {}, {}, {}
for i = 2, #arg do
	local path = arg[i]
	local file = io.open(path, "rb")
	local text = file and file:read("*a")
	if file then file:close() end
	if not text then
		problems[#problems + 1] = ("%s: cannot be read"):format(path)
		manifest[#manifest + 1] = { file = path, refused = "cannot be read" }
	else
		local row = { file = path, bytes = #text, sha256 = R.Hex(SHA256(text)), sessions = 0 }
		manifest[#manifest + 1] = row
		local ok, parsed = pcall(Check.Parse, text)
		if not ok then
			row.refused = tostring(parsed)
			problems[#problems + 1] = ("%s: not a SavedVariables file (%s)"):format(path, row.refused)
		else
			local sessions, why = Check.Sessions(R, parsed.OlympusRecordDB, path)
			-- The census reports each session heard (E lines), as Record.VerifyFile reads them.
			local claimsOf = {}
			for _, v in ipairs(R.VerifyFile(parsed.OlympusRecordDB, nil).sessions) do
				local list = {}
				for _, o in ipairs(v.observations) do
					if o.kind == "E" then list[#list + 1] = o end
				end
				if v.id then claimsOf[v.id] = list end
			end
			for _, e in ipairs(sessions) do e.claims = e.id and claimsOf[e.id] or {} end
			if why then
				row.refused = why
				problems[#problems + 1] = ("%s: %s (record mode was never on here, or another format)"):format(path, why)
			end
			row.sessions = #sessions
			for _, e in ipairs(sessions) do
				entries[#entries + 1] = e
				if not e.ok then
					problems[#problems + 1] = ("%s: session %s (%s) chain broken at line %s: %s"):format(path, tostring(e.id),
						tostring(e.char), tostring(e.at), tostring(e.why))
				end
			end
		end
	end
end

-- Step 3: copies of one session must be identical.
local kept, conflicts = Check.Dedupe(entries)
local conflicted = {}
for _, c in ipairs(conflicts) do
	conflicted[c.id] = true
	problems[#problems + 1] = ("session %s: the copies differ (%s); every copy is left out of the counts"):format(tostring(c.id), table.concat(c.files, ", "))
end
local copies = {}
for _, e in ipairs(entries) do if e.id then copies[e.id] = (copies[e.id] or 0) + 1 end end

-- Steps 6 and 7: each witness once per guild and quarter hour.
local groups = Check.Compare(kept, BOUND)

local witnessRows = {}
for _, e in ipairs(entries) do
	witnessRows[#witnessRows + 1] = {
		file = e.file, id = e.id, character = e.char, guild = e.guild, battleTagHash = e.tag, start = Utc(tonumber(e.start)),
		lines = e.lines, head = e.head,
		chain = conflicted[e.id] and "COPIES DIFFER" or (e.ok and "ok" or ("BROKEN at line %s: %s"):format(tostring(e.at), tostring(e.why))),
		copies = copies[e.id],
	}
end

local function Intersection(sets)
	local count = {}
	for _, set in ipairs(sets) do for _, name in ipairs(set) do count[name] = (count[name] or 0) + 1 end end
	local out = {}
	for name, n in pairs(count) do if n == #sets then out[#out + 1] = name end end
	table.sort(out)
	return out
end

local function Part(s)
	return ("%s %s/%d +%ds%s"):format(tostring(s.who), tostring(s.c.total), #s.c.onlineSet, s.c.late or -1,
		s.readings > 1 and (" (%d readings)"):format(s.readings) or "")
end

-- Step 8, witnessed part: per guild, the online set its witnesses agree on, else their intersection.
local checkpointRows, slots, slotOrder = {}, {}, {}
local function Slot(t)
	local s = slots[t]
	if not s then
		s = { slot = t, online = 0, guilds = 0, worst = 0, single = 0, disagree = 0, witnessed = {}, claims = 0, claimGuilds = 0 }
		slots[t], slotOrder[#slotOrder + 1] = s, t
	end
	return s
end
for _, g in ipairs(groups) do
	local sets, parts, lateParts, worst = {}, {}, {}, nil
	for _, s in ipairs(g.seen) do
		sets[#sets + 1] = s.c.onlineSet
		parts[#parts + 1] = Part(s)
		if not worst or s.c.late > worst then worst = s.c.late end
	end
	for _, s in ipairs(g.late) do lateParts[#lateParts + 1] = Part(s) end
	local online = #g.seen > 0 and #Intersection(sets) or nil
	local flags = {}
	if #g.seen == 1 then flags[#flags + 1] = "single witness" end
	if #g.seen > 1 and not g.agree then flags[#flags + 1] = "witnesses disagree: intersection used" end
	if #g.seen == 0 then flags[#flags + 1] = ("no reading within %d s"):format(BOUND) end
	checkpointRows[#checkpointRows + 1] = {
		slot = Utc(g.slot), guild = g.guild, witnesses = #g.seen, agree = #g.seen > 1 and (g.agree and "yes" or "NO") or "",
		online = online, latest = worst and ("+" .. worst .. "s") or "", flags = table.concat(flags, "; "),
		seen = table.concat(parts, "; "), late = table.concat(lateParts, "; "),
	}
	local s = Slot(g.slot)
	if online then
		s.online, s.guilds = s.online + online, s.guilds + 1
		if worst > s.worst then s.worst = worst end
		if #g.seen == 1 then s.single = s.single + 1 end
		if not g.agree then s.disagree = s.disagree + 1 end
		s.witnessed[g.guild:lower()] = true
	end
end

-- Step 8, reporters' claims: the E lines (Record.VerifyFile's "E" observations: guild, reportedAt,
-- total, online, users, reporter) for guilds no witness read at that instant. Each report once,
-- whoever heard it; never part of the witnessed figure.
local claims, claimRows = {}, {}
for _, e in ipairs(kept) do
	if e.ok then
		for _, o in ipairs(e.claims or {}) do
			local reportSt = o.reportedAt
			local key = tostring(o.guild):lower() .. "\0" .. tostring(reportSt) .. "\0" .. tostring(o.reporter)
			if reportSt and not claims[key] then
				local t = reportSt - reportSt % 900
				claims[key] = { slot = t, guild = tostring(o.guild), reportSt = reportSt, total = o.total, online = o.online,
					users = o.users, sender = o.reporter, heardBy = e.char }
			end
		end
	end
end
for _, c in pairs(claims) do
	local s = slots[c.slot]
	if not (s and s.witnessed[c.guild:lower()]) then
		local d = c.reportSt - c.slot
		local within = d <= BOUND
		claimRows[#claimRows + 1] = { slot = Utc(c.slot), guild = c.guild, online = c.online, total = c.total, users = c.users,
			reporter = c.sender, heardBy = c.heardBy, after = ("+%ds"):format(d),
			label = within and "reporter's claim, not witnessed; within one instant" or ("reporter's claim, not witnessed; read %d s after T"):format(d) }
		if within then
			s = Slot(c.slot)
			s.claims, s.claimGuilds = s.claims + (c.online or 0), s.claimGuilds + 1
		end
	end
end
table.sort(claimRows, function(a, b)
	if a.slot ~= b.slot then return a.slot < b.slot end
	return a.guild < b.guild
end)

table.sort(slotOrder)
local figureRows = {}
for _, t in ipairs(slotOrder) do
	local s = slots[t]
	figureRows[#figureRows + 1] = {
		slot = Utc(t), witnessed = s.online, guilds = s.guilds, latest = ("+%ds"):format(s.worst),
		singleWitness = s.single, disagreements = s.disagree,
		claimsWithin = s.claims, claimGuilds = s.claimGuilds, withClaims = s.online + s.claims,
		label = "characters online at T = accounts online at T among the guilds' rosters",
	}
end

-- Step 9: manual marks, compared only where several witnesses marked within MARK_WINDOW seconds.
local marks = {}
for _, e in ipairs(kept) do
	if e.ok then
		for _, c in ipairs(e.checkpoints) do
			if c.kind == "M" then marks[#marks + 1] = { who = e.char, c = c } end
		end
	end
end
table.sort(marks, function(a, b) return (a.c.at or 0) < (b.c.at or 0) end)
local markRows, group = {}, 0
for i, m in ipairs(marks) do
	if i == 1 or (m.c.at or 0) - (marks[i - 1].c.at or 0) > MARK_WINDOW then group = group + 1 end
	markRows[#markRows + 1] = { group = group, asked = Utc(m.c.slot), read = Utc(m.c.at), guild = m.c.guild, witness = m.who,
		total = m.c.total, online = #m.c.onlineSet }
end
local markGroups = {}
for _, row in ipairs(markRows) do
	local g = markGroups[row.group] or { n = 0, values = {} }
	markGroups[row.group] = g
	g.n = g.n + 1
	g.values[row.guild:lower() .. " " .. tostring(row.total) .. "/" .. tostring(row.online)] = true
end
for _, row in ipairs(markRows) do
	local g = markGroups[row.group]
	local distinct = 0
	for _ in pairs(g.values) do distinct = distinct + 1 end
	row.compared = g.n < 2 and "alone, not compared" or (distinct == 1 and "agree" or "differ")
end

WriteCsv(outDir .. "/manifest.csv", { "file", "bytes", "sha256", "sessions", "refused" }, manifest)
WriteCsv(outDir .. "/witnesses.csv", { "file", "id", "character", "guild", "battleTagHash", "start", "lines", "head", "chain", "copies" }, witnessRows)
WriteCsv(outDir .. "/checkpoints.csv", { "slot", "guild", "witnesses", "agree", "online", "latest", "flags", "seen", "late" }, checkpointRows)
WriteCsv(outDir .. "/figures.csv", { "slot", "witnessed", "guilds", "latest", "singleWitness", "disagreements", "claimsWithin", "claimGuilds", "withClaims", "label" }, figureRows)
WriteCsv(outDir .. "/claims.csv", { "slot", "guild", "online", "total", "users", "reporter", "heardBy", "after", "label" }, claimRows)
WriteCsv(outDir .. "/marks.csv", { "group", "asked", "read", "guild", "witness", "total", "online", "compared" }, markRows)

local counted = 0
for _, e in ipairs(kept) do if e.ok then counted = counted + 1 end end
local confirmed, single, disagree = 0, 0, 0
for _, g in ipairs(groups) do
	if #g.seen == 1 then single = single + 1
	elseif #g.seen > 1 and g.agree then confirmed = confirmed + 1
	elseif #g.seen > 1 then disagree = disagree + 1 end
end
local best
for _, row in ipairs(figureRows) do if not best or row.witnessed > best.witnessed then best = row end end
local summary = {
	("Files: %d, sessions: %d (%d counted: chain intact, one copy), guild checkpoints: %d"):format(#manifest, #entries, counted, #groups),
	("Guild checkpoints read by 2 or more witnesses who agree: %d; who disagree: %d; by a single witness: %d"):format(confirmed, disagree, single),
	("One instant = read at most %d s after the quarter hour; later readings are listed, never added."):format(BOUND),
	best and ("Highest witnessed figure: %d characters online at %s UTC (%d guild(s), latest reading %s); with reporters' claims within one instant: %d")
		:format(best.witnessed, best.slot, best.guilds, best.latest, best.withClaims) or "No quarter hour was witnessed.",
	"",
	"Problems:",
}
for _, p in ipairs(problems) do summary[#summary + 1] = "  - " .. p end
if #problems == 0 then summary[#summary + 1] = "  none" end
local out = assert(io.open(outDir .. "/summary.txt", "wb"))
out:write(table.concat(summary, "\n"), "\n")
out:close()
print(table.concat(summary, "\n"))
os.exit(#problems > 0 and 1 or 0)

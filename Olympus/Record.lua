local ADDON, ns = ...
local L = ns.L

-- Record mode (the Guinness attempt, 2026-10-20 and 21): a witness's own file. With /oly record on
-- (off by default, kept per character until /oly record off) this client writes to its own
-- SavedVariable, OlympusRecordDB (Olympus.toc), and to nothing else:
--   - its own guild's roster at each quarter hour of the server's clock (:00, :15, :30, :45) and at
--     each /oly record mark, never in combat: each member once (name-realm, GUID, class, level at
--     first sight), then per checkpoint who is on the roster, who is online and whose level changed;
--   - the first census report this client accepts (Data.Receive) from each guild in each quarter
--     hour;
--   - who wrote it: character, GUID, guild and rank, faction, realm, versions, BattleTag if any.
-- Every record is one line of text, and each line is hashed into a chain (SHA-256, Sign.SHA256)
-- that starts from the witness's GUID and the session's start. Nothing secret goes into the chain,
-- so whoever edits the file can compute it again: it proves that the file is unedited only up to
-- a head published at the time (shown in the status), and the count's truth rests on independent
-- witnesses whose files agree. docs/RECORD-FORMAT.md gives the exact format and hash rule, for the
-- offline verifier.
-- Nothing here sends anything: no addon message, no chat line, no whisper (tests/record.lua reads
-- this file's source for it). SavedVariables reach the disk only at /reload, logout or quit.

local Record = {}
ns.Record = Record

Record.FORMAT = "olympus-record"
Record.VERSION = 1
Record.SEED = "olympus-record-1|"  -- the chain's seed: SHA-256 of this, the GUID, "|" and the start
Record.SLOT = 15 * 60              -- checkpoints at each quarter hour of the server's clock
Record.SLOT_LATE = 5 * 60          -- a checkpoint not read this long after its time (combat) is missed
Record.TICK = 5                    -- how often the clock is looked at while record mode is on
Record.READ_WAIT = 4               -- the roster read this long after asking the server, at the latest
Record.READ_TRIES = 3              -- asked again while the game gives fewer rows than members
Record.MARK_GAP = 60               -- one /oly record mark a minute
Record.EVENTS_PER_DAY = 7000       -- census report lines kept a UTC day at most (70 guilds: 6,720)
Record.LINES_MAX = 30000           -- lines a file holds at most (about 2.5 MB): then nothing more
Record.HASH_BUDGET = 2048          -- bytes of lines chained per frame (the rest on the next frames)

---------------------------------------------------------------------------
-- The format (docs/RECORD-FORMAT.md). Pure functions: the tests and scripts/record-check.lua use
-- them as they are.
---------------------------------------------------------------------------

local HEXBYTE, NIBBLE = {}, {}
for i = 0, 255 do HEXBYTE[string.char(i)] = ("%02x"):format(i) end
for i = 0, 15 do NIBBLE[i] = ("%x"):format(i) end

-- 32 bytes as 64 lowercase hex digits.
function Record.Hex(bytes) return (bytes:gsub(".", HEXBYTE)) end
function Record.Hash(text) return Record.Hex(ns.Sign.SHA256(text)) end
-- A line's hash from the one before it (or the seed).
function Record.Link(prev, line) return Record.Hash(prev .. "|" .. line) end
-- The seed, from the S line's GUID and start fields as they are written.
function Record.Seed(guid, start) return Record.Hash(Record.SEED .. guid .. "|" .. start) end

-- A text field: every control byte, " \ | , and : becomes _ (bytes of UTF-8 letters stay as they
-- are), so no line ever needs an escape in the saved file. nil is the empty field.
function Record.Field(v)
	if v == nil then return "" end
	return (tostring(v):gsub('[%c"\\|,:]', "_"))
end
-- A number field: a whole number from 0 up, in decimal, no sign, point or exponent; anything else
-- is the empty field.
function Record.Int(v)
	local n = tonumber(v)
	if not n or n ~= n or n < 0 or n >= 2 ^ 53 then return "" end
	return ("%.0f"):format(math.floor(n))
end
local Field, Int = Record.Field, Record.Int

-- A set of member numbers (set[i] = true, i from 1 to top) as hex digits: digit d holds members
-- 4d-3 (8), 4d-2 (4), 4d-1 (2) and 4d (1); the zero digits at the end are left out.
function Record.Bitmap(set, top)
	local out, last = {}, 0
	for d = 1, math.ceil((top or 0) / 4) do
		local b = (d - 1) * 4
		local v = (set[b + 1] and 8 or 0) + (set[b + 2] and 4 or 0) + (set[b + 3] and 2 or 0) + (set[b + 4] and 1 or 0)
		out[d] = NIBBLE[v]
		if v > 0 then last = d end
	end
	return table.concat(out, "", 1, last)
end
-- The set back, and its size; nil for a text that is no bitmap.
local WEIGHTS = { 8, 4, 2, 1 }
function Record.Unbitmap(hex)
	if type(hex) ~= "string" or hex:find("[^0-9a-f]") then return nil end
	local set, n = {}, 0
	for d = 1, #hex do
		local v, b = tonumber(hex:sub(d, d), 16), (d - 1) * 4
		for k, weight in ipairs(WEIGHTS) do
			if v >= weight then
				v = v - weight
				set[b + k], n = true, n + 1
			end
		end
	end
	return set, n
end

-- A line's fields (split on "|").
function Record.Split(line)
	local out = {}
	for f in (tostring(line) .. "|"):gmatch("([^|]*)|") do out[#out + 1] = f end
	return out
end
local function Line(...) return table.concat({ ... }, "|") end

-- A session as the file holds it: true, the chain's head and the lines it covers when every stored
-- hash (marks, head) is what its lines give; else false, the first line found wrong (0: the session
-- itself) and why.
function Record.Verify(s)
	if type(s) ~= "table" or type(s.lines) ~= "table" then return false, 0, "no lines" end
	local first = s.lines[1]
	if type(first) ~= "string" or first:sub(1, 4) ~= "S|1|" then return false, 1, "the first line is no S line of format 1" end
	local f = Record.Split(first)
	if s.id ~= nil and s.id ~= f[5] .. ":" .. f[3] then return false, 0, "the id is not the S line's GUID and start" end
	local marks = {}
	for _, m in ipairs(type(s.marks) == "table" and s.marks or {}) do
		local i, hex = tostring(m):match("^(%d+):(%x+)$")
		if not i then return false, 0, "a mark that is no mark: " .. tostring(m) end
		marks[tonumber(i)] = hex
	end
	local n, upto = #s.lines, tonumber(s.n) or #s.lines
	if upto > n then return false, 0, "n is past the last line" end
	local h, head = Record.Seed(f[5], f[3]), nil
	for i = 1, n do
		local line = s.lines[i]
		if type(line) ~= "string" then return false, i, "a line that is not text" end
		h = Record.Link(h, line)
		if marks[i] and marks[i] ~= h then return false, i, "its mark is not its hash" end
		marks[i] = nil
		if i == upto then head = h end
	end
	if next(marks) then return false, next(marks), "a mark past the last line" end
	if upto == 0 then head = Record.Seed(f[5], f[3]) end
	if s.head ~= nil and s.head ~= head then return false, upto, "the head is not the hash of line n" end
	return true, h, n
end

---------------------------------------------------------------------------
-- The witness's client
---------------------------------------------------------------------------

local function Public(v)
	if v == nil then return nil end
	if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
	return v
end
local function Text(v)
	v = Public(v)
	return type(v) == "string" and v ~= "" and v or nil
end
local function Now() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or nil end
local function InCombat() return InCombatLockdown and InCombatLockdown() and true or false end
local function Clock(t, short)
	if type(t) ~= "number" or not date then return "?" end
	return date(short and "!%H:%M UTC" or "!%Y-%m-%d %H:%M:%S UTC", t)
end

local db             -- OlympusRecordDB once it is open (nil until record mode is first turned on)
local lines = 0      -- lines in the whole file (Record.LINES_MAX)
local loaded = 0     -- sessions the game loaded back from the file at login
local persisted = false -- the file loaded back holds a logout's write (the game loads saved data)
local cur            -- the session being written (Begin)
local pending        -- the checkpoint being read: { kind, slot, tries }
local markWanted, lastMark

-- OlympusRecordDB, made when create (the first /oly record on). nil when it is another format's.
local function Open(create)
	if db then return db end
	local t = OlympusRecordDB
	if type(t) ~= "table" then
		if not create then return nil end
		t = {}
		OlympusRecordDB = t
	end
	if (t.format ~= nil and t.format ~= Record.FORMAT) or (t.version ~= nil and t.version ~= Record.VERSION) then return nil end
	t.format, t.version = Record.FORMAT, Record.VERSION
	if type(t.on) ~= "table" then t.on = {} end
	if type(t.sessions) ~= "table" then t.sessions = {} end
	t.events = math.max(0, math.floor(tonumber(t.events) or 0))
	t.eventsDay = math.floor(tonumber(t.eventsDay) or 0)
	lines = 0
	for _, s in ipairs(t.sessions) do
		if type(s) == "table" and type(s.lines) == "table" then lines = lines + #s.lines end
	end
	db = t
	return db
end

function Record.On() return db ~= nil and ns.me ~= nil and db.on[ns.me] ~= nil end
function Record.Recording() return cur ~= nil end

-- The chain: each line's hash from the one before, a few lines a frame (Sign.SHA256 is plain Lua:
-- a guild's first checkpoint, a thousand member lines, would be a hitch at once), all of it at once
-- when the session ends. A mark is kept for the lines that ask for one (S, C, Z).
local hashQueued = false
local function HashSome(budget)
	local c = cur
	if not c then return end
	local s, spent = c.s, 0
	while c.hashed < #s.lines and (budget == nil or spent < budget) do
		local i = c.hashed + 1
		local line = s.lines[i]
		c.prev, c.hashed = Record.Link(c.prev, line), i
		spent = spent + #line + 65
		if c.markAt[i] then
			s.marks[#s.marks + 1] = Int(i) .. ":" .. c.prev
			c.markAt[i] = nil
		end
	end
	s.head, s.n = c.prev, c.hashed
end
local QueueHash
local function HashStep()
	hashQueued = false
	if not cur then return end
	if not InCombat() then HashSome(Record.HASH_BUDGET) end
	if cur.hashed < #cur.s.lines then QueueHash(InCombat() and 1 or 0) end
end
QueueHash = function(delay)
	if hashQueued then return end
	hashQueued = true
	ns.After(delay or 0, "record chain", HashStep)
end

local function Append(line, mark)
	local s = cur.s
	s.lines[#s.lines + 1] = line
	lines = lines + 1
	if mark then cur.markAt[#s.lines] = true end
	QueueHash()
end

local function TestBuildN()
	local t = rawget(ns, "TEST_BUILD")
	local n = type(t) == "table" and tonumber(t.n) or nil
	return n and n >= 1 and n <= 999 and n == math.floor(n) and n or nil
end
-- The player's own BattleTag (BNGetInfo's second return, as Blizzard's FriendsFrame reads it), nil
-- when the game gives none.
local function BattleTag()
	if type(BNGetInfo) ~= "function" then return nil end
	local ok, _, tag = pcall(BNGetInfo)
	return ok and Text(tag) or nil
end
local function ClientBuild()
	if type(GetBuildInfo) ~= "function" then return nil, nil end
	local version, build, _, interface = GetBuildInfo()
	if version and build then version = tostring(version) .. "." .. tostring(build) end
	return version, interface
end

-- A session: one login (or /reload) of this character while record mode is on, in one guild.
local function Begin(now, guild, rankName, rankIndex)
	local guid = Text(UnitGUID and UnitGUID("player"))
	local build, interface = ClientBuild()
	local first = Line("S", "1", Int(now), Field(ns.me), Field(guid), Field(guild), Int(rankIndex), Field(rankName),
		Field(ns.faction or (ns.Faction and ns.Faction())), Field(ns.realm), Field(ns.group), Field(ns.VERSION),
		Int(TestBuildN()), Field(BattleTag()), Int(interface), Field(build), Field(GetLocale and GetLocale()))
	local f = Record.Split(first)
	local s = { id = f[5] .. ":" .. f[3], char = ns.me, start = now, lines = {}, marks = {}, n = 0 }
	db.sessions[#db.sessions + 1] = s
	cur = { s = s, guild = guild, dict = {}, levels = {}, top = 0, prev = Record.Seed(f[5], f[3]), hashed = 0,
		markAt = {}, heard = {}, checkpoints = 0, events = 0, skipped = 0, lastSlot = 0, battleTag = f[14] }
	s.head = cur.prev
	Append(first, true)
end

local function End(reason)
	if not cur then return end
	local at = Now() or cur.s.start
	Append(Line("Z", Int(at), Field(reason), Int(cur.skipped)), true)
	HashSome(nil)
	cur.s.ended = at
	cur, pending = nil, nil
end

-- The guild roster as the game gives it now (GetGuildRosterInfo: name 1st, level 4th, online 9th,
-- class file 11th, GUID 17th, as Blizzard's Classic FriendsFrame.lua reads them).
local function ReadRoster()
	local total, online = GetNumGuildMembers()
	total = tonumber(Public(total)) or 0
	local rows = {}
	for i = 1, total do
		local name, _, _, level, _, _, _, _, isOnline, _, classFile, _, _, _, _, _, guid = GetGuildRosterInfo(i)
		name = Text(name)
		if name then
			rows[#rows + 1] = { name = ns.FullName(name) or name, guid = Text(guid) or "", class = Text(classFile) or "",
				level = tonumber(Public(level)) or 0, online = Public(isOnline) and true or false }
		end
	end
	return { total = total, online = tonumber(Public(online)), rows = rows }
end

-- One checkpoint: the members new to this session first (M lines), then the checkpoint (C).
local function Store(p, snap, at)
	local c = cur
	local present, online, changed, changes, rowsOnline = {}, {}, {}, {}, 0
	for _, row in ipairs(snap.rows) do
		local key = row.name .. "\0" .. row.guid
		local i = c.dict[key]
		if not i then
			c.top = c.top + 1
			i = c.top
			c.dict[key], c.levels[i] = i, row.level
			Append(Line("M", Int(i), Field(row.name), Field(row.guid), Field(row.class), Int(row.level)))
		elseif c.levels[i] ~= row.level and not changed[i] then
			changed[i], c.levels[i] = true, row.level
			changes[#changes + 1] = i
		end
		present[i] = true
		if row.online then
			online[i] = true
			rowsOnline = rowsOnline + 1
		end
	end
	table.sort(changes)
	for k, i in ipairs(changes) do changes[k] = Int(i) .. ":" .. Int(c.levels[i]) end
	local guild = Text(GetGuildInfo("player")) or c.guild
	Append(Line("C", p.kind, Int(p.slot), Int(at), Field(guild), Int(snap.total), Int(snap.online), Int(#snap.rows),
		Int(rowsOnline), Record.Bitmap(present, c.top), Record.Bitmap(online, c.top), table.concat(changes, ",")), true)
	c.checkpoints = c.checkpoints + 1
	c.last = { at = at, online = rowsOnline, total = snap.total, rows = #snap.rows }
	if p.kind == "M" then ns.Print(L.RECORD_MARK_DONE:format(Clock(at), rowsOnline, snap.total)) end
end

local function RequestRoster()
	if C_GuildInfo and C_GuildInfo.GuildRoster then
		C_GuildInfo.GuildRoster()
	elseif GuildRoster then
		GuildRoster()
	end
end
local Read
local function Ask(p)
	pending = p
	p.tries = (p.tries or 0) + 1
	RequestRoster()
	ns.After(Record.READ_WAIT, "record read", function() Read(p) end)
end
Read = function(p)
	if pending ~= p or not cur then return end
	if InCombat() then
		p.waiting = true -- (the clock's next look reads it, out of combat)
		return
	end
	local at = Now()
	if not at then return end
	local snap = ReadRoster()
	-- (Right after login the game may give no roster yet: asked again too.)
	if (#snap.rows < snap.total or snap.total == 0) and p.tries < Record.READ_TRIES then return Ask(p) end
	pending = nil
	Store(p, snap, at)
end

-- Every TICK while record mode is on: a session begun or ended, a checkpoint due.
local function Tick()
	if not Record.On() then return end
	local now = Now()
	if not now then return end
	local guild, rankName, rankIndex = GetGuildInfo("player")
	guild = Text(guild)
	if cur and guild ~= cur.guild then End("guild") end
	if cur and lines >= Record.LINES_MAX then End("full") end
	if not cur then
		if not guild or lines >= Record.LINES_MAX then return end
		Begin(now, guild, Text(rankName), tonumber(Public(rankIndex)))
	end
	if pending then
		if now - pending.slot > Record.SLOT_LATE then
			pending = nil -- (missed: the C lines show which checkpoints were read)
		elseif pending.waiting and not InCombat() then
			pending.waiting = nil
			Read(pending)
		end
		return
	end
	if InCombat() then return end
	if markWanted then
		local at = markWanted
		markWanted = nil
		if now - at <= Record.SLOT_LATE then return Ask({ kind = "M", slot = at }) end
	end
	local slot = now - now % Record.SLOT
	if slot > cur.lastSlot and now - slot < Record.SLOT_LATE then
		cur.lastSlot = slot
		Ask({ kind = "Q", slot = slot })
	end
end

local ticker, hooked = nil, false
local function OnRoster()
	local p = pending
	if not p or p.soon then return end
	p.soon = true
	ns.After(1, "record roster", function()
		p.soon = nil
		Read(p)
	end)
end
local function OnLogout()
	if cur then End("logout") end
	if db then db.saves = math.max(0, math.floor(tonumber(db.saves) or 0)) + 1 end
end
local function Events()
	if hooked then return end
	hooked = true
	ns.RegisterEvent("GUILD_ROSTER_UPDATE", OnRoster)
	ns.RegisterEvent("PLAYER_LOGOUT", OnLogout)
end
local function Start()
	Events()
	if not ticker then ticker = ns.Every(Record.TICK, "record clock", Tick) end
	Tick()
end
local function Stop()
	if ticker then ticker.Cancel() end
	ticker = nil
end

-- A census report Data.Receive took (r: its row): the first of its guild in this quarter hour is
-- kept, EVENTS_PER_DAY a UTC day at most. The reporter is the sender's name as the server stamped it.
function Record.Heard(r)
	local c = cur
	if not c or type(r) ~= "table" or type(r.guild) ~= "string" then return end
	local at = Now()
	if not at then return end
	local slot, key = at - at % Record.SLOT, r.guild:lower()
	if c.heard[key] == slot then return end
	local day = math.floor(at / 86400)
	if db.eventsDay ~= day then db.eventsDay, db.events = day, 0 end
	if db.events >= Record.EVENTS_PER_DAY or lines >= Record.LINES_MAX then
		c.skipped = c.skipped + 1
		return
	end
	c.heard[key] = slot
	db.events, c.events = db.events + 1, c.events + 1
	Append(Line("E", Int(at), Int(r.st), Field(r.guild), Int(r.total), Int(r.online), Int(r.users), Field(r.reporterFull)))
end

ns.On("INIT", function()
	local t = OlympusRecordDB
	loaded = type(t) == "table" and type(t.sessions) == "table" and #t.sessions or 0
	persisted = type(t) == "table" and (tonumber(t.saves) or 0) > 0
	if Open(false) then Events() end
end)
ns.On("LOGIN", function()
	if Record.On() then Start() end
end)

---------------------------------------------------------------------------
-- The command, the status and the window's line
---------------------------------------------------------------------------

function Record.StatusText()
	local out = {}
	local function Add(s) out[#out + 1] = s end
	Add(L.RECORD_TITLE)
	Add(Record.On() and L.RECORD_STATE_ON:format(ns.DisplayName(ns.me) or "?", Clock(db.on[ns.me])) or L.RECORD_STATE_OFF)
	Add(L.RECORD_WHAT)
	local now = Now()
	if cur then
		local s = cur.s
		Add(L.RECORD_SESSION:format(Clock(s.start), #s.lines, cur.checkpoints, cur.events, cur.hashed, cur.prev:sub(1, 16)))
		if cur.last then
			Add(L.RECORD_LAST:format(Clock(cur.last.at), cur.last.online, cur.last.total, cur.last.rows))
			if cur.last.rows < cur.last.total then Add(L.RECORD_PARTIAL) end
		end
		if now then Add(L.RECORD_NEXT:format(Clock(now - now % Record.SLOT + Record.SLOT, true))) end
		if cur.hashed < #s.lines then Add(L.RECORD_HASHING:format(#s.lines - cur.hashed)) end
	elseif Record.On() then
		Add(lines >= Record.LINES_MAX and L.RECORD_FULL:format(lines) or now and L.RECORD_WAITING or L.RECORD_NO_CLOCK)
	end
	local tag = cur and cur.battleTag or Field(BattleTag())
	Add(tag ~= "" and L.RECORD_BATTLETAG:format(tag) or L.RECORD_NO_BATTLETAG)
	local today = now and db and db.eventsDay == math.floor(now / 86400) and db.events or 0
	Add(L.RECORD_EVENTS:format(today, Record.EVENTS_PER_DAY, cur and cur.skipped or 0))
	Add(persisted and L.RECORD_LOADED:format(loaded) or L.RECORD_NOT_LOADED)
	Add(L.RECORD_SEND)
	Add(L.RECORD_FILE)
	Add(L.RECORD_NOTHING_SENT)
	Add(L.RECORD_COMMANDS)
	return table.concat(out, "\n")
end

function Record.ShowStatus()
	local text = Record.StatusText()
	if ns.UI and ns.UI.ShowCopy then return ns.UI.ShowCopy(L.RECORD_TITLE, text, nil, { key = "record" }) end
	ns.Print(text)
end

-- The census page's first line while record mode is on (Views.lua): a click opens the status.
function Record.Line()
	if not Record.On() then return nil end
	local now = Now()
	local nextAt = now and (now - now % Record.SLOT + Record.SLOT)
	return { text = "|cffff5555" .. L.RECORD_LINE:format(Clock(nextAt, true)) .. "|r", gapAfter = true,
		onClick = function() Record.ShowStatus() end }
end

-- /oly record [on | off | status | mark]
function Record.Slash(rest)
	local verb = (tostring(rest or "")):lower():match("^%s*(%S*)") or ""
	if verb == "" or verb == "status" then return Record.ShowStatus() end
	if verb == "on" then
		local d = Open(true)
		if not d then return ns.Print(L.RECORD_OTHER_FORMAT) end
		if not Now() then return ns.Print(L.RECORD_NO_CLOCK) end
		if d.on[ns.me] == nil then d.on[ns.me] = Now() end
		Start()
		ns.Print(L.RECORD_ON)
		return Record.ShowStatus()
	elseif verb == "off" then
		if not Record.On() then return ns.Print(L.RECORD_ALREADY_OFF) end
		End("off")
		db.on[ns.me] = nil
		Stop()
		markWanted = nil
		return ns.Print(L.RECORD_OFF)
	elseif verb == "mark" then
		if not Record.On() then return ns.Print(L.RECORD_NOT_ON) end
		local now = Now()
		if not now then return ns.Print(L.RECORD_NO_CLOCK) end
		if lastMark and now - lastMark < Record.MARK_GAP then return ns.Print(L.RECORD_MARK_WAIT:format(Record.MARK_GAP - (now - lastMark))) end
		lastMark, markWanted = now, now
		ns.Print(InCombat() and L.RECORD_MARK_COMBAT or L.RECORD_MARK_ASKED)
		return Tick()
	end
	ns.Print(L.HELP_CMD_RECORD)
end

-- Tests: this module's session state forgotten (OlympusRecordDB itself is the test's).
function Record.Reset()
	Stop()
	db, lines, loaded, persisted, cur, pending, markWanted, lastMark, hashQueued = nil, 0, 0, false, nil, nil, nil, nil, false
end

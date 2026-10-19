-- Record mode (Record.lua, /oly record): the Guinness attempt's witnesses' own file, its format
-- (docs/RECORD-FORMAT.md), its hash chain and the sample the offline verifier is built against
-- (tests/fixtures/record-sample.lua, record-sample-b.lua). Loaded by tests/run.lua.
--   OLYMPUS_RECORD_SAMPLE_WRITE=1  rewrites the two fixtures from what the format gives now
--   OLYMPUS_RECORD_SAMPLE_OUT=DIR  also writes them to DIR (OlympusRecordDB-sample.lua, -b.lua)
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]record%.lua$")) or "./"

local function ReadFile(path)
	local f = io.open(path, "rb")
	if not f then return nil end
	local text = f:read("*a")
	f:close()
	return text
end
local function WriteFile(path, text)
	local f = assert(io.open(path, "wb"))
	f:write(text)
	f:close()
end

-- The record lines' English (Locales/RecordText.lua) on the harness's table, as the TOC loads it.
assert(loadfile(ROOT .. "Olympus/Locales/RecordText.lua"))("Olympus", ns)
local L = ns.L

-- 2026-10-20 14:00:00 UTC, a quarter hour of the server's clock.
local T14 = 1792504800

-- A roster member of the fake guild: invented names, GUIDs of a server id no realm has.
local function Member(name, guid, class, level, online)
	return { name = name, guid = guid, class = class, level = level, online = online }
end
local function SampleRoster()
	return {
		Member("Leader Example-ClassicBetaPvP", "Player-0000-00000001", "WARRIOR", 60, true),
		Member("Witness Example-ClassicBetaPvP", "Player-0000-0000000A", "PALADIN", 42, true),
		Member("Member Alpha-ClassicBetaPvP", "Player-0000-00000002", "MAGE", 25, false),
		Member("Member Bravo-ClassicBetaPvP2", "Player-0000-00000003", "PRIEST", 33, true),
		Member("Member Charlie-ClassicBetaPvP", "Player-0000-00000004", "ROGUE", 12, false),
		Member("Member Delta-ClassicBetaPvP2", "Player-0000-00000005", "HUNTER", 59, true),
		Member("Witness Second-ClassicBetaPvP", "Player-0000-0000000B", "DRUID", 50, true),
		Member("Member Echo-ClassicBetaPvP", "Player-0000-00000006", "WARLOCK", 18, false),
	}
end

-- Record.lua loaded fresh in a namespace of its own over the harness's, on a clock of the test's:
-- w.step(t) runs the seconds up to t (its timers, its 5-second clock, the server's roster answer one
-- second after each ask), w.event(name), w.login(), w.logout(), w.slash(text). Every way a message
-- could leave is counted (w.sent); the game's globals it reads are the world's, put back by w.close().
local GLOBALS = { "OlympusRecordDB", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "UnitGUID", "BNGetInfo",
	"InCombatLockdown", "C_GuildInfo", "GuildRoster", "GetBuildInfo", "GetLocale", "C_ChatInfo", "SendChatMessage",
	"SendAddonMessage", "GetServerTime", "issecretvalue" }
local function RecordWorld(o)
	o = o or {}
	local w = { clock = o.clock or (T14 - 60), combat = false, roster = o.roster or SampleRoster(), guild = o.guild or "Olympus Example",
		rank = o.rank or 4, rankName = o.rankName or "Soldier", sent = 0, timers = {}, tickers = {}, events = {}, on = {},
		prints = {}, copies = {}, asks = 0, battleTag = o.battleTag }
	local saved = {}
	for _, k in ipairs(GLOBALS) do saved[k] = rawget(_G, k) end
	local function Count() w.sent = w.sent + 1 end
	OlympusRecordDB = o.db
	GetServerTime = function() return w.clock end
	GetGuildInfo = function() if w.guild then return w.guild, w.rankName, w.rank end end
	GetNumGuildMembers = function()
		local online = 0
		for _, m in ipairs(w.roster) do if m.online then online = online + 1 end end
		return #w.roster, online
	end
	GetGuildRosterInfo = function(i)
		local m = w.roster[i]
		if not m or (w.partial and i > w.partial) then return nil end
		return m.name, "rank", 3, m.level, "class", m.online and "Stormwind City" or nil, "", "", m.online, 0, m.class,
			0, 0, false, false, 4, m.guid
	end
	UnitGUID = function(unit) if unit == "player" then return o.guid or "Player-0000-0000000A" end end
	BNGetInfo = function() return 1, w.battleTag, 2, "", false, false, true end
	InCombatLockdown = function() return w.combat end
	C_GuildInfo = { GuildRoster = function()
		w.asks = w.asks + 1
		w.timers[#w.timers + 1] = { at = w.clock + 1, fn = function() w.event("GUILD_ROSTER_UPDATE") end }
	end }
	GuildRoster = function() error("C_GuildInfo.GuildRoster comes first") end
	GetBuildInfo = function() return "1.60.1", "70450", "Oct 1 2026", 16001 end
	GetLocale = function() return "enUS" end
	C_ChatInfo = setmetatable({}, { __index = function() return Count end })
	SendChatMessage, SendAddonMessage = Count, Count
	local rns = setmetatable({
		me = o.me or "Witness Example-ClassicBetaPvP", realm = "ClassicBetaPvP", group = "ClassicBetaPvP", faction = "Alliance",
		VERSION = "1.2.5.1", -- (fixed: the sample must not change with each release)
		Comm = setmetatable({}, { __index = function() return Count end }),
		Data = { ServerTime = function() return w.clock end },
		On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end,
		RegisterEvent = function(name, fn) w.events[name] = w.events[name] or {}; table.insert(w.events[name], fn) end,
		After = function(delay, _, fn) w.timers[#w.timers + 1] = { at = w.clock + math.max(1, delay), fn = fn } end,
		Every = function(period, _, fn)
			local t = { period = period, fn = fn, next = w.clock + period }
			w.tickers[#w.tickers + 1] = t
			return { Cancel = function() t.cancelled = true end }
		end,
		Print = function(text) w.prints[#w.prints + 1] = tostring(text) end,
		UI = { ShowCopy = function(title, text, _, opts) w.copies[#w.copies + 1] = { title = title, text = text, key = opts and opts.key } end },
	}, { __index = ns })
	w.ns = rns
	assert(loadfile(ROOT .. "Olympus/Record.lua"))("Olympus", rns)
	w.R = rns.Record
	function w.fire(name) for _, fn in ipairs(w.on[name] or {}) do fn() end end
	function w.event(name, ...) for _, fn in ipairs(w.events[name] or {}) do fn(...) end end
	function w.step(to)
		while w.clock < to do
			w.clock = w.clock + 1
			local due, later = {}, {}
			for _, t in ipairs(w.timers) do if t.at <= w.clock then due[#due + 1] = t else later[#later + 1] = t end end
			w.timers = later
			for _, t in ipairs(due) do t.fn() end
			for _, t in ipairs(w.tickers) do
				if not t.cancelled and w.clock >= t.next then
					t.next = t.next + t.period
					t.fn()
				end
			end
		end
	end
	function w.login() w.fire("INIT"); w.fire("LOGIN") end
	function w.logout() w.event("PLAYER_LOGOUT") end
	function w.slash(text) w.R.Slash(text) end
	function w.session() return OlympusRecordDB and OlympusRecordDB.sessions[#OlympusRecordDB.sessions] end
	function w.close()
		local db = OlympusRecordDB
		for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
		return db
	end
	return w
end
local function InWorld(o, fn)
	local w = RecordWorld(o)
	local ok, err = pcall(fn, w)
	local db = w.close()
	if not ok then error(err, 0) end
	return db, w
end
-- The lines of a session of one type, split.
local function Typed(R, s, kind)
	local out = {}
	for _, line in ipairs(s.lines) do
		local f = R.Split(line)
		if f[1] == kind then out[#out + 1] = f end
	end
	return out
end
local function Set(R, hex)
	local set = R.Unbitmap(hex)
	local list = {}
	for i in pairs(set) do list[#list + 1] = i end
	table.sort(list)
	return table.concat(list, ",")
end

test("record mode: the format's fields, bitmaps and hash rule (SHA-256, the vectors docs/RECORD-FORMAT.md gives)", function()
	InWorld(nil, function(w)
		local R = w.R
		eq(R.Field('a|b,c:d"e\\f\ng\127'), "a_b_c_d_e_f_g_", "each byte a line could need escaped becomes _")
		eq(R.Field("Fëanor Ásgeir"), "Fëanor Ásgeir", "UTF-8 letters stay as they are")
		eq(R.Field(nil), ""); eq(R.Int(nil), ""); eq(R.Int(-1), ""); eq(R.Int(0 / 0), "")
		eq(R.Int(12.7), "12"); eq(R.Int(1792504800), "1792504800"); eq(R.Int(0), "0")
		eq(R.Bitmap({ [1] = true, [3] = true, [4] = true, [9] = true }, 12), "b08", "members 1, 3, 4: b; 5-8: 0; 9: 8; the zero digit after it left out")
		eq(R.Bitmap({}, 12), ""); eq(R.Bitmap({ [12] = true }, 12), "001")
		eq(Set(R, "b08"), "1,3,4,9"); eq(R.Unbitmap("B0"), nil, "lowercase only")
		eq(table.concat(R.Split("C|Q||5"), ","), "C,Q,,5", "an empty field stays a field")
		-- The vectors (checked against Python's hashlib when written).
		local seed = R.Seed("Player-0000-00000001", "1792483200")
		eq(seed, "fb8d3cadfb9b6377f6f6ca518a1953bdd8edb24e424ee1aef982ecdc7e638b9f")
		local line = "S|1|1792483200|Witness Example-ClassicBetaPvP|Player-0000-00000001|Olympus Example|4|Soldier|Alliance|ClassicBetaPvP|ClassicBetaPvP|1.2.5.1||SampleWitness#0000|16001|1.60.1.70450|enUS"
		eq(R.Link(seed, line), "fab4a9c5c564c053fdf89d00322d9c59b253f74af68cf346ce6b51ac9aa5c080")
		eq(R.Hash(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "Sign.SHA256 itself")
	end)
end)

test("record mode: off by default, nothing is read, written or sent; the census line and the reports wait for an on", function()
	local db, w = InWorld(nil, function(w)
		w.login()
		w.step(T14 + 20 * 60)
		eq(#w.tickers, 0, "no clock runs for a player who never turned it on")
		eq(w.asks, 0, "the roster is never asked for")
		eq(OlympusRecordDB, nil, "and no saved table is made")
		eq(w.R.Line(), nil, "no line in the window")
		w.R.Heard({ guild = "Olympus Heard", total = 900, online = 300, reporterFull = "Reporter One-ClassicBetaPvP" })
		eq(OlympusRecordDB, nil)
		w.slash("status")
		eq(#w.copies, 1, "the status still opens"); eq(w.copies[1].key, "record")
		assert(w.copies[1].text:find(L.RECORD_STATE_OFF, 1, true), w.copies[1].text)
		w.slash("mark")
		eq(w.prints[#w.prints], L.RECORD_NOT_ON)
		w.logout()
	end)
	eq(db, nil, "a logout writes nothing either")
	eq(w.sent, 0)
end)

test("record mode: on is kept for that character until off; checkpoints at :00, :15, :30 and :45 by the server's clock, never in combat; nothing sent", function()
	local db, w = InWorld(nil, function(w)
		w.login()
		w.slash("on")
		eq(w.prints[1], L.RECORD_ON); eq(#w.copies, 1, "on opens the status")
		local on = OlympusRecordDB.on["Witness Example-ClassicBetaPvP"]
		eq(on, T14 - 60, "on since the server's time it was typed")
		local s = w.session()
		eq(#s.lines, 1, "the session begins at once: its S line")
		w.step(T14 + 14 * 60 + 50)
		w.combat = true -- (a fight from 14:14:50 to 14:21: the 14:15 checkpoint is missed, 5 minutes late at most)
		w.step(T14 + 21 * 60)
		w.combat = false
		w.step(T14 + 31 * 60)
		local cs = Typed(w.R, s, "C")
		eq(#cs, 2, "14:00 and 14:30; 14:15 fell in the fight")
		eq(cs[1][2], "Q"); eq(cs[1][3], tostring(T14)); eq(cs[1][4], tostring(T14 + 2), "read two seconds after: the server's answer, then a second")
		eq(cs[2][3], tostring(T14 + 30 * 60))
		assert(w.R.Line().text:find("14:45 UTC", 1, true), w.R.Line().text)
		-- A new session (a /reload) of the same character: still on, from the saved table.
		w.logout()
		eq(OlympusRecordDB.saves, 1)
	end)
	eq(w.sent, 0, "no message of any kind")
	local again
	db, again = InWorld({ db = db, clock = T14 + 40 * 60 }, function(w2)
		w2.login()
		eq(#w2.tickers, 1, "on again at login: the file came back")
		w2.step(T14 + 46 * 60)
		eq(#OlympusRecordDB.sessions, 2)
		local cs = Typed(w2.R, w2.session(), "C")
		eq(#cs, 1); eq(cs[1][3], tostring(T14 + 45 * 60))
		w2.slash("status")
		assert(w2.copies[1].text:find(L.RECORD_LOADED:format(1), 1, true), "it says the game loaded the file back")
		w2.slash("off")
		eq(w2.prints[#w2.prints], L.RECORD_OFF)
		eq(OlympusRecordDB.on["Witness Example-ClassicBetaPvP"], nil)
		local z = Typed(w2.R, w2.session(), "Z")
		eq(#z, 1); eq(z[1][3], "off")
		w2.step(T14 + 61 * 60)
		eq(#Typed(w2.R, w2.session(), "C"), 1, "nothing more once off")
	end)
	eq(again.sent, 0)
end)

test("record mode: each member is written once (M), then each checkpoint's roster and online members as bitmaps, level changes and who left", function()
	InWorld(nil, function(w)
		local R = w.R
		w.login()
		w.slash("on")
		w.step(T14 + 5)
		local s = w.session()
		local ms = Typed(R, s, "M")
		eq(#ms, 8, "the whole roster once")
		eq(table.concat(ms[4], "|"), "M|4|Member Bravo-ClassicBetaPvP2|Player-0000-00000003|PRIEST|33")
		local c = Typed(R, s, "C")[1]
		eq(c[5], "Olympus Example"); eq(c[6], "8"); eq(c[7], "5"); eq(c[8], "8"); eq(c[9], "5")
		eq(Set(R, c[10]), "1,2,3,4,5,6,7,8"); eq(Set(R, c[11]), "1,2,4,6,7"); eq(c[12], "")
		-- Charlie levels, Alpha logs in; Echo leaves and Foxtrot joins; a mark, then 14:15.
		w.roster[5].level, w.roster[3].online = 13, true
		w.step(T14 + 10 * 60)
		w.slash("mark")
		eq(w.prints[#w.prints], L.RECORD_MARK_ASKED)
		w.step(T14 + 10 * 60 + 5)
		eq(w.prints[#w.prints], L.RECORD_MARK_DONE:format("2026-10-20 14:10:02 UTC", 6, 8))
		w.slash("mark")
		eq(w.prints[#w.prints], L.RECORD_MARK_WAIT:format(55), "one mark a minute")
		table.remove(w.roster, 8)
		w.roster[#w.roster + 1] = Member("Member Foxtrot-ClassicBetaPvP", "Player-0000-00000007", "PALADIN", 1, true)
		w.step(T14 + 15 * 60 + 5)
		local cs = Typed(R, s, "C")
		eq(#cs, 3)
		eq(cs[2][2], "M"); eq(cs[2][3], tostring(T14 + 10 * 60)); eq(Set(R, cs[2][11]), "1,2,3,4,6,7"); eq(cs[2][12], "5:13")
		eq(Set(R, cs[3][10]), "1,2,3,4,5,6,7,9", "Echo (8) off the roster, Foxtrot (9) on it")
		eq(Set(R, cs[3][11]), "1,2,3,4,6,7,9"); eq(cs[3][12], "", "no level changed since the mark")
		ms = Typed(R, s, "M")
		eq(#ms, 9); eq(ms[9][3], "Member Foxtrot-ClassicBetaPvP")
		-- An M line comes before the checkpoint that first saw its member.
		local order = {}
		for _, line in ipairs(s.lines) do order[#order + 1] = line:sub(1, 1) end
		eq(table.concat(order), "SMMMMMMMMCCMC", "Foxtrot's M line between the mark's checkpoint and 14:15's")
		w.logout()
	end)
end)

test("record mode: a partial roster is asked again, then written as it is with its rows; no guild is no session", function()
	InWorld(nil, function(w)
		local R = w.R
		w.partial = 6
		w.login()
		w.slash("on")
		w.step(T14 + 20)
		local c = Typed(R, w.session(), "C")[1]
		eq(w.asks, 3, "three asks while the game gave 6 rows of 8")
		eq(c[6], "8"); eq(c[8], "6", "the rows read")
		w.slash("status")
		assert(w.copies[#w.copies].text:find(L.RECORD_PARTIAL, 1, true), "the status says how to get every row")
		w.guild = nil
		w.step(T14 + 30)
		eq(Typed(R, w.session(), "Z")[1][3], "guild", "out of the guild: the session ends")
		local n = #OlympusRecordDB.sessions
		w.step(T14 + 16 * 60)
		eq(#OlympusRecordDB.sessions, n, "and none begins without a guild")
		w.slash("status")
		assert(w.copies[#w.copies].text:find(L.RECORD_WAITING, 1, true))
	end)
end)

test("record mode: the chain verifies; an edited line breaks it at that line; an edit with every hash computed again is the limit the docs state", function()
	InWorld(nil, function(w)
		local R = w.R
		w.login()
		w.slash("on")
		w.step(T14 + 16 * 60)
		w.logout()
		local s = OlympusRecordDB.sessions[1]
		eq(s.n, #s.lines, "a logout chains every line")
		local ok, head, n = R.Verify(s)
		assert(ok, tostring(head) .. " " .. tostring(n)); eq(head, s.head); eq(n, #s.lines)
		eq(s.id, "Player-0000-0000000A:" .. (T14 - 60))
		-- The marks: the S, each C and the Z line's hash.
		local marked = {}
		for _, m in ipairs(s.marks) do marked[#marked + 1] = R.Split(s.lines[tonumber(m:match("^(%d+):"))])[1] end
		eq(table.concat(marked), "SCCZ")
		local c = 0
		for i, line in ipairs(s.lines) do
			if line:sub(1, 2) == "C|" then
				c = c + 1
				if c == 2 then
					local copy = { id = s.id, lines = {}, marks = s.marks, head = s.head, n = s.n }
					for k, v in ipairs(s.lines) do copy.lines[k] = v end
					copy.lines[i] = line:gsub("|5|8|5|", "|6|8|6|", 1)
					local good, at, why = R.Verify(copy)
					eq(good, false); eq(at, i, why)
					-- Every hash computed again (no secret goes in): the edit verifies. The chain proves
					-- only what a head published at the time pins down (docs/RECORD-FORMAT.md, 7.1).
					copy.marks, copy.head = {}, nil
					local again, newHead = R.Verify(copy)
					eq(again, true); copy.head = newHead
					eq(R.Verify(copy), true); eq(newHead ~= s.head, true, "only its head differs from the published one")
				end
			end
		end
		eq(c, 2)
		local wrongId = { id = "Player-0000-0000000B:1", lines = s.lines }
		eq(R.Verify(wrongId), false, "the id is the S line's GUID and start")
	end)
end)

test("record mode: census reports Data.Receive takes are kept once per guild per quarter hour, up to the day's limit; none while off", function()
	local savedRecord, savedGuilds = rawget(ns, "Record"), ns.rdb.guilds
	local ok, err = pcall(InWorld, nil, function(w)
		local R = w.R
		ns.Record, ns.rdb.guilds = R, {}
		local function Report(guild, total, online, sender)
			local text = ns.Codec.EncodeReport({ guild = guild, total = total, online = online, st = w.clock - 2, users = 7 })
			return ns.Data.Receive(ns.Codec.DecodeReport(text), sender)
		end
		eq(Report("Olympus Heard", 900, 300, "Reporter One-ClassicBetaPvP"), true)
		eq(OlympusRecordDB, nil, "record mode off: nothing kept")
		w.login()
		w.slash("on")
		w.step(T14 + 70)
		eq(Report("Olympus Heard", 901, 301, "Reporter One-ClassicBetaPvP"), true)
		w.step(T14 + 250)
		eq(Report("Olympus Heard", 902, 302, "Reporter One-ClassicBetaPvP"), true, "taken by the census")
		w.step(T14 + 15 * 60 + 10)
		eq(Report("Olympus Heard", 903, 303, "Reporter One-ClassicBetaPvP"), true)
		local es = Typed(R, w.session(), "E")
		eq(#es, 2, "the first of each quarter hour")
		eq(table.concat(es[1], "|"), ("E|%d|%d|Olympus Heard|901|301|7|Reporter One-ClassicBetaPvP"):format(T14 + 70, T14 + 68))
		eq(es[2][5], "903")
		eq(OlympusRecordDB.events, 2)
		-- Our own guild's report never comes from the channel, so never from here either.
		eq(Report("Olympus Example", 50, 5, "Guildmate One-ClassicBetaPvP"), false)
		eq(#Typed(R, w.session(), "E"), 2)
		-- The day's limit: counted, not kept; the next UTC day starts afresh.
		OlympusRecordDB.events = R.EVENTS_PER_DAY
		eq(Report("Olympus Other", 10, 2, "Reporter Three-ClassicBetaPvP"), true)
		eq(#Typed(R, w.session(), "E"), 2)
		OlympusRecordDB.eventsDay = OlympusRecordDB.eventsDay - 1 -- (as if the full count were yesterday's)
		eq(Report("Olympus Fourth", 11, 3, "Reporter Four-ClassicBetaPvP"), true)
		eq(#Typed(R, w.session(), "E"), 3, "a new UTC day: kept again")
		eq(OlympusRecordDB.events, 1)
		w.logout()
		eq(Typed(R, OlympusRecordDB.sessions[1], "Z")[1][4], "1", "the Z line says how many were not kept")
		eq(w.sent, 0)
	end)
	ns.Record, ns.rdb.guilds = savedRecord, savedGuilds
	if not ok then error(err, 0) end
end)

test("record mode: the status is a copy window: what is written, the file to send, /reload or log out first, the BattleTag or none", function()
	InWorld({ battleTag = "SampleWitness#0000" }, function(w)
		w.login()
		w.slash("on")
		w.step(T14 + 5)
		w.slash("")
		local text = w.copies[#w.copies].text
		eq(w.copies[#w.copies].title, L.RECORD_TITLE)
		for _, want in ipairs({ L.RECORD_WHAT, L.RECORD_SEND, L.RECORD_FILE, L.RECORD_NOTHING_SENT, L.RECORD_NOT_LOADED,
			L.RECORD_BATTLETAG:format("SampleWitness#0000"), L.RECORD_NEXT:format("14:15 UTC") }) do
			assert(text:find(want, 1, true), want)
		end
		assert(L.RECORD_FILE:find("SavedVariables\\Olympus.lua", 1, true))
		assert(L.RECORD_SEND:find("/reload", 1, true))
		assert(text:find("Chain head after", 1, true))
	end)
	InWorld(nil, function(w)
		w.login()
		w.slash("status")
		assert(w.copies[1].text:find(L.RECORD_NO_BATTLETAG, 1, true), "no BattleTag given: says so")
	end)
	-- Every line in both languages.
	local en, pt = {}, {}
	assert(loadfile(ROOT .. "Olympus/Locales/RecordText.lua"))("Olympus", { L = en })
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local okPt, errPt = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales/RecordText.lua"))("Olympus", { L = pt }) end)
	GetLocale = savedLocale
	assert(okPt, errPt)
	local n = 0
	for k, v in pairs(en) do
		n = n + 1
		assert(pt[k] and (pt[k] ~= v or k == "RECORD_COMMANDS"), k)
		local _, a = v:gsub("%%[ds]", ""); local _, b = pt[k]:gsub("%%[ds]", "")
		eq(b, a, k .. ": the same placeholders")
	end
	assert(n >= 30, n)
end)

test("record mode: the source sends nothing; the TOC declares its own SavedVariable and loads its files; Core stands in until a restart", function()
	local src = assert(ReadFile(ROOT .. "Olympus/Record.lua"))
	local code = src:gsub("%-%-[^\n]*", "")
	for _, word in ipairs({ "Send", "Comm", "C_ChatInfo", "Whisper", "Channel", "C_Timer", "hooksecurefunc", "SetScript" }) do
		eq(code:find(word, 1, true), nil, "Record.lua uses no " .. word)
	end
	local toc = assert(ReadFile(ROOT .. "Olympus/Olympus.toc"))
	assert(toc:find("\n## SavedVariables: OlympusDB, OlympusRecordDB\r?\n"), "OlympusRecordDB next to OlympusDB")
	local at, n = {}, 0
	for line in toc:gmatch("[^\r\n]+") do n = n + 1; at[line] = n end
	assert(at["Locales\\RecordText.lua"] and at["Locales\\RecordText.lua"] < at["Core.lua"], "its lines with the other languages")
	assert(at["Record.lua"] and at["Record.lua"] > at["Data.lua"] and at["Record.lua"] > at["Sign.lua"] and at["Record.lua"] > at["UI.lua"])
	local core = assert(ReadFile(ROOT .. "Olympus/Core.lua"))
	assert(core:find('StandIn("Record", { "Slash" })', 1, true))
	assert(core:find('"Nominees", "Record" }) do', 1, true), "named among the files a restart loads")
	assert(core:find('elseif cmd == "record" then', 1, true))
	eq(rawget(ns, "Record") and ns.Record.missing, true, "the harness, like a client updated without a restart, has the stand-in")
	-- The census page's line: first, a click opens the status.
	InWorld(nil, function(w)
		local saved = rawget(ns, "Record")
		ns.Record = w.R
		local ok, err = pcall(function()
			w.login()
			w.slash("on")
			local function RecLine()
				for i, line in ipairs(ns.Views.Build("census")) do
					if tostring(line.text):find("[REC]", 1, true) then return line, i end
				end
			end
			local line, at = RecLine()
			assert(line, "the census page has the line")
			eq(at, 2, "right below the page's search box")
			local before = #w.copies
			line.onClick()
			eq(#w.copies, before + 1, "a click opens the status")
			w.slash("off")
			eq(RecLine(), nil, "gone once off")
		end)
		ns.Record = saved
		if not ok then error(err, 0) end
	end)
end)

---------------------------------------------------------------------------
-- The sample: two witnesses of one fake guild, as their SavedVariables files hold them.
---------------------------------------------------------------------------

-- SavedVariables as the game writes them: tabs, ["key"] = value, an array's values with "-- [n]".
-- (Keys sorted here, so the sample is the same each run; the game's order is its own.)
local function Quote(s)
	return '"' .. (s:gsub('[\\"\n\r]', { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r" })) .. '"'
end
local function Write(out, v, indent)
	if type(v) == "table" then
		out[#out + 1] = "{\n"
		local n = #v
		local keys = {}
		for k in pairs(v) do
			if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end
		end
		table.sort(keys, function(a, b)
			if type(a) ~= type(b) then return type(a) == "number" end
			return a < b
		end)
		for _, k in ipairs(keys) do
			out[#out + 1] = indent .. "\t[" .. (type(k) == "string" and Quote(k) or ("%d"):format(k)) .. "] = "
			Write(out, v[k], indent .. "\t")
			out[#out + 1] = ",\n"
		end
		for i = 1, n do
			out[#out + 1] = indent .. "\t"
			Write(out, v[i], indent .. "\t")
			out[#out + 1] = (", -- [%d]\n"):format(i)
		end
		out[#out + 1] = indent .. "}"
	elseif type(v) == "string" then
		out[#out + 1] = Quote(v)
	elseif type(v) == "number" then
		out[#out + 1] = v == math.floor(v) and ("%.0f"):format(v) or tostring(v)
	else
		out[#out + 1] = tostring(v)
	end
end
local function SavedFile(vars)
	local out = {}
	for _, pair in ipairs(vars) do
		out[#out + 1] = "\n" .. pair[1] .. " = "
		Write(out, pair[2], "")
		out[#out + 1] = "\n"
	end
	return table.concat(out)
end

-- Witness A logs in at 13:59, turns record mode on, takes 14:00, marks 14:10, takes 14:15 and logs
-- out at 14:20; witness B, a guildmate, logs in at 14:05, takes 14:15 and logs out at 14:20. Both
-- hear the same census reports. Between 14:00 and 14:15 one member levels, one logs in, one leaves
-- and one joins.
local function Witness(which)
	local A = which == "A"
	local db = InWorld({ clock = A and (T14 - 60) or (T14 + 5 * 60), me = A and "Witness Example-ClassicBetaPvP" or "Witness Second-ClassicBetaPvP",
		guid = A and "Player-0000-0000000A" or "Player-0000-0000000B", rank = A and 4 or 2, rankName = A and "Soldier" or "Captain",
		battleTag = A and "SampleWitness#0000" or nil }, function(w)
		local savedRecord, savedGuilds = rawget(ns, "Record"), ns.rdb.guilds
		local ok, err = pcall(function()
			ns.Record, ns.rdb.guilds = w.R, {}
			local function Heard(at, guild, total, online, sender)
				w.step(at)
				local text = ns.Codec.EncodeReport({ guild = guild, total = total, online = online, st = at - 2, users = 12 })
				ns.Data.Receive(ns.Codec.DecodeReport(text), sender)
			end
			w.login()
			w.slash("on")
			if A then
				w.step(T14 + 5)
				Heard(T14 + 70, "Olympus Second", 950, 310, "Sample Reporter-ClassicBetaPvP2")
				Heard(T14 + 250, "Olympus Second", 951, 312, "Sample Reporter-ClassicBetaPvP2") -- (the same quarter hour: not kept)
				-- (The sample's reporters are its own: the census keeps one guild per sender all session.)
			end
			Heard(T14 + 300, "Olympus Third", 420, 96, "Sample Herald-ClassicBetaPvP")
			w.step(T14 + 6 * 60)
			w.roster[5].level, w.roster[3].online = 13, true
			if A then
				w.step(T14 + 10 * 60)
				w.slash("mark")
			end
			w.step(T14 + 12 * 60)
			table.remove(w.roster, 8)
			w.roster[#w.roster + 1] = Member("Member Foxtrot-ClassicBetaPvP", "Player-0000-00000007", "PALADIN", 1, true)
			Heard(T14 + 16 * 60, "Olympus Second", 955, 330, "Sample Reporter-ClassicBetaPvP2")
			w.step(T14 + 20 * 60)
			w.logout()
		end)
		ns.Record, ns.rdb.guilds = savedRecord, savedGuilds
		if not ok then error(err, 0) end
	end)
	return db
end

-- The budget: a 1000-member guild recorded for two whole days by one witness, a /reload every 8 hours
-- (6 sessions, each with its own member lines), 40% of the guild online and changing every quarter
-- hour, levels moving, and 70 other guilds reporting every 170 seconds (the reporter's period).
test("record mode: a 1000-member guild over two days, six sessions and 70 guilds' reports: the roster well under 1 MB, the file under 2 MB", function()
	local roster = {}
	for i = 1, 1000 do
		roster[i] = Member(("Member %04d-ClassicBetaPvP%s"):format(i, i % 2 == 0 and "2" or ""), ("Player-0000-%08X"):format(i), "WARRIOR", 1 + i % 60, false)
	end
	local db, w = InWorld({ roster = roster }, function(w)
		w.login()
		w.slash("on")
		local stop = T14 + 2 * 24 * 3600
		local nextRelog = T14 + 8 * 3600
		while w.clock < stop do
			local q = math.floor(w.clock / 900)
			if w.clock % 900 == 0 then
				for i, m in ipairs(roster) do m.online = (i * 7 + q) % 10 < 4 end
				roster[q % 1000 + 1].level = roster[q % 1000 + 1].level % 60 + 1
			end
			if w.clock % 170 == 0 then
				for g = 1, 70 do
					w.R.Heard({ guild = ("Olympus Guild %02d"):format(g), total = 900 + g, online = 300, users = 9, st = w.clock - 1,
						reporterFull = ("Reporter %02d-ClassicBetaPvP"):format(g) })
				end
			end
			if w.clock >= nextRelog then
				w.logout()
				w.login()
				nextRelog = nextRelog + 8 * 3600
			end
			w.step(w.clock + 1)
		end
		w.logout()
	end)
	eq(w.sent, 0)
	eq(#db.sessions, 6)
	local checkpoints, members = 0, 0
	for _, s in ipairs(db.sessions) do
		assert(w.R.Verify(s), s.id)
		for _, line in ipairs(s.lines) do
			if line:sub(1, 2) == "C|" then checkpoints = checkpoints + 1 elseif line:sub(1, 2) == "M|" then members = members + 1 end
		end
	end
	eq(checkpoints, 192, "every quarter hour of the two days")
	eq(members, 6000, "each session's member lines")
	local events, rosterBytes = 0, 0
	for _, s in ipairs(db.sessions) do
		for _, line in ipairs(s.lines) do
			if line:sub(1, 2) == "E|" then events = events + 1 else rosterBytes = rosterBytes + #line end
		end
	end
	assert(events >= 2 * 96 * 70 and events < 2 * w.R.EVENTS_PER_DAY, "each guild each quarter hour of both days: " .. events)
	local bytes = #SavedFile({ { "OlympusRecordDB", db } })
	print(("       two days, 1000 members: %d bytes on disk; the roster's lines alone %d bytes"):format(bytes, rosterBytes))
	assert(rosterBytes < 1024 * 1024, rosterBytes)
	assert(bytes < 2 * 1024 * 1024, bytes)
end)

test("record mode: the sample files (tests/fixtures/record-sample.lua and -b.lua) are what the format gives; their chains verify, and record-check.lua reads them and finds the two witnesses agreeing at 14:15", function()
	local files = {}
	for _, which in ipairs({ "A", "B" }) do
		local db = Witness(which)
		-- Another SavedVariable in the same file, as Olympus.lua holds OlympusDB too: a verifier skips it.
		local other = { log = { '10-20 13:59:01 ---- session 3, v1.2.5.1 "sample" ----' }, sessions = 3 }
		files[which] = SavedFile({ { "OlympusDB", other }, { "OlympusRecordDB", db } })
	end
	local names = { A = "record-sample.lua", B = "record-sample-b.lua" }
	local outNames = { A = "OlympusRecordDB-sample.lua", B = "OlympusRecordDB-sample-b.lua" }
	local write, out = os.getenv("OLYMPUS_RECORD_SAMPLE_WRITE") == "1", os.getenv("OLYMPUS_RECORD_SAMPLE_OUT")
	for which, text in pairs(files) do
		local path = ROOT .. "tests/fixtures/" .. names[which]
		if write then WriteFile(path, text) end
		if out and out ~= "" then WriteFile(out .. "/" .. outNames[which], text) end
		eq(ReadFile(path), text, names[which] .. " is what the format gives now (OLYMPUS_RECORD_SAMPLE_WRITE=1 rewrites it)")
	end
	local C = assert(loadfile(ROOT .. "scripts/record-check.lua"))("--module")
	local R = C.Load()
	local all = {}
	for _, which in ipairs({ "A", "B" }) do
		local parsed = C.Parse(files[which])
		eq(parsed.OlympusDB.sessions, 3, "the reader reads the other variable too")
		local sessions = C.Sessions(R, parsed.OlympusRecordDB)
		eq(#sessions, 1)
		local e = sessions[1]
		assert(e.ok, tostring(e.at) .. ": " .. tostring(e.why))
		eq(e.head, parsed.OlympusRecordDB.sessions[1].head)
		print(("       sample %s: %s, %d lines, chain head %s"):format(which, e.id, e.n, e.head))
		all[#all + 1] = e
	end
	eq(all[1].head, "8d4b9293d2601663f36c667d0ab4853a827023ddae3797ed0af6b2158b8d19ac", "witness A's head, as docs/RECORD-FORMAT.md gives it")
	local groups = C.Compare(all)
	eq(#groups, 2, "14:00 (A alone) and 14:15 (both)")
	eq(groups[2].slot, T14 + 15 * 60); eq(#groups[2].seen, 2); eq(groups[2].agree, true, "the same members and online members, though their numbers differ")
	-- One witness's online member changed: they disagree.
	local B = all[2].checkpoints[1]
	B.onlineSet[1] = "Someone Else|Player-0000-000000FF"
	eq(C.Compare(all)[2].agree, false)
end)

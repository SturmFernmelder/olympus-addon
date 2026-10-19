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
local GLOBALS = { "OlympusRecordDB", "GetGuildInfo", "IsInGuild", "GetNumGuildMembers", "GetGuildRosterInfo", "UnitGUID", "BNGetInfo",
	"InCombatLockdown", "C_GuildInfo", "GuildRoster", "GetBuildInfo", "GetLocale", "C_ChatInfo", "SendChatMessage",
	"SendAddonMessage", "GetServerTime", "issecretvalue" }
local function RecordWorld(o)
	o = o or {}
	local w = { clock = o.clock or (T14 - 60), combat = false, roster = o.roster or SampleRoster(), guild = o.guild or "Olympus Example",
		rank = o.rank or 4, rankName = o.rankName or "Soldier", sent = 0, timers = {}, tickers = {}, events = {}, on = {},
		prints = {}, copies = {}, asks = 0, askedAt = {}, battleTag = o.battleTag }
	local saved = {}
	for _, k in ipairs(GLOBALS) do saved[k] = rawget(_G, k) end
	local function Count() w.sent = w.sent + 1 end
	OlympusRecordDB = o.db
	GetServerTime = function() return w.clock end
	-- (w.loading: a loading screen's moment, still in the guild but its name not given yet.)
	GetGuildInfo = function() if w.guild and not w.loading then return w.guild, w.rankName, w.rank end end
	IsInGuild = function() return w.guild ~= nil end
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
		w.askedAt[#w.askedAt + 1] = w.clock
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
		local tag = R.TagHash("SampleWitness#0000")
		eq(tag, "973dcf3aa89dd097c64d6764c475996c11ee2aa22b4ec83c542453d341eb76eb", "field 14: the BattleTag's hash")
		local line = "S|1|1792483200|Witness Example-ClassicBetaPvP|Player-0000-00000001|Olympus Example|4|Soldier|Alliance|ClassicBetaPvP|ClassicBetaPvP|1.2.5.1||" .. tag .. "|16001|1.60.1.70450|enUS"
		eq(R.Link(seed, line), "b4d70a7f064a26ed45d75604d8a4279db182e0551066bbdd07cb98e4b3e289bf")
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

test("record mode: a partial roster is asked again, about 5 s apart, then written as it is with its rows; no guild is no session", function()
	InWorld(nil, function(w)
		local R = w.R
		w.partial = 6
		w.login()
		w.slash("on")
		w.step(T14 + 20)
		local c = Typed(R, w.session(), "C")[1]
		eq(w.asks, 3, "three asks while the game gave 6 rows of 8")
		-- (Each ask read once: the game's answer and the 4-second fallback are one read, not two tries.)
		eq(table.concat(w.askedAt, ","), table.concat({ T14, T14 + 5, T14 + 10 }, ","), "on the clock's looks, not at once")
		eq(c[4], tostring(T14 + 12), "the third read, 12 s after the slot")
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

-- A regression: a loading screen gives no guild name while the player is still in the guild
-- (Bank.lua's Loading). That moment once ended the session as "guild", began a new one, wrote every
-- member again and read the same quarter hour twice.
test("record mode: a loading screen's moment (in the guild, its name not given yet) ends no session and writes no member again", function()
	InWorld(nil, function(w)
		local R = w.R
		w.login()
		w.slash("on")
		w.step(T14 + 60)
		local s = w.session()
		w.loading = true
		w.step(T14 + 66) -- (the clock looks every 5 s: one look at least while it lasts)
		w.loading = false
		w.step(T14 + 15 * 60 + 5)
		eq(#OlympusRecordDB.sessions, 1, "the same session goes on")
		eq(#Typed(R, s, "Z"), 0, "no end written")
		eq(#Typed(R, s, "M"), 8, "each member once")
		local cs = Typed(R, s, "C")
		eq(#cs, 2); eq(cs[1][3], tostring(T14)); eq(cs[2][3], tostring(T14 + 15 * 60), "14:00 and 14:15, each once")
		-- Out of the guild for real (the game says so): the session ends as before.
		w.guild = nil
		w.step(T14 + 15 * 60 + 15)
		eq(Typed(R, s, "Z")[1][3], "guild")
	end)
end)

-- A regression: a roster the game had not given yet (0 members right after login) was written as a
-- checkpoint of 0 members and 0 online after three asks in about 4 s.
test("record mode: a roster the game has not given yet is never written as a checkpoint; it is asked again and written once it comes, or the slot is missed", function()
	InWorld({ roster = {} }, function(w)
		local R = w.R
		w.login()
		w.slash("on")
		w.step(T14 + 6)
		eq(#Typed(R, w.session(), "C"), 0, "no checkpoint of nobody")
		w.roster = SampleRoster() -- (the roster arrives 6 s after the slot)
		w.step(T14 + 60)
		local cs = Typed(R, w.session(), "C")
		eq(#cs, 1, "written once it came")
		eq(cs[1][3], tostring(T14)); eq(cs[1][4], tostring(T14 + 12), "at the next ask, 10 s after the first"); eq(cs[1][6], "8"); eq(cs[1][8], "8")
	end)
	InWorld({ roster = {} }, function(w)
		w.login()
		w.slash("on")
		w.step(T14 + 6 * 60)
		eq(#Typed(w.R, w.session(), "C"), 0, "never given within 5 minutes: missed, no C line")
		eq(w.asks, 31, "asked every 10 s until 5 minutes after the slot, then no more")
		w.step(T14 + 15 * 60 + 5)
		eq(#Typed(w.R, w.session(), "C"), 0)
		eq(w.asks, 32, "the next quarter hour is asked again")
	end)
end)

-- A regression: record mode began a session in any guild, so a guild outside Olympus could have
-- its roster written (the 09-28 methodology: the addon runs only for members of Olympus guilds).
test("record mode: only for a member of an Olympus guild: on is refused elsewhere, and a session ends in a guild that is not one", function()
	local db, w0 = InWorld({ guild = "Plain Example Guild" }, function(w)
		eq(w.ns.IsFederation("Plain Example Guild"), false, "(the test's other guild is no Olympus guild)")
		w.login()
		w.slash("on")
		eq(w.prints[#w.prints], L.RECORD_NOT_MEMBER)
		w.step(T14 + 16 * 60)
		eq(w.asks, 0, "its roster never read")
	end)
	eq(db, nil, "nothing made or written")
	eq(w0.sent, 0)
	InWorld(nil, function(w)
		local R = w.R
		w.login()
		w.slash("on")
		w.step(T14 + 5)
		w.guild = "Plain Example Guild"
		w.step(T14 + 16 * 60)
		eq(#OlympusRecordDB.sessions, 1, "none begins in the other guild")
		eq(Typed(R, w.session(), "Z")[1][3], "guild")
		for _, line in ipairs(w.session().lines) do eq(line:find("Plain Example", 1, true), nil, line) end
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

test("record mode: the status is a copy window: what is written, the file to send, /reload or log out first; the BattleTag only as a hash in the file, never shown", function()
	-- SHA-256 of "olympus-record-1|battletag|SampleWitness#0000" (checked against Python's hashlib).
	local TAG_HASH = "973dcf3aa89dd097c64d6764c475996c11ee2aa22b4ec83c542453d341eb76eb"
	for _, kings in ipairs({ false, true }) do
		InWorld({ battleTag = "SampleWitness#0000" }, function(w)
			w.ns.KingsScreen = function() return kings end -- (the King's stream too: the same window)
			w.login()
			w.slash("on")
			w.step(T14 + 5)
			w.slash("")
			local text = w.copies[#w.copies].text
			for _, never in ipairs({ "SampleWitness", "#0000", TAG_HASH:sub(1, 8) }) do
				eq(text:find(never, 1, true), nil, "the window never shows the tag or its hash: " .. never)
			end
			eq(w.R.Split(w.session().lines[1])[14], TAG_HASH, "the S line holds the tag's hash, not the tag")
			eq(w.R.TagHash("SampleWitness#0000"), TAG_HASH)
			eq(w.copies[#w.copies].title, L.RECORD_TITLE)
			for _, want in ipairs({ L.RECORD_WHAT, L.RECORD_SEND, L.RECORD_FILE, L.RECORD_NOTHING_SENT, L.RECORD_NOT_LOADED,
				L.RECORD_BATTLETAG, L.RECORD_NEXT:format("14:15 UTC") }) do
				assert(text:find(want, 1, true), want)
			end
			w.logout()
			for _, line in ipairs(OlympusRecordDB.sessions[1].lines) do eq(line:find("SampleWitness", 1, true), nil, line) end
			assert(L.RECORD_FILE:find("SavedVariables\\Olympus.lua", 1, true))
			assert(L.RECORD_SEND:find("/reload", 1, true))
			assert(text:find("Chain head after", 1, true))
		end)
	end
	InWorld(nil, function(w)
		w.login()
		w.slash("status")
		assert(w.copies[1].text:find(L.RECORD_NO_BATTLETAG, 1, true), "no BattleTag given: says so")
		w.slash("on")
		eq(w.R.Split(w.session().lines[1])[14], "", "and none is written")
	end)
	-- The units: characters on the roster, never "members" online; what it writes names the locale and
	-- the test build too.
	for _, k in ipairs({ "RECORD_MARK_DONE", "RECORD_LAST" }) do
		eq(L[k]:find("members", 1, true), nil, k); assert(L[k]:find("characters", 1, true), k)
	end
	assert(L.RECORD_WHAT:find("language", 1, true) and L.RECORD_WHAT:find("test build", 1, true))
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
		local sessions = C.Sessions(R, parsed.OlympusRecordDB, names[which])
		eq(#sessions, 1)
		local e = sessions[1]
		assert(e.ok, tostring(e.at) .. ": " .. tostring(e.why))
		eq(e.head, parsed.OlympusRecordDB.sessions[1].head)
		print(("       sample %s: %s, %d lines, chain head %s"):format(which, e.id, e.n, e.head))
		all[#all + 1] = e
	end
	eq(all[1].head, "95bd06d6c5853eaad1af8e9e3d42c6c93cea3e8893226b367b586ba648683344", "witness A's head, as docs/RECORD-FORMAT.md gives it")
	eq(all[2].head, "d50c51179f068b5bffa0a396a70f33f037f941e6659c4eb0771cbc20cfb8dbf0", "witness B's head, as docs/RECORD-FORMAT.md gives it")
	local groups = C.Compare(all)
	eq(#groups, 2, "14:00 (A alone) and 14:15 (both)")
	eq(groups[2].slot, T14 + 15 * 60); eq(#groups[2].seen, 2); eq(groups[2].agree, true, "the same members and online members, though their numbers differ")
	-- One witness's online member changed: they disagree.
	local B = all[2].checkpoints[1]
	B.onlineSet[1] = "Someone Else|Player-0000-000000FF"
	eq(C.Compare(all)[2].agree, false)
end)

-- Regressions: a copy of a session with a line removed and every hash computed again passed
-- record-check (it compared copies only when their n was equal, and used whichever file came
-- first), and a copy with a line added after its Z line verified.
test("record mode: copies of one session must be identical whatever the files' order, and nothing may follow the Z line; record-check exits 1", function()
	local C = assert(loadfile(ROOT .. "scripts/record-check.lua"))("--module")
	local R = C.Load()
	local db = Witness("A")
	local s = db.sessions[1]
	-- Every hash computed again from the lines, as anyone holding the file can.
	local function Rechained(lines)
		local c = { id = s.id, char = s.char, start = s.start, lines = lines, marks = {} }
		local f = R.Split(lines[1])
		local h = R.Seed(f[5], f[3])
		for i, line in ipairs(lines) do
			h = R.Link(h, line)
			local k = line:sub(1, 2)
			if k == "S|" or k == "C|" or k == "Z|" then c.marks[#c.marks + 1] = i .. ":" .. h end
		end
		c.head, c.n = h, #lines
		return { format = db.format, version = db.version, sessions = { c } }
	end
	eq(R.Verify(Rechained(s.lines).sessions[1]), true, "(the same lines chained again are the same session)")
	local cut, added = {}, {}
	for i, line in ipairs(s.lines) do
		if i ~= 16 then cut[#cut + 1] = line end
		added[i] = line
	end
	eq(s.lines[16]:sub(1, 2), "E|", "(line 16 of the sample is an E line)")
	added[#added + 1] = ("C|Q|%d|%d|Olympus Example|8|9|8|9|ff|ff|"):format(T14 + 30 * 60, T14 + 30 * 60 + 2)
	local cutDb, addedDb = Rechained(cut), Rechained(added)
	eq(R.Verify(cutDb.sessions[1]), true, "a line removed, every hash again: the chain alone cannot tell")
	local ok, at, why = R.Verify(addedDb.sessions[1])
	eq(ok, false); eq(at, #s.lines + 1); eq(why, "a line after the Z line")
	local noZ = Rechained({ s.lines[1], s.lines[2] })
	eq(select(3, R.Verify(noZ.sessions[1])), "the last line is no Z line")
	local twoS = Rechained({ s.lines[1], s.lines[1], s.lines[17] })
	eq(select(3, R.Verify(twoS.sessions[1])), "an S line after line 1")
	local wrongN = Rechained(s.lines)
	wrongN.sessions[1].n = 16
	eq(select(3, R.Verify(wrongN.sessions[1])), "n is not the number of lines")
	local function Dedupe(...)
		local all = {}
		for _, pair in ipairs({ ... }) do
			for _, e in ipairs(C.Sessions(R, pair[2], pair[1])) do all[#all + 1] = e end
		end
		return C.Dedupe(all)
	end
	for _, other in ipairs({ cutDb, addedDb }) do
		for _, order in ipairs({ { { "day1", db }, { "day2", other } }, { { "day2", other }, { "day1", db } } }) do
			local kept, conflicts = Dedupe(order[1], order[2])
			eq(#conflicts, 1, "flagged whichever file comes first"); eq(#kept, 0, "and neither copy counted")
			eq(table.concat(conflicts[1].files, ","), order[1][1] .. "," .. order[2][1])
		end
	end
	local kept, conflicts = Dedupe({ "day1", db }, { "day2", Witness("A") })
	eq(#conflicts, 0); eq(#kept, 1, "the same session in two days' files: kept once")
	-- The command itself: the edited copy makes it exit 1.
	local a, b = os.tmpname(), os.tmpname()
	WriteFile(a, SavedFile({ { "OlympusRecordDB", db } }))
	WriteFile(b, SavedFile({ { "OlympusRecordDB", cutDb } }))
	local lua = (arg and arg[-1]) or "luajit"
	local pipe = assert(io.popen(("%s %sscripts/record-check.lua %s %s; echo \"exit=$?\""):format(lua, ROOT, b, a)))
	local out = pipe:read("*a")
	pipe:close()
	os.remove(a); os.remove(b)
	assert(out:find("the copies differ", 1, true), out)
	assert(out:find("exit=1", 1, true), out)
end)

-- A regression: record-check counted each session as a witness, so one character's two sessions
-- in one quarter hour (a /reload just after it) showed as two witnesses agreeing.
test("record mode: record-check counts each witness once per slot, its reading nearest the slot, and lists a reading more than 30 s after the slot apart", function()
	local C = assert(loadfile(ROOT .. "scripts/record-check.lua"))("--module")
	local R = C.Load()
	-- Witness A takes 14:00 and logs out at 14:03; the game did not load the file back (the beta's bug),
	-- so the next session, on again at 14:03, is in another file and reads 14:00 again.
	local first = InWorld(nil, function(w) w.login(); w.slash("on"); w.step(T14 + 3 * 60); w.logout() end)
	local second = InWorld({ clock = T14 + 3 * 60 }, function(w) w.login(); w.slash("on"); w.step(T14 + 4 * 60); w.logout() end)
	eq(Typed(R, second.sessions[1], "C")[1][4], tostring(T14 + 3 * 60 + 2), "(the second session read 14:00 again)")
	-- Witness B turns it on at 14:04:50: its 14:00 is read almost 5 minutes after the slot.
	local late = InWorld({ clock = T14 + 4 * 60 + 50, me = "Witness Second-ClassicBetaPvP", guid = "Player-0000-0000000B" }, function(w)
		w.login(); w.slash("on"); w.step(T14 + 5 * 60 + 30); w.logout()
	end)
	local all = {}
	for _, f in ipairs({ { "a-1", first }, { "a-2", second }, { "b", late } }) do
		for _, e in ipairs(C.Sessions(R, f[2], f[1])) do all[#all + 1] = e end
	end
	local g = C.Compare(all)[1]
	eq(g.slot, T14)
	eq(#g.seen, 1, "one witness, not two"); eq(g.seen[1].readings, 2); eq(g.seen[1].c.late, 2, "its reading nearest the slot")
	eq(#g.late, 1, "B's reading is not one instant with A's"); eq(g.late[1].c.late, 4 * 60 + 52)
	-- The command prints it so: one witness, how late each reading was, B's apart.
	local paths, args = {}, {}
	for k, db in ipairs({ first, second, late }) do
		paths[k] = os.tmpname()
		WriteFile(paths[k], SavedFile({ { "OlympusRecordDB", db } }))
		args[k] = paths[k]
	end
	local pipe = assert(io.popen(("%s %sscripts/record-check.lua %s; echo \"exit=$?\""):format((arg and arg[-1]) or "luajit", ROOT, table.concat(args, " "))))
	local out = pipe:read("*a")
	pipe:close()
	for _, path in ipairs(paths) do os.remove(path) end
	assert(out:find("<Olympus Example>  1 witness(es), latest +2s: Witness Example-ClassicBetaPvP 8/5 +2s (2 readings)", 1, true), out)
	assert(out:find("read more than 30 s after the slot, not one instant: Witness Second-ClassicBetaPvP 8/5 +292s", 1, true), out)
	assert(out:find("exit=0", 1, true), out)
	-- Two accounts' files of one person (one BattleTag hash) are one witness too.
	local x = InWorld({ battleTag = "SampleWitness#0000" }, function(w) w.login(); w.slash("on"); w.step(T14 + 5); w.logout() end)
	local y = InWorld({ battleTag = "SampleWitness#0000", me = "Witness Second-ClassicBetaPvP", guid = "Player-0000-0000000B" }, function(w)
		w.login(); w.slash("on"); w.step(T14 + 5); w.logout()
	end)
	local both = {}
	for _, f in ipairs({ { "x", x }, { "y", y } }) do
		for _, e in ipairs(C.Sessions(R, f[2], f[1])) do both[#both + 1] = e end
	end
	eq(#C.Compare(both)[1].seen, 1, "one BattleTag: one witness")
	-- With the file loaded back, a /reload just after 14:00 does not read 14:00 again.
	local carried = InWorld({ db = first, clock = T14 + 3 * 60 }, function(w) w.login(); w.step(T14 + 4 * 60); w.logout() end)
	eq(#carried.sessions, 2); eq(#Typed(R, carried.sessions[2], "C"), 0, "14:00 is already in the file")
end)

-- A regression: a file held 30,000 lines at most. A 1,000-member guild's witness who logs in again
-- often filled it in about 20 hours, and then recorded nothing for the rest of the attempt.
test("record mode: a day of 50-minute sessions in a 1000-member guild, with 70 guilds' reports, fills under a third of the file; a full file stops", function()
	local roster = {}
	for i = 1, 1000 do
		roster[i] = Member(("Member %04d-ClassicBetaPvP%s"):format(i, i % 2 == 0 and "2" or ""), ("Player-0000-%08X"):format(i), "WARRIOR", 1 + i % 60, false)
	end
	local db, w = InWorld({ roster = roster }, function(w)
		w.login()
		w.slash("on")
		local stop, nextRelog = T14 + 24 * 3600, T14 + 50 * 60
		while w.clock < stop do
			if w.clock % 900 == 0 then
				local q = math.floor(w.clock / 900)
				for i, m in ipairs(roster) do m.online = (i * 7 + q) % 10 < 4 end
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
				nextRelog = nextRelog + 50 * 60
			end
			w.step(w.clock + 1)
		end
		w.logout()
	end)
	local lines, checkpoints = 0, 0
	for _, s in ipairs(db.sessions) do
		lines = lines + #s.lines
		local z = w.R.Split(s.lines[#s.lines])
		eq(z[1] .. z[3], "Zlogout", "no session ended full")
		for _, line in ipairs(s.lines) do if line:sub(1, 2) == "C|" then checkpoints = checkpoints + 1 end end
	end
	eq(#db.sessions, 29)
	eq(checkpoints, 96, "every quarter hour of the day, each once")
	assert(lines * 3 < w.R.LINES_MAX, "both days of the attempt fit, with room to spare: " .. lines)
	local bytes = #SavedFile({ { "OlympusRecordDB", db } })
	print(("       a day, 29 sessions: %d lines, %d bytes on disk (%.0f a line)"):format(lines, bytes, bytes / lines))
	-- The limit itself: a full file ends the session, and none begins until the file is sent.
	InWorld(nil, function(w2)
		w2.R.LINES_MAX = 11
		w2.login()
		w2.slash("on")
		w2.step(T14 + 15 * 60 + 10)
		local s = w2.session()
		eq(s.lines[#s.lines], ("Z|%d|full|0"):format(T14 + 15 * 60 + 5))
		w2.logout()
		w2.login()
		w2.step(T14 + 31 * 60)
		eq(#OlympusRecordDB.sessions, 1)
		w2.slash("status")
		assert(w2.copies[#w2.copies].text:find(L.RECORD_FULL:format(12), 1, true))
	end)
end)

---------------------------------------------------------------------------
-- Record.VerifyFile: the check the Companion's verifier and record-check.lua run, the recorder's
-- own hash rule and line reading (docs/RECORD-FORMAT.md, section 8.1).
---------------------------------------------------------------------------

local DOC_HEAD = {
	A = "95bd06d6c5853eaad1af8e9e3d42c6c93cea3e8893226b367b586ba648683344",
	B = "d50c51179f068b5bffa0a396a70f33f037f941e6659c4eb0771cbc20cfb8dbf0",
}

-- Olympus/Sign.lua and Olympus/Record.lua loaded as an offline verifier loads them, in a namespace
-- of ns.L alone, with no global but Lua's own library and the bit library Sign.lua reads (as
-- _G.bit): any other name read or written is recorded in touched, and fails.
local LUA_ONLY = { "assert", "error", "ipairs", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "select",
	"setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "string", "table", "math" }
local function Sandboxed()
	local touched, env = {}, { bit = rawget(_G, "bit") or require("bit") }
	for _, k in ipairs(LUA_ONLY) do env[k] = _G[k] end
	env._G = env
	setmetatable(env, {
		__index = function(_, k) touched[#touched + 1] = "read " .. tostring(k); error("no global " .. tostring(k), 2) end,
		__newindex = function(_, k) touched[#touched + 1] = "write " .. tostring(k); error("no global " .. tostring(k), 2) end,
	})
	local sns = { L = {} }
	for _, file in ipairs({ "Sign.lua", "Record.lua" }) do
		local chunk = assert(loadfile(ROOT .. "Olympus/" .. file))
		setfenv(chunk, env)
		chunk("Olympus", sns)
	end
	return sns.Record, sns.Sign.SHA256, touched, sns
end
-- A committed sample's OlympusRecordDB, read from the file by record-check.lua's reader.
local function SampleDb(name)
	local C = assert(loadfile(ROOT .. "scripts/record-check.lua"))("--module")
	return C.Parse(assert(ReadFile(ROOT .. "tests/fixtures/" .. name))).OlympusRecordDB
end
local function Copied(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in pairs(v) do out[k] = Copied(x) end
	return out
end
-- Each observation as one text: kind, guild, checkpoint, read at, total, online, reporter, line.
local function Seen(e)
	local out = {}
	for _, o in ipairs(e.observations) do
		out[#out + 1] = table.concat({ o.kind, tostring(o.guild), tostring(o.checkpoint), tostring(o.readAt), tostring(o.total),
			tostring(o.online), tostring(o.reporter), tostring(o.line) }, "|")
	end
	return table.concat(out, "\n")
end

test("record mode: Record.VerifyFile reads both committed samples: each chain computed again from its seed gives the documented head, and members and checkpoints come back as names", function()
	local R, sha = Sandboxed()
	local a = R.VerifyFile(SampleDb("record-sample.lua"), sha)
	local b = R.VerifyFile(SampleDb("record-sample-b.lua"), sha)
	for _, r in ipairs({ a, b }) do
		eq(r.ok, true); eq(r.why, nil); eq(#r.sessions, 1); eq(#r.conflicts, 0); eq(r.duplicates, 0)
	end
	local A, B = a.sessions[1], b.sessions[1]
	eq(A.ok, true, tostring(A.why)); eq(A.why, nil); eq(A.brokenAt, nil)
	eq(A.lastHash, DOC_HEAD.A, "witness A's head, as docs/RECORD-FORMAT.md gives it")
	eq(B.ok, true, tostring(B.why))
	eq(B.lastHash, DOC_HEAD.B, "witness B's head, as docs/RECORD-FORMAT.md gives it")
	eq(A.firstHash, "6cac157f898125f1892460687e68b5651d850a922d7633bea5a79ad9731648c4", "the hash after the S line: its mark 1 in the file")
	eq(A.id, "Player-0000-0000000A:" .. (T14 - 60))
	eq(A.character, "Witness Example-ClassicBetaPvP"); eq(A.witness, "Player-0000-0000000A"); eq(A.guild, "Olympus Example")
	eq(A.battleTagHash, "973dcf3aa89dd097c64d6764c475996c11ee2aa22b4ec83c542453d341eb76eb"); eq(A.start, T14 - 60); eq(A.records, 17)
	eq(B.character, "Witness Second-ClassicBetaPvP"); eq(B.witness, "Player-0000-0000000B"); eq(B.guild, "Olympus Example")
	eq(B.battleTagHash, nil, "B's game gave no BattleTag"); eq(B.start, T14 + 5 * 60); eq(B.records, 13)
	-- Every C and E line in order: a quarter hour by its slot, a mark by the time it was asked, a census
	-- report by the quarter hour this client took it in.
	eq(Seen(A), table.concat({
		("C|Olympus Example|%d|%d|8|5|nil|10"):format(T14, T14 + 2),
		("E|Olympus Second|%d|%d|950|310|Sample Reporter-ClassicBetaPvP2|11"):format(T14, T14 + 70),
		("E|Olympus Third|%d|%d|420|96|Sample Herald-ClassicBetaPvP|12"):format(T14, T14 + 5 * 60),
		("C|Olympus Example|mark:%d|%d|8|6|nil|13"):format(T14 + 10 * 60, T14 + 10 * 60 + 2),
		("C|Olympus Example|%d|%d|8|7|nil|15"):format(T14 + 15 * 60, T14 + 15 * 60 + 2),
		("E|Olympus Second|%d|%d|955|330|Sample Reporter-ClassicBetaPvP2|16"):format(T14 + 15 * 60, T14 + 16 * 60),
	}, "\n"))
	local c, e = A.observations[1], A.observations[2]
	eq(c.slot, T14); eq(c.rows, 8); eq(c.rowsOnline, 5)
	eq(e.reportedAt, T14 + 68, "the report's own time, field 3"); eq(e.users, 12); eq(e.slot, nil)
	-- The rosters, by checkpoint. Between 14:00 and 14:15 Charlie levels, Alpha logs in, Echo leaves and
	-- Foxtrot joins.
	local function List(t) return table.concat(t, ", ") end
	local at14 = A.roster[T14]
	eq(List(at14.present), "Leader Example-ClassicBetaPvP, Member Alpha-ClassicBetaPvP, Member Bravo-ClassicBetaPvP2, Member Charlie-ClassicBetaPvP, "
		.. "Member Delta-ClassicBetaPvP2, Member Echo-ClassicBetaPvP, Witness Example-ClassicBetaPvP, Witness Second-ClassicBetaPvP")
	eq(List(at14.online), "Leader Example-ClassicBetaPvP, Member Bravo-ClassicBetaPvP2, Member Delta-ClassicBetaPvP2, Witness Example-ClassicBetaPvP, Witness Second-ClassicBetaPvP")
	eq(List(A.roster["mark:" .. (T14 + 10 * 60)].online), "Leader Example-ClassicBetaPvP, Member Alpha-ClassicBetaPvP, Member Bravo-ClassicBetaPvP2, "
		.. "Member Delta-ClassicBetaPvP2, Witness Example-ClassicBetaPvP, Witness Second-ClassicBetaPvP")
	local at15 = A.roster[T14 + 15 * 60]
	eq(List(at15.present), "Leader Example-ClassicBetaPvP, Member Alpha-ClassicBetaPvP, Member Bravo-ClassicBetaPvP2, Member Charlie-ClassicBetaPvP, "
		.. "Member Delta-ClassicBetaPvP2, Member Foxtrot-ClassicBetaPvP, Witness Example-ClassicBetaPvP, Witness Second-ClassicBetaPvP")
	eq(List(at15.online), "Leader Example-ClassicBetaPvP, Member Alpha-ClassicBetaPvP, Member Bravo-ClassicBetaPvP2, Member Delta-ClassicBetaPvP2, "
		.. "Member Foxtrot-ClassicBetaPvP, Witness Example-ClassicBetaPvP, Witness Second-ClassicBetaPvP")
	eq(at15.presentKeys[6], "Member Foxtrot-ClassicBetaPvP|Player-0000-00000007", "with the GUID too")
	-- B's 14:15 is A's, though Foxtrot is member 9 for A and 8 for B.
	local b15 = B.roster[T14 + 15 * 60]
	for _, k in ipairs({ "present", "online", "presentKeys", "onlineKeys" }) do eq(List(b15[k]), List(at15[k]), k) end
	eq(B.roster[T14], nil, "B arrived after 14:00")
end)

-- A regression: the check compared n with the lines before it hashed them, so a line removed from a
-- session said only "n is not the number of lines", not where.
test("record mode: Record.VerifyFile says where an edited sample breaks: an edited total at its own line, a dropped or a reordered line at the first mark after it", function()
	local R, sha = Sandboxed()
	local function Edited(edit)
		local db = SampleDb("record-sample.lua")
		edit(db.sessions[1].lines)
		local r = R.VerifyFile(db, sha)
		eq(#r.sessions, 1)
		return r, r.sessions[1]
	end
	-- 14:15's checkpoint (line 15) says 9 members instead of 8.
	local r, e = Edited(function(lines) lines[15] = lines[15]:gsub("|Olympus Example|8|", "|Olympus Example|9|", 1) end)
	eq(r.ok, false); eq(e.ok, false); eq(e.brokenAt, 15); eq(e.why, "line 15: its mark is not its hash")
	eq(e.lastHash ~= DOC_HEAD.A, true, "the head computed again is no longer the published one")
	eq(e.observations[5].total, 9, "(the edited claim is still read: the session is broken, kept out of the counts)")
	-- An E line edited after the last checkpoint: only the Z line's mark finds it (section 7).
	r, e = Edited(function(lines) lines[16] = lines[16]:gsub("|955|", "|999|", 1) end)
	eq(e.why, "line 17: its mark is not its hash")
	-- A line dropped: an E line (11), then a member's line (5).
	r, e = Edited(function(lines) table.remove(lines, 11) end)
	eq(e.ok, false); eq(e.records, 16); eq(e.why, "line 13: its mark is not its hash", "the first mark after line 10, the last mark before it")
	r, e = Edited(function(lines) table.remove(lines, 5) end)
	eq(e.why, "line 10: its mark is not its hash")
	r, e = Edited(function(lines) table.remove(lines) end)
	eq(e.why, "line 16: the last line is no Z line", "the Z line dropped")
	-- Two lines swapped, each of them intact: two census reports (11, 12), then two members (2, 3).
	r, e = Edited(function(lines) lines[11], lines[12] = lines[12], lines[11] end)
	eq(e.records, 17); eq(e.why, "line 13: its mark is not its hash")
	r, e = Edited(function(lines) lines[2], lines[3] = lines[3], lines[2] end)
	eq(e.why, "line 10: its mark is not its hash")
	-- Untouched, the same file verifies.
	r, e = Edited(function() end)
	eq(r.ok, true); eq(e.lastHash, DOC_HEAD.A)
end)

-- A regression: Record.lua needed ns.On to load, which a verifier's namespace has no use for.
test("record mode: Record.VerifyFile never calls any WoW API: Sign.lua and Record.lua load and verify with no global but Lua's own and bit, in a namespace of ns.L alone", function()
	local R, sha, touched, sns = Sandboxed()
	local A, B = SampleDb("record-sample.lua"), SampleDb("record-sample-b.lua")
	local edited = Copied(A)
	edited.sessions[1].lines[15] = edited.sessions[1].lines[15]:gsub("|8|7|8|7|", "|8|8|8|8|", 1)
	local odd = Copied(B)
	odd.sessions[2], odd.sessions[3], odd.sessions[4] = "no session", { lines = { 5 } }, Copied(odd.sessions[1])
	for _, db in ipairs({ A, B, edited, odd }) do R.VerifyFile(db, sha) end
	eq(R.VerifyFile(A).sessions[1].lastHash, DOC_HEAD.A, "with no sha given: the namespace's own Sign.SHA256")
	local refused = R.VerifyFile({ format = "olympus-record", version = 2, sessions = A.sessions }, sha)
	eq(refused.ok, false); eq(refused.why, "no OlympusRecordDB of format 1"); eq(#refused.sessions, 0)
	eq(R.VerifyFile(nil, sha).why, "no OlympusRecordDB of format 1")
	local r = R.VerifyFile(odd, sha)
	eq(#r.sessions, 3, "the repeat left out"); eq(r.duplicates, 1); eq(r.ok, false)
	eq(r.sessions[2].why, "no lines"); eq(r.sessions[2].brokenAt, 0); eq(r.sessions[3].why, "line 1: the first line is no S line of format 1")
	eq(#touched, 0, "globals touched: " .. table.concat(touched, ", "))
	local keys = {}
	for k in pairs(sns) do keys[#keys + 1] = k end
	table.sort(keys)
	eq(table.concat(keys, ","), "L,Record,Sign", "nothing else added to the namespace")
	-- A SHA-256 that gives hex instead of the 32 bytes is refused, not hashed into wrong heads.
	local ok, err = pcall(R.VerifyFile, A, function(text) return R.Hex(sha(text)) end)
	eq(ok, false); assert(tostring(err):find("32 bytes", 1, true), tostring(err))
end)

-- A regression: copies of one session were compared by their lines, n and head, not their marks,
-- so a copy whose marks were edited was kept or left out by the order of the files.
test("record mode: a session that repeats is kept once, by VerifyFile in one file and record-check across files; copies that differ, even by one mark, are all left out whatever the order", function()
	local R, sha = Sandboxed()
	local db = SampleDb("record-sample.lua")
	local twice = Copied(db)
	twice.sessions[2] = Copied(db.sessions[1])
	local r = R.VerifyFile(twice, sha)
	eq(r.ok, true); eq(#r.sessions, 1); eq(r.duplicates, 1); eq(#r.conflicts, 0)
	local marked = Copied(db)
	marked.sessions[1].marks[3] = marked.sessions[1].marks[3]:gsub(":6e", ":7e", 1)
	local both = Copied(db)
	both.sessions[2] = marked.sessions[1]
	r = R.VerifyFile(both, sha)
	eq(r.ok, false); eq(#r.conflicts, 1); eq(r.conflicts[1].id, db.sessions[1].id); eq(r.conflicts[1].copies, 2)
	eq(#r.sessions, 2, "both copies listed"); eq(r.sessions[1].ok, false); eq(r.sessions[2].ok, false)
	eq(r.sessions[1].why, ("the copies of session %s in this file differ"):format(db.sessions[1].id))
	eq(r.sessions[2].why, "line 13: its mark is not its hash")
	-- record-check, across two days' files in either order.
	local C = assert(loadfile(ROOT .. "scripts/record-check.lua"))("--module")
	local CR = C.Load()
	for _, order in ipairs({ { { "day1", db }, { "day2", marked } }, { { "day2", marked }, { "day1", db } } }) do
		local all = {}
		for _, pair in ipairs(order) do
			for _, e in ipairs(C.Sessions(CR, pair[2], pair[1])) do all[#all + 1] = e end
		end
		local kept, conflicts = C.Dedupe(all)
		eq(#kept, 0, "neither copy counted"); eq(#conflicts, 1)
		eq(table.concat(conflicts[1].files, ","), order[1][1] .. "," .. order[2][1])
	end
	local all = {}
	for _, f in ipairs({ { "day1", db }, { "day2", SampleDb("record-sample.lua") } }) do
		for _, e in ipairs(C.Sessions(CR, f[2], f[1])) do all[#all + 1] = e end
	end
	local kept, conflicts = C.Dedupe(all)
	eq(#kept, 1, "the same copy in two files: kept once"); eq(#conflicts, 0)
	-- record-check reads the files only through VerifyFile and Dedupe: no chain or line reading of its own.
	local src = assert(ReadFile(ROOT .. "scripts/record-check.lua")):gsub("%-%-[^\n]*", "")
	assert(src:find("R.VerifyFile(", 1, true) and src:find("R.Dedupe(", 1, true), "it calls them")
	for _, own in ipairs({ "Unbitmap", "Split", "Verify(", "Link", "Seed", "SHA256" }) do
		eq(src:find(own, 1, true), nil, "record-check has no " .. own .. " of its own")
	end
end)

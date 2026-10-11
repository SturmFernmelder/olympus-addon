-- 1.2.3, the once-a-minute roster scan (Roster.lua): it keeps what has not changed (a member's row,
-- the members' order, byName), reads GetGuildRosterLastOnline for every member offline at every scan
-- as 1.2.2 did, and asks GetPlayerInfoByGUID again for a race it did not give after a wait that
-- doubles. What a reader gets must be what 1.2.2's scan gave (tests/fixtures/roster-1.2.2.lua). Each
-- test loads Roster.lua into a table of its own over the harness's ns and scans a guild made here.
-- Run alone: luajit tests/run.lua "1.2.3 roster"
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]roster%.lua$")) or "./"

local RANKS = { "Lord", "Captain", "Veteran", "Member", "Recruit" }
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local ZONES = { "Stormwind City", "Elwynn Forest", "Westfall", "The Stockade", "Duskwood" }
local RACES = { { "Human", "Human" }, { "Dwarf", "Dwarf" }, { "NightElf", "Night Elf" }, { "Gnome", "Gnome" } }
local T0 = 1800000000

-- A guild of n members (invented names), the harness's own player the third (so a scan of every
-- row is a complete one): ranks, levels, classes, zones, hours offline, GUIDs and races varied.
local function Guild(n)
	local roster = {}
	for i = 1, n do
		roster[i] = {
			name = i == 3 and ns.me or ("Member%03d-Realm"):format(i),
			rank = i == 1 and 0 or (i <= 4 and 1 or (i <= 20 and 2 or (i <= 80 and 3 or 4))),
			level = (i * 7) % 60 + 1, class = CLASSES[i % #CLASSES + 1], online = i == 1 or i % 4 == 0,
			zone = ZONES[i % #ZONES + 1], last = { 0, i % 3, i % 28, i % 24 },
			guid = ("Player-4619-%08X"):format(i), race = RACES[i % #RACES + 1],
		}
	end
	return roster
end
local function Member(name, level, online, guid)
	return { name = name, rank = 4, level = level, class = "MAGE", online = online, zone = "Westfall",
		last = { 0, 0, 3, 0 }, guid = guid, race = RACES[2] }
end

-- The game's roster functions over w.roster, counting the calls (w.last: GetGuildRosterLastOnline's,
-- w.asked[guid]: GetPlayerInfoByGUID's); fn(w); then the harness's own back. A member `loading` is
-- a row the client has not filled yet; `silent`, a GUID it never gives a race for; `answersAt`, one
-- it gives at that ask.
local function World(roster, fn)
	local saved = { GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, GetGuildRosterLastOnline, GetPlayerInfoByGUID,
		GuildControlGetNumRanks, GuildControlGetRankName }
	local w = { roster = roster, clock = T0, last = 0, asked = {} }
	GetGuildInfo = function() return "Olympus II", "Captain", 1 end
	GetNumGuildMembers = function()
		local on = 0
		for _, m in ipairs(w.roster) do if m.online then on = on + 1 end end
		return #w.roster, on
	end
	GetGuildRosterInfo = function(i)
		local m = w.roster[i]
		if not m or m.loading then return nil end
		return m.name, RANKS[m.rank + 1], m.rank, m.level, "Class", m.online and m.zone or nil, "", "", m.online, 0, m.class,
			0, 0, false, false, 0, m.guid
	end
	GetGuildRosterLastOnline = function(i)
		w.last = w.last + 1
		local m = w.roster[i]
		if not m or m.online then return nil end
		return unpack(m.last)
	end
	GetPlayerInfoByGUID = function(guid)
		w.asked[guid] = (w.asked[guid] or 0) + 1
		for _, m in ipairs(w.roster) do
			if m.guid == guid then
				if m.silent or (m.answersAt and w.asked[guid] < m.answersAt) then return nil end
				return "Mage", "MAGE", m.race[2], m.race[1], 2, ns.ShortName(m.name), "Realm"
			end
		end
		return nil
	end
	GuildControlGetNumRanks = function() return #RANKS end
	GuildControlGetRankName = function(i) return RANKS[i] end
	local ok, err = pcall(fn, w)
	GetGuildInfo, GetNumGuildMembers, GetGuildRosterInfo, GetGuildRosterLastOnline, GetPlayerInfoByGUID,
		GuildControlGetNumRanks, GuildControlGetRankName = unpack(saved, 1, 7)
	if not ok then error(err, 0) end
end

-- Roster.lua (or 1.2.2's: `file`) loaded into a table of its own over the harness's ns, on w's
-- clock; no event of the harness's reaches it.
local function Load(file, w)
	local c = setmetatable({ RegisterEvent = function() end, On = function() end }, { __index = ns })
	c.Now = function() return w.clock end
	assert(loadfile(ROOT .. file))("Olympus", c)
	return c
end

-- The first difference between a and b (where, and both values), or nil: tables by their keys and
-- values, recursively, whatever order pairs gives them in.
local function Diff(a, b, path)
	if type(a) ~= "table" or type(b) ~= "table" then
		if a ~= b then return ("%s: %s ~= %s"):format(path, tostring(a), tostring(b)) end
		return nil
	end
	for k, v in pairs(a) do
		local d = Diff(v, b[k], path .. "." .. tostring(k))
		if d then return d end
	end
	for k, v in pairs(b) do
		if a[k] == nil then return ("%s.%s: nil ~= %s"):format(path, tostring(k), tostring(v)) end
	end
	return nil
end

-- Everything a reader gets from a scan (r: what it returned): the report and Roster's tables and
-- fields; of lastStats all but the time the scan took.
local function Seen(c, r)
	local R, stats = c.Roster, {}
	for k, v in pairs(R.lastStats or {}) do if k ~= "ms" then stats[k] = v end end
	return { report = r, members = R.members, online = R.online, byName = R.byName, guild = R.guild, complete = R.complete,
		rawRealms = R.rawRealms, servers = R.servers, rawSample = R.rawSample, stats = stats, group = R.group,
		faction = R.faction, generation = R.generation, snapshotAt = R.snapshotAt }
end

local function RowOf(c, raw)
	for _, row in ipairs(c.Roster.members) do if row.raw == raw then return row end end
	return nil
end

test("1.2.3 roster: each scan gives what 1.2.2's gave: unchanged, the hours of one who logged in and out between two scans, a rank, a logout and a login, a zone, a level, one leaving and one joining, a few and many at once, a row not loaded yet, a new server order, a row read twice, one name with and without its realm", function()
	World(Guild(120), function(w)
		local old, new = Load("tests/fixtures/roster-1.2.2.lua", w), Load("Olympus/Roster.lua", w)
		local R = w.roster
		local function Both(what)
			w.clock = w.clock + 60
			local a, b = old.Roster.Scan(), new.Roster.Scan()
			local d = Diff(Seen(old, a), Seen(new, b), "")
			if d then error(what .. ": " .. d, 2) end
		end
		R[7].silent = true -- (a GUID the client never answers for: no race in either)
		Both("the first scan")
		Both("nothing changed")
		Both("nothing changed again")
		-- Offline at both scans: one logged in and out between them, another's hour ticked.
		R[2].last, R[5].last = { 0, 0, 0, 0 }, { 0, 2, 5, 6 }
		Both("in and out between two scans, an hour more")
		R[30].rank = 1
		Both("a rank")
		R[40].online, R[41].online = false, true
		Both("a logout and a login")
		R[8].zone = "Duskwood"
		Both("a zone")
		R[50].level = R[50].level + 1
		Both("a level")
		R[25].guid, R[26].guid = "Player-4620-0000BEEE", nil
		Both("a GUID of another server, and none")
		table.remove(R, 60)
		Both("one left")
		table.insert(R, 33, Member("Newcomer-Realm", 5, true, "Player-4619-0000BEEF"))
		Both("one joined")
		for i = 70, 74 do R[i].level = R[i].level % 60 + 1 end
		table.remove(R, 90)
		table.insert(R, 12, Member("Second-Realm", 44, false, "Player-4619-0000BEF0"))
		R[20].online = not R[20].online
		Both("a few at once")
		for i = 10, 100 do R[i].level = R[i].level % 60 + 1 end
		Both("many levels at once")
		Both("steady after them")
		R[15].loading = true
		Both("a row not loaded yet")
		R[15].loading = nil
		Both("loaded")
		local reversed = {}
		for i = #R, 1, -1 do reversed[#reversed + 1] = R[i] end
		w.roster, R = reversed, reversed
		Both("the server's order")
		table.insert(R, 5, R[20])
		Both("a row read twice")
		table.remove(R, 5)
		Both("read once again")
		-- "Twin" without its realm is ns.FullName's "Twin-Realm": one name in byName, a tie in the order.
		table.insert(R, 2, Member("Twin", 30, true, "Player-4619-0000BEF1"))
		table.insert(R, Member("Twin-Realm", 30, false, "Player-4619-0000BEF2"))
		Both("a name with and without its realm")
		Both("still both")
		table.remove(R, 2)
		table.remove(R)
		Both("the twins gone")
		-- The same names on another realm (ns.realm: what ns.DisplayName shortens): every name anew.
		local realm = ns.realm
		local ok, err = pcall(function()
			ns.realm = "Elsewhere"
			Both("another realm")
		end)
		ns.realm = realm
		if not ok then error(err, 0) end
		Both("our realm again")
		for k = 1, 6 do Both("steady " .. k) end
	end)
end)

test("1.2.3 roster: an unchanged roster makes nothing new (the same rows, order and byName); who changed gets a new row and the others keep theirs; byName is new only when a name or rank changed; a table a reader holds is never written again", function()
	World(Guild(40), function(w)
		local c = Load("Olympus/Roster.lua", w)
		local R = c.Roster
		R.Scan()
		local members, byName, online = R.members, R.byName, R.online
		R.Scan()
		eq(R.members, members, "the same order")
		eq(R.byName, byName, "the same byName")
		eq(#R.online, #online)
		for i, o in ipairs(R.online) do eq(o, online[i], "the same online row " .. i) end
		-- A zone: his online row alone (the members' rows have no zone).
		local zoned = w.roster[8]
		zoned.zone = "Duskwood"
		R.Scan()
		eq(R.members, members, "a zone changes no member's row")
		for i, o in ipairs(R.online) do
			if o.name == ns.ShortName(zoned.name) then
				assert(o ~= online[i], "his online row is new"); eq(o.zone, ns.Zones.KeyForName("Duskwood"))
			else
				eq(o, online[i], "the others' online rows kept")
			end
		end
		-- A level: his row new, a new order; the one a reader holds as it was.
		local held = {}
		for i, row in ipairs(members) do held[i] = row end
		local leveled = w.roster[13]
		local before = RowOf(c, leveled.name)
		leveled.level = leveled.level + 1
		R.Scan()
		assert(R.members ~= members, "a new order")
		eq(#members, #held)
		for i, row in ipairs(members) do eq(row, held[i], "the order a reader holds, place " .. i) end
		eq(before.level, leveled.level - 1, "his old row as it was")
		for _, row in ipairs(R.members) do
			if row.raw == leveled.name then
				assert(row ~= before, "his row is new"); eq(row.level, leveled.level)
			else
				local kept
				for _, h in ipairs(held) do if h == row then kept = true end end
				assert(kept, row.raw .. " keeps his row")
			end
		end
		eq(R.byName, byName, "no name or rank changed")
		-- A rank: a new byName; the one a reader holds says what it said.
		w.roster[30].rank = 1
		R.Scan()
		assert(R.byName ~= byName, "a new byName")
		eq(byName[w.roster[30].name], 3, "the held one as it was")
		eq(R.byName[w.roster[30].name], 1)
		-- Written by someone else (a name added, one taken out) or replaced: the next scan's is a new
		-- one, as the server gives it.
		local written = R.byName
		written["Ghost-Realm"] = 3
		R.Scan()
		assert(R.byName ~= written); eq(R.byName["Ghost-Realm"], nil)
		written = R.byName
		written[w.roster[9].name] = nil
		R.Scan()
		assert(R.byName ~= written); eq(R.byName[w.roster[9].name], 2)
		local foreign = {}
		for k, v in pairs(R.byName) do foreign[k] = v end
		R.byName = foreign
		R.Scan()
		assert(R.byName ~= foreign, "not someone else's table")
		eq(Diff(foreign, R.byName, "byName"), nil)
	end)
end)

test("1.2.3 roster: GetGuildRosterLastOnline is read for every member offline at every scan, as 1.2.2: one offline at two scans who logged in and out between them has his new hours at the next (his row, the inactive counts, the Lord's leaderDays); one whose hours are the same keeps his row", function()
	World(Guild(20), function(w)
		local c = Load("Olympus/Roster.lua", w)
		local R = c.Roster
		local lord = w.roster[1]
		lord.online, lord.last = false, { 0, 1, 15, 0 }
		local offline = 0
		for _, m in ipairs(w.roster) do if not m.online then offline = offline + 1 end end
		local function Scan()
			w.last, w.clock = 0, w.clock + 60
			return R.Scan()
		end
		local r = Scan()
		eq(w.last, offline, "the first scan reads every member offline")
		local away, ticking, still = w.roster[2], w.roster[5], w.roster[6] -- (offline: 2 months 2 days 2 hours; 2 months 5 days 5 hours; 6 days 6 hours)
		eq(RowOf(c, away.name).days, 2 * 30 + 2 + 2 / 24)
		eq(r.leaderDays, 45)
		local inactive7, inactive30 = r.inactive7, r.inactive30
		r = Scan()
		local before, kept = RowOf(c, away.name), RowOf(c, still.name)
		-- Between this scan and the next, he logs in for his mail and out again (offline at both), the
		-- Lord too, and another one's hour ticks.
		away.last, lord.last, ticking.last = { 0, 0, 0, 0 }, { 0, 0, 0, 1 }, { 0, ticking.last[2], ticking.last[3], ticking.last[4] + 1 }
		r = Scan()
		local row = RowOf(c, away.name)
		eq(row.days, 0, "the hours of his visit, not the 62 days before it")
		eq(row.online, false)
		assert(row ~= before, "his row is new")
		eq(before.days, 2 * 30 + 2 + 2 / 24, "the row a reader holds as it was")
		eq(r.inactive7, inactive7 - 2, "he and the Lord no longer 7 days away")
		eq(r.inactive30, inactive30 - 2, "nor 30")
		eq(r.leaderDays, 1 / 24, "the Lord's hour, not his 45 days")
		eq(RowOf(c, ticking.name).days, 2 * 30 + 5 + 6 / 24, "the hour he gained")
		eq(RowOf(c, still.name), kept, "the same hours: his row kept")
		eq(w.last, offline, "every member offline read at every scan")
		-- One more logs out, one is new, one comes back: every member offline read, not he.
		local out = w.roster[4]
		out.online, out.last = false, { 0, 0, 0, 2 }
		w.roster[#w.roster + 1] = Member("Late-Realm", 9, false, "Player-4619-0000CAFE")
		local back = w.roster[7]
		back.online = true
		Scan()
		eq(w.last, offline + 1, "one more out, one new, one back")
		eq(RowOf(c, out.name).days, 2 / 24)
		eq(RowOf(c, "Late-Realm").days, 3)
		eq(RowOf(c, back.name).days, 0)
	end)
end)

test("1.2.3 roster: a GUID the client gives no race for is asked again at the next scan, then after a wait that doubles up to RACE_RETRY; an answer is kept while he stays (a row not loaded yet included) and asked anew once a complete scan no longer has him", function()
	World(Guild(12), function(w)
		local c = Load("Olympus/Roster.lua", w)
		local R = c.Roster
		eq(R.RACE_RETRY, 600)
		local silent, late, known = w.roster[5], w.roster[6], w.roster[7]
		silent.silent, late.answersAt = true, 2
		local asks = {}
		for t = 0, 1500, 60 do
			w.clock = T0 + t
			R.Scan()
			if t == 0 then eq(RowOf(c, late.name).race, nil, "not given yet") end
			if t == 60 then
				eq(RowOf(c, late.name).race, late.race[1], "given at the next scan, as before")
				eq(RowOf(c, late.name).raceName, late.race[2])
			end
			if (w.asked[silent.guid] or 0) > #asks then asks[#asks + 1] = t end
		end
		eq(table.concat(asks, ","), "0,60,180,420,900,1500", "the next scan, then after 2, 4 and 8 minutes, then every 10")
		eq(RowOf(c, silent.name).race, nil)
		eq(w.asked[late.guid], 2, "never asked once it answered")
		eq(w.asked[known.guid], 1, "an answer is kept")
		eq(RowOf(c, known.name).race, known.race[1])
		-- His row not loaded yet (a partial scan): his answer kept.
		known.loading = true
		w.clock = T0 + 1560
		R.Scan()
		eq(R.complete, false)
		eq(RowOf(c, known.name), nil)
		known.loading = nil
		w.clock = T0 + 1620
		R.Scan()
		eq(w.asked[known.guid], 1, "not asked again")
		eq(RowOf(c, known.name).race, known.race[1])
		-- He leaves (a complete scan without him) and comes back: asked anew.
		table.remove(w.roster, 7)
		w.clock = T0 + 1680
		R.Scan()
		eq(R.complete, true)
		table.insert(w.roster, 7, known)
		w.clock = T0 + 1740
		R.Scan()
		eq(w.asked[known.guid], 2, "forgotten when he left")
		eq(RowOf(c, known.name).race, known.race[1])
	end)
end)

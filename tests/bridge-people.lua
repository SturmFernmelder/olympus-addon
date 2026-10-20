-- The Companion's people sections (Olympus/BridgePeople.lua, and the ranking boards in
-- Olympus/BridgeSections.lua): realm, roster, rankings' boards, wanted, church, games and profile.
-- What each carries is what the page that shows it lists, within the registry's limits; nothing
-- before the Olympus Accord, nor for a non-member; a module's error leaves its own section empty and
-- every other one whole; all of them together stay small for a guild of 1000 members and full
-- boards. The modules a section reads are stand-ins here (the registry's own contract is in
-- tests/run.lua); the roster's and the census's are the harness's own. Loaded by tests/run.lua.
-- Run alone: luajit tests/run.lua "bridge people"
local ns, test, eq = ...
local B = OlympusBridge

local NOW = 1800000000
local ME = ns.me -- "Tester-Realm"
local MY_GK = "4619-0000ABCD"
local NEW = { "realm", "roster", "church", "games", "profile" }
-- (The census's guilds and statistics too: no page shows them before the Accord or to an outsider,
-- UI.Locked; the review of 2026-10-20 found them given to both.)
local GATED = { "realm", "roster", "church", "games", "profile", "rankings", "wanted", "guilds", "stats" }

local function Fields(row) local out = {} for f in (row .. "~"):gmatch("(.-)~") do out[#out + 1] = f end return out end
local function Count(fields) local n = 0 for _ in fields:gmatch("[^~]+") do n = n + 1 end return n end

-- Every string of a section, at any depth (to look for what must never be there).
local function Strings(v, out)
	out = out or {}
	if type(v) == "string" then out[#out + 1] = v
	elseif type(v) == "table" then for k, x in pairs(v) do Strings(k, out) Strings(x, out) end end
	return out
end
local function Never(data, needle, what)
	for _, s in ipairs(Strings(data)) do assert(not s:find(needle, 1, true), (what or needle) .. " in " .. s) end
end

-- n names of up to 12 letters, one per i, none alike.
local function Name(prefix, i)
	local s, n = "", i
	repeat s = string.char(97 + n % 26) .. s; n = math.floor(n / 26) until n == 0
	return (prefix .. s):sub(1, 12)
end

---------------------------------------------------------------------------
-- The stand-ins: the modules the sections read, full by default (o.rows rows per board).
---------------------------------------------------------------------------

local function Rows(n, make) local out = {} for i = 1, n do out[i] = make(i) end return out end

local function Modules(o)
	o = o or {}
	local rows = o.rows or 60
	local public = o.public or { arena = true, bones = true }
	local m = {}
	m.ArenaHome = {
		RankingsPublic = function(game) return public[game] == true end,
		Name = function(name) return ns.DisplayName(name) end,
		TabVisible = function() if o.arenaOff then return false end return true end,
	}
	m.ArenaProfile = { MyGk = function() return MY_GK end, Mine = function() return { nick = "3.4" } end,
		NickText = function(nick) return nick == "3.4" and "the Grim Wolf" or nil end }
	m.ArenaLedger = {
		Ranking = function()
			return Rows(rows, function(i)
				return { rank = i, gk = i == 7 and MY_GK or ("4619-%08X"):format(i), name = i == 7 and ME or (Name("Duelist", i) .. "-Realm"),
					rating = 2000 - i, wins = 40 - (i % 40), losses = i % 9 }
			end)
		end,
		-- (ArenaLedger.History's rows: `title` is the ledger's flag, a boolean, true for a title fight.)
		History = function()
			return Rows(40, function(i)
				return { fid = ("F%04d"):format(i), t = NOW - i * 600, A = Name("Red", i) .. "-Realm", B = Name("Blue", i) .. "-Realm",
					winner = Name("Red", i) .. "-Realm", public = true, method = "KO", title = i == 2 }
			end)
		end,
	}
	m.ArenaFights = {
		Events = function()
			return Rows(30, function(i)
				local kind = ({ "card", "tourney", "fight" })[i % 3 + 1]
				return { kind = kind, id = ("E%04d"):format(i), title = "|cffff0000Fight Night|r " .. i, at = NOW + i * 60, live = i == 1,
					ended = false, upcoming = i > 1, count = 4, mode = "L" }
			end)
		end,
	}
	m.FarkleTable = {
		Best = function()
			return Rows(rows, function(i)
				return { place = i, name = i == 4 and ME or (Name("Thrower", i) .. "-Realm"), games = 30, won = 30 - (i % 30) }
			end)
		end,
		LiveTables = function()
			return { { id = "K0001", p1 = "Host-Realm", p2 = "Guest-Realm", at = NOW - 30, mode = "L", official = true },
				{ id = "K0002", p1 = "Rehearsal-Realm", p2 = "Other-Realm", at = NOW - 20, mode = "T" } }
		end,
		MyGames = function()
			return { { id = "g1", res = "W" }, { id = "g2", res = "W" }, { id = "g3", res = "L" }, { id = "g4", res = "W", reh = true }, { id = "g5", res = "D" } }
		end,
	}
	m.CraftRanking = {
		Current = function()
			return Rows(rows, function(i)
				return { place = i, name = i == 2 and ME or (Name("Smith", i) .. "-Realm"), points = 500 - i, deliveries = 20, customers = 9 }
			end)
		end,
	}
	m.Wanted = {
		Rankings = function()
			local function Board()
				return Rows(rows, function(i)
					return { place = i, key = "k" .. i, name = i == 9 and ME or Name("Slayer", i), guid = ("Player-4619-%08X"):format(i),
						points = 900 - i, claims = 3 }
				end)
			end
			return { month = Board(), all = Board() }
		end,
	}
	m.ChurchCount = {
		PUBLIC_ROWS = 10,
		PublicView = function()
			if o.churchShut then return nil end
			local function List(prefix)
				local out = {}
				for i = 1, 10 do out[i] = { name = i == 3 and "Tester" or Name(prefix, i), s30 = 12.5 - i / 10, sall = 99.25 } end
				return out
			end
			return { a = List("Apostle"), m = List("Missionary") }
		end,
		DetailView = function(person, window)
			if person ~= ME then error("another person's detail") end
			if window == "w" then return {} end
			return { { "s", 4, 1.5, 0.5, 0 }, { "j", 6, 2, 5, 1 }, { "t", 1, 3, 12, 6 }, { "g", "Olympus II", 6, 5, 0 },
				{ "r", "Secret Recruit", NOW - 60, "open", 0 } }
		end,
		Local = function() return { invWeek = 7, invAll = 40, joins = 2, leaves = 1, members = 990 } end,
		Mine = function() return { pub = true, regs = { a = { n = "Secret Recruit", at = NOW }, b = { n = "Other Recruit", at = NOW } }, inv = {} } end,
	}
	local person = o.churchPerson ~= false
	m.Church = {
		IsPerson = function() return person end,
		Role = function() return person and "M" or nil end,
		Key = function(name) return ns.Fold(ns.FullName(name)) end,
		State = function()
			return { apostle = { ap = { n = "Saint-Realm" } }, miss = { pa = { n = "Elder-Realm" } }, corrOf = {}, corr = {} }
		end,
		Place = function() return { role = "M", net = "ap", parent = "pa" } end,
	}
	m.HonorsNet = {
		Holdings = function()
			return Rows(o.honours or 3, function(i)
				return { key = i == 1 and "donor-top" or ("honour-" .. i), frame = i % 2 == 1 and ("frame-" .. i) or nil,
					title = i <= 2 and ("title-" .. i) or nil, place = i, art = "secret/art" }
			end)
		end,
		TitleText = function(key) return "Title of " .. key end,
	}
	m.API = {
		Profile = function()
			return { member = true, name = ME, guild = "Olympus II", rank = "Zeus", rankIndex = 0, role = "guildmaster", frame = "donor-top",
				title = "Title of donor-top" }
		end,
		Rankings = function()
			local function Slayers() return Rows(50, function(i) return { place = i, name = Name("Slayer", i), points = 900 - i, claims = 3 } end) end
			return {
				slayers = { month = Slayers(), all = Slayers(), signed = Rows(3, function(i) return { place = i, name = Name("Slayer", i), points = 1, claims = 1 } end) },
				donors = { all = { "Giver", ME, "Third" }, month = { "Monthly" } },
				church = { missionaries = { "A", "B", "C" }, apostles = { "D", "E", "F" } },
				games = {
					arena = Rows(10, function(i) return { place = i, name = Name("Duelist", i), rating = 2000 - i, wins = 3, losses = 1 } end),
					bones = Rows(10, function(i) return { place = i, name = Name("Thrower", i), games = 30, won = 20 } end),
				},
			}
		end,
		Wanted = function()
			return Rows(o.wanted or 150, function(i)
				return { place = i, name = Name("Hordie", i), guid = ("Player-4619-%08X"):format(i), bounty = 50, kills = 3, cycle = 1,
					victims = { "Victim" }, addedBy = "A Mod" }
			end)
		end,
	}
	m.Treasury = {
		PublicShows = function(what) return (o.treasury or { ranking = true })[what] == true end,
		PublicSpending = function() return 123456, 3 end,
		Report = function(shared, public)
			assert(shared == true and public == true, "the ranking as it may go out")
			return { rank = Rows(rows, function(i) return { name = i == 5 and "Tester" or Name("Giver", i), money = 1000000 - i } end) }
		end,
	}
	return m
end

-- The census: n guilds (the King's <Olympus> first), each from its own roster's report; every
-- 50th an old report (3 hours), its Lord online in it when staleLordOnline.
local function Census(n, now, staleLordOnline)
	local guilds = {}
	guilds.Olympus = { guild = "Olympus", total = 1000, online = 400, t = now - 5, mine = true, avgLevel = 52.34, leader = "Kingly",
		leaderOnline = true, officers = Rows(30, function(i) return { name = Name("Captain", i), online = i % 2 == 0, days = 1 } end),
		inactive7 = 40, inactive30 = 12, battleTag = "Secret#1234" }
	for i = 2, n do
		local name = ("Olympus Vanguard %s"):format(Name("", i))
		guilds[name] = { guild = name, total = 1000 - i, online = 200, t = i % 50 == 0 and now - 3 * 3600 or now - 5, mine = true,
			avgLevel = 40 + (i % 20), leader = Name("Lord", i), leaderOnline = i % 3 == 0 or (staleLordOnline == true and i % 50 == 0), leaderDays = 2.5,
			officers = Rows(30, function(k) return { name = Name("Cap", i * 31 + k), online = false, days = 3 } end),
			inactive7 = i % 7, inactive30 = i % 30, battleTag = "Secret#1234" }
	end
	return guilds
end

-- fn with these modules in place of the harness's, this census, the clock at NOW, then all as it was.
local function With(o, fn)
	o = o or {}
	local m = Modules(o)
	local saved = { rdb = ns.rdb, now = ns.Now, realm = ns.realm, group = ns.group, faction = ns.faction, accord = ns.db.accord,
		guildInfo = GetGuildInfo, level = rawget(_G, "UnitLevel"), class = rawget(_G, "UnitClass"), race = rawget(_G, "UnitRace"),
		guid = rawget(_G, "UnitGUID"), modules = {} }
	for key in pairs(m) do saved.modules[key] = rawget(ns, key) end
	if o.modules then for key in pairs(o.modules) do saved.modules[key] = rawget(ns, key) end end
	for key, value in pairs(m) do rawset(ns, key, value) end
	for key, value in pairs(o.modules or {}) do rawset(ns, key, value or nil) end
	ns.rdb = { guilds = Census(o.guilds or 8, NOW, o.staleLordOnline), seen = {}, treasuryFlags = {} }
	ns.Now = function() return NOW end
	ns.realm, ns.group, ns.faction = "Realm", "Realm", "Alliance"
	UnitLevel = function() return 60 end
	UnitClass = function() return "Mage", "MAGE" end
	UnitRace = function() return "Gnome", "Gnome" end
	UnitGUID = function() return "Player-4619-0000ABCD" end
	local ok, err = pcall(fn, m)
	ns.rdb, ns.Now, ns.realm, ns.group, ns.faction, ns.db.accord = saved.rdb, saved.now, saved.realm, saved.group, saved.faction, saved.accord
	GetGuildInfo, UnitLevel, UnitClass, UnitRace, UnitGUID = saved.guildInfo, saved.level, saved.class, saved.race, saved.guid
	for key, value in pairs(saved.modules) do rawset(ns, key, value) end
	if not ok then error(err, 0) end
end

local function Data(name) return assert(B.GetSection(name), name .. ": the section").data end

local function BoardOf(boards, board, period, list)
	for _, b in ipairs(boards) do
		if b.board == board and b.period == period and b.list == list then return b end
	end
	return nil
end

---------------------------------------------------------------------------

test("bridge people: every section is registered at version 1, and none gives anything before the Olympus Accord, for an older Accord, or to a non-member", function()
	local versions = {}
	for _, s in ipairs(B.Sections()) do versions[s.name] = s.version end
	for _, name in ipairs(NEW) do eq(versions[name], 1, name) end
	ns.Roster.Scan()
	With({}, function()
		for _, name in ipairs(GATED) do assert(B.GetSection(name), name .. ": a member who accepted the Accord gets it") end
		ns.db.accord = nil
		for _, name in ipairs(GATED) do eq(B.GetSection(name), nil, name .. ": no Accord") end
		ns.db.accord = { v = ns.ACCORD_VERSION - 1, yes = true, at = 0 }
		for _, name in ipairs(GATED) do eq(B.GetSection(name), nil, name .. ": an older Accord") end
		ns.db.accord = { v = ns.ACCORD_VERSION, yes = false, at = 0 }
		for _, name in ipairs(GATED) do eq(B.GetSection(name), nil, name .. ": the Accord declined") end
		ns.db.accord = { v = ns.ACCORD_VERSION, yes = true, at = 0 }
		GetGuildInfo = function() return "Horde Pals", "Member", 3 end
		for _, name in ipairs(GATED) do eq(B.GetSection(name), nil, name .. ": not in an Olympus guild") end
	end)
end)

test("bridge people: realm lists the Realm's guilds as rows of their fields in the census's order, at most 256, online only while fresh, the King's name, nothing private", function()
	With({ guilds = 300 }, function()
		local d = Data("realm")
		eq(d.fields, "members~online~avgLevel~captains~inactive7~inactive30~lordOnline~lordDays~lordSeenAt~fresh~name~lord")
		eq(d.faction, "Alliance"); eq(d.realmGroup, "Realm"); eq(d.king, "Kingly"); eq(d.at, NOW)
		eq(#d.guilds, 256, "cut to 256, the census checkpoint's own cap")
		local first = Fields(d.guilds[1])
		eq(#first, Count(d.fields), "an empty lordSeenAt is a field all the same")
		eq(first[1], "1000"); eq(first[2], "400"); eq(first[3], "52.3"); eq(first[4], "30"); eq(first[5], "40"); eq(first[6], "12")
		eq(first[7], "1"); eq(first[8], "0"); eq(first[9], "", "no old report's time for a Lord online now")
		eq(first[10], "1"); eq(first[11], "Olympus"); eq(first[12], "Kingly")
		-- The census's own order (Data.Summary's, the Realm's by default), cut from its end.
		local s = ns.Data.Summary()
		eq(#s.guilds, 300)
		for i, row in ipairs(d.guilds) do
			eq(Fields(row)[11], s.guilds[i].name, "row " .. i .. " in the census's order")
			assert(#row <= B.SECTION_LIMITS.string, row)
		end
		Never(d, "Secret#1234", "a BattleTag")
		Never(d, "Captain", "a Captain's name (their count only)")
	end)
	With({ guilds = 60 }, function()
		local stale = 0
		for _, row in ipairs(Data("realm").guilds) do
			local f = Fields(row)
			if f[10] == "0" then stale = stale + 1; eq(f[2], "0", "an old report counts nobody online") end
			if f[7] == "0" then eq(f[8], "2", "a Lord offline: his days away, whole"); eq(f[9], "") end
		end
		eq(stale, 1, "an old report is listed, grey")
	end)
end)

test("bridge people: realm: a Lord an old report had online, nobody seeing him now, is not known to be online or offline: empty lordOnline and lordDays, and that report's time, as the row's \"online <age> ago\"", function()
	-- (The review of 2026-10-20: the row said "online 3h ago", the section "offline today".)
	With({ guilds = 60, staleLordOnline = true }, function()
		local s, rows = ns.Data.Summary(), {}
		for _, row in ipairs(Data("realm").guilds) do local f = Fields(row) rows[f[11]] = f end
		local old
		for _, e in ipairs(s.guilds) do if e.fresh == false then old = e end end
		assert(old, "the old report")
		local on, days, dim, at = ns.Views.PresenceNow(old, old.g.leader, old.g.leaderOnline, old.g.leaderDays)
		eq(on, nil, "the page: not known now"); eq(days, nil); eq(dim, true); eq(at, NOW - 3 * 3600, "the page: online <age> ago")
		local f = assert(rows[old.name], "its row")
		eq(f[7], "", "lordOnline: unknown"); eq(f[8], "", "lordDays: unknown"); eq(f[9], tostring(NOW - 3 * 3600), "lordSeenAt: the report's time")
		eq(f[10], "0", "an old report")
		-- The others as before: online now, or offline for whole days, and no lordSeenAt.
		local online, offline = 0, 0
		for name, r in pairs(rows) do
			if name ~= old.name then
				eq(r[9], "", name)
				if r[7] == "1" then online = online + 1; eq(r[8], "0") else eq(r[7], "0", name); offline = offline + 1 end
			end
		end
		assert(online > 0 and offline > 0, "both kinds listed")
	end)
end)

test("bridge people: roster is our own guild's every member, online first, with level, class, rank and hours offline; nothing for a roster of another guild", function()
	ns.Roster.Scan() -- (the harness's guild: 1000 members of <Olympus II>, 300 online)
	With({}, function()
		local d = Data("roster")
		eq(d.guild, "Olympus II"); eq(d.total, 1000); eq(d.online, 300); eq(d.at, NOW)
		eq(d.fields, "level~class~rankIndex~online~hoursOffline~name~rank")
		eq(#d.members, 1000, "every member, none cut")
		local top = Fields(d.members[1])
		eq(#top, Count(d.fields)); eq(top[3], "0", "the guild master first"); eq(top[4], "1"); eq(top[5], "0"); eq(top[6], "Member1"); eq(top[7], "rank")
		eq(top[2], "PALADIN", "the class's file name, as the game names it")
		local seenOffline, away = false, 0
		for i, row in ipairs(d.members) do
			local f = Fields(row)
			assert(#row <= B.SECTION_LIMITS.string, row)
			if i <= 300 then eq(f[4], "1", "online first") else
				seenOffline = true
				eq(f[4], "0")
				if f[5] == "768" then away = away + 1 else eq(f[5], "5", "5 hours offline, as the game says") end
			end
		end
		assert(seenOffline); eq(away, 100, "32 days offline: 768 hours")
		-- A roster of the guild this character was in before: nothing, until the new one is read.
		local real = GetGuildInfo
		GetGuildInfo = function(unit) if unit == "player" then return "Olympus III", "Recruit", 3 end return real(unit) end
		eq(B.GetSection("roster"), nil, "another guild's roster")
	end)
end)

test("bridge people: rankings' boards: each public board with its fields, 50 rows at most cut from the end, this character's own place; a game kept private, a closed Treasury or Church give none", function()
	With({}, function()
		local d = Data("rankings")
		local boards = d.boards
		local want = {
			{ "arena", "all", nil, "place~rating~wins~losses~name", 50, 7, 1993 },
			{ "bones", "month", nil, "place~won~games~name", 10, 4, 26 },
			{ "church", "month", "apostles", "place~points10~allTime10~name", 10, 3, 122 },
			{ "church", "month", "missionaries", "place~points10~allTime10~name", 10, 3, 122 },
			{ "crafting", "month", nil, "place~points~deliveries~customers~name", 50, 2, 498 },
			{ "treasury", "all", nil, "place~copper~name", 50, 5, 999995 },
			{ "donors", "all", nil, "place~name", 3, 2, nil },
			{ "donors", "month", nil, "place~name", 1, nil, nil },
			{ "wanted", "month", nil, "place~points~claims~name", 50, 9, 891 },
			{ "wanted", "all", nil, "place~points~claims~name", 50, 9, 891 },
		}
		eq(#boards, #want)
		for _, w in ipairs(want) do
			local b = assert(BoardOf(boards, w[1], w[2], w[3]), w[1] .. " " .. w[2])
			local label = w[1] .. " " .. w[2] .. " " .. tostring(w[3])
			eq(b.fields, w[4], label); eq(#b.rows, w[5], label)
			for i, row in ipairs(b.rows) do
				local f = Fields(row)
				eq(#f, Count(b.fields), label .. " row " .. i)
				eq(f[1], tostring(i), label .. ": in place order, cut from the end")
				assert(#row <= B.SECTION_LIMITS.string, row)
			end
			if w[6] then eq(b.own and b.own.place, w[6], label .. ": his place"); eq(b.own.value, w[7], label .. ": his value")
			else eq(b.own, nil, label .. ": he is not on it") end
		end
		eq(Fields(BoardOf(boards, "arena", "all").rows[7])[5], "Tester", "his own row, by name as the page shows it")
		eq(Fields(BoardOf(boards, "church", "month", "apostles").rows[1])[2], "124", "points in tenths: 12.4")
		-- The legacy kinds stay as they were beside the boards.
		eq(#d.slayers.month, 50); eq(d.treasury, nil, "no spending while the King keeps the balance private")
	end)
	With({ public = {}, treasury = {}, churchShut = true }, function()
		local boards = Data("rankings").boards
		for _, b in ipairs(boards) do
			assert(b.board ~= "arena" and b.board ~= "bones", "a game the King keeps private: no board")
			assert(b.board ~= "treasury", "the Treasury's ranking hidden: no board")
			assert(b.board ~= "church", "the Church's public ranking shut: no board")
		end
		assert(BoardOf(boards, "crafting", "month") and BoardOf(boards, "wanted", "all"), "the boards every member sees stay")
	end)
end)

test("bridge people: a name's colour codes and the rows' separator never reach a board, and a long name keeps its row within the registry's string limit", function()
	With({}, function(m)
		m.CraftRanking.Current = function()
			return { { place = 1, name = "|cffff0000Red|r~Smith-Realm", points = 5, deliveries = 1, customers = 1 },
				{ place = 2, name = string.rep("Long", 60), points = 4, deliveries = 1, customers = 1 } }
		end
		local b = BoardOf(Data("rankings").boards, "crafting", "month")
		local f = Fields(b.rows[1])
		eq(#f, 5); eq(f[5], "RedSmith")
		assert(#b.rows[2] <= B.SECTION_LIMITS.string and #Fields(b.rows[2]) == 5, b.rows[2])
	end)
end)

test("bridge people: wanted keeps its first 100 targets in the list's order, the GUID its target's page shows, never the victims or who added him", function()
	With({ wanted = 150 }, function()
		local d = Data("wanted")
		eq(#d.targets, 100, "cut from the end")
		eq(d.targets[1].place, 1); eq(d.targets[100].place, 100)
		eq(d.targets[1].guid, "Player-4619-00000001")
		for _, t in ipairs(d.targets) do
			for k in pairs(t) do assert(({ place = true, name = true, guid = true, bounty = true, kills = true, cycle = true })[k], k) end
		end
		Never(d, "Victim"); Never(d, "A Mod")
	end)
end)

test("bridge people: church: the public rows while its switch is open, and a Church person's own place and numbers as his page shows them, never his recruits' names", function()
	With({}, function()
		local d = Data("church")
		eq(d.open, true); eq(#d.public, 20)
		eq(d.public[1].list, "apostles"); eq(d.public[11].list, "missionaries"); eq(d.public[3].name, "Tester")
		eq(d.public[1].points, 12.4); eq(d.public[1].allTime, 99.3)
		for _, r in ipairs(d.public) do
			for k in pairs(r) do assert(({ list = true, place = true, name = true, points = true, allTime = true })[k], k) end
		end
		local own = assert(d.own, "a Church person")
		eq(own.role, "missionary"); eq(own.apostle, "Saint"); eq(own.parent, "Elder")
		eq(#own.windows, 2, "the windows his client holds an answer for")
		local m = own.windows[1]
		eq(m.window, "m"); eq(m.points, 6); eq(m.ownPoints, 4); eq(m.recruits, 6); eq(m.pending, 2); eq(m.stays, 5); eq(m.transfers, 1)
		eq(m.taken, 1); eq(m.openRegistrations, 3); eq(m.network, 12)
		eq(own.invitesWeek, 7); eq(own.invitesAll, 40); eq(own.registrations, 2); eq(own.publicRow, true)
		eq(own.guildMembers, nil, "a correspondent's guild numbers only for a correspondent")
		Never(d, "Secret Recruit", "a recruit's name")
		Never(d, "Other Recruit", "a recruit's name")
	end)
	With({ churchPerson = false, churchShut = true }, function()
		local d = Data("church")
		eq(d.open, false); eq(#d.public, 0); eq(d.own, nil, "no Church place: no own numbers")
	end)
end)

test("bridge people: games: the public events and results the pages list, newest first, at most 50, the live realm's alone; his own record, his places only while public; nothing while the arena is off", function()
	With({}, function()
		local d = Data("games")
		eq(#d.events, 50, "cut from the end")
		for i = 2, #d.events do assert(d.events[i - 1].at >= d.events[i].at, "newest first") end
		local kinds, ids = {}, {}
		for _, e in ipairs(d.events) do
			kinds[e.kind] = (kinds[e.kind] or 0) + 1
			ids[e.id] = true
			for k in pairs(e) do
				assert(({ kind = true, id = true, at = true, a = true, b = true, winner = true, state = true, title = true, titleFight = true,
					count = true, official = true })[k], k)
			end
			-- (The review of 2026-10-20: a title fight's `title` was the ledger's boolean beside the
			-- events' text in the same field.)
			if e.title ~= nil then eq(type(e.title), "string", e.id .. ": title is an event's text"); assert(not e.title:find("|", 1, true), e.title) end
			if e.titleFight ~= nil then eq(e.titleFight, true, e.id) end
		end
		eq(kinds.night + kinds.tourney + kinds.duel + kinds.bones, 50)
		assert(ids.K0001, "a live public table"); eq(ids.K0002, nil, "a rehearsal's table")
		local duel, titled
		for _, e in ipairs(d.events) do
			if e.id == "F0001" then duel = e end
			if e.id == "F0002" then titled = e end
		end
		eq(duel.kind, "duel"); eq(duel.state, "over"); eq(duel.winner, Name("Red", 1)); eq(duel.a, Name("Red", 1)); eq(duel.b, Name("Blue", 1))
		eq(duel.titleFight, nil, "not a title fight")
		eq(titled.kind, "duel"); eq(titled.titleFight, true, "a public title fight, flagged"); eq(titled.title, nil, "no text in place of the flag")
		local own = d.own
		eq(own.duelsWon, 33); eq(own.duelsLost, 7); eq(own.rating, 1993); eq(own.duelsPlace, 7)
		eq(own.bonesWon, 2, "the live realm's games alone"); eq(own.bonesLost, 1); eq(own.bonesPlace, 4)
	end)
	With({ public = {} }, function()
		local own = Data("games").own
		eq(own.duelsWon, 33, "his own record whatever the King shows")
		eq(own.duelsPlace, nil, "no place on a ranking the King keeps private"); eq(own.bonesPlace, nil)
	end)
	With({ arenaOff = true }, function() eq(B.GetSection("games"), nil, "the arena off") end)
end)

test("bridge people: profile is his own: name, guild, rank, role, level, class, race, frame, title, nickname and his honours with their titles, at most 40", function()
	With({ honours = 55 }, function()
		local d = Data("profile")
		eq(d.name, ME); eq(d.guild, "Olympus II"); eq(d.rank, "Zeus"); eq(d.rankIndex, 0); eq(d.role, "guildmaster")
		eq(d.level, 60); eq(d.class, "MAGE"); eq(d.race, "Gnome"); eq(d.frame, "donor-top"); eq(d.title, "Title of donor-top")
		eq(d.nickname, "the Grim Wolf")
		eq(#d.honors, 40, "cut from the end")
		eq(d.honors[1].key, "donor-top"); eq(d.honors[1].frame, true); eq(d.honors[1].title, "Title of donor-top"); eq(d.honors[1].place, 1)
		eq(d.honors[2].frame, false)
		for _, h in ipairs(d.honors) do for k in pairs(h) do assert(({ key = true, title = true, frame = true, place = true })[k], k) end end
		eq(#d.titles, 2); eq(d.titles[2], "Title of honour-2")
		Never(d, "secret/art", "an honour's art path")
	end)
	With({}, function(m)
		m.API.Profile = function() return { member = false } end
		eq(B.GetSection("profile"), nil, "not a member: nothing")
	end)
end)

test("bridge people: a module's error leaves its own section nil and every other section whole; a board's leaves that board out alone", function()
	ns.Roster.Scan()
	local function Boom() error("boom") end
	local roster = ns.Roster
	local cases = {
		-- (The census's guilds and statistics read the same Data.Summary: they go with it, nothing else.)
		realm = { modules = { Data = setmetatable({ Summary = Boom }, { __index = ns.Data }) }, alike = { guilds = true, stats = true } },
		roster = { modules = { Roster = setmetatable({}, { __index = function(_, k)
			if k == "members" then error("boom") end
			return roster[k]
		end }) } },
		church = { churchBoom = true },
		games = { gamesBoom = true },
		profile = { profileBoom = true },
	}
	for name, o in pairs(cases) do
		With(o, function(m)
			if o.churchBoom then m.ChurchCount.PublicView = Boom end
			if o.gamesBoom then m.ArenaHome.TabVisible = Boom end
			if o.profileBoom then m.API.Profile = Boom end
			eq(B.GetSection(name), nil, name .. ": its module failed")
			for other in pairs(o.alike or {}) do eq(B.GetSection(other), nil, other .. ": the same module failed") end
			for _, other in ipairs(GATED) do
				if other ~= name and not (o.alike and o.alike[other]) then
					assert(B.GetSection(other), name .. " failed: " .. other .. " still whole")
				end
			end
		end)
	end
	With({}, function(m)
		m.ArenaLedger.Ranking = Boom
		m.Wanted.Rankings = Boom
		local d = Data("rankings")
		eq(BoardOf(d.boards, "arena", "all"), nil, "the board whose module failed")
		eq(BoardOf(d.boards, "wanted", "month"), nil)
		assert(BoardOf(d.boards, "crafting", "month") and BoardOf(d.boards, "treasury", "all"), "the others stay")
		eq(Data("games").own.rating, nil, "the same failure leaves his duels' rating unknown, nothing else")
	end)
end)

---------------------------------------------------------------------------
-- The size: every section this build registers, at its fullest, as the private sidecar's
-- SavedVariables file would hold them (the game's own layout: tabs, ["key"] = value, -- [n]).
---------------------------------------------------------------------------

local function Saved(v, indent, out)
	indent = indent or ""
	local t = type(v)
	if t == "string" then out[#out + 1] = ("%q"):format(v)
	elseif t ~= "table" then out[#out + 1] = tostring(v)
	else
		out[#out + 1] = "{\n"
		local inner = indent .. "\t"
		local n = #v
		for i = 1, n do
			out[#out + 1] = inner
			Saved(v[i], inner, out)
			out[#out + 1] = (", -- [%d]\n"):format(i)
		end
		local keys = {}
		for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then keys[#keys + 1] = k end end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			out[#out + 1] = inner .. "[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "] = "
			Saved(v[k], inner, out)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	end
	return out
end

test("bridge people: every section together, for a guild of 1000 members, 256 guilds and full boards, stays under 2 MiB and nothing is cut by the registry", function()
	-- A roster at the game's cap, with long names and rank names.
	local members = Rows(1000, function(i)
		return { name = Name("Membername", i) .. "-Argentdawnx", level = i % 60 + 1, class = "WL", rankIndex = i % 10, rank = "Veteran Centurion",
			online = i <= 400, days = i > 400 and 33.5 or 0 }
	end)
	local roster = { guild = "Olympus II", members = members, lastStats = { numTotal = 1000 } }
	setmetatable(roster, { __index = ns.Roster })
	With({ guilds = 256, wanted = 200, honours = 60, modules = { Roster = roster } }, function()
		local file, total, sizes = { sections = {} }, 0, {}
		for _, s in ipairs(B.Sections()) do
			local got = B.GetSection(s.name)
			-- (The census is the sidecar's own checkpoint, below; t_*: the registry's own test's sections.)
			if got and s.name ~= "census" and not s.name:find("^t_") then
				file.sections[s.name] = { version = got.version, data = got.data }
				sizes[s.name] = #table.concat(Saved(got.data, "\t\t\t", {}))
			end
		end
		file.checkpoint = B.GetCensusCheckpoint()
		sizes.checkpoint = #table.concat(Saved(file.checkpoint, "\t", {}))
		local text = "OlympusCompanionDB = " .. table.concat(Saved(file, "", {})) .. "\n"
		total = #text
		local parts = {}
		for name, n in pairs(sizes) do parts[#parts + 1] = ("%s %d"):format(name, n) end
		table.sort(parts)
		print(("       sizes (bytes): %s; the file %d bytes (%.1f KiB)"):format(table.concat(parts, ", "), total, total / 1024))
		assert(total < 2 * 1024 * 1024, "under 2 MiB: " .. total)
		local d = file.sections
		eq(#d.roster.data.members, 1000, "the whole roster inside the value budget")
		eq(#d.realm.data.guilds, 256, "every guild")
		eq(#d.wanted.data.targets, 100)
		eq(#d.games.data.events, 50)
		eq(#d.profile.data.honors, 40)
		eq(#d.church.data.public, 20)
		local boards = d.rankings.data.boards
		eq(#boards, 10, "every board")
		for _, b in ipairs(boards) do assert(b.fields and b.rows, b.board) end
		eq(#BoardOf(boards, "wanted", "all").rows, 50, "the last board whole too")
		eq(#d.rankings.data.slayers.all, 50, "the legacy kinds whole beside the boards")
		eq(#d.rankings.data.crafting, 50)
	end)
end)

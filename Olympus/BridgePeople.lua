local ADDON, ns = ...

-- The Companion's sections for the people tabs (1.2.6; Daniel: "quero as features igual do addon,
-- rankings etc"): the Realm's guilds, our own guild's members, the Church's public rows and this
-- character's own place, the games' public events and his own record, and his own profile. Each
-- reads what the page that shows it reads, through that module's public functions, and builds its
-- rows field by field (Bridge.lua's registry copies them again within its limits). The same
-- audience as the page: our own guild's members for our own guild alone, the Church's numbers of
-- this character alone, the games' rankings only while the King made them public. Never another
-- player's BattleTag, chat text or chat-strike line, a staff or council view, treasury items, the
-- Church's or the Watch's detail meant for fewer people, nor a GUID. Nothing before this account
-- accepted the Olympus Accord, nor for anyone but a member (BridgeKit.Open).
-- Big lists are rows of "~" strings beside their `fields` (BridgeKit.Row): a guild of 1000 members
-- stays inside the registry's value budget (SECTION_LIMITS.values) that way.
if type(OlympusBridge) ~= "table" or type(OlympusBridge.RegisterSection) ~= "function" or type(ns.BridgeKit) ~= "table" then return end

local Kit = ns.BridgeKit
local Open, Try, Text, Row, Same, Whole = Kit.Open, Kit.Try, Kit.Text, Kit.Row, Kit.Same, Kit.Whole

local REALM_GUILDS = 256  -- as the census checkpoint's guilds
local ROSTER_MEMBERS = 1000 -- the game's guild cap
local CHURCH_PUBLIC = 100
local GAME_EVENTS = 50
local HONOURS = 40

local function Now()
	local t = Try("Data", "ServerTime")
	return Whole(t or ns.Now())
end

-- A value a module may not give: its call protected, nil when it fails.
local function Safe(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return a, b end
	return nil
end

---------------------------------------------------------------------------
-- realm: the Realm tab's guilds (Data.Summary, the shared order), as their rows and tooltips show
-- them: members, online while fresh, average level, Captains, inactive members, the Lord and
-- whether he is online now (Views.PresenceNow, as the row), and the King's name (the Realm's line).
-- The census's faction and realm group once, for every guild.
-- The Lord's presence as the row says it: online (lordOnline 1, lordDays 0), offline for lordDays
-- whole days (lordOnline 0), or not known now (lordOnline and lordDays empty): an old report had
-- him online and nobody sees him now, the row's "online <age> ago", lordSeenAt that report's time.
---------------------------------------------------------------------------

-- The Lord's three fields from Views.PresenceNow's online, days and at: nil, nil and the old
-- report's time while he is not known now.
local function LordPresence(on, days, at)
	if on == true then return true, 0, nil end
	if on == nil and type(at) == "number" then return nil, nil, Whole(at) end
	return false, Whole(days), nil
end

OlympusBridge.RegisterSection("realm", 1, function()
	if not Open() then return nil end
	local D = ns.Data
	local s = D.Summary() -- (an error leaves the section nil)
	if type(s) ~= "table" or type(s.guilds) ~= "table" then return nil end
	local V = ns.Views
	local out = { at = Now(), faction = Text(ns.faction, 16), realmGroup = Text(ns.group or ns.realm, 96),
		fields = "members~online~avgLevel~captains~inactive7~inactive30~lordOnline~lordDays~lordSeenAt~fresh~name~lord", guilds = {} }
	for _, e in ipairs(s.guilds) do
		if #out.guilds >= REALM_GUILDS then break end
		local g = type(e) == "table" and e.g
		if type(g) == "table" and type(e.name) == "string" then
			if not out.king and type(g.leader) == "string" and ns.IsKingGuild(e.name) then out.king = Text(g.leader) end
			local on, days, at = g.leaderOnline, g.leaderDays, nil
			if type(V) == "table" and type(V.PresenceNow) == "function" then
				local okP, pOn, pDays, _, pAt = pcall(V.PresenceNow, e, g.leader, g.leaderOnline, g.leaderDays)
				if okP then on, days, at = pOn, pDays, pAt end
			end
			local lordOnline, lordDays, lordSeenAt = LordPresence(on, days, at)
			local tenths = Safe(D.AvgTenths, g)
			local fresh = e.fresh == true
			out.guilds[#out.guilds + 1] = Row(Whole(g.total), fresh and Whole(g.online) or 0, tenths and ("%.1f"):format(tenths / 10) or "",
				type(g.officers) == "table" and #g.officers or 0, Whole(g.inactive7), Whole(g.inactive30), lordOnline, lordDays, lordSeenAt,
				fresh, e.name, g.leader)
		end
	end
	return out
end)

---------------------------------------------------------------------------
-- roster: our own guild's members (Members.lua's page, the Realm's members online): every member
-- of the roster the server gave this client (Roster.members), with level, class, rank, online and
-- the hours since he was last online (the game's word, as the page's "5h ago" / "45 days ago").
-- Our own guild only, an Olympus guild, and only that guild's roster (never one left in memory
-- from a guild before). Online first, then by rank, level and name.
---------------------------------------------------------------------------

OlympusBridge.RegisterSection("roster", 1, function()
	if not Open() then return nil end
	local R = ns.Roster
	local guild = GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" or not ns.IsFederation(guild) or R.guild ~= guild then return nil end
	local all = R.members
	if type(all) ~= "table" then return nil end
	local list = {}
	for _, m in ipairs(all) do
		if type(m) == "table" and type(m.name) == "string" then list[#list + 1] = m end
	end
	table.sort(list, function(a, b)
		if (a.online == true) ~= (b.online == true) then return a.online == true end
		local ra, rb = tonumber(a.rankIndex) or 9, tonumber(b.rankIndex) or 9
		if ra ~= rb then return ra < rb end
		local la, lb = tonumber(a.level) or 0, tonumber(b.level) or 0
		if la ~= lb then return la > lb end
		return a.name < b.name
	end)
	local stats = type(R.lastStats) == "table" and R.lastStats or {}
	local out = { at = Now(), guild = Text(guild, 64), total = math.max(Whole(stats.numTotal), #list), online = 0,
		fields = "level~class~rankIndex~online~hoursOffline~name~rank", members = {} }
	for _, m in ipairs(list) do
		if m.online == true then out.online = out.online + 1 end
		if #out.members < ROSTER_MEMBERS then
			local class = ns.CLASS_FILES and ns.CLASS_FILES[m.class] or m.class
			out.members[#out.members + 1] = Row(Whole(m.level), type(class) == "string" and class or "", Whole(m.rankIndex),
				m.online == true, m.online == true and 0 or Whole((tonumber(m.days) or 0) * 24), Text(m.name), Text(m.rank, 32))
		end
	end
	return out
end)

---------------------------------------------------------------------------
-- church: the Church tab's public page for everyone while its switch is open (ChurchCount.PublicView:
-- the Apostles' and the missionaries' rows, the last 30 days' points and all time's), and, for a
-- Church person alone (the Mine page's own gate, Church.IsPerson), his own place and numbers as
-- his Mine page shows them: never the ranking the Church's own people see, nor his registrations'
-- names (their count only).
---------------------------------------------------------------------------

local ROLE_WORD = { H = "head", A = "apostle", M = "missionary", C = "correspondent" }
local function Tenth(v) return math.floor((tonumber(v) or 0) * 10 + 0.5) / 10 end

-- His numbers in one window (w: this week, m: the last 30 days, a: all time), as his page reads them
-- (ChurchCount.DetailView: his own client's ledger, or the keepers' answer it holds); nil without one.
local function ChurchNumbers(Count, window)
	local detail = Count.DetailView(ns.me, window)
	if type(detail) ~= "table" then return nil end
	local out
	for _, d in ipairs(detail) do
		if type(d) == "table" and d[1] == "s" then
			out = out or { window = window }
			out.ownPoints = Tenth(d[2])
			out.points = Tenth((tonumber(d[2]) or 0) + (tonumber(d[3]) or 0) + (tonumber(d[4]) or 0) + (tonumber(d[5]) or 0))
		elseif type(d) == "table" and d[1] == "j" then
			out = out or { window = window }
			out.recruits, out.pending, out.stays, out.transfers = Whole(d[2]), Whole(d[3]), Whole(d[4]), Whole(d[5])
		elseif type(d) == "table" and d[1] == "t" then
			out = out or { window = window }
			out.taken, out.openRegistrations, out.network = Whole(d[2]), Whole(d[3]), Whole(d[4])
		end
	end
	return out
end

local function ChurchOwn(Church, Count)
	local role = Church.Role(ns.me)
	local out = { role = ROLE_WORD[role or ""] or "member" }
	local S = Church.State()
	local p = Church.Place(ns.me)
	if role == "M" and type(p) == "table" and type(S) == "table" then
		local net = p.net and S.apostle[p.net]
		local parent = p.parent and (S.apostle[p.parent] or S.miss[p.parent])
		out.apostle = net and Text(ns.DisplayName(ns.FullName(net.n))) or nil
		out.parent = parent and Text(ns.DisplayName(ns.FullName(parent.n))) or nil
	end
	local key = type(Church.Key) == "function" and Safe(Church.Key, ns.me) or nil
	local gkey = key and type(S) == "table" and type(S.corrOf) == "table" and S.corrOf[key]
	if gkey and type(S.corr) == "table" and type(S.corr[gkey]) == "table" then out.guild = Text(S.corr[gkey].g, 64) end
	out.windows = {}
	for _, window in ipairs({ "w", "m", "a" }) do
		local n = Safe(ChurchNumbers, Count, window)
		if n then out.windows[#out.windows + 1] = n end
	end
	local loc = Safe(Count.Local)
	if type(loc) == "table" then
		out.invitesWeek, out.invitesAll = Whole(loc.invWeek), Whole(loc.invAll)
		if out.guild then out.guildMembers, out.guildJoins, out.guildLeaves = Whole(loc.members), Whole(loc.joins), Whole(loc.leaves) end
	end
	local mine = Safe(Count.Mine)
	if type(mine) == "table" then
		local n = 0
		for _ in pairs(type(mine.regs) == "table" and mine.regs or {}) do n = n + 1 end
		out.registrations = n
		out.publicRow = mine.pub == true
	end
	return out
end

OlympusBridge.RegisterSection("church", 1, function()
	if not Open() then return nil end
	local Church, Count = ns.Church, ns.ChurchCount
	if type(Church) ~= "table" or Church.missing or type(Count) ~= "table" or Count.missing then return nil end
	local v = Count.PublicView() -- (an error leaves the section nil)
	local out = { open = type(v) == "table", public = {} }
	if type(v) == "table" then
		local most = tonumber(Count.PUBLIC_ROWS) or 10
		for _, it in ipairs({ { "a", "apostles" }, { "m", "missionaries" } }) do
			local rows = type(v[it[1]]) == "table" and v[it[1]] or {}
			for place = 1, most do
				local r = rows[place]
				if type(r) == "table" and type(r.name) == "string" and #out.public < CHURCH_PUBLIC then
					out.public[#out.public + 1] = { list = it[2], place = place, name = Text(ns.DisplayName(ns.FullName(r.name))),
						points = Tenth(r.s30), allTime = Tenth(r.sall) }
				end
			end
		end
	end
	if Church.IsPerson(ns.me) == true then out.own = ChurchOwn(Church, Count) end
	return out
end)

---------------------------------------------------------------------------
-- games: the Games tab and the Arena window, for a member while the arena is on
-- (ArenaHome.TabVisible): the public events they list (Fight Nights, tournaments and public fights,
-- ArenaFights.Events), the recent public duels' results (ArenaLedger.History, the Arena profile's),
-- the Bone Throw tables live to watch (FarkleTable.LiveTables), names as those pages show them;
-- and this character's own record: his duels (his row of the arena's ranking), his Bone Throw
-- games (FarkleTable.MyGames, the live realm's), and his places only while the King made that
-- game's ranking public. The live realm's alone: never a rehearsal's, never the showcase's samples
-- (the modules themselves, not the screens' view models).
---------------------------------------------------------------------------

local function ArenaName(name)
	if type(name) ~= "string" or name == "" then return nil end
	local shown = Try("ArenaHome", "Name", name)
	return Text(type(shown) == "string" and shown or ns.DisplayName(name))
end

local EVENT_KIND = { fight = "duel", card = "night", tourney = "tourney" }

local function GameEvents()
	local out, seen = {}, {}
	local function Add(e)
		if e.id and not seen[e.id] and #out < GAME_EVENTS * 2 then
			seen[e.id] = true
			out[#out + 1] = e
		end
	end
	-- The recent public duels, ended, with their winner; titleFight: a public title fight (the
	-- ledger's flag, ArenaLedger.History's `title`, a boolean there). `title` is always an event's
	-- text, never that flag.
	for _, r in ipairs(Try("ArenaLedger", "History", { limit = 30, mode = "L" }) or {}) do
		if type(r) == "table" and type(r.fid) == "string" and r.public ~= false then
			Add({ kind = "duel", id = Text(r.fid, 32), at = Whole(r.t), a = ArenaName(r.A), b = ArenaName(r.B), winner = ArenaName(r.winner),
				state = "over", titleFight = r.title == true or nil })
		end
	end
	-- The events the tab and the window list: live, upcoming and ended.
	for _, e in ipairs(Try("ArenaFights", "Events", { limit = 40, mode = "L" }) or {}) do
		if type(e) == "table" and type(e.id) == "string" and EVENT_KIND[e.kind] then
			Add({ kind = EVENT_KIND[e.kind], id = Text(e.id, 32), at = Whole(e.at), title = Text(e.title, 60),
				state = e.live and "live" or (e.ended and "over" or "upcoming"), count = Whole(e.count) })
		end
	end
	-- The Bone Throw tables one may watch now.
	for _, t in ipairs(Try("FarkleTable", "LiveTables") or {}) do
		if type(t) == "table" and type(t.id) == "string" and t.mode == "L" then
			Add({ kind = "bones", id = Text(t.id, 32), at = Whole(t.at), a = ArenaName(t.p1), b = ArenaName(t.p2), state = "live",
				official = t.official == true or nil })
		end
	end
	table.sort(out, function(x, y)
		if x.at ~= y.at then return x.at > y.at end
		return x.id < y.id
	end)
	for i = #out, GAME_EVENTS + 1, -1 do out[i] = nil end
	return out
end

local function GamesOwn()
	local out = { duelsWon = 0, duelsLost = 0, bonesWon = 0, bonesLost = 0 }
	local me = Try("ArenaProfile", "MyGk")
	if me then
		for i, r in ipairs(Try("ArenaLedger", "Ranking", "all", "A", { mode = "L" }) or {}) do
			if type(r) == "table" and r.gk == me then
				out.duelsWon, out.duelsLost, out.rating = Whole(r.wins), Whole(r.losses), Whole(r.rating)
				if Try("ArenaHome", "RankingsPublic", "arena") == true then out.duelsPlace = Whole(r.rank) > 0 and Whole(r.rank) or i end
				break
			end
		end
	end
	for _, h in ipairs(Try("FarkleTable", "MyGames") or {}) do
		if type(h) == "table" and not h.reh then
			if h.res == "W" then out.bonesWon = out.bonesWon + 1 elseif h.res == "L" then out.bonesLost = out.bonesLost + 1 end
		end
	end
	if Try("ArenaHome", "RankingsPublic", "bones") == true then
		for i, r in ipairs(Try("FarkleTable", "Best", "L") or {}) do
			if type(r) == "table" and Same(r.name, ns.me) then out.bonesPlace = Whole(r.place) > 0 and Whole(r.place) or i break end
		end
	end
	return out
end

OlympusBridge.RegisterSection("games", 1, function()
	if not Open() then return nil end
	local H = ns.ArenaHome
	if type(H) ~= "table" or H.missing or H.TabVisible() ~= true then return nil end -- (an error leaves the section nil)
	return { at = Now(), events = GameEvents(), own = GamesOwn() }
end)

---------------------------------------------------------------------------
-- profile: this character's own profile ("My profile" and his Arena profile's card): the API's own
-- model (API.Profile: his name, guild, rank, role, the frame and title others see), his level,
-- class and race as the card shows them, his nickname, and the honours he holds with their titles
-- (HonorsNet.Holdings, the list "My profile" picks from). His own alone.
---------------------------------------------------------------------------

OlympusBridge.RegisterSection("profile", 1, function()
	if not Open() then return nil end
	local p = ns.API.Profile() -- (an error leaves the section nil)
	if type(p) ~= "table" or p.member ~= true then return nil end
	local out = { name = Text(p.name, 72), guild = Text(p.guild, 64), rank = Text(p.rank, 64), rankIndex = Whole(p.rankIndex),
		role = Text(p.role, 16), frame = Text(p.frame, 48), title = p.title and Text(p.title, 64) or nil, honors = {}, titles = {} }
	if type(UnitLevel) == "function" then out.level = Whole(Safe(UnitLevel, "player")) end
	if type(UnitClass) == "function" then
		local _, file = Safe(UnitClass, "player")
		if type(file) == "string" then out.class = Text(file, 16) end
	end
	if type(UnitRace) == "function" then
		local _, file = Safe(UnitRace, "player")
		if type(file) == "string" then out.race = Text(file, 16) end
	end
	local P = ns.ArenaProfile
	if type(P) == "table" and not P.missing then
		local mine = Safe(P.Mine)
		local nick = type(mine) == "table" and Safe(P.NickText, mine.nick) or nil
		if type(nick) == "string" then out.nickname = Text(nick, 64) end
	end
	local held = Try("HonorsNet", "Holdings", ns.me, Try("ArenaProfile", "MyGk"))
	for _, h in ipairs(type(held) == "table" and held or {}) do
		if type(h) == "table" and type(h.key) == "string" and #out.honors < HONOURS then
			local words = Try("HonorsNet", "TitleText", h.key)
			out.honors[#out.honors + 1] = { key = Text(h.key, 48), title = type(words) == "string" and Text(words, 64) or nil,
				frame = h.frame ~= nil, place = tonumber(h.place) and Whole(h.place) or nil }
			if h.title and type(words) == "string" and #out.titles < HONOURS then out.titles[#out.titles + 1] = Text(words, 64) end
		end
	end
	return out
end)

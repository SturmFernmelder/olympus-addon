local ADDON, ns = ...

-- The Companion's sections beyond the census (Bridge.lua's registry). Each reads only a module's
-- public function, what every member already sees on Olympus's own pages, and builds its rows
-- field by field: a field a module adds later never reaches the Companion by itself.
-- Never another player's BattleTag, chat text or chat-strike line, a council/High Council-only view, treasury
-- items, the Wanted page's victims or
-- sightings, or Church/Watch detail meant for fewer people.
if type(OlympusBridge) ~= "table" or type(OlympusBridge.RegisterSection) ~= "function" then return end

local ROWS = 50

local function Call(module, fn, ...)
	local m = ns[module]
	if type(m) ~= "table" or type(m[fn]) ~= "function" then return nil end
	local ok, a, b = pcall(m[fn], ...)
	if ok then return a, b end
	return nil
end

local function Whole(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 then return 0 end
	return math.floor(v)
end

-- The Companion keeps an account-level answer to its own disclosure. It is deliberately
-- separate from the ordinary chat switch: reading an Olympus chat in game is not consent to keep
-- that chat in the private Bridge file or send it to the relay. A changed disclosure version asks
-- again; nil and No both fail closed.
local COMPANION_ACCORD_VERSION = 1
local function CompanionAnswer()
	local a = type(ns.db) == "table" and ns.db.companionAccord or nil
	if type(a) ~= "table" or a.version ~= COMPANION_ACCORD_VERSION or type(a.accepted) ~= "boolean" then return nil end
	return a.accepted
end
function ns.CompanionAccordAccepted() return CompanionAnswer() == true end

local C = ns.Consent
if type(C) == "table" and type(C.Register) == "function" then
	C.Register({
		key = "companionAccord", label = "CONSENT_COMPANION", text = "CONSENT_COMPANION_TEXT",
		version = COMPANION_ACCORD_VERSION, explicit = true, adopt = false,
		shown = function()
			return type(OlympusBridge) == "table" and OlympusBridge.COMPANION_ATTACHED == true
		end,
		get = CompanionAnswer,
		set = function(on)
			if type(ns.db) ~= "table" then return end
			ns.db.companionAccord = { version = COMPANION_ACCORD_VERSION, accepted = on == true,
				at = Whole(type(ns.Now) == "function" and ns.Now() or 0) }
			ns.Fire("COMPANION_ACCORD_CHANGED", on == true)
		end,
	})
end

-- The helpers the Companion's other section files share (BridgePeople.lua, loaded after this one):
-- ns.BridgeKit, Olympus's own table, never a global.
-- Open(): a member who accepted the Olympus Accord (ns.AccordAccepted, ns.IsMember); the census's
--   guilds and statistics, the rankings, the Wanted list and every section of BridgePeople.lua give
--   nothing before it ("self" asks the Accord itself).
-- Try(module, fn, ...): Call, but nil for a stand-in of a file this build has not loaded yet (Core's
--   StandIn, `missing`).
-- Text(v, max): a plain one-line text for a row: no colour or link codes, control characters or
--   "~" (the rows' separator), cut at max bytes (48 by default), never half a letter; "" for none.
-- Row(...): one row as "a~b~...", numbers whole (a "%.1f" string stays as given), within the
--   registry's string limit (SECTION_LIMITS.string): the last field is cut when it is longer.
--   Rows are strings where a list would pass the registry's value budget (SECTION_LIMITS.values)
--   as tables: each such list sits beside its `fields`, the names of the row's fields in order.
-- Same(a, b): one character, whatever realm form or letter case each name has.
local Kit = { Call = Call, Whole = Whole }
ns.BridgeKit = Kit
function Kit.Open()
	return type(ns.AccordAccepted) == "function" and ns.AccordAccepted() == true
		and type(ns.IsMember) == "function" and ns.IsMember() == true
end
function Kit.Try(module, fn, ...)
	local m = ns[module]
	if type(m) ~= "table" or m.missing then return nil end
	return Call(module, fn, ...)
end
function Kit.Text(v, max)
	if type(v) ~= "string" then return "" end
	local s = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1")
		:gsub("[|~%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, max or 48)
end
function Kit.Row(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		if type(v) == "number" then parts[i] = tostring(Whole(v))
		elseif type(v) == "boolean" then parts[i] = v and "1" or "0"
		else parts[i] = Kit.Text(v, 120) end
	end
	return ns.Cut(table.concat(parts, "~"), OlympusBridge.SECTION_LIMITS.string)
end
function Kit.Same(a, b)
	return type(a) == "string" and type(b) == "string" and a ~= "" and ns.Fold(ns.FullName(a)) == ns.Fold(ns.FullName(b))
end
local Open, Try, Text, Row, Same = Kit.Open, Kit.Try, Kit.Text, Kit.Row, Kit.Same

---------------------------------------------------------------------------
-- The ranking boards (the Companion's Rankings tab): each board as the page that lists it, its
-- rows as "~" strings in `fields` order, cut from the end, and this character's own place where
-- the board has him. Only boards every member's page shows: the games' while the King made them
-- public (ArenaHome.RankingsPublic, as the Games tab and the API), the treasury's donors while the
-- King shows the Treasury's ranking (Treasury.PublicShows("ranking")), the Church's public rows
-- while its switch is open (ChurchCount.PublicView). Never a staff view.
---------------------------------------------------------------------------

local BOARD_ROWS = 50

-- A name as the Arena's pages show it (ArenaHome.Name: masked on the King's screen while his
-- councillors' names are, Arena.Mask), else as the other pages do.
local function ArenaName(name)
	local shown = Try("ArenaHome", "Name", name)
	if type(shown) == "string" then return shown end
	return type(name) == "string" and ns.DisplayName(name) or ""
end

local function Board(board, period, fields, list)
	return { board = board, period = period, fields = fields, rows = {}, list = list }
end

-- The arena's overall ranking (the Games tab's, every page of the Arena window's): all time.
local function ArenaBoard()
	if Try("ArenaHome", "RankingsPublic", "arena") ~= true then return nil end
	local rows = Try("ArenaLedger", "Ranking", "all", "A", { mode = "L" })
	if type(rows) ~= "table" then return nil end
	local b, me = Board("arena", "all", "place~rating~wins~losses~name"), Try("ArenaProfile", "MyGk")
	for i, r in ipairs(rows) do
		if type(r) == "table" then
			local place = Whole(r.rank) > 0 and Whole(r.rank) or i
			if #b.rows < BOARD_ROWS then b.rows[#b.rows + 1] = Row(place, r.rating, r.wins, r.losses, ArenaName(r.name or r.gk)) end
			if me and r.gk == me then b.own = { place = place, value = Whole(r.rating) } end
		end
	end
	return b
end

-- Bones' best players this month (FarkleTable.Best), the ten the Games tab lists.
local function BonesBoard()
	if Try("ArenaHome", "RankingsPublic", "bones") ~= true then return nil end
	local rows = Try("FarkleTable", "Best", "L")
	if type(rows) ~= "table" then return nil end
	local b = Board("bones", "month", "place~won~games~name")
	for i, r in ipairs(rows) do
		if type(r) == "table" then
			local place = Whole(r.place) > 0 and Whole(r.place) or i
			if #b.rows < 10 then b.rows[#b.rows + 1] = Row(place, r.won, r.games, ArenaName(r.name)) end
			if Same(r.name, ns.me) then b.own = { place = place, value = Whole(r.won) } end
		end
	end
	return b
end

-- The Church's public rankings (its Public page): the Apostles' and the missionaries', the last
-- 30 days' points (tenths) and all time's.
local function Tenths(v) return math.floor((tonumber(v) or 0) * 10 + 0.5) end
local function ChurchBoards(out)
	local v = Try("ChurchCount", "PublicView")
	if type(v) ~= "table" then return end
	local most = tonumber(ns.ChurchCount.PUBLIC_ROWS) or 10
	for _, it in ipairs({ { "a", "apostles" }, { "m", "missionaries" } }) do
		local b = Board("church", "month", "place~points10~allTime10~name", it[2])
		local rows = type(v[it[1]]) == "table" and v[it[1]] or {}
		for place = 1, most do
			local r = rows[place]
			if type(r) == "table" then
				b.rows[#b.rows + 1] = Row(place, Tenths(r.s30), Tenths(r.sall), ns.DisplayName(ns.FullName(r.name)))
				if Same(r.name, ns.me) then b.own = { place = place, value = Tenths(r.s30) } end
			end
		end
		out[#out + 1] = b
	end
end

-- The month's crafting ranking (the Realm's crafting page, CraftRanking.Current).
local function CraftingBoard()
	local rows = Try("CraftRanking", "Current")
	if type(rows) ~= "table" then return nil end
	local b = Board("crafting", "month", "place~points~deliveries~customers~name")
	for i, r in ipairs(rows) do
		if type(r) == "table" then
			local place = Whole(r.place) > 0 and Whole(r.place) or i
			if #b.rows < BOARD_ROWS then b.rows[#b.rows + 1] = Row(place, r.points, r.deliveries, r.customers, ns.DisplayName(r.name)) end
			if Same(r.name, ns.me) then b.own = { place = place, value = Whole(r.points) } end
		end
	end
	return b
end

-- The Treasury's ranking of donors (its tab's, as it may go out: Treasury.Report(true, true), the
-- copy the army reads), copper given, while the King shows the ranking.
local function TreasuryBoard()
	if Try("Treasury", "PublicShows", "ranking") ~= true then return nil end
	local r = Try("Treasury", "Report", true, true)
	if type(r) ~= "table" or type(r.rank) ~= "table" then return nil end
	local person = Try("Alts", "Person", ns.me) or ns.ShortName(ns.me)
	local b = Board("treasury", "all", "place~copper~name")
	for i, g in ipairs(r.rank) do
		if type(g) == "table" then
			if #b.rows < BOARD_ROWS then b.rows[#b.rows + 1] = Row(i, g.money, g.name) end
			if type(g.name) == "string" and type(person) == "string" and ns.Fold(g.name) == ns.Fold(person) then
				b.own = { place = i, value = Whole(g.money) }
			end
		end
	end
	return b
end

-- The donors' honours (the API's, its own gate: while the King shows the Treasury's ranking): the
-- all-time three, and the month's where this build wears their frame. Names alone.
local function DonorBoards(out, donors)
	if type(donors) ~= "table" then return end
	for _, period in ipairs({ "all", "month" }) do
		local names = donors[period]
		if type(names) == "table" then
			local b = Board("donors", period, "place~name")
			for i, name in ipairs(names) do
				if type(name) == "string" then
					b.rows[#b.rows + 1] = Row(i, name)
					if Same(name, ns.me) then b.own = { place = i } end
				end
			end
			out[#out + 1] = b
		end
	end
end

-- The Wanted tab's Slayers boards (Wanted.Rankings): this month's and all time's.
local function WantedBoards(out)
	local rank = Try("Wanted", "Rankings")
	if type(rank) ~= "table" then return end
	local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
	for _, period in ipairs({ "month", "all" }) do
		local b = Board("wanted", period, "place~points~claims~name")
		for i, r in ipairs(type(rank[period]) == "table" and rank[period] or {}) do
			if type(r) == "table" then
				local place = Whole(r.place) > 0 and Whole(r.place) or i
				if #b.rows < BOARD_ROWS then b.rows[#b.rows + 1] = Row(place, r.points, r.claims, ns.DisplayName(r.name)) end
				if (type(guid) == "string" and r.guid == guid) or Same(r.name, ns.me) then b.own = { place = place, value = Whole(r.points) } end
			end
		end
		out[#out + 1] = b
	end
end

-- Every board, each from its own module: one that fails or has nothing is left out alone.
local function Boards(donors)
	local out = {}
	for _, make in ipairs({ ArenaBoard, BonesBoard }) do
		local ok, b = pcall(make)
		if ok and b then out[#out + 1] = b end
	end
	pcall(ChurchBoards, out)
	for _, make in ipairs({ CraftingBoard, TreasuryBoard }) do
		local ok, b = pcall(make)
		if ok and b then out[#out + 1] = b end
	end
	pcall(DonorBoards, out, donors)
	pcall(WantedBoards, out)
	return out
end

-- Public rankings: the API's (Slayers boards, donors' top three only while the King shows the
-- Treasury's ranking, the Church's public top three, the games the King made public), the month's
-- crafting ranking as the Realm's crafting page lists it, and the Treasury's spending only while
-- the King shows the balance (numbers alone). 1.2.6 (the Companion's Rankings tab): `boards`, every
-- board above with its rows and this character's own place (Boards); nothing before the Accord.
OlympusBridge.RegisterSection("rankings", 1, function()
	if not Open() then return nil end
	local out = {}
	local API = ns.API
	if type(API) == "table" and type(API.Rankings) == "function" then
		local ok, rankings = pcall(API.Rankings)
		if ok and type(rankings) == "table" then
			out.slayers, out.donors, out.church, out.games = rankings.slayers, rankings.donors, rankings.church, rankings.games
		end
	end
	local crafting = {}
	for i, row in ipairs(Call("CraftRanking", "Current") or {}) do
		if i > ROWS then break end
		if type(row) == "table" then
			crafting[#crafting + 1] = { place = Whole(row.place) > 0 and Whole(row.place) or i, name = row.name,
				points = Whole(row.points), deliveries = Whole(row.deliveries), customers = Whole(row.customers) }
		end
	end
	out.crafting = crafting
	if Call("Treasury", "PublicShows", "balance") == true then
		local spent, entries = Call("Treasury", "PublicSpending")
		if spent then out.treasury = { spentCopper = Whole(spent), entries = Whole(entries) } end
	end
	out.boards = Boards(out.donors)
	return out
end)

-- The census's guilds as the Census tab lists them: members (characters), online while fresh,
-- average level, plus the people/characters/linked-alts totals. Nothing before the Accord, nor for
-- a non-member: the window shows him the Accord's or the Join page alone, no census (UI.Locked).
OlympusBridge.RegisterSection("guilds", 1, function()
	if not Open() then return nil end
	local D = ns.Data
	if type(D) ~= "table" or type(D.Summary) ~= "function" then return nil end
	local ok, s = pcall(D.Summary)
	if not ok or type(s) ~= "table" then return nil end
	local rows = {}
	for _, e in ipairs(type(s.guilds) == "table" and s.guilds or {}) do
		local g = type(e) == "table" and e.g
		if type(g) == "table" and type(e.name) == "string" and e.counted == true then
			local tenths = type(D.AvgTenths) == "function" and D.AvgTenths(g) or nil
			rows[#rows + 1] = { name = e.name, members = Whole(g.total), online = e.fresh == true and Whole(g.online) or 0,
				fresh = e.fresh == true, avgLevel = tenths and tenths / 10 or nil }
		end
	end
	table.sort(rows, function(a, b)
		if a.members ~= b.members then return a.members > b.members end
		return a.name < b.name
	end)
	while #rows > 256 do rows[#rows] = nil end
	return { people = Whole(s.total), characters = Whole(s.characters or s.total), alts = Whole(s.alts), guilds = rows }
end)

-- The Wanted tab's list (the API's rows: place, name, bounty, kills, cycle), its first 100. The
-- GUID stays: each target's own page shows it (L.WANTED_GUID), and it is who he is on the list.
-- Nothing before the Accord (1.2.6).
local WANTED_ROWS = 100
OlympusBridge.RegisterSection("wanted", 1, function()
	if not Open() then return nil end
	local API = ns.API
	if type(API) ~= "table" or type(API.Wanted) ~= "function" then return nil end
	local ok, rows = pcall(API.Wanted)
	if not ok or type(rows) ~= "table" then return nil end
	local targets = {}
	for i, r in ipairs(rows) do
		if #targets >= WANTED_ROWS then break end
		if type(r) == "table" and type(r.name) == "string" then
			targets[#targets + 1] = { place = Whole(r.place) > 0 and Whole(r.place) or i, name = r.name, guid = r.guid,
				bounty = Whole(r.bounty), kills = Whole(r.kills), cycle = Whole(r.cycle) }
		end
	end
	return { targets = targets }
end)

-- The roles this character holds, as the Companion's tabs read them: officer (his guild rank may
-- act as an officer, Roster.IsOfficer), guildMaster (rank 0), council (the signed High Council),
-- crown (the pinned King), author (the addon's author). His own, never another player's; absent
-- roles are left out, so a plain member has an empty list.
local function Yes(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	return ok and v == true
end
-- This character's own guild, by the name the census uses (GetGuildInfo, as the census reads it),
-- or nil outside a guild: the Companion's relay hands a guild's own musters only to its members.
local function SelfGuild()
	if not Yes(IsInGuild) or type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	if not ok or type(guild) ~= "string" or guild == "" then return nil end
	return guild
end
local function SelfBattleTag()
	local A = ns.Accord
	if type(A) ~= "table" or type(A.ReadTag) ~= "function" then return nil end
	local ok, tag = pcall(A.ReadTag)
	return ok and type(tag) == "string" and tag ~= "" and tag or nil
end
local function SelfRoles(me)
	local out, R, W = {}, ns.Roster, ns.Workshop
	if type(R) == "table" then
		if Yes(R.IsOfficer) then out[#out + 1] = "officer" end
		local ok, rank = pcall(type(R.MyRank) == "function" and R.MyRank or function() return nil end)
		if ok and rank == 0 and Yes(IsInGuild) then out[#out + 1] = "guildMaster" end
	end
	if Yes(ns.IsHighCouncillor, me) then out[#out + 1] = "council" end
	if Yes(ns.IsKingCharacter, me) then out[#out + 1] = "crown" end
	if type(W) == "table" and Yes(W.IsAuthorName, me) then out[#out + 1] = "author" end
	return out
end

local function RealmGroup()
	local realm = ns.realm
	if type(realm) ~= "string" or realm == "" then
		local ok, current = pcall(type(ns.CurrentRealm) == "function" and ns.CurrentRealm or function() return nil end)
		if ok then realm = current end
	end
	if type(realm) ~= "string" or realm == "" or type(ns.GroupOf) ~= "function" then return nil end
	local ok, group = pcall(ns.GroupOf, realm)
	return ok and type(group) == "string" and group ~= "" and group or nil
end

-- Membership names nobody and is therefore safe to export before the Companion disclosure is
-- accepted. `olympus` comes only from this character's native guild membership plus Olympus's
-- fixed/signed guild rule; a census row is never authority. `accord` controls every named export.
OlympusBridge.RegisterSection("membership", 1, function()
	return { olympus = Yes(ns.IsMember), accord = ns.CompanionAccordAccepted(), realmGroup = RealmGroup() }
end)

-- The character on this computer, after explicit consent. The name and guild are direct game
-- facts; roles use the same current native/signed checks as the addon. The UI supplies its actual
-- (not View-as preview) tab keys when available. The player's own BattleTag comes only from the
-- game's Accord.ReadTag after both explicit accords; it is display/linking data, never membership
-- authority. No census-inferred role or remote rank crosses this boundary. The unnamed closed value is still exported when access disappears so a
-- Companion can overwrite a previously relayed identity instead of leaving it stale.
OlympusBridge.RegisterSection("self", 1, function()
	local closed = { roles = {}, olympus = false, tabs = {} }
	if not ns.CompanionAccordAccepted() or not Yes(ns.IsMember) then return closed end
	local me, guild, battleTag = ns.me, SelfGuild(), SelfBattleTag()
	if type(me) ~= "string" or not me:find("^[^%-]+%-.+$") or not guild or not battleTag then return closed end
	local tabs, UI = nil, ns.UI
	if type(UI) == "table" and not UI.missing and type(UI.CompanionTabs) == "function" then
		local ok, value = pcall(UI.CompanionTabs)
		if ok and type(value) == "table" then tabs = value end
	end
	return { character = me, guild = guild, battleTag = battleTag, accord = Whole(ns.ACCORD_VERSION),
		at = Whole(type(ns.Now) == "function" and ns.Now() or 0), roles = SelfRoles(me), olympus = true, tabs = tabs }
end)

-- The census statistics (docs/CENSUS-STATS.md): the census page's own figures and series
-- (Data.Summary, and CensusStats.lua's history where this build has it), so the Companion shows what
-- the game shows, and beside them the sanitized census (CensusClean.lua): banned and departed
-- guilds, how sure each part is, sizes held back; on a moderation team client, how many validated
-- BattleTags it holds (numbers only). Counts and guild names only; rows as
-- "a~b~...~name" strings, which keep every guild inside the section's value budget. Registered
-- addon users and Battle.net accounts are not counted yet: they are left out.
local STATS_GUILDS = 256

local function Series(fn, now)
	local out = {}
	for _, e in ipairs(Call("CensusStats", fn, now) or {}) do
		if type(e) == "table" and tonumber(e.t) and tonumber(e.c) then
			out[#out + 1] = ("%d~%d~%d~%d"):format(Whole(e.t), Whole(e.c), Whole(e.p), Whole(e.o))
		end
	end
	return out
end

-- (Nothing before the Accord, nor for a non-member, as the census page itself: UI.Locked.)
OlympusBridge.RegisterSection("stats", 1, function()
	if not Open() then return nil end
	local D, C = ns.Data, ns.CensusClean
	if type(D) ~= "table" or type(D.Summary) ~= "function" or type(C) ~= "table" or type(C.Compute) ~= "function" then return nil end
	local now = ns.Now()
	local ok, s = pcall(D.Summary)
	if not ok or type(s) ~= "table" then return nil end
	local okClean, c = pcall(C.Compute, s, now)
	if not okClean or type(c) ~= "table" then return nil end
	local characters, people = Whole(s.characters or s.total), Whole(s.total)
	local counted = 0
	for _, e in ipairs(s.guilds or {}) do if type(e) == "table" and e.counted then counted = counted + 1 end end
	local out = {
		at = Whole(now), characters = characters, people = people, linkedAlts = Whole(s.alts), online = Whole(s.online),
		freshGuilds = Whole(s.fresh), countedGuilds = counted, addonOnline = c.addonOnline,
		charactersWithBanned = characters + c.banned.characters,
		sanitizedPeople = math.max(0, people - c.excess), confirmedPeople = c.confirmedPeople,
		confidence = c.confidence,
		banned = { guilds = c.banned.guilds, characters = c.banned.characters, list = {} },
		departed = { guilds = c.departed.guilds, characters = c.departed.characters, list = {} },
		outliers = { guilds = c.outliers.guilds, list = {} },
		days = Series("DaySeries", now), hours = Series("HourSeries", now), guilds = {},
	}
	local avg = Call("CensusStats", "AverageLevel", s)
	if type(avg) == "string" then out.avgLevel = avg end
	-- Validated people (the Olympus Accord's BattleTags): only on a moderation team client, the only
	-- one that holds any (Accord.lua's team store), and as two numbers, never a tag or a name. Every
	-- other client sends none, and its Companion says "not counted yet".
	if Call("Accord", "TeamShown") == true then
		local groups = Call("Accord", "Groups")
		out.validated = { battleTags = type(groups) == "table" and #groups or 0, characters = Whole(Call("Accord", "Count")) }
	end
	for _, b in ipairs(c.banned.list) do out.banned.list[#out.banned.list + 1] = ("%d~%s"):format(b.members, b.name) end
	for _, d in ipairs(c.departed.list) do out.departed.list[#out.departed.list + 1] = ("%d~%d~%s"):format(d.members, d.t, d.name) end
	for _, o in ipairs(c.outliers.list) do out.outliers.list[#out.outliers.list + 1] = ("%d~%d~%s"):format(o.reported, o.kept, o.name) end
	for _, g in ipairs(c.guilds) do
		if #out.guilds >= STATS_GUILDS then break end
		out.guilds[#out.guilds + 1] = ("%d~%d~%d~%d~%s~%s"):format(g.members, g.online, g.users, g.avg10 or 0, g.status, g.name)
	end
	for _, e in ipairs(c.seen) do
		if #out.guilds >= STATS_GUILDS then break end
		out.guilds[#out.guilds + 1] = ("0~%d~0~0~seen~%s"):format(e.online, e.name)
	end
	return out
end)

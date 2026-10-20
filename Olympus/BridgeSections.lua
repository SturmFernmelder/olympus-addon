local ADDON, ns = ...

-- The Companion's sections beyond the census (Bridge.lua's registry). Each reads only a module's
-- public function, what every member already sees on Olympus's own pages, and builds its rows
-- field by field: a field a module adds later never reaches the Companion by itself.
-- Never another player's BattleTag (only "self", below, carries the player's own), chat text or
-- chat-strike line, a council/High Council-only view, treasury items, the Wanted page's victims or
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

-- Public rankings: the API's (Slayers boards, donors' top three only while the King shows the
-- Treasury's ranking, the Church's public top three, the games the King made public), the month's
-- crafting ranking as the Realm's crafting page lists it, and the Treasury's spending only while
-- the King shows the balance (numbers alone).
OlympusBridge.RegisterSection("rankings", 1, function()
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
	return out
end)

-- The census's guilds as the Census tab lists them: members (characters), online while fresh,
-- average level, plus the people/characters/linked-alts totals.
OlympusBridge.RegisterSection("guilds", 1, function()
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

-- The Wanted tab's list (the API's rows: place, name, bounty, kills, cycle).
OlympusBridge.RegisterSection("wanted", 1, function()
	local API = ns.API
	if type(API) ~= "table" or type(API.Wanted) ~= "function" then return nil end
	local ok, rows = pcall(API.Wanted)
	if not ok or type(rows) ~= "table" then return nil end
	local targets = {}
	for i, r in ipairs(rows) do
		if type(r) == "table" and type(r.name) == "string" then
			targets[#targets + 1] = { place = Whole(r.place) > 0 and Whole(r.place) or i, name = r.name, guid = r.guid,
				bounty = Whole(r.bounty), kills = Whole(r.kills), cycle = Whole(r.cycle) }
		end
	end
	return { targets = targets }
end)

-- The player himself (Daniel, 2026-10-19: his BattleTag to the Companion's online census, so the
-- staff know who is who; the Companion shows it to staff alone, never publicly): this character's
-- Name-Realm and his own BattleTag, read from his own game as the Accord reads it (Accord.ReadTag),
-- the Accord's version and the server's time now. Nothing until this account accepted the Olympus
-- Accord, whose letter says so (ACCORD_T5_3), and nothing while the tag can't be read. Never the
-- tags a moderation team client keeps of other players (ns.rdb.battletags). A file of the
-- player's own computer, not a screen: the King's account exports it too, and it is never printed
-- or logged.
-- The roles this character holds, as the Companion's tabs read them: officer (his guild rank may
-- act as an officer, Roster.IsOfficer), guildMaster (rank 0), council (the signed High Council),
-- crown (the pinned King), author (the addon's author). His own, never another player's; absent
-- roles are left out, so a plain member has an empty list.
local function Yes(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	return ok and v == true
end
local function SelfRoles(me)
	local out, R, W = {}, ns.Roster, ns.Workshop
	if type(R) == "table" then
		if Yes(R.IsOfficer) then out[#out + 1] = "officer" end
		local ok, rank = pcall(type(R.MyRank) == "function" and R.MyRank or function() return nil end)
		if ok and rank == 0 and type(IsInGuild) == "function" and IsInGuild() then out[#out + 1] = "guildMaster" end
	end
	if Yes(ns.IsHighCouncillor, me) then out[#out + 1] = "council" end
	if Yes(ns.IsKingCharacter, me) then out[#out + 1] = "crown" end
	if type(W) == "table" and Yes(W.IsAuthorName, me) then out[#out + 1] = "author" end
	return out
end

OlympusBridge.RegisterSection("self", 1, function()
	if type(ns.AccordAccepted) ~= "function" or ns.AccordAccepted() ~= true then return nil end
	local A = ns.Accord
	if type(A) ~= "table" or A.missing or type(A.ReadTag) ~= "function" then return nil end
	local tag = A.ReadTag()
	local me = ns.me
	if type(tag) ~= "string" or type(me) ~= "string" or not me:find("^[^%-]+%-.+$") then return nil end
	local at = Call("Data", "ServerTime")
	return { character = me, battleTag = tag, accord = ns.ACCORD_VERSION, at = Whole(at or (ns.Now and ns.Now())),
		roles = SelfRoles(me) }
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

OlympusBridge.RegisterSection("stats", 1, function()
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

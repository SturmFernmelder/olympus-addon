local ADDON, ns = ...

-- The Companion's sections beyond the census (Bridge.lua's registry). Each reads only a module's
-- public function, what every member already sees on Olympus's own pages, and builds its rows
-- field by field: a field a module adds later never reaches the Companion by itself.
-- Never a BattleTag, chat text or chat-strike line, a council/High Council-only view, treasury
-- items, the Wanted page's victims or sightings, or Church/Watch detail meant for fewer people.
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

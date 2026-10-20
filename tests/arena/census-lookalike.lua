-- 1.2.1, the Census's search (Olympus/Views.lua's CensusLines): a guild's name may mix letters
-- that look alike ("OLYMPUS XIlI", a small L among capital i's; a one or a zero for I or O), and
-- the player types what he sees. The Census's search reads l, I and 1 as one letter and 0 and O
-- as another, in what is typed and in the guilds, Lords, players and zones it reads; any other
-- letter as ever. CR-08 (the author's ask): the Realm's search (RealmLines) reads the same
-- guilds, Lords, Captains and members seen the same way. On the harness's namespace, its census
-- swapped for a few invented guilds.
local H = ...
local test, eq = H.test, H.eq
local ns = H.ns

local function check(cond, msg, ...) if not cond then error((msg or "check failed"):format(...), 2) end end
local function Plain(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")) end
-- The guild rows of a list, in order.
local function Guilds(lines)
	local out = {}
	for _, l in ipairs(lines) do if l.cols then out[#out + 1] = (Plain(l.cols[1]):gsub("^%s+", "")) end end
	return table.concat(out, ",")
end
-- The rows that open a person, in order.
local function People(lines)
	local out = {}
	for _, l in ipairs(lines) do if l.player then out[#out + 1] = l.player end end
	return table.concat(out, ",")
end

-- The census as these guilds, nothing typed before nor after, the UI and /who quiet.
local function WithCensus(fn)
	local V, rdb = ns.Views, ns.rdb
	local saved = { guilds = rdb.guilds, seen = rdb.seen }
	local now = os.time()
	rdb.guilds = {
		["OLYMPUS XIlI"] = { total = 120, online = 20, zones = {}, t = now, leader = "Marrek Dunholt", leaderOnline = true, officers = {} },
		["Olympus II"] = { total = 300, online = 40, zones = {}, t = now, leader = "Brannoc Velt", leaderOnline = false, leaderDays = 2,
			officers = { { name = "Ysolde Imrie", online = true, days = 0, class = "PA", level = 22 } }, top = {} },
		["Olympus H0use"] = { total = 40, online = 4, zones = {}, t = now, leader = "Cadoc Arlen", leaderOnline = true, officers = {} },
		["Olympus Amber Hollow"] = { total = 60, online = 6, zones = {}, t = now, leader = "Tamsin Rook", leaderOnline = true, officers = {} },
	}
	rdb.seen = { ["Olympus 1ron"] = { online = 3, t = now } }
	local ui = { Refresh = function() end, ShowPerson = function() end, StatusLine = function() return "status" end }
	local ok, err = pcall(H.WithStub, "UI", ui, function()
		V.ClearFilters()
		fn(V)
	end)
	V.ClearFilters()
	rdb.guilds, rdb.seen = saved.guilds, saved.seen
	if not ok then error(err, 0) end
end

local function Find(V, text)
	V.SetFilter("census", text)
	return V.Build("census")
end

print("1.2.1: the Census's search reads look-alike letters as one")

test("1.2.1 Census search: l, I and 1 read alike, 0 and O too, so XIII finds OLYMPUS XIlI; other letters as ever", function()
	WithCensus(function(V)
		-- Typed as it looks: capital i's find the small L among them, any case.
		eq(Guilds(Find(V, "XIII")), "OLYMPUS XIlI")
		eq(Guilds(Find(V, "xiii")), "OLYMPUS XIlI")
		eq(Guilds(Find(V, "XlII")), "OLYMPUS XIlI", "a small L typed finds capital i's")
		eq(Guilds(Find(V, "X1II")), "OLYMPUS XIlI", "a one typed too")
		eq(Guilds(Find(V, "olympus xili")), "OLYMPUS XIlI", "as written")
		-- A zero for an O, either way round, and a one for an I in a guild only seen.
		eq(Guilds(Find(V, "house")), "Olympus H0use")
		eq(Guilds(Find(V, "h0use")), "Olympus H0use")
		eq(Guilds(Find(V, "iron")), "Olympus 1ron")
		-- Lords and Captains read the same way.
		eq(Guilds(Find(V, "marrek dunhoit")), "OLYMPUS XIlI", "a Lord, an l typed as I")
		local lines = Find(V, "ysoide")
		eq(Guilds(lines), "Olympus II"); eq(People(lines), "Ysolde Imrie", "a Captain found under his guild")
		-- Every other letter as ever: no false friends beyond these.
		eq(Guilds(Find(V, "amber")), "Olympus Amber Hollow")
		eq(Guilds(Find(V, "hoiiow")), "Olympus Amber Hollow", "Hollow's two Ls read as I")
		eq(Guilds(Find(V, "XIIII")), "", "one letter too many finds nothing")
		local all = Guilds(Find(V, ""))
		eq(select(2, all:gsub(",", "")), 4, "five guilds listed: " .. all)
		eq(Guilds(Find(V, "olympus")), all, "every guild, the order as ever")
		eq(Guilds(Find(V, "0LYMPUS")), all, "with a zero typed too")
	end)
end)

test("1.2.1 Census search: what is typed stays as typed, and the recruiting word still lists the guilds with room", function()
	WithCensus(function(V)
		Find(V, "XIlI")
		eq(V.Filter("census"), "XIlI", "the box keeps what was typed")
		local word = ns.Fold(ns.L.SEARCH_RECRUITING_WORDS):match("[^,%s]+")
		local lines = Find(V, word)
		local found = false
		for _, l in ipairs(lines) do if l.header and l.text == ns.L.RECRUITING then found = true end end
		check(found, "the recruiting list for %s", word)
	end)
end)

-- CR-08, the Realm's search (Olympus/Views.lua's RealmLines) over the same census: the guilds'
-- rows, by their id, in order.
local function RealmGuilds(lines)
	local out = {}
	for _, l in ipairs(lines) do
		local name = type(l.id) == "string" and l.id:match("^guild:(.+)$")
		if name then out[#out + 1] = name end
	end
	return table.concat(out, ",")
end
local function FindRealm(V, text)
	V.SetFilter("realm", text)
	return V.Build("realm")
end
local function Says(lines, text)
	for _, l in ipairs(lines) do if Plain(l.text) == text then return true end end
	return false
end

test("CR-08 Realm search: l, I and 1 read alike, 0 and O too, as in the Census: XIII finds OLYMPUS XIlI, its Lord, Captains and members seen", function()
	WithCensus(function(V)
		local who, savedSweep = ns.Who, ns.Who and ns.Who.sweep
		-- A member of Olympus Amber Hollow the /who round saw online.
		who.sweep = { list = { { name = "Ilvara", guild = "Olympus Amber Hollow", level = 18, class = "MAGE" } } }
		local ok, err = pcall(function()
			-- A guild by its name, typed as it looks, any case.
			eq(RealmGuilds(FindRealm(V, "XIII")), "OLYMPUS XIlI")
			eq(RealmGuilds(FindRealm(V, "xiii")), "OLYMPUS XIlI")
			eq(RealmGuilds(FindRealm(V, "X1lI")), "OLYMPUS XIlI", "a one and a small L typed")
			eq(RealmGuilds(FindRealm(V, "olympus xili")), "OLYMPUS XIlI", "as written")
			eq(RealmGuilds(FindRealm(V, "house")), "Olympus H0use", "a zero for an O")
			eq(RealmGuilds(FindRealm(V, "h0use")), "Olympus H0use")
			-- Its Lord, a Captain and a member seen online, opened under their guild.
			local lines = FindRealm(V, "marrek dunhoit")
			eq(RealmGuilds(lines), "OLYMPUS XIlI", "a Lord, an l typed as I"); eq(People(lines), "Marrek Dunholt")
			lines = FindRealm(V, "ysoide")
			eq(RealmGuilds(lines), "Olympus II"); eq(People(lines), "Ysolde Imrie", "a Captain")
			lines = FindRealm(V, "llvara")
			eq(RealmGuilds(lines), "Olympus Amber Hollow", "a member seen, his capital i typed as a small L")
			eq(People(lines), "Ilvara", "his row under it")
			-- Every other letter as ever.
			eq(RealmGuilds(FindRealm(V, "amber")), "Olympus Amber Hollow")
			eq(RealmGuilds(FindRealm(V, "hoiiow")), "Olympus Amber Hollow", "Hollow's two Ls read as I")
			lines = FindRealm(V, "XIIII")
			eq(RealmGuilds(lines), "", "one letter too many finds nothing")
			check(Says(lines, ns.L.SEARCH_NO_MATCH), "and says so")
			eq(V.Filter("realm"), "XIIII", "the box keeps what was typed")
		end)
		who.sweep = savedSweep
		if not ok then error(err, 0) end
	end)
end)

-- CR-08, the Realm's other views (Olympus/Views.lua's RealmGroupedLines: classes, races and
-- professions), each with a search of its own over the same people: its groups' rows by their key,
-- in order.
local function Groups(lines)
	local out = {}
	for _, l in ipairs(lines) do
		local key = type(l.id) == "string" and l.id:match("^realm:%a+:(.+)$")
		if key then out[#out + 1] = key end
	end
	return table.concat(out, ",")
end
local function FindIn(V, mode, text)
	V.SetRealmMode(mode, true)
	V.SetFilter("realm:" .. mode, text)
	return V.Build("realm")
end

test("CR-08 Realm's classes, races and professions: their search reads l, I and 1 alike, 0 and O too, as the guilds': XIII finds OLYMPUS XIlI's people, a name and a profession typed as they look", function()
	WithCensus(function(V)
		local who, crafters = ns.Who, ns.Crafters
		local saved = { sweep = who.sweep, board = crafters.Board }
		-- A member of Olympus Amber Hollow the /who round saw online, a tailor on the crafters' board.
		who.sweep = { list = { { name = "Ilvara", guild = "Olympus Amber Hollow", level = 18, class = "MAGE" } } }
		crafters.Board = function()
			return { { name = "Ilvara", guild = "Olympus Amber Hollow", t = os.time(),
				profs = { { key = "197", name = "Tailoring", rank = 120, max = 150 } } } }
		end
		local ok, err = pcall(function()
			-- A guild's people by its name, typed as it looks.
			eq(People(FindIn(V, "classes", "olympus xiii")), "Marrek Dunholt-Realm", "XIlI's Lord, by his guild")
			eq(People(FindIn(V, "races", "XIII")), "Marrek Dunholt-Realm", "the races' search too")
			-- A name, his capital i typed as a small L or a one, under his group.
			local lines = FindIn(V, "classes", "llvara")
			eq(Groups(lines), "MA"); eq(People(lines), "Ilvara-Realm")
			eq(People(FindIn(V, "classes", "1lvara")), "Ilvara-Realm", "a one typed")
			eq(People(FindIn(V, "classes", "ysoide")), "Ysolde Imrie-Realm", "a Captain, his l typed as I")
			-- A profession's name, and its crafter's guild.
			lines = FindIn(V, "professions", "taiioring")
			eq(Groups(lines), "197", "Tailoring"); eq(People(lines), "Ilvara-Realm")
			eq(People(FindIn(V, "professions", "amber hoiiow")), "Ilvara-Realm", "his guild, Hollow's Ls typed as I")
			-- Every other letter as ever.
			lines = FindIn(V, "classes", "XIIII")
			eq(People(lines), "", "one letter too many finds nothing")
			check(Says(lines, ns.L.SEARCH_NO_MATCH), "and says so")
			eq(V.Filter("realm:classes"), "XIIII", "the box keeps what was typed")
		end)
		who.sweep, crafters.Board = saved.sweep, saved.board
		V.SetRealmMode("guilds", true)
		if not ok then error(err, 0) end
	end)
end)

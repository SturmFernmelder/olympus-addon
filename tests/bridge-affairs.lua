-- The Companion's sections for the tabs of affairs (931, Olympus/BridgeAffairs.lua): crafting,
-- crafters, treasury, decrees, agenda, notices, watch and chatRooms. Each test's name holds
-- "companion bridge affairs", so `luajit tests/run.lua bridge` and `... companion` run them.
-- Loaded by tests/run.lua with the Chat tab's world (WithWindow) and the repository's root.
local ns, test, eq, extra = ...
local ROOT = extra.ROOT or "./"
local WithWindow = extra.WithWindow

local AFFAIRS = { "crafting", "crafters", "treasury", "decrees", "agenda", "notices", "watch", "chatRooms" }

-- Every string and key inside a value (for "never carries" checks).
local function Strings(v, out, depth)
	out = out or {}
	depth = depth or 0
	if type(v) == "string" or type(v) == "number" then out[#out + 1] = tostring(v)
	elseif type(v) == "table" and depth < 10 then
		for k, x in pairs(v) do
			out[#out + 1] = tostring(k)
			Strings(x, out, depth + 1)
		end
	end
	return out
end
local function Carries(v, needle) return table.concat(Strings(v), "\n"):find(needle, 1, true) ~= nil end

-- Each key of each row is in `allowed` ("what" names the list for the message).
local function OnlyFields(rows, allowed, what)
	for i, row in ipairs(rows) do
		for k in pairs(row) do assert(allowed[k], ("%s[%d]: field %s"):format(what, i, tostring(k))) end
	end
end
local function Set(list) local s = {} for _, k in ipairs(list) do s[k] = true end return s end

-- The section's data through the registry (OlympusBridge.GetSection: a plain copy within its limits).
local function Data(name)
	local got = OlympusBridge.GetSection(name)
	return got and got.data
end

---------------------------------------------------------------------------
-- A world of its own: Bridge.lua's registry fresh (the real OlympusBridge put back after), the
-- affairs' file loaded into a namespace over the harness's, with the real OfficerMuster, Chronicle,
-- Decree and Week where o asks, and stand-ins for the rest. Every module a section reads is off
-- (false) unless the test gives it. w.now: this computer's clock; w.clock: the server's.
---------------------------------------------------------------------------
local function World(fn, o)
	o = o or {}
	local w = { now = 1800000000, clock = 1800000007, member = true, accord = true, roles = {}, ranks = {},
		guild = "Olympus Ember", kingGuild = "Olympus Ember", lordGuild = "Olympus Ember", handlers = {}, kingHandlers = {}, printed = {}, team = false }
	local c = setmetatable({ me = "Tester-Realm", realm = "Realm", group = "Realm", faction = "Alliance",
		db = { accord = { v = 1, yes = true, at = 0 } }, rdb = { guilds = {} }, L = setmetatable({}, { __index = ns.L }),
		DecreePages = {}, RealmPages = {} }, { __index = ns })
	w.c = c
	local function Role(name) return name and w.roles[c.FullName(name)] end
	c.Now = function() return w.now end
	c.AccordAccepted = function() return w.accord end
	c.IsMember = function() return w.member end
	c.IsFederation = function(g) return type(g) == "string" and g:find("Olympus", 1, true) ~= nil end
	c.IsKingGuild = function(g) return g ~= nil and g == w.kingGuild end
	c.KingGuildName = function() return w.kingGuild end
	c.IsKingCharacter = function(n) return Role(n) == "king" end
	c.IsHighCouncillor = function(n) return Role(n) == "council" end
	c.IsCrown = function() return false end
	c.CouncilMasked = function() return w.masked == true end
	c.GroupOf = function(realm) return realm end
	c.On, c.Every, c.After, c.Fire, c.Log, c.Alert = function() end, function() end, function() end, function() end, function() end, function() end
	c.RegisterEvent = function() end
	c.Print = function(t) w.printed[#w.printed + 1] = tostring(t) end
	c.Data = { ServerTime = function() return w.clock end, Summary = function() return { guilds = {} } end,
		ClaimGuild = function() return true end,
		-- A "lord" masters w.lordGuild alone: rank 0 there, the roster's word in this character's own
		-- guild and the census's in another (Data.AuthorizedRank before the signed enforcement).
		AuthorizedRank = function(name, guild)
			if Role(name) ~= "lord" or guild ~= w.lordGuild then return nil end
			return 0, guild == w.guild and "roster" or "census"
		end }
	c.Roster = { RankOf = function(n) return w.ranks[c.FullName(n)] end, MyRank = function() return w.ranks[c.me] or 3 end,
		IsOfficer = function() return false end }
	c.King = { HAND_MAY = {}, STEWARD_MAY = {}, Register = function(kind, f) w.kingHandlers[kind] = f end,
		CleanGuild = function(g) return type(g) == "string" and g ~= "" and g or nil end,
		Preview = function() return false end, IsKing = function() return Role(c.me) == "king" end, IsSteward = function() return false end,
		IsStewardName = function(n) return Role(n) == "steward" end, IsHandName = function(n) return Role(n) == "hand" end,
		FromKing = function(n) return Role(n) == "king" end, Agenda = function() return w.agenda end,
		AgendaAuthorized = function(name) return w.roles[c.FullName(name)] ~= nil end, CanAgenda = function() return false end }
	c.Moderation = { Hides = function(name) return w.hidden and w.hidden[name] and {} or nil end, SelfOff = function() return nil end }
	c.Workshop = { IsAuthorName = function(n) return Role(n) == "author" end }
	c.Comm = { Handle = function(prefix, h) w.handlers[prefix] = h end, Send = function() return true end, Hello = function() end,
		DeliveredLogged = function() return true end }
	c.Zones = { NameForKey = function(k) return ({ m1429 = "Elwynn Forest", m1453 = "Stormwind City" })[k] or k end }
	c.Layers = { CountSharedInZone = function() return 3 end, CurrentMap = function() return 1429 end }
	c.Views = { ShowDecreePage = function() end, DecreePageShown = function() return nil end }
	c.UI = { RefreshSoon = function() end, Refresh = function() end }
	c.ViewAs = { Previewing = function() return false end }
	c.Filter = { Hides = function(text) return w.hide ~= nil and type(text) == "string" and text:find(w.hide, 1, true) ~= nil end }
	c.WatchChat = { Barred = function() return false end, InRoom = function(name) return w.team == true and name == c.me end }
	for _, m in ipairs({ "CraftRequests", "Crafters", "Treasury", "Decree", "Week", "OfficerMuster", "Chronicle", "HonorsNet",
		"Watch", "Inspect", "Channels", "ChatRooms", "ChatWindow" }) do c[m] = false end
	local saved = { bridge = rawget(_G, "OlympusBridge"), guild = GetGuildInfo, inGuild = IsInGuild, time = GetServerTime,
		best = C_Map.GetBestMapForUnit, pos = C_Map.GetPlayerMapPosition, info = C_Map.GetMapInfo, chat = C_ChatInfo,
		members = GetNumGuildMembers }
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild end
		IsInGuild = function() return true end
		GetServerTime = function() return w.clock end
		C_ChatInfo = nil
		C_Map.GetBestMapForUnit = function() return 1429 end
		C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.4125, 0.5875 end } end
		C_Map.GetMapInfo = function(id)
			if id == 1429 then return { mapID = id, name = "Elwynn Forest", mapType = 3 } end
			if id == 1453 then return { mapID = id, name = "Stormwind City", mapType = 3 } end
		end
		for _, file in ipairs(o.load or {}) do assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c) end
		OlympusBridge = nil
		assert(loadfile(ROOT .. "Olympus/Bridge.lua"))("Olympus", c)
		if o.sections then assert(loadfile(ROOT .. "Olympus/BridgeSections.lua"))("Olympus", c) end
		assert(loadfile(ROOT .. "Olympus/BridgeAffairs.lua"))("Olympus", c)
		w.B = OlympusBridge
		fn(w, c)
	end)
	OlympusBridge, GetGuildInfo, IsInGuild, GetServerTime = saved.bridge, saved.guild, saved.inGuild, saved.time
	C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition, C_Map.GetMapInfo, C_ChatInfo = saved.best, saved.pos, saved.info, saved.chat
	GetNumGuildMembers = saved.members
	if not ok then error(err, 0) end
end

-- Stand-ins for the modules whose page data a test makes up (the shapes their own public
-- functions return), with private fields beside the public ones to show they stay out.
local function Craft(o)
	o = o or {}
	local rows = {}
	for i = 1, o.open or 3 do
		rows[#rows + 1] = { id = "c" .. i, itemName = "Lionheart Helm " .. i, quantity = i, requester = "Asker" .. i .. "-Realm",
			guild = "Olympus Ember", state = "open", updated = 1799999000 + i, details = "SECRET DETAILS", quote = { reference = 987654 },
			claimNonces = { abc = true }, audit = { { detail = "SECRET AUDIT" } } }
	end
	for i = 1, o.own or 2 do
		rows[#rows + 1] = { id = "m" .. i, itemName = "Flask of the Titans", quantity = 2, requester = "Tester-Realm", crafter = "Maker" .. i .. "-Realm",
			guild = "Olympus Ember", state = "terms", updated = 1799998000 + i, terms = { unit = 424242, total = 848484, source = "SECRET TERMS" },
			settlement = { custodian = "Keeper-Realm", rail = "guild" }, chat = { { text = "SECRET CHAT" } }, crafterGuild = "Olympus Ember" }
	end
	for i = 1, o.making or 1 do
		rows[#rows + 1] = { id = "k" .. i, itemName = "Arcanite Bar", quantity = 5, requester = "Buyer" .. i .. "-Realm", crafter = "Tester-Realm",
			guild = "Olympus Ember", state = "in_progress", updated = 1799997000 + i, terms = { unit = 1, source = "SECRET TERMS" } }
	end
	rows[#rows + 1] = { id = "done", itemName = "Old Deal", quantity = 1, requester = "Tester-Realm", crafter = "Maker-Realm", state = "completed",
		guild = "Olympus Ember", updated = 1799990000 }
	return { All = function() return rows end, CanFulfill = function(r) return r.id == "c2" end }
end

---------------------------------------------------------------------------
-- The registry
---------------------------------------------------------------------------

test("companion bridge affairs (931): every section of the tabs of affairs is registered at version 1, chatRooms by the name the Companion reads", function()
	local B = OlympusBridge
	local names = {}
	for _, s in ipairs(B.Sections()) do names[s.name] = s.version end
	for _, name in ipairs(AFFAIRS) do eq(names[name], 1, name) end
	-- (Bridge.lua's name rule: a lowercase letter, then letters, digits or "_".)
	local function F() return {} end
	eq(select(2, B.RegisterSection("ChatRooms", 1, F)), "name", "a capital first is refused")
	eq(select(2, B.RegisterSection("chat rooms", 1, F)), "name")
	eq(select(2, B.RegisterSection("chatRooms", 1, F)), "taken", "the affairs' file holds it")
	-- The private sidecar knows every tab's section, both lanes' (OlympusCompanionBridge/Checkpoint.lua).
	local text = assert(io.open(ROOT .. "OlympusCompanionBridge/Checkpoint.lua")):read("*a")
	local known = text:match("local KNOWN_SECTIONS = (%b{})")
	assert(known, "KNOWN_SECTIONS")
	for _, name in ipairs({ "guilds", "rankings", "self", "stats", "wanted", "realm", "roster", "church", "games", "profile",
		"crafting", "crafters", "treasury", "decrees", "agenda", "notices", "watch", "chatRooms" }) do
		assert(known:find("[{,%s]" .. name .. " = 1"), "the sidecar knows " .. name)
	end
	local readme = assert(io.open(ROOT .. "OlympusCompanionBridge/README.md")):read("*a")
	for _, name in ipairs(AFFAIRS) do assert(readme:find("`" .. name .. "`", 1, true), "README names " .. name) end
	local toc = assert(io.open(ROOT .. "Olympus/Olympus.toc")):read("*a")
	assert(toc:find("\nBridgeSections%.lua\r?\nBridgeAffairs%.lua\r?\n"), "the TOC loads it right after BridgeSections.lua")
end)

test("companion bridge affairs (931): nothing at all before the Olympus Accord is accepted, nor for a character who is no member", function()
	World(function(w, c)
		c.CraftRequests = Craft()
		c.Crafters = { Board = function() return { { name = "Smith-Realm", guild = "Olympus Ember", t = w.now, profs = { { key = "164", name = "Blacksmithing", rank = 300, max = 300, n = 12 } } } } end }
		c.Treasury = { PublicShows = function() return true end, Report = function() return { balance = 5, allIn = 9, allOut = 4, week = 1, donors = 1, t = w.now } end }
		c.Week = { Entries = function() return {} end }
		c.Decree = { Active = function() return {} end }
		c.Watch = { DeskShown = function() return true end, CanRead = function() return false end }
		c.Channels = { ORDER = { "A" }, TIERS = { A = { label = "CHAN_ALL" } }, CanUse = function() return true end }
		local function All() local n = 0 for _, name in ipairs(AFFAIRS) do if Data(name) then n = n + 1 end end return n end
		eq(All(), #AFFAIRS, "a member who accepted the Accord: every section")
		w.accord = false
		eq(All(), 0, "the Accord not accepted: none")
		w.accord, w.member = true, false
		eq(All(), 0, "no member: none")
		w.member = true
		eq(All(), #AFFAIRS)
	end)
end)

test("companion bridge affairs (931): a module that errors leaves its own section nil and every other section as it was", function()
	World(function(w, c)
		c.CraftRequests = { All = function() error("boom") end, CanFulfill = function() return false end }
		c.Crafters = { Board = function() return {} end }
		c.Decree = { Active = function() error("boom") end }
		c.Week = { Entries = function() return {} end, GuildEvents = function() error("boom") end }
		c.Treasury = { PublicShows = function() return false end, Report = function() return nil end }
		c.Watch = { DeskShown = function() return true end, CanRead = function() return true end, Cases = function() error("boom") end }
		c.Channels = { ORDER = { "A" }, TIERS = { A = { label = "CHAN_ALL" } }, CanUse = function() return true end }
		eq(Data("crafting"), nil, "its module errored")
		eq(Data("decrees"), nil); eq(Data("agenda"), nil); eq(Data("watch"), nil)
		eq(Data("notices"), nil, "its decrees errored: nil, not half a list")
		eq(type(Data("crafters")), "table", "the others go on")
		eq(Data("treasury").shown, false)
		eq(#Data("chatRooms"), 1)
		-- A module missing (a file that failed: a stand-in marked missing) is no section either.
		c.CraftRequests = { missing = true }
		eq(Data("crafting"), nil)
	end)
end)

---------------------------------------------------------------------------
-- crafting
---------------------------------------------------------------------------

test("companion bridge affairs (931): crafting carries the board's open cards and this character's own open deals, never terms, prices, details or request chat", function()
	World(function(w, c)
		c.CraftRequests = Craft()
		local d = assert(Data("crafting"))
		eq(#d.board, 3); eq(#d.own, 3, "his two requests taken and the one he is making; the completed one left out")
		local b = d.board[2]
		eq(b.id, "c2"); eq(b.item, "Lionheart Helm 2"); eq(b.quantity, 2); eq(b.guild, "Olympus Ember")
		-- (The review of 931: the board's line and its opened card name no requester; its search alone
		-- matches him. The board's rows carry none.)
		eq(b.requester, nil, "the board names no requester"); assert(not Carries(d.board, "Asker"), "no requester on the board")
		eq(b.status, "open"); eq(b.canMake, true, "the page's 'you can make it'"); eq(d.board[1].canMake, false)
		eq(b.at, 1799999002 + 7, "the server's time")
		OnlyFields(d.board, Set({ "id", "item", "quantity", "guild", "status", "at", "canMake" }), "board")
		OnlyFields(d.own, Set({ "id", "item", "quantity", "status", "guild", "at", "role", "crafter", "requester" }), "own")
		eq(d.own[1].role, "requester"); eq(d.own[1].crafter, "Maker1"); eq(d.own[1].requester, nil); eq(d.own[1].status, "terms")
		eq(d.own[3].role, "crafter"); eq(d.own[3].requester, "Buyer1"); eq(d.own[3].crafter, nil)
		for _, secret in ipairs({ "SECRET", "987654", "424242", "848484", "Keeper", "abc" }) do
			assert(not Carries(d, secret), "crafting carries " .. secret)
		end
	end)
end)

test("companion bridge affairs (931): crafting keeps the page's order and cuts the board at 100 and his deals at 30, from the end", function()
	World(function(w, c)
		c.CraftRequests = Craft({ open = 150, own = 40, making = 0 })
		local d = assert(Data("crafting"))
		eq(#d.board, 100); eq(d.board[1].id, "c1"); eq(d.board[100].id, "c100")
		eq(#d.own, 30); eq(d.own[30].id, "m30")
	end)
end)

test("companion bridge affairs (931): crafting from the real request store: an open card and his own taken request as the board's pages list them", function()
	local R = ns.CraftRequests
	local saved = ns.rdb.craftRequests
	local ok, err = pcall(function()
		local now = ns.Now()
		ns.rdb.craftRequests = { invites = {}, records = {
			cardx = { id = "cardx", requester = "Asker-Realm", itemName = "Thorium Bar", quantity = 4, kind = "c", profession = "",
				guild = "Olympus II", state = "open", created = now - 60, expires = now + 3600, updated = now - 60, details = "bring ore SECRET",
				audit = {}, chat = {}, seenActions = {}, seenChat = {} },
			mine = { id = "mine", requester = ns.me, crafter = "Maker-Realm", itemName = "Truesilver Rod", quantity = 1, kind = "c", profession = "",
				guild = "Olympus II", state = "accepted", created = now - 120, expires = now + 3600, updated = now - 30,
				terms = { unit = 777777, total = 777777, source = "SECRET" }, chat = { { text = "SECRET CHAT" } }, audit = {}, seenActions = {}, seenChat = {} },
		} }
		local d = assert(Data("crafting"), "the real registry's crafting section")
		eq(#d.board, 1); eq(d.board[1].id, "cardx"); eq(d.board[1].item, "Thorium Bar"); eq(d.board[1].quantity, 4)
		eq(d.board[1].requester, nil, "as the board shows it: no requester"); assert(not Carries(d.board, "Asker"))
		eq(#d.own, 1); eq(d.own[1].id, "mine"); eq(d.own[1].status, "accepted"); eq(d.own[1].crafter, "Maker")
		assert(not Carries(d, "SECRET") and not Carries(d, "777777"), "no terms, details or chat")
		eq(#R.All(), 2, "the store itself unchanged by the export")
	end)
	ns.rdb.craftRequests = saved
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- crafters
---------------------------------------------------------------------------

test("companion bridge affairs (931): crafters lists the directory, best skill first, 300 at most, four professions each, with nothing but name, guild and skills", function()
	World(function(w, c)
		local board = {}
		for i = 1, 400 do
			local profs = {}
			for j = 1, 6 do profs[j] = { key = tostring(160 + j), name = "Prof" .. j, rank = (i % 300) + j, max = 300, n = i, recipes = { { i = 99 } }, secret = "SECRET" } end
			board[i] = { name = ("Crafter%03d-Realm"):format(i), guild = "Olympus Ember", t = w.now - i, profs = profs }
		end
		c.Crafters = { PROFS_MAX = 4, Board = function() return board end,
			CanonicalProfessionKey = function(key) return key end, ProfessionLabel = function(key, name) return name .. " (" .. key .. ")" end }
		local d = assert(Data("crafters"))
		eq(#d, 300, "cut at 300")
		eq(#d[1].professions, 4, "four professions a listing carries")
		eq(d[1].professions[1].name, "Prof1 (161)", "the page's English label")
		assert(d[1].professions[4].skill >= d[300].professions[4].skill, "the best first")
		eq(d[1].name, "Crafter299", "the highest skill (299 + 4) first, the display name")
		eq(d[1].at, w.now - 299 + 7)
		OnlyFields(d, Set({ "name", "guild", "at", "professions" }), "crafter")
		for _, row in ipairs(d) do OnlyFields(row.professions, Set({ "name", "skill", "max", "recipes" }), "profession") end
		assert(not Carries(d, "SECRET"))
	end)
end)

test("companion bridge affairs (931): crafters from the real board, as the tab lists it", function()
	local saved = ns.rdb
	local ok, err = pcall(function()
		ns.rdb = { guilds = {}, craftersBoard = {
			["Smith-Realm"] = { guild = "Olympus II", t = ns.Now() - 60, profs = { { key = "164", name = "Blacksmithing", rank = 290, max = 300, n = 41 } } },
		} }
		local d = assert(Data("crafters"))
		eq(#d, 1); eq(d[1].name, "Smith"); eq(d[1].guild, "Olympus II")
		eq(d[1].professions[1].skill, 290); eq(d[1].professions[1].max, 300); eq(d[1].professions[1].recipes, 41)
		eq(d[1].professions[1].name, ns.Crafters.ProfessionLabel(ns.Crafters.CanonicalProfessionKey("164", "Blacksmithing"), "Blacksmithing"))
	end)
	ns.rdb = saved
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- treasury
---------------------------------------------------------------------------

test("companion bridge affairs (931): treasury carries public numbers alone, and only while the King shows the balance", function()
	local T = ns.Treasury
	local saved = { flags = ns.rdb.treasuryFlags, report = T.Report }
	local ok, err = pcall(function()
		ns.rdb.treasuryFlags = { balance = false, ranking = true, book = true }
		local d = assert(Data("treasury"))
		eq(d.shown, false); eq(d.balanceCopper, nil, "no number while the balance is private")
		for k in pairs(d) do eq(k, "shown") end
		ns.rdb.treasuryFlags = { balance = true }
		eq(Data("treasury").shown, true, "shown, nothing heard from the keepers yet")
		local asked
		T.Report = function(shared, public)
			asked = { shared, public }
			return { balance = 12345678, allIn = 20000000, allOut = 7654322, week = 50000, donors = 7, t = ns.Now(),
				rank = { { name = "Donor Secret", money = 1 } }, book = { { e = { who = "Book Secret" } } }, items = { { id = 19019, n = 1 } },
				keepers = { { name = "Keeper Secret" } }, opening = 99 }
		end
		d = assert(Data("treasury"))
		eq(asked[1], true); eq(asked[2], true, "the treasury as it may go out")
		eq(d.balanceCopper, 12345678); eq(d.collectedCopper, 20000000); eq(d.spentCopper, 7654322); eq(d.weekCopper, 50000); eq(d.weekDonors, 7)
		OnlyFields({ d }, Set({ "shown", "balanceCopper", "collectedCopper", "spentCopper", "weekCopper", "weekDonors", "at" }), "treasury")
		assert(not Carries(d, "Secret") and not Carries(d, "19019"), "no item, book line, donor or keeper")
	end)
	ns.rdb.treasuryFlags, T.Report = saved.flags, saved.report
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- decrees and notices, with the real Decree.lua, OfficerMuster.lua and Chronicle.lua
---------------------------------------------------------------------------

local REAL = { "Locales/OfficerMusterText", "Chronicle", "OfficerMuster", "Decree" }

test("companion bridge affairs (931): decrees lists the Decrees tab's decrees as the real module holds them: the King's, the High Council's and a guild's own, never a local preview", function()
	World(function(w, c)
		w.roles["Royal-Realm"], w.roles["Sage-Realm"], w.ranks["Lord-Realm"] = "king", "council", 0
		local D1 = w.handlers.D1
		D1("CHANNEL", "Royal-Realm", ns.Codec.EncodeDecree("ROYAL", 1453, 0.5, 0.25, "Olympus Ember", 0, "Muster at the gates"))
		w.now, w.clock = w.now + 61, w.clock + 61
		D1("CHANNEL", "Sage-Realm", ns.Codec.EncodeDecree("ARMS", 1429, 0.1, 0.2, "Olympus Ember", 0, ""))
		w.now, w.clock = w.now + 61, w.clock + 61
		D1("GUILD", "Lord-Realm", ns.Codec.EncodeDecree("ROYAL", 1429, 0.3, 0.3, "Olympus Ember", 0, "Guild meeting"))
		c.Decree.Preview("ROYAL")
		eq(#c.Decree.Active(), 4, "the module holds four, the preview among them")
		local d = assert(Data("decrees"))
		eq(#d, 3, "the preview is not a decree anyone sent")
		local guild, council, royal = d[1], d[2], d[3]
		eq(guild.scope, "guild"); eq(guild.role, "guildMaster"); eq(guild.kind, "royal"); eq(guild.text, "Guild meeting")
		eq(guild.title, c.Decree.Label({ kind = "ROYAL", scope = "guild" }))
		eq(council.scope, "army"); eq(council.role, "council"); eq(council.kind, "arms"); eq(council.text, nil); eq(council.zone, "Elwynn Forest")
		eq(royal.role, "crown"); eq(royal.by, "Royal"); eq(royal.guild, "Olympus Ember"); eq(royal.zone, "Stormwind City")
		eq(royal.at, 1800000007, "the server's time of its arrival"); eq(royal.expires, 1800000007 + 3600)
		OnlyFields(d, Set({ "id", "kind", "scope", "role", "title", "zone", "text", "hidden", "by", "guild", "at", "expires" }), "decree")
		-- Words the player's block terms hide stay hidden, as on the page.
		w.hide = "secret plan"
		w.now, w.clock = w.now + 61, w.clock + 61
		D1("CHANNEL", "Royal-Realm", ns.Codec.EncodeDecree("ROYAL", 1453, 0.6, 0.6, "Olympus Ember", 0, "our secret plan"))
		local veiled = Data("decrees")[1]
		eq(veiled.hidden, true); eq(veiled.text, ns.L.FILTER_WORDS_HIDDEN_SHORT); assert(not Carries(Data("decrees"), "secret plan"))
	end, { load = REAL })
end)

test("companion bridge affairs (931): on the King's screen while the councillors' names are hidden, a councillor's decree has no role and is no notice, never the Crown's", function()
	World(function(w, c)
		w.roles["Royal-Realm"], w.roles["Sage-Realm"] = "king", "council"
		local D1 = w.handlers.D1
		D1("CHANNEL", "Royal-Realm", ns.Codec.EncodeDecree("ROYAL", 1453, 0.5, 0.25, "Olympus Ember", 0, "Crown speaks"))
		w.now, w.clock = w.now + 61, w.clock + 61
		D1("CHANNEL", "Sage-Realm", ns.Codec.EncodeDecree("ROYAL", 1429, 0.1, 0.2, "Olympus Ember", 0, "Council speaks"))
		local shown = assert(Data("decrees"))
		eq(#shown, 2); eq(shown[1].role, "council", "the names shown: the council's mark")
		eq(Data("notices").items[1].kind, "council")
		w.masked = true
		local d = assert(Data("decrees"))
		eq(#d, 2, "the Decrees tab still lists it")
		eq(d[1].id, shown[1].id); eq(d[1].text, "Council speaks"); eq(d[1].by, "Sage", "the sender the page's tooltip names")
		eq(d[1].role, nil, "no council mark while the names are hidden, and not the Crown's")
		eq(d[2].role, "crown", "the King's own decree")
		local items = assert(Data("notices")).items
		eq(#items, 1, "the councillor's decree is no notice while hidden")
		eq(items[1].kind, "king"); eq(items[1].role, "crown"); eq(items[1].text, "Crown speaks")
		for _, item in ipairs(items) do assert(item.id ~= shown[1].id and item.kind ~= "council", item.id) end
		w.masked = false
		eq(#Data("notices").items, 2, "the eye open: the council's decree again")
	end, { load = REAL })
end)

test("companion bridge affairs (931): notices in the agreed shape: an officer muster, its withdrawal under the same id, the Crown's and the High Council's decrees, a guild master's muster for his guild", function()
	World(function(w, c)
		w.roles["Royal-Realm"], w.roles["Sage-Realm"], w.roles["Lord-Realm"] = "king", "council", "lord"
		local OM, D1 = w.handlers.OM, w.handlers.D1
		local seq = w.clock
		assert(OM("CHANNEL", "Royal-Realm", ("OM~1~P~A~Realm~%d~%d~Olympus Ember~1429~Defend Goldshire"):format(seq, w.clock)))
		assert(OM("GUILD", "Lord-Realm", ("OM~1~P~A~Realm~%d~%d~Olympus Ember~1429~Guild raid"):format(seq + 5, w.clock)))
		w.now, w.clock = w.now + 30, w.clock + 30
		D1("CHANNEL", "Sage-Realm", ns.Codec.EncodeDecree("ROYAL", 1453, 0.5, 0.5, "Olympus Ember", 0, "Council speaks"))
		local items = assert(Data("notices")).items
		eq(#items, 3)
		local decree, crown, guild = items[1], items[2], items[3]
		eq(decree.kind, "council"); eq(decree.role, "council"); eq(decree.text, "Council speaks"); eq(decree.audience, "army")
		eq(crown.id, ("muster:%d:%s"):format(seq, ns.Fold("Royal-Realm")), "the agreed id: muster:<sequence>:<poster key>")
		eq(crown.kind, "muster"); eq(crown.role, "crown"); eq(crown.title, "Defend Goldshire"); eq(crown.zone, "Elwynn Forest")
		eq(crown.withdrawn, false); eq(crown.at, seq); eq(crown.audience, "army"); eq(crown.guild, nil)
		eq(guild.role, "guildMaster"); eq(guild.guild, "Olympus Ember", "a guild master's muster names his guild"); eq(guild.audience, "guild")
		for _, item in ipairs(items) do
			assert(#item.title <= 60 and (item.text == nil or (#item.text <= 120 and not item.text:find("\n"))), item.id)
			for k in pairs(item) do
				assert(({ id = true, kind = true, role = true, title = true, text = true, zone = true, guild = true, at = true, withdrawn = true, audience = true })[k], "notice field " .. k)
			end
		end
		-- The King withdraws his: the same id, withdrawn, newest first.
		w.now, w.clock = w.now + 30, w.clock + 30
		assert(OM("CHANNEL", "Royal-Realm", ("OM~1~E~A~Realm~%d~%d"):format(seq, seq)))
		items = Data("notices").items
		eq(items[1].id, crown.id); eq(items[1].withdrawn, true); eq(items[1].title, "Defend Goldshire")
		local ids = {}
		for _, item in ipairs(items) do assert(not ids[item.id], "each id once: " .. item.id); ids[item.id] = true end
		-- A day later the ended muster is gone from the notices (the acts log still keeps it).
		w.now, w.clock = w.now + 86400 + 60, w.clock + 86400 + 60
		for _, item in ipairs(Data("notices").items) do assert(item.id ~= crown.id, "an old ending") end
	end, { load = REAL })
end)

test("companion bridge affairs (931): notices carry this character's own letters from the King, one line, his alone; at most 30, newest first", function()
	World(function(w, c)
		local letters = {}
		for i = 1, 40 do letters[i] = { key = "donor-top-" .. (i % 3 + 1), t = 1799000000 + i } end
		c.HonorsNet = { Letters = function() return letters end,
			LetterText = function(key) return "Dude,\n\nYou've put more gold into Olympus than almost anyone. That's not a little, that's insane. You're the Patron, keep it.", "Patron of Olympus" end }
		c.Decree = { Active = function() return {} end }
		local items = assert(Data("notices")).items
		eq(#items, 30, "30 at most")
		eq(items[1].at, 1799000040, "the newest first"); eq(items[30].at, 1799000011)
		local x = items[1]
		eq(x.kind, "king"); eq(x.role, "crown"); eq(x.audience, "self", "his alone: never fanned out"); eq(x.title, "Patron of Olympus")
		eq(x.text:sub(1, 30), "Dude, You've put more gold int"); assert(#x.text <= 120 and not x.text:find("\n"))
		eq(x.id, "letter:donor-top-2:1799000040")
		-- A Slayer letter's key (Wanted.lua's: a digest, numbers and the Horde player's name) goes by its digest.
		letters[40].key = "wanted@0123456789abcdef~12~4~3~0~2~60~Some Horde Player"
		local slayer = Data("notices").items[1]
		assert(slayer.id:find("^letter:%x+:1799000040$"), slayer.id); assert(not slayer.id:find("Horde", 1, true))
	end)
end)

-- Each notice by its id.
local function ById(items)
	local out = {}
	for _, item in ipairs(items or {}) do out[item.id] = item end
	return out
end

test("companion bridge affairs (931): an ended muster keeps its audience and role: a guild master's stays his guild's, the Crown's the army's; another guild's or faction's is no notice", function()
	World(function(w, c)
		-- Lord-Realm masters Olympus Ember, which is not the King's guild: his calls reach his guild alone.
		w.kingGuild = "Olympus"
		w.roles["Royal-Realm"], w.roles["Lord-Realm"] = "king", "lord"
		local OM = w.handlers.OM
		local seq = w.clock
		assert(OM("GUILD", "Lord-Realm", ("OM~1~P~A~Realm~%d~%d~Olympus Ember~1429~Guild raid"):format(seq, seq)))
		assert(OM("CHANNEL", "Royal-Realm", ("OM~1~P~A~Realm~%d~%d~Olympus~1429~Defend Goldshire"):format(seq + 1, seq)))
		local guildId, crownId = ("muster:%d:%s"):format(seq, ns.Fold("Lord-Realm")), ("muster:%d:%s"):format(seq + 1, ns.Fold("Royal-Realm"))
		local active = ById(assert(Data("notices")).items)
		eq(active[guildId].audience, "guild"); eq(active[guildId].guild, "Olympus Ember"); eq(active[guildId].role, "guildMaster")
		eq(active[crownId].audience, "army"); eq(active[crownId].role, "crown")
		w.now, w.clock = w.now + 30, w.clock + 30
		assert(OM("GUILD", "Lord-Realm", ("OM~1~E~A~Realm~%d~%d"):format(seq, seq)))
		assert(OM("CHANNEL", "Royal-Realm", ("OM~1~E~A~Realm~%d~%d"):format(seq + 1, seq)))
		eq(#c.OfficerMuster.List(), 0, "both ended: only the acts log holds them")
		local ended = ById(Data("notices").items)
		local g, k = assert(ended[guildId], "the guild's withdrawn muster"), assert(ended[crownId], "the Crown's withdrawn muster")
		eq(g.withdrawn, true); eq(g.title, "Guild raid")
		eq(g.audience, "guild", "his guild's alone, withdrawn as while it stood"); eq(g.guild, "Olympus Ember"); eq(g.role, "guildMaster")
		eq(k.withdrawn, true); eq(k.audience, "army"); eq(k.guild, nil); eq(k.role, "crown")
		for _, item in pairs(ended) do assert(item.audience, "every notice has its audience: " .. item.id) end
		-- The acts log is this account's on the realm group: another character of it, in another
		-- guild, holds the same rows. The guild's call is none of his; the Crown's still reaches him.
		w.guild = "Olympus II"
		ended = ById(Data("notices").items)
		eq(ended[guildId], nil, "another guild's muster is no notice here")
		eq(ended[crownId].audience, "army")
		-- A role lost since: no notice to place.
		w.guild, w.roles["Lord-Realm"] = "Olympus Ember", nil
		eq(ById(Data("notices").items)[guildId], nil, "its poster no longer that guild's master")
		-- Nor the other faction's call, on a character of the same account of the other faction.
		w.roles["Lord-Realm"], c.faction = "lord", "Horde"
		eq(#Data("notices").items, 0, "the Alliance's calls are no Horde character's")
	end, { load = REAL })
	-- The King's guild's master calls the whole army: the same role and audience once withdrawn.
	World(function(w, c)
		w.roles["Lord-Realm"], w.ranks["Lord-Realm"] = "lord", 0
		local OM = w.handlers.OM
		local seq = w.clock
		assert(OM("CHANNEL", "Lord-Realm", ("OM~1~P~A~Realm~%d~%d~Olympus Ember~1429~Hold the bridge"):format(seq, seq)))
		local id = ("muster:%d:%s"):format(seq, ns.Fold("Lord-Realm"))
		local before = ById(Data("notices").items)[id]
		eq(before.role, "crown"); eq(before.audience, "army")
		w.now, w.clock = w.now + 30, w.clock + 30
		assert(OM("CHANNEL", "Lord-Realm", ("OM~1~E~A~Realm~%d~%d"):format(seq, seq)))
		local after = ById(Data("notices").items)[id]
		eq(after.withdrawn, true); eq(after.role, before.role, "the same role as while active"); eq(after.audience, "army"); eq(after.guild, nil)
	end, { load = REAL })
end)

---------------------------------------------------------------------------
-- agenda, with the real Week.lua
---------------------------------------------------------------------------

test("companion bridge affairs (931): agenda lists the week as the real module holds it: the King's Agenda, the dated entries, this guild's own, the Arena's fights; soonest first, 30 at most", function()
	World(function(w, c)
		w.roles["Royal-Realm"], w.roles["Lord-Realm"], w.roles["Stew-Realm"], w.roles["Hand-Realm"] = "king", "lord", "steward", "hand"
		w.ranks["Lord-Realm"] = 0
		-- 26 heard entries (the King's 10 and his Steward's 10, the most each holds; a Hand's 5; the
		-- guild master's one for his guild), the current Agenda, and 5 Arena fights: 32 rows.
		local heard = {}
		for i = 1, 26 do
			local by = i == 1 and "Lord-Realm" or i <= 11 and "Royal-Realm" or i <= 21 and "Stew-Realm" or "Hand-Realm"
			heard[i] = { id = 1000 + i, by = by, title = "Raid night " .. i, zone = "Molten Core", at = w.now + 3000 + i * 3600,
				crown = (by == "Royal-Realm" or by == "Stew-Realm") or nil, heardAt = w.now, guild = "Olympus Ember", guildOnly = i == 1 or nil }
		end
		c.rdb.weekHeard = heard
		c.Week.Restore(w.now)
		eq(#c.Week.Entries(w.now), 26, "the module keeps every one of them")
		w.agenda = { id = 7, title = "Court at the throne", at = w.now + 600, zone = "Stormwind City", by = "Royal-Realm", guild = "Olympus Ember" }
		table.insert(c.Week.providers, function()
			local out = {}
			for i = 1, 5 do out[i] = { at = w.now + 1800 + i, title = "Arena final " .. i, zone = "Gurubashi", tip = "SECRET TIP" } end
			return out
		end)
		local d = assert(Data("agenda"))
		eq(#d, 30, "cut at 30, the furthest left out")
		eq(d[1].source, "agenda"); eq(d[1].title, "Court at the throne"); eq(d[1].by, ns.KingName("Royal-Realm")); eq(d[1].role, "crown")
		eq(d[1].at, w.now + 600 + 7, "the server's time"); eq(d[1].zone, "Stormwind City")
		eq(d[2].source, "arena"); eq(d[2].title, "Arena final 1"); eq(d[2].scope, "army")
		eq(d[7].title, "Raid night 1"); eq(d[7].scope, "guild"); eq(d[7].role, "guildMaster"); eq(d[7].by, "Lord"); eq(d[7].source, "week")
		eq(d[8].title, "Raid night 2"); eq(d[8].scope, "army"); eq(d[8].role, "crown"); eq(d[8].by, ns.KingName("Royal-Realm"))
		eq(d[18].role, "crown", "the Steward's"); eq(d[18].by, "Stew")
		eq(d[30].title, "Raid night 24")
		for i = 2, #d do assert(d[i - 1].at <= d[i].at, "soonest first") end
		OnlyFields(d, Set({ "id", "title", "zone", "at", "scope", "source", "role", "by" }), "agenda")
		assert(not Carries(d, "SECRET"))
	end, { load = { "Week" } })
end)

---------------------------------------------------------------------------
-- watch
---------------------------------------------------------------------------

local function WatchStub(w)
	local function Case(i, open)
		return { key = "k" .. i, target = "Reported" .. i .. "-Realm", open = open, reporters = 2, cats = { A = 2 }, firstAt = 100 + i, lastAt = 200 + i,
			reports = { { reporter = "Reporter Secret", note = "NOTE SECRET", lines = { "LINE SECRET" } } },
			finding = i % 2 == 0 and { verdict = "up" } or nil, -- (the even ones upheld)
			record = { lastReason = "REASON SECRET" } }
	end
	local open, handled, records = {}, {}, {}
	for i = 1, 120 do open[i] = Case(i, true) end
	for i = 1, 30 do handled[i] = Case(500 + i, false) end
	for i = 1, 150 do
		records[i] = { name = "Rec" .. i .. "-Realm", status = i <= 5 and "ban" or i <= 10 and "watch" or nil, warnings = i % 3, interventions = 1,
			timeoutUntil = i == 1 and 1800009999 or 0, updatedAt = 300 + i, lastReason = "REASON SECRET", lastBy = "Moderator Secret", statusBy = "Moderator Secret" }
	end
	return {
		DeskShown = function() return w.desk == true end, CanRead = function() return w.canRead == true end,
		CouncilDeskShown = function() return false end, TabardsShown = function() return w.tabards ~= false end,
		Cases = function() return open, handled end, Records = function() return records end,
		CatsText = function(cats) return ("abuse or slurs (%d)"):format(cats.A or 0) end,
		Reports = function() error("the reports themselves are never read") end, Audit = function() error("nor the audit") end,
	}
end

test("companion bridge affairs (931): watch exists only on a moderation team client or for the desk's own staff, with the counts and lists the pages show and nothing private", function()
	World(function(w, c)
		c.Watch = WatchStub(w)
		local players = {}
		for i = 1, 150 do players[i] = { name = "Seen" .. i .. "-Realm", guild = "Olympus Ember", status = i % 2 == 0 and "NONE" or "GUILD", level = 30, t = w.now, note = "NOTE SECRET", by = "Officer Secret" } end
		c.Inspect = { Summary = function() return { players = players, total = 150, counts = { GUILD = 75, NONE = 70, OTHER = 5 } } end,
			ShameOpen = function() return true end, Shame = function() return { list = { { name = "Bare", guild = "Olympus Ember" } }, t = w.now } end }
		eq(Data("watch"), nil, "a plain member: no watch section at all")
		w.team = true
		local d = assert(Data("watch"), "a moderation team client")
		eq(#d.cases, 0, "the desk's lists only for those who read the desk"); eq(#d.records, 0)
		eq(d.counts.inspected, 150); eq(d.counts.untabarded, 70); eq(d.counts.tabardsCaught, 75); eq(d.counts.wallOfShame, 1)
		w.team, w.desk, w.canRead = false, true, true
		d = assert(Data("watch"), "an officer of the desk")
		eq(d.counts.casesOpen, 120); eq(d.counts.casesHandled, 30); eq(d.counts.reportsOpen, 240)
		eq(#d.cases, 100, "100 per list"); eq(d.cases[1].name, "Reported1"); eq(d.cases[1].open, true); eq(d.cases[1].reports, 2)
		eq(d.cases[1].categories, "abuse or slurs (2)")
		eq(#d.records, 100); eq(d.records[1].status, "ban"); eq(d.records[1].timeoutUntil, 1800009999); eq(d.counts.banned, 5); eq(d.counts.watched, 5)
		eq(#d.inspected, 100); eq(d.untabarded[1].name, "Bare")
		OnlyFields(d.cases, Set({ "name", "open", "reports", "categories", "firstAt", "lastAt", "council" }), "case")
		OnlyFields(d.records, Set({ "name", "status", "warnings", "interventions", "timeoutUntil", "at" }), "record")
		OnlyFields(d.inspected, Set({ "name", "guild", "status", "level", "at" }), "inspected")
		assert(not Carries(d, "SECRET") and not Carries(d, "Secret"), "no reporter, note, line, reason or moderator")
		w.tabards = false
		eq(Data("watch").counts.inspected, nil, "the Tabards' numbers only where the Tabards show")
	end)
end)

test("companion bridge affairs (931): watch on the King's stream carries the cases as the page shows them there: the accused cut short until upheld, no report counts or dates", function()
	World(function(w, c)
		-- The real Watch.lua (its Accused and Upheld, on this world's stream switch, c.CouncilMasked),
		-- loaded into a namespace of its own over the world's; the stub's cases and records for its data.
		local wns = setmetatable({ On = function() end, UI = {}, Moderation = {}, Comm = { Handle = function() end },
			PlayerMenu = { Add = function() return true end } }, { __index = c })
		local dialogs = {}
		for name, d in pairs(StaticPopupDialogs) do dialogs[name] = d end
		local loaded, why = pcall(function() assert(loadfile(ROOT .. "Olympus/Watch.lua"))("Olympus", wns) end)
		for name in pairs(StaticPopupDialogs) do StaticPopupDialogs[name] = dialogs[name] end
		assert(loaded, why)
		c.Watch = WatchStub(w)
		c.Watch.Accused, c.Watch.Upheld = wns.Watch.Accused, wns.Watch.Upheld
		w.desk, w.canRead = true, true
		local d = assert(Data("watch"))
		eq(d.cases[1].name, "Reported1"); eq(d.cases[1].reports, 2); eq(d.cases[1].firstAt, 101); eq(d.counts.reportsOpen, 240)
		w.masked = true
		eq(wns.Watch.OnStream(), true, "the page's own stream switch")
		d = assert(Data("watch"))
		eq(#d.cases, 100)
		for i, case in ipairs(d.cases) do
			eq(case.name, i % 2 == 0 and ("Reported" .. i) or ns.MaskName("Reported" .. i), "case " .. i .. ": whole only once upheld")
			eq(case.reports, nil); eq(case.firstAt, nil); eq(case.lastAt, nil)
			eq(case.categories, "abuse or slurs (2)", "the allegation the row shows")
		end
		eq(d.counts.reportsOpen, nil, "no count of reports on the stream")
		eq(d.counts.casesOpen, 120, "the sections' own counts, as their headers show them"); eq(d.counts.casesHandled, 30)
		eq(d.records[1].name, "Rec1", "the guild's records as their list shows them")
		local whole = Set(Strings(d))
		for i = 1, 99, 2 do assert(not whole["Reported" .. i] and not whole["Reported" .. i .. "-Realm"], "an unproven accused name whole: " .. i) end
		-- A Watch without the accessors: every accused name cut short.
		c.Watch.Accused, c.Watch.Upheld = nil, nil
		eq(Data("watch").cases[2].name, ns.MaskName("Reported2"))
	end)
end)

---------------------------------------------------------------------------
-- chatRooms, with the real ChatWindow.lua, ChatRooms.lua and Channels.lua
---------------------------------------------------------------------------

test("companion bridge affairs (931): chatRooms lists the Chat tab's rooms this character is in with the tab's unread counts, and no line of chat", function()
	WithWindow(function(w)
		local savedMembers = GetNumGuildMembers
		local ok, err = pcall(function()
			GetNumGuildMembers = function() return 812, 120 end
			ns.Channels.History = function() return { { sender = "Talker-Realm", text = "a line of chat SECRET" } } end
			w.CW.Open("A")
			eq(w.CW.Unread("guild"), 0)
			w.fire("CHAT_ROOM_LINE", "guild")
			w.fire("CHAT_ROOM_LINE", "guild")
			eq(w.CW.Unread("guild"), 2, "the tab's count (ChatWindow.Unread)")
			local d = assert(Data("chatRooms"))
			local by = {}
			for _, r in ipairs(d) do by[r.id] = r end
			assert(by.A, "the Olympus channel"); eq(by.A.kind, "channel"); eq(by.A.room, ns.L.CHAN_ALL); eq(by.A.unread, 0)
			eq(by.C, nil, "a soldier reads no [Captains]")
			eq(by.guild.kind, "guild"); eq(by.guild.unread, 2); eq(by.guild.members, 812)
			OnlyFields(d, Set({ "id", "room", "kind", "members", "unread" }), "room")
			assert(not Carries(d, "SECRET") and not Carries(d, "Talker"), "no chat text, no sender")
		end)
		GetNumGuildMembers = savedMembers
		if not ok then error(err, 0) end
	end)
end)

test("companion bridge affairs (931): chatRooms names a role room with its members as the page last counted them (ChatRooms.KnownRecipientCount), never a previewed role's", function()
	World(function(w, c)
		local counted = nil
		c.ChatRooms = { Info = function(id) if id == "guild" then return { id = "guild", label = "Guild" } end end, CanAccess = function() return true end,
			Options = function() return { { id = "council", label = "High Council" }, { id = "secretariat", label = "Secretariat", disabled = true } } end,
			KnownRecipientCount = function(id) return id == "council" and counted or nil end }
		local d = assert(Data("chatRooms"))
		eq(#d, 2, "the guild and the council: the previewed (disabled) room left out")
		eq(d[2].id, "council"); eq(d[2].room, "High Council"); eq(d[2].members, nil, "not counted this session")
		counted = 11
		eq(Data("chatRooms")[2].members, 11)
	end)
	-- The accessor itself, on the real module: nil until the page counted the room, then its count.
	local R = ns.ChatRooms
	local council = ns.IsHighCouncillor
	local ok, err = pcall(function()
		R.Reset()
		ns.IsHighCouncillor = function(name) return name == nil or name == ns.me end
		eq(R.KnownRecipientCount("council"), nil)
		local n, left = R.RecipientCount("council")
		eq(R.KnownRecipientCount("council"), (n or 0) + (left or 0))
	end)
	ns.IsHighCouncillor = council
	R.Reset()
	if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- Size: every section of the file together, with full boards and a 1000-member guild
---------------------------------------------------------------------------

-- A value as the game writes SavedVariables: tabs, ["key"] = value, and "-- [n]" after list items.
local function Serialize(v, indent, out)
	local t = type(v)
	if t == "string" then out[#out + 1] = ("%q"):format(v)
	elseif t == "number" or t == "boolean" then out[#out + 1] = tostring(v)
	elseif t == "table" then
		local inner = indent .. "\t"
		out[#out + 1] = "{\n"
		local n = #v
		local keys = {}
		for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(keys) do
			out[#out + 1] = inner .. "[" .. (type(k) == "string" and ("%q"):format(k) or tostring(k)) .. "] = "
			Serialize(v[k], inner, out)
			out[#out + 1] = ",\n"
		end
		for i = 1, n do
			out[#out + 1] = inner
			Serialize(v[i], inner, out)
			out[#out + 1] = ", -- [" .. i .. "]\n"
		end
		out[#out + 1] = indent .. "}"
	else out[#out + 1] = "nil" end
end
local function Bytes(v)
	local out = {}
	Serialize(v, "", out)
	return #table.concat(out)
end

local function Long(prefix, n) return (prefix .. string.rep("x", n)):sub(1, n) end

test("companion bridge affairs (931): every section together, full boards, caps and a 1000-member guild's roster, stays well under 2 MiB", function()
	World(function(w, c)
		-- The tabs of affairs at their caps and beyond, with the longest strings each field takes.
		local cards = {}
		for i = 1, 150 do cards[i] = { id = Long("id" .. i, 24), itemName = Long("Item" .. i, 60), quantity = 1000, requester = Long("Asker" .. i, 40) .. "-Realm",
			guild = Long("Olympus Guild" .. i, 72), state = "open", updated = w.now } end
		for i = 1, 40 do cards[#cards + 1] = { id = Long("own" .. i, 24), itemName = Long("Own" .. i, 60), quantity = 1000, requester = c.me, crafter = Long("Maker" .. i, 40) .. "-Realm",
			guild = Long("Olympus Guild", 72), state = "in_progress", updated = w.now } end
		c.CraftRequests = { All = function() return cards end, CanFulfill = function() return true end }
		local board = {}
		for i = 1, 400 do
			local profs = {}
			for j = 1, 4 do profs[j] = { key = tostring(j), name = Long("Profession" .. j, 40), rank = 300, max = 300, n = 250 } end
			board[i] = { name = Long("Crafter" .. i, 40) .. "-Realm", guild = Long("Olympus Guild" .. i, 72), t = w.now, profs = profs }
		end
		c.Crafters = { PROFS_MAX = 4, Board = function() return board end }
		c.Treasury = { PublicShows = function() return true end, Report = function() return { balance = 2147483647, allIn = 2147483647, allOut = 2147483647, week = 2147483647, donors = 1000, t = w.now } end }
		local decrees = {}
		for i = 1, 40 do decrees[i] = { kind = "HERALDRY", mapID = 1453, x = i / 100, y = 0.5, guild = Long("Olympus Guild", 72), rank = 0, text = Long("Words" .. i, 500),
			sender = Long("Sender" .. i, 40) .. "-Realm", t = w.now - i, expires = w.now + 3600 } end
		c.Decree = { Active = function() return decrees end, Label = function() return Long("TABARD INSPECTION", 60) end }
		local week = {}
		for i = 1, 40 do week[i] = { id = 100000 + i, title = Long("Event" .. i, 60), zone = Long("Zone", 40), at = w.now + i * 60, by = "Royal-Realm" } end
		c.Week = { Entries = function() return week end, GuildEvents = function() return {} end, Provided = function() return {} end }
		local letters = {}
		for i = 1, 20 do letters[i] = { key = Long("donor-top-" .. i, 40), t = w.now - i } end
		c.HonorsNet = { Letters = function() return letters end, LetterText = function() return Long("Letter words ", 400), Long("Title", 60) end }
		local stub = WatchStub(w)
		w.desk, w.canRead = true, true
		c.Watch = stub
		local players = {}
		for i = 1, 2000 do players[i] = { name = Long("Inspected" .. i, 40) .. "-Realm", guild = Long("Olympus Guild", 72), status = "UNCHECKED", level = 60, t = w.now } end
		local shame = {}
		for i = 1, 300 do shame[i] = { name = Long("Bare" .. i, 40), guild = Long("Olympus Guild", 72) } end
		c.Inspect = { Summary = function() return { players = players, total = 2000, counts = {} } end, ShameOpen = function() return true end,
			Shame = function() return { list = shame, t = w.now } end }
		c.Channels = { ORDER = { "A", "C", "L" }, TIERS = { A = { label = "CHAN_ALL" }, C = { label = "CHAN_CAPTAINS" }, L = { label = "CHAN_LORDS" } }, CanUse = function() return true end }
		local options = {}
		for i = 1, 300 do options[i] = { id = Long("gcorr:" .. i, 40), label = Long("Room" .. i, 60) } end
		c.ChatRooms = { Info = function() return { label = "Guild" } end, CanAccess = function() return true end, Options = function() return options end,
			KnownRecipientCount = function() return 1000 end }
		GetNumGuildMembers = function() return 1000, 300 end

		-- The census's own sections (BridgeSections.lua) at their caps: 256 guilds, the Wanted list,
		-- the rankings.
		local guilds = {}
		for i = 1, 256 do guilds[i] = { name = Long("Olympus Guild" .. i, 72), counted = true, fresh = true,
			g = { total = 1000, online = 300, t = w.now, mine = i == 1, avgLevel = 47.9, realm = "Realm", vouch = { a = true } } } end
		c.Data = setmetatable({ Summary = function() return { guilds = guilds, seen = {}, total = 250000, characters = 256000, alts = 6000, online = 70000, fresh = 256 } end,
			AvgTenths = function() return 479 end }, { __index = c.Data })
		local wanted, slayers = {}, {}
		for i = 1, 100 do wanted[i] = { place = i, name = Long("Horde" .. i, 40), guid = "Player-1-" .. i, bounty = 999, kills = 999, cycle = 9 } end
		for i = 1, 50 do slayers[i] = { place = i, name = Long("Slayer" .. i, 40), points = 999, kills = 999 } end
		c.API = { Wanted = function() return wanted end, Rankings = function() return { slayers = { month = slayers, signed = slayers }, donors = { all = { "a", "b", "c" } },
			church = { missionaries = { "a", "b", "c" } }, games = { arena = slayers, bones = slayers } } end }
		local crafting = {}
		for i = 1, 60 do crafting[i] = { place = i, name = Long("Smith" .. i, 40), points = 999, deliveries = 99, customers = 99 } end
		c.CraftRanking = { Current = function() return crafting end }
		-- The other lane's sections (realm, roster, church, games, profile: BRIDGE-SECTIONS.md's caps),
		-- as stand-ins of their documented shapes, so the measure is the whole file's.
		local B = w.B
		local roster, realm, public, events = {}, {}, {}, {}
		for i = 1, 1000 do roster[i] = { name = Long("Member" .. i, 40), level = 60, class = "Warrior", rank = Long("Rank", 30), online = true, lastSeen = w.now } end
		for i = 1, 256 do
			local emissaries = {}
			for j = 1, 4 do emissaries[j] = { office = Long("Office" .. j, 40), name = Long("Emissary" .. j, 40) } end
			realm[i] = { name = Long("Olympus Guild" .. i, 72), lord = Long("Lord" .. i, 40), members = 1000, online = 300, avgLevel = 47.9, faction = "Alliance",
				realmGroup = Long("Realm", 60), founded = w.now, emissaries = emissaries }
		end
		for i = 1, 100 do public[i] = { place = i, name = Long("Pious" .. i, 40), title = Long("Missionary", 40), recruits = 99, points = 999 } end
		for i = 1, 50 do events[i] = { kind = "duel", at = w.now, a = Long("A" .. i, 40), b = Long("B" .. i, 40), winner = Long("A" .. i, 40), points = 99 } end
		assert(B.RegisterSection("roster", 1, function() return { guild = "Olympus Guild", members = roster } end, { values = 8000 }))
		assert(B.RegisterSection("realm", 1, function() return { guilds = realm } end, { values = 8000 }))
		assert(B.RegisterSection("church", 1, function() return { public = public, own = { title = "Missionary", apostle = "A", missionaries = 3, recruits = 14, points = 140, pending = 2 } } end))
		assert(B.RegisterSection("games", 1, function() return { events = events, own = { duelsWon = 1, duelsLost = 1, bonesWon = 1, bonesLost = 1, points = 1, place = 1 } } end))
		assert(B.RegisterSection("profile", 1, function() return { name = "Tester", guild = "Olympus Guild", rank = "Officer", level = 60, class = "Warrior", frame = "rank" } end))

		local sections, affairs, total = {}, 0, 0
		local sizes = {}
		for _, s in ipairs(B.Sections()) do
			local got = B.GetSection(s.name)
			if got and s.name ~= "census" then
				sections[s.name] = { version = got.version, data = got.data }
				local n = Bytes(sections[s.name])
				sizes[#sizes + 1] = ("%s %d"):format(s.name, n)
				for _, a in ipairs(AFFAIRS) do if a == s.name then affairs = affairs + n end end
			end
		end
		-- Each affairs' list at its cap, none cut short by the copy's value budget.
		eq(#sections.crafting.data.board, 100); eq(#sections.crafting.data.own, 30)
		eq(#sections.crafters.data, 300); eq(#sections.crafters.data[300].professions, 4)
		eq(#sections.decrees.data, 30); eq(#sections.decrees.data[30].text, 500, "a decree's words whole, 500 bytes")
		eq(#sections.agenda.data, 30); eq(#sections.notices.data.items, 30)
		eq(#sections.watch.data.cases, 100); eq(#sections.watch.data.records, 100); eq(#sections.watch.data.inspected, 100); eq(#sections.watch.data.untabarded, 100)
		eq(#sections.chatRooms.data, 100)
		eq(#sections.roster.data.members, 1000, "the stand-in roster whole")
		local census = assert(B.GetCensusCheckpoint(), "the census checkpoint")
		local file = { schema = "olympus-companion-db", version = 1, checkpoint = census, sections = sections }
		total = Bytes(file)
		print(("    measured: the affairs' sections %d bytes; the whole file %d bytes (%s)"):format(affairs, total, table.concat(sizes, ", ")))
		assert(affairs < 512 * 1024, "the affairs' sections under 512 KiB: " .. affairs)
		assert(total < 2 * 1024 * 1024, "the whole file under 2 MiB: " .. total)
	end, { sections = true })
end)

local ns, test, eq, H = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]event%-notebook%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = ns })

local function Setup()
	local w = World.New({ council = false, arenaFiles = {}, compliance = "shipped" })
	local organizer, member, king, treasurer = w:Role("fighterA"), w:Role("fighterB"), w:Role("king"), w:Role("treasurer")
	local id = 77123
	for _, c in ipairs({ organizer, member, king, treasurer }) do w:As(c, function()
		c.ns.L = setmetatable({}, { __index = ns.L })
		assert(loadfile(ROOT .. "Olympus/Locales/EventNotebookText.lua"))("Olympus", c.ns)
		local event = { id = id, title = "Trial of the Mountain", by = organizer.name, mine = c == organizer }
		c.ns.Week = {
			Entry = function(want) return tostring(want) == tostring(id) and event or nil end,
			Entries = function() return { event } end,
			MayEdit = function(e) return e == event and c == organizer end,
		}
		assert(loadfile(ROOT .. "Olympus/EventNotebook.lua"))("Olympus", c.ns)
		local b = c.ns.Treasury.Book(); b.opening, b.openedAt = 0, w.clock
	end) end
	-- Capture organizer whispers as complete private payloads. Treasury's chunk transport and
	-- permission guards have their own suite; these tests exercise this module's exact payload.
	organizer.private = {}
	w:As(organizer, function()
		organizer.ns.Treasury.Private = function(to, kind, msg, key)
			organizer.private[#organizer.private + 1] = { to = to, kind = kind, msg = msg, key = key }
			return true
		end
	end)
	return w, organizer, member, king, treasurer, id
end

local function Build(w, organizer, id)
	w:As(organizer, function()
		local E = organizer.ns.EventNotebook
		assert(E.SetParticipants(id, "Torvin Hale, Selka Drummond, Lida Fenn"))
		assert(E.AddResult(id, "Semifinal", "Torvin Hale", "Selka Drummond", "Torvin Hale"))
		assert(E.SetPodium(id, "Torvin Hale, Selka Drummond, Lida Fenn"))
		assert(E.SetMoney(id, 1230000, 10))
		assert(E.SetPrize(id, "Torvin Hale", 700000))
		assert(E.SetPrize(id, "Selka Drummond", 400000))
		assert(E.MarkEntry(id, "Lida Fenn", 25000))
	end)
end

test("Event notebook: organizer fills a zero-default manual bracket and arithmetic without creating a wager or automatic payment", function()
	local w, organizer, _, _, _, id = Setup()
	w:As(organizer, function()
		local E = organizer.ns.EventNotebook
		local book = assert(E.Book(id, true)); local zero = assert(E.Arithmetic(book))
		eq(zero.pot, 0); eq(zero.cut, 0); eq(zero.organizer, 0); eq(zero.treasurer, 0); eq(zero.pool, 0)
		assert(E.SetParticipants(id, "Torvin Hale, Selka Drummond"))
		assert(E.SetMoney(id, 1000000, 0), "zero cut is a valid running bracket")
		eq(E.Arithmetic(book).pool, 1000000)
		assert(E.SetMoney(id, 1000000, 15))
		local a = E.Arithmetic(book)
		eq(a.cut, 150000); eq(a.organizer, 75000); eq(a.treasurer, 75000); eq(a.pool, 850000)
		assert(E.SetPrize(id, "Torvin Hale", 850000)); eq(E.SetPrize(id, "Selka Drummond", 1), false, "prizes cannot exceed the remainder")
		assert(E.MarkEntry(id, "Selka Drummond", 50000), "entry is marked received by the host")
		eq(book.pot, 1000000, "entry does not silently alter the organizer-entered pot")
		eq(E.SetPrize(id, "Outsider", 1), false); eq(E.MarkEntry(id, "Outsider", 1), false)
	end)
end)

test("Event notebook: public channel receives only bracket fields; financial sheet is accepted only by authorized private recipients", function()
	local w, organizer, member, king, treasurer, id = Setup(); Build(w, organizer, id)
	local public, private
	w:As(organizer, function()
		local E, book = organizer.ns.EventNotebook, assert(organizer.ns.EventNotebook.Book(id))
		book.public = true
		public, private = E.PublicMessage(book), E.PrivateMessage(book, 8844)
		assert(public:find("Torvin Hale", 1, true)); assert(not public:find("1230000", 1, true))
		assert(not public:find("700000", 1, true)); assert(not public:find("25000", 1, true))
		assert(private:find("1230000", 1, true) and private:find("700000", 1, true) and private:find("25000", 1, true))
	end)
	w:As(member, function()
		assert(member.ns.EventNotebook.HandlePublic("CHANNEL", organizer.name, public))
		local held = member.rdb.eventNotebooks.public[tostring(id)]
		assert(held and held.participants[1]); eq(held.pot, nil); eq(held.prizes, nil); eq(held.entries, nil)
		eq(member.ns.EventNotebook.HandlePrivate("WHISPER", organizer.name, private), false, "ordinary member cannot receive private sheet")
		eq(member.ns.EventNotebook.HandlePublic("CHANNEL", member.name, public), false, "non-organizer cannot forge bracket")
	end)
	-- Requested nonce for the King; unsolicited nonce zero for the single pinned Treasurer.
	local query = nil
	w:As(king, function()
		king.ns.Treasury.Private = function(_, kind, msg) query = msg; eq(kind, "EN"); return true end
		assert(king.ns.EventNotebook.Request(id))
	end)
	local nonce = assert(tonumber(query:match("^EN~1~Q~(%d+)~")))
	local requested
	w:As(organizer, function()
		assert(organizer.ns.IsKingCharacter(king.name), "fixture King must pass the production pin")
		assert(organizer.ns.EventNotebook.Book(id))
		assert(organizer.ns.EventNotebook.HandlePrivate("WHISPER", king.name, query), query)
		requested = organizer.private[#organizer.private].msg
	end)
	w:As(king, function()
		assert(king.ns.EventNotebook.HandlePrivate("WHISPER", organizer.name, requested))
		local key = organizer.name:lower() .. ":" .. id
		local held = assert(king.rdb.eventNotebooks.private[key]); eq(held.pot, 1230000); eq(held.prizes[organizer.ns.FullName("Torvin Hale"):lower()], 700000)
		eq(king.ns.EventNotebook.HandlePrivate("WHISPER", member.name, requested), false)
	end)
	local automatic = private:gsub("~8844~", "~0~", 1)
	w:As(treasurer, function()
		assert(treasurer.ns.EventNotebook.HandlePrivate("WHISPER", organizer.name, automatic))
		local key = organizer.name:lower() .. ":" .. id
		eq(treasurer.rdb.eventNotebooks.private[key].pot, 1230000)
	end)
	assert(nonce > 0)
end)

test("Event notebook: Fill is an explicit click for the exact open trade, never an entry refund, never AcceptTrade, and blocked APIs degrade to instructions", function()
	local w, organizer, member, _, treasurer, id = Setup(); Build(w, organizer, id)
	local set, accepted = {}, 0
	organizer.globals.TradeFrame = { IsShown = function() return organizer.trade ~= nil end }
	organizer.globals.C_TradeInfo = { SetTradeMoney = function(copper) set[#set + 1] = copper end }
	organizer.globals.GetMoney = function() return 2000000 end
	organizer.globals.AcceptTrade = function() accepted = accepted + 1 end
	w:As(organizer, function()
		local E, book = organizer.ns.EventNotebook, assert(organizer.ns.EventNotebook.Book(id))
		local a = E.Arithmetic(book); eq(a.treasurer, 61500)
		eq(select(2, E.Fill(id, "treasurer")), "closed"); eq(#set, 0)
		organizer.trade = { with = member }
		eq(select(2, E.Fill(id, "treasurer")), "other"); eq(#set, 0)
		organizer.trade = { with = treasurer }
		eq(organizer.ns.UnitFullName("NPC"), organizer.ns.FullName(organizer.ns.TREASURER, organizer.ns.TREASURER_REALM))
		assert(E.Fill(id, "treasurer")); eq(set[#set], 61500); eq(accepted, 0)
		eq(E.Fill(id, "entry", "Lida Fenn"), false, "an entry is never staged back out")
		organizer.db.eventTradeBlocked = true
		local before = #set; eq(select(2, E.Fill(id, "treasurer")), "type"); eq(#set, before)
	end)
end)

test("Event notebook: pinned Treasurer books only one exact actual event share, keeps it out of dues/donor/public lines, and rejects ambiguous or repeated money", function()
	local w, organizer, _, _, treasurer, id = Setup(); Build(w, organizer, id)
	local private
	w:As(organizer, function() private = organizer.ns.EventNotebook.PrivateMessage(assert(organizer.ns.EventNotebook.Book(id)), 0) end)
	w:As(treasurer, function()
		assert(treasurer.ns.EventNotebook.HandlePrivate("WHISPER", organizer.name, private))
		local T = treasurer.ns.Treasury
		local e = assert(T.Record(organizer.name, 61500, "trade", nil, { observed = true, quiet = true }))
		eq(e.kind, "event"); assert(e.eventRef)
		local sums = T.SumsOf(T.Book()); eq(sums.allIn, 61500); eq(sums.byDonor[e.name], nil)
		local again = assert(T.Record(organizer.name, 61500, "trade", nil, { observed = true, quiet = true }))
		eq(again.kind, nil, "same expected share cannot classify twice")
		local publicBook = T.Message(); assert(not publicBook:find(e.eventRef, 1, true)); assert(not publicBook:find("61500", 1, true), "private event line is not on OlympusNet")
	end)
end)


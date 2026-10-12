-- 1.2.3, Bones' live tables (Olympus/FarkleTable.lua's KN, the Arena window's Bones > Live tables):
-- a table between two players with the default settings is announced by both and listed for a
-- member who is not at it, and stays listed while it is played (KN every minute, the list keeps a
-- notice three minutes). The triple check of 1.2.2 (bug 6): the live record kept neither player's
-- yes to watchers (spec), so after a /reload that player stopped announcing his table (both
-- reloaded: gone from the member's list within three minutes), ignored a watcher's ask, and his
-- Play again opened the next table closed to watchers for both players. Practice against the
-- House is never announced, by design (nothing of it is sent), and the empty page says so.
-- On the release's gate (compliance "shipped": no wager, the King's live switch off as 1.2.x has
-- it), the test world (tests/arena/lib/world.lua) with the table's additions
-- (tests/arena/lib/farkle-world.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local N = H.World.NAMES
local P1, P2, VIEWER = N.fighterA, N.fighterB, N.bettor3

local function Get(c, id) return c.ns.FarkleTable.Get(id) end
local function Do(w, c, fn, ...) return w:As(c, c.ns.FarkleTable[fn], ...) end
local function Listed(w, c, id)
	for _, n in ipairs(Do(w, c, "LiveTables")) do if n.id == id then return n end end
	return nil
end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
		if c.K then for _, e in ipairs(c.K.errors) do error(c.name .. " (a script): " .. e, 2) end end
	end
end

-- Two members at the Goldshire inn in one party (the first with the companion's board when asked:
-- o.board), a third member on the channel, not in their party.
local function Setup(o)
	o = o or {}
	local w = FW.New({ compliance = "shipped", seed = o.seed })
	local a = w:Player(P1, o.board and { companion = {} } or nil)
	if o.board then
		a.K = BoardUI.New(function() return w.clock end)
		a.K.Install(a.globals)
	end
	local b = w:Player(P2)
	local c = w:Player(VIEWER)
	w:Group({ a, b })
	return w, a, b, c
end
-- A table as a member makes it: the default settings (watchers allowed, nothing said), the guest's
-- answer with his box as it opens (ticked), the opening rolled (the host first).
local function Open(w, host, guest)
	local id = assert(Do(w, host, "Create", { guest = guest.name, target = 2000 }))
	w:Run(0)
	assert(Do(w, guest, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(host.name, 90); w:QueueRoll(guest.name, 10)
	Do(w, host, "Roll", id); Do(w, guest, "Roll", id)
	w:Run(0)
	eq(Get(host, id).state, "play"); eq(Get(guest, id).state, "play")
	return id
end
-- A /reload: the saved data written, the addon loaded again; the party as it was.
local function Reload(w, c, party)
	w:Logout(c); w:Login(c)
	w:Group(party)
	w:Run(0)
end

print("1.2.3: Bones' live tables")

test("1.2.3 Bones live tables: a two-player table with the default settings is announced by both players on the channel and listed for a member who is not at it, and stays listed while it is played", function()
	local w, a, b, c = Setup()
	local id = Open(w, a, b)
	eq(Get(a, id).mode, "T", "the live switch is off: the table's messages travel in T")
	eq(#w:Sent({ from = a, type = "KN", dist = "CHANNEL" }), 1, "the host announced it")
	eq(#w:Sent({ from = b, type = "KN", dist = "CHANNEL" }), 1, "the guest too")
	local n = assert(Listed(w, c, id), "listed for the member")
	eq(n.p1:lower(), a.name:lower()); eq(n.p2:lower(), b.name:lower())
	eq(Do(w, c, "Watchable", a.name), id, "the right-click's Watch finds it")
	-- A minute's notice at a time, the list keeping one three minutes: still there past them.
	w:Run(200)
	assert(not Get(a, id).game.over, "still played")
	assert(Listed(w, c, id), "still listed after 200 s")
	assert(#w:Sent({ from = a, type = "KN" }) >= 3, "announced again every minute")
	-- Its end takes it off the list.
	assert(Do(w, a, "Concede", id))
	w:Run(0)
	eq(Listed(w, c, id), nil, "an ended table is no live one")
	NoErrors(w)
end)

test("1.2.3 Bones live tables (bug 6): both players /reload mid-game; their table is still announced and still in the member's list after 200 s", function()
	local w, a, b, c = Setup()
	local id = Open(w, a, b)
	assert(Listed(w, c, id))
	Reload(w, a, { a, b })
	Reload(w, b, { a, b })
	local ta, tb = Get(a, id), Get(b, id)
	eq(ta.state, "play"); eq(tb.state, "play")
	eq(ta.spec[1], true, "the host's yes to watchers survived the reload")
	eq(tb.spec[2], true, "the guest's too")
	local before = #w:Sent({ type = "KN" })
	w:Run(200)
	assert(not Get(a, id).game.over, "still played")
	assert(#w:Sent({ from = a, type = "KN" }) > 0 and #w:Sent({ type = "KN" }) > before, "the reloaded players announce it again")
	assert(Listed(w, c, id), "still listed after 200 s")
	NoErrors(w)
end)

test("1.2.3 Bones live tables (bug 6): a member asks a reloaded player to watch his table and gets its state", function()
	local w, a, b, c = Setup()
	local id = Open(w, a, b)
	Reload(w, a, { a, b })
	Reload(w, b, { a, b })
	w:Run(61) -- (their notices again, from the reloaded clients)
	local n = assert(Listed(w, c, id))
	assert(Do(w, c, "Watch", id))
	w:Run(0)
	local relayer = w:Find(n.by)
	assert(Get(relayer, id).reloaded, "the relayer asked is a reloaded client")
	local tc = Get(c, id)
	eq(tc.role, "watch")
	assert(tc.snap, "the reloaded relayer answered the watcher with the table's state")
	eq(tc.snap.cur, Get(a, id).game.current)
	NoErrors(w)
end)

test("1.2.3 Bones live tables (bug 6): after a /reload, the board's Play again opens the next table with watchers allowed, as the player left them; the member lists it", function()
	local w, a, b, c = Setup({ board = true })
	local id = Open(w, a, b)
	Reload(w, a, { a, b })
	eq(Get(a, id).spec[1], true)
	assert(Do(w, b, "Concede", id))
	w:Run(31) -- (a guest takes one invitation from a sender every 30 s)
	assert(w:As(a, a.ns.Arena.LoadUI))
	local Board = a.ns.Arena.ui.FarkleBoard
	local spec = assert(w:As(a, Board.CardSpec, id), "the result card")
	local again
	for _, btn in ipairs(spec.buttons) do if btn[1] == a.ns.L.FARKLE_B_REMATCH then again = btn[2] end end
	assert(again, "the card's Play again")
	w:As(a, again)
	w:Run(0)
	local id2 = Do(w, a, "Live") and Do(w, a, "Live").id
	assert(id2 and id2 ~= id, "a new invitation went out")
	eq(Get(a, id2).spec[1], true, "the host still lets watchers in")
	assert(Do(w, b, "Answer", id2, true, nil, {}))
	w:Run(0)
	eq(Get(a, id2).noWatch, nil); eq(Get(b, id2).noWatch, nil, "the guest's table is not closed to watchers")
	assert(Listed(w, c, id2), "the member lists the new table")
	NoErrors(w)
end)

test("1.2.3 Bones live tables: practice with the innkeeper is never announced nor listed, by design; the empty page says so in both languages", function()
	-- (pt-BR first: the world's clients share the harness's words, and the English load puts them back)
	for _, locale in ipairs({ "ptBR", "enUS" }) do
		local w = FW.New({ compliance = "shipped" })
		local a = w:Player(P1)
		local c = w:Player(VIEWER, { companion = {} })
		c.K = BoardUI.New(function() return w.clock end)
		c.K.Install(c.globals)
		c.globals.GetLocale = function() return locale end
		local id = assert(Do(w, a, "Practice", { target = 2000 }))
		eq(Get(a, id).role, "practice")
		w:Run(130)
		eq(#w:Sent({ from = a, type = "KN" }), 0, "nothing of practice is sent")
		eq(#Do(w, c, "LiveTables"), 0)
		assert(w:As(c, c.ns.Arena.LoadUI))
		local L, UI = c.ns.L, c.ns.Arena.ui
		local lines = w:As(c, UI.Pane("bone.live").lines, { key = "bone.live" })
		local said = false
		for _, l in ipairs(lines) do if tostring(l.text or ""):find(L.ARENA_BONE_LIVE_NONE, 1, true) then said = true end end
		assert(said, "the empty list's line")
		assert(L.ARENA_BONE_LIVE_NONE:find(locale == "ptBR" and "taverneiro" or "innkeeper", 1, true), L.ARENA_BONE_LIVE_NONE)
		NoErrors(w)
	end
end)

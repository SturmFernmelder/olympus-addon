-- 1.2.4, the author's ask (rankings kept, never lost, passed from client to client): what the duels'
-- rankings keep (Olympus/ArenaLedger.lua). Before: the ledger lived in the companion's saved data
-- alone, and halves waiting for their other half in memory alone, so a fighter who never opened the
-- Arena window never saw his own duel ranked, a member without the window kept nothing, a logout lost
-- a half whose other half came later, and the clerk's carousel brought a later member the last two
-- weeks with duels only. Every name is invented; the account keys and signatures are real.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function Fights(w, c) return W3.M(w, c, "ArenaFights") end
local function Ledger(w, c) return W3.M(w, c, "ArenaLedger") end

-- The game's GetPlayerInfoByGUID on a client (the world's characters by their GUID), as
-- tests/arena/duels-count.lua gives it: a duel is rated only once the game pairs names and GUIDs.
local function Info(w, c)
	c.globals.GetPlayerInfoByGUID = function(guid)
		for _, o in ipairs(w.clients) do
			if o.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, o.short, o.realm ~= c.realm and o.realm or "" end
		end
		return nil
	end
end
-- A world as 1.2.4 ships (no wager anywhere) with the King's live switch off; opts.clock, opts.more.
local function World124(opts)
	opts = opts or {}
	local w, cast = W3.New({ live = false, world = { compliance = "shipped", clock = opts.clock }, more = opts.more })
	cast.A.target, cast.B.target = cast.B.name, cast.A.name
	for _, c in ipairs({ cast.A, cast.B }) do c.globals.UnitRace = function() return "Human", "Human", 1 end end
	for _, c in ipairs(w.clients) do Info(w, c) end
	local client = w.Client
	w.Client = function(self, ...)
		local c = client(self, ...)
		Info(self, c)
		return c
	end
	return w, cast
end
local function Agreed(w, cast)
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	assert(Fights(w, cast.B).Answer(oid, true))
	w:Run(0)
	return oid
end
local function Round(w, cast, winner, loser, secs)
	local a, b = cast.A, cast.B
	w:Combat(a, true)
	w:Combat(b, true)
	w:Run(secs or 20)
	W3.Duel(w, { a, b }, winner, loser)
	w:Fire(a, "DUEL_FINISHED")
	w:Fire(b, "DUEL_FINISHED")
	w:Run(0)
	w:Combat(a, false)
	w:Combat(b, false)
	w:Run(0)
end
local function Relog(w, c)
	w:Logout(c)
	w:Login(c)
	w:Run(0)
end

print("1.2.4: what the duels' rankings keep")

test("1.2.4 duels kept: fighters and a member who never open the Arena window keep the duel, ranked, in the core's saved data; kept after a relog", function()
	local w, cast = World124()
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B, 25)
	for _, c in ipairs({ cast.A, cast.B, cast.spectator }) do
		eq(c.companion.loaded, nil, c.short .. ": the Arena window never opened")
		local list = Ledger(w, c).Entries()
		eq(#list, 1, c.short .. ": the duel in his ledger"); eq(list[1] and list[1].fid, oid)
		eq(list[1] and list[1].fl, "dr", "rated")
		local book = c.rdb.arena.realms[c.realm].ledger
		assert(type(book) == "table" and next(book), c.short .. ": in the core's saved data")
	end
	local view = Ledger(w, cast.spectator).RankingView("all", "A", 1)
	eq(view.total, 2, "both fighters ranked"); eq(view.loaded, true)
	eq(view.rows[1].gk, cast.A.ns.Arena.GK(cast.A.guid))
	for _, c in ipairs({ cast.A, cast.spectator }) do
		Relog(w, c)
		eq(#Ledger(w, c).Entries(), 1, c.short .. ": kept after a relog")
	end
	W3.NoErrors(w)
end)

test("1.2.4 duels kept: a half waiting for its other half is kept through a relog and matched when the other half comes later", function()
	local w, cast = World124()
	local sp = cast.spectator
	-- (B's half never leaves his client at the duel's end: lost; his repeat brings it later)
	local send = cast.B.ns.Arena.Send
	cast.B.ns.Arena.Send = function(kind, ...)
		if kind == "AX" then return true end
		return send(kind, ...)
	end
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	cast.B.ns.Arena.Send = send
	eq(#Ledger(w, sp).Entries(), 0)
	eq(w:As(sp, sp.ns.ArenaLedger.Pending), 1, "A's half waits")
	-- A logs out (his repeats stop); the member relogs before B's half comes
	w:Logout(cast.A)
	Relog(w, sp)
	eq(w:As(sp, sp.ns.ArenaLedger.Pending), 1, "taken back from the saved data")
	w:Run(cast.B.ns.ArenaFights.HALF_REPEAT + 2)
	local list = Ledger(w, sp).Entries()
	eq(#list, 1, "matched with B's half, heard later"); eq(list[1] and list[1].fid, oid)
	eq(w:As(sp, sp.ns.ArenaLedger.Pending), 0)
	eq(next(sp.rdb.arena.realms[sp.realm].duelHalves or {}), nil, "nothing left waiting in the saved data")
	W3.NoErrors(w)
end)

test("1.2.4 duels kept: a fighter's own duel the ledger lost (the build before kept it in the companion's alone) is listed again at his login: his own half waits for the other's, which completes it", function()
	local w, cast = World124()
	local A = cast.A
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	eq(#Ledger(w, A).Entries(), 1)
	-- (as a build before left it: no entry, no half waiting; the fight and his own half kept)
	w:Logout(A)
	local rdb = A.saved.db.realms[World.GROUP]
	local store = rdb.arena.realms[A.realm]
	store.ledger, store.duelHalves = nil, nil
	w:Login(A)
	w:Run(0)
	eq(#Ledger(w, A).Entries(), 0, "lost")
	eq(w:As(A, A.ns.ArenaLedger.Pending), 1, "his own half, from his fight, waits for the other's")
	-- B's repeat (within HALF_FOR) brings his half: listed again
	w:Run(cast.B.ns.ArenaFights.HALF_REPEAT + 2)
	local list = Ledger(w, A).Entries()
	eq(#list, 1, "his own duel listed again"); eq(list[1] and list[1].fid, oid)
	W3.NoErrors(w)
end)

test("1.2.4 duels kept: the clerk's carousel brings a later member the season's eight weeks of duels (it was the last two weeks with duels)", function()
	local release = 1790812800 -- (ArenaLedger.RELEASE: season 1's first second)
	local w, cast = World124({ clock = release + 3600, more = { { "councillor", N.councillor } } })
	local clerk = cast.councillor
	local LG = clerk.ns.ArenaLedger
	eq(LG.RELEASE, release)
	local week = 7 * 86400
	local others = {}
	for _, c in ipairs(w.clients) do if c ~= cast.A and c ~= cast.B and c ~= clerk then others[#others + 1] = c end end
	for _, c in ipairs(others) do w:Logout(c) end
	local fids = {}
	for k = 0, 7 do
		if k > 0 then
			for _, c in ipairs({ cast.A, cast.B, clerk }) do w:Logout(c) end
			w:Run(week)
			for _, c in ipairs({ cast.A, cast.B, clerk }) do w:Login(c) end
		end
		W3.Companion(w, clerk)
		fids[#fids + 1] = Agreed(w, cast)
		Round(w, cast, k % 2 == 0 and cast.A or cast.B, k % 2 == 0 and cast.B or cast.A)
		w:Run(60)
	end
	eq(#Ledger(w, clerk).Entries(), 8, "the clerk heard every week's duel")
	local ax = 0
	-- (the clerk's namespace of this session: a login loads the files again)
	for _, p in ipairs(w:As(clerk, clerk.ns.ArenaLedger.Pieces, "L")) do if p[1] == "AX" then ax = ax + 1 end end
	eq(ax, 16, "the carousel carries all eight duels' halves")
	w:Logout(cast.A); w:Logout(cast.B)
	local late = w:Client("Idris Fold")
	W3.Rules(w, late)
	w:Run(LG.CLERK_WAIT + LG.CAROUSEL_GAP + 900)
	eq(#Ledger(w, late).Entries(), 8, "a member who logged in after them all has the season's eight")
	W3.NoErrors(w)
end)

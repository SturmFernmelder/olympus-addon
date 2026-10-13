-- 1.2.3, the duels (the Arena's triple check of 1.2.2 and the owner's decisions of 2026-10-11): a
-- free duel counts without the King's live switch (the bets' alone), a direct duel reaches every
-- client's rankings through its two signed halves (AX), and the triple check's bugs 3, 4, 5, 7, 8,
-- 9, 10, 11, 12 and 13. Every name is invented; the account keys and signatures are real
-- (Debts.lua's account key, Ed25519.lua).
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local N = World.NAMES

local function Fights(w, c) return W3.M(w, c, "ArenaFights") end
local function Ledger(w, c) return W3.M(w, c, "ArenaLedger") end
local function Fight(c, fid) return c.ns.ArenaFights.Find("fights", fid) end
local function State(w, c, fid)
	local f = Fight(c, fid)
	return f and w:As(c, c.ns.ArenaFights.State, f) or nil
end
local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
	return false
end
local function GK(c) return c.ns.Arena.GK(c.guid) end

-- The game's GetPlayerInfoByGUID on a client: the world's characters by their GUID (a real
-- character's resolves; a GUID nobody has gives nothing), as the client gives it: the realm left
-- empty for one's own. (1.2.3, the review: a duel is rated on a client only once the game there
-- pairs each fighter's name with his GUID, ArenaLedger's Bound; see the in-game checks.)
local function Info(w, c)
	c.globals.GetPlayerInfoByGUID = function(guid)
		for _, o in ipairs(w.clients) do
			if o.guid == guid then return "Warrior", "WARRIOR", "Human", "Human", 2, o.short, o.realm ~= c.realm and o.realm or "" end
		end
		return nil
	end
end

-- A world as 1.2.3 ships (no wager anywhere, the Wallet off) with the King's live switch OFF
-- unless opts.live; the two fighters target each other and read their own race (the weigh-in's
-- facts). opts.more: more clients, as W3.New's. Every client, the ones made later too, has the
-- game's GetPlayerInfoByGUID (Info) unless opts.info == false.
local function World123(opts)
	opts = opts or {}
	local w, cast = W3.New({ live = opts.live == true, world = { compliance = opts.compliance or "shipped" }, more = opts.more })
	cast.A.target, cast.B.target = cast.B.name, cast.A.name
	for _, c in ipairs({ cast.A, cast.B }) do c.globals.UnitRace = function() return "Human", "Human", 1 end end
	if opts.info ~= false then
		for _, c in ipairs(w.clients) do Info(w, c) end
		local client = w.Client
		w.Client = function(self, ...)
			local c = client(self, ...)
			Info(self, c)
			return c
		end
	end
	return w, cast
end
-- A challenge from a to b (the fighters by default), agreed: its oid.
local function Agreed(w, cast, opts, a, b)
	a, b = a or cast.A, b or cast.B
	local oid = assert(Fights(w, a).Challenge(b.name, opts or { bo = 1 }))
	w:Run(0)
	assert(Fights(w, b).Answer(oid, true))
	w:Run(0)
	return oid
end
-- A round as the game plays it: both fighters in combat (PLAYER_REGEN_DISABLED) for secs, the duel
-- line on both clients with DUEL_FINISHED, out of combat after. opts: { fled, before = fn() just
-- before the line, a, b (the fighters, cast.A and cast.B by default) }.
local function Round(w, cast, winner, loser, secs, opts)
	opts = opts or {}
	local a, b = opts.a or cast.A, opts.b or cast.B
	w:Combat(a, true)
	w:Combat(b, true)
	w:Run(secs or 20)
	if opts.before then opts.before() end
	W3.Duel(w, { a, b }, winner, loser, opts.fled)
	w:Fire(a, "DUEL_FINISHED")
	w:Fire(b, "DUEL_FINISHED")
	w:Run(0)
	w:Combat(a, false)
	w:Combat(b, false)
	w:Run(0)
end

print("1.2.3: a free duel counts without the live switch")

test("1.2.3 duels count: with the King's live switch off a free challenge is L, both clients end it final, each fighter's history has it and the winner's qualification points", function()
	local w, cast = World123()
	eq(cast.A.Roles.Live(), false, "the switch stays off")
	local oid = Agreed(w, cast)
	eq(cast.A.ns.ArenaFights.challenges[oid].mode, "L", "a free duel is L, not a rehearsal")
	eq(State(w, cast.B, oid), "S")
	Round(w, cast, cast.A, cast.B)
	eq(State(w, cast.A, oid), "F"); eq(State(w, cast.B, oid), "F")
	eq(Fight(cast.A, oid).mode, "L"); eq(Fight(cast.B, oid).w, "A")
	for _, c in ipairs({ cast.A, cast.B }) do
		local mine = w:As(c, c.ns.ArenaFights.MyFights, "L")
		eq(#mine, 1, c.short .. "'s own history"); eq(mine[1].fid, oid)
	end
	eq(w:As(cast.A, cast.A.ns.ArenaFights.MyFights, "L")[1].w, "W")
	eq(Fights(w, cast.A).Qualification().pointsTenths, 10, "a win at equal levels: 1 point")
	eq(Fights(w, cast.B).Qualification().pointsTenths, 0)
	W3.NoErrors(w)
end)

test("1.2.3 duels count: the mode helpers the Bones tables share (Arena.GameMode, FreeCounts); a stake or a test build is still no count", function()
	local w, cast = World123()
	local A = cast.A.ns.Arena
	eq(w:As(cast.A, A.GameMode, false, false), "L", "a free game")
	eq(w:As(cast.A, A.GameMode, true, false), "T", "a rehearsal ticked")
	eq(w:As(cast.A, A.GameMode, false, true), "T", "a wager waits for the live switch")
	eq(w:As(cast.A, A.FreeCounts), true)
	local tb = w:Client("Wenna Crale", { testBuild = { n = 3, base = "1.2.2", built = w.clock - 60, expires = w.clock + 86400 } })
	eq(w:As(tb, tb.ns.Arena.GameMode, false, false), "T", "a test build never counts")
	eq(w:As(tb, tb.ns.Arena.FreeCounts), false)
	-- A staked challenge where wagers are allowed (the dormant 2.0 paths) and the switch is off: T.
	local w2, c2 = W3.New({ live = false })
	for _, c in ipairs({ c2.A, c2.B }) do W3.Money(w2, c) end
	local oid = assert(Fights(w2, c2.A).Challenge(c2.B.name, { bo = 1, stake = 10000, how = "d", cur = "g" }))
	eq(c2.A.ns.ArenaFights.challenges[oid].mode, "T", "gold on it: the switch's word")
	W3.NoErrors(w)
end)

test("1.2.3 duels count: the wire takes a free game's types in L with the switch off (a challenge, its fight, its reports, the halves, Bones), never the rest", function()
	local w, cast = World123()
	local a, b = cast.A, cast.B
	for _, kind in ipairs({ "AS", "AF", "AC", "AW", "AR", "AX", "AB", "AQ", "KI", "KN", "KS" }) do
		eq(w:As(a, a.ns.Arena.Refusal, kind, "L", {}), nil, kind .. " goes")
	end
	for _, kind in ipairs({ "AE", "AN", "AT", "AV" }) do
		eq(w:As(a, a.ns.Arena.Refusal, kind, "L", {}), "live-off", kind .. " still waits for the switch")
	end
	eq(w:As(a, a.ns.Arena.Refusal, "KH", "L", {}), "compliance", "a stake's word: the compliance gate")
	local before = b.Arena.Stats().dropped["live-off"] or 0
	b.Arena.Inject("CHANNEL", a.name, "AF~L1~x")
	b.Arena.Inject("CHANNEL", a.name, "KN~L1~x")
	eq(b.Arena.Stats().dropped["live-off"] or 0, before, "taken in")
	b.Arena.Inject("CHANNEL", a.name, "AE~L1~x")
	eq(b.Arena.Stats().dropped["live-off"], before + 1, "an arbiter's entry is not")
	W3.NoErrors(w)
end)

print("1.2.3: the two signed halves")

test("1.2.3 two halves: both fighters' signed halves reach a third client, which counts the duel in its ledger, its rankings and the winner's record", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B, 25)
	local list = Ledger(w, sp).Entries()
	eq(#list, 1, "one entry from the two halves")
	local e = list[1]
	eq(e.fid, oid); eq(e.fl, "dr", "a duel, rated: each saw the other"); eq(e.w, "A"); eq(e.sc, "1:0"); eq(e.m, "K")
	eq(e.gkA, GK(cast.A)); eq(e.gkB, GK(cast.B)); eq(e.gkArb, nil, "no arbiter")
	eq(e.dur >= 15 and e.dur <= 25, true, "the shorter of the two clocks: " .. tostring(e.dur))
	eq(e.fA and e.fA.level, 60); eq(e.fB and e.fB.level, 60)
	local view = Ledger(w, sp).RankingView("all", "A", 1)
	eq(view.total, 2, "both fighters ranked")
	eq(view.rows[1].gk, GK(cast.A)); eq(view.rows[1].wins, 1)
	eq(Ledger(w, sp).Record(GK(cast.A)).wins, 1, "the profile's record")
	eq(Ledger(w, sp).Record(GK(cast.B)).losses, 1)
	local hist = Ledger(w, sp).History({ gk = GK(cast.A), own = true })
	eq(#hist, 1); eq(hist[1].fid, oid); eq(hist[1].direct, true)
	W3.NoErrors(w)
end)

test("1.2.3 two halves: a member who logs in soon after hears the fighters' own repeats (HALF_REPEAT, for HALF_FOR), and a fighter with the companion counts his own duel", function()
	local w, cast = World123()
	W3.Companion(w, cast.A)
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	local mine = Ledger(w, cast.A).Entries()
	eq(#mine, 1, "the fighter's own ledger"); eq(mine[1].fid, oid)
	local late = w:Client("Wenna Crale")
	W3.Rules(w, late)
	W3.Companion(w, late)
	eq(#Ledger(w, late).Entries(), 0)
	local F = cast.A.ns.ArenaFights
	w:Run(F.HALF_REPEAT + 2)
	eq(#Ledger(w, late).Entries(), 1, "both halves again")
	-- After HALF_FOR they stop (the clerk's carousel is for later logins).
	local halves = {}
	local send = cast.A.ns.Arena.Send
	cast.A.ns.Arena.Send = function(kind, ...)
		if kind == "AX" then halves[#halves + 1] = w.clock end
		return send(kind, ...)
	end
	w:Run(F.HALF_FOR)
	cast.A.ns.Arena.Send = send
	local last = halves[#halves] or 0
	eq(#halves >= 1, true, "repeated within HALF_FOR")
	eq(last - Fight(cast.A, oid).halfAt <= F.HALF_FOR, true, "never after it")
	W3.NoErrors(w)
end)

test("1.2.3 two halves: one half alone never counts (the other fighter's client published none)", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	-- (B's client publishes no half: an older Olympus, or one that refuses to sign.)
	rawset(cast.B.ns.ArenaLedger, "Publish", nil)
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	eq(State(w, cast.B, oid), "F", "the duel itself ended")
	eq(#Ledger(w, sp).Entries(), 0, "one half: nothing in the ledger")
	eq(w:As(sp, sp.ns.ArenaLedger.Pending), 1, "A's half waits for its other half")
	W3.NoErrors(w)
end)

test("1.2.3 two halves: mismatched halves never count (B signs a fled where A signs a knockout)", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local real = cast.B.ns.ArenaLedger.Publish
	cast.B.ns.ArenaLedger.Publish = function(f)
		local copy = {}
		for k, v in pairs(f) do copy[k] = v end
		copy.m = "R"
		copy.rounds = { { w = f.rounds[1].w, m = "R", dur = f.rounds[1].dur } }
		return real(copy)
	end
	Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	eq(#Ledger(w, sp).Entries(), 0, "the halves differ: nothing")
	eq((sp.ns.ArenaLedger.Stats().refused.result or 0) >= 1, true, "refused as a different result")
	W3.NoErrors(w)
end)

test("1.2.3 two halves: an alt's duel (one account key on both sides) and a half whose signature does not fit never count", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	-- The same account: both characters sign with one key (Debts.lua: one key per account).
	w:As(cast.A, cast.A.ns.Debts.MyKey)
	cast.B.db.arenaKey = cast.A.db.arenaKey
	Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	eq(#Ledger(w, sp).Entries(), 0, "one account on both sides: nothing")
	eq((sp.ns.ArenaLedger.Stats().refused.alts or 0) >= 1, true)
	-- A half changed after it was signed: its signature fails.
	local w2, c2 = World123()
	local sp2 = c2.spectator
	W3.Companion(w2, sp2)
	c2.A.onChannel = false -- (A's own half reaches nobody but B: we send its changed copy below)
	local oid = Agreed(w2, c2)
	Round(w2, c2, c2.A, c2.B)
	local body = assert(Fight(c2.A, oid).half)
	local fields = {}
	for part in (body .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = part end
	fields[12] = c2.A.ns.Arena.B36(c2.A.ns.Arena.N(fields[12]) - 1) -- (its time, a second earlier)
	c2.A.onChannel = nil
	w2:As(c2.A, c2.A.ns.Arena.Send, "AX", "L", table.concat(fields, "~"))
	w2:Run(0)
	eq(#Ledger(w2, sp2).Entries(), 0, "a changed half: nothing")
	eq((sp2.ns.ArenaLedger.Stats().refused.signature or 0) >= 1, true)
	W3.NoErrors(w)
	W3.NoErrors(w2)
end)

test("1.2.3 two halves: a member who was offline gets them from a clerk (a High Councillor), checked as the fighters' own; never from anyone else, nor with another key than its fighter's", function()
	local w, cast = World123({ more = { { "councillor", N.councillor } } })
	local clerk = cast.councillor
	W3.Companion(w, clerk)
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	eq(#Ledger(w, clerk).Entries(), 1, "the clerk heard both halves")
	-- The carousel relays a duel as its two halves, never as an entry on the clerk's word.
	local pieces = w:As(clerk, clerk.ns.ArenaLedger.Pieces, "L")
	local ax = {}
	for _, p in ipairs(pieces) do if p[1] == "AX" then ax[#ax + 1] = p[2] end end
	eq(#ax, 2, "the two halves in the carousel")
	-- A member who logs in later.
	local late = w:Client("Wenna Crale")
	W3.Rules(w, late)
	W3.Companion(w, late)
	for _, body in ipairs(ax) do w:As(clerk, clerk.ns.Arena.Send, "AX", "L", body, { to = late.name }) end
	w:Run(0)
	local list = Ledger(w, late).Entries()
	eq(#list, 1, "caught up"); eq(list[1].fid, oid); eq(list[1].w, "A")
	-- A plain member relaying them: refused.
	local other = w:Client("Idris Fold")
	W3.Rules(w, other)
	W3.Companion(w, other)
	for _, body in ipairs(ax) do w:As(cast.spectator, cast.spectator.ns.Arena.Send, "AX", "L", body, { to = other.name }) end
	w:Run(0)
	eq(#Ledger(w, other).Entries(), 0, "not from a member who is no clerk")
	eq((other.ns.ArenaLedger.Stats().refused.relay or 0) >= 2, true)
	-- A relayed half with another key than the one its fighter gave first-hand here: refused.
	local fields = {}
	for part in (ax[1] .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = part end
	local core = table.concat(fields, "~", 1, 15)
	local sig = w:As(clerk, clerk.ns.Debts.Sign, "OLYH1|" .. core)
	local _, pk = w:As(clerk, clerk.ns.Debts.MyKey)
	local forged = core .. "~" .. clerk.ns.Debts.B64(pk) .. "~" .. clerk.ns.Debts.B64(sig)
	-- (The review: a key is pinned only once its own half's signature checked. 1.2.4, the author's
	-- ask: the ledger is the core's, so a client without the companion matches and checks the halves
	-- too: the spectator, who never opened the Arena window, holds the duel and its fighters' keys
	-- already, and the forged one is refused for its key at once, "pin". It was "conflict" before:
	-- his side held, unchecked, until the companion loaded.)
	w:As(clerk, clerk.ns.Arena.Send, "AX", "L", forged, { to = cast.spectator.name })
	w:Run(0)
	eq((cast.spectator.ns.ArenaLedger.Stats().refused.pin or 0) >= 1, true, "no companion: the real key, heard first-hand")
	eq(#Ledger(w, cast.spectator).Entries(), 1, "the duel, matched without the companion")
	W3.Companion(w, cast.spectator)
	w:Run(0)
	eq(#Ledger(w, cast.spectator).Entries(), 1, "the same once it loads")
	local pins = cast.spectator.ns.ArenaLedger.Stats().refused.pin or 0
	w:As(clerk, clerk.ns.Arena.Send, "AX", "L", forged, { to = cast.spectator.name })
	w:Run(0)
	eq((cast.spectator.ns.ArenaLedger.Stats().refused.pin or 0) > pins, true, "the spectator heard the real key first-hand")
	W3.NoErrors(w)
end)

test("1.2.3 two halves: the ledger's limits apply (15 s a round, a pair's 4th duel in 7 days unrated) and the duel the other never saw is history only", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	for i = 1, 4 do
		Agreed(w, cast)
		Round(w, cast, cast.A, cast.B, 20)
		w:Run(5)
	end
	local list = Ledger(w, sp).Entries()
	eq(#list, 4)
	local counts = w:As(sp, sp.ns.ArenaLedger.Counted, list)
	local n = 0
	for _, e in ipairs(list) do if counts[e.fid] then n = n + 1 end end
	eq(n, 3, "a pair's 4th in 7 days is not rated")
	eq(Ledger(w, sp).Record(GK(cast.A)).wins, 3)
	-- (The qualification points' own limits, the triple check's bug 8: the 4th capped "pair".)
	local q = Fights(w, cast.A).Qualification()
	eq(#q, 4); eq(q.wins, 3); eq(q.pointsTenths, 30); eq(q[4].capped, "pair")
	-- A short round: in the ledger, never rated.
	local w2, c2 = World123()
	W3.Companion(w2, c2.spectator)
	Agreed(w2, c2)
	Round(w2, c2, c2.A, c2.B, 5)
	local l2 = Ledger(w2, c2.spectator).Entries()
	eq(#l2, 1); eq(w2:As(c2.spectator, c2.spectator.ns.ArenaLedger.Counted, l2)[l2[1].fid], false, "under 15 s")
	eq(Fights(w2, c2.A).Qualification()[1].capped, "short")
	-- B never saw A (no unit of A's on B's client): the entry is history only, not rated.
	local w3, c3 = World123()
	W3.Companion(w3, c3.spectator)
	c3.B.target = nil
	Agreed(w3, c3)
	Round(w3, c3, c3.A, c3.B)
	local l3 = Ledger(w3, c3.spectator).Entries()
	eq(#l3, 1); eq(l3[1].fl, "d", "not rated")
	W3.NoErrors(w)
	W3.NoErrors(w2)
	W3.NoErrors(w3)
end)

-- (The 1.2.3 clocks, with their values where a build has none: the bugs' tests also run on the
-- build they were found in, live switch on, to show each fails there.)
local function Const(t, key, v) return rawget(t, key) or v end

print("1.2.3: the triple check's bugs")

test("1.2.3 bug 3: one game duel settles exactly one fight; a second challenge between the pair does not open while one is", function()
	local w, cast = World123({ live = true })
	local oid = Agreed(w, cast)
	eq(select(2, Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 })), "busy", "the challenger's own client")
	w:Run(5)
	eq(select(2, Fights(w, cast.B).Challenge(cast.A.name, { bo = 1 })), "busy", "nor the other way")
	-- A modified client sends it anyway: the opponent answers no ("b") and the challenger hears why.
	local id = w:As(cast.A, cast.A.ns.Arena.NewId, "F", function() return false end)
	cast.A.ns.ArenaFights.challenges[id] = { oid = id, A = cast.A.name, B = cast.B.name, bo = 1, stake = 0, how = "d", state = "asked",
		t = w.clock, mode = "L" }
	w:As(cast.A, cast.A.ns.Arena.Send, "AS", "L", table.concat({ id, "X", "1", "0", "d", "-", "g" }, "~"), { to = cast.B.name, urgent = true })
	w:Run(0)
	eq(cast.A.ns.ArenaFights.challenges[id].state, "no"); eq(cast.A.ns.ArenaFights.challenges[id].why, "b")
	eq(cast.B.ns.ArenaFights.challenges[id], nil, "not kept")
	-- Two fights open between them anyway (agreed before 1.2.3): one duel settles the oldest alone.
	local open = cast.A.ns.ArenaFights.OpenDuel
	cast.A.ns.ArenaFights.OpenDuel = function() return nil end
	cast.B.ns.ArenaFights.OpenDuel = function() return nil end
	w:Run(60)
	local second = Agreed(w, cast)
	cast.A.ns.ArenaFights.OpenDuel, cast.B.ns.ArenaFights.OpenDuel = open, open
	eq(State(w, cast.A, oid), "S"); eq(State(w, cast.A, second), "S")
	Round(w, cast, cast.A, cast.B)
	for _, c in ipairs({ cast.A, cast.B }) do
		eq(State(w, c, oid), "F", c.short .. ": the oldest takes the duel")
		eq(State(w, c, second), "S", c.short .. ": the other is untouched")
		eq(#w:As(c, c.ns.ArenaFights.MyFights, "L"), 1, "one row for one duel")
	end
	eq(Fights(w, cast.A).Qualification().wins, 1)
	W3.NoErrors(w)
end)

test("1.2.3 bug 4: an agreed duel never fought is void ('late') on both clients after DIRECT_EXPIRE, and a casual duel later does not touch it; a best-of left between rounds ends no contest", function()
	local w, cast = World123({ live = true })
	local oid = Agreed(w, cast)
	local F = cast.A.ns.ArenaFights
	w:Run(Const(F, "DIRECT_EXPIRE", 1800) + 2)
	for _, c in ipairs({ cast.A, cast.B }) do
		eq(State(w, c, oid), "V", c.short); eq(Fight(c, oid).code, "late")
	end
	local sent = #w:Sent{ type = "AF" }
	w:Run(Const(F, "REPEAT_NEAR", 60) * 5)
	eq(#w:Sent{ type = "AF" } - sent, 0, "no more AF repeats once it is over")
	Round(w, cast, cast.A, cast.B)
	eq(State(w, cast.A, oid), "V", "a duel days later is not that fight")
	eq(#w:As(cast.A, F.MyFights, "L"), 1, "only its void row")
	eq(w:As(cast.A, F.MyFights, "L")[1].w, "-")
	eq(Fights(w, cast.A).OpenDuel(cast.B.name), nil, "and the pair may challenge again")
	-- A best of 3 left after its first round.
	local bo3 = Agreed(w, cast, { bo = 3 })
	Round(w, cast, cast.A, cast.B)
	eq(State(w, cast.A, bo3), "B")
	w:Run(Const(F, "DIRECT_EXPIRE", 1800) + 2)
	for _, c in ipairs({ cast.A, cast.B }) do
		eq(State(w, c, bo3), "N", c.short); eq(Fight(c, bo3).code, "late")
	end
	W3.NoErrors(w)
end)

test("1.2.3 bug 5: a lost report still ends final on both clients (resent while the other's is missing, a repeat answered), and so does a reload between the duel line and the report", function()
	local w, cast = World123({ live = true })
	local F = cast.A.ns.ArenaFights
	local oid = Agreed(w, cast)
	w:Combat(cast.A, true); w:Combat(cast.B, true)
	w:Run(20)
	-- A's report to B never arrives (the game refuses it: given up, not retried).
	w:Results(cast.A, { 2 })
	W3.Duel(w, { cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	eq(State(w, cast.A, oid), "F", "A had B's report")
	eq(State(w, cast.B, oid), "L", "B lacks A's")
	w:Run(Const(F, "AW_RESEND", 60) + 2)
	eq(State(w, cast.B, oid), "F", "B's report again, answered with A's")
	eq(Fight(cast.B, oid).w, "A")
	-- A reload at the knockout, before the report went: the record keeps it and it goes after.
	w:Combat(cast.A, false); w:Combat(cast.B, false)
	w:Run(5)
	local two = Agreed(w, cast)
	w:Combat(cast.A, true); w:Combat(cast.B, true)
	w:Run(20)
	W3.Duel(w, { cast.A, cast.B }, cast.B, cast.A)
	w:Logout(cast.B)
	w:Login(cast.B)
	W3.Rules(w, cast.B)
	w:Run(0)
	w:Run(Const(F, "AW_RESEND", 60) + 2)
	eq(State(w, cast.A, two), "F"); eq(State(w, cast.B, two), "F")
	eq(Fight(cast.A, two).w, "B"); eq(Fight(cast.B, two).w, "B")
	eq(#w:As(cast.B, F.MyFights, "L"), 2, "both duels in B's history")
	W3.NoErrors(w)
end)

test("1.2.3 bug 7: a member on the realm group's other realm: the challenge arrives where his realm's switch is off, and the winner earns his points", function()
	for _, farLive in ipairs({ false, true }) do
		-- (The King's word is our realm's: the other realm's switch is off, unless farLive, where
		-- the challenge always arrived and the points alone were refused.)
		local w, cast = World123({ live = true, more = { { "far", "Wenna Crale-" .. World.REALMS[2] } } })
		local far = cast.far
		if farLive then far.ns.ArenaRoles.Live = function() return true end end
		cast.A.target, far.target = far.name, cast.A.name
		far.globals.UnitRace = function() return "Human", "Human", 1 end
		local oid = Agreed(w, cast, { bo = 1 }, cast.A, far)
		eq(State(w, far, oid), "S", "it arrived")
		Round(w, cast, cast.A, far, 20, { a = cast.A, b = far })
		eq(State(w, cast.A, oid), "F"); eq(State(w, far, oid), "F")
		eq(Fights(w, cast.A).Qualification().pointsTenths, 10, "the group's other realm is ours too")
		W3.NoErrors(w)
	end
end)

test("1.2.3 bug 8: the qualification points keep the ledger's limits: a fighter's day (DAY_MAX) and a short round", function()
	local w, cast = World123({ live = true })
	cast.A.ns.ArenaLedger.DAY_MAX = 2
	for _ = 1, 3 do
		Agreed(w, cast)
		Round(w, cast, cast.A, cast.B, 20)
		w:Run(5)
	end
	local q = Fights(w, cast.A).Qualification()
	eq(#q, 3); eq(q.wins, 2); eq(q.pointsTenths, 20); eq(q[3].capped, "day")
	eq(q.lastWhy and q.lastWhy.why, "day", "the profile's line says why")
	W3.NoErrors(w)
end)

test("1.2.3 bug 9: each round's length runs from the fighters' combat, not from the challenge, and a best-of's next round is not 0", function()
	local w, cast = World123({ live = true })
	local oid = Agreed(w, cast, { bo = 3 })
	w:Run(600) -- (they walk to the place for ten minutes)
	Round(w, cast, cast.A, cast.B, 20)
	local f = Fight(cast.A, oid)
	eq(f.rounds[1].dur, 20)
	w:Run(30)
	Round(w, cast, cast.A, cast.B, 25)
	eq(f.rounds[2].dur, 25)
	eq(State(w, cast.A, oid), "F"); eq(f.dur, 45)
	eq(Fights(w, cast.A).Qualification().wins, 2, "each round its own record")
	W3.NoErrors(w)
end)

test("1.2.3 bug 10: an opponent seen during the duel still counts when no unit is at hand at the line; a win that earns nothing says why", function()
	local w, cast = World123({ live = true })
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B, 20, { before = function() cast.A.target = nil end })
	eq(Fights(w, cast.A).Qualification().pointsTenths, 10, "his GUID, level and guild from earlier in the duel")
	-- Never seen at all: no points, and the reason.
	local w2, c2 = World123({ live = true })
	c2.A.target = nil
	Agreed(w2, c2)
	Round(w2, c2, c2.A, c2.B)
	w2:Run(Const(c2.A.ns.ArenaFights, "QUAL_WAIT", 3) + 1)
	eq(Fights(w2, c2.A).Qualification().pointsTenths, 0)
	eq(Fights(w2, c2.A).Qualification().lastWhy.why, "unseen")
	eq(Printed(c2.A, c2.A.ns.L.ARENA_QUAL_WHY_UNSEEN), true, "the line in chat")
	eq(oid ~= nil, true)
	W3.NoErrors(w)
	W3.NoErrors(w2)
end)

test("1.2.3 bug 11: a fighter killed by something else during the duel: the round stands, for nothing (no points, no half for the rankings)", function()
	local w, cast = World123({ live = true })
	W3.Companion(w, cast.spectator)
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B, 20, { before = function() w:Fire(cast.B, "PLAYER_DEAD") end })
	w:Run(Const(cast.A.ns.ArenaFights, "QUAL_WAIT", 3) + 1)
	for _, c in ipairs({ cast.A, cast.B }) do
		eq(State(w, c, oid), "F", c.short); eq(Fight(c, oid).code, "int", c.short)
	end
	eq(Fights(w, cast.A).Qualification().pointsTenths, 0)
	eq(Fights(w, cast.A).Qualification().lastWhy.why, "int")
	eq(#Ledger(w, cast.spectator).Entries(), 0, "no half went")
	W3.NoErrors(w)
end)

test("1.2.3 bug 12: the challenger hears that a challenge went nowhere; a stake on the switch's side is answered 'live'", function()
	local w, cast = World123({ live = true })
	w:Logout(cast.B)
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	local F = cast.A.ns.ArenaFights
	eq(F.challenges[oid].state, "asked")
	w:Run(Const(F, "CHALLENGE_TIME", 60) + Const(F, "CHALLENGE_SLACK", 30) + 1)
	eq(F.challenges[oid].state, "expired")
	local toasts = w:As(cast.A, cast.A.ns.ArenaHome.Toasts)
	eq(toasts[#toasts], cast.A.ns.L.ARENA_CHALLENGE_EXPIRED:format(cast.A.ns.ArenaHome.Name(cast.B.name)), "told")
	eq(Fights(w, cast.A).OpenDuel(cast.B.name), nil, "and free to challenge again")
	-- Gold on it (the dormant 2.0 paths) where the opponent's switch is off: no, "live".
	local w2, c2 = W3.New()
	for _, c in ipairs({ c2.A, c2.B }) do W3.Money(w2, c) end
	c2.B.ns.ArenaRoles.Live = function() return false end
	local oid2 = assert(Fights(w2, c2.A).Challenge(c2.B.name, { bo = 1, stake = 10000, how = "d", cur = "g" }))
	w2:Run(0)
	eq(c2.A.ns.ArenaFights.challenges[oid2].state, "no"); eq(c2.A.ns.ArenaFights.challenges[oid2].why, "live")
	W3.NoErrors(w)
	W3.NoErrors(w2)
end)

test("1.2.3 bug 13: the words say what counts (English and pt-BR): direct duels earn points and reach the rankings; the live switch is the bets'", function()
	local function Text(path, key, which)
		local n = 0
		for line in io.lines(path) do
			local s = line:match("^%s*L%." .. key .. " = (\".*\")%s*$")
			if s then
				n = n + 1
				if n == which then return assert(loadstring("return " .. s))() end
			end
		end
		error("no " .. key .. " " .. which)
	end
	local ui, home, net = H.ARENA_DIR .. "Locales/UIText.lua", H.ADDON_DIR .. "Locales/ArenaHomeText.lua", H.ADDON_DIR .. "Locales/ArenaNetText.lua"
	for which = 1, 2 do
		local free = Text(ui, "ARENA_HOWTO_FREE_WORKS_1", which)
		eq(free:find("do not earn", 1, true) or free:find("não contam para os pontos", 1, true), nil, "no 'direct duels earn nothing'")
		eq((free:find("rankings", 1, true) or free:find("ranking", 1, true)) ~= nil, true)
		local works = Text(ui, "ARENA_HOWTO_WORKS_1", which)
		eq(works:find("Only qualifying duels judged", 1, true) or works:find("Só duelos elegíveis julgados", 1, true), nil)
		local three = Text(ui, "ARENA_HOWTO_WORKS_3", which)
		eq(three:find("Qualification points rank", 1, true) or three:find("Os pontos de qualificação ordenam", 1, true), nil)
		local off = Text(net, "ARENA_LIVE_OFF", which)
		eq(off:find("rehearsal only", 1, true) or off:find("só ensaio", 1, true), nil)
		local tab = Text(home, "ARENA_TAB_LIVE_OFF", which)
		eq(tab:find("rehearsals", 1, true) or tab:find("ensaios", 1, true), nil, "events no longer run as rehearsals")
	end
end)

-- (1.2.3, the review of v123/duels: three reviewers' findings, each test failing on that branch's
-- 44e582e and on e04dd45.)
print("1.2.3: the review of the duels")

-- A half as a modified client makes it: the fields given, signed with the sender's own account key
-- (Debts.lua's, as LG.Publish signs). o: { fid, side, gkA, A, gkB, B, bo, w, m, dur, t, lvl, opp }.
local function Forge(w, c, o)
	local A = c.ns.Arena
	local m = o.m or "K"
	local core = table.concat({ o.fid, o.side, o.gkA, o.A, o.gkB, o.B, tostring(o.bo or 1), o.cat or "A", o.w, m,
		o.rounds or (o.w .. m .. A.B36(o.dur or 20)), A.B36(o.t or w.clock), o.facts or "-", o.lvl or "60", o.opp or "60" }, "~")
	local sig = w:As(c, c.ns.Debts.Sign, "OLYH1|" .. core)
	local _, pk = w:As(c, c.ns.Debts.MyKey)
	return core .. "~" .. c.ns.Debts.B64(pk) .. "~" .. c.ns.Debts.B64(sig)
end
-- A half sent as that client sends it: on the channel, or whispered to `to`.
local function SendHalf(w, c, body, to)
	assert(w:As(c, c.ns.Arena.Send, "AX", "L", body, { to = to and to.name or nil }))
	w:Run(0)
end
-- A fake duel between a and b, each half signed and sent by its own fighter (two modified clients):
-- o as Forge's, its sides' names and gks a's and b's own unless o says otherwise.
local function FakeDuel(w, a, b, o, to)
	local f = {}
	for k, v in pairs(o) do f[k] = v end
	f.A, f.B = f.A or a.name, f.B or b.name
	f.gkA, f.gkB = f.gkA or GK(a), f.gkB or GK(b)
	f.side = "A"
	local ha = Forge(w, a, f)
	f.side = "B"
	local hb = Forge(w, b, f)
	SendHalf(w, a, ha, to)
	SendHalf(w, b, hb, to)
	return ha, hb
end
local function Refused(c, why) return c.ns.ArenaLedger.Stats().refused[why] or 0 end
-- The game knows nobody on this client (GetPlayerInfoByGUID gives nothing yet).
local function Unknown(c) c.globals.GetPlayerInfoByGUID = function() return nil end end

test("1.2.3 review: a best of 3 free duel with the live switch off reaches a third client (its halves go as EP pieces), and a piece's inner type still asks for the switch", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local oid = Agreed(w, cast, { bo = 3 })
	Round(w, cast, cast.A, cast.B, 25)
	w:Run(30)
	Round(w, cast, cast.A, cast.B, 25)
	w:Run(5)
	eq(State(w, cast.A, oid), "F"); eq(State(w, cast.B, oid), "F")
	eq(#Fight(cast.A, oid).half > 240, true, "a best of 3's half is longer than one message's room")
	eq(#w:Sent{ from = cast.A, type = "EP" } >= 2, true, "so it went as pieces")
	local list = Ledger(w, sp).Entries()
	eq(#list, 1, "the third client has it"); eq(list[1].fid, oid); eq(list[1].sc, "2:0"); eq(list[1].fl, "dr")
	eq(sp.ns.Arena.Stats().dropped["live-off"], nil, "nothing dropped as live-off")
	-- Pieces of a type that waits for the switch (an arbiter's AE): whole, then dropped by its own wrapper.
	local before = sp.ns.Arena.Stats()
	local assembled, off = before.assembled, before.dropped["live-off"] or 0
	local whole = "AE~L1~" .. ("x"):rep(300)
	sp.ns.Arena.Inject("CHANNEL", cast.A.name, ("EP~L1~zz1~1~2~%s"):format(whole:sub(1, 200)))
	sp.ns.Arena.Inject("CHANNEL", cast.A.name, ("EP~L1~zz1~2~2~%s"):format(whole:sub(201)))
	local after = sp.ns.Arena.Stats()
	eq(after.assembled, assembled + 1, "the pieces were put together")
	eq(after.dropped["live-off"], off + 1, "and the AE inside them still waits for the switch")
	W3.NoErrors(w)
end)

test("1.2.3 review: a fighter whose client reads the other's level as ?? (-1) at the line: his half names none, and the duel is in a third client's history, not rated", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local oid = Agreed(w, cast)
	-- (B's client: A's unit shows ?? once the duel is on, the game's skull for a hostile character
	-- 10 or more levels above.)
	local base = cast.B.globals.UnitLevel
	cast.B.globals.UnitLevel = function(unit) if unit == "player" then return base(unit) end return -1 end
	Round(w, cast, cast.A, cast.B, 25)
	local fields = {}
	for part in (assert(Fight(cast.B, oid).half) .. "~"):gmatch("([^~]*)~") do fields[#fields + 1] = part end
	eq(fields[15], "-", "B's half names no level for A")
	local list = Ledger(w, sp).Entries()
	eq(#list, 1, "in the history"); eq(list[1].fl, "d", "not rated: B never saw A's level")
	eq(Refused(sp, "level"), 0)
	W3.NoErrors(w)
end)

test("1.2.3 review: a creature's fight that ends 20 s before the duel is not the duel's clock; the two clocks agree and the duel counts", function()
	local w, cast = World123()
	local sp = cast.spectator
	W3.Companion(w, sp)
	local oid = Agreed(w, cast)
	w:Combat(cast.B, true); w:Run(40); w:Combat(cast.B, false); w:Run(20)
	Round(w, cast, cast.A, cast.B, 25)
	eq(Fight(cast.A, oid).reports[1].A.dur, 25)
	eq(Fight(cast.B, oid).reports[1].B.dur, 25, "B's clock started again with the duel")
	local list = Ledger(w, sp).Entries()
	eq(#list, 1); eq(list[1].dur, 25); eq(Refused(sp, "times"), 0)
	-- A combat that flickers inside the duel (dropped and taken again within COMBAT_GAP) keeps it.
	local two = Agreed(w, cast)
	w:Combat(cast.A, true); w:Combat(cast.B, true)
	w:Run(10)
	w:Combat(cast.A, false); w:Combat(cast.B, false)
	w:Run(cast.A.ns.ArenaFights.COMBAT_GAP - 1)
	Round(w, cast, cast.A, cast.B, 10)
	eq(Fight(cast.A, two).reports[1].A.dur, 10 + cast.A.ns.ArenaFights.COMBAT_GAP - 1 + 10)
	W3.NoErrors(w)
end)

test("1.2.3 review: a challenger who reloads before the yes (his AF never comes) keeps the pair busy only for the yes's short wait, not 30 minutes", function()
	local w, cast = World123()
	local F = cast.A.ns.ArenaFights
	local oid = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	w:Logout(cast.A)
	w:Login(cast.A)
	W3.Rules(w, cast.A)
	assert(Fights(w, cast.B).Answer(oid, true))
	w:Run(5)
	eq(Fight(cast.B, oid), nil, "no fight on B's side: A's client no longer knew the challenge")
	eq(select(2, Fights(w, cast.B).CanChallenge(cast.A.name, {})), "busy", "the yes still waits for A's AF")
	w:Run(F.CHALLENGE_TIME + F.CHALLENGE_SLACK)
	eq(Fights(w, cast.B).CanChallenge(cast.A.name, {}), true, "B is free again")
	local again = assert(Fights(w, cast.A).Challenge(cast.B.name, { bo = 1 }))
	w:Run(0)
	eq(cast.A.ns.ArenaFights.challenges[again].state, "asked", "A's new challenge is not answered busy")
	assert(Fights(w, cast.B).Answer(again, true))
	w:Run(0)
	eq(State(w, cast.B, again), "S", "and it makes the fight")
	W3.NoErrors(w)
end)

test("1.2.3 review: a clerk who logs in after the fighters' repeats still gets their duel (each fighter's own half to him), and a member after him from his carousel", function()
	local w, cast = World123()
	local F = cast.A.ns.ArenaFights
	local oid = Agreed(w, cast)
	Round(w, cast, cast.A, cast.B)
	w:Run(F.HALF_FOR + 3600) -- (no clerk online: nobody keeps it for later logins)
	local clerk = w:Client(N.councillor)
	W3.Rules(w, clerk)
	W3.Companion(w, clerk)
	w:Run(cast.A.ns.ArenaLedger.CLERK_WAIT + 120)
	local list = Ledger(w, clerk).Entries()
	eq(#list, 1, "the fighters' own halves reached the clerk"); eq(list[1] and list[1].fid, oid); eq(list[1] and list[1].fl, "dr")
	local late = w:Client("Idris Fold")
	W3.Rules(w, late)
	W3.Companion(w, late)
	w:Run(cast.A.ns.ArenaLedger.CAROUSEL_GAP + 600)
	eq(#Ledger(w, late).Entries(), 1, "and the clerk's carousel brought it to a later member")
	-- (A fighter's own half goes to a clerk once a session, and never past HALF_LATE.)
	local sent = #w:Sent{ from = cast.A, type = "AX" }
	w:Run(cast.A.ns.ArenaLedger.DIGEST_EVERY + 200)
	eq(#w:Sent{ from = cast.A, type = "AX" }, sent, "not again to the same clerk")
	W3.NoErrors(w)
end)

test("1.2.3 review: two modified clients writing a duel onto another member's GUID: refused where the game knows him, history only (never rated) where it does not yet, gone once it does", function()
	local w, cast = World123({ more = { { "C", N.bettor2 }, { "D", N.bettor3 } } })
	local sp, C, D, victim = cast.spectator, cast.C, cast.D, cast.A
	W3.Companion(w, sp)
	-- C writes himself as side A with the victim's gk; D signs the other half; D wins.
	FakeDuel(w, C, D, { fid = "Fzz1", gkA = GK(victim), w = "B", dur = 20 })
	eq(#Ledger(w, sp).Entries(), 0, "the game gives that GUID another character: refused")
	eq(Refused(sp, "gk") >= 1, true)
	eq(Ledger(w, sp).Record(GK(victim)).losses, 0)
	-- Where the game knows nobody yet: kept for the history alone, never rated.
	local w2, c2 = World123({ info = false, more = { { "C", N.bettor2 }, { "D", N.bettor3 } } })
	local sp2, victim2 = c2.spectator, c2.A
	W3.Companion(w2, sp2)
	FakeDuel(w2, c2.C, c2.D, { fid = "Fzz1", gkA = GK(victim2), w = "B", dur = 20 })
	local list = Ledger(w2, sp2).Entries()
	eq(#list, 1); eq(list[1].fl, "d", "not rated"); eq(list[1].wait, "r")
	eq(Ledger(w2, sp2).Record(GK(victim2)).losses, 0, "the victim's record stays empty")
	eq(#Ledger(w2, sp2).RankingView("all", "A", 1).rows, 0, "nobody ranked")
	-- The game answers later: that GUID is the victim's, so the entry goes.
	Info(w2, sp2)
	w2:Run(sp2.ns.ArenaLedger.GK_RECHECK + 1)
	eq(#Ledger(w2, sp2).Entries(), 0, "gone once the game names its GUID's character")
	-- An honest duel heard where the game knows nobody yet: history first, rated once it does.
	local w3, c3 = World123()
	local sp3 = c3.spectator
	W3.Companion(w3, sp3)
	Unknown(sp3)
	Agreed(w3, c3)
	Round(w3, c3, c3.A, c3.B)
	eq(Ledger(w3, sp3).Entries()[1].fl, "d", "not rated yet")
	eq(Ledger(w3, sp3).Record(GK(c3.A)).wins, 0)
	Info(w3, sp3)
	w3:Run(sp3.ns.ArenaLedger.GK_RECHECK + 1)
	eq(Ledger(w3, sp3).Entries()[1].fl, "dr", "rated once the game pairs both")
	eq(Ledger(w3, sp3).Record(GK(c3.A)).wins, 1)
	W3.NoErrors(w)
	W3.NoErrors(w2)
	W3.NoErrors(w3)
end)

test("1.2.3 review: halves dated earlier and sent later never push a fighter's counted duel out of the day's limit, and a first-hand half from the past is refused", function()
	local w, cast = World123({ more = { { "C", N.bettor2 } } })
	local sp, A, B, C = cast.spectator, cast.A, cast.B, cast.C
	W3.Companion(w, sp)
	sp.ns.ArenaLedger.DAY_MAX = 2 -- (a smaller real cap: stands for 10)
	local real = Agreed(w, cast)
	Round(w, cast, A, B, 25)
	eq(Ledger(w, sp).Record(GK(A)).wins, 1, "A's real win counts")
	w:Run(60)
	-- B, the loser, and a friend: two duels dated 15 and 20 minutes before the real one.
	FakeDuel(w, C, B, { fid = "Fzz2", w = "B", t = w.clock - 20 * 60 })
	FakeDuel(w, C, B, { fid = "Fzz3", w = "B", t = w.clock - 15 * 60 })
	local list = Ledger(w, sp).Entries()
	eq(#list, 3)
	local counts = w:As(sp, sp.ns.ArenaLedger.Counted, list)
	eq(counts[real], true, "the real duel, kept first, keeps its place")
	eq(Ledger(w, sp).Record(GK(A)).wins, 1, "B did not erase his loss")
	eq(counts.Fzz2 and counts.Fzz3, false, "one of them is past B's day")
	-- A first-hand half older than the fighters' repeats: refused ("late"); a clerk takes it up to HALF_LATE.
	local LG = sp.ns.ArenaLedger
	FakeDuel(w, C, B, { fid = "Fzz4", w = "B", t = w.clock - LG.HalfFresh() - 60 })
	eq(#Ledger(w, sp).Entries(), 3, "not kept")
	eq(Refused(sp, "late") >= 2, true)
	W3.NoErrors(w)
end)

test("1.2.3 review: a pair naming a new made-up GUID for every duel cannot fill the book: a day's duel entries are counted per fighter's name and key", function()
	local w, cast = World123({ more = { { "C", N.bettor2 }, { "D", N.bettor3 } } })
	local sp, C, D = cast.spectator, cast.C, cast.D
	W3.Companion(w, sp)
	sp.ns.ArenaLedger.DUEL_KEEP_DAY = 3 -- (a smaller real cap: stands for 30)
	for i = 1, 5 do
		local A = C.ns.Arena
		FakeDuel(w, C, D, { fid = "Fmint" .. i, w = "A", dur = 20, gkA = A.GK(("Player-4999-00ABC%03X"):format(i)),
			gkB = A.GK(("Player-4999-00DEF%03X"):format(i)) })
	end
	eq(#Ledger(w, sp).Entries(), 3, "DUEL_KEEP_DAY a day for those two names")
	eq(Refused(sp, "duel-day"), 2)
	W3.NoErrors(w)
end)

test("1.2.3 review: a made-up half never blocks a late member's catch-up: no key pinned from an unchecked half, and every pair of a fight's halves is tried", function()
	for _, how in ipairs({ "pin", "slots", "full" }) do
		local w, cast = World123({ more = { { "councillor", N.councillor }, { "C", N.bettor2 } } })
		local clerk, C = cast.councillor, cast.C
		W3.Companion(w, clerk)
		local oid = Agreed(w, cast)
		Round(w, cast, cast.A, cast.B)
		local ax = {}
		for _, p in ipairs(w:As(clerk, clerk.ns.ArenaLedger.Pieces, "L")) do if p[1] == "AX" then ax[#ax + 1] = p[2] end end
		eq(#ax, 2)
		local late = w:Client("Idris Fold")
		Unknown(late)
		W3.Rules(w, late)
		W3.Companion(w, late)
		if how == "pin" then
			-- C names himself side A of another fight with Torvin's gk (the game here knows nobody yet).
			SendHalf(w, C, Forge(w, C, { fid = "Fzz5", side = "A", A = C.name, gkA = GK(cast.A), B = cast.spectator.name, gkB = GK(cast.spectator), w = "A" }), late)
		elseif how == "slots" then
			-- C takes both sides of the real fight's id first: himself as A against Selka, and as B against Torvin.
			SendHalf(w, C, Forge(w, C, { fid = oid, side = "A", A = C.name, gkA = GK(C), B = cast.B.name, gkB = GK(cast.B), w = "A" }), late)
			SendHalf(w, C, Forge(w, C, { fid = oid, side = "B", A = cast.A.name, gkA = GK(cast.A), B = C.name, gkB = GK(C), w = "A" }), late)
		else
			-- As many characters as a side has room for (HALF_CANDIDATES), each naming himself its side A.
			local names = { "Doran Pike", "Mirel Ash", "Tobin Reed", "Ysa Lorn", "Garet Moss", "Hollis Fenwick" }
			for i = 1, late.ns.ArenaLedger.HALF_CANDIDATES do
				local x = i == 1 and C or w:Client(names[i - 1])
				W3.Rules(w, x)
				SendHalf(w, x, Forge(w, x, { fid = oid, side = "A", A = x.name, gkA = GK(x), B = cast.B.name, gkB = GK(cast.B), w = "A" }), late)
			end
		end
		for _, body in ipairs(ax) do w:As(clerk, clerk.ns.Arena.Send, "AX", "L", body, { to = late.name }) end
		w:Run(0)
		local list = Ledger(w, late).Entries()
		eq(#list, 1, how .. ": the real duel caught up"); eq(list[1] and list[1].fid, oid); eq(list[1] and list[1].w, "A")
		eq(Refused(late, "pin"), 0, how); eq(Refused(late, "conflict"), 0, how)
		W3.NoErrors(w)
	end
end)

test("1.2.3 review: with the live switch off and no arbiters, a clerk's carousel piece carrying an arbiter's entry is refused", function()
	local w, cast = World123({ more = { { "councillor", N.councillor } } })
	local sp, hc = cast.spectator, cast.councillor
	W3.Companion(w, sp)
	local LG, A = hc.ns.ArenaLedger, hc.ns.Arena
	local e = { season = 1, fid = "Fab1", t = w.clock, cat = "A", bo = 1, gkA = GK(cast.A), A = cast.A.name, gkB = GK(cast.B), B = cast.B.name,
		sc = "1:0", w = "A", m = "K", dur = 60, gkArb = A.GK("Player-4999-00ABCDEF"), fl = "r" }
	local text = w:As(hc, LG.Encode, e):gsub("^[^~]*~", "", 1)
	assert(w:As(hc, A.Send, "AB", "L", table.concat({ "P", A.B36(1), A.B36(0), "1", "1", text }, "~")))
	w:Run(0)
	eq(#Ledger(w, sp).Entries(), 0, "no arbiter's entry while there are none")
	eq(Ledger(w, sp).Record(GK(cast.A)).wins, 0)
	eq(Refused(sp, "live-off"), 1)
	W3.NoErrors(w)
end)

test("1.2.3 review: ArenaProfile.VerifyGk reads WoW: Forever's GetPlayerInfoByGUID as Debts.InfoName does (the surname where the realm goes)", function()
	local w, cast = World123()
	local sp, A = cast.spectator, cast.A
	sp.ns.splitNames = true
	local first, surname = A.short:match("^(%S+) (%S+)$")
	sp.globals.GetPlayerInfoByGUID = function(guid) if guid == A.guid then return "Warrior", "WARRIOR", "Human", "Human", 2, first, surname end end
	eq(w:As(sp, sp.ns.ArenaProfile.VerifyGk, A.name, GK(A)), true, "First + Surname is the fighter")
	eq(w:As(sp, sp.ns.ArenaProfile.VerifyGk, cast.B.name, GK(A)), false, "and nobody else")
	-- A realm of ours stays a realm.
	sp.globals.GetPlayerInfoByGUID = function(guid) if guid == A.guid then return "Warrior", "WARRIOR", "Human", "Human", 2, A.short, World.REALMS[2] end end
	eq(w:As(sp, sp.ns.ArenaProfile.VerifyGk, A.short .. "-" .. World.REALMS[2], GK(A)), true)
	sp.ns.splitNames = nil
	W3.NoErrors(w)
end)

-- 1.2.3, the Bones ranking (Olympus/FarkleTable.lua's Best, ArenaHome's Data.GamesRanking("bones"),
-- the honours' source): before 1.2.3 Data.GamesRanking("bones") called FarkleTable.Best, which did
-- not exist, so the list was always empty. The owner's decisions for 1.2.3: a free game (no gold,
-- the only kind 1.2.x allows) always counts for the history and the ranking, whatever the King's
-- live switch, and a test build's never (decision 1); a game counts for everyone's ranking only when
-- both players' clients reported the same result, each its own half (the duels' two halves,
-- decision 2), with the ledger's caps and the alt check. Halves travel as the table's end (KN "e"
-- with the result) on the channel and to the other player, and again after a later login.
-- On the release's gate (compliance "shipped"), the test world (tests/arena/lib/world.lua) with the
-- table's additions (tests/arena/lib/farkle-world.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES
local P1, P2, VIEWER = N.fighterA, N.fighterB, N.bettor3
local P3, P4 = N.bettor1, N.bettor2

local function Get(c, id) return c.ns.FarkleTable.Get(id) end
local function Do(w, c, fn, ...) return w:As(c, c.ns.FarkleTable[fn], ...) end
local function Best(w, c, opts) return Do(w, c, "Best", "L", opts) end
local function Row(rows, c)
	for _, r in ipairs(rows) do if r.key == c.name:lower() then return r end end
	return nil
end
local function Order(rows)
	local out = {}
	for _, r in ipairs(rows) do out[#out + 1] = r.name:gsub("%-.*$", "") end
	return table.concat(out, ", ")
end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

local function Setup(o)
	o = o or {}
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(P1, o.whereA)
	local b = w:Player(P2, o.whereB)
	local c = w:Player(VIEWER)
	w:Group({ a, b })
	return w, a, b, c
end
-- A table as members make it (the default settings), played 20 s, then the host concedes: the
-- guest wins. Returns its id.
local function PlayConceded(w, host, guest)
	local id = assert(Do(w, host, "Create", { guest = guest.name, target = 2000 }))
	w:Run(0)
	assert(Do(w, guest, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(host.name, 90); w:QueueRoll(guest.name, 10)
	Do(w, host, "Roll", id); Do(w, guest, "Roll", id)
	w:Run(20)
	assert(Do(w, host, "Concede", id))
	w:Run(0)
	eq(Get(host, id).game.over, true); eq(Get(guest, id).game.winner, 2)
	return id
end
-- A player's half of a game as his client says it (the end's KN with the result), crafted: o =
-- { id, p1, p2 (clients), w ("1"|"2"), s1, s2, how, steps, hash, t, dur }, sent by `from`.
local function Half(w, from, o)
	local B36 = from.ns.Arena.B36
	local body = ("%s~%s~%s~-~2~-~e~%s~%s~%s~%s~%s~%s~%s~%s"):format(o.id, o.p1.name, o.p2.name, o.w or "1", B36(o.s1 or 2000), B36(o.s2 or 300),
		o.how or "t", B36(o.steps or 40), o.hash or "0a1b2c3d", B36(o.t or w.clock), B36(o.dur or 300))
	assert(w:As(from, from.ns.Arena.Send, "KN", "T", body, {}))
	w:Run(0)
end
-- Both players' halves of one game, agreeing.
local function Game(w, o)
	Half(w, o.p1, o)
	Half(w, o.p2, o)
end

print("1.2.3: the Bones ranking")

test("1.2.3 Bones ranking: a free game between two members counts: each player's half on the channel and to the other; a member ranks both, Data.GamesRanking(\"bones\") gives it, and its record is the live realm's", function()
	local w, a, b, c = Setup()
	local id = PlayConceded(w, a, b)
	-- (the Games tab's list, as the screens read it: empty before 1.2.3 whatever was played)
	local list = w:As(c, c.ns.ArenaHome.Data.GamesRanking, "bones")
	eq(#list, 2, "the Games tab's Bones ranking")
	eq(list[1].name:lower(), b.name:lower()); eq(list[1].won, 1); eq(list[1].games, 1)
	for _, p in ipairs({ a, b }) do
		eq(Do(w, p, "Counted", id), true, "decision 1: the free game counts, the live switch off")
		local other = p == a and b or a
		local ch = w:Sent({ from = p, type = "KN", dist = "CHANNEL" })
		local last = ch[#ch].msg
		assert(last:find("~e~2~", 1, true), last)
		local f = {}
		for part in (last:match("^KN~T%d+~(.*)$") .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
		eq(#f, 15, "the end's eight fields and the result")
		eq(#w:Sent({ from = p, type = "KN", dist = "WHISPER", to = other.name }), 1, "told the other player for sure")
		-- (its record counts: the games' ledger's and Bones's own, the live realm's, no rehearsal's)
		eq(w:As(p, p.ns.ArenaLedger.MyGames)[1].mode, "L")
		eq(Do(w, p, "MyGames")[1].reh, nil)
	end
	for _, viewer in ipairs({ c, a, b }) do
		local rows = Best(w, viewer)
		eq(#rows, 2, viewer.name)
		eq(Order(rows), "Selka Drummond, Torvin Hale")
		eq(Row(rows, b).won, 1); eq(Row(rows, b).games, 1); eq(Row(rows, b).place, 1)
		eq(Row(rows, a).won, 0); eq(Row(rows, a).lost, 1); eq(Row(rows, a).place, 2)
	end
	eq(#Best(w, c,{ month = w:As(c, c.ns.Honors.MonthOf, w.clock) - 1 }), 0, "nothing last month")
	NoErrors(w)
end)

-- (The live record kept no start before 1.2.3: a reloaded client said the game lasted 0 s, and
-- with both players reloaded the ledger's minimum length refused every such game.)
test("1.2.3 Bones ranking: both players /reload mid-game; the game they finish still counts, its length the whole game's", function()
	local w, a, b, c = Setup()
	local id = assert(Do(w, a, "Create", { guest = b.name, target = 2000 }))
	w:Run(0)
	assert(Do(w, b, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Do(w, a, "Roll", id); Do(w, b, "Roll", id)
	w:Run(20)
	for _, p in ipairs({ a, b }) do
		w:Logout(p); w:Login(p)
		w:Group({ a, b })
	end
	w:Run(0)
	eq(Get(a, id).state, "play"); eq(Get(b, id).state, "play")
	assert(Do(w, a, "Concede", id))
	w:Run(0)
	eq(Get(b, id).game.winner, 2)
	for _, p in ipairs({ a, b }) do
		local h = Do(w, c, "Halves", id)[1].by[p.name:lower()]
		assert(h and h.dur >= 20, p.name .. "'s half says the game's whole length: " .. tostring(h and h.dur))
		assert(w:As(p, p.ns.ArenaLedger.MyGames)[1].dur >= 20, "the games' ledger's length too")
	end
	local rows = Best(w, c)
	eq(#rows, 2); eq(Row(rows, b).won, 1)
	NoErrors(w)
end)

test("1.2.3 Bones ranking: a test build's game never counts: no half from it, so its opponent's alone ranks nothing; its record stays a rehearsal's", function()
	local tb = { n = 3, base = "1.2.3", built = H.World.CLOCK - 60, expires = H.World.CLOCK + 86400 }
	local w, a, b, c = Setup({ whereA = { testBuild = tb } })
	assert(w:As(a, a.ns.Arena.TestBuild), "a runs a test build")
	local id = PlayConceded(w, a, b)
	eq(Do(w, a, "Counted", id), false, "a test build never counts")
	-- (a test build announces its table to its party alone, never on the channel, and has no half)
	eq(#w:Sent({ from = a, type = "KN", dist = "CHANNEL" }), 0, "nothing of the test build's on the channel")
	eq(#w:Sent({ from = a, type = "KN", dist = "WHISPER" }), 0, "no half from the test build")
	for _, s in ipairs(w:Sent({ from = a, type = "KN" })) do
		local n = 0
		for _ in (s.msg .. "~"):gmatch("([^~]*)~") do n = n + 1 end
		assert(n <= 11, "the test build's notice carries no result: " .. s.msg)
	end
	eq(w:As(a, a.ns.ArenaLedger.MyGames)[1].mode, "T", "its record a rehearsal's")
	eq(#w:Sent({ from = b, type = "KN", dist = "CHANNEL" }), 2, "the release player's notice and half")
	eq(#Best(w, c), 0, "one half alone ranks nothing")
	eq(#Best(w, b), 0)
	NoErrors(w)
end)

test("1.2.3 Bones ranking: one half alone, a half from someone not at the game, halves that differ or end far apart never count; the halves that agree do", function()
	local w, a, b, c = Setup()
	local x = w:Player(P3)
	Half(w, a, { id = "Kone", p1 = a, p2 = b, w = "1" })
	eq(#Best(w, c), 0, "one half")
	-- a member not at the game speaks for b: not taken
	Half(w, x, { id = "Kone", p1 = a, p2 = b, w = "1" })
	local held = Do(w, c, "Halves", "Kone")
	eq(#held, 1); eq(held[1].by[x.name:lower()], nil); eq(held[1].by[b.name:lower()], nil)
	eq(#Best(w, c), 0)
	-- b says he won: they differ
	Half(w, b, { id = "Kone", p1 = a, p2 = b, w = "2" })
	eq(Do(w, c, "Halves", "Kone")[1].agreed, false)
	eq(#Best(w, c), 0, "halves that differ")
	-- other scores, or another transcript, differ too
	Half(w, b, { id = "Kone", p1 = a, p2 = b, w = "1", s2 = 350 })
	eq(#Best(w, c), 0, "other scores")
	Half(w, b, { id = "Kone", p1 = a, p2 = b, w = "1", hash = "ffffffff" })
	eq(#Best(w, c), 0, "another transcript")
	-- his later word, the same as a's: it counts
	Half(w, b, { id = "Kone", p1 = a, p2 = b, w = "1" })
	eq(Do(w, c, "Halves", "Kone")[1].agreed, true)
	local rows = Best(w, c)
	eq(Order(rows), "Torvin Hale, Selka Drummond"); eq(Row(rows, a).won, 1)
	-- ends more than HALF_SKEW apart: not one game
	Half(w, a, { id = "Ktwo", p1 = a, p2 = b, w = "1", t = w.clock - 1000 })
	Half(w, b, { id = "Ktwo", p1 = a, p2 = b, w = "1", t = w.clock })
	eq(Row(Best(w, c), a).won, 1, "the far-apart game is not counted")
	-- the same id with other seats is another game, which never spoils the agreed one
	Half(w, x, { id = "Kone", p1 = x, p2 = b, w = "1" })
	eq(Row(Best(w, c), a).won, 1)
	eq(#Do(w, c, "Halves", "Kone"), 2)
	-- a void game, or a time ahead of the clock, is no half
	Half(w, a, { id = "Kthree", p1 = a, p2 = b, w = "1", how = "v" })
	Half(w, a, { id = "Kfour", p1 = a, p2 = b, w = "1", t = w.clock + 3600 })
	eq(#Do(w, c, "Halves", "Kthree"), 0); eq(#Do(w, c, "Halves", "Kfour"), 0)
	NoErrors(w)
end)

test("1.2.3 Bones ranking: the ledger's caps, in time order: a game under the minimum length, a pair past its games in PAIR_DAYS, a player past his in a day never count; most wins first, a tie to fewer games", function()
	local w, a, b, c = Setup()
	local d, e = w:Player(P3), w:Player(P4)
	-- (smaller real caps on the member's client: ArenaLedger's own, which Best reads)
	c.ns.ArenaLedger.DAY_MAX, c.ns.ArenaLedger.PAIR_MAX = 2, 2
	local today = math.floor(w.clock / 86400) * 86400 + 3600
	local yesterday = today - 86400
	Game(w, { id = "Kg0", p1 = a, p2 = b, w = "1", t = yesterday })            -- counted (a-b: 1)
	Game(w, { id = "Kg1", p1 = a, p2 = b, w = "1", t = today, dur = 10 })      -- too short
	Game(w, { id = "Kg2", p1 = a, p2 = b, w = "2", t = today + 100 })          -- counted (a-b: 2)
	Game(w, { id = "Kg3", p1 = a, p2 = b, w = "1", t = today + 200 })          -- the pair's third in 7 days
	Game(w, { id = "Kg5", p1 = a, p2 = d, w = "1", t = today + 300 })          -- counted (a today: 2)
	Game(w, { id = "Kg6", p1 = d, p2 = e, w = "2", t = today + 400 })          -- counted
	Game(w, { id = "Kg7", p1 = a, p2 = e, w = "1", t = today + 500 })          -- a's third today
	local rows = Best(w, c)
	eq(Order(rows), "Torvin Hale, Parric Stowe, Selka Drummond, Lida Fenn")
	eq(Row(rows, a).won, 2); eq(Row(rows, a).games, 3)
	eq(Row(rows, e).won, 1); eq(Row(rows, e).games, 1, "Kg7 not counted")
	eq(Row(rows, b).won, 1); eq(Row(rows, b).games, 2, "Kg1 and Kg3 not counted")
	eq(Row(rows, d).won, 0); eq(Row(rows, d).games, 2)
	for i, r in ipairs(rows) do eq(r.place, i) end
	NoErrors(w)
end)

test("1.2.3 Bones ranking: a tie in wins and games goes to who reached his wins first; a game of last month is that month's; never one owner's characters (the alt check)", function()
	local w, a, b, c = Setup()
	local d, e = w:Player(P3), w:Player(P4)
	local now = w.clock
	Game(w, { id = "Kt1", p1 = b, p2 = d, w = "1", t = now - 7200 })
	Game(w, { id = "Kt2", p1 = a, p2 = e, w = "1", t = now - 3600 })
	eq(Order(Best(w, c)), "Selka Drummond, Torvin Hale, Lida Fenn, Parric Stowe", "b reached one win before a")
	local last = w:As(c, c.ns.Honors.MonthOf, now) - 1
	Game(w, { id = "Kt3", p1 = a, p2 = b, w = "1", t = now - 25 * 86400 })
	eq(#Best(w, c), 4, "last month's game is not this month's")
	local old = Best(w, c, { month = last })
	eq(Order(old), "Torvin Hale, Selka Drummond")
	-- a and e are one player's characters (each said so on the channel: Alts' AL, both ways)
	local at = w.clock
	w:As(c, c.ns.Alts.Handle, "CHANNEL", a.name, ("AL~%d~M~%s~%s"):format(at, H.World.GUILD, e.short))
	w:As(c, c.ns.Alts.Handle, "CHANNEL", e.name, ("AL~%d~A~%s~%s"):format(at, H.World.GUILD, a.short))
	eq(w:As(c, c.ns.Debts.SameOwner, a.name, e.name), true, "linked on the member's client")
	w:Run(61) -- (the list worked out again: a minute at most)
	local rows = Best(w, c)
	eq(Row(rows, a), nil, "his only game this month was against his own alt")
	eq(Row(rows, e), nil)
	eq(Order(rows), "Selka Drummond, Lida Fenn")
	NoErrors(w)
end)

test("1.2.3 Bones ranking: one sender opens HALVES_FIRST_DAY games a day at most on a member's client; the halves of those he opened still count", function()
	local w, a, b, c = Setup()
	c.ns.FarkleTable.HALVES_FIRST_DAY = 2 -- (a smaller real cap)
	for i = 1, 4 do Half(w, a, { id = "Kf" .. i, p1 = a, p2 = b, w = "1", t = w.clock - 100 * i }) end
	eq(#Do(w, c, "Halves", "Kf1"), 1); eq(#Do(w, c, "Halves", "Kf2"), 1)
	eq(#Do(w, c, "Halves", "Kf3"), 0, "past his room for the day"); eq(#Do(w, c, "Halves", "Kf4"), 0)
	for i = 1, 2 do Half(w, b, { id = "Kf" .. i, p1 = a, p2 = b, w = "1", t = w.clock - 100 * i }) end
	eq(Row(Best(w, c), a).won, 2)
	NoErrors(w)
end)

test("1.2.3 Bones ranking: a member away when the game ended hears both halves after the players' next logins; each player's own half said again at most once in 20 hours", function()
	local w, a, b, c = Setup()
	w:Logout(c)
	local id = PlayConceded(w, a, b)
	w:Login(c)
	eq(#Best(w, c), 0, "away when it ended")
	for _, p in ipairs({ a, b }) do
		w:Logout(p); w:Login(p)
		w:Group({ a, b })
	end
	w:Run(80)
	for _, p in ipairs({ a, b }) do
		local ch = w:Sent({ from = p, type = "KN", dist = "CHANNEL" })
		assert(ch[#ch].msg:find("^KN~T%d+~" .. id .. "~"), "said again: " .. ch[#ch].msg)
	end
	local rows = Best(w, c)
	eq(#rows, 2); eq(Row(rows, b).won, 1)
	-- the next login within 20 hours: nothing again
	local before = #w:Sent({ from = a, type = "KN" })
	w:Logout(a); w:Login(a); w:Run(80)
	eq(#w:Sent({ from = a, type = "KN" }), before)
	NoErrors(w)
end)

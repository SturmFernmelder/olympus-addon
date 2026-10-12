-- 1.2.3, the Bones ranking (Olympus/FarkleTable.lua's Best, ArenaHome's Data.GamesRanking("bones"),
-- the honours' source): before 1.2.3 Data.GamesRanking("bones") called FarkleTable.Best, which did
-- not exist, so the list was always empty. The owner's decisions for 1.2.3: a free game (no gold,
-- the only kind 1.2.x allows) always counts for the history and the ranking, whatever the King's
-- live switch, and a test build's never (decision 1); a game counts for everyone's ranking only when
-- both players' clients reported the same result, each its own signed half (the duels' two halves,
-- decision 2), with the ledger's caps and the alt check. Halves travel as the table's end (KN "e"
-- with the result, start, seat, key and signature) on the channel and to the other player, and
-- again, both of them, at each player's later logins, spaced.
-- The review of v123/bones (88dec8e) found, and these tests hold fixed: a member away when a game
-- ended never ranked it once the players had a quick login or /reload (the halves, unsigned, came
-- only from their own players, once in 20 hours); a player's later half replaced his first, so a
-- loser could un-count a counted win at any time; a whispered half was taken by a client not at
-- the game; a player who came back more than 10 minutes after the end never agreed (the ends were
-- compared); a flood of unanswered halves pushed agreed games out of the store; backdated games
-- used up a loser's day after the fact and dropped an honest win; a release player against a test
-- build counted the game alone; the list was worked out again every minute with nothing new, and
-- every half heard was kept whole.
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
local function Store(c) return c.rdb.bonesRank and c.rdb.bonesRank[c.faction] end
local function FieldsOf(body)
	local f = {}
	for part in (body .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	return f
end
local function Fields(msg) return FieldsOf(msg:match("^KN~[LT]%d+~(.*)$")) end
-- Every KN a client sent, a long one's EP pieces put together: { msg, dist, target }.
local function KNs(w, from, dist)
	local out, open = {}, {}
	for _, s in ipairs(w.sent) do
		if s.client == from and (not dist or s.dist == dist) then
			if s.msg:sub(1, 3) == "KN~" then
				out[#out + 1] = { msg = s.msg, dist = s.dist, target = s.target }
			else
				local id, i, n, chunk = s.msg:match("^EP~[LT]%d+~([0-9a-z]+)~([0-9a-z]+)~([0-9a-z]+)~(.+)$")
				if id then
					local key = s.dist .. (s.target or "") .. id
					local p = open[key] or { parts = {}, got = 0 }
					open[key] = p
					i, n = tonumber(i, 36), tonumber(n, 36)
					if not p.parts[i] then p.parts[i], p.got = chunk, p.got + 1 end
					if p.got == n then
						open[key] = nil
						local whole = table.concat(p.parts, "", 1, n)
						if whole:sub(1, 3) == "KN~" then out[#out + 1] = { msg = whole, dist = s.dist, target = s.target } end
					end
				end
			end
		end
	end
	return out
end
-- The halves (KN "e" with the result) among them.
local function HalvesSent(w, from, dist)
	local out = {}
	for _, s in ipairs(KNs(w, from, dist)) do if #Fields(s.msg) == 18 then out[#out + 1] = s end end
	return out
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
-- A player's half of a game as a 1.2.3 client writes it, crafted: o = { id, p1, p2 (clients), w
-- ("1"|"2"), s1, s2, how, steps, hash, t (its end), began (default t - dur), dur, unsigned },
-- signed with `signer`'s account key (its player's), for seat 1 (the host's) or 2.
local function Body(w, signer, o, seat)
	local B36 = signer.ns.Arena.B36
	local t = o.t or w.clock
	local began = o.began or (t - (o.dur or 300))
	local core = ("%s~%s~%s~-~2~-~e~%s~%s~%s~%s~%s~%s~%s~%s~%d"):format(o.id, o.p1.name, o.p2.name, o.w or "1", B36(o.s1 or 2000),
		B36(o.s2 or 300), o.how or "t", B36(o.steps or 40), o.hash or "0a1b2c3d", B36(t), B36(began), seat)
	if o.unsigned then return core .. "~-~-" end
	return w:As(signer, function()
		local D = signer.ns.Debts
		local _, pk = D.MyKey()
		return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYB1|" .. core))
	end)
end
-- That half sent by `from` on the channel (o.to: whispered to that client): its own player's, or
-- (o.seat, o.signer) another's relayed.
local function Half(w, from, o)
	local seat = o.seat or (from == o.p2 and 2 or 1)
	local signer = o.signer or (seat == 1 and o.p1 or o.p2)
	local body = Body(w, signer, o, seat)
	assert(w:As(from, from.ns.Arena.Send, "KN", "T", body, o.to and { to = o.to.name } or {}))
	w:Run(0)
	return body
end
-- Both players' halves of one game, agreeing.
local function Game(w, o)
	Half(w, o.p1, o)
	Half(w, o.p2, o)
end
local function Counts(c)
	local n = 0
	for _ in pairs(c) do n = n + 1 end
	return n
end

print("1.2.3: the Bones ranking")

test("1.2.3 Bones ranking: a free game between two members counts: each player's signed half on the channel and to the other; a member ranks both, Data.GamesRanking(\"bones\") gives it, and its record is the live realm's", function()
	local w, a, b, c = Setup()
	local id = PlayConceded(w, a, b)
	-- (the Games tab's list, as the screens read it: empty before 1.2.3 whatever was played)
	local list = w:As(c, c.ns.ArenaHome.Data.GamesRanking, "bones")
	eq(#list, 2, "the Games tab's Bones ranking")
	eq(list[1].name:lower(), b.name:lower()); eq(list[1].won, 1); eq(list[1].games, 1)
	for seat, p in ipairs({ a, b }) do
		eq(Do(w, p, "Counted", id), true, "decision 1: the free game counts, the live switch off")
		local other = p == a and b or a
		local ch = HalvesSent(w, p, "CHANNEL")
		eq(#ch, 1, "its half on the channel")
		local f = Fields(ch[1].msg)
		eq(f[1], id); eq(f[7], "e"); eq(f[8], "2", "the guest won")
		eq(f[16], tostring(seat), "whose half it is")
		eq(#f[17], 43, "his account's key"); eq(#f[18], 86, "its signature")
		-- (the signature is his account key's over the half, as any client checks a relayed one)
		local core = table.concat(f, "~", 1, 16)
		local ok = w:As(c, function()
			local Ed = c.ns.Ed25519
			return Ed.Verify(Ed.FromB64(f[17]), "OLYB1|" .. core, Ed.FromB64(f[18]))
		end)
		eq(ok, true, "signed with " .. p.short .. "'s key")
		eq(#HalvesSent(w, p, "WHISPER"), 1, "told the other player for sure")
		eq(HalvesSent(w, p, "WHISPER")[1].target:lower(), other.name:lower())
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
	eq(#Best(w, c, { month = w:As(c, c.ns.Honors.MonthOf, w.clock) - 1 }), 0, "nothing last month")
	-- (each member's client learned each player's key from his own half)
	eq(Do(w, c, "Pin", a.name), Fields(HalvesSent(w, a, "CHANNEL")[1].msg)[17])
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
	local held = Do(w, c, "Halves", id)
	eq(#held, 1); eq(held[1].agreed, true)
	assert(held[1].dur >= 20, "the game's whole length: " .. tostring(held[1].dur))
	for _, p in ipairs({ a, b }) do assert(w:As(p, p.ns.ArenaLedger.MyGames)[1].dur >= 20, "the games' ledger's length too") end
	local rows = Best(w, c)
	eq(#rows, 2); eq(Row(rows, b).won, 1)
	NoErrors(w)
end)

-- (Review of 88dec8e, its FreeCounts and GameCounts: each side decided on its own build, so a
-- release player against a test build, or against a 1.2.2 client, recorded the game as counted
-- alone: an L history row, an L games' ledger record, and its half sent. Both clients say whether
-- they count the free game now, "c" on the invitation and on the answer.)
test("1.2.3 Bones ranking: against a test build, or a 1.2.2 client, the game counts on neither side: the release player's history, games' ledger and notice stay a rehearsal's, and no half goes", function()
	local tb = { n = 3, base = "1.2.3", built = H.World.CLOCK - 60, expires = H.World.CLOCK + 86400 }
	-- the test build hosts, the release member is the guest
	local w, a, b, c = Setup({ whereA = { testBuild = tb } })
	assert(w:As(a, a.ns.Arena.TestBuild), "a runs a test build")
	local id = PlayConceded(w, a, b)
	eq(Do(w, a, "Counted", id), false, "a test build never counts")
	eq(Do(w, b, "Counted", id), false, "nor its release opponent, alone")
	eq(#w:Sent({ from = a, type = "KN", dist = "CHANNEL" }), 0, "nothing of the test build's on the channel")
	for _, p in ipairs({ a, b }) do
		eq(#HalvesSent(w, p), 0, p.short .. ": no half")
		eq(w:As(p, p.ns.ArenaLedger.MyGames)[1].mode, "T", p.short .. ": the games' ledger's record a rehearsal's")
		eq(Do(w, p, "MyGames")[1].reh, true, p.short .. ": Bones's history a rehearsal's (TESTE)")
	end
	for _, s in ipairs(KNs(w, b, "CHANNEL")) do
		local f = Fields(s.msg)
		assert(#f <= 8, "the release player's notices say nothing counts: " .. s.msg)
	end
	eq(#Best(w, c), 0); eq(#Best(w, b), 0)
	NoErrors(w)
	-- the release member hosts, the test build is the guest
	w, a, b, c = Setup({ whereB = { testBuild = tb } })
	id = PlayConceded(w, a, b)
	eq(Do(w, a, "Counted", id), false, "the guest's answer said no c")
	eq(#HalvesSent(w, a), 0)
	eq(w:As(a, a.ns.ArenaLedger.MyGames)[1].mode, "T"); eq(Do(w, a, "MyGames")[1].reh, true)
	NoErrors(w)
	-- a 1.2.2 guest: its answer has no "c" (a 1.2.3 client's answer with the flag cut off, as 1.2.2 sends it)
	w, a, b, c = Setup()
	w:As(b, function()
		local Send = b.ns.Arena.Send
		b.ns.Arena.Send = function(kind, mode, body, o)
			if kind == "KA" then body = body:gsub("~~~c$", "") end
			return Send(kind, mode, body, o)
		end
	end)
	id = PlayConceded(w, a, b)
	eq(Do(w, a, "Counted", id), false, "a 1.2.2 guest never said his client counts it")
	eq(#HalvesSent(w, a), 0, "no half from the release host")
	eq(w:As(a, a.ns.ArenaLedger.MyGames)[1].mode, "T"); eq(Do(w, a, "MyGames")[1].reh, true)
	eq(#Best(w, c), 0)
	NoErrors(w)
end)

test("1.2.3 Bones ranking: one half alone, a half from someone not at the game, halves that differ never count, and a player's later word never replaces his first; other seats under that id are another game", function()
	local w, a, b, c = Setup()
	local x = w:Player(P3)
	Half(w, a, { id = "Kone", p1 = a, p2 = b, w = "1" })
	eq(#Best(w, c), 0, "one half")
	-- a member not at the game speaks for b: not taken
	Half(w, x, { id = "Kone", p1 = a, p2 = b, w = "1", seat = 2, signer = x })
	local held = Do(w, c, "Halves", "Kone")
	eq(#held, 1); eq(held[1].by[x.name:lower()], nil); eq(held[1].by[b.name:lower()], nil)
	eq(#Best(w, c), 0)
	-- b says he won: they differ, and stay apart
	Half(w, b, { id = "Kone", p1 = a, p2 = b, w = "2" })
	eq(Do(w, c, "Halves", "Kone")[1].agreed, false)
	eq(#Best(w, c), 0, "halves that differ")
	-- (88dec8e took his later word in place of the first: his half the same as a's, it counted.
	-- An honest client never says two; the first stays, and the game never counts.)
	Half(w, b, { id = "Kone", p1 = a, p2 = b, w = "1" })
	eq(Do(w, c, "Halves", "Kone")[1].by[b.name:lower()].w, "2", "b's first word stays")
	eq(Do(w, c, "Halves", "Kone")[1].agreed, false)
	eq(#Best(w, c), 0, "a mismatched game stays uncounted")
	-- other scores, or another transcript, differ too
	Half(w, a, { id = "Ktwo", p1 = a, p2 = b, w = "1" })
	Half(w, b, { id = "Ktwo", p1 = a, p2 = b, w = "1", s2 = 350 })
	Half(w, a, { id = "Kthree", p1 = a, p2 = b, w = "1" })
	Half(w, b, { id = "Kthree", p1 = a, p2 = b, w = "1", hash = "ffffffff" })
	eq(#Best(w, c), 0, "other scores, another transcript")
	-- the same result: it counts
	Game(w, { id = "Kfour", p1 = a, p2 = b, w = "1" })
	eq(Do(w, c, "Halves", "Kfour")[1].agreed, true)
	local rows = Best(w, c)
	eq(Order(rows), "Torvin Hale, Selka Drummond"); eq(Row(rows, a).won, 1)
	-- starts more than HALF_SKEW apart: not one game
	Half(w, a, { id = "Kfive", p1 = a, p2 = b, w = "1", began = w.clock - 1000 })
	Half(w, b, { id = "Kfive", p1 = a, p2 = b, w = "1", began = w.clock - 300 })
	eq(Row(Best(w, c), a).won, 1, "the far-apart game is not counted")
	-- the same id with other seats is another game, which never spoils the agreed one
	Half(w, x, { id = "Kfour", p1 = x, p2 = b, w = "1" })
	eq(Row(Best(w, c), a).won, 1)
	eq(#Do(w, c, "Halves", "Kfour"), 2)
	-- a void game, a time ahead of the clock, or a start after the end is no half
	Half(w, a, { id = "Ksix", p1 = a, p2 = b, w = "1", how = "v" })
	Half(w, a, { id = "Kseven", p1 = a, p2 = b, w = "1", t = w.clock + 3600 })
	Half(w, a, { id = "Keight", p1 = a, p2 = b, w = "1", began = w.clock + 10, t = w.clock })
	eq(#Do(w, c, "Halves", "Ksix"), 0); eq(#Do(w, c, "Halves", "Kseven"), 0); eq(#Do(w, c, "Halves", "Keight"), 0)
	NoErrors(w)
end)

-- (Review of 88dec8e, TakeHalf: a player's later half always replaced his earlier one, after both
-- agreed too, so a sore loser could un-count a ranked win at any time, even weeks later, the end of
-- the month before the honours.)
test("1.2.3 Bones ranking: once both halves agree the game is fixed: the loser's later half with another winner, sent at once or weeks later, leaves the win counted", function()
	local w, a, b, c = Setup()
	local id = PlayConceded(w, a, b)
	eq(Row(Best(w, c), b).won, 1)
	-- a's client (a modified one) says his half again with the winner rewritten: same id, seats,
	-- transcript and times (the end KN he sent, its winner field changed)
	local ends = {}
	for _, s in ipairs(KNs(w, a, "CHANNEL")) do if Fields(s.msg)[7] == "e" then ends[#ends + 1] = s end end
	local f = Fields(ends[#ends].msg)
	eq(f[8], "2")
	f[8] = "1"
	assert(w:As(a, a.ns.Arena.Send, "KN", "T", table.concat(f, "~"), {}))
	w:Run(0)
	eq(Row(Best(w, c), b).won, 1, "b's win stays")
	eq(Row(Best(w, c), a).won, 0)
	local held = Do(w, c, "Halves", id)
	eq(#held, 1); eq(held[1].agreed, true, "still agreed"); eq(held[1].w, "2")
	-- two of b's wins, 20 and 10 days ago; on the month's last day a's client says both again, won by him
	local now = w.clock
	Game(w, { id = "Kv1", p1 = a, p2 = b, w = "2", t = now - 20 * 86400 })
	Game(w, { id = "Kv2", p1 = a, p2 = b, w = "2", t = now - 10 * 86400 })
	local month = w:As(c, c.ns.Honors.MonthOf, now - 20 * 86400)
	local before = Row(Best(w, c, { month = month }), b).won
	assert(before >= 1, "b's older wins count")
	Half(w, a, { id = "Kv1", p1 = a, p2 = b, w = "1", t = now - 20 * 86400 })
	Half(w, a, { id = "Kv2", p1 = a, p2 = b, w = "1", t = now - 10 * 86400 })
	eq(Do(w, c, "Halves", "Kv1")[1].agreed, true); eq(Do(w, c, "Halves", "Kv2")[1].agreed, true)
	eq(Row(Best(w, c, { month = month }), b).won, before, "nothing taken back")
	NoErrors(w)
end)

-- (Review of 88dec8e, OnNotice: a whispered half was taken from any player of the game, whoever it
-- reached, so two players could feed one chosen client halves the channel never saw.)
test("1.2.3 Bones ranking: a half whispered to a client not at the game is not held there; the other player's whisper is", function()
	local w, a, b, c = Setup()
	c.onChannel = false -- (c hears nothing of the channel: only what is whispered to him)
	local id = PlayConceded(w, a, b)
	eq(#Do(w, c, "Halves", id), 0)
	-- both players whisper c their halves of the game, as they sent them on the channel
	for _, p in ipairs({ a, b }) do
		local ends = {}
		for _, s in ipairs(KNs(w, p, "CHANNEL")) do if Fields(s.msg)[7] == "e" then ends[#ends + 1] = s end end
		assert(w:As(p, p.ns.Arena.Send, "KN", "T", ends[#ends].msg:match("^KN~[LT]%d+~(.*)$"), { to = c.name }))
		w:Run(0)
	end
	eq(#Do(w, c, "Halves", id), 0, "nothing held by the client they whispered")
	eq(#Best(w, c), 0)
	-- the other player's whisper at the game's end is held (his own game's half): b ranks it
	eq(#HalvesSent(w, a, "WHISPER") >= 1, true)
	eq(#Best(w, b), 2)
	NoErrors(w)
end)

-- (Review of 88dec8e, Agreed: the halves had to end within HALF_SKEW, each client stamping its
-- own end; a player away at the last event finishes the game when he is back, so his half ended
-- later and the game never ranked anywhere, not even on the players' own clients.)
test("1.2.3 Bones ranking: the guest is away more than 10 minutes when the host wins, then comes back; his client finishes the game and it ranks on a third client", function()
	local w, a, b, c = Setup()
	local id = assert(Do(w, a, "Create", { guest = b.name, target = 2000 }))
	w:Run(0)
	assert(Do(w, b, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Do(w, a, "Roll", id); Do(w, b, "Roll", id)
	w:Run(20)
	eq(Get(a, id).state, "play")
	-- b's client drops (a disconnect): a rolls six 1s and banks, winning to 2,000
	w:Logout(b)
	w:QueueRoll(a.name, (a.ns.FarkleRules.Encode({ 1, 1, 1, 1, 1, 1 })))
	assert(Do(w, a, "Roll", id))
	w:Run(0)
	assert(Do(w, a, "Keep", { 1, 2, 3, 4, 5, 6 }, "b", id))
	w:Run(0)
	local ga = Get(a, id).game
	eq(ga.over, true); eq(ga.winner, 1); eq(ga.reason, "target")
	w:Run(660)
	w:Login(b)
	w:Group({ a, b })
	w:Run(30)
	local gb = Get(b, id) and Get(b, id).game
	assert(gb and gb.over, "b's client finished the game on his return")
	eq(gb.winner, 1)
	for _, viewer in ipairs({ c, a, b }) do
		local rows = Best(w, viewer)
		eq(#rows, 2, viewer.short .. " ranks it"); eq(Row(rows, a).won, 1)
	end
	local hb = HalvesSent(w, b)
	assert(#hb >= 1, "b's half went")
	local fa, fb = Fields(HalvesSent(w, a, "CHANNEL")[1].msg), Fields(hb[1].msg)
	assert(tonumber(fb[14], 36) - tonumber(fa[14], 36) > 600, "his end is more than 10 minutes after a's")
	assert(math.abs(tonumber(fb[15], 36) - tonumber(fa[15], 36)) <= 2, "their starts are the same")
	for _, viewer in ipairs({ c, a, b }) do
		local held = Do(w, viewer, "Halves", id)
		eq(#held, 1); eq(held[1].agreed, true, viewer.short)
		-- (the game's time is the earlier end: a's)
		eq(held[1].t, tonumber(fa[14], 36))
	end
	NoErrors(w)
end)

-- (Review of 88dec8e, PruneHalves: past HALVES_MAX the store dropped the oldest games by the time
-- their sender gave, agreed or not, so one sender's unanswered halves dated now pushed agreed games
-- out; and a sender could open HALVES_FIRST_DAY games a day without end.)
test("1.2.3 Bones ranking: a flood of unanswered halves never pushes an agreed game out of a full store; one sender holds HALVES_OPEN_MAX games with a single half at once", function()
	local w, a, b, c = Setup()
	local x, y = w:Player(P3), w:Player(P4)
	c.ns.FarkleTable.HALVES_MAX, c.ns.FarkleTable.HALVES_OPEN_MAX = 5, 3 -- (smaller real caps)
	Game(w, { id = "Ka1", p1 = a, p2 = b, w = "2", t = w.clock - 600 })
	eq(Row(Best(w, c), b).won, 1)
	-- x opens games with made-up opponents, dated ahead of the agreed one: three at once, no more
	for i = 1, 5 do Half(w, x, { id = "Kj" .. i, p1 = x, p2 = y, w = "1", t = w.clock - 10 + i }) end
	eq(#Do(w, c, "Halves", "Kj3"), 1); eq(#Do(w, c, "Halves", "Kj4"), 0, "past his open games")
	-- y opens more, the store fills: the unanswered ones go first, never the agreed game
	for i = 1, 6 do Half(w, y, { id = "Ky" .. i, p1 = y, p2 = x, w = "1", t = w.clock + i - 10 }) end
	local s = Store(c)
	assert(Counts(s.open) + Counts(s.done) <= 5, "the store within HALVES_MAX")
	eq(Do(w, c, "Halves", "Ka1")[1].agreed, true, "the agreed game is still held")
	eq(Row(Best(w, c), b).won, 1, "and still counts")
	NoErrors(w)
end)

-- (Review of 88dec8e, Best: the caps went in the order of the senders' end times, so games dated
-- back into a day already counted used up a player's day after the fact and dropped an honest win.)
test("1.2.3 Bones ranking: backdated agreed games told later never take out a win counted before them; they are capped themselves", function()
	local w, a, b, c = Setup()
	local h = w:Player(P3)
	c.ns.ArenaLedger.DAY_MAX = 2 -- (a smaller real cap on the member's client: ArenaLedger's own, which Best reads)
	local at = w.clock - 3600
	assert(math.floor((at - 3000) / 86400) == math.floor(at / 86400), "the games below on one server day")
	Game(w, { id = "Kh1", p1 = h, p2 = a, w = "1", t = at })
	eq(Row(Best(w, c), h).won, 1, "h beat a, counted")
	w:Run(60)
	-- later, a and b say games of theirs played earlier that day, b winning
	for i = 1, 3 do Game(w, { id = "Kb" .. i, p1 = a, p2 = b, w = "2", t = at - 1000 * i }) end
	local rows = Best(w, c)
	eq(Row(rows, h).won, 1, "h's win stays")
	eq(Row(rows, b).won, 1, "a's day had room for one more game")
	eq(Row(rows, a).games, 2)
	NoErrors(w)
end)

-- (Review of 88dec8e, Best and the store: every half heard was kept whole, up to 3,000 games of 62
-- days in every member's saved data, and the list was worked out again whenever it was a minute
-- old, nothing new or not: once a minute with the Games tab open, as live tables announce.)
test("1.2.3 Bones ranking: an agreed game is one short line in a member's saved data; the list is worked out again only when a game, an alt link or a moderation word changed, never on a clock", function()
	local w, a, b, c = Setup()
	local id = PlayConceded(w, a, b)
	local s = Store(c)
	eq(Counts(s.open), 0, "no half kept apart once both agree")
	eq(Counts(s.done), 1)
	local line = s.done[id .. ":" .. (a.name .. ":" .. b.name):lower()]
	eq(type(line), "string", "one line")
	assert(#line < 120, "a short one: " .. #line .. " bytes")
	-- a live table announcing every minute: the list stays the one worked out
	local d, e = w:Player(P3), w:Player(P4)
	w:Group({ d, e })
	w:Run(61) -- (their first alt claims, which every client takes once)
	local open = assert(Do(w, d, "Create", { guest = e.name, target = 2000 }))
	w:Run(0)
	assert(Do(w, e, "Answer", open, true, nil, {}))
	w:Run(0)
	w:QueueRoll(d.name, 90); w:QueueRoll(e.name, 10)
	Do(w, d, "Roll", open); Do(w, e, "Roll", open)
	local first = Best(w, c)
	w:Run(300)
	assert(#KNs(w, d, "CHANNEL") >= 4, "the live table announced every minute")
	assert(Best(w, c) == first, "the same list, not worked out again")
	-- a new game: worked out again
	Game(w, { id = "Knew", p1 = d, p2 = e, w = "1" })
	local second = Best(w, c)
	assert(second ~= first); eq(#second, 4)
	-- an alt link: worked out again (a and e, one player's characters)
	local now = w.clock
	w:As(c, c.ns.Alts.Handle, "CHANNEL", d.name, ("AL~%d~M~%s~%s"):format(now, H.World.GUILD, e.short))
	w:As(c, c.ns.Alts.Handle, "CHANNEL", e.name, ("AL~%d~A~%s~%s"):format(now, H.World.GUILD, d.short))
	local third = Best(w, c)
	assert(third ~= second); eq(#third, 2, "d and e's game left out at once")
	NoErrors(w)
end)

test("1.2.3 Bones ranking: the ledger's caps: a game under the minimum length, a pair past its games in PAIR_DAYS, a player past his in a day never count; most wins first, a tie to fewer games", function()
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
	local rows = Best(w, c)
	eq(Row(rows, a), nil, "his only game this month was against his own alt")
	eq(Row(rows, e), nil)
	eq(Order(rows), "Selka Drummond, Lida Fenn")
	NoErrors(w)
end)

-- (Review of 88dec8e, RepeatHalves: a player's own half said again once in 20 hours, at the first
-- login after the game, a /reload counting, while the members who missed it were still away; and
-- nobody else could pass a half on. Each player now says both halves, his and the other's signed
-- one, at up to three later logins spaced an hour, 6 and 20 hours after the last telling, and a
-- member takes the other's half from him when it carries the key he holds for that player.)
test("1.2.3 Bones ranking: members away when a game ended rank it at the players' later logins, a /reload soon after spending nothing; the other's half relayed with its key; three repeats at most, spaced", function()
	local w, a, b, c = Setup()
	local x = w:Player(P3)
	local d = w:Player(P4)
	-- (c heard b's own half of an earlier game: c holds b's key; d was away)
	w:Logout(d)
	Half(w, b, { id = "Kpin", p1 = b, p2 = x, w = "1", t = w.clock - 7200 })
	assert(Do(w, c, "Pin", b.name), "c holds b's key")
	w:Logout(c)
	local id = PlayConceded(w, a, b)
	local ended = w.clock
	local key = id .. ":" .. (a.name .. ":" .. b.name):lower()
	local function Own(p) return Store(p).own[key] end
	eq(Own(a).n, 0); assert(Own(a).theirs, "a keeps b's signed half")
	-- a /reloads a minute later, the members still away: nothing said, nothing spent
	w:Run(60)
	local before = #HalvesSent(w, a)
	w:Logout(a); w:Login(a); w:Group({ a, b })
	w:Run(80)
	eq(#HalvesSent(w, a), before, "nothing said again a minute after the game")
	eq(Own(a).n, 0, "the repeats are still all there")
	-- the members come back; b relogs half an hour after the game: still nothing
	w:Login(c); w:Login(d)
	w:Run(1800 - 140)
	before = #HalvesSent(w, b)
	w:Logout(b); w:Login(b); w:Group({ a, b })
	w:Run(80)
	eq(#HalvesSent(w, b), before)
	eq(#Best(w, c), 0, "c missed it so far")
	-- a relogs an hour after the game: both halves go, c ranks it, d holds a's alone (no key of b's)
	w:Run(ended + 3600 - w.clock)
	before = #HalvesSent(w, a, "CHANNEL")
	w:Logout(a); w:Login(a); w:Group({ a, b })
	w:Run(80)
	local said = HalvesSent(w, a, "CHANNEL")
	eq(#said - before, 2, "a said his half and b's")
	eq(Fields(said[#said].msg)[16], "2", "b's half, as b signed it")
	eq(Own(a).n, 1, "one repeat spent")
	local rows = Best(w, c)
	eq(#rows, 2, "c ranks the game"); eq(Row(rows, b).won, 1)
	eq(#Best(w, d), 0, "d holds a's half only: b's relayed one carries a key d does not hold")
	local held = Do(w, d, "Halves", id)
	eq(#held, 1); assert(held[1].by[a.name:lower()] and not held[1].by[b.name:lower()])
	-- b relogs: his own repeat (an hour after his last telling) completes it on d
	w:Logout(b); w:Login(b); w:Group({ a, b })
	w:Run(80)
	eq(#Best(w, d), 2, "d ranks it once b's own half came")
	NoErrors(w)
	-- a's next logins, everyone else away: within 6 hours of his repeat nothing; 6 hours after it the
	-- second; 20 hours after that the third; then no more
	for _, p in ipairs({ b, c, d, x }) do w:Logout(p) end
	local function Relog(after)
		w:Logout(a)
		w:Run(after) -- (nobody online: the clock alone moves)
		w:Login(a)
		w:Run(80)
	end
	Relog(0); eq(Own(a).n, 1)
	Relog(21600); eq(Own(a).n, 2)
	Relog(72000); eq(Own(a).n, 3)
	before = #HalvesSent(w, a)
	Relog(72000)
	eq(#HalvesSent(w, a), before, "three repeats at most"); eq(Own(a).n, 3)
	NoErrors(w)
end)

test("1.2.3 Bones ranking: a repeat that did not go out is not spent; a relayed half with a wrong signature, or from someone not at the game, is never taken", function()
	local w, a, b, c = Setup()
	local x = w:Player(P3)
	local id = PlayConceded(w, a, b)
	local key = id .. ":" .. (a.name .. ":" .. b.name):lower()
	w:Run(3600)
	-- the game refuses every send of a's for a while (the throttle): the repeat waits for his next login
	local nines = {}
	for i = 1, 200 do nines[i] = 9 end
	w:Logout(a); w:Login(a); w:Results(a, nines); w:Group({ a, b })
	w:Run(80)
	a.comm.results = {}
	eq(Store(a).own[key].n, 0, "not spent")
	w:Logout(a); w:Login(a); w:Group({ a, b })
	w:Run(80)
	eq(Store(a).own[key].n, 1, "said at the next login")
	-- relays c refuses (c holds b's key from the game): b's half saying another winner than b signed,
	-- sent by a; b's half sent by x, not at the game
	local f = FieldsOf(Body(w, b, { id = "Kbad", p1 = a, p2 = b, w = "2" }, 2))
	f[8] = "1"
	Half(w, a, { id = "Kbad", p1 = a, p2 = b, w = "1" })
	assert(w:As(a, a.ns.Arena.Send, "KN", "T", table.concat(f, "~"), {}))
	w:Run(0)
	eq(Do(w, c, "Halves", "Kbad")[1].by[b.name:lower()], nil, "a forged half of b's: its signature fails")
	Half(w, x, { id = "Kbad", p1 = a, p2 = b, w = "1", seat = 2, signer = b })
	eq(Do(w, c, "Halves", "Kbad")[1].by[b.name:lower()], nil, "nobody but the game's players passes a half on")
	eq(#Best(w, c), 2, "only the real game")
	NoErrors(w)
end)

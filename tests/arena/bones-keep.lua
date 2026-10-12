-- 1.2.4, the author's ask ("rankings ... should be cumulative ... not erased"): what the Bones
-- ranking keeps (Olympus/FarkleTable.lua). Before: a game with one half was erased after 7 days, so
-- an other half heard later never counted, and nobody asked for it; a player said his games again at
-- three logins within a day, so a member away for a weekend never ranked them; a closed month's
-- list went with its games after 62 days (no champion, no totals kept); the Games tab showed this
-- month alone; the profile never showed Bones (no module filled stats.bones); and a free table's
-- live record sat in the rehearsals' store, which `test clear` empties mid-game.
-- On the release's gate (compliance "shipped"), the test world with the table's additions
-- (tests/arena/lib/farkle-world.lua). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES
local P1, P2, VIEWER = N.fighterA, N.fighterB, N.bettor3
local P3 = N.bettor1

local function Get(c, id) return c.ns.FarkleTable.Get(id) end
local function Do(w, c, fn, ...) return w:As(c, c.ns.FarkleTable[fn], ...) end
local function Best(w, c, opts) return Do(w, c, "Best", "L", opts) end
local function Row(rows, c)
	for _, r in ipairs(rows) do if r.key == c.name:lower() then return r end end
	return nil
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
local function KNs(w, from, dist)
	local out = {}
	for _, s in ipairs(w:Sent({ from = from, type = "KN", dist = dist })) do
		out[#out + 1] = { msg = s.msg, dist = s.dist, target = s.target, f = FieldsOf(s.msg:match("^KN~[LT]%d+~(.*)$")) }
	end
	return out
end
local function MonthOf(w, c, t) return w:As(c, c.ns.Honors.MonthOf, t) end

local function Setup()
	local w = FW.New({ compliance = "shipped" })
	local a = w:Player(P1)
	local b = w:Player(P2)
	local c = w:Player(VIEWER)
	w:Group({ a, b })
	return w, a, b, c
end
-- A table as members make it, played 20 s, then the host concedes: the guest wins. Its id.
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
	eq(Get(guest, id).game.winner, 2)
	return id
end
-- A player's signed half as a 1.2.3/1.2.4 client writes it (o = { id, p1, p2, w, t }), sent by
-- `from` on the channel (its own player's).
local function Half(w, from, o)
	local seat = from == o.p2 and 2 or 1
	local B36 = from.ns.Arena.B36
	local t = o.t or w.clock
	local core = ("%s~%s~%s~-~2~-~e~%s~%s~%s~%s~%s~%s~%s~%s~%d"):format(o.id, o.p1.name, o.p2.name, o.w or "1", B36(2000), B36(300), "t",
		B36(40), "0a1b2c3d", B36(t), B36(t - 300), seat)
	local body = w:As(from, function()
		local D = from.ns.Debts
		local _, pk = D.MyKey()
		return core .. "~" .. D.B64(pk) .. "~" .. D.B64(D.Sign("OLYB1|" .. core))
	end)
	assert(w:As(from, from.ns.Arena.Send, "KN", "T", body, {}))
	w:Run(0)
end
local function Game(w, o) Half(w, o.p1, o) Half(w, o.p2, o) end
local function Relog(w, c, after, group)
	w:Logout(c)
	w:Run(after or 0)
	w:Login(c)
	if group then w:Group(group) end
	w:Run(80)
end

print("1.2.4: what the Bones ranking keeps")

test("1.2.4 Bones kept: a game with one half is kept with its month (it was erased after 7 days): the other half heard on the 8th day still counts", function()
	local w, a, b, c = Setup()
	local t = w.clock - 60
	Half(w, a, { id = "Klate", p1 = a, p2 = b, w = "1", t = t })
	eq(#Do(w, c, "Halves", "Klate"), 1)
	w:Run(8 * 86400)
	Do(w, c, "Prune")
	eq(#Do(w, c, "Halves", "Klate"), 1, "the lone half, still held on the 8th day")
	Half(w, b, { id = "Klate", p1 = a, p2 = b, w = "1", t = t })
	eq(Do(w, c, "Halves", "Klate")[1].agreed, true)
	eq(Row(Best(w, c, { month = MonthOf(w, c, t) }), a).won, 1, "it counts in its month")
	NoErrors(w)
end)

test("1.2.4 Bones kept: a player whose client never got the other's half asks the other player for it at a later login (a whisper), and the other's client answers with his own signed half", function()
	local w, a, b, c = Setup()
	-- b's client loses its half at the game's end (a crash before it went: nothing of it on the wire)
	local send = b.ns.Arena.Send
	b.ns.Arena.Send = function(kind, mode, body, o)
		if kind == "KN" and #FieldsOf(tostring(body)) == 18 then return true end
		return send(kind, mode, body, o)
	end
	local id = PlayConceded(w, a, b)
	b.ns.Arena.Send = send
	eq(#Best(w, a), 0, "a holds his own half alone")
	eq(#Best(w, c), 0)
	-- a logs in an hour later: his repeat, and the ask for b's half
	w:Run(3600)
	Relog(w, a, 0, { a, b })
	local asks = {}
	for _, s in ipairs(KNs(w, a, "WHISPER")) do if s.f[7] == "h" then asks[#asks + 1] = s end end
	eq(#asks, 1, "the ask, whispered"); eq(asks[1].target:lower(), b.name:lower()); eq(asks[1].f[1], id)
	eq(#asks[1].f, 7, "the game's id, seats and target, nothing else")
	local rows = Best(w, a)
	eq(#rows, 2, "b's half came back: a ranks the game"); eq(Row(rows, b).won, 1)
	assert(Store(a).own[id .. ":" .. (a.name .. ":" .. b.name):lower()].theirs, "kept for a's repeats")
	-- (an ask from a client not at the game is never answered)
	local x = w:Player(P3)
	local before = #KNs(w, b, "WHISPER")
	w:As(x, x.ns.Arena.Send, "KN", "T", ("%s~%s~%s~-~2~-~h"):format(id, a.name, b.name), { to = b.name })
	w:Run(0)
	eq(#KNs(w, b, "WHISPER"), before, "not to a member who did not play it")
	NoErrors(w)
end)

test("1.2.4 Bones kept: a player says his game again at 8 later logins over about two weeks (it was 3 within a day), then no more", function()
	local w, a, b, c = Setup()
	local id = PlayConceded(w, a, b)
	local key = id .. ":" .. (a.name .. ":" .. b.name):lower()
	for _, p in ipairs({ b, c }) do w:Logout(p) end
	-- a logs in every 30 hours for four weeks, nobody else online
	local said = {}
	for login = 1, 22 do
		local n = Store(a).own[key].n
		local before = #KNs(w, a, "CHANNEL")
		Relog(w, a, 108000 - 80)
		if Store(a).own[key].n > n then
			said[#said + 1] = login
			eq(#KNs(w, a, "CHANNEL") - before, 2, "his half and b's, said again")
		end
	end
	eq(#said, 8, "eight repeats, at logins " .. table.concat(said, ","))
	assert(said[8] * 30 <= 21 * 24, "the eighth within three weeks: login " .. tostring(said[8]))
	eq(Store(a).own[key].n, 8)
	NoErrors(w)
end)

test("1.2.4 Bones kept: a closed month's list is kept for good, its totals and champion, after its games are gone; the Games tab shows last month's podium; the profile counts a player's games", function()
	local w, a, b, c = Setup()
	local d = w:Player(P3)
	local king = w:Role("king")
	assert(w:As(king, king.ns.ArenaRoles.Publish, "bones", true))
	w:Run(0)
	local Hs = c.ns.Honors
	local closed = MonthOf(w, c, w.clock) - 1
	local start = w.clock - w.clock % 86400
	while w:As(c, Hs.MonthOf, start - 1) >= closed + 1 do start = start - 86400 end
	-- last month: b beats a and d, a beats d; this month: a beats b
	Game(w, { id = "Km1", p1 = a, p2 = b, w = "2", t = start - 5 * 86400 })
	Game(w, { id = "Km2", p1 = d, p2 = b, w = "2", t = start - 4 * 86400 })
	Game(w, { id = "Km3", p1 = a, p2 = d, w = "1", t = start - 3 * 86400 })
	Game(w, { id = "Kn1", p1 = a, p2 = b, w = "1", t = w.clock - 3600 })
	eq(MonthOf(w, c, start - 5 * 86400), closed)
	-- The Games tab: this month's list, then last month's, its champion named.
	local L = c.ns.L
	local lines = w:As(c, c.ns.ArenaHome.TabLines)
	local at
	for i, l in ipairs(lines) do if tostring(l.text):find(L.ARENA_GAMES_BONES_LAST, 1, true) then at = i end end
	if not at then
		w:As(c, function() c.ns.ArenaHome.rankGame = "bones" end)
		lines = w:As(c, c.ns.ArenaHome.TabLines)
		for i, l in ipairs(lines) do if tostring(l.text):find(L.ARENA_GAMES_BONES_LAST, 1, true) then at = i end end
	end
	assert(at, "last month's header on the Games tab")
	assert(tostring(lines[at].right):find(b.short, 1, true), "its champion: " .. tostring(lines[at].right))
	assert(tostring(lines[at + 1].text):find("#1", 1, true) and tostring(lines[at + 1].text):find(b.short, 1, true), tostring(lines[at + 1].text))
	-- Everyone but c logs out; 64 days on, c's login prunes the games (past HALVES_DAYS).
	for _, p in ipairs({ a, b, d, king }) do w:Logout(p) end
	Relog(w, c, 64 * 86400)
	eq(#Best(w, c, { month = closed }), 0, "its games are gone")
	eq(#Best(w, c, { month = closed + 1 }), 0)
	local kept = Do(w, c, "Month", closed)
	eq(kept.kept, true, "the list kept")
	eq(kept.champion, b.name, "its champion")
	eq(Row(kept.rows, b).won, 2); eq(Row(kept.rows, b).games, 2)
	eq(Row(kept.rows, a).won, 1); eq(Row(kept.rows, a).games, 2)
	eq(Row(kept.rows, d).won, 0); eq(Row(kept.rows, d).lost, 2)
	eq(Do(w, c, "Month", closed + 1).champion, a.name, "the next month's too")
	-- (the profile page's stats.bones: every month's games the rankings counted)
	local card = w:As(c, c.ns.ArenaHome.Data.Profile, b.name)
	local stats = card and card.stats and card.stats.v
	assert(stats and stats.bones, "the profile's Bones")
	eq(stats.bones.games, 3); eq(stats.bones.won, 2)
	-- kept through another login
	Relog(w, c, 86400)
	eq(Do(w, c, "Month", closed).champion, b.name)
	NoErrors(w)
end)

test("1.2.4 Bones kept: a free table's live record is the live realm's, not the rehearsals': `test clear` mid-game, then a /reload, and the game goes on and counts", function()
	local w, a, b, c = Setup()
	local id = assert(Do(w, a, "Create", { guest = b.name, target = 2000 }))
	w:Run(0)
	assert(Do(w, b, "Answer", id, true, nil, {}))
	w:Run(0)
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	Do(w, a, "Roll", id); Do(w, b, "Roll", id)
	w:Run(20)
	eq(Get(a, id).state, "play")
	eq(Get(a, id).mode, "T", "the table is T while the live switch is off")
	for _, p in ipairs({ a, b }) do
		local m = p.rdb.arena.realms[p.realm].farkle[p.name:lower()]
		eq(m.live and m.live.id, id, p.short .. ": the record in the live realm's store")
		local t = p.rdb.arenaTest
		local tm = type(t) == "table" and type(t.farkle) == "table" and t.farkle[p.name:lower()]
		eq(tm and tm.live or nil, nil, p.short .. ": none in the rehearsals'")
	end
	w:As(a, a.ns.ArenaTest.Clear)
	Relog(w, a, 0, { a, b })
	eq(Get(a, id) and Get(a, id).state, "play", "found again after the /reload")
	assert(Do(w, a, "Concede", id))
	w:Run(0)
	local rows = Best(w, c)
	eq(#rows, 2, "it counts"); eq(Row(rows, b).won, 1)
	NoErrors(w)
end)

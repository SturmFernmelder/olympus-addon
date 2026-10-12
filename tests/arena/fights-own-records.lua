-- 1.2.1, the fights part (ArenaFights.lua): a fighter's own records (his history, myFights, and his
-- games' ledger) take only a fight his own client took part in: accepted, came to the ring, fought,
-- signed for or agreed the challenge of. An arbiter's word naming two players is not their taking
-- part. On the test world. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)

local function Fights(w, c) return W3.M(w, c, "ArenaFights") end
local function State(w, c, fid)
	local f = c.ns.ArenaFights.Find("fights", fid)
	return f and w:As(c, c.ns.ArenaFights.State, f) or nil
end
local function History(w, c) return #w:As(c, c.ns.ArenaFights.MyFights, "L") end
local function Games(w, c) return #W3.M(w, c, "ArenaLedger").MyGames() end
-- The rows of his own fight history as his profile lists them (ArenaLedger.History for his own gk):
-- the fights his client holds as well as his own list.
local function Shown(w, c, fid)
	local gk = w:As(c, c.ns.ArenaFights.MyGk)
	local n = 0
	for _, row in ipairs(W3.M(w, c, "ArenaLedger").History({ gk = gk, mode = "L" })) do
		if row.fid == fid then n = n + 1 end
	end
	return n
end
-- The arbiter's own AF, whispered to each of `to` (a modified client may say anything).
local function Whisper(w, from, to, kind, fields)
	local body = table.concat(fields, "~")
	for _, c in ipairs(to) do
		assert(w:As(from, function() return from.ns.Arena.Send(kind, "L", body, { to = c.name, urgent = true }) end))
	end
	w:Run(0)
end
local function NewFid(w, arb) return w:As(arb, function() return arb.ns.Arena.NewId("F", function() return false end) end) end

-- A public fight judged by the signed arbiter, both fighters' own yes; then called, both at the
-- ring, belled and live (as tests/arena/fights.lua does).
local function Fought(w, cast)
	local AF = Fights(w, cast.arbiter)
	local fid = assert(AF.New({ A = cast.A.name, B = cast.B.name, bo = 1 }))
	assert(AF.Announce(fid))
	w:Run(0)
	eq(Fights(w, cast.A).Accept(fid), true)
	eq(Fights(w, cast.B).Accept(fid), true)
	w:Run(0)
	W3.Stand(cast.arbiter, 100, 100)
	W3.Stand(cast.A, 110, 100)
	W3.Stand(cast.B, 100, 120)
	W3.Sees(cast.arbiter, { [cast.A] = true, [cast.B] = true })
	assert(AF.Call(fid))
	w:Run(0)
	Fights(w, cast.A).Here(fid)
	Fights(w, cast.B).Here(fid)
	w:Run(1)
	assert(AF.Bell(fid))
	w:Run(0)
	w:Run(cast.arbiter.ns.Arena.LastCall(true))
	eq(State(w, cast.arbiter, fid), "L", "live")
	W3.Duel(w, { cast.arbiter, cast.A, cast.B }, cast.A, cast.B)
	w:Run(0)
	w:Run(cast.arbiter.ns.ArenaFights.GRACE + cast.arbiter.ns.ArenaFights.FINAL_SLACK + 1)
	return fid
end

print("1.2.1 the fights part: a fighter's own records")

test("1.2.1 the fights part: an arbiter's word alone writes no fight into a fighter's own records: a final result two members never accepted, came to or fought is in neither one's history nor games' ledger; a fight they fought is", function()
	local w, cast = W3.New()
	local arb, A, B = cast.arbiter, cast.A, cast.B
	-- The arbiter's own AF, whispered to each: a private fight already final, A the winner by knockout.
	local fid = NewFid(w, arb)
	Whisper(w, arb, { A, B }, "AF", { fid, "F", "r", "1", "A", arb.short, "-", A.short, "-", B.short, "-", "0", "0", "0", "1", "1:0", "A", "K", "0" })
	for _, c in ipairs({ A, B }) do
		-- (A private result that is not his own is not held: his profile's history lists what his
		-- client holds as well as his own list.)
		eq(State(w, c, fid), nil, c.short .. " holds no record of it")
		eq(Shown(w, c, fid), 0, c.short .. ": not in the history his profile shows")
		eq(History(w, c), 0, c.short .. ": nothing in his own history")
		eq(Games(w, c), 0, c.short .. ": nothing in his games' ledger")
	end
	-- A fight they accepted, came to and fought: in each one's history.
	local real = Fought(w, cast)
	for _, c in ipairs({ A, B }) do
		eq(State(w, c, real), "F", c.short)
		local mine = w:As(c, c.ns.ArenaFights.MyFights, "L")
		eq(#mine, 1, c.short .. ": the fight he fought")
		eq(mine[1].fid, real, c.short)
		eq(Shown(w, c, real), 1, c.short .. ": in the history his profile shows")
		eq(Games(w, c), 1, c.short .. ": in his games' ledger")
	end
	eq(w:As(A, A.ns.ArenaFights.MyFights, "L")[1].w, "W"); eq(w:As(B, B.ns.ArenaFights.MyFights, "L")[1].w, "L")
	W3.NoErrors(w)
end)

test("1.2.1 the fights part: an arbiter's result for a private fight the fighters never accepted (his AF, then his round's or final AR), or a record with a member's own gk under other names, is held by no one it names and shows in no one's own history", function()
	local w, cast = W3.New()
	local arb, A, B, x = cast.arbiter, cast.A, cast.B, cast.spectator
	-- Announced to both, set, never accepted: each holds it (he may still say yes).
	local fid = NewFid(w, arb)
	Whisper(w, arb, { A, B }, "AF", { fid, "S", "-", "1", "A", arb.short, "-", A.short, "-", B.short, "-", "0", "0", "0", "0", "0:0", "-", "-", "0" })
	for _, c in ipairs({ A, B }) do eq(State(w, c, fid), "S", c.short .. ": the fight he may accept") end
	-- His round's result (A 1:0, its grace already over), then his final word: neither is theirs.
	Whisper(w, arb, { A, B }, "AR", { fid, "1", "1:0", "A", "K", "0", "0", "A", "0", "0", "-" })
	for _, c in ipairs({ A, B }) do
		eq(State(w, c, fid), nil, c.short .. ": a round he never fought is not held")
		eq(Shown(w, c, fid), 0, c.short)
	end
	local fid2 = NewFid(w, arb)
	Whisper(w, arb, { A, B }, "AF", { fid2, "S", "-", "1", "A", arb.short, "-", A.short, "-", B.short, "-", "0", "0", "0", "0", "0:0", "-", "-", "0" })
	Whisper(w, arb, { A, B }, "AR", { fid2, "1", "1:0", "B", "K", "0", "0", "A", "1", "0", "-" })
	for _, c in ipairs({ A, B }) do
		eq(State(w, c, fid2), nil, c.short .. ": a final result of a fight he never accepted")
		eq(Shown(w, c, fid2), 0, c.short)
		eq(History(w, c), 0, c.short)
		eq(Games(w, c), 0, c.short)
	end
	-- Two invented names, the spectator's own gk on the winner: not his, not held.
	local gk = w:As(x, x.ns.ArenaFights.MyGk)
	assert(gk, "the spectator's gk")
	local fid3 = NewFid(w, arb)
	Whisper(w, arb, { x }, "AF", { fid3, "F", "r", "1", "A", arb.short, "-", "Brannoc", gk, "Ysolde", "-", "0", "0", "0", "1", "1:0", "A", "K", "0" })
	eq(State(w, x, fid3), nil, "a record with his gk is not held")
	eq(Shown(w, x, fid3), 0, "nor in the history his profile shows")
	W3.NoErrors(w)
end)

test("1.2.1 the fights part: a private fight a fighter accepted and then missed is still his own: his walkover loss is held and in his history", function()
	local w, cast = W3.New()
	local arb, A, B = cast.arbiter, cast.A, cast.B
	local AF = Fights(w, arb)
	local fid = assert(AF.New({ A = A.name, B = B.name, bo = 1, public = false }))
	assert(AF.Announce(fid))
	w:Run(0)
	eq(Fights(w, A).Accept(fid), true)
	eq(Fights(w, B).Accept(fid), true)
	w:Run(0)
	W3.Stand(arb, 100, 100)
	W3.Stand(A, 105, 100)
	AF.Call(fid) w:Run(0)
	Fights(w, A).Here(fid)
	w:Run(arb.ns.ArenaFights.CALL_WINDOW + arb.ns.ArenaFights.WO_AUTO + 2)
	eq(State(w, arb, fid), "W")
	for _, c in ipairs({ A, B }) do
		eq(State(w, c, fid), "W", c.short .. " holds it")
		eq(Shown(w, c, fid), 1, c.short .. ": in the history his profile shows")
		eq(History(w, c), 1, c.short .. ": in his own list")
	end
	eq(w:As(B, B.ns.ArenaFights.MyFights, "L")[1].w, "L", "the one who missed it lost")
	W3.NoErrors(w)
end)

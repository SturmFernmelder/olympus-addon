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
	local fid = w:As(arb, function() return arb.ns.Arena.NewId("F", function() return false end) end)
	local body = table.concat({ fid, "F", "r", "1", "A", arb.short, "-", A.short, "-", B.short, "-", "0", "0", "0", "1", "1:0", "A", "K", "0" }, "~")
	for _, c in ipairs({ A, B }) do
		assert(w:As(arb, function() return arb.ns.Arena.Send("AF", "L", body, { to = c.name, urgent = true }) end))
	end
	w:Run(0)
	for _, c in ipairs({ A, B }) do
		eq(State(w, c, fid), "F", c.short .. " holds the arbiter's record")
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
		eq(Games(w, c), 1, c.short .. ": in his games' ledger")
	end
	eq(w:As(A, A.ns.ArenaFights.MyFights, "L")[1].w, "W"); eq(w:As(B, B.ns.ArenaFights.MyFights, "L")[1].w, "L")
	W3.NoErrors(w)
end)

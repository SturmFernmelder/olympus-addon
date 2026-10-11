-- 1.2.1, Bones' dice picked while the table is busy for a moment (Olympus_Arena/FarkleBoard.lua's
-- Refresh): a report said a player who picked a 2 and put it back could not roll until he picked it
-- again. The plain pick and put-back was right offline (farkle-board.lua's "deselecting a
-- non-scoring die" test); what went wrong was the light. With the mouse on a die he had picked, a
-- redraw while the table could not be played for a moment (the other player in combat, the
-- player a step outside the inn) put out its light and kept it picked: the 2 looked put back,
-- Keep & roll stayed off ("the 2 doesn't score"), and only another click on it, which put it back
-- for real, let him roll. A picked die now stays lit until it is put back. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local BoardUI = assert(loadfile(H.ROOT .. "tests/arena/lib/board-ui.lua"))(H)
local N = H.World.NAMES

local function check(cond, msg, ...) if not cond then error((msg or "check failed"):format(...), 2) end end
local function Seat(w, name)
	local c = w:Player(name, { companion = {} })
	c.K = BoardUI.New(function() return w.clock end)
	c.K.Install(c.globals)
	c.w = w
	return c
end
local function Board(c) return c.ns.Arena.ui.FarkleBoard end
local function X(c) return Board(c)._ end
local function P(c) return X(c).parts() end
local function R(c) return c.ns.FarkleRules end
local function Click(w, c, b) return w:As(c, function() return c.K.UserClick(b) end) end
local function Roll(c, dice) return (R(c).Encode(dice)) end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
		if c.K then for _, e in ipairs(c.K.errors) do error(c.name .. " (a script): " .. e, 2) end end
	end
end
local function InPlay(c)
	local sd, out = X(c).sides[1], {}
	for j, i in ipairs(sd.play) do out[j] = sd.dice[i] end
	return out
end
local function Step(w, seconds)
	local stop = w.clock + seconds
	while w.clock < stop - 1e-9 do w:Run(math.min(0.05, stop - w.clock)) end
end
local function Until(w, pred, limit)
	local t0 = w.clock
	while not pred() do
		check(w.clock - t0 <= (limit or 30), "waited %.1f s", w.clock - t0)
		Step(w, 0.05)
	end
end
local function Idle(c)
	local S = X(c).S
	if S.animating or #S.queue > 0 or S.flying[1] > 0 or S.flying[2] > 0 then return false end
	return not c.w:As(c, function() return Board(c).Busy(S.id) end)
end
-- The mouse onto a die and off it, as the game calls its scripts.
local function Enter(w, c, d) w:As(c, function() d.f.scripts.OnEnter(d.f) end) end
local function Leave(w, c, d) w:As(c, function() d.f.scripts.OnLeave(d.f) end) end
-- Each die in play shows as picked exactly when it is picked.
local function LightsTrue(c, what)
	for j, d in ipairs(InPlay(c)) do
		check((d.lit and true or false) == (X(c).S.sel[d.i] and true or false),
			"%s: the die %d (a %d) %s but is %s", what, j, d.value, d.lit and "shows picked" or "shows put back",
			X(c).S.sel[d.i] and "picked" or "put back")
	end
end
-- Throws 1 2 3 4 6 6, picks the 1 (the mouse then off it) and the 2 (the mouse left on it).
local function PickOneAndTwo(w, a)
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 6 }))
	check(Click(w, a, P(a).primary), "Roll")
	Until(w, function() return Idle(a) and InPlay(a)[6] and InPlay(a)[6].where == "lane" end, 8)
	local one, two = InPlay(a)[1], InPlay(a)[2]
	eq(one.value, 1); eq(two.value, 2)
	Enter(w, a, one); check(Click(w, a, one.f), "pick the 1"); Leave(w, a, one)
	Enter(w, a, two); check(Click(w, a, two.f), "pick the 2")
	check(one.lit and two.lit and two.hover, "both picked, the mouse on the 2")
	eq(P(a).primary.enabled, false, "the 1 and the 2 don't score together")
	return one, two
end
-- The 2 put back with one click: Keep & roll with the 1 alone.
local function PutBackTwo(w, a, one, two)
	check(Click(w, a, two.f), "put the 2 back")
	check(one.lit and not two.lit, "the 1 alone picked")
	eq(P(a).primary:GetText(), "Keep & roll 5")
	eq(P(a).primary.enabled, true, "Keep & roll on that one click")
	eq(P(a).bank:GetText(), "Bank 100")
end

print("1.2.1: Bones' picked dice stay lit while the table is busy for a moment")

test("1.2.1 Bones selection: the other player in combat a moment while a 2 is picked: the 2 stays lit, and one click puts it back for Keep & roll", function()
	local w = FW.New({ seed = 3 })
	local a, b = Seat(w, N.fighterA), Seat(w, N.fighterB)
	w:Group({ a, b })
	local id = assert(w:As(a, function() return a.ns.FarkleTable.Create({ guest = b.name, target = 2000, rehearsal = true }) end))
	w:Run(0)
	check(Click(w, b, P(b).ask.yes), "the guest's yes")
	w:Run(0)
	w:As(a, function() a.ns.FarkleTable.ShowUI("table", id) end)
	if P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	w:QueueRoll(a.name, 90); w:QueueRoll(b.name, 10)
	w:As(a, function() a.ns.FarkleTable.Roll(id) end); w:As(b, function() b.ns.FarkleTable.Roll(id) end)
	Step(w, 3)
	local one, two = PickOneAndTwo(w, a)
	-- The other player is pulled into a fight: the clock waits, and the table with it.
	w:Fire(b, "PLAYER_REGEN_DISABLED")
	Step(w, 1)
	check(P(a).info:GetText():find("combat", 1, true), "the pause is said: %s", P(a).info:GetText())
	LightsTrue(a, "while the clock waits")
	w:Fire(b, "PLAYER_REGEN_ENABLED")
	Step(w, 1)
	LightsTrue(a, "the fight over")
	check(two.lit, "the 2 still shows picked")
	eq(P(a).primary.enabled, false, "and still doesn't score with the 1")
	PutBackTwo(w, a, one, two)
	NoErrors(w)
end)

test("1.2.1 Bones selection: a step outside the inn in a lesson while a 2 is picked: the 2 stays lit, and one click puts it back for Keep & roll", function()
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = Seat(w, N.fighterA)
	w:Stand(a.name, FW.INN, true)
	w:As(a, function() a.ns.FarkleTable.ShowUI("practice") end)
	if P(a).help and P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	for i, t in ipairs(R(a).TARGETS) do if t == 2000 then Click(w, a, P(a).targets[i]) end end
	check(Click(w, a, P(a).setup.tips), "Show tips")
	check(Click(w, a, P(a).setup.start), "Start")
	w:Run(0)
	eq(a.ns.FarkleTable.Get(X(a).S.id).inn ~= nil, true, "the innkeeper's table")
	local one, two = PickOneAndTwo(w, a)
	-- A step out of the inn's rest area as the table redraws (an arena change heard), and back.
	w:Stand(a.name, FW.ROAD, false)
	w:As(a, function() a.ns.Fire("ARENA_CHANGED") end)
	LightsTrue(a, "a step outside")
	w:Stand(a.name, FW.INN, true)
	w:As(a, function() a.ns.Fire("ARENA_CHANGED") end)
	LightsTrue(a, "back in the inn")
	check(two.lit, "the 2 still shows picked")
	PutBackTwo(w, a, one, two)
	NoErrors(w)
end)

test("1.2.1 Bones selection: a die the mouse is on but never picked loses its hover glow while the table is busy, as before", function()
	local w = FW.New({ seed = 7, compliance = "shipped" })
	local a = Seat(w, N.fighterA)
	w:Stand(a.name, FW.INN, true)
	w:As(a, function() a.ns.FarkleTable.ShowUI("practice") end)
	if P(a).help and P(a).help:IsShown() then Click(w, a, P(a).help.ok) end
	check(Click(w, a, P(a).setup.start), "Start")
	w:Run(0)
	w:QueueRoll(a.name, Roll(a, { 1, 2, 3, 4, 6, 6 }))
	check(Click(w, a, P(a).primary), "Roll")
	Until(w, function() return Idle(a) and InPlay(a)[6] and InPlay(a)[6].where == "lane" end, 8)
	local three = InPlay(a)[3]
	Enter(w, a, three)
	check(three.hover and not three.lit, "hovered, not picked")
	w:Stand(a.name, FW.ROAD, false)
	w:As(a, function() a.ns.Fire("ARENA_CHANGED") end)
	check(not three.hover and not three.lit, "its glow gone while the table can't be played")
	check(not three.f:IsMouseEnabled(), "and it takes no click")
	NoErrors(w)
end)

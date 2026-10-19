-- 1.2.6, Bones' dice picked near their lower edge (Olympus_Arena/FarkleBoard.lua's Draw): the
-- report of a player who picked a 2, put it back and could not roll until he picked it again.
-- bones-pick-busy.lua has the cause found in 1.2.1 (a picked die's light put out by a redraw);
-- this is the other one, in the dice's place on the screen. A die the mouse is on rises a
-- little and a picked one rises more, and the spot that takes its clicks rose with it: picked
-- from near its lower edge, a die was no longer under the mouse, so the next click on that same
-- spot (to put the 2 back) missed it. The 2 stayed picked and Keep & roll stayed off ("the 2
-- doesn't score") until a click higher up. The mouse on that edge also lifted the die off itself
-- and let it drop back, over and over. A die now keeps the bottom of its resting square when it
-- rises, and its raised top too.
-- The stand-in's clicks reach a button however the mouse is placed, so the client's mouse is
-- modelled here: the die whose hit rect (its anchors, size and SetHitRectInsets) holds the point
-- gets the mouse and the click, and the mouse is looked at again after each redraw, as the game
-- does every frame. Every name is invented.
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

-- A die's hit rect on the table (left, top, right, bottom from the table's top left, y down): its
-- frame where its anchors put it (nothing animates on a die at rest), less its hit rect insets.
local function Hit(c, d)
	local K, f = c.K, d.f
	local l, b, r, t = K.Layout(f)
	local wl, _, _, wt = K.Layout(P(c).win)
	local ins = f.insets or { 0, 0, 0, 0 }
	return { l - wl + ins[1], wt - t + ins[3], r - wl - ins[2], wt - b - ins[4] }
end
local function Holds(rect, x, y) return x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4] end
local function Str(r) return ("%.2f,%.2f-%.2f,%.2f"):format(r[1], r[2], r[3], r[4]) end
-- The client's mouse at (x, y) on the table: the die under it (shown, taking the mouse, its hit
-- rect holding the point) gets OnEnter, the one it left OnLeave; looked at again for `frames`
-- frames, since a die that moves under a still mouse is entered or left as it moves. Returns how
-- often the mouse went onto or off a die.
local function MouseAt(w, c, m, x, y, frames)
	local changes = 0
	for _ = 1, frames or 1 do
		local under
		for _, d in ipairs(X(c).sides[1].dice) do
			if d.f:IsShown() and d.f:IsMouseEnabled() and Holds(Hit(c, d), x, y) then under = d end
		end
		if under ~= m.on then
			if m.on then local old = m.on; w:As(c, function() old.f.scripts.OnLeave(old.f) end) end
			m.on = under
			if under then w:As(c, function() under.f.scripts.OnEnter(under.f) end) end
			changes = changes + 1
		end
	end
	m.x, m.y = x, y
	return changes
end
-- A click where the mouse is: it reaches the die under it, if any.
local function ClickHere(w, c, m)
	MouseAt(w, c, m, m.x, m.y)
	return m.on ~= nil and Click(w, c, m.on.f)
end

-- A lesson against the House, the player's throw 1 2 3 4 6 6 on the table.
local function Thrown()
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
	Step(w, 0.3) -- (the landing's settle over)
	local one, two = InPlay(a)[1], InPlay(a)[2]
	eq(one.value, 1); eq(two.value, 2)
	return w, a, one, two
end

print("1.2.6: Bones' dice picked near their lower edge")

test("1.2.6 Bones selection: a 2 picked near its lower edge is put back by a click on that same spot, and Keep & roll comes on", function()
	local w, a, one, two = Thrown()
	local m = {}
	local r1 = Hit(a, one)
	MouseAt(w, a, m, (r1[1] + r1[3]) / 2, (r1[2] + r1[4]) / 2)
	check(m.on == one and ClickHere(w, a, m), "pick the 1 from its middle")
	-- the 2 at rest: its square, as before
	local rest = Hit(a, two)
	eq(math.floor(rest[3] - rest[1] + 0.5), 44, "a resting die's hit square, wide")
	eq(math.floor(rest[4] - rest[2] + 0.5), 44, "and high")
	-- The mouse onto the 2 two points above its lower edge, and a click: the 2 picked.
	local x, y = (rest[1] + rest[3]) / 2, rest[4] - 2
	MouseAt(w, a, m, x, y, 4)
	check(m.on == two and two.hover, "the mouse on the 2, its glow on")
	check(ClickHere(w, a, m), "pick the 2")
	check(two.lit and X(a).S.sel[two.i], "the 2 picked")
	eq(P(a).primary.enabled, false, "the 1 and the 2 don't score together")
	-- The report: the same spot clicked again to put the 2 back.
	local reached = ClickHere(w, a, m)
	check(reached, "the click on the spot the 2 was picked from reaches it: (%.2f, %.2f), its hit rect %s", x, y, Str(Hit(a, two)))
	check(not two.lit and not X(a).S.sel[two.i], "the 2 put back")
	check(one.lit and X(a).S.sel[one.i], "the 1 still picked")
	eq(P(a).primary:GetText(), "Keep & roll 5")
	eq(P(a).primary.enabled, true, "Keep & roll on that one click")
	eq(P(a).bank:GetText(), "Bank 100")
	NoErrors(w)
end)

test("1.2.6 Bones selection: the mouse a point above a die's lower edge enters it once; the die does not rise off the mouse and drop back under it", function()
	local w, a, _, two = Thrown()
	local m = {}
	local rest = Hit(a, two)
	local x, y = (rest[1] + rest[3]) / 2, rest[4] - 1
	local changes = MouseAt(w, a, m, x, y, 12)
	eq(changes, 1, "the mouse went onto or off the 2 this often in 12 frames (its hit rect " .. Str(Hit(a, two)) .. ")")
	check(m.on == two and two.hover, "the mouse on the 2, its glow on")
	check(ClickHere(w, a, m), "pick the 2")
	eq(MouseAt(w, a, m, x, y, 12), 0, "the picked 2 still under the mouse")
	check(ClickHere(w, a, m) and not two.lit and not X(a).S.sel[two.i], "and put back from there")
	NoErrors(w)
end)

test("1.2.6 Bones selection: a raised die still takes a click on its raised top, and a resting die's square is unchanged", function()
	local w, a, one, two = Thrown()
	local m = {}
	local rest = Hit(a, two)
	MouseAt(w, a, m, (rest[1] + rest[3]) / 2, (rest[2] + rest[4]) / 2)
	check(m.on == two and ClickHere(w, a, m), "pick the 2 from its middle")
	local up = Hit(a, two)
	check(up[2] < rest[2] - 4, "the picked 2's hit rect reaches its raised top: %s over %s", Str(up), Str(rest))
	check(up[4] >= rest[4] - 0.01, "and still the bottom of its resting square: %s over %s", Str(up), Str(rest))
	check(up[1] <= rest[1] + 0.01 and up[3] >= rest[3] - 0.01, "and its sides: %s over %s", Str(up), Str(rest))
	-- the mouse to its raised top (above where it rests) and a click there puts it back
	MouseAt(w, a, m, (up[1] + up[3]) / 2, up[2] + 1, 4)
	check(m.on == two, "the raised top of the 2 under the mouse")
	check(ClickHere(w, a, m), "click its raised top")
	check(not two.lit and not X(a).S.sel[two.i], "the 2 put back")
	-- the mouse gone: every die in play rests in its own 44 square, none reaching another's lane
	MouseAt(w, a, m, -100, -100)
	local last
	for _, d in ipairs(InPlay(a)) do
		local h = Hit(a, d)
		eq(math.floor(h[3] - h[1] + 0.5), 44, "die " .. d.i .. " wide")
		eq(math.floor(h[4] - h[2] + 0.5), 44, "die " .. d.i .. " high")
		if last then check(h[1] > last[3], "die %d clear of the one before it", d.i) end
		last = h
	end
	check(one.f:IsMouseEnabled(), "the dice still take the mouse")
	NoErrors(w)
end)

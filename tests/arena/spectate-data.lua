-- 1.2.6, Watch duel (Daniel's duel-view request, 2026-10-19): the duel view's data, ArenaSpectate.lua,
-- on the test world: who is watched (the menu line, /oly arena watch, the viewer's own duel), each
-- fighter's unit while in sight, the live values going from the game into the view's widgets and
-- never into the model (Forever's secrets), Era's and TBC's plain values, the cast, the result
-- line, the gear's stats and the talents from an inspection, the status line, the copyable text,
-- the weight rule. Inspect.lua's wants have their tests in tests/run.lua's Inspect section (the
-- arena world does not load Inspect.lua): here Inspect stands in at that boundary, its own
-- ReadGear the real one. Every name is invented; the game's functions are stand-ins shaped as
-- Forever's documentation gives them (F docs UnitDocumentation.lua, SharedTraitsDocumentation.lua,
-- SpecializationInfoDocumentation.lua, ItemDocumentation.lua) and Era's/TBC's.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local Secret = assert(loadfile(H.ROOT .. "tests/arena/lib/secret.lua"))()
local N = World.NAMES

local function S(w, c) return W3.M(w, c, "ArenaSpectate") end
local function Printed(c, text)
	for _, line in ipairs(c.printed) do if line:find(text, 1, true) then return true end end
	return false
end

local SW = assert(loadfile(H.ROOT .. "tests/arena/lib/spectate-world.lua"))(H)
local Scene, StubInspect, Answer, ForeverTalents = SW.Scene, SW.StubInspect, SW.Answer, SW.ForeverTalents

-- A StatusBar, a FontString, a Texture of the view (the calls they get).
local function Bar()
	local b = {}
	function b:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
	function b:SetValue(v) self.value = v end
	return b
end
local function Text()
	local t = {}
	function t:SetText(s) self.value, self.fmt, self.args = s, nil, nil end
	function t:SetFormattedText(fmt, ...)
		self.fmt, self.args = fmt, { ... }
		local ok, s = pcall(string.format, fmt, ...)
		self.value = ok and s or nil
	end
	function t:SetTexture(v) self.texture = v end
	return t
end
local function Widgets()
	return { health = Bar(), power = Bar(), healthText = Text(), healthPct = Text(), powerText = Text() }
end

-- Two fighters and a spectator (an ordinary member: no role, no rules' yes needed to watch).
local function Cast(opts)
	local w = World.New(opts)
	local cast = { A = w:Role("fighterA"), B = w:Role("fighterB"), V = w:Role("bettor1"), C = w:Role("bettor2") }
	return w, cast
end

print("ArenaSpectate: who is watched")

test("watch duel: the menu line shows on a player whose target is another player he can attack (the game's plain true); not when UnitCanAttack is false, nothing or secret; the pair is the one of the right-click, whatever the target does after", function()
	local w, cast = Cast()
	local V = cast.V
	local o = Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	local function Lines(target)
		local lines = {}
		local menu = { Button = function(text, fn) lines[#lines + 1] = { text = text, fn = fn } end }
		w:As(V, V.ns.ArenaHome.MenuLines, target, menu)
		local found
		for _, l in ipairs(lines) do if l.text == V.ns.L.ARENA_MENU_WATCH_DUEL then found = l end end
		return found, #lines
	end
	local target = { name = cast.A.name, unit = "target" }
	local line = Lines(target)
	assert(line, "Watch duel in the menu")
	for _, v in ipairs({ false, "none", "secret" }) do
		o.canAttack = v
		eq(Lines(target), nil, "UnitCanAttack " .. tostring(v) .. ": no line")
	end
	o.canAttack = nil
	-- Not a player's target, the same unit, a chat name with no unit: no line.
	o.units.targettarget = cast.A
	eq(Lines(target), nil, "his target is himself")
	o.units.targettarget = nil
	eq(Lines(target), nil, "no target")
	eq(Lines({ name = cast.A.name }), nil, "a chat name, no fight of the viewer's")
	o.units.targettarget = cast.B
	line = Lines(target)
	-- The click: the pair of the right-click, though his target changed since.
	W3.Companion(w, V)
	local shown = {}
	V.ns.Arena.ui.Spectate = { Show = function(subject) shown[#shown + 1] = subject return true end }
	o.units.targettarget = cast.C
	w:As(V, line.fn)
	eq(#shown, 1, "ArenaHome.Open(\"duel.watch\") reached the view")
	eq(shown[1].A.name, cast.A.name); eq(shown[1].B.name, cast.B.name, "the pair taken at the right-click")
	eq(shown[1].A.guid, cast.A.guid); eq(shown[1].B.gk, V.ns.Arena.GK(cast.B.guid))
	eq(shown[1].olympus, false, "no Olympus fight this client knows of"); eq(shown[1].own, nil)
	eq(shown[1].B.unit, "targettarget", "the token it came from, looked at first for him")
	W3.NoErrors(w)
end)

test("watch duel: /oly arena watch takes the viewer's own duel, else his target and its target, else his target and focus, else a named fighter in sight; it says why when there is none; off closes", function()
	local w, cast = Cast()
	local V = cast.V
	local o = Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	StubInspect(V)
	W3.Companion(w, V)
	local shown = {}
	V.ns.Arena.ui.Spectate = { Show = function(subject) shown[#shown + 1] = subject w:As(V, V.ns.ArenaSpectate.Start, subject) return true end,
		Hide = function() shown.hidden = (shown.hidden or 0) + 1 end }
	w:As(V, V.ns.Arena.RunSlash, "watch")
	eq(#shown, 1); eq(shown[1].A.name, cast.A.name); eq(shown[1].B.name, cast.B.name); eq(shown[1].how, "slash")
	-- Target and focus.
	o.units.targettarget, o.units.focus = nil, cast.C
	w:As(V, V.ns.Arena.RunSlash, "watch")
	eq(shown[2].A.name, cast.A.name); eq(shown[2].B.name, cast.C.name)
	-- A named fighter, by the token the game gives him (his nameplate) and that token's target.
	o.units = { nameplate2 = cast.B, nameplate2target = cast.A }
	w:As(V, V.ns.Arena.RunSlash, "watch Selka Drummond")
	eq(shown[3].A.name, cast.B.name, "the named fighter first"); eq(shown[3].B.name, cast.A.name)
	-- Nobody in sight: a line saying what to do; nothing opened.
	o.units = {}
	w:As(V, V.ns.Arena.RunSlash, "watch")
	assert(Printed(V, V.ns.L.ARENA_WATCH_NONE), "says how to pick a duel")
	w:As(V, V.ns.Arena.RunSlash, "watch Selka Drummond")
	assert(Printed(V, V.ns.L.ARENA_WATCH_NO_SIGHT:format("Selka Drummond")), "says he is not in sight")
	eq(#shown, 3)
	-- Off: the view hidden and the session over.
	assert(S(w, V).Watching(), "watching")
	w:As(V, V.ns.Arena.RunSlash, "watch off")
	eq(shown.hidden, 1); eq(S(w, V).Watching(), nil)
	W3.NoErrors(w)
end)

test("watch duel: a fighter's own duel (an agreed direct challenge) is his subject: his side, the fight's id, best of, round and score in the model; his own gear and talents read at once; watching sends nothing", function()
	local w, cast = W3.New({ live = false, world = { compliance = "shipped" } })
	local A, B = cast.A, cast.B
	local oid = assert(W3.M(w, A, "ArenaFights").Challenge(B.name, { bo = 3 }))
	w:Run(0)
	assert(W3.M(w, B, "ArenaFights").Answer(oid, true))
	w:Run(0)
	Scene(w, A, { units = { target = B }, items = { [A] = { [1] = { id = 1001, link = "|cff1eff00|Hitem:1001::::::::60:::::|h[Ring Helm]|h|r" } } },
		stats = { [1001] = { ITEM_MOD_STAMINA_SHORT = 7 } } })
	StubInspect(A)
	local own = S(w, A).OwnFight()
	assert(own and own.fid, "his own fight")
	eq(own.own, "A"); eq(own.olympus, true); eq(own.A.name, A.name); eq(own.B.name, B.name)
	-- The menu line on his opponent, from a chat name too: his own duel.
	local watch = S(w, A).Watchable({ name = B.name })
	assert(watch, "Watch duel on his opponent"); eq(watch.fid, own.fid)
	local sent = #w.sent
	assert(S(w, A).Start(own))
	local m = S(w, A).Model()
	eq(m.fight.fid, own.fid); eq(m.fight.bo, 3); eq(m.fight.round, 0); eq(m.fight.a, 0); eq(m.fight.b, 0); eq(m.fight.state, "S")
	eq(m.sides.A.inspect.status, "own"); eq(m.sides.A.gear[1], "item:1001::::::::60"); eq(m.sides.A.stats.sta, 7)
	eq(A.ns.Inspect.wants["spectate:A"], nil, "no inspection of himself"); assert(A.ns.Inspect.wants["spectate:B"], "his opponent's asked")
	eq(S(w, A).StatusLine("A"), A.ns.L.ARENA_WATCH_ST_OWN)
	w:Run(5)
	S(w, A).Stop()
	eq(#w.sent, sent, "watching sends nothing")
	W3.NoErrors(w)
end)

print("ArenaSpectate: the live values")

test("watch duel: Forever's secret health, power and percentages go from the game into the bars and texts unchanged, no error; the model and the copyable text hold none", function()
	local w, cast = Cast()
	local V = cast.V
	local o = Scene(w, V, { units = { target = cast.A, targettarget = cast.B }, bodies = {
		[cast.A] = { secret = true, hpMax = 2138, powerMax = 100, powerType = { 3, "ENERGY" }, class = { "Rogue", "ROGUE", 4 }, race = { "Undead", "Scourge", 5 } },
		[cast.B] = { secret = true, hpMax = 1960, powerMax = 100, class = { "Hunter", "HUNTER", 3 }, race = { "Orc", "Orc", 2 } } } })
	StubInspect(V)
	V.ns.ArenaSpectate.ResetCurve()
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	local wa, wb = Widgets(), Widgets()
	eq(S(w, V).Push("A", wa), true); eq(S(w, V).Push("B", wb), true)
	eq(S(w, V).Token("B"), "targettarget", "B through the token the pair came from")
	eq(wa.health.min, 0); eq(wa.health.max, 2138, "UnitHealthMax: plain for a player")
	assert(Secret.Is(wa.health.value), "the secret health reached SetValue unchanged")
	eq(wa.healthText.fmt, "%d / %d"); assert(Secret.Is(wa.healthText.args[1]), "cur, secret"); eq(wa.healthText.args[2], 2138)
	eq(wa.healthPct.fmt, "%.0f%%"); assert(Secret.Is(wa.healthPct.args[1]), "UnitHealthPercent's secret into SetFormattedText")
	assert(Secret.Is(wa.power.value)); eq(wa.power.max, 100)
	eq(wa.powerText.fmt, "%.0f%%"); assert(Secret.Is(wa.powerText.args[1]))
	-- The percentages asked with the 0-100 curve (an in-game probe: S.PCT_SCALE).
	local curve = o.percent[1].curve
	assert(curve, "a curve passed"); eq(table.concat(curve.points, " "), "0,0 1,100")
	local m = S(w, V).Model()
	eq(Secret.Any(m), false, "no secret in the model")
	eq(m.sides.A.className, "Rogue"); eq(m.sides.A.raceName, "Undead"); eq(m.sides.A.powerToken, "ENERGY"); eq(m.sides.A.inSight, true)
	local text = S(w, V).Text(m)
	assert(type(text) == "string" and text:find("Torvin Hale", 1, true), text)
	assert(text:find(V.ns.L.ARENA_WATCH_NOT_OLYMPUS, 1, true), "labelled: not an Olympus duel")
	W3.NoErrors(w)
end)

test("watch duel: Era's and TBC's plain values: 37 of 100 for a player outside the group shows \"37%\", 847 of 2239 for a group member \"847 / 2239\"; power in percent", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, party1 = cast.B }, bodies = {
		[cast.A] = { hp = 37, hpMax = 100, power = 30, powerMax = 120 }, [cast.B] = { hp = 847, hpMax = 2239 } } })
	StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnits("target", "party1"))))
	local wa, wb = Widgets(), Widgets()
	S(w, V).Push("A", wa)
	S(w, V).Push("B", wb)
	eq(wa.healthText.value, "37%"); eq(wa.health.value, 37); eq(wa.health.max, 100)
	eq(wa.healthPct.value, "37%"); eq(wa.powerText.value, "25%")
	eq(wb.healthText.value, "847 / 2239"); eq(wb.healthPct.value, "38%")
	W3.NoErrors(w)
end)

test("watch duel: out of sight the bars empty and say \"—\" and the class and race come from the game's word on the GUID; a nameplate showing him brings him back at the next forced sight pass", function()
	local w, cast = Cast()
	local V = cast.V
	local o = Scene(w, V, { units = { target = cast.A, targettarget = cast.B }, bodies = {
		[cast.A] = { class = { "Mage", "MAGE", 8 }, race = { "Gnome", "Gnome", 7 }, hp = 1200, hpMax = 1500 } } })
	StubInspect(V)
	local subject = assert(S(w, V).PairFromUnit("target"))
	o.units = {}
	assert(S(w, V).Start(subject))
	local wa = Widgets()
	eq(S(w, V).Push("A", wa), false)
	eq(wa.health.max, 1); eq(wa.health.value, 0); eq(wa.healthText.value, V.ns.L.ARENA_WATCH_DASH)
	local m = S(w, V).Model()
	eq(m.sides.A.inSight, false); eq(m.sides.A.class, "MAGE"); eq(m.sides.A.raceName, "Gnome")
	eq(S(w, V).StatusLine("A"), V.ns.L.ARENA_WATCH_ST_INSPECTING, "his inspection waits its turn (Inspect says why)")
	-- NAME_PLATE_UNIT_ADDED: the view forces a sight pass.
	o.units.nameplate4 = cast.A
	S(w, V).Track(true)
	eq(S(w, V).Token("A"), "nameplate4")
	eq(S(w, V).Push("A", wa), true); eq(wa.healthText.value, "1200 / 1500")
	-- His opponent, whose own target he is: through that token ("nameplate4target").
	o.units.nameplate4target = cast.B
	S(w, V).Track(true)
	eq(S(w, V).Token("B"), "nameplate4target")
	W3.NoErrors(w)
end)

test("watch duel: the cast: none when isTradeskill (never secret) is nil; a secret cast's name, icon and fill set from the game unchanged, no seconds; Era's cast with its seconds; a channel says so", function()
	local w, cast = Cast()
	local V = cast.V
	local now = w.clock
	local o = Scene(w, V, { units = { target = cast.A, focus = cast.B }, bodies = {
		[cast.A] = { secret = true }, [cast.B] = { cast = { name = "Frostbolt", texture = 135846, start = now * 1000, finish = (now + 2.5) * 1000 } } } })
	StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnits("target", "focus"))))
	local wc = { bar = Bar(), name = Text(), icon = Text(), time = Text() }
	eq(S(w, V).Cast("A", wc), nil, "no cast")
	eq(wc.name.value, nil, "nothing set")
	o.bodies[cast.A].cast = { name = "Shadow Bolt", texture = 136197, start = 1, finish = 2 }
	eq(S(w, V).Cast("A", wc), "cast")
	assert(Secret.Is(wc.name.value), "the secret name into SetText"); assert(Secret.Is(wc.icon.texture), "the secret icon into SetTexture")
	assert(Secret.Is(wc.bar.min) and Secret.Is(wc.bar.max), "the secret start and end into SetMinMaxValues")
	eq(wc.bar.value, now * 1000, "the fill: the client's clock"); eq(wc.time.value, "", "no seconds for a secret cast")
	local wb = { bar = Bar(), name = Text(), icon = Text(), time = Text() }
	eq(S(w, V).Cast("B", wb), "cast")
	eq(wb.name.value, "Frostbolt"); eq(wb.icon.texture, 135846); eq(wb.time.value, "2.5")
	o.bodies[cast.B].cast = { name = "First Aid", texture = 133685, start = now * 1000, finish = (now + 8) * 1000, channel = true }
	eq(S(w, V).Cast("B", wb), "channel"); eq(wb.time.value, "8.0")
	eq(Secret.Any(S(w, V).Model()), false)
	W3.NoErrors(w)
end)

test("watch duel: in combat (UnitAffectingCombat, plain) either fighter: true; neither: false; unknown (secret, out of sight): nil, the view kept as it is", function()
	local w, cast = Cast()
	local V = cast.V
	local o = Scene(w, V, { units = { target = cast.A, focus = cast.B }, bodies = { [cast.A] = { combat = true }, [cast.B] = { combat = false } } })
	StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnits("target", "focus"))))
	eq(S(w, V).Fighting(), true)
	o.bodies[cast.A].combat = false
	eq(S(w, V).Fighting(), false)
	o.bodies[cast.A].combat = "secret"
	o.units.focus = nil
	S(w, V).Track(true)
	eq(S(w, V).Fighting(), nil, "A's word secret, B out of sight")
	W3.NoErrors(w)
end)

test("watch duel: the game's duel line read by a spectator gives the result (knockout or fled), and nothing else: no fight record, no report, no ledger row, nothing sent", function()
	local w, cast = W3.New({ live = false, world = { compliance = "shipped" } })
	local V = cast.spectator
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	StubInspect(V)
	local fights = #W3.M(w, V, "ArenaFights").List()
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	local sent = #w.sent
	eq(S(w, V).OnSystem(W3.DUEL_KO:format(cast.B.short, cast.A.short)), "B")
	local m = S(w, V).Model()
	eq(m.result.w, "B"); eq(m.result.m, "K")
	assert(S(w, V).Text():find(V.ns.L.ARENA_WATCH_WON_KO:format("Selka Drummond"), 1, true))
	eq(S(w, V).OnSystem(W3.DUEL_FLED:format(cast.A.short, cast.B.short)), "B", "the one who fled lost")
	eq(S(w, V).Model().result.m, "R")
	eq(S(w, V).OnSystem(W3.DUEL_KO:format("Someone Else", cast.A.short)), nil, "another pair's line")
	eq(S(w, V).OnSystem(Secret.New()), nil, "a secret line is no error")
	W3.Duel(w, { V }, cast.A, cast.B)
	w:Run(30)
	eq(#W3.M(w, V, "ArenaFights").List(), fights, "no fight record")
	for _, kind in ipairs({ "AW", "AX", "AR", "AG", "AF", "AE" }) do eq(#W3.Bodies(w, V, kind), 0, "no " .. kind) end
	eq(#w.sent, sent, "nothing sent")
	S(w, V).Stop()
	W3.NoErrors(w)
end)

print("ArenaSpectate: gear, stats, talents")

test("watch duel: the inspection's reader keeps the gear's item strings and sums the items' own stats (C_Item.GetItemStats): unknown keys ignored, one key an item counts once; an item not cached is asked again each second, five times", function()
	local w, cast = Cast()
	local V = cast.V
	local o = Scene(w, V, { units = { target = cast.A, targettarget = cast.B },
		items = { [cast.A] = {
			[1] = { id = 1001, link = "|cff1eff00|Hitem:1001::::::::60:::::|h[Ring Helm]|h|r" },
			[5] = { id = 1002 },
			[16] = { id = 1003, link = "|cffa335ee|Hitem:1003:1900::::::::60:::::|h[Notched Blade]|h|r" } } },
		stats = { [1001] = { ITEM_MOD_STRENGTH_SHORT = 11, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE0_NAME = 300, RESISTANCE3_NAME = 9, ITEM_MOD_NOT_A_ROW = 99 },
			[1002] = { ITEM_MOD_AGILITY_SHORT = 20, ITEM_MOD_HIT_RATING_SHORT = 10, ITEM_MOD_HIT_MELEE_RATING_SHORT = 10 },
			[1003] = { ITEM_MOD_AGILITY_SHORT = 5, RESISTANCE5_NAME = 5 } },
		uncached = { [1003] = true } })
	local I = StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	eq(I.wants["spectate:A"].guid, cast.A.guid); eq(I.wants["spectate:B"].guid, cast.B.guid)
	eq(Answer(w, V, I, "spectate:A"), "target", "the reader on his token")
	local m = S(w, V).Model()
	eq(m.sides.A.gear[1], "item:1001::::::::60"); eq(m.sides.A.gear[5], "item:1002"); eq(m.sides.A.gearN, 3)
	eq(m.sides.A.stats.str, 11); eq(m.sides.A.stats.sta, 8); eq(m.sides.A.stats.armor, 300); eq(m.sides.A.stats.agi, 20)
	eq(m.sides.A.stats.hit, 10, "one key an item counts once"); eq(m.sides.A.resist.nature, 9); eq(m.sides.A.resist.shadow, 0, "not cached yet")
	eq(m.sides.A.statsPending, true); eq(o.loads[1], 1003, "asked for")
	o.uncached[1003] = nil
	w:Run(1)
	m = S(w, V).Model()
	eq(m.sides.A.stats.agi, 25); eq(m.sides.A.resist.shadow, 5); eq(m.sides.A.statsPending, false)
	-- Never cached: five more tries, then it stops.
	o.uncached[1001] = true
	S(w, V).Reinspect("A")
	Answer(w, V, I, "spectate:A")
	local loads = #o.loads
	w:Run(30)
	eq(#o.loads - loads, V.ns.ArenaSpectate.STATS_TRIES, "five retries")
	eq(S(w, V).Model().sides.A.statsPending, true)
	eq(Secret.Any(S(w, V).Model()), false)
	S(w, V).Stop()
	eq(V.ns.Arena.Ticking(), false, "the retries gone with the session")
	W3.NoErrors(w)
end)

test("watch duel: Forever's talents: each tree's grid from the trait tree (tier, column, rank, max, icon), its name and points; a talent's tooltip: its name, Passive, its description, Rank r / max", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B }, bodies = { [cast.A] = { class = { "Rogue", "ROGUE", 4 } } } })
	ForeverTalents(V.globals)
	local I = StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	Answer(w, V, I, "spectate:A")
	local t = S(w, V).Model().sides.A.talents
	eq(t.source, "traits"); eq(t.grid, true); eq(t.total, 5); eq(#t.trees, 3)
	local a, c, s = t.trees[1], t.trees[2], t.trees[3]
	eq(a.name, "Assassination"); eq(a.points, 5); eq(a.tiers, 2); eq(a.columns, 2); eq(#a.talents, 3); eq(a.icon, 111)
	eq(a.talents[1].name, "Talent 11201"); eq(a.talents[1].tier, 1); eq(a.talents[1].column, 1); eq(a.talents[1].rank, 3); eq(a.talents[1].max, 5)
	eq(a.talents[1].icon, 141201); eq(a.talents[1].entryID, 201)
	eq(a.talents[2].column, 2); eq(a.talents[2].rank, 0, "an untaken talent: 0, the view dims it")
	eq(a.talents[3].tier, 2); eq(a.talents[3].max, 2)
	eq(c.name, "Combat"); eq(c.points, 0); eq(#c.talents, 1)
	eq(s.name, "Subtlety"); eq(#s.talents, 0, "a hidden node left out")
	local lines = S(w, V).TalentLines(a.talents[1])
	eq(lines.title, "Talent 11201"); eq(lines.kind, V.ns.L.ARENA_WATCH_PASSIVE); eq(lines.desc, "Reduces your speed penalty by 9%.")
	eq(lines.rank, V.ns.L.ARENA_WATCH_RANK:format(3, 5))
	eq(S(w, V).TalentLines(a.talents[2]).kind, V.ns.L.ARENA_WATCH_ACTIVE)
	W3.NoErrors(w)
end)

test("watch duel: Era's and TBC's talents (C_SpecializationInfo.GetTalentInfo on the inspected player, as its own inspect frame asks); points only where the client gives no grid; a secret count hidden (\"—\"), never guessed; nothing at all: nil", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	local g = V.globals
	local TALENTS = {
		{ { talentID = 1, name = "Improved Heroic Strike", icon = 132282, tier = 1, column = 1, rank = 3, maxRank = 3, spellID = 12282 },
			{ talentID = 2, name = "Deflection", icon = 132269, tier = 1, column = 2, rank = 2, maxRank = 5, spellID = 16462 } },
		{ { talentID = 3, name = "Cruelty", icon = 132292, tier = 1, column = 2, rank = 0, maxRank = 5, spellID = 12320 } },
		{ { talentID = 4, name = "Shield Specialization", icon = 134952, tier = 1, column = 2, rank = 0, maxRank = 5, spellID = 12298 } },
	}
	g.GetNumTalentTabs = function(inspect) assert(inspect == true, "the inspected player's") return 3 end
	g.GetNumTalents = function(tab) return #TALENTS[tab] end
	local points = { 5, 0, 0 }
	g.C_SpecializationInfo = {
		GetActiveSpecGroup = function() return 1 end,
		GetNumSpecializationsForClassID = function() return 3 end,
		GetSpecializationInfo = function(i) return 0, ({ "Arms", "Fury", "Protection" })[i], "", 200 + i, nil, nil, points[i] end,
		GetTalentInfo = function(q)
			assert(q.isInspect == true and q.groupIndex == 1, "an inspect query")
			return TALENTS[q.specializationIndex][q.talentIndex]
		end,
	}
	local I = StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	Answer(w, V, I, "spectate:A")
	local t = S(w, V).Model().sides.A.talents
	eq(t.source, "talents"); eq(t.grid, true); eq(t.trees[1].name, "Arms"); eq(t.trees[1].points, 5); eq(t.trees[1].columns, 2)
	eq(t.trees[1].talents[2].name, "Deflection"); eq(t.trees[1].talents[2].talentID, 2); eq(t.trees[3].talents[1].rank, 0)
	-- No grid on this client: the points per tree alone.
	g.GetNumTalentTabs, g.GetNumTalents = nil, nil
	g.C_SpecializationInfo.GetTalentInfo = nil
	S(w, V).Reinspect("A")
	Answer(w, V, I, "spectate:A")
	t = S(w, V).Model().sides.A.talents
	eq(t.source, "spec"); eq(t.grid, false); eq(t.trees[2].name, "Fury"); eq(t.trees[1].points, 5)
	-- A secret count: hidden.
	points[1] = Secret.New()
	S(w, V).Reinspect("A")
	Answer(w, V, I, "spectate:A")
	t = S(w, V).Model().sides.A.talents
	eq(t.trees[1].points, nil); eq(t.trees[1].secret, true); eq(Secret.Any(t), false)
	assert(S(w, V).Text():find("Arms " .. V.ns.L.ARENA_WATCH_DASH, 1, true), "\"—\" in the text")
	-- Nothing given: nil.
	g.C_SpecializationInfo = nil
	S(w, V).Reinspect("A")
	Answer(w, V, I, "spectate:A")
	eq(S(w, V).Model().sides.A.talents, nil)
	W3.NoErrors(w)
end)

-- The regression (1.2.6): UNIT_INVENTORY_CHANGED from a fighter before his first read asked again
-- at once (REINSPECT_GAP after "never": minus infinity), and asking again replaced his request on
-- its way, so its answer was dropped and he was asked once more: a fighter changing gear at the
-- start could keep the view from ever showing his gear. With the fix taken out, the asks counted
-- below go up at each event.
test("watch duel: his gear changing (UNIT_INVENTORY_CHANGED) before his first read or while his inspection is on its way asks nothing then, and he is looked at again REINSPECT_GAP after that read; after a read, REINSPECT_GAP after it at the soonest, one ask however many events", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	local I = StubInspect(V)
	local GAP = V.ns.ArenaSpectate.REINSPECT_GAP
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	eq(I.asked["spectate:A"], 1, "asked at the start")
	I.wants["spectate:A"].status = "pending" -- (its request out)
	for _ = 1, 3 do eq(S(w, V).OnInventory("target"), false) end
	eq(I.asked["spectate:A"], 1, "nothing asked while it is on its way")
	eq(I.wants["spectate:A"].status, "pending", "its request still the one out")
	Answer(w, V, I, "spectate:A")
	w:Run(GAP - 1)
	eq(I.asked["spectate:A"], 1, "not before REINSPECT_GAP")
	w:Run(2)
	eq(I.asked["spectate:A"], 2, "the change seen on its way: looked at again once, after the read")
	Answer(w, V, I, "spectate:A")
	w:Run(5)
	for _ = 1, 4 do S(w, V).OnInventory("target") end
	eq(I.asked["spectate:A"], 2, "not at once after a read")
	w:Run(GAP)
	eq(I.asked["spectate:A"], 3, "one ask for the four events")
	w:Run(GAP * 3)
	eq(I.asked["spectate:A"], 3, "and no more without a change")
	-- B: never read and given up (no answer, WANT_TRIES times): his gear changing asks nothing.
	local wantB = I.wants["spectate:B"]
	wantB.status, wantB.tries = "timeout", I.WANT_TRIES
	S(w, V).OnInventory("targettarget")
	w:Run(GAP * 2)
	eq(I.asked["spectate:B"], 1, "Inspect again is his")
	S(w, V).Stop()
	eq(V.ns.Arena.Ticking(), false, "nothing left running")
	W3.NoErrors(w)
end)

-- The regression (1.2.6): Era's and TBC's TalentInfoResult gives spellID 0 by default (classic_era
-- SpecializationInfoDocumentation.lua), and the talent kept 0 as its spell: its tooltip asked spell
-- 0 whether it is passive and what it does.
test("watch duel: a talent whose result gives spellID 0 has no spell: nothing asked about spell 0, its tooltip its name and rank alone; a real spell's its Passive and what it does", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	local g = V.globals
	local asked = {}
	g.C_Spell = nil -- (the legacy spell functions, below)
	g.IsPassiveSpell = function(id) asked[#asked + 1] = id return true end
	g.GetSpellDescription = function(id) asked[#asked + 1] = id return "What spell " .. id .. " does." end
	g.GetNumTalentTabs = function() return 1 end
	g.GetNumTalents = function() return 2 end
	local TALENTS = { { talentID = 1, name = "Deflection", icon = 132269, tier = 1, column = 1, rank = 2, maxRank = 5, spellID = 0 },
		{ talentID = 2, name = "Cruelty", icon = 132292, tier = 1, column = 2, rank = 1, maxRank = 5, spellID = 12320 } }
	g.C_SpecializationInfo = {
		GetActiveSpecGroup = function() return 1 end,
		GetTalentInfo = function(q) return TALENTS[q.talentIndex] end,
	}
	local I = StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	Answer(w, V, I, "spectate:A")
	local t = S(w, V).Model().sides.A.talents.trees[1].talents
	eq(t[1].name, "Deflection"); eq(t[1].spellID, nil, "no spell 0")
	local lines = S(w, V).TalentLines(t[1])
	eq(lines.title, "Deflection"); eq(lines.kind, nil); eq(lines.desc, nil); eq(lines.rank, V.ns.L.ARENA_WATCH_RANK:format(2, 5))
	eq(#asked, 0, "spell 0 never asked about")
	lines = S(w, V).TalentLines(t[2])
	eq(lines.kind, V.ns.L.ARENA_WATCH_PASSIVE); eq(lines.desc, "What spell 12320 does.")
	W3.NoErrors(w)
end)

-- The weight (1.2.6): the view reads the model once a second; it deep-copied both fighters' gear,
-- stats and whole talent trees each time (about 61 KB a model with Era's trees on both sides).
test("watch duel: the model copies a fighter's gear, stats and talents once per read: the same copy until the next read, a model a second allocating little; S.Active says whether a view is open, copying nothing", function()
	local w, cast = Cast()
	local V = cast.V
	local items = {}
	for slot = 1, 16 do items[slot] = { id = 2000 + slot, link = "|cff1eff00|Hitem:" .. (2000 + slot) .. "::::::::60:::::|h[Item]|h|r" } end
	local stats = {}
	for slot = 1, 16 do stats[2000 + slot] = { ITEM_MOD_STAMINA_SHORT = slot, ITEM_MOD_STRENGTH_SHORT = 2 } end
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B }, items = { [cast.A] = items, [cast.B] = items }, stats = stats })
	local g = V.globals
	g.GetNumTalentTabs = function() return 3 end
	g.GetNumTalents = function() return 20 end
	g.C_SpecializationInfo = {
		GetActiveSpecGroup = function() return 1 end,
		GetNumSpecializationsForClassID = function() return 3 end,
		GetSpecializationInfo = function(i) return 0, ({ "Arms", "Fury", "Protection" })[i], "", 200 + i, nil, nil, 5 end,
		GetTalentInfo = function(q)
			local i = q.talentIndex
			return { talentID = q.specializationIndex * 100 + i, name = "Talent " .. i, icon = 132000 + i, tier = math.floor((i - 1) / 4) + 1,
				column = (i - 1) % 4 + 1, rank = i % 3, maxRank = 5, spellID = 12000 + i }
		end,
	}
	local I = StubInspect(V)
	eq(S(w, V).Active(), false)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	eq(S(w, V).Active(), true)
	Answer(w, V, I, "spectate:A")
	Answer(w, V, I, "spectate:B")
	local m1, m2 = S(w, V).Model(), S(w, V).Model()
	eq(#m1.sides.A.talents.trees, 3); eq(#m1.sides.A.talents.trees[1].talents, 20); eq(m1.sides.A.gearN, 16)
	eq(m1.sides.A.talents, m2.sides.A.talents, "the same copy until the next read"); eq(m1.sides.A.gear, m2.sides.A.gear)
	local kb = w:As(V, function()
		local Sp = V.ns.ArenaSpectate
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		for _ = 1, 50 do Sp.Model() end
		local used = (collectgarbage("count") - before) / 50
		collectgarbage("restart")
		return used
	end)
	assert(kb < 8, ("%.1f KB a model"):format(kb))
	-- A new read: a new copy for that side, the other's kept.
	S(w, V).Reinspect("A")
	Answer(w, V, I, "spectate:A")
	local m3 = S(w, V).Model()
	assert(m3.sides.A.talents ~= m1.sides.A.talents, "A read again: copied again")
	eq(m3.sides.B.talents, m1.sides.B.talents, "B's kept")
	eq(Secret.Any(m3), false)
	S(w, V).Stop()
	eq(S(w, V).Active(), false)
	W3.NoErrors(w)
end)

test("watch duel: each inspection status has its line: \"Waiting for inspection – move within inspect range\", Inspecting…, After combat, Close the Inspect window, cannot be inspected here (refused, or given up), not in sight, inspected just now / N min ago", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	local I = StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	local L = V.ns.L
	local want = I.wants["spectate:A"]
	for _, case in ipairs({ { "range", L.ARENA_WATCH_ST_RANGE }, { "queued", L.ARENA_WATCH_ST_INSPECTING }, { "pending", L.ARENA_WATCH_ST_INSPECTING },
		{ "combat", L.ARENA_WATCH_ST_COMBAT }, { "busy", L.ARENA_WATCH_ST_BUSY }, { "refused", L.ARENA_WATCH_ST_REFUSED },
		{ "sight", L.ARENA_WATCH_ST_SIGHT } }) do
		want.status = case[1]
		eq(S(w, V).StatusLine("A"), case[2], case[1])
	end
	eq(L.ARENA_WATCH_ST_RANGE, "Waiting for inspection – move within inspect range", "the screenshot's words")
	want.status, want.tries = "timeout", 1
	eq(S(w, V).StatusLine("A"), L.ARENA_WATCH_ST_INSPECTING, "asked again soon")
	want.tries = 3
	eq(S(w, V).StatusLine("A"), L.ARENA_WATCH_ST_REFUSED, "given up")
	Answer(w, V, I, "spectate:A")
	eq(S(w, V).StatusLine("A"), L.ARENA_WATCH_ST_NOW)
	w:Run(300)
	eq(S(w, V).StatusLine("A"), L.ARENA_WATCH_ST_DONE:format(5))
	W3.NoErrors(w)
end)

print("ArenaSpectate: the rules")

test("watch duel: the weight rule: a member who never watches has no arena listener, timer or frame from it; a session is involved while it lasts; its end drops the inspections and leaves nothing running", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B } })
	local I = StubInspect(V)
	local idle = w:ArenaWeight(V)
	eq(V.ns.Arena.Ticking(), false)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	local involved = table.concat(V.ns.Arena.Involved(), ",")
	assert(involved:find("spectate", 1, true), involved)
	assert(I.wants["spectate:A"] and I.wants["spectate:B"])
	S(w, V).Stop()
	eq(next(I.wants), nil, "the inspections dropped")
	eq(V.ns.Arena.Ticking(), false, "nothing running")
	local after = w:ArenaWeight(V)
	eq(table.concat(after.events, ","), table.concat(idle.events, ",")); eq(after.timers, idle.timers); eq(after.frames, idle.frames)
	eq(S(w, V).Model(), nil); eq(S(w, V).Push("A", Widgets()), false)
	W3.NoErrors(w)
end)

test("watch duel: in combat with the companion not loaded /oly arena watch is refused with the arena's combat line and starts nothing; an open session goes on updating in combat", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B }, bodies = { [cast.A] = { hp = 500, hpMax = 1000 } } })
	StubInspect(V)
	w:Combat(V, true)
	w:As(V, V.ns.Arena.RunSlash, "watch")
	assert(Printed(V, V.ns.L.ARENA_UI_COMBAT), "the arena's combat line")
	eq(S(w, V).Watching(), nil)
	w:Combat(V, false)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	w:Combat(V, true)
	local wa = Widgets()
	S(w, V).Track(true)
	eq(S(w, V).Push("A", wa), true); eq(wa.healthText.value, "500 / 1000")
	W3.NoErrors(w)
end)

test("watch duel: the copyable text holds names, numbers and the game's own words; a guild only an Olympus guild's (King.CleanGuild)", function()
	local w, cast = Cast()
	local V = cast.V
	Scene(w, V, { units = { target = cast.A, targettarget = cast.B }, bodies = {
		[cast.A] = { class = { "Rogue", "ROGUE", 4 }, race = { "Undead", "Scourge", 5 }, level = 30 },
		[cast.B] = { guild = "Bad |cffff0000Guild|r", class = { "Hunter", "HUNTER", 3 }, race = { "Orc", "Orc", 2 }, level = 30 } } })
	StubInspect(V)
	assert(S(w, V).Start(assert(S(w, V).PairFromUnit("target"))))
	local text = S(w, V).Text()
	assert(text:find("Torvin Hale · Rogue · Undead · Level 30 · <Olympus Ember>", 1, true), text)
	assert(text:find("Selka Drummond · Hunter · Orc · Level 30", 1, true), text)
	assert(not text:find("Bad", 1, true) and not text:find("|c", 1, true), "no guild another player named, no markup")
	eq(S(w, V).Model().sides.B.guild, nil)
	W3.NoErrors(w)
end)

-- Every call of the values Forever keeps secret sits in S.Push or S.Cast, where each goes from the
-- game into a widget (a stand-in can't trap a truth test or a table key, so the source is read too).
test("watch duel: the source: UnitHealth, UnitHealthPercent, UnitPower, UnitPowerPercent, UnitCastingInfo and UnitChannelInfo appear only inside S.Push and S.Cast", function()
	local f = assert(io.open(H.ADDON_DIR .. "ArenaSpectate.lua", "rb"))
	local src = f:read("*a")
	f:close()
	local inside, where, seen = nil, {}, 0
	local n = 0
	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
		n = n + 1
		local code = line:gsub("%-%-.*$", "")
		local fn = code:match("^function S%.(%w+)%(") or code:match("^local function (%w+)%(") or code:match("^function (%S+)%(")
		if fn then inside = fn end
		for _, api in ipairs({ "UnitHealth", "UnitHealthPercent", "UnitPower", "UnitPowerPercent", "UnitCastingInfo", "UnitChannelInfo" }) do
			if code:find("%f[%w_]" .. api .. "%f[^%w_]") then
				seen = seen + 1
				if inside ~= "Push" and inside ~= "Cast" then where[#where + 1] = n .. ": " .. api .. " in " .. tostring(inside) end
			end
		end
		if code:match("^end") then inside = nil end
	end
	assert(seen >= 6, "the six found")
	eq(table.concat(where, "; "), "", "outside S.Push and S.Cast")
end)

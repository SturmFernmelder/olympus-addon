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

-- The simple tokens UnitTokenFromGUID gives (never a compound one, "targettarget").
local TOKENS = { "target", "focus", "mouseover", "party1", "party2" }
for i = 1, 8 do TOKENS[#TOKENS + 1] = "nameplate" .. i end

-- What client c's game shows: o.units (token -> client; "player" is c), o.bodies (client -> {
-- class = { name, file, id }, race = { name, file, id }, level, guild, powerType = { n, token },
-- hp, hpMax, power, powerMax, combat (true | false | "secret"), cast = { name, texture, start,
-- finish (ms), channel }, secret (Forever: the live values secret), secretGuid, npc }),
-- o.canAttack (true | false | "none" | "secret"), o.items (client -> slot -> { id, link }),
-- o.stats (item id -> GetItemStats's table), o.uncached (item id -> true). Unit functions Olympus
-- must never call (UnitInRange is always secret; TargetUnit, FocusUnit, SetCVar reach into the
-- game) raise. Returns o (its tables may change later: the game moves on).
local function Scene(w, c, o)
	o = o or {}
	o.units, o.bodies, o.items, o.stats, o.uncached, o.loads = o.units or {}, o.bodies or {}, o.items or {}, o.stats or {}, o.uncached or {}, {}
	o.percent = {}
	local g = c.globals
	local function Of(unit)
		assert(not Secret.Is(unit), "a secret unit token was passed")
		if unit == "player" then return c end
		return o.units[unit]
	end
	local function B(x) return o.bodies[x] or {} end
	local function Live(x, v) if B(x).secret then return Secret.New() end return v end
	g.issecretvalue = Secret.Is
	g.UnitExists = function(u) return Of(u) ~= nil end
	g.UnitIsPlayer = function(u) local x = Of(u) return x ~= nil and not B(x).npc end
	g.UnitGUID = function(u)
		local x = Of(u)
		if not x then return nil end
		if B(x).secretGuid then return Secret.New() end
		return x.guid
	end
	g.UnitFullName = function(u) local x = Of(u) if x then return x.short, x.realm end end
	g.UnitName = function(u) local x = Of(u) if x then return x.short, x.realm ~= c.realm and x.realm or nil end end
	g.GetUnitName = function(u, withRealm) local x = Of(u) if x then return withRealm and (x.short .. "-" .. x.realm) or x.short end end
	g.UnitIsUnit = function(a, b) local x, y = Of(a), Of(b) return x ~= nil and x == y end
	g.UnitCanAttack = function()
		local v = o.canAttack
		if v == "secret" then return Secret.New() end
		if v == "none" then return nil end
		if v == nil then return true end
		return v
	end
	g.UnitTokenFromGUID = function(guid)
		if guid == c.guid then return "player" end
		for _, t in ipairs(TOKENS) do
			local x = o.units[t]
			if x and x.guid == guid and not B(x).secretGuid then return t end
		end
		return nil
	end
	g.UnitClass = function(u)
		local x = Of(u)
		if not x then return nil end
		local cl = B(x).class or { "Warrior", "WARRIOR", 1 }
		return cl[1], cl[2], cl[3]
	end
	g.UnitRace = function(u)
		local x = Of(u)
		if not x then return nil end
		local r = B(x).race or { "Human", "Human", 1 }
		return r[1], r[2], r[3]
	end
	g.UnitLevel = function(u) local x = Of(u) return x and (B(x).level or x.level) or 0 end
	g.UnitSex = function(u) return Of(u) and 2 or nil end
	g.UnitFactionGroup = function(u) local x = Of(u) return x and x.faction or nil end
	g.GetGuildInfo = function(u)
		local x = Of(u or "player")
		if not x then return nil end
		local guild = B(x).guild
		if guild == nil then guild = x.guild end
		return guild or nil, "Member", 3
	end
	g.UnitPowerType = function(u)
		local x = Of(u)
		if not x then return nil end
		local p = B(x).powerType or { 0, "MANA" }
		return p[1], p[2]
	end
	g.UnitHealth = function(u) local x = Of(u) if x then return Live(x, B(x).hp or 100) end end
	g.UnitHealthMax = function(u) local x = Of(u) if x then return B(x).hpMax or 100 end end
	g.UnitHealthPercent = function(u, predicted, curve)
		o.percent[#o.percent + 1] = { unit = u, curve = curve }
		local x = Of(u)
		if x then return Live(x, 0.5) end
	end
	g.UnitPower = function(u) local x = Of(u) if x then return Live(x, B(x).power or 50) end end
	g.UnitPowerMax = function(u) local x = Of(u) if x then return B(x).powerMax or 100 end end
	g.UnitPowerPercent = function(u, kind, unmodified, curve)
		o.percent[#o.percent + 1] = { unit = u, curve = curve, power = true }
		local x = Of(u)
		if x then return Live(x, 0.5) end
	end
	g.UnitAffectingCombat = function(u)
		local x = Of(u)
		if not x then return nil end
		if B(x).combat == "secret" then return Secret.New() end
		return B(x).combat == true
	end
	local function CastOf(u, channel)
		local x = Of(u)
		local cast = x and B(x).cast
		if not cast or (cast.channel == true) ~= channel then return nil end
		return x, cast
	end
	g.UnitCastingInfo = function(u)
		local x, cast = CastOf(u, false)
		if not x then return nil end
		-- (name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill (NeverSecret), castID, notInterruptible, spellID)
		return Live(x, cast.name), Live(x, cast.name), Live(x, cast.texture), Live(x, cast.start), Live(x, cast.finish), false, "Cast-1", Live(x, false), Live(x, 116)
	end
	g.UnitChannelInfo = function(u)
		local x, cast = CastOf(u, true)
		if not x then return nil end
		return Live(x, cast.name), Live(x, cast.name), Live(x, cast.texture), Live(x, cast.start), Live(x, cast.finish), false, Live(x, false), Live(x, 746)
	end
	g.UnitInParty = function(u) local x = Of(u) return x ~= nil and B(x).grouped == true end
	g.UnitInRaid = function() return nil end
	g.C_CurveUtil = { CreateCurve = function()
		local curve = { points = {} }
		function curve:AddPoint(x, y) self.points[#self.points + 1] = x .. "," .. y end
		return curve
	end }
	g.GetPlayerInfoByGUID = function(guid)
		for _, x in ipairs(w.clients) do
			if x.guid == guid then
				local cl, r = B(x).class or { "Warrior", "WARRIOR", 1 }, B(x).race or { "Human", "Human", 1 }
				return cl[1], cl[2], r[1], r[2], 2, x.short, ""
			end
		end
		return nil
	end
	g.GetInventoryItemLink = function(u, slot) local x = Of(u) local it = x and o.items[x] and o.items[x][slot] return it and it.link end
	g.GetInventoryItemID = function(u, slot) local x = Of(u) local it = x and o.items[x] and o.items[x][slot] return it and it.id end
	g.C_Item = {
		GetItemStats = function(link) return o.stats[tonumber(link:match("item:(%d+)"))] end,
		IsItemDataCachedByID = function(id) return not o.uncached[id] end,
		RequestLoadItemDataByID = function(id) o.loads[#o.loads + 1] = id end,
	}
	for _, name in ipairs({ "UnitInRange", "TargetUnit", "FocusUnit", "SetCVar" }) do
		g[name] = function() error(name .. " called") end
	end
	return o
end

-- Inspect.lua at its boundary (the arena world loads none): Want/Unwant/WantStatus kept here,
-- ReadGear the real one (it only reads GetInventoryItemLink/GetInventoryItemID).
local function StubInspect(c)
	local I = { wants = {}, WANT_TRIES = 3, ReadGear = H.ns.Inspect.ReadGear }
	function I.Want(guid, key, o) I.wants[key] = { guid = guid, unit = o.unit, read = o.read, status = "queued", tries = 0 } return true end
	function I.Unwant(key) I.wants[key] = nil end
	function I.WantStatus(guid)
		for _, x in pairs(I.wants) do
			if x.guid == guid then return x.status, x.at, x.tries end
		end
		return nil
	end
	rawset(c.ns, "Inspect", I)
	return I
end
-- The game's answer to a want (INSPECT_READY): its reader on the unit its own function gives.
local function Answer(w, c, I, key)
	local x = assert(I.wants[key], "no want " .. key)
	local unit = w:As(c, x.unit)
	assert(unit, "the want found no unit")
	w:As(c, x.read, unit, x.guid)
	x.status, x.at = "done", c.ns.Now()
	return unit
end

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

-- Forever's talent tree as its own Camelot talent frame reads it (C_Traits on the inspect config,
-- the class's three trees its groups): five nodes, one hidden.
local function ForeverTalents(g, points)
	g.Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
	local NODES = {
		[101] = { posX = 600, posY = 600, groupIDs = { 11 }, currentRank = 3, maxRanks = 5, activeEntry = { entryID = 201, rank = 3 }, entryIDs = { 201 } },
		[102] = { posX = 1200, posY = 600, groupIDs = { 11 }, currentRank = 0, maxRanks = 5, entryIDs = { 202 } },
		[103] = { posX = 600, posY = 1200, groupIDs = { 11 }, currentRank = 2, maxRanks = 2, activeEntry = { entryID = 203, rank = 2 }, entryIDs = { 203 } },
		[104] = { posX = 2400, posY = 600, groupIDs = { 12 }, currentRank = 0, maxRanks = 5, entryIDs = { 204 } },
		[105] = { posX = 4200, posY = 600, groupIDs = { 13 }, currentRank = 1, maxRanks = 1, entryIDs = { 205 }, isVisible = false },
	}
	g.C_Traits = {
		HasValidInspectData = function() return true end,
		GetConfigInfo = function(id) if id == -1 then return { ID = -1, treeIDs = { 77 } } end end,
		GetGroupDisplayInfoByTreeID = function() return {
			{ groupID = 12, treeID = 77, orderIndex = 2, displayName = "Combat", icon = 222 },
			{ groupID = 11, treeID = 77, orderIndex = 1, displayName = "Assassination", icon = 111 },
			{ groupID = 13, treeID = 77, orderIndex = 3, displayName = "Subtlety", icon = 333 } } end,
		GetTreeNodes = function() return { 101, 102, 103, 104, 105 } end,
		GetNodeInfo = function(config, node) assert(config == -1, "the inspect config") return NODES[node] end,
		GetEntryInfo = function(_, entry) return { definitionID = entry + 1000, maxRanks = 5 } end,
		GetDefinitionInfo = function(def) return { spellID = def + 10000 } end,
		GetTraitDescription = function(entry, rank) return "Reduces your speed penalty by " .. (3 * rank) .. "%." end,
	}
	g.C_Spell = { GetSpellName = function(id) return "Talent " .. id end, GetSpellTexture = function(id) return 130000 + id end,
		IsSpellPassive = function(id) return id ~= 11202 end }
	g.C_SpecializationInfo = { GetActiveSpecGroup = function() return 1 end, GetNumSpecializationsForClassID = function() return 3 end,
		GetSpecializationInfo = function(i) return 0, ({ "Assassination", "Combat", "Subtlety" })[i], "", 100 + i, nil, nil, (points or { 5, 0, 0 })[i] end }
end

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

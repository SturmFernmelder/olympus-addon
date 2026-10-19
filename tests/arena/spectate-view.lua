-- 1.2.6, Watch duel (Daniel's duel-view request, 2026-10-19): the duel view's window and bar,
-- Olympus_Arena/Spectate.lua, on the test world with the real core (ArenaSpectate.lua) and the real
-- companion: the right-click line opening the split window, the live values reaching its bars only
-- through the core's S.Push and S.Cast (Forever's secrets unchanged, Era's plain values), out of
-- sight, the cast and its ticker, Auto's bar in combat and the full view at the result, the gear
-- and its tooltips, the talent grids and theirs, the status line, the scale and places kept, the
-- close, the weight rule. Inspect.lua stands in at its boundary (tests/arena/lib/spectate-world.lua);
-- every name is invented.
--
-- The secret sentinel (tests/arena/lib/secret.lua) raises on every comparison, arithmetic, join,
-- tostring, length, index and call. Its limits, as there: a truth test (`if v`) and a secret used
-- as a table key cannot be trapped, and LuaJIT never asks a table's __eq against a number. So the
-- last test also reads the view's source: it names none of the six functions whose values Forever
-- keeps secret, nor reads a widget back.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
local Secret = assert(loadfile(H.ROOT .. "tests/arena/lib/secret.lua"))()
local SW = assert(loadfile(H.ROOT .. "tests/arena/lib/spectate-world.lua"))(H)
local Scene, StubInspect, Answer, ForeverTalents = SW.Scene, SW.StubInspect, SW.Answer, SW.ForeverTalents

local function S(w, c) return W3.M(w, c, "ArenaSpectate") end

-- The view's frames as the game's widgets would hold what they are given: each frame the client
-- makes (and its textures and texts) keeps its bars' values, its texts (plain or formatted with
-- their arguments, never formatted with a secret), its textures and colours, its points, scale
-- and the model's units; a frame's Show and Hide run its OnShow and OnHide when its own shown
-- state changes, as the client's do (its parent's left out). Installed after the companion
-- loaded, before the view's first show (it builds its frames then).
local function Recording(c)
	local made = {}
	local function Region(r)
		r.anchors = {}
		function r:SetText(t) self.text, self.fmt, self.args = t, nil, nil end
		function r:SetFormattedText(fmt, ...)
			self.fmt, self.args = fmt, { ... }
			local ok, s = pcall(string.format, fmt, ...)
			self.text = ok and s or nil
		end
		function r:SetTexture(t) self.texture = t end
		function r:SetTexCoord(...) self.coords = { ... } end
		function r:SetVertexColor(...) self.vertex = { ... } end
		function r:SetColorTexture(...) self.color = { ... } end
		function r:SetTextColor(...) self.ink = { ... } end
		function r:SetDesaturated(on) self.desaturated = on end
		function r:SetAlpha(a) self.alpha = a end
		function r:SetPoint(...) self.anchors[#self.anchors + 1] = { ... } end
		function r:ClearAllPoints() self.anchors = {} end
		function r:GetPoint(i) local p = self.anchors[i or 1] if p then return unpack(p, 1, 5) end end
		made[#made + 1] = r
		return r
	end
	local base = c.globals.CreateFrame
	c.globals.CreateFrame = function(kind, name, parent, template)
		local f = Region(base(kind, name, parent, template))
		f.kindName, f.template = kind, template
		function f:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
		function f:SetValue(v) self.value = v end
		function f:SetStatusBarColor(...) self.barColor = { ... } end
		function f:SetReverseFill(on) self.reverse = on end
		function f:SetScale(s) self.scale = s end
		function f:CreateTexture() return Region(World.NewFrame("Texture", nil, self)) end
		function f:CreateFontString() return Region(World.NewFrame("FontString", nil, self)) end
		function f:UnregisterAllEvents() self.events = {} end
		function f:Show()
			if self.shown then return end
			self.shown = true
			if self.scripts.OnShow then self.scripts.OnShow(self) end
		end
		function f:Hide()
			if not self.shown then return end
			self.shown = false
			if self.scripts.OnHide then self.scripts.OnHide(self) end
		end
		function f:SetShown(on) if on then self:Show() else self:Hide() end end
		if kind == "PlayerModel" then
			f.units = {}
			function f:SetUnit(u) self.units[#self.units + 1] = u return true end
			function f:SetFacing(r) self.facing = r end
			function f:ClearModel() self.cleared = (self.cleared or 0) + 1 end
		end
		return f
	end
	return made
end

-- The game's tooltip, as Olympus's own tooltips use it (its owner and lines).
local function Tooltip(c)
	local tip = { lines = {} }
	function tip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines, self.link = owner, anchor, {}, nil end
	function tip:AddLine(text, r, g, b, wrap) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b, wrap = wrap } end
	function tip:SetHyperlink(link) self.link = link end
	function tip:Show() self.shown = true end
	function tip:Hide() self.shown = false end
	function tip:IsOwned(f) return self.owner == f end
	c.globals.GameTooltip = tip
	return tip
end

local function UI(c) return c.ns.Arena.ui end
local function View(c) return UI(c).Spectate end
-- An event of the game on the view's own event frame (registered: as the client sends it).
local function Event(w, c, event, ...)
	local f = View(c).Events()
	if f and f.events[event] then w:As(c, f.scripts.OnEvent, f, event, ...) return true end
	return false
end
-- What the client does on a frame's hide (the stand-ins run no script by themselves).
local function Hidden(w, c, f) w:As(c, f.scripts.OnHide, f) end
local function Lines(tip) local out = {} for _, l in ipairs(tip.lines) do out[#out + 1] = l.text end return table.concat(out, " | ") end

-- Two fighters and a spectator (an ordinary member), the scene, Inspect at its boundary, the
-- tooltip, the recording frames and the companion loaded; opened on target and targettarget.
local function Watch(o, open)
	local w = World.New()
	local cast = { A = w:Role("fighterA"), B = w:Role("fighterB"), V = w:Role("bettor1"), C = w:Role("bettor2") }
	local V = cast.V
	local scene = Scene(w, V, o or { units = { target = cast.A, targettarget = cast.B } })
	local I = StubInspect(V)
	local tip = Tooltip(V)
	W3.Companion(w, V)
	local made = Recording(V)
	V.ns.ArenaSpectate.ResetCurve()
	local env = { w = w, cast = cast, V = V, o = scene, I = I, tip = tip, made = made }
	if open ~= false then
		local subject = assert(S(w, V).PairFromUnits("target", scene.units.focus and "focus" or "targettarget"))
		assert(S(w, V).Open(subject), "opened")
		env.win, env.bar = View(V).Frame(), View(V).Bar()
		env.A, env.B = env.win.halves.A, env.win.halves.B
	end
	return env
end

print("Spectate: the window")

test("watch duel view: the right-click line opens one window split down the middle (ArenaUI.Open \"duel.watch\"): A left in red, B right in blue and mirrored, the VS seal between; nothing of it made, ticking or listening before", function()
	local e = Watch(nil, false)
	local w, V = e.w, e.V
	eq(View(V).Frame(), nil, "no window before the first watch"); eq(View(V).Events(), nil, "no event frame")
	eq(select(1, View(V).Ticking()), false)
	local found
	local menu = { Button = function(text, fn) if text == V.ns.L.ARENA_MENU_WATCH_DUEL then found = fn end end }
	w:As(V, V.ns.ArenaHome.MenuLines, { name = e.cast.A.name, unit = "target" }, menu)
	assert(found, "Watch duel in the menu")
	w:As(V, found)
	local win = assert(View(V).Frame(), "the window")
	eq(win:IsShown(), true); eq(View(V).Mode(), "full"); eq(View(V).Bar():IsShown(), false, "the bar waits for combat")
	assert(win.name:find("^OlympusArenaWatch"), win.name); eq(win.TitleText.text, V.ns.L.ARENA_WATCH_TITLE)
	local A, B = win.halves.A, win.halves.B
	eq(A.name.text, "Torvin Hale"); eq(B.name.text, "Selka Drummond")
	eq(A.hp.barColor[1], 0.75, "A red"); eq(B.hp.barColor[3], 0.75, "B blue")
	eq(rawget(A.hp, "reverse"), nil); eq(rawget(B.hp, "reverse"), true, "B's bars fill from his outer edge")
	eq(A.anchors[1][4] < B.anchors[1][4], true, "A left of B")
	eq(win.seal.text.text, V.ns.L.ARENA_WATCH_VS)
	eq(win.fight.text, V.ns.L.ARENA_WATCH_NOT_OLYMPUS, "a pair with no Olympus fight known here")
	for _, ev in ipairs(View(V).EVENTS) do eq(View(V).Events().events[ev], true, ev .. " registered") end
	eq(select(1, View(V).Ticking()), true, "the ticker runs while shown")
	assert(S(w, V).Watching(), "the session")
	W3.NoErrors(w)
end)

test("watch duel view: Forever's secret health and power reach the window's bars and texts unchanged through S.Push at each tick, no error; every secret in the view sits in a live widget; the model and the copied text hold none", function()
	local e = Watch({ units = {}, bodies = {} }, false)
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.units.target, o.units.targettarget = cast.A, cast.B
	o.bodies[cast.A] = { secret = true, hpMax = 2138, powerMax = 100, powerType = { 3, "ENERGY" }, class = { "Rogue", "ROGUE", 4 }, race = { "Undead", "Scourge", 5 }, level = 30 }
	o.bodies[cast.B] = { secret = true, hpMax = 1960, powerMax = 100, class = { "Hunter", "HUNTER", 3 }, race = { "Orc", "Orc", 2 }, level = 30 }
	assert(S(w, V).Open(assert(S(w, V).PairFromUnit("target"))))
	local win = View(V).Frame()
	local A = win.halves.A
	w:Run(0.2)
	assert(Secret.Is(A.hp.value), "the secret health into SetValue"); eq(A.hp.max, 2138)
	eq(A.hpText.fmt, "%d / %d"); assert(Secret.Is(A.hpText.args[1])); eq(A.hpText.args[2], 2138)
	assert(Secret.Is(A.power.value)); eq(A.powerText.fmt, "%.0f%%"); assert(Secret.Is(A.powerText.args[1]))
	assert(Secret.Is(win.halves.B.hp.value))
	-- The sentinel: a secret anywhere in the view's widgets is in one of its live ones.
	local live = {}
	for _, key in ipairs({ "A", "B" }) do
		local h, b = win.halves[key], View(V).Bar().sides[key]
		for _, x in ipairs({ h.hp, h.hpText, h.power, h.powerText, h.cast.bar, h.cast.name, h.cast.icon, b.hp, b.hpText, b.power, b.powerText, b.cast.bar }) do live[x] = true end
	end
	local holding = 0
	for _, r in ipairs(e.made) do
		for k, v in pairs(r) do
			if Secret.Is(v) or (k == "args" and Secret.Any(v)) then
				if not live[r] then error("a secret in a widget that is no live one: " .. tostring(k)) end
				holding = holding + 1
			end
		end
	end
	assert(holding >= 6, "the live widgets hold the secrets: " .. holding)
	eq(Secret.Any(S(w, V).Model()), false, "no secret in the model")
	-- The header: his class's colour darkened for the ink, the words of the game.
	eq(A.who.text, "Rogue · Undead · Level 30")
	local ink = A.name.ink
	assert(ink and ink[1] < 0.5 and ink[2] < 0.5, "a rogue's yellow darkened for the parchment")
	-- Copy: the text in the copy pop-up (Kit.Copy), never in chat; no secret in it.
	local printed = #V.printed
	w:As(V, win.copy.scripts.OnClick, win.copy)
	eq(UI(V).lastCopy, w:As(V, V.ns.ArenaHome.Plain, S(w, V).Text()))
	assert(UI(V).lastCopy:find("Torvin Hale · Rogue · Undead · Level 30", 1, true), UI(V).lastCopy)
	eq(#V.printed, printed, "nothing printed")
	w:Run(3)
	W3.NoErrors(w)
end)

test("watch duel view: Era's and TBC's plain values: 37 of 100 for a player outside the group shows \"37%\", 847 of 2239 for a group member \"847 / 2239\"; the bar's own percentages", function()
	local e = Watch(nil, false)
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.units.targettarget = nil
	o.units.party1 = cast.B
	o.bodies[cast.A] = { hp = 37, hpMax = 100, power = 30, powerMax = 120 }
	o.bodies[cast.B] = { hp = 847, hpMax = 2239, grouped = true }
	assert(S(w, V).Open(assert(S(w, V).PairFromUnits("target", "party1"))))
	local win = View(V).Frame()
	w:Run(0.2)
	eq(win.halves.A.hpText.text, "37%"); eq(win.halves.A.powerText.text, "25%")
	eq(win.halves.B.hpText.text, "847 / 2239")
	assert(w:As(V, View(V).Pin, "compact"))
	w:Run(0.2)
	local b = View(V).Bar()
	eq(b:IsShown(), true); eq(win:IsShown(), false)
	eq(b.sides.A.hpText.text, "37%"); eq(b.sides.B.hpText.text, "38%"); eq(b.sides.A.powerText.text, "25%")
	W3.NoErrors(w)
end)

test("watch duel view: out of sight the bars empty to \"—\" and the stage says so, his last model kept (drawn once); one never seen keeps his class's picture; a nameplate showing him (NAME_PLATE_UNIT_ADDED) brings his bars and model back at once", function()
	local e = Watch()
	local w, V, o, cast, A, B = e.w, e.V, e.o, e.cast, e.A, e.B
	o.bodies[cast.A] = { hp = 1200, hpMax = 1500, class = { "Mage", "MAGE", 8 } }
	o.bodies[cast.B] = { hp = 900, hpMax = 1000, class = { "Priest", "PRIEST", 5 } }
	w:Run(1)
	eq(A.stage.model.units[1], "target", "his model on his unit"); eq(A.stage.model.facing, 0.45, "turned towards the seal")
	eq(B.stage.model.facing, -0.45)
	eq(A.hpText.text, "1200 / 1500"); eq(A.stage.sight.shown, false)
	o.units = {}
	w:Run(2)
	eq(A.hpText.text, V.ns.L.ARENA_WATCH_DASH); eq(A.hp.value, 0)
	eq(A.stage.sight.shown, true); eq(A.stage.sight.text, V.ns.L.ARENA_WATCH_OUT)
	eq(A.stage.model.shown, true, "his last model kept"); eq(#A.stage.model.units, 1, "drawn once")
	eq(A.stage.class.shown, false)
	-- A nameplate shows B again.
	o.units.nameplate3 = cast.B
	eq(Event(w, V, "NAME_PLATE_UNIT_ADDED", "nameplate3"), true)
	eq(B.hpText.text, "900 / 1000", "back at once, before the next tick")
	eq(B.stage.sight.shown, false)
	-- His look changed (UNIT_MODEL_CHANGED on his unit): drawn again on it.
	eq(Event(w, V, "UNIT_MODEL_CHANGED", "nameplate3"), true)
	w:Run(1)
	eq(B.stage.model.units[#B.stage.model.units], "nameplate3")
	W3.NoErrors(w)
end)

test("watch duel view: a fighter never in sight shows his class's picture on the stage and no model", function()
	local e = Watch(nil, false)
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.bodies[cast.B] = { class = { "Warlock", "WARLOCK", 9 } }
	local subject = assert(S(w, V).PairFromUnit("target"))
	o.units.targettarget = nil
	assert(S(w, V).Open(subject))
	local B = View(V).Frame().halves.B
	w:Run(1)
	eq(B.stage.model.shown, false); eq(#B.stage.model.units, 0)
	eq(B.stage.class.shown, true); eq(B.stage.class.texture, "Interface\\TargetingFrame\\UI-Classes-Circles")
	eq(B.stage.sight.shown, true)
	W3.NoErrors(w)
end)

test("watch duel view: the cast: hidden when none; a secret cast's name, icon and fill set unchanged with no seconds, Era's with its seconds, a channel's colours swapped; the 0.1 s ticker runs only while a cast shows", function()
	local e = Watch(nil, false)
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.units.targettarget, o.units.focus = nil, cast.B
	o.bodies[cast.A] = { secret = true }
	o.bodies[cast.B] = {}
	assert(S(w, V).Open(assert(S(w, V).PairFromUnits("target", "focus"))))
	local A, B = View(V).Frame().halves.A, View(V).Frame().halves.B
	w:Run(0.2)
	eq(A.cast.shown, false); eq(select(2, View(V).Ticking()), false, "no cast ticker without a cast")
	o.bodies[cast.A].cast = { name = "Shadow Bolt", texture = 136197, start = 1, finish = 2 }
	o.bodies[cast.B].cast = { name = "Frostbolt", texture = 135846, start = w.clock * 1000, finish = (w.clock + 2.5) * 1000 }
	w:Run(0.2)
	eq(A.cast.shown, true); eq(select(2, View(V).Ticking()), true, "the cast ticker now")
	assert(Secret.Is(A.cast.name.text), "the secret name into SetText"); assert(Secret.Is(A.cast.icon.texture), "the secret icon into SetTexture")
	assert(Secret.Is(A.cast.bar.min) and Secret.Is(A.cast.bar.max)); eq(A.cast.time.text, "", "no seconds for a secret cast")
	eq(B.cast.name.text, "Frostbolt"); eq(B.cast.icon.texture, 135846)
	assert(B.cast.time.text == "2.3" or B.cast.time.text == "2.4", B.cast.time.text)
	eq(B.cast.bar.barColor[1], 1, "a cast's fill bright")
	o.bodies[cast.B].cast = { name = "First Aid", texture = 133685, start = w.clock * 1000, finish = (w.clock + 8) * 1000, channel = true }
	w:Run(0.1)
	eq(B.cast.bar.barColor[1] < 0.2, true, "a channel's fill dark..."); eq(B.cast.bar.bg.color[2] > 0.5, true, "...its ground bright")
	o.bodies[cast.A].cast, o.bodies[cast.B].cast = nil, nil
	w:Run(0.1)
	eq(A.cast.shown, false); eq(B.cast.shown, false); eq(select(2, View(V).Ticking()), false, "the cast ticker gone with the casts")
	eq(Secret.Any(S(w, V).Model()), false)
	W3.NoErrors(w)
end)

-- A frame shown with all its parents (what the player sees).
local function Visible(f)
	while f do
		if rawget(f, "shown") == false then return false end
		f = rawget(f, "parent")
	end
	return true
end

-- The regression (1.2.6): a half's cast bar was a child of the gear stage, hidden with it on the
-- Talents tab: the cast was filled and its ticker ran, and nothing showed (Daniel's screenshots 42
-- and 43 show the trees with the cast bar under them).
test("watch duel view: a cast shows on the Talents tab too (the half's own bar, under the trees) and on Gear above the weapons; its ticker runs while it shows", function()
	local e = Watch(nil, false)
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.units.targettarget, o.units.focus = nil, cast.B
	o.bodies[cast.A], o.bodies[cast.B] = {}, {}
	assert(S(w, V).Open(assert(S(w, V).PairFromUnits("target", "focus"))))
	local A = View(V).Frame().halves.A
	assert(w:As(V, View(V).SetTab, "talents"))
	o.bodies[cast.A].cast = { name = "First Aid", texture = 133685, start = w.clock * 1000, finish = (w.clock + 8) * 1000, channel = true }
	w:Run(0.4)
	eq(A.gear.shown, false); eq(A.talents.shown, true)
	eq(A.cast.shown, true); eq(Visible(A.cast), true, "seen on the Talents tab"); eq(A.cast.name.text, "First Aid")
	eq(A.cast.anchors[1][2], A.talents, "under the trees")
	eq(select(2, View(V).Ticking()), true)
	assert(w:As(V, View(V).SetTab, "gear"))
	w:Run(0.2)
	eq(Visible(A.cast), true, "and on Gear"); eq(A.cast.anchors[1][2], A.stage, "on the stage, above the weapons")
	o.bodies[cast.A].cast = nil
	w:Run(0.2)
	eq(A.cast.shown, false); eq(select(2, View(V).Ticking()), false, "the cast ticker gone with the cast")
	W3.NoErrors(w)
end)

print("Spectate: Auto, the bar, the result")

test("watch duel view: Auto: the bar while either fighter is in combat, the full view back after a short hold and at once at the result (whatever the lingering combat flag says); a pin wins; the session lives across the swaps", function()
	local e = Watch()
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.bodies[cast.A] = { combat = false, hp = 50, hpMax = 100, grouped = true }
	o.bodies[cast.B] = { combat = false }
	local win, b = View(V).Frame(), View(V).Bar()
	w:Run(0.2)
	eq(View(V).Mode(), "full")
	o.bodies[cast.A].combat = true
	w:Run(0.2)
	eq(View(V).Mode(), "compact"); eq(win:IsShown(), false); eq(b:IsShown(), true)
	assert(S(w, V).Watching(), "the session lives (the window's OnHide in the swap is no close)")
	eq(b.sides.A.hpText.text, "50%", "the bar's live values")
	eq(b.seal.text.text, V.ns.L.ARENA_WATCH_VS, "no fight known: VS")
	-- Unknown (a secret flag): the view kept.
	o.bodies[cast.A].combat = "secret"
	w:Run(1)
	eq(View(V).Mode(), "compact")
	o.bodies[cast.A].combat = false
	w:Run(0.4)
	eq(View(V).Mode(), "compact", "a short hold")
	w:Run(2)
	eq(View(V).Mode(), "full"); eq(win:IsShown(), true); eq(b:IsShown(), false)
	-- The result: the full view at once, its line in the strip, though the flag still says combat.
	o.bodies[cast.A].combat = true
	w:Run(0.2)
	eq(View(V).Mode(), "compact")
	local sent = #w.sent
	eq(Event(w, V, "CHAT_MSG_SYSTEM", W3.DUEL_KO:format(cast.B.short, cast.A.short)), true)
	eq(View(V).Mode(), "full")
	eq(win.fight.text, V.ns.L.ARENA_WATCH_WON_KO:format("Selka Drummond"))
	w:Run(3)
	eq(View(V).Mode(), "full", "the result keeps the full view")
	eq(#w.sent, sent, "nothing sent")
	for _, kind in ipairs({ "AW", "AX", "AR", "AG", "AF" }) do eq(#W3.Bodies(w, V, kind), 0, "no " .. kind) end
	w:Run(10)
	eq(View(V).Mode(), "compact", "a new round's combat: the bar again")
	-- Pins: Full whatever the combat; Bar whatever the calm; kept.
	w:As(V, win.pins.buttons[2].scripts.OnClick, win.pins.buttons[2])
	eq(View(V).Mode(), "full"); eq(V.ns.db.arenaUI.watch.pin, "full")
	w:Run(1)
	eq(View(V).Mode(), "full")
	assert(w:As(V, View(V).Pin, "compact"))
	o.bodies[cast.A].combat = false
	w:Run(5)
	eq(View(V).Mode(), "compact")
	-- The bar's + pins the full view.
	w:As(V, b.expand.scripts.OnClick, b.expand)
	eq(View(V).Mode(), "full"); eq(V.ns.db.arenaUI.watch.pin, "full")
	W3.NoErrors(w)
end)

test("watch duel view: a fighter's own duel: the strip says best of, round, score and state from his record; the bar's seal the score and round; his own half has no Inspect again; nothing is sent", function()
	local w, cast = W3.New({ live = false, world = { compliance = "shipped" } })
	local A, B = cast.A, cast.B
	local oid = assert(W3.M(w, A, "ArenaFights").Challenge(B.name, { bo = 3 }))
	w:Run(0)
	assert(W3.M(w, B, "ArenaFights").Answer(oid, true))
	w:Run(0)
	Scene(w, A, { units = { target = B } })
	StubInspect(A)
	Tooltip(A)
	W3.Companion(w, A)
	Recording(A)
	local sent = #w.sent
	w:As(A, A.ns.Arena.RunSlash, "watch")
	local win = assert(View(A).Frame(), "his own duel opened")
	eq(win.fight.text, A.ns.L.ARENA_WATCH_FIGHT_LINE:format(3, 1, 0, 0) .. " · " .. w:As(A, A.ns.ArenaHome.StateWord, { state = "S" }))
	eq(win.halves.A.refresh.shown, false, "his own gear: no inspection"); eq(win.halves.B.refresh.shown, true)
	eq(win.halves.A.status.text, A.ns.L.ARENA_WATCH_ST_OWN)
	assert(w:As(A, View(A).Pin, "compact"))
	eq(View(A).Bar().seal.text.text, "0 : 0"); eq(View(A).Bar().seal.small.text, A.ns.L.ARENA_WATCH_BAR_ROUND:format(1))
	w:Run(5)
	eq(#w.sent, sent, "watching sends nothing")
	w:As(A, View(A).Pin, "auto")
	W3.NoErrors(w)
end)

-- The regression (1.2.6): every round's duel line set the result for the rest of the session: in a
-- best of 3 the strip said the first round's winner had won the duel while it stood 1 : 0, and
-- kept saying so through the later rounds (the copied text too).
test("watch duel view: a best of 3: after a round the strip keeps the fight's line with that round's outcome (\"Last round\"), never \"wins\" before the fight is won; the next round clears it; the winner once the fight is over", function()
	local w, cast = W3.New({ live = false, world = { compliance = "shipped" } })
	local A, B = cast.A, cast.B
	A.target, B.target = B.name, A.name
	local oid = assert(W3.M(w, A, "ArenaFights").Challenge(B.name, { bo = 3 }))
	w:Run(0)
	assert(W3.M(w, B, "ArenaFights").Answer(oid, true))
	w:Run(0)
	local o = Scene(w, A, { units = { target = B }, bodies = { [A] = { combat = false }, [B] = { combat = false } } })
	StubInspect(A)
	Tooltip(A)
	W3.Companion(w, A)
	Recording(A)
	w:As(A, A.ns.Arena.RunSlash, "watch")
	local win = assert(View(A).Frame(), "his own duel opened")
	local L = A.ns.L
	local function Strip() return tostring(win.fight.text) end
	-- A round as the game plays it, the duel line on the fighters' clients and in the view.
	local function Round(winner, loser, during)
		w:Combat(A, true); w:Combat(B, true)
		o.bodies[A].combat, o.bodies[B].combat = true, true
		w:Run(10)
		if during then during() end
		w:Run(10)
		W3.Duel(w, { A, B }, winner, loser)
		Event(w, A, "CHAT_MSG_SYSTEM", W3.DUEL_KO:format(winner.short, loser.short))
		w:Fire(A, "DUEL_FINISHED"); w:Fire(B, "DUEL_FINISHED")
		w:Run(0)
		w:Combat(A, false); w:Combat(B, false)
		o.bodies[A].combat, o.bodies[B].combat = false, false
		w:Run(3)
	end
	Round(A, B)
	assert(not Strip():find(L.ARENA_WATCH_WON_KO:format("Torvin Hale"), 1, true), "no win at 1 : 0: " .. Strip())
	assert(Strip():find(L.ARENA_WATCH_ROUND_KO:format("Torvin Hale"), 1, true), Strip())
	assert(Strip():find("1 : 0", 1, true), Strip())
	local text = w:As(A, A.ns.ArenaSpectate.Text)
	assert(text:find(L.ARENA_WATCH_ROUND_KO:format("Torvin Hale"), 1, true) and not text:find(L.ARENA_WATCH_WON_KO:format("Torvin Hale"), 1, true), text)
	Round(B, A, function()
		assert(not Strip():find(L.ARENA_WATCH_ROUND_KO:format("Torvin Hale"), 1, true), "the next round: no old outcome: " .. Strip())
	end)
	assert(Strip():find(L.ARENA_WATCH_ROUND_KO:format("Selka Drummond"), 1, true), Strip())
	assert(Strip():find("1 : 1", 1, true) and not Strip():find(L.ARENA_WATCH_WON_KO:format("Selka Drummond"), 1, true), Strip())
	Round(A, B)
	eq(Strip(), L.ARENA_WATCH_WON_KO:format("Torvin Hale"), "the fight won: the winner")
	W3.NoErrors(w)
end)

-- (The same regression for a pair this client knows no fight of: a re-duel kept the old winner.)
test("watch duel view: a pair with no Olympus fight: the result stays through the calm after it and goes when they fight again", function()
	local e = Watch()
	local w, V, o, cast, win = e.w, e.V, e.o, e.cast, e.win
	o.bodies[cast.A], o.bodies[cast.B] = { combat = true }, { combat = true }
	w:As(V, View(V).Pin, "full")
	w:Run(1)
	eq(Event(w, V, "CHAT_MSG_SYSTEM", W3.DUEL_KO:format(cast.A.short, cast.B.short)), true)
	eq(win.fight.text, V.ns.L.ARENA_WATCH_WON_KO:format("Torvin Hale"))
	w:Run(3)
	eq(win.fight.text, V.ns.L.ARENA_WATCH_WON_KO:format("Torvin Hale"), "the combat flag lingering")
	o.bodies[cast.A].combat, o.bodies[cast.B].combat = false, false
	w:Run(5)
	eq(win.fight.text, V.ns.L.ARENA_WATCH_WON_KO:format("Torvin Hale"), "kept through the calm")
	o.bodies[cast.A].combat, o.bodies[cast.B].combat = true, true
	w:Run(2)
	assert(not tostring(win.fight.text):find(V.ns.L.ARENA_WATCH_WON_KO:format("Torvin Hale"), 1, true), "a re-duel: no old winner: " .. tostring(win.fight.text))
	assert(tostring(win.fight.text):find(V.ns.L.ARENA_WATCH_NOT_OLYMPUS, 1, true), tostring(win.fight.text))
	w:As(V, View(V).Pin, "auto")
	W3.NoErrors(w)
end)

-- The regression (1.2.6): the bar looked for Bones' wood in the host's table (ns.Games), but the
-- companion keeps it in its own (own.Games, as BracketView.lua reads it): the bar was a flat colour.
test("watch duel view: the bar's strip is Bones' tavern wood (the companion's Games.WOOD) in its bronze edge", function()
	local e = Watch()
	local wood = e.V.companion.own.Games.WOOD
	eq(e.bar.bg.texture, wood.file); eq(rawget(e.bar.bg, "color"), nil, "no flat colour")
	eq(e.bar.bg.coords[3], wood.coords[3])
	W3.NoErrors(e.w)
end)

print("Spectate: gear and talents")

test("watch duel view: Gear: the slots' icons from the inspection, an empty slot's own picture, a good item's quality round it; hovering a slot shows the game's own tooltip of that item; the stats and resistances in dark ink, \"Items only, enchants not counted\", or that items still load", function()
	local e = Watch()
	local w, V, o, cast, A, I, tip = e.w, e.V, e.o, e.cast, e.A, e.I, e.tip
	o.items[cast.A] = { [1] = { id = 1001, link = "|cff1eff00|Hitem:1001::::::::60:::::|h[Ring Helm]|h|r" }, [16] = { id = 1003 } }
	o.stats[1001] = { ITEM_MOD_STRENGTH_SHORT = 11, ITEM_MOD_STAMINA_SHORT = 8, RESISTANCE3_NAME = 9 }
	o.stats[1003] = { ITEM_MOD_AGILITY_SHORT = 5 }
	o.uncached[1003] = true
	V.globals.C_Item.GetItemIconByID = function(id) return 130000 + id end
	V.globals.C_Item.GetItemQualityByID = function(id) return id == 1001 and 2 or 1 end
	V.globals.ITEM_QUALITY_COLORS = { [2] = { r = 0.12, g = 1, b = 0 } }
	V.globals.GetInventorySlotInfo = function(name) return 1, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name end
	w:Run(1)
	eq(A.stats.values.str.text, V.ns.L.ARENA_WATCH_DASH, "not inspected yet")
	Answer(w, V, I, "spectate:A")
	w:Run(1)
	local head, weapon, neck = A.stage.slots[1], A.stage.slots[16], A.stage.slots[2]
	eq(head.icon.texture, 131001); eq(head.frame.vertex[2], 1, "an uncommon item's green")
	eq(weapon.icon.texture, 131003)
	eq(neck.icon.texture, "Interface\\PaperDoll\\UI-PaperDoll-Slot-NeckSlot", "an empty slot's own picture"); eq(neck.icon.desaturated, true)
	eq(A.stats.values.str.text, "11"); eq(A.stats.values.sta.text, "8"); eq(A.stats.resist.nature.text, "9")
	eq(A.stats.note.text, V.ns.L.ARENA_WATCH_LOADING, "an item still loading")
	assert(A.stats.values.str.ink[1] < 0.3, "dark ink")
	w:As(V, head.scripts.OnEnter, head)
	eq(tip.owner, head); eq(tip.link, "item:1001::::::::60", "the game's own tooltip of that item"); eq(tip.shown, true)
	w:As(V, head.scripts.OnLeave, head)
	eq(tip.shown, false)
	w:As(V, neck.scripts.OnEnter, neck)
	eq(tip.owner, head, "an empty slot: no tooltip")
	o.uncached[1003] = nil
	w:Run(2)
	eq(A.stats.values.agi.text, "5"); eq(A.stats.note.text, V.ns.L.ARENA_WATCH_STATS_NOTE)
	W3.NoErrors(w)
end)

test("watch duel view: Talents for both halves (kept): each tree's grid by tier and column, \"3/5\", an untaken talent dimmed, its name and points; hovering a talent: its name, Passive, what it does, Rank 3 / 5; before the inspection the status line; points only: the trees' pictures and the line saying so", function()
	local e = Watch()
	local w, V, cast, A, B, I, tip = e.w, e.V, e.cast, e.A, e.B, e.I, e.tip
	ForeverTalents(V.globals)
	Answer(w, V, I, "spectate:A")
	local win = View(V).Frame()
	w:As(V, win.tabs.buttons[2].scripts.OnClick, win.tabs.buttons[2])
	eq(V.ns.db.arenaUI.watch.tab, "talents", "kept")
	eq(A.talents.shown, true); eq(A.gear.shown, false); eq(B.talents.shown, true, "both halves")
	local t1 = A.talents.trees[1]
	eq(t1.name.text, "Assassination"); eq(t1.points.text, V.ns.L.ARENA_WATCH_POINTS:format(5))
	local c1, c2, c3 = t1.cells[1], t1.cells[2], t1.cells[3]
	eq(c1.rank.text, "3/5"); eq(c1.icon.desaturated, false); eq(c1.icon.texture, 141201)
	eq(c2.rank.text, "0/5"); eq(c2.icon.desaturated, true); eq(c2.icon.alpha, 0.45, "dimmed")
	eq(c3.rank.text, "2/2"); eq(c3.rank.ink[1], 1, "a full talent's gold")
	local x1, y1 = c1.anchors[1][4], c1.anchors[1][5]
	eq(c2.anchors[1][5], y1, "the same tier"); eq(c2.anchors[1][4] > x1, true, "the next column")
	eq(c3.anchors[1][4], x1, "the same column"); eq(c3.anchors[1][5] < y1, true, "the next tier down")
	eq(A.talents.trees[2].name.text, "Combat"); eq(A.talents.trees[3].name.text, "Subtlety")
	w:As(V, c1.scripts.OnEnter, c1)
	eq(tip.owner, c1); eq(Lines(tip), "Talent 11201 | " .. V.ns.L.ARENA_WATCH_PASSIVE .. " | Reduces your speed penalty by 9%. | " .. V.ns.L.ARENA_WATCH_RANK:format(3, 5))
	eq(tip.lines[3].g, 0.82, "what it does in gold"); eq(tip.lines[3].wrap, true)
	w:As(V, c1.scripts.OnLeave, c1)
	eq(tip.shown, false)
	-- B not inspected yet: his status line there.
	eq(B.talents.note.text, V.ns.L.ARENA_WATCH_ST_INSPECTING)
	-- A client with the points per tree only.
	V.globals.C_Traits = nil
	w:As(V, V.ns.ArenaSpectate.Reinspect, "B")
	Answer(w, V, I, "spectate:B")
	w:Run(1.2)
	eq(B.talents.trees[1].name.text, "Assassination"); eq(B.talents.trees[1].icon.shown, true); eq(B.talents.trees[1].icon.texture, 101)
	eq(B.talents.note.text, V.ns.L.ARENA_WATCH_POINTS_ONLY)
	eq(#(B.talents.trees[1].cells), 0, "no grid")
	-- Back to Gear.
	w:As(V, win.tabs.buttons[1].scripts.OnClick, win.tabs.buttons[1])
	eq(A.gear.shown, true); eq(A.talents.shown, false)
	W3.NoErrors(w)
end)

test("watch duel view: each half's status line is the core's (\"Waiting for inspection – move within inspect range\"); Inspect again asks again", function()
	local e = Watch()
	local w, V, A, I = e.w, e.V, e.A, e.I
	I.wants["spectate:A"].status = "range"
	w:Run(1.2)
	eq(A.status.text, "Waiting for inspection – move within inspect range")
	-- (Asked again while it waits: the same want, back in line; Inspect.Want keeps a want still
	-- waiting rather than replacing it, so the ask is counted, not a new want.)
	local asked = I.asked["spectate:A"] or 0
	w:As(V, A.refresh.scripts.OnClick, A.refresh)
	eq(I.asked["spectate:A"], asked + 1, "asked again"); eq(I.wants["spectate:A"].status, "queued")
	eq(A.status.text, V.ns.L.ARENA_WATCH_ST_INSPECTING)
	W3.NoErrors(w)
end)

print("Spectate: kept, closed, weightless")

-- Regression (the login's settings check, ArenaHome.CheckUI, keeps only the fields it knows: the
-- view's place, scale, pin and tab were dropped at every login before "watch" was one of them).
test("watch duel view: -/+ scale both the window and the bar within 0.6-1.6; their dragged places, the scale, the pin and the tab are kept and survive the login's settings check", function()
	local e = Watch()
	local w, V = e.w, e.V
	local win, b = View(V).Frame(), View(V).Bar()
	for _ = 1, 9 do w:As(V, win.larger.scripts.OnClick, win.larger) end
	eq(V.ns.db.arenaUI.watch.scale, 1.6); eq(win.scale, 1.6); eq(b.scale, 1.6)
	for _ = 1, 3 do w:As(V, win.smaller.scripts.OnClick, win.smaller) end
	eq(V.ns.db.arenaUI.watch.scale, 1.3)
	win:ClearAllPoints(); win:SetPoint("TOPLEFT", nil, "TOPLEFT", 120, -60)
	w:As(V, win.scripts.OnDragStop, win)
	b:ClearAllPoints(); b:SetPoint("BOTTOM", nil, "BOTTOM", 10, 240)
	w:As(V, b.scripts.OnDragStop, b)
	w:As(V, View(V).Pin, "compact")
	w:As(V, View(V).SetTab, "talents")
	V.ns.db.arenaUI.watch.junk = "x"
	w:As(V, V.ns.ArenaHome.CheckUI)
	local kept = V.ns.db.arenaUI.watch
	assert(kept, "the view's settings kept through the login's check")
	eq(kept.scale, 1.3); eq(kept.pin, "compact"); eq(kept.tab, "talents"); eq(kept.junk, nil)
	eq(table.concat(kept.point, ","), "TOPLEFT,TOPLEFT,120,-60"); eq(table.concat(kept.barPoint, ","), "BOTTOM,BOTTOM,10,240")
	V.ns.db.arenaUI.watch = { scale = 9, pin = "nowhere", point = { "TOP" } }
	w:As(V, V.ns.ArenaHome.CheckUI)
	eq(V.ns.db.arenaUI.watch.scale, 1.6, "clamped"); eq(V.ns.db.arenaUI.watch.pin, nil); eq(V.ns.db.arenaUI.watch.point, nil)
	-- A new watch opens where it was left.
	w:As(V, View(V).Hide)
	V.ns.db.arenaUI.watch = kept
	assert(S(w, V).Open(assert(S(w, V).PairFromUnit("target"))))
	eq(View(V).Mode(), "compact", "the pin kept")
	W3.NoErrors(w)
end)

test("watch duel view: its X, Escape or /oly arena watch off close it: the tickers cancelled, every event unregistered, the session over; a swap to the bar or the UI hidden with its parent is no close; in combat it goes on updating", function()
	local e = Watch()
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	o.bodies[cast.A] = { hp = 10, hpMax = 20, grouped = true }
	local win = View(V).Frame()
	-- The UI hidden (Alt+Z): its OnHide comes while it is still shown itself.
	Hidden(w, V, win)
	assert(S(w, V).Watching(), "not closed by its parent's hide")
	-- In combat (the spectator's): still updating.
	w:Combat(V, true)
	o.bodies[cast.A].hp = 12
	w:Run(0.2)
	eq(win.halves.A.hpText.text, "12 / 20")
	w:Combat(V, false)
	-- Its X (Escape hides it the same way).
	w:As(V, win.close.scripts.OnClick, win.close)
	eq(win:IsShown(), false); eq(View(V).Bar():IsShown(), false)
	eq(S(w, V).Watching(), nil, "the session over")
	local ticking, casting = View(V).Ticking()
	eq(ticking, false); eq(casting, false)
	eq(next(View(V).Events().events), nil, "every event unregistered")
	local involved = table.concat(V.ns.Arena.Involved(), ",")
	assert(not involved:find("spectate", 1, true), involved)
	for _, t in ipairs(w:Timers(V, true)) do assert(not (t.every == 0.2 or t.every == 0.1), "a ticker of the view's left") end
	-- Again, closed by /oly arena watch off.
	assert(S(w, V).Open(assert(S(w, V).PairFromUnit("target"))))
	eq(win:IsShown(), true)
	w:As(V, V.ns.Arena.RunSlash, "watch off")
	eq(win:IsShown(), false); eq(S(w, V).Watching(), nil); eq((View(V).Ticking()), false)
	W3.NoErrors(w)
end)

test("watch duel view: the weight rule: a member who never watches has no frame, ticker or event of the view's; a whole watch calls none of UnitInRange, TargetUnit, FocusUnit, SetCVar (each raises)", function()
	local e = Watch(nil, false)
	local w, V, o, cast = e.w, e.V, e.o, e.cast
	local idle = w:ArenaWeight(V)
	eq(View(V).Frame(), nil); eq(View(V).Bar(), nil); eq(View(V).Events(), nil)
	for _, c in ipairs(V.frames) do assert(not tostring(c.frame.name or ""):find("OlympusArenaWatch", 1, true), "no frame of the view's") end
	o.bodies[cast.A] = { combat = true, cast = { name = "Smite", texture = 1, start = 1, finish = 2 } }
	assert(S(w, V).Open(assert(S(w, V).PairFromUnit("target"))))
	w:Run(2)
	Event(w, V, "PLAYER_TARGET_CHANGED")
	Event(w, V, "UNIT_INVENTORY_CHANGED", "target")
	w:Run(2)
	w:As(V, View(V).Hide)
	local after = w:ArenaWeight(V)
	eq(table.concat(after.events, ","), table.concat(idle.events, ","), "no listener left")
	assert(after.timers <= idle.timers, "no timer left: " .. after.timers .. " of " .. idle.timers)
	W3.NoErrors(w)
end)

-- Every value Forever keeps secret comes into the view through the core's S.Push and S.Cast only
-- (the sentinel can't trap a truth test or a table key: the source is read too).
test("watch duel view: the source: Spectate.lua names none of UnitHealth, UnitHealthPercent, UnitPower, UnitPowerPercent, UnitCastingInfo, UnitChannelInfo, and reads no widget back", function()
	local f = assert(io.open(H.ARENA_DIR .. "Spectate.lua", "rb"))
	local src = f:read("*a")
	f:close()
	local code = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
	for _, api in ipairs({ "UnitHealth", "UnitHealthMax", "UnitHealthPercent", "UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitCastingInfo", "UnitChannelInfo" }) do
		eq(code:find("%f[%w_]" .. api .. "%f[^%w_]") ~= nil, false, api .. " in the view")
	end
	for _, read in ipairs({ ":GetValue(", ":GetMinMaxValues(", ":GetText(", ":GetTexture(" }) do
		eq(code:find(read, 1, true) ~= nil, false, read .. " in the view")
	end
	assert(code:find("S.Push(key, w.live)", 1, true) and code:find("S.Cast(key, c.widgets)", 1, true), "through the core")
end)

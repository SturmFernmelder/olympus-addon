-- 1.2.1, the stutter players reported (it stopped with Olympus off): what the views do while nobody
-- looks at them. The world map's census refresh with the map closed (Map.lua), the crafters' board
-- each minute (Crafters.lua), and the Olympus Chat tab's redraws (ChatWindow.lua). Counted with
-- spies (timers, the pin library's calls, the moderators' word asked, sorts, bubbles laid out),
-- never by the clock of this machine.
local ns, test, eq, h = ...
local ADDON_DIR = h.ADDON_DIR

local function SameLog(got, want, what)
	eq(table.concat(got, ", "), table.concat(want, ", "), what)
end

---------------------------------------------------------------------------
-- The world map
---------------------------------------------------------------------------

-- Map.lua loaded fresh against `lib` (RecordingPins): its message listeners (w.fire), its timers
-- (w.run) and its gamepad gate's hooks (w.gate) kept here, not given to the addon's.
local function LoadMap(lib)
	local w = { on = {}, timers = {}, gate = {} }
	local gns = setmetatable({}, { __index = ns })
	gns.On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end
	gns.After = function(sec, where, fn) w.timers[#w.timers + 1] = { sec = sec, where = where, fn = fn } end
	gns.Gate = setmetatable({ Hooks = function(id, t) w.gate[id] = t end, Install = function() end }, { __index = ns.Gate })
	local savedLibStub = LibStub
	LibStub = function(name) if name == "HereBeDragons-Pins-2.0" then return lib end end
	local ok, err = pcall(function() assert(loadfile(ADDON_DIR .. "Map.lua"))("Olympus", gns) end)
	LibStub = savedLibStub
	if not ok then error(err, 0) end
	lib.names[gns.Map] = "Map"
	w.ns, w.Map = gns, gns.Map
	w.fire = function(name, ...) for _, fn in ipairs(w.on[name] or {}) do fn(...) end end
	w.run = function()
		local t = w.timers
		w.timers = {}
		for _, x in ipairs(t) do x.fn() end
	end
	return w
end

test("1.2.1 performance: the census leaves the closed world map alone (no timer, no pin taken off or put back, only marked); opened, it is drawn once; the map's menu and /oly map still draw at once", function()
	h.WithMapIcons(function()
		h.WithGamepadUI(false, function()
			local lib = h.RecordingPins()
			local w = LoadMap(lib)
			local Map = w.Map
			local summaries = 0
			local summary = ns.Data.Summary
			ns.Data.Summary = function(...) summaries = summaries + 1; return summary(...) end
			local ok, err = pcall(function()
				local onShow
				WorldMapFrame.HookScript = function(_, kind, fn) if kind == "OnShow" then onShow = fn end end
				WorldMapFrame.shown = false
				-- Census reports with the map closed (on the owner's game ~0.7 a second, bursts of 9).
				for _ = 1, 9 do w.fire("DATA_CHANGED") end
				eq(#w.timers, 0, "no refresh queued while the map is closed")
				SameLog(lib:Take(), {}, "no pin touched")
				eq(summaries, 0, "the census not summed for it")
				eq(Map.dirty, true, "marked for its opening")
				-- Mouse and keyboard: the map's hooks (the gate's "map-overlay"); the map opened: drawn
				-- once, from the census as it is now.
				w.gate["map-overlay"].install()
				SameLog(lib:Take(), {}, "the hooks alone draw nothing while it is closed")
				assert(type(onShow) == "function", "its OnShow hooked")
				WorldMapFrame.shown = true
				onShow(WorldMapFrame)
				SameLog(lib:Take(), { "worldAll Map", "world+ Map 1453", "world+ Map 1429" }, "drawn at its opening")
				eq(Map.dirty, false)
				eq(#Map.overlayData, 1, "the continent's total too"); eq(Map.overlayData[1].count, 10)
				-- Closed and opened again with nothing new: nothing.
				WorldMapFrame.shown = false; WorldMapFrame.shown = true
				onShow(WorldMapFrame)
				SameLog(lib:Take(), {}, "nothing changed: nothing drawn")
				-- Open: the census redraws it as before, once per gap.
				w.fire("DATA_CHANGED"); w.fire("DATA_CHANGED")
				eq(#w.timers, 1, "one refresh queued while open"); eq(w.timers[1].sec, Map.RefreshGap())
				w.run()
				SameLog(lib:Take(), { "worldAll Map", "world+ Map 1453", "world+ Map 1429" }, "redrawn while open")
				-- Queued while open, closed before its turn: left for the next opening.
				w.fire("DATA_CHANGED")
				eq(#w.timers, 1)
				WorldMapFrame.shown = false
				w.run()
				SameLog(lib:Take(), {}, "closed by then: not drawn")
				eq(Map.dirty, true)
				w.fire("DATA_CHANGED")
				eq(#w.timers, 0, "and nothing queued after it")
				-- Asked for by name with the map closed (its menu, /oly map, Map.SetEnabled): at once.
				Map.SetEnabled(true)
				SameLog(lib:Take(), { "worldAll Map", "world+ Map 1453", "world+ Map 1429" }, "Map.SetEnabled draws at once")
				eq(Map.dirty, false, "and is up to date")
				Map.Refresh()
				SameLog(lib:Take(), { "worldAll Map", "world+ Map 1453", "world+ Map 1429" }, "Map.Refresh too")
				WorldMapFrame.shown = true
				onShow(WorldMapFrame)
				SameLog(lib:Take(), {}, "opened after it: nothing again")
				-- Switched to mouse and keyboard with the map open and a census change waiting: drawn then.
				WorldMapFrame.shown = false
				w.fire("DATA_CHANGED")
				WorldMapFrame.shown = true
				w.gate["map-overlay"].install()
				SameLog(lib:Take(), { "worldAll Map", "world+ Map 1453", "world+ Map 1429" }, "at the switch, with the map open")
			end)
			ns.Data.Summary = summary
			if not ok then error(err, 0) end
		end)
	end)
end)

-- With the gamepad UI nothing of Olympus's is on the world map: its opening draws nothing there.
test("1.2.1 performance: with the gamepad UI, the world map's opening takes nothing off and puts nothing on it; the census redraws it while open, as before", function()
	h.WithMapIcons(function()
		h.WithGamepadUI(true, function()
			local lib = h.RecordingPins()
			local w = LoadMap(lib)
			WorldMapFrame.shown = false
			w.fire("DATA_CHANGED")
			eq(#w.timers, 0); eq(w.Map.dirty, true)
			WorldMapFrame.shown = true
			w.Map.WorldMapShown()
			SameLog(lib:Take(), {}, "nothing on the gamepad map")
			w.fire("DATA_CHANGED")
			eq(#w.timers, 1, "open: the census's refresh as before")
		end)
	end)
end)

---------------------------------------------------------------------------
-- The crafters' board
---------------------------------------------------------------------------

-- The board as this client holds it, the clock (w.clock) its own; nothing of ours listed, nothing sent.
local function WithBoard(fn)
	local Cr = ns.Crafters
	local saved = { now = ns.Now, send = ns.Comm.Send, choice = ns.db.crafterChoice, data = ns.db.crafterData }
	local w = { clock = 5000000, sent = {} }
	local ok, err = pcall(function()
		Cr.Reset()
		ns.db.crafterChoice, ns.db.crafterData = nil, nil
		ns.Now = function() return w.clock end
		ns.Comm.Send = function(dist, msg) w.sent[#w.sent + 1] = dist .. " " .. msg end
		fn(w, Cr)
	end)
	ns.Now, ns.Comm.Send, ns.db.crafterChoice, ns.db.crafterData = saved.now, saved.send, saved.choice, saved.data
	Cr.Reset()
	if not ok then error(err, 0) end
end

test("1.2.1 performance: the crafters' minute tick only forgets the quiet listings: no board built, no moderators' word asked, nothing sorted; the board, built for its page, is the same", function()
	WithBoard(function(w, Cr)
		local start = w.clock
		for i = 1, 10 do Cr.HandleListing("CHANNEL", "Quiet Crafter" .. i .. "-Realm", "W1~Olympus Zeus~197:Tailoring:250:300:12") end
		w.clock = start + 1000
		for i = 1, 20 do Cr.HandleListing("CHANNEL", "Busy Crafter" .. i .. "-Realm", "W1~Olympus Zeus~164:Blacksmithing:200:300:30") end
		local M = ns.Moderation
		local asked, sorts = 0, 0
		local hides, sort = M.Hides, table.sort
		M.Hides = function(...) asked = asked + 1; if hides then return hides(...) end end
		-- (A sort of the board's size: our own listing's professions, none here, may be sorted.)
		table.sort = function(t, ...) if #t >= 20 then sorts = sorts + 1 end return sort(t, ...) end
		local prune, forgot = Cr.Prune, {}
		Cr.Prune = function(...) local n = prune(...); forgot[#forgot + 1] = n; return n end
		local board, built = Cr.Board, 0
		Cr.Board = function(...) built = built + 1; return board(...) end
		local ok, err = pcall(function()
			Cr.Tick()
			eq(built, 0, "no board built")
			eq(asked, 0, "no crafter asked of the moderators' word (30 before, each minute)")
			eq(sorts, 0, "nothing of the board sorted")
			eq(table.concat(forgot, ","), "0", "the tick forgets who went quiet: nobody yet")
			-- The first ten went quiet LIST_KEEP ago: the tick forgets them, still building nothing.
			w.clock = start + Cr.LIST_KEEP + 1
			Cr.Tick()
			eq(table.concat(forgot, ","), "0,10", "the ten quiet ones forgotten")
			eq(built, 0); eq(asked, 0); eq(sorts, 0)
			-- The page builds it: the twenty left, sorted, each asked of the word.
			local names = {}
			for _, c in ipairs(Cr.Board()) do names[#names + 1] = c.name end
			eq(#names, 20)
			for i = 2, #names do assert(names[i - 1] < names[i], "sorted") end
			eq(asked, 20, "each crafter asked of the word for the page"); eq(sorts, 1)
			local page = {}
			for _, l in ipairs(Cr.Lines()) do page[#page + 1] = tostring(l.text) end
			page = table.concat(page, "\n")
			assert(page:find("Busy Crafter1", 1, true) and not page:find("Quiet Crafter", 1, true), page)
			eq(#w.sent, 0, "(nothing of ours listed: nothing sent)")
		end)
		M.Hides, table.sort, Cr.Prune, Cr.Board = hides, sort, prune, board
		if not ok then error(err, 0) end
	end)
end)

---------------------------------------------------------------------------
-- The Olympus Chat tab
---------------------------------------------------------------------------

local T0 = h.T0
local function Line(t, sender, text, extra)
	local e = { t = t, sender = sender, guild = "Olympus II", text = text }
	for k, v in pairs(extra or {}) do e[k] = v end
	return e
end

-- How many bubbles were laid out (their line's words set) while fn ran.
local function LaidOut(w, fn)
	local W = h.Widget
	local set = {}
	local orig = rawget(W, "SetText")
	W.SetText = function(self, text) set[#set + 1] = self; return orig(self, text) end
	local ok, err = pcall(fn)
	W.SetText = orig
	if not ok then error(err, 0) end
	local bodies = {}
	for _, b in ipairs(w.CW.Frame().bubbles) do bodies[b.body] = true end
	local n = 0
	for _, s in ipairs(set) do if bodies[s] then n = n + 1 end end
	return n
end

-- The tab's bubbles as they show, top to bottom: words, header, size, side and place.
local function Shown(f)
	local out = {}
	for _, b in ipairs(f.bubbles) do
		if b:IsShown() then
			local a = b:Anchor("TOPLEFT") or b:Anchor("TOPRIGHT")
			local head = b.header:IsShown()
			out[#out + 1] = table.concat({ tostring(b.body:GetText()), tostring(b.body:GetWidth()), tostring(head),
				head and tostring(b.who:GetText()) or "", head and tostring(b.time:GetText()) or "", tostring(b:GetWidth()),
				tostring(b:GetHeight()), a[1], tostring(a[5]), tostring(b.entry and b.entry.text) }, " / ")
		end
	end
	return out
end

local function SameShown(got, want, what)
	eq(#got, #want, what .. ": bubbles")
	for i = 1, #want do eq(got[i], want[i], what .. ": bubble " .. i) end
end

local function History(n)
	local list = {}
	for i = 1, n do
		list[i] = Line(T0 + i * 10, (i % 2 == 0) and "Aa-Realm" or "Bb-Realm", "line number " .. i .. " " .. ("words "):rep(i % 7 * 4))
	end
	return list
end

test("1.2.1 performance: the Chat tab: a new line lays out its own bubble alone, at a channel's 100 lines too (the others only move, each with its line); the same tab as a full redraw; a resize, a setting or a new scale lays them out again", function()
	h.WithWindow(function(w)
		local list = History(100)
		ns.rdb.chat = { A = list }
		local f
		eq(LaidOut(w, function() f = w.CW.Open("A") end), 100, "opened: every line laid out")
		-- A new line at the channel's 100: the oldest goes, every bubble moves up.
		local function Arrive(text, sender)
			table.remove(list, 1)
			list[#list + 1] = Line(list[#list].t + 10, sender or "Cc-Realm", text)
			w.fire("CHAT_CHANGED", "A"); w.fire("CHAT_LINE", "A", sender or "Cc-Realm", text)
			f:Fire("OnUpdate", 0.3)
		end
		local first = list[2]
		eq(LaidOut(w, function() Arrive("the newest line") end), 1, "only the new line laid out (100 before)")
		eq(#f.bubbles, 100, "no bubble made")
		local reused = Shown(f)
		eq(reused[1]:find("line number 2 ", 1, true), 1, "the oldest gone")
		for _, b in ipairs(f.bubbles) do if b.entry == first then assert(b.header:IsShown(), "the new first line starts its group") end end
		-- Just what a full redraw shows.
		w.CW.ForgetLooks()
		eq(LaidOut(w, function() w.CW.Render() end), 100, "(a full redraw)")
		SameShown(Shown(f), reused, "the same as a full redraw")
		-- A line from the writer of the last one: it joins his group (no header); its bubble alone.
		Arrive("first of mine", "Dd-Realm")
		eq(LaidOut(w, function() Arrive("second of mine", "Dd-Realm") end), 1)
		reused = Shown(f)
		w.CW.ForgetLooks(); w.CW.Render()
		SameShown(Shown(f), reused, "a group's second line")
		-- Ten lines at once (one redraw): the ten alone.
		eq(LaidOut(w, function()
			for k = 1, 10 do
				table.remove(list, 1)
				list[#list + 1] = Line(list[#list].t + 400, "Ee" .. k .. "-Realm", "burst " .. k)
				w.fire("CHAT_LINE", "A", "Ee" .. k .. "-Realm", "burst " .. k)
			end
			f:Fire("OnUpdate", 0.3)
		end), 10)
		-- Nothing new: a redraw lays out nothing.
		eq(LaidOut(w, function() w.CW.Render() end), 0, "nothing new")
		-- A wider window: every bubble wraps again.
		eq(LaidOut(w, function() w.CW.Window():SetSize(800, 600); w.CW.Render() end), 100, "a resize lays them all out again")
		-- The guild names hidden (the gear): every header changes, laid out again.
		local savedHide = ns.db.chatHideGuildNames
		ns.db.chatHideGuildNames = true
		local n = LaidOut(w, function() w.fire("CHAT_SETTINGS_CHANGED"); f:Fire("OnUpdate", 0.3) end)
		ns.db.chatHideGuildNames = savedHide
		local headers = 0
		for _, b in ipairs(f.bubbles) do if b:IsShown() and b.header:IsShown() then headers = headers + 1 end end
		eq(n, headers, "each line with a header laid out again")
		-- The UI's scale: all of them.
		eq(LaidOut(w, function() w.event("UI_SCALE_CHANGED"); f:Fire("OnUpdate", 0.3) end), 100, "a new scale lays them all out again")
		-- A line the block terms hide, revealed by a click: that bubble alone.
		local savedHides = ns.Filter.Hides
		ns.Filter.Hides = function(text) return text:find("burst 3", 1, true) ~= nil end
		eq(LaidOut(w, function() w.CW.Render() end), 1, "the hidden line greyed")
		local veiled
		for _, b in ipairs(f.bubbles) do if b:IsShown() and b.hidden then veiled = b end end
		assert(veiled, "the hidden line's bubble")
		eq(LaidOut(w, function() veiled:Fire("OnMouseUp", "LeftButton") end), 1, "revealed: that bubble alone")
		ns.Filter.Hides = savedHides
	end)
end)

test("1.2.1 performance: the Chat tab, scrolled up at a channel's 100 lines: new lines lay out no other bubble and the line read stays in its place", function()
	h.WithWindow(function(w)
		local list = History(100)
		ns.rdb.chat = { A = list }
		local f = w.CW.Open("A")
		local s = f.scroll
		s:Settle()
		s:SetVerticalScroll(math.floor(s:GetVerticalScrollRange() / 2))
		local function AtTop()
			local at = s:GetVerticalScroll()
			for _, b in ipairs(f.bubbles) do
				local a = b:IsShown() and (b:Anchor("TOPLEFT") or b:Anchor("TOPRIGHT"))
				if a and -a[5] + b:GetHeight() > at then return b.entry, -a[5] - at end
			end
		end
		local read, off = AtTop()
		local n = LaidOut(w, function()
			for k = 1, 3 do
				table.remove(list, 1)
				list[#list + 1] = Line(list[#list].t + 10, "Cc-Realm", "new " .. k)
				w.fire("CHAT_LINE", "A", "Cc-Realm", "new " .. k)
				f:Fire("OnUpdate", 0.3)
				s:Settle()
			end
		end)
		eq(n, 3, "the three new lines alone")
		local now, nowOff = AtTop()
		eq(now, read, "the same line at the view's top"); eq(nowOff, off, "in the same place")
	end)
end)

test("1.2.1 performance: the Chat tab's redraws a change asks for wait ten times what the last one cost (at least 0.2 s, as before, at most 5 s); a click still draws at once", function()
	h.WithWindow(function(w)
		local CW = w.CW
		eq(CW.RedrawGap(), 0.2, "nothing measured yet: as before")
		ns.rdb.chat = { A = { Line(T0, "Aa-Realm", "hello") } }
		local f = CW.Open("A")
		local draws = 0
		local real = ns.Channels.History
		ns.Channels.History = function(...) draws = draws + 1; return real(...) end
		-- The client's clock (ChatWindow.Clock: debugprofilestop) moves `step` ms each read.
		local ms, step = 0, 100
		local savedClock, savedProfile = CW.Clock, debugprofilestop
		local ok, err = pcall(function()
			-- (WithWindow's tab has no clock; a fresh ChatWindow.lua's reads the client's.)
			local fresh = setmetatable({ On = function() end, RegisterEvent = function() end }, { __index = ns })
			assert(loadfile(ADDON_DIR .. "ChatWindow.lua"))("Olympus", fresh)
			debugprofilestop = function() return 1234.5 end
			eq(fresh.ChatWindow.Clock(), 1234.5, "ChatWindow.Clock reads the client's debugprofilestop")
			debugprofilestop = nil
			eq(fresh.ChatWindow.Clock(), nil, "none on a client without it")
			debugprofilestop = savedProfile
			CW.Clock = function() local v = ms; ms = ms + step; return v end
			local function Arrive(text)
				local l = ns.rdb.chat.A
				l[#l + 1] = Line(T0 + #l, "Bb-Realm", text)
				w.fire("CHAT_CHANGED", "A"); w.fire("CHAT_LINE", "A", "Bb-Realm", text)
			end
			CW.Render() -- (100 ms)
			eq(CW.RedrawGap(), 1, "ten times 100 ms")
			draws = 0
			Arrive("one")
			f:Fire("OnUpdate", 0.3)
			eq(draws, 0, "not after 0.3 s (drawn then before)")
			f:Fire("OnUpdate", 0.3); f:Fire("OnUpdate", 0.3)
			eq(draws, 0, "nor 0.9 s")
			f:Fire("OnUpdate", 0.3)
			eq(draws, 1, "after its second")
			Arrive("two")
			f:Fire("OnUpdate", 0.3)
			eq(draws, 1, "the next waits as long")
			-- A click draws at once, whatever the gap.
			CW.SelectLegacy("A")
			eq(draws, 2, "a channel picked: at once")
			-- At most 5 s; a cheap redraw: 0.2 s, as before.
			step = 20000
			CW.Render()
			eq(CW.RedrawGap(), 5, "at most 5 s")
			step = 1
			CW.Render()
			eq(CW.RedrawGap(), 0.2, "a cheap redraw: as before")
			draws = 0
			Arrive("three")
			f:Fire("OnUpdate", 0.3)
			eq(draws, 1, "drawn at the next 0.2 s")
		end)
		CW.Clock, debugprofilestop = savedClock, savedProfile
		ns.Channels.History = real
		if not ok then error(err, 0) end
	end)
end)

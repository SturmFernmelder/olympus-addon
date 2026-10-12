-- 1.2.1, the stutter players reported (it stopped with the addon off; memory and the shown CPU
-- low): measured on the owner's PC, every census report heard (about one a second, up to nine in a
-- burst) ran every DATA_CHANGED listener at once inside the game's addon-message event, the open
-- window redrew from inside them, the roster's scan fired it once a minute for a report that had
-- not changed, every PLAYER_GUILD_UPDATE (a nameplate's too) queued a guild change, and the
-- addon's dozens of tickers all started on one frame. Each part here through the real file
-- (Data.lua, Roster.lua, Core.lua's ns.Every, UI.lua), counted by spies, never by the clock.
local H = ...
local test, eq = H.test, H.eq
local ns = H.ns

print("1.2.1 performance: the census's news coalesced, the roster's scan, the tickers spread")

-- Data.lua in a namespace of its own (nothing registered on the harness's): its DATA_CHANGED
-- fires and its timers kept here, the clock the test's.
local function CensusWorld()
	local w = { fires = 0, timers = {}, clock = 2000000000 }
	local dns = setmetatable({
		rdb = { guilds = {}, seen = {} },
		Who = { Listen = function() end },
		On = function() end,
		Fire = function(name)
			if name ~= "DATA_CHANGED" then return end
			w.fires = w.fires + 1
			if w.onFire then w.onFire() end
		end,
		After = function(seconds, where, fn) w.timers[#w.timers + 1] = { seconds = seconds, where = where, fn = fn } end,
		Now = function() return w.clock end,
	}, { __index = ns })
	assert(loadfile(H.ADDON_DIR .. "Data.lua"))("Olympus", dns)
	w.ns, w.D = dns, dns.Data
	-- The timers due now, run (those they make wait for the next call); how many ran.
	function w.Run()
		local due = w.timers
		w.timers = {}
		for _, t in ipairs(due) do t.fn() end
		return #due
	end
	return w
end

local function Report(guild, sender, leader)
	return { guild = guild, faction = ns.faction, total = 20, online = 2, zones = {},
		leader = leader or ns.ShortName(sender), officers = {} }
end

local function Receive(w, guild, sender, leader)
	return w.D.Receive(Report(guild, sender, leader), sender)
end

test("1.2.1 census news: nine reports heard in a burst fire DATA_CHANGED once, from one timer a second later, never inside the report's own handler", function()
	local w = CensusWorld()
	local D = w.D
	local before = D.Revision and D.Revision() -- (1.2.1's)
	for k = 1, 9 do
		eq(Receive(w, "Olympus Burst " .. k, "Burstvoice" .. k .. "-Realm"), true, "report " .. k .. " taken")
		eq(w.fires, 0, "nothing fired inside the handler of report " .. k)
	end
	eq(#w.timers, 1, "one timer for the nine")
	eq(w.timers[1].where, "census changed")
	eq(w.timers[1].seconds, D.NOTIFY_GAP); eq(D.NOTIFY_GAP, 1)
	eq(D.Revision() - before, 9, "each report a revision of the census")
	eq(w.Run(), 1)
	eq(w.fires, 1, "one DATA_CHANGED for the nine")
	-- The next report waits for a timer of its own.
	eq(Receive(w, "Olympus Burst 1", "Burstvoice1-Realm"), true)
	eq(w.fires, 1); eq(#w.timers, 1)
	w.Run()
	eq(w.fires, 2)
	-- Nothing heard since: nothing waits, nothing fired.
	eq(w.Run(), 0); eq(w.fires, 2)
	-- A report not taken (another guild claimed by the same sender) changes nothing.
	local revision = D.Revision()
	eq(Receive(w, "Olympus Other", "Burstvoice1-Realm"), false)
	eq(#w.timers, 0); eq(D.Revision(), revision)
end)

test("1.2.1 census news: a report the other senders outvote waits for the same one timer, its vote kept", function()
	local w = CensusWorld()
	local D = w.D
	eq(Receive(w, "Olympus Vote", "Votera-Realm", "Leaderone"), true)
	eq(Receive(w, "Olympus Vote", "Voterb-Realm", "Leaderone"), true)
	w.Run()
	local fires, revision = w.fires, D.Revision()
	-- A third sender names another leader: two senders say otherwise, the row stays theirs.
	eq(Receive(w, "Olympus Vote", "Voterc-Realm", "Leadertwo"), false, "outvoted")
	local g = w.ns.rdb.guilds["Olympus Vote"]
	eq(g.outvoted, true); eq(g.leader, "Leaderone")
	assert(g.vouch["Voterc-Realm"], "its vote kept")
	eq(w.fires, fires, "nothing fired inside its handler")
	eq(#w.timers, 1); eq(w.timers[1].where, "census changed")
	eq(D.Revision(), revision + 1)
	-- A report taken right after it: the same timer.
	eq(Receive(w, "Olympus Burst 2", "Burstvoice2-Realm"), true)
	eq(#w.timers, 1)
	w.Run()
	eq(w.fires, fires + 1)
end)

test("1.2.1 census news: a guild heard twice within the gap: its first report is told to the listeners before the second takes its place, as each report was before", function()
	local w = CensusWorld()
	local D = w.D
	local seen = {}
	w.onFire = function()
		local g = w.ns.rdb.guilds["Olympus Twice"]
		seen[#seen + 1] = g and g.reporterFull or "-"
	end
	local revision = D.Revision()
	eq(Receive(w, "Olympus Twice", "Firstvoice-Realm", "Leaderone"), true)
	eq(w.fires, 0, "the first: nothing inside its handler")
	eq(Receive(w, "Olympus Twice", "Secondvoice-Realm", "Leaderone"), true)
	eq(w.fires, 1, "the second: the first one told before it is replaced")
	eq(seen[1], "Firstvoice-Realm", "the listeners read the first report's row")
	eq(w.ns.rdb.guilds["Olympus Twice"].reporterFull, "Secondvoice-Realm", "the second took its place")
	eq(#w.timers, 1, "still the one timer")
	eq(D.Revision(), revision + 2, "a revision a report, none for the telling")
	eq(w.Run(), 1)
	eq(w.fires, 2, "the timer tells the second")
	eq(seen[2], "Secondvoice-Realm")
	-- Told by the timer: the next report of that guild is no reason to fire inside its handler.
	eq(Receive(w, "Olympus Twice", "Firstvoice-Realm", "Leaderone"), true)
	eq(w.fires, 2)
	w.Run()
	eq(w.fires, 3)
	-- Told at once by the player's own change (a /who) meanwhile: neither.
	eq(Receive(w, "Olympus Twice", "Secondvoice-Realm", "Leaderone"), true)
	D.RecordSightings({ { guild = "Olympus Seen" } })
	eq(w.fires, 4, "the /who: at once")
	eq(Receive(w, "Olympus Twice", "Firstvoice-Realm", "Leaderone"), true)
	eq(w.fires, 4, "its row was told by the /who")
	w.Run()
	eq(w.fires, 5)
	-- A burst of other guilds' reports: still nothing inside a handler.
	for k = 1, 5 do eq(Receive(w, "Olympus Many " .. k, "Manyvoice" .. k .. "-Realm"), true) end
	eq(w.fires, 5)
	w.Run()
	eq(w.fires, 6)
end)

test("1.2.1 census news: two senders of a guild heard within one second both count for a level-race claim (the review's probe)", function()
	local W3 = assert(loadfile(H.ROOT .. "tests/arena/lib/fights-world.lua"))(H)
	local w, cast = W3.New({ more = { { "young", "Brisa Vale", { level = 19 } },
		{ "reporter", "Dovan Quell" }, { "reporter2", "Elsa Thornby" } } })
	local young, viewer = cast.young, cast.spectator
	-- The viewer's own census (the world shares the harness's Data otherwise).
	w:As(viewer, function() assert(loadfile(H.ADDON_DIR .. "Data.lua"))("Olympus", viewer.ns) end)
	viewer.ns.HonorsNet.RACE_START = w.clock - 86400
	w:Fire(young, "PLAYER_LEVEL_UP", 20)
	w:Run(61)
	local claim
	for _, c in pairs(viewer.ns.HonorsNet.Store().claims) do claim = c end
	assert(claim, "her claim heard")
	eq(claim.vouched, false, "no census yet")
	local function Rep()
		return { guild = "Olympus Vale", faction = viewer.ns.faction or "Alliance", total = 20, online = 2, zones = {},
			leader = "Corin Ash", officers = {}, top = { { name = "Brisa Vale", level = 20, class = "MA" } } }
	end
	eq(w:As(viewer, function() return viewer.ns.Data.Receive(Rep(), cast.reporter.name) end), true)
	eq(w:As(viewer, function() return viewer.ns.Data.Receive(Rep(), cast.reporter2.name) end), true)
	eq(viewer.rdb.guilds["Olympus Vale"].reporterFull, cast.reporter2.name, "the second report is the row")
	w:Run(2)
	local senders = 0
	for _, list in pairs(claim.by or {}) do for _ in pairs(list) do senders = senders + 1 end end
	eq(senders, 2, "both senders seen")
	eq(claim.vouched, true, "two senders of her guild: vouched")
end)

-- Our guild's report as Roster.Scan builds it (the fields that matter here).
local function Ours(online)
	return { guild = "Olympus II", total = 100, online = online, zones = { m1453 = online }, classes = { MA = online },
		levels = { 0, 0, 0, 0, 0, 0, online }, ranks = { { name = "Zeus", count = 1 }, { name = "Hero", count = 99 } },
		officers = { { name = "Officerone", online = true, days = 0, class = "MA", level = 60 } },
		top = { { name = "Officerone", level = 60, class = "MA" } }, avgLevel = 42.5, leader = "Leaderone", leaderOnline = true }
end

test("1.2.1 census news: our roster's report tells DATA_CHANGED through the one timer when it changed, never inside the scan, and not at all when it came out as the last one did", function()
	local w = CensusWorld()
	local D = w.D
	D.SetLocal(Ours(5))
	eq(w.fires, 0, "nothing inside the scan")
	eq(#w.timers, 1, "the session's first report of ours: news, through the timer")
	eq(w.timers[1].where, "census changed"); eq(w.timers[1].seconds, D.NOTIFY_GAP)
	eq(w.Run(), 1); eq(w.fires, 1)
	local revision = D.Revision()
	-- A minute later, the same roster.
	w.clock = w.clock + 60
	D.SetLocal(Ours(5))
	eq(w.fires, 1, "the same report: no DATA_CHANGED")
	eq(D.Revision(), revision, "nor a revision")
	eq(w.ns.rdb.guilds["Olympus II"].t, w.clock, "stored all the same, its time the new one")
	eq(#w.timers, 0, "nothing waits for it")
	-- One more online; so does a change deep in it (an officer gone offline), and a field the
	-- last one lacked: each a timer, nothing inside the scan.
	w.clock = w.clock + 60
	D.SetLocal(Ours(6))
	eq(w.fires, 1, "nothing inside the scan")
	eq(#w.timers, 1)
	assert(D.Revision() > revision, "a revision")
	w.Run(); eq(w.fires, 2)
	local r = Ours(6)
	r.officers[1].online = false
	D.SetLocal(r)
	eq(#w.timers, 1, "an officer's line changed")
	w.Run(); eq(w.fires, 3)
	r = Ours(6)
	r.officers[1].online = false
	r.users = 3
	D.SetLocal(r)
	eq(#w.timers, 1, "a field the last one lacked")
	w.Run(); eq(w.fires, 4)
	-- Reports of others waiting, then ours: the one timer tells both, once.
	eq(Receive(w, "Olympus Burst 3", "Burstvoice3-Realm"), true)
	eq(w.fires, 4); eq(#w.timers, 1)
	D.SetLocal(Ours(7))
	eq(w.fires, 4, "nothing inside the scan")
	eq(#w.timers, 1, "the timer already waiting")
	w.Run()
	eq(w.fires, 5, "one DATA_CHANGED for both")
	-- /oly reset (our row gone), or a row this session did not store (the saved one, another
	-- realm's store): the next report is news though it is the same.
	w.ns.rdb.guilds = {}
	D.SetLocal(Ours(7))
	eq(#w.timers, 1); w.Run(); eq(w.fires, 6)
	w.ns.rdb.guilds["Olympus II"] = Ours(7)
	D.SetLocal(Ours(7))
	eq(#w.timers, 1); w.Run(); eq(w.fires, 7)
	-- A /who of the player's: at once, as before; the timer waiting then tells nothing more.
	w.clock = w.clock + 60
	D.SetLocal(Ours(8))
	eq(#w.timers, 1)
	D.RecordSightings({ { guild = "Olympus Seen" } })
	eq(w.fires, 8, "the /who: at once")
	w.Run()
	eq(w.fires, 8, "the timer waiting had nothing left to tell")
end)

test("1.2.1 census news: a realm linked (another store) and /oly reset are the player's own: DATA_CHANGED at once, the census's revision with them", function()
	local D = ns.Data
	local fired = 0
	local keepPrint, keepJoin, keepName = print, ns.Comm.JoinChannel, ns.Comm.ChannelName
	local now = os.time()
	local R0 = { guilds = { ["Olympus Here"] = { total = 10, t = now } }, seen = {} }
	local db = { log = {}, realms = { Realm = R0, Other = { guilds = { ["Olympus There"] = { total = 20, t = now } } } } }
	local ok, err = pcall(function()
		print = function() end
		ns.Comm.JoinChannel = function() end
		ns.Comm.ChannelName = function() return "OlympusNet" end
		H.WithStub("Fire", function(name) if name == "DATA_CHANGED" then fired = fired + 1 end end, function()
			H.WithStub("db", db, function()
				H.WithStub("rdb", R0, function()
					H.WithStub("realm", "Realm", function()
						H.WithStub("group", "Realm", function()
							local before = D.Revision()
							eq(ns.LinkRealms("Realm", "Other"), true)
							eq(fired, 1, "the linked store: at once")
							eq(D.Revision(), before + 1)
							SlashCmdList.OLYMPUS("reset")
							eq(next(ns.rdb.guilds), nil, "the census cleared")
							eq(fired, 2, "/oly reset: at once")
							eq(D.Revision(), before + 2)
						end)
					end)
				end)
			end)
		end)
	end)
	print, ns.Comm.JoinChannel, ns.Comm.ChannelName = keepPrint, keepJoin, keepName
	if not ok then error(err, 0) end
end)

-- Roster.lua (and Data.lua) in a namespace of their own, the harness's 1000-member roster.
local function RosterWorld()
	local w = { fires = 0, timers = {}, events = {}, checks = 0, peers = 0, clock = 2000000000 }
	local rns = setmetatable({
		rdb = { guilds = {}, seen = {} },
		Who = { Listen = function() end },
		RegisterEvent = function(event, fn) w.events[event] = fn end,
		On = function() end,
		Fire = function(name) if name == "DATA_CHANGED" then w.fires = w.fires + 1 end end,
		After = function(seconds, where, fn) w.timers[#w.timers + 1] = { seconds = seconds, where = where, fn = fn } end,
		Now = function() return w.clock end,
		Members = { OnScan = function() end },
		Comm = { CheckMembership = function() w.checks = w.checks + 1 end, PeerCount = function() return w.peers end,
			MaybeBroadcast = function() end, CAPABILITY = 1 },
	}, { __index = ns })
	assert(loadfile(H.ADDON_DIR .. "Data.lua"))("Olympus", rns)
	assert(loadfile(H.ADDON_DIR .. "Roster.lua"))("Olympus", rns)
	w.ns, w.R = rns, rns.Roster
	function w.Timers(where)
		local out = {}
		for _, t in ipairs(w.timers) do if t.where == where then out[#out + 1] = t end end
		return out
	end
	return w
end

test("1.2.1 roster: a scan whose report came out as the last one fires no DATA_CHANGED; one that differs tells it through the census's timer, never inside the scan", function()
	local w = RosterWorld()
	local R = w.R
	local function Scan()
		w.timers = {}
		R.RequestScan(true); R.TryScan()
		eq(w.fires, w.told, "nothing fired inside the scan")
		local due = w.Timers("census changed")
		for _, t in ipairs(due) do eq(t.seconds, w.ns.Data.NOTIFY_GAP) end
		for _, t in ipairs(due) do t.fn() end
		w.told = w.fires
		return #due
	end
	w.told = 0
	eq(Scan(), 1, "the first scan: one timer")
	eq(w.fires, 1, "the first scan: told")
	assert(w.ns.rdb.guilds["Olympus II"], "our report stored")
	w.clock = w.clock + 60
	eq(Scan(), 0, "the same roster a minute later: nothing waits")
	eq(w.fires, 1, "no DATA_CHANGED")
	eq(w.ns.rdb.guilds["Olympus II"].t, w.clock, "the report stored again, its time new")
	-- A roster that changed (as a big guild's does most minutes: two guildmates' addons more).
	w.clock = w.clock + 60
	w.peers = 2
	eq(Scan(), 1, "news: one timer")
	eq(w.fires, 2, "told once, a frame after the scan")
	w.clock = w.clock + 60
	w.peers = 3
	eq(Scan(), 1); eq(w.fires, 3)
end)

test("1.2.1 roster: PLAYER_GUILD_UPDATE for another unit is no guild change of ours; a burst of ours waits for one timer", function()
	local w = RosterWorld()
	local update = assert(w.events.PLAYER_GUILD_UPDATE)
	for _, unit in ipairs({ "nameplate1", "nameplate12", "party1", "target", "mouseover" }) do update(unit) end
	eq(#w.Timers("guild changed"), 0, "another unit's guild: nothing")
	update("player"); update("player"); update(nil)
	local changed = w.Timers("guild changed")
	eq(#changed, 1, "one timer for ours")
	eq(changed[1].seconds, 2)
	changed[1].fn()
	eq(w.checks, 1, "membership checked")
	eq(w.fires, 1, "the map and the window told")
	-- Once it ran, the next change of ours has a timer of its own.
	update("player")
	eq(#w.Timers("guild changed"), 2)
end)

test("1.2.1 tickers: each starts after a random part of its period (a minute at most) and ticks a period after; its Cancel works before its start, inside a tick and after", function()
	local savedTimer, savedRandom = C_Timer, math.random
	local afters, tickers, rolls, calls = {}, {}, { 0.25, 0.5, 0.75, 0.5, 0.5, 0.5 }, {}
	local ok, err = pcall(function()
		C_Timer = {
			After = function(seconds, fn) afters[#afters + 1] = { seconds = seconds, fn = fn } end,
			NewTicker = function(seconds, fn)
				local k = { seconds = seconds, fn = fn }
				function k.Cancel(self) self.cancelled = true end
				tickers[#tickers + 1] = k
				return k
			end,
		}
		math.random = function(...)
			eq(select("#", ...), 0, "a fraction")
			return table.remove(rolls, 1)
		end
		local function Count(key) return function() calls[key] = (calls[key] or 0) + 1 end end
		local a = ns.Every(60, "test minute", Count("a"))
		local b = ns.Every(1.2, "test pump", Count("b"))
		local c = ns.Every(300, "test five minutes", Count("c"))
		eq(#tickers, 0, "none started on the frame that asked")
		eq(#afters, 3)
		eq(afters[1].seconds, 15, "a quarter of its minute")
		eq(afters[2].seconds, 0.6, "half of its 1.2 s")
		eq(afters[3].seconds, 45, "five minutes: a minute at most, three quarters of it")
		-- Cancelled before its start: it never starts.
		c:Cancel()
		eq(c:IsCancelled(), true)
		for _, t in ipairs(afters) do t.fn() end
		eq(#tickers, 2, "the other two started, the cancelled one never")
		eq(tickers[1].seconds, 60); eq(tickers[2].seconds, 1.2)
		eq(calls.a, nil, "its first tick a period after its start")
		tickers[1].fn(); tickers[1].fn()
		eq(calls.a, 2)
		-- Cancelled after: its ticker stops.
		eq(a:IsCancelled(), false)
		a:Cancel()
		eq(tickers[1].cancelled, true)
		tickers[1].fn()
		eq(calls.a, 2, "nothing after its Cancel")
		tickers[2].fn()
		eq(calls.b, 1, "the other goes on")
		eq(b:IsCancelled(), false)
		-- Cancelled from inside its own tick (Letters.lua's ticker does).
		local d
		d = ns.Every(10, "test once", function() calls.d = (calls.d or 0) + 1; d:Cancel() end)
		afters[#afters].fn()
		local k = tickers[#tickers]
		k.fn()
		eq(calls.d, 1); eq(k.cancelled, true)
		-- Two tickers asked on one frame start apart.
		local e = ns.Every(60, "test e", Count("e"))
		local f = ns.Every(30, "test f", Count("f"))
		eq(afters[#afters - 1].seconds, 30); eq(afters[#afters].seconds, 15)
		e:Cancel(); f:Cancel()
		eq(ns.EVERY_SPREAD, 60)
	end)
	C_Timer, math.random = savedTimer, savedRandom
	if not ok then error(err, 0) end
end)

test("1.2.1 window: a census change redraws it through RefreshSoon's timer, never inside the listener; one timer for many", function()
	H.WithUI(function()
		local listeners, timers = {}, {}
		local uns = setmetatable({}, { __index = H.ns })
		uns.On = function(name, fn)
			listeners[name] = listeners[name] or {}
			table.insert(listeners[name], fn)
		end
		uns.After = function(seconds, where, fn) timers[#timers + 1] = { seconds = seconds, where = where, fn = fn } end
		assert(loadfile(H.ADDON_DIR .. "UI.lua"))("Olympus", uns)
		local UI = uns.UI
		H.WithStub("UI", UI, function()
			UI.Toggle()
			local refresh, redraws = UI.Refresh, 0
			UI.Refresh = function(...) redraws = redraws + 1; return refresh(...) end
			timers = {}
			-- The last redraw long ago: the gap is over.
			UI.lastRedraw = -math.huge
			local changed = assert(listeners.DATA_CHANGED, "the window listens to the census")
			for _ = 1, 5 do
				for _, fn in ipairs(changed) do fn() end
			end
			eq(redraws, 0, "nothing drawn inside the listener")
			eq(#timers, 1, "one timer for the five")
			eq(timers[1].where, "ui redraw")
			eq(timers[1].seconds, 0, "at the next frame")
			timers[1].fn()
			eq(redraws, 1)
			-- Right after a redraw: its gap first, still one timer.
			timers = {}
			UI.lastRedraw = GetTime()
			UI.RefreshSoon(); UI.RefreshSoon()
			eq(#timers, 1)
			assert(timers[1].seconds > 0 and timers[1].seconds <= UI.REDRAW_MAX_GAP, "its gap: " .. timers[1].seconds)
			eq(redraws, 1)
			timers[1].fn()
			eq(redraws, 2)
			-- Closed: nothing waits.
			UI.Toggle()
			timers = {}
			UI.RefreshSoon()
			eq(#timers, 0)
		end)
	end)
end)

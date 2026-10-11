local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]perf%.lua$") or "./"

-- 1.2.1: the built-in profiler (Olympus/Perf.lua, /oly perf). Players' games stuttered with the
-- addon on while its memory and the CPU shown looked low; the profiler tells which of Olympus's
-- calls take the time, on their own computers. Each world here is Core.lua loaded into a table of
-- its own (its ns.SafeCall, ns.Fire, events and the /oly dispatcher), the profiler over it, a clock
-- that moves only when a call here moves it (w.now, milliseconds) and GetTime (w.t, seconds). The
-- game's next frame: w.Tick() runs the timers due (C_Timer.After), as the load's end does once.
-- before(c, Perf): what else the files register after Perf.lua, before INIT.

local GLOBALS = { "CreateFrame", "debugprofilestop", "GetTime", "C_Timer", "SLASH_OLYMPUS1", "SLASH_OLYMPUS2", "SLASH_OLYMPUSARENA1" }
local SLASH = { "OLYMPUS", "OLYMPUSARENA" }

local function World(db, fn, before)
	local w = { now = 0, t = 1000, frames = {}, printed = {}, errors = {}, copies = {}, timers = {} }
	local saved, slash = {}, {}
	for _, k in ipairs(GLOBALS) do saved[k] = rawget(_G, k) end
	for _, k in ipairs(SLASH) do slash[k] = SlashCmdList[k] end
	CreateFrame = function()
		local f = { scripts = {}, events = {} }
		function f:SetScript(kind, script) self.scripts[kind] = script end
		function f:RegisterEvent(event) self.events[event] = true end
		w.frames[#w.frames + 1] = f
		return setmetatable(f, { __index = function() return function() end end })
	end
	debugprofilestop = function() return w.now end
	GetTime = function() return w.t end
	C_Timer = { After = function(_, f) w.timers[#w.timers + 1] = f end, NewTicker = function() return { Cancel = function() end } end }
	function w.Tick()
		local due = w.timers
		w.timers = {}
		for _, f in ipairs(due) do f() end
	end
	local c = setmetatable({}, { __index = ns })
	c.L = setmetatable({}, { __index = ns.L })
	local ok, err = pcall(function()
		assert(loadfile(ROOT .. "Olympus/Core.lua"))("Olympus", c)
		for _, f in ipairs(w.frames) do if f.scripts.OnEvent then w.eventFrame = f end end
		assert(w.eventFrame, "Core.lua's event frame")
		c.Print = function(msg) w.printed[#w.printed + 1] = tostring(msg) end
		c.CaptureError = function(where, e) w.errors[#w.errors + 1] = tostring(where) .. ": " .. tostring(e) end
		c.UI = { ShowCopy = function(title, text, action, opts)
			w.copies[#w.copies + 1] = { title = title, text = text, action = action, opts = opts }
			return {}
		end }
		c.db = db
		w.core = c.SafeCall
		w.mark = #w.frames
		assert(loadfile(ROOT .. "Olympus/Locales/PerfText.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/Perf.lua"))("Olympus", c)
		if before then before(c, c.Perf) end
		c.Fire("INIT")
		w.Tick() -- (the load is over: the next frame)
		-- /oly as the login installs it with mouse and keyboard (Core.lua's own gate here).
		c.Gate.Install("slash")
		w.slash = SlashCmdList.OLYMPUS
		function w.Frame() local f = w.frames[w.mark + 1]; return f end
		function w.Draw() local f = w.Frame(); if f and f.scripts.OnUpdate then f.scripts.OnUpdate(f, 0.016) end end
		function w.Report() return w.copies[#w.copies] and w.copies[#w.copies].text or "" end
		fn(c.Perf, w, c, c.L)
	end)
	for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
	for _, k in ipairs(SLASH) do SlashCmdList[k] = slash[k] end
	if not ok then error(err, 0) end
end

local function KeyStarting(t, prefix)
	local found
	for k in pairs(t) do
		if k:sub(1, #prefix) == prefix and (#k == #prefix or k:sub(#prefix + 1, #prefix + 1) == " ") then
			assert(not found, "one key for " .. prefix)
			found = k
		end
	end
	return found
end

test("1.2.1 profiler: off it installs nothing (ns.SafeCall stays Core.lua's, no frame, nothing saved); /oly perf opens its report in the copy window; on then off puts everything back", function()
	World({}, function(P, w, c, L)
		eq(c.SafeCall, w.core, "Core.lua's own ns.SafeCall")
		eq(#w.frames, w.mark, "no frame made")
		eq(c.db.perf, nil, "nothing saved")
		eq(P.IsOn(), false)
		w.slash("perf")
		eq(#w.copies, 1, "/oly perf: the report in a copy window")
		eq(w.copies[1].title, L.PERF_TITLE)
		eq(w.copies[1].opts.key, "perf")
		assert(w.Report():find(L.PERF_STATE_NEVER, 1, true), w.Report())
		assert(w.Report():find(L.PERF_HELP, 1, true), "how to start it")
		eq(c.SafeCall, w.core, "the report installs nothing"); eq(c.db.perf, nil, "nor saves"); eq(#w.frames, w.mark)
		w.slash("perf on")
		eq(w.printed[#w.printed], L.PERF_ON)
		assert(c.SafeCall ~= w.core, "on: the calls are timed")
		eq(c.db.perf.on, true, "remembered for the /reload")
		assert(w.Frame() and w.Frame().scripts.OnUpdate, "its own frame counts the frames")
		w.slash("perf off")
		eq(w.printed[#w.printed], L.PERF_OFF)
		eq(c.SafeCall, w.core, "off: Core.lua's own ns.SafeCall again")
		eq(w.Frame().scripts.OnUpdate, nil, "and no OnUpdate")
		eq(c.db.perf.on, false)
		c.SafeCall("perf test off", function() w.now = w.now + 50 end)
		eq(c.db.perf.stats["perf test off"], nil, "a call while off is not measured")
		-- An update without a restart: the file is missing and /oly perf says to restart.
		c.Perf = nil
		w.slash("perf on")
		eq(w.printed[#w.printed], L.RESTART_NEEDED)
	end)
	local toc, at, n = assert(io.open(ROOT .. "Olympus/Olympus.toc")):read("*a"), {}, 0
	for line in toc:gmatch("[^\r\n]+") do n = n + 1; at[line] = n end
	assert(at["Perf.lua"] and at["Perf.lua"] > at["Diagnostics.lua"] and at["Perf.lua"] < at["Dialog.lua"], "Perf.lua loads early, after Core.lua's protected calls and the error capture")
	assert(at["Locales\\PerfText.lua"] and at["Locales\\PerfText.lua"] < at["Core.lua"], "its words with the other locales")
end)

test("1.2.1 profiler: on, each label and each listener has its own line, the slowest calls are kept with their times, frames of 30 ms or more are counted, and the report lists them", function()
	World({}, function(P, w, c, L)
		w.slash("perf on")
		w.Draw()
		c.On("PERF_PROBE", function() w.now = w.now + 2 end)
		c.On("PERF_PROBE", function() w.now = w.now + 45 end)
		c.RegisterEvent("PERF_PROBE_EVENT", function() w.now = w.now + 1 end)
		c.Fire("PERF_PROBE")
		w.eventFrame.scripts.OnEvent(w.eventFrame, "PERF_PROBE_EVENT")
		eq(c.SafeCall("perf test slow", function() w.now = w.now + 120 end), true, "the answer of Core.lua's SafeCall")
		w.Draw()
		local p = c.db.perf
		local k1, k2 = KeyStarting(p.stats, "callback PERF_PROBE #1"), KeyStarting(p.stats, "callback PERF_PROBE #2")
		assert(k1 and k2, "each listener of one callback on its own line")
		eq(p.stats[k1].total, 2); eq(p.stats[k2].total, 45); eq(p.stats[k2].n, 1); eq(p.stats[k2].max, 45)
		assert(k1:find("perf.lua:", 1, true), "its file and line where the game's Lua gives them: " .. k1)
		eq(p.events["callback PERF_PROBE"].total, 47, "the event's listeners together")
		eq(p.events["callback PERF_PROBE"].n, 2)
		local ke = KeyStarting(p.stats, "event PERF_PROBE_EVENT #1")
		assert(ke, "an event's handler too")
		eq(p.stats["perf test slow"].max, 120)
		eq(p.slow[1].label, "perf test slow"); eq(p.slow[1].ms, 120); eq(type(p.slow[1].at), "number")
		eq(p.slow[2].label, k2)
		eq(p.frames, 2); eq(p.heavy, 1, "one frame with 168 ms of Olympus's work")
		eq(p.worst[1].ms, 168); eq(p.worst[1].top, "perf test slow"); eq(p.worst[1].topMs, 120)
		c.SafeCall("perf test light", function() w.now = w.now + 10 end)
		w.Draw()
		eq(p.frames, 3); eq(p.heavy, 1, "a frame of 10 ms is not counted")
		-- A call inside a call: both have their line, the frame counts the outer one alone.
		c.SafeCall("perf outer", function() c.SafeCall("perf inner", function() w.now = w.now + 40 end) end)
		w.Draw()
		eq(p.stats["perf outer"].total, 40); eq(p.stats["perf inner"].total, 40)
		eq(p.heavy, 2); eq(p.worst[2].ms, 40, "40 ms in that frame, not 80")
		-- No source from the game's Lua: the listener's place, and its name where the namespace has it.
		c.PerfProbe = { Named = function() w.now = w.now + 1 end }
		c.On("PERF_PLAIN", function() w.now = w.now + 1 end)
		c.On("PERF_PLAIN", c.PerfProbe.Named)
		local savedDebug = rawget(_G, "debug")
		rawset(_G, "debug", nil)
		local okFire, errFire = pcall(c.Fire, "PERF_PLAIN")
		rawset(_G, "debug", savedDebug)
		assert(okFire, errFire)
		assert(p.stats["callback PERF_PLAIN #1"], "no source: its place in the order")
		assert(p.stats["callback PERF_PLAIN #2 PerfProbe.Named"], "registered by name: that name")
		-- The report: 2 min 05 s measured.
		w.t = w.t + 125
		w.slash("perf")
		local text = w.Report()
		for _, want in ipairs({ L.PERF_SLOW_ROW:format("120.0", date("%H:%M:%S", p.slow[1].at), "perf test slow"), k1, k2, ke, L.PERF_INPUT_KEYS,
			L.PERF_FRAMES:format(30, "2", "4"), L.PERF_STATE_ON:format(L.PERF_DURATION_M:format(2, 5), date("%Y-%m-%d %H:%M", p.since)),
			L.PERF_TOTAL_ROW:format(k2, "1", "45", "45.00", "45.0"), L.PERF_TOTAL_ROW:format("callback PERF_PROBE", "2", "47", "23.50", "45.0"),
			L.PERF_FRAME_ROW:format("168.0", date("%H:%M:%S", p.worst[1].at), "perf test slow", "120.0") }) do
			assert(text:find(want, 1, true), "the report lists: " .. want .. "\n" .. text)
		end
		eq(w.copies[#w.copies].action.label, L.PERF_REFRESH)
		eq(w.copies[#w.copies].opts.second.label, L.PERF_RESET_BTN)
		eq(#w.errors, 0, table.concat(w.errors, "; "))
	end)
end)

test("1.2.1 profiler: /oly perf reset clears what it measured; on stays on through a /reload, with what it measured; off stays off", function()
	local db = {}
	World(db, function(P, w, c, L)
		w.slash("perf on")
		c.SafeCall("perf test slow", function() w.now = w.now + 120 end)
		w.Draw()
		w.t = w.t + 30
		w.eventFrame.scripts.OnEvent(w.eventFrame, "PLAYER_LOGOUT") -- (the /reload)
		eq(db.perf.measured, 30, "the run's time kept at the logout")
	end)
	World(db, function(P, w, c, L)
		eq(P.IsOn(), true, "on again after the /reload")
		assert(c.SafeCall ~= w.core)
		assert(w.Frame().scripts.OnUpdate)
		eq(db.perf.stats["perf test slow"].max, 120, "what it measured is kept")
		eq(db.perf.heavy, 1)
		w.t = w.t + 15
		eq(P.Elapsed(), 45)
		w.slash("perf reset")
		eq(w.printed[#w.printed], L.PERF_RESET_DONE)
		for k in pairs(db.perf.stats) do eq(k, "slash perf", "cleared but the command itself") end
		for _, e in ipairs(db.perf.slow) do eq(e.label, "slash perf") end
		eq(db.perf.frames, 0); eq(db.perf.heavy, 0); eq(#db.perf.worst, 0); eq(P.Elapsed(), 0)
		eq(P.IsOn(), true, "still measuring")
		w.slash("perf")
		assert(not w.Report():find("perf test slow", 1, true), w.Report())
		w.slash("perf off")
		eq(c.SafeCall, w.core); eq(db.perf.on, false)
	end)
	World(db, function(P, w, c)
		eq(P.IsOn(), false, "off after the /reload")
		eq(c.SafeCall, w.core); eq(#w.frames, w.mark, "no frame")
	end)
end)

test("1.2.1 profiler: the 40 slowest calls kept in order, a typed command's words and menu lines never kept, labels bounded, and a fault of its own breaks no call", function()
	World({}, function(P, w, c)
		w.slash("perf on")
		local p = c.db.perf
		for i = 1, 60 do c.SafeCall("perf many " .. i % 3, function() w.now = w.now + i end) end
		eq(#p.slow, 40); eq(p.slow[1].ms, 60); eq(p.slow[40].ms, 21)
		for i = 2, 40 do assert(p.slow[i - 1].ms >= p.slow[i].ms, "slowest first") end
		eq(p.stats["perf many 0"].n, 20); eq(p.stats["perf many 0"].max, 60)
		c.SafeCall("slash key Sealedword", function() end)
		c.SafeCall("slash   Block Somename-Realm", function() end)
		c.SafeCall("player menu Whisper Somename", function() end)
		assert(p.stats["slash key"] and p.stats["slash block"] and p.stats["player menu"])
		for k in pairs(p.stats) do assert(not k:find("Sealedword", 1, true) and not k:find("Somename", 1, true), k) end
		for _, e in ipairs(p.slow) do assert(not e.label:find("Somename", 1, true)) end
		local was = P.MAX_KEYS
		P.MAX_KEYS = p.keys
		c.SafeCall("perf beyond", function() end)
		P.MAX_KEYS = was
		eq(p.stats["perf beyond"], nil, "no label past the bound"); assert(p.stats["(other)"], "counted as (other)")
		-- A damaged row (a saved file edited by hand): the call is made, its answer kept, the profiler stops.
		p.stats["perf broken"] = { n = "x", total = 0, max = 0 }
		local ran = false
		eq(c.SafeCall("perf broken", function() ran = true end), true)
		eq(ran, true)
		eq(P.IsOn(), false, "the profiler stops"); eq(c.SafeCall, w.core)
		assert(w.errors[#w.errors] and w.errors[#w.errors]:find("perf record", 1, true), "and says why")
		-- Started again over that saved data: the bad row is dropped.
		w.slash("perf on")
		eq(p.stats["perf broken"], nil)
		eq(P.IsOn(), true)
	end)
end)

-- The gamepad pass's client (tests/gamepad.lua: Forever's UI modelled, every reach of the game's
-- UI recorded): the profiler on from the saved variables, in a whole session with the gamepad UI
-- on, then with mouse and keyboard and its report opened by /oly perf. It touches none of the
-- game's frames (its frame is its own) and nothing it does is refused.
-- The saved variables of a player who answered the login's questions, with the profiler on.
local function Saved()
	return { addonChat = true, royalInspection = true, rollCall = true, layerHelp = true, treasurerShares = true,
		chatWarned = { A = true, C = true, L = true }, shareLocation = true, perf = { on = true } }
end

test("1.2.1 profiler in the gamepad pass's client: on from the saved variables it measures a whole session, gamepad UI on or not, and reaches nothing of the game's UI", function()
	local GPM = assert(loadfile(ROOT .. "tests/gamepad.lua"))("--debug")
	for _, pad in ipairs({ true, false }) do
		local what = pad and "the gamepad UI" or "mouse and keyboard"
		local C, gns = GPM.Session(pad, { saved = Saved() })
		eq(gns.Perf.IsOn(), true, what .. ": on again from the saved word")
		GPM.WindowFlow(C)
		C.Advance(90)
		local p = gns.db.perf
		assert(next(p.stats), what .. ": the session's calls measured")
		assert(p.frames > 0, what .. ": its frame counted the frames")
		assert(gns.Perf.ReportText():find(pad and gns.L.PERF_INPUT_PAD or gns.L.PERF_INPUT_KEYS, 1, true), what .. ": the report says which")
		if not pad then
			eq(GPM.TypeSlash(C, "/oly perf"), true, "/oly perf typed")
			local f = gns.UI.CopyFrame("perf")
			assert(f and f:IsShown(), "the report in Olympus's copy window")
			assert(f.text:find(gns.L.PERF_TITLE, 1, true), "its text")
			eq(GPM.TypeSlash(C, "/oly perf off"), true)
			eq(gns.Perf.IsOn(), false)
		end
		GPM.Check(C.ledger, what)
		local errs = GPM.Errors(C)
		eq(#errs, 0, what .. ": " .. tostring(errs[1]))
	end
end)

-- (A player's report: the game's Lua has no debug library, so a listener's line reads "callback
-- DATA_CHANGED #18" alone, and only its place says which. Started from the saved word inside INIT,
-- the 1.2.1 draft numbered the listeners of INIT after its own, and the ADDON_LOADED handlers after
-- Core.lua's, from #1.) The model of the client with the debug library in its Lua, so each line has
-- the file and line the profiler found: every listener's line of a whole session, started from the
-- saved word, is the one scripts/perf-listeners.lua prints for its #n.
test("1.2.1 profiler: each listener's #n is its place in the order of registration, the one scripts/perf-listeners.lua names, through a whole session started from the saved word", function()
	local Map = assert(loadfile(ROOT .. "scripts/perf-listeners.lua"))("--module")
	local GPM = assert(loadfile(ROOT .. "tests/gamepad.lua"))("--debug")
	local C, gns = Map.Session(false, Saved())
	eq(gns.Perf.IsOn(), true, "on again from the saved word")
	GPM.WindowFlow(C)
	C.Advance(90)
	gns.Fire("DATA_CHANGED")
	C.Fire("PLAYER_ENTERING_WORLD", false, true)
	C.Fire("ZONE_CHANGED_NEW_AREA")
	C.Fire("GUILD_ROSTER_UPDATE")
	local map = Map.Map(gns)
	local stats, checked, labels = gns.db.perf.stats, 0, {}
	for key in pairs(stats) do
		if key:find("^callback ") or key:find("^event ") then
			local label, n, site = key:match("^(.-) #(%d+) (.+)$")
			assert(label, "a listener's line, its #n and its file and line: " .. key)
			local row = map[label] and map[label][tonumber(n)]
			assert(row, key .. ": the script lists no such listener")
			eq(site, row.site, key)
			checked, labels[label] = checked + 1, true
		end
	end
	assert(checked >= 30 and labels["callback DATA_CHANGED"], "the session's listeners: " .. checked)
	for k in pairs(stats) do assert(not k:find("^callback INIT ") and not k:find("^event ADDON_LOADED "), "the load itself is not measured: " .. k) end
	-- Each DATA_CHANGED listener on its own line, the script's line for its #n.
	local rows = map["callback DATA_CHANGED"]
	assert(#rows >= 10, "the census's listeners")
	for n, row in ipairs(rows) do
		assert(stats["callback DATA_CHANGED #" .. n .. " " .. row.site], "callback DATA_CHANGED #" .. n .. " " .. row.site)
	end
	local lines = Map.Lines(map, { "data_changed" })
	eq(#lines, #rows, "a word keeps the labels holding it")
	eq(lines[1], "callback DATA_CHANGED #1  " .. rows[1].site)
	eq(lines[#rows], ("callback DATA_CHANGED #%d  %s"):format(#rows, rows[#rows].site))
	assert(#Map.Lines(map) > #rows, "no word: every label")
	eq(#GPM.Errors(C), 0, tostring(GPM.Errors(C)[1]))
end)

test("1.2.1 profiler: after a /reload it starts again on the frame after the load, never inside INIT, so no listener is numbered out of its order", function()
	local during
	World({ perf = { on = true } }, function(P, w, c)
		eq(during, false, "not measuring inside INIT")
		eq(P.IsOn(), true, "measuring from the frame after")
		local p = c.db.perf
		for k in pairs(p.stats) do assert(not k:find("^callback INIT"), "INIT is not measured: " .. k) end
		c.On("PERF_ORDER", function() w.now = w.now + 1 end)
		c.On("PERF_ORDER", function() w.now = w.now + 2 end)
		c.Fire("PERF_ORDER")
		local k1, k2 = KeyStarting(p.stats, "callback PERF_ORDER #1"), KeyStarting(p.stats, "callback PERF_ORDER #2")
		eq(p.stats[k1].total, 1); eq(p.stats[k2].total, 2)
		-- Cleared, each listener keeps its #n (its place).
		w.slash("perf reset")
		c.Fire("PERF_ORDER")
		eq(p.stats[k1].total, 1); eq(p.stats[k2].total, 2)
	end, function(c, P)
		c.On("INIT", function() during = P.IsOn() end)
		c.On("INIT", function() end)
	end)
	-- Off before the frame after the load (the saved word changed in between): it stays off.
	local db = { perf = { on = true } }
	World(db, function(P, w, c)
		eq(P.IsOn(), false)
		eq(c.SafeCall, w.core); eq(#w.frames, w.mark, "no frame")
	end, function(c, P)
		c.On("INIT", function() c.db.perf.on = false end)
	end)
	eq(db.perf.on, false)
end)

test("1.2.1 profiler: a label keeps nothing that changes from call to call (a name, a nonce, an id): a timer's key with a player's name is one line, no name is saved, and every listener has its own line once the labels are full", function()
	World({}, function(P, w, c)
		w.slash("perf on")
		local p = c.db.perf
		for i = 1, 1000 do c.SafeCall("arena after match:offer:q" .. i .. "|somename-realm", function() w.now = w.now + 1 end) end
		eq(p.stats["arena after match:offer"].n, 1000, "one line")
		for raw, kept in pairs({
			["arena after witness 3fa2c:2"] = "arena after witness",
			["arena after wallet auto Somebank-Realm"] = "arena after wallet auto",
			["watch sync 1760000123 4"] = "watch sync",
			["after combat room:w:somename-realm"] = "after combat room",
			["arena after ~k:123456|somename"] = "arena after ~k:#",
			["tabards v2"] = "tabards v2",
			["button |cffffd100Somename|r"] = "button",
			["arena every fights"] = "arena every fights",
		}) do
			c.SafeCall(raw, function() w.now = w.now + 1 end)
			c.SafeCall(raw, function() w.now = w.now + 1 end)
			eq(p.stats[kept] and p.stats[kept].n, 2, raw .. " is kept as " .. kept)
		end
		-- A long label: LABEL_MAX bytes at most, cut between two characters (é's 2 bytes are its 80th and 81st).
		c.SafeCall(("x"):rep(79) .. "é" .. ("y"):rep(20), function() end)
		eq(p.stats[("x"):rep(79)] and p.stats[("x"):rep(79)].n, 1, "cut before the é")
		local function NoName(s) return not s:find("omename", 1, true) and not s:find("omebank", 1, true) end
		for k in pairs(p.stats) do assert(NoName(k), "a saved label: " .. k) end
		for k in pairs(p.events) do assert(NoName(k), k) end
		for _, e in ipairs(p.slow) do assert(NoName(e.label), e.label) end
		eq(p.keys < 20, true, "a few labels: " .. p.keys)
		-- The labels full: a label never seen is "(other)", a listener's line is its own.
		local was = P.MAX_KEYS
		P.MAX_KEYS = p.keys
		c.SafeCall("perf beyond", function() end)
		c.On("PERF_LATE", function() end)
		c.On("PERF_LATE", function() end)
		c.Fire("PERF_LATE")
		P.MAX_KEYS = was
		eq(p.stats["perf beyond"], nil); assert(p.stats["(other)"])
		assert(KeyStarting(p.stats, "callback PERF_LATE #1") and KeyStarting(p.stats, "callback PERF_LATE #2"), "each listener on its own line")
		-- Labels as called past MAX_BASES: not remembered, kept the same; a listener's #n kept.
		local wasB = P.MAX_BASES
		P.MAX_BASES = 0
		c.SafeCall("perf unremembered", function() end)
		c.SafeCall("perf unremembered", function() end)
		c.On("PERF_LATER", function() end)
		c.Fire("PERF_LATER"); c.Fire("PERF_LATER")
		P.MAX_BASES = wasB
		eq(p.stats["perf unremembered"].n, 2)
		eq(p.stats[KeyStarting(p.stats, "callback PERF_LATER #1")].n, 2, "its #n the same at each call")
		eq(#w.errors, 0, table.concat(w.errors, "; "))
	end)
end)

test("1.2.1 profiler: /oly help lists /oly perf, so does the README's table of commands, and each of its words has its pt-BR", function()
	World({}, function(P, w, c, L)
		local printed, savedPrint = {}, print
		print = function(s) printed[#printed + 1] = tostring(s) end
		local ok, err = pcall(w.slash, "no-such-command")
		print = savedPrint
		assert(ok, err)
		assert(rawget(c.L, "HELP_CMD_PERF"), "its line, from PerfText.lua")
		assert(table.concat(printed, "\n"):find(L.HELP_CMD_PERF, 1, true), "in /oly help")
	end)
	local readme = assert(io.open(ROOT .. "README.md")):read("*a")
	assert(readme:find("\n| `/oly perf`", 1, true), "the README's commands")
	-- Each word set in English and again for pt-BR, with the same format codes.
	local function Load(locale)
		local store, sets = {}, {}
		local L = setmetatable({}, { __index = store, __newindex = function(_, k, v) sets[k] = (sets[k] or 0) + 1; store[k] = v end })
		local saved = GetLocale
		GetLocale = function() return locale end
		local ok, err = pcall(function() assert(loadfile(ROOT .. "Olympus/Locales/PerfText.lua"))("Olympus", { L = L }) end)
		GetLocale = saved
		assert(ok, err)
		return store, sets
	end
	local en = Load("enUS")
	local pt, sets = Load("ptBR")
	local function Codes(s) local out = {} for code in s:gmatch("%%[%d%.%-]*%a") do out[#out + 1] = code end return table.concat(out, " ") end
	local n = 0
	for k, v in pairs(en) do
		n = n + 1
		eq(sets[k], 2, "pt-BR: " .. k)
		eq(Codes(pt[k]), Codes(v), "pt-BR codes: " .. k)
	end
	assert(n >= 25 and en.HELP_CMD_PERF and pt.HELP_CMD_PERF ~= en.HELP_CMD_PERF)
end)

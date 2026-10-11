local ADDON, ns = ...
local L = ns.L

-- 1.2.1: the built-in profiler, for the players whose game stutters with Olympus on (the
-- owner's ask: "O addon nao pode prejudicar a experiencia do jogo"). /oly perf on starts it and it
-- stays on through /reload (ns.db.perf.on) until /oly perf off; /oly perf reset clears what it
-- measured; /oly perf alone opens the report in a copy window (a chat line can't be copied).
--
-- While off it costs nothing: no wrapper, no OnUpdate, nothing saved; ns.SafeCall is Core.lua's
-- own. While on, ns.SafeCall is timed (debugprofilestop) by its label: events, listeners, timers,
-- commands and clicks all go through it. A listener's label ("callback DATA_CHANGED", "event
-- CHAT_MSG_ADDON") gets the listener's place in the order it was registered (#n), with its file
-- and line where the game's Lua tells them (debug.getinfo) or its name in the namespace
-- (ChatRooms.RefreshAuthority), so each DATA_CHANGED listener has its own line. Where the client's
-- Lua has no debug library (the gamepad pass's model of Forever has none), #n alone names most:
-- the order is the TOC's and the files', the same on every client of one version, and
-- scripts/perf-listeners.lua prints each #n's file and line for the checkout. (So the profiler is
-- never started inside a dispatch, whose later listeners would be numbered from #1: after a
-- /reload it starts on the frame after the load.) A label is kept without what changes from call
-- to call (Kept: a typed word, a name, an id), so it takes one line. An
-- OnUpdate of its own frame (never one of the game's) adds up the top-level calls of each drawn
-- frame and counts the frames where Olympus took 30 ms or more. Kept: each label's calls, total
-- and slowest; the 40 slowest calls with their times; the 10 worst frames; the time measured.
-- The numbers are saved with the rest (ns.db.perf), so a /reload keeps them.

local Perf = {}
ns.Perf = Perf

Perf.FRAME_MS = 30   -- a frame with this much of Olympus's work is counted
Perf.SLOW_KEEP = 40  -- the slowest calls kept
Perf.WORST_KEEP = 10 -- the worst frames kept
Perf.MAX_KEYS = 1000 -- labels kept; any further one is counted as "(other)" (a listener's never is)
Perf.MAX_BASES = 2000 -- labels as called, remembered in this session (a listener's always are)
Perf.LABEL_MAX = 80  -- a kept label's length at most, in bytes
-- Labels whose rest is data (Kept): a name, a nonce, an id after these words.
Perf.DATA_AFTER = { "arena after match:offer", "arena after witness", "arena after wallet auto", "watch sync", "after combat room" }
Perf.MAX_LISTENERS = 200 -- listeners named one by one under one label
Perf.TOP = 25        -- the report's "most time in all" lines
Perf.TOP_EVENTS = 12 -- the report's "each event's listeners together" lines

local on = false        -- measuring now
local installed = false -- our wrapper is in ns.SafeCall's chain
local inner             -- the ns.SafeCall ours calls (Core.lua's, unless someone wrapped it first)
local data              -- ns.db.perf while on
local clock             -- debugprofilestop
local frame             -- our own frame, made at the first start
local logoutHooked = false
local runStart = 0      -- GetTime() at this run's start (or the last fold)
local depth = 0         -- protected calls running now (0: a top-level call)
local frameSum, frameTopMs, frameTop = 0, 0, nil
local slowMin, worstMin = -1, -1

local function Now() return GetTime() end

-- The game's Lua (if it has its debug library): a function's file and line.
local function Source(fn)
	local dbg = rawget(_G, "debug")
	local getinfo = type(dbg) == "table" and dbg.getinfo
	if type(getinfo) ~= "function" or type(fn) ~= "function" then return nil end
	local ok, info = pcall(getinfo, fn, "S")
	if not ok or type(info) ~= "table" or type(info.short_src) ~= "string" or info.what == "C" then return nil end
	local src = info.short_src:gsub('"%]$', "")
	return (src:match("([^/\\]+)$") or src) .. ":" .. tostring(info.linedefined or "?")
end

-- Functions found in the namespace (ns.X.Y): a listener registered by name keeps that name.
-- Built at the first listener met without a source, once per start.
local nsNames
local function NsName(fn)
	if not nsNames then
		nsNames = setmetatable({}, { __mode = "k" })
		pcall(function()
			for k, v in pairs(ns) do
				if type(k) == "string" and type(v) == "function" then
					nsNames[v] = nsNames[v] or k
				elseif type(k) == "string" and type(v) == "table" and k:find("^%u") and k ~= "L" then
					for k2, v2 in pairs(v) do
						if type(k2) == "string" and type(v2) == "function" and not nsNames[v2] then nsNames[v2] = k .. "." .. k2 end
					end
				end
			end
		end)
	end
	return nsNames[fn]
end

-- A label as kept: nothing in it that changes from call to call, so one label is one line and
-- one saved slot, and no name is saved. A typed command's words never are (a key, a name: "slash
-- key ..." is "slash key"), nor a menu line's (it can hold a player's name), nor what follows the
-- words of DATA_AFTER (a timer's key with a player's name, a nonce, a fight's id: "arena after
-- match:offer:<id>|<name>" is "arena after match:offer"); anywhere else what follows a "|" is
-- dropped and a number of two digits or more is "#". An event's or a callback's label is its name
-- (the code's own) and stays whole. The same answer for a label already kept.
local function Kept(s)
	local cmd = s:match("^slash%s+(%S*)")
	if cmd then return "slash " .. cmd:lower() end
	if s:find("^player menu ") then return "player menu" end
	for _, p in ipairs(Perf.DATA_AFTER) do
		if s:sub(1, #p) == p and (#s == #p or s:sub(#p + 1, #p + 1):find("[%s:|]")) then return p end
	end
	s = s:gsub("|.*$", ""):gsub("%d%d+", "#"):gsub("%s+$", "")
	if #s > Perf.LABEL_MAX then
		-- (Cut between two characters: a byte 0x80-0xBF continues one.)
		local cut = Perf.LABEL_MAX
		while cut > 0 and (s:byte(cut + 1) or 0) >= 0x80 and s:byte(cut + 1) < 0xC0 do cut = cut - 1 end
		s = s:sub(1, cut)
	end
	return s
end

-- [kept label] = { label, listener?, its listeners' names by function, how many }. A label as
-- called finds its own when it is kept as called; one with data in it is kept anew (Kept) at each
-- call. Bounded: past MAX_BASES a new label that is no listener's is kept anew at each call, never
-- remembered. A listener's is always remembered: its #n live here, for the whole session.
local bases, nBases = {}, 0
local function Base(where)
	local b = bases[where]
	if b then return b end
	local s = tostring(where)
	local listener = (s:find("^callback ") or s:find("^event ")) and true or false
	local kept = listener and s or Kept(s)
	b = bases[kept]
	if b then return b end
	b = { label = kept, listener = listener, count = 0 }
	if listener or nBases < Perf.MAX_BASES then
		bases[kept] = b
		nBases = nBases + 1
	end
	return b
end

local function ListenerKey(b, fn)
	local byFn = b.byFn
	if not byFn then
		byFn = setmetatable({}, { __mode = "k" })
		b.byFn = byFn
	end
	local key = byFn[fn]
	if key then return key end
	if b.count >= Perf.MAX_LISTENERS then return b.label .. " #+" end
	b.count = b.count + 1
	local named = Source(fn) or NsName(fn)
	key = b.label .. " #" .. b.count .. (named and (" " .. named) or "")
	byFn[fn] = key
	return key
end

local function Bump(t, key, dt)
	local s = t[key]
	if not s then
		s = { n = 0, total = 0, max = 0, at = 0 }
		t[key] = s
	end
	s.n = s.n + 1
	s.total = s.total + dt
	if dt > s.max then s.max, s.at = dt, time() end
end

-- Into a list kept slowest first, `keep` long: entry where its ms puts it.
local function Keep(list, keep, entry)
	local i = #list
	if i >= keep then
		list[i] = nil
		i = i - 1
	end
	while i >= 1 and list[i].ms < entry.ms do
		list[i + 1] = list[i]
		i = i - 1
	end
	list[i + 1] = entry
	return #list >= keep and list[#list].ms or -1
end

local function Record(where, fn, dt)
	local b = Base(where)
	local key = b.listener and ListenerKey(b, fn) or b.label
	local stats = data.stats
	if not stats[key] then
		-- (A listener's line always: a label, kept, is the code's own, so these are bounded.)
		if data.keys >= Perf.MAX_KEYS and not b.listener then
			key = "(other)"
		else
			data.keys = data.keys + 1
		end
	end
	Bump(stats, key, dt)
	if b.listener then Bump(data.events, b.label, dt) end
	if dt > slowMin then slowMin = Keep(data.slow, Perf.SLOW_KEEP, { label = key, ms = dt, at = time() }) end
	if depth == 0 then
		frameSum = frameSum + dt
		if dt > frameTopMs then frameTopMs, frameTop = dt, key end
	end
end

-- ns.SafeCall while on: Core.lua's (or what it was) between two reads of the clock.
local function Timed(where, fn, ...)
	if not on then return inner(where, fn, ...) end
	depth = depth + 1
	local t0 = clock()
	local ok = inner(where, fn, ...)
	local dt = clock() - t0
	depth = depth - 1
	if on then
		local fine, err = pcall(Record, where, fn, dt)
		if not fine then
			-- (A fault of the profiler's never breaks the call it measured: it stops, and says why.)
			Perf.Stop()
			if ns.CaptureError then ns.CaptureError("perf record", err) end
		end
	end
	return ok
end

-- One drawn frame done (our frame's OnUpdate): what Olympus's top-level calls took in it.
local function FrameDone()
	if not on then return end
	data.frames = data.frames + 1
	local sum = frameSum
	if sum >= Perf.FRAME_MS then
		data.heavy = data.heavy + 1
		if sum > worstMin then
			worstMin = Keep(data.worst, Perf.WORST_KEEP, { ms = sum, at = time(), top = frameTop, topMs = frameTopMs })
		end
	end
	frameSum, frameTopMs, frameTop = 0, 0, nil
end

-- This run's time into what was measured (a stop, a logout or /reload).
local function Fold()
	if not data then return end
	local t = Now()
	data.measured = data.measured + math.max(0, t - runStart)
	runStart = t
end

local function Num(v) return type(v) == "number" and v == v and v or 0 end

-- A saved stats table, checked in place (a damaged saved file loses its bad rows): its rows.
local function CleanStats(t)
	local bad, n = nil, 0
	for k, s in pairs(t) do
		if type(k) == "string" and type(s) == "table" and type(s.n) == "number" and type(s.total) == "number" and type(s.max) == "number" then
			if type(s.at) ~= "number" then s.at = 0 end
			n = n + 1
		else
			bad = bad or {}
			bad[#bad + 1] = k
		end
	end
	if bad then for _, k in ipairs(bad) do t[k] = nil end end
	return n
end

-- A saved list, slowest first and `keep` long: itself when it is one, else one made of its good rows.
local function CleanList(t, keep, frames)
	local fine = #t <= keep
	for i, e in ipairs(t) do
		if not (type(e) == "table" and type(e.ms) == "number" and (frames or type(e.label) == "string")) or (i > 1 and t[i - 1].ms < e.ms) then
			fine = false
			break
		end
	end
	if fine then return t end
	local out = {}
	for _, e in ipairs(t) do
		if type(e) == "table" and type(e.ms) == "number" and (frames or type(e.label) == "string") then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a.ms > b.ms end)
	for i = #out, keep + 1, -1 do out[i] = nil end
	return out
end

local function Table(v) return type(v) == "table" and v or {} end

-- ns.db.perf, made (create) and checked.
local function Data(create)
	local db = ns.db
	if type(db) ~= "table" then return nil end
	local p = db.perf
	if type(p) ~= "table" then
		if not create then return nil end
		p = {}
		db.perf = p
	end
	p.stats, p.events = Table(p.stats), Table(p.events)
	p.keys = CleanStats(p.stats)
	CleanStats(p.events)
	p.slow = CleanList(Table(p.slow), Perf.SLOW_KEEP)
	p.worst = CleanList(Table(p.worst), Perf.WORST_KEEP, true)
	p.frames, p.heavy, p.measured = Num(p.frames), Num(p.heavy), Num(p.measured)
	if type(p.since) ~= "number" then p.since = time() end
	return p
end

function Perf.IsOn() return on end

-- Starts measuring (false, why when it can't).
function Perf.Start()
	if on then return true end
	local clk = rawget(_G, "debugprofilestop")
	if type(clk) ~= "function" then return false, "clock" end
	local p = Data(true)
	if not p then return false, "db" end
	clock, data = clk, p
	p.on = true
	runStart = Now()
	slowMin = #p.slow >= Perf.SLOW_KEEP and p.slow[#p.slow].ms or -1
	worstMin = #p.worst >= Perf.WORST_KEEP and p.worst[#p.worst].ms or -1
	depth, frameSum, frameTopMs, frameTop = 0, 0, 0, nil
	nsNames = nil
	if not installed then
		inner = ns.SafeCall
		ns.SafeCall = Timed
		installed = true
	end
	if not frame then frame = CreateFrame("Frame") end
	frame:SetScript("OnUpdate", FrameDone)
	if not logoutHooked then
		logoutHooked = true
		ns.RegisterEvent("PLAYER_LOGOUT", function() if on then Fold() end end)
	end
	on = true
	return true
end

-- Stops measuring: ns.SafeCall is what it was (unless something wrapped it after us: then ours
-- stays in its chain and only passes the calls on), the OnUpdate is gone. What was measured stays.
function Perf.Stop()
	local p = ns.db and type(ns.db.perf) == "table" and ns.db.perf
	if p then p.on = false end
	if not on then return end
	Fold()
	on = false
	-- (inner is kept: a caller that took Timed while it was ns.SafeCall still gets its call made.)
	if installed and ns.SafeCall == Timed then
		ns.SafeCall = inner
		installed = false
	end
	if frame then frame:SetScript("OnUpdate", nil) end
	frameSum, frameTopMs, frameTop = 0, 0, nil
end

-- Clears what was measured; measuring goes on if it was on.
function Perf.Reset()
	local p = ns.db and type(ns.db.perf) == "table" and ns.db.perf
	if not p then return end
	p.stats, p.events, p.slow, p.worst = {}, {}, {}, {}
	p.keys, p.frames, p.heavy, p.measured = 0, 0, 0, 0
	p.since = time()
	runStart = Now()
	slowMin, worstMin = -1, -1
	frameSum, frameTopMs, frameTop = 0, 0, nil
	-- (Each listener keeps its #n: it is its place in the order of registration, for the session.)
end

-- Seconds measured, this run's included.
function Perf.Elapsed()
	local p = ns.db and type(ns.db.perf) == "table" and ns.db.perf
	local t = p and Num(p.measured) or 0
	if on then t = t + math.max(0, Now() - runStart) end
	return t
end

local function Duration(sec)
	sec = math.floor(math.max(0, tonumber(sec) or 0))
	if sec >= 3600 then return L.PERF_DURATION_H:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
	if sec >= 60 then return L.PERF_DURATION_M:format(math.floor(sec / 60), sec % 60) end
	return L.PERF_DURATION_S:format(sec)
end

local function Ms(v) return ("%.1f"):format(tonumber(v) or 0) end
local function Count(v) return ns.FormatNumber and ns.FormatNumber(v) or tostring(math.floor(tonumber(v) or 0)) end
local function At(t) return (type(t) == "number" and t > 0) and date("%H:%M:%S", t) or "-" end

local function Sorted(t, field, n)
	local rows = {}
	for k, s in pairs(t) do rows[#rows + 1] = { key = k, s = s } end
	table.sort(rows, function(a, b)
		if a.s[field] ~= b.s[field] then return a.s[field] > b.s[field] end
		return a.key < b.key
	end)
	for i = #rows, n + 1, -1 do rows[i] = nil end
	return rows
end

local function TotalRow(key, s)
	local n = math.max(1, s.n)
	return "  " .. L.PERF_TOTAL_ROW:format(key, Count(s.n), Count(s.total + 0.5), ("%.2f"):format(s.total / n), Ms(s.max))
end

-- The report, as the copy window shows it.
function Perf.ReportText()
	local out = {}
	local function Add(s) out[#out + 1] = s end
	local game = "?"
	if GetBuildInfo then
		local ok, version, build, _, interface = pcall(GetBuildInfo)
		if ok then game = ("%s.%s (%s)"):format(tostring(version), tostring(build), tostring(interface)) end
	end
	Add(L.PERF_TITLE .. " - " .. L.PERF_VERSION:format(tostring(ns.VERSION), game))
	-- (Which session scripts/perf-listeners.lua is to model: a few listeners are registered by mode.)
	if ns.GamepadUI then Add(ns.GamepadUI() and L.PERF_INPUT_PAD or L.PERF_INPUT_KEYS) end
	local p = ns.db and type(ns.db.perf) == "table" and Data(false) or nil
	if not p then
		Add(L.PERF_STATE_NEVER)
		Add("")
		Add(L.PERF_HELP)
		return table.concat(out, "\n")
	end
	local since = date("%Y-%m-%d %H:%M", p.since)
	Add((on and L.PERF_STATE_ON or L.PERF_STATE_OFF):format(Duration(Perf.Elapsed()), since))
	Add(L.PERF_FRAMES:format(Perf.FRAME_MS, Count(p.heavy), Count(p.frames)))
	Add("")
	Add(L.PERF_WORST_FRAMES)
	if #p.worst == 0 then Add("  " .. L.PERF_NONE) end
	for _, f in ipairs(p.worst) do
		Add("  " .. L.PERF_FRAME_ROW:format(Ms(f.ms), At(f.at), tostring(f.top or "?"), Ms(f.topMs)))
	end
	Add("")
	Add(L.PERF_SLOWEST:format(Perf.SLOW_KEEP))
	if #p.slow == 0 then Add("  " .. L.PERF_NONE) end
	for _, e in ipairs(p.slow) do Add("  " .. L.PERF_SLOW_ROW:format(Ms(e.ms), At(e.at), e.label)) end
	Add("")
	Add(L.PERF_TOTALS)
	local rows = Sorted(p.stats, "total", Perf.TOP)
	if #rows == 0 then Add("  " .. L.PERF_NONE) end
	for _, r in ipairs(rows) do Add(TotalRow(r.key, r.s)) end
	Add("")
	Add(L.PERF_EVENTS)
	rows = Sorted(p.events, "total", Perf.TOP_EVENTS)
	if #rows == 0 then Add("  " .. L.PERF_NONE) end
	for _, r in ipairs(rows) do Add(TotalRow(r.key, r.s)) end
	Add("")
	Add(L.PERF_HELP)
	Add(L.PERF_NOTES)
	return table.concat(out, "\n")
end

-- The report in Olympus's copy window (chat as the fallback where the window is missing).
function Perf.Show()
	local text = Perf.ReportText()
	if ns.UI and ns.UI.ShowCopy then
		return ns.UI.ShowCopy(L.PERF_TITLE, text, { label = L.PERF_REFRESH, fn = function() Perf.Show() end },
			{ key = "perf", big = true, second = { label = L.PERF_RESET_BTN, fn = function() Perf.Reset(); Perf.Show() end } })
	end
	for line in text:gmatch("[^\n]+") do ns.Print(line) end
end

-- /oly perf [on | off | reset]
function Perf.Slash(rest)
	local word = (tostring(rest or ""):match("^%s*(%S*)") or ""):lower()
	if word == "on" then
		local ok, why = Perf.Start()
		ns.Print(ok and L.PERF_ON or (why == "clock" and L.PERF_NO_CLOCK or L.PERF_OFF))
	elseif word == "off" then
		Perf.Stop()
		ns.Print(L.PERF_OFF)
	elseif word == "reset" then
		Perf.Reset()
		ns.Print(L.PERF_RESET_DONE)
	else
		Perf.Show()
	end
end

-- A function's file and line where the game's Lua tells them (scripts/perf-listeners.lua's names).
Perf.Site = Source

-- On through a /reload: the saved word starts it again on the frame after the load, not in INIT
-- itself. INIT runs inside Core.lua's ADDON_LOADED handler: started there, the listeners of INIT
-- after this one and the ADDON_LOADED handlers after Core.lua's would be numbered from #1, and
-- each #n of theirs would name another listener than its place in the order of registration.
ns.On("INIT", function()
	local p = ns.db and ns.db.perf
	if type(p) == "table" and p.on == true then
		ns.After(0, "perf resume", function()
			local q = ns.db and ns.db.perf
			if type(q) == "table" and q.on == true then Perf.Start() end
		end)
	end
end)

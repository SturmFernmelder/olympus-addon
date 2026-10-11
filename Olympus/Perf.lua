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
--
-- 1.2.3: memory too, for the RAM's spikes (the owner: "o problema da ram ... sao os picos, nao o
-- regular"). Each call's Lua heap before and after (collectgarbage("count"), two reads around the
-- clock's two): what it allocated (the profiler's own records aside), by label, total and biggest
-- with its time. A lower bound: a step of the garbage collector inside the call frees memory and
-- lowers it (never below 0). Like the time, a call's KB includes the calls made inside it, so a
-- DATA_CHANGED listener run inside an event's handler has its own line too. Each frame our
-- OnUpdate reads the heap (every addon's and the game's own Lua, all one heap): the frames where
-- it grew 1 MB or more since the last are counted, the 10 biggest kept with what Olympus's
-- top-level calls allocated in that frame and the biggest of them; the highest heap seen and when.
-- The game's own figures per addon (GetAddOnMemoryUsage) are measured once as the report opens
-- (UpdateAddOnMemoryUsage walks every addon's memory: never on a timer, nor at each frame).

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
Perf.JUMP_KB = 1024  -- 1.2.3: a frame whose Lua heap grew this much (KB) since the last is counted
Perf.JUMP_KEEP = 10  -- the biggest of those kept
Perf.TOP_ALLOC = 25  -- the report's "biggest allocations" lines

local on = false        -- measuring now
local installed = false -- our wrapper is in ns.SafeCall's chain
local inner             -- the ns.SafeCall ours calls (Core.lua's, unless someone wrapped it first)
local data              -- ns.db.perf while on
local clock             -- debugprofilestop
local heap              -- collectgarbage: heap("count"), the Lua heap in KB (every addon's)
local frame             -- our own frame, made at the first start
local logoutHooked = false
local runStart = 0      -- GetTime() at this run's start (or the last fold)
local depth = 0         -- protected calls running now (0: a top-level call)
local frameSum, frameTopMs, frameTop = 0, 0, nil
local frameKb, frameKbTop, frameKbTopKb = 0, nil, 0 -- what this frame's top-level calls allocated
local lastHeap          -- the heap at the last frame's end (nil: no frame yet in this run)
local own = 0           -- KB the profiler's own records allocated inside calls (only ever grows)
local slowMin, worstMin, jumpMin = -1, -1, -1

local function Now() return GetTime() end
local function NoHeap() return 0 end

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

-- A label's row: its calls, their ms (total, slowest and when) and, 1.2.3, the KB they
-- allocated (kb: total; kbMax, kbAt: the biggest one call's, and when).
local function Bump(t, key, dt, kb)
	local s = t[key]
	if not s then
		s = { n = 0, total = 0, max = 0, at = 0, kb = 0, kbMax = 0, kbAt = 0 }
		t[key] = s
	end
	s.n = s.n + 1
	s.total = s.total + dt
	if dt > s.max then s.max, s.at = dt, time() end
	if kb > 0 then
		s.kb = s.kb + kb
		if kb > s.kbMax then s.kbMax, s.kbAt = kb, time() end
	end
end

-- Into a list kept biggest first by `field` (ms unless told), `keep` long: entry where it puts it.
local function Keep(list, keep, entry, field)
	field = field or "ms"
	local i = #list
	if i >= keep then
		list[i] = nil
		i = i - 1
	end
	while i >= 1 and list[i][field] < entry[field] do
		list[i + 1] = list[i]
		i = i - 1
	end
	list[i + 1] = entry
	return #list >= keep and list[#list][field] or -1
end

local function Record(where, fn, dt, kb)
	-- (A collection inside the call can leave the heap lower than before it: nothing allocated, then.)
	if kb < 0 then kb = 0 end
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
	Bump(stats, key, dt, kb)
	if b.listener then Bump(data.events, b.label, dt, kb) end
	if dt > slowMin then slowMin = Keep(data.slow, Perf.SLOW_KEEP, { label = key, ms = dt, at = time() }) end
	if depth == 0 then
		frameSum = frameSum + dt
		if dt > frameTopMs then frameTopMs, frameTop = dt, key end
		frameKb = frameKb + kb
		if kb > frameKbTopKb then frameKbTopKb, frameKbTop = kb, key end
	end
end

-- ns.SafeCall while on: Core.lua's (or what it was) between two reads of the clock, and two of
-- the Lua heap around those (1.2.3: what the call allocated, in KB). What the profiler's own
-- records of the calls inside it allocated is not the call's (a label's row and name at its first
-- call; at the first listener met without a source, the namespace's names, 100 KB and more): the
-- heap around a record made inside another call is read too, and that call's KB is without it.
local function Timed(where, fn, ...)
	if not on then return inner(where, fn, ...) end
	depth = depth + 1
	local own0 = own
	local m0 = heap("count")
	local t0 = clock()
	local ok = inner(where, fn, ...)
	local dt = clock() - t0
	local kb = heap("count") - m0 - (own - own0)
	depth = depth - 1
	if on then
		local r0 = depth > 0 and heap("count")
		local fine, err = pcall(Record, where, fn, dt, kb)
		if r0 then
			local mine = heap("count") - r0
			if mine > 0 then own = own + mine end
		end
		if not fine then
			-- (A fault of the profiler's never breaks the call it measured: it stops, and says why.)
			Perf.Stop()
			if ns.CaptureError then ns.CaptureError("perf record", err) end
		end
	end
	return ok
end

-- One drawn frame done (our frame's OnUpdate): what Olympus's top-level calls took in it; 1.2.3,
-- the Lua heap now, how much it grew since the last frame's end, and what Olympus allocated in it.
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
	local kb = heap("count")
	if kb > data.peak then data.peak, data.peakAt = kb, time() end
	local grew = lastHeap and kb - lastHeap or 0
	lastHeap = kb
	if grew >= Perf.JUMP_KB then
		data.jumped = data.jumped + 1
		if grew > jumpMin then
			jumpMin = Keep(data.jumps, Perf.JUMP_KEEP,
				{ kb = grew, at = time(), heap = kb, ours = frameKb, top = frameKbTop, topKb = frameKbTopKb }, "kb")
		end
	end
	frameKb, frameKbTop, frameKbTopKb = 0, nil, 0
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
			-- (1.2.3's KB: none in a row saved by 1.2.2.)
			if type(s.kb) ~= "number" or type(s.kbMax) ~= "number" then s.kb, s.kbMax = 0, 0 end
			if type(s.kbAt) ~= "number" then s.kbAt = 0 end
			n = n + 1
		else
			bad = bad or {}
			bad[#bad + 1] = k
		end
	end
	if bad then for _, k in ipairs(bad) do t[k] = nil end end
	return n
end

-- A saved list, biggest first by `field` (ms unless told) and `keep` long: itself when it is one,
-- else one made of its good rows.
local function CleanList(t, keep, frames, field)
	field = field or "ms"
	local fine = #t <= keep
	for i, e in ipairs(t) do
		if not (type(e) == "table" and type(e[field]) == "number" and (frames or type(e.label) == "string")) or (i > 1 and t[i - 1][field] < e[field]) then
			fine = false
			break
		end
	end
	if fine then return t end
	local out = {}
	for _, e in ipairs(t) do
		if type(e) == "table" and type(e[field]) == "number" and (frames or type(e.label) == "string") then out[#out + 1] = e end
	end
	table.sort(out, function(a, b) return a[field] > b[field] end)
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
	p.jumps = CleanList(Table(p.jumps), Perf.JUMP_KEEP, true, "kb")
	p.frames, p.heavy, p.measured = Num(p.frames), Num(p.heavy), Num(p.measured)
	p.jumped, p.peak, p.peakAt = Num(p.jumped), Num(p.peak), Num(p.peakAt)
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
	-- (A Lua with no collectgarbage, which the game's has: no KB, the time measured as before.)
	local gc = rawget(_G, "collectgarbage")
	heap = type(gc) == "function" and gc or NoHeap
	p.on = true
	runStart = Now()
	slowMin = #p.slow >= Perf.SLOW_KEEP and p.slow[#p.slow].ms or -1
	worstMin = #p.worst >= Perf.WORST_KEEP and p.worst[#p.worst].ms or -1
	jumpMin = #p.jumps >= Perf.JUMP_KEEP and p.jumps[#p.jumps].kb or -1
	depth, frameSum, frameTopMs, frameTop = 0, 0, 0, nil
	frameKb, frameKbTop, frameKbTopKb, lastHeap = 0, nil, 0, heap("count")
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
	frameKb, frameKbTop, frameKbTopKb, lastHeap = 0, nil, 0, nil
end

-- Clears what was measured; measuring goes on if it was on.
function Perf.Reset()
	local p = ns.db and type(ns.db.perf) == "table" and ns.db.perf
	if not p then return end
	p.stats, p.events, p.slow, p.worst, p.jumps = {}, {}, {}, {}, {}
	p.keys, p.frames, p.heavy, p.measured = 0, 0, 0, 0
	p.jumped, p.peak, p.peakAt = 0, 0, 0
	p.since = time()
	runStart = Now()
	slowMin, worstMin, jumpMin = -1, -1, -1
	frameSum, frameTopMs, frameTop = 0, 0, nil
	frameKb, frameKbTop, frameKbTopKb = 0, nil, 0
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
-- KB: one decimal under 10, whole above.
local function Kb(v)
	v = tonumber(v) or 0
	if v ~= v then v = 0 end
	return v < 10 and ("%.1f"):format(v) or Count(v + 0.5)
end

-- 1.2.3: the game's figure for one addon's memory (KB, as UpdateAddOnMemoryUsage last measured it).
local function AddOnKb(name)
	local get = rawget(_G, "GetAddOnMemoryUsage")
	if type(get) ~= "function" then return "?" end
	local ok, v = pcall(get, name)
	return (ok and type(v) == "number") and Kb(v) or "?"
end

local function HeapNow()
	local gc = rawget(_G, "collectgarbage")
	local ok, v = pcall(type(gc) == "function" and gc or NoHeap, "count")
	return (ok and type(v) == "number") and Kb(v) or "?"
end

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
	-- (1.2.3: measured or not, the memory now; Perf.Show had the game measure it as it opened.)
	Add(L.PERF_MEMORY_NOW:format(AddOnKb("Olympus"), AddOnKb("Olympus_Arena"), HeapNow()))
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
	Add(L.PERF_JUMPED:format(Kb(Perf.JUMP_KB), Count(p.jumped), Count(p.frames)))
	if p.peak > 0 then Add(L.PERF_HEAP_PEAK:format(Kb(p.peak), At(p.peakAt))) end
	Add("")
	Add(L.PERF_WORST_FRAMES)
	if #p.worst == 0 then Add("  " .. L.PERF_NONE) end
	for _, f in ipairs(p.worst) do
		Add("  " .. L.PERF_FRAME_ROW:format(Ms(f.ms), At(f.at), tostring(f.top or "?"), Ms(f.topMs)))
	end
	Add("")
	Add(L.PERF_JUMPS)
	if #p.jumps == 0 then Add("  " .. L.PERF_NONE) end
	for _, j in ipairs(p.jumps) do
		if j.top then
			Add("  " .. L.PERF_JUMP_ROW:format(Kb(j.kb), At(j.at), Kb(j.heap), Kb(j.ours), tostring(j.top), Kb(j.topKb)))
		else
			Add("  " .. L.PERF_JUMP_ROW_NONE:format(Kb(j.kb), At(j.at), Kb(j.heap)))
		end
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
	-- (1.2.3: the biggest allocations, by the biggest one call: the spikes, beside each label's total.)
	Add(L.PERF_ALLOCS)
	local shown = 0
	for _, r in ipairs(Sorted(p.stats, "kbMax", Perf.TOP_ALLOC)) do
		if r.s.kbMax > 0 then
			shown = shown + 1
			Add("  " .. L.PERF_ALLOC_ROW:format(r.key, Kb(r.s.kbMax), At(r.s.kbAt), Kb(r.s.kb), Count(r.s.n)))
		end
	end
	if shown == 0 then Add("  " .. L.PERF_NONE) end
	Add("")
	Add(L.PERF_EVENTS)
	rows = Sorted(p.events, "total", Perf.TOP_EVENTS)
	if #rows == 0 then Add("  " .. L.PERF_NONE) end
	for _, r in ipairs(rows) do Add(TotalRow(r.key, r.s)) end
	Add("")
	Add(L.PERF_HELP)
	Add(L.PERF_NOTES)
	Add(L.PERF_MEMORY_NOTES)
	return table.concat(out, "\n")
end

-- The report in Olympus's copy window (chat as the fallback where the window is missing).
function Perf.Show()
	-- (1.2.3: the game's figures per addon measured now, once, as the report opens.)
	local update = rawget(_G, "UpdateAddOnMemoryUsage")
	if type(update) == "function" then pcall(update) end
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

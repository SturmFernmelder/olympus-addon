-- Names each listener of a /oly perf report by its file and line: "callback DATA_CHANGED #18" is
-- the 18th function registered for DATA_CHANGED (ns.On), "event CHAT_MSG_ADDON #3" the 3rd one
-- registered for that event (ns.RegisterEvent).
--
--   luajit scripts/perf-listeners.lua [--gamepad] [word ...]
--
-- From the repository root, with the report's version checked out (the report's first line names
-- it). Words: only the labels holding one of them (DATA_CHANGED, CHAT_MSG_ADDON); none, every
-- label. --gamepad: the report's player had the gamepad UI on.
--
-- Why: the game's Lua has no debug library, so Olympus/Perf.lua names most listeners by their
-- place alone (#n; a name where the namespace has the function). That place is the order of
-- registration: the TOC's files in order, then what they register at the login, the same on every
-- client of one version. This loads the checkout in the gamepad pass's model of the client
-- (tests/gamepad.lua: every file of the TOC, ADDON_LOADED, the login and its first 30 s of timers),
-- reads Core.lua's own lists (ns.Fire's listeners, ns.RegisterEvent's handlers) and prints each
-- listener's file and line as the profiler gives them where it can (ns.Perf.Site). A listener
-- registered later in a session (a window first opened, a feature switched on) comes after these.
--
-- tests/perf.lua loads it with "--module": then it returns its parts and prints nothing.

local MODE = ...
local M = {}

-- The model of the client, logged in, with the debug library in its Lua (the profiler's sites).
-- saved: the saved variables it starts from (nil: the model's usual answered ones).
function M.Session(gamepad, saved)
	local load = loadfile("tests/gamepad.lua")
	if not load then error("tests/gamepad.lua not found: run this from the repository root", 0) end
	local GPM = load("--debug")
	return GPM.Session(gamepad and true or false, { saved = saved, setup = function(C) rawset(C.env, "debug", debug) end })
end

local function Upvalue(fn, want)
	for i = 1, 255 do
		local name, v = debug.getupvalue(fn, i)
		if name == nil then return nil end
		if name == want then return v end
	end
end

-- [label] = { [n] = { fn = the listener, site = "File.lua:line" } }, a label as the profiler's:
-- "callback NAME" for ns.On's, "event NAME" for ns.RegisterEvent's.
function M.Map(ns)
	local listeners = type(ns.Fire) == "function" and Upvalue(ns.Fire, "listeners")
	local handlers = type(ns.RegisterEvent) == "function" and Upvalue(ns.RegisterEvent, "handlers")
	assert(type(listeners) == "table" and type(handlers) == "table", "Core.lua's lists of listeners: ns.Fire's listeners, ns.RegisterEvent's handlers")
	local site = ns.Perf and ns.Perf.Site
	assert(type(site) == "function", "Perf.lua's Perf.Site")
	local map = {}
	for prefix, lists in pairs({ callback = listeners, event = handlers }) do
		for name, list in pairs(lists) do
			local rows = {}
			for i, fn in ipairs(list) do rows[i] = { fn = fn, site = site(fn) or "?" } end
			map[prefix .. " " .. tostring(name)] = rows
		end
	end
	return map
end

-- The lines printed: "callback DATA_CHANGED #18  HonorsNet.lua:634", by label then #n; words as
-- above (nil or none: every label).
function M.Lines(map, words)
	local labels = {}
	for label in pairs(map) do
		local keep = not words or #words == 0
		for _, w in ipairs(words or {}) do
			if label:lower():find(w:lower(), 1, true) then keep = true end
		end
		if keep then labels[#labels + 1] = label end
	end
	table.sort(labels)
	local out = {}
	for _, label in ipairs(labels) do
		for n, row in ipairs(map[label]) do out[#out + 1] = ("%s #%d  %s"):format(label, n, row.site) end
	end
	return out
end

if MODE == "--module" then return M end

local gamepad, words = false, {}
for _, a in ipairs(arg or {}) do
	if a == "--gamepad" then gamepad = true else words[#words + 1] = a end
end
local _, ns = M.Session(gamepad)
print(("Olympus %s, %s: each listener's #n in /oly perf"):format(tostring(ns.VERSION), gamepad and "gamepad UI" or "mouse and keyboard"))
for _, line in ipairs(M.Lines(M.Map(ns), words)) do print(line) end

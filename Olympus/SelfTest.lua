local ADDON, ns = ...
local L = ns.L

-- /oly selftest: the checks a tester alone with one account would otherwise make by hand, run by
-- themselves and kept in OlympusDB.selftest for whoever reads the SavedVariables after a /reload.
-- Only on a test build (ns.TEST_BUILD, written by scripts/package.sh --test N) and for the addon's
-- author (Workshop.IsAuthorName); anywhere else it says it is not there.
--
-- What it does, in small steps over many frames (C_Timer, a few milliseconds of work a frame, one
-- window drawn a frame):
--   api.*   the client's answers the newer features rely on (Battle.net, the guild roster, the
--           clock, atlases, talents, percentages, casts, item stats, secret values), each guarded;
--   ui.*    the Olympus window on every tab, every page its strips and links reach, the pages other
--           files list (ns.RealmPages, UI.TABS, the openers below), the Accord's letter, the privacy
--           page, the copy window, the Arena window: errors, a Back on every page reached by a link,
--           light text on parchment, text past its window;
--   mod.*   read-only states and counts of the modules (no setter is ever called);
--   build.* which version and files run, which later features are in this build, errors seen.
-- It never sends: every Olympus send (Comm, Arena.Send, SayTo) is held while a step runs or a page
-- draws, and only its type is counted. It never changes a setting: the window's tab and page, the
-- modules' pages and the saved keys the pages write are put back as they were. It never clicks a
-- row or a button but a page's own navigation, its links and its Back; it stops in combat or at a
-- loading screen, putting everything back first.

local SelfTest = {}
ns.SelfTest = SelfTest

SelfTest.MAX_PROBES = 300
SelfTest.DETAIL_MAX = 160
SelfTest.ID_MAX = 48
SelfTest.LIST_MAX = 30
SelfTest.BUDGET_MS = 6           -- a frame's work for light steps (at least one a frame)
SelfTest.HEAVY_GAP = 0.1         -- after a step that drew a window, the next frame comes this much later
SelfTest.RUN_MAX = 240           -- seconds: past this the run stops and reports what it has
SelfTest.SLOW_STEP_MS = 50
SelfTest.TOOLTIPS_PER_PAGE = 40
SelfTest.WALK_NODES_MAX = 2e6
SelfTest.RECORD_VERIFY_MAX_BYTES = 8192
SelfTest.HISTORY_MAX = 10
SelfTest.LIGHT_LUMA = 0.5
SelfTest.LINKS_PER_PAGE = 16
SelfTest.SIBLINGS_PER_TAB = 12
SelfTest.FINGERPRINT_MAX = 4096  -- a saved key larger than this (serialized) is not compared
SelfTest.BYTES_MAX = 32000       -- the probes' text kept at most (past it, details are dropped)
SelfTest.TEXT_MAX = 6000         -- the copy window's text
SelfTest.OVERFLOW_PX = 4
SelfTest.REGIONS_MAX = 2000
SelfTest.DEPTH_MAX = 8

-- Swappable in tests: the timer, the millisecond clock, the seconds clock, a frame's parts.
SelfTest.After = function(seconds, fn) C_Timer.After(seconds, fn) end
SelfTest.Clock = function() return debugprofilestop() end
SelfTest.Now = function() return GetTime() end
function SelfTest.Regions(frame)
	if type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return {} end
	return { frame:GetRegions() }
end
function SelfTest.Children(frame)
	if type(frame) ~= "table" or type(frame.GetChildren) ~= "function" then return {} end
	return { frame:GetChildren() }
end
-- Tests: fn(tick, stepId, heavy) after each step.
SelfTest.trace = nil

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- A value the client keeps secret: never compared, never read.
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end

-- A module of this addon that is loaded (not Core.lua's stand-in), else nil.
local function Mod(name)
	local m = rawget(ns, name)
	if type(m) ~= "table" or rawget(m, "missing") == true then return nil end
	return m
end

-- fn(...) protected, when it is a function: pcall's results.
local function Try(fn, ...)
	if type(fn) ~= "function" then return false, "absent" end
	return pcall(fn, ...)
end

local function Trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

-- A text without its textures, atlases, links' codes and colours.
local function Strip(s)
	if type(s) ~= "string" or Secret(s) then return "" end
	return (s:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- At most n bytes, never half a letter.
local function Clip(s, n)
	if Secret(s) then return "<secret>" end
	s = tostring(s == nil and "" or s)
	n = n or SelfTest.DETAIL_MAX
	if #s <= n then return s end
	s = s:sub(1, n)
	local tail = s:match("[\192-\255][\128-\191]*$")
	if tail then
		local lead = tail:byte(1)
		local need = lead >= 240 and 4 or (lead >= 224 and 3 or 2)
		if #tail < need then s = s:sub(1, #s - #tail) end
	end
	return s
end

function SelfTest.Luma(r, g, b) return 0.2126 * (tonumber(r) or 0) + 0.7152 * (tonumber(g) or 0) + 0.0722 * (tonumber(b) or 0) end

local function Round(x, places)
	local m = 10 ^ (places or 0)
	return math.floor((tonumber(x) or 0) * m + 0.5) / m
end

local function Bool(v) if Secret(v) then return "secret" end return tostring(v) end

-- Each value of a plain table of numbers or booleans, "k=v" in key order.
local function Pairs(t, keys)
	local out = {}
	if type(t) ~= "table" then return "" end
	if not keys then
		keys = {}
		for k, v in pairs(t) do if type(k) == "string" and (type(v) == "number" or type(v) == "boolean") then keys[#keys + 1] = k end end
		table.sort(keys)
	end
	for _, k in ipairs(keys) do
		local v = t[k]
		if type(v) == "number" then out[#out + 1] = k .. "=" .. tostring(Round(v, 1))
		elseif type(v) == "boolean" then out[#out + 1] = k .. "=" .. tostring(v) end
	end
	return table.concat(out, " ")
end

-- A deep copy of a plain value (cycles kept as one copy).
local function Copy(v, seen)
	if type(v) ~= "table" then return v end
	seen = seen or {}
	if seen[v] then return seen[v] end
	local out = {}
	seen[v] = out
	for k, x in pairs(v) do out[Copy(k, seen)] = Copy(x, seen) end
	return out
end

local function SortedKeys(t)
	local keys = {}
	for k in pairs(type(t) == "table" and t or {}) do if type(k) == "string" then keys[#keys + 1] = k end end
	table.sort(keys)
	return keys
end

-- A value as text, its keys in order, or nil when longer than max: what tells a change.
local function Fingerprint(v, max)
	local parts, size, over, seen = {}, 0, false, {}
	local function Put(s)
		size = size + #s
		if size > max then over = true return end
		parts[#parts + 1] = s
	end
	local function Key(k) return type(k) .. tostring(k) end
	local function Walk(x, depth)
		if over then return end
		local t = type(x)
		if t == "table" then
			if seen[x] or depth > 12 then Put("@") return end
			seen[x] = true
			local keys = {}
			for k in pairs(x) do
				keys[#keys + 1] = k
				if #keys > max then over = true return end
			end
			table.sort(keys, function(a, b) return Key(a) < Key(b) end)
			Put("{")
			for _, k in ipairs(keys) do
				Put(Key(k) .. "=")
				Walk(x[k], depth + 1)
				Put(",")
				if over then return end
			end
			Put("}")
		elseif t == "string" then
			Put("s" .. #x .. ":" .. x)
		elseif t == "number" or t == "boolean" then
			Put(t:sub(1, 1) .. tostring(x))
		else
			Put(t)
		end
	end
	Walk(v, 0)
	if over then return nil end
	return table.concat(parts)
end

-- Words of a page's id that name no one: they stay; anything else after a ":" becomes "*".
local STATIC = {}
for _, k in ipairs({ "guilds", "classes", "races", "professions", "recruits", "look", "icons", "privacy", "letters",
	"desk", "reports", "cases", "judgments", "justice", "chat", "tabards", "member", "tags", "summary", "book",
	"keepers", "wallet", "dues", "guild-finance", "own-guild", "guild", "money", "rules", "stats", "list", "review",
	"hands", "home", "ranking", "mine", "people", "name", "public", "detail" }) do STATIC[k] = true end
local function Static(word)
	if STATIC[word] then return true end
	local M = Mod("Members")
	for _, f in ipairs(M and type(M.FILTERS) == "table" and M.FILTERS or {}) do if tostring(f) == word then return true end end
	local PE = Mod("ProfileEdit")
	for _, s in ipairs(PE and type(PE.SECTIONS) == "table" and PE.SECTIONS or {}) do if s == word then return true end end
	return false
end

-- A page's id as the report keeps it: "watch/case:*", "player-profile:self#look", "player-profile:other".
function SelfTest.SafeId(id)
	if Secret(id) then return "?" end
	id = tostring(id or "")
	local who, section = id:match("^player%-profile:([^#]*)#?(.*)$")
	if who then
		local mine = type(ns.me) == "string" and type(ns.Fold) == "function" and ns.Fold(who) == ns.Fold(ns.me)
		if not mine then return "player-profile:other" end
		return Clip("player-profile:self" .. (section ~= "" and ("#" .. (Static(section) and section or "*")) or ""), SelfTest.ID_MAX)
	end
	id = id:gsub(":([^/]*)", function(rest) return Static(rest) and (":" .. rest) or ":*" end)
	return Clip(id, SelfTest.ID_MAX)
end
local SafeId = SelfTest.SafeId

-- An error's text, from its file on (the folders before it say nothing).
local function ErrText(err, n)
	if Secret(err) then return "<secret>" end
	return Clip((tostring(err):gsub("^.-[Aa]dd[Oo]ns[/\\]", "")), n or 120)
end

-- Where an error came from, without what a player typed after a command.
local function SafeWhere(where)
	where = tostring(where or "?")
	local cmd = where:match("^slash%s+(%S+)")
	if cmd then return "slash " .. cmd end
	return Clip(where, 40)
end

---------------------------------------------------------------------------
-- The run and its report
---------------------------------------------------------------------------

local run -- the run in progress, or nil
local tokens = 0

local function Note(list, value)
	if type(list) ~= "table" or value == nil then return end
	for _, v in ipairs(list) do if v == value then return end end
	if #list < SelfTest.LIST_MAX then list[#list + 1] = value end
end

-- One result: id, area, what was checked, ok | warn | fail | skip, and a short detail.
local function Add(id, area, what, result, detail)
	local r = run
	if not r then return nil end
	r.counts[result] = (r.counts[result] or 0) + 1
	if #r.probes >= SelfTest.MAX_PROBES then
		r.dropped = r.dropped + 1
		return nil
	end
	local p = { id = Clip(id, SelfTest.ID_MAX), area = Clip(area or "selftest", 12), what = Clip(what or "", 60), result = result }
	local d = Clip(detail or "", SelfTest.DETAIL_MAX)
	if r.bytes + #d > SelfTest.BYTES_MAX then
		r.trimmed = r.trimmed + 1
		d = ""
	end
	p.detail = d
	r.bytes = r.bytes + #p.id + #p.what + #d + 24
	r.probes[#r.probes + 1] = p
	if r.current then r.current.made[#r.current.made + 1] = p end
	return p
end

local function Step(id, area, what, fn, opts)
	local s = { id = id, area = area, what = what, fn = fn }
	for k, v in pairs(opts or {}) do s[k] = v end
	return s
end
local function P(step, result, detail) return Add(step.id, step.area, step.what, result, detail) end

-- Steps to run right after the one running now, in this order.
local function Insert(steps)
	local r = run
	if not r then return end
	for i, s in ipairs(steps) do table.insert(r.queue, r.pos + i - 1, s) end
end

---------------------------------------------------------------------------
-- The send fence and the error tap
---------------------------------------------------------------------------

-- The sends held: { module, function, the argument whose type is counted, the done callback's
-- argument (called once with false, "selftest", as each refuses) }. Comm.SendChat, WhisperOutside,
-- Arena.Send and ns.SayTo refuse without calling theirs.
local FENCED = {
	{ "Comm", "Send", 2, 6 }, { "Comm", "Whisper", 2, 6 }, { "Comm", "SendBatch", 2, 6 }, { "Comm", "SendChunked", 1, 4 },
	{ "Comm", "SendChat", 1 }, { "Comm", "WhisperOutside", 2 }, { "Arena", "Send", 1 }, { false, "SayTo" },
}

local function Kind(spec, v)
	if spec[2] == "SayTo" then return "say" end
	if type(v) == "table" then v = v[1] end
	if type(v) ~= "string" or Secret(v) then return "?" end
	if spec[1] == "Arena" then return "arena:" .. (v:match("^%w+$") and v:sub(1, 8) or "?") end
	return v:match("^(%u+%d?)~") or (spec[2] == "SendChat" and "chat" or "?")
end

local function FenceOn(r)
	local f = { depth = 0, blocked = {}, wrapped = {}, left = {} }
	for _, spec in ipairs(FENCED) do
		local owner = spec[1] == false and ns or Mod(spec[1])
		local key = spec[2]
		local orig = type(owner) == "table" and rawget(owner, key) or nil
		if type(orig) == "function" then
			local wrapper = function(...)
				if f.depth > 0 then
					local kind = Kind(spec, (select(spec[3] or 1, ...)))
					f.blocked[kind] = (f.blocked[kind] or 0) + 1
					local step = run and run.current
					if step then step.sends[kind] = (step.sends[kind] or 0) + 1 end
					local done = spec[4] and (select(spec[4], ...)) or nil
					if type(done) == "function" then ns.SafeCall("selftest refused send", done, false, "selftest") end
					if spec[1] == "Arena" then return false, "selftest" end
					return false
				end
				return orig(...)
			end
			owner[key] = wrapper
			f.wrapped[#f.wrapped + 1] = { owner = owner, key = key, orig = orig, wrapper = wrapper }
		end
	end
	r.fence = f
	-- Every redraw of the window while the run lasts is inside the fence too: a page drawn again by
	-- itself (its timer, an event) may ask the network as it draws.
	SelfTest.FenceRedraws(Mod("UI"), "Refresh")
	return f
end

-- owner[key] (a window's redraw) inside the fence whenever it runs, until the run ends.
function SelfTest.FenceRedraws(owner, key)
	local f = run and run.fence
	local redraw = type(owner) == "table" and rawget(owner, key) or nil
	if not f or f.off or type(redraw) ~= "function" then return false end
	for _, w in ipairs(f.wrapped) do if w.owner == owner and w.key == key then return true end end
	local wrapper = function(...)
		f.depth = f.depth + 1
		local ok, err = pcall(redraw, ...)
		f.depth = f.depth - 1
		if not ok then error(err, 0) end
	end
	owner[key] = wrapper
	f.wrapped[#f.wrapped + 1] = { owner = owner, key = key, orig = redraw, wrapper = wrapper }
	return true
end

local function FenceOff(r)
	local f = r and r.fence
	if not f or f.off then return end
	f.off = true
	for i = #f.wrapped, 1, -1 do
		local w = f.wrapped[i]
		if rawget(w.owner, w.key) == w.wrapper then w.owner[w.key] = w.orig else f.left[#f.left + 1] = w.key end
	end
end

-- ns.CaptureError (Diagnostics.lua: every ns.SafeCall's) seen by the step that runs, then handed on
-- as it came: /oly bug still has every real error.
local function TapOn(r)
	local orig = ns.CaptureError
	local t = { orig = orig }
	t.tap = function(where, err)
		local step = run and run.current
		if step then step.errors[#step.errors + 1] = { where = SafeWhere(where), msg = ErrText(err) } end
		if type(orig) == "function" then return orig(where, err) end
	end
	ns.CaptureError = t.tap
	r.tap = t
end
local function TapOff(r)
	local t = r and r.tap
	if not t or t.off then return end
	t.off = true
	if ns.CaptureError == t.tap then ns.CaptureError = t.orig else r.fence.left[#r.fence.left + 1] = "CaptureError" end
end

local function AllErrors() return type(ns.allErrors) == "table" and #ns.allErrors or 0 end

---------------------------------------------------------------------------
-- The scheduler
---------------------------------------------------------------------------

local function RunStep(step)
	local r = run
	step.made, step.sends, step.errors = {}, {}, {}
	step.errBase = AllErrors()
	r.current = step
	r.fence.depth = r.fence.depth + 1
	local t0 = SelfTest.Clock()
	local ok, res = pcall(step.fn, step)
	local ms = SelfTest.Clock() - t0
	r.fence.depth = r.fence.depth - 1
	r.current = nil
	r.ms, r.steps = r.ms + ms, r.steps + 1
	if ms > r.worst.ms then r.worst.ms, r.worst.id = ms, step.id end
	r.raised = r.raised + math.max(0, AllErrors() - step.errBase)
	r.errorsSeen = r.errorsSeen + #step.errors
	if not ok then Add(step.id, step.area, step.what, "fail", "selftest: " .. ErrText(res)) end
	for _, p in ipairs(step.made) do if p.ms == nil then p.ms = Round(ms, 1) end end
	if SelfTest.trace then pcall(SelfTest.trace, r.ticks, step.id, step.heavy == true) end
	if ok and res == "again" and run == r then table.insert(r.queue, r.pos, step) end
end

local function Tick(token)
	local r = run
	if not r or r.token ~= token then return end
	r.ticks = r.ticks + 1
	ns.SafeCall("selftest cast", SelfTest.SampleCast)
	if SelfTest.Now() - r.started > SelfTest.RUN_MAX then
		SelfTest.Abort("time")
		return
	end
	-- (Combat or the gamepad UI without their event seen: stopped all the same.)
	if type(InCombatLockdown) == "function" and InCombatLockdown() then
		SelfTest.Abort("combat")
		ns.Print(L.SELFTEST_ABORT_COMBAT)
		return
	end
	if type(ns.GamepadUI) == "function" and ns.GamepadUI() then
		SelfTest.Abort("gamepad")
		ns.Print(L.SELFTEST_GAMEPAD)
		return
	end
	local started, n, heavy = SelfTest.Clock(), 0, false
	while run == r and r.pos <= #r.queue do
		local step = r.queue[r.pos]
		if step.heavy and n > 0 then break end
		r.pos = r.pos + 1
		RunStep(step)
		n = n + 1
		if step.heavy then heavy = true break end
		if SelfTest.Clock() - started >= SelfTest.BUDGET_MS then break end
	end
	if run ~= r then return end
	if r.done or r.pos > #r.queue then SelfTest.Teardown() return end
	SelfTest.After(heavy and SelfTest.HEAVY_GAP or 0, function() Tick(token) end)
end

---------------------------------------------------------------------------
-- What the run keeps and puts back
---------------------------------------------------------------------------

-- The saved keys the pages write as they open (the Chat tab's place, the Arena window's, the
-- privacy page's asked questions, the letters read, the author's View as): put back as they were.
SelfTest.SAVED_KEYS = { "chatWin", "arenaUI", "consentAsked", "consentNotices", "lettersRead", "lettersAutoVersion", "devKingView",
	"devTreasurerView", "devGMView", "previewTreasuryFlags", "previewTreasuryKeepers", "arenaRules" }

-- The Olympus window's page now, with the Church's page (UI.PageId says "church/" for every one).
local function PageKey()
	local UI = Mod("UI")
	if not (UI and type(UI.PageId) == "function") then return "?" end
	local ok, id = pcall(UI.PageId)
	id = ok and type(id) == "string" and id or "?"
	local CV = Mod("ChurchView")
	if CV and id == "church/" then id = "church/" .. tostring(CV.page or "") .. ((CV.page == "detail" and CV.arg ~= nil) and ":*" or "") end
	local CS = Mod("CensusStats")
	if CS and id == "census/" and type(CS.Shown) == "function" and CS.Shown() == true then id = "census/stats" end
	return id
end
SelfTest.PageKey = PageKey

local function Shown(f) return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() == true end
local function FrameOf(m, fn) local ok, f = Try(m and m[fn]) return ok and f or nil end

local function ArenaUI()
	local A = Mod("Arena")
	local loaded = A and type(A.UILoaded) == "function" and A.UILoaded() == true
	local ui = loaded and rawget(A, "ui")
	return type(ui) == "table" and ui or nil
end

function SelfTest.Snapshot()
	local s = { db = {}, prints = {} }
	local UI = Mod("UI")
	local view = UI and type(UI.SelfTestView) == "function" and UI.SelfTestView() or nil
	s.shown = view ~= nil and view.shown == true
	s.tab = view and view.tab or nil
	s.docked = view ~= nil and view.docked == true
	s.page = PageKey()
	s.profile = UI and type(UI.CurrentPlayerProfile) == "function" and UI.CurrentPlayerProfile() or nil
	local V = ns.Views
	if type(V) == "table" then
		s.realmMode = type(V.RealmMode) == "function" and V.RealmMode() or nil
		s.pageShown = type(V.PageShown) == "function" and V.PageShown() or nil
		s.board = type(V.BoardShown) == "function" and V.BoardShown() == true
	end
	local M = Mod("Members")
	if M and type(M.Shown) == "function" and M.Shown() then s.members = M.Filter() end
	local CV = Mod("ChurchView")
	if CV then s.church = { page = CV.page, list = CV.list, window = CV.window, arg = CV.arg } end
	local W = Mod("Watch")
	if W then s.watch = { mode = W.mode, caseKey = W.caseKey, profileKey = W.profileKey } end
	local Wa = Mod("Wanted")
	if Wa and type(Wa.PageId) == "function" then
		s.wanted = Wa.PageId()
		local key = type(s.wanted) == "string" and s.wanted:match("^target:(.+)$")
		if key and type(Wa.Targets) == "function" then
			for _, t in ipairs(Wa.Targets() or {}) do if t.key == key then s.wantedTarget = t end end
		end
	end
	local T = Mod("Treasury")
	if T then s.treasury = T.mode end
	local K = Mod("King")
	if K then s.king = K.mode end
	local CS = Mod("CensusStats")
	if CS and type(CS.Shown) == "function" then s.censusStats = CS.Shown() == true end
	local PE = Mod("ProfileEdit")
	if PE and type(PE.Section) == "function" then s.peSection = PE.Section() end
	local ui = ArenaUI()
	if ui then
		local ok, route = Try(ui.CurrentRoute)
		s.arena = { route = ok and route or nil, shown = Try(ui.IsShown) and ui.IsShown() == true }
	end
	s.frames = {
		accord = Shown(FrameOf(Mod("Accord"), "Frame")),
		consent = Shown(FrameOf(Mod("Consent"), "Frame")),
		copy = UI and type(UI.CopyFrame) == "function" and Shown(UI.CopyFrame("selftest")) or false,
	}
	for _, k in ipairs(SelfTest.SAVED_KEYS) do s.db[k] = Copy(type(ns.db) == "table" and ns.db[k] or nil) end
	for _, k in ipairs(SelfTest.SAVED_KEYS) do s.prints[k] = Fingerprint(s.db[k], 1e6) end
	return s
end

-- The saved key put back in place (the table the modules hold stays the same table).
local function RestoreInto(key, value)
	if type(ns.db) ~= "table" then return end
	local cur = ns.db[key]
	if type(value) == "table" and type(cur) == "table" then
		for k in pairs(cur) do cur[k] = nil end
		for k, v in pairs(Copy(value)) do cur[k] = v end
	else
		ns.db[key] = Copy(value)
	end
end

local function WantedTo(s)
	local Wa = Mod("Wanted")
	if not (Wa and type(Wa.PageId) == "function") or Wa.PageId() == s.wanted then return end
	for _ = 1, 3 do if Wa.PageId() ~= "list" and type(Wa.Back) == "function" then Wa.Back() end end
	if s.wanted == "review" then Try(Wa.OpenReview)
	elseif s.wanted == "rules" then Try(Wa.OpenRules)
	elseif s.wantedTarget then Try(Wa.OpenTarget, s.wantedTarget) end
end

-- Everything back as Snapshot found it; returns the saved keys it had to put back.
function SelfTest.Restore(s)
	local restored = {}
	if type(s) ~= "table" then return restored end
	local UI = Mod("UI")
	-- The windows the run opened.
	local A = Mod("Accord")
	if not s.frames.accord and Shown(FrameOf(A, "Frame")) then Try(A.Hide) end
	local C = Mod("Consent")
	if not s.frames.consent and Shown(FrameOf(C, "Frame")) then Try(C.Hide) end
	if UI and type(UI.CopyFrame) == "function" and not s.frames.copy then
		local f = UI.CopyFrame("selftest")
		if Shown(f) then f:Hide() end
	end
	local S = Mod("ArenaSpectate")
	if S and run and run.spectated and type(S.Close) == "function" then Try(S.Close) end
	local ui = ArenaUI()
	if ui then
		if s.arena and s.arena.route then Try(ui.RestoreRoute, s.arena.route) end
		if not (s.arena and s.arena.shown) and Try(ui.IsShown) and ui.IsShown() then Try(ui.Hide) end
	end
	-- The modules' pages.
	local CV = Mod("ChurchView")
	if CV and s.church then CV.page, CV.list, CV.window, CV.arg = s.church.page, s.church.list, s.church.window, s.church.arg end
	local W = Mod("Watch")
	if W and s.watch and type(W.Show) == "function" and (W.mode ~= s.watch.mode or W.caseKey ~= s.watch.caseKey or W.profileKey ~= s.watch.profileKey) then
		Try(W.Show, s.watch.mode, s.watch.mode == "case" and s.watch.caseKey or s.watch.profileKey)
	end
	ns.SafeCall("selftest restore wanted", WantedTo, s)
	local T = Mod("Treasury")
	if T and s.treasury and T.mode ~= s.treasury and type(T.Show) == "function" then Try(T.Show, s.treasury) end
	local K = Mod("King")
	if K and K.mode ~= s.king then K.mode = s.king end
	local PE = Mod("ProfileEdit")
	if PE and type(s.peSection) == "string" and type(PE.Section) == "function" and PE.Section() ~= s.peSection then Try(PE.SetSection, s.peSection) end
	-- The window: its tab and the Realm's page; closed when it was.
	local V = ns.Views
	if type(V) == "table" and s.realmMode and type(V.SetRealmMode) == "function" then Try(V.SetRealmMode, s.realmMode, true) end
	if type(V) == "table" and type(V.CloseChat) == "function" then Try(V.CloseChat) end
	if UI and type(UI.SelectTab) == "function" and (s.shown or (type(UI.IsShown) == "function" and UI.IsShown())) then
		Try(UI.SelectTab, s.tab or "census")
		if s.tab == "realm" and type(V) == "table" then
			local M = Mod("Members")
			if s.board then Try(V.ShowBoard, true)
			elseif s.pageShown then Try(V.ShowPage, s.pageShown)
			elseif s.members and M then Try(M.Show, s.members) end
		end
		if s.profile and type(UI.OpenPlayerProfile) == "function" then Try(UI.OpenPlayerProfile, s.profile) end
		-- (The census's own page, after its tab: opening a tab closes it.)
		local CS = Mod("CensusStats")
		if CS and s.censusStats and s.tab == "census" and not s.profile and type(UI.OpenCensusStats) == "function" then Try(UI.OpenCensusStats) end
		if not s.shown and type(UI.IsShown) == "function" and UI.IsShown() and type(UI.Toggle) == "function" then Try(UI.Toggle) end
	end
	local CS = Mod("CensusStats")
	if CS and s.censusStats == false and type(CS.Shown) == "function" and CS.Shown() == true then Try(CS.Close) end
	-- The saved keys.
	for _, k in ipairs(SelfTest.SAVED_KEYS) do
		local now = Fingerprint(type(ns.db) == "table" and ns.db[k] or nil, 1e6)
		if now ~= s.prints[k] then
			RestoreInto(k, s.db[k])
			restored[#restored + 1] = k
		end
	end
	return restored
end

-- What must be the same after the run as before: never changed by it.
function SelfTest.Invariants()
	local out = {}
	out.quiet = type(ns.QuietPresence) == "function" and ns.QuietPresence() == true
	local R = Mod("Record")
	local okR, on = Try(R and R.On)
	out.record = okR and on == true
	local a = type(ns.db) == "table" and ns.db.accord or nil
	out.accord = type(a) == "table" and (tostring(a.v) .. "|" .. tostring(a.yes) .. "|" .. tostring(a.at) .. "|" .. tostring(a.fp)) or "-"
	local s = type(ns.rdb) == "table" and rawget(ns.rdb, "chatStrikes") or nil
	local n, latest = 0, 0
	if type(s) == "table" and type(s.mine) == "table" then
		n = #s.mine
		for _, e in ipairs(s.mine) do if type(e) == "table" and type(e.untilAt) == "number" and e.untilAt > latest then latest = e.untilAt end end
	end
	out.strikes = n .. "|" .. latest
	local okM, off = Try(Mod("Moderation") and Mod("Moderation").SelfOff)
	out.selfOff = okM and off ~= nil
	local okC, cover = Try(Mod("Cover") and Mod("Cover").Active)
	out.cover = okC and cover ~= nil and cover ~= false
	return out
end

---------------------------------------------------------------------------
-- The detectors
---------------------------------------------------------------------------

local backTexts
-- Every Back the addon writes: its *_BACK lines (the short ones and those starting "<").
local function BackTexts()
	if backTexts then return backTexts end
	local t = {}
	for k, v in pairs(L) do
		if type(k) == "string" and k:find("_BACK$") and type(v) == "string" and not v:find("%", 1, true) then
			local s = Trim(Strip(v))
			if s ~= "" and (s:sub(1, 1) == "<" or #s <= 32) then t[s] = true end
		end
	end
	backTexts = t
	return t
end
local function IsBack(text)
	if type(text) ~= "string" or Secret(text) then return false end
	local s = Trim(Strip(text))
	return s:sub(1, 2) == "< " or BackTexts()[s] == true
end
SelfTest.IsBack = IsBack

local function ButtonText(b)
	if type(b) ~= "table" or type(b.GetText) ~= "function" then return nil end
	if type(b.IsShown) == "function" and not b:IsShown() then return nil end
	local ok, text = pcall(b.GetText, b)
	return ok and text or nil
end

-- How to go back from the page in `view` (its lines, its strips, its buttons), or nil.
function SelfTest.FindBack(view)
	if type(view) ~= "table" then return nil end
	for _, line in ipairs(view.lines or {}) do
		if type(line) == "table" then
			if IsBack(line.text) and type(line.onClick) == "function" then return line.onClick end
			for _, item in ipairs(type(line.nav) == "table" and line.nav or {}) do
				if type(item) == "table" and IsBack(item.text) and type(item.onClick) == "function" then return item.onClick end
			end
		end
	end
	for _, line in ipairs(view.nav or {}) do
		for _, item in ipairs(type(line) == "table" and type(line.nav) == "table" and line.nav or {}) do
			if type(item) == "table" and IsBack(item.text) and type(item.onClick) == "function" then return item.onClick end
		end
	end
	for _, list in ipairs({ view.buttons or {}, view.detailButtons or {} }) do
		for _, b in ipairs(list) do
			if IsBack(ButtonText(b)) then
				local click = type(b.GetScript) == "function" and b:GetScript("OnClick")
				if type(click) == "function" then return function() click(b, "LeftButton") end end
			end
		end
	end
	return nil
end

-- The page in `view` has a Back: a line, a strip's item or a button that says one.
function SelfTest.HasBack(view)
	if type(view) ~= "table" then return false end
	for _, line in ipairs(view.lines or {}) do
		if type(line) == "table" then
			if IsBack(line.text) then return true end
			for _, item in ipairs(type(line.nav) == "table" and line.nav or {}) do if type(item) == "table" and IsBack(item.text) then return true end end
		end
	end
	for _, line in ipairs(view.nav or {}) do
		for _, item in ipairs(type(line) == "table" and type(line.nav) == "table" and line.nav or {}) do
			if type(item) == "table" and IsBack(item.text) then return true end
		end
	end
	for _, list in ipairs({ view.buttons or {}, view.detailButtons or {} }) do
		for _, b in ipairs(list) do if IsBack(ButtonText(b)) then return true end end
	end
	return false
end

local function ObjType(r)
	if type(r) ~= "table" or type(r.GetObjectType) ~= "function" then return nil end
	local ok, t = pcall(r.GetObjectType, r)
	return ok and t or nil
end

local function Visible(r)
	if type(r) ~= "table" then return false end
	if type(r.IsVisible) == "function" then return r:IsVisible() == true end
	return type(r.IsShown) == "function" and r:IsShown() == true
end

local PARCHMENT_FILES
local function FilePath(p) return (p:gsub("/", "\\"):gsub("%.%w+$", "")):lower() end
local function ParchmentFile(path)
	if type(path) ~= "string" or Secret(path) then return false end
	if not PARCHMENT_FILES then
		PARCHMENT_FILES = {}
		local UI = Mod("UI")
		for _, p in ipairs(UI and type(UI.PARCHMENTS) == "table" and UI.PARCHMENTS or {}) do PARCHMENT_FILES[FilePath(p)] = true end
	end
	return PARCHMENT_FILES[FilePath(path)] == true
end

-- A frame's parchment: its own paper (the letters' f.paper, a page's parchment) shown, or a
-- texture of the game's parchment among its parts; that region, else nil.
local function PaperOf(f, regions)
	for _, key in ipairs({ "paper", "parchment" }) do
		local p = type(f) == "table" and rawget(f, key)
		if type(p) == "table" and Shown(p) then return p end
	end
	for _, r in ipairs(regions) do
		if ObjType(r) == "Texture" and Shown(r) then
			for _, getter in ipairs({ "GetTextureFilePath", "GetTexture" }) do
				local ok, path = Try(r[getter], r)
				if ok and ParchmentFile(path) then return r end
			end
		end
	end
	return nil
end

-- A font string drawn on that parchment: its centre inside the paper (true when either can't say:
-- the window's own title over its metal is not on the paper).
local function OnPaper(fs, paper)
	if paper == true then return true end
	if not paper then return false end
	local okC, x, y = Try(fs.GetCenter, fs)
	local okR, l, b, w, h = Try(paper.GetRect, paper)
	if not (okC and okR) or type(x) ~= "number" or type(y) ~= "number" or type(l) ~= "number" or type(b) ~= "number"
		or type(w) ~= "number" or type(h) ~= "number" or Secret(x) or Secret(y) or Secret(l) or Secret(b) or Secret(w) or Secret(h) then return true end
	return x >= l and x <= l + w and y >= b and y <= b + h
end

-- Every font string under `root` (at most REGIONS_MAX parts, DEPTH_MAX deep): { fs, paper, button, path }.
function SelfTest.FontStrings(root)
	local out, count = {}, 0
	local stack = { { f = root, depth = 0, paper = nil, button = false, path = "f" } }
	while #stack > 0 and count < SelfTest.REGIONS_MAX do
		local e = table.remove(stack)
		local regions = SelfTest.Regions(e.f)
		local paper = PaperOf(e.f, regions) or e.paper
		local button = e.button or ObjType(e.f) == "Button"
		for i, r in ipairs(regions) do
			count = count + 1
			if ObjType(r) == "FontString" then out[#out + 1] = { fs = r, paper = paper, button = button, path = e.path .. ".r" .. i } end
		end
		if e.depth < SelfTest.DEPTH_MAX then
			for i, c in ipairs(SelfTest.Children(e.f)) do
				count = count + 1
				stack[#stack + 1] = { f = c, depth = e.depth + 1, paper = paper, button = button, path = e.path .. ".c" .. i }
			end
		end
	end
	return out
end

-- A surface's font strings: the Olympus window's rows (its parchment for all of them), or a
-- window's parts walked.
local function SurfaceStrings(surface)
	if type(surface.strings) == "table" then return surface.strings end
	return SelfTest.FontStrings(surface.frame)
end

-- The text's runs of visible letters, each with its colour: { r, g, b, n }; base: the font
-- string's own colour (nil when the client gives none).
local function Runs(text, base)
	local runs, cur, n = {}, base, 0
	local function Close() if n > 0 then runs[#runs + 1] = { cur, n } end n = 0 end
	local i, len = 1, #text
	while i <= len do
		local c = text:sub(i, i)
		if c == "|" then
			local nx = text:sub(i + 1, i + 1)
			if nx == "c" and text:match("^|c%x%x%x%x%x%x%x%x", i) then
				Close()
				local hex = text:sub(i + 4, i + 9)
				cur = { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255 }
				i = i + 10
			elseif nx == "r" then
				Close()
				cur, i = base, i + 2
			elseif nx == "T" or nx == "A" then
				local e = text:find(nx == "T" and "|t" or "|a", i + 2, true)
				i = e and e + 2 or len + 1
			elseif nx == "H" then
				local e = text:find("|h", i + 2, true)
				i = e and e + 2 or len + 1
			elseif nx == "|" then
				n, i = n + 1, i + 2
			else
				i = i + 2
			end
		elseif c:match("%s") then
			i = i + 1
		else
			n, i = n + 1, i + 1
		end
	end
	Close()
	return runs
end

-- Light text on parchment: { checked, light, where = { up to 5 places } }.
function SelfTest.Ink(surface)
	local out = { checked = 0, light = 0, where = {} }
	if type(surface) ~= "table" then return out end
	for _, e in ipairs(SurfaceStrings(surface)) do
		local paper = surface.paper == true or (e.paper ~= nil and OnPaper(e.fs, e.paper))
		if paper and not e.button and Visible(e.fs) then
			local okText, text = Try(e.fs.GetText, e.fs)
			if okText and type(text) == "string" and not Secret(text) and text ~= "" then
				out.checked = out.checked + 1
				local base
				if type(e.fs.GetTextColor) == "function" then
					local ok, r, g, b = pcall(e.fs.GetTextColor, e.fs)
					if ok and type(r) == "number" and not Secret(r) and not Secret(g) and not Secret(b) then base = { r, g, b } end
				end
				local light = false
				for _, run in ipairs(Runs(text, base)) do
					local c = run[1]
					if c and run[2] >= 3 and SelfTest.Luma(c[1], c[2], c[3]) > SelfTest.LIGHT_LUMA then light = true end
				end
				if light then
					out.light = out.light + 1
					if #out.where < 5 then out.where[#out.where + 1] = e.path end
				end
			end
		end
	end
	return out
end

local function Edges(r)
	if type(r) ~= "table" or type(r.GetLeft) ~= "function" or type(r.GetRight) ~= "function" then return nil end
	local ok, l = pcall(r.GetLeft, r)
	local ok2, rt = pcall(r.GetRight, r)
	if ok and ok2 and type(l) == "number" and type(rt) == "number" and not Secret(l) and not Secret(rt) then return l, rt end
	return nil
end

-- Text past its surface's edges by more than OVERFLOW_PX: { checked, over, truncated, where }.
function SelfTest.Overflow(surface)
	local out = { checked = 0, over = 0, truncated = 0, where = {} }
	if type(surface) ~= "table" then return out end
	local cl, cr = Edges(surface.clip or surface.frame)
	for _, e in ipairs(SurfaceStrings(surface)) do
		if Visible(e.fs) then
			local okText, text = Try(e.fs.GetText, e.fs)
			if okText and type(text) == "string" and not Secret(text) and text ~= "" then
				out.checked = out.checked + 1
				local l, r = Edges(e.fs)
				if cl and l and (l < cl - SelfTest.OVERFLOW_PX or r > cr + SelfTest.OVERFLOW_PX) then
					out.over = out.over + 1
					if #out.where < 5 then out.where[#out.where + 1] = e.path end
				end
				local okT, cut = Try(e.fs.IsTruncated, e.fs)
				if okT and cut == true then out.truncated = out.truncated + 1 end
			end
		end
	end
	return out
end

-- The Olympus window's rows as a surface.
local function MainSurface(view)
	local strings = {}
	local count = view.content and view.content.lineCount or 0
	for i, r in ipairs(view.rows or {}) do
		if i > count then break end
		if Shown(r) then
			for _, k in ipairs({ "left", "right" }) do
				if type(r[k]) == "table" then strings[#strings + 1] = { fs = r[k], path = ("row %d %s"):format(i, k) } end
			end
			for c, fs in ipairs(type(r.cols) == "table" and r.cols or {}) do strings[#strings + 1] = { fs = fs, path = ("row %d col %d"):format(i, c) } end
		end
	end
	local frame = view.frame
	return { strings = strings, paper = view.parchment == true, clip = type(frame) == "table" and frame.scroll or nil }
end

---------------------------------------------------------------------------
-- (a) The client's answers
---------------------------------------------------------------------------

local TYPE_LETTER = { string = "s", number = "n", boolean = "b", ["nil"] = "-", table = "t", ["function"] = "f", userdata = "u" }
local function RosterRow(...)
	local letters = {}
	for i = 1, 17 do
		local v = (select(i, ...))
		letters[i] = Secret(v) and "?" or (TYPE_LETTER[type(v)] or "x")
	end
	local online, class, guid = (select(9, ...)), (select(11, ...)), (select(17, ...))
	return { n = select("#", ...), letters = table.concat(letters),
		online = not Secret(online) and type(online) == "boolean",
		isOnline = not Secret(online) and online == true,
		class = not Secret(class) and type(class) == "string" and class:find("^%u+$") ~= nil,
		guid = not Secret(guid) and type(guid) == "string" and guid:find("^Player%-") ~= nil }
end

-- A unit's answer as the report keeps it: its type, "secret", or "absent".
local function UnitAnswer(fn, unit)
	if type(fn) ~= "function" then return "absent", nil end
	local ok, v = pcall(fn, unit)
	if not ok then return "error", nil end
	if Secret(v) then return "secret", v end
	return type(v), v
end

local API = {}
API[#API + 1] = { id = "api.bn", what = "BNGetInfo: its returns and secrecy, the Accord's read", fn = function(step)
	if type(BNGetInfo) ~= "function" then return P(step, "fail", "BNGetInfo absent") end
	local function Shape(...)
		local second = (select(2, ...))
		if Secret(second) then return select("#", ...), "secret", true, false end
		return select("#", ...), type(second), false, type(second) == "string" and second:find("^[^#~|%c]+#%d+$") ~= nil
	end
	local ok, n, kind, secret, shape = pcall(function() return Shape(BNGetInfo()) end)
	if not ok then return P(step, "fail", "BNGetInfo errored") end
	local readable = "?"
	local A = Mod("Accord")
	if A and type(A.ReadTag) == "function" then
		local okTag, tag, why = pcall(A.ReadTag)
		readable = (okTag and tag ~= nil) and "readable" or ("not readable (" .. tostring(okTag and why or "error") .. ")")
		tag = nil
	end
	local kindC, connected = UnitAnswer(BNConnected)
	local conn = kindC == "boolean" and tostring(connected) or kindC
	local detail = ("%d returns, 2nd %s%s; Accord: %s; BNConnected %s; BNFeaturesEnabledAndConnected %s"):format(n, kind,
		kind == "string" and (shape and " Name#digits" or " other shape") or "", readable, conn, type(BNFeaturesEnabledAndConnected))
	local result = secret and "fail" or ((kind ~= "string" or not shape or conn ~= "true") and "warn" or "ok")
	P(step, result, detail)
end }

API[#API + 1] = { id = "api.roster", what = "GetGuildRosterInfo's returns on the first rows", fn = function(step)
	local ok, total, online = Try(GetNumGuildMembers)
	if not ok or type(total) ~= "number" or Secret(total) then return P(step, "skip", "GetNumGuildMembers gave nothing") end
	if total == 0 then return P(step, "skip", "no roster rows (no guild, or the roster not loaded yet)") end
	local rows, bad = {}, {}
	for i = 1, math.min(3, total) do
		local okRow, row = pcall(function() return RosterRow(GetGuildRosterInfo(i)) end)
		if okRow then
			rows[#rows + 1] = row.n .. ":" .. row.letters
			if not row.online then bad.online = true end
			if not row.guid then bad.guid = true end
			if not row.class then bad.class = true end
		else
			bad.error = true
		end
	end
	local gr = type(C_GuildInfo) == "table" and type(C_GuildInfo.GuildRoster) or "nil"
	local detail = ("%d members (%s online); 9 online %s, 11 class %s, 17 GUID %s; C_GuildInfo.GuildRoster %s, GuildRoster %s; rows %s"):format(
		math.floor(total), Secret(online) and "?" or tostring(online), bad.online and "no" or "ok", bad.class and "no" or "ok",
		bad.guid and "no" or "ok", gr, type(GuildRoster), table.concat(rows, " "))
	P(step, (bad.online or bad.guid) and "fail" or ((bad.class or bad.error) and "warn" or "ok"), detail)
end }

API[#API + 1] = { id = "api.time", what = "GetServerTime against this computer's clock", fn = function(step)
	local ok, st = Try(GetServerTime)
	if not ok or type(st) ~= "number" or Secret(st) then return P(step, "fail", "GetServerTime: " .. (ok and type(st) or "absent")) end
	local diff = st - time()
	local D = ns.Data
	local same = type(D) == "table" and type(D.ServerTime) == "function" and D.ServerTime() == st
	P(step, math.abs(diff) > 300 and "warn" or "ok", ("server - computer %ds; Data.ServerTime %s"):format(math.floor(diff + 0.5), same and "agrees" or "differs"))
end }

API[#API + 1] = { id = "api.atlas", what = "C_Texture.GetAtlasInfo for the atlases Olympus draws", fn = function(step)
	local info = type(C_Texture) == "table" and C_Texture.GetAtlasInfo or nil
	if type(info) ~= "function" then return P(step, "warn", "C_Texture.GetAtlasInfo absent: every atlas falls back to a file") end
	local names = { ns.Views and ns.Views.PICKER_ATLAS, Mod("KingArrow") and Mod("KingArrow").NATIVE_ATLAS, "Quest-Horde-WaxSeal", "Quest-Alliance-WaxSeal",
		"nameplates-icon-elite-gold", "nameplates-icon-elite-silver", "NPE_ArrowDown", "raceicon128-human-male" }
	local missing, n = {}, 0
	for i = 1, 8 do
		local name = names[i]
		if type(name) == "string" then
			n = n + 1
			local okA, a = pcall(info, name)
			if not (okA and type(a) == "table" and tonumber(a.width) and tonumber(a.height)) then missing[#missing + 1] = name end
		end
	end
	P(step, #missing > 0 and "warn" or "ok", ("%d of %d found%s"):format(n - #missing, n, #missing > 0 and ("; missing: " .. table.concat(missing, ", ")) or ""))
end }

API[#API + 1] = { id = "api.menu", what = "the right-click menus' lines (Menu.ModifyMenu)", fn = function(step)
	local PM = Mod("PlayerMenu")
	if not PM then return P(step, "skip", "no PlayerMenu.lua in this session") end
	local okH, hooked = Try(PM.Hooked)
	local okS, line = Try(PM.StatusLine)
	P(step, (okH and hooked) and "ok" or "warn", okS and line or "no status")
end }

API[#API + 1] = { id = "api.talents", what = "the talent and inspection APIs, and this character's trees", fn = function(step)
	local have = {}
	local function Has(t, names, label)
		local n = 0
		for _, k in ipairs(names) do if type(t) == "table" and type(t[k]) == "function" then n = n + 1 end end
		have[#have + 1] = ("%s %d/%d"):format(label, n, #names)
	end
	Has(C_Traits, { "GetConfigInfo", "GetTreeNodes", "GetNodeInfo", "GetEntryInfo", "GetDefinitionInfo", "GetGroupDisplayInfoByTreeID",
		"HasValidInspectData", "GetTraitDescription" }, "C_Traits")
	Has(C_ClassTalents, { "GetActiveConfigID" }, "C_ClassTalents")
	Has(C_SpecializationInfo, { "GetSpecializationInfo", "GetTalentInfo", "GetNumSpecializationsForClassID", "GetActiveSpecGroup" }, "C_SpecializationInfo")
	local globals, list = 0, { GetTalentInfo, GetNumTalentTabs, GetNumTalents }
	for i = 1, 3 do if type(list[i]) == "function" then globals = globals + 1 end end
	have[#have + 1] = ("talent globals %d/3"):format(globals)
	local inspect = "absent"
	if type(C_Traits) == "table" and type(C_Traits.HasValidInspectData) == "function" then
		local ok, v = pcall(C_Traits.HasValidInspectData)
		inspect = ok and Bool(v) or "error"
	end
	have[#have + 1] = "inspect data " .. inspect
	local S, trees, points = Mod("ArenaSpectate"), 0, 0
	if S and type(S.ReadTalents) == "function" then
		local classID = type(UnitClass) == "function" and select(3, UnitClass("player")) or nil
		local ok, t = pcall(S.ReadTalents, "player", classID, false)
		if ok and type(t) == "table" then
			trees = #(t.trees or {})
			points = tonumber(t.total) or 0
			have[#have + 1] = ("own: %d trees, %d points (%s)"):format(trees, math.floor(points), tostring(t.source))
		else
			have[#have + 1] = "own: none read"
		end
	end
	local level = type(UnitLevel) == "function" and UnitLevel("player") or 0
	local warn = type(level) == "number" and not Secret(level) and level >= 10 and trees == 0
	P(step, warn and "warn" or "ok", table.concat(have, "; "))
end }

API[#API + 1] = { id = "api.pct", what = "UnitHealthPercent and UnitPowerPercent on yourself", fn = function(step)
	local notes, disagree = {}, false
	local S = Mod("ArenaSpectate")
	local want = S and tonumber(S.PCT_SCALE) or nil
	for _, pair in ipairs({ { "health", UnitHealthPercent, UnitHealth, UnitHealthMax }, { "power", UnitPowerPercent, UnitPower, UnitPowerMax } }) do
		local kind, v = UnitAnswer(pair[2], "player")
		if kind == "secret" then
			run.secret = run.secret or v
			notes[#notes + 1] = pair[1] .. " secret"
		elseif kind == "number" then
			local _, cur = UnitAnswer(pair[3], "player")
			local _, max = UnitAnswer(pair[4], "player")
			local scale
			if type(cur) == "number" and type(max) == "number" and max > 0 and cur > 0 then
				scale = (v / (cur / max)) > 10 and 100 or 1
			end
			notes[#notes + 1] = ("%s %s (scale %s)"):format(pair[1], tostring(Round(v, 3)), tostring(scale or "?"))
			if pair[1] == "health" and scale and want and scale ~= want then disagree = true end
		else
			notes[#notes + 1] = pair[1] .. " " .. kind
		end
	end
	notes[#notes + 1] = "ArenaSpectate.PCT_SCALE " .. tostring(want)
	P(step, disagree and "warn" or "ok", table.concat(notes, "; "))
end }

API[#API + 1] = { id = "api.target", what = "a stranger's health: secret or not", fn = function(step)
	local function Plain(fn, ...)
		if type(fn) ~= "function" then return nil end
		local ok, v = pcall(fn, ...)
		if not ok or Secret(v) then return "secret" end
		return v
	end
	local exists, isPlayer, isMe = Plain(UnitExists, "target"), Plain(UnitIsPlayer, "target"), Plain(UnitIsUnit, "target", "player")
	local party, raid = Plain(UnitInParty, "target"), Plain(UnitInRaid, "target")
	if exists == "secret" or isPlayer == "secret" or isMe == "secret" or party == "secret" or raid == "secret" then
		return P(step, "skip", "the target's own answers are secret")
	end
	if not exists or not isPlayer or isMe or party or raid then
		return P(step, "skip", "no stranger targeted (target a player outside your group for this check)")
	end
	local hpKind, hp = UnitAnswer(UnitHealth, "target")
	local maxKind = UnitAnswer(UnitHealthMax, "target")
	local pctKind, pct = UnitAnswer(UnitHealthPercent, "target")
	if hpKind == "secret" then run.secret = run.secret or hp end
	if pctKind == "secret" then run.secret = run.secret or pct end
	P(step, "ok", ("UnitHealth %s, UnitHealthMax %s, UnitHealthPercent %s"):format(hpKind, maxKind, pctKind))
end }

API[#API + 1] = { id = "api.itemstats", what = "an equipped item's stats' keys", fn = function(step)
	local getter = (type(C_Item) == "table" and C_Item.GetItemStats) or GetItemStats
	local which = (type(C_Item) == "table" and type(C_Item.GetItemStats) == "function") and "C_Item.GetItemStats" or "GetItemStats"
	if type(getter) ~= "function" then return P(step, "warn", "no GetItemStats on this client") end
	local link, slot
	for _, s in ipairs({ 5, 16, 1, 7 }) do
		local ok, l = Try(GetInventoryItemLink, "player", s)
		if ok and type(l) == "string" and not Secret(l) then link, slot = l, s break end
	end
	if not link then return P(step, "skip", "nothing equipped in slots 5, 16, 1 or 7") end
	local ok, stats = pcall(getter, link)
	if not ok or type(stats) ~= "table" then return P(step, "warn", which .. ": no stats yet for slot " .. slot .. " (not cached?)") end
	local keys, mods, res = 0, 0, 0
	for k in pairs(stats) do
		keys = keys + 1
		if type(k) == "string" and k:find("^ITEM_MOD_") then mods = mods + 1 end
		if type(k) == "string" and k:find("^RESISTANCE") then res = res + 1 end
	end
	local known = {}
	local S = Mod("ArenaSpectate")
	for _, list in ipairs({ S and S.STATS or {}, S and S.RESISTS or {} }) do
		for _, e in ipairs(list) do
			for _, k in ipairs(e.keys or {}) do if stats[k] ~= nil and #known < 8 then known[#known + 1] = k end end
		end
	end
	P(step, mods == 0 and "warn" or "ok", ("%s slot %d: %d keys, %d ITEM_MOD_, %d RESISTANCE; read: %s"):format(which, slot, keys, mods, res,
		#known > 0 and table.concat(known, ",") or "none"))
end }

API[#API + 1] = { id = "api.range", what = "CheckInteractDistance's answers", fn = function(step)
	if type(CheckInteractDistance) ~= "function" then return P(step, "warn", "CheckInteractDistance absent") end
	local out = { "player:" .. (UnitAnswer(function(u) return CheckInteractDistance(u, 1) end, "player")) }
	local okE, exists = Try(UnitExists, "target")
	if okE and not Secret(exists) and exists then
		for i = 1, 4 do out[#out + 1] = ("target %d:%s"):format(i, (UnitAnswer(function(u) return CheckInteractDistance(u, i) end, "target"))) end
	end
	P(step, "ok", table.concat(out, " "))
end }

API[#API + 1] = { id = "api.lockdown", what = "combat and chat lockdown", fn = function(step)
	local okC, combat = Try(InCombatLockdown)
	local chat = "absent"
	if type(C_ChatInfo) == "table" and type(C_ChatInfo.InChatMessagingLockdown) == "function" then
		local ok, v = pcall(C_ChatInfo.InChatMessagingLockdown)
		chat = ok and Bool(v) or "error"
	end
	local inCombat = okC and not Secret(combat) and combat == true
	P(step, (inCombat or chat == "true") and "warn" or "ok", ("InCombatLockdown %s; InChatMessagingLockdown %s"):format(okC and Bool(combat) or "absent", chat))
end }

-- (The cast is read on every frame of the run: the first one seen. Reported at the end, api.cast.)
function SelfTest.SampleCast()
	local r = run
	if not r or r.cast then return end
	local function Read(kind, ...)
		local first = ...
		if not Secret(first) and first == nil then return nil end
		local n, secrets = select("#", ...), 0
		for i = 1, n do if Secret((select(i, ...))) then secrets = secrets + 1 end end
		local six = (select(6, ...))
		local sixth = Secret(six) and "secret" or (type(six) .. (type(six) == "boolean" and (" " .. tostring(six)) or ""))
		return { kind = kind, n = n, sixth = sixth, secrets = secrets, endSecret = Secret((select(5, ...))) }
	end
	for _, pair in ipairs({ { "cast", UnitCastingInfo }, { "channel", UnitChannelInfo } }) do
		if type(pair[2]) == "function" then
			local ok, seen = pcall(function() return Read(pair[1], pair[2]("player")) end)
			if ok and seen then r.cast = seen return end
		end
	end
end

---------------------------------------------------------------------------
-- (c) The modules, read only
---------------------------------------------------------------------------

local function Count(t) local n = 0 for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end return n end
local function Age(t)
	if type(t) ~= "number" or type(ns.Now) ~= "function" then return "-" end
	local s = math.max(0, ns.Now() - t)
	if s < 120 then return math.floor(s) .. "s" end
	if s < 7200 then return math.floor(s / 60) .. "m" end
	return math.floor(s / 3600) .. "h"
end
local function KB(bytes) return ("%.1f KB"):format((tonumber(bytes) or 0) / 1024) end

local function Previous()
	local r = type(ns.db) == "table" and ns.db.selftest or nil
	local t = type(r) == "table" and type(r.trend) == "table" and r.trend or {}
	return t[#t]
end

-- The values in a plain table and how deep it goes.
local function Measure(v, depth, out)
	out = out or { values = 0, depth = 0, strings = {} }
	depth = depth or 0
	if depth > out.depth then out.depth = depth end
	if type(v) == "table" then
		for _, x in pairs(v) do Measure(x, depth + 1, out) end
	else
		out.values = out.values + 1
		if type(v) == "string" and #out.strings < 3000 then out.strings[#out.strings + 1] = v end
	end
	return out
end

-- The player's own BattleTag, read for this moment's comparison and never kept: true when it is
-- in one of `texts`.
local function TagIn(texts)
	local A = Mod("Accord")
	local ok, tag = Try(A and A.ReadTag)
	if not ok or type(tag) ~= "string" or Secret(tag) then return nil end
	local digits = tag:match("(#%d+)$")
	for _, s in ipairs(texts) do
		if type(s) == "string" and (s:find(tag, 1, true) or (digits and s:find(digits, 1, true))) then return true end
	end
	return false
end

local MOD = {}
MOD[#MOD + 1] = { id = "mod.record", what = "record mode: on, sessions, its chains", fn = function(step)
	local R = Mod("Record")
	if not R then return P(step, "skip", "not in this build") end
	local db = rawget(_G, "OlympusRecordDB")
	local sessions, lines, bytes = 0, 0, 0
	if type(db) == "table" and type(db.sessions) == "table" then
		sessions = #db.sessions
		for _, s in ipairs(db.sessions) do
			for _, line in ipairs(type(s) == "table" and type(s.lines) == "table" and s.lines or {}) do
				lines = lines + 1
				bytes = bytes + (type(line) == "string" and #line or 0)
			end
		end
	end
	local okOn, on = Try(R.On)
	local okRec, recording = Try(R.Recording)
	local okText = Try(R.StatusText)
	local detail = ("on %s, recording %s, %d sessions, %d lines, %s; status %s"):format(Bool(okOn and on), Bool(okRec and recording), sessions, lines, KB(bytes),
		okText and "builds" or "fails")
	if type(R.VerifyFile) ~= "function" or type(db) ~= "table" then return P(step, okText and "ok" or "fail", detail) end
	if bytes > SelfTest.RECORD_VERIFY_MAX_BYTES then return P(step, okText and "ok" or "fail", detail .. "; verify with record-check over SSH") end
	local ok, v = pcall(R.VerifyFile, db)
	if not ok or type(v) ~= "table" then return P(step, "fail", detail .. "; verify errored") end
	P(step, v.ok and "ok" or "fail", ("%s; verify %s, %d conflicts, %d duplicates"):format(detail, v.ok and "ok" or "failed", #(v.conflicts or {}), tonumber(v.duplicates) or 0))
end }

MOD[#MOD + 1] = { id = "mod.accord", what = "the Olympus Accord's state", fn = function(step)
	local A = Mod("Accord")
	if not A then return P(step, "fail", "Accord.lua not loaded: restart the game") end
	local accepted = type(ns.AccordAccepted) == "function" and ns.AccordAccepted() == true
	local okS, line = Try(A.StatusLine)
	local okT, team = Try(A.TeamMember)
	P(step, accepted and "ok" or "warn", ("accepted %s, team %s; %s"):format(tostring(accepted), Bool(okT and team), okS and line or "no status"))
end }

MOD[#MOD + 1] = { id = "mod.strikes", what = "the chat warnings' list and counts", fn = function(step)
	local S = Mod("ChatStrikes")
	if not S then return P(step, "skip", "ChatStrikes.lua not loaded") end
	local okS, stats = Try(S.Stats)
	P(step, "ok", ("%d digests; %s"):format(Count(S.LIST), okS and Pairs(stats) or "no stats"))
end }

MOD[#MOD + 1] = { id = "mod.quiet", what = "quiet presence and cover names", fn = function(step)
	local okQ, q = Try(ns.QuietPresenceState)
	local on = okQ and type(q) == "table" and q.on == true
	local C = Mod("Cover")
	local cover = "not in this build"
	if C then
		local okC, active = Try(C.Active)
		cover = okC and ((active and active ~= false) and "on" or "off") or "no state"
	end
	P(step, "ok", ("quiet presence %s%s; cover %s"):format(on and "on" or "off", on and (" for " .. Age(q.since)) or "", cover))
end }

MOD[#MOD + 1] = { id = "mod.api", what = "what the Olympus API says it has", fn = function(step)
	local A = Mod("API")
	local has = A and A.Has or (type(OlympusAPI) == "table" and OlympusAPI.Has) or nil
	if type(has) ~= "function" then return P(step, "fail", "no API.Has") end
	local features = { "wanted", "rankings", "rankings.slayers", "rankings.donors", "rankings.church", "rankings.games", "profile", "leader",
		"network.sightings", "network.sightings.area-scope", "network.profile-effects", "presence.quiet", "ui.guild-tools", "ui.surface", "callbacks" }
	for _, e in ipairs(A and type(A.EVENTS) == "table" and A.EVENTS or {}) do features[#features + 1] = e end
	local missing, n = {}, 0
	for _, f in ipairs(features) do
		local ok, yes = pcall(has, f)
		if ok and yes == true then n = n + 1 elseif f ~= "rankings.games" then missing[#missing + 1] = f end
	end
	P(step, #missing > 0 and "warn" or "ok", ("%d of %d%s"):format(n, #features, #missing > 0 and ("; no: " .. table.concat(missing, ", ")) or ""))
end }

-- (A type's index is worked out at its first need, each record hashed: one type a frame.)
MOD[#MOD + 1] = { id = "mod.records", what = "the shared records per type", fn = function(step)
	local R = Mod("Records")
	if not (R and type(R.TYPES) == "table") then return P(step, "skip", "Records.lua not loaded") end
	local out, byType, steps = {}, {}, {}
	for _, letter in ipairs(SortedKeys(R.TYPES)) do
		steps[#steps + 1] = Step("mod.records." .. letter, "mod", "one type of the shared records", function()
			local okC, n = Try(R.Count, letter)
			local okP, pend = Try(R.Pending, letter)
			local okX, clashes = Try(R.Clashes, letter)
			n = okC and tonumber(n) or 0
			byType[letter] = n
			out[#out + 1] = ("%s %d/%d/%d"):format(letter, n, okP and tonumber(pend) or 0, okX and type(clashes) == "table" and #clashes or 0)
		end, { heavy = true })
	end
	steps[#steps + 1] = Step("mod.records", "mod", step.what, function(last)
		run.recordsByType = byType
		P(last, "ok", "held/pending/clashes: " .. (#out > 0 and table.concat(out, ", ") or "none"))
	end)
	Insert(steps)
end }

MOD[#MOD + 1] = { id = "mod.church", what = "the Church's numbers and its ledger", heavy = true, fn = function(step)
	local Church, Cnt = Mod("Church"), Mod("ChurchCount")
	if not (Church and Cnt) then return P(step, "skip", "the Church is not loaded") end
	local okS, stats = Try(Church.Stats)
	local records, people, archived, gone
	local okL, lines = Try(Cnt.StatusLines)
	if okL and type(lines) == "table" then
		for _, line in ipairs(lines) do
			local a, b, c, d = tostring(line):match("ledger (%d+) records, (%d+) people, (%d+) archived, (%d+) let go")
			if a then records, people, archived, gone = tonumber(a), tonumber(b), tonumber(c), tonumber(d) end
		end
	end
	run.church = { records = records, people = people }
	local okK, keepers = Try(Church.KeepersOnline, false)
	local okR, relays = Try(Church.LedgerRelaysOnline, false)
	local okSet, settled = Try(Cnt.Settled)
	local okSL, since = Try(Cnt.SettledSinceLogin)
	local prev, dropped = Previous(), {}
	if prev and records and prev.churchRecords and records < prev.churchRecords then dropped[#dropped + 1] = ("records %d -> %d"):format(prev.churchRecords, records) end
	if prev and people and prev.churchPeople and people < prev.churchPeople then dropped[#dropped + 1] = ("people %d -> %d"):format(prev.churchPeople, people) end
	P(step, #dropped > 0 and "warn" or "ok", ("ledger %s records, %s people, %s archived, %s let go; settled %s (since login %s); keepers %d, relays %d%s"):format(
		tostring(records or "?"), tostring(people or "?"), tostring(archived or "?"), tostring(gone or "?"), Bool(okSet and settled), Bool(okSL and since),
		okK and #(keepers or {}) or -1, okR and #(relays or {}) or -1, #dropped > 0 and ("; dropped since last run: " .. table.concat(dropped, ", ")) or ""))
	Add("mod.church.stats", "mod", "Church.Stats()", okS and "ok" or "warn", okS and Pairs(stats) or "no stats")
	local views = {}
	for _, list in ipairs({ "a", "m", "c" }) do
		for _, window in ipairs({ "w", "m", "a" }) do
			local ok, rows, asOf, remote = Try(Cnt.RankingView, list, window)
			if ok and type(rows) == "table" then
				local joins = 0
				for _, row in ipairs(rows) do joins = joins + (tonumber(row.joins) or 0) end
				local top = rows[1] and (tonumber(rows[1].score) or tonumber(rows[1].average)) or nil
				views[#views + 1] = ("%s%s %d/%s/%d/%s%s"):format(list, window, #rows, top and tostring(Round(top)) or "-", joins, Age(asOf), remote and "r" or "")
			end
		end
	end
	Add("mod.church.views", "mod", "rows/top/joins/age per list and window", "ok", table.concat(views, " ") .. "; catching-up line " ..
		(rawget(L, "CHURCH_ASOF_CATCHING") and "in" or "not in") .. " this build")
end }

MOD[#MOD + 1] = { id = "mod.census", what = "the census's totals", heavy = true, fn = function(step)
	local D = ns.Data
	local ok, s = Try(D and D.Summary)
	if not ok or type(s) ~= "table" then return P(step, "fail", "Data.Summary failed") end
	run.census = { people = tonumber(s.total), characters = tonumber(s.characters) }
	local okR, rebuilding = Try(D.Rebuilding)
	local prev = Previous()
	local change = ""
	if prev and prev.people and s.total then change = ("; since last run %+d people, %+d characters"):format(s.total - prev.people, (s.characters or 0) - (prev.characters or 0)) end
	P(step, "ok", ("%d characters, %d people, %d alts, %d online, %d guilds (%d fresh), newest report %s ago; rebuilding %s%s"):format(
		tonumber(s.characters) or 0, tonumber(s.total) or 0, tonumber(s.alts) or 0, tonumber(s.online) or 0, #(s.guilds or {}), tonumber(s.fresh) or 0,
		Age(s.newest), okR and tostring(rebuilding or false) or "?", change))
end }

-- Each section its own frame (the census's can be large), then the whole: within the limits, and
-- no BattleTag in any of them. Nothing is saved.
MOD[#MOD + 1] = { id = "mod.bridge", what = "the Companion file's sections, each within its limits", fn = function(step)
	local B = type(OlympusBridge) == "table" and OlympusBridge or nil
	if not (B and type(B.Sections) == "function" and type(B.GetSection) == "function") then return P(step, "skip", "no OlympusBridge") end
	local limits = type(B.SECTION_LIMITS) == "table" and B.SECTION_LIMITS or { values = 1500, depth = 5 }
	local acc = { out = {}, over = false, texts = {}, names = {} }
	local steps = {}
	for _, e in ipairs(B.Sections() or {}) do
		local name = tostring(e.name)
		acc.names[#acc.names + 1] = name
		steps[#steps + 1] = Step("mod.bridge." .. name, "mod", "one section of the Companion file", function()
			local t0 = SelfTest.Clock()
			local ok, sec = pcall(B.GetSection, name)
			local ms = SelfTest.Clock() - t0
			if not (ok and type(sec) == "table") then acc.out[#acc.out + 1] = name .. " none" return end
			local m = Measure(sec.data)
			for _, text in ipairs(m.strings) do if #acc.texts < 6000 then acc.texts[#acc.texts + 1] = text end end
			local within = m.values <= (limits.values or 1500) + 1 and m.depth <= (limits.depth or 5) + 1
			if not within then acc.over = true end
			acc.out[#acc.out + 1] = ("%s %dv d%d %dms%s"):format(name, m.values, m.depth, math.floor(ms + 0.5), within and "" or " OVER")
		end, { heavy = true })
	end
	steps[#steps + 1] = Step("mod.bridge", "mod", step.what, function(last)
		run.leaks.bridge = TagIn(acc.texts)
		run.bridge = acc.names
		P(last, (acc.over or run.leaks.bridge) and "fail" or "ok", (#acc.out > 0 and table.concat(acc.out, ", ") or "no sections")
			.. (run.leaks.bridge and "; the BattleTag is in them" or ""))
	end)
	Insert(steps)
end }

MOD[#MOD + 1] = { id = "mod.partyguard", what = "the Party Guard", fn = function(step)
	local G = Mod("PartyGuard")
	if not G then return P(step, "skip", "PartyGuard.lua not loaded") end
	local okE, on = Try(G.Enabled)
	local okK, king = Try(G.KingOnline)
	local okC, list = Try(G.Candidates)
	P(step, "ok", ("enabled %s, King online %s, %d candidates"):format(Bool(okE and on), Bool(okK and king), okC and #(list or {}) or -1))
end }

MOD[#MOD + 1] = { id = "mod.gate", what = "the gamepad gate, the profiler, the language", fn = function(step)
	local okG, gate = Try(ns.Gate and ns.Gate.StatusLine)
	local Perf = Mod("Perf")
	local okP, perf = Try(Perf and Perf.IsOn)
	local okL, lang = Try(ns.LocaleReport)
	P(step, "ok", ("perf %s; %s; %s"):format(okP and tostring(perf) or "absent", okL and lang or "?", okG and gate or "no gate"))
end }

-- The saved variables' size, key by key: walked a few milliseconds a frame.
local function Bytes(v)
	local t = type(v)
	if t == "string" then return #v + 3 end
	if t == "number" then return 8 end
	if t == "boolean" then return 5 end
	return 2
end
MOD[#MOD + 1] = { id = "mod.saved", what = "OlympusDB's size per top-level key", fn = function(step)
	local w = step.walk
	if not w then
		w = { keys = SortedKeys(ns.db), ki = 0, stack = {}, seen = {}, nodes = 0, sizes = {}, total = 0 }
		if type(rawget(_G, "OlympusRecordDB")) == "table" then w.keys[#w.keys + 1] = "(OlympusRecordDB)" end
		step.walk = w
	end
	local started = SelfTest.Clock()
	while true do
		if #w.stack == 0 then
			w.ki = w.ki + 1
			local k = w.keys[w.ki]
			if k == nil then break end
			w.cur = k
			w.sizes[k] = { nodes = 0, bytes = 0 }
			local v
			if k == "(OlympusRecordDB)" then v = rawget(_G, "OlympusRecordDB") elseif k ~= "selftest" then v = ns.db[k] end
			if type(v) == "table" then w.stack[1] = v else w.sizes[k].bytes = Bytes(v) end
		else
			local t = table.remove(w.stack)
			local acc = w.sizes[w.cur]
			if not w.seen[t] then
				w.seen[t] = true
				for k, v in pairs(t) do
					acc.nodes, acc.bytes = acc.nodes + 1, acc.bytes + Bytes(k) + Bytes(v)
					if type(v) == "table" then w.stack[#w.stack + 1] = v end
				end
				w.nodes = w.nodes + Count(t)
			end
		end
		if w.nodes >= SelfTest.WALK_NODES_MAX then w.capped = true break end
		if SelfTest.Clock() - started > SelfTest.BUDGET_MS then return "again" end
	end
	local list, total = {}, 0
	for k, s in pairs(w.sizes) do list[#list + 1] = { k = k, bytes = s.bytes, nodes = s.nodes }; total = total + s.bytes end
	table.sort(list, function(a, b) if a.bytes ~= b.bytes then return a.bytes > b.bytes end return a.k < b.k end)
	local parts = {}
	for i = 1, math.min(15, #list) do parts[i] = ("%s %s"):format(list[i].k, KB(list[i].bytes)) end
	P(step, w.capped and "warn" or "ok", ("total %s in %d values%s; %s"):format(KB(total), w.nodes, w.capped and " (stopped at the cap)" or "",
		table.concat(parts, ", ", 1, math.min(5, #parts))))
	if #parts > 5 then Add("mod.saved.2", "mod", "the next keys by size", "ok", table.concat(parts, ", ", 6, math.min(10, #parts))) end
	if #parts > 10 then Add("mod.saved.3", "mod", "the next keys by size", "ok", table.concat(parts, ", ", 11, #parts)) end
end }

---------------------------------------------------------------------------
-- Build probes
---------------------------------------------------------------------------

local function Meta(addon, field)
	local AO = C_AddOns
	local get = type(AO) == "table" and AO.GetAddOnMetadata or nil
	local ok, v = Try(get, addon, field)
	return ok and v or nil
end

local function BuildInfo()
	local W = Mod("Workshop")
	local tb = W and type(W.TestBuild) == "function" and W.TestBuild() or nil
	local AO = C_AddOns
	local okL, loaded = Try(type(AO) == "table" and AO.IsAddOnLoaded or nil, "Olympus_Arena")
	return { version = ns.VERSION, test = tb and tb.n, base = tb and tb.base, commit = tb and tb.commit and Clip(tb.commit, 24),
		expires = tb and tb.expires, toc = Meta("Olympus", "Version"), arena = Meta("Olympus_Arena", "Version"), arenaLoaded = okL and loaded == true }
end

local function ClientInfo()
	local version, build, _, toc = "?", "?", nil, nil
	if type(GetBuildInfo) == "function" then version, build, _, toc = GetBuildInfo() end
	local W = Mod("Workshop")
	local okScale, scale = pcall(function() return UIParent:GetEffectiveScale() end)
	local okW, sw = Try(GetScreenWidth)
	local okH, sh = Try(GetScreenHeight)
	return { flavor = W and type(W.Client) == "function" and W.Client() or "?", interface = tonumber(toc), build = tostring(build), gameVersion = tostring(version),
		locale = type(GetLocale) == "function" and GetLocale() or "?", uiScale = okScale and Round(scale, 3) or nil,
		screenW = okW and Round(sw) or nil, screenH = okH and Round(sh) or nil }
end

-- The markers of the parts built beside this one: which of them this build has.
function SelfTest.Features()
	local UI, CW = Mod("UI"), Mod("ChatWindow")
	local B = type(OlympusBridge) == "table" and OlympusBridge or nil
	local bridgeSelf = false
	for _, e in ipairs(B and type(B.Sections) == "function" and B.Sections() or {}) do if e.name == "self" then bridgeSelf = true end end
	local text = rawget(L, "ACCORD_T1_1")
	local fp = "-"
	if type(text) == "string" then
		local S = Mod("Sign")
		local ok, h = Try(S and S.SHA256, text)
		local words = {}
		for word in Strip(text):gmatch("%S+") do
			words[#words + 1] = word
			if #words == 3 then break end
		end
		fp = (ok and type(h) == "string" and (h:sub(1, 4):gsub(".", function(c) return ("%02x"):format(c:byte()) end)) or "?") .. " " .. table.concat(words, " ")
	end
	return {
		{ "record", Mod("Record") ~= nil },
		{ "census-stats", Mod("CensusStats") ~= nil and UI ~= nil and type(UI.OpenCensusStats) == "function" },
		{ "chat-reply", CW ~= nil and (type(CW.EncodeReply) == "function" or type(CW.QuoteOf) == "function") },
		{ "cover", Mod("Cover") ~= nil },
		{ "church-catchup", rawget(L, "CHURCH_ASOF_CATCHING") ~= nil },
		{ "bridge-self", bridgeSelf },
	}, fp
end

local BUILD = {}
BUILD[#BUILD + 1] = { id = "build.version", what = "the version, the test build, the TOCs", fn = function(step)
	local b = BuildInfo()
	run.build = b
	local A = Mod("Arena")
	local okE, expired = Try(A and A.Expired)
	local tocOk = b.toc == nil or b.toc == b.version or (b.test and b.toc == (b.version .. "-test." .. b.test))
	local detail = ("%s, test %s (base %s, commit %s, expires %s%s); TOC %s; Olympus_Arena %s%s"):format(tostring(b.version), tostring(b.test or "-"),
		tostring(b.base or "-"), tostring(b.commit or "-"), b.expires and date and date("%Y-%m-%d", b.expires) or "-", (okE and expired) and ", EXPIRED" or "",
		tostring(b.toc), tostring(b.arena or "absent"), b.arenaLoaded and " loaded" or "")
	P(step, not tocOk and "fail" or ((okE and expired) and "warn" or "ok"), (tocOk and "" or "files from two installs: ") .. detail)
end }

BUILD[#BUILD + 1] = { id = "build.standins", what = "files this session has not loaded (an update without a restart)", fn = function(step)
	local missing = {}
	for k, v in pairs(ns) do if type(k) == "string" and type(v) == "table" and rawget(v, "missing") == true then missing[#missing + 1] = k end end
	table.sort(missing)
	P(step, #missing > 0 and "fail" or "ok", #missing > 0 and ("restart needed: " .. table.concat(missing, ", ")) or "every file loaded")
end }

BUILD[#BUILD + 1] = { id = "build.features", what = "the parts built beside this one: in this build or not", fn = function(step)
	local list, fp = SelfTest.Features()
	local out = {}
	for _, f in ipairs(list) do out[#out + 1] = f[1] .. " " .. (f[2] and "yes" or "no") end
	run.features = table.concat(out, ", ") .. "; accord T1 " .. fp
	P(step, "ok", run.features)
end }

---------------------------------------------------------------------------
-- (b) The Olympus window, page by page
---------------------------------------------------------------------------

local Sweep = {}

local function View()
	local UI = Mod("UI")
	if not (UI and type(UI.SelfTestView) == "function") then return nil end
	local ok, v = pcall(UI.SelfTestView)
	return ok and v or nil
end

local function Redraw()
	local UI = Mod("UI")
	if UI and type(UI.Refresh) == "function" then pcall(UI.Refresh) end
end

-- The window on a tab: true, or false and why not.
local function SelectTab(key)
	local UI = Mod("UI")
	if not UI then return false, "no window" end
	local ok, why = UI.SelectTab(key)
	if ok == false then return false, "no " .. key .. " tab here (" .. tostring(why) .. ")" end
	return true
end
local function RealmFirst()
	local V = ns.Views
	if type(V) == "table" and type(V.CloseChat) == "function" then V.CloseChat() end
	return SelectTab("realm")
end
-- (The page shown is the tab's: a tab hidden for this character shows the Census instead.)
local function OnTab(key) return function() return PageKey():sub(1, #key + 1) == key .. "/" end end

local function Sends(step)
	local out = {}
	for k in pairs(step.sends or {}) do out[#out + 1] = k end
	table.sort(out)
	return table.concat(out, ", ")
end

-- What a page shows now: its errors, its Back, its ink, its text's room.
function Sweep.Examine(step, key, needsBack)
	local view = View() or {}
	local res = { errors = #step.errors + math.max(0, AllErrors() - (step.errBase or 0)), first = step.errors[1] and step.errors[1].msg or nil }
	if needsBack and not SelfTest.HasBack(view) then
		res.noBack = true
		Note(run.noBack, SafeId(key))
	end
	local surface = MainSurface(view)
	res.ink = SelfTest.Ink(surface)
	res.over = SelfTest.Overflow(surface)
	if res.ink.light > 0 then Note(run.lightInk, ("%s (%d: %s)"):format(SafeId(key), res.ink.light, table.concat(res.ink.where, ", "))) end
	if res.over.over > 0 then Note(run.overflow, ("%s (%d: %s)"):format(SafeId(key), res.over.over, table.concat(res.over.where, ", "))) end
	-- The tooltips of its lines, for their own step.
	local tips = {}
	for _, line in ipairs(view.lines or {}) do
		if type(line) == "table" and type(line.tooltip) == "function" and #tips < SelfTest.TOOLTIPS_PER_PAGE then tips[#tips + 1] = line.tooltip end
	end
	for _, line in ipairs(view.nav or {}) do
		for _, item in ipairs(type(line) == "table" and type(line.nav) == "table" and line.nav or {}) do
			if type(item.tooltip) == "function" and #tips < SelfTest.TOOLTIPS_PER_PAGE then tips[#tips + 1] = item.tooltip end
		end
	end
	res.tips = tips
	res.view = view
	run.pages = run.pages + 1
	run.seen[key] = true
	return res
end

-- Its Back clicked: the page must change, and to the page the link was on (origin, when known).
function Sweep.TryBack(step, key, res, origin)
	local click = SelfTest.FindBack(res.view)
	if not click then return end
	local ok = pcall(click)
	Redraw()
	local now = PageKey()
	if not ok or now == key then
		res.brokenBack = true
		Note(run.brokenBack, SafeId(key))
	elseif origin and now ~= origin then
		res.wrongBack = SafeId(now)
		Note(run.wrongBack, SafeId(key) .. " -> " .. SafeId(now))
	end
end

function Sweep.Report(step, key, res)
	local notes = {}
	if res.errors > 0 then notes[#notes + 1] = ("%d error%s: %s"):format(res.errors, res.errors > 1 and "s" or "", tostring(res.first or "(raised)")) end
	if res.noBack then notes[#notes + 1] = "no Back" end
	if res.brokenBack then notes[#notes + 1] = "its Back stays" end
	if res.wrongBack then notes[#notes + 1] = "its Back leads to " .. res.wrongBack end
	if res.ink.light > 0 then notes[#notes + 1] = ("light ink x%d"):format(res.ink.light) end
	if res.over.over > 0 then notes[#notes + 1] = ("past the edge x%d"):format(res.over.over) end
	local sends = Sends(step)
	if sends ~= "" then notes[#notes + 1] = "would send: " .. sends end
	local result = (res.errors > 0 or res.brokenBack) and "fail"
		or ((res.noBack or res.wrongBack or res.ink.light > 0 or res.over.over > 0) and "warn" or "ok")
	P(step, result, SafeId(key) .. (#notes > 0 and (": " .. table.concat(notes, "; ")) or (" (" .. res.over.checked .. " texts" .. (res.ink.checked > 0 and (", " .. res.ink.checked .. " on parchment") or "") .. ")")))
end

-- Each tooltip called with a stand-in tooltip that draws nothing.
local function FakeTip()
	return setmetatable({}, { __index = function(_, k)
		if k == "NumLines" or k == "GetWidth" or k == "GetHeight" then return function() return 0 end end
		if k == "IsShown" or k == "IsOwned" or k == "IsForbidden" then return function() return false end end
		if k == "GetName" then return function() return "OlympusSelfTestTooltip" end end
		return function() end
	end })
end
function Sweep.Tooltips(key, tips)
	return Step("ui.tooltips." .. SafeId(key), "ui", "the page's tooltips", function(step)
		local t = run.tooltips
		for _, fn in ipairs(tips) do
			t.calls = t.calls + 1
			local ok, err = pcall(fn, FakeTip())
			if not ok then
				t.errors = t.errors + 1
				Note(t.pages, SafeId(key))
				t.first = t.first or ErrText(err, 80)
			end
		end
	end)
end

-- The items of the page's navigation strips (pageNav: the window moves them out of the list): the
-- tab's other pages, one click away. Never a strip inside the list (its items may act: a filter, a
-- payment), never a picker's list.
function Sweep.Siblings(view)
	local out = {}
	for _, line in ipairs(view.nav or {}) do
		for _, item in ipairs(type(line) == "table" and type(line.nav) == "table" and line.nav or {}) do
			if type(item) == "table" and type(item.onClick) == "function" and not item.selected and not item.picker and not IsBack(item.text) then out[#out + 1] = item end
		end
	end
	return out
end
-- The page links (a Realm page's, a ranking's rules).
function Sweep.Links(view)
	local out = {}
	for _, line in ipairs(view.lines or {}) do
		if type(line) == "table" and type(line.onClick) == "function"
			and (line.pageLink or (type(line.id) == "string" and line.id:find("^ranking%-rules:") ~= nil)) then out[#out + 1] = line end
	end
	return out
end

-- The page a link was on, shown again: as it is, by its own way in, or by that way in after
-- another tab (a page left without a Back stays its tab's page until another tab is opened).
local function Reopen(origin)
	if PageKey() == origin.key then return true end
	pcall(origin.open)
	Redraw()
	if PageKey() == origin.key then return true end
	local UI = Mod("UI")
	local other = origin.key:sub(1, 7) == "census/" and "decrees" or "census"
	if UI and pcall(UI.SelectTab, other) then
		pcall(origin.open)
		Redraw()
	end
	return PageKey() == origin.key
end

local function Link(stepId, origin, line)
	return Step(stepId, "ui", "a page a link opens", function(step)
		if not Reopen(origin) then return P(step, "skip", "could not open " .. SafeId(origin.key) .. " again") end
		local ok, err = pcall(line.onClick)
		if not ok then return P(step, "fail", SafeId(origin.key) .. ": its link errored: " .. ErrText(err)) end
		Redraw()
		local key = PageKey()
		if key == origin.key then return P(step, "warn", SafeId(origin.key) .. ": a link opened no other page") end
		if run.seen[key] then
			local back = SelfTest.FindBack(View())
			if back then pcall(back) Redraw() end
			return
		end
		local res = Sweep.Examine(step, key, true)
		Sweep.TryBack(step, key, res, origin.key)
		Sweep.Report(step, key, res)
		Insert({ Sweep.Tooltips(key, res.tips) })
	end, { heavy = true })
end

-- After the strip's other pages, the one it had selected first, selected again (a page kept in
-- its module alone, as the crafters' board's: the snapshot does not know it).
local function Reselect(tab, text)
	return Step("ui.nav." .. tab .. ".again", "ui", "the tab's first page again", function()
		if type(text) ~= "string" or not SelectTab(tab) then return end
		for _, line in ipairs((View() or {}).nav or {}) do
			for _, item in ipairs(type(line) == "table" and type(line.nav) == "table" and line.nav or {}) do
				if type(item) == "table" and item.text == text and type(item.onClick) == "function" then
					pcall(item.onClick)
					Redraw()
					return
				end
			end
		end
	end, { heavy = true })
end

-- A page opened by open() (true, or false and why not here); opts: needsBack, rendered (open drew
-- the window itself), expect() (false: the page is not this player's), expand: "tab" (its strip's
-- other pages, its links) or "page" (its links).
function Sweep.Visit(stepId, open, opts)
	opts = opts or {}
	return Step(stepId, "ui", opts.what or "a page", function(step)
		local ok, shown, why = pcall(open)
		if not ok then return P(step, "fail", "opening it errored: " .. ErrText(shown)) end
		if shown == false then return P(step, "skip", tostring(why or "not here for this character")) end
		if not opts.rendered then Redraw() end
		if opts.expect and not opts.expect() then return P(step, "skip", "not shown for this character (" .. SafeId(PageKey()) .. ")") end
		local key = PageKey()
		if opts.dedupe and run.seen[key] then return end
		local res = Sweep.Examine(step, key, opts.needsBack)
		local more = { Sweep.Tooltips(key, res.tips) }
		if opts.expand then
			-- Its links first, while the tab still shows this page; then the strip's other pages.
			local origin = { key = key, open = open }
			for i, line in ipairs(Sweep.Links(res.view)) do
				if i > SelfTest.LINKS_PER_PAGE then break end
				more[#more + 1] = Link(("ui.link.%s.%d"):format(SafeId(key), i), origin, line)
			end
			if opts.expand == "tab" then
				local tab, selected, siblings = opts.tab, nil, 0
				for i, item in ipairs(Sweep.Siblings(res.view)) do
					if i > SelfTest.SIBLINGS_PER_TAB then break end
					siblings = i
					more[#more + 1] = Sweep.Visit(("ui.nav.%s.%d"):format(tab, i), function()
						if not SelectTab(tab) then return false, "its tab" end
						item.onClick()
						return true
					end, { what = "another page of the tab", dedupe = true, expand = "page" })
				end
				for _, line in ipairs(res.view.nav or {}) do
					for _, item in ipairs(type(line) == "table" and type(line.nav) == "table" and line.nav or {}) do
						if type(item) == "table" and item.selected and not selected then selected = item.text end
					end
				end
				if siblings > 0 then more[#more + 1] = Reselect(tab, selected) end
			end
		end
		if opts.needsBack then Sweep.TryBack(step, key, res) end
		Sweep.Report(step, key, res)
		Insert(more)
	end, { heavy = true })
end


local function FirstRosterMate()
	local ok, total = Try(GetNumGuildMembers)
	if not ok or type(total) ~= "number" or Secret(total) then return nil end
	for i = 1, math.min(total, 100) do
		local okRow, name, _, _, _, _, _, _, _, online = pcall(GetGuildRosterInfo, i)
		if okRow and type(name) == "string" and not Secret(name) and not Secret(online) and online == true
			and type(ns.Fold) == "function" and ns.Fold(ns.FullName(name)) ~= ns.Fold(ns.me) then return name end
	end
	return nil
end

-- The pages reached otherwise than by a tab's strip or a link: opened by their own module's
-- function. A file that adds such a page adds its line here, or to ns.SelfTestOpeners before
-- this file loads (the same { id, back, open, rendered, tab } shape).
SelfTest.OPENERS = {
	{ id = "church-detail", back = true, rendered = true, open = function()
		local CV, Cnt = Mod("ChurchView"), Mod("ChurchCount")
		if not (CV and Cnt) then return false, "no Church here" end
		local rows = Cnt.RankingView("a", "m")
		local row = type(rows) == "table" and rows[1]
		if not (row and row.name) then return false, "no one on the ranking yet" end
		local ok, why = SelectTab("church")
		if not ok then return false, why end
		CV.Show("detail", ns.FullName(row.name))
		Redraw()
		return CV.page == "detail", "this character may not see a person's numbers"
	end },
	{ id = "church-apostle", back = true, rendered = true, open = function()
		local CV, Church = Mod("ChurchView"), Mod("Church")
		if not (CV and Church) then return false, "no Church here" end
		local S = Church.State()
		local k = type(S) == "table" and type(S.order) == "table" and S.order[1]
		local a = k and S.apostle and S.apostle[k]
		if not (a and a.n) then return false, "no Apostle in the book" end
		local ok, why = SelectTab("church")
		if not ok then return false, why end
		CV.Show("detail", ns.FullName(a.n))
		Redraw()
		return CV.page == "detail", "this character may not see a person's numbers"
	end },
	{ id = "watch-case", back = true, rendered = true, open = function()
		local W = Mod("Watch")
		if not W then return false, "no Watch here" end
		local cases = type(W.Cases) == "function" and W.Cases() or {}
		if not cases[1] then return false, "no case open" end
		local ok, why = SelectTab("watch")
		if not ok then return false, why end
		W.Show("case", cases[1].key)
		Redraw()
		return PageKey():find("^watch/case:") ~= nil, "the desk is not this character's"
	end },
	{ id = "watch-member", back = true, rendered = true, open = function()
		local W = Mod("Watch")
		if not (W and type(W.OpenMember) == "function") then return false, "no Watch here" end
		local ok, why = SelectTab("watch")
		if not ok then return false, why end
		local opened, w = W.OpenMember(ns.me)
		if not opened then return false, "not this character's (" .. tostring(w) .. ")" end
		Redraw()
		return true
	end },
	{ id = "wanted-target", back = true, open = function()
		local Wa = Mod("Wanted")
		if not Wa then return false, "no Wanted here" end
		local t = (Wa.Targets() or {})[1]
		if not t then return false, "nobody on the ledger" end
		local ok, why = SelectTab("wanted")
		if not ok then return false, why end
		return Wa.OpenTarget(t) == true, "the entry did not open"
	end, rendered = true },
	{ id = "wanted-review", back = true, open = function()
		local Wa = Mod("Wanted")
		if not Wa then return false, "no Wanted here" end
		local ok, why = SelectTab("wanted")
		if not ok then return false, why end
		return Wa.OpenReview() == true, "not this character's"
	end, rendered = true },
	{ id = "wanted-rules", back = true, open = function()
		local Wa = Mod("Wanted")
		if not Wa then return false, "no Wanted here" end
		local ok, why = SelectTab("wanted")
		if not ok then return false, why end
		return Wa.OpenRules() == true, "no rules page"
	end, rendered = true },
	{ id = "other-profile", back = true, open = function()
		local PP = Mod("PlayerProfile")
		if not (PP and type(PP.OpenName) == "function") then return false, "no profiles here" end
		local name = FirstRosterMate()
		if not name then return false, "no guildmate online" end
		local ok = PP.OpenName(name)
		return ok == true, "it did not open"
	end, rendered = true },
	{ id = "census-stats", back = true, rendered = true, open = function()
		local UI = Mod("UI")
		if not (UI and type(UI.OpenCensusStats) == "function") then return false, "not in this build" end
		UI.OpenCensusStats()
		Redraw()
		return true
	end },
	{ id = "board", back = true, open = function()
		local V = ns.Views
		if not (type(V) == "table" and type(V.ShowBoard) == "function") then return false, "no Board" end
		local ok, why = RealmFirst()
		if not ok then return false, why end
		V.ShowBoard(true)
		return V.BoardShown() == true, "the Board did not open"
	end, rendered = true },
	{ id = "king-hands", back = true, rendered = true, open = function()
		local K = Mod("King")
		if not K then return false, "no Throne here" end
		local ok, why = SelectTab("throne")
		if not ok then return false, why end
		if PageKey():find("^throne/") == nil or (type(K.ThroneShown) == "function" and not K.ThroneShown()) then
			return false, "the Throne is not this character's"
		end
		K.Show("hands")
		Redraw()
		return true
	end },
}

-- The openers whose list comes from their module: the Members filters, the profile's sections,
-- the Treasury's modes.
local function MoreOpeners()
	local out = {}
	local M = Mod("Members")
	for _, f in ipairs(M and type(M.FILTERS) == "table" and M.FILTERS or {}) do
		local filter = f
		out[#out + 1] = { id = "members-" .. tostring(f), back = true, rendered = true, open = function()
			local ok, why = RealmFirst()
			if not ok then return false, why end
			M.Show(filter)
			return M.Shown() == true, "the members page did not open"
		end }
	end
	local PE, PP = Mod("ProfileEdit"), Mod("PlayerProfile")
	for _, s in ipairs(PE and type(PE.SECTIONS) == "table" and PE.SECTIONS or {}) do
		local section = s
		out[#out + 1] = { id = "my-profile-" .. section, back = false, open = function()
			local UI = Mod("UI")
			if not (UI and type(UI.OpenPlayerProfile) == "function" and type(PE.SetSection) == "function") then return false, "no profile here" end
			local me = PP and type(PP.Find) == "function" and PP.Find(ns.me) or nil
			if UI.OpenPlayerProfile(type(me) == "table" and me or { name = ns.me }) ~= true then return false, "it did not open" end
			return PE.SetSection(section) == true, "not this character's"
		end }
	end
	local T = Mod("Treasury")
	if T and type(T.Show) == "function" then
		for _, m in ipairs({ "summary", "book", "keepers", "wallet", "dues", "guild-finance", "own-guild" }) do
			local mode = m
			out[#out + 1] = { id = "treasury-" .. mode, back = false, tab = "treasury", rendered = true, open = function()
				local ok, why = SelectTab("treasury")
				if not ok then return false, why end
				T.Show(mode)
				Redraw()
				return T.mode == mode, "not this character's"
			end }
		end
	end
	return out
end

-- The sweep's steps, from what this session has: every tab, every page of ns.RealmPages, every
-- opener.
function Sweep.Plan(step)
	local UI = Mod("UI")
	if not (UI and type(UI.SelfTestView) == "function" and type(UI.SelectTab) == "function") then return P(step, "fail", "the window has no UI.SelfTestView") end
	if type(UI.Locked) == "function" and UI.Locked() then
		return P(step, "skip", "the window shows only its Accord or join page here")
	end
	local steps = {}
	for _, tab in ipairs(type(UI.TABS) == "table" and UI.TABS or {}) do
		local key = tab.key
		if type(key) == "string" and tab.apiSurface then
			-- Another addon's page in the window (the Olympus API): its code is its own and may send
			-- what no fence here holds back, so it is listed, never opened.
			steps[#steps + 1] = Step("ui.tab." .. key, "ui", "another addon's tab", function(step)
				P(step, "skip", "another addon's page: not opened (its sends are its own)")
			end)
		elseif type(key) == "string" then
			steps[#steps + 1] = Sweep.Visit("ui.tab." .. key, function() return SelectTab(key) end,
				{ what = "the tab", tab = key, rendered = true, expect = OnTab(key), expand = "tab" })
		end
	end
	for _, p in ipairs(type(ns.RealmPages) == "table" and ns.RealmPages or {}) do
		local pageKey = type(p) == "table" and p.key
		if type(pageKey) == "string" then
			steps[#steps + 1] = Sweep.Visit("ui.page.realm/" .. pageKey, function()
				local ok, why = RealmFirst()
				if not ok then return false, why end
				local V = ns.Views
				if type(V.SetRealmMode) == "function" then V.SetRealmMode("guilds", true) end
				V.ShowPage(pageKey)
				return V.PageShown() == pageKey, "it did not open"
			end, { what = "a page of the Realm", needsBack = true, rendered = true, expand = "page" })
		end
	end
	local openers = {}
	for _, list in ipairs({ SelfTest.OPENERS, MoreOpeners(), type(ns.SelfTestOpeners) == "table" and ns.SelfTestOpeners or {} }) do
		for _, o in ipairs(list) do
			if type(o) == "table" and type(o.id) == "string" and type(o.open) == "function" then openers[#openers + 1] = o end
		end
	end
	for _, o in ipairs(openers) do
		steps[#steps + 1] = Sweep.Visit("ui.open." .. o.id, o.open, { what = "a page its module opens", needsBack = o.back, rendered = o.rendered,
			expect = type(o.tab) == "string" and OnTab(o.tab) or nil, expand = "page" })
	end
	Insert(steps)
	P(step, "ok", ("%d tabs, %d Realm pages, %d openers"):format(#(UI.TABS or {}), #(ns.RealmPages or {}), #openers))
end

---------------------------------------------------------------------------
-- The other windows
---------------------------------------------------------------------------

local WINDOWS = {}

WINDOWS[#WINDOWS + 1] = { id = "ui.accord", what = "the Olympus Accord's letter", fn = function(step)
	local A = Mod("Accord")
	if not (A and type(A.Show) == "function") then return P(step, "skip", "no Accord here") end
	local was = Shown(FrameOf(A, "Frame"))
	local ok, f = pcall(A.Show, "selftest")
	if not ok or type(f) ~= "table" then return P(step, "fail", "the letter: " .. ErrText(f)) end
	local notes, bad, warn = {}, false, false
	local want = 1
	for _, t in ipairs(type(A.TOPICS) == "table" and A.TOPICS or {}) do want = want + 1 + 2 * (tonumber(t[2]) or 0) end
	local parts = type(f.parts) == "table" and #f.parts or -1
	if parts ~= want then bad = true end
	notes[#notes + 1] = ("parts %d/%d"):format(parts, want)
	if not _G.QuestTitleFont then warn = true; notes[#notes + 1] = "no QuestTitleFont" end
	local okTag, tagText = Try(f.tag and f.tag.GetText, f.tag)
	local masked = okTag and type(tagText) == "string" and not Secret(tagText) and (tagText == "-" or tagText:find("#%*%*%*%*$") ~= nil)
	tagText = nil
	if not masked then bad = true end
	notes[#notes + 1] = masked and "tag masked" or "tag NOT masked"
	if type(ns.AccordAccepted) == "function" and ns.AccordAccepted() then
		local closeOk = Shown(f.close) and not Shown(f.accept) and not Shown(f.notNow)
		local marker = tostring(rawget(L, "ACCORD_ACCEPTED_ON") or ""):match("^(.-)%%s") or ""
		local okF, footer = Try(f.footer and f.footer.GetText, f.footer)
		local dated = okF and type(footer) == "string" and marker ~= "" and footer:find(marker, 1, true) ~= nil
		if not closeOk then bad = true end
		if not dated then warn = true end
		notes[#notes + 1] = ("accepted: Close only %s, dated %s"):format(closeOk and "yes" or "NO", dated and "yes" or "no")
	end
	local okR, range = Try(f.body and f.body.GetVerticalScrollRange, f.body)
	if okR and type(range) == "number" and range < 0 then bad = true end
	local ink, over = SelfTest.Ink({ frame = f }), SelfTest.Overflow({ frame = f })
	notes[#notes + 1] = ("ink %d/%d light, %d past the edge"):format(ink.light, ink.checked, over.over)
	if ink.light > 0 then warn = true; Note(run.lightInk, ("accord (%d: %s)"):format(ink.light, table.concat(ink.where, ", "))) end
	if over.over > 0 then warn = true; Note(run.overflow, ("accord (%d)"):format(over.over)) end
	local _, fp = SelfTest.Features()
	notes[#notes + 1] = "T1 " .. fp
	if not was then Try(A.Hide) end
	P(step, bad and "fail" or (warn and "warn" or "ok"), table.concat(notes, "; "))
end }

WINDOWS[#WINDOWS + 1] = { id = "ui.privacy", what = "the privacy page", fn = function(step)
	local C = Mod("Consent")
	if not (C and type(C.Show) == "function") then return P(step, "skip", "no privacy page here") end
	local pending = #(C.Pending(nil) or {}) + #(C.Pending("profile") or {})
	if pending > 0 or (type(C.NoticeDue) == "function" and C.NoticeDue()) then
		return P(step, "skip", ("opening it would mark %d questions asked"):format(pending))
	end
	local Lt = Mod("Letters")
	if Lt and type(Lt.IsRead) == "function" and not Lt.IsRead(ns.VERSION) then return P(step, "skip", "the version letter would follow its closing") end
	local was = Shown(FrameOf(C, "Frame"))
	local ok, f = pcall(C.Show)
	if not ok or type(f) ~= "table" then return P(step, "fail", "the page: " .. ErrText(f)) end
	local rows = 0
	for _, r in ipairs(type(f.rows) == "table" and f.rows or {}) do if Shown(r.label) then rows = rows + 1 end end
	local over = SelfTest.Overflow({ frame = f })
	if over.over > 0 then Note(run.overflow, ("privacy (%d)"):format(over.over)) end
	if not was then Try(C.Hide) end
	P(step, over.over > 0 and "warn" or "ok", ("%d rows, %d past the edge, %d cut"):format(rows, over.over, over.truncated))
end }

WINDOWS[#WINDOWS + 1] = { id = "ui.copy", what = "the copy window", fn = function(step)
	local UI = Mod("UI")
	if not (UI and type(UI.ShowCopy) == "function") then return P(step, "fail", "no UI.ShowCopy") end
	local f = UI.ShowCopy(L.SELFTEST_TITLE, "selftest", nil, { key = "selftest", big = true, auto = true })
	local okT, text = Try(f and f.eb and f.eb.GetText, f and f.eb)
	local good = Shown(f) and okT and text == "selftest"
	if not run.snap.frames.copy and Shown(f) then f:Hide() end
	P(step, good and "ok" or "fail", good and "shown with its text" or "not shown, or another text")
end }

WINDOWS[#WINDOWS + 1] = { id = "ui.reports", what = "/oly status and /oly bug's texts", fn = function(step)
	local okS, status = Try(ns.StatusText)
	local okB, bug = Try(ns.BuildBugReport)
	local texts = {}
	if okS then texts[#texts + 1] = status end
	if okB then texts[#texts + 1] = bug end
	local leak = TagIn(texts)
	run.leaks.status = leak
	P(step, (okS and okB and not leak) and "ok" or "fail", ("status %s (%d bytes), bug report %s (%d bytes)%s"):format(okS and "builds" or "FAILS",
		okS and type(status) == "string" and #status or 0, okB and "builds" or "FAILS", okB and type(bug) == "string" and #bug or 0,
		leak and "; the BattleTag is in them" or ""))
end }

-- The Arena window: each of its panes and staff pages, then closed.
local function ArenaPage(id, show)
	return Step(id, "ui", "a pane of the Arena window", function(step)
		local ui = ArenaUI()
		if not ui then return P(step, "skip", "the window is gone") end
		local ok, err = pcall(show, ui)
		if not ok then return P(step, "fail", "it errored: " .. ErrText(err)) end
		local f = FrameOf(ui, "Frame")
		local ink, over = SelfTest.Ink({ frame = f }), SelfTest.Overflow({ frame = f })
		local errors = #step.errors
		if ink.light > 0 then Note(run.lightInk, ("%s (%d: %s)"):format(id, ink.light, table.concat(ink.where, ", "))) end
		if over.over > 0 then Note(run.overflow, ("%s (%d)"):format(id, over.over)) end
		P(step, errors > 0 and "fail" or ((ink.light > 0 or over.over > 0) and "warn" or "ok"),
			("%d errors; ink %d/%d light, %d past the edge%s"):format(errors, ink.light, ink.checked, over.over,
			Sends(step) ~= "" and ("; would send: " .. Sends(step)) or ""))
	end, { heavy = true })
end

WINDOWS[#WINDOWS + 1] = { id = "ui.arena", what = "the Arena window", fn = function(step)
	local AH, A = Mod("ArenaHome"), Mod("Arena")
	if not (AH and A and type(AH.Open) == "function") then return P(step, "skip", "no Arena here") end
	if type(ns.db.arenaRules) ~= "table" then return P(step, "skip", "its first open would show the arena's rules first") end
	local ui = type(ns.db.arenaUI) == "table" and ns.db.arenaUI or {}
	if not (type(ui.seen) == "table" and ui.seen["explained:arena"] == true) then return P(step, "skip", "its first open would show the arena's explanation first") end
	local okOff, off = Try(A.Off)
	if okOff and off then return P(step, "skip", "the arena is off") end
	if not AH.Open(nil) then return P(step, "skip", "the window did not open") end
	local w = ArenaUI()
	-- (Its own redraws, from its timers and events while it shows, inside the fence too.)
	if w then SelfTest.FenceRedraws(w, "Refresh") end
	if not (w and Try(w.IsShown) and w.IsShown()) then return P(step, "skip", "the window did not open") end
	local more = {}
	for _, section in ipairs(type(w.SECTIONS) == "table" and w.SECTIONS or {}) do
		local okP, panes = Try(w.SectionPanes, section)
		for _, e in ipairs(okP and panes or {}) do
			local key = e.key
			more[#more + 1] = ArenaPage("ui.arena." .. tostring(key), function(u) u.ShowPane(key) end)
		end
	end
	local okS, staff = Try(w.StaffTabs)
	for _, e in ipairs(okS and staff or {}) do
		local key = e.key
		more[#more + 1] = ArenaPage("ui.arena.staff." .. tostring(key), function(u) u.ShowStaff(key) end)
	end
	more[#more + 1] = Step("ui.arena.close", "ui", "the Arena window closed again", function()
		local u = ArenaUI()
		if not u then return end
		local s = run.snap
		if s.arena and s.arena.route then Try(u.RestoreRoute, s.arena.route) end
		if not (s.arena and s.arena.shown) then Try(u.Hide) end
	end, { heavy = true })
	Insert(more)
	P(step, "ok", ("opened; %d panes and staff pages to show"):format(#more - 1))
end }

WINDOWS[#WINDOWS + 1] = { id = "ui.duel", what = "the duel view (yourself and your focus)", fn = function(step)
	local S = Mod("ArenaSpectate")
	if not (S and type(S.PairFromUnits) == "function" and type(S.Open) == "function") then return P(step, "skip", "no duel view here") end
	local okE, exists = Try(UnitExists, "focus")
	local okP, player = Try(UnitIsPlayer, "focus")
	if not (okE and okP) or Secret(exists) or Secret(player) or not exists or not player then
		return P(step, "skip", "no focus: target a player standing still, /focus, target yourself, then run again")
	end
	if type(S.Active) == "function" and S.Active() then return P(step, "skip", "a duel view is open already") end
	local subject = S.PairFromUnits("player", "focus")
	if not subject then return P(step, "skip", "the pair was refused") end
	local ok, opened = pcall(S.Open, subject)
	if not ok or not opened then return P(step, "skip", "it did not open") end
	run.spectated = true
	local ui = ArenaUI()
	local view = ui and type(ui.Spectate) == "table" and ui.Spectate or nil
	local f = view and FrameOf(view, "Frame") or nil
	local ink, over = SelfTest.Ink({ frame = f }), SelfTest.Overflow({ frame = f })
	Try(S.Close)
	run.spectated = false
	P(step, #step.errors > 0 and "fail" or "ok", ("opened; %d errors, ink %d/%d light, %d past the edge"):format(#step.errors, ink.light, ink.checked, over.over))
end, heavy = true }

-- The right-click menus' lines, built into a recorder: no Blizzard menu opens. Only the lines'
-- L keys are kept.
WINDOWS[#WINDOWS + 1] = { id = "ui.menu", what = "the right-click menu's Olympus lines", fn = function(step)
	local PM = Mod("PlayerMenu")
	if not (PM and type(PM.Build) == "function") then return P(step, "skip", "no PlayerMenu here") end
	local reverse = {}
	for k, v in pairs(L) do if type(k) == "string" and type(v) == "string" and not reverse[v] then reverse[v] = k end end
	local function Lines(ctx)
		local items = {}
		local function Item(kind, text)
			items[#items + 1] = { kind = kind, text = text }
			local entry = items[#items]
			return { SetTooltip = function() end, SetEnabled = function(_, on) entry.off = on == false end }
		end
		local root = { CreateTitle = function(_, text) return Item("t", text) end, CreateButton = function(_, text) return Item("b", text) end,
			CreateDivider = function() items[#items + 1] = { kind = "-" } end }
		local ok = pcall(PM.Build, "PLAYER", root, ctx)
		local keys = {}
		for _, it in ipairs(items) do
			if it.kind ~= "-" and #keys < 12 then keys[#keys + 1] = (reverse[it.text] or "?") .. (it.off and "(off)" or "") end
		end
		return ok, keys
	end
	local okA, outsider = Lines({ name = "Selftestoutsider", server = ns.realm })
	local mate = FirstRosterMate()
	local okB, member = true, nil
	if mate then
		local short, realm = tostring(mate):match("^([^%-]+)%-?(.*)$")
		okB, member = Lines({ name = short, server = realm ~= "" and realm or ns.realm })
	end
	mate = nil
	P(step, (okA and okB) and "ok" or "fail", ("outsider: %s; guildmate: %s"):format(#outsider > 0 and table.concat(outsider, ",") or "none",
		member and (#member > 0 and table.concat(member, ",") or "none") or "nobody online"))
end }

---------------------------------------------------------------------------
-- Closing: everything back, the totals
---------------------------------------------------------------------------

local CLOSING = {}
CLOSING[#CLOSING + 1] = { id = "ui.restore", what = "the window and the pages as they were", heavy = true, fn = function(step)
	local s = run.snap
	if not s then return P(step, "skip", "nothing to put back (stopped before it began)") end
	run.restored = SelfTest.Restore(s)
	local notes = {}
	local after = SelfTest.Snapshot()
	if after.shown ~= s.shown then notes[#notes + 1] = "window " .. (after.shown and "open" or "closed") end
	if s.shown and after.page ~= s.page then notes[#notes + 1] = ("page %s, was %s"):format(SafeId(after.page), SafeId(s.page)) end
	if s.church and after.church and (after.church.page ~= s.church.page or after.church.list ~= s.church.list or after.church.window ~= s.church.window) then notes[#notes + 1] = "the Church's page" end
	if s.watch and after.watch and (after.watch.mode ~= s.watch.mode or after.watch.caseKey ~= s.watch.caseKey) then notes[#notes + 1] = "The Watch's page" end
	if after.realmMode ~= s.realmMode then notes[#notes + 1] = "the Realm's mode" end
	if after.docked ~= s.docked then notes[#notes + 1] = "docked " .. tostring(after.docked) end
	P(step, #notes > 0 and "warn" or "ok", #notes > 0 and ("not as before: " .. table.concat(notes, ", ")) or ("as before: " .. (s.shown and SafeId(s.page) or "closed")))
end }

CLOSING[#CLOSING + 1] = { id = "ui.back", what = "a Back on every page a link opens", fn = function(step)
	local r = run
	local detail = ("%d pages; without a Back: %s; Back that stays: %s; Back elsewhere: %s"):format(r.pages,
		#r.noBack > 0 and table.concat(r.noBack, ", ") or "none", #r.brokenBack > 0 and table.concat(r.brokenBack, ", ") or "none",
		#r.wrongBack > 0 and table.concat(r.wrongBack, ", ") or "none")
	P(step, #r.brokenBack > 0 and "fail" or ((#r.noBack > 0 or #r.wrongBack > 0) and "warn" or "ok"), detail)
end }
CLOSING[#CLOSING + 1] = { id = "ui.ink", what = "dark ink on every parchment", fn = function(step)
	P(step, #run.lightInk > 0 and "warn" or "ok", #run.lightInk > 0 and table.concat(run.lightInk, "; ") or "none light")
end }
CLOSING[#CLOSING + 1] = { id = "ui.overflow", what = "no text past its window's edge", fn = function(step)
	P(step, #run.overflow > 0 and "warn" or "ok", #run.overflow > 0 and table.concat(run.overflow, "; ") or "none")
end }
CLOSING[#CLOSING + 1] = { id = "ui.tooltips", what = "every row's tooltip draws", fn = function(step)
	local t = run.tooltips
	P(step, t.errors > 0 and "fail" or "ok", ("%d tooltips, %d errors%s"):format(t.calls, t.errors,
		t.errors > 0 and (" on " .. table.concat(t.pages, ", ") .. ": " .. tostring(t.first)) or ""))
end }
CLOSING[#CLOSING + 1] = { id = "ui.glyphs", what = "letters the game's fonts lack", fn = function(step)
	P(step, "skip", "the rule lives only in tests/run.lua (FontsLack)")
end }
CLOSING[#CLOSING + 1] = { id = "api.cast", what = "UnitCastingInfo / UnitChannelInfo on yourself", fn = function(step)
	local c = run.cast
	if not c then return P(step, "skip", "no cast during the run (start your hearthstone while it runs)") end
	P(step, (c.sixth == "boolean false" or c.sixth == "boolean true") and "ok" or "warn", ("%s: %d returns, 6th %s, %d secret, end time %s"):format(c.kind, c.n,
		c.sixth, c.secrets, c.endSecret and "secret" or "plain"))
end }
CLOSING[#CLOSING + 1] = { id = "api.secretfs", what = "SetFormattedText with a secret value", fn = function(step)
	if type(issecretvalue) ~= "function" then return P(step, "skip", "this client has no secret values") end
	local v = run.secret
	if v == nil then return P(step, "skip", "no secret value seen (target a stranger for one)") end
	local fs = run.fs
	if not fs then
		local holder = SelfTest.EventFrame()
		fs = holder and holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") or nil
		run.fs = fs
	end
	if not fs then return P(step, "skip", "no font string") end
	local ok = pcall(fs.SetFormattedText, fs, "%d", v)
	run.secret = nil
	P(step, ok and "ok" or "fail", ok and "accepted" or "refused")
end }
CLOSING[#CLOSING + 1] = { id = "selftest.keys", what = "the small saved keys after the run", fn = function(step)
	return SelfTest.KeysStep(step, "after")
end }
CLOSING[#CLOSING + 1] = { id = "selftest.invariants", what = "quiet presence, record mode, the Accord, warnings, net-off, cover: unchanged", fn = function(step)
	if not run.inv then return P(step, "skip", "stopped before its first look") end
	local before, after, changed = run.inv, SelfTest.Invariants(), {}
	for _, k in ipairs({ "quiet", "record", "accord", "strikes", "selfOff", "cover" }) do if before[k] ~= after[k] then changed[#changed + 1] = k end end
	P(step, #changed > 0 and "fail" or "ok", #changed > 0 and ("changed: " .. table.concat(changed, ", ")) or "all as before")
end }
CLOSING[#CLOSING + 1] = { id = "selftest.settings", what = "the settings: put back, or changed by something else", fn = function(step)
	local before, after, others = run.prints.before or {}, run.prints.after or {}, {}
	for k, v in pairs(after) do
		local was = before[k]
		if was ~= nil and was ~= false and v ~= false and was ~= v then others[#others + 1] = k end
	end
	table.sort(others)
	P(step, "ok", ("put back: %s; other small keys changed meanwhile: %s"):format(#(run.restored or {}) > 0 and table.concat(run.restored, ", ") or "none",
		#others > 0 and table.concat(others, ", ") or "none"))
end }
CLOSING[#CLOSING + 1] = { id = "mod.comm", what = "the channel and the queue", fn = function(step)
	local C = Mod("Comm")
	if not C then return P(step, "fail", "no Comm") end
	local okR, ready = Try(C.ChannelReady)
	local okQ, queue = Try(C.QueueSize)
	local okP, peers = Try(C.PeerCount)
	local okS, stats = Try(C.Stats)
	local sent = okS and type(stats) == "table" and tonumber(stats.sent) or nil
	P(step, "ok", ("channel %s, queue %s, peers %s; sent meanwhile (background) %s"):format(Bool(okR and ready), tostring(okQ and queue or "?"),
		tostring(okP and peers or "?"), (sent and run.sentBefore) and tostring(sent - run.sentBefore) or "?"))
end }
CLOSING[#CLOSING + 1] = { id = "build.errors", what = "Olympus's errors this session", fn = function(step)
	local wheres = {}
	local saved = type(ns.db) == "table" and type(ns.db.errors) == "table" and ns.db.errors or {}
	for i = #saved, 1, -1 do
		local e = saved[i]
		if type(e) == "table" and #wheres < 5 then Note(wheres, SafeWhere(e.where)) end
	end
	P(step, run.errorsSeen > 0 and "warn" or "ok", ("this session %d, saved %d, during the run %d; latest at: %s"):format(AllErrors(), #saved, run.errorsSeen,
		#wheres > 0 and table.concat(wheres, ", ") or "-"))
end }
CLOSING[#CLOSING + 1] = { id = "selftest.fence", what = "sends held back during the run", fn = function(step)
	FenceOff(run)
	TapOff(run)
	local list = {}
	for k, n in pairs(run.fence.blocked) do list[#list + 1] = k .. " x" .. n end
	table.sort(list)
	local left = run.fence.left
	P(step, #left > 0 and "warn" or (#list > 0 and "warn" or "ok"), (#list > 0 and ("held: " .. table.concat(list, ", ")) or "nothing held")
		.. (#left > 0 and ("; replaced meanwhile by another file: " .. table.concat(left, ", ")) or ""))
end }
CLOSING[#CLOSING + 1] = { id = "selftest.cost", what = "what the run cost", fn = function(step)
	local r = run
	local slow = r.worst.ms > SelfTest.SLOW_STEP_MS or (SelfTest.Now() - r.started) > SelfTest.RUN_MAX
	P(step, slow and "warn" or "ok", ("%d steps in %d frames, %d ms of work, %ds in all; slowest %s %d ms"):format(r.steps, r.ticks, math.floor(r.ms + 0.5),
		math.floor(SelfTest.Now() - r.started + 0.5), SafeId(r.worst.id or "-"), math.floor(r.worst.ms + 0.5)))
end }

-- The small saved keys' fingerprints, a few milliseconds a frame (which: "before" or "after").
function SelfTest.KeysStep(step, which)
	local r = run
	step.keys = step.keys or SortedKeys(ns.db)
	step.i = step.i or 1
	r.prints[which] = r.prints[which] or {}
	local store = r.prints[which]
	local started = SelfTest.Clock()
	while step.i <= #step.keys do
		local k = step.keys[step.i]
		step.i = step.i + 1
		if k ~= "selftest" then store[k] = Fingerprint(ns.db[k], SelfTest.FINGERPRINT_MAX) or false end
		if SelfTest.Clock() - started > SelfTest.BUDGET_MS then return "again" end
	end
end

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------

local function Trend(r)
	local prev = type(ns.db.selftest) == "table" and type(ns.db.selftest.trend) == "table" and ns.db.selftest.trend or {}
	local out = {}
	for i = math.max(1, #prev - SelfTest.HISTORY_MAX + 2), #prev do
		local e = prev[i]
		if type(e) == "table" then
			local byType = {}
			for k, v in pairs(type(e.recordsByType) == "table" and e.recordsByType or {}) do if type(k) == "string" and type(v) == "number" then byType[k] = v end end
			out[#out + 1] = { at = tonumber(e.at), people = tonumber(e.people), characters = tonumber(e.characters), churchRecords = tonumber(e.churchRecords),
				churchPeople = tonumber(e.churchPeople), recordsByType = byType }
		end
	end
	out[#out + 1] = { at = time(), people = r.census and r.census.people, characters = r.census and r.census.characters,
		churchRecords = r.church and r.church.records, churchPeople = r.church and r.church.people, recordsByType = r.recordsByType or {} }
	return out
end

-- Whether a text of the report holds the BattleTag (it never should).
local function ReportLeaks(report)
	local texts = {}
	local function Walk(v)
		if type(v) == "table" then for _, x in pairs(v) do Walk(x) end elseif type(v) == "string" then texts[#texts + 1] = v end
	end
	Walk(report)
	return TagIn(texts)
end

local function Finish(step)
	local r = run
	local leak = ReportLeaks(r.probes)
	local leaks = {}
	if r.leaks.status then leaks[#leaks + 1] = "/oly status or /oly bug" end
	if r.leaks.bridge then leaks[#leaks + 1] = "the Companion's sections" end
	if leak then leaks[#leaks + 1] = "this report" end
	if leak == nil and r.leaks.status == nil then
		Add("build.privacy", "build", "the BattleTag in no report", "skip", "the BattleTag is not readable now")
	else
		Add("build.privacy", "build", "the BattleTag in no report", #leaks > 0 and "fail" or "ok", #leaks > 0 and ("found in: " .. table.concat(leaks, ", ")) or "in none of them")
	end
	if leak then for _, p in ipairs(r.probes) do p.detail = "" end end
	local blocked = {}
	for k, n in pairs(r.fence.blocked) do blocked[Clip(k, 16)] = n end
	local report = {
		v = 1, at = time(), build = r.build or BuildInfo(), client = ClientInfo(), probes = r.probes,
		summary = { ok = r.counts.ok or 0, warn = r.counts.warn or 0, fail = r.counts.fail or 0, skip = r.counts.skip or 0,
			ms = Round(r.ms), seconds = Round(SelfTest.Now() - r.started), worstStepMs = Round(r.worst.ms), worstStep = r.worst.id and SafeId(r.worst.id) or nil,
			ticks = r.ticks, steps = r.steps, aborted = r.aborted, pages = r.pages, noBack = r.noBack, brokenBack = r.brokenBack, wrongBack = r.wrongBack,
			lightInk = r.lightInk, overflow = r.overflow, sends = blocked, errors = r.errorsSeen, dropped = r.dropped, trimmed = r.trimmed,
			features = r.features },
		trend = Trend(r),
	}
	ns.db.selftest = report
	ns.Print(L.SELFTEST_DONE:format(report.summary.ok, report.summary.warn, report.summary.fail, report.summary.skip))
	local UI = Mod("UI")
	if UI and type(UI.ShowCopy) == "function" then UI.ShowCopy(L.SELFTEST_TITLE, SelfTest.ReportText(report), nil, { key = "selftest", big = true, auto = true }) end
	r.done = true
end

-- The copy window's text: the totals, what failed, what to look at, the pages, the /reload.
function SelfTest.ReportText(report)
	if type(report) ~= "table" then return L.SELFTEST_NO_REPORT end
	local s = type(report.summary) == "table" and report.summary or {}
	local out = {}
	local function Line(text) out[#out + 1] = tostring(text) end
	Line(L.SELFTEST_DONE:format(tonumber(s.ok) or 0, tonumber(s.warn) or 0, tonumber(s.fail) or 0, tonumber(s.skip) or 0))
	if s.aborted then Line(L.SELFTEST_STOPPED_EARLY:format(tostring(s.aborted))) end
	local b, c = type(report.build) == "table" and report.build or {}, type(report.client) == "table" and report.client or {}
	Line(("%s  |  Olympus %s%s  |  %s %s (%s) %s, UI scale %s, %sx%s"):format(date and date("%Y-%m-%d %H:%M", tonumber(report.at) or 0) or "?",
		tostring(b.version), b.test and (" test " .. tostring(b.test) .. " (" .. tostring(b.commit or "?") .. ")") or "", tostring(c.flavor), tostring(c.interface),
		tostring(c.build), tostring(c.locale), tostring(c.uiScale), tostring(c.screenW), tostring(c.screenH)))
	if s.features then Line("features: " .. tostring(s.features)) end
	Line(("%d pages, %d frames, %s ms of work, %ss"):format(tonumber(s.pages) or 0, tonumber(s.ticks) or 0, tostring(s.ms), tostring(s.seconds)))
	local probes = type(report.probes) == "table" and report.probes or {}
	for _, kind in ipairs({ "fail", "warn" }) do
		local head = false
		for _, p in ipairs(probes) do
			if type(p) == "table" and p.result == kind then
				if not head then
					Line("")
					Line(kind == "fail" and L.SELFTEST_HEAD_FAILS or L.SELFTEST_HEAD_WARNS)
					head = true
				end
				Line("  " .. tostring(p.id) .. ": " .. tostring(p.detail))
			end
		end
	end
	for _, list in ipairs({ { s.noBack, L.SELFTEST_HEAD_NOBACK }, { s.brokenBack, L.SELFTEST_HEAD_BROKEN }, { s.wrongBack, L.SELFTEST_HEAD_ELSEWHERE }, { s.lightInk, L.SELFTEST_HEAD_INK },
		{ s.overflow, L.SELFTEST_HEAD_OVERFLOW } }) do
		if type(list[1]) == "table" and #list[1] > 0 then
			Line("")
			Line(list[2] .. " " .. table.concat(list[1], ", "))
		end
	end
	Line("")
	Line(L.SELFTEST_ASKS)
	Line(L.SELFTEST_RELOAD)
	local text = table.concat(out, "\n")
	if #text > SelfTest.TEXT_MAX then
		local tail = "\n...\n\n" .. L.SELFTEST_ASKS .. "\n" .. L.SELFTEST_RELOAD
		text = Clip(text, SelfTest.TEXT_MAX - #tail) .. tail
	end
	return text
end

---------------------------------------------------------------------------
-- Starting, stopping
---------------------------------------------------------------------------

local eventFrame
function SelfTest.EventFrame()
	if not eventFrame and type(CreateFrame) == "function" then
		eventFrame = CreateFrame("Frame")
		if eventFrame and eventFrame.Hide then eventFrame:Hide() end
	end
	return eventFrame
end
function SelfTest.OnEvent(event)
	if not run then return end
	if event == "PLAYER_REGEN_DISABLED" then
		SelfTest.Abort("combat")
		ns.Print(L.SELFTEST_ABORT_COMBAT)
	elseif event == "PLAYER_ENTERING_WORLD" then
		SelfTest.Abort("zone")
		ns.Print(L.SELFTEST_ABORT_ZONE)
	end
end
local function EventsOn()
	local f = SelfTest.EventFrame()
	if not f then return end
	f:SetScript("OnEvent", function(_, event) ns.SafeCall("selftest event", SelfTest.OnEvent, event) end)
	f:RegisterEvent("PLAYER_REGEN_DISABLED")
	f:RegisterEvent("PLAYER_ENTERING_WORLD")
end
local function EventsOff()
	if eventFrame and eventFrame.UnregisterAllEvents then eventFrame:UnregisterAllEvents() end
end

function SelfTest.Teardown()
	local r = run
	if not r then return end
	run = nil
	FenceOff(r)
	TapOff(r)
	EventsOff()
end

-- Stopped before the end (combat, a loading screen, /oly selftest stop, too long): everything is
-- put back now, the report keeps what was checked.
function SelfTest.Abort(reason)
	local r = run
	if not r or r.aborted then return false end
	r.aborted = reason
	local keep = {}
	for i = r.pos, #r.queue do if r.queue[i].closing then keep[#keep + 1] = r.queue[i] end end
	r.queue, r.pos = keep, 1
	r.token = -1 -- (the frame already asked for finds the run gone)
	while run == r and r.pos <= #r.queue and not r.done do
		local step = r.queue[r.pos]
		r.pos = r.pos + 1
		RunStep(step)
	end
	if run == r then SelfTest.Teardown() end
	if reason == "time" then ns.Print(L.SELFTEST_ABORT_TIME) end
	return true
end

local function Plan()
	local q = {}
	q[#q + 1] = Step("selftest.snapshot", "selftest", "the state before the run", function()
		run.snap = SelfTest.Snapshot()
		run.inv = SelfTest.Invariants()
		local C = Mod("Comm")
		local ok, stats = Try(C and C.Stats)
		run.sentBefore = ok and type(stats) == "table" and tonumber(stats.sent) or nil
		backTexts, PARCHMENT_FILES = nil, nil
	end)
	q[#q + 1] = Step("selftest.keys.before", "selftest", "the small saved keys before the run", function(step) return SelfTest.KeysStep(step, "before") end)
	for _, p in ipairs(BUILD) do q[#q + 1] = Step(p.id, "build", p.what, p.fn) end
	for _, p in ipairs(API) do q[#q + 1] = Step(p.id, "api", p.what, p.fn) end
	for _, p in ipairs(MOD) do q[#q + 1] = Step(p.id, "mod", p.what, p.fn, { heavy = p.heavy }) end
	q[#q + 1] = Step("ui.plan", "ui", "the pages to open", Sweep.Plan)
	for _, p in ipairs(WINDOWS) do q[#q + 1] = Step(p.id, "ui", p.what, p.fn, { heavy = true }) end
	for _, p in ipairs(CLOSING) do q[#q + 1] = Step(p.id, p.id:match("^(%a+)") or "selftest", p.what, p.fn, { heavy = p.heavy, closing = true }) end
	q[#q + 1] = Step("selftest.finish", "selftest", "the report", Finish, { closing = true })
	return q
end

-- Whether this client may run it: true, or false and what to say.
function SelfTest.Allowed()
	local W = Mod("Workshop")
	local test = W and type(W.TestBuild) == "function" and W.TestBuild() or nil
	local author = W and type(W.IsAuthorName) == "function" and W.IsAuthorName(ns.me) == true
	if not test or not author then return false, L.SELFTEST_UNAVAILABLE end
	if type(ns.GamepadUI) == "function" and ns.GamepadUI() then return false, L.SELFTEST_GAMEPAD end
	return true
end

function SelfTest.Running() return run ~= nil end
function SelfTest.Report() return type(ns.db) == "table" and ns.db.selftest or nil end

function SelfTest.Start()
	local ok, why = SelfTest.Allowed()
	if not ok then ns.Print(why) return false, "refused" end
	if run then ns.Print(L.SELFTEST_BUSY) return false, "busy" end
	if type(InCombatLockdown) == "function" and InCombatLockdown() then ns.Print(L.SELFTEST_COMBAT) return false, "combat" end
	local UI = Mod("UI")
	local H = Mod("HonorsNet")
	local okL, letters = Try(H and H.QueuedLetters)
	if okL and type(letters) == "table" and letters[1] and not (UI and type(UI.IsShown) == "function" and UI.IsShown()) then
		ns.Print(L.SELFTEST_LETTER_WAITS)
		return false, "letter"
	end
	-- (The privacy page shows by itself, over the window or a chat, while a line was never asked
	-- or its notice never shown: the run would mark them asked. Answered first, by the player.)
	local C = Mod("Consent")
	local okW, waiting = Try(C and C.Waiting)
	local okN, notice = Try(C and C.NoticeDue)
	if (okW and waiting == true) or (okN and notice == true) then
		ns.Print(L.SELFTEST_PRIVACY_WAITS)
		return false, "privacy"
	end
	tokens = tokens + 1
	run = { token = tokens, started = SelfTest.Now(), queue = {}, pos = 1, probes = {}, counts = {}, dropped = 0, trimmed = 0, bytes = 0,
		ms = 0, steps = 0, ticks = 0, worst = { ms = 0 }, raised = 0, errorsSeen = 0, pages = 0, seen = {}, noBack = {}, brokenBack = {}, wrongBack = {},
		lightInk = {}, overflow = {}, prints = {}, leaks = {}, tooltips = { calls = 0, errors = 0, pages = {} } }
	FenceOn(run)
	TapOn(run)
	EventsOn()
	run.queue = Plan()
	ns.Print(L.SELFTEST_STARTED)
	local token = run.token
	SelfTest.After(0, function() Tick(token) end)
	return true
end

-- The last report again, in the copy window.
function SelfTest.ShowLast()
	local report = SelfTest.Report()
	if type(report) ~= "table" then ns.Print(L.SELFTEST_NO_REPORT) return false end
	local UI = Mod("UI")
	if not (UI and type(UI.ShowCopy) == "function") then return false end
	UI.ShowCopy(L.SELFTEST_TITLE, SelfTest.ReportText(report), nil, { key = "selftest", big = true })
	return true
end

-- /oly selftest [status | stop]
function SelfTest.Slash(rest)
	local verb = Trim(rest):lower()
	local ok, why = SelfTest.Allowed()
	if not ok then ns.Print(why) return false end
	if verb == "" or verb == "run" then return SelfTest.Start() end
	if verb == "status" then return SelfTest.ShowLast() end
	if verb == "stop" then
		if not run then ns.Print(L.SELFTEST_USAGE) return false end
		SelfTest.Abort("stop")
		ns.Print(L.SELFTEST_STOPPED)
		return true
	end
	ns.Print(L.SELFTEST_USAGE)
	return false
end

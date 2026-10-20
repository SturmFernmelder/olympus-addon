-- /oly selftest (Olympus/SelfTest.lua): refused outside test builds and for anyone but the author,
-- never sends while it runs (every send it holds back is counted, and the spies under it see none),
-- a page that errors is a failed probe and the run goes on, the Back and parchment detectors, the
-- report's bounds (no BattleTag, no roster name), everything put back, a stop in combat, the last
-- report again, the pacing. Run with the harness's WithUI and LoadUI: the window and its pages are
-- the real UI.lua and Views.lua on the harness's stand-in frames. Every name and tag here is invented.
local ns, test, eq, H = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]selftest%.lua$")) or "./"
local L = ns.L
local WithUI, LoadUI = H.WithUI, H.LoadUI

assert(loadfile(ROOT .. "Olympus/Locales/SelfTestText.lua"))("Olympus", ns)
local standIn = ns.SelfTest
assert(loadfile(ROOT .. "Olympus/SelfTest.lua"))("Olympus", ns)
local S = ns.SelfTest
local TAG = "Selftester#57319"

-- A scene: a test build and the author's character (opts.test = false, opts.author = false: not),
-- the run's frames a queue the test pumps, ns.Print kept, InCombatLockdown as w.combat says.
local function Scene(fn, opts)
	opts = opts or {}
	local saved = { tb = rawget(ns.Arena, "TestBuild"), author = ns.Workshop.IsAuthorName, after = S.After, clock = S.Clock, now = S.Now,
		print = ns.Print, combat = rawget(_G, "InCombatLockdown"), report = ns.db.selftest, trace = S.trace, pages = ns.RealmPages,
		bn = rawget(_G, "BNGetInfo"), bnc = rawget(_G, "BNConnected"), waiting = ns.Consent.Waiting, notice = ns.Consent.NoticeDue }
	local w = { printed = {}, queue = {}, combat = false }
	local ok, err = pcall(function()
		rawset(ns.Arena, "TestBuild", function()
			if opts.test == false then return nil end
			return { n = 930, base = ns.VERSION, built = 1800000000, expires = 1800000000 + 86400, commit = "abc1234", lane = "group" }
		end)
		ns.Workshop.IsAuthorName = function(name) return opts.author ~= false and name == ns.me end
		ns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		S.After = function(_, f) w.queue[#w.queue + 1] = f end
		InCombatLockdown = function() return w.combat == true end
		-- (The privacy page answered: a run would otherwise refuse, below.)
		ns.Consent.Waiting = function() return opts.privacy == true end
		ns.Consent.NoticeDue = function() return false end
		ns.db.selftest = opts.report
		local pages = {}
		for i, p in ipairs(saved.pages or {}) do pages[i] = p end
		ns.RealmPages = pages
		-- The run's frames, in order, until none is asked for (max: at most that many).
		function w.Pump(max)
			local n = 0
			while #w.queue > 0 and n < (max or 1e6) do
				local f = table.remove(w.queue, 1)
				n = n + 1
				f()
			end
			return n
		end
		function w.Said(text) for _, p in ipairs(w.printed) do if p == text then return true end end return false end
		fn(w)
	end)
	if S.Running() then pcall(S.Abort, "stop") end
	if w.cleanup then pcall(w.cleanup) end
	rawset(ns.Arena, "TestBuild", saved.tb)
	ns.Workshop.IsAuthorName, S.After, S.Clock, S.Now, ns.Print = saved.author, saved.after, saved.clock, saved.now, saved.print
	InCombatLockdown, ns.db.selftest, S.trace, ns.RealmPages = saved.combat, saved.report, saved.trace, saved.pages
	BNGetInfo, BNConnected = saved.bn, saved.bnc
	ns.Consent.Waiting, ns.Consent.NoticeDue = saved.waiting, saved.notice
	if not ok then error(err, 0) end
end

-- fn(UI, uns) in a fresh Olympus window (the harness's toolkit), the harness's error capture
-- quiet: a page the test makes fail is the run's to report.
local function InWindow(fn)
	WithUI(function()
		local UI, uns = LoadUI()
		ns.CaptureError = function() end
		fn(UI, uns)
	end)
end

-- A whole run, pumped to its end: the report.
local function Run(w)
	local started = S.Start()
	assert(started, "started: " .. table.concat(w.printed, " / "))
	w.Pump()
	eq(S.Running(), false, "the run ended")
	return ns.db.selftest
end

local function ProbeOf(report, id)
	for _, p in ipairs(report.probes) do if p.id == id then return p end end
	return nil
end
local function Serialized(v, out)
	out = out or {}
	if type(v) == "table" then
		for k, x in pairs(v) do Serialized(k, out); Serialized(x, out) end
	else
		out[#out + 1] = tostring(v)
	end
	return table.concat(out, "\n")
end

test("selftest: refused outside a test build and for anyone but the author; in combat, with the gamepad UI, with a privacy question never asked and while it runs it says why", function()
	Scene(function(w)
		SlashCmdList.OLYMPUS("selftest")
		eq(w.printed[#w.printed], L.SELFTEST_UNAVAILABLE, "a public build")
		SlashCmdList.OLYMPUS("selftest status")
		eq(w.printed[#w.printed], L.SELFTEST_UNAVAILABLE, "its status too")
		eq(S.Running(), false); eq(ns.db.selftest, nil, "nothing written"); eq(#w.queue, 0, "no frame asked for")
	end, { test = false })
	Scene(function(w)
		SlashCmdList.OLYMPUS("selftest")
		eq(w.printed[#w.printed], L.SELFTEST_UNAVAILABLE, "a test build, but not the author")
		eq(S.Running(), false); eq(ns.db.selftest, nil); eq(#w.queue, 0)
	end, { author = false })
	Scene(function(w)
		w.combat = true
		SlashCmdList.OLYMPUS("selftest")
		eq(w.printed[#w.printed], L.SELFTEST_COMBAT, "in combat")
		eq(S.Running(), false); eq(#w.queue, 0)
	end)
	Scene(function(w)
		SlashCmdList.OLYMPUS("selftest")
		eq(w.printed[#w.printed], L.SELFTEST_PRIVACY_WAITS, "a privacy question never asked: the run would mark it asked")
		eq(S.Running(), false); eq(#w.queue, 0); eq(ns.db.selftest, nil)
	end, { privacy = true })
	Scene(function(w)
		-- (With the gamepad UI /oly is not even typed: Core.lua's slash gate. Its own refusal too.)
		GamepadStyle(true)
		eq(S.Slash(""), false)
		GamepadStyle(false)
		eq(w.printed[#w.printed], L.SELFTEST_GAMEPAD, "the gamepad UI")
		eq(S.Running(), false); eq(#w.queue, 0)
	end)
	Scene(function(w)
		InWindow(function()
			SlashCmdList.OLYMPUS("selftest")
			eq(S.Running(), true, "the author on a test build: it runs")
			eq(w.printed[#w.printed], L.SELFTEST_STARTED)
			SlashCmdList.OLYMPUS("selftest")
			eq(w.printed[#w.printed], L.SELFTEST_BUSY, "once at a time")
			SlashCmdList.OLYMPUS("selftest stop")
			eq(S.Running(), false, "stopped")
			eq(w.printed[#w.printed], L.SELFTEST_STOPPED)
			eq(ns.db.selftest.summary.aborted, "stop", "its report says so")
		end)
	end)
	-- A client updated without a restart: Core.lua's stand-in says to restart.
	Scene(function(w)
		ns.SelfTest = standIn
		local ok, err = pcall(SlashCmdList.OLYMPUS, "selftest")
		ns.SelfTest = S
		assert(ok, err)
		eq(w.printed[#w.printed], L.RESTART_NEEDED)
	end)
end)

test("selftest: nothing is sent while it runs: the sends a page makes are held and counted, the spies under them see none, and every send is the module's again after", function()
	Scene(function(w)
		InWindow(function()
			local spied = {}
			local COMM = { "Send", "Whisper", "SendBatch", "SendChunked", "SendChat" }
			local savedComm, savedChat, savedSay, savedSCM, savedTimer = {}, C_ChatInfo, ns.SayTo, rawget(_G, "SendChatMessage"), C_Timer
			local timers = {}
			local ok, err = pcall(function()
				for _, k in ipairs(COMM) do
					savedComm[k] = ns.Comm[k]
					ns.Comm[k] = function() spied[#spied + 1] = "Comm." .. k return false end
				end
				local spies = {}
				for _, k in ipairs(COMM) do spies[k] = ns.Comm[k] end
				C_ChatInfo = setmetatable({ SendAddonMessage = function() spied[#spied + 1] = "SendAddonMessage" end,
					SendAddonMessageLogged = function() spied[#spied + 1] = "SendAddonMessageLogged" end }, { __index = savedChat })
				SendChatMessage = function() spied[#spied + 1] = "SendChatMessage" end
				ns.SayTo = function() spied[#spied + 1] = "SayTo" return true end
				-- What the pages queue for later (ns.After) runs too, after the run.
				C_Timer = { After = function(_, f) timers[#timers + 1] = f end, NewTicker = function() return { Cancel = function() end } end }
				-- (A type of its own: the Board's ask, GQ, may be held in the same run.)
				table.insert(ns.RealmPages, { key = "selftestasks", Lines = function()
					ns.Comm.Send("CHANNEL", "SELFTEST~1", "x")
					return { { text = "< Back", onClick = function() ns.Views.ShowPage(nil) end }, { text = "A page that asks" } }
				end })
				local report = Run(w)
				local n = 0
				while #timers > 0 and n < 2000 do n = n + 1; table.remove(timers, 1)() end
				eq(table.concat(spied, ","), "", "no send reached the game or the queue")
				eq(report.summary.sends.SELFTEST, 1, "the page's ask held, and counted by its type")
				local p = ProbeOf(report, "ui.page.realm/selftestasks")
				assert(p, "the page's probe")
				assert(p.detail:find("would send: SELFTEST", 1, true), p.detail)
				eq(p.result, "ok", "a page that asks is no failure: " .. p.detail)
				for _, k in ipairs(COMM) do eq(ns.Comm[k], spies[k], "Comm." .. k .. " is its own again") end
				eq(ProbeOf(report, "selftest.fence").detail:find("SELFTEST x1", 1, true) ~= nil, true, "the fence's probe names it")
			end)
			for _, k in ipairs(COMM) do ns.Comm[k] = savedComm[k] end
			C_ChatInfo, ns.SayTo, SendChatMessage, C_Timer = savedChat, savedSay, savedSCM, savedTimer
			if not ok then error(err, 0) end
		end)
	end)
end)

test("selftest: a page that errors is a failed probe with its error, and the run goes on to the next page and to the end", function()
	Scene(function(w)
		InWindow(function()
			table.insert(ns.RealmPages, { key = "selftestboom", Lines = function() error("boom") end })
			table.insert(ns.RealmPages, { key = "selftestfine", Lines = function()
				return { { text = "< Back", onClick = function() ns.Views.ShowPage(nil) end }, { text = "Fine" } }
			end })
			local report = Run(w)
			local boom, fine = ProbeOf(report, "ui.page.realm/selftestboom"), ProbeOf(report, "ui.page.realm/selftestfine")
			assert(boom and fine, "both probes")
			eq(boom.result, "fail")
			assert(boom.detail:find("boom", 1, true), boom.detail)
			eq(fine.result, "ok", fine.detail)
			assert(ProbeOf(report, "selftest.cost"), "it ran to its end")
			eq(report.summary.aborted, nil)
		end)
	end)
end)

-- A plain stand-in of the client's frames, for the detectors alone: every method these read, and
-- what the client gives (FontString:GetTextColor, Frame:GetChildren and GetRegions, regions' edges).
local function FakeString(text, color, left, right)
	return { GetObjectType = function() return "FontString" end, IsVisible = function() return true end, IsShown = function() return true end,
		GetText = function() return text end, GetTextColor = function() return color[1], color[2], color[3], 1 end,
		GetLeft = function() return left or 10 end, GetRight = function() return right or 100 end, IsTruncated = function() return false end }
end
local function FakeFrame(regions, children, paper, left, right)
	return { paper = paper and { IsShown = function() return true end } or nil, GetObjectType = function() return "Frame" end,
		GetRegions = function() return unpack(regions or {}) end, GetChildren = function() return unpack(children or {}) end,
		GetLeft = function() return left or 0 end, GetRight = function() return right or 200 end, IsShown = function() return true end }
end

test("selftest: the detectors: a page without a Back, light text on parchment (its own colour or a colour code), text past its window", function()
	eq(S.HasBack({ lines = { { header = true, text = "A Person" }, { text = "Points 12" } } }), false, "no Back line")
	eq(S.HasBack({ lines = { { text = "|cffffd200< Back|r", onClick = function() end } } }), true, "a Back line, coloured")
	eq(S.HasBack({ lines = {}, nav = { { nav = { { text = L.RANK_RULES_BACK } } } } }), true, "a strip's Back")
	eq(S.HasBack({ lines = {}, buttons = { { IsShown = function() return true end, GetText = function() return L.PLAYER_PROFILE_BACK end } } }), true, "a Back button")
	eq(S.HasBack({ lines = {}, buttons = { { IsShown = function() return false end, GetText = function() return L.PLAYER_PROFILE_BACK end } } }), false,
		"a hidden one is none")
	eq(S.IsBack(L.CHURCH_BACK), true, "the short *_BACK lines count"); eq(S.IsBack("Points"), false)
	-- Ink: the parchment, white text on it; dark ink; dark ink with white words in it.
	local white = S.Ink({ frame = FakeFrame({ FakeString("Some words here", { 1, 1, 1 }) }, nil, true) })
	eq(white.checked, 1); eq(white.light, 1, "white on parchment")
	local dark = S.Ink({ frame = FakeFrame({ FakeString("Some words here", { 0.18, 0.10, 0.02 }) }, nil, true) })
	eq(dark.light, 0, "the letters' ink")
	local mixed = S.Ink({ frame = FakeFrame({ FakeString("Ink and |cffffffffwhite words|r", { 0.18, 0.10, 0.02 }) }, nil, true) })
	eq(mixed.light, 1, "white words inside dark ink")
	local short = S.Ink({ frame = FakeFrame({ FakeString("Ink |cffffffffab|r", { 0.18, 0.10, 0.02 }) }, nil, true) })
	eq(short.light, 0, "two light letters are not a run")
	eq(S.Ink({ frame = FakeFrame({ FakeString("Some words here", { 1, 1, 1 }) }, nil, false) }).checked, 0, "no parchment: not checked")
	local nested = S.Ink({ frame = FakeFrame(nil, { FakeFrame({ FakeString("Deep white text", { 1, 1, 1 }) }) }, true) })
	eq(nested.light, 1, "a child frame's text on its parent's parchment")
	-- Overflow: 20 px past the window's right edge.
	local over = S.Overflow({ frame = FakeFrame({ FakeString("Wide", { 1, 1, 1 }, 10, 220) }, nil, false, 0, 200) })
	eq(over.checked, 1); eq(over.over, 1, "past the edge")
	eq(S.Overflow({ frame = FakeFrame({ FakeString("Fits", { 1, 1, 1 }, 10, 203) }, nil, false, 0, 200) }).over, 0, "within its 4 px")
	-- Ids: nobody's name.
	eq(S.SafeId("watch/case:Some Name"), "watch/case:*")
	eq(S.SafeId("realm/members:7"), "realm/members:7", "a members filter stays")
	eq(S.SafeId("player-profile:" .. ns.me .. "#look"), "player-profile:self#look")
	eq(S.SafeId("player-profile:Another One-Realm"), "player-profile:other")
end)

test("selftest: the Back detector on the Church's own pages: a person's detail page has none (the missing Back reported), its rules page has one", function()
	local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
	local w = World.New({ apostles = { "Aldric Vane-Realm" } })
	local author = w:Client(World.AUTHOR, { view = true })
	author.View.page, author.View.arg = "detail", "Aldric Vane-Realm"
	local lines = w:As(author, author.View.Build)
	eq(author.View.page, "detail", "the author sees a person's numbers")
	eq(S.HasBack({ lines = lines }), false, "no Back on the detail page: only its header goes back, with CHURCH_BACK as its tooltip")
	author.View.page, author.View.arg = "ranking", nil
	local rules
	for _, line in ipairs(w:As(author, author.View.Build)) do if type(line.id) == "string" and line.id:find("^ranking%-rules:") then rules = line end end
	assert(rules, "the ranking's rules link")
	w:As(author, rules.onClick)
	eq(S.HasBack({ lines = w:As(author, author.View.Build) }), true, "the rules page: its Back line")
end)

test("selftest: a page a Realm link opens without a Back is in the report's pages without a Back", function()
	Scene(function(w)
		InWindow(function()
			table.insert(ns.RealmPages, 1, { key = "selftestnoback", beforeBoard = true, Link = function()
				return { text = "Selftest page", onClick = function() ns.Views.ShowPage("selftestnoback") end }
			end, Lines = function() return { { header = true, text = "A page with no way back" } } end })
			-- (And one whose Back opens another page than the tree it was opened from: the Board.)
			table.insert(ns.RealmPages, 2, { key = "selftestelsewhere", beforeBoard = true, Link = function()
				return { text = "Selftest other page", onClick = function() ns.Views.ShowPage("selftestelsewhere") end }
			end, Lines = function() return { { text = "< Back", onClick = function() ns.Views.ShowBoard(true) end }, { text = "Its Back goes astray" } } end })
			local report = Run(w)
			local found = false
			for _, id in ipairs(report.summary.noBack) do if id == "realm/selftestnoback" then found = true end end
			assert(found, "listed: " .. table.concat(report.summary.noBack, ", "))
			eq(table.concat(report.summary.wrongBack, ", "), "realm/selftestelsewhere -> realm/board", "the Back that leads elsewhere")
			for _, id in ipairs(report.summary.noBack) do assert(id ~= "realm/selftestelsewhere", "it has a Back") end
			eq(#report.summary.brokenBack, 0, "every Back left its page")
			eq(ProbeOf(report, "ui.back").result, "warn", ProbeOf(report, "ui.back").detail)
			local link
			for _, p in ipairs(report.probes) do if p.id:find("^ui%.link%.realm/guilds") and p.detail:find("selftestnoback", 1, true) then link = p end end
			if not link then
				local ids = {}
				for _, p in ipairs(report.probes) do if p.id:find("^ui%.") then ids[#ids + 1] = p.id .. "=" .. p.result .. ":" .. p.detail end end
				print(table.concat(ids, "\n"))
			end
			assert(link, "reached by its link from the Realm's tree")
			eq(link.result, "warn"); assert(link.detail:find("no Back", 1, true), link.detail)
			assert(S.ReportText(report):find("realm/selftestnoback", 1, true), "in the copy window's text")
		end)
	end)
end)

test("selftest: the report is bounded and plain: at most MAX_PROBES probes, short details, plain values; never the BattleTag, never a roster name", function()
	Scene(function(w)
		InWindow(function()
			BNConnected = function() return true end
			BNGetInfo = function() return 1, TAG, nil, "", false, false, false end
			-- The roster as Forever gives it: 17 fields, the GUID last, invented names.
			local savedRoster = GetGuildRosterInfo
			GetGuildRosterInfo = function(i)
				return "Rostermate" .. i .. "-Realm", "rank", 3, 60, "Mage", "Elwynn Forest", "", "", i <= 2, 0, "MAGE", 0, 0, false, false, 0,
					"Player-4242-0000BEE" .. i
			end
			w.cleanup = function() GetGuildRosterInfo = savedRoster end
			for i = 1, 400 do
				table.insert(ns.RealmPages, { key = "selftestmany" .. i, Lines = function()
					return { { text = "< Back", onClick = function() ns.Views.ShowPage(nil) end }, { text = "Page " .. i } }
				end })
			end
			local report = Run(w)
			assert(#report.probes <= S.MAX_PROBES, "probes: " .. #report.probes)
			eq(#report.probes, S.MAX_PROBES, "the cap reached")
			assert(report.summary.dropped > 0, "and counted past it")
			local function Plain(v, depth)
				assert(depth <= 4, "too deep")
				local t = type(v)
				if t == "table" then for k, x in pairs(v) do Plain(k, depth + 1); Plain(x, depth + 1) end return end
				assert(t == "string" or t == "number" or t == "boolean", "a " .. t)
			end
			Plain(report, 1)
			for _, p in ipairs(report.probes) do
				assert(#p.detail <= S.DETAIL_MAX, p.id .. ": " .. #p.detail)
				assert(#p.id <= S.ID_MAX, p.id)
			end
			local text = Serialized(report) .. S.ReportText(report)
			eq(text:find("57319", 1, true), nil, "the tag's digits nowhere")
			eq(text:find("Selftester#", 1, true), nil, "the tag nowhere")
			for i = 1, 3 do
				eq(text:find("Rostermate" .. i, 1, true), nil, "a guildmate's name: Rostermate" .. i)
				eq(text:find("0000BEE" .. i, 1, true), nil, "a guildmate's GUID")
			end
			local roster = ProbeOf(report, "api.roster")
			eq(roster.result, "ok", roster.detail)
			assert(roster.detail:find("17 GUID ok", 1, true), roster.detail)
			w.cleanup()
			local privacy = ProbeOf(report, "build.privacy") or {}
			eq(privacy.result ~= "fail", true, "the privacy probe: " .. tostring(privacy.detail))
			local bn = ProbeOf(report, "api.bn")
			assert(bn and bn.detail:find("Name#digits", 1, true), "the tag's shape, without the tag")
		end)
	end)
end)

test("selftest: everything put back: the window's tab and Realm page, open or closed, and the saved keys the pages write", function()
	Scene(function(w)
		InWindow(function(UI)
			table.insert(ns.RealmPages, { key = "selftestmine", Lines = function()
				return { { text = "< Back", onClick = function() ns.Views.ShowPage(nil) end }, { text = "The player's page" } }
			end })
			local saved = { chatWin = ns.db.chatWin, arenaUI = ns.db.arenaUI, consentAsked = ns.db.consentAsked }
			local chatWin, arenaUI = { point = { "CENTER", 1, 2 }, room = "A" }, { tab = "arena:events", seen = { x = true } }
			ns.db.chatWin, ns.db.arenaUI, ns.db.consentAsked = chatWin, arenaUI, { location = true }
			local ok, err = pcall(function()
				UI.SelectTab("realm")
				ns.Views.ShowPage("selftestmine")
				eq(UI.PageId(), "realm/selftestmine")
				local report = Run(w)
				eq(UI.PageId(), "realm/selftestmine", "the page it was on")
				eq(UI.IsShown(), true, "still open")
				eq(ns.db.chatWin, chatWin, "the same table"); eq(ns.db.chatWin.room, "A"); eq(ns.db.chatWin.point[3], 2)
				eq(ns.db.arenaUI, arenaUI); eq(ns.db.arenaUI.tab, "arena:events"); eq(ns.db.arenaUI.seen.x, true)
				eq(ns.db.consentAsked.location, true)
				eq(ProbeOf(report, "ui.restore").result, "ok", ProbeOf(report, "ui.restore").detail)
				eq(ProbeOf(report, "selftest.invariants").result, "ok", ProbeOf(report, "selftest.invariants").detail)
				-- Closed before: closed after, on the tab it had.
				UI.SelectTab("decrees")
				UI.Toggle()
				eq(UI.IsShown(), false)
				Run(w)
				eq(UI.IsShown(), false, "closed again")
				UI.Toggle()
				eq(UI.PageId(), "decrees/", "its tab")
			end)
			ns.db.chatWin, ns.db.arenaUI, ns.db.consentAsked = saved.chatWin, saved.arenaUI, saved.consentAsked
			if not ok then error(err, 0) end
		end)
	end)
end)

test("selftest: a window's own redraws while it runs (an event, a timer: outside any step) are fenced too, and their sends counted; after, the redraw is its own again", function()
	Scene(function(w)
		InWindow(function()
			local spied, savedSend = {}, ns.Comm.Send
			local ok, err = pcall(function()
				ns.Comm.Send = function() spied[#spied + 1] = "Comm.Send" return false end
				local spy = ns.Comm.Send
				local redraws = 0
				local window = {}
				window.Refresh = function() redraws = redraws + 1 ns.Comm.Send("CHANNEL", "SELFTESTW~x", "x") end
				local own = window.Refresh
				eq(S.FenceRedraws(window, "Refresh"), false, "no run: nothing to fence")
				assert(S.Start())
				w.Pump(3)
				eq(S.Running(), true)
				eq(S.FenceRedraws(window, "Refresh"), true)
				window.Refresh() -- (between two steps: the window's own timer)
				eq(redraws, 1, "it drew")
				ns.Comm.Send("CHANNEL", "SELFTESTW~y", "y") -- (not a redraw, not a step: the player's own)
				w.Pump()
				eq(table.concat(spied, ","), "Comm.Send", "only the send outside a redraw went out")
				eq(ns.db.selftest.summary.sends.SELFTESTW, 1, "the redraw's send held and counted")
				eq(window.Refresh, own, "its own redraw again"); eq(ns.Comm.Send, spy)
			end)
			ns.Comm.Send = savedSend
			if not ok then error(err, 0) end
		end)
	end)
end)

test("selftest: combat in the middle stops it: everything put back at once, the report says combat, the fence and the error tap gone", function()
	Scene(function(w)
		InWindow(function(UI)
			local send, capture = ns.Comm.Send, ns.CaptureError
			UI.SelectTab("census")
			assert(S.Start())
			w.Pump(40)
			eq(S.Running(), true, "still running")
			assert(ns.Comm.Send ~= send, "the fence is up while it runs")
			S.OnEvent("PLAYER_REGEN_DISABLED")
			eq(S.Running(), false, "stopped at once")
			eq(w.printed[#w.printed], L.SELFTEST_ABORT_COMBAT)
			eq(ns.db.selftest.summary.aborted, "combat")
			eq(ns.Comm.Send, send, "Comm.Send is its own again"); eq(ns.CaptureError, capture, "and ns.CaptureError")
			eq(UI.PageId(), "census/", "the window as it was"); eq(UI.IsShown(), true)
			assert(ProbeOf(ns.db.selftest, "ui.restore"), "its closing ran")
			w.Pump()
			eq(S.Running(), false, "the frame asked for before finds nothing to do")
		end)
	end)
end)

test("selftest: /oly selftest status opens the last report in the copy window; with none it says so", function()
	Scene(function(w)
		local shown
		local savedUI = ns.UI
		ns.UI = setmetatable({ ShowCopy = function(title, text, action, opts) shown = { title = title, text = text, opts = opts } end }, { __index = savedUI })
		local ok, err = pcall(function()
			SlashCmdList.OLYMPUS("selftest status")
			eq(w.printed[#w.printed], L.SELFTEST_NO_REPORT); eq(shown, nil)
			ns.db.selftest = { at = 1800000000, summary = { ok = 3, warn = 1, fail = 0, skip = 2, noBack = { "church/detail:*" } },
				probes = { { id = "ui.back", result = "warn", detail = "without a Back: church/detail:*" } }, build = {}, client = {} }
			SlashCmdList.OLYMPUS("selftest status")
			assert(shown, "shown")
			eq(shown.opts.key, "selftest"); eq(shown.title, L.SELFTEST_TITLE)
			eq(shown.text, S.ReportText(ns.db.selftest))
			assert(shown.text:find(L.SELFTEST_DONE:format(3, 1, 0, 2), 1, true), "its totals")
			assert(shown.text:find("church/detail:*", 1, true), "the page without a Back")
			assert(shown.text:find(L.SELFTEST_RELOAD, 1, true), "and the /reload")
		end)
		ns.UI = savedUI
		if not ok then error(err, 0) end
	end)
end)

test("selftest: paced: a frame runs one window's step alone, light steps until the frame's few milliseconds are spent", function()
	Scene(function(w)
		InWindow(function()
			local clock = 0
			S.Clock = function() clock = clock + 1 return clock end
			local ticks = {}
			S.trace = function(tick, id, heavy)
				ticks[tick] = ticks[tick] or { light = 0, heavy = 0 }
				if heavy then ticks[tick].heavy = ticks[tick].heavy + 1 else ticks[tick].light = ticks[tick].light + 1 end
			end
			Run(w)
			local batched, n = false, 0
			for tick, t in pairs(ticks) do
				n = n + 1
				assert(t.heavy <= 1, "two windows in frame " .. tick)
				if t.heavy == 1 then eq(t.light, 0, "a window's step runs alone: frame " .. tick) end
				assert(t.light <= S.BUDGET_MS, "past the budget in frame " .. tick .. ": " .. t.light)
				if t.light > 1 then batched = true end
			end
			assert(n > 20, "many frames: " .. n)
			assert(batched, "light steps share a frame")
		end)
	end)
end)

test("selftest: its lines in English and Portuguese, with the same codes; the TOC loads its words with the locales and its file the core's last, before the Arena's own files", function()
	local function Codes(s) local out = {} for c in tostring(s):gmatch("%%[%d%.%-]*%a") do out[#out + 1] = c end return table.concat(out, " ") end
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local pt = { L = setmetatable({}, { __index = function(_, k) return k end }) }
	local ok, err = pcall(assert(loadfile(ROOT .. "Olympus/Locales/SelfTestText.lua")), "Olympus", pt)
	GetLocale = savedLocale
	assert(ok, err)
	local n = 0
	for k, v in pairs(L) do
		if type(k) == "string" and k:find("^SELFTEST_") then
			n = n + 1
			local p = rawget(pt.L, k)
			assert(type(p) == "string" and p ~= v, k .. ": its Portuguese")
			eq(Codes(p), Codes(v), k)
		end
	end
	assert(n >= 20, "its lines: " .. n)
	local toc = assert(io.open(ROOT .. "Olympus/Olympus.toc")):read("*a")
	local lines = {}
	for line in toc:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
	local at = {}
	for i, line in ipairs(lines) do at[line] = i end
	-- (Every module it reads is looked up when it runs: its place is the core's last, before the
	-- Arena's load tail, whose files the arena's own rules cover.)
	assert(at["SelfTest.lua"] and at["ArenaMath.lua"], "both listed")
	eq(at["SelfTest.lua"], at["ArenaMath.lua"] - 1, "the core's last file, before the Arena's load tail")
	assert(toc:find("Locales\\SelfTestText.lua\nCore.lua", 1, true), "with the locales, before Core.lua")
	assert(assert(io.open(ROOT .. "Olympus/Core.lua")):read("*a"):find('StandIn("SelfTest", { "Slash" })', 1, true), "its stand-in")
end)

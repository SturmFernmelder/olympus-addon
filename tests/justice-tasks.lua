local base, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]justice%-tasks%.lua$") or "./"
-- Actual Comm queue/dispatch, native Roster.Scan/Fresh, Members manual removal and Watch UI.
-- The simulated server supplies identity/appointment verdicts and its native roster rows.
local function Client(name)
	local w = { name = name, guild = "Olympus II", now = 1800000000, sent = {}, events = {}, listeners = {}, ranks = {},
		justice = "Justice-Realm", council = { ["Council-Realm"] = true }, native = {}, dialogs = {} }
	local n = setmetatable({ me = name, realm = "Realm", group = "Realm", faction = "Alliance", CAPTAIN_RANK = 1,
		db = { blocked = {} }, rdb = { guilds = {} }, ViewAs = {}, WatchChat = {}, Nominees = {}, King = {}, Workshop = {}, UI = {},
		Moderation = { Blocks = function() return false end }, TabardsV2 = { SurfaceVisible = function() return false end },
		Judgment = { Visible = function() return false end }, RealmPages = {} }, { __index = base })
	w.ns = n
	n.Now = function() return w.now end; n.Fold = string.lower
	n.FullName = function(s) return s:find("-", 1, true) and s or s .. "-Realm" end
	n.ShortName = function(s) return s:match("^[^-]+") end; n.DisplayName = n.ShortName
	n.Moderation.CharName = function(s) return type(s) == "string" and n.FullName(s) or nil end
	n.RealmOf = function(s) return s:match("%-(.+)$") end; n.GroupOf = function(s) return s end
	n.IsMember = function() return w.guild ~= nil end; n.IsFederation = function(g) return g == "Olympus II" or g == "Olympus III" end
	n.IsKingCharacter = function(s) return s == "Crown-Realm" end; n.IsHighCouncillor = function(s) return w.council[s] == true end
	n.KingRealm = function() return "Realm" end; n.IsKingGuild = function() return false end
	n.King.Preview = function() return w.preview == true end; n.King.IsKing = function() return n.IsKingCharacter(n.me) end
	n.Workshop.IsAuthor = function() return n.me == "Author-Realm" end; n.Workshop.Visible = function() return false end
	n.ViewAs.Previewing = n.King.Preview; n.ViewAs.Available = function() return false end
	n.WatchChat.Justice = function() return w.justice end
	n.WatchChat.IsNamedWatcher = function(s) return s == w.justice end
	n.WatchChat.PowersBarred = function() return w.barred and "blocked" or nil end
	n.Nominees.IsCorrespondent = function(s) return s == w.justice end
	n.Data = { AuthorizedRank = function(s, guild)
		if guild == w.guild then local rank = w.ranks[s]; return rank, rank ~= nil and "roster" or nil end
		local fact = w.remote and w.remote[s]; if fact then return fact.rank, fact.source end
	end }
	n.Zones = { KeyForName = function() return nil end }
	n.On = function(event, fn) w.listeners[event] = w.listeners[event] or {}; table.insert(w.listeners[event], fn) end
	n.Fire = function(event, ...) for _, fn in ipairs(w.listeners[event] or {}) do fn(...) end end
	n.RegisterEvent = function(event, fn) w.events[event] = fn end
	n.After, n.Every, n.Print, n.Log = function() end, function() end, function() end, function() end
	n.SafeCall = function(_, fn, ...) return fn(...) end
	n.ShowDialog = function(which, a, b, data) w.dialogs[#w.dialogs + 1] = { which = which, data = data }; return true end
	n.CouncilMasked = function() return false end
	local rows = {}
	local env = setmetatable({ StaticPopupDialogs = {}, GetGuildInfo = function() return w.guild, "Rank", w.ranks[n.me] or 9 end,
		IsInGuild = function() return w.guild ~= nil end, GetTime = function() return w.now end, GetServerTime = function() return math.floor(w.now) end,
		GetNumGuildMembers = function() return #rows + (w.partial and 1 or 0), #rows end,
		GetGuildRosterInfo = function(i) local row = rows[i]; if row then return row.name, "Member", row.rank, 60, "Warrior", "Town", "", "", true, 0, "WARRIOR" end end,
		GuildControlGetNumRanks = function() return 0 end, GetGuildRosterLastOnline = function() return 0, 0, 0, 0 end,
		CanGuildRemove = function() return w.canRemove ~= false end,
		C_GuildInfo = { GuildRoster = function() end, Uninvite = function(raw) w.native[#w.native + 1] = raw end },
		GetChannelName = function() return 0 end, JoinChannelByName = function() end, LeaveChannelByName = function() end, HideChannelFromChat = function() end,
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
			SendAddonMessage = function(_, text, dist, target) w.sent[#w.sent + 1] = { text = text, dist = dist, target = target, logged = false }; return 0 end,
			SendAddonMessageLogged = function(_, text, dist, target) w.sent[#w.sent + 1] = { text = text, dist = dist, target = target, logged = true }; return 0 end } }, { __index = _G })
	w.env = env
	local function Load(file) local f = assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua")); setfenv(f, env); f("Olympus", n) end
	Load("Comm"); for _, login in ipairs(w.listeners.LOGIN or {}) do login() end
	Load("Roster"); Load("Members"); Load("Watch"); Load("JusticeTasks")
	function w.scan()
		rows = {}; for who, rank in pairs(w.ranks) do rows[#rows + 1] = { name = who, rank = rank } end
		table.sort(rows, function(a, b) return a.name < b.name end); n.Roster.Scan()
	end
	function w.pump() for _ = 1, 20 do w.now = w.now + 1.2; n.Comm.Pump() end end
	function w.receive(sender, text, logged)
		local event = logged == false and "CHAT_MSG_ADDON" or "CHAT_MSG_ADDON_LOGGED"
		if not w.events[event] then event = "CHAT_MSG_ADDON" end
		return w.events[event](n.PREFIX, text, "WHISPER", sender)
	end
	function w.reloadTasks() Load("JusticeTasks") end
	return w
end
local function Setup()
	local a, b = Client("Crown-Realm"), Client("Justice-Realm")
	for _, w in ipairs({ a, b }) do w.ranks = { ["Crown-Realm"] = 0, ["Justice-Realm"] = 1, ["Subject-Realm"] = 9, ["Other-Realm"] = 9, ["Council-Realm"] = 3, ["Author-Realm"] = 9 }; w.scan() end
	return a, b
end
local function Row(w, key) for _, e in ipairs(w.ns.JusticeTasks.Tasks()) do if e.key == key then return e.task end end end
local function Last(w, op) for i = #w.sent, 1, -1 do if w.sent[i].text:sub(1, 7) == "JT~1~" .. op .. "~" then return w.sent[i].text end end end
local function Issue(a, b)
	local ok, key = a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject-Realm"); assert(ok); a.pump()
	return key, assert(Last(a, "I"))
end
local function Receive(a, b, key, text)
	b.now = a.now; b.scan(); b.receive(a.name, text); b.pump(); a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "R")))
	assert(Row(a, key).receivedAt); return Row(b, key)
end
local function Attempt(a, b, key)
	b.now = b.now + 30; b.scan(); assert(b.ns.JusticeTasks.AskRemoval(key))
	local dialog = b.dialogs[#b.dialogs]; eq(dialog.which, "OLYMPUS_GUILD_REMOVE")
	assert(b.ns.Members.Remove(dialog.data)); b.pump(); a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "R")))
end
local function Absent(a, b, key)
	b.now = b.now + 10; b.ranks["Subject-Realm"] = nil; b.scan(); b.ns.Fire("DATA_CHANGED"); b.pump()
	a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "R"))); assert(Row(a, key).absentAt)
end

test("Justice tasks: a real private receipt starts the clock, never creation offline or a generic successful send", function()
	local a, b = Setup(); local key, text = Issue(a, b)
	eq(Row(a, key).receivedAt, nil); eq(#b.native, 0)
	b.now = a.now + 3600; b.scan(); b.receive(a.name, text)
	local t = Row(b, key); eq(t.receivedAt, math.floor(b.now)); assert(t.receivedAt > t.createdAt)
	b.pump(); a.now = b.now; a.scan(); a.receive(b.name, Last(b, "R")); eq(Row(a, key).receivedAt, t.receivedAt)
	for _, packet in ipairs(a.sent) do eq(packet.dist, "WHISPER"); eq(packet.logged, true); eq(a.ns.FullName(packet.target), b.name, "Comm uses the native same-realm short whisper target") end
	b.ns.Watch.Show("justice"); local lines = b.ns.Watch.Build(); assert(#lines > 0); eq(#b.native, 0, "opening private activity never removes anyone")
end)

test("Justice tasks: manual native attempt and fresh absence stay pending until explicit original staff review", function()
	local a, b = Setup(); local key, text = Issue(a, b); local t = Receive(a, b, key, text)
	eq(a.ns.JusticeTasks.Confirm(key), false)
	Attempt(a, b, key); eq(#b.native, 1); eq(b.native[1], "Subject-Realm")
	eq(Row(a, key).confirmedAt, nil); eq(a.ns.JusticeTasks.Confirm(key), false)
	local old = Last(b, "R"); Absent(a, b, key)
	eq(Row(a, key).confirmedAt, nil); eq(Row(b, key).confirmedAt, nil)
	a.receive(b.name, old); assert(Row(a, key).absentAt, "older phase cannot roll back newer evidence")
	assert(a.ns.JusticeTasks.Confirm(key)); a.pump(); b.now = a.now; b.scan(); b.receive(a.name, Last(a, "F")); b.pump()
	a.now = b.now; a.scan(); a.receive(b.name, Last(b, "A"))
	eq(Row(a, key).confirmedBy, a.name); eq(Row(a, key).terminalAck, "F"); eq(Row(b, key).confirmedBy, a.name)
	eq(b.ns.JusticeTasks.AskRemoval(key), false); eq(#b.native, 1)
	assert(t.attemptedAt - t.receivedAt < 100, "elapsed time is receipt to manual attempt, not the offline creation gap")
end)

test("Justice tasks: spoofing, foreign guild/subject, preview, replay conflicts and unrelated reporters cannot grant access", function()
	local a, b = Setup(); local key, text = Issue(a, b)
	b.receive("Other-Realm", text); eq(#b.ns.JusticeTasks.Tasks(), 0)
	b.receive(a.name, text:gsub("Subject%-Realm", "Justice-Realm")); eq(#b.ns.JusticeTasks.Tasks(), 0)
	b.receive(a.name, text:gsub("Olympus II", "Olympus III")); eq(#b.ns.JusticeTasks.Tasks(), 0)
	b.receive(a.name, text:gsub("~A~", "~H~")); eq(#b.ns.JusticeTasks.Tasks(), 0, "factions stay isolated")
	b.receive("Crown-Elsewhere", text); eq(#b.ns.JusticeTasks.Tasks(), 0, "another realm group is not the pinned issuer")
	b.receive(a.name, "JT~1~invalid"); eq(#b.ns.JusticeTasks.Tasks(), 0)
	b.preview = true; b.receive(a.name, text); eq(#b.ns.JusticeTasks.Tasks(), 0); b.preview = false
	Receive(a, b, key, text); local received = Row(b, key).receivedAt
	b.now = b.now + 30; b.scan(); b.receive(a.name, text); eq(Row(b, key).receivedAt, received)
	b.receive(a.name, text:gsub("Subject%-Realm", "Other-Realm")); eq(Row(b, key).subject, "Subject-Realm")
	a.receive("Other-Realm", Last(b, "R")); eq(Row(a, key).attemptedAt, nil)
	b.ns.me = "Other-Realm"; eq(b.ns.JusticeTasks.Visible(), false); eq(#b.ns.JusticeTasks.Tasks(), 0); eq(#b.ns.JusticeTasks.Lines(), 0)
	b.ns.me = "Author-Realm"; eq(b.ns.JusticeTasks.Staff(), true); eq(b.ns.JusticeTasks.CanIssue(), false)
	b.preview = true; eq(b.ns.JusticeTasks.Staff(), false)
end)

test("Justice tasks: confirmed terminal delivery recovers without old-phase rollback or false acknowledgement credit", function()
	local a, b = Setup(); local key, text = Issue(a, b); Receive(a, b, key, text); Attempt(a, b, key); Absent(a, b, key)
	local prior = Last(b, "R")
	assert(a.ns.JusticeTasks.Confirm(key)); local confirmedAt = Row(a, key).confirmedAt
	a.pump(); eq(Row(b, key).confirmedAt, nil, "the first terminal send is deliberately not delivered")
	-- The assignee's original pending receipt is a bounded recovery ask; it cannot overwrite
	-- the issuer's terminal record or turn a reported observation into a second completion.
	a.now = a.now + 60; a.scan(); a.receive(b.name, prior); a.pump()
	eq(Row(a, key).confirmedAt, confirmedAt)
	b.now = a.now; b.scan(); b.receive(a.name, assert(Last(a, "F"))); b.pump()
	local ack = assert(Last(b, "A")); a.now = b.now; a.scan()
	a.receive("Other-Realm", ack); eq(Row(a, key).terminalAck, nil)
	a.receive(b.name, ack:gsub("~F~", "~X~")); eq(Row(a, key).terminalAck, nil)
	a.receive(b.name, ack); eq(Row(a, key).terminalAck, "F")
	b.receive(a.name, Last(a, "F")); eq(Row(b, key).confirmedAt, confirmedAt, "terminal replay is idempotent")
	eq(a.ns.JusticeTasks.Confirm(key), false); eq(#b.native, 1)
end)

test("Justice tasks: cancellation before an issue and bounded terminal retries cannot recreate work or native powers", function()
	local a, b = Setup(); local key, text = Issue(a, b)
	assert(a.ns.JusticeTasks.Cancel(key)); a.pump(); local cancel = assert(Last(a, "X"))
	b.now = a.now; b.scan(); b.receive(a.name, cancel); b.receive(a.name, text)
	eq(#b.ns.JusticeTasks.Tasks(), 0, "a direct original cancellation retires even a reordered unseen issue")
	for _ = 1, a.ns.JusticeTasks.RETRY_MAX + 5 do a.now = a.now + 60; a.scan(); a.ns.JusticeTasks.Tick(); a.pump() end
	local count = 0; for _, packet in ipairs(a.sent) do if packet.text:sub(1, 7) == "JT~1~X~" then count = count + 1 end end
	eq(count, a.ns.JusticeTasks.RETRY_MAX, "terminal traffic has a hard bound, not indefinite blind resends")
	eq(#b.native, 0); eq(Row(a, key).confirmedAt, nil)
	assert(a.ns.JusticeTasks.Retry(key)); a.pump(); eq(Row(a, key).terminalTries, 1, "explicit original issuer retry is available after the bound")
end)

test("Justice tasks: task storage and worst-case private packets remain bounded; no request can target the King", function()
	local a, b = Setup(); eq(a.ns.JusticeTasks.Issue(a.guild, b.name, a.name), false, "the pinned King's exact full name is protected")
	for i = 1, a.ns.JusticeTasks.MAX + 1 do a.ranks["Subject" .. i .. "-Realm"] = 9 end; a.scan()
	for i = 1, a.ns.JusticeTasks.MAX do assert(a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject" .. i .. "-Realm")) end
	eq(select(2, a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject61-Realm")), "full")
	eq(#a.ns.JusticeTasks.Tasks(), a.ns.JusticeTasks.MAX); eq(#a.native, 0)
	local c = Client("Crown-Realm")
	local assignee, subject = "J" .. string.rep("j", 65) .. "-Realm", "S" .. string.rep("s", 65) .. "-Realm"
	c.guild = "Olympus " .. string.rep("g", 64); c.justice = assignee; c.ranks = { [c.name] = 0, [assignee] = 1, [subject] = 9 }
	c.ns.IsFederation = function(guild) return guild == c.guild end; c.scan()
	eq(#assignee, 72); eq(#subject, 72); eq(#c.guild, 72)
	assert(c.ns.JusticeTasks.Issue(c.guild, assignee, subject)); c.pump()
	local packet = assert(Last(c, "I")); assert(#packet <= 255, "all three maximum fields fit one private packet")
	eq(#c.native, 0)
end)

test("Justice tasks: stale manual buttons and queued messages lose appointment, guild and issuer authority", function()
	local a, b = Setup(); local key, text = Issue(a, b); Receive(a, b, key, text)
	assert(b.ns.JusticeTasks.AskRemoval(key)); local m = b.dialogs[#b.dialogs].data
	b.justice = "Other-Realm"; eq(b.ns.Members.Remove(m), false); eq(#b.native, 0)
	b.justice = b.name; b.guild = "Olympus III"; b.scan(); eq(b.ns.Members.Remove(m), false); eq(#b.native, 0)
	b.guild = "Olympus II"; b.scan(); b.ranks["Subject-Realm"] = 0; b.scan(); eq(b.ns.Members.Remove(m), false); eq(#b.native, 0)
	local c, d = Setup(); local ok, queued = c.ns.JusticeTasks.Issue(c.guild, d.name, "Subject-Realm"); assert(ok)
	c.preview = true; c.pump(); eq(Last(c, "I"), nil); eq(Row(c, queued), nil, "preview exposes no real activity")
	local h = Client("Council-Realm"); h.ranks = a.ranks; h.scan(); local accepted, ownKey = h.ns.JusticeTasks.Issue(h.guild, "Justice-Realm", "Other-Realm"); assert(accepted)
	h.council[h.name] = nil; h.pump(); eq(Last(h, "I"), nil)
end)

test("Justice tasks: partial/filtered or pre-attempt absence never proves completion, even with a fresh-looking cache", function()
	local a, b = Setup(); local key, text = Issue(a, b); Receive(a, b, key, text); Attempt(a, b, key)
	b.ranks["Subject-Realm"] = nil; b.partial = true; b.scan(); eq(b.ns.Roster.complete, false)
	b.ns.Fire("DATA_CHANGED"); eq(Row(a, key).absentAt, nil)
	b.partial = false; b.scan(); b.ns.Fire("DATA_CHANGED"); assert(Row(b, key).absentAt)
	eq(Row(b, key).confirmedAt, nil); eq(#b.native, 1)
end)

test("Justice tasks: reloaded native absence cannot reuse a process-local generation or an undated cache", function()
	local a, b = Setup(); local key, text = Issue(a, b); Receive(a, b, key, text); Attempt(a, b, key)
	b.reloadTasks(); b.ranks["Subject-Realm"] = nil; b.now = b.now + 10; b.scan()
	b.ns.Roster.serverAt = nil; b.ns.JusticeTasks.Observe(); eq(Row(b, key).absentAt, nil)
	b.scan(); b.ns.JusticeTasks.Observe(); assert(Row(b, key).absentAt, "a new native complete server-dated post-attempt capture can observe absence")
	eq(Row(b, key).confirmedAt, nil, "reload does not certify actor or completion")
end)

test("Justice tasks: terminal cancellation recovers privately, stops old buttons and cannot reopen after replay or eviction", function()
	local a, b = Setup(); local key, text = Issue(a, b); Receive(a, b, key, text)
	assert(b.ns.JusticeTasks.AskRemoval(key)); local oldButton = b.dialogs[#b.dialogs].data
	assert(a.ns.JusticeTasks.Cancel(key)); a.pump(); local cancelled = assert(Last(a, "X"))
	eq(Row(b, key).cancelledAt, nil, "send alone is not delivery")
	a.now = a.now + 60; a.scan(); a.ns.JusticeTasks.Tick(); a.pump(); assert(Last(a, "X"))
	b.now = a.now; b.scan(); b.receive(a.name, cancelled); eq(b.ns.Members.Remove(oldButton), false)
	b.pump(); a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "A"))); eq(Row(a, key).terminalAck, "X")
	b.receive(a.name, text); assert(Row(b, key).cancelledAt)
	b.receive(a.name, cancelled); assert(Row(b, key).cancelledAt)
	b.now = b.now + b.ns.JusticeTasks.KEEP + 1; b.scan(); b.ns.JusticeTasks.Prune(); eq(#b.ns.JusticeTasks.Tasks(), 0)
	b.now = 1800000100; b.scan(); b.receive(a.name, text); eq(#b.ns.JusticeTasks.Tasks(), 0, "independent retired-id floor refuses resurrection")
end)

test("Justice tasks: report counts are separate latest retained accepted pairs with partial coverage, not lifetime work", function()
	local a, b = Setup()
	local function Report(seq) a.receive(b.name, ("MR~1~C~%d~%d~Olympus II~Realm~Alliance~A~Subject-Realm~0~Report"):format(seq, a.now)) end
	Report(1); local store = a.ns.Watch.CouncilStore(false); assert(store)
	local m = a.ns.JusticeTasks.ReportMetric(); eq(m.retained, 1); eq(m.by[b.name], 1); eq(m.partial, true)
	a.now = a.now + 60; a.scan(); Report(2); eq(a.ns.JusticeTasks.ReportMetric().retained, 1, "newest accepted pair replaces, not another lifetime report")
	store.reports["justice-realm#subject-realm"].at = a.now - a.ns.Watch.REPORT_KEEP - 1
	eq(a.ns.JusticeTasks.ReportMetric().retained, 0, "expired evidence is not invented history")
	local expected = (rawget(a.ns.L, "JUSTICE_TASKS_REPORT_COUNT") or "Locally retained accepted report pairs: %d (partial coverage)."):format(0)
	local zero = false; for _, line in ipairs(a.ns.JusticeTasks.Lines()) do if line.text == expected then zero = true end end
	eq(zero, true, "empty retained evidence explicitly says local zero, never lifetime zero")
	eq(b.ns.JusticeTasks.ReportMetric(), nil, "missing local council evidence stays unknown")
end)

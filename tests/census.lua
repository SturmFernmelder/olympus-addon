-- Census boundaries and alt membership revisions. Loaded by tests/run.lua.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%.lua$")) or "./"
local Codec = ns.Codec

local function Decode(fields)
	fields.guild = fields.guild or "Olympus Test"
	return Codec.DecodeReport(Codec.EncodeReport(fields))
end

test("census: a zero-member report cannot contribute online members", function()
	local r = assert(Decode({ total = 0, online = 10000 }))
	eq(r.online, 0)
	eq(Decode({ total = 0, online = 10000, zones = { m1453 = 10000 } }), nil)
end)
test("census: zone, class and level distributions cannot exceed online members", function()
	for _, field in ipairs({ "zones", "classes", "levels" }) do
		local counts = field == "levels" and { 3, 3 } or { a = 3, b = 3 }
		local r = { total = 10, online = 5, [field] = counts }
		eq(Decode(r), nil, field .. ": individually plausible counts, impossible sum")
	end
	eq(Decode({ total = 1000, online = 5000, zones = { m1453 = 10000 } }), nil)
end)

test("census: partial, privacy-suppressed and older reports keep their wire contract", function()
	local r = assert(Decode({ total = 100, online = 20, zones = { m1453 = 3 }, classes = { WA = 2 }, levels = { 1, 1 } }))
	eq(r.online, 20); eq(r.zones.m1453, 3); eq(r.classes.WA, 2); eq(r.levels[1], 1)
	local hidden = Codec.Shareable(r, false, nil)
	local d = assert(Decode(hidden))
	eq(next(d.zones), nil); eq(d.online, 20)
	local old = assert(Codec.DecodeReport("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0"))
	eq(old.online, 2); eq(old.zones.m1453, 2)
	local clamped = assert(Decode({ total = 10, online = 20 }))
	eq(clamped.online, 10, "the existing online clamp remains")
end)

-- 1.2.3, the memory peaks on the owner's PC: about 40 census reports a minute were each decoded and
-- voted from scratch. A sender's report again but for its time (field 25) is now its row again.
-- Data.lua in a namespace of its own (its claims, kept reports and revision fresh), its DATA_CHANGED
-- fires, timers, log lines and decodes counted here, the clock the test's.
local function CensusWorld()
	local w = { fires = 0, timers = {}, logs = {}, decodes = 0, clock = 2000000000, on = {}, events = {} }
	local codec = setmetatable({
		DecodeReport = function(s) w.decodes = w.decodes + 1 return Codec.DecodeReport(s) end,
	}, { __index = Codec })
	local dns = setmetatable({
		rdb = { guilds = {}, seen = {} },
		Codec = codec,
		Who = { Listen = function() end },
		On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end,
		RegisterEvent = function(event, fn) w.events[event] = w.events[event] or {}; table.insert(w.events[event], fn) end,
		Every = function() end,
		Fire = function(name) if name == "DATA_CHANGED" then w.fires = w.fires + 1 end end,
		After = function(seconds, where, fn) w.timers[#w.timers + 1] = { seconds = seconds, where = where, fn = fn } end,
		Now = function() return w.clock end,
		Log = function(fmt, ...)
			local ok, line = pcall(string.format, fmt, ...)
			w.logs[#w.logs + 1] = ok and line or fmt
		end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/Data.lua"))("Olympus", dns)
	w.ns, w.D = dns, dns.Data
	function w.Run()
		local due = w.timers
		w.timers = {}
		for _, t in ipairs(due) do t.fn() end
		return #due
	end
	function w.Fire(name, ...) for _, fn in ipairs(w.on[name] or {}) do fn(...) end end
	return w
end

-- Two values alike, tables compared value by value whatever their identity; the first difference.
local function Alike(a, b, path)
	if type(a) ~= "table" or type(b) ~= "table" then
		if a ~= b then return ("%s: %s, not %s"):format(path, tostring(a), tostring(b)) end
		return nil
	end
	for k, v in pairs(a) do
		local diff = Alike(v, b[k], path .. "." .. tostring(k))
		if diff then return diff end
	end
	for k in pairs(b) do
		if a[k] == nil then return path .. "." .. tostring(k) .. ": missing" end
	end
	return nil
end

-- A report's text as its sender's client sends it (Comm.Broadcast), with its own server time.
local function ReportText(fields, st)
	local r = {}
	for k, v in pairs(fields) do r[k] = v end
	r.st = st
	return Codec.EncodeReport(r)
end
local function Echo(changes)
	local r = { guild = "Olympus Echo", total = 40, online = 6, leader = "Echoboss", leaderOnline = true, users = 3,
		zones = { m1453 = 2, m1429 = 1 }, classes = { WA = 2, PR = 1 }, levels = { 0, 0, 0, 0, 0, 1, 2 },
		ranks = { { name = "Boss", count = 1 }, { name = "Captain", count = 2 }, { name = "Member", count = 37 } },
		officers = { { name = "Echocapt", online = true, days = 0, class = "WA", level = 60, zone = "m1453" } },
		leaderDays = 0, inactive7 = 3, inactive30 = 9, avgLevel = 41.5,
		top = { { name = "Echoboss", level = 60, class = "WA" }, { name = "Echocapt", level = 60, class = "WA" } },
		leaderClass = "WA", leaderLevel = 60, leaderZone = "m1453", from = "Realm", home = "Realm",
		versions = { ["1.2.2"] = 3 }, cap = "a", pres = { "k3a" } }
	for k, v in pairs(changes or {}) do r[k] = v end
	return r
end

test("census (1.2.3): a sender's report again but for its time is not decoded, and the census is what decoding every report made it: rows, votes, marks, DATA_CHANGED, Revision and the log (a fixture of 22 reports)", function()
	-- The same reports to two clients: one through Data.DecodeReport (as Comm.lua hears them now),
	-- one decoding each (Codec.DecodeReport, as 1.2.2's Comm.lua did). After every report both
	-- censuses are alike in every field of every row.
	local P, P2 = Echo(), Echo({ online = 5, zones = { m1453 = 2 }, levels = { 0, 0, 0, 0, 0, 1, 1 } })
	local Q = Echo({ leader = "Usurper", top = { { name = "Usurper", level = 60, class = "WA" } } })
	local X = Echo({ guild = "Olympus Tide", leader = "Tideboss", officers = {}, top = {} })
	local Y = Echo({ guild = "Olympus Tide", leader = "Tidefake", officers = {}, top = {} })
	local OTHER = Echo({ guild = "OLYMPUS ECHO" }) -- (the stored key's other spelling: one more vote)
	-- { seconds after the first report, sender, report, its server time, what to look for }
	local steps = {
		{ 0, "Tidea-Realm", X }, { 1, "Tideb-Realm", X }, -- (votes that will be 30 minutes old later)
		{ 10, "Echoa-Realm", P }, -- a new row
		{ 190, "Echoa-Realm", P, again = true }, -- the same but for its time: not decoded
		{ 190, "Echoa-Realm", P, again = true }, -- within NOTIFY_GAP: its row told before it is taken again
		{ 370, "Echob-Realm", P }, -- another sender of the guild: his row
		{ 550, "Echoa-Realm", P }, -- decoded again: the row is the other sender's
		{ 730, "Echoa-Realm", P2 }, -- changed: decoded
		{ 910, "Echoa-Realm", P2, again = true },
		{ 911, "Echoc-Realm", Q }, -- outvoted: the row stays, marked
		{ 1000, "Tidec-Realm", X }, { 1001, "Tided-Realm", X }, -- the row Tided's
		{ 1002, "Tidee-Realm", Y }, { 1003, "Tidef-Realm", Y }, { 1004, "Tideg-Realm", Y }, -- outvoted, kept as votes
		{ 1090, "Echoa-Realm", P2, again = true }, -- the outvoted mark goes as a new report's would
		{ 1091, "Echoe-Realm", OTHER }, -- another spelling: a vote on the row, taken, its text not kept
		{ 1270, "Echoe-Realm", OTHER },
		{ 1802, "Tided-Realm", X, again = true }, -- the first two votes gone (VOUCH_TTL): outvoted, its row kept
		{ 1803, "Tided-Realm", X, again = true },
		{ 1950, "Tided-Realm", X, again = true }, -- its row older than FRESH: taken
		{ 1990, "Echoa-Realm", P2 }, -- the row is the other spelling's sender's
	}
	local now, old = CensusWorld(), CensusWorld()
	local start, last = now.clock, now.clock
	for i, step in ipairs(steps) do
		local sender = step[2]
		local decodes = now.decodes
		local revNow, revOld = now.D.Revision(), old.D.Revision()
		now.clock, old.clock = start + step[1], start + step[1]
		if now.clock > last then now.Run(); old.Run() end -- (a second gone: the waiting timer ran)
		last = now.clock
		local text = ReportText(step[3], 1000 + step[1])
		local rNow = now.D.DecodeReport(text, sender)
		local takenNow = rNow ~= nil and now.D.Receive(rNow, sender)
		local takenOld = old.D.Receive(assert(Codec.DecodeReport(text)), sender)
		local label = "report " .. i .. " (" .. sender .. ")"
		eq(now.decodes - decodes, step.again and 0 or 1, label .. ": decoded")
		eq(takenNow, takenOld, label .. ": taken")
		eq(now.D.Revision() - revNow, old.D.Revision() - revOld, label .. ": revisions")
		eq(now.fires, old.fires, label .. ": DATA_CHANGED"); eq(#now.timers, #old.timers, label .. ": timers")
		eq(Alike(now.ns.rdb.guilds, old.ns.rdb.guilds, "guilds"), nil, label)
		eq(table.concat(now.logs, "\n"), table.concat(old.logs, "\n"), label .. ": log")
		for _, guild in ipairs({ "Olympus Echo", "Olympus Tide" }) do
			eq(Alike(now.D.Dispute(now.D.Guild(guild), now.clock), old.D.Dispute(old.D.Guild(guild), old.clock), "dispute"), nil, label .. " " .. guild)
		end
		eq(now.D.ClaimedGuild(sender), old.D.ClaimedGuild(sender), label .. ": claim")
	end
	-- What the fixture went through, so neither census was alike by having nothing in it.
	local echo, tide = now.ns.rdb.guilds["Olympus Echo"], now.ns.rdb.guilds["Olympus Tide"]
	eq(echo.reporterFull, "Echoa-Realm"); eq(echo.online, 5); eq(echo.st, 1000 + 1990)
	eq(tide.reporterFull, "Tided-Realm"); eq(tide.t, start + 1950); eq(tide.st, 1000 + 1950)
	assert(tide.vouch["Tidee-Realm"] and not tide.vouch["Tidea-Realm"], "the outvoted senders' votes kept, the old ones gone")
	assert(old.logs[1] and table.concat(old.logs, "\n"):find("is not what the other senders say", 1, true), "an outvoted report logged")
	eq(now.D.Repeats(), 2, "the two rows' senders' reports kept, the replaced ones' gone")
	-- Its row gone another way (a reset): decoded, and the kept reports go with the next tick.
	wipe(now.ns.rdb.guilds)
	now.D.Housekeeping()
	eq(now.D.Repeats(), 0)
	local decodes = now.decodes
	now.clock = now.clock + 180
	assert(now.D.Receive(assert(now.D.DecodeReport(ReportText(P2, 1), "Echoa-Realm")), "Echoa-Realm"))
	eq(now.decodes - decodes, 1, "a reset store: decoded")
end)

test("census (1.2.3): Codec.ReportTime finds field 25 where Codec.DecodeReport reads it, nil without one", function()
	for _, st in ipairs({ 0, 35, 1799999999, 36 ^ 8 - 1, false }) do
		local text = ReportText(Echo(), st or nil)
		local at, stop, t = Codec.ReportTime(text)
		eq(t, Codec.DecodeReport(text).st, tostring(st))
		eq(text:sub(at + 1, stop - 1), st and Codec.Base36(st) or "")
		eq(select(2, text:sub(1, at):gsub("~", "")), 24, "the 24 fields before it")
	end
	-- The last field (fields 26 and 27 left out).
	local short = table.concat(Codec.Split(ReportText(Echo(), 99), "~"), "~", 1, 25)
	local at, stop, t = Codec.ReportTime(short)
	eq(stop, #short + 1); eq(t, 99); eq(Codec.DecodeReport(short).st, 99); eq(at, #short - 2)
	eq(Codec.ReportTime("R1~Olympus~10~2~Boss~1~2~m1453=2~WA=2~0,2,0,0,0,0,0"), nil, "older versions: no field 25")
	eq(Codec.ReportTime(("~"):rep(30) .. ("x"):rep(Codec.CHUNK * Codec.MAX_CHUNKS)), nil, "a text DecodeReport refuses by its length")
	eq(Codec.ReportTime(nil), nil)
end)

test("census (1.2.3): through Comm's own handler a reporter's report again but for its time is its row, not decoded; changed, after another sender's, or after a reset, decoded", function()
	local FreshComm = assert(extra and extra.FreshComm, "tests/run.lua hands FreshComm to this file")
	local savedGuilds, savedDecode, savedNow = ns.rdb.guilds, Codec.DecodeReport, ns.Now
	local ok, err = pcall(function()
		local cns, _, Report = FreshComm()
		local decodes, clock = 0, 2000000000
		Codec.DecodeReport = function(s) decodes = decodes + 1 return savedDecode(s) end
		ns.Now = function() return clock end
		ns.rdb.guilds = {}
		local P, P2 = Echo({ guild = "Olympus Combo" }), Echo({ guild = "Olympus Combo", online = 5 })
		local function Send(sender, r, st)
			local copy = {}
			for k, v in pairs(r) do copy[k] = v end
			copy.st = st
			Report(sender, copy)
		end
		Send("Combo One-Realm", P, 1)
		eq(decodes, 1)
		local row = ns.rdb.guilds["Olympus Combo"]
		eq(row.reporterFull, "Combo One-Realm"); eq(row.st, 1)
		clock = clock + 180
		Send("Combo One-Realm", P, 2)
		eq(decodes, 1, "the same but for its time: not decoded")
		eq(ns.rdb.guilds["Olympus Combo"], row, "its row")
		eq(row.t, clock); eq(row.st, 2); eq(row.vouch["Combo One-Realm"].t, clock, "its vote's time new")
		clock = clock + 180
		Send("Combo Two-Realm", P, 3)
		eq(decodes, 2, "another sender: decoded"); eq(ns.rdb.guilds["Olympus Combo"].reporterFull, "Combo Two-Realm")
		clock = clock + 180
		Send("Combo One-Realm", P, 4)
		eq(decodes, 3, "his report after another sender's: decoded")
		clock = clock + 180
		Send("Combo One-Realm", P, 5)
		eq(decodes, 3)
		Send("Combo One-Realm", P2, 6)
		eq(decodes, 4, "changed: decoded"); eq(ns.rdb.guilds["Olympus Combo"].online, 5)
		ns.rdb.guilds = {} -- (/oly reset)
		Send("Combo One-Realm", P2, 7)
		eq(decodes, 5, "a reset store: decoded"); eq(ns.rdb.guilds["Olympus Combo"].st, 7)
		eq(cns.Comm.Stats().reports, 7, "every report counted")
		local lines = 0
		for _, line in ipairs(ns.db.log) do
			if line:find("report Olympus Combo from Combo", 1, true) then lines = lines + 1 end
		end
		eq(lines, 7, "every report taken logged as before")
	end)
	Codec.DecodeReport, ns.rdb.guilds, ns.Now = savedDecode, savedGuilds, savedNow
	if not ok then error(err, 0) end
end)

test("census (1.2.3): the reports kept are one per row: another sender's report of the guild, Data.Trim or a reset lets them go", function()
	local w = CensusWorld()
	local D = w.D
	local function Hear(sender, r, st)
		w.clock = w.clock + 1
		return D.Receive(assert(D.DecodeReport(ReportText(r, st), sender)), sender)
	end
	D.MAX_GUILDS = 3
	for k = 1, 3 do assert(Hear("Keeper" .. k .. "-Realm", Echo({ guild = "Olympus Keep " .. k }), k)) end
	eq(D.Repeats(), 3)
	assert(Hear("Keeper9-Realm", Echo({ guild = "Olympus Keep 1" }), 9))
	eq(D.Repeats(), 3, "the guild's other sender: his report kept, the first one's gone")
	assert(Hear("Keeper4-Realm", Echo({ guild = "Olympus Keep 4" }), 4))
	eq(w.ns.rdb.guilds["Olympus Keep 2"], nil, "the report heard longest ago went (Data.Trim)")
	eq(D.Repeats(), 3, "and its sender's with it")
	local decodes = w.decodes
	assert(Hear("Keeper2-Realm", Echo({ guild = "Olympus Keep 2" }), 5))
	eq(w.decodes - decodes, 1, "his row gone: decoded")
	-- A guild quiet for FRESH: its sender's report goes at the next tick; the others stay.
	w.clock = w.clock + D.FRESH - 1
	assert(Hear("Keeper4-Realm", Echo({ guild = "Olympus Keep 4" }), 6))
	w.clock = w.clock + 2
	D.Housekeeping()
	eq(D.Repeats(), 1, "the one heard within FRESH")
	decodes = w.decodes
	assert(Hear("Keeper4-Realm", Echo({ guild = "Olympus Keep 4" }), 7))
	eq(w.decodes - decodes, 0)
	w.ns.rdb = { guilds = {}, seen = {} } -- (another realm's store)
	D.Housekeeping()
	eq(D.Repeats(), 0)
end)

test("census (1.2.3): votes past VOUCH_TTL leave the rows at INIT and at logout, the others kept; what counts the votes reads as before", function()
	local w = CensusWorld()
	local D, now = w.D, w.clock
	local function Rows()
		local ranks = { ["Oldboss-Realm"] = 0, ["Oldcapt-Realm"] = 1 }
		local function Vote(age) return { t = now - age, sig = "Oldboss-Realm=0,Oldcapt-Realm=1", ranks = ranks, n = 30 } end
		return {
			["Olympus Old"] = { guild = "Olympus Old", t = now - 100, leader = "Oldboss", officers = { { name = "Oldcapt" } },
				realm = "Realm", heardOn = "Realm", total = 30, reporterFull = "Fresh One-Realm",
				vouch = { ["Fresh One-Realm"] = Vote(60), ["Fresh Two-Realm"] = Vote(D.VOUCH_TTL), ["Stale-Realm"] = Vote(D.VOUCH_TTL + 1),
					["Broken-Realm"] = "x" } },
			["Olympus Gone"] = { guild = "Olympus Gone", t = now - 7200, leader = "Goneboss", realm = "Realm", heardOn = "Realm",
				total = 10, vouch = { ["Long Ago-Realm"] = Vote(7200) } },
		}
	end
	local function Check(how)
		local g = w.ns.rdb.guilds["Olympus Old"]
		assert(g.vouch["Fresh One-Realm"] and g.vouch["Fresh Two-Realm"], how .. ": the votes still counted stay")
		eq(g.vouch["Stale-Realm"], nil, how); eq(g.vouch["Broken-Realm"], nil, how)
		eq(w.ns.rdb.guilds["Olympus Gone"].vouch, nil, how .. ": a row whose votes are all past it keeps none")
	end
	w.ns.rdb.guilds = Rows()
	local dispute, rank = D.Dispute(w.ns.rdb.guilds["Olympus Old"], now), { D.KnownRank("Oldcapt-Realm", "Olympus Old") }
	eq(rank[1], 1, "(the fixture's officer, vouched by the two fresh votes)")
	w.Fire("INIT")
	Check("INIT")
	eq(Alike(D.Dispute(w.ns.rdb.guilds["Olympus Old"], now), dispute, "dispute"), nil)
	eq(Alike({ D.KnownRank("Oldcapt-Realm", "Olympus Old") }, rank, "rank"), nil)
	w.ns.rdb.guilds = Rows()
	eq(w.events.PLAYER_LOGOUT, nil, "registered at login")
	w.Fire("LOGIN")
	eq(#w.events.PLAYER_LOGOUT, 1)
	w.events.PLAYER_LOGOUT[1]()
	Check("logout")
end)

test("census (1.2.3): a claim CLAIM_TTL old keeps only its guild: Data.ClaimedGuild still answers it, another guild may be claimed, and past CLAIMS_KNOWN senders those go", function()
	local w = CensusWorld()
	local D = w.D
	local t0 = w.clock
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), true)
	w.clock = t0 + D.CLAIM_TTL - 1
	D.Housekeeping()
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), false, "still bound")
	w.clock = t0 + D.CLAIM_TTL
	D.Housekeeping()
	eq(D.ClaimedGuild("Mover-Realm"), "Olympus Alpha", "his guild still answered (the game's chat marks)")
	eq(D.ClaimGuild("Mover-Realm", "Olympus Beta"), true, "after CLAIM_TTL quiet")
	eq(D.ClaimedGuild("Mover-Realm"), "Olympus Beta")
	eq(D.ClaimGuild("Mover-Realm", "Olympus Alpha"), false, "and now bound to the new one")
	-- Past CLAIMS_KNOWN senders, the claims that bind nobody go; one that binds stays.
	D.CLAIMS_KNOWN = 3
	for k = 1, 4 do eq(D.ClaimGuild("Quiet" .. k .. "-Realm", "Olympus Quiet"), true) end
	w.clock = w.clock + D.CLAIM_TTL
	eq(D.ClaimGuild("Loud-Realm", "Olympus Loud"), true)
	D.Housekeeping()
	eq(D.ClaimedGuild("Quiet1-Realm"), nil, "an old claim past CLAIMS_KNOWN")
	eq(D.ClaimedGuild("Mover-Realm"), nil)
	eq(D.ClaimedGuild("Loud-Realm"), "Olympus Loud")
	eq(D.ClaimGuild("Loud-Realm", "Olympus Other"), false, "still bound")
	eq(D.ClaimGuild("Quiet1-Realm", "Olympus Other"), true)
end)

-- The source Alts module, with only identity/state/event/transport boundaries supplied by
-- this scene. Claims, revisions, grouping and duplicate counts all run through Alts.lua.
local function WithAlts(fn)
	local savedGuild, savedDialog = GetGuildInfo, StaticPopupDialogs.OLYMPUS_ALT_CONFIRM
	local w = { now = 1800000000, guild = "Olympus Old" }
	GetGuildInfo = function() return w.guild end
	local function Client(me, own)
		local c = setmetatable({ me = me, realm = "Realm", db = {}, rdb = {}, sent = {}, timers = {}, events = {}, callbacks = {}, changes = 0 }, { __index = ns })
		c.Now = function() return w.now end
		c.Data = { ServerTime = c.Now }
		c.IsMember = function() return type(w.guild) == "string" and w.guild:find("Olympus", 1, true) ~= nil end
		c.On = function(event, cb) c.callbacks[event] = cb end
		c.RegisterEvent = function(event, cb) c.events[event] = cb end
		c.After = function(delay, label, cb) c.timers[#c.timers + 1] = { delay = delay, label = label, cb = cb } end
		c.Every = function() end
		c.Fire = function(event) if event == "DATA_CHANGED" then c.changes = c.changes + 1 end end
		c.Log = function() end
		c.Moderation = { Character = function() end }
		c.Comm = {
			Handle = function() end,
			Send = function(dist, msg) c.sent[#c.sent + 1] = { dist = dist, msg = msg } end,
		}
		if own then
			c.db.alts = {
				at = w.now - 10,
				links = { ["alt guy-realm"] = { name = "Alt Guy-Realm", main = "Main Guy-Realm", at = w.now - 10 } },
				guilds = { ["alt guy-realm"] = "Olympus Old", ["main guy-realm"] = "Olympus Main" },
			}
		end
		assert(loadfile(ROOT .. "Olympus/Alts.lua"))("Olympus", c)
		function c.Run(delay)
			local pending = c.timers
			c.timers = {}
			for _, timer in ipairs(pending) do
				if timer.delay <= delay then timer.cb() else c.timers[#c.timers + 1] = timer end
			end
		end
		return c
	end
	local ok, err = pcall(function() fn(w, Client) end)
	GetGuildInfo, StaticPopupDialogs.OLYMPUS_ALT_CONFIRM = savedGuild, savedDialog
	if not ok then error(err, 0) end
end

local function Revision(msg) return assert(tonumber(msg:match("^AL~(%d+)~"))) end
local function GuildOf(alts, name)
	for _, member in ipairs(assert(alts.Group(name)).members) do
		if member.name == name then return member.guild end
	end
	error("missing group member " .. name)
end

test("alts: a live guild change revises and sends the claim, refreshing both clients' counts", function()
	WithAlts(function(w, Client)
		local c, peer = Client("Alt Guy-Realm", true), Client("Watcher-Realm")
		peer.Alts.Handle("CHANNEL", "Main Guy-Realm", ("AL~%d~M~Olympus Main~Alt Guy"):format(w.now - 10))
		assert(c.Alts.Send(false))
		local old = c.sent[1].msg
		peer.Alts.Handle("CHANNEL", c.me, old)
		eq(GuildOf(c.Alts, c.me), "Olympus Old")
		eq(GuildOf(peer.Alts, c.me), "Olympus Old")
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus old"] = true }), 1)
		w.guild = "Olympus New"
		assert(c.events.PLAYER_GUILD_UPDATE, "membership changes are observed")("player")
		c.Run(2)
		eq(#c.sent, 2, "a guild change does not wait thirty minutes")
		local changed = c.sent[2].msg
		assert(Revision(changed) > Revision(old), "a changed guild has a newer revision")
		eq(GuildOf(c.Alts, c.me), "Olympus New", "own cached group invalidated")
		peer.Alts.Handle("CHANNEL", c.me, changed)
		eq(GuildOf(peer.Alts, c.me), "Olympus New")
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus old"] = true }), 0)
		eq(peer.Alts.Duplicates({ ["olympus main"] = true, ["olympus new"] = true }), 1)
		peer.Alts.Handle("CHANNEL", c.me, old)
		eq(GuildOf(peer.Alts, c.me), "Olympus New", "a delayed old claim cannot undo the move")
		local revision = c.db.alts.at
		c.events.PLAYER_GUILD_UPDATE("player"); c.Run(2)
		eq(c.db.alts.at, revision); eq(#c.sent, 2, "an unchanged guild produces no extra send")
	end)
end)

test("alts: login refresh revises a saved guild before the first claim", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		local old = c.db.alts.at
		w.guild = "Olympus New"
		c.callbacks.LOGIN()
		c.Run(10)
		assert(c.db.alts.at > old, "login membership change increments the wire revision")
		eq(GuildOf(c.Alts, c.me), "Olympus New")
		eq(#c.sent, 0, "login still waits for its channel before sending")
		c.Run(c.Alts.LOGIN_AFTER)
		eq(#c.sent, 1)
		eq(Revision(c.sent[1].msg), c.db.alts.at)
		assert(c.sent[1].msg:find("~Olympus New~", 1, true))
	end)
end)

test("alts: leaving updates local membership without sending outside Olympus; rejoining advances again", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		assert(c.Alts.Send(true))
		local old = c.db.alts.at
		w.guild = nil
		assert(c.events.PLAYER_GUILD_UPDATE)("player"); c.Run(2)
		eq(GuildOf(c.Alts, c.me), nil)
		assert(c.db.alts.at > old)
		eq(#c.sent, 1, "no network claim outside Olympus")
		local left = c.db.alts.at
		w.guild = "Olympus New"
		c.events.PLAYER_GUILD_UPDATE("target"); c.Run(2)
		eq(c.db.alts.at, left, "another unit's event leaves this character alone")
		c.events.PLAYER_GUILD_UPDATE("player"); c.Run(2)
		assert(c.db.alts.at > left, "even multiple changes in one second are ordered")
		eq(#c.sent, 2)
	end)
end)

test("alts: the send path records a newly observed guild even without a delivered event", function()
	WithAlts(function(w, Client)
		local c = Client("Alt Guy-Realm", true)
		assert(c.Alts.Send(false))
		local old = Revision(c.sent[1].msg)
		w.guild = "Olympus New"
		assert(c.Alts.Send(false), "a new guild overrides the ordinary repeat interval")
		assert(Revision(c.sent[2].msg) > old)
		eq(c.db.alts.guilds["alt guy-realm"], "Olympus New")
		eq(c.Alts.Send(false), false, "repeats remain paced")
	end)
end)

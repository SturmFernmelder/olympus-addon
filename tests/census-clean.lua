-- The sanitized census (Daniel, 2026-10-19; docs/CENSUS-STATS.md): CensusClean.lua's banned and
-- departed guilds, confidence and outlier rule, and the Bridge's "stats" section that hands them to
-- the Companion beside the census page's own figures. Loaded by tests/run.lua.
local ns, test, eq = ...
local C, D = ns.CensusClean, ns.Data

local NOW = 1800000000

local function Vote(sig, n, t) return { t = t or NOW - 60, sig = sig, ranks = { ["Lead-Realm"] = 0 }, n = n } end

-- A report as Data keeps it: `age` seconds old, these senders' votes ({ "Ann-Realm", ... }).
local function Report(total, age, senders, more)
	local r = { total = total, online = math.floor(total / 10), users = math.floor(total / 20), zones = {}, t = NOW - (age or 60),
		leader = "Lead", officers = {}, avgLevel = 40 }
	if senders then
		r.vouch = {}
		for _, who in ipairs(senders) do r.vouch[who] = Vote("Lead-Realm=0", total, NOW - (age or 60)) end
	end
	for k, v in pairs(more or {}) do r[k] = v end
	return r
end

-- fn with these reports, these banned guilds ({ [name] = true }), these linked alts per guild, and
-- a fresh store; everything as it was afterwards.
local function With(o, fn)
	local M, A = ns.Moderation, ns.Alts
	local saved = { guilds = ns.rdb.guilds, global = ns.rdb.censusGlobal, seen = ns.rdb.seen, clean = ns.rdb.censusClean,
		now = ns.Now, list = M.List, guild = M.Guild, dup = A.Duplicates, stats = ns.CensusStats }
	ns.rdb.guilds, ns.rdb.censusGlobal, ns.rdb.seen, ns.rdb.censusClean = o.guilds or {}, o.global or {}, o.seen or {}, nil
	ns.CensusStats = o.page
	local clock = { now = NOW }
	ns.Now = function() return clock.now end
	local banned = o.banned or {}
	M.Guild = function(name)
		for b in pairs(banned) do if b:lower() == tostring(name):lower() then return { kind = "g", name = b, off = true } end end
		return nil
	end
	M.List = function()
		local out = {}
		for b in pairs(banned) do out[#out + 1] = { kind = "g", name = b, off = true, at = NOW - 3600 } end
		return out
	end
	A.Duplicates = function(set)
		local n = 0
		for name, alts in pairs(o.alts or {}) do if set[name:lower()] then n = n + alts end end
		return n
	end
	local ok, err = pcall(fn, clock)
	ns.rdb.guilds, ns.rdb.censusGlobal, ns.rdb.seen, ns.rdb.censusClean = saved.guilds, saved.global, saved.seen, saved.clean
	ns.Now, M.List, M.Guild, A.Duplicates, ns.CensusStats = saved.now, saved.list, saved.guild, saved.dup, saved.stats
	if not ok then error(err, 0) end
end

local function Army()
	return {
		["Olympus Home"] = Report(100, 60, nil, { mine = true }),
		["Olympus Agreed"] = Report(200, 60, { "Ann-Realm", "Bob-Realm" }),
		["Olympus Lonely"] = Report(50, 60, { "Cid-Realm" }),
		["Olympus Split"] = Report(60, 60, { "Dee-Realm", "Eve-Realm" }, { conflict = true }),
		["Olympus Asleep"] = Report(80, 2 * 3600),
		["Olympus Gone"] = Report(30, 2 * 86400),
		["Olympus Banned"] = Report(40, 600),
	}
end

local function Find(list, name)
	for _, e in ipairs(list) do if e.name == name then return e end end
	return nil
end

test("census clean: banned guilds apart, departed guilds tombstoned, each counted guild's confidence", function()
	With({ guilds = Army(), banned = { ["Olympus Banned"] = true }, alts = { ["Olympus Home"] = 3 } }, function()
		local s = D.Summary()
		local c = C.Compute(s)
		eq(s.characters, 100 + 200 + 50 + 60 + 80, "the census counts neither the banned guild nor the departed one")
		eq(c.banned.guilds, 1); eq(c.banned.characters, 40); eq(c.banned.list[1].name, "Olympus Banned")
		eq(c.departed.guilds, 1); eq(c.departed.list[1].name, "Olympus Gone"); eq(c.departed.list[1].members, 30)
		eq(c.confidence.own, 100); eq(c.confidence.confirmed, 200); eq(c.confidence.single, 50)
		eq(c.confidence.disputed, 60); eq(c.confidence.stale, 80); eq(c.confidence.relayed, 0)
		eq(c.confirmedPeople, 300 - 3, "own and confirmed, their linked alts once")
		eq(c.addonOnline, 5 + 10 + 2 + 3, "fresh reports only")
		eq(c.excess, 0)
		eq(Find(c.guilds, "Olympus Gone"), nil); eq(Find(c.guilds, "Olympus Banned"), nil)
		eq(Find(c.guilds, "Olympus Asleep").status, "stale"); eq(Find(c.guilds, "Olympus Asleep").online, 0)
		eq(c.guilds[1].name, "Olympus Agreed", "biggest first")
	end)
end)

test("census clean: a banned guild never heard is listed with its size unknown; a relay row gives one", function()
	With({ guilds = Army(), banned = { ["Olympus Unheard"] = true, ["Olympus Relayed"] = true },
		global = { ["olympus relayed"] = { name = "Olympus Relayed", total = 70, online = 5, avg10 = 400, observed = NOW - 300 } } }, function()
		local c = C.Compute()
		eq(Find(c.banned.list, "Olympus Unheard").known, false)
		eq(Find(c.banned.list, "Olympus Relayed").members, 70)
		eq(c.banned.characters, 70)
	end)
end)

test("census clean: a lone reporter's jump past the guild's reach is held back on the statistics only, until agreement or an hour", function()
	local guilds = { ["Olympus Lonely"] = Report(100, 60, { "Cid-Realm" }) }
	With({ guilds = guilds }, function(clock)
		eq(C.Compute().excess, 0, "the first size is the last good one")
		clock.now = NOW + 120
		guilds["Olympus Lonely"] = Report(500, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		local c = C.Compute()
		eq(c.outliers.guilds, 1); eq(c.outliers.list[1].reported, 500); eq(c.outliers.list[1].kept, 100)
		eq(c.excess, 400)
		eq(Find(c.guilds, "Olympus Lonely").status, "outlier")
		eq(D.Summary().total, 500, "the header's count is untouched")
		-- Within its reach: 100 + max(25, 10) + 20 a minute for 2 minutes is 165.
		guilds["Olympus Lonely"] = Report(160, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		eq(C.Compute().excess, 0, "a size within reach is taken")
		guilds["Olympus Lonely"] = Report(600, 0, { "Cid-Realm" })
		guilds["Olympus Lonely"].t = clock.now
		eq(C.Compute().excess, 440)
		clock.now = clock.now + C.OUTLIER_HOLD
		guilds["Olympus Lonely"].t = clock.now
		for _, v in pairs(guilds["Olympus Lonely"].vouch) do v.t = clock.now end
		eq(C.Compute().excess, 0, "held for an hour, it is the guild's size")
	end)
	local agreed = { ["Olympus Agreed"] = Report(100, 60, { "Ann-Realm", "Bob-Realm" }) }
	With({ guilds = agreed }, function()
		C.Compute()
		agreed["Olympus Agreed"] = Report(700, 30, { "Ann-Realm", "Bob-Realm" })
		eq(C.Compute().excess, 0, "two reporters agreeing take a jump at once")
	end)
end)

test("census clean: last good sizes older than Data.KEEP go at login", function()
	With({ guilds = Army() }, function(clock)
		C.Compute()
		assert(ns.rdb.censusClean.sizes["olympus agreed"], "kept")
		clock.now = NOW + D.KEEP + 1
		C.Prune()
		eq(next(ns.rdb.censusClean.sizes), nil)
	end)
end)

test("census stats section: the page's figures and series, the sanitized census beside them, no registered users yet", function()
	local page = {
		DaySeries = function() return { { t = NOW - 86400, c = 480, p = 470, o = 30 }, { t = NOW - 43200 }, { t = NOW, c = 490, p = 487, o = 41 } } end,
		HourSeries = function() return { { ago = 1 }, { t = NOW - 600, c = 490, p = 487, o = 41 } } end,
		AverageLevel = function() return "40.0" end,
	}
	With({ guilds = Army(), banned = { ["Olympus Banned"] = true }, alts = { ["Olympus Home"] = 3 }, page = page }, function()
		local section = assert(OlympusBridge.GetSection("stats"), "the section")
		eq(section.version, 1)
		local data, s = section.data, D.Summary()
		eq(data.characters, s.characters); eq(data.people, s.total); eq(data.linkedAlts, s.alts); eq(data.online, s.online)
		eq(data.charactersWithBanned, s.characters + 40)
		eq(data.sanitizedPeople, s.total)
		eq(data.confirmedPeople, 297)
		eq(data.countedGuilds, 5); eq(data.freshGuilds, 4)
		eq(data.avgLevel, "40.0")
		eq(data.registered, nil, "not counted yet"); eq(data.accounts, nil)
		eq(data.confidence.disputed, 60)
		eq(data.banned.list[1], "40~Olympus Banned")
		eq(data.departed.list[1], ("30~%d~Olympus Gone"):format(NOW - 2 * 86400))
		eq(#data.days, 2, "a day without a sample is left out")
		eq(data.days[2], ("%d~490~487~41"):format(NOW))
		eq(data.hours[1], ("%d~490~487~41"):format(NOW - 600))
		eq(data.guilds[1], "200~20~10~400~confirmed~Olympus Agreed")
		eq(#data.guilds, 5)
	end)
	-- A build without the census page: the figures still go, without the series.
	With({ guilds = Army() }, function()
		local data = assert(OlympusBridge.GetSection("stats")).data
		eq(data.people, D.Summary().total)
		eq(#data.days, 0); eq(#data.hours, 0); eq(data.avgLevel, nil)
	end)
end)

local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]church%-fullness%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/church-world.lua"))(ns, ROOT)
local DAY = 86400
local function Setup()
	local w = World.New({ apostles = { "Aldric Vane-Realm" } }); w.clock = math.floor(w.clock / DAY) * DAY + 100
	local c = { author = w:Client(World.AUTHOR, { view = true }), king = w:Client(World.KING, { view = true }),
		keeper = w:Client("Aldric Vane"), gm = w:Client("Guild Master", { rank = 0 }), corr = w:Client("Guild Corr", { view = true }) }
	assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Corr", World.GUILD))
	w:Presence(); w:Flush()
	return w, c
end
local function Fill(w, cl, n)
	local existing = 0; for _, c in ipairs(w.clients) do if c.guild == cl.guild then existing = existing + 1 end end
	local rows = {}; for i = 1, n - existing do rows[#rows + 1] = "Native Member " .. i end
	w.members[cl.guild] = rows; w:RefreshRosters()
end
local function Observe(w, c, n)
	w:Presence(); w:Flush()
	Fill(w, c.corr, n)
	assert(w:As(c.corr, c.corr.c.ChurchFullness.Observe))
	w:Flush()
end
local function Row(w, cl) return w:As(cl, cl.c.ChurchFullness.Ranking)[1] end
local function NextDay(w) w.clock = (math.floor(w.clock / DAY) + 1) * DAY + 100 end
local function Wire(w, c, n, at, seq)
	local B = ns.Codec.Base36; local app = w:As(c.author, c.author.Church.State).corr[ns.Fold(World.GUILD)].at
	return table.concat({ "NF", "1", "o", "-", World.GUILD, c.corr.name, B(app), B(at or w.clock), B(seq or 99), B(n) }, "~")
end

test("Church fullness: strict 950 boundary and completed UTC days, same-day 1000 to 950 breaks", function()
	local w, c = Setup(); Observe(w, c, 1000)
	eq(Row(w, c.corr).days, nil, "current day never invents a zero or point")
	w.clock = w.clock + 10; Observe(w, c, 950)
	NextDay(w); local row = Row(w, c.corr); eq(row.days, 0); eq(row.average, nil); eq(row.state, "break")
	Observe(w, c, 951); NextDay(w); row = Row(w, c.corr); eq(row.days, 1); eq(row.average, 951)
end)

test("Church fullness: an unobserved day pauses without points or erasing a proven streak; resumed days count", function()
	local w, c = Setup(); Observe(w, c, 980); NextDay(w)
	eq(Row(w, c.corr).days, 1); NextDay(w)
	local row = Row(w, c.corr); eq(row.days, 1); eq(row.state, "unknown"); eq(row.average, 980)
	Observe(w, c, 960); NextDay(w); row = Row(w, c.corr); eq(row.days, 2); eq(row.average, 970)
	c.corr.online = false; w.clock = w.clock + 30 * DAY
	row = Row(w, c.keeper); eq(row.days, 2); eq(row.average, 970); eq(row.state, "unknown", "native evidence survives source absence and local folding")
end)

test("Church fullness: daily mean has equal streak weight despite noisy sampling; observed failure resets it", function()
	local w, c = Setup(); Observe(w, c, 960); w.clock = w.clock + 10; Observe(w, c, 1000); NextDay(w)
	for i = 1, 8 do Observe(w, c, 1000); w.clock = w.clock + 1 end
	NextDay(w); local row = Row(w, c.corr); eq(row.days, 2); eq(row.average, 990, "(980 + 1000)/2, not sample-weighted")
	Observe(w, c, 949); NextDay(w); eq(Row(w, c.corr).days, 0)
	Observe(w, c, 952); NextDay(w); row = Row(w, c.corr); eq(row.days, 1); eq(row.average, 952)
end)

test("Church fullness: incomplete, stale, filtered or census-only totals never supply native observations", function()
	local w, c = Setup(); Fill(w, c.corr, 1000)
	local F, R = c.corr.c.ChurchFullness, c.corr.c.Roster
	R.lastStats = nil; eq(w:As(c.corr, F.Observe), false)
	R.lastStats = { numTotal = 1000, seen = 999 }; eq(w:As(c.corr, F.Observe), false)
	R.lastStats.seen = 1000; R.members[1000] = nil; eq(w:As(c.corr, F.Observe), false)
	Fill(w, c.corr, 1000); R.Fresh = function() return nil end; eq(w:As(c.corr, F.Observe), false)
	c.corr.c.Data.Guild = function() return { total = 1000 } end
	NextDay(w); eq(Row(w, c.corr).days, nil)
end)

test("Church fullness: only the authenticated current non-census correspondent sends live evidence, never retrospective owner claims", function()
	local w, c = Setup(); local F = c.keeper.c.ChurchFullness
	local msg = Wire(w, c, 1000)
	eq(w:As(c.keeper, F.Receive, "CHANNEL", c.corr.name, msg), false)
	eq(w:As(c.keeper, F.Receive, "WHISPER", c.gm.name, msg), false)
	eq(w:As(c.keeper, F.Receive, "WHISPER", "Guild Corr-Unrelated", msg), false, "same short name on an unrelated realm is not the current correspondent")
	eq(w:As(c.keeper, F.Receive, "WHISPER", c.corr.name, Wire(w, c, 1000, w.clock - 61)), false)
	eq(w:As(c.keeper, F.Receive, "WHISPER", c.corr.name, msg), true)
	eq(w:As(c.keeper, F.Receive, "WHISPER", c.corr.name, msg), false, "transport replay is not a new observation")
	NextDay(w); eq(w:As(c.keeper, F.Receive, "WHISPER", c.corr.name, msg), false, "no offline yesterday claims")
	assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Master", World.GUILD))
	eq(w:As(c.keeper, F.Receive, "WHISPER", c.corr.name, Wire(w, c, 1000)), false)
	eq(Row(w, c.keeper).name, "Guild Master-Realm"); eq(Row(w, c.keeper).days, nil, "a new management tenure never inherits the predecessor's evidence")
end)

test("Church management: A to B and returning A under a new appointment start fresh; unchanged appointment heartbeat preserves its own streak", function()
	local w, c = Setup(); Observe(w, c, 980); NextDay(w)
	eq(Row(w, c.corr).days, 1)
	local original = w:As(c.author, c.author.Church.State).corr[ns.Fold(World.GUILD)].at
	w:Presence(); w:Flush(); eq(Row(w, c.corr).days, 1, "ordinary presence never changes appointment or streak")
	eq(w:As(c.author, c.author.Church.State).corr[ns.Fold(World.GUILD)].at, original)
	assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Master", World.GUILD))
	eq(Row(w, c.keeper).days, nil, "B has no inherited completed day")
	Fill(w, c.gm, 990); assert(w:As(c.gm, c.gm.c.ChurchFullness.Observe)); w:Flush(); NextDay(w)
	eq(Row(w, c.gm).days, 1); eq(Row(w, c.gm).average, 990)
	w.clock = w.clock + 1; assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Corr", World.GUILD))
	eq(Row(w, c.corr).days, nil, "returning A receives a new tenure, not A's former or B's streak")
	Observe(w, c, 960); NextDay(w); eq(Row(w, c.corr).days, 1); eq(Row(w, c.corr).average, 960)
	NextDay(w); eq(Row(w, c.corr).days, 1); eq(Row(w, c.corr).state, "unknown", "missing day pauses only current management")
end)

test("Church management: compacted old checkpoint and same-day old low observation cannot bleed into the new manager", function()
	local w, c = Setup(); Observe(w, c, 975); NextDay(w); Observe(w, c, 985); NextDay(w)
	w.clock = w.clock + 10 * DAY; eq(Row(w, c.corr).days, 2, "A's compacted proof survives its unknown days")
	Observe(w, c, 950)
	w.clock = w.clock + 1; assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Master", World.GUILD))
	eq(Row(w, c.gm).days, nil, "B inherits neither compacted A points nor A's low observation")
	eq(Row(w, c.keeper).days, nil, "keeper's old compacted A checkpoint is also excluded")
	eq(w:As(c.gm, c.gm.c.ChurchFullness.Observe), false, "cached native capture predates B's actual appointment")
	Fill(w, c.gm, 995); assert(w:As(c.gm, c.gm.c.ChurchFullness.Observe)); w:Flush(); NextDay(w)
	eq(Row(w, c.gm).days, 1); eq(Row(w, c.gm).average, 995)
	eq(Row(w, c.keeper).days, 1); eq(Row(w, c.keeper).average, 995, "A's same-day low observation cannot break B's new management")
	w.clock = w.clock + 10 * DAY; eq(Row(w, c.gm).days, 1, "only B's own checkpoint remains credited")
	w:As(c.gm, function() assert(loadfile(ROOT .. "Olympus/ChurchFullness.lua"))("Olympus", c.gm.c) end)
	eq(Row(w, c.gm).days, 1, "reload preserves the exact current tenure")
	w.clock = w.clock + 1; assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Corr", World.GUILD))
	eq(Row(w, c.corr).days, nil, "new appointment cannot recover A's former compacted checkpoint")
end)

test("Church management: an old unscoped checkpoint is preserved but never assigned to a named person's management", function()
	local w, c = Setup()
	local old = { days = 50, sum = 49000, known = true, last = math.floor(w.clock / DAY) - 10 }
	c.corr.c.rdb.churchFullness = { guilds = { [ns.Fold(World.GUILD)] = { name = World.GUILD, days = {}, base = old } }, seq = 0 }
	eq(Row(w, c.corr).days, nil)
	local g = c.corr.c.ChurchFullness.Book().guilds[ns.Fold(World.GUILD)]
	eq(g.unscopedBase, old, "old aggregate retained without inventing a personal appointment")
	Observe(w, c, 970); NextDay(w); eq(Row(w, c.corr).days, 1); eq(Row(w, c.corr).average, 970)
end)

test("Church management: private keeper cap and break markers belong only to the original appointment", function()
	local w, c = Setup(); c.keeper.c.ChurchFullness.DAY_MAX = 1
	Observe(w, c, 1000); w.clock = w.clock + 1; Observe(w, c, 950)
	w.clock = w.clock + 1; assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Master", World.GUILD))
	c.keeper.c.ChurchFullness.DAY_MAX = 4096
	Fill(w, c.gm, 995); assert(w:As(c.gm, c.gm.c.ChurchFullness.Observe)); w:Flush(); NextDay(w)
	w:Presence(); w:Flush(); assert(w:As(c.author, c.author.c.ChurchFullness.Ask)); w:Flush()
	local row = Row(w, c.author); eq(row.name, "Guild Master-Realm"); eq(row.days, 1); eq(row.average, 995)
	eq(row.state, "full", "A's admitted capped low-day marker cannot break or pause B's management")
end)

test("Church fullness: bounded solicited keeper relay survives reload and never accepts unsolicited or non-keeper historical claims", function()
	local w, c = Setup(); Observe(w, c, 975); NextDay(w)
	local k, a = c.keeper.c.ChurchFullness, c.author.c.ChurchFullness
	eq(Row(w, c.author).days, nil)
	w:Presence(); w:Flush()
	assert(w:As(c.author, a.Ask)); w:Flush(); eq(Row(w, c.author).days, 1); eq(Row(w, c.author).average, 975)
	local relay; for _, e in ipairs(w.sent) do if e.msg:find("NF~1~r~", 1, true) then relay = e.msg end end
	assert(relay)
	eq(w:As(c.king, c.king.c.ChurchFullness.Receive, "WHISPER", c.keeper.name, relay), false)
	eq(w:As(c.author, a.Receive, "WHISPER", c.gm.name, relay), false)
	eq(w:As(c.author, a.Receive, "WHISPER", "Aldric Vane-Unrelated", relay), false, "unrelated realm cannot impersonate an appointed keeper")
	w:As(c.author, function() assert(loadfile(ROOT .. "Olympus/ChurchFullness.lua"))("Olympus", c.author.c) end)
	eq(Row(w, c.author).days, 1, "saved admitted evidence, not an owner summary")
	assert(k.REPLY_MAX <= 150)
end)

test("Church fullness: daily budget exhaustion is unknown, preserving prior streak, and low observation still breaks", function()
	local w, c = Setup(); Observe(w, c, 970); NextDay(w)
	c.corr.c.ChurchFullness.DAY_MAX = 1
	Observe(w, c, 1000); w.clock = w.clock + 1; Observe(w, c, 990); NextDay(w)
	local row = Row(w, c.corr); eq(row.days, 1); eq(row.state, "unknown")
	Observe(w, c, 1000); w.clock = w.clock + 1; Observe(w, c, 950); NextDay(w); eq(Row(w, c.corr).days, 0)
end)

test("Church fullness: queued live sends recheck current role, guild, preview, and timestamp", function()
	local w, c = Setup(); local captures = {}; local comm = c.corr.c.Comm
	comm.Whisper = function(target, text, key, urgent, logged, done, options) captures[#captures + 1] = options.guard; return true end
	Observe(w, c, 1000); assert(captures[1]); eq(w:As(c.corr, captures[1]), true)
	c.corr.c.ViewAs = { Previewing = function() return true end }; eq(w:As(c.corr, captures[1]), false)
	c.corr.c.ViewAs = nil; w.clock = w.clock + 61; eq(w:As(c.corr, captures[1]), false)
	Observe(w, c, 999); local guard = captures[#captures]
	c.corr.guild = World.GUILD2; w:RefreshRosters(); eq(w:As(c.corr, guard), false, "guild transfer cancels old-guild queued observation")
	c.corr.guild = World.GUILD; w:RefreshRosters()
	assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Guild Master", World.GUILD))
	eq(w:As(c.corr, guard), false, "stale correspondent cannot deliver queued evidence")
end)

test("Church fullness: many identical native observations coalesce exactly and relay without duplicate weighting", function()
	local w, c = Setup()
	for i = 1, 300 do Observe(w, c, 975); w.clock = w.clock + 1 end
	local b = c.keeper.c.ChurchFullness.Book(); eq(b.count, 1, "one exact contiguous observation run, not 300 message-sized records")
	NextDay(w); w:Presence(); w:Flush(); assert(w:As(c.author, c.author.c.ChurchFullness.Ask)); w:Flush()
	local row = Row(w, c.author); eq(row.days, 1); eq(row.average, 975)
	w.clock = w.clock + 121; w:Presence(); w:Flush(); assert(w:As(c.author, c.author.c.ChurchFullness.Ask)); w:Flush()
	eq(c.author.c.ChurchFullness.Book().count, 1, "replayed run is not a second observation set")
	eq(Row(w, c.author).average, 975)
	Observe(w, c, 1000); NextDay(w); row = Row(w, c.corr); eq(row.average, 987.5, "300 observations on one day still have one day's weight")
end)

test("Church fullness: guild streak is primary, daily average breaks ties, missing data is not a zero, invitation ranking is retired", function()
	local w, c = Setup()
	local other = w:Client("Other Corr", { guild = World.GUILD2 })
	assert(w:Act(c.author, c.author.Church.NameCorrespondent, "Other Corr", World.GUILD2))
	Observe(w, c, 970); Fill(w, other, 990); assert(w:As(other, other.c.ChurchFullness.Observe)); w:Flush(); NextDay(w)
	local rows = w:As(c.keeper, c.keeper.c.ChurchFullness.Ranking)
	eq(rows[1].guild, World.GUILD2); eq(rows[1].days, 1); eq(rows[1].average, 990)
	Observe(w, c, 960); NextDay(w); rows = w:As(c.keeper, c.keeper.c.ChurchFullness.Ranking)
	eq(rows[1].guild, World.GUILD); eq(rows[1].days, 2, "longer streak beats higher daily mean")
	w:As(c.keeper, c.keeper.Count.MergeIn, World.Key("Old Invitee") .. ":" .. World.Key(c.corr.name), {
		n = "Old Invitee", bn = "Guild Corr", g = World.GUILD, kind = "i", tc = w.clock - 7200, tj = w.clock - 3600, ws = { "keeper witness" } }, false)
	assert(w:As(c.keeper, c.keeper.Count.Score, World.Key(c.corr.name), "m") > 0, "old invitation credit still exists but is not a correspondent ranking")
	eq(#w:As(c.keeper, c.keeper.Count.Ranking, "c", "m"), 0, "old invitation wire cannot publish a false fullness score")
	local view = w:As(c.keeper, c.keeper.Count.RankingView, "c", "w"); eq(view[1].days, 2)
end)

test("Church fullness: private catch-up is bounded and rotates; capped-day markers preserve unknown instead of awarding a partial day", function()
	local w, c = Setup()
	for i = 1, 10 do Observe(w, c, 951 + i); w.clock = w.clock + 1 end
	NextDay(w); c.keeper.c.ChurchFullness.REPLY_MAX = 2
	for _ = 1, 5 do
		w:Presence(); w:Flush(); local before = #w.sent
		assert(w:As(c.author, c.author.c.ChurchFullness.Ask)); w:Flush()
		local n = 0; for i = before + 1, #w.sent do if w.sent[i].msg:find("NF~1~r~", 1, true) then n = n + 1 end end
		eq(n, 2); w.clock = w.clock + 121
	end
	eq(c.author.c.ChurchFullness.Book().count, 10); eq(Row(w, c.author).average, 956.5)
	c.keeper.c.ChurchFullness.DAY_MAX = 1; Observe(w, c, 1000); w.clock = w.clock + 1; Observe(w, c, 999); NextDay(w)
	c.keeper.c.ChurchFullness.REPLY_MAX = 150; w:Presence(); w:Flush()
	assert(w:As(c.author, c.author.c.ChurchFullness.Ask)); w:Flush()
	local row = Row(w, c.author); eq(row.days, 1); eq(row.state, "unknown", "keeper's capped day does not turn into proof from its partial relay")
end)

test("Church fullness: census-only foreign appointments remain visible but cannot authorize count evidence", function()
	local w, c = Setup()
	local gm = w:Client("Other Master", { guild = World.GUILD2, rank = 0 })
	local corr = w:Client("Other Corr", { guild = World.GUILD2 })
	w.census[ns.Fold(World.GUILD2) .. ":" .. World.Key(gm.name)] = 0
	assert(w:Act(gm, gm.Church.NameCorrespondent, "Other Corr", World.GUILD2))
	local s = w:As(c.keeper, c.keeper.Church.State); local gk = ns.Fold(World.GUILD2)
	assert(s.corr[gk] and s.corrCensus[gk], "ordinary census-backed appointment is still displayed")
	Fill(w, corr, 1000); assert(w:As(corr, corr.c.ChurchFullness.Observe)); w:Flush(); NextDay(w)
	for _, row in ipairs(w:As(c.keeper, c.keeper.c.ChurchFullness.Ranking)) do if row.guild == World.GUILD2 then eq(row.days, nil) end end
end)

test("Church fullness: a pre-midnight cached native roster stays on its captured UTC day, never manufactures the next day", function()
	local w, c = Setup(); w.clock = (math.floor(w.clock / DAY) + 1) * DAY - 5
	Fill(w, c.corr, 980); local captured = w.clock
	w.clock = w.clock + 10
	assert(w:As(c.corr, c.corr.c.ChurchFullness.Observe))
	local row = Row(w, c.corr); eq(row.days, 1); eq(row.average, 980, "the native observation belongs to yesterday")
	NextDay(w); row = Row(w, c.corr); eq(row.days, 1); eq(row.state, "unknown", "no next-day sample was observed")
	c.corr.c.Roster.serverAt = nil; c.corr.c.Roster.generation = c.corr.c.Roster.generation + 1
	eq(w:As(c.corr, c.corr.c.ChurchFullness.Observe), false, "absent captured server timestamp cannot prove a UTC day")
end)

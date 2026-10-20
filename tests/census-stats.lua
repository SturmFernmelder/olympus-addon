-- CR-02 / KH-08 (the author's ask, 2026-10-19): the people next to the characters in the window's
-- header, smaller and darker; a click on that count opens the census's own page inside the Census
-- tab (CensusStats.lua): its numbers, its largest guilds and levels online, and two graphs of this
-- client's own light history (a sample every 15 minutes, 30 days kept, bounded, never sent).
-- Loaded by tests/run.lua with the harness's WithUI and LoadUI.
local ns, test, eq, extra = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]census%-stats%.lua$")) or "./"
local WithUI, LoadUI = extra.WithUI, extra.LoadUI
local L, V = ns.L, ns.Views

-- The page's words, as the game loads them (English here; Portuguese below).
assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", ns)

local function Bare(s) return (tostring(s or ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

local T0 = os.time({ year = 2026, month = 10, day = 19, hour = 15, min = 0, sec = 0 })

-- CensusStats.lua in a namespace of its own: its own saved store (rdb), clock and listeners, and
-- (o.data) a census of its own, or the harness's real one (Data.Summary over ns.rdb.guilds).
-- Anything sent fails the test: the history is this client's alone.
local function World(o)
	o = o or {}
	local w = { clock = o.clock or T0, on = {}, every = {}, sent = 0 }
	local census = { characters = 1000, total = 990, online = 120, guilds = {} }
	w.census = census
	local data = o.realData and ns.Data or setmetatable({
		Summary = function() return census end,
		Rebuilding = function() return w.rebuilding end,
		CROWN_AFTER = 200,
	}, { __index = ns.Data })
	local cns = setmetatable({
		rdb = o.rdb or {},
		Data = data,
		Now = function() return w.clock end,
		Comm = { loginAt = o.loginAt or (T0 - 100 * 86400), Send = function() w.sent = w.sent + 1 end, SendChunked = function() w.sent = w.sent + 1 end },
		On = function(name, fn) w.on[name] = w.on[name] or {}; table.insert(w.on[name], fn) end,
		Every = function(seconds, where, fn) w.every[#w.every + 1] = { seconds = seconds, where = where, fn = fn } end,
	}, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/CensusStats.lua"))("Olympus", cns)
	w.ns, w.CS = cns, cns.CensusStats
	function w.History() return cns.rdb.censusHistory end
	function w.Fire(name) for _, fn in ipairs(w.on[name] or {}) do fn() end end
	return w
end

local function Keys(t)
	local out = {}
	for k in pairs(t) do out[#out + 1] = k end
	table.sort(out)
	return out
end

test("census history: a sample every 15 minutes once the census is rebuilt after login, the day's highest counts kept; nothing sent", function()
	local w = World({ loginAt = T0 - 60 })
	local CS = w.CS
	eq(CS.EVERY, 15 * 60); eq(CS.DAYS, 30)
	-- Right after login, the census is still being rebuilt: no sample (it would look like growth).
	eq(CS.Sample(), false, "within Data.CROWN_AFTER of login")
	w.clock = T0 - 60 + 200
	w.rebuilding = 4
	eq(CS.Sample(), false, "the census still says it is rebuilding")
	w.rebuilding = nil
	eq(CS.Sample(), true, "the first sample")
	local h = w.History()
	eq(#h.recent, 1); eq(h.recent[1], ("%d,1000,990,120"):format(w.clock)); eq(h.t, w.clock)
	local today = os.date("%Y-%m-%d", w.clock)
	eq(h.days[today], "1000,990,120,1")
	-- Not again before the quarter-hour is over.
	w.clock = w.clock + CS.EVERY - 1
	eq(CS.Sample(), false)
	-- Then again; the day keeps its highest counts and how many samples it holds.
	w.clock = w.clock + 1
	w.census.characters, w.census.total, w.census.online = 1012, 1001, 80
	eq(CS.Sample(), true)
	eq(#w.History().recent, 2)
	eq(w.History().days[today], "1012,1001,120,2", "the highest characters and people, the most online")
	-- An empty census (nothing heard) is no sample.
	w.clock = w.clock + CS.EVERY
	w.census.characters, w.census.total, w.census.online = 0, 0, 0
	eq(CS.Sample(), false)
	eq(w.sent, 0, "nothing sent")
	-- The sampler runs on its own minute tick from login, and the store is mended at INIT.
	eq(#w.every, 0)
	w.Fire("LOGIN")
	eq(#w.every, 1); eq(w.every[1].seconds, CS.TICK)
	assert(w.on.INIT and #w.on.INIT == 1, "pruned at INIT")
end)

test("census history: bounded: the last 48 hours sample by sample, 30 days of daily lines, nothing from the future; a damaged store starts again", function()
	local w = World()
	local CS = w.CS
	-- 32 days of a sample every 15 minutes.
	local start = T0 - 32 * 86400
	for k = 0, 32 * 96 do
		w.clock = start + k * CS.EVERY
		w.census.characters = 1000 + math.floor(k / 96)
		w.census.total = w.census.characters - 10
		CS.Sample()
	end
	local h = w.History()
	assert(#h.recent <= CS.RECENT_MAX, "recent " .. #h.recent)
	eq(#h.recent, 193, "two days of quarter-hours (both ends)")
	local first = tonumber(h.recent[1]:match("^(%d+),"))
	assert(w.clock - first <= CS.RECENT_KEEP, "nothing older than 48 hours")
	local days = Keys(h.days)
	eq(#days, CS.DAYS, "30 days")
	eq(days[#days], os.date("%Y-%m-%d", w.clock), "today the last")
	eq(days[1], os.date("%Y-%m-%d", w.clock - 29 * 86400), "29 days ago the first")
	-- The clock went back an hour: what was taken "later" is dropped, and a sample is due again.
	w.clock = w.clock - 3600 - CS.FUTURE - 1
	eq(CS.Sample(), true, "a store from the future does not stop the sampler")
	for _, s in ipairs(w.History().recent) do
		assert(tonumber(s:match("^(%d+),")) <= w.clock + CS.FUTURE, "no sample from the future")
	end
	-- Damaged: another shape, junk entries, keys and text.
	local d = World({ rdb = { censusHistory = "junk" } })
	d.CS.Prune()
	eq(type(d.History()), "table"); eq(d.History().v, 1); eq(#d.History().recent, 0)
	local j = World({ rdb = { censusHistory = { v = 1, t = 0,
		recent = { "x", ("%d,5,4,3"):format(T0 - 60), ("%d,5,4,3|cffff0000"):format(T0), 42, ("%d,99999999999,1,1"):format(T0) },
		days = { [os.date("%Y-%m-%d", T0)] = "5,4,3,1", ["2026-13-99x"] = "1,1,1,1", [7] = "1,1,1,1", [os.date("%Y-%m-%d", T0 - 86400)] = "a,b" } } } })
	j.CS.Prune()
	eq(#j.History().recent, 1, "only the well formed sample"); eq(j.History().recent[1], ("%d,5,4,3"):format(T0 - 60))
	eq(table.concat(Keys(j.History().days), ","), os.date("%Y-%m-%d", T0))
end)

test("census history: the 30 days oldest first (no sample: no value), the 24 hours each its most online", function()
	local w = World()
	local CS = w.CS
	w.clock = T0 - 2 * 86400
	CS.Sample() -- two days ago
	w.clock = T0 - 3 * 3600 - 45 * 60
	w.census.online = 50
	CS.Sample()
	w.clock = w.clock + CS.EVERY
	w.census.online = 70
	w.census.characters = 1005
	CS.Sample()
	w.clock = T0
	w.census.online = 30
	CS.Sample()
	local days = CS.DaySeries()
	eq(#days, 30)
	eq(days[30].key, os.date("%Y-%m-%d", T0)); eq(days[30].ago, 0); eq(days[30].c, 1005)
	eq(days[28].c, 1000, "two days ago"); eq(days[29].c, nil, "yesterday: no sample")
	eq(days[1].key, os.date("%Y-%m-%d", T0 - 29 * 86400))
	local hours = CS.HourSeries()
	eq(#hours, 24)
	eq(hours[24].o, 30, "the last hour")
	eq(hours[21].o, 70, "three hours back: the most online of its two samples"); eq(hours[21].c, 1005)
	eq(hours[22].o, nil); eq(hours[23].o, nil)
	eq(hours[1].ago, 23)
	local first = os.date("*t", T0 - 2 * 86400)
	eq(CS.Since(), os.time({ year = first.year, month = first.month, day = first.day, hour = 0 }), "since the first day's start")
	-- Scales: online from 0 to a round number; the army from a round number under its lowest.
	local lo, hi = CS.Scale({ 30, nil, 3210 }, 3, true)
	eq(lo, 0); eq(hi, 4000)
	lo, hi = CS.Scale({ 84900, 85012 }, 2, false)
	assert(lo < 84900 and hi > 85012, lo .. " " .. hi)
	eq(lo % 10, 0); eq(hi % 10, 0)
	lo, hi = CS.Scale({ 500, 500 }, 2, false)
	assert(lo < 500 and hi > 500, "a flat series still has a scale")
	eq(CS.Scale({}, 3, true), nil)
end)

-- fn with these reports as the census, a sample history from `samples` ({ ago, c, p, o } each),
-- and the page built by CensusStats.Build with the harness's real Data.Summary.
local function Report(total, more)
	local r = { total = total, online = 10, zones = {}, t = os.time(), leader = "Lead", leaderOnline = true, officers = {}, mine = true }
	for k, v in pairs(more or {}) do r[k] = v end
	return r
end
local function WithCensus(guilds, alts, fn)
	local saved = { guilds = ns.rdb.guilds, seen = ns.rdb.seen, alts = ns.Alts }
	ns.rdb.guilds, ns.rdb.seen = guilds, {}
	ns.Alts = { Duplicates = function() return alts end }
	local ok, err = pcall(fn)
	ns.rdb.guilds, ns.rdb.seen, ns.Alts = saved.guilds, saved.seen, saved.alts
	if not ok then error(err, 0) end
end
local function Find(lines, text)
	for i, line in ipairs(lines) do if Bare(line.text) == text then return line, i end end
end

test("census page: characters, people, linked alts, online, guilds counted, the weighted average level, the largest guilds against the cap and the levels online", function()
	WithCensus({
		["Olympus"] = Report(900, { online = 200, avgLevel = 40, levels = { 10, 20, 30, 40, 50, 30, 20 } }),
		["Olympus II"] = Report(300, { online = 50, avgLevel = 60, levels = { 0, 0, 0, 0, 10, 20, 20 } }),
		["Olympus III"] = Report(100, { online = 0, avgLevel = nil, t = os.time() - ns.Data.FRESH - 60 }),
	}, 4, function()
		local w = World({ realData = true, clock = os.time() })
		local lines, title, text = w.CS.Build()
		eq(title, L.CENSUS_STATS_DETAIL_TITLE); eq(text, L.CENSUS_STATS_DETAIL)
		eq(Bare(lines[1].text), L.CENSUS_STATS_BACK, "the way back first"); assert(lines[1].onClick)
		eq(lines[2].text, L.CENSUS_STATS_TITLE); eq(lines[2].header, true)
		eq(Bare(Find(lines, L.CENSUS_STATS_CHARACTERS).right), "1,300")
		eq(Bare(Find(lines, L.CENSUS_STATS_PEOPLE).right), "1,296", "the linked alts counted once")
		eq(Bare(Find(lines, L.CENSUS_STATS_ALTS).right), "4")
		eq(Bare(Find(lines, L.CENSUS_STATS_ONLINE).right), "250", "online: the guilds reporting now")
		eq(Bare(Find(lines, L.CENSUS_STATS_GUILDS).right), "3  " .. L.CENSUS_STATS_GUILDS_LIVE:format(2))
		-- (40 x 900 + 60 x 300) / 1200 = 45; the guild without one is left out.
		eq(Bare(Find(lines, L.CENSUS_STATS_AVG).right), "45.0")
		-- The people row explains itself.
		local tip = {}
		Find(lines, L.CENSUS_STATS_PEOPLE).tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end })
		eq(tip[2], L.CENSUS_STATS_PEOPLE_TIP)
		-- The largest guilds, each a meter of the game's 1,000 cap, an old report grey.
		local largest, at = Find(lines, L.CENSUS_STATS_LARGEST)
		eq(largest.header, true)
		eq(Bare(lines[at + 1].text), "Olympus"); eq(Bare(lines[at + 1].right), "900 " .. L.CENSUS_STATS_OF_CAP:format("1,000"))
		eq(lines[at + 1].meter.value, 900); eq(lines[at + 1].meter.total, ns.Codec.GUILD_CAP)
		eq(lines[at + 3].text, V.Grey("Olympus III"), "an old report: grey")
		tip = {}
		lines[at + 1].tooltip({ AddLine = function(_, s) tip[#tip + 1] = s end, AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end })
		eq(tip[#tip], L.CENSUS_STATS_SHARE:format("69"), "900 of 1,300 characters")
		-- The levels online, the highest band first, from the guilds reporting now.
		local _, lv = Find(lines, L.CENSUS_STATS_LEVELS)
		assert(lv, "levels online")
		eq(Bare(lines[lv + 1].text), L.CENSUS_STATS_LEVEL_TOP:format(60)); eq(lines[lv + 1].meter.value, 40)
		eq(Bare(lines[lv + 1].right), "40 16%", "40 of 250")
		eq(Bare(lines[lv + 7].text), L.CENSUS_STATS_LEVEL_BAND:format(1, 9))
		-- No history yet: each graph says why there is none.
		local _, g = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		eq(Bare(lines[g + 1].text), L.CENSUS_STATS_EMPTY_GRAPH); eq(lines[g + 1].graph, nil)
		eq(Find(lines, L.CENSUS_STATS_KEPT:format("x")), nil)
	end)
end)

test("census page: the graphs: 30 days of characters, the scale's ends written on its left, today last and brighter; 24 hours of online from 0; each slot its own tooltip", function()
	WithCensus({ ["Olympus"] = Report(900, { online = 200 }) }, 0, function()
		-- (Noon today: the samples' days and hours whatever the time the test runs.)
		local d = os.date("*t")
		local now = os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
		local w = World({ realData = true, clock = now - 2 * 86400 })
		w.CS.Sample()
		w.clock = now - 30 * 60
		w.CS.Sample()
		w.clock = now
		local lines = w.CS.Build()
		local _, g = Find(lines, L.CENSUS_STATS_ARMY_GRAPH)
		local army = lines[g + 1].graph
		assert(army, "the army's graph")
		eq(army.n, 30); eq(army.values[30], 900); eq(army.values[28], 900); eq(army.values[29], nil)
		eq(army.left, L.CENSUS_STATS_DAYS_AGO:format(29)); eq(army.right, L.CENSUS_STATS_TODAY)
		assert(army.min < 900 and army.max > 900)
		eq(army.top, ns.FormatNumber(army.max)); eq(army.bottom, ns.FormatNumber(army.min))
		local tip = {}
		local tt = { AddLine = function(_, s) tip[#tip + 1] = s end, AddDoubleLine = function(_, a, b) tip[#tip + 1] = a .. "=" .. b end }
		army.tips[30](tt)
		eq(tip[1], L.CENSUS_STATS_TODAY); eq(tip[2], L.CENSUS_STATS_CHARACTERS .. "=900"); eq(tip[3], L.CENSUS_STATS_PEOPLE .. "=900")
		tip = {}
		army.tips[29](tt)
		eq(tip[2], L.CENSUS_STATS_NO_SAMPLE)
		-- The scale's own tooltip sums the series up (the row takes no mouse).
		eq(lines[g + 1].tooltip, nil); eq(lines[g + 1].onClick, nil)
		tip = {}
		army.tip(tt)
		eq(tip[1], L.CENSUS_STATS_ARMY_GRAPH); eq(tip[2], L.CENSUS_STATS_HIGHEST .. "=" .. L.CENSUS_STATS_WHEN:format("900", L.CENSUS_STATS_TODAY))
		local _, o = Find(lines, L.CENSUS_STATS_ONLINE_GRAPH)
		local online = lines[o + 1].graph
		eq(online.n, 24); eq(online.min, 0); eq(online.values[24], 200); eq(online.right, L.CENSUS_STATS_NOW)
		assert(Find(lines, L.CENSUS_STATS_KEPT:format(os.date(L.CENSUS_STATS_DAY_FORMAT, w.CS.Since()))), "how long it is kept")
	end)
end)

test("census page: a graph row drawn with plain textures: a step line at each value over a faint fill, a dot where none, the last slot brighter, each slot's tooltip on hover, gone when the row shows text again", function()
	WithUI(function()
		local content = CreateFrame("Frame", nil, UIParent)
		content:SetWidth(346)
		content.style = "old"
		local graph = { n = 4, values = { 10, nil, 20, 30 }, min = 0, max = 40, color = { 1, 0.82, 0 },
			top = "40", bottom = "0", left = "first", right = "last",
			tips = { function(tt) tt:AddLine("slot one") end, nil, nil, function(tt) tt:AddLine("slot four") end },
			tip = function(tt) tt:AddLine("the whole series") end }
		V.Render(content, { { text = "Heading", header = true }, { graph = graph } })
		local r = content.rows[2]
		eq(r.h, V.GraphHeight(graph)); eq(V.GraphHeight(graph), V.GRAPH_H + V.GRAPH_AXIS_H + 4)
		eq(V.LinesHeight({ { graph = graph } }, false, 346), 2 + V.GraphHeight(graph) + 8, "measured as drawn")
		local g = r.graph
		assert(g and g:IsShown(), "the graph's holder")
		eq(r.left:IsShown(), false)
		eq(g.top:GetText(), "40"); eq(g.bottom:GetText(), "0"); eq(g.left:GetText(), "first"); eq(g.right:GetText(), "last")
		local plotW = 346 - V.GRAPH_GUTTER - 4
		local s1, s2, s3, s4 = g.slots[1], g.slots[2], g.slots[3], g.slots[4]
		-- Slot one: its fill from the baseline up to a quarter of the plot, its line on top.
		local base = V.GRAPH_AXIS_H
		eq(s1.fill:Anchor("BOTTOMLEFT")[4], V.GRAPH_GUTTER); eq(s1.fill:Anchor("BOTTOMLEFT")[5], base)
		eq(s1.fill.h, V.GRAPH_H / 4); eq(s1.cap.h, 2); eq(s1.cap:Anchor("BOTTOMLEFT")[5], base + V.GRAPH_H / 4 - 1)
		eq(s1.rise:IsShown(), false, "nothing before it")
		-- Slot two has no value: a dot on the baseline, no fill.
		eq(s2.fill:IsShown(), false); eq(s2.cap.w, 2); eq(s2.cap.h, 2); eq(s2.cap:Anchor("BOTTOMLEFT")[5], base)
		eq(s3.rise:IsShown(), false, "no step from a slot with no value")
		-- Slot four: a step up from slot three.
		eq(s4.rise:IsShown(), true); eq(s4.rise.w, 2)
		eq(s4.rise:Anchor("BOTTOMLEFT")[5], base + V.GRAPH_H / 2 - 1); eq(s4.rise.h, V.GRAPH_H / 4 + 2)
		-- Across the plot, slot by slot, nothing past its end.
		local right = s4.hit:Anchor("BOTTOMLEFT")[4] + s4.hit.w
		assert(math.abs(right - (V.GRAPH_GUTTER + plotW)) <= 1, "the last slot ends with the plot: " .. right)
		-- The colours: the last slot brighter than the others, the empty slot's dot grey.
		for _, s in ipairs({ s1, s2, s4 }) do
			for _, t in ipairs({ s.fill, s.cap }) do t.SetVertexColor = function(self, ...) self.vc = { ... } end end
		end
		V.Render(content, { { text = "Heading", header = true }, { graph = graph } })
		assert(s4.cap.vc[4] > s1.cap.vc[4] and s4.fill.vc[4] > s1.fill.vc[4], "the last slot brighter")
		eq(s1.cap.vc[1], 1); eq(s2.cap.vc[1], 0.62, "a grey dot")
		-- A slot's own tooltip; a slot without one takes no mouse.
		GameTooltip.AddDoubleLine = function(self, a, b) self.lines[#self.lines + 1] = a .. "=" .. b end
		s4.hit:Fire("OnEnter")
		eq(GameTooltip.owner, s4.hit); eq(GameTooltip.lines[1], "slot four")
		s2.hit:Fire("OnEnter")
		eq(GameTooltip.owner, s4.hit, "no tooltip for a slot without one")
		-- The scale on the left: the whole series; the row itself takes no mouse.
		eq(g.scale.w, V.GRAPH_GUTTER - 2); eq(g.scale.h, V.GRAPH_H)
		g.scale:Fire("OnEnter")
		eq(GameTooltip.owner, g.scale); eq(GameTooltip.lines[1], "the whole series")
		-- Fewer slots: the rest hide; the same row as text: the graph goes.
		V.Render(content, { { text = "Heading", header = true }, { graph = { n = 2, values = { 1, 2 }, min = 0, max = 2 } } })
		eq(s3.hit:IsShown(), false); eq(s4.cap:IsShown(), false)
		V.Render(content, { { text = "Heading", header = true }, { text = "a line again" } })
		eq(r.graph:IsShown(), false); eq(r.left:IsShown(), true); eq(r.h, 16)
	end)
end)

-- The window opened on the Census with these reports, this module as the game has it (ns.CensusStats).
local function OpenWindow(fn)
	WithUI(function()
		WithCensus({
			["Olympus"] = Report(900, { online = 200, avgLevel = 40 }),
			["Olympus II"] = Report(300, { online = 50 }),
		}, 4, function()
			local w = World({ realData = true, clock = os.time() })
			local saved = ns.CensusStats
			ns.CensusStats = w.CS
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				fn(OlympusFrame, UI, w)
			end)
			ns.CensusStats = saved
			if not ok then error(err, 0) end
		end)
	end)
end

test("census header: the characters, and next to them, smaller and darker, the people; lit under the mouse; the same in the copy for Discord and on the minimap button", function()
	OpenWindow(function(main, UI)
		eq(main.tab, "census")
		eq(main.total:GetText(), L.ARMY_TOTAL:format("1,200"), "the characters")
		eq(main.people:GetText(), L.ARMY_PEOPLE:format("1,196"), "the people: the 4 linked alts once")
		eq(main.people:IsShown(), true)
		eq(main.people.font, "GameFontNormalSmall", "smaller than the characters'"); eq(main.total.font, "GameFontNormalLarge")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_COLOR, ","), "darker")
		assert(UI.PEOPLE_COLOR[1] < 1 and UI.PEOPLE_COLOR[2] < 0.82, "darker than the gold of the characters")
		-- Right after the characters' words, on their line, inside the window.
		local a = main.people:Anchor("BOTTOMLEFT")
		eq(a[2], main.total); eq(a[4], main.total:GetUnboundedStringWidth() + UI.PEOPLE_GAP)
		assert(main.headerX + a[4] + main.people:GetUnboundedStringWidth() <= main:GetWidth() - 26, "inside the header")
		-- The hover lights it and says a click opens the page.
		main.headerHover:Fire("OnEnter")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_LIT, ","))
		eq(GameTooltip.lines[#GameTooltip.lines], L.HEADER_TIP_OPEN)
		main.headerHover:Fire("OnLeave")
		eq(table.concat(main.people.textColor, ","), table.concat(UI.PEOPLE_COLOR, ","))
		-- The copy for Discord: the same two counts.
		local copy = ns.Data.DiscordText()
		assert(copy:find(L.DISCORD_HEADER:format("1,200", "250", 2) .. " · " .. L.ARMY_PEOPLE:format("1,196"), 1, true), copy)
		-- The minimap button's tooltip: the same two counts, the people in the same colour.
		eq(UI.PEOPLE_CODE, "|cffb89957")
		Minimap = CreateFrame("Frame", "Minimap", UIParent)
		Minimap:SetSize(140, 140)
		UI.UpdateMinimapButton()
		OlympusMinimapButton:Fire("OnEnter")
		eq(GameTooltip.lines[2], L.ARMY_TOTAL:format("1,200") .. "  " .. UI.PEOPLE_CODE .. L.ARMY_PEOPLE:format("1,196") .. "|r")
		Minimap = nil
		-- On the Join screen (no Olympus guild) the header is the roast's alone.
		GetGuildInfo = function() return nil end
		UI.Refresh()
		eq(main.people:IsShown(), false)
	end)
end)

test("census page: a click on the header's count opens it inside the Census tab from any tab, no column titles, its own page id; Back, the tab or another tab returns to the list; a drag opens nothing", function()
	OpenWindow(function(main, UI, w)
		local CS = w.CS
		eq(main.colHeader:IsShown(), true)
		UI.SelectTab("realm")
		-- A drag of the window from the count opens nothing.
		local hover = main.headerHover
		hover:Fire("OnMouseDown", "LeftButton"); hover:Fire("OnDragStart"); hover:Fire("OnDragStop"); hover:Fire("OnMouseUp", "LeftButton")
		eq(main.tab, "realm"); eq(CS.Shown(), false)
		-- A right click neither.
		hover:Fire("OnMouseDown", "RightButton"); hover:Fire("OnMouseUp", "RightButton")
		eq(CS.Shown(), false)
		-- A click: the Census tab, its own page.
		hover:Fire("OnMouseDown", "LeftButton"); hover:Fire("OnMouseUp", "LeftButton")
		eq(main.tab, "census"); eq(CS.Shown(), true)
		eq(main.colHeader:IsShown(), false, "no column titles over the page")
		eq(UI.PageId(), "census/stats")
		local rows = main.views.census.rows
		eq(Bare(rows[1].left:GetText()), L.CENSUS_STATS_BACK)
		eq(rows[2].left:GetText(), L.CENSUS_STATS_TITLE)
		eq(main.detailTitle:GetText(), L.CENSUS_STATS_DETAIL_TITLE)
		eq(main.people:IsShown(), true, "the count stays in the header")
		-- Back: the list again, its column titles too.
		rows[1]:Click()
		eq(CS.Shown(), false); eq(main.colHeader:IsShown(), true); eq(UI.PageId(), "census/")
		assert(main.views.census.rows[1].line.input, "the Census's search on top again")
		-- The Census tab clicked, or another tab: the list.
		UI.OpenCensusStats()
		eq(CS.Shown(), true)
		UI.SelectTab("census")
		eq(CS.Shown(), false); eq(main.colHeader:IsShown(), true)
		UI.OpenCensusStats()
		UI.SelectTab("realm")
		eq(CS.Shown(), false)
		-- Never from a person page or the Join screen.
		GetGuildInfo = function() return nil end
		UI.Refresh()
		eq(UI.OpenCensusStats(), false); eq(CS.Shown(), false)
	end)
end)

test("census page: a client updated without a restart (no CensusStats.lua yet) keeps the Census list, says to restart on a click, and offers no click in the tooltip", function()
	WithUI(function()
		WithCensus({ ["Olympus"] = Report(900) }, 0, function()
			local saved = ns.CensusStats
			ns.CensusStats = nil
			local printed = {}
			local savedPrint = ns.Print
			ns.Print = function(s) printed[#printed + 1] = s end
			local ok, err = pcall(function()
				local UI = LoadUI()
				UI.Toggle()
				local main = OlympusFrame
				eq(main.people:GetText(), L.ARMY_PEOPLE:format("900"))
				main.headerHover:Fire("OnEnter")
				for _, line in ipairs(GameTooltip.lines) do assert(line ~= L.HEADER_TIP_OPEN, "no click offered") end
				main.headerHover:Fire("OnMouseDown", "LeftButton"); main.headerHover:Fire("OnMouseUp", "LeftButton")
				eq(printed[#printed], L.RESTART_NEEDED)
				eq(main.colHeader:IsShown(), true); eq(UI.PageId(), "census/")
			end)
			ns.CensusStats, ns.Print = saved, savedPrint
			if not ok then error(err, 0) end
		end)
	end)
end)

test("census page: every line in English and Portuguese, the Portuguese its own", function()
	local pt = {}
	local savedLocale = GetLocale
	GetLocale = function() return "ptBR" end
	local ok, err = pcall(function()
		pt.L = setmetatable({}, { __index = function(_, k) return k end })
		assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", pt)
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
	local en = {}
	en.L = setmetatable({}, { __index = function(_, k) return k end })
	assert(loadfile(ROOT .. "Olympus/Locales/CensusStatsText.lua"))("Olympus", en)
	local same = { CENSUS_STATS_TIME_FORMAT = true, CENSUS_STATS_WHEN = true, CENSUS_STATS_OF_CAP = true }
	local n = 0
	for key, text in pairs(en.L) do
		n = n + 1
		assert(type(rawget(pt.L, key)) == "string", "Portuguese " .. key)
		if not same[key] then assert(pt.L[key] ~= text, "Portuguese of its own: " .. key) end
		local function Codes(s) local c = {} for spec in s:gsub("%%%%", ""):gmatch("%%%a") do c[#c + 1] = spec end return table.concat(c) end
		if key ~= "CENSUS_STATS_DAY_FORMAT" then eq(Codes(pt.L[key]), Codes(text), key .. ": the same format codes") end
	end
	assert(n >= 40, "lines: " .. n)
	eq(pt.L.ARMY_PEOPLE:format("80.544"), "80.544 pessoas")
	eq(pt.L.CENSUS_STATS_TITLE, "O censo em números")
end)

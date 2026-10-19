local ADDON, ns = ...
local L = ns.L

-- CR-02 / KH-08 (the author's ask, 2026-10-19: "um número do lado, menorzinho, mais escuro: número
-- de pessoas ... quando você clicar no número ... uma página dentro do Census"): the window's header
-- shows the people (each player once) next to the characters, and a click on that count opens this
-- page in place of the Census's list: characters, people, linked alts, online, the guilds counted,
-- the army's average level, the largest guilds and the levels online, all from the census this
-- client already holds (Data.Summary), and how its totals moved.
--
-- The history is this client's own: every EVERY seconds while the player is on (after the census is
-- rebuilt at login, Data.CROWN_AFTER, as Tonight's count waits) it writes down the characters, the
-- people and who is online, in the realm group's store (ns.rdb.censusHistory): each sample of the
-- last RECENT_KEEP, and one line a day (its highest counts) for DAYS days. Both are bounded and
-- pruned at each sample and at login. Nothing is sent: another client keeps its own history, and
-- the page says so.

local CS = {}
ns.CensusStats = CS

CS.EVERY = 15 * 60         -- a sample every quarter-hour
CS.RECENT_KEEP = 48 * 3600 -- each sample of the last two days
CS.RECENT_MAX = 200        -- at most (two days of quarter-hours: 192)
CS.DAYS = 30               -- days, today among them
CS.HOURS = 24              -- the online graph's hours
CS.FUTURE = 5 * 60         -- a sample later than now by more than this (the clock went back) is dropped
CS.TOP_GUILDS = 5          -- the largest guilds listed
CS.TICK = 60               -- how often the sampler looks whether a sample is due
CS.ARMY_COLOR = { 1, 0.82, 0 }
CS.ONLINE_COLOR = { 0.25, 1, 0.25 }

local MAX_COUNT = 10000000 -- far above any census (Data.MAX_GUILDS guilds of Codec.GUILD_CAP)
local DAY_KEY = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

local shown = false

---------------------------------------------------------------------------
-- The page's state: shown from the header (UI.OpenCensusStats), closed by its Back line or any tab
-- opened (UI.lua's ShowTab).
---------------------------------------------------------------------------

function CS.Shown() return shown end
function CS.Open() shown = true end
function CS.Close() shown = false end

---------------------------------------------------------------------------
-- The history kept
---------------------------------------------------------------------------

local function Count(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 or v > MAX_COUNT then return nil end
	return math.floor(v)
end

-- The store, made or mended (a saved table of another shape starts again).
local function Store()
	local rdb = ns.rdb
	if type(rdb) ~= "table" then return nil end
	local h = rdb.censusHistory
	if type(h) ~= "table" or h.v ~= 1 then
		h = { v = 1, t = 0, recent = {}, days = {} }
		rdb.censusHistory = h
	end
	if type(h.recent) ~= "table" then h.recent = {} end
	if type(h.days) ~= "table" then h.days = {} end
	return h
end

-- "t,characters,people,online" and "characters,people,online,samples": numbers alone, so the saved
-- variables stay small and nothing else can ride in them.
local function ParseSample(s)
	if type(s) ~= "string" then return nil end
	local t, c, p, o = s:match("^(%d+),(%d+),(%d+),(%d+)$")
	t, c, p, o = tonumber(t), Count(c), Count(p), Count(o)
	if not (t and c and p and o) then return nil end
	return { t = t, c = c, p = p, o = o }
end
local function ParseDay(s)
	if type(s) ~= "string" then return nil end
	local c, p, o, n = s:match("^(%d+),(%d+),(%d+),(%d+)$")
	c, p, o, n = Count(c), Count(p), Count(o), Count(n)
	if not (c and p and o and n) then return nil end
	return { c = c, p = p, o = o, n = n }
end

-- A day's key, in the player's own calendar ("2026-10-19"), and noon of the day `t` falls in: a
-- step of a whole day back from noon stays in the day before, whatever the clocks did that night.
local function DayKey(t) return date("%Y-%m-%d", t) end
local function Noon(t)
	local d = date("*t", t)
	return time({ year = d.year, month = d.month, day = d.day, hour = 12, min = 0, sec = 0 })
end
-- The DAYS days' keys, the oldest first, today last.
local function DayKeys(now)
	local noon, keys = Noon(now), {}
	for k = CS.DAYS - 1, 0, -1 do keys[#keys + 1] = DayKey(noon - k * 86400) end
	return keys
end

-- Only what the bounds allow: the samples of the last RECENT_KEEP (none from the future), in time
-- order, RECENT_MAX at most; the days of the last DAYS (none after today), each well formed.
function CS.Prune(now)
	local h = Store()
	if not h then return end
	now = now or ns.Now()
	local kept = {}
	for _, s in ipairs(h.recent) do
		local e = ParseSample(s)
		if e and e.t <= now + CS.FUTURE and now - e.t <= CS.RECENT_KEEP then kept[#kept + 1] = e end
	end
	table.sort(kept, function(a, b) return a.t < b.t end)
	local recent = {}
	for i = math.max(1, #kept - CS.RECENT_MAX + 1), #kept do
		local e = kept[i]
		recent[#recent + 1] = ("%d,%d,%d,%d"):format(e.t, e.c, e.p, e.o)
	end
	h.recent = recent
	local keys = DayKeys(now)
	local first, last = keys[1], keys[#keys]
	local days = {}
	for key, s in pairs(h.days) do
		if type(key) == "string" and key:match(DAY_KEY) and key >= first and key <= last and ParseDay(s) then days[key] = s end
	end
	h.days = days
	if (tonumber(h.t) or 0) > now + CS.FUTURE then h.t = 0 end
end

-- One sample, at `now`, when one is due: EVERY after the last, the census rebuilt after login and
-- holding a count. True when it was taken.
function CS.Sample(now)
	now = now or ns.Now()
	local h = Store()
	if not h then return false end
	local last = tonumber(h.t) or 0
	if last > now + CS.FUTURE then last = 0 end
	if now - last < CS.EVERY then return false end
	local D = ns.Data
	local loginAt = ns.Comm and ns.Comm.loginAt
	if loginAt and now - loginAt < (D.CROWN_AFTER or 0) then return false end
	if D.Rebuilding and D.Rebuilding(now) then return false end
	local s = D.Summary()
	local c, p, o = Count(s.characters or s.total), Count(s.total), Count(s.online)
	if not (c and p and o) or c <= 0 then return false end
	h.t = now
	h.recent[#h.recent + 1] = ("%d,%d,%d,%d"):format(now, c, p, o)
	local key = DayKey(now)
	local day = ParseDay(h.days[key]) or { c = 0, p = 0, o = 0, n = 0 }
	h.days[key] = ("%d,%d,%d,%d"):format(math.max(day.c, c), math.max(day.p, p), math.max(day.o, o), day.n + 1)
	CS.Prune(now)
	return true
end

-- The DAYS days, the oldest first: { key, t (its noon), c, p, o, n } each, c nil for a day with no
-- sample.
function CS.DaySeries(now)
	now = now or ns.Now()
	local h = Store()
	local out, noon = {}, Noon(now)
	for k = CS.DAYS - 1, 0, -1 do
		local t = noon - k * 86400
		local key = DayKey(t)
		local d = h and ParseDay(h.days[key]) or nil
		out[#out + 1] = { key = key, t = t, ago = k, c = d and d.c, p = d and d.p, o = d and d.o, n = d and d.n or 0 }
	end
	return out
end

-- The HOURS hours up to now, the oldest first: each its own 60 minutes back from now (the last one
-- the hour just gone), with its sample of the most online ({ t, c, p, o }), nil where none.
function CS.HourSeries(now)
	now = now or ns.Now()
	local h = Store()
	local out = {}
	for k = CS.HOURS - 1, 0, -1 do out[#out + 1] = { ago = k } end
	for _, s in ipairs(h and h.recent or {}) do
		local e = ParseSample(s)
		local age = e and now - e.t
		if age and age >= -CS.FUTURE and age < CS.HOURS * 3600 then
			local slot = out[CS.HOURS - math.floor(math.max(0, age) / 3600)]
			if slot and (not slot.o or e.o > slot.o or e.o == slot.o and e.t > slot.t) then
				slot.t, slot.c, slot.p, slot.o = e.t, e.c, e.p, e.o
			end
		end
	end
	return out
end

-- When the history kept starts (its oldest sample or day), nil for none.
function CS.Since()
	local h = Store()
	if not h then return nil end
	local since
	for _, s in ipairs(h.recent) do
		local e = ParseSample(s)
		if e and (not since or e.t < since) then since = e.t end
	end
	for key in pairs(h.days) do
		local y, m, d = tostring(key):match(DAY_KEY)
		if y then
			local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0, min = 0, sec = 0 })
			if t and (not since or t < since) then since = t end
		end
	end
	return since
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------

local function V() return ns.Views end
local function F(n) return ns.FormatNumber(n) end
local function White(s) return "|cffffffff" .. s .. "|r" end

-- A scale for `values` (nil entries skipped): from 0 (`fromZero`) or from a little under the
-- lowest, to a little over the highest, its ends round numbers. nil for no value.
function CS.Scale(values, n, fromZero)
	local lo, hi
	for i = 1, n do
		local v = values[i]
		if v then
			lo = (not lo or v < lo) and v or lo
			hi = (not hi or v > hi) and v or hi
		end
	end
	if not lo then return nil end
	if fromZero then
		local top = math.max(1, hi)
		local step = 10 ^ math.floor(math.log10(top))
		return 0, math.max(step, math.ceil(top / step) * step)
	end
	local pad = math.max((hi - lo) * 0.25, hi * 0.005, 1)
	lo, hi = math.max(0, lo - pad), hi + pad
	local step = 10 ^ math.floor(math.log10(math.max(1, hi - lo)))
	lo = math.max(0, math.floor(lo / step) * step)
	hi = math.ceil(hi / step) * step
	if hi <= lo then hi = lo + step end
	return lo, hi
end

-- The highest, the lowest and the latest of a series ({ v, label } each), for a graph's own tooltip.
local function SeriesTip(title, series, value, label)
	return function(tt)
		tt:AddLine(title, 1, 0.82, 0)
		local hi, lo, latest
		for _, e in ipairs(series) do
			local v = value(e)
			if v then
				if not hi or v >= value(hi) then hi = e end
				if not lo or v < value(lo) then lo = e end
				latest = e
			end
		end
		if not latest then
			tt:AddLine(L.CENSUS_STATS_EMPTY_GRAPH, 1, 1, 1, true)
			return
		end
		tt:AddDoubleLine(L.CENSUS_STATS_HIGHEST, L.CENSUS_STATS_WHEN:format(F(value(hi)), label(hi)), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.CENSUS_STATS_LOWEST, L.CENSUS_STATS_WHEN:format(F(value(lo)), label(lo)), 1, 0.82, 0, 1, 1, 1)
		tt:AddDoubleLine(L.CENSUS_STATS_LATEST, L.CENSUS_STATS_WHEN:format(F(value(latest)), label(latest)), 1, 0.82, 0, 1, 1, 1)
		tt:AddLine(" ")
		tt:AddLine(L.CENSUS_STATS_DETAIL, 0.75, 0.75, 0.75, true)
	end
end

local function DayLabel(e)
	if e.ago == 0 then return L.CENSUS_STATS_TODAY end
	return date(L.CENSUS_STATS_DAY_FORMAT, e.t)
end
local function HourLabel(e)
	return e.t and date(L.CENSUS_STATS_TIME_FORMAT, e.t) or L.CENSUS_STATS_HOURS_AGO:format(e.ago)
end

-- The army over the last DAYS days: each day's highest count of characters.
local function ArmyGraph(now)
	local days = CS.DaySeries(now)
	local values, tips = {}, {}
	for i, e in ipairs(days) do
		values[i] = e.c
		tips[i] = function(tt)
			tt:AddLine(DayLabel(e), 1, 0.82, 0)
			if not e.c then tt:AddLine(L.CENSUS_STATS_NO_SAMPLE, 0.75, 0.75, 0.75, true) return end
			tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(e.c), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L.CENSUS_STATS_PEOPLE, F(e.p), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L.CENSUS_STATS_PEAK_ONLINE, F(e.o), 1, 0.82, 0, 0.25, 1, 0.25)
			tt:AddDoubleLine(L.CENSUS_STATS_SAMPLES, tostring(e.n), 0.75, 0.75, 0.75, 0.75, 0.75, 0.75)
		end
	end
	local lo, hi = CS.Scale(values, #days, false)
	if not lo then return nil, days end
	return {
		n = #days, values = values, min = lo, max = hi, color = CS.ARMY_COLOR, tips = tips,
		top = F(hi), bottom = F(lo), left = L.CENSUS_STATS_DAYS_AGO:format(CS.DAYS - 1), right = L.CENSUS_STATS_TODAY,
	}, days
end

-- Who was online over the last HOURS hours: each hour's most online, from 0.
local function OnlineGraph(now)
	local hours = CS.HourSeries(now)
	local values, tips = {}, {}
	for i, e in ipairs(hours) do
		values[i] = e.o
		tips[i] = function(tt)
			if not e.o then
				tt:AddLine(L.CENSUS_STATS_HOURS_AGO:format(e.ago + 1), 1, 0.82, 0)
				tt:AddLine(L.CENSUS_STATS_NO_SAMPLE, 0.75, 0.75, 0.75, true)
				return
			end
			tt:AddLine(L.CENSUS_STATS_AROUND:format(HourLabel(e)), 1, 0.82, 0)
			tt:AddDoubleLine(L.CENSUS_STATS_ONLINE, F(e.o), 1, 0.82, 0, 0.25, 1, 0.25)
			tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(e.c), 1, 0.82, 0, 1, 1, 1)
			tt:AddDoubleLine(L.CENSUS_STATS_PEOPLE, F(e.p), 1, 0.82, 0, 1, 1, 1)
		end
	end
	local lo, hi = CS.Scale(values, #hours, true)
	if not lo then return nil, hours end
	return {
		n = #hours, values = values, min = lo, max = hi, color = CS.ONLINE_COLOR, tips = tips,
		top = F(hi), bottom = F(lo), left = L.CENSUS_STATS_HOURS_AGO:format(CS.HOURS), right = L.CENSUS_STATS_NOW,
	}, hours
end

-- A graph's heading, the graph (or why there is none yet) and its summary on hover.
local function GraphLines(lines, title, graph, series, value, label)
	local Vw = V()
	lines[#lines + 1] = { text = title, header = true }
	local tip = SeriesTip(title, series, value, label)
	if graph then
		graph.tip = tip
		lines[#lines + 1] = { graph = graph, gapAfter = true }
	else
		lines[#lines + 1] = { text = Vw.Grey(L.CENSUS_STATS_EMPTY_GRAPH), tooltip = tip, gapAfter = true }
	end
end

local function Row(label, right, tip, indent)
	return { text = label, right = right, indent = indent, tooltip = tip and function(tt)
		tt:AddLine(label, 1, 0.82, 0)
		tt:AddLine(tip, 1, 1, 1, true)
	end or nil }
end

-- The army's average level: each guild's, weighted by its size, over those with one.
function CS.AverageLevel(s)
	local sum, weight = 0, 0
	for _, e in ipairs(s.guilds or {}) do
		local tenths = e.counted and ns.Data.AvgTenths(e.g)
		local size = tonumber(e.g and e.g.total) or 0
		if tenths and size > 0 then
			sum, weight = sum + tenths * size, weight + size
		end
	end
	if weight == 0 then return nil end
	return ns.Data.AvgLevelText({ avgLevel = sum / weight / 10 })
end

-- The levels of the soldiers online (seven bands: 1-9 ... 50-59, 60+), from the guilds reporting
-- now whose reports carry them; nil for none.
function CS.LevelBands(s)
	local bands, any = { 0, 0, 0, 0, 0, 0, 0 }, false
	for _, e in ipairs(s.guilds or {}) do
		local levels = e.fresh and type(e.g) == "table" and e.g.levels
		if type(levels) == "table" then
			for i = 1, 7 do
				local n = Count(levels[i])
				if n and n > 0 then bands[i], any = bands[i] + n, true end
			end
		end
	end
	return any and bands or nil
end

local function Percent(n, of)
	if not of or of <= 0 then return "0" end
	local p = n * 100 / of
	if p >= 10 or p == 0 then return tostring(math.floor(p + 0.5)) end
	return ("%d%s%d"):format(math.floor(p), L.DECIMAL_MARK or ".", math.floor(p * 10) % 10)
end

-- The page's lines, its detail title and text (Views.Build's census, while the page shows).
function CS.Build(s, now)
	s = s or ns.Data.Summary()
	now = now or ns.Now()
	local Vw = V()
	local Gold, Grey, Green = Vw.Gold, Vw.Grey, Vw.Green
	local Plain = ns.Codec.Plain
	local lines = {
		{ text = Gold(L.CENSUS_STATS_BACK), onClick = function()
			CS.Close()
			if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
		end, gapAfter = true },
		{ text = L.CENSUS_STATS_TITLE, header = true },
	}
	local characters, people = s.characters or s.total or 0, s.total or 0
	local counted, live = 0, 0
	for _, e in ipairs(s.guilds or {}) do
		if e.counted then counted = counted + 1 end
		if e.fresh then live = live + 1 end
	end
	lines[#lines + 1] = Row(L.CENSUS_STATS_CHARACTERS, White(F(characters)), L.CENSUS_STATS_CHARACTERS_TIP)
	lines[#lines + 1] = Row(L.CENSUS_STATS_PEOPLE, White(F(people)), L.CENSUS_STATS_PEOPLE_TIP)
	lines[#lines + 1] = Row(L.CENSUS_STATS_ALTS, Grey(F(s.alts or 0)), L.CENSUS_STATS_PEOPLE_TIP, 1)
	lines[#lines + 1] = Row(L.CENSUS_STATS_ONLINE, Green(F(s.online or 0)))
	lines[#lines + 1] = Row(L.CENSUS_STATS_GUILDS, White(tostring(counted)) .. "  " .. Grey(L.CENSUS_STATS_GUILDS_LIVE:format(live)), L.CENSUS_STATS_GUILDS_TIP)
	local avg = CS.AverageLevel(s)
	lines[#lines + 1] = Row(L.CENSUS_STATS_AVG, avg and White(avg) or Grey("-"), L.CENSUS_STATS_AVG_TIP)
	lines[#lines].gapAfter = true

	local army, days = ArmyGraph(now)
	GraphLines(lines, L.CENSUS_STATS_ARMY_GRAPH, army, days, function(e) return e.c end, DayLabel)
	local online, hours = OnlineGraph(now)
	GraphLines(lines, L.CENSUS_STATS_ONLINE_GRAPH, online, hours, function(e) return e.o end, HourLabel)

	-- The largest guilds counted, each against the game's cap of a guild.
	local cap = ns.Codec.GUILD_CAP
	local largest = {}
	for _, e in ipairs(s.guilds or {}) do if e.counted then largest[#largest + 1] = e end end
	if #largest > 0 then
		lines[#lines + 1] = { text = L.CENSUS_STATS_LARGEST, header = true }
		for i = 1, math.min(CS.TOP_GUILDS, #largest) do
			local e = largest[i]
			local size = math.min(tonumber(e.g.total) or 0, cap)
			local name = Plain(e.name)
			lines[#lines + 1] = {
				text = e.fresh and name or Grey(name),
				right = White(F(size)) .. " " .. Grey(L.CENSUS_STATS_OF_CAP:format(F(cap))),
				meter = { value = size, total = cap },
				tooltip = function(tt)
					tt:AddLine(name, 1, 0.82, 0)
					tt:AddDoubleLine(L.CENSUS_STATS_CHARACTERS, F(size), 1, 0.82, 0, 1, 1, 1)
					tt:AddDoubleLine(L.CENSUS_STATS_ONLINE, F(e.g.online or 0), 1, 0.82, 0, 0.25, 1, 0.25)
					tt:AddLine(L.CENSUS_STATS_SHARE:format(Percent(size, characters)), 0.75, 0.75, 0.75)
				end,
			}
		end
		if #largest > CS.TOP_GUILDS then
			lines[#lines + 1] = { text = Grey(L.CENSUS_STATS_MORE_GUILDS:format(#largest - CS.TOP_GUILDS)), indent = 1 }
		end
		lines[#lines].gapAfter = true
	end

	-- The levels online.
	local bands = CS.LevelBands(s)
	if bands then
		local sum = 0
		for i = 1, 7 do sum = sum + bands[i] end
		lines[#lines + 1] = { text = L.CENSUS_STATS_LEVELS, header = true, tooltip = function(tt)
			tt:AddLine(L.CENSUS_STATS_LEVELS, 1, 0.82, 0)
			tt:AddLine(L.CENSUS_STATS_LEVELS_TIP, 1, 1, 1, true)
		end }
		for i = 7, 1, -1 do
			if bands[i] > 0 then
				local label = i == 7 and L.CENSUS_STATS_LEVEL_TOP:format(60) or L.CENSUS_STATS_LEVEL_BAND:format(i == 1 and 1 or (i - 1) * 10, i * 10 - 1)
				lines[#lines + 1] = { text = label, right = Green(F(bands[i])) .. " " .. Grey(Percent(bands[i], sum) .. "%"),
					meter = { value = bands[i], total = sum } }
			end
		end
		lines[#lines].gapAfter = true
	end

	local since = CS.Since()
	if since then lines[#lines + 1] = { text = Grey(L.CENSUS_STATS_KEPT:format(date(L.CENSUS_STATS_DAY_FORMAT, since))) } end
	return lines, L.CENSUS_STATS_DETAIL_TITLE, L.CENSUS_STATS_DETAIL
end

---------------------------------------------------------------------------
-- The sampler
---------------------------------------------------------------------------

ns.On("INIT", function() ns.SafeCall("census history", CS.Prune) end)
ns.On("LOGIN", function()
	ns.Every(CS.TICK, "census history", function() CS.Sample() end)
end)

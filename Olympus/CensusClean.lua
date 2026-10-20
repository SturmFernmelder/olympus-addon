local ADDON, ns = ...

-- The sanitized census (Daniel, 2026-10-19; docs/CENSUS-STATS.md): what the census statistics add
-- to the count, worked out on this client from what it already holds. Computation only, no page:
-- the Bridge's "stats" section (BridgeSections.lua) hands it to the Companion beside the census
-- page's own figures (CensusStats.lua), and the page may show it as lines of its own later.
--   * banned guilds apart: a guild the moderators took off the network (net-off, Moderation.lua) is
--     in no total; its last size this client holds (its report from before, or a trusted relay's
--     row) gives the census "with banned guilds";
--   * departed guilds: not heard for over Data.TOTAL_KEEP, out of every total, listed until Data.KEEP;
--   * each counted guild's confidence: own (our roster), confirmed (two reporters or more agree,
--     Data.Dispute has nothing to say), relayed (a trusted keeper's row), single (one reporter),
--     disputed (Data.Dispute), stale (counted, not fresh: no vote is current);
--   * outliers: a size past what the guild can do since its last good size, behind one reporter or
--     a dispute, counts at that last good size until two reporters agree on the new one, our roster
--     or a relay gives it, or it holds for OUTLIER_HOLD. On the statistics only: the header's count
--     stays Data.Summary's.
-- Its one saved table: ns.rdb.censusClean.sizes, the last good size per guild (pruned at login).
-- Nothing is sent.

local Clean = {}
ns.CensusClean = Clean

Clean.JUMP_MIN = 25          -- members a guild may move between two reports, at least...
Clean.JUMP_SHARE = 0.10      -- ...or this share of its last good size
Clean.JUMP_DRIFT = 20        -- plus this many a minute since (Data.SIZE_DRIFT, the census's own)
Clean.OUTLIER_HOLD = 60 * 60 -- a size held this long by its lone reporter is taken
Clean.MAX_SIZES = 400        -- last good sizes kept (Data.MAX_GUILDS reports at most, and a margin)

local function Whole(v)
	v = tonumber(v)
	if not v or v ~= v or v < 0 then return 0 end
	return math.floor(v)
end

local function Cap() return ns.Codec and ns.Codec.GUILD_CAP or 1000 end
local function Keep() return ns.Data and ns.Data.KEEP or 7 * 24 * 60 * 60 end

local function Sizes()
	local rdb = ns.rdb
	if type(rdb) ~= "table" then return {} end
	local s = type(rdb.censusClean) == "table" and rdb.censusClean or {}
	rdb.censusClean = s
	if type(s.sizes) ~= "table" then s.sizes = {} end
	return s.sizes
end

-- A counted guild's confidence (e: a Data.Summary entry).
function Clean.Confidence(e, now)
	local g = e.g
	if g.mine then return "own" end
	if not e.fresh then return "stale" end
	if g.relayed then return "relayed" end
	local D = ns.Data
	local d = D and D.Dispute and D.Dispute(g, now)
	if not d then return "confirmed" end
	if d.disputed then return "disputed" end
	return "single"
end

local function Allowance(n, minutes)
	return math.max(Clean.JUMP_MIN, n * Clean.JUMP_SHARE) + Clean.JUMP_DRIFT * math.max(0, minutes)
end

-- The size a counted guild counts at on the statistics, and whether it is held as an outlier; keeps
-- its last good size. Agreement (own, confirmed, relayed) always gives the good one.
local function Judge(name, total, status, now)
	local sizes = Sizes()
	local key = name:lower()
	local last = sizes[key]
	local trusted = status == "own" or status == "confirmed" or status == "relayed"
	if type(last) ~= "table" or type(last.n) ~= "number" or trusted
		or math.abs(total - last.n) <= Allowance(last.n, (now - (tonumber(last.t) or now)) / 60) then
		sizes[key] = { n = total, t = now }
		return total, false
	end
	if last.pend == total then
		if now - (tonumber(last.pendT) or now) >= Clean.OUTLIER_HOLD then
			sizes[key] = { n = total, t = now }
			return total, false
		end
	else
		last.pend, last.pendT = total, now
	end
	return last.n, true
end

function Clean.Prune(now)
	now = now or ns.Now()
	local sizes, list = Sizes(), {}
	for key, e in pairs(sizes) do
		if type(e) ~= "table" or now - (tonumber(e.t) or 0) > Keep() then sizes[key] = nil else list[#list + 1] = { key = key, t = e.t } end
	end
	if #list > Clean.MAX_SIZES then
		table.sort(list, function(a, b) return a.t > b.t end)
		for i = Clean.MAX_SIZES + 1, #list do sizes[list[i].key] = nil end
	end
end

-- A banned guild's last size held (its own report kept from before: Data refuses new ones; or a
-- trusted relay's row), and when it was observed; nil when this client never heard it.
local function BannedSize(name)
	local key, found = name:lower(), nil
	for gname, g in pairs(ns.rdb and ns.rdb.guilds or {}) do
		if type(gname) == "string" and gname:lower() == key and type(g) == "table" then found = { n = g.total, t = g.t }; break end
	end
	local relay = type(ns.rdb and ns.rdb.censusGlobal) == "table" and ns.rdb.censusGlobal[key]
	if type(relay) == "table" and (not found or (tonumber(relay.observed) or 0) > (tonumber(found.t) or 0)) then
		found = { n = relay.total, t = relay.observed }
	end
	if not found or ns.Now() - (tonumber(found.t) or 0) > Keep() then return nil end
	return math.min(Whole(found.n), Cap()), Whole(found.t)
end

local function Banned()
	local M, out, seen = ns.Moderation, {}, {}
	if type(M) ~= "table" or type(M.List) ~= "function" then return out end
	local ok, list = pcall(M.List)
	if not ok or type(list) ~= "table" then return out end
	for _, e in ipairs(list) do
		if type(e) == "table" and e.kind == "g" and e.off and type(e.name) == "string" and not seen[e.name:lower()] then
			seen[e.name:lower()] = true
			local n, t = BannedSize(e.name)
			out[#out + 1] = { name = e.name, members = n or 0, known = n ~= nil, t = t }
		end
	end
	table.sort(out, function(a, b)
		if a.members ~= b.members then return a.members > b.members end
		return a.name < b.name
	end)
	return out
end

local function Duplicates(set)
	local A = ns.Alts
	if not (A and A.Duplicates) or not next(set) then return 0 end
	local ok, n = pcall(A.Duplicates, set)
	return ok and Whole(n) or 0
end

-- Everything the sanitized census adds, from `s` (Data.Summary(), read once by the caller so the
-- figures beside it are the same census) at `now`.
function Clean.Compute(s, now)
	s = s or ns.Data.Summary()
	now = now or ns.Now()
	local D = ns.Data
	local out = {
		excess = 0, confirmedPeople = 0, addonOnline = 0,
		confidence = { own = 0, confirmed = 0, relayed = 0, single = 0, disputed = 0, stale = 0 },
		banned = { guilds = 0, characters = 0, list = {} },
		departed = { guilds = 0, characters = 0, list = {} },
		outliers = { guilds = 0, list = {} },
		guilds = {}, seen = {},
	}
	local sure = {}
	for _, e in ipairs(s.guilds or {}) do
		local g = e.g
		local reported = math.min(Whole(g.total), Cap())
		if not e.counted then
			out.departed.guilds = out.departed.guilds + 1
			out.departed.characters = out.departed.characters + reported
			out.departed.list[#out.departed.list + 1] = { name = e.name, members = reported, t = Whole(g.t) }
		else
			local status = Clean.Confidence(e, now)
			local members, outlier = Judge(e.name, reported, status, now)
			if outlier then
				out.outliers.guilds = out.outliers.guilds + 1
				out.outliers.list[#out.outliers.list + 1] = { name = e.name, reported = reported, kept = members }
				out.excess = out.excess + (reported - members)
			end
			out.confidence[status] = out.confidence[status] + members
			if status == "own" or status == "confirmed" or status == "relayed" then
				out.confirmedPeople = out.confirmedPeople + members
				sure[e.name:lower()] = true
			end
			local online, users = 0, 0
			if e.fresh then
				online, users = math.min(members, Whole(g.online)), Whole(g.users)
				out.addonOnline = out.addonOnline + users
			end
			out.guilds[#out.guilds + 1] = { name = e.name, members = members, online = online, users = users,
				avg10 = D.AvgTenths and D.AvgTenths(g) or nil, status = outlier and "outlier" or status }
		end
	end
	out.confirmedPeople = math.max(0, out.confirmedPeople - Duplicates(sure))
	for _, b in ipairs(Banned()) do
		out.banned.guilds = out.banned.guilds + 1
		out.banned.characters = out.banned.characters + b.members
		out.banned.list[#out.banned.list + 1] = b
	end
	for _, e in ipairs(s.seen or {}) do out.seen[#out.seen + 1] = { name = e.name, online = Whole(e.online) } end
	table.sort(out.guilds, function(a, b)
		if a.members ~= b.members then return a.members > b.members end
		local la, lb = a.avg10 or 0, b.avg10 or 0
		if la ~= lb then return la > lb end
		return a.name < b.name
	end)
	table.sort(out.departed.list, function(a, b)
		if a.t ~= b.t then return a.t > b.t end
		return a.name < b.name
	end)
	return out
end

ns.On("INIT", function() ns.SafeCall("census clean", Clean.Prune) end)

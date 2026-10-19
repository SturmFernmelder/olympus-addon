local ADDON, ns = ...
local L = ns.L

-- The Watch is the restricted, guild-local moderation desk.  It deliberately keeps its own
-- records out of GUILD and the realm channel: actions are logged addon whispers to the other
-- currently-online officers of this guild, and both ends recheck the live guild roster.  The
-- realm-wide net-off list and the King's court remain owned by Moderation.lua and Court.lua; this
-- page only brings their existing views together.

local Watch = {}
ns.Watch = Watch
if ns.Moderation then ns.Moderation.Watch = Watch end

Watch.PROTOCOL = 1
Watch.MESSAGE_MAX = 255
Watch.REASON_MAX = 80
Watch.MAX_RECORDS = 200
Watch.RECORDS_HARD = 1000   -- 1.2.0: records at most, active or not (the oldest watch first, a ban last)
Watch.MW_RATE = 30          -- 1.2.0: one officer's actions taken a minute at most
Watch.MAX_AUDIT = 200
Watch.MIN_AUDIT = 20
Watch.MAX_ATTEMPTS = 50
Watch.MAX_SEEN = 100
Watch.MAX_SEQ = 2147483647
Watch.SEQ_EPOCH = 1767225600 -- 2026-01-01; a SavedVariables reset still advances for other officers.
Watch.SEQ_SLOP = 120
Watch.DATE_AHEAD = 60
Watch.KEEP = 90 * 86400
Watch.WARNING_KEEP = 30 * 86400
Watch.ATTEMPT_GAP = 60
Watch.ROSTER_FRESH = 120
Watch.SYNC_GAP = 300
Watch.SYNC_WINDOW = 20 * 60
Watch.SYNC_MAX_ROWS = 1400
Watch.SYNC_MAX_PAGES = 1400
Watch.SYNC_MAX_SESSIONS = 6
Watch.SYNC_INITIAL_PER_SENDER = 2
Watch.SYNC_INITIAL_WINDOW = 600
-- The High Council's ladder: a warning, then 1 hour, 24 hours and 7 days; the
-- count resets after WARNING_KEEP (30 days) without a new warning. 1.1.6: a step is a real timeout
-- in Olympus's chats (WatchChat.lua), not only a flag on the desk.
Watch.TIMEOUTS = { 0, 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60 }
Watch.MAX_TIMEOUT = Watch.TIMEOUTS[#Watch.TIMEOUTS]
-- 1.1.6: the players' reports (MR) and the Reports and Cases pages.
Watch.REPORT_CATEGORIES = { A = "WATCH_REPORT_CAT_A", S = "WATCH_REPORT_CAT_S", E = "WATCH_REPORT_CAT_E", O = "WATCH_REPORT_CAT_O" }
-- Abuse or slurs, spam or scams, not in English (Olympus's chats are in English only), something else.
Watch.REPORT_ORDER = { "A", "S", "E", "O" }
Watch.REPORT_NOTE_MAX = 80
Watch.REPORT_LINES = 3            -- the reported player's newest Olympus-chat lines this client kept, at most
Watch.REPORT_LINE_MAX = 140       -- bytes of each
Watch.REPORT_LINE_WINDOW = 86400  -- lines this recent
-- Of the public Olympus channel alone: the Captains' and Lords' channels' lines would reach
-- officers (or a signed moderator) who can't read those channels.
Watch.REPORT_TIERS = { "A" }
Watch.REPORT_DEDUPE = 86400       -- a reporter's client: one report a day on the same name...
Watch.REPORT_GAP = 60             -- ...one a minute...
Watch.REPORT_DAY = 5              -- ...and five a day
Watch.REPORT_HOLD = 30 * 86400    -- a report no officer was online for waits privately for one
Watch.REPORT_RETRY = 60           -- and is tried again at most this often
Watch.OUTBOX_MAX = 5
Watch.MAX_REPORTS = 200           -- reports an officer's client keeps (the oldest go)
Watch.REPORT_KEEP = 30 * 86400
Watch.REPORT_RATE = 5             -- an officer's client takes this many reports from one player...
Watch.REPORT_RATE_WINDOW = 3600   -- ...in this long
Watch.REPORT_RATE_ALL = 40        -- and this many from everyone...
Watch.REPORT_RATE_ALL_WINDOW = 600 -- ...in this long
Watch.LINES_WAIT = 120            -- a report's evidence lines are taken this long after it
Watch.TOLD_GAP = 600              -- an officer is told of new reports on one name this often at most

local OPS = { W = true, V = true, B = true, C = true }
-- 1.1.6: the chat moderation's own entries in this audit (WatchChat.lua: a line deleted, recent
-- lines deleted, a timeout, a lift). This client's own record: never in a recovery snapshot (each
-- client hears the action itself, and its actor repeats it).
local CHAT_OPS = { D = true, P = true, T = true, L = true }
Watch.CHAT_OPS = CHAT_OPS
local stats = { sent = 0, taken = 0, refused = 0, replay = 0, malformed = 0, oversized = 0, revoked = 0, attempts = 0 }
local attemptAt = {}
local pendingTargets = {}
local syncAsked, syncIncoming, syncOutgoing, syncRates = {}, {}, {}, {}
local mwRates = {} -- [sender key] = { times }: his actions this minute (Watch.MW_RATE)
local syncQueued, flushQueued = false, false -- (1.2.1: one recovery ask, one report flush waiting: DATA_CHANGED)
local syncCounter, syncPeerIndex, lastSync = 0, 0, -math.huge

Watch.after = function(seconds, where, fn) ns.After(seconds, where, fn) end

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff6060" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local function Clock() return ns.Data and ns.Data.ServerTime and ns.Data.ServerTime() or ns.Now() end
local function Mono() return ns.Now() end
local function Key(s) return ns.Fold(tostring(s or "")) end

local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and Key(a) == Key(b)
end

local function CleanReason(s)
	s = tostring(s or ""):gsub("[~|%^%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, Watch.REASON_MAX)
end

local function OwnGuild()
	local guild = GetGuildInfo and GetGuildInfo("player")
	if type(guild) ~= "string" or guild == "" or not ns.IsFederation(guild)
		or guild:find("~", 1, true) or guild:find("|", 1, true) or guild:find("[%c]") then return nil end
	return ns.Cut(guild, 72)
end
Watch.OwnGuild = OwnGuild

local function Character(input, target)
	local M = ns.Moderation
	local name = M and M.CharName and M.CharName(input, target)
	if type(name) ~= "string" or name == "" or #name > 72 or name:find("[~%^%c]") then return nil end
	return name
end

local function LiveRank()
	if not GetGuildInfo then return nil end
	local guild, _, rank = GetGuildInfo("player")
	if guild ~= OwnGuild() or type(rank) ~= "number" then return nil end
	return math.max(0, math.floor(rank))
end

local function FreshRoster()
	local R, guild = ns.Roster, OwnGuild()
	if not R or not guild or R.complete ~= true or type(R.byName) ~= "table" or type(R.generation) ~= "number" or R.generation < 1
		or R.guild ~= guild or R.group ~= ns.group or R.faction ~= ns.faction or type(R.snapshotAt) ~= "number" then return nil end
	local age = Mono() - R.snapshotAt
	if age < 0 or age > Watch.ROSTER_FRESH then return nil end
	return R
end
Watch.FreshRoster = FreshRoster

local function RosterRank(name)
	name = type(name) == "string" and ns.FullName(name) or nil
	if not name then return nil end
	if ns.me and Same(name, ns.me) then return LiveRank() end
	local R = FreshRoster()
	if not (R and R.RankOf) then return nil end
	local rank = R.RankOf(name)
	-- (1.2.0: a target written in another case is the same member, never a stranger to warn.)
	if rank == nil and type(R.byName) == "table" then
		local key = ns.Fold(name)
		for n, r in pairs(R.byName) do if ns.Fold(n) == key then return r end end
	end
	return rank
end
Watch.RosterRank = RosterRank -- (1.1.6: WatchChat.lua)

-- This is intentionally local-guild authority.  The live server roster is the trust anchor for
-- Lords/Captains; an existing signed moderator counts only while that same character is also in
-- this roster.  A census claim cannot grant access.
local function SignedModerator(name, guild, rank)
	if rank == nil or not guild then return false end
	-- A signed moderator is an additional local role only after the explicit authority boundary is
	-- active, its certificate is live, and that certificate names this exact character in this
	-- exact guild.  A legacy title or census report alone never upgrades a roster member.
	local A = ns.Authority
	if not (A and A.Enforced and A.Enforced() and A.Manifest and A.Manifest()
		and A.Rank and ns.Moderation and ns.Moderation.IsIssuer and ns.Moderation.IsIssuer(name)) then return false end
	local signed, source = A.Rank(name, guild)
	return signed ~= nil and source == "signed"
end

function Watch.IsAuthorized(name)
	local guild = OwnGuild()
	if not guild or type(name) ~= "string" or name == "" then return false end
	name = ns.FullName(name)
	local rank = RosterRank(name)
	if rank == nil then return false end
	local M = ns.Moderation
	if M and ((M.Hides and M.Hides(name, guild)) or (not M.Hides and M.Hidden and M.Hidden(name))) then return false end
	-- 1.1.6 (WatchChat.lua): a sanctioned player (a timeout, a hold) has none of the powers Olympus
	-- gives; and the guild master's named Watchers (and his Justice correspondent) are Watchers.
	local WC = ns.WatchChat
	local who = name
	if Same(name, ns.me) then who = nil end -- (this character: its own word and guild too, Moderation.SelfOff)
	if WC and WC.Barred and WC.Barred("powers", who) then return false end
	return rank <= ns.CAPTAIN_RANK or SignedModerator(name, guild, rank) or (WC ~= nil and WC.IsNamedWatcher ~= nil and WC.IsNamedWatcher(name) == true)
end

function Watch.CanRead()
	return ns.me ~= nil and ns.IsMember() and OwnGuild() ~= nil and Watch.IsAuthorized(ns.me)
end
Watch.CanManage = Watch.CanRead

local function Identity()
	local guild = OwnGuild()
	if not guild or type(ns.group) ~= "string" or ns.group == "" or type(ns.faction) ~= "string" or ns.faction == "" then return nil end
	return { guild = guild, group = ns.group, faction = ns.faction }
end

local function EmptyStore(id)
	return { version = 2, guild = id.guild, group = id.group, faction = id.faction,
		records = {}, audit = {}, attempts = {}, seen = {}, seq = 0, localAt = 0, revision = 0,
		reports = {}, reportSeen = {}, closed = {}, findings = {} }
end

local function SameIdentity(s, id)
	return type(s) == "table" and s.version == 2 and s.guild == id.guild and s.group == id.group and s.faction == id.faction
end

local function IdentityKey(id)
	-- Keep all three dimensions in the key even though ns.rdb is already selected by faction and
	-- realm group.  That redundancy makes a misplaced/corrupt table unreachable instead of ever
	-- being mistaken for this guild's private state.
	local faction, group, guild = Key(id.faction), Key(id.group), Key(id.guild)
	return #faction .. ":" .. faction .. #group .. ":" .. group .. #guild .. ":" .. guild
end

local function Store(create)
	local id = Identity()
	if not id or type(ns.rdb) ~= "table" then return nil end
	local all = ns.rdb.watchGuilds
	if type(all) ~= "table" then
		if not create then return nil end
		all = {}
		ns.rdb.watchGuilds = all
	end
	local key = IdentityKey(id)
	local s = all[key]
	-- Account-wide v1 data is intentionally not consulted or migrated: its realm/faction origin is
	-- unknowable.  Likewise, legacy guild-only or mismatched identities in this realm store remain
	-- unreachable and are never merged into this exact identity.
	if not SameIdentity(s, id) then
		if not create then return nil end
		s = EmptyStore(id)
		all[key] = s
	end
	-- (1.1.6: the players' reports, the cases closed without action and this officer's own
	-- findings; this client's alone, never in a recovery snapshot.)
	for _, field in ipairs({ "records", "audit", "attempts", "seen", "reports", "reportSeen", "closed", "findings" }) do
		if type(s[field]) ~= "table" then s[field] = {} end
	end
	s.seq = math.max(0, math.floor(tonumber(s.seq) or 0))
	s.localAt = math.max(0, math.floor(tonumber(s.localAt) or 0))
	s.revision = math.max(0, math.floor(tonumber(s.revision) or 0))
	return s, id.guild
end
Watch.Store = Store

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

local function SequenceFits(seq, at)
	return type(seq) == "number" and type(at) == "number" and seq >= 1 and seq <= Watch.MAX_SEQ
		and seq <= math.max(1, at - Watch.SEQ_EPOCH) + Watch.SEQ_SLOP
end

local function Trim(list, max)
	while #list > max do table.remove(list, 1) end
end

local function ValidRecord(key, e)
	if type(key) ~= "string" or type(e) ~= "table" or Character(e.name) == nil then return false end
	if Key(e.name) ~= key or (e.status ~= nil and e.status ~= "watch" and e.status ~= "ban") then return false end
	if type(e.warnings) ~= "number" or e.warnings < 0 or e.warnings ~= math.floor(e.warnings) then return false end
	if type(e.interventions) ~= "number" or e.interventions < 0 or e.interventions ~= math.floor(e.interventions) then return false end
	return true
end

local function Inactive(e, now)
	return not e.status and (tonumber(e.warnings) or 0) == 0 and (tonumber(e.timeoutUntil) or 0) <= now
end

local function TrimInactive(s, now, reserve)
	reserve = math.max(0, math.floor(tonumber(reserve) or 0))
	while Count(s.records) + reserve > Watch.MAX_RECORDS do
		local oldest, oldestAt
		for key, e in pairs(s.records) do
			if Inactive(e, now) then
				local at = tonumber(e.lastAt) or 0
				if not oldestAt or at < oldestAt or (at == oldestAt and key < oldest) then oldest, oldestAt = key, at end
			end
		end
		if not oldest then break end -- active entries are never discarded merely to satisfy the soft cap
		s.records[oldest] = nil
	end
	-- (1.2.0: the hard cap, active or not: the oldest one not ban-listed first, then the oldest ban.)
	while Count(s.records) + reserve > Watch.RECORDS_HARD do
		local oldest, oldestAt, oldestBan
		for key, e in pairs(s.records) do
			local at, ban = tonumber(e.lastAt) or 0, e.status == "ban"
			local better = not oldest or (oldestBan and not ban) or (ban == oldestBan and (at < oldestAt or (at == oldestAt and key < oldest)))
			if better then oldest, oldestAt, oldestBan = key, at, ban end
		end
		if not oldest then break end
		s.records[oldest] = nil
	end
end

-- 1.1.6: may a report's evidence line be of this chat (REPORT_TIERS)?
local function TierAllowed(tier)
	for _, t in ipairs(Watch.REPORT_TIERS) do if t == tier then return true end end
	return false
end

-- 1.1.6: a report as an officer's client keeps it ([reporter key .. "#" .. name key]: the
-- newest from each player on each name), checked again (the SavedVariables can be edited).
local function ValidReport(id, r)
	if type(r) ~= "table" or not Character(r.reporter) or not Character(r.target) or Same(r.reporter, r.target) then return false end
	if id ~= Key(r.reporter) .. "#" .. Key(r.target) or not Watch.REPORT_CATEGORIES[r.cat] then return false end
	if type(r.at) ~= "number" or r.at ~= math.floor(r.at) or type(r.note) ~= "string" or type(r.lines) ~= "table" then return false end
	local n = tonumber(r.n) or 0
	if n < 0 or n > Watch.REPORT_LINES then return false end
	for i, line in pairs(r.lines) do
		if type(i) ~= "number" or i < 1 or i > n or type(line) ~= "table" or type(line.text) ~= "string"
			or type(line.at) ~= "number" or not TierAllowed(line.tier) then r.lines[i] = nil end
	end
	return true
end

local function TrimReports(s)
	while Count(s.reports) > Watch.MAX_REPORTS do
		local oldest, at
		for id, r in pairs(s.reports) do
			if not at or r.at < at or (r.at == at and id < oldest) then oldest, at = id, r.at end
		end
		if not oldest then break end
		s.reports[oldest] = nil
	end
end

function Watch.Prune()
	-- (1.2.1: the council's book too, on the King's and each councillor's client.)
	if Watch.PruneCouncil then Watch.PruneCouncil() end
	local s = Store(false)
	if not s then return end
	local now = Clock()
	-- 1.1.6: reports past REPORT_KEEP or that no longer read go, then the oldest past MAX_REPORTS;
	-- so do the cases' closes, this officer's findings and the reporters' replay floors.
	for id, r in pairs(s.reports) do
		if not ValidReport(id, r) or now - r.at > Watch.REPORT_KEEP then s.reports[id] = nil end
	end
	TrimReports(s)
	for key, c in pairs(s.closed) do
		if type(key) ~= "string" or type(c) ~= "table" or type(c.at) ~= "number" or now - c.at > Watch.REPORT_KEEP then s.closed[key] = nil end
	end
	for key, f in pairs(s.findings) do
		if type(key) ~= "string" or type(f) ~= "table" or (f.verdict ~= "up" and f.verdict ~= "down")
			or now - (tonumber(f.at) or 0) > Watch.REPORT_KEEP then s.findings[key] = nil end
	end
	-- (A replay floor goes once a report of its date is refused by its date alone: TakeReportHead.)
	for who, e in pairs(s.reportSeen) do
		if type(who) ~= "string" or type(e) ~= "table" or type(e.seq) ~= "number" or type(e.at) ~= "number"
			or now - e.at > Watch.REPORT_HOLD + Watch.DATE_AHEAD then s.reportSeen[who] = nil end
	end
	for key, e in pairs(s.records) do
		if not ValidRecord(key, e) then
			s.records[key] = nil
		else
			e.timeoutUntil = tonumber(e.timeoutUntil) or 0
			e.lastAt = tonumber(e.lastAt) or 0
			e.statusAt = tonumber(e.statusAt) or 0
			e.warningAt = tonumber(e.warningAt) or (e.warnings > 0 and e.lastAt or 0)
			e.warningResetAt = tonumber(e.warningResetAt) or (e.warnings == 0 and e.warningAt or 0)
			e.updatedAt = tonumber(e.updatedAt) or e.lastAt
			if e.lastVia and not Character(e.lastVia) then e.lastVia = nil end
			if e.timeoutUntil <= now then e.timeoutUntil = 0 end
			if e.warnings > 0 and now - e.warningAt > Watch.WARNING_KEEP then
				e.warnings, e.warningAt = 0, now
				e.warningResetAt = now
				e.updatedAt, e.updatedBy = now, ns.me or e.updatedBy
				s.revision = s.revision + 1
			end
			if Inactive(e, now) and now - e.lastAt > Watch.KEEP then s.records[key] = nil end
		end
	end
	TrimInactive(s, now, 0)
	local validAudit = {}
	for _, e in ipairs(s.audit) do
		if type(e) == "table" and (OPS[e.op] or CHAT_OPS[e.op]) and Character(e.name) and Character(e.by)
			and type(e.at) == "number" and e.at <= now + Watch.DATE_AHEAD then
			e.reason = CleanReason(e.reason)
			if e.text ~= nil then e.text = type(e.text) == "string" and ns.Cut(e.text, Watch.REPORT_LINE_MAX) or nil end
			if e.via and not Character(e.via) then e.via = nil end
			e.seq = math.max(0, math.floor(tonumber(e.seq) or 0))
			if SequenceFits(e.seq, e.at) then validAudit[#validAudit + 1] = e end
		end
	end
	local audit, keepFrom = {}, math.max(1, #validAudit - Watch.MIN_AUDIT + 1)
	for i, e in ipairs(validAudit) do
		if now - e.at <= Watch.KEEP or i >= keepFrom then audit[#audit + 1] = e end
	end
	s.audit = audit
	Trim(s.audit, Watch.MAX_AUDIT)
	local attempts = {}
	for _, e in ipairs(s.attempts) do
		if type(e) == "table" and Character(e.name) and Character(e.match) and type(e.at) == "number" and now - e.at <= Watch.KEEP then
			attempts[#attempts + 1] = e
		end
	end
	s.attempts = attempts
	Trim(s.attempts, Watch.MAX_ATTEMPTS)
	for who, e in pairs(s.seen) do
		if type(who) ~= "string" or type(e) ~= "table" or type(e.seq) ~= "number" or type(e.at) ~= "number" or not SequenceFits(e.seq, e.at)
			or now - e.at > Watch.KEEP then s.seen[who] = nil end
	end
	while Count(s.seen) > Watch.MAX_SEEN do
		local oldest, at
		for who, e in pairs(s.seen) do if not at or e.at < at then oldest, at = who, e.at end end
		if not oldest then break end
		s.seen[oldest] = nil
	end
end

local function TupleNewer(at, by, oldAt, oldBy)
	at, oldAt = tonumber(at) or 0, tonumber(oldAt) or 0
	if at ~= oldAt then return at > oldAt end
	return Key(by) > Key(oldBy)
end

local function StatusNewer(a, e)
	return TupleNewer(a.at, a.by, e.statusAt, e.statusBy)
end

local function Apply(a)
	local s = Store(true)
	if not s then return false, "guild" end
	local key = Key(a.name)
	local e = s.records[key]
	if type(e) ~= "table" then
		TrimInactive(s, Clock(), 1)
		e = { name = a.name, warnings = 0, interventions = 0, warningAt = 0, warningResetAt = 0,
			timeoutUntil = 0, statusAt = 0, updatedAt = 0 }
		s.records[key] = e
	end
	e.name = a.name
	e.warningResetAt = tonumber(e.warningResetAt) or 0
	local warningApplied = a.op == "W" and a.at > e.warningResetAt
	local statusApplied = a.op ~= "W" and StatusNewer(a, e)
	local applied = warningApplied or statusApplied
	if applied and (a.at > (tonumber(e.lastAt) or 0)
		or (a.at == (tonumber(e.lastAt) or 0) and Key(a.by) >= Key(e.lastBy))) then
		e.lastAt, e.lastBy, e.lastReason, e.lastVia = a.at, a.by, a.reason, nil
	end
	if warningApplied then
		e.warnings = (tonumber(e.warnings) or 0) + 1
		e.interventions = (tonumber(e.interventions) or 0) + 1
		e.warningAt = math.max(tonumber(e.warningAt) or 0, a.at)
		e.timeoutUntil = math.max(tonumber(e.timeoutUntil) or 0, tonumber(a.untilAt) or 0)
	elseif statusApplied then
		e.interventions = (tonumber(e.interventions) or 0) + 1
		e.statusAt, e.statusBy = a.at, a.by
		if a.op == "V" then e.status = "watch"
		elseif a.op == "B" then e.status = "ban"
		elseif a.op == "C" then
			e.status = nil
			e.warningResetAt = math.max(e.warningResetAt, a.at)
			if (tonumber(e.warningAt) or 0) <= a.at then
				e.timeoutUntil = 0
				e.warnings, e.warningAt = 0, a.at
			end
		end
	end
	if applied and TupleNewer(a.at, a.by, e.updatedAt, e.updatedBy) then e.updatedAt, e.updatedBy = a.at, a.by end
	s.audit[#s.audit + 1] = { op = a.op, name = a.name, at = a.at, by = a.by, seq = a.seq,
		reason = a.reason, untilAt = a.untilAt or 0 }
	Trim(s.audit, Watch.MAX_AUDIT)
	s.revision = s.revision + 1
	ns.Fire("WATCH_CHANGED")
	return true
end

-- 1.1.6: a chat moderation action (WatchChat.lua) on a member, as this guild's Watch keeps it:
-- in the audit (who, whom, what, why, when, and the deleted words this client kept, local only)
-- and as one intervention on his record. Once per actor and sequence (a repeat adds nothing).
function Watch.ApplyChat(a)
	if type(a) ~= "table" or not CHAT_OPS[a.op] then return false, "op" end
	local name, by = Character(a.name), Character(a.by)
	local s = Store(true)
	if not name or not by or not s then return false, "shape" end
	local at, seq = math.floor(tonumber(a.at) or 0), math.floor(tonumber(a.seq) or 0)
	if not SequenceFits(seq, at) then return false, "sequence" end
	for i = #s.audit, 1, -1 do
		local x = s.audit[i]
		if x.op == a.op and x.seq == seq and Same(x.by, by) then return false, "repeat" end
	end
	local key = Key(name)
	local e = s.records[key]
	if type(e) ~= "table" then
		TrimInactive(s, Clock(), 1)
		e = { name = name, warnings = 0, interventions = 0, warningAt = 0, warningResetAt = 0,
			timeoutUntil = 0, statusAt = 0, updatedAt = 0 }
		s.records[key] = e
	end
	local reason, via = CleanReason(a.reason), Character(a.via)
	e.interventions = (tonumber(e.interventions) or 0) + 1
	if at > (tonumber(e.lastAt) or 0) then e.lastAt, e.lastBy, e.lastReason, e.lastVia = at, by, reason, via end
	s.audit[#s.audit + 1] = { op = a.op, name = name, at = at, by = by, via = via, seq = seq, reason = reason,
		untilAt = math.max(0, math.floor(tonumber(a.untilAt) or 0)), scope = a.scope == "O" and "O" or "G",
		text = type(a.text) == "string" and a.text ~= "" and ns.Cut(a.text, Watch.REPORT_LINE_MAX) or nil }
	Trim(s.audit, Watch.MAX_AUDIT)
	s.revision = s.revision + 1
	ns.Fire("WATCH_CHANGED")
	return true
end

function Watch.ActiveTimeout(name, now)
	if not Watch.CanRead() then return nil end
	local s = Store(false)
	local e = s and s.records[Key(Character(name) or "")]
	local untilAt = e and tonumber(e.timeoutUntil) or 0
	-- 1.1.6: the one enforced in Olympus's chats (WatchChat.lua), from whichever moderator.
	local WC = ns.WatchChat
	local enforced = WC and WC.TimeoutEnd and WC.TimeoutEnd(name)
	untilAt = math.max(untilAt, tonumber(enforced) or 0)
	return untilAt > (tonumber(now) or Clock()) and untilAt or nil
end

function Watch.Record(name)
	if not Watch.CanRead() then return nil end
	Watch.Prune()
	local s = Store(false)
	return s and s.records[Key(Character(name) or "")] or nil
end

function Watch.Records()
	if not Watch.CanRead() then return {} end
	Watch.Prune()
	local s, out = Store(false), {}
	for _, e in pairs(s and s.records or {}) do out[#out + 1] = e end
	table.sort(out, function(a, b)
		local ap, bp = a.status == "ban" and 1 or a.status == "watch" and 2 or 3, b.status == "ban" and 1 or b.status == "watch" and 2 or 3
		if ap ~= bp then return ap < bp end
		if (a.interventions or 0) ~= (b.interventions or 0) then return (a.interventions or 0) > (b.interventions or 0) end
		return Key(a.name) < Key(b.name)
	end)
	return out
end

function Watch.Audit()
	if not Watch.CanRead() then return {} end
	Watch.Prune()
	local s, out = Store(false), {}
	for i = #(s and s.audit or {}), 1, -1 do out[#out + 1] = s.audit[i] end
	return out
end

function Watch.Attempts()
	if not Watch.CanRead() then return {} end
	Watch.Prune()
	local s, out = Store(false), {}
	for i = #(s and s.attempts or {}), 1, -1 do out[#out + 1] = s.attempts[i] end
	return out
end

function Watch.Interventions(name)
	local e = Watch.Record(name)
	return e and tonumber(e.interventions) or 0
end

function Watch.TimeoutFor(warnings)
	warnings = math.max(1, math.floor(tonumber(warnings) or 1))
	return Watch.TIMEOUTS[math.min(warnings, #Watch.TIMEOUTS)]
end

local function TargetAllowed(actor, target)
	if ns.Moderation and ns.Moderation.IsKing and ns.Moderation.IsKing(target) then return false, "rank" end
	-- A fresh snapshot is required even for a target absent from it: only then does absence mean
	-- "not a current guild member" rather than "we are looking at the last guild's rows".
	if not FreshRoster() then return false, "roster" end
	local actorRank, targetRank = RosterRank(actor), RosterRank(target)
	if actorRank == nil then return false, "roster" end
	-- Guild rank order governs Lords/Captains.  A signed moderator may act on ordinary members at
	-- the same Blizzard rank, but never on a Lord/Captain or another Watch-authorized peer.
	if targetRank ~= nil and targetRank <= ns.CAPTAIN_RANK
		and (actorRank == nil or targetRank <= actorRank) then return false, "rank" end
	if actorRank ~= nil and actorRank > ns.CAPTAIN_RANK and Watch.IsAuthorized(target) then return false, "rank" end
	local M = ns.Moderation
	local authority = M and M.TargetRank and M.TargetRank(target) or 0
	local mine = M and M.Rank and M.Rank(actor) or 0
	if authority > 0 and mine <= authority then return false, "rank" end
	return true
end

Watch.TargetAllowed = TargetAllowed -- (1.1.6: WatchChat.lua, a Watcher's chat actions)

local function Action(op, target, reason)
	if not OPS[op] then return nil, "op" end
	if not Watch.CanManage() then return nil, "access" end
	Watch.Prune()
	local guild = OwnGuild()
	target = Character(target, true)
	if not target then return nil, "name" end
	if Same(target, ns.me) then return nil, "self" end
	local allowed, why = TargetAllowed(ns.me, target)
	if not allowed then return nil, why end
	reason = CleanReason(reason)
	if op ~= "C" and reason == "" then return nil, "reason" end
	local s = Store(true)
	if not s then return nil, "guild" end
	local now = math.floor(Clock())
	local ownSeen = tonumber(s.seen[Key(ns.me)] and s.seen[Key(ns.me)].seq) or 0
	local seq = math.max(1, now - Watch.SEQ_EPOCH, (tonumber(s.seq) or 0) + 1, ownSeen + 1)
	if seq > Watch.MAX_SEQ then return nil, "sequence" end
	local at = math.max(now, (tonumber(s.localAt) or 0) + 1, Watch.SEQ_EPOCH + seq - Watch.SEQ_SLOP)
	if at > now + Watch.DATE_AHEAD then return nil, "rate" end
	if not SequenceFits(seq, at) then return nil, "sequence" end
	local untilAt = 0
	if op == "W" then
		local e = s.records[Key(target)]
		local warnings = (e and tonumber(e.warnings) or 0) + 1
		untilAt = at + Watch.TimeoutFor(warnings)
		if Watch.TimeoutFor(warnings) == 0 then untilAt = 0 end
	end
	return { op = op, name = target, reason = reason, guild = guild, group = ns.group, faction = ns.faction,
		seq = seq, at = at, untilAt = untilAt, by = ns.me }
end

local function Wire(a)
	if type(a.guild) ~= "string" or type(a.group) ~= "string" or type(a.faction) ~= "string"
		or a.guild == "" or a.group == "" or a.faction == ""
		or a.guild:find("[~%^%c]") or a.group:find("[~%^%c]") or a.faction:find("[~%^%c]") then return nil, "identity" end
	local head = ("MW~%d~%d~%d~%s~%s~%s~%s~%s~%d~"):format(Watch.PROTOCOL, a.seq, a.at,
		a.guild, a.group, a.faction, a.op, a.name, a.untilAt or 0)
	if #head > Watch.MESSAGE_MAX then return nil, "size" end
	local reason = ns.Cut(CleanReason(a.reason), Watch.MESSAGE_MAX - #head)
	local msg = head .. reason
	if #msg > Watch.MESSAGE_MAX then return nil, "size" end
	return msg
end
Watch.Wire = Wire

local function Recipients()
	local roster = FreshRoster()
	if not roster then return {} end
	local out, seen = {}, {}
	for _, m in ipairs(roster.online or {}) do
		local name = Character(m.name)
		local key = name and Key(name)
		if name and not Same(name, ns.me) and not seen[key] and Watch.IsAuthorized(name) then
			seen[key] = true
			out[#out + 1] = name
		end
	end
	table.sort(out, function(a, b) return Key(a) < Key(b) end)
	return out
end
Watch.Recipients = Recipients

-- The capability is evaluated by Comm immediately before the game API call.  A demotion, guild
-- move, net-off word or recipient demotion while the whisper is queued cancels it.
local function Permit(a, recipient, msg, guardKey)
	return function(owner, key, dist, target, payload)
		if owner ~= Watch or key ~= guardKey or dist ~= "WHISPER" or payload ~= msg or not Same(target, recipient) then return false, "guard" end
		local targetAllowed = TargetAllowed(ns.me, a.name)
		if not Watch.CanManage() or OwnGuild() ~= a.guild or ns.group ~= a.group or ns.faction ~= a.faction
			or not Watch.IsAuthorized(recipient) or not targetAllowed then
			stats.revoked = stats.revoked + 1
			return false, "revoked"
		end
		return true
	end
end

local function CommitLocal(a)
	if OwnGuild() ~= a.guild or ns.group ~= a.group or ns.faction ~= a.faction then return false end
	local s = Store(true)
	if not s then return false end
	local ok = Apply(a)
	if ok then
		s.seq, s.localAt = math.max(tonumber(s.seq) or 0, a.seq), math.max(tonumber(s.localAt) or 0, a.at)
		local seen = s.seen[Key(a.by)]
		if not seen or a.seq > (tonumber(seen.seq) or 0) then s.seen[Key(a.by)] = { seq = a.seq, at = a.at } end
		stats.sent = stats.sent + 1
	end
	return ok
end

-- 1.1.6: the High Council's ladder makes a warning's step a real timeout in Olympus's chats,
-- given with it (WatchChat.lua: over GUILD, every client of the guild checks it in its roster).
-- The desk's reason stays the desk's (its officers' logged whispers): the timeout goes without it,
-- as every chat moderation message reaches the guild's members' clients. A warning on a player
-- whose case the King upheld is that judgment applied: its line leaves the case's page.
local function Ladder(a)
	local WC = ns.WatchChat
	if a.op ~= "W" or not WC or WC.missing then return end
	if WC.JudgmentApplied then WC.JudgmentApplied(a.name) end
	if (tonumber(a.untilAt) or 0) <= a.at or not WC.Act then return end
	WC.Act("T", a.name, { seconds = a.untilAt - a.at })
end

function Watch.Send(op, target, reason)
	local targetKey = Key(Character(target, true) or "")
	if targetKey ~= "" and pendingTargets[targetKey] then return false, "pending" end
	local a, why = Action(op, target, reason)
	if not a then return false, why end
	local msg
	msg, why = Wire(a)
	if not msg then return false, why end
	local recipients = Recipients()
	if #recipients == 0 then
		local committed = CommitLocal(a)
		if committed then Ladder(a) end
		return committed, "local"
	end
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < #recipients then return false, "busy" end
	local guardKey = a.guild .. "#" .. tostring(a.seq)
	-- Reserve the sequence before queueing.  A send that later fails may leave a harmless gap, but
	-- two actions queued before either callback can never share a replay identity.
	local store = Store(true)
	store.seq, store.localAt = math.max(store.seq, a.seq), math.max(store.localAt, a.at)
	targetKey = Key(a.name)
	pendingTargets[targetKey] = guardKey
	local pending, accepted, success, committed = #recipients, true, 0, false
	local function Done(ok)
		pending = pending - 1
		if ok then
			success = success + 1
			if not committed then committed = CommitLocal(a) end
		end
		if pending == 0 then
			if pendingTargets[targetKey] == guardKey then pendingTargets[targetKey] = nil end
			if success == 0 then ns.Fire("WATCH_SEND_FAILED", "revoked") end
		end
	end
	for _, recipient in ipairs(recipients) do
		local ok = ns.Comm.Whisper(recipient, msg, nil, false, true, Done,
			{ owner = Watch, key = guardKey, permit = Permit(a, recipient, msg, guardKey) })
		if not ok then accepted = false end
	end
	if not accepted then
		if ns.Comm.CancelQueued then ns.Comm.CancelQueued(Watch, guardKey, "cancelled") end
		return false, "busy"
	end
	Ladder(a)
	return true, "queued"
end

function Watch.IssueWarning(target, reason) return Watch.Send("W", target, reason) end
Watch.Warn = Watch.IssueWarning -- public compatibility for commands, UI and older callers
function Watch.Mark(target, reason) return Watch.Send("V", target, reason) end
function Watch.Ban(target, reason) return Watch.Send("B", target, reason) end
function Watch.Clear(target) return Watch.Send("C", target, "") end

local function Parse(text)
	if type(text) ~= "string" or #text > Watch.MESSAGE_MAX then return nil, "size" end
	local version, seq, at, guild, group, faction, op, name, untilAt, reason =
		text:match("^MW~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)~([WVBC])~([^~]+)~(%d+)~(.*)$")
	version, seq, at, untilAt = tonumber(version), tonumber(seq), tonumber(at), tonumber(untilAt)
	if version ~= Watch.PROTOCOL or not seq or seq < 1 or seq > Watch.MAX_SEQ or seq ~= math.floor(seq)
		or not at or at < 1 or at ~= math.floor(at) or not untilAt or untilAt ~= math.floor(untilAt) or not OPS[op] then return nil, "shape" end
	if not SequenceFits(seq, at) then return nil, "sequence" end
	if guild ~= OwnGuild() or #guild > 72 then return nil, "guild" end
	if group ~= ns.group or faction ~= ns.faction then return nil, "identity" end
	local cleanName = Character(name)
	if not cleanName or cleanName ~= name then return nil, "name" end
	name = cleanName
	local cleanReason = CleanReason(reason)
	if cleanReason ~= reason then return nil, "reason" end
	reason = cleanReason
	if op ~= "C" and reason == "" then return nil, "reason" end
	if op == "W" then
		if untilAt ~= 0 and (untilAt <= at or untilAt - at > Watch.MAX_TIMEOUT) then return nil, "timeout" end
	elseif untilAt ~= 0 then return nil, "timeout" end
	local now = Clock()
	if at > now + Watch.DATE_AHEAD or now - at > Watch.KEEP then return nil, "time" end
	return { op = op, name = name, reason = reason, guild = guild, group = group, faction = faction,
		seq = seq, at = at, untilAt = untilAt }
end
Watch.Parse = Parse

---------------------------------------------------------------------------
-- Private recovery.  One officer asks one other currently-online officer over logged addon
-- WHISPER.  The responder freezes a bounded snapshot and the requester pulls strictly ordered
-- pages.  No page is applied until the final page arrives and every row validates.
---------------------------------------------------------------------------

local function Rate(key, max, window)
	local now = Mono()
	local list = syncRates[key]
	if type(list) ~= "table" then list = {}; syncRates[key] = list end
	for i = #list, 1, -1 do if now - list[i] >= window then table.remove(list, i) end end
	if #list >= max then return false end
	list[#list + 1] = now
	return true
end

local function CleanupSync()
	local now = Mono()
	for nonce, e in pairs(syncAsked) do
		if type(e) ~= "table" or now - (e.started or 0) > Watch.SYNC_WINDOW then syncAsked[nonce] = nil end
	end
	for key, e in pairs(syncIncoming) do
		if type(e) ~= "table" or now - (e.t or 0) > Watch.SYNC_WINDOW then syncIncoming[key], syncOutgoing[key] = nil, nil end
	end
end

local function PrivatePermit(peer, guild, group, faction, msg, guardKey, expected)
	return function(owner, key, dist, target, payload)
		if owner ~= Watch or key ~= guardKey or dist ~= "WHISPER" or not Same(target, peer) or payload ~= msg then return false, "guard" end
		if not Watch.CanRead() or OwnGuild() ~= guild or ns.group ~= group or ns.faction ~= faction
			or not FreshRoster() or not Watch.IsAuthorized(peer)
			or (expected and expected() ~= msg) then
			stats.revoked = stats.revoked + 1
			return false, "revoked"
		end
		return true
	end
end

local function PrivateSend(peer, guild, group, faction, msg, guardKey, expected, done)
	if type(msg) ~= "string" or #msg > Watch.MESSAGE_MAX or not ns.Comm or not ns.Comm.Whisper then return false end
	return ns.Comm.Whisper(peer, msg, nil, false, true, done,
		{ owner = Watch, key = guardKey, permit = PrivatePermit(peer, guild, group, faction, msg, guardKey, expected) })
end

local function SnapshotRows()
	Watch.Prune()
	local s, rows = Store(true), {}
	if not s then return nil end
	local failed = false
	local function Add(row)
		if failed then return end
		if type(row) ~= "string" or #row > 205 or row:find("^", 1, true) or #rows >= Watch.SYNC_MAX_ROWS then failed = true return end
		rows[#rows + 1] = row
	end
	Add("I~" .. tostring(s.revision or 0))
	local keys = {}
	for key in pairs(s.records) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		local e = s.records[key]
		local status = e.status == "watch" and "V" or e.status == "ban" and "B" or "N"
		local statusBy = Character(e.statusBy) or "-"
		local updatedBy = Character(e.updatedBy) or "-"
		local lastBy = Character(e.lastBy) or "-"
		Add(("R~%s~%s~%d~%s~%d"):format(e.name, status, math.floor(tonumber(e.statusAt) or 0), statusBy,
			math.max(0, math.floor(tonumber(e.timeoutUntil) or 0))))
		Add(("C~%s~%d~%d~%d~%d~%d~%s"):format(e.name, math.max(0, math.floor(tonumber(e.warnings) or 0)),
			math.max(0, math.floor(tonumber(e.interventions) or 0)), math.max(0, math.floor(tonumber(e.warningAt) or 0)),
			math.max(0, math.floor(tonumber(e.warningResetAt) or 0)),
			math.max(0, math.floor(tonumber(e.updatedAt) or 0)), updatedBy))
		if (tonumber(e.lastAt) or 0) > 0 and lastBy ~= "-" then
			Add(("L~%s~%d~%s"):format(e.name, math.floor(e.lastAt), lastBy))
			Add(("D~%s~%d~%s"):format(e.name, math.floor(e.lastAt), CleanReason(e.lastReason)))
		end
	end
	for _, e in ipairs(s.audit) do
		-- A recovered entry is hearsay authenticated only as far as its immediate relay. Never
		-- forward the actor name that relay claimed as though a later client had authenticated it;
		-- every recovery hop advances provenance to the officer who actually sent this snapshot.
		local by, name, seq = Character(e.via) or Character(e.by), Character(e.name), math.floor(tonumber(e.seq) or 0)
		if by and name and SequenceFits(seq, tonumber(e.at)) and OPS[e.op] then
			Add(("A~%s~%s~%d~%s~%d~%d"):format(e.op, name, math.floor(tonumber(e.at) or 0), by, seq,
				math.max(0, math.floor(tonumber(e.untilAt) or 0))))
			Add(("X~%s~%d~%s"):format(by, seq, CleanReason(e.reason)))
		end
	end
	local seenKeys = {}
	for who in pairs(s.seen) do seenKeys[#seenKeys + 1] = who end
	table.sort(seenKeys)
	for _, who in ipairs(seenKeys) do
		local e = s.seen[who]
		local name = Character(who)
		if name and type(e) == "table" and SequenceFits(tonumber(e.seq), tonumber(e.at)) then
			Add(("E~%s~%d~%d"):format(name, math.max(0, math.floor(tonumber(e.seq) or 0)),
				math.max(0, math.floor(tonumber(e.at) or 0))))
		end
	end
	return not failed and rows or nil
end
Watch.SnapshotRows = SnapshotRows

local function SnapshotMessage(nonce, session, cursor)
	local total = #session.rows
	if cursor < 0 or cursor >= total then return nil end
	local page = {}
	for i = cursor + 1, total do
		local trial = {}
		for j = 1, #page do trial[j] = page[j] end
		trial[#trial + 1] = session.rows[i]
		local nextCursor = i < total and i or 0
		local msg = ("MW~%d~S~%s~%d~%d~%d~%d~%s~%s~%s^%s"):format(Watch.PROTOCOL, nonce, session.stamp,
			cursor, nextCursor, total, session.guild, session.group, session.faction, table.concat(trial, "^"))
		if #msg > Watch.MESSAGE_MAX then break end
		page = trial
	end
	if #page == 0 then return nil end
	local taken = cursor + #page
	local nextCursor = taken < total and taken or 0
	local msg = ("MW~%d~S~%s~%d~%d~%d~%d~%s~%s~%s^%s"):format(Watch.PROTOCOL, nonce, session.stamp,
		cursor, nextCursor, total, session.guild, session.group, session.faction, table.concat(page, "^"))
	return #msg <= Watch.MESSAGE_MAX and msg or nil, nextCursor
end

local function AnswerSync(sender, nonce, cursor, qkey)
	local progress, session = syncIncoming[qkey], syncOutgoing[qkey]
	if not progress or not session then return false, "session" end
	if session.guild ~= OwnGuild() or session.group ~= ns.group or session.faction ~= ns.faction then
		syncIncoming[qkey], syncOutgoing[qkey] = nil, nil
		return false, "session"
	end
	local msg, nextCursor
	if cursor == progress.lastCursor and progress.lastMsg then
		msg, nextCursor = progress.lastMsg, progress.expected
	elseif cursor == progress.expected then
		msg, nextCursor = SnapshotMessage(nonce, session, cursor)
		if not msg then return false, "size" end
		progress.pages = (progress.pages or 0) + 1
		if progress.pages > Watch.SYNC_MAX_PAGES then syncIncoming[qkey], syncOutgoing[qkey] = nil, nil return false, "pages" end
		progress.lastCursor, progress.lastMsg, progress.expected = cursor, msg, nextCursor
	else
		return false, "order"
	end
	progress.t, session.t = Mono(), Mono()
	local guardKey = "sync-answer#" .. qkey .. "#" .. tostring(cursor)
	local expected = function()
		local p = syncIncoming[qkey]
		return p and p.lastCursor == cursor and p.lastMsg or nil
	end
	return PrivateSend(sender, session.guild, session.group, session.faction, msg, guardKey, expected) and true or false
end

local function HandleSyncQuery(sender, text)
	local nonce, cursor, guild, group, faction = text:match("^MW~1~Q~([0-9]+)~(%d+)~([^~]+)~([^~]+)~([^~]+)$")
	cursor = tonumber(cursor)
	if not nonce or #nonce > 18 or not cursor or cursor < 0 or cursor > Watch.SYNC_MAX_ROWS then return false, "shape" end
	if guild ~= OwnGuild() or group ~= ns.group or faction ~= ns.faction then return false, "identity" end
	CleanupSync()
	local qkey = Key(sender) .. "\1" .. nonce
	local progress = syncIncoming[qkey]
	if cursor == 0 and not progress then
		if Count(syncIncoming) >= Watch.SYNC_MAX_SESSIONS then return false, "rate" end
		if not Rate("ask:" .. Key(sender), Watch.SYNC_INITIAL_PER_SENDER, Watch.SYNC_INITIAL_WINDOW)
			or not Rate("ask:*", 6, 60) then return false, "rate" end
		local rows = SnapshotRows()
		if not rows or #rows < 1 then return false, "store" end
		progress = { expected = 0, t = Mono(), pages = 0 }
		syncIncoming[qkey] = progress
		syncOutgoing[qkey] = { rows = rows, stamp = math.floor(Clock()), guild = guild,
			group = group, faction = faction, t = Mono() }
	elseif not progress then
		return false, "session"
	end
	return AnswerSync(sender, nonce, cursor, qkey)
end

local SendSyncQuery
local function ArmSyncRetry(request, cursor)
	Watch.after(20, "watch sync " .. request.nonce .. " " .. tostring(cursor), function()
		if syncAsked[request.nonce] ~= request or request.cursor ~= cursor then return end
		request.tries = (request.tries or 0) + 1
		if request.tries > 2 then syncAsked[request.nonce] = nil return end
		SendSyncQuery(request)
	end)
end

SendSyncQuery = function(request)
	local cursor = request.cursor
	local msg = ("MW~%d~Q~%s~%d~%s~%s~%s"):format(Watch.PROTOCOL, request.nonce, cursor,
		request.guild, request.group, request.faction)
	local guardKey = "sync-query#" .. request.nonce .. "#" .. tostring(cursor)
	local expected = function()
		local current = syncAsked[request.nonce]
		return current == request and current.cursor == cursor and msg or nil
	end
	local ok = PrivateSend(request.peer, request.guild, request.group, request.faction, msg, guardKey, expected)
	if ok then ArmSyncRetry(request, cursor) end
	return ok
end

local function Int(s, low, high)
	local n = tonumber(s)
	if not n or n ~= math.floor(n) or n < (low or 0) or (high and n > high) then return nil end
	return n
end

local function SnapshotName(s)
	local name = Character(s)
	return name == s and name or nil
end

local function SnapshotMoment(s, zero)
	local n = Int(s, zero and 0 or Watch.SEQ_EPOCH, math.floor(Clock()) + Watch.DATE_AHEAD)
	return n
end

local function SplitRow(row)
	local out = {}
	for field in (row .. "~"):gmatch("(.-)~") do out[#out + 1] = field end
	return out
end

local function DecodeSnapshot(rows)
	local snap = { records = {}, audit = {}, reasons = {}, seen = {}, revision = nil }
	for _, row in ipairs(rows) do
		local f, kind = SplitRow(row), row:sub(1, 1)
		if kind == "I" and #f == 2 and snap.revision == nil then
			snap.revision = Int(f[2], 0)
		elseif kind == "R" and #f == 6 then
			local name, statusAt, timeout = SnapshotName(f[2]), SnapshotMoment(f[4], true), Int(f[6], 0, math.floor(Clock()) + Watch.MAX_TIMEOUT + Watch.DATE_AHEAD)
			local status
			if f[3] == "V" then status = "watch"
			elseif f[3] == "B" then status = "ban"
			elseif f[3] == "N" then status = false
			else return nil end
			local by = f[5] == "-" and false or SnapshotName(f[5])
			if not name or status == nil or not statusAt or not timeout
				or (status == false and ((statusAt == 0 and by ~= false) or (statusAt > 0 and not by)))
				or (status ~= false and (statusAt == 0 or not by)) then return nil end
			local e = snap.records[Key(name)] or { name = name }
			if e.r then return nil end
			e.r, e.status, e.statusAt, e.statusBy, e.timeoutUntil = true, status or nil, statusAt, by or nil, timeout
			snap.records[Key(name)] = e
		elseif kind == "C" and #f == 8 then
			local name = SnapshotName(f[2])
			local warnings, interventions = Int(f[3], 0, Watch.MAX_SEQ), Int(f[4], 0, Watch.MAX_SEQ)
			local warningAt, warningResetAt = SnapshotMoment(f[5], true), SnapshotMoment(f[6], true)
			local updatedAt = SnapshotMoment(f[7], true)
			local updatedBy = f[8] == "-" and false or SnapshotName(f[8])
			if not name or not warnings or not interventions or warnings > interventions or not warningAt or not warningResetAt or not updatedAt
				or warningResetAt > warningAt or warningAt > updatedAt
				or (updatedAt == 0 and updatedBy ~= false) or (updatedAt > 0 and not updatedBy) then return nil end
			local e = snap.records[Key(name)] or { name = name }
			if e.c then return nil end
			e.c, e.warnings, e.interventions, e.warningAt, e.warningResetAt, e.updatedAt, e.updatedBy =
				true, warnings, interventions, warningAt, warningResetAt, updatedAt, updatedBy or nil
			snap.records[Key(name)] = e
		elseif kind == "L" and #f == 4 then
			local name, at, by = SnapshotName(f[2]), SnapshotMoment(f[3], false), SnapshotName(f[4])
			if not name or not at or not by then return nil end
			local e = snap.records[Key(name)] or { name = name }
			if e.l then return nil end
			e.l, e.lastAt, e.lastBy = true, at, by
			snap.records[Key(name)] = e
		elseif kind == "D" and #f == 4 then
			local name, at, reason = SnapshotName(f[2]), SnapshotMoment(f[3], false), f[4]
			if not name or not at or CleanReason(reason) ~= reason then return nil end
			local e = snap.records[Key(name)] or { name = name }
			if e.d then return nil end
			e.d, e.reasonAt, e.lastReason = true, at, reason
			snap.records[Key(name)] = e
		elseif kind == "A" and #f == 7 then
			local op, name, at, by = OPS[f[2]] and f[2], SnapshotName(f[3]), SnapshotMoment(f[4], false), SnapshotName(f[5])
			local seq, untilAt = Int(f[6], 1, Watch.MAX_SEQ), Int(f[7], 0, math.floor(Clock()) + Watch.MAX_TIMEOUT + Watch.DATE_AHEAD)
			if not op or not name or not at or not by or not seq or not untilAt or not SequenceFits(seq, at) then return nil end
			local id = Key(by) .. "#" .. tostring(seq)
			if snap.audit[id] then return nil end
			snap.audit[id] = { op = op, name = name, at = at, by = by, seq = seq, untilAt = untilAt }
		elseif kind == "X" and #f == 4 then
			local by, seq, reason = SnapshotName(f[2]), Int(f[3], 1, Watch.MAX_SEQ), f[4]
			if not by or not seq or CleanReason(reason) ~= reason then return nil end
			local id = Key(by) .. "#" .. tostring(seq)
			if snap.reasons[id] ~= nil then return nil end
			snap.reasons[id] = reason
		elseif kind == "E" and #f == 4 then
			local who, seq, at = SnapshotName(f[2]), Int(f[3], 1, Watch.MAX_SEQ), SnapshotMoment(f[4], false)
			if not who or not seq or not at or not SequenceFits(seq, at) or snap.seen[Key(who)] then return nil end
			snap.seen[Key(who)] = { name = who, seq = seq, at = at }
		else
			return nil
		end
	end
	if snap.revision == nil then return nil end
	for _, e in pairs(snap.records) do
		if not e.r or not e.c or e.l ~= e.d or (e.d and e.reasonAt ~= e.lastAt) then return nil end
	end
	for id, e in pairs(snap.audit) do
		local reason = snap.reasons[id]
		if reason == nil or (e.op ~= "C" and reason == "") then return nil end
		e.reason = reason
	end
	for id in pairs(snap.reasons) do if not snap.audit[id] then return nil end end
	return snap
end

local function MergeSnapshot(snap, relay)
	local s = Store(true)
	if not s then return false end
	local changed, now = false, Clock()
	for key, remote in pairs(snap.records) do
		local localRecord = s.records[key]
		if type(localRecord) ~= "table" then
			localRecord = { name = remote.name, warnings = 0, interventions = 0, statusAt = 0,
				warningAt = 0, warningResetAt = 0, updatedAt = 0, timeoutUntil = 0 }
			s.records[key], changed = localRecord, true
		end
		if TupleNewer(remote.statusAt, relay, localRecord.statusAt, localRecord.statusBy) then
			-- Only `relay` is authenticated by the server-stamped whisper. Claimed actors are
			-- deliberately not installed as authenticated provenance or tie-break authority.
			localRecord.status, localRecord.statusAt, localRecord.statusBy = remote.status, remote.statusAt, relay
			changed = true
		end
		if remote.warningAt > (tonumber(localRecord.warningAt) or 0) then
			localRecord.warnings, localRecord.warningAt = remote.warnings, remote.warningAt
			localRecord.warningResetAt = math.max(tonumber(localRecord.warningResetAt) or 0, remote.warningResetAt)
			changed = true
		elseif remote.warningAt == (tonumber(localRecord.warningAt) or 0) and remote.warnings > (tonumber(localRecord.warnings) or 0) then
			localRecord.warnings, localRecord.warningResetAt, changed = remote.warnings,
				math.max(tonumber(localRecord.warningResetAt) or 0, remote.warningResetAt), true
		elseif remote.warningResetAt > (tonumber(localRecord.warningResetAt) or 0) then
			localRecord.warningResetAt, changed = remote.warningResetAt, true
		end
		if remote.interventions > (tonumber(localRecord.interventions) or 0) then localRecord.interventions, changed = remote.interventions, true end
		if remote.l and TupleNewer(remote.lastAt, relay, localRecord.lastAt, localRecord.lastBy) then
			localRecord.lastAt, localRecord.lastBy, localRecord.lastReason = remote.lastAt, relay, remote.lastReason
			localRecord.lastVia = relay
			changed = true
		end
		if TupleNewer(remote.updatedAt, relay, localRecord.updatedAt, localRecord.updatedBy) then
			localRecord.updatedAt, localRecord.updatedBy = remote.updatedAt, relay
			localRecord.timeoutUntil = remote.timeoutUntil > now and remote.timeoutUntil or 0
			changed = true
		end
	end
	local function AuditId(e)
		if not Character(e.by) or not Int(e.seq, 1, Watch.MAX_SEQ) then return nil end
		if CHAT_OPS[e.op] then return "C#" .. e.op .. "#" .. Key(e.by) .. "#" .. tostring(e.seq) end
		if e.via then
			-- A relay has no authenticated global event id. Keep distinct safe actions apart using
			-- their bounded contents, and make a repeated snapshot from that relay idempotent.
			return table.concat({ "R", Key(e.via), tostring(e.seq), tostring(e.at), tostring(e.op),
				Key(e.name), CleanReason(e.reason) }, "#")
		end
		return "D#" .. Key(e.by) .. "#" .. tostring(e.seq)
	end
	local auditIds = {}
	for _, e in ipairs(s.audit) do local id = AuditId(e); if id then auditIds[id] = true end end
	for _, e in pairs(snap.audit) do
		-- The claimed actor is not retained at all. The server-stamped whisper authenticates the
		-- relay, and `via` makes the recovered nature explicit to UI and later snapshots.
		e.by, e.via = relay, relay
		local id = AuditId(e)
		if id and not auditIds[id] then
			s.audit[#s.audit + 1], auditIds[id], changed = e, true, true
		end
	end
	table.sort(s.audit, function(a, b)
		if a.at ~= b.at then return a.at < b.at end
		if Key(a.by) ~= Key(b.by) then return Key(a.by) < Key(b.by) end
		return (a.seq or 0) < (b.seq or 0)
	end)
	Trim(s.audit, Watch.MAX_AUDIT)
	-- Replay floors are an authority decision. A relay may recover only its own floor; names it
	-- merely claims to have seen cannot suppress a future authenticated action by another officer.
	local relayKey, relaySeen = Key(relay), snap.seen[Key(relay)]
	if relaySeen then
		local old = s.seen[relayKey]
		if not old or relaySeen.seq > (tonumber(old.seq) or 0) then
			s.seen[relayKey], changed = { seq = relaySeen.seq, at = relaySeen.at }, true
		end
	end
	TrimInactive(s, now, 0)
	if changed then
		s.revision = math.max(s.revision or 0, snap.revision or 0) + 1
		ns.Fire("WATCH_CHANGED")
	end
	return true, changed
end

-- Recovery is a transfer of state, not delegated authority. The whisper authenticates `relay`
-- alone, so every target in the frozen snapshot must be one that relay could act on through the
-- ordinary live path right now. Validate the complete decoded set before MergeSnapshot touches
-- any row; claimed status/audit actors are intentionally irrelevant to this capability check.
local function SnapshotAllowed(snap, relay)
	if not Watch.IsAuthorized(relay) then return false, "sender" end
	for _, e in pairs(snap.records) do
		local allowed = TargetAllowed(relay, e.name)
		if not allowed then return false, "authority" end
	end
	for _, e in pairs(snap.audit) do
		local allowed = TargetAllowed(relay, e.name)
		if not allowed then return false, "authority" end
	end
	return true
end

local function TakeSnapshot(sender, text)
	local nonce, stamp, cursor, nextCursor, total, guild, group, faction, body =
		text:match("^MW~1~S~([0-9]+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)%^(.*)$")
	stamp, cursor, nextCursor, total = tonumber(stamp), tonumber(cursor), tonumber(nextCursor), tonumber(total)
	local request = nonce and syncAsked[nonce]
	if not request or not stamp or stamp < request.at or stamp > math.floor(Clock()) + Watch.DATE_AHEAD
		or not cursor or cursor ~= request.cursor or not nextCursor or not total or total < 1 or total > Watch.SYNC_MAX_ROWS
		or guild ~= request.guild or group ~= request.group or faction ~= request.faction
		or OwnGuild() ~= request.guild or ns.group ~= request.group or ns.faction ~= request.faction
		or not Same(sender, request.peer) or body == "" or body:sub(1, 1) == "^" or body:sub(-1) == "^" or body:find("^^", 1, true)
		or (request.stamp and request.stamp ~= stamp) or (request.total and request.total ~= total) then return false, "stale" end
	local page = {}
	for row in body:gmatch("[^%^]+") do page[#page + 1] = row end
	if #page < 1 or cursor + #page > total or (nextCursor > 0 and (nextCursor ~= cursor + #page or nextCursor >= total))
		or (nextCursor == 0 and cursor + #page ~= total) then return false, "order" end
	request.pages = request.pages + 1
	if request.pages > Watch.SYNC_MAX_PAGES then syncAsked[nonce] = nil return false, "pages" end
	request.stamp, request.total = request.stamp or stamp, request.total or total
	for _, row in ipairs(page) do request.rows[#request.rows + 1] = row end
	request.started, request.tries = Mono(), 0
	if nextCursor > 0 then
		request.cursor = nextCursor
		return SendSyncQuery(request) and true or false, "next"
	end
	local snap = DecodeSnapshot(request.rows)
	syncAsked[nonce] = nil
	if not snap then return false, "snapshot" end
	local allowed, why = SnapshotAllowed(snap, sender)
	if not allowed then return false, why end
	local ok, changed = MergeSnapshot(snap, sender)
	if ok then stats.synced = (stats.synced or 0) + 1 end
	return ok, changed and "changed" or "same"
end

function Watch.AskSync(force)
	CleanupSync()
	local now = Mono()
	if not Watch.CanRead() or not FreshRoster() then return false, "access" end
	if not force and now - lastSync < Watch.SYNC_GAP then return false, "rate" end
	local recipients = Recipients()
	if #recipients == 0 then return false, "peer" end
	if not Rate("ask:local", 3, Watch.SYNC_INITIAL_WINDOW) then return false, "rate" end
	syncPeerIndex = syncPeerIndex % #recipients + 1
	syncCounter = syncCounter % 999999 + 1
	local nonce = tostring(math.floor(Clock())) .. tostring(syncCounter)
	while syncAsked[nonce] do syncCounter = syncCounter % 999999 + 1 nonce = tostring(math.floor(Clock())) .. tostring(syncCounter) end
	local request = { nonce = nonce, peer = recipients[syncPeerIndex], guild = OwnGuild(), group = ns.group, faction = ns.faction,
		at = math.floor(Clock()), started = now,
		cursor = 0, pages = 0, rows = {}, tries = 0 }
	syncAsked[nonce] = request
	if not SendSyncQuery(request) then syncAsked[nonce] = nil return false, "busy" end
	lastSync = now
	return true, nonce
end

function Watch.RetrySync(nonce)
	local request = syncAsked[tostring(nonce or "")]
	if not request then return false end
	return SendSyncQuery(request)
end

function Watch.SyncPending(nonce) return syncAsked[tostring(nonce or "")] end

function Watch.Handle(dist, sender, text)
	if type(text) ~= "string" then stats.malformed = stats.malformed + 1 return false, "shape" end
	if #text > Watch.MESSAGE_MAX then stats.oversized = stats.oversized + 1 return false, "size" end
	if dist ~= "WHISPER" or not Watch.CanRead() then stats.refused = stats.refused + 1 return false, "access" end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		stats.refused = stats.refused + 1
		return false, "unlogged"
	end
	sender = Character(sender)
	if not sender or not Watch.IsAuthorized(sender) then stats.refused = stats.refused + 1 return false, "sender" end
	Watch.Prune()
	if text:sub(1, 7) == "MW~1~Q~" then
		local ok, why = HandleSyncQuery(sender, text)
		if not ok then stats.refused = stats.refused + 1 end
		return ok, why
	elseif text:sub(1, 7) == "MW~1~S~" then
		local ok, why = TakeSnapshot(sender, text)
		if not ok then stats.refused = stats.refused + 1 end
		return ok, why
	end
	local a, why = Parse(text)
	if not a then
		if why == "size" then stats.oversized = stats.oversized + 1 else stats.malformed = stats.malformed + 1 end
		return false, why
	end
	-- (1.2.0: one officer's actions, MW_RATE a minute at most.)
	local rk, now = Key(sender), ns.Now()
	local times = mwRates[rk] or {}
	mwRates[rk] = times
	for i = #times, 1, -1 do if now - times[i] >= 60 then table.remove(times, i) end end
	if #times >= Watch.MW_RATE then stats.refused = stats.refused + 1 return false, "rate" end
	times[#times + 1] = now
	a.by = sender
	local allowed
	allowed, why = TargetAllowed(sender, a.name)
	if not allowed then stats.refused = stats.refused + 1 return false, why end
	local s = Store(true)
	local seen = s.seen[Key(sender)]
	if seen and a.seq <= (tonumber(seen.seq) or 0) then stats.replay = stats.replay + 1 return false, "replay" end
	local ok
	ok, why = Apply(a)
	if not ok then stats.refused = stats.refused + 1 return false, why end
	s.seen[Key(sender)] = { seq = a.seq, at = a.at }
	stats.taken = stats.taken + 1
	return true
end

if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("MW", function(...) Watch.Handle(...) end) end

---------------------------------------------------------------------------
-- 1.1.6: Report to Olympus. Any member reports a player from the game's right-click menu (or
-- /oly watch report <name>) to his own guild's Watch: a category, a short note of his own, and
-- the newest few lines that player wrote in the Olympus channel this client already kept (its
-- history: never a whisper, a private room, nor a line this client never saw). They go by logged
-- whisper to the authorized officers of his guild online now, never to the one reported (nor to a
-- name his player linked); with none online the report waits a day on the reporter's client and
-- goes, while it is online, to those online then. Both ends recheck the live roster, as the
-- Watch's own actions do, and the receiver takes each player's newest report on each name only, a
-- few an hour from one player. The lines are the reporter's client's copy: the receiver can't
-- check them. A report is never a sanction: it opens a case or adds to one, and only an officer's
-- own action (warn, watch, ban-list, clear, or close without action) handles it.
--   MR~1~R~<seq>~<at>~<guild>~<group>~<faction>~<A|S|E|O>~<Name-Realm>~<lines>~<note>   the report
--   MR~1~E~<seq>~<i>~<at>~<A>~<line>            its evidence lines, each after it (A: the Olympus channel)
--   MR~1~X~<at>~<guild>~<group>~<faction>~<Name-Realm>      an officer closed that case without action
-- Clients before 1.1.6 know no MR and leave it alone.
---------------------------------------------------------------------------

local reportLines = {} -- [reporter key] = { id, seq, n, t }: the evidence lines its report announced
local reportTold = {}  -- [name key] = Mono(): an officer was told of a report on that name
local lastFlush = -math.huge

local function CategoryLabel(cat) return L[Watch.REPORT_CATEGORIES[cat] or "WATCH_REPORT_CAT_O"] end
Watch.CategoryLabel = CategoryLabel

-- A line as a report carries it: no colour, link or texture codes, no "~", "|", "^" or control byte.
local function CleanLine(s, max)
	s = tostring(s or "")
	s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
	s = s:gsub("[~|%^%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, max or Watch.REPORT_LINE_MAX)
end
Watch.CleanLine = CleanLine

local function IsKingName(name)
	local M = ns.Moderation
	return type(M) == "table" and type(M.IsKing) == "function" and M.IsKing(name) == true
end

local function SelfOff()
	local M = ns.Moderation
	return type(M) == "table" and not M.missing and type(M.SelfOff) == "function" and M.SelfOff() ~= nil
end

local function MemberPreview()
	local V = ns.ViewAs
	return type(V) == "table" and not V.missing and V.Available and V.Available() == true
		and V.Role and V.Role() ~= "my"
end

function Watch.MemberShown()
	local V = ns.ViewAs
	return ns.IsMember() == true and not (MemberPreview() and V.Role() == "outsider")
end

-- Is `name` the player a report is about: that character, or a name his player linked (Alts.lua)?
-- A report on an officer never reaches him: not his notes, his case nor who reported him.
local function Accused(name, target)
	if Same(name, target) then return true end
	local linked = ns.Alts and ns.Alts.Linked and ns.Alts.Linked(target)
	for _, other in ipairs(type(linked) == "table" and linked or {}) do
		if Same(name, Character(other) or other) then return true end
	end
	return false
end

-- The officers online a report (or a close) on `target` goes to: all but the accused.
local function RecipientsFor(target)
	local out = {}
	for _, name in ipairs(Recipients()) do if not Accused(name, target) then out[#out + 1] = name end end
	return out
end
Watch.RecipientsFor = RecipientsFor

-- The reporter's own book, per guild identity: his sequence, the names he reported and when, his
-- reports of the last day, and those still waiting for an officer (outbox).
local function Book(create)
	local id = Identity()
	if not id or type(ns.rdb) ~= "table" then return nil end
	local all = ns.rdb.watchReporter
	if type(all) ~= "table" then
		if not create then return nil end
		all = {}
		ns.rdb.watchReporter = all
	end
	local key = IdentityKey(id)
	local b = all[key]
	if type(b) ~= "table" then
		if not create then return nil end
		b = {}
		all[key] = b
	end
	for _, field in ipairs({ "sent", "times", "outbox" }) do if type(b[field]) ~= "table" then b[field] = {} end end
	b.seq = math.max(0, math.floor(tonumber(b.seq) or 0))
	return b, id
end
Watch.Book = Book

-- The newest lines `target` wrote in the Olympus chats this client kept and may read now
-- (Channels.History: lines already hidden by net-off are out), oldest first.
function Watch.Evidence(target)
	local C, out = ns.Channels, {}
	if not (type(C) == "table" and not C.missing and type(C.History) == "function") then return out end
	target = Character(target)
	if not target then return out end
	local since = ns.Now() - Watch.REPORT_LINE_WINDOW
	for _, tier in ipairs(Watch.REPORT_TIERS) do
		for _, e in ipairs(C.History(tier) or {}) do
			-- (1.1.6: a line a moderator deleted is never evidence: its words are gone.)
			if type(e) == "table" and not e.mine and not e.del and Same(e.sender, target) and (tonumber(e.t) or 0) >= since then
				local text = CleanLine(e.text)
				if text ~= "" then out[#out + 1] = { at = math.floor(tonumber(e.t) or 0), tier = tier, text = text } end
			end
		end
	end
	table.sort(out, function(a, b) return a.at < b.at end)
	while #out > Watch.REPORT_LINES do table.remove(out, 1) end
	return out
end

-- Only messages the client can still read in the public Olympus channel may be selected.
-- The selected line is rechecked before sending; callers cannot attach arbitrary private text.
-- (1.2.1: every such line of the last day, newest first; the member page lists the 20 newest, but
-- a right-click on an older line in the Chat tab, ChatWindow.lua, may report it too.)
function Watch.ReportableMessages()
	local C, out = ns.Channels, {}
	if not Watch.MemberShown() or MemberPreview() or not (C and C.History) then return out end
	for _, e in ipairs(C.History("A") or {}) do
		if type(e) == "table" and not e.mine and not e.del and Character(e.sender) and not Same(e.sender, ns.me)
			and not IsKingName(e.sender) and (tonumber(e.t) or 0) >= ns.Now() - Watch.REPORT_LINE_WINDOW
			and CleanLine(e.text) ~= "" then
			out[#out + 1] = { sender = e.sender, t = e.t, text = e.text, tier = "A" }
		end
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end
function Watch.ReportMessages()
	local out = Watch.ReportableMessages()
	while #out > 20 do table.remove(out) end
	return out
end

-- 1.2.1: the line a right-click in the Chat tab picked (ChatWindow.lua), as Watch.AskReport takes
-- it: another player's line of the public Olympus channel that may still be reported, else nil (a
-- Captains', Lords' or room line, one's own, the King's, a deleted one, one older than a day).
function Watch.LineMessage(entry, chat)
	if chat ~= "A" or type(entry) ~= "table" then return nil end
	for _, m in ipairs(Watch.ReportableMessages()) do
		if Same(m.sender, entry.sender) and m.t == entry.t and m.text == entry.text then return m end
	end
	return nil
end

local function SelectedEvidence(target, message)
	if not message then return Watch.Evidence(target) end
	if type(message) ~= "table" or message.tier ~= "A" or not Same(message.sender, target) then return nil end
	for _, e in ipairs(Watch.ReportableMessages()) do
		if Same(e.sender, target) and e.t == message.t and e.text == message.text then
			return { { at = math.floor(e.t), tier = "A", text = CleanLine(e.text) } }
		end
	end
	return nil
end

-- Why this client can't report `name` now (the end of a WATCH_REPORT_NO_ key, in capitals there), or nil.
function Watch.ReportBlocked(name)
	if not ns.IsMember() or not OwnGuild() then return "guild" end
	local target = Character(name)
	if not target then return "name" end
	if ns.me and Same(target, ns.me) then return "self" end
	if IsKingName(target) then return "king" end
	if SelfOff() then return "netoff" end
	local b = Book(false)
	if b then
		local now = Clock()
		local last = tonumber(b.sent[Key(target)])
		if last and now - last < Watch.REPORT_DEDUPE then return "already" end
		local recent, newest = 0, -math.huge
		for _, at in ipairs(b.times) do
			if now - at < 86400 then recent = recent + 1 end
			newest = math.max(newest, at)
		end
		if recent >= Watch.REPORT_DAY then return "day" end
		if now - newest < Watch.REPORT_GAP then return "rate" end
	end
	return nil
end

-- A report's messages: its head, then each evidence line.
local function ReportWire(r)
	local head = ("MR~1~R~%d~%d~%s~%s~%s~%s~%s~%d~"):format(r.seq, r.at, r.guild, r.group, r.faction, r.cat, r.target, #r.lines)
	if #head > Watch.MESSAGE_MAX then return nil end
	local msgs = { head .. ns.Cut(r.note, Watch.MESSAGE_MAX - #head) }
	for i, line in ipairs(r.lines) do
		local m = ("MR~1~E~%d~%d~%d~%s~"):format(r.seq, i, line.at, line.tier)
		msgs[#msgs + 1] = m .. ns.Cut(line.text, Watch.MESSAGE_MAX - #m)
	end
	return msgs
end
Watch.ReportWire = ReportWire

-- Checked by Comm right before the game sends it: still this guild's member, not net-off, and
-- the officer still authorized (a demotion or a guild move while it waits cancels it).
local function ReportPermit(r, recipient, msg, guardKey)
	return function(owner, key, dist, target, payload)
		if owner ~= Watch or key ~= guardKey or dist ~= "WHISPER" or payload ~= msg or not Same(target, recipient) then return false, "guard" end
		if not ns.IsMember() or OwnGuild() ~= r.guild or ns.group ~= r.group or ns.faction ~= r.faction
			or SelfOff() or not Watch.IsAuthorized(recipient) or Accused(recipient, r.target) then
			stats.revoked = stats.revoked + 1
			return false, "revoked"
		end
		return true
	end
end

local function Unqueue(r)
	local b = Book(false)
	if not b then return end
	for i = #b.outbox, 1, -1 do
		local q = b.outbox[i]
		if type(q) == "table" and q.seq == r.seq then table.remove(b.outbox, i) end
	end
end

-- Is that name's case open on this officer's client? A report newer than the Watch's last action
-- on the name (warn, watch, ban-list or clear: synced and recovered with the list) and than its
-- last close without action.
local function HandledAt(s, key)
	local e, closed = s.records[key], s.closed[key]
	return math.max(type(e) == "table" and tonumber(e.lastAt) or 0, type(closed) == "table" and tonumber(closed.at) or 0)
end
local function CaseOpen(s, key)
	local handled = HandledAt(s, key)
	for _, r in pairs(s.reports) do
		if type(r) == "table" and Key(r.target) == key and r.at > handled then return true end
	end
	return false
end

-- An officer's client keeps a report: each player's newest on each name.
local function KeepReport(r)
	local s = Store(true)
	if not s then return false, "guild" end
	local id = Key(r.reporter) .. "#" .. Key(r.target)
	local old = s.reports[id]
	if type(old) == "table" and (tonumber(old.at) or 0) >= r.at then return false, "older" end
	local key = Key(r.target)
	local wasOpen = CaseOpen(s, key)
	s.reports[id] = r
	TrimReports(s)
	s.revision = s.revision + 1
	-- Told once in a while per name (a flood of reports is one line), and never a sanction.
	local now = Mono()
	if not wasOpen or now - (reportTold[key] or -math.huge) >= Watch.TOLD_GAP then
		reportTold[key] = now
		ns.Print(Gold(L.WATCH_REPORT_IN:format(ns.DisplayName(r.target) or r.target, CategoryLabel(r.cat))))
		if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	end
	ns.Fire("WATCH_CHANGED")
	return true, id
end

---------------------------------------------------------------------------
-- 1.2.1 (the owner: a member's report "deveria chegar na watch... que inclui high council nessa
-- tab"): a report reaches the High Council and the King too, in their Watch (Reports and Cases).
-- Their one reachable client is the King's (the Tabards' lease, TabardsV2.Collector: the exact King
-- client heard in the last 10 minutes), as for the Judgments: the reporter's client whispers the
-- same report to it (op C, its own copy beside the guild's R), and the King's client keeps it in the
-- council's own book (never in a guild's Watch) and passes it on to the councillors whose clients
-- asked it lately; a councillor's client asks every COUNCIL_ASK_EVERY while the King's client is
-- on, for those it received after the last one he got (op Q). With the King's client off the report
-- waits, as one for absent officers does, a day at most on the reporter's client. Each end checks
-- what it can: the reporter is one the King's client knows for his guild without this whisper (the
-- King's own guild by its roster; another, by his own earlier messages heard there: CouncilReporter),
-- each line he names is one the King's client heard itself (HeardLine: never words put in the
-- accused's mouth), a councillor is on the signed list and not sanctioned, the King's client is the
-- lease's, the accused (or a name his player linked) is never sent his own case, every message is
-- a logged whisper, and each end has its own rate limits (each guild its own on the King's client).
-- The King's chat may be on stream: what it prints names no one. The council's reports and cases
-- stay apart from a guild's in every page (Watch.CouncilReports, Watch.CouncilCases), so an officer
-- who sits on the council, and the King, never act on one with their guild's Watch.
--   MR~1~C~<seq>~<at>~<guild>~<group>~<faction>~<A|S|E|O>~<Name-Realm>~<lines>~<note>   to the King's client
--   MR~1~E~...                                       its evidence lines, as after R
--   MR~1~Q~<since>                                   a councillor's client: the council's reports received after <since>
--   MR~1~F~<in>~<a|p<prev>>~<seq>~<at>~<guild>~<A|S|E|O>~<Name-Realm>~<lines>~<reporter>~<note>   the King's
--                                                    client passes one on (an answer to his ask, or a push), then its lines
-- <in>: when the King's client received it, one number a report, each newer than the one before
-- (KeepCouncil: the server's second, or one more than the last). A councillor's cursor moves only by
-- what proves him whole up to there: each answer to his own ask (oldest first), or a push whose
-- <prev> (the King's client's receipt before it) he had already reached; so a report the King's
-- client takes late, or a long backlog cut by a push, still reaches him at his next ask.
---------------------------------------------------------------------------
Watch.COUNCIL_ASK_EVERY = 15 * 60  -- a councillor's client asks this often
Watch.COUNCIL_SPREAD = 5 * 60      -- its first ask once the King's client comes on: within this
Watch.COUNCIL_HEARD = 20 * 60      -- the King's client passes a new report at once to those who asked this recently
Watch.COUNCIL_ASK_GAP = 30         -- and answers one asker this often at most
Watch.COUNCIL_SHOWN = 6            -- reports in one answer (the oldest first; a full one is asked again soon)
Watch.COUNCIL_BACKLOG = 3 * 86400  -- a councillor's first ask goes this far back
Watch.COUNCIL_RATE_GUILD = 10      -- the King's client takes this many council reports from one guild's members...
Watch.COUNCIL_RATE_ALL = 60        -- ...and from all guilds but its own (whose roster vouches for them)...
Watch.COUNCIL_RATE_ALL_WINDOW = 600 -- ...in this long
Watch.COUNCIL_LINE_SLACK = 300     -- a copy's line is one the King's client heard when it heard those words from him within this
                                   -- of the time the reporter's client gave it (two computers' clocks)
Watch.COUNCIL_RELAY_WAIT = 15      -- a new report is passed on once its lines had this long to arrive
Watch.COUNCIL_RELAY_RATE = 200     -- a councillor's client takes this many from the King's client in 10 minutes
Watch.COUNCIL_QUEUE_KEEP = 20      -- the King's client passes reports on only while its queue keeps this much room for its own
Watch.random = math.random         -- (tests)

local councilHeard = {}   -- the King's client: [councillor key] = { name, t }: asked lately (session only)
local councilAnswered = {} -- the King's client: [councillor key] = Mono() of its last answer
local councilAsk = { lease = nil, at = -math.huge, got = 0 } -- a councillor's client: its asks

-- The King's client on now (its exact name), as the lease says, or nil.
local function KingClient()
	local T = ns.TabardsV2
	if type(T) ~= "table" or T.missing or type(T.Collector) ~= "function" then return nil end
	local c = T.Collector()
	if type(c) ~= "table" or type(c.name) ~= "string" or type(ns.IsKingCharacter) ~= "function" or not ns.IsKingCharacter(c.name) then return nil end
	return c.name
end
-- This client is the King's own.
local function KingHere()
	local K = ns.King
	return type(K) == "table" and type(K.IsKing) == "function" and K.IsKing() == true
end
local function PowersBarred(name)
	local WC = ns.WatchChat
	return type(WC) == "table" and not WC.missing and type(WC.PowersBarred) == "function" and WC.PowersBarred(name) ~= nil
end
-- On the signed council list (the King left out), under no sanction.
local function CouncilObserver(name)
	if type(name) ~= "string" then return false end
	local W = ns.Workshop
	local author = type(W) == "table" and type(W.IsAuthorName) == "function" and W.IsAuthorName(name) == true
	local councillor = type(ns.IsHighCouncillor) == "function" and ns.IsHighCouncillor(name) == true
	return (author or councillor)
		and not (type(ns.IsKingCharacter) == "function" and ns.IsKingCharacter(name)) and not PowersBarred(name)
end
-- This client keeps the council's reports: the King's, a councillor's (Watch.CouncilDeskShown,
-- below: a member, not net-off, under no sanction).
local function CouncilReader() return Watch.CouncilDeskShown ~= nil and Watch.CouncilDeskShown() == true end

-- The council's book on this client (the King's and each councillor's own): its reports, their
-- replay floors; never a guild's Watch store, never in a recovery snapshot. The King's client's
-- last receipt (lastIn: see <in> above); a councillor's cursor on each King's client (cursors).
local function CouncilStore(create)
	if type(ns.rdb) ~= "table" or type(ns.group) ~= "string" or type(ns.faction) ~= "string" then return nil end
	local s = ns.rdb.watchCouncil
	if type(s) ~= "table" or s.version ~= 1 or s.group ~= ns.group or s.faction ~= ns.faction then
		if not create then return nil end
		s = { version = 1, group = ns.group, faction = ns.faction }
		ns.rdb.watchCouncil = s
	end
	for _, field in ipairs({ "reports", "reportSeen", "records", "closed", "findings", "cursors" }) do
		if type(s[field]) ~= "table" then s[field] = {} end
	end
	s.revision = math.max(0, math.floor(tonumber(s.revision) or 0))
	s.lastIn = math.max(0, math.floor(tonumber(s.lastIn) or 0))
	return s
end
Watch.CouncilStore = CouncilStore

local function CouncilGuild(guild)
	return type(guild) == "string" and guild ~= "" and #guild <= 72 and not guild:find("[~|%^%c]") and ns.IsFederation(guild) and guild or nil
end

local function PruneCouncil()
	local s = CouncilStore(false)
	if not s then return end
	local now = Clock()
	for id, r in pairs(s.reports) do
		if not ValidReport(id, r) or not CouncilGuild(r.guild) or now - r.at > Watch.REPORT_KEEP then s.reports[id] = nil end
	end
	TrimReports(s)
	for who, e in pairs(s.reportSeen) do
		if type(who) ~= "string" or type(e) ~= "table" or type(e.seq) ~= "number" or type(e.at) ~= "number"
			or now - e.at > Watch.REPORT_KEEP + Watch.DATE_AHEAD then s.reportSeen[who] = nil end
	end
	while Count(s.reportSeen) > Watch.MAX_REPORTS * 2 do
		local oldest, at
		for who, e in pairs(s.reportSeen) do if not at or e.at < at or (e.at == at and who < oldest) then oldest, at = who, e.at end end
		if not oldest then break end
		s.reportSeen[oldest] = nil
	end
	for king, at in pairs(s.cursors) do
		if type(king) ~= "string" or type(at) ~= "number" or at ~= math.floor(at) or at < 0 then s.cursors[king] = nil end
	end
	while Count(s.cursors) > 10 do
		local oldest, at
		for king, v in pairs(s.cursors) do if not at or v < at or (v == at and king < oldest) then oldest, at = king, v end end
		s.cursors[oldest] = nil
	end
end

Watch.PruneCouncil = PruneCouncil

-- A council report kept here: each player's newest on each name. Told once in a while, naming no one
-- (quiet: one passed on long after it was made, as a councillor's first ask brings them).
-- 1.2.1 (the review): one the King's client takes gets its receipt (<in>, newer than every one
-- before it, and <prev>, the one before); one passed on keeps the King's client's own.
local function KeepCouncil(r, quiet)
	local s = CouncilStore(true)
	if not s then return false, "store" end
	local id = Key(r.reporter) .. "#" .. Key(r.target)
	local old = s.reports[id]
	if type(old) == "table" and (tonumber(old.at) or 0) >= r.at then return false, "older" end
	if r.inAt == nil then
		r.prevIn = s.lastIn
		r.inAt = math.min(Watch.MAX_SEQ, math.max(s.lastIn + 1, math.floor(Clock())))
		s.lastIn = r.inAt
	end
	r.council = true
	s.reports[id] = r
	TrimReports(s)
	s.revision = s.revision + 1
	local key, now = "council#" .. Key(r.target), Mono()
	if not quiet and now - (reportTold[key] or -math.huge) >= Watch.TOLD_GAP then
		reportTold[key] = now
		ns.Print(Gold(L.WATCH_REPORT_IN_COUNCIL:format(CategoryLabel(r.cat))))
		if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	end
	ns.Fire("WATCH_CHANGED")
	return true, id
end

-- The King's client passes one council report on to a councillor: its head, then each line it has.
-- kind: "a", an answer to his ask; "p" (or none), a push, with the King's client's receipt before it.
local function RelayWire(r, kind)
	local mark = kind == "a" and "a" or ("p" .. math.max(0, math.floor(tonumber(r.prevIn) or 0)))
	local head = ("MR~1~F~%d~%s~%d~%d~%s~%s~%s~%d~%s~"):format(math.max(0, math.floor(tonumber(r.inAt) or 0)), mark,
		r.seq, r.at, r.guild, r.cat, r.target, tonumber(r.n) or 0, r.reporter)
	if #head > Watch.MESSAGE_MAX then return nil end
	local msgs = { head .. ns.Cut(r.note or "", Watch.MESSAGE_MAX - #head) }
	for i = 1, tonumber(r.n) or 0 do
		local line = r.lines[i]
		if type(line) == "table" then
			local m = ("MR~1~E~%d~%d~%d~%s~"):format(r.seq, i, line.at, line.tier)
			msgs[#msgs + 1] = m .. ns.Cut(line.text, Watch.MESSAGE_MAX - #m)
		end
	end
	return msgs
end
Watch.RelayWire = RelayWire

-- False and why: "accused" (never his own case), "size" (it can't go), "room" (not now).
local function RelayTo(name, r, kind)
	if Accused(name, r.target) or Same(name, ns.me) then return false, "accused" end
	local msgs = RelayWire(r, kind)
	if not msgs then return false, "size" end
	-- (The King's client's own messages first: the lease, the Judgments. A councillor's next ask
	-- brings what did not go.)
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < #msgs + Watch.COUNCIL_QUEUE_KEEP then return false, "room" end
	for i, msg in ipairs(msgs) do
		local guardKey = "council-relay#" .. Key(name) .. "#" .. Key(r.reporter) .. "#" .. Key(r.target) .. "#" .. i
		ns.Comm.Whisper(name, msg, nil, false, true, nil, { owner = Watch, key = guardKey, permit = function(owner, key, dist, to, payload)
			if owner ~= Watch or key ~= guardKey or dist ~= "WHISPER" or payload ~= msg or not Same(to, name) then return false, "guard" end
			if not KingHere() or not CouncilReader() or not CouncilObserver(name) or Accused(name, r.target) then
				stats.revoked = stats.revoked + 1
				return false, "revoked"
			end
			return true
		end })
	end
	return true
end

-- The King's client: a new council report to the councillors who asked lately, once its lines came.
local function RelayFresh(id)
	Watch.after(Watch.COUNCIL_RELAY_WAIT, "watch council relay", function()
		local s = CouncilStore(false)
		local r = s and s.reports[id]
		if type(r) ~= "table" or not KingHere() then return end
		local now = Mono()
		for _, e in pairs(councilHeard) do
			if now - e.t <= Watch.COUNCIL_HEARD and CouncilObserver(e.name) then RelayTo(e.name, r, "p") end
		end
	end)
end

-- The reporter's client: the council's copy of report r, to the King's client (true: on its way, or
-- this is the King's client and keeps it itself).
local function CouncilWire(r)
	local msgs = ReportWire(r)
	if not msgs then return nil end
	msgs[1] = msgs[1]:gsub("^MR~1~R~", "MR~1~C~")
	return msgs
end
Watch.CouncilWire = CouncilWire

local function SendCouncil(r)
	local king = KingClient()
	if not king then return false end
	-- (Queued already, its first message not gone yet: on its way.)
	if r.councilTryAt and Mono() - r.councilTryAt < Watch.REPORT_RETRY then return true end
	if ns.me and Same(king, ns.me) then
		if not KingHere() then return false end
		local copy = { reporter = ns.me, target = r.target, cat = r.cat, note = r.note, at = r.at, seq = r.seq, n = #r.lines, lines = {},
			guild = r.guild, heard = Clock() }
		for i, line in ipairs(r.lines) do copy.lines[i] = { at = line.at, tier = line.tier, text = line.text } end
		local ok, id = KeepCouncil(copy)
		if ok then RelayFresh(id) end
		r.councilDone = true
		return true
	end
	local msgs = CouncilWire(r)
	if not msgs then return false end
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < #msgs then return false end
	r.councilTryAt = Mono()
	for i, msg in ipairs(msgs) do
		local guardKey = "report-council#" .. tostring(r.seq) .. "#" .. i
		local done = i == 1 and function(ok)
			if not ok then return end
			r.councilDone = true
			if r.delivered then Unqueue(r) end
		end or nil
		ns.Comm.Whisper(king, msg, nil, false, true, done, { owner = Watch, key = guardKey, permit = function(owner, key, dist, to, payload)
			if owner ~= Watch or key ~= guardKey or dist ~= "WHISPER" or payload ~= msg or not Same(to, king) then return false, "guard" end
			if not ns.IsMember() or OwnGuild() ~= r.guild or ns.group ~= r.group or ns.faction ~= r.faction or SelfOff()
				or not Same(KingClient(), king) then
				stats.revoked = stats.revoked + 1
				return false, "revoked"
			end
			return true
		end })
	end
	return true
end

-- Sends a report now to every authorized officer of this guild online but the accused (and, on an
-- officer's own client, to its own desk). "held": nobody to send it to yet.
-- 1.2.1: and its council copy to the King's client while it is on (SendCouncil, above). Each part
-- goes once; the report leaves the reporter's outbox when both did (or after a day).
local function Deliver(r, guildPart)
	if not ns.IsMember() or OwnGuild() ~= r.guild or ns.group ~= r.group or ns.faction ~= r.faction then return false, "guild" end
	if SelfOff() then return false, "netoff" end
	local msgs = ReportWire(r)
	if not msgs then return false, "size" end
	-- An officer's own report goes to his own desk too.
	if Watch.CanRead() and not r.ownTaken then
		local copy = { reporter = ns.me, target = r.target, cat = r.cat, note = r.note, at = r.at, seq = r.seq, n = #r.lines, lines = {}, heard = Clock() }
		for i, line in ipairs(r.lines) do copy.lines[i] = { at = line.at, tier = line.tier, text = line.text } end
		r.ownTaken = KeepReport(copy) or nil
	end
	-- (1.2.1: the council's copy, while the King's client is on: SendCouncil.)
	local council = r.councilDone == true or SendCouncil(r)
	if r.delivered or guildPart == false then
		if r.delivered and r.councilDone then Unqueue(r) end
		return council, council and "sent" or "held", 0
	end
	local recipients = RecipientsFor(r.target)
	if #recipients == 0 then
		if r.ownTaken then
			r.delivered = true
			if r.councilDone then Unqueue(r) end
			return true, "local", 0
		end
		if council then return true, "sent", 0 end
		return false, "held"
	end
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < #recipients * #msgs then
		if council then return true, "sent", 0 end
		return false, "busy"
	end
	r.tryAt = Mono()
	for _, recipient in ipairs(recipients) do
		for i, msg in ipairs(msgs) do
			local guardKey = "report#" .. tostring(r.seq) .. "#" .. Key(recipient) .. "#" .. i
			local done = i == 1 and function(ok)
				if not ok then return end
				r.delivered = true
				if r.councilDone then Unqueue(r) end
			end or nil
			ns.Comm.Whisper(recipient, msg, nil, false, true, done, { owner = Watch, key = guardKey, permit = ReportPermit(r, recipient, msg, guardKey) })
		end
	end
	return true, "sent", #recipients
end

local function ReportWhy(why, name)
	local text = rawget(L, "WATCH_REPORT_NO_" .. tostring(why):upper()) or L.WATCH_REPORT_NO_BUSY
	return text:format(ns.DisplayName(name) or tostring(name or "?"))
end
Watch.ReportWhy = ReportWhy

-- Reports `name` (or the target) to this guild's Watch: cat one of REPORT_ORDER, an optional
-- note. True and "sent", "local", "held" (it waits for an officer) or "busy" (the addon's queue is
-- full: it goes at the next try), or false and why.
function Watch.SendReport(name, cat, note, message)
	if MemberPreview() then return false, "access" end
	local target = Character(name, true)
	local why = Watch.ReportBlocked(target or name)
	if why then return false, why end
	if not Watch.REPORT_CATEGORIES[cat] then return false, "category" end
	if ns.ChatLocked and ns.ChatLocked() then return false, "locked" end
	local evidence = SelectedEvidence(target, message)
	if not evidence then return false, "name" end
	local b, id = Book(true)
	if not b then return false, "guild" end
	local now = math.floor(Clock())
	local seq = math.max(1, now - Watch.SEQ_EPOCH, b.seq + 1)
	if seq > Watch.MAX_SEQ then return false, "busy" end
	b.seq = seq
	local r = { guild = id.guild, group = id.group, faction = id.faction, seq = seq, at = now, cat = cat, target = target,
		note = CleanLine(note, Watch.REPORT_NOTE_MAX), lines = evidence }
	b.sent[Key(target)] = now
	b.times[#b.times + 1] = now
	while #b.times > Watch.REPORT_DAY * 2 do table.remove(b.times, 1) end
	b.outbox[#b.outbox + 1] = r
	while #b.outbox > Watch.OUTBOX_MAX do table.remove(b.outbox, 1) end
	local ok, how, count = Deliver(r)
	if ok then return true, how, count end
	if how == "held" or how == "busy" then return true, how end
	Unqueue(r)
	return false, how
end

-- The reports waiting for an officer: sent, oldest first, once one is online (the roster says so)
-- while this client is too, dropped after REPORT_HOLD (the reporter is told).
function Watch.FlushReports(force)
	local now = Mono()
	if not force and now - lastFlush < Watch.REPORT_RETRY then return 0 end
	lastFlush = now
	local b = Book(false)
	if not b or #b.outbox == 0 then return 0 end
	local sent, clock = 0, Clock()
	for i = #b.outbox, 1, -1 do
		local r = b.outbox[i]
		if type(r) ~= "table" or type(r.at) ~= "number" or type(r.seq) ~= "number" or type(r.lines) ~= "table" or clock - r.at > Watch.REPORT_HOLD then
			table.remove(b.outbox, i)
			-- (1.2.1: one that reached the guild's officers or the council goes quietly.)
			if type(r) == "table" and r.target and not r.delivered and not r.councilDone then
				ns.Print(L.WATCH_REPORT_DROPPED:format(ns.DisplayName(r.target) or tostring(r.target)))
			end
		end
	end
	-- The oldest first, in the order they were made (a copy: a delivery takes one out of the outbox).
	local waiting = {}
	for _, r in ipairs(b.outbox) do waiting[#waiting + 1] = r end
	table.sort(waiting, function(x, y) return x.seq < y.seq end)
	for _, r in ipairs(waiting) do
		local guild = not r.delivered and (force or now - (tonumber(r.tryAt) or -math.huge) >= Watch.REPORT_RETRY) and FreshRoster() ~= nil
		-- (1.2.1: its council copy, once the King's client is on: Deliver's SendCouncil.)
		if guild or (not r.councilDone and KingClient() ~= nil) then
			local ok, how = Deliver(r, guild)
			if ok and how == "sent" then sent = sent + 1 end
		end
	end
	return sent
end

-- An officer closes a case without action: kept here and told to the other officers online. It
-- changes nothing else (the list, the warnings, the player).
function Watch.CloseCase(name)
	if not Watch.CanManage() then return false, "access" end
	local target = Character(name)
	if not target then return false, "name" end
	local allowed, why = TargetAllowed(ns.me, target)
	if not allowed then return false, why end
	local s = Store(true)
	if not s then return false, "guild" end
	local at = math.floor(Clock())
	local key = Key(target)
	local old = s.closed[key]
	s.closed[key] = { at = math.max(at, type(old) == "table" and (tonumber(old.at) or 0) + 1 or 0), by = ns.me }
	s.revision = s.revision + 1
	ns.Fire("WATCH_CHANGED")
	local id = Identity()
	local msg = ("MR~1~X~%d~%s~%s~%s~%s"):format(s.closed[key].at, id.guild, id.group, id.faction, target)
	if #msg > Watch.MESSAGE_MAX then return true, "local" end
	for _, recipient in ipairs(RecipientsFor(target)) do
		local guardKey = "close#" .. key .. "#" .. Key(recipient)
		local guard = { guild = id.guild, group = id.group, faction = id.faction }
		ns.Comm.Whisper(recipient, msg, nil, false, true, nil, { owner = Watch, key = guardKey, permit = function(owner, k, dist, to, payload)
			if owner ~= Watch or k ~= guardKey or dist ~= "WHISPER" or payload ~= msg or not Same(to, recipient) then return false, "guard" end
			if not Watch.CanManage() or OwnGuild() ~= guard.guild or ns.group ~= guard.group or ns.faction ~= guard.faction
				or not Watch.IsAuthorized(recipient) or Accused(recipient, target) or not TargetAllowed(ns.me, target) then
				stats.revoked = stats.revoked + 1
				return false, "revoked"
			end
			return true
		end })
	end
	return true
end

-- 1.2.1 (the review of the council copies): the reporter as the King's client knows him, without his
-- whisper making him known (Data.ClaimedGuild is a lookup; the claim is what his own earlier messages
-- said): a member of the King's own guild by its roster, the server's word ("roster"); of another
-- guild, only when his own messages heard here before (his lines in Olympus's chats, a census report,
-- a board post) spoke for that one ("claim"), and never a guildmate of the King's speaking for
-- another. Nil: not known here (his guild's officers still have his report, and may send its case
-- to the King).
local function CouncilReporter(sender, guild)
	local R = ns.Roster
	local rank = type(R) == "table" and type(R.RankOf) == "function" and R.RankOf(sender) or nil
	if guild == OwnGuild() then
		if FreshRoster() then return RosterRank(sender) ~= nil and "roster" or nil end
		return rank ~= nil and "roster" or nil
	end
	if rank ~= nil then return nil end
	local D = ns.Data
	local claimed = type(D) == "table" and type(D.ClaimedGuild) == "function" and D.ClaimedGuild(sender) or nil
	return type(claimed) == "string" and claimed:lower() == guild:lower() and "claim" or nil
end

-- 1.2.1 (the review): a council copy's line is taken on the King's client only as one it heard
-- itself: the accused's own line in the public Olympus channel (as History keeps it: not deleted,
-- not hidden by net-off), the same words, within COUNCIL_LINE_SLACK of the time the reporter's client
-- gave it. Its time here, or nil (never words put in his mouth: such a line is left out).
local function HeardLine(target, text, at)
	local C = ns.Channels
	if type(C) ~= "table" or C.missing or type(C.History) ~= "function" then return nil end
	local best
	for _, e in ipairs(C.History("A") or {}) do
		local t = type(e) == "table" and tonumber(e.t) or nil
		if t and not e.mine and not e.del and Same(e.sender, target) and math.abs(t - at) <= Watch.COUNCIL_LINE_SLACK
			and CleanLine(e.text) == text and (not best or math.abs(t - at) < math.abs(best - at)) then best = t end
	end
	return best and math.floor(best) or nil
end

-- Rate limits checked together: a slot is taken in each only when all have room.
local function Rates(list)
	local now = Mono()
	for _, b in ipairs(list) do
		local n = 0
		for _, t in ipairs(type(syncRates[b[1]]) == "table" and syncRates[b[1]] or {}) do if now - t < b[3] then n = n + 1 end end
		if n >= b[2] then return false end
	end
	for _, b in ipairs(list) do Rate(b[1], b[2], b[3]) end
	return true
end

local function TakeReportHead(sender, text)
	local seq, at, guild, group, faction, cat, target, n, note =
		text:match("^MR~1~R~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)~(%u)~([^~]+)~(%d)~(.*)$")
	seq, at, n = tonumber(seq), tonumber(at), tonumber(n)
	if not seq or seq < 1 or seq > Watch.MAX_SEQ or not at or not n or n > Watch.REPORT_LINES or not Watch.REPORT_CATEGORIES[cat] then return false, "shape" end
	if guild ~= OwnGuild() or group ~= ns.group or faction ~= ns.faction then return false, "identity" end
	-- The reporter: a member of this guild in the live roster, not hidden by net-off.
	local M = ns.Moderation
	if RosterRank(sender) == nil or (M and M.Hides and M.Hides(sender, guild)) then return false, "sender" end
	local name = Character(target)
	if not name or name ~= target or Same(name, sender) or IsKingName(name) then return false, "name" end
	-- Never one about this officer himself (or a name his player linked): it goes to the others.
	if ns.me and Accused(ns.me, name) then return false, "accused" end
	local now = Clock()
	if at > now + Watch.DATE_AHEAD or now - at > Watch.REPORT_HOLD + Watch.DATE_AHEAD then return false, "time" end
	local s = Store(true)
	if not s then return false, "guild" end
	-- Its replay floor: per reporter and name, so a report held on his client and sent after a newer
	-- one on another name (an officer came online in between, or only the accused was) is taken.
	local seenKey = Key(sender) .. "#" .. Key(name)
	local seen = s.reportSeen[seenKey]
	if seen and seq <= (tonumber(seen.seq) or 0) then stats.replay = stats.replay + 1 return false, "replay" end
	if not Rate("report:" .. Key(sender), Watch.REPORT_RATE, Watch.REPORT_RATE_WINDOW)
		or not Rate("report:*", Watch.REPORT_RATE_ALL, Watch.REPORT_RATE_ALL_WINDOW) then return false, "rate" end
	s.reportSeen[seenKey] = { seq = seq, at = at }
	local r = { reporter = sender, target = name, cat = cat, note = CleanLine(note, Watch.REPORT_NOTE_MAX), at = at, seq = seq,
		n = n, lines = {}, heard = now }
	local ok, id = KeepReport(r)
	if not ok then return false, id end
	reportLines[Key(sender)] = n > 0 and { id = id, seq = seq, n = n, t = Mono() } or nil
	return true
end

local function TakeReportLine(sender, text)
	local seq, i, at, tier, line = text:match("^MR~1~E~(%d+)~(%d)~(%d+)~(%u)~(.*)$")
	seq, i, at = tonumber(seq), tonumber(i), tonumber(at)
	-- The public channel's alone, as Evidence sends them: a Captains' or Lords' line would show to
	-- officers who can't read those channels (and no honest client sends one).
	if tier and not TierAllowed(tier) then return false, "tier" end
	local wait = reportLines[Key(sender)]
	if not seq or not wait or wait.seq ~= seq or Mono() - wait.t > Watch.LINES_WAIT or not i or i < 1 or i > wait.n then return false, "stale" end
	-- (1.2.1: a council report's lines, on the King's client or a councillor's, go to the council's book;
	-- one passed on by the King's client may be as old as the reports it keeps.)
	local s = wait.council and CouncilStore(false) or (not wait.council and Store(false)) or nil
	local r = s and s.reports[wait.id]
	if type(r) ~= "table" or r.seq ~= seq or r.lines[i] then return false, "stale" end
	local now = Clock()
	local oldest = Watch.REPORT_LINE_WINDOW + (wait.relay and Watch.REPORT_KEEP or Watch.REPORT_HOLD) + Watch.DATE_AHEAD
	if not at or at > now + Watch.DATE_AHEAD or now - at > oldest then return false, "time" end
	line = CleanLine(line)
	if line == "" then return false, "shape" end
	-- (1.2.1, the review: a council copy's line, on the King's client, only as one it heard itself,
	-- at its own time for it; any other is left out, and the councillors are passed what it kept.)
	if wait.council and not wait.relay then
		local heard = HeardLine(r.target, line, at)
		if not heard then stats.unconfirmed = (stats.unconfirmed or 0) + 1 return false, "unconfirmed" end
		at = heard
	end
	r.lines[i] = { at = at, tier = tier, text = line }
	s.revision = s.revision + 1
	ns.Fire("WATCH_CHANGED")
	return true
end

local function TakeClose(sender, text)
	local at, guild, group, faction, target = text:match("^MR~1~X~(%d+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)$")
	at = tonumber(at)
	if not at then return false, "shape" end
	if guild ~= OwnGuild() or group ~= ns.group or faction ~= ns.faction then return false, "identity" end
	if not Watch.IsAuthorized(sender) then return false, "sender" end
	local name = Character(target)
	if not name or name ~= target then return false, "name" end
	local allowed, why = TargetAllowed(sender, name)
	if not allowed then return false, why end
	local now = Clock()
	if at > now + Watch.DATE_AHEAD or now - at > Watch.REPORT_KEEP then return false, "time" end
	local s = Store(true)
	local key = Key(name)
	local old = s.closed[key]
	if type(old) == "table" and (tonumber(old.at) or 0) >= at then return true, "same" end
	s.closed[key] = { at = at, by = sender }
	s.revision = s.revision + 1
	ns.Fire("WATCH_CHANGED")
	return true
end

---------------------------------------------------------------------------
-- 1.2.1: the council's reports as the King's client and the councillors' take them (see above).
---------------------------------------------------------------------------

-- The King's client: a member's council copy of his report (C), its lines after it (E).
local function TakeCouncilHead(sender, text)
	local seq, at, guild, group, faction, cat, target, n, note =
		text:match("^MR~1~C~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)~(%u)~([^~]+)~(%d)~(.*)$")
	seq, at, n = tonumber(seq), tonumber(at), tonumber(n)
	if not seq or seq < 1 or seq > Watch.MAX_SEQ or not at or not n or n > Watch.REPORT_LINES or not Watch.REPORT_CATEGORIES[cat] then return false, "shape" end
	if group ~= ns.group or faction ~= ns.faction or not CouncilGuild(guild) then return false, "identity" end
	-- The reporter, as a guild's Watch takes him: not hidden by net-off (a lookup: this whisper notes
	-- no guild of his). His guild: one this client knows him in without this whisper (CouncilReporter:
	-- 1.2.1, the review; a claim made here by anyone was taken before).
	local M = ns.Moderation
	if M and M.Hides and M.Hides(sender, guild, true) then return false, "sender" end
	local known = CouncilReporter(sender, guild)
	if not known then stats.unknown = (stats.unknown or 0) + 1 return false, "sender" end
	local name = Character(target)
	if not name or name ~= target or Same(name, sender) or IsKingName(name) then return false, "name" end
	if ns.me and Accused(ns.me, name) then return false, "accused" end
	local now = Clock()
	if at > now + Watch.DATE_AHEAD or now - at > Watch.REPORT_HOLD + Watch.DATE_AHEAD then return false, "time" end
	local s = CouncilStore(true)
	if not s then return false, "store" end
	local seenKey = Key(sender) .. "#" .. Key(name)
	local seen = s.reportSeen[seenKey]
	if seen and seq <= (tonumber(seen.seq) or 0) then stats.replay = stats.replay + 1 return false, "replay" end
	-- (1.2.1, the review: a few an hour from one player, each guild its own share, so no guild's
	-- characters use up another's; and all of them but the King's own guild a share in all.)
	local limits = { { "council:" .. Key(sender), Watch.REPORT_RATE, Watch.REPORT_RATE_WINDOW },
		{ "council:g:" .. Key(guild), Watch.COUNCIL_RATE_GUILD, Watch.COUNCIL_RATE_ALL_WINDOW } }
	if known ~= "roster" then limits[#limits + 1] = { "council:*", Watch.COUNCIL_RATE_ALL, Watch.COUNCIL_RATE_ALL_WINDOW } end
	if not Rates(limits) then return false, "rate" end
	s.reportSeen[seenKey] = { seq = seq, at = at }
	local r = { reporter = sender, target = name, guild = guild, cat = cat, note = CleanLine(note, Watch.REPORT_NOTE_MAX), at = at,
		seq = seq, n = n, lines = {}, heard = now }
	local ok, id = KeepCouncil(r)
	if not ok then return false, id end
	reportLines[Key(sender)] = n > 0 and { id = id, seq = seq, n = n, t = Mono(), council = true } or nil
	RelayFresh(id)
	return true
end

-- A councillor's client: one the King's client passed on (F), its lines after it (E).
local function TakeRelay(sender, text)
	if KingHere() or not CouncilObserver(ns.me) then return false, "access" end
	if not (Same(KingClient(), sender) and ns.IsKingCharacter(sender)) then return false, "sender" end
	local inAt, kind, prev, seq, at, guild, cat, target, n, reporter, note =
		text:match("^MR~1~F~(%d+)~([ap])(%d*)~(%d+)~(%d+)~([^~]+)~(%u)~([^~]+)~(%d)~([^~]+)~(.*)$")
	inAt, prev, seq, at, n = tonumber(inAt), tonumber(prev), tonumber(seq), tonumber(at), tonumber(n)
	if not inAt or inAt > Watch.MAX_SEQ or (kind == "p" and not prev) or not seq or seq < 1 or seq > Watch.MAX_SEQ or not at or not n
		or n > Watch.REPORT_LINES or not Watch.REPORT_CATEGORIES[cat] then return false, "shape" end
	if not Rate("council-relay:" .. Key(sender), Watch.COUNCIL_RELAY_RATE, 600) then return false, "rate" end
	local s = CouncilStore(true)
	if not s then return false, "store" end
	-- (1.2.1, the review: his cursor on this King's client moves by an answer to his ask, the oldest
	-- first, whatever this one is (one he has, or one he refuses), and by a push only from where he
	-- already is; see <in> above. A full answer is asked again soon: CouncilTick.)
	local ck, cursor = Key(sender), tonumber(s.cursors[Key(sender)]) or 0
	if kind == "a" then councilAsk.got = councilAsk.got + 1 end
	if inAt > cursor and (kind == "a" or prev <= cursor) then s.cursors[ck] = inAt end
	if not CouncilGuild(guild) then return false, "identity" end
	local name, by = Character(target), Character(reporter)
	if not name or name ~= target or not by or by ~= reporter or Same(name, by) or IsKingName(name) then return false, "name" end
	if ns.me and Accused(ns.me, name) then return false, "accused" end
	local now = Clock()
	if at > now + Watch.DATE_AHEAD or now - at > Watch.REPORT_KEEP then return false, "time" end
	local seenKey = Key(by) .. "#" .. Key(name)
	local seen = s.reportSeen[seenKey]
	if seen and seq <= (tonumber(seen.seq) or 0) then return false, "replay" end
	s.reportSeen[seenKey] = { seq = seq, at = at }
	local r = { reporter = by, target = name, guild = guild, cat = cat, note = CleanLine(note, Watch.REPORT_NOTE_MAX), at = at,
		seq = seq, n = n, lines = {}, heard = now, inAt = inAt }
	local ok, id = KeepCouncil(r, now - at > Watch.COUNCIL_HEARD)
	if not ok then return false, id end
	reportLines[Key(sender)] = n > 0 and { id = id, seq = seq, n = n, t = Mono(), council = true, relay = true } or nil
	return true
end

-- The King's client: a councillor's ask (Q): the council's reports it received after <since> (their
-- <in>), the oldest first, COUNCIL_SHOWN at most, never one about himself or a name his player linked;
-- it stops at the first that can't go now, so none is skipped (his next ask starts there).
local function TakeCouncilAsk(sender, text)
	local since = tonumber(text:match("^MR~1~Q~(%d+)$"))
	if not since then return false, "shape" end
	if not CouncilObserver(sender) then return false, "sender" end
	local key, now = Key(sender), Mono()
	if not councilHeard[key] and Count(councilHeard) >= 200 then
		for k, e in pairs(councilHeard) do if now - e.t > Watch.COUNCIL_HEARD then councilHeard[k], councilAnswered[k] = nil, nil end end
		if Count(councilHeard) >= 200 then return false, "busy" end
	end
	councilHeard[key] = { name = sender, t = now }
	if now - (councilAnswered[key] or -math.huge) < Watch.COUNCIL_ASK_GAP then return false, "rate" end
	councilAnswered[key] = now
	PruneCouncil()
	local s, list = CouncilStore(false), {}
	for _, r in pairs(s and s.reports or {}) do
		if type(r) == "table" and (tonumber(r.inAt) or 0) > since and not Accused(sender, r.target) then list[#list + 1] = r end
	end
	table.sort(list, function(a, b)
		if a.inAt ~= b.inAt then return a.inAt < b.inAt end
		return Key(a.reporter) .. "#" .. Key(a.target) < Key(b.reporter) .. "#" .. Key(b.target)
	end)
	local shown = 0
	for _, r in ipairs(list) do
		if shown >= Watch.COUNCIL_SHOWN then break end
		local ok, why = RelayTo(sender, r, "a")
		if ok then shown = shown + 1 elseif why == "room" then break end
	end
	return true
end

-- A councillor's client, each minute: its ask, once the King's client comes on (at a moment of its
-- own within COUNCIL_SPREAD, so the councillors' asks do not all reach it at once), then every
-- COUNCIL_ASK_EVERY; sooner after an answer that came full. force: now.
function Watch.CouncilTick(force)
	if KingHere() or not CouncilObserver(ns.me) or not CouncilReader() then return false end
	local king = KingClient()
	if not king then councilAsk.lease = nil return false end
	local now = Mono()
	if not Same(councilAsk.lease, king) then
		councilAsk.lease = king
		councilAsk.at = now - Watch.COUNCIL_ASK_EVERY + Watch.random(0, Watch.COUNCIL_SPREAD)
		councilAsk.got = 0
	end
	local due = now - councilAsk.at >= Watch.COUNCIL_ASK_EVERY
		or (councilAsk.got >= Watch.COUNCIL_SHOWN and now - councilAsk.at >= Watch.COUNCIL_ASK_GAP * 2)
	if not (force or due) then return false end
	councilAsk.at, councilAsk.got = now, 0
	PruneCouncil()
	-- (1.2.1, the review: from his cursor on this King's client, the reports it received since, not
	-- the reporters' dates: one it took late still comes; never further back than COUNCIL_BACKLOG.)
	local s = CouncilStore(false)
	local since = math.max(math.floor(Clock() - Watch.COUNCIL_BACKLOG), s and tonumber(s.cursors[Key(king)]) or 0)
	local msg = "MR~1~Q~" .. math.max(0, since)
	return ns.Comm.Whisper(king, msg, nil, false, true, nil, { owner = Watch, key = "council-ask", permit = function(owner, key, dist, to, payload)
		if owner ~= Watch or key ~= "council-ask" or dist ~= "WHISPER" or payload ~= msg or not Same(to, king) then return false, "guard" end
		if not CouncilObserver(ns.me) or not CouncilReader() or not Same(KingClient(), king) then return false, "revoked" end
		return true
	end }) ~= false
end

function Watch.HandleReport(dist, sender, text)
	if type(text) ~= "string" then stats.malformed = stats.malformed + 1 return false, "shape" end
	if #text > Watch.MESSAGE_MAX then stats.oversized = stats.oversized + 1 return false, "size" end
	-- (1.2.1: a guild's Watch takes R, E and X; the King's client C, E and Q; a councillor's F and E.)
	local desk, council = Watch.CanRead(), CouncilReader()
	if dist ~= "WHISPER" or not (desk or council) then stats.refused = stats.refused + 1 return false, "access" end
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and ns.Comm.DeliveredLogged and not ns.Comm.DeliveredLogged() then
		stats.refused = stats.refused + 1
		return false, "unlogged"
	end
	sender = Character(sender)
	if not sender then stats.refused = stats.refused + 1 return false, "sender" end
	Watch.Prune()
	local op = text:match("^MR~1~(%u)~")
	local ok, why
	local king = council and KingHere()
	if op == "R" and desk then ok, why = TakeReportHead(sender, text)
	elseif op == "E" then ok, why = TakeReportLine(sender, text)
	elseif op == "X" and desk then ok, why = TakeClose(sender, text)
	elseif op == "C" and king then ok, why = TakeCouncilHead(sender, text)
	elseif op == "Q" and king then ok, why = TakeCouncilAsk(sender, text)
	elseif op == "F" and council and not king then ok, why = TakeRelay(sender, text)
	elseif op == "R" or op == "X" or op == "C" or op == "Q" or op == "F" then ok, why = false, "access"
	else ok, why = false, "shape" end
	if ok then stats.reports = (stats.reports or 0) + 1 else stats.refused = stats.refused + 1 end
	return ok, why
end

if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("MR", function(...) Watch.HandleReport(...) end) end

-- Existing block terms are the only language list.  The Watch can present a censored form, but a
-- hit never creates a warning, timeout or list entry; all interventions still require an explicit
-- officer action.
function Watch.FilterText(text)
	text = tostring(text or "")
	local hit = ns.Filter and ns.Filter.Hit and ns.Filter.Hit(text)
	if hit then return L.FILTER_WORDS_HIDDEN_SHORT, hit end
	return text, nil
end

local function Match(name)
	local direct = Watch.Record(name)
	if direct and direct.status then return direct, direct.name, false end
	local linked = ns.Alts and ns.Alts.Linked and ns.Alts.Linked(name) or {}
	local found, matched
	for _, other in ipairs(type(linked) == "table" and linked or {}) do
		local e = Watch.Record(other)
		if e and e.status and (not found or (e.status == "ban" and found.status ~= "ban")) then found, matched = e, e.name end
	end
	return found, matched, found ~= nil
end
Watch.Match = Match

-- Called only by the existing addon recruitment request.  It notifies; it never rejects or
-- invites.  A related character counts solely when Alts.Linked already has a two-sided link.
function Watch.EntryAttempt(name)
	if not Watch.CanRead() then return nil end
	name = Character(name)
	if not name then return nil end
	local e, matched, alt = Match(name)
	if not e then return nil end
	local now, key = Clock(), Key(OwnGuild()) .. "#" .. Key(name)
	if now - (attemptAt[key] or -math.huge) < Watch.ATTEMPT_GAP then return e, matched, alt end
	attemptAt[key] = now
	local s = Store(true)
	s.attempts[#s.attempts + 1] = { name = name, match = matched, alt = alt and true or nil, status = e.status, at = now }
	Trim(s.attempts, Watch.MAX_ATTEMPTS)
	stats.attempts = stats.attempts + 1
	local label = ns.DisplayName(name) or name
	if alt then ns.Print(Red(L.WATCH_ENTRY_ALT:format(label, ns.DisplayName(matched) or matched)))
	else ns.Print(Red(L.WATCH_ENTRY:format(label))) end
	if ns.PlayAlert then ns.PlayAlert("soft", "watch") end
	ns.Fire("WATCH_CHANGED")
	return e, matched, alt
end

local function StatusLabel(e)
	if e.status == "ban" then return Red(L.WATCH_BANNED) end
	if e.status == "watch" then return Gold(L.WATCH_WATCHED) end
	return Grey(L.WATCH_WARNED)
end

local function ShownBy(name)
	local shown = ns.DisplayName(name) or "?"
	if ns.CouncilMasked and ns.CouncilMasked() and not ns.IsKingCharacter(name) then return ns.MaskName(shown) end
	return shown
end
Watch.ShownBy = ShownBy -- (1.2: Judgment.lua's names too)

-- 1.2.0: on the King's stream an accused player's name shows only once a finding upheld the case;
-- until then, and beside the guild's own record (a warning, a ban-list), it is cut short as the
-- council's names are. Nor does the stream show how many reported him (alts could inflate it).
local function OnStream() return ns.CouncilMasked ~= nil and ns.CouncilMasked() == true end
Watch.OnStream = OnStream
local function Accused(name, upheld)
	local shown = ns.DisplayName(name) or name or "?"
	if OnStream() and not upheld then return ns.MaskName(shown) end
	return shown
end
Watch.Accused = Accused
local function Upheld(c) return type(c) == "table" and type(c.finding) == "table" and c.finding.verdict == "up" end

local function ShownReason(e)
	local authenticated = e.via or e.by
	if ns.CouncilMasked and ns.CouncilMasked() and not ns.IsKingCharacter(authenticated) then return L.NETOFF_REASON_HIDDEN end
	local shown = Watch.FilterText(e.reason)
	return shown ~= "" and shown or "-"
end

local function AddWatchLines(lines)
	local records = Watch.Records()
	lines[#lines + 1] = { header = true, text = L.WATCH_LIST_TITLE, right = Grey(tostring(#records)),
		tooltip = function(tt) tt:AddLine(L.WATCH_LIST_TITLE, 1, 0.82, 0); tt:AddLine(L.WATCH_LIST_TIP, 1, 1, 1, true) end }
	if #records == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_LIST_EMPTY) } end
	for _, e in ipairs(records) do
		local timeout = Watch.ActiveTimeout(e.name)
		lines[#lines + 1] = {
			indent = 1, text = StatusLabel(e) .. "  " .. (ns.DisplayName(e.name) or e.name),
			right = timeout and Red(L.WATCH_TIMEOUT_LEFT:format(math.max(1, math.ceil((timeout - Clock()) / 60)))) or Grey(L.WATCH_INTERVENTIONS:format(e.interventions or 0)),
			onClick = e.status and function() ns.ShowDialog("OLYMPUS_WATCH_CLEAR", ns.DisplayName(e.name) or e.name, nil, e.name) end or nil,
			tooltip = function(tt)
				tt:AddLine(ns.DisplayName(e.name) or e.name, 1, 0.82, 0)
				tt:AddLine(L.WATCH_COUNTS:format(e.warnings or 0, e.interventions or 0), 1, 1, 1, true)
				if timeout then tt:AddLine(L.WATCH_TIMEOUT_UNTIL:format(date and date("%Y-%m-%d %H:%M", timeout) or tostring(timeout)), 1, 0.35, 0.35) end
				if e.lastAt and e.lastAt > 0 then
					tt:AddLine(L.WATCH_LAST_ACTION:format(ShownBy(e.lastBy), ns.Ago(e.lastAt)), 0.7, 0.7, 0.7)
					if e.lastVia and not Same(e.lastVia, e.lastBy) then
						tt:AddLine(L.WATCH_RECOVERED_VIA:format(ShownBy(e.lastVia)), 0.7, 0.7, 0.7)
					end
					local reason = (ns.CouncilMasked and ns.CouncilMasked() and not ns.IsKingCharacter(e.lastBy))
						and L.NETOFF_REASON_HIDDEN or Watch.FilterText(e.lastReason)
					tt:AddLine(L.WATCH_REASON:format(reason ~= "" and reason or "-"), 1, 1, 1, true)
				end
				if e.status then tt:AddLine(L.WATCH_CLICK_CLEAR, 0.6, 0.6, 0.6, true) end
			end,
		}
	end
	lines[#lines].gapAfter = true
end

local function AddAttemptLines(lines)
	local attempts = Watch.Attempts()
	if #attempts == 0 then return end
	lines[#lines + 1] = { header = true, text = L.WATCH_ATTEMPTS, right = Grey(tostring(#attempts)) }
	for i = 1, math.min(10, #attempts) do
		local e = attempts[i]
		lines[#lines + 1] = { indent = 1, text = Red(Accused(e.name)), right = Grey(ns.Ago(e.at)),
			tooltip = function(tt)
				tt:AddLine(L.WATCH_ATTEMPT_TIP:format(Accused(e.name)), 1, 0.82, 0, true)
				if e.alt then tt:AddLine(L.WATCH_LINKED_MATCH:format(ns.DisplayName(e.match) or e.match), 1, 1, 1, true) end
			end }
	end
	lines[#lines].gapAfter = true
end

local function AddAuditLines(lines)
	local audit = Watch.Audit()
	lines[#lines + 1] = { header = true, text = L.WATCH_AUDIT_TITLE, right = Grey(tostring(#audit)) }
	if #audit == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_AUDIT_EMPTY) } end
	for i = 1, math.min(12, #audit) do
		local e = audit[i]
		local label = e.op == "W" and L.WATCH_ACTION_WARN or e.op == "V" and L.WATCH_ACTION_WATCH
			or e.op == "B" and L.WATCH_ACTION_BAN or CHAT_OPS[e.op] and L["WATCHCHAT_OP_" .. e.op] or L.WATCH_ACTION_CLEAR
		lines[#lines + 1] = { indent = 1, text = label:format(Accused(e.name)), right = Grey(ns.Ago(e.at)),
			tooltip = function(tt)
				tt:AddLine(label:format(Accused(e.name)), 1, 0.82, 0)
				-- A snapshot authenticates only its relay. Never present its claimed original actor as
				-- though this client had authenticated that character.
				if e.via then tt:AddLine(L.WATCH_RECOVERED_VIA:format(ShownBy(e.via)), 0.7, 0.7, 0.7)
				else tt:AddLine(L.WATCH_BY:format(ShownBy(e.by)), 0.7, 0.7, 0.7) end
				if e.reason ~= "" then tt:AddLine(L.WATCH_REASON:format(ShownReason(e)), 1, 1, 1, true) end
			end }
	end
end

---------------------------------------------------------------------------
-- 1.1.6: the Watch's pages. The desk (as before), Reports (each one as it came), Cases (one per
-- reported name: open while a report is newer than the last action on it) and a case's own page,
-- with its judgment card for the stream. Reporters' names show in tooltips alone, masked on the
-- King's stream as the council's are; notes and lines through the block terms (Watch.FilterText),
-- and hidden there too (ShownWords).
---------------------------------------------------------------------------

Watch.mode = nil    -- nil: the desk; "reports", "cases", "case" (Watch.caseKey: the name's key) or "tabards"
Watch.caseKey = nil
local cardFrame     -- the judgment card (built on first use)

---------------------------------------------------------------------------
-- 1.2: The Watch takes in the Tabards (the old Tabards tab: the untabarded, the inspected guilds
-- and players, gear seen; Views.lua's lines, UI.lua's buttons for them, its "heraldry" view).
-- Whoever had that tab has them here: the King, the officers, the author, and every member while
-- the King's publication is fresh (TabardsV2.SurfaceVisible). The desk, Reports and Cases stay the
-- officers' private data; the King and High Council share the desk's layout with only the data
-- their client is already authorized to read.
---------------------------------------------------------------------------

-- The Tabards show here (a client updated without a restart, with no TabardsV2.lua: as the old
-- tab did then, always).
function Watch.TabardsShown()
	local T = ns.TabardsV2
	return type(T) ~= "table" or T.missing == true or type(T.SurfaceVisible) ~= "function" or T.SurfaceVisible() == true
end

-- Council access is presentation only. It never makes a councillor an officer in this roster,
-- authorizes recovery, or exposes guild-local reports and audit records.
function Watch.CouncilDeskShown()
	if not ns.me or not ns.IsMember() or SelfOff() then return false end
	local WC = ns.WatchChat
	if WC and WC.Barred and WC.Barred("powers") then return false end
	local W = ns.Workshop
	return (type(ns.IsKingCharacter) == "function" and ns.IsKingCharacter(ns.me) == true)
		or (type(ns.IsHighCouncillor) == "function" and ns.IsHighCouncillor(ns.me) == true)
		or (type(W) == "table" and type(W.IsAuthorName) == "function" and W.IsAuthorName(ns.me) == true)
end

-- The desk's pages show: an officer's (Watch.CanRead), the King and High Council's layout;
-- the author's in his own view, with only
-- what his client holds (nothing he was not sent, no action his rank does not allow); a View-as
-- role's that has them (ViewAs.lua).
function Watch.DeskShown()
	local V = ns.ViewAs
	if type(V) == "table" and not V.missing and type(V.Available) == "function" and V.Available() == true then
		return V.Role() == "my" or V.Allows("watch") == true
	end
	return Watch.CanRead() or Watch.CouncilDeskShown()
end

-- 1.2: the Judgments (Judgment.lua): the cases the guilds' officers sent the King, the High
-- Council's votes and his final word, for the King, the councillors and the author.
local function Judgment()
	local J = ns.Judgment
	return type(J) == "table" and not J.missing and J or nil
end
function Watch.JudgmentsShown()
	local J = Judgment()
	return J ~= nil and type(J.Visible) == "function" and J.Visible() == true
end

-- 1.1.6: Chat moderation (WatchChat.lua): the desk's officers and Watchers, and the author, the
-- King and the High Council (their own Olympus moderators, appeals and the Olympus-wide actions).
local function ChatShown()
	local WC = ns.WatchChat
	return type(WC) == "table" and not WC.missing and type(WC.PageShown) == "function" and WC.PageShown() == true
end
Watch.ChatShown = ChatShown

-- The tab (UI.AddTab's visible).
function Watch.TabVisible() return Watch.DeskShown() or Watch.JudgmentsShown() or ChatShown()
	or (ns.JusticeTasks and ns.JusticeTasks.Visible()) or false end

-- The sections this player sees, and the one shown when he picked none (or one he no longer
-- sees): the desk (with its Reports, Cases and a case's page), else the Judgments, else the Tabards.
local function Sections()
	local desk = Watch.DeskShown()
	local list = { desk = desk, reports = desk, cases = desk, case = desk,
		judgments = Watch.JudgmentsShown(), justice = ns.JusticeTasks and ns.JusticeTasks.Visible(), chat = ChatShown(), tabards = Watch.TabardsShown(), member = Watch.MemberShown() }
	list.profile = Watch.CanRead()
	list.first = desk and "desk" or list.judgments and "judgments" or list.justice and "justice" or list.chat and "chat" or list.tabards and "tabards" or list.member and "member" or "desk"
	return list
end

-- The section shown: "desk", "reports", "cases", "case", "judgments" or "tabards".
local function Section()
	local list = Sections()
	local mode = Watch.mode or "desk"
	if list[mode] then return mode end
	return list.first
end

-- The Tabards are the section shown.
local function OnTabards() return Section() == "tabards" end

-- The view whose buttons and columns the window takes (UI.AddTab's view): the Tabards the old
-- tab's; the Judgments none (their own lines act), never the desk's Warn, Watch and Ban-list.
function Watch.ViewKey()
	local section = Section()
	if section == "tabards" then return "heraldry" end
	if section == "chat" then return Watch.DeskShown() and "watch" or "judgments" end
	return (section == "judgments" or section == "member" or section == "justice") and "judgments" or "watch"
end

-- The page shown, for the window's place and its "?" (UI.PageId: "watch/cases").
function Watch.PageId()
	local section = Section()
	if section == "case" then return "case:" .. tostring(Watch.caseKey or "") end
	if section == "profile" then return "profile:" .. tostring(Watch.profileKey or "") end
	return section
end

function Watch.Show(mode, key)
	Watch.mode = (mode == "reports" or mode == "cases" or mode == "case" or mode == "tabards" or mode == "judgments"
		or mode == "chat" or mode == "member" or mode == "justice" or mode == "profile") and mode or nil
	Watch.caseKey = Watch.mode == "case" and key or nil
	Watch.profileKey = Watch.mode == "profile" and key or nil
	ns.Fire("WATCH_CHANGED")
end

-- Opens the host-owned, access-controlled record for one named character.  The
-- caller receives only a success/failure result; every record, audit row and
-- retained chat line remains inside The Watch and is filtered there exactly as
-- it is on the normal Watch pages.
function Watch.OpenMember(name)
	if not Watch.CanRead() then return false, "access" end
	local target = Character(name, true)
	if not target then return false, "name" end
	Watch.Show("profile", target)
	return true
end

local function LinesGot(r)
	local n = 0
	for _ in pairs(type(r) == "table" and type(r.lines) == "table" and r.lines or {}) do n = n + 1 end
	return n
end

local function Stamp(at) return date and date("%Y-%m-%d %H:%M", at) or tostring(at) end

local function ShownReporter(name)
	local shown = ns.DisplayName(name) or "?"
	if ns.CouncilMasked and ns.CouncilMasked() then return ns.MaskName(shown) end
	return shown
end

-- A reporter's note, or a reported line, as it shows: through the block terms, and hidden while
-- the council's names are (the King's stream), as another player's net-off reason is
-- (ShownReason): a line could carry a word the block terms don't know. by: whose words (the
-- King's own note shows).
local function ShownWords(text, by)
	if ns.CouncilMasked and ns.CouncilMasked() and not (by and ns.IsKingCharacter(by)) then return L.NETOFF_REASON_HIDDEN end
	return Watch.FilterText(text)
end

local function TierLabel(tier)
	local C = ns.Channels
	local t = type(C) == "table" and type(C.TIERS) == "table" and C.TIERS[tier]
	return t and L[t.label] or tostring(tier)
end

-- "abuse or slurs (2), spam or scams (1)"
local function CatsText(cats)
	local out = {}
	for _, cat in ipairs(Watch.REPORT_ORDER) do
		if (cats[cat] or 0) > 0 then out[#out + 1] = L.WATCH_CAT_COUNT:format(CategoryLabel(cat), cats[cat]) end
	end
	return #out > 0 and table.concat(out, ", ") or "-"
end
Watch.CatsText = CatsText -- (1.2: Judgment.lua's lines too)

-- Every report this officer's client keeps, the newest first.
-- 1.2.1 (the review): the guild's Watch alone (an officer's: Store); the council's book has its own
-- list (Watch.CouncilReports), never mixed with a guild's, so an officer who sits on the council, and
-- the King, never act on a council report with their guild's Watch (warn, watch, ban-list, close,
-- the King's judgment).
local function Newest(reports)
	local out = {}
	for _, r in pairs(reports or {}) do if type(r) == "table" then out[#out + 1] = r end end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return Key(a.reporter) < Key(b.reporter)
	end)
	return out
end

function Watch.Reports()
	if not Watch.CanRead() then return {} end
	Watch.Prune()
	local s = Store(false)
	return Newest(s and s.reports)
end

-- 1.2.1: the council's reports on the King's and a councillor's client (CouncilStore), each
-- player's newest on each name, the newest first.
function Watch.CouncilReports()
	if not Watch.CouncilDeskShown() then return {} end
	PruneCouncil()
	local s = CouncilStore(false)
	return Newest(s and s.reports)
end

-- The cases: one per reported name, with its reports (each player's newest), how many players,
-- the categories and the evidence lines, open while a report is newer than the Watch's last action
-- on the name and its last close without action. Open ones (most players first, then the newest),
-- and the handled ones (the newest first).
-- 1.2.1: from one store: the guild's Watch, or the council's book (council: each case marked so,
-- its key "council:" and the name's, so no page, card or judgment takes it for the guild's; its
-- book has no record, close or finding: every case of it is open while a report is kept).
local function BuildCases(s, council)
	local open, handled = {}, {}
	if not s then return open, handled end
	local by = {}
	for _, r in pairs(s.reports) do
		local key = Key(r.target)
		local c = by[key]
		if not c then
			c = { key = (council and "council:" or "") .. key, target = r.target, all = {}, council = council or nil }
			by[key] = c
		end
		c.all[#c.all + 1] = r
	end
	for key, c in pairs(by) do
		c.handledAt = HandledAt(s, key)
		c.reports = {}
		for _, r in ipairs(c.all) do if r.at > c.handledAt then c.reports[#c.reports + 1] = r end end
		c.open = #c.reports > 0
		if not c.open then c.reports = c.all end
		table.sort(c.reports, function(a, b)
			if a.at ~= b.at then return a.at < b.at end
			return Key(a.reporter) < Key(b.reporter)
		end)
		c.reporters, c.lines, c.cats = #c.reports, 0, {}
		c.firstAt, c.lastAt = c.reports[1].at, c.reports[#c.reports].at
		for _, r in ipairs(c.reports) do
			c.cats[r.cat] = (c.cats[r.cat] or 0) + 1
			c.lines = c.lines + LinesGot(r)
		end
		local f = s.findings[key]
		c.finding = type(f) == "table" and (not c.open or (tonumber(f.at) or 0) > c.handledAt) and f or nil
		c.closed, c.record = s.closed[key], s.records[key]
		table.insert(c.open and open or handled, c)
	end
	table.sort(open, function(a, b)
		if a.reporters ~= b.reporters then return a.reporters > b.reporters end
		if a.lastAt ~= b.lastAt then return a.lastAt > b.lastAt end
		return a.key < b.key
	end)
	table.sort(handled, function(a, b)
		if a.lastAt ~= b.lastAt then return a.lastAt > b.lastAt end
		return a.key < b.key
	end)
	return open, handled
end

function Watch.Cases()
	if not Watch.CanRead() then return {}, {} end
	Watch.Prune()
	return BuildCases((Store(false)))
end

-- 1.2.1: the council's cases (the King's and a councillor's client), apart from any guild's.
function Watch.CouncilCases()
	if not Watch.CouncilDeskShown() then return {}, {} end
	PruneCouncil()
	return BuildCases(CouncilStore(false), true)
end

local function Find(key, open, handled)
	for _, list in ipairs({ open, handled }) do
		for _, c in ipairs(list) do if c.key == key then return c end end
	end
	return nil
end
-- The guild's case on that name (its key), or nil; the council's: Watch.CouncilCase.
function Watch.Case(key) return Find(key, Watch.Cases()) end
function Watch.CouncilCase(key) return Find(key, Watch.CouncilCases()) end

-- This officer's own finding on a case: "up" (upheld), "down" (not upheld), anything else takes
-- it back. Kept on this client alone and sent to nobody: a judgment beyond this guild's officers,
-- and its rules (quorum, ties, who picks the sanction), are not built yet. It changes nothing by
-- itself: the sanction (warn, watch, ban-list) or the close without action is the next, separate click.
function Watch.SetFinding(name, verdict)
	if not Watch.CanManage() then return false, "access" end
	local target = Character(name)
	if not target then return false, "name" end
	local s = Store(true)
	if not s then return false, "guild" end
	local key = Key(target)
	if verdict == "up" or verdict == "down" then s.findings[key] = { verdict = verdict, at = math.floor(Clock()) }
	else s.findings[key] = nil end
	s.revision = s.revision + 1
	ns.Fire("WATCH_CHANGED")
	if cardFrame and cardFrame:IsShown() then Watch.RefreshCard() end
	return true
end

local function Nav()
	local mode = Section()
	local items = {}
	if Watch.DeskShown() then
		-- (1.2.1: what the Reports and Cases pages list: the guild's and the council's, each its own.)
		local open, councilOpen = Watch.Cases(), Watch.CouncilCases()
		items[#items + 1] = { key = "desk", text = L.WATCH_NAV_DESK }
		items[#items + 1] = { key = "reports", text = L.WATCH_NAV_REPORTS:format(#Watch.Reports() + #Watch.CouncilReports()) }
		items[#items + 1] = { key = "cases", text = L.WATCH_NAV_CASES:format(#open + #councilOpen) }
	end
	-- 1.2: the Judgments and the Tabards, for whoever sees them.
	local J = Judgment()
	if Watch.JudgmentsShown() then items[#items + 1] = { key = "judgments", text = L.WATCH_NAV_JUDGMENTS:format(J.Count()) } end
	if ns.JusticeTasks and ns.JusticeTasks.Visible() then items[#items + 1] = { key = "justice", text = rawget(L, "JUSTICE_TASKS_NAV") or "Justice requests" } end
	-- 1.1.6: Chat moderation (WatchChat.lua).
	if ChatShown() then items[#items + 1] = { key = "chat", text = L.WATCHCHAT_NAV } end
	if Watch.TabardsShown() then items[#items + 1] = { key = "tabards", text = L.TAB_HERALDRY } end
	if Watch.MemberShown() then items[#items + 1] = { key = "member", text = L.WATCH_MEMBER_NAV } end
	local nav = {}
	for _, it in ipairs(items) do
		local key = it.key
		local selected = mode == key or (mode == "case" and key == "cases")
		nav[#nav + 1] = { text = it.text, selected = selected,
			onClick = not selected and function() Watch.Show(key ~= "desk" and key or nil) end or nil }
	end
	return { nav = nav, pageNav = true, id = "watch-navigation", gapAfter = true }
end

local function ReportTip(tt, r)
	tt:AddLine(L.WATCH_REPORT_ON:format(ns.DisplayName(r.target) or r.target), 1, 0.82, 0)
	tt:AddLine(L.WATCH_REPORT_CATEGORY:format(CategoryLabel(r.cat)), 1, 1, 1, true)
	tt:AddLine(L.WATCH_REPORT_NOTE:format(r.note ~= "" and ShownWords(r.note, r.reporter) or "-"), 1, 1, 1, true)
	tt:AddLine(L.WATCH_REPORT_BY:format(ShownReporter(r.reporter), Stamp(r.at)), 0.7, 0.7, 0.7)
	-- (1.2.1: a council report's guild, as the reporter's own client said it.)
	if type(r.guild) == "string" and not OnStream() then tt:AddLine(L.WATCH_REPORT_GUILD:format(r.guild), 0.7, 0.7, 0.7, true) end
	-- (1.2.1, the review: a council report keeps only the lines the King's client heard itself.)
	tt:AddLine((r.council and L.WATCH_REPORT_LINES_COUNCIL or L.WATCH_REPORT_LINES):format(LinesGot(r), tonumber(r.n) or 0), 0.7, 0.7, 0.7, true)
end

-- 1.2.1 (the review): the guild's reports (an officer's) and the council's (the King's and a
-- councillor's), each in its own section; a report opens its own case.
local function ReportSection(lines, title, tip, reports, council)
	lines[#lines + 1] = { header = true, text = title, right = Grey(tostring(#reports)),
		tooltip = function(tt) tt:AddLine(title, 1, 0.82, 0); tt:AddLine(tip, 1, 1, 1, true) end }
	if #reports == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_REPORTS_EMPTY) } end
	for _, r in ipairs(reports) do
		lines[#lines + 1] = {
			indent = 1, text = Gold(CategoryLabel(r.cat)) .. "  " .. Accused(r.target),
			right = Grey(ns.Ago(r.at)),
			tooltip = function(tt) ReportTip(tt, r); tt:AddLine(L.WATCH_CLICK_CASE, 0.6, 0.6, 0.6, true) end,
			onClick = function() Watch.Show("case", (council and "council:" or "") .. Key(r.target)) end,
		}
	end
	lines[#lines].gapAfter = true
end

local function AddReportLines(lines)
	local council = Watch.CouncilDeskShown()
	if Watch.CanRead() or not council then ReportSection(lines, L.WATCH_REPORTS_TITLE, L.WATCH_REPORTS_TIP, Watch.Reports()) end
	if council then ReportSection(lines, L.WATCH_REPORTS_TITLE_COUNCIL, L.WATCH_COUNCIL_TIP, Watch.CouncilReports(), true) end
end

local function CaseRow(c)
	return {
		indent = 1,
		text = (c.open and Red(L.WATCH_CASE_OPEN) or Grey(L.WATCH_CASE_HANDLED)) .. "  " .. Accused(c.target, Upheld(c))
			.. "  " .. Grey(CatsText(c.cats)),
		right = not OnStream() and Grey(L.WATCH_CASE_REPORTS:format(c.reporters)) or nil,
		tooltip = function(tt)
			tt:AddLine(Accused(c.target, Upheld(c)), 1, 0.82, 0)
			tt:AddLine(L.WATCH_CASE_ALLEGATION:format(CatsText(c.cats)), 1, 1, 1, true)
			if not OnStream() then tt:AddLine(L.WATCH_CASE_REPORTED:format(c.reporters, ns.Ago(c.firstAt), ns.Ago(c.lastAt)), 1, 1, 1, true) end
			tt:AddLine(L.WATCH_CLICK_CASE, 0.6, 0.6, 0.6, true)
		end,
		onClick = function() Watch.Show("case", c.key) end,
	}
end

local function CaseSection(lines, title, tip, open, handled)
	lines[#lines + 1] = { header = true, text = title, right = Grey(tostring(#open)),
		tooltip = function(tt) tt:AddLine(title, 1, 0.82, 0); tt:AddLine(tip, 1, 1, 1, true) end }
	if #open == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_CASES_EMPTY) } end
	for _, c in ipairs(open) do lines[#lines + 1] = CaseRow(c) end
	lines[#lines].gapAfter = true
	if #handled == 0 then return end
	lines[#lines + 1] = { header = true, text = L.WATCH_CASES_HANDLED, right = Grey(tostring(#handled)) }
	for i = 1, math.min(20, #handled) do lines[#lines + 1] = CaseRow(handled[i]) end
	lines[#lines].gapAfter = true
end

-- (1.2.1, the review: the guild's cases and the council's, each in its own section.)
local function AddCaseLines(lines)
	local council = Watch.CouncilDeskShown()
	if Watch.CanRead() or not council then CaseSection(lines, L.WATCH_CASES_TITLE, L.WATCH_CASES_TIP, Watch.Cases()) end
	if council then CaseSection(lines, L.WATCH_CASES_TITLE_COUNCIL, L.WATCH_COUNCIL_TIP, Watch.CouncilCases()) end
end

local function RecordText(e)
	local status = type(e) == "table" and (e.status == "ban" and L.WATCH_BANNED or e.status == "watch" and L.WATCH_WATCHED) or "-"
	return L.WATCH_CASE_RECORD:format(type(e) == "table" and tonumber(e.warnings) or 0, type(e) == "table" and tonumber(e.interventions) or 0, status)
end

-- The case as plain text, for the copy box: no reporter's name (the count only), and on the
-- King's stream no note or line either (ShownWords).
-- (1.2.1) The accused's name, the notes and the reported lines are other players' words: each
-- through Codec.Discord, as written, never as Discord's markup.
function Watch.CaseText(c)
	if type(c) ~= "table" then return "" end
	local D = ns.Codec.Discord
	-- (Ours, the words hidden on the King's stream or by the block terms, as they are.)
	local function Words(text, by)
		local shown = ShownWords(text, by)
		if shown == L.NETOFF_REASON_HIDDEN or shown == L.FILTER_WORDS_HIDDEN_SHORT then return shown end
		return D(shown)
	end
	local out = { L.WATCH_CASE_TITLE:format(D(Accused(c.target, Upheld(c)))),
		L.WATCH_CASE_ALLEGATION:format(CatsText(c.cats)),
		OnStream() and "" or L.WATCH_CASE_REPORTED:format(c.reporters, Stamp(c.firstAt), Stamp(c.lastAt)),
		RecordText(c.record), "" }
	for _, r in ipairs(c.reports) do
		out[#out + 1] = ("%s · %s · %s"):format(Stamp(r.at), CategoryLabel(r.cat), r.note ~= "" and Words(r.note, r.reporter) or "-")
		for i = 1, tonumber(r.n) or 0 do
			local line = r.lines[i]
			if line then out[#out + 1] = ("    [%s] %s: %s"):format(TierLabel(line.tier), Stamp(line.at), Words(line.text)) end
		end
	end
	out[#out + 1] = ""
	out[#out + 1] = L.WATCH_CASE_GAPS
	return table.concat(out, "\n")
end

local function CaseLines(c)
	local lines = { { indent = 0, text = Gold("< " .. L.WATCH_NAV_CASES_BACK), onClick = function() Watch.Show("cases") end, gapAfter = true } }
	if not c then
		lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_CASE_GONE) }
		return lines
	end
	local name = Accused(c.target, Upheld(c))
	lines[#lines + 1] = { header = true, text = L.WATCH_CASE_TITLE:format(name), right = c.open and Red(L.WATCH_CASE_OPEN) or Grey(L.WATCH_CASE_HANDLED) }
	lines[#lines + 1] = { indent = 1, text = L.WATCH_CASE_ALLEGATION:format(CatsText(c.cats)) }
	if not OnStream() then
		lines[#lines + 1] = { indent = 1, text = L.WATCH_CASE_REPORTED:format(c.reporters, ns.Ago(c.firstAt), ns.Ago(c.lastAt)),
			tooltip = function(tt)
				tt:AddLine(L.WATCH_CASE_REPORTERS_TIP, 1, 0.82, 0, true)
				for _, r in ipairs(c.reports) do tt:AddLine(ShownReporter(r.reporter) .. "  " .. Grey(Stamp(r.at)), 1, 1, 1) end
			end }
	end
	-- (1.2.1, the review: a council case has no guild's record, close, finding or judgment.)
	local council = c.council == true
	if not council then lines[#lines + 1] = { indent = 1, text = RecordText(c.record) } end
	if not c.open and not council then
		local closed = c.closed
		if type(closed) == "table" and (tonumber(closed.at) or 0) >= c.handledAt then
			lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_CASE_CLOSED_BY:format(ShownBy(closed.by), ns.Ago(closed.at))) }
		elseif type(c.record) == "table" and c.record.lastBy then
			lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_LAST_ACTION:format(ShownBy(c.record.lastBy), ns.Ago(c.record.lastAt))) }
		end
	end
	local verdict = c.finding and c.finding.verdict
	if not council then
		lines[#lines + 1] = { indent = 1,
			text = verdict == "up" and Green(L.WATCH_CASE_FINDING_UP) or verdict == "down" and Red(L.WATCH_CASE_FINDING_DOWN) or Grey(L.WATCH_CASE_FINDING_NONE),
			tooltip = function(tt) tt:AddLine(L.WATCH_CASE_FINDING_TIP, 1, 1, 1, true) end }
	end
	-- 1.2: sent to the King (Judgment.lua): how it stands.
	local J = Judgment()
	for _, line in ipairs(not council and J and J.CaseLines and J.CaseLines(c) or {}) do lines[#lines + 1] = line end
	lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_CASE_GAPS), gapAfter = true }
	lines[#lines + 1] = { header = true, text = L.WATCH_CASE_EVIDENCE }
	for _, r in ipairs(c.reports) do
		lines[#lines + 1] = { indent = 1,
			text = Gold(CategoryLabel(r.cat)) .. "  " .. (r.note ~= "" and ShownWords(r.note, r.reporter) or Grey(L.WATCH_REPORT_NO_NOTE)),
			right = Grey(ns.Ago(r.at)), tooltip = function(tt) ReportTip(tt, r) end }
		for i = 1, tonumber(r.n) or 0 do
			local line = r.lines[i]
			if line then
				lines[#lines + 1] = { indent = 2, text = Grey("[" .. TierLabel(line.tier) .. "] ") .. ShownWords(line.text), right = Grey(Stamp(line.at)),
					tooltip = function(tt)
						tt:AddLine(L.WATCH_CASE_LINE_RAW, 1, 0.82, 0, true)
						-- The words as written, for the officer's own judgment; never on the King's stream.
						if ns.CouncilMasked and ns.CouncilMasked() then tt:AddLine(L.NETOFF_REASON_HIDDEN, 1, 1, 1, true)
						else tt:AddLine(line.text, 1, 1, 1, true) end
					end }
			else
				lines[#lines + 1] = { indent = 2, text = Grey(L.WATCH_CASE_LINE_MISSING) }
			end
		end
	end
	lines[#lines].gapAfter = true
	if council then
		-- 1.2.1: the King and the High Council act on a council report in Olympus's chats (the
		-- reported lines, his recent lines, a timeout: WatchChat.lua, each checked there), never
		-- with a guild's own Watch: an officer among them (the King too) included (the review).
		local WC = ns.WatchChat
		local chat = Watch.CouncilDeskShown() and WC and not WC.missing and WC.CaseLines and WC.CaseLines(c) or {}
		if #chat > 0 then
			lines[#lines + 1] = { header = true, text = L.WATCH_CASE_ACTIONS }
			for _, line in ipairs(chat) do lines[#lines + 1] = line end
		end
		return lines
	end
	if not Watch.CanManage() then return lines end
	local target = c.target
	lines[#lines + 1] = { header = true, text = L.WATCH_CASE_ACTIONS,
		tooltip = function(tt) tt:AddLine(L.WATCH_CASE_ACTIONS, 1, 0.82, 0); tt:AddLine(L.WATCH_CASE_ACTIONS_TIP, 1, 1, 1, true) end }
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_CASE_CARD), onClick = function() Watch.ShowCard(c.key) end,
		tooltip = function(tt) tt:AddLine(L.WATCH_CASE_CARD, 1, 0.82, 0); tt:AddLine(L.WATCH_CASE_CARD_TIP, 1, 1, 1, true) end }
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_CASE_UPHOLD), onClick = function() Watch.SetFinding(target, "up") end }
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_CASE_DISMISS), onClick = function() Watch.SetFinding(target, "down") end }
	-- 1.2: or the King's judgment, the High Council voting first (Judgment.lua).
	for _, line in ipairs(J and J.ActionLines and J.ActionLines(c) or {}) do lines[#lines + 1] = line end
	-- 1.1.6: the King upheld it, the Council having voted: his guild's Justice correspondent
	-- (with none named, its guild master; the author always) applies it, as the ladder's next step.
	-- The King's word reaches this client as the case's own escalation (the officer who sent it:
	-- WatchChat.TellCase keeps it) or as that officer's word to the player over guild, which every
	-- Watcher's client keeps: the Justice correspondent and the guild master find it too
	-- (WatchChat.KingUpheld), until a warning on him applies it.
	local WC = ns.WatchChat
	local upheld = WC and not WC.missing and WC.KingUpheld and WC.KingUpheld(target) ~= nil
	if upheld and WC.MayApplyJudgment and WC.MayApplyJudgment() then
		local step = Watch.TimeoutFor(((c.record and c.record.warnings) or 0) + 1)
		lines[#lines + 1] = { indent = 1, text = Gold(L.WATCHCHAT_APPLY_JUDGMENT:format(step > 0 and WC.Span(step) or L.WATCH_WARNED)),
			onClick = function() Watch.Ask("warn", target) end,
			tooltip = function(tt) tt:AddLine(L.WATCHCHAT_APPLY_JUDGMENT_TIP, 1, 1, 1, true) end }
	end
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_WARN_BTN), onClick = function() Watch.Ask("warn", target) end }
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_WATCH_BTN), onClick = function() Watch.Ask("watch", target) end }
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_BAN_BTN), onClick = function() Watch.Ask("ban", target) end }
	-- 1.1.6: Olympus's chats: the reported lines, his recent lines, a timeout or its lift (WatchChat.lua).
	for _, line in ipairs(WC and WC.CaseLines and WC.CaseLines(c) or {}) do lines[#lines + 1] = line end
	if c.open then
		lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_CASE_CLOSE),
			onClick = function() ns.ShowDialog("OLYMPUS_WATCH_CASE_CLOSE", name, nil, target) end,
			tooltip = function(tt) tt:AddLine(L.WATCH_CASE_CLOSE, 1, 0.82, 0); tt:AddLine(L.WATCH_CASE_CLOSE_TIP, 1, 1, 1, true) end }
	end
	lines[#lines + 1] = { indent = 1, text = Gold(L.WATCH_CASE_COPY), onClick = function()
		if ns.UI and ns.UI.ShowCopy then ns.UI.ShowCopy(L.WATCH_CASE_TITLE:format(name), Watch.CaseText(Watch.Case(c.key) or c), nil, { key = "watch-case" }) end
	end }
	return lines
end

-- The judgment card: a parchment on the left of the screen for the stream, with no reporter's
-- name, note or chat line (a line could carry a word the block terms don't know), nor The Watch's
-- record (its warnings and its watch and ban list are the guild's own): the name, what it is
-- about, how many players reported it, how many lines came with them, and this officer's finding,
-- its two buttons the finding itself (Watch.SetFinding). Olympus's own window with no edit box and
-- none of the game's popups, so it is the same with the gamepad UI.
local function CardBody(c)
	local parts = { L.WATCH_CARD_ACCUSED:format(CatsText(c.cats)) }
	if not OnStream() then parts[#parts + 1] = L.WATCH_CARD_REPORTED:format(c.reporters) end
	parts[#parts + 1] = L.WATCH_CARD_EVIDENCE:format(c.lines)
	return table.concat(parts, "\n\n")
end
Watch.CardBody = CardBody

local function MakeCard()
	local f = ns.Window("OlympusWatchCard", UIParent, { inset = false, close = false, escape = false })
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetSize(300, 340)
	f:SetPoint("LEFT", UIParent, "LEFT", 24, 40)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	-- (1.1.5: every window in the Olympus window's bronze metal, ns.Window; the parchment inside it.)
	local bg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetPoint("TOPLEFT", f.inner[1], f.inner[2])
	bg:SetPoint("BOTTOMRIGHT", f.inner[3], f.inner[4])
	local ui = ns.UI
	local parchments = ui and ui.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG", "Interface\\Stationery\\StationeryTest1" }
	local file = ui and ui.FirstTexture and ui.FirstTexture(parchments) or parchments[1]
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		bg:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		bg:SetTexture(file)
		if file:find("QuestBG", 1, true) then bg:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	local title = _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge"
	local ink = _G.QuestFont and "QuestFont" or "GameFontHighlight"
	f.title = f:CreateFontString(nil, "ARTWORK", ink)
	f.title:SetPoint("TOP", 0, -30)
	f.name = f:CreateFontString(nil, "ARTWORK", title)
	f.name:SetPoint("TOP", f.title, "BOTTOM", 0, -8)
	f.body = f:CreateFontString(nil, "ARTWORK", ink)
	f.body:SetPoint("TOPLEFT", 28, -84)
	f.body:SetPoint("RIGHT", -28, 0)
	f.body:SetJustifyH("LEFT")
	f.body:SetJustifyV("TOP")
	f.verdict = f:CreateFontString(nil, "ARTWORK", title)
	f.verdict:SetPoint("BOTTOM", 0, 82)
	f.foot = f:CreateFontString(nil, "ARTWORK", ink)
	f.foot:SetPoint("BOTTOMLEFT", 28, 52)
	f.foot:SetPoint("RIGHT", -28, 0)
	f.foot:SetJustifyH("CENTER")
	f.up = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.up:SetSize(118, 24)
	f.up:SetPoint("BOTTOMLEFT", 24, 22)
	f.down = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	f.down:SetSize(118, 24)
	f.down:SetPoint("BOTTOMRIGHT", -24, 22)
	f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	f.close:SetPoint("TOPRIGHT", -4, -4)
	f.close:SetScript("OnClick", function() f:Hide() end)
	ns.EscapeCloses("OlympusWatchCard")
	if f.HookScript then f:HookScript("OnShow", function(self) ns.EscapeCloses(self:GetName()) end) end
	return f
end

local UP = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t "
local DOWN = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16|t "

function Watch.RefreshCard()
	local f = cardFrame
	if not (f and f.key) then return nil end
	local c = Watch.CanRead() and Watch.Case(f.key) or nil
	if not c then f:Hide() return nil end
	f.title:SetText(L.WATCH_CARD_TITLE)
	f.name:SetText(Accused(c.target, Upheld(c)))
	f.body:SetText(CardBody(c))
	local verdict = c.finding and c.finding.verdict
	f.verdict:SetText(verdict == "up" and ("|cff1f6f1f" .. L.WATCH_CARD_UPHELD .. "|r")
		or verdict == "down" and ("|cff8f1f1f" .. L.WATCH_CARD_NOT_UPHELD .. "|r") or L.WATCH_CARD_AWAITING)
	f.foot:SetText(L.WATCH_CARD_FOOT)
	local manage = Watch.CanManage()
	local target = c.target
	f.up:SetText(UP .. L.WATCH_CARD_UP)
	f.down:SetText(DOWN .. L.WATCH_CARD_DOWN)
	f.up:SetScript("OnClick", function() ns.SafeCall("watch finding", Watch.SetFinding, target, "up") end)
	f.down:SetScript("OnClick", function() ns.SafeCall("watch finding", Watch.SetFinding, target, "down") end)
	if f.up.SetEnabled then f.up:SetEnabled(manage) end
	if f.down.SetEnabled then f.down:SetEnabled(manage) end
	return f
end

function Watch.ShowCard(key)
	if not Watch.CanRead() or not Watch.Case(key) then return nil end
	cardFrame = cardFrame or MakeCard()
	cardFrame.key = key
	cardFrame:Show()
	return Watch.RefreshCard()
end
function Watch.Card() return cardFrame end

-- The right-click menu's line (PlayerMenu.lua): Report to Olympus, for any member, on any player
-- but himself and the King; greyed, with why, when it can't go now (in a dungeon or a raid too).
function Watch.MenuLines(target, menu)
	if type(target) ~= "table" or type(target.name) ~= "string" or not OwnGuild() or IsKingName(target.name) then return end
	local why = Watch.ReportBlocked(target.name)
	local locked = target.locked == true
	local tip = locked and L.PLAYERMENU_LOCKED or (why and ReportWhy(why, target.name)) or L.WATCH_REPORT_TIP
	menu.Button(L.WATCH_REPORT, function() Watch.AskReport(target.name) end, L.WATCH_REPORT, tip, not locked and not why)
end
if ns.PlayerMenu and ns.PlayerMenu.Add then
	ns.PlayerMenu.Add("report", function(target, menu) Watch.MenuLines(target, menu) end, 30)
end

-- What the reporter sees before he sends: the category, and the lines that go with it.
function Watch.ReportPreview(cat, lines)
	local out = { L.WATCH_REPORT_PREVIEW:format(CategoryLabel(cat), #lines) }
	for _, line in ipairs(lines) do out[#out + 1] = '"' .. ns.Cut(Watch.FilterText(line.text), 90) .. '"' end
	return table.concat(out, "\n")
end

-- The report's dialogs: what it is about (three answers: the writ's way, only a click counts; the
-- third, More, asks again between the other two), then the preview with a short note and Send.
function Watch.AskReport(name, message)
	if MemberPreview() then return false end
	local target = Character(name, true)
	if not SelectedEvidence(target, message) then return false end
	local why = Watch.ReportBlocked(target or name)
	if why then ns.Print(ReportWhy(why, target or name)) return false end
	ns.ShowDialog("OLYMPUS_WATCH_REPORT_WHAT", ns.DisplayName(target) or target, nil, { name = target, message = message })
	return true
end

local function ReportNote(data, cat)
	if MemberPreview() or type(data) ~= "table" or not data.name then return end
	local lines = SelectedEvidence(data.name, data.message)
	if not lines then return end
	ns.ShowDialog("OLYMPUS_WATCH_REPORT_NOTE", ns.DisplayName(data.name) or data.name, Watch.ReportPreview(cat, lines), { name = data.name, cat = cat, message = data.message })
end

local function ReportMore(data)
	if type(data) ~= "table" or not data.name then return end
	if MemberPreview() then return end
	ns.ShowDialog("OLYMPUS_WATCH_REPORT_MORE", ns.DisplayName(data.name) or data.name, nil, { name = data.name, message = data.message })
end

local function ReportSend(data, text)
	if type(data) ~= "table" or not data.name then return end
	local label = ns.DisplayName(data.name) or data.name
	local ok, how = Watch.SendReport(data.name, data.cat, text, data.message)
	if not ok then return ns.Print(L.WATCH_REPORT_FAILED:format(ReportWhy(how, data.name))) end
	ns.Print(how == "held" and L.WATCH_REPORT_HELD:format(label) or how == "busy" and L.WATCH_REPORT_QUEUED:format(label)
		or L.WATCH_REPORT_SENT:format(label))
end

local function AskPerson()
	if not Watch.MemberShown() or MemberPreview() then return false end
	ns.ShowDialog("OLYMPUS_WATCH_REPORT_PERSON")
	return true
end

StaticPopupDialogs["OLYMPUS_WATCH_REPORT_PERSON"] = {
	text = L.WATCH_MEMBER_REPORT_PERSON, button1 = L.WATCH_REPORT, button2 = CANCEL or "Cancel",
	hasEditBox = true, editBoxWidth = 320, maxLetters = 72,
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); eb:SetFocus() end end,
	OnAccept = function(self) local eb = self.editBox or self.EditBox if eb then Watch.AskReport(eb:GetText()) end end,
	EditBoxOnEnterPressed = function(self) Watch.AskReport(self:GetText()); self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WATCH_REPORT_WHAT"] = {
	text = L.WATCH_REPORT_WHAT_PROMPT,
	button1 = L.WATCH_REPORT_CAT_A,
	button2 = L.WATCH_REPORT_CAT_S,
	button3 = L.WATCH_REPORT_CAT_MORE,
	OnAccept = function(self, data) ns.SafeCall("watch report", ReportNote, data or (self and self.data), "A") end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then ns.SafeCall("watch report", ReportNote, data or (self and self.data), "S") end
	end,
	OnAlt = function(self, data) ns.SafeCall("watch report", ReportMore, data or (self and self.data)) end,
	noCancelOnEscape = true,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- More: not in English, or something else (and Cancel).
StaticPopupDialogs["OLYMPUS_WATCH_REPORT_MORE"] = {
	text = L.WATCH_REPORT_MORE_PROMPT,
	button1 = L.WATCH_REPORT_CAT_E,
	button2 = L.WATCH_REPORT_CAT_O,
	button3 = CANCEL or "Cancel",
	OnAccept = function(self, data) ns.SafeCall("watch report", ReportNote, data or (self and self.data), "E") end,
	OnCancel = function(self, data, reason)
		if reason == "clicked" then ns.SafeCall("watch report", ReportNote, data or (self and self.data), "O") end
	end,
	OnAlt = function() end,
	noCancelOnEscape = true,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WATCH_REPORT_NOTE"] = {
	text = L.WATCH_REPORT_NOTE_PROMPT,
	button1 = L.WATCH_REPORT_SEND,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = Watch.REPORT_NOTE_MAX,
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); eb:SetFocus() end end,
	OnAccept = function(self, data) local eb = self.editBox or self.EditBox ns.SafeCall("watch report", ReportSend, data or self.data, eb and eb:GetText()) end,
	EditBoxOnEnterPressed = function(self, data)
		local parent = self:GetParent()
		ns.SafeCall("watch report", ReportSend, data or (parent and parent.data), self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WATCH_CASE_CLOSE"] = {
	text = L.WATCH_CASE_CLOSE_CONFIRM,
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function(self, data)
		local ok, why = Watch.CloseCase(data or (self and self.data))
		if not ok then ns.Print(L.WATCH_ACTION_FAILED:format(tostring(why or "?"))) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function MemberLines()
	local lines = { Nav(), { header = true, text = L.WATCH_MEMBER_TITLE } }
	if MemberPreview() then
		lines[#lines + 1] = { text = Grey(L.WATCH_MEMBER_PREVIEW), wrap = true }
		return lines
	end
	local WC = ns.WatchChat
	local sanction = WC and not WC.missing and WC.Sanction and WC.Sanction()
	local restriction = sanction and (WC.BarredText and WC.BarredText(sanction) or L.WATCH_MEMBER_RESTRICTED)
	lines[#lines + 1] = { text = restriction or L.WATCH_MEMBER_NO_RESTRICTION, wrap = true, gapAfter = true }
	if sanction then
		local e = sanction.entry or {}
		if e.reason and e.reason ~= "" then lines[#lines + 1] = { text = L.WATCH_REASON:format(Watch.FilterText(e.reason)), wrap = true } end
		if e.untilAt and e.untilAt > 0 then lines[#lines + 1] = { text = L.WATCH_MEMBER_UNTIL:format(Stamp(e.untilAt)) } end
		lines[#lines + 1] = { id = "watch-personal-review", text = Gold(L.WATCH_MEMBER_REVIEW), wrap = true,
			onClick = function()
				if MemberPreview() or not Watch.MemberShown() then return end
				if ns.UI and ns.UI.ShowCopy then
					ns.UI.ShowCopy(L.WATCH_MEMBER_REVIEW, L.WATCH_MEMBER_REVIEW_COPY:format(ns.DisplayName(ns.me) or ns.me, restriction))
				end
			end }
	end
	local record = WC and not WC.missing and WC.RecordLines and WC.RecordLines() or {}
	for _, row in ipairs(record) do
		local copy = {}
		for key, value in pairs(row) do copy[key] = value end
		copy.tooltip, copy.gapAfter, copy.indent = row.tip, row.gap, row.indent and 1 or nil
		if row.onClick then copy.onClick = function() if not MemberPreview() then row.onClick() end end end
		lines[#lines + 1] = copy
	end
	if #record == 0 then lines[#lines + 1] = { text = Grey(L.WATCH_MEMBER_NO_RECORD), wrap = true, gapAfter = true } end
	lines[#lines + 1] = { id = "watch-report-person", header = true, text = Gold(L.WATCH_MEMBER_REPORT_PERSON), onClick = AskPerson }
	lines[#lines + 1] = { text = Grey(L.WATCH_MEMBER_REPORT_DETAIL), wrap = true, gapAfter = true }
	lines[#lines + 1] = { header = true, text = L.WATCH_MEMBER_MESSAGES }
	local messages = Watch.ReportMessages()
	for _, message in ipairs(messages) do
		lines[#lines + 1] = { text = (ns.DisplayName(message.sender) or message.sender) .. ": " .. Watch.FilterText(ns.Cut(message.text, 140)),
			wrap = true, right = Grey(ns.Ago(message.t)), onClick = function() Watch.AskReport(message.sender, message) end }
	end
	if #messages == 0 then lines[#lines + 1] = { text = Grey(L.WATCH_MEMBER_MESSAGES_EMPTY), wrap = true } end
	return lines
end

-- One named member's host-owned context. Integrations can open this page, but they never
-- receive its records or retained words: the same Watch authorization and display filters
-- used by the native pages remain the only path to the data.
local function ProfileLines()
	local target = Character(Watch.profileKey, true)
	local shown = target and (ns.DisplayName(target) or target) or "?"
	local lines = { Nav(), { header = true, text = L.WATCH_PROFILE_TITLE:format(shown) } }
	if not target or not Watch.CanRead() then
		lines[#lines + 1] = { id = "watch-profile-no-access", text = Grey(L.WATCH_NO_ACCESS), wrap = true }
		return lines
	end

	local record = Watch.Record(target)
	if record then
		lines[#lines + 1] = { id = "watch-profile-status",
			text = L.WATCH_PROFILE_STATUS:format(StatusLabel(record), tonumber(record.warnings) or 0,
				tonumber(record.interventions) or 0), wrap = true }
		if (tonumber(record.lastAt) or 0) > 0 then
			lines[#lines + 1] = { text = L.WATCH_LAST_ACTION:format(ShownBy(record.lastBy), ns.Ago(record.lastAt)) }
			local reason = (ns.CouncilMasked and ns.CouncilMasked() and not ns.IsKingCharacter(record.lastBy))
				and L.NETOFF_REASON_HIDDEN or Watch.FilterText(record.lastReason)
			lines[#lines + 1] = { text = L.WATCH_REASON:format(reason ~= "" and reason or "-"), wrap = true }
		end
	else
		lines[#lines + 1] = { id = "watch-profile-no-record", text = Grey(L.WATCH_PROFILE_NO_RECORD), wrap = true }
	end

	local WC = ns.WatchChat
	local sanction = WC and not WC.missing and WC.Sanction and WC.Sanction(target)
	if sanction then
		local restriction = WC.BarredText and WC.BarredText(sanction) or L.WATCH_MEMBER_RESTRICTED
		lines[#lines + 1] = { id = "watch-profile-restriction", text = Red(L.WATCH_PROFILE_ACTIVE:format(restriction)),
			wrap = true }
	end
	lines[#lines].gapAfter = true

	local audit = {}
	for _, entry in ipairs(Watch.Audit()) do
		if Same(entry.name, target) then audit[#audit + 1] = entry end
		if #audit >= 10 then break end
	end
	lines[#lines + 1] = { id = "watch-profile-audit", header = true, text = L.WATCH_PROFILE_AUDIT,
		right = Grey(tostring(#audit)) }
	if #audit == 0 then
		lines[#lines + 1] = { text = Grey(L.WATCH_PROFILE_AUDIT_EMPTY), wrap = true }
	else
		for _, entry in ipairs(audit) do
			local label = entry.op == "W" and L.WATCH_ACTION_WARN or entry.op == "V" and L.WATCH_ACTION_WATCH
				or entry.op == "B" and L.WATCH_ACTION_BAN or CHAT_OPS[entry.op] and L["WATCHCHAT_OP_" .. entry.op]
				or L.WATCH_ACTION_CLEAR
			lines[#lines + 1] = { indent = 1, text = label:format(shown), right = Grey(ns.Ago(entry.at)),
				tooltip = function(tt)
					tt:AddLine(label:format(shown), 1, 0.82, 0)
					if entry.via then tt:AddLine(L.WATCH_RECOVERED_VIA:format(ShownBy(entry.via)), 0.7, 0.7, 0.7)
					else tt:AddLine(L.WATCH_BY:format(ShownBy(entry.by)), 0.7, 0.7, 0.7) end
					if entry.reason ~= "" then tt:AddLine(L.WATCH_REASON:format(ShownReason(entry)), 1, 1, 1, true) end
				end }
		end
	end
	lines[#lines].gapAfter = true

	local evidence = Watch.Evidence(target)
	lines[#lines + 1] = { id = "watch-profile-messages", header = true, text = L.WATCH_PROFILE_MESSAGES,
		right = Grey(tostring(#evidence)) }
	if #evidence == 0 then
		lines[#lines + 1] = { text = Grey(L.WATCH_PROFILE_MESSAGES_EMPTY), wrap = true }
	else
		for i = #evidence, math.max(1, #evidence - 9), -1 do
			local entry = evidence[i]
			lines[#lines + 1] = { indent = 1, text = Watch.FilterText(ns.Cut(entry.text, 140)), wrap = true,
				right = Grey(ns.Ago(entry.at)) }
		end
	end
	return lines
end

function Watch.Build()
	if Section() == "profile" then return ProfileLines(), L.TAB_WATCH, L.WATCH_PROFILE_DETAIL end
	if Section() == "member" then return MemberLines(), L.TAB_WATCH, L.WATCH_MEMBER_DETAIL end
	if Section() == "justice" and ns.JusticeTasks and ns.JusticeTasks.Visible() then
		local lines = { Nav() }
		for _, row in ipairs(ns.JusticeTasks.Lines()) do lines[#lines + 1] = row end
		return lines, L.TAB_WATCH, rawget(L, "JUSTICE_TASKS_TITLE") or "Justice requests - private activity"
	end
	-- 1.2: the Tabards (Views.lua's own lines, search box and detail) under the same navigation.
	if OnTabards() then
		local lines, title, text = ns.Views.Build("heraldry")
		table.insert(lines, 1, Nav())
		return lines, title, text
	end
	-- 1.1.6: Chat moderation (WatchChat.lua's lines) under the same navigation.
	if Section() == "chat" then
		local lines = { Nav() }
		for _, line in ipairs(ns.WatchChat.PageLines()) do lines[#lines + 1] = line end
		return lines, L.TAB_WATCH, L.WATCHCHAT_PAGE_DETAIL
	end
	-- 1.2: the Judgments (Judgment.lua's lines) under the same navigation.
	if Section() == "judgments" then
		local lines = { Nav() }
		for _, line in ipairs(Judgment().Lines()) do lines[#lines + 1] = line end
		return lines, L.TAB_WATCH, L.JUDGMENT_DETAIL
	end
	if not Watch.DeskShown() then return {}, L.TAB_WATCH, L.WATCH_NO_ACCESS end
	Watch.Prune()
	local guild = OwnGuild() or "?"
	-- 1.1.6: Reports, Cases and a case's page, under the same navigation as the desk.
	if Watch.mode == "reports" or Watch.mode == "cases" or Watch.mode == "case" then
		local lines = { Nav() }
		if Watch.mode == "reports" then AddReportLines(lines)
		elseif Watch.mode == "cases" then AddCaseLines(lines)
		else for _, line in ipairs(CaseLines(Watch.Case(Watch.caseKey) or Watch.CouncilCase(Watch.caseKey))) do lines[#lines + 1] = line end end
		-- (1.2.1: one who sees the council's alone, the council's words.)
		if not Watch.CanRead() and Watch.CouncilDeskShown() then return lines, L.TAB_WATCH, L.WATCH_COUNCIL_DETAIL end
		return lines, L.TAB_WATCH, (Watch.mode == "reports" and L.WATCH_REPORTS_DETAIL or L.WATCH_CASES_DETAIL):format(guild)
	end
	local lines = {
		Nav(),
		{ header = true, text = "|TInterface\\Icons\\INV_Misc_Eye_01:0|t " .. L.WATCH_TITLE },
		{ text = Grey(L.WATCH_SCOPE:format(guild)), gapAfter = true },
		{ header = true, text = L.WATCH_FILTER_TITLE,
			right = (ns.Filter and ns.Filter.SharedOn and ns.Filter.SharedOn()) and Green(L.WATCH_FILTER_ON) or Grey(L.WATCH_FILTER_OFF),
			onClick = function()
				if ns.Filter and ns.Filter.SetSharedOn and ns.Filter.SharedOn then ns.Filter.SetSharedOn(not ns.Filter.SharedOn()) end
			end,
			tooltip = function(tt) tt:AddLine(L.WATCH_FILTER_TITLE, 1, 0.82, 0); tt:AddLine(L.WATCH_FILTER_TIP, 1, 1, 1, true) end },
		{ indent = 1, text = Grey(L.WATCH_FILTER_COMMANDS), gapAfter = true },
		{ header = true, text = L.WATCH_JUDGMENT },
	}
	-- The King pointer has an independent switch.  This row never changes the crown,
	-- location consent, layer sharing or any other map feature.
	for _, line in ipairs(ns.KingArrow and ns.KingArrow.ControlLines and ns.KingArrow.ControlLines() or {}) do
		lines[#lines + 1] = line
	end
	local court = ns.Court and ns.Court.HomeLines and ns.Court.HomeLines() or {}
	if #court == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WATCH_COURT_EMPTY), gapAfter = true }
	else
		for _, line in ipairs(court) do
			local watchLine = {}
			for key, value in pairs(line) do if key ~= "font" then watchLine[key] = value end end
			lines[#lines + 1] = watchLine
		end
	end
	for _, line in ipairs(ns.Moderation and ns.Moderation.Lines and ns.Moderation.Lines() or {}) do lines[#lines + 1] = line end
	AddAttemptLines(lines)
	AddWatchLines(lines)
	AddAuditLines(lines)
	return lines, L.TAB_WATCH, L.WATCH_DETAIL:format(guild)
end

local function AskReason(data, text)
	local kind = type(data) == "table" and data.kind
	local name = type(data) == "table" and data.name
	name = Character(name or text, true)
	if not name then return ns.Print(L.WATCH_BAD_NAME) end
	if kind == "clear" then return Watch.Clear(name) end
	ns.ShowDialog("OLYMPUS_WATCH_REASON", ns.DisplayName(name) or name, nil, { kind = kind, name = name })
end

local function Give(data, text)
	if type(data) ~= "table" then return end
	local reason = CleanReason(text)
	local ok, why
	if data.kind == "warn" then ok, why = Watch.IssueWarning(data.name, reason)
	elseif data.kind == "watch" then ok, why = Watch.Mark(data.name, reason)
	elseif data.kind == "ban" then
		if reason == "" then return ns.Print(L.WATCH_REASON_REQUIRED) end
		ns.ShowDialog("OLYMPUS_WATCH_BAN_CONFIRM", ns.DisplayName(data.name) or data.name, reason,
			{ name = data.name, reason = reason })
		return true
	end
	if not ok then ns.Print(L.WATCH_ACTION_FAILED:format(tostring(why or "?"))) end
end

function Watch.Ask(kind, name)
	if not Watch.CanManage() then return ns.Print(L.WATCH_NO_ACCESS) end
	if kind ~= "warn" and kind ~= "watch" and kind ~= "ban" then return false end
	local full = Character(name, true)
	if full then return ns.ShowDialog("OLYMPUS_WATCH_REASON", ns.DisplayName(full) or full, nil, { kind = kind, name = full }) end
	ns.ShowDialog("OLYMPUS_WATCH_WHO", L["WATCH_" .. kind:upper() .. "_BTN"], nil, { kind = kind })
	return true
end

StaticPopupDialogs["OLYMPUS_WATCH_WHO"] = {
	text = L.WATCH_WHO_PROMPT,
	button1 = L.WRIT_NEXT,
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 240,
	maxLetters = 80,
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		if eb then
			-- (Nothing while the game hides who the target is, in a battleground: Moderation.TargetName.)
			local M = ns.Moderation
			local target = M and M.TargetName and M.TargetName()
			eb:SetText(target and (ns.DisplayName(target) or target) or "")
			eb:SetFocus()
		end
	end,
	OnAccept = function(self, data)
		local eb = self.editBox or self.EditBox
		ns.SafeCall("watch who", AskReason, data or self.data, eb and eb:GetText())
	end,
	EditBoxOnEnterPressed = function(self, data)
		local parent = self:GetParent()
		ns.SafeCall("watch who", AskReason, data or (parent and parent.data), self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WATCH_REASON"] = {
	text = L.WATCH_REASON_PROMPT,
	button1 = OKAY or "OK",
	button2 = CANCEL or "Cancel",
	hasEditBox = true,
	editBoxWidth = 320,
	maxLetters = Watch.REASON_MAX,
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); eb:SetFocus() end end,
	OnAccept = function(self, data) local eb = self.editBox or self.EditBox ns.SafeCall("watch reason", Give, data or self.data, eb and eb:GetText()) end,
	EditBoxOnEnterPressed = function(self, data)
		local parent = self:GetParent()
		ns.SafeCall("watch reason", Give, data or (parent and parent.data), self:GetText())
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WATCH_CLEAR"] = {
	text = L.WATCH_CLEAR_CONFIRM,
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function(self, data) ns.SafeCall("watch clear", Watch.Clear, data or (self and self.data)) end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- A ban-list mark is deliberately never an automatic consequence of filtered text or a join
-- attempt.  Even after entering a reason, the officer must confirm it here; Ban revalidates the
-- live roster again when the confirmation is accepted, and Comm revalidates it once more at the
-- actual game send.
StaticPopupDialogs["OLYMPUS_WATCH_BAN_CONFIRM"] = {
	text = L.WATCH_BAN_CONFIRM,
	button1 = YES or "Yes", button2 = NO or "No",
	OnAccept = function(self, data)
		data = data or (self and self.data)
		if type(data) ~= "table" then return end
		local ok, why = Watch.Ban(data.name, data.reason)
		if not ok then ns.Print(L.WATCH_ACTION_FAILED:format(tostring(why or "?"))) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

function Watch.Slash(rest)
	rest = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local verb, arg = rest:match("^(%S*)%s*(.-)$")
	verb = (verb or ""):lower()
	if verb == "report" then
		-- 1.1.6: any member, the name or the target.
		return Watch.AskReport(arg)
	elseif verb == "tabards" or verb == "tabard" then
		-- 1.2 (also /oly tabard): The Watch's Tabards. Not shown to this player yet (no fresh
		-- publication of the King's): the window opens on what he sees, as the old tab did.
		Watch.Show("tabards")
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("watch") end
		return true
	elseif verb == "judgments" or verb == "judgment" then
		-- 1.2: the King's and the High Council's (Judgment.lua).
		if not Watch.JudgmentsShown() then return ns.Print(L.WATCH_NO_ACCESS) end
		Watch.Show("judgments")
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("watch") end
		return true
	elseif verb == "" or verb == "open" or verb == "list" or verb == "reports" or verb == "cases" then
		if not Watch.DeskShown() then
			-- (A councillor sees his Judgments; a member who sees only the Tabards, those.)
			if Watch.JudgmentsShown() then verb = "judgments"
			elseif Watch.TabardsShown() then verb = "tabards"
			elseif Watch.MemberShown() then verb = "member"
			else return ns.Print(L.WATCH_NO_ACCESS) end
		end
		if verb == "reports" or verb == "cases" or verb == "tabards" or verb == "judgments" or verb == "member" then Watch.Show(verb) end
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("watch") end
		return true
	elseif verb == "filter" then
		if not Watch.CanRead() then return ns.Print(L.WATCH_NO_ACCESS) end
		return ns.Filter and ns.Filter.Status and ns.Filter.Status()
	elseif verb == "chat" then
		-- 1.1.6: Chat moderation (WatchChat.lua).
		if not ChatShown() then return ns.Print(L.WATCH_NO_ACCESS) end
		Watch.Show("chat")
		if ns.UI and ns.UI.SelectTab then ns.UI.SelectTab("watch") end
		return true
	elseif verb == "timeout" or verb == "purge" or verb == "watchers" or verb == "justice" or verb == "mods" then
		-- 1.1.6: a timeout, his recent lines, the guild master's Watchers, the Olympus moderators.
		local WC = ns.WatchChat
		if not (WC and WC.Slash) or WC.missing then return ns.Print(L.RESTART_NEEDED) end
		return WC.Slash(verb, arg)
	end
	local name, reason = arg:match("^([^:]*):%s*(.*)$")
	if not name then name, reason = arg, "" end
	if verb == "warn" then return Watch.IssueWarning(name, reason)
	elseif verb == "add" or verb == "mark" then return Watch.Mark(name, reason)
	elseif verb == "ban" then
		if not Watch.CanManage() then return ns.Print(L.WATCH_NO_ACCESS) end
		name = Character(name, true)
		reason = CleanReason(reason)
		if not name then return ns.Print(L.WATCH_BAD_NAME) end
		if reason == "" then return ns.Print(L.WATCH_REASON_REQUIRED) end
		ns.ShowDialog("OLYMPUS_WATCH_BAN_CONFIRM", ns.DisplayName(name) or name, reason, { name = name, reason = reason })
		return true
	elseif verb == "clear" or verb == "remove" then return Watch.Clear(name) end
	ns.Print(L.WATCH_USAGE)
	return false, "usage"
end

function Watch.Stats() return stats end

function Watch.ResetForTests()
	wipe(attemptAt)
	wipe(pendingTargets)
	wipe(reportLines); wipe(reportTold)
	wipe(councilHeard); wipe(councilAnswered)
	councilAsk.lease, councilAsk.at, councilAsk.got = nil, -math.huge, 0
	lastFlush = -math.huge
	Watch.mode, Watch.caseKey, Watch.profileKey = nil, nil, nil
	if cardFrame then cardFrame:Hide() end
	cardFrame = nil
	wipe(syncAsked); wipe(syncIncoming); wipe(syncOutgoing); wipe(syncRates); wipe(mwRates)
	syncCounter, syncPeerIndex, lastSync = 0, 0, -math.huge
	syncQueued, flushQueued = false, false
	for k in pairs(stats) do stats[k] = 0 end
end

local buttons = {
	{ "WATCH_WARN_BTN", function() Watch.Ask("warn") end },
	{ "WATCH_WATCH_BTN", function() Watch.Ask("watch") end },
	{ "WATCH_BAN_BTN", function() Watch.Ask("ban") end },
}

if ns.UI and ns.UI.AddTab then
	ns.UI.AddTab({ key = "watch", label = "TAB_WATCH", icon = "Interface\\Icons\\INV_Misc_Eye_01",
		after = "treasury", visible = Watch.TabVisible, build = Watch.Build, buttons = buttons, view = Watch.ViewKey })
end

ns.On("FILTER_CHANGED", function() ns.Fire("WATCH_CHANGED") end)
ns.On("NETOFF_CHANGED", function() ns.Fire("WATCH_CHANGED") end)
ns.On("NETOFF_TIMED_CHANGED", function() ns.Fire("WATCH_CHANGED") end) -- (1.1.6: the desk lists the timed words)
ns.On("WATCH_CHANGED", function() if cardFrame and cardFrame:IsShown() then Watch.RefreshCard() end end)
-- 1.2.1 (DATA_CHANGED comes with the census's news, once a second at most): the records are
-- pruned on their own ticker (and by every read of them), and one recovery ask and one report
-- flush wait at a time, however many changes come meanwhile.
Watch.PRUNE_EVERY = 60
ns.On("DATA_CHANGED", function()
	-- Visibility is recomputed by UI.  Pending sends are guarded by Watch.CanManage and therefore
	-- need no eager cancellation here.
	if not syncQueued and Watch.CanRead() then
		syncQueued = true
		Watch.after(5, "watch roster recovery", function() syncQueued = false; Watch.AskSync(false) end)
	end
	-- 1.1.6: a report waiting for an officer goes once the roster shows one online.
	local b = not flushQueued and Book(false)
	if b and #b.outbox > 0 then
		flushQueued = true
		Watch.after(3, "watch reports", function() flushQueued = false; Watch.FlushReports(false) end)
	end
end)

ns.On("LOGIN", function()
	Watch.Prune()
	Watch.after(20, "watch login recovery", function() Watch.AskSync(false) end)
	Watch.after(30, "watch login reports", function() Watch.FlushReports(true) end)
	if ns.Every then
		ns.Every(Watch.PRUNE_EVERY, "watch prune", function() if Watch.CanRead() then Watch.Prune() end end)
		ns.Every(Watch.SYNC_GAP, "watch recovery", function() Watch.AskSync(false) end)
		ns.Every(Watch.SYNC_GAP, "watch reports", function() Watch.FlushReports(false) end)
		-- 1.2.1: a councillor's client asks the King's client for the council's reports.
		ns.Every(60, "watch council reports", function() Watch.CouncilTick(false) end)
	end
end)

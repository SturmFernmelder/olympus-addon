local ADDON, ns = ...
local L = ns.L

-- Horde Most Wanted (1.2.3, Daniel: "that list should never have existed"): there is no list to
-- be put on first. A Horde player enters by himself the moment an Olympus member's own client
-- observes him killing that member (the member's own death recap) or being killed by that member
-- (the member's own killing blow, PARTY_KILL), and the kill or death counts at once: a bounty on
-- him, or a claim of his open bounty for the member's Slayers row. The faction is proven by this
-- client, never guessed or typed: a Horde unit it sees (or saw within a minute), else the GUID's
-- own race as the game gives it (GetPlayerInfoByGUID); a pet, a creature, the environment, an
-- Alliance player (a free-for-all zone), an instance (a battleground, an arena) and a hidden
-- (secret) payload never count.
--
-- Each own row goes at once to the Olympus channel (WK, the section "Shared kills and deaths"
-- below), and every member's client applies it to its own Wanted list straight away: no Send, no
-- review, no accept. A receiver takes it only from a verified member (its own guild's roster, or
-- a guild rank it can verify), about that member's own death or killing blow (the Olympian side is
-- the server-stamped sender; his GUID only where this client can prove it is his), of this realm
-- group and faction, fresh, once, within per-sender and per-Horde-player rate limits and caps. A
-- reviewer (the King, a signed High Councillor or the author) relays what his client admitted, so
-- members of other guilds hear it too, and answers a late login's catch-up ask (W4) with the
-- recent rows. A reviewer can only take an abusive entry off afterwards, or void one row (WV): it
-- stops counting on every client, and a later event does not bring the entry back.
--
-- A full list never refuses a Horde player: the least active entry makes room (Share.MakeRoom),
-- and the ones taken off are kept off apart, taking no place (MAX_REMOVED). A Horde player is his
-- GUID: rows find his entry by it alone (ResolveTarget), and his name, only a label, is the one the
-- game gives for that GUID wherever this client can look it up (Share.HordeOf, Share.Take).
--
-- The signed top three (WY) is the publisher's own Slayers board, by verified GUID: GUIDs and
-- scores only, never victims, locations or rows. It is signed with the existing Arena account key
-- and accepted only when the server-stamped sender is currently the King, a signed High
-- Councillor, or the author. The receivers keep the last word they accepted live, and after a
-- reload check it again (its signature, the key pinned for its issuer, its expiry, and that its
-- issuer still holds the role) before it shows any frame. A saved word is only ever used by the
-- client that heard it. W4 asks for catch-up; a real reviewer may relay an unchanged signed word
-- in W5. A receiver must already have independently pinned that issuer's key from a verified
-- direct word: a relay never supplies a first-use key or key rotation. Editing a word's rows
-- breaks its signature, and a word under another key than the one pinned for its issuer is
-- refused; whoever rewrites both in his own saved data changes only what his own client shows,
-- as editing the addon itself would.
--
-- Sightings (the section "Most Wanted sightings" below): a Horde player this client saw,
-- where its own player stood then, on its map for 15 minutes and whispered to the one reviewer
-- the member chose. Off until the member's Yes; never on the channel, never in an instance.
local Wanted = {}
ns.Wanted = Wanted

Wanted.VERSION = 1
-- The Horde players held on the list (the most recently active: a full list makes room by itself,
-- Share.MakeRoom, and never refuses one), and apart from them the ones a reviewer took off, kept
-- off (the oldest removal goes first).
Wanted.MAX_TARGETS = 200
Wanted.MAX_REMOVED = 512
Wanted.MAX_SLAYERS = 500
Wanted.MAX_EVIDENCE = 512
Wanted.MAX_SEEN = 2048
Wanted.MAX_VICTIMS = 32
Wanted.MAX_CLAIMS = 30
Wanted.MAX_AUDIT = 100
Wanted.MAX_MONTHS = 24
Wanted.MAX_POINTS = 100000
Wanted.RATE_MAX = 20
Wanted.RATE_WINDOW = 60
Wanted.GLOBAL_BORDERS_ACTIVE = true
Wanted.GLOBAL_ROWS = 3
-- A signed word holds for a month unless a newer one replaces it, its issuer loses the role or
-- he revokes it (was 30 minutes, for one session). Publishing again starts a new month.
Wanted.GLOBAL_LIFE = 31 * 86400
Wanted.GLOBAL_SKEW = 2 * 60
-- The publisher repeats his word for late logins: 6 times 5 minutes apart, then every 30
-- minutes while he stays online, and once 90 seconds after he logs in. Never a new expiry.
Wanted.GLOBAL_BURST = 6
Wanted.GLOBAL_BURST_GAP = 5 * 60
Wanted.GLOBAL_REPEAT_EVERY = 30 * 60
Wanted.GLOBAL_LOGIN_REPEAT = 90
Wanted.GLOBAL_ASK_FIRST, Wanted.GLOBAL_ASK_GAP, Wanted.GLOBAL_ASK_TRIES = 45, 300, 3
Wanted.GLOBAL_DIRECT_PINS_MAX = 64
-- One death has one killer: rows naming the same victim this close together describe one death.
Wanted.DEATH_WINDOW = 5
-- Shared kills and deaths (WK, WV: see "Shared kills and deaths" below).
Wanted.SHARE_AGE = 7 * 86400     -- a row heard older than this is refused (a live row is seconds old)
Wanted.SHARE_RATE_MAX = 8        -- rows taken from one member a window...
Wanted.SHARE_RATE_WINDOW = 60    -- ...of this many seconds
Wanted.SHARE_TARGET_MAX = 20     -- rows taken about one Horde player a window...
Wanted.SHARE_TARGET_WINDOW = 300 -- ...of this many seconds, from everyone
Wanted.SHARE_DAY_MAX = 60        -- rows taken from one member a day (SHARE_DAY): a flood of made-up deaths
Wanted.SHARE_DAY = 86400
Wanted.SHARE_SENDERS_MAX = 1024  -- members (and Horde players) counted at once in a window
Wanted.SHARE_DAY_SENDERS_MAX = 8192 -- members counted at once in a day
Wanted.SHARE_RELAY_MAX = 40      -- rows taken from one reviewer's relays a window (SHARE_RATE_WINDOW)
Wanted.SHARE_ROOM = 20           -- a relay or a catch-up answer leaves this much of Comm's queue free
Wanted.SHARE_CATCH_ROWS = 24     -- rows one catch-up answer carries at most (the newest)
Wanted.SHARE_CATCH_MARKS = 8     -- and removals, and voided rows, each
Wanted.SHARE_RELAY_DELAY = 3     -- a reviewer relays a row this long after he took it (and a part of 8 s his own)
Wanted.SHARE_RESEND_FIRST = 60   -- this client's own rows the channel did not take go again this long after login...
Wanted.SHARE_RESEND_EVERY = 300  -- ...then this often...
Wanted.SHARE_RESEND_MAX = 4      -- ...this many at a time
Wanted.SHARE_HEARD_MAX = 512     -- relayed row ids remembered (a reviewer relays each once)
Wanted.VOIDS_MAX = 256           -- voided rows remembered, so one heard later is refused too
Wanted.DIAG_MAX = 40             -- this session's captures and refusals /oly wanted status lists
Wanted.GLOBAL_MAX_SEQ = 2147483647
Wanted.GLOBAL_MAX_EPOCH = 2147483647
Wanted.GLOBAL_MAX_VERIFY = 8
-- Sightings (see "Most Wanted sightings" below).
Wanted.SIGHT_TTL = 15 * 60       -- a pin shows this long after the sighting
Wanted.SIGHT_GAP = 180           -- this client records one Horde player once this often on one map
Wanted.SIGHT_GRID = 5            -- the observer's spot, in thousandths of the map rounded to 5 (0.5%)
Wanted.SIGHT_SEND_MAX = 3        -- sightings this client sends a window...
Wanted.SIGHT_WINDOW = 60         -- ...of this many seconds (the rest stay on its own map)
Wanted.SIGHT_QUEUE_MAX = 8       -- sighting whispers waiting in Comm, at most
Wanted.SIGHT_QUEUE_TTL = 30      -- a sighting that waited this long in Comm is not sent
Wanted.SIGHT_RECV_MAX = 3        -- sightings a reviewer takes from one sender a window...
Wanted.SIGHT_INTAKE_MAX = 30     -- ...and from everyone
Wanted.SIGHT_SENDERS_MAX = 128   -- senders a reviewer counts at once
Wanted.SIGHT_PINS = 48           -- pins held at most (the newest)
Wanted.SIGHT_SEEN_MAX = 512      -- sighting ids remembered (replays)
Wanted.SIGHT_OWN_MAX = 256       -- Horde players this client remembers seeing (SIGHT_GAP)
Wanted.SIGHT_LAYER_FRESH = 120   -- this client's layer, when Layers saw it this recently
Wanted.SIGHT_TICK = 15           -- pins expire (and follow the interface style) on this beat
Wanted.SIGHT_QUIET = 5           -- the server's "No player named" for a sighting whisper, kept out of chat this long
Wanted.SIGHT_BADGE = 16          -- the world map's badge
Wanted.SIGHT_MINI = 12           -- the minimap's
Wanted.REVIEWER_FIRST = 45       -- a reviewer says he takes sightings this long after login...
Wanted.REVIEWER_EVERY = 5 * 60   -- ...then this often...
Wanted.REVIEWER_FOR = 11 * 60    -- ...and is sent them for this long after the last time
Wanted.REVIEWERS_MAX = 32
Wanted.ICON_PATHS = {
	"Interface\\Icons\\INV_Misc_Tournaments_banner_Orc",
	"Interface\\Icons\\INV_BannerPVP_01",
	"Interface\\Icons\\INV_Misc_QuestionMark",
}

local stats = { accepted = 0, replay = 0, refused = 0, corrected = 0, checkpointed = 0, conflict = 0,
	reviewed = 0, globalAccepted = 0, globalRefused = 0, globalReplay = 0, globalRestored = 0,
	sightSeen = 0, sightRepeat = 0, sightRate = 0, sightSent = 0, sightCancelled = 0, sightTaken = 0,
	sightRefused = 0, sightReplay = 0, sightExpired = 0, sightWithdrawn = 0, leases = 0 }
local rate = {}
local mode, opened = "list", nil
-- The word shown now. After a reload it comes back only through RestoreGlobal, which checks the
-- saved copy again; the copy alone (or any other saved field) never shows a frame.
local authenticatedGlobal
local globalFloor, publisherHeads = nil, {}
local pendingGlobal, pendingGlobalCount = {}, 0
-- The saved word being checked again after a load (its floor and pin hold meanwhile), and each
-- saved text's signature, checked once a session.
local restoring, restoreChecked = nil, {}
local publishedGlobal
Wanted.globalCatch = { asked = -math.huge, replied = -math.huge, generation = 0 }
local watchingNotFound = false
-- 1.2.3: the shared kills and deaths' helpers and this session's state (the section "Shared kills
-- and deaths" below; a table, as Wanted.lua's main chunk is at Lua's 200 locals): the senders'
-- and Horde players' rate windows, the rows a reviewer heard relayed (he relays each once), and
-- this session's captures and refusals for /oly wanted status.
local Share = { rates = {}, days = {}, targets = {}, relayed = {}, relayedOrder = {},
	log = {}, why = {}, counts = {}, catchReplied = -math.huge, catchHeard = -math.huge }
local ScheduleGlobalRepeat
-- Sightings, this session's only (nothing of them is saved): the pins ([Horde GUID] = the newest
-- sighting of him), their frames, the ids taken (replays), this client's own last sighting of each
-- Horde player (SIGHT_GAP), when its last ones went (SIGHT_SEND_MAX), its whispers waiting in Comm,
-- the reviewers they reached (a No takes them back), the reviewers whose "No player named" it
-- keeps out of chat for a moment, each sender's count and everyone's (a reviewer's intake), and
-- the reviewers heard taking them.
local pins, pinFrames, spareFrames = {}, {}, {}
local sightSeen, sightSeenOrder = {}, {}
local ownSeen, ownSeenCount = {}, 0
local sightSends = {}
local sightJobs, sightJobCount = {}, 0
-- (told.by: [folded reviewer] = { name, target }; told.quiet: [lowered name] = until)
local told = { by = {}, quiet = {}, filter = false }
local sightFrom, sightFromCount, sightIntake = {}, 0, { at = 0, n = 0 }
local reviewers, reviewerCount = {}, 0
local leaseGen, leaseAt = 0, nil
local pinTicker = false
local SightingNotFound
local deathSerial = 0
local knownHorde = {} -- this session's verified unit identities, never addon messages

local function Clock()
	local D = ns.Data
	return (D and D.ServerTime and D.ServerTime()) or ns.Now()
end

local function Secret(...)
	if type(issecretvalue) ~= "function" then return false end
	for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then return true end end
	return false
end

local function Whole(v, lo, hi)
	if Secret(v) then return nil end
	local ok, number = pcall(tonumber, v)
	v = ok and number or nil
	return v and v == math.floor(v) and v >= lo and v <= hi and v or nil
end

local function Count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do n = n + 1 end
	return n
end

local function Clean(value, limit)
	if Secret(value) then return nil end
	local ok, s = pcall(tostring, value or "")
	if not ok then return nil end
	s = s:gsub("[~|%^%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	return ns.Cut(s, limit or 96)
end

local function CleanRealm(realm)
	if Secret(realm) then return nil end
	realm = type(realm) == "string" and realm:gsub("[%s%-]", "") or nil
	if not realm or realm == "" or realm == "?" or realm:find("+", 1, true) then return nil end
	return ns.Cut(realm, 48)
end

local function CleanName(name, realm)
	if Secret(name, realm) then return nil end
	name = Clean(ns.Normal and ns.Normal(name) or name, 72)
	if not name then return nil end
	local namedRealm = ns.RealmOf and ns.RealmOf(name) or name:match("%-(.+)$")
	local short = ns.ShortName and ns.ShortName(name) or name:gsub("%-.*$", "")
	short = Clean(short, 48)
	if not short then return nil end
	realm = CleanRealm(namedRealm) or CleanRealm(realm) or CleanRealm(ns.realm)
	return realm and (short .. "-" .. realm) or short
end

local function Guid(guid)
	if Secret(guid) then return nil end
	if type(guid) ~= "string" or #guid > 64 then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	if not server or #id < 8 or #id > 16 then return nil end
	return "Player-" .. server .. "-" .. id:upper()
end

local function GuidKey(guid)
	guid = Guid(guid)
	return guid and ("g:" .. guid) or nil
end

local function NameKey(name)
	name = CleanName(name)
	return name and ("n:" .. ns.Fold(name)) or nil
end

local function Identity(value, guid, realm)
	if type(value) == "table" then
		guid, realm, value = value.guid, value.realm, value.name
	end
	local name = CleanName(value, realm)
	guid = Guid(guid)
	if not name and not guid then return nil end
	return { name = name, realm = name and ns.RealmOf(name) or CleanRealm(realm), guid = guid,
		key = GuidKey(guid) or NameKey(name), nameKey = NameKey(name), guidKey = GuidKey(guid) }
end
Wanted.Identity = Identity

local function SameIdentity(a, b)
	a, b = type(a) == "table" and a or Identity(a), type(b) == "table" and b or Identity(b)
	if not a or not b then return false end
	if a.guid and b.guid then return a.guid == b.guid end
	return a.nameKey ~= nil and a.nameKey == b.nameKey
end

local function Store(create)
	if type(ns.rdb) ~= "table" then return nil end
	local s = ns.rdb.wanted
	if type(s) ~= "table" or s.version ~= Wanted.VERSION or s.group ~= ns.group or s.faction ~= ns.faction then
		if not create then return nil end
		s = { version = Wanted.VERSION, group = ns.group, faction = ns.faction, targets = {}, aliases = {},
		slayers = {}, slayerAliases = {}, baseSlayers = {}, evidence = {}, seen = {}, seenOrder = {}, recent = {}, audit = {},
		voids = {}, seq = 0 }
		ns.rdb.wanted = s
	end
	-- (voids, 1.2.3: [sender#digest] = when a reviewer voided that shared row, so a copy heard later
	-- is refused too.)
	for _, key in ipairs({ "targets", "aliases", "slayers", "slayerAliases", "baseSlayers", "evidence", "seen", "seenOrder", "recent", "audit", "voids" }) do
		if type(s[key]) ~= "table" then s[key] = {} end
	end
	s.seq = Whole(s.seq, 0, 2147483647) or 0
	return s
end

local function Sighting(value)
	if type(value) ~= "table" then return nil end
	local zone, at = Clean(value.zone, 80), Whole(value.at, 0, 4294967295)
	if not zone or not at then return nil end
	return { zone = zone, at = at, precision = value.precision == "consented" and "consented" or "approximate",
		evidence = value.evidence == "SELF_DEATH" and "SELF_DEATH" or "PARTY_KILL" }
end

local CopySlayers

-- (paid, 1.2.3: what this entry's claims paid each Slayer, in the shape of the Slayers rows. The
-- Slayers board is built from the entries on the list, so an entry taken off takes its points with
-- it, folded or not: Rebuild.)
local function TargetDerived(t)
	return {
		current = Whole(t.current, 0, Wanted.MAX_POINTS) or 0,
		lifetimeKills = Whole(t.lifetimeKills, 0, Wanted.MAX_POINTS) or 0,
		cycle = Whole(t.cycle, 1, Wanted.MAX_POINTS) or 1,
		openSince = Whole(t.openSince, 0, 4294967295) or (tonumber(t.addedAt) or 0),
		lastDeath = Whole(t.lastDeath, 0, 4294967295),
		lastSighting = Sighting(t.lastSighting),
		victimOverflow = Whole(t.victimOverflow, 0, Wanted.MAX_POINTS) or 0,
		victims = type(t.victims) == "table" and t.victims or {},
		claims = type(t.claims) == "table" and t.claims or {},
		paid = CopySlayers(t.paid),
	}
end

local function CopyList(list, limit)
	local out = {}
	for i = math.max(1, #(type(list) == "table" and list or {}) - (limit or 100) + 1), #(type(list) == "table" and list or {}) do
		local e = list[i]
		if type(e) == "table" then
			local c = {}
			for k, v in pairs(e) do
				if type(v) == "table" then c[k] = CopyList(v, Wanted.MAX_VICTIMS) else c[k] = v end
			end
			out[#out + 1] = c
		end
	end
	return out
end

CopySlayers = function(rows)
	local out = {}
	for key, r in pairs(type(rows) == "table" and rows or {}) do
		if type(key) == "string" and type(r) == "table" then
			local months, monthAt, monthClaims, available = {}, {}, {}, {}
			for m, n in pairs(type(r.months) == "table" and r.months or {}) do
				m, n = tonumber(m), Whole(n, 0, Wanted.MAX_POINTS)
				if m and n then available[#available + 1] = { m, n } end
			end
			table.sort(available, function(a, b) return a[1] > b[1] end)
			for i = 1, math.min(Wanted.MAX_MONTHS, #available) do
				local m, n = available[i][1], available[i][2]
				months[m] = n
				monthAt[m] = Whole(type(r.monthAt) == "table" and r.monthAt[m], 0, 4294967295) or 0
				monthClaims[m] = Whole(type(r.monthClaims) == "table" and r.monthClaims[m], 0, Wanted.MAX_POINTS) or 0
			end
			out[key] = { key = key, name = CleanName(r.name), guid = Guid(r.guid), total = Whole(r.total, 0, Wanted.MAX_POINTS) or 0,
				claims = Whole(r.claims, 0, Wanted.MAX_POINTS) or 0, reachedAt = Whole(r.reachedAt, 0, 4294967295) or 0,
				lastAt = Whole(r.lastAt, 0, 4294967295) or 0, months = months, monthAt = monthAt, monthClaims = monthClaims }
		end
	end
	return out
end

local function MergeSlayer(into, from)
	into.total = math.min(Wanted.MAX_POINTS, (into.total or 0) + (from.total or 0))
	into.claims = math.min(Wanted.MAX_POINTS, (into.claims or 0) + (from.claims or 0))
	into.reachedAt = math.max(into.reachedAt or 0, from.reachedAt or 0)
	into.lastAt = math.max(into.lastAt or 0, from.lastAt or 0)
	into.months, into.monthAt, into.monthClaims = into.months or {}, into.monthAt or {}, into.monthClaims or {}
	for month, points in pairs(from.months or {}) do
		into.months[month] = math.min(Wanted.MAX_POINTS, (into.months[month] or 0) + points)
		into.monthAt[month] = math.max(into.monthAt[month] or 0, from.monthAt and from.monthAt[month] or 0)
		into.monthClaims[month] = math.min(Wanted.MAX_POINTS,
			(into.monthClaims[month] or 0) + (from.monthClaims and from.monthClaims[month] or 0))
	end
	into.name, into.guid = into.name or from.name, into.guid or from.guid
	return into
end

-- A Slayer's key as this store knows him now (a name known first, his GUID learned later: the
-- aliases ResolveSlayer keeps).
function Share.SlayerKey(s, key)
	for _ = 1, 3 do
		local alias = s.slayerAliases[key]
		if type(alias) ~= "string" or alias == key then break end
		key = alias
	end
	return key
end

-- One entry's contribution (a Slayers-shaped row) added into a Slayers table under its Slayer's
-- key now (rows: s.slayers, or the points no entry holds any more, s.baseSlayers).
function Share.AddPaid(s, rows, r)
	local key = Share.SlayerKey(s, r.key)
	local into = rows[key]
	if not into then
		-- (A GUID's key names his GUID, though the row was folded when his name alone was known.)
		into = { key = key, name = r.name, guid = r.guid or Guid(key:match("^g:(.+)$")), total = 0, claims = 0,
			months = {}, monthAt = {}, monthClaims = {} }
		rows[key] = into
	end
	MergeSlayer(into, r)
end

local function ResolveSlayer(s, value, create, upgrade)
	local ident = Identity(value)
	if not ident then return nil end
	if upgrade == nil then upgrade = create == true end
	local gk, nk = ident.guidKey, ident.nameKey
	local key = gk and (s.slayerAliases[gk] or gk) or nil
	local r = key and s.slayers[key] or nil
	if not r and nk then
		key = s.slayerAliases[nk] or nk
		r = s.slayers[key]
	end
	if r and r.guid and ident.guid and r.guid ~= ident.guid then return nil end
	if r and gk and r.key ~= gk and upgrade then
		local oldKey, other = r.key, s.slayers[gk]
		if other and other ~= r then
			r = MergeSlayer(other, r)
			s.slayers[oldKey] = nil
		else
			s.slayers[oldKey] = nil
			r.key = gk
			s.slayers[gk] = r
		end
		s.slayerAliases[oldKey] = gk
		key = gk
	elseif not r and create then
		if Count(s.slayers) >= Wanted.MAX_SLAYERS then return nil, "full" end
		key = gk or nk
		if not key then return nil, "identity" end
		r = { key = key, name = ident.name, guid = ident.guid, total = 0, claims = 0,
			months = {}, monthAt = {}, monthClaims = {} }
		s.slayers[key] = r
	end
	if not r then return nil end
	if upgrade or create then r.name, r.guid = ident.name or r.name, ident.guid or r.guid end
	if upgrade or create then
		if nk then s.slayerAliases[nk] = r.key end
		if gk then s.slayerAliases[gk] = r.key end
	end
	return r, r.key
end

local function TrimList(list, max)
	while #list > max do table.remove(list, 1) end
end

-- Whether entry a holds a name's alias before entry b (or none): one on the list before one taken
-- off, a name this client's game gave before one only a shared row wrote, then the newer.
function Share.Better(a, b)
	if type(b) ~= "table" then return true end
	if (a.active == true) ~= (b.active == true) then return a.active == true end
	if (a.wireName == true) ~= (b.wireName == true) then return b.wireName == true end
	return (tonumber(a.addedAt) or 0) > (tonumber(b.addedAt) or 0)
end

-- An entry's name, and its alias (only a lookup by name reads it: a row about a Horde player
-- finds him by his GUID alone, ResolveTarget). wire: the name is a shared row's, which this
-- client's game could not check; it takes the alias only from an entry no better (Share.Better).
-- A name this client's game gave takes it from anyone: the newest proof wins.
function Share.Name(s, t, ident, wire)
	local oldKey = NameKey(t.name)
	-- (The name he had still finds him, unless only a row wrote it.)
	if oldKey and oldKey ~= ident.nameKey then
		if t.wireName then
			if s.aliases[oldKey] == t.key then s.aliases[oldKey] = nil end
		elseif s.aliases[oldKey] == nil then
			s.aliases[oldKey] = t.key
		end
	end
	t.name, t.realm, t.wireName = ident.name, ident.realm, wire and true or nil
	local nk = ident.nameKey
	if not nk or nk == t.key then return end
	local holder = s.targets[s.aliases[nk] or nk]
	if not wire or holder == t or Share.Better(t, holder) then s.aliases[nk] = t.key end
end

-- An entry taken off lets go of his name: it finds the best other entry under it (Share.Better,
-- one on the list first), and him only while there is none (his page, as an audit). Nothing a row
-- counts against is found by a name any more (ResolveTarget), so a name never keeps anyone off.
function Share.ReleaseName(s, t)
	local nk = NameKey(t.name)
	if not nk or nk == t.key or s.aliases[nk] ~= t.key then return end
	local best = t
	for key, o in pairs(s.targets) do
		if o ~= t and key ~= nk and NameKey(o.name) == nk and Share.Better(o, best) then best = o end
	end
	s.aliases[nk] = best.key
end

-- The entry an identity names, or nil. A GUID finds only the entry pinned to it, or a name-only
-- listing (1.2.2's, a moderator's) under his name while it is on the list, and that only from
-- what this client proved itself: a shared row's name is its sender's word (wire), and never
-- pins a GUID to a typed name. A name alone finds the entry under it; from a shared row (wire:
-- its Olympian, by the name the server stamps), only one pinned to no GUID, so that an entry a
-- row made under someone's name never stands for him. upgrade: what the identity teaches the
-- entry (his GUID, a name from this client's game, or a name where it had none).
local function ResolveTarget(s, ident, upgrade, wire)
	if not ident then return nil end
	local t, key
	if ident.guidKey then
		key = s.aliases[ident.guidKey] or ident.guidKey
		t = s.targets[key]
		if t and t.guid ~= ident.guid then t = nil end
		if not t and ident.nameKey and not wire then
			local named = s.targets[ident.nameKey]
			if type(named) == "table" and not named.guid and named.active == true then t, key = named, ident.nameKey end
		end
	elseif ident.nameKey then
		key = s.aliases[ident.nameKey] or ident.nameKey
		t = s.targets[key]
		if not t then key = ident.nameKey; t = s.targets[key] end
		if t and wire and t.guid then t = nil end
	end
	if not t then return nil end
	if ident.guid and not t.guid and upgrade then
		local newKey = ident.guidKey
		local other = s.targets[newKey]
		if other and other ~= t then return nil end
		local oldKey = t.key
		s.targets[oldKey] = nil
		t.key, t.guid = newKey, ident.guid
		s.targets[newKey] = t
		s.aliases[oldKey], s.aliases[newKey] = newKey, newKey
		if ident.name then Share.Name(s, t, ident, false) end
		for _, e in ipairs(s.evidence) do if e.targetKey == oldKey then e.targetKey = newKey end end
		key = newKey
	elseif ident.name and ident.guid and upgrade and (not t.name or not wire and t.name ~= ident.name) then
		Share.Name(s, t, ident, wire)
	end
	return t, key
end

local function MonthNow()
	local c = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
	if type(c) == "table" and Whole(c.year, 1970, 9999) and Whole(c.month, 1, 12) then return c.year * 12 + c.month - 1 end
	local now = Clock()
	local offset = 0
	if type(GetGameTime) == "function" then
		local ok, h, m = pcall(GetGameTime)
		if ok and type(h) == "number" and type(m) == "number" then
			local d = (h * 60 + m - math.floor(now / 60) % 1440) % 1440
			if d > 720 then d = d - 1440 end
			offset = math.floor(d / 15 + 0.5) * 900
		end
	end
	if ns.Honors and ns.Honors.MonthOf then return ns.Honors.MonthOf(now, offset) end
	local dateFn = date or (os and os.date)
	if type(dateFn) ~= "function" then return math.floor(now / 2592000) end
	local d = dateFn("!*t", now + offset)
	return d.year * 12 + d.month - 1
end
Wanted.MonthNow = MonthNow

local function TrimMonths(r, current)
	local first = current - Wanted.MAX_MONTHS + 1
	for month in pairs(type(r.months) == "table" and r.months or {}) do
		if type(month) ~= "number" or month < first or month > current then
			r.months[month] = nil
			if type(r.monthAt) == "table" then r.monthAt[month] = nil end
			if type(r.monthClaims) == "table" then r.monthClaims[month] = nil end
		end
	end
end

-- One paid claim on a Slayers-shaped row: the Slayer's own, or what one entry paid him.
function Share.Pay(r, points, at, month)
	r.months, r.monthAt, r.monthClaims = r.months or {}, r.monthAt or {}, r.monthClaims or {}
	r.total, r.claims, r.reachedAt, r.lastAt = math.min(Wanted.MAX_POINTS, (r.total or 0) + points),
		math.min(Wanted.MAX_POINTS, (r.claims or 0) + 1), at, at
	r.months[month], r.monthAt[month] = math.min(Wanted.MAX_POINTS, (r.months[month] or 0) + points), at
	r.monthClaims[month] = math.min(Wanted.MAX_POINTS, (r.monthClaims[month] or 0) + 1)
	TrimMonths(r, MonthNow())
end

local function AddVictim(t, e)
	local row = { name = e.victimName, guid = e.victimGuid, at = e.at, evidence = e.kind, id = e.id,
		zone = e.zone, precision = e.precision }
	t.victims[#t.victims + 1] = row
	if #t.victims > Wanted.MAX_VICTIMS then
		table.remove(t.victims, 1)
		t.victimOverflow = (t.victimOverflow or 0) + 1
	end
end

local function ApplyEvidence(s, e)
	local t = s.targets[e.targetKey]
	if not t then return false end
	-- 1.2.3: an entry a reviewer took off (abuse) keeps its rows, and they count for nothing: no
	-- bounty on him, no point paid for him (Wanted.RemoveTarget rebuilds the totals without them).
	if t.active ~= true then return true end
	if e.action == "bounty" then
		if t.current >= Wanted.MAX_POINTS or t.lifetimeKills >= Wanted.MAX_POINTS then return false end
		t.current, t.lifetimeKills = t.current + 1, t.lifetimeKills + 1
		AddVictim(t, e)
	elseif e.action == "claim" then
		local points = t.current
		local r
		if points > 0 then
			r = ResolveSlayer(s, { name = e.killerName, guid = e.killerGuid }, true)
			if not r then return false end
		end
		e.points = points
		local claim = { id = e.id, at = e.at, slayer = e.killerName, slayerGuid = e.killerGuid, points = points,
			evidence = e.kind, cycle = t.cycle, victims = CopyList(t.victims, Wanted.MAX_VICTIMS), overflow = t.victimOverflow or 0 }
		t.claims[#t.claims + 1] = claim
		TrimList(t.claims, Wanted.MAX_CLAIMS)
		t.current, t.victims, t.victimOverflow = 0, {}, 0
		t.lastDeath, t.openSince, t.cycle = e.at, e.at, math.min(Wanted.MAX_POINTS, t.cycle + 1)
		if points > 0 then
			r.name, r.guid = e.killerName or r.name, e.killerGuid or r.guid
			Share.Pay(r, points, e.at, e.month)
			-- (And on this entry's own account of what it paid him: Rebuild, Checkpoint.)
			if type(t.paid) ~= "table" then t.paid = {} end
			local p = t.paid[r.key]
			if not p then p = { key = r.key } t.paid[r.key] = p end
			p.name, p.guid = r.name, r.guid
			Share.Pay(p, points, e.at, e.month)
		end
	else
		return false
	end
	if e.zone then t.lastSighting = { zone = e.zone, at = e.at, precision = e.precision, evidence = e.kind } end
	return true
end

-- The totals built again: each entry from its base, the Slayers from the points no entry holds any
-- more (s.baseSlayers: an entry that made room for another, or folded before 1.2.3) and what each
-- entry on the list paid, folded (its base's paid: an entry taken off pays nothing any more, on
-- every client, whenever it folded), then the live rows in the order of the deaths.
local function Rebuild(s)
	for _, t in pairs(s.targets) do
		local b = TargetDerived(type(t.base) == "table" and t.base or {})
		t.current, t.lifetimeKills, t.cycle, t.openSince, t.lastDeath = b.current, b.lifetimeKills, b.cycle, b.openSince, b.lastDeath
		t.lastSighting = b.lastSighting
		t.victimOverflow, t.victims, t.claims = b.victimOverflow, CopyList(b.victims, Wanted.MAX_VICTIMS), CopyList(b.claims, Wanted.MAX_CLAIMS)
		t.paid = b.paid
	end
	s.slayers = CopySlayers(s.baseSlayers)
	for _, t in pairs(s.targets) do
		if t.active == true then for _, p in pairs(t.paid) do Share.AddPaid(s, s.slayers, p) end end
	end
	for _, e in ipairs(s.evidence) do if type(e) == "table" and not e.void then ApplyEvidence(s, e) end end
	return true
end
Wanted.Rebuild = function() local s = Store(false); return s and Rebuild(s) or false end

local function Checkpoint(s)
	for _, t in pairs(s.targets) do
		t.base = TargetDerived(t)
		t.base.victims, t.base.claims = CopyList(t.victims, Wanted.MAX_VICTIMS), CopyList(t.claims, Wanted.MAX_CLAIMS)
		-- (What it paid, each Slayer under his key now.)
		local paid = {}
		for _, p in pairs(t.base.paid) do Share.AddPaid(s, paid, p) end
		for _, p in pairs(paid) do TrimMonths(p, MonthNow()) end
		t.base.paid = paid
	end
	-- (The Slayers' points stay with the entries that paid them; s.baseSlayers keeps only the
	-- points no entry holds any more.)
	for _, r in pairs(s.baseSlayers) do TrimMonths(r, MonthNow()) end
	-- (1.2.3: the newest death folded. A shared row about a death before it can no longer take its
	-- place in the order of the deaths, and is refused: "late".)
	for _, e in ipairs(s.evidence) do
		local at = Whole(type(e) == "table" and e.at, 0, 4294967295)
		if at and at > (Whole(s.foldedAt, 0, 4294967295) or 0) then s.foldedAt = at end
	end
	s.evidence = {}
	stats.checkpointed = stats.checkpointed + 1
end

local function Audit(s, op, target, detail)
	s.audit[#s.audit + 1] = { op = op, target = target, detail = detail, at = math.floor(Clock()), by = ns.me }
	TrimList(s.audit, Wanted.MAX_AUDIT)
end

local function Changed()
	ns.Fire("WANTED_CHANGED")
	if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end
end

function Wanted.CanManage()
	if not ns.IsMember or not ns.IsMember() or not ns.me then return false end
	local M = ns.Moderation
	if M and M.CanIssue and M.CanIssue() == true then return true end
	local W = ns.Workshop
	return W and W.IsAuthor and W.IsAuthor() == true or false
end

-- 1.2.3: nobody lists a Horde player first any more, and no button does it: he enters by himself
-- from a member's own death or killing blow (RecordKill). This listing by name or GUID, for a
-- Watch moderator or the author and through this function alone, stays for the targets 1.2.2
-- saved and for the tests: such an entry is a Horde player like any other, and an own event
-- about him counts against it (a name-only one learns his GUID then).
function Wanted.AddTarget(value, guid, realm)
	if not Wanted.CanManage() then return false, "access" end
	local ident = Identity(value, guid, realm)
	if not ident then return false, "identity" end
	local s = Store(true)
	local t = ResolveTarget(s, ident, true)
	if t then
		if t.active then return false, "listed" end
		Share.MakeRoom(s)
		t.active, t.removedAt, t.removedBy = true, nil, nil
		t.addedAt, t.addedBy = math.floor(Clock()), ns.me
	else
		Share.MakeRoom(s)
		t = { key = ident.key, name = ident.name, realm = ident.realm, guid = ident.guid, active = true,
			addedAt = math.floor(Clock()), addedBy = ns.me, source = "manual", current = 0, lifetimeKills = 0,
			cycle = 1, openSince = math.floor(Clock()), victims = {}, claims = {}, victimOverflow = 0 }
		s.targets[t.key] = t
		if ident.nameKey then s.aliases[ident.nameKey] = t.key end
		if ident.guidKey then s.aliases[ident.guidKey] = t.key end
	end
	Audit(s, "add", t.key)
	Changed()
	return true, t.key
end

-- 1.2.3: who may take an abusive entry off, or void one row: the King, a signed High Councillor
-- or the author (the roles every client checks on his word, WV), never a member, nor a review.
function Wanted.CanRemove() return Wanted.CanPublish(ns.me) == true end

-- An abusive entry taken off: here at once, and on every client through the reviewer's word on
-- the channel (WV, Share.SendMark). Its rows stay, as an audit, and count for nothing any more
-- (ApplyEvidence): no bounty on him, no point paid for him, even what was folded (Rebuild). A
-- later event about him is refused ("removed"), so it never comes back by itself. He is kept off
-- by his GUID apart from the list (MAX_REMOVED), and lets go of his name (Share.ReleaseName).
function Wanted.RemoveTarget(value, guid, realm)
	if not Wanted.CanRemove() then return false, "access" end
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	if not (t and t.active) then return false, "missing" end
	Share.TakeOff(s, t, CleanName(ns.me), math.floor(Clock()))
	Audit(s, "remove", t.key)
	if opened == t.key then mode, opened = "list", nil end
	if t.guid then Share.SendMark("T", t.guid) end
	Changed()
	return true
end

-- (The entry off, nothing of what it held kept, folded or not, and the totals again without it.)
function Share.TakeOff(s, t, by, at)
	t.active, t.removedAt, t.removedBy, t.base = false, at, by, nil
	Share.ReleaseName(s, t)
	Share.TrimRemoved(s)
	Rebuild(s)
end

-- One entry gone from this store: its aliases and its rows with it.
function Share.Drop(s, key)
	s.targets[key] = nil
	for alias, held in pairs(s.aliases) do if held == key then s.aliases[alias] = nil end end
	for i = #s.evidence, 1, -1 do if s.evidence[i].targetKey == key then table.remove(s.evidence, i) end end
end

-- The entries taken off, MAX_REMOVED at most, apart from the list: past it the oldest removal goes.
function Share.TrimRemoved(s)
	local off = {}
	for key, t in pairs(s.targets) do if t.active ~= true then off[#off + 1] = key end end
	if #off <= Wanted.MAX_REMOVED then return end
	table.sort(off, function(a, b)
		local x, y = tonumber(s.targets[a].removedAt) or 0, tonumber(s.targets[b].removedAt) or 0
		if x ~= y then return x < y end
		return a < b
	end)
	for i = 1, #off - Wanted.MAX_REMOVED do Share.Drop(s, off[i]) end
end

local function UnitIdentity(unit)
	if type(UnitIsPlayer) == "function" then
		local ok, yes = pcall(UnitIsPlayer, unit)
		if not ok or yes ~= true then return nil end
	end
	local okName, name = pcall(function() return ns.UnitFullName and ns.UnitFullName(unit) or nil end)
	local okGuid, guid = pcall(function() return UnitGUID and UnitGUID(unit) or nil end)
	if not okName or not okGuid or Secret(name, guid) then return nil end
	return Identity(name, guid)
end

function Wanted.AddTargetUnit(unit)
	unit = unit or "target"
	local ident = UnitIdentity(unit)
	if not ident then return false, "identity" end
	if type(UnitFactionGroup) == "function" then
		local ok, known, horde = pcall(function()
			local faction = UnitFactionGroup(unit)
			if Secret(faction) then return true, false end
			return faction ~= nil, faction == "Horde"
		end)
		if not ok or known and not horde then return false, "faction" end
	end
	return Wanted.AddTarget(ident)
end

local function UnitMatches(unit, ident)
	local u = UnitIdentity(unit)
	return u and SameIdentity(u, ident)
end

local function RememberHorde(ident)
	if not ident or not ident.guid or not ident.name then return end
	local now = math.floor(Clock())
	knownHorde[ident.guid] = { identity = ident, at = now }
	for guid, row in pairs(knownHorde) do if now - row.at > 60 or row.at > now then knownHorde[guid] = nil end end
	while Count(knownHorde) > Wanted.MAX_TARGETS do
		local oldest
		for guid, row in pairs(knownHorde) do if not oldest or row.at < knownHorde[oldest].at then oldest = guid end end
		knownHorde[oldest] = nil
	end
end

-- A Horde player this client sees now (a unit with his GUID: the target, the focus, the mouse's,
-- a nameplate, or the game's own token for that GUID) or saw within a minute, or nil. nil, true
-- when a unit of his shows now and is no Horde player (or its faction is unknown): the current
-- unit overrides an old observation.
local function KnownHorde(ident)
	if not ident or not ident.guid then return nil end
	local units = { "target", "focus", "mouseover" }
	for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
	if type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, ident.guid)
		if ok and type(token) == "string" and not Secret(token) then table.insert(units, 1, token) end
	end
	for _, unit in ipairs(units) do
		local observed = UnitIdentity(unit)
		if observed and observed.guid == ident.guid then
			local ok, faction = pcall(function() return UnitFactionGroup and UnitFactionGroup(unit) end)
			if ok and not Secret(faction) and faction == "Horde" then RememberHorde(observed); return observed end
			return nil, true -- current contradictory/unknown faction overrides an old observation
		end
	end
	local row, now = knownHorde[ident.guid], math.floor(Clock())
	return row and row.at <= now and now - row.at <= 60 and row.identity or nil
end

local function VerifiedOlympian(ident)
	if not ident then return false end
	local mine = UnitIdentity("player") or Identity(ns.me)
	if mine and SameIdentity(mine, ident) and ns.IsMember and ns.IsMember() then return true end
	local R = ns.Roster
	if ident.name and R and R.RankOf and R.RankOf(ident.name) ~= nil then return true end
	local units = { "player", "target", "focus", "mouseover" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for i = 1, 40 do units[#units + 1] = "raid" .. i end
	for _, unit in ipairs(units) do
		if UnitMatches(unit, ident) then
			local guild = GetGuildInfo and GetGuildInfo(unit)
			if not Secret(guild) and type(guild) == "string" and ns.IsFederation(guild) then return true end
		end
	end
	return false
end

local function Zone()
	if type(GetRealZoneText) ~= "function" then return nil end
	local ok, zone = pcall(GetRealZoneText)
	return ok and Clean(zone, 80) or nil
end

local function InInstance()
	if type(IsInInstance) ~= "function" then return false end
	local ok, inside = pcall(IsInInstance)
	if not ok or Secret(inside) then return true end -- (not known: as if inside)
	return inside == true
end

local function Hex(bytes)
	return type(bytes) == "string" and (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) or nil
end

local function Digest(text)
	local S = ns.Sign
	local raw = S and S.SHA256 and S.SHA256(tostring(text or "")) or nil
	return raw and Hex(raw):sub(1, 16) or nil
end

-- 1.2.3: the races only the Horde plays, by the game's own file names (GetPlayerInfoByGUID's
-- fourth return, as C_CreatureInfo.GetRaceInfo's clientFileString). Forever's Skyborn are of both
-- factions (ChatRooms.lua), and a race this table does not name proves nothing either.
Share.HORDE_RACES = { Orc = true, Scourge = true, Undead = true, Tauren = true, Troll = true, BloodElf = true,
	Goblin = true, Nightborne = true, HighmountainTauren = true, MagharOrc = true, ZandalariTroll = true, Vulpera = true }

-- A character's name as the game's lookup of his GUID gives it (Debts.InfoName: Forever splits a
-- surname into the realm's place), or nil.
function Share.InfoName(guid)
	local D = ns.Debts
	if type(D) == "table" and type(D.InfoName) == "function" then
		local ok, name = pcall(D.InfoName, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) then return name end
		return nil
	end
	if type(GetPlayerInfoByGUID) ~= "function" then return nil end
	local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
	if not ok or type(name) ~= "string" or name == "" or Secret(name, realm) then return nil end
	return ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)
end

-- A Horde player's identity as this client proves it, never as a row or a player names him: his
-- entry here (a Horde player already), a unit of his it sees now or saw within a minute
-- (KnownHorde: the target, the focus, the mouse's, a nameplate, the game's token for his GUID),
-- else the game's lookup of his GUID (GetPlayerInfoByGUID: a race only the Horde plays, and his
-- name). No unit, nameplate or target is needed: a killer never targeted, a stealth or ranged
-- kill, nameplates off. nil, why otherwise: "identities" (no player GUID: a pet, a creature, the
-- environment), "faction" (a unit of his shows no Horde player, or nothing proves it: an
-- Alliance race, a race of both factions, no answer from the game). hint: the name the death
-- recap gives him (no surname on Forever), used only when the game's lookup has none.
function Share.HordeOf(guid, hint)
	guid = Guid(guid)
	if not guid then return nil, "identities" end
	local s, key = Store(false), GuidKey(guid)
	local t = s and s.targets[s.aliases[key] or key]
	-- (His name as the game gives it first, so that a name a shared row wrote, which the game could
	-- not check then, is corrected now (ResolveTarget learns it); else the one held here, unless a
	-- row wrote it; else the recap's. One kept off by a reviewer's word may have no name here.)
	if type(t) == "table" and t.guid == guid then
		return Identity(Share.InfoName(guid) or (not t.wireName and t.name) or hint or t.name, guid)
	end
	local seen, contradicted = KnownHorde(Identity(nil, guid))
	if seen then return seen end
	if contradicted then return nil, "faction" end
	if type(GetPlayerInfoByGUID) ~= "function" then return nil, "faction" end
	local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, guid)
	if not ok or Secret(race) or not Share.HORDE_RACES[race] then return nil, "faction" end
	local ident = Identity(Share.InfoName(guid) or hint, guid)
	if not ident or not ident.name then return nil, "identity" end
	return ident
end

local function RateAllowed(now)
	for i = #rate, 1, -1 do if now - rate[i] >= Wanted.RATE_WINDOW then table.remove(rate, i) end end
	if #rate >= Wanted.RATE_MAX then return false end
	rate[#rate + 1] = now
	return true
end

local function Remember(s, id, fingerprint, at, seq)
	s.seen[id] = { at = at, seq = seq }
	s.seenOrder[#s.seenOrder + 1] = id
	s.recent[fingerprint] = at
	while #s.seenOrder > Wanted.MAX_SEEN do
		local old = table.remove(s.seenOrder, 1)
		if old and s.seen[old] and s.seen[old].seq <= seq - Wanted.MAX_SEEN then s.seen[old] = nil end
	end
	for key, seenAt in pairs(s.recent) do if at - (tonumber(seenAt) or 0) > 30 then s.recent[key] = nil end end
end

local function EvidenceId(kind, raw, killer, victim)
	local source = Clean(raw, 64) or tostring(math.floor(Clock()))
	return ns.Cut(table.concat({ kind, killer.guid or killer.name or "?", victim.guid or victim.name or "?", source }, ":"), 160)
end

-- The newest live evidence about this victim's death inside the death window: "replay" when it
-- names the same killer (two adapters, or one row read twice across a 3-second bucket),
-- "conflict" when it names another (one death never pays twice, nor two slayers).
local function SameDeath(s, killer, victim, now)
	for i = #s.evidence, 1, -1 do
		local e = s.evidence[i]
		if type(e) == "table" and not e.void and math.abs(now - (tonumber(e.at) or 0)) <= Wanted.DEATH_WINDOW
			and SameIdentity(Identity(e.victimName, e.victimGuid), victim) then
			return SameIdentity(Identity(e.killerName, e.killerGuid), killer) and "replay" or "conflict"
		end
	end
	return nil
end

-- A death at or before the newest one folded into the targets' base (Checkpoint): a shared row
-- about it could no longer take its place in the order of the deaths.
function Share.Late(s, at)
	local folded = Whole(s.foldedAt, 0, 4294967295)
	return folded ~= nil and at <= folded
end

-- An entry's last activity: its newest death (a bounty), its last claim, or when it entered.
function Share.LastActive(t)
	local at = math.max(tonumber(t.lastDeath) or 0, tonumber(t.openSince) or 0, tonumber(t.addedAt) or 0)
	local victims = type(t.victims) == "table" and t.victims or {}
	local last = victims[#victims]
	return math.max(at, type(last) == "table" and tonumber(last.at) or 0)
end

-- Room for one more Horde player on the list (MAX_TARGETS; those taken off are kept apart and
-- take no place). It never refuses one (Daniel: every Horde killer enters by himself): the least
-- active entry goes, with its rows: the oldest with nothing open and nothing it ever paid (a Horde
-- player killed once for no bounty), else the oldest of all by its last activity (Share.LastActive),
-- an open bounty too. What its claims paid stays with its Slayers, in the points no entry holds
-- any more (s.baseSlayers). Returns true.
function Share.MakeRoom(s)
	while true do
		local listed, drop, dropAt, spare, spareAt = 0, nil, nil, nil, nil
		for key, t in pairs(s.targets) do
			if t.active == true then
				listed = listed + 1
				local at = Share.LastActive(t)
				if not drop or at < dropAt or at == dropAt and key < drop then drop, dropAt = key, at end
				local paid = type(t.paid) == "table" and next(t.paid) ~= nil
				for _, c in ipairs(type(t.claims) == "table" and t.claims or {}) do if (tonumber(c.points) or 0) > 0 then paid = true break end end
				if (tonumber(t.current) or 0) == 0 and not paid and (not spare or at < spareAt or at == spareAt and key < spare) then
					spare, spareAt = key, at
				end
			end
		end
		if listed < Wanted.MAX_TARGETS or not drop then return true end
		local key = spare or drop
		for _, p in pairs(type(s.targets[key].paid) == "table" and s.targets[key].paid or {}) do Share.AddPaid(s, s.baseSlayers, p) end
		Share.Drop(s, key)
	end
end

-- One kill or death into this client's ledger, its entry made when the Horde player has none.
-- opts: zone, precision (where this client's player stood: its own rows only); horde = "killer"
-- or "victim", the side whose Horde faction the caller proved (Share.HordeOf, or the sharing
-- member's client: Share.Take), the side whose entry the row may make; own = this client's own
-- death or killing blow (shared on the channel by its caller); peer = a row another member
-- shared: from (his server-stamped name), digest, id, at and month as he sent them; wire = the
-- Horde player's name is that row's, which this client's game could not check (Share.Take).
local function RecordKill(kind, rawId, killer, victim, opts)
	opts = opts or {}
	killer, victim = Identity(killer), Identity(victim)
	local peer = opts.peer == true
	local hordeSide = opts.horde == "killer" and killer or opts.horde == "victim" and victim or nil
	local olympianSide = opts.horde == "killer" and victim or opts.horde == "victim" and killer or nil
	-- Both sides must be players the row names and identifies (Guid takes Player- GUIDs only): a
	-- pet, a creature or the environment never credits a kill, and a pet or an NPC that merely
	-- carries a listed target's name never matches that target. (Prune keeps no other row.) A
	-- shared row's Olympian side is its sender by the name the server stamps: his GUID only where
	-- this client proved it is his (Share.Take).
	if not killer or not victim or not killer.name or not victim.name
		or not killer.guid and not (peer and olympianSide == killer) or not victim.guid and not (peer and olympianSide == victim) then
		stats.refused = stats.refused + 1
		return false, "identities"
	end
	local s = Store(true)
	if not s then return false, "store" end
	-- (wire: a side whose name is only a shared row's word: its Olympian, named by the server,
	-- and its Horde player where this client's game could not check his name, opts.wire. Such a
	-- name finds no entry pinned to a GUID, and teaches none: ResolveTarget.)
	local killerWire, victimWire = peer, peer
	if hordeSide == killer then killerWire = opts.wire == true elseif hordeSide == victim then victimWire = opts.wire == true end
	-- Resolve first without learning anything: a rejected/forged row must not be able to pin a
	-- new GUID or spelling onto a listed target merely by naming it.
	local killerTarget = ResolveTarget(s, killer, false, killerWire)
	local victimTarget = ResolveTarget(s, victim, false, victimWire)
	if killerTarget and victimTarget then
		stats.refused = stats.refused + 1
		return false, "ambiguous"
	end
	local now = peer and opts.at or math.floor(Clock())
	-- 1.2.3 (Daniel: "that list should never have existed"): a Horde player nobody listed enters
	-- by himself, from the proven side of the row. Only a row without that proof (the combat-log
	-- adapter's, CaptureCombatLog) still needs one side already here.
	local fresh
	if not killerTarget and not victimTarget then
		if not hordeSide then
			stats.refused = stats.refused + 1
			return false, "unlisted"
		end
		-- (Every proven side carries his GUID, and his entry is his GUID's alone: another entry
		-- under his name, pinned to another GUID, is another character (a made-up GUID a shared row
		-- named, a rename, a typed listing), and never keeps him off. Before, it did: "identity".)
		fresh = { key = hordeSide.key, name = hordeSide.name, realm = hordeSide.realm, guid = hordeSide.guid, active = true,
			addedAt = now, addedBy = peer and opts.from or CleanName(ns.me), source = peer and "shared" or kind, current = 0,
			lifetimeKills = 0, cycle = 1, openSince = now, victims = {}, claims = {}, victimOverflow = 0 }
		if opts.horde == "killer" then killerTarget = fresh else victimTarget = fresh end
	end
	local action, target, olympian
	if killerTarget then action, target, olympian = "bounty", killerTarget, victim
	else action, target, olympian = "claim", victimTarget, killer end
	-- The proven Horde side is the one the row is about: an Olympian found on the list instead is
	-- no Horde player's entry.
	if opts.horde and (opts.horde == "killer") ~= (action == "bounty") then
		stats.refused = stats.refused + 1
		return false, "ambiguous"
	end
	if not target.active then
		stats.refused = stats.refused + 1
		return false, "removed"
	end
	-- (A shared row's sender was verified as a member when it was taken: Share.Take.)
	if not peer and not VerifiedOlympian(olympian) then
		stats.refused = stats.refused + 1
		return false, "olympus"
	end
	if action == "claim" and target.current > 0 and not ResolveSlayer(s, killer, false, false)
		and Count(s.slayers) >= Wanted.MAX_SLAYERS then return false, "slayers" end
	local id = peer and opts.id or EvidenceId(kind, rawId, killer, victim)
	local fingerprint = table.concat({ killer.guidKey or killer.nameKey, victim.guidKey or victim.nameKey, tostring(math.floor(now / 3)) }, ">")
	if s.seen[id] or s.recent[fingerprint] and math.abs(now - s.recent[fingerprint]) <= 5 then
		stats.replay = stats.replay + 1
		return false, "replay"
	end
	local death = SameDeath(s, killer, victim, now)
	if death == "replay" then stats.replay = stats.replay + 1 return false, "replay" end
	if death == "conflict" then stats.conflict = stats.conflict + 1 return false, "conflict" end
	if peer and Share.Late(s, now) then stats.refused = stats.refused + 1 return false, "late" end
	if not peer and not RateAllowed(now) then stats.refused = stats.refused + 1 return false, "rate" end
	if fresh then
		Share.MakeRoom(s)
		s.targets[fresh.key] = fresh
		if hordeSide.guidKey then s.aliases[hordeSide.guidKey] = fresh.key end
		Share.Name(s, fresh, hordeSide, opts.wire == true)
	end
	local learned
	if action == "bounty" then learned = ResolveTarget(s, killer, true, killerWire)
	else learned = ResolveTarget(s, victim, true, victimWire) end
	if not learned or learned ~= target then
		if fresh and s.targets[fresh.key] == fresh then Share.Drop(s, fresh.key) end
		return false, "identity"
	end
	target = learned
	if #s.evidence >= Wanted.MAX_EVIDENCE then Checkpoint(s) end
	s.seq = s.seq + 1
	local e = { id = id, seq = s.seq, at = now, month = peer and opts.month or MonthNow(), kind = kind, action = action,
		targetKey = target.key, killerName = killer.name, killerGuid = killer.guid, victimName = victim.name, victimGuid = victim.guid,
		zone = opts.zone, precision = opts.precision, from = peer and opts.from or CleanName(ns.me),
		peer = peer or nil, own = opts.own == true or nil }
	e.digest = peer and opts.digest or Digest(table.concat({ e.id, e.at, e.kind, e.action, e.killerGuid or "", e.victimGuid or "" }, "|"))
	Remember(s, id, fingerprint, now, e.seq)
	-- In the order of the deaths: a shared row may come after a later one (a relay, a catch-up),
	-- and then the totals are built again, so that every client holding the same rows counts them
	-- the same.
	local at = #s.evidence + 1
	while at > 1 and (tonumber(s.evidence[at - 1].at) or 0) > now do at = at - 1 end
	table.insert(s.evidence, at, e)
	if at < #s.evidence then
		Rebuild(s)
	elseif not ApplyEvidence(s, e) then
		e.void = true
		Rebuild(s)
		return false, "bounds"
	end
	stats.accepted = stats.accepted + 1
	Changed()
	return true, e
end

-- The combat-log adapter accepts only PARTY_KILL, whose payload names both sides. UNIT_DIED and
-- damage rows never identify a killer reliably and are intentionally ignored. Nothing registers
-- it on Forever (its combat log is restricted: see the registrations at the end); it stays the
-- ledger's adapter for a client that allows the combat log, and the tests'. Its rows carry no
-- faction proof, so one of their sides must already have an entry ("unlisted" otherwise), and
-- they are never shared.
function Wanted.CaptureCombatLog(...)
	local a = { ... }
	if #a == 0 and type(CombatLogGetCurrentEventInfo) == "function" then
		local ok, values = pcall(function() return { CombatLogGetCurrentEventInfo() } end)
		if not ok then return false, "api" end
		a = values
	end
	local timestamp, subevent, sourceGuid, sourceName, destGuid, destName = a[1], a[2], a[4], a[5], a[8], a[9]
	if Secret(timestamp, subevent, sourceGuid, sourceName, destGuid, destName) then return false, "secret" end
	if subevent ~= "PARTY_KILL" then return false, "event" end
	if not sourceGuid or not sourceName or not destGuid or not destName then return false, "identities" end
	return RecordKill("PARTY_KILL", tostring(timestamp or ""), { name = sourceName, guid = sourceGuid },
		{ name = destName, guid = destGuid }, { zone = Zone(), precision = "approximate" })
end

-- Native frame event, distinct from the CLEU subevent: UnitDocumentation.lua, PartyKill (Forever
-- 1.60.1's own API documentation): attackerGUID and targetGUID, nothing else, both secret while
-- unit identity is restricted (an unfinished PvP match). Only our own killing blow counts: another
-- party member's is his to share, and a pet's GUID is not ours. The victim needs no listing: his
-- Horde faction is proven here (Share.HordeOf) and the row makes his entry, then goes to every
-- member (Share.Send). Returns true and the row, or false and why, and the Horde player's name.
function Share.PartyKill(attackerGUID, targetGUID)
	if Secret(attackerGUID, targetGUID) then return false, "secret" end
	local attacker, victim = Guid(attackerGUID), Guid(targetGUID)
	if not attacker or not victim then return false, "identities" end
	local mine = UnitIdentity("player")
	if not mine or mine.guid ~= attacker then return false, "attacker" end
	if not ns.IsMember or ns.IsMember() ~= true then return false, "olympus" end
	if ns.faction == "Horde" then return false, "faction" end
	if InInstance() then return false, "instance" end
	local horde, why = Share.HordeOf(victim)
	if not horde then return false, why end
	local ok, e = RecordKill("PARTY_KILL", "native:" .. tostring(math.floor(Clock())), mine, horde,
		{ zone = Zone(), precision = "approximate", horde = "victim", own = true })
	if ok then Share.Send(e) end
	return ok, e, horde.name
end

function Wanted.CapturePartyKill(attackerGUID, targetGUID)
	local ok, e, who = Share.PartyKill(attackerGUID, targetGUID)
	-- (/oly wanted status: a kill of a player only, or a hidden one (a PvP match); every creature a
	-- party member kills fires it too.)
	if Secret(attackerGUID, targetGUID) or Guid(targetGUID) then
		Share.Note("kill", ok, e, who or (not ok and Share.InfoName(Guid(targetGUID))) or nil)
	end
	return ok, e
end

-- Forever's last-death reader: C_DeathRecap without a recap ID, as the game's own death dialog
-- and feedback form read it (GameDialogDefs.lua, Blizzard_PTRFeedback_Events.lua: the client's
-- UI source, 1.60.1). Its rows come newest first, and the first is the one that killed
-- (Blizzard_DeathRecap.lua: causedDeath = i == 1). HeadHunter's Forever probe (build 69913,
-- https://github.com/GudaAddons/HeadHunter/blob/main/Detection/ForeverDeaths.lua) gives the
-- rest: sourceName "Given-Realm" (no surname), sourceFlags, overkill 0 or more on the killing
-- blow and -1 on the others, timestamp in the server's seconds. The killing blow is the first
-- row with overkill 0 or more; it counts when it is recent, a damage event, a hostile player's
-- (flags 0x440, where the row has flags), with a player GUID whose Horde faction this client
-- proves (Share.HordeOf): no target, nameplate or listing is needed. Never the latest damage, a
-- pet's possible owner, or a death in an instance (a battleground, an arena). The victim is our
-- own verified player unit. Returns true and the row, or false and why, and the killer's name.
local function ReadSelfDeathRecap()
	local recap = C_DeathRecap
	if type(recap) ~= "table" or type(recap.HasRecapEvents) ~= "function" or type(recap.GetRecapEvents) ~= "function" then return false, "recap" end
	local hasOK, has = pcall(recap.HasRecapEvents)
	if not hasOK or Secret(has) or has ~= true then return false, "recap" end
	local readOK, events = pcall(recap.GetRecapEvents)
	if not readOK or type(events) ~= "table" then return false, "recap" end
	local mine = UnitIdentity("player")
	local deadOK, dead = pcall(function() return UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") end)
	if not mine or not deadOK or Secret(dead) or dead ~= true then return false, "alive" end
	if ns.faction == "Horde" then return false, "faction" end
	if InInstance() then return false, "instance" end
	local now = math.floor(Clock())
	for i = 1, #events do
		local row = events[i]
		if type(row) == "table" then
			if Secret(row.sourceGUID, row.sourceName, row.sourceFlags, row.event, row.overkill, row.timestamp) then return false, "secret" end
			if Whole(row.overkill, 0, 2147483647) then
				local stampOK, stamp = pcall(tonumber, row.timestamp)
				local at = stampOK and stamp and stamp >= now - Wanted.DEATH_WINDOW and stamp <= now + 1 and stamp or nil
				local name = Clean(row.sourceName, 72)
				if not at then return false, "stale", name end
				if type(row.event) ~= "string" or not row.event:match("_DAMAGE$") then return false, "event", name end
				local flags = row.sourceFlags
				if flags ~= nil and not (Whole(flags, 0, 2147483647) and bit.band(flags, 0x440) == 0x440) then return false, "flags", name end
				local horde, why = Share.HordeOf(row.sourceGUID, row.sourceName)
				if not horde then return false, why, name end
				local ok, e = RecordKill("SELF_DEATH", "native:" .. tostring(at), horde, mine,
					{ zone = Zone(), precision = "approximate", horde = "killer", own = true })
				if ok then Share.Send(e) end
				return ok, e, horde.name
			end
		end
	end
	return false, "fatal"
end

-- A reviewer voids one row he finds wrong (the King, a signed High Councillor or the author:
-- Wanted.CanRemove), with a reason: here, and on every client through his word (WV), as long as
-- the row is still live (not yet folded into the base: Checkpoint).
function Wanted.Correct(id, reason)
	if not Wanted.CanRemove() then return false, "access" end
	id = Clean(id, 160)
	if not id then return false, "id" end
	local s = Store(false)
	for _, e in ipairs(s and s.evidence or {}) do
		if e.id == id and not e.void then
			e.void, e.correctedAt, e.correctedBy, e.correction = true, math.floor(Clock()), CleanName(ns.me), Clean(reason, 80)
			Audit(s, "correct", e.targetKey, id)
			Share.KeepVoid(s, e.from, e.digest, e.correctedAt)
			Rebuild(s)
			stats.corrected = stats.corrected + 1
			if e.from and e.digest then Share.SendMark("V", e.from, e.digest) end
			Changed()
			return true
		end
	end
	return false, "expired"
end

-- A voided shared row remembered (VOIDS_MAX, the oldest go), so that a copy heard later is
-- refused too: [folded sender#digest] = { at = when, from, digest }.
function Share.KeepVoid(s, from, digest, at)
	from = CleanName(from)
	if not from or type(digest) ~= "string" then return end
	s.voids[ns.Fold(from) .. "#" .. digest] = { at = Whole(at, 0, 4294967295) or 0, from = from, digest = digest }
	local n = Count(s.voids)
	while n > Wanted.VOIDS_MAX do
		local oldest
		for key, v in pairs(s.voids) do if not oldest or (v.at or 0) < (s.voids[oldest].at or 0) then oldest = key end end
		s.voids[oldest], n = nil, n - 1
	end
end

local function PublicTarget(t)
	if type(t) ~= "table" then return nil end
	return { key = t.key, name = t.name, realm = t.realm, guid = t.guid, active = t.active == true, addedAt = t.addedAt,
		addedBy = t.addedBy, source = t.source, removedAt = t.removedAt, removedBy = t.removedBy,
		current = t.current or 0, lifetimeKills = t.lifetimeKills or 0, cycle = t.cycle or 1,
		openSince = t.openSince, lastDeath = t.lastDeath, lastSighting = t.lastSighting and CopyList({ t.lastSighting }, 1)[1] or nil,
		victimOverflow = t.victimOverflow or 0, victims = CopyList(t.victims, Wanted.MAX_VICTIMS), claims = CopyList(t.claims, Wanted.MAX_CLAIMS) }
end

function Wanted.Target(value, guid, realm)
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	return PublicTarget(t)
end

function Wanted.Targets(activeOnly)
	local s, out = Store(false), {}
	for _, t in pairs(s and s.targets or {}) do if not activeOnly or t.active then out[#out + 1] = PublicTarget(t) end end
	table.sort(out, function(a, b)
		if a.active ~= b.active then return a.active end
		if a.current ~= b.current then return a.current > b.current end
		if a.lifetimeKills ~= b.lifetimeKills then return a.lifetimeKills > b.lifetimeKills end
		return tostring(a.name or a.guid or a.key) < tostring(b.name or b.guid or b.key)
	end)
	return out
end

local function Ranked(rows, month)
	local out = {}
	for _, r in pairs(type(rows) == "table" and rows or {}) do
		local points = month and (type(r.months) == "table" and r.months[month] or 0) or r.total
		if (tonumber(points) or 0) > 0 then
			out[#out + 1] = { key = r.key, name = r.name, guid = r.guid, points = points,
				claims = month and (r.monthClaims and r.monthClaims[month] or 0) or r.claims or 0,
				reachedAt = month and (r.monthAt and r.monthAt[month] or 0) or r.reachedAt or 0, lastAt = r.lastAt or 0 }
		end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.key < b.key
	end)
	for i, r in ipairs(out) do r.place = i end
	return out
end

function Wanted.Rankings(month)
	local s = Store(false)
	month = tonumber(month) or MonthNow()
	return { month = Ranked(s and s.slayers or {}, month), all = Ranked(s and s.slayers or {}, nil), monthNo = month }
end

---------------------------------------------------------------------------
-- The signed global top three
---------------------------------------------------------------------------

local function Scope()
	return Digest(tostring(ns.group or ns.realm or "?") .. "|" .. tostring(ns.faction or "?"))
end

local function SameName(a, b)
	return type(a) == "string" and type(b) == "string" and ns.Fold(ns.FullName(a)) == ns.Fold(ns.FullName(b))
end

-- Authority is derived every time from the current signed/pinned state. Preview/debug views never
-- count. Revoking the signed council list therefore removes a held snapshot on the next read.
function Wanted.CanPublish(name)
	name = CleanName(name)
	if not name or not ns.IsMember or ns.IsMember() ~= true then return false end
	local WC = ns.WatchChat
	if WC and WC.PowersBarred and WC.PowersBarred(name) then return false end
	local W = ns.Workshop
	if W and W.IsAuthorName and W.IsAuthorName(name) == true then return true end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) == true then return true end
	if ns.IsHighCouncillor and ns.IsHighCouncillor(name) == true then return true end
	return false
end

local function WireGuid(guid)
	guid = Guid(guid)
	if not guid then return nil end
	local server, id = guid:match("^Player%-(%d+)%-(%x+)$")
	return server .. "." .. id:lower()
end

local function GameGuid(wire)
	if type(wire) ~= "string" or #wire > 24 then return nil end
	local server, id = wire:match("^(%d+)%.(%x+)$")
	if not server or #server > 7 or #id < 8 or #id > 16 or id:find("[A-F]") then return nil end
	return Guid("Player-" .. server .. "-" .. id)
end

local function CanonicalRows(rows)
	local out, seen = {}, {}
	for _, row in ipairs(type(rows) == "table" and rows or {}) do
		local guid = Guid(type(row) == "table" and row.guid)
		local points = Whole(type(row) == "table" and row.points, 1, Wanted.MAX_POINTS)
		local claims = Whole(type(row) == "table" and row.claims, 0, Wanted.MAX_POINTS)
		local reachedAt = Whole(type(row) == "table" and row.reachedAt, 0, 4294967295)
		if not guid or not points or not claims or not reachedAt or seen[guid] then return nil, "rows" end
		seen[guid] = true
		out[#out + 1] = { key = GuidKey(guid), guid = guid, points = points, claims = claims, reachedAt = reachedAt }
		if #out > Wanted.GLOBAL_ROWS then return nil, "rows" end
	end
	table.sort(out, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.reachedAt ~= b.reachedAt then return a.reachedAt < b.reachedAt end
		return a.guid < b.guid
	end)
	return out
end

local function RowsText(rows)
	local out = {}
	for i, row in ipairs(rows) do
		local wire = WireGuid(row.guid)
		if not wire then return nil end
		out[i] = table.concat({ wire, row.points, row.claims, row.reachedAt }, ":")
	end
	return #out > 0 and table.concat(out, ",") or "-"
end

local function ReadRows(text)
	if text == "-" then return {} end
	if type(text) ~= "string" or text == "" or #text > 256 then return nil, "rows" end
	local rows = {}
	for item in text:gmatch("[^,]+") do
		local wire, points, claims, reachedAt = item:match("^([^:]+):(%d+):(%d+):(%d+)$")
		rows[#rows + 1] = { guid = GameGuid(wire), points = tonumber(points), claims = tonumber(claims), reachedAt = tonumber(reachedAt) }
	end
	return CanonicalRows(rows)
end

local function AuthorityWeight(name)
	local W = ns.Workshop
	if W and W.IsAuthorName and W.IsAuthorName(name) == true then return 3 end
	if ns.IsKingCharacter and ns.IsKingCharacter(name) == true then return 2 end
	return 1
end

-- Between publishers the newer word wins (its issue time), then the higher role, then a fixed
-- name order; the epoch and sequence come last, and one publisher's own words also follow his
-- pins (NewerSnapshot). (It was the epoch first: a publisher whose key generation began earlier,
-- the King say, could then never replace or revoke the word of a councillor who began later.)
local function Order(snapshot)
	return { snapshot.issued, AuthorityWeight(snapshot.issuer), ns.Fold(snapshot.issuer), snapshot.epoch, snapshot.seq }
end

local function CompareOrder(a, b)
	if not b then return 1 end
	for i = 1, 5 do
		if a[i] ~= b[i] then
			if i == 3 then return a[i] < b[i] and 1 or -1 end -- deterministic name tie-break
			return a[i] > b[i] and 1 or -1
		end
	end
	return 0
end

local function Fresh(snapshot, now)
	now = now or math.floor(Clock())
	return snapshot.issued <= now + Wanted.GLOBAL_SKEW and snapshot.expires >= now
		and snapshot.epoch <= snapshot.issued + Wanted.GLOBAL_SKEW
		and snapshot.expires > snapshot.issued and snapshot.expires - snapshot.issued <= Wanted.GLOBAL_LIFE
end

-- The saved copy of the word shown (this realm group and faction's store): its text, its issuer,
-- when it came, and the publishers' pins as they were then. Only RestoreGlobal reads it.
local function SaveGlobal(snapshot)
	local s = Store(true)
	if not s then return end
	s.global = { text = snapshot.text, issuer = snapshot.issuer, at = math.floor(Clock()), relay = snapshot.relay }
	local heads = {}
	for who, h in pairs(publisherHeads) do heads[who] = { epoch = h.epoch, seq = h.seq, pk64 = h.pk64 } end
	s.globalHeads = heads
end

local function ForgetGlobal(text)
	local s = Store(false)
	if s and type(s.global) == "table" and (text == nil or s.global.text == text) then s.global, s.globalHeads = nil, nil end
end

local function ClearGlobal(expired)
	local held = authenticatedGlobal
	authenticatedGlobal = nil
	-- The floor and per-publisher key pins protect only a currently valid word. Keeping them
	-- after that word expires, leaves this realm/faction, or loses its authority would let a
	-- revoked publisher strand every legitimate replacement until /reload.
	globalFloor, publisherHeads = nil, {}
	-- An expired word leaves the saved data too. One whose issuer does not hold the role now
	-- (the council's list may not have come yet) or of another realm group stays saved for
	-- RestoreGlobal to look at again; it shows nothing meanwhile.
	if expired and held then ForgetGlobal(held.text) end
	if held then Changed() end
	return held ~= nil
end

local function CurrentGlobal()
	local held = authenticatedGlobal
	if held then
		if not Fresh(held) then ClearGlobal(true)
		elseif not Wanted.CanPublish(held.issuer) or held.scope ~= Scope() then ClearGlobal(false) end
	end
	return authenticatedGlobal
end

-- A fresh own-guild roster, or independently verified federation membership; a guild claim
-- alone (VerifiedLevel's numeric fallback) is not evidence authority. guild (1.2.3): the guild a
-- shared row says its sender speaks for, when this client heard none of his own (M.GuildOf).
local function EvidenceMember(sender, guild)
	local R = ns.Roster
	if R and type(R.Fresh) == "function" and type(R.RankOf) == "function" then
		local ok, fresh = pcall(R.Fresh)
		if ok and fresh and R.RankOf(sender) ~= nil then return true end
	end
	local C, M = ns.Channels, ns.Moderation
	if type(C) ~= "table" or C.missing or type(C.VerifiedLevel) ~= "function" then return false end
	guild = M and M.GuildOf and M.GuildOf(sender) or guild
	if type(guild) ~= "string" or guild == "" or not (ns.IsFederation and ns.IsFederation(guild)) then return false end
	local ok, level, verified = pcall(C.VerifiedLevel, sender, guild)
	return ok and type(level) == "number" and level >= 1 and verified == true
end

-- Whether a player GUID is the sender's character: true or false when this client can name it
-- (a unit, or the game's cache of seen players), nil when it cannot.
local function GuidIsSender(guid, sender)
	local who = ns.Fold(ns.FullName(sender))
	local self = UnitIdentity("player")
	if self and self.guid == guid then return ns.Fold(ns.FullName(self.name)) == who end
	if type(UnitTokenFromGUID) == "function" then
		local ok, token = pcall(UnitTokenFromGUID, guid)
		if ok and type(token) == "string" and not Secret(token) then
			local unit = UnitIdentity(token)
			if unit and unit.guid == guid then return ns.Fold(ns.FullName(unit.name)) == who end
		end
	end
	-- Debts.InfoName is the existing guarded server GUID lookup (including clients that split
	-- character surnames into the realm field); it does not accept a packet's asserted name.
	local D = ns.Debts
	if D and type(D.InfoName) == "function" then
		local ok, name = pcall(D.InfoName, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) then return ns.Fold(ns.FullName(name)) == who end
	end
	if type(GetPlayerInfoByGUID) == "function" then
		local ok, _, _, _, _, _, name, realm = pcall(GetPlayerInfoByGUID, guid)
		if ok and type(name) == "string" and name ~= "" and not Secret(name) and not Secret(realm) then
			return ns.Fold(ns.FullName(name, type(realm) == "string" and realm ~= "" and realm or nil)) == who
		end
	end
	return nil
end

-- 1.2.3: the top three this client would sign, as its own Slayers board counts it (every member's
-- shared kills and deaths it holds: Share.Take), all time, by verified GUID: a slayer this client
-- knows by his name alone (a member of another guild whose GUID it could not prove) is left out,
-- never awarded a frame by a name. No review: the rows counted as they came.
function Wanted.SignableRankings()
	local rows = {}
	for _, r in ipairs(Wanted.Rankings().all) do
		if Guid(r.guid) and #rows < Wanted.GLOBAL_ROWS then
			rows[#rows + 1] = { guid = r.guid, points = math.min(r.points, Wanted.MAX_POINTS), claims = r.claims or 0, reachedAt = r.reachedAt or 0 }
		end
	end
	return CanonicalRows(rows) or {}
end

-- The Slayers ranked among the top three's places whom this client knows by name only, left out
-- of what it would sign (the frames page names them).
function Share.Unsignable()
	local out, signable = {}, 0
	for _, r in ipairs(Wanted.Rankings().all) do
		if signable >= Wanted.GLOBAL_ROWS or #out >= Wanted.GLOBAL_ROWS then break end
		if Guid(r.guid) then signable = signable + 1 else out[#out + 1] = r end
	end
	return out
end

local function ParseSnapshot(sender, text, relay)
	if type(text) ~= "string" or #text > 1200 then return nil, "size" end
	local version, scope, issuer, epoch, seq, issued, expires, rowsText, pk64, sig64 =
		text:match("^WY~(%d+)~(%x+)~([^~]+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)~([^~]+)$")
	epoch, seq, issued, expires = tonumber(epoch), tonumber(seq), tonumber(issued), tonumber(expires)
	issuer = CleanName(issuer)
	if version ~= "1" or not issuer or not Whole(epoch, 1, Wanted.GLOBAL_MAX_EPOCH) or not Whole(seq, 1, Wanted.GLOBAL_MAX_SEQ)
		or not Whole(issued, 0, 4294967295) or not Whole(expires, 0, 4294967295) then return nil, "shape" end
	if scope ~= Scope() then return nil, "scope" end
	if not Wanted.CanPublish(issuer) or not Wanted.CanPublish(sender) or (not relay and not SameName(sender, issuer)) then return nil, "authority" end
	local rows, why = ReadRows(rowsText)
	if not rows then return nil, why end
	local D, Ed = ns.Debts, ns.Ed25519
	local pk = D and D.UnB64 and D.UnB64(pk64) or nil
	local sig = D and D.UnB64 and D.UnB64(sig64) or nil
	if not pk or #pk ~= 32 or not sig or #sig ~= 64 or not Ed or not Ed.ValidPublicKey or not Ed.ValidPublicKey(pk) then return nil, "signature" end
	local signed = table.concat({ "OLYW1", scope, issuer, epoch, seq, issued, expires, rowsText }, "|")
	return { scope = scope, issuer = issuer, epoch = epoch, seq = seq, issued = issued, expires = expires,
		rows = rows, rowsText = rowsText, pk = pk, pk64 = pk64, sig = sig, signed = signed, text = text, relay = relay and CleanName(sender) or nil }
end

-- These anchors are learned only after a direct issuer word's signature was verified. Neither
-- another reviewer's role nor a relay's globalHeads can introduce or rotate an issuer key.
function Wanted.IndependentlyPinned(snapshot)
	local s = Store(false)
	local pin = s and type(s.globalDirectPins) == "table" and s.globalDirectPins[ns.Fold(snapshot.issuer)]
	return type(pin) == "table" and Whole(pin.epoch, 1, Wanted.GLOBAL_MAX_EPOCH) == snapshot.epoch and pin.pk64 == snapshot.pk64
end

function Wanted.PinDirectGlobal(snapshot)
	if snapshot.relay then return false end
	local s = Store(true)
	if not s then return false end
	if type(s.globalDirectPins) ~= "table" then s.globalDirectPins = {} end
	local pins, key = s.globalDirectPins, ns.Fold(snapshot.issuer)
	if not pins[key] and Count(pins) >= Wanted.GLOBAL_DIRECT_PINS_MAX then
		local oldest, at
		for k, p in pairs(pins) do
			local t = type(p) == "table" and tonumber(p.at) or 0
			if not at or (t or 0) < at then oldest, at = k, t or 0 end
		end
		if oldest then pins[oldest] = nil end
	end
	pins[key] = { epoch = snapshot.epoch, pk64 = snapshot.pk64, at = math.floor(Clock()) }
	return true
end

local function NewerSnapshot(snapshot)
	local head = publisherHeads[ns.Fold(snapshot.issuer)]
	if head then
		if snapshot.epoch < head.epoch then return false, "rollback" end
		if snapshot.epoch == head.epoch and snapshot.seq <= head.seq then return false, "replay" end
		if snapshot.epoch == head.epoch and snapshot.pk64 ~= head.pk64 then return false, "key" end
	end
	if CompareOrder(Order(snapshot), globalFloor) <= 0 then return false, "rollback" end
	return true
end

-- The order (Order) of the word a WY body carries, read from its fields, or nil.
local function BodyOrder(body)
	if type(body) ~= "string" then return nil end
	local issuer, epoch, seq, issued = body:match("^WY~%d+~%x+~([^~]+)~(%d+)~(%d+)~(%d+)~")
	if not issuer then return nil end
	return Order({ issued = tonumber(issued), issuer = issuer, epoch = tonumber(epoch), seq = tonumber(seq) })
end

-- A word this client checked that is newer than the one published here replaced ours for good:
-- ours is not repeated any more, after a reload neither. (A client that never heard the newer
-- word would take ours, the older, from the repeat: an issuer's revocation undone by another's
-- older word.)
local function NoteReplaced(snapshot)
	local p = publishedGlobal
	local mine = p and not p.replaced and BodyOrder(p.body)
	if not mine or CompareOrder(Order(snapshot), mine) <= 0 then return end
	p.replaced = true
	local last = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
	if type(last) == "table" and last.body == p.body then last.replaced = true end
end

local function Install(snapshot)
	globalFloor = Order(snapshot)
	authenticatedGlobal = snapshot
	NoteReplaced(snapshot)
	Changed()
	if ns.After then
		local held = snapshot
		ns.After(math.max(1, snapshot.expires - math.floor(Clock()) + 1), "wanted global expiry", function()
			if authenticatedGlobal == held and not Fresh(held) then ClearGlobal(true) end
		end)
	end
	return true
end

local function AcceptSnapshot(snapshot)
	-- Recheck every mutable trust input after the asynchronous Ed25519 job. In particular, a
	-- realm/faction transition while verification yielded must never install the old scope.
	if snapshot.scope ~= Scope() or not Fresh(snapshot) or not Wanted.CanPublish(snapshot.issuer) then return false, "stale" end
	if snapshot.relay and (not Wanted.CanPublish(snapshot.relay) or not Wanted.IndependentlyPinned(snapshot)) then return false, "unanchored" end
	local ok, why = NewerSnapshot(snapshot)
	if not ok then return false, why end
	publisherHeads[ns.Fold(snapshot.issuer)] = { epoch = snapshot.epoch, seq = snapshot.seq, pk64 = snapshot.pk64 }
	stats.globalAccepted = stats.globalAccepted + 1
	Wanted.PinDirectGlobal(snapshot)
	Install(snapshot)
	SaveGlobal(snapshot)
	return true
end

-- After a load, and again while no word is shown (a change of authority or realm group): the
-- saved word comes back only once its signature holds again under the key pinned for its
-- issuer, unexpired, of this realm group and faction, from someone who holds the role now. Its
-- order and pins hold while the signature is checked, so a live replay of an older word cannot
-- slip in meanwhile; a newer live word simply wins. Nothing else saved ever shows a frame.
local function RestoreGlobal()
	if authenticatedGlobal or restoring then return false, "held" end
	local s = Store(false)
	local saved = s and s.global
	if type(saved) ~= "table" then return false, "none" end
	local snapshot, why = ParseSnapshot(saved.issuer, saved.text)
	if not snapshot then
		-- Not a role holder here now, or another realm group's word: kept for a later look.
		if why ~= "authority" and why ~= "scope" then ForgetGlobal() end
		return false, why
	end
	if not Fresh(snapshot) then ForgetGlobal() return false, "stale" end
	-- A legacy saved word came directly from its issuer (the old protocol admitted no relays).
	-- Retain provenance for new relayed copies so restoration cannot turn them into direct pins.
	snapshot.relay = type(saved.relay) == "string" and saved.relay or nil
	if snapshot.relay and not Wanted.IndependentlyPinned(snapshot) then return false, "unanchored" end
	local pins = {}
	for who, h in pairs(type(s.globalHeads) == "table" and s.globalHeads or {}) do
		local epoch = type(h) == "table" and Whole(h.epoch, 1, Wanted.GLOBAL_MAX_EPOCH)
		local seq = type(h) == "table" and Whole(h.seq, 1, Wanted.GLOBAL_MAX_SEQ)
		if type(who) == "string" and epoch and seq and type(h.pk64) == "string" then pins[who] = { epoch = epoch, seq = seq, pk64 = h.pk64 } end
	end
	local pin = pins[ns.Fold(snapshot.issuer)]
	if not pin or pin.epoch ~= snapshot.epoch or pin.seq ~= snapshot.seq or pin.pk64 ~= snapshot.pk64 then
		ForgetGlobal()
		return false, "key"
	end
	local floor = Order(snapshot)
	globalFloor, publisherHeads, restoring = floor, pins, snapshot
	local function Done(valid)
		if restoring ~= snapshot then return false, "superseded" end
		restoring = nil
		restoreChecked[snapshot.text] = valid
		local current = not authenticatedGlobal and globalFloor == floor
		if valid and current and snapshot.scope == Scope() and Fresh(snapshot) and Wanted.CanPublish(snapshot.issuer)
			and (not snapshot.relay or Wanted.IndependentlyPinned(snapshot)) then
			stats.globalRestored = stats.globalRestored + 1
			Wanted.PinDirectGlobal(snapshot)
			return Install(snapshot)
		end
		if not valid then ForgetGlobal(snapshot.text) stats.globalRefused = stats.globalRefused + 1 end
		if current then globalFloor, publisherHeads = nil, {} end
		return false, valid and "stale" or "signature"
	end
	if restoreChecked[snapshot.text] ~= nil then return Done(restoreChecked[snapshot.text]) end
	local Ed = ns.Ed25519
	local started = Ed and Ed.Run and Ed.Verify and not (Ed.Busy and Ed.Busy() >= 40) and Ed.Run(function()
		return Ed.Verify(snapshot.pk, snapshot.signed, snapshot.sig)
	end, function(jobOk, valid) Done(jobOk and valid == true) end)
	if not started then
		if restoring == snapshot then restoring, globalFloor, publisherHeads = nil, nil, {} end
		return false, "busy"
	end
	return true, "pending"
end
Wanted.RestoreGlobal = RestoreGlobal

function Wanted.HandleGlobalSnapshot(dist, sender, text, relay)
	if dist ~= "CHANNEL" then stats.globalRefused = stats.globalRefused + 1 return false, "lane" end
	CurrentGlobal() -- expiry/revocation must release its ordering floor before a replacement arrives
	local snapshot, why = ParseSnapshot(sender, text, relay)
	if not snapshot or not Fresh(snapshot) then stats.globalRefused = stats.globalRefused + 1 return false, why or "stale" end
	if relay and not Wanted.IndependentlyPinned(snapshot) then stats.globalRefused = stats.globalRefused + 1 return false, "unanchored" end
	local ok
	ok, why = NewerSnapshot(snapshot)
	if not ok then
		if why == "replay" or why == "rollback" then stats.globalReplay = stats.globalReplay + 1 end
		stats.globalRefused = stats.globalRefused + 1
		return false, why
	end
	local digest = Digest(snapshot.signed .. snapshot.pk64 .. tostring(text:match("([^~]+)$") or ""))
	if not digest or pendingGlobal[digest] or pendingGlobalCount >= Wanted.GLOBAL_MAX_VERIFY then return false, pendingGlobal[digest] and "pending" or "busy" end
	local Ed = ns.Ed25519
	if not Ed or not Ed.Run or Ed.Busy and Ed.Busy() >= 40 then return false, "busy" end
	pendingGlobal[digest], pendingGlobalCount = snapshot, pendingGlobalCount + 1
	local started = Ed.Run(function() return Ed.Verify(snapshot.pk, snapshot.signed, snapshot.sig) end, function(jobOk, valid)
		pendingGlobal[digest], pendingGlobalCount = nil, math.max(0, pendingGlobalCount - 1)
		if jobOk and valid == true then
			local accepted, refused = AcceptSnapshot(snapshot)
			if not accepted then
				if refused == "replay" or refused == "rollback" then stats.globalReplay = stats.globalReplay + 1 end
				stats.globalRefused = stats.globalRefused + 1
			end
		else stats.globalRefused = stats.globalRefused + 1 end
	end)
	if not started then pendingGlobal[digest], pendingGlobalCount = nil, math.max(0, pendingGlobalCount - 1) return false, "busy" end
	return true, "pending"
end

function Wanted.HandleGlobalRelay(dist, sender, text)
	if type(text) ~= "string" or text:sub(1, 5) ~= "W5~1~" then return false, "shape" end
	return Wanted.HandleGlobalSnapshot(dist, sender, text:sub(6), true)
end

-- Public, unchanged signed rankings only. A reply does not publish this client's observations
-- or ledger; it repeats precisely its already-verified current word, subject to all live roles.
function Wanted.AnswerGlobal(dist, sender, text)
	if dist ~= "CHANNEL" or text ~= "W4~1" then return false, "shape" end
	if SameName(sender, ns.me) then return false, "own" end
	if not Wanted.CanPublish(ns.me) then return false, "authority" end
	local held, C, now = CurrentGlobal(), ns.Comm, ns.Now()
	if not held then return false, "none" end
	if now - Wanted.globalCatch.replied < Wanted.GLOBAL_ASK_GAP then return false, "rate" end
	if not C or not C.SendChunked then return false, "transport" end
	local body = SameName(held.issuer, ns.me) and held.text or ("W5~1~" .. held.text)
	local sent, why = C.SendChunked(body, false, nil, nil, { owner = Wanted, guardKey = "wanted-global-relay", guard = function()
		return Wanted.CanPublish(ns.me) and Wanted.CanPublish(held.issuer) and CurrentGlobal() == held and held.scope == Scope() and Fresh(held)
	end })
	if sent then Wanted.globalCatch.replied = now end
	return sent, why
end

function Wanted.AskGlobal()
	local C, now, scope = ns.Comm, ns.Now(), Scope()
	if not ns.IsMember or not ns.IsMember() then return false, "member" end
	if now - Wanted.globalCatch.asked < Wanted.GLOBAL_ASK_GAP then return false, "rate" end
	if not C or not C.Send then return false, "transport" end
	local sent, why = C.Send("CHANNEL", "W4~1", "wanted-global-ask", false, false, nil,
		{ owner = Wanted, guardKey = "wanted-global-ask", guard = function() return ns.IsMember() == true and Scope() == scope end })
	if sent then Wanted.globalCatch.asked = now end
	return sent, why
end

function Wanted.ScheduleGlobalCatchUp(generation, attempt)
	if not ns.After or generation ~= Wanted.globalCatch.generation or attempt > Wanted.GLOBAL_ASK_TRIES then return end
	ns.After(attempt == 1 and Wanted.GLOBAL_ASK_FIRST or Wanted.GLOBAL_ASK_GAP, "wanted global catch-up", function()
		if generation ~= Wanted.globalCatch.generation then return end
		Wanted.AskGlobal()
		Wanted.ScheduleGlobalCatchUp(generation, attempt + 1)
	end)
end

-- A publication's lease is its captured signed word, actor and realm/faction audience. Every
-- native chunk rechecks this same lease; queue admission never lets a replaced word escape.
function Wanted.PublicationGuard(p)
	local body, expires, issuer, scope = p.body, p.expires, p.issuer, p.scope
	local mine = BodyOrder(body)
	local signedScope, signedIssuer, signedExpires
	if type(body) == "string" then signedScope, signedIssuer, signedExpires = body:match("^WY~1~(%x+)~([^~]+)~%d+~%d+~%d+~(%d+)~") end
	local fresh = mine and { issued = mine[1], epoch = mine[4], expires = expires }
	return function()
		return mine ~= nil and publishedGlobal == p and not p.replaced and p.body == body
			and p.expires == expires and p.issuer == issuer and p.scope == scope and scope == Scope()
			and signedScope == scope and signedIssuer == issuer and tonumber(signedExpires) == expires
			and SameName(issuer, ns.me) and Wanted.CanPublish(ns.me) and Wanted.CanPublish(issuer)
			and Fresh(fresh) and not (globalFloor and CompareOrder(globalFloor, mine) > 0)
	end
end

local function PublishRows(rows)
	if not Wanted.CanPublish(ns.me) then return false, "access" end
	rows = CanonicalRows(rows)
	if not rows then return false, "rows" end
	local D, C = ns.Debts, ns.Comm
	local _, pk
	if D and D.MyKey then _, pk = D.MyKey() end
	local Ed = ns.Ed25519
	if type(pk) ~= "string" or #pk ~= 32 or not Ed or not Ed.ValidPublicKey or not Ed.ValidPublicKey(pk)
		or not D.Sign or not D.B64 or not C or not C.SendChunked then return false, "key" end
	local now = math.floor(Clock())
	if type(ns.db) ~= "table" then return false, "store" end
	local p = type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher or {}
	local pk64 = D.B64(pk)
	local epoch = Whole(p.epoch, 1, Wanted.GLOBAL_MAX_EPOCH) or math.min(now, Wanted.GLOBAL_MAX_EPOCH)
	-- A regenerated account key starts a new epoch automatically. Within one epoch receivers pin
	-- the first public key, so an edited packet cannot swap it underneath an accepted publisher.
	if type(p.pk64) == "string" and p.pk64 ~= pk64 then
		if epoch >= Wanted.GLOBAL_MAX_EPOCH then return false, "sequence" end
		epoch = math.max(epoch + 1, math.min(now, Wanted.GLOBAL_MAX_EPOCH))
	end
	if epoch > now + Wanted.GLOBAL_SKEW then return false, "epoch" end
	local seq = epoch == p.epoch and p.pk64 == pk64 and (tonumber(p.seq) or 0) + 1 or 1
	if seq > Wanted.GLOBAL_MAX_SEQ then return false, "sequence" end
	local rowsText, issuer, scope = RowsText(rows), CleanName(ns.me), Scope()
	local expires = now + Wanted.GLOBAL_LIFE
	local signed = table.concat({ "OLYW1", scope, issuer, epoch, seq, now, expires, rowsText }, "|")
	local sig = D.Sign(signed)
	if type(sig) ~= "string" or #sig ~= 64 then return false, "key" end
	p.epoch, p.seq, p.pk64 = epoch, seq, pk64
	ns.db.wantedPublisher = p
	local body = table.concat({ "WY", 1, scope, issuer, epoch, seq, now, expires, rowsText, pk64, D.B64(sig) }, "~")
	publishedGlobal = { body = body, expires = expires, issuer = issuer, scope = scope }
	local sent, why = C.SendChunked(body, true, nil, nil, { owner = Wanted, guardKey = "wanted-global", guard = Wanted.PublicationGuard(publishedGlobal) })
	if sent then
		-- Kept, so that after his next login the publisher repeats this same word (Wanted.Load).
		p.last = { body = body, expires = expires, issuer = issuer, scope = scope }
		if ScheduleGlobalRepeat then ScheduleGlobalRepeat(publishedGlobal) end
		-- Our own message never comes back to us (Comm drops our echo): the word is taken here as
		-- heard from ourselves, through every check another client makes, so that the publisher's
		-- own client shows it (or, a revocation, stops showing the frames) as everyone's does.
		Wanted.HandleGlobalSnapshot("CHANNEL", ns.me, body)
	end
	return sent, why
end

-- The server's "No player named ... is currently playing" (its pattern as Treasury reads it)
-- for a reviewer this client sends sightings to: he is not online, so his lease goes, and what
-- waits for him (SightingNotFound).
function Wanted.NotFound(text)
	if type(text) ~= "string" or Secret(text) or next(reviewers) == nil then return false end
	local T = ns.Treasury
	local pattern = T and T.NotFoundPattern and T.NotFoundPattern()
	local who = pattern and text:match(pattern)
	if not who then return false end
	return SightingNotFound ~= nil and SightingNotFound(who:lower()) == true
end

-- (Registered the first time a sighting goes, as the Arena's whispers do.)
local function WatchNotFound()
	if watchingNotFound then return end
	watchingNotFound = true
	pcall(ns.RegisterEvent, "CHAT_MSG_SYSTEM", function(text) Wanted.NotFound(text) end)
end

-- What this reviewer last published here (for his frames page), or nil.
function Wanted.LastPublished()
	local p = publishedGlobal
	if not p then
		local saved = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
		p = type(saved) == "table" and saved.scope == Scope() and SameName(saved.issuer, ns.me) and saved or nil
	end
	if not p or type(p.body) ~= "string" then return nil end
	local issued, expires, rowsText = p.body:match("^WY~%d+~%x+~[^~]+~%d+~%d+~(%d+)~(%d+)~([^~]+)~")
	local rows = rowsText and ReadRows(rowsText) or nil
	return { issued = tonumber(issued), expires = tonumber(expires), rows = rows or {} }
end

-- The public publication path is deliberately tied to this client's own Slayers board
-- (Wanted.SignableRankings: every shared kill and death it counted, by verified GUID). An
-- authority may publish an empty board or use RevokeGlobal for an emergency removal, but no
-- caller can hand this API an arbitrary scoreboard.
function Wanted.PublishGlobal()
	return PublishRows(Wanted.SignableRankings())
end

function Wanted.RevokeGlobal()
	return PublishRows({})
end

-- Repeats the same signed word for late logins; it never extends its expiry or silently turns a
-- stale review into a fresh one. A caller/timer may invoke this while the publisher stays online.
-- A word replaced is not repeated: by a newer one this client checked (NoteReplaced), or by the
-- saved one it is checking again after a load (its floor is newer than ours).
function Wanted.RepeatGlobal()
	local p, C = publishedGlobal, ns.Comm
	local mine = p and BodyOrder(p.body)
	if not mine or p.expires < math.floor(Clock()) or not SameName(p.issuer, ns.me) or not Wanted.CanPublish(ns.me)
		or (p.scope and p.scope ~= Scope()) or not C or not C.SendChunked then return false, "stale" end
	if p.replaced or globalFloor and CompareOrder(globalFloor, mine) > 0 then return false, "replaced" end
	local sent, why = C.SendChunked(p.body, false, nil, nil, { owner = Wanted, guardKey = "wanted-global-repeat", guard = Wanted.PublicationGuard(p) })
	-- Heard from ourselves again where this client does not hold it (its check was busy when he
	-- published, say), as PublishRows does.
	if sent and not restoring and not (authenticatedGlobal and authenticatedGlobal.text == p.body) then
		Wanted.HandleGlobalSnapshot("CHANNEL", ns.me, p.body)
	end
	return sent, why
end

-- GLOBAL_BURST repeats GLOBAL_BURST_GAP apart, then one every GLOBAL_REPEAT_EVERY, for as long
-- as this word is the one published, has not expired and was not replaced (a tick while the role
-- is not known sends nothing and waits for the next one).
ScheduleGlobalRepeat = function(p, n)
	if not ns.After then return end
	n = n or 0
	ns.After(n < Wanted.GLOBAL_BURST and Wanted.GLOBAL_BURST_GAP or Wanted.GLOBAL_REPEAT_EVERY, "wanted global repeat", function()
		if publishedGlobal ~= p or p.replaced or p.expires < math.floor(Clock()) then return end
		if Wanted.CanPublish(ns.me) then Wanted.RepeatGlobal() end
		ScheduleGlobalRepeat(p, n + 1)
	end)
end

-- Pure deterministic assignment used by the future authoritative publication: the current
-- all-time first, second and third get distinct keys; everyone else is absent (revoked).
function Wanted.BorderAssignments(rows)
	local ranked = type(rows) == "table" and rows or {}
	local out = {}
	for i = 1, math.min(3, #ranked) do
		local r = ranked[i]
		if type(r) == "table" and type(r.key) == "string" then out[r.key] = "wanted-slayer-" .. i end
	end
	return out
end

function Wanted.GlobalBorder(name, guid)
	if Wanted.GLOBAL_BORDERS_ACTIVE ~= true then return nil end
	local snapshot = CurrentGlobal()
	local key = GuidKey(guid)
	if not snapshot or not key then return nil end -- never award a global frame by a name alone
	return Wanted.BorderAssignments(snapshot.rows)[key]
end

function Wanted.GlobalSnapshot()
	local s = CurrentGlobal()
	if not s then return nil end
	return { issuer = s.issuer, epoch = s.epoch, seq = s.seq, issued = s.issued, expires = s.expires,
		rows = CopyList(s.rows, Wanted.GLOBAL_ROWS) }
end

function Wanted.Icon()
	local UI = ns.UI
	return UI and UI.FirstTexture and UI.FirstTexture(Wanted.ICON_PATHS) or Wanted.ICON_PATHS[#Wanted.ICON_PATHS]
end

local function Grey(s) return "|cff9d9d9d" .. tostring(s or "") .. "|r" end
local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff40ff40" .. tostring(s or "") .. "|r" end
local PLACE = { "|cffffd200#1|r", "|cffc7c7cf#2|r", "|cffb07a45#3|r" }

local function Display(identity)
	return identity.name and ((ns.DisplayName and ns.DisplayName(identity.name)) or ns.ShortName(identity.name) or identity.name)
		or L.WANTED_UNKNOWN
end

local function EvidenceLabel(kind)
	return kind == "PARTY_KILL" and L.WANTED_EVIDENCE_PARTY or kind == "SELF_DEATH" and L.WANTED_EVIDENCE_RECAP or L.WANTED_UNKNOWN
end

local function TargetTip(t)
	return function(tt)
		tt:AddLine(Display(t), 1, 0.82, 0)
		tt:AddLine(L.WANTED_BOUNTY:format(t.current), 1, 1, 1)
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills), 0.8, 0.8, 0.8)
		if t.lastSighting then
			local precision = t.lastSighting.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE
			tt:AddLine(L.WANTED_LAST_SIGHTING:format(t.lastSighting.zone or L.WANTED_UNKNOWN, precision, ns.Ago(t.lastSighting.at)), 0.8, 0.8, 0.8, true)
		end
		for _, v in ipairs(t.victims) do
			tt:AddLine(L.WANTED_VICTIM_TIP:format(v.name and (ns.DisplayName(v.name) or v.name) or L.WANTED_UNKNOWN,
				v.zone or L.WANTED_UNKNOWN, EvidenceLabel(v.evidence), ns.Ago(v.at)), 1, 1, 1, true)
		end
		if t.victimOverflow > 0 then tt:AddLine(L.WANTED_MORE_EVIDENCE:format(t.victimOverflow), 0.7, 0.7, 0.7) end
	end
end

function Wanted.OpenTarget(value, guid, realm)
	local s, ident = Store(false), Identity(value, guid, realm)
	local t = s and ResolveTarget(s, ident, false)
	if not t then return false end
	mode, opened = "target", t.key
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

-- The frames page (the King, a signed High Councillor or the author): the top three he would
-- sign from his own Slayers board, and his last word.
function Wanted.OpenReview()
	if not Wanted.CanPublish(ns.me) then return false end
	mode, opened = "review", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.Back()
	if mode == "list" then return false end
	mode, opened = "list", nil
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
	return true
end

function Wanted.PageId()
	if mode == "target" then return "target:" .. tostring(opened) end
	return mode == "review" and "review" or "list"
end

local function OpenSlayer(r)
	if not (r and r.name and ns.UI and ns.UI.ShowPerson) then return false end
	return ns.UI.ShowPerson({ name = ns.ShortName(r.name), realm = ns.RealmOf(r.name), source = "addon", at = r.lastAt })
end

-- A GUID as a name a person can read: what this client knows of it (its slayers, its targets,
-- the game's own lookup through Debts.InfoName), else the GUID itself.
local function GuidName(guid)
	guid = Guid(guid)
	if not guid then return L.WANTED_UNKNOWN end
	local s, key = Store(false), GuidKey(guid)
	local known = s and (s.slayers[s.slayerAliases[key] or key] or s.targets[s.aliases[key] or key]) or nil
	local name = type(known) == "table" and known.name or nil
	if not name then
		local D = ns.Debts
		local ok, info = false, nil
		if type(D) == "table" and type(D.InfoName) == "function" then ok, info = pcall(D.InfoName, guid) end
		name = ok and type(info) == "string" and info ~= "" and not Secret(info) and info or nil
	end
	return name and (ns.DisplayName and ns.DisplayName(name) or name) or guid
end

local function DaysLeft(expires)
	return math.max(0, math.ceil(((tonumber(expires) or 0) - Clock()) / 86400))
end

local function IssuerName(name) return ns.DisplayName and ns.DisplayName(name) or name end

local function RankingLines(lines, title, rows)
	lines[#lines + 1] = { header = true, text = title }
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_SLAYERS) } return end
	for i, r in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, key = r.key, player = r.name,
			text = (PLACE[i] or ("#" .. i)) .. "  " .. (r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN),
			right = L.WANTED_POINTS:format(r.points), onClick = r.name and function() return OpenSlayer(r) end or nil,
			tooltip = function(tt)
				tt:AddLine(r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN, 1, 0.82, 0)
				tt:AddLine(L.WANTED_SLAYER_TIP:format(r.points, r.claims), 1, 1, 1, true)
			end }
	end
end

-- The signed all-time top three this client holds (the one that sets the frames), if any.
local function SignedLines(lines)
	local g = Wanted.GlobalSnapshot()
	if not g then return false end
	lines[#lines + 1] = { header = true, text = L.WANTED_SIGNED, right = Grey(L.WANTED_SIGNED_BY:format(IssuerName(g.issuer), ns.Ago(g.issued))) }
	if #g.rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_SIGNED_EMPTY) } end
	for i, row in ipairs(g.rows) do
		local name = GuidName(row.guid)
		lines[#lines + 1] = { indent = 1, key = row.key, text = (PLACE[i] or ("#" .. i)) .. "  " .. name,
			right = L.WANTED_POINTS:format(row.points), tooltip = function(tt)
				tt:AddLine(name, 1, 0.82, 0)
				tt:AddLine(L.WANTED_SLAYER_TIP:format(row.points, row.claims), 1, 1, 1, true)
				tt:AddLine(L.WANTED_SIGNED_HELD:format(IssuerName(g.issuer), DaysLeft(g.expires)), 0.8, 0.8, 0.8, true)
			end }
	end
	lines[#lines].gapAfter = true
	return true
end

local function ListLines()
	local lines, targets = {}, Wanted.Targets(true)
	lines[#lines + 1] = { header = true, text = L.WANTED_TARGETS, right = Grey(tostring(#targets)) }
	if #targets == 0 then lines[#lines + 1] = { text = Grey(L.WANTED_EMPTY) } end
	for _, t in ipairs(targets) do
		lines[#lines + 1] = { id = "wanted:" .. t.key, key = t.key, text = Display(t),
			right = L.WANTED_ROW_COUNTS:format(t.current, t.lifetimeKills), onClick = function() return Wanted.OpenTarget(t) end,
			tooltip = TargetTip(t) }
	end
	lines[#lines].gapAfter = true
	local signed = SignedLines(lines)
	-- This client's own two boards: what it observed, never everyone's ranking (only the signed
	-- top three above is that).
	local rank = Wanted.Rankings()
	local year, month = math.floor(rank.monthNo / 12), rank.monthNo % 12 + 1
	RankingLines(lines, L.WANTED_MONTHLY:format(year, month), rank.month)
	lines[#lines].gapAfter = true
	RankingLines(lines, L.WANTED_LOCAL_ALL, rank.all)
	if not signed then lines[#lines + 1] = { text = Grey(L.WANTED_AUTHORITY_OFF), gapAfter = true } end
	return lines
end

local function LiveEvidence(id)
	local s = Store(false)
	for _, e in ipairs(s and s.evidence or {}) do if e.id == id and not e.void then return true end end
	return false
end

-- A reviewer (Wanted.CanRemove) voids a row still live (not yet checkpointed), with a reason.
local function CorrectClick(id, label)
	if not (id and Wanted.CanRemove() and LiveEvidence(id)) then return nil end
	return function() return ns.ShowDialog("OLYMPUS_WANTED_CORRECT", label, nil, id) end
end

local function TargetLines()
	local s, t = Store(false), nil
	if s and opened then t = s.targets[s.aliases[opened] or opened] end
	if not t then mode, opened = "list", nil return ListLines() end
	t = PublicTarget(t)
	local lines = { { text = Gold(L.WANTED_BACK), onClick = Wanted.Back },
		{ header = true, text = Display(t), right = t.active and Green(L.WANTED_LISTED) or Grey(L.WANTED_REMOVED) },
		{ indent = 1, text = L.WANTED_GUID:format(t.guid or L.WANTED_UNKNOWN) },
		{ indent = 1, text = L.WANTED_BOUNTY:format(t.current), right = L.WANTED_LIFETIME:format(t.lifetimeKills) },
		{ indent = 1, text = L.WANTED_CYCLE:format(t.cycle, t.openSince and ns.Ago(t.openSince) or L.WANTED_UNKNOWN) },
	}
	-- (1.2.3: how he entered, by himself, and who took him off.)
	if t.addedAt and t.addedBy then
		lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_ENTERED:format(ns.Ago(t.addedAt), IssuerName(t.addedBy))) }
	end
	if not t.active and t.removedBy then
		lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_TAKEN_OFF:format(IssuerName(t.removedBy), t.removedAt and ns.Ago(t.removedAt) or L.WANTED_UNKNOWN)) }
	end
	if t.lastSighting then
		local precision = t.lastSighting.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE
		lines[#lines + 1] = { indent = 1, text = L.WANTED_LAST_SIGHTING:format(t.lastSighting.zone or L.WANTED_UNKNOWN, precision,
			ns.Ago(t.lastSighting.at)) }
	end
	lines[#lines + 1] = { header = true, text = L.WANTED_OPEN_CYCLE }
	if #t.victims == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_VICTIMS) } end
	for _, v in ipairs(t.victims) do
		local label = v.name and (ns.DisplayName(v.name) or v.name) or L.WANTED_UNKNOWN
		lines[#lines + 1] = { indent = 1, text = label, right = Grey(ns.Ago(v.at)), onClick = CorrectClick(v.id, label),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_EVIDENCE, 1, 0.82, 0)
				tt:AddLine(EvidenceLabel(v.evidence), 1, 1, 1, true)
				tt:AddLine(L.WANTED_LOCATION:format(v.zone or L.WANTED_UNKNOWN, v.precision == "consented" and L.WANTED_CONSENTED or L.WANTED_APPROXIMATE),
					0.8, 0.8, 0.8, true)
			end }
	end
	if t.victimOverflow > 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_MORE_EVIDENCE:format(t.victimOverflow)) } end
	lines[#lines + 1] = { header = true, text = L.WANTED_CLAIMS }
	if #t.claims == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_CLAIMS) } end
	for i = #t.claims, 1, -1 do
		local c = t.claims[i]
		local label = c.slayer and (ns.DisplayName(c.slayer) or c.slayer) or L.WANTED_UNKNOWN
		lines[#lines + 1] = { indent = 1, text = label, right = L.WANTED_CLAIM_POINTS:format(c.points or 0), onClick = CorrectClick(c.id, label),
			tooltip = function(tt)
				tt:AddLine(L.WANTED_CLAIM_TIP:format(c.points or 0, c.cycle or 0, EvidenceLabel(c.evidence), ns.Ago(c.at)), 1, 1, 1, true)
			end }
	end
	return lines
end

-- The frames page: the top three this reviewer would sign (Wanted.SignableRankings), the Slayers
-- left out of it for want of a verified GUID, and when he last published.
local function FramesLines()
	if not Wanted.CanPublish(ns.me) then mode, opened = "list", nil return ListLines() end
	local lines = { { text = Gold(L.WANTED_BACK), onClick = Wanted.Back } }
	lines[#lines + 1] = { header = true, text = L.WANTED_TO_PUBLISH }
	local rows = Wanted.SignableRankings()
	if #rows == 0 then lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_SLAYERS) } end
	for i, row in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, key = row.key, text = (PLACE[i] or ("#" .. i)) .. "  " .. GuidName(row.guid),
			right = L.WANTED_POINTS:format(row.points) }
	end
	for _, r in ipairs(Share.Unsignable()) do
		lines[#lines + 1] = { indent = 1, text = Grey(L.WANTED_NO_GUID:format(r.name and (ns.DisplayName(r.name) or r.name) or L.WANTED_UNKNOWN)) }
	end
	local last = Wanted.LastPublished()
	lines[#lines + 1] = { indent = 1, text = Grey(last and last.issued and L.WANTED_LAST_PUBLISHED:format(ns.Ago(last.issued), DaysLeft(last.expires))
		or L.WANTED_NOT_PUBLISHED) }
	return lines
end

function Wanted.Build()
	if mode == "review" then
		local lines = FramesLines()
		if mode == "review" then return lines, L.WANTED_REVIEW_TITLE, L.WANTED_REVIEW_ABOUT end
		return lines, L.WANTED_TITLE, L.WANTED_ABOUT
	end
	local lines = mode == "target" and TargetLines() or ListLines()
	local g = Wanted.GlobalSnapshot()
	local note = g and L.WANTED_SIGNED_HELD:format(IssuerName(g.issuer), DaysLeft(g.expires)) or L.WANTED_AUTHORITY_OFF
	return lines, L.WANTED_TITLE, L.WANTED_ABOUT .. "\n" .. Grey(note)
end

-- The entry open now, while it is on the list (a reviewer's Remove).
local function OpenedActive()
	local s = Store(false)
	local t = mode == "target" and s and opened and s.targets[s.aliases[opened] or opened]
	return type(t) == "table" and t.active == true and t or nil
end

local function PromptRemove()
	local t = Wanted.CanRemove() and OpenedActive()
	if not t then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REMOVE", Display(t), nil, t.key)
end

-- 1.2.3: the one reviewer this member's sightings are whispered to. He was the one the member sent
-- his evidence to; there is no evidence to send any more, so the member names him here: the King,
-- a signed High Councillor or the author, typed, or nobody (empty). Returns true, or false and why.
function Wanted.SetReviewer(name)
	name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
	if name == "" then
		local s = Store(false)
		if s then s.reviewer = nil end
		ns.Print(L.WANTED_REVIEWER_NONE)
		return true
	end
	local reviewer = CleanName(ns.FullName and ns.FullName(name) or name)
	if not reviewer or SameName(reviewer, ns.me) or not Wanted.CanPublish(reviewer) then return false, "reviewer" end
	local s = Store(true)
	if not s then return false, "store" end
	s.reviewer = reviewer
	ns.Print(L.WANTED_REVIEWER_SET:format(IssuerName(reviewer)))
	return true
end

local function PromptReviewer()
	if not Wanted.SightingsOn() then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REVIEWER")
end

local function RowsSummary(rows)
	local out = {}
	for i, row in ipairs(rows) do out[i] = ("#%d %s · %s"):format(i, GuidName(row.guid), L.WANTED_POINTS:format(row.points)) end
	return #out > 0 and table.concat(out, "\n") or L.WANTED_SIGNED_EMPTY
end

local function PromptPublish()
	if not Wanted.CanPublish(ns.me) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_PUBLISH", RowsSummary(Wanted.SignableRankings()))
end

local function PromptRevoke()
	if not Wanted.CanPublish(ns.me) then return false end
	return ns.ShowDialog("OLYMPUS_WANTED_REVOKE")
end

local function Failed(why) ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end

local function Focus(eb)
	if ns.Focus then ns.Focus(eb) elseif eb.SetFocus then eb:SetFocus() end
end

StaticPopupDialogs["OLYMPUS_WANTED_REMOVE"] = {
	text = L.WANTED_REMOVE_PROMPT, button1 = REMOVE or "Remove", button2 = CANCEL or "Cancel",
	OnAccept = function(self, key)
		key = key or (self and self.data)
		local s = Store(false)
		local t = s and s.targets[s.aliases[key] or key]
		local ok, why
		if t then ok, why = Wanted.RemoveTarget(t) else ok, why = false, "missing" end
		if not ok then ns.Print(L.WANTED_ACTION_FAILED:format(tostring(why or "?"))) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- Sightings to: the reviewer typed (prefilled with the one chosen), or nobody.
StaticPopupDialogs["OLYMPUS_WANTED_REVIEWER"] = {
	text = L.WANTED_REVIEWER_PROMPT, button1 = L.WANTED_REVIEWER_ACCEPT, button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 72,
	-- (Focus: with the gamepad UI, never the keyboard taken from another box, the chat's.)
	OnShow = function(self)
		local eb = self.editBox or self.EditBox
		local s = Store(false)
		if eb then eb:SetText(s and s.reviewer and (ns.TellName(s.reviewer) or s.reviewer) or ""); Focus(eb) end
	end,
	OnAccept = function(self)
		local eb = self.editBox or self.EditBox
		local ok, why = Wanted.SetReviewer(eb and eb:GetText() or "")
		if not ok then Failed(why) end
	end,
	EditBoxOnEnterPressed = function(self)
		local parent = self:GetParent()
		local ok, why = Wanted.SetReviewer(self:GetText() or "")
		if not ok then Failed(why) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_PUBLISH"] = {
	text = L.WANTED_PUBLISH_PROMPT, button1 = L.WANTED_PUBLISH_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ok, why = Wanted.PublishGlobal()
		if ok then ns.Print(L.WANTED_PUBLISHED) else Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_REVOKE"] = {
	text = L.WANTED_REVOKE_PROMPT, button1 = L.WANTED_REVOKE_BTN, button2 = CANCEL or "Cancel",
	OnAccept = function()
		local ok, why = Wanted.RevokeGlobal()
		if ok then ns.Print(L.WANTED_REVOKED) else Failed(why) end
	end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

StaticPopupDialogs["OLYMPUS_WANTED_CORRECT"] = {
	text = L.WANTED_CORRECT_PROMPT, button1 = L.WANTED_CORRECT_BTN, button2 = CANCEL or "Cancel", hasEditBox = true,
	editBoxWidth = 300, maxLetters = 80,
	OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(""); Focus(eb) end end,
	OnAccept = function(self, id)
		local eb = self.editBox or self.EditBox
		local ok, why = Wanted.Correct(id or (self and self.data), eb and eb:GetText() or "")
		if not ok then Failed(why) end
	end,
	EditBoxOnEnterPressed = function(self, id)
		local parent = self:GetParent()
		local ok, why = Wanted.Correct(id or (parent and parent.data), self:GetText() or "")
		if not ok then Failed(why) end
		parent:Hide()
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

-- 1.2.3: no Add (Horde players enter by themselves), no Send evidence and no review: a reviewer's
-- Frames page (the top three he signs), his Remove on an entry, and a member's Sightings to.
local buttons = {
	{ "WANTED_BACK_BTN", Wanted.Back, shown = function() return mode ~= "list" end },
	{ "WANTED_REVIEW_BTN", Wanted.OpenReview, shown = function() return mode == "list" and Wanted.CanPublish(ns.me) end },
	{ "WANTED_REVIEWER_BTN", PromptReviewer, shown = function()
		return mode == "list" and ns.IsMember ~= nil and ns.IsMember() == true and ns.faction ~= "Horde" and Wanted.SightingsOn()
	end },
	{ "WANTED_REMOVE_BTN", PromptRemove, shown = function() return mode == "target" and Wanted.CanRemove() and OpenedActive() ~= nil end },
	{ "WANTED_PUBLISH_BTN", PromptPublish, shown = function() return mode == "review" and Wanted.CanPublish(ns.me) end },
	{ "WANTED_REVOKE_BTN", PromptRevoke, shown = function() return mode == "review" and Wanted.CanPublish(ns.me) end },
}
Wanted.buttons = buttons -- (tests)

---------------------------------------------------------------------------
-- Most Wanted sightings
--
-- A sighting is what this client saw itself: a Horde player on its own Most Wanted list (1.2.3:
-- every Horde player who killed or was killed by a member it heard of, by himself), by his name
-- and GUID as the game gives them (a secret value is refused), and where this player stood then:
-- his own map position, rounded to SIGHT_GRID thousandths of the map, and his layer when Layers
-- knows it. "Seen nearby": never the Horde player's own coordinates. Off until the member's own
-- Yes on its line of the privacy page (1.2.0), off again by his No (/oly sightings off), which
-- stops collecting, cancels what waits in Comm and takes back what reached a reviewer, at once.
-- Nothing goes while he keeps his zone and layer private (Layers.Sharing). The King's position is
-- his crown on the map (King.SharingLocation, as for his layer): while it is hidden his client
-- sends none, and hiding it takes back what went. Nothing is collected in an instance, nor by a
-- client the moderators took off (net-off).
-- It shows on this client's own map, and goes to the one reviewer (the King, a signed High
-- Councillor, the author) the member chose (Sightings to on the Most Wanted page:
-- Wanted.SetReviewer; until 1.2.3, the one he sent his evidence to), by whisper only, never on
-- the channel, and only while that reviewer's client says it takes sightings (its lease: no place
-- in it); a member who chose nobody sends his sightings to nobody. SIGHT_SEND_MAX a window from
-- this client, each Horde player once per SIGHT_GAP.
-- Comm checks each whisper again when it leaves (the No, net-off, the crown, the reviewer's
-- lease, its age).
--   WS~R~1                                                             channel: a reviewer's lease
--   WS~R~0                                                             channel: his No (lease off)
--   WS~S~1~<guild>~<id>~<at>~<map>~<x>~<y>~<layer>~<guid>~<name>       whisper: one sighting
--   WS~X~1                                                             whisper: the sender's taken back
-- A reviewer takes one only while his own sightings are on, from a member of an Olympus guild (as
-- the Olympus chats verify one), fresh (SIGHT_TTL, GLOBAL_SKEW), once (its id, per sender),
-- SIGHT_RECV_MAX a window from one sender and SIGHT_INTAKE_MAX from all (counted before anything
-- is parsed). A client without WS (1.1.4, or 1.2 before it) ignores every one of these words.
-- A pin is one Horde player where he was seen last, SIGHT_TTL long, SIGHT_PINS at most; its hover
-- says his name, his kills by this client's Most Wanted ledger, how long ago and by whom. Nothing
-- of it is saved. Pins follow the map rules of Olympus's other icons: on the world map only with
-- mouse and keyboard (ns.WorldMapIcons), on the minimap always, for members only, none while this
-- player is in an instance.
---------------------------------------------------------------------------

-- (1.2.0: off until the member's own Yes on its line.)
local function SightingsOn() return type(ns.db) == "table" and ns.db.wantedSightings == true end
Wanted.SightingsOn = SightingsOn
-- (The section's helpers: Wanted.lua's main chunk is near Lua's 200 locals.)
local Sight = {}

-- The moderators took this client off (net-off): it sends none of this.
local function NetOff()
	local M = ns.Moderation
	if type(M) ~= "table" or M.missing or type(M.SelfOff) ~= "function" then return false end
	local ok, off = pcall(M.SelfOff)
	return not ok or (off ~= nil and off ~= false)
end

-- A unit API's first answer, nil when it fails or is secret.
local function Ask(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, v = pcall(fn, ...)
	if not ok or Secret(v) then return nil end
	return v
end

-- This client collects sightings: a member's, on the Alliance side, not refused, not off.
local function Collects()
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if ns.faction == "Horde" then return false, "faction" end
	if not SightingsOn() then return false, "off" end
	if NetOff() then return false, "netoff" end
	return true
end

-- This client takes sightings: a reviewer's (Wanted.CanPublish), a member's, not off (his own
-- No stops what he takes too), not net-off.
local function TakesSightings()
	return ns.IsMember and ns.IsMember() == true and ns.me ~= nil and ns.faction ~= "Horde"
		and SightingsOn() and Wanted.CanPublish(ns.me) and not NetOff()
end

-- The King's position goes out only while his crown shows on the map (King.SharingLocation), as
-- his zone and layer do (Layers.Sharing): while it is hidden, his client sends no sighting (it
-- still pins what it saw on his own map). Not known (King.lua missing, or failing): hidden for a
-- King's character.
function Sight.CrownHidden()
	local K = ns.King
	if type(K) ~= "table" or K.missing or type(K.IsKing) ~= "function" or type(K.SharingLocation) ~= "function" then
		return ns.IsKingCharacter ~= nil and ns.me ~= nil and ns.IsKingCharacter(ns.me) == true
	end
	local ok, king = pcall(K.IsKing)
	if not ok then return true end
	if king ~= true then return false end
	local okShown, shown = pcall(K.SharingLocation)
	return not okShown or shown ~= true
end

function Sight.GuildName(guild)
	if Secret(guild) or type(guild) ~= "string" or guild == "" or #guild > 48 or guild:find("[~|%c]") then return nil end
	return ns.IsFederation and ns.IsFederation(guild) and guild or nil
end

-- This player's Olympus guild, as the game says it.
function Sight.OwnGuild()
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	return ok and Sight.GuildName(guild) or nil
end

-- A zone's map (or a smaller one in it): never a continent, the world, or a dungeon's.
function Sight.OpenMap(mapID)
	if not Whole(mapID, 1, 9999999) or type(C_Map) ~= "table" or type(C_Map.GetMapInfo) ~= "function" then return false end
	local ok, info = pcall(C_Map.GetMapInfo, mapID)
	if not ok or type(info) ~= "table" or Secret(info.mapType) then return false end
	local T = type(Enum) == "table" and type(Enum.UIMapType) == "table" and Enum.UIMapType or {}
	return info.mapType == (T.Zone or 3) or info.mapType == (T.Micro or 5)
end

function Sight.Grid(v)
	local g = Wanted.SIGHT_GRID
	return math.max(0, math.min(1000, math.floor(v * 1000 / g + 0.5) * g))
end

-- Where this player stands: his map and position there, rounded (Grid), or nil.
function Sight.Spot()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" or type(C_Map.GetPlayerMapPosition) ~= "function" then return nil end
	local mapID = Ask(C_Map.GetBestMapForUnit, "player")
	if not Sight.OpenMap(mapID) then return nil end
	local pos = Ask(C_Map.GetPlayerMapPosition, mapID, "player")
	if not pos then return nil end
	local ok, x, y = pcall(function() return pos:GetXY() end)
	if not ok or Secret(x, y) or type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y
		or x < 0 or x > 1 or y < 0 or y > 1 or (x == 0 and y == 0) then return nil end
	return mapID, Sight.Grid(x), Sight.Grid(y)
end

-- This player's layer on that map when Layers saw it lately, else 0 (not known).
function Sight.MyLayer(mapID)
	local Ly = ns.Layers
	if type(Ly) ~= "table" or Ly.missing or type(Ly.Mine) ~= "function" then return 0 end
	local ok, m = pcall(Ly.Mine)
	local now = ns.Now()
	if not ok or type(m) ~= "table" or m.mapID ~= mapID or not Whole(m.zoneUID, 1, 2147483647) or type(m.t) ~= "number"
		or now - m.t > Wanted.SIGHT_LAYER_FRESH or m.t > now + 5 then return 0 end
	return m.zoneUID
end

-- The unit, when it is a sighting: a Horde player (not us) listed here (true). Only the wanted:
-- nobody else is recorded, sent or pinned. nil, why otherwise (and, for a hostile one flagged for
-- PvP of no Olympus guild, his identity: remembered here as Horde, for one's own death recap).
local function SightedUnit(unit)
	if Ask(UnitIsPlayer, unit) ~= true then return nil, "player" end
	if Ask(UnitFactionGroup, unit) ~= "Horde" then return nil, "faction" end
	local ident = UnitIdentity(unit)
	if not ident or not ident.guid or not ident.name then return nil, "identity" end
	local me = UnitIdentity("player") or Identity(ns.me)
	if me and SameIdentity(me, ident) then return nil, "self" end
	local s = Store(false)
	local t = s and ResolveTarget(s, ident, false)
	if t and t.active then return ident, true end
	if Ask(UnitCanAttack, "player", unit) ~= true or Ask(UnitIsPVP, unit) ~= true then return nil, "unlisted" end
	if type(GetGuildInfo) == "function" then
		local ok, guild = pcall(GetGuildInfo, unit)
		if not ok or Secret(guild) or (type(guild) == "string" and ns.IsFederation and ns.IsFederation(guild)) then return nil, "unlisted" end
	end
	return nil, "unlisted", ident
end

local function SightLive(e, now)
	return now - e.at <= Wanted.SIGHT_TTL and e.at <= now + Wanted.GLOBAL_SKEW
end

-- The newest sighting of each Horde player, SIGHT_PINS of them at most (the oldest go first).
local function Keep(e)
	local old = pins[e.guid]
	if old and old.at > e.at then return false end
	pins[e.guid] = e
	local n = Count(pins)
	while n > Wanted.SIGHT_PINS do
		local oldest
		for guid, p in pairs(pins) do if not oldest or p.at < pins[oldest].at then oldest = guid end end
		pins[oldest], n = nil, n - 1
	end
	return pins[e.guid] == e
end

local function LeaseLive(r, now)
	return type(r) == "table" and now - r.at <= Wanted.REVIEWER_FOR and r.at <= now + Wanted.GLOBAL_SKEW
		and Wanted.CanPublish(r.name)
end

-- Whom a sighting goes to: the reviewer this member chose (s.reviewer, set by Wanted.SetReviewer;
-- by 1.2.2's Send evidence before), while his client says it takes them (his lease) and he holds
-- the role; never us, never anyone else. Nobody when this member chose nobody.
local function Recipients(now)
	local s = Store(false)
	local chosen = s and CleanName(s.reviewer) or nil
	if not chosen or SameName(chosen, ns.me) then return {} end
	local r = reviewers[ns.Fold(chosen)]
	if not LeaseLive(r, now) then return {} end
	return { r.name }
end
Wanted.SightingRecipients = function() return Recipients(math.floor(Clock())) end

local function DropJob(job)
	if sightJobs[job.key] == job then sightJobs[job.key], sightJobCount = nil, sightJobCount - 1 end
end

-- Cancels the sightings waiting in Comm (every one, or one reviewer's: his folded name).
local function CancelSightings(why, onlyTo)
	local list = {}
	for _, job in pairs(sightJobs) do
		if onlyTo == nil or job.toKey == onlyTo then list[#list + 1] = job end
	end
	local C = ns.Comm
	for _, job in ipairs(list) do
		job.cancelled = true
		DropJob(job)
		if type(C) == "table" and type(C.CancelQueued) == "function" then C.CancelQueued(Wanted, job.key, why or "cancelled") end
	end
	stats.sightCancelled = stats.sightCancelled + #list
	return #list
end

-- When Comm is about to send one: still wanted, still allowed, still fresh, still taken.
local function SightPermit(job)
	if sightJobs[job.key] ~= job or job.cancelled then return false, "cancelled" end
	local ok, why = Collects()
	if not ok then return false, why end
	if Sight.CrownHidden() then return false, "crown" end
	if not Sight.Sharing() then return false, "private" end
	local now = math.floor(Clock())
	if now - job.at > Wanted.SIGHT_QUEUE_TTL then return false, "stale" end
	if not LeaseLive(reviewers[job.toKey], now) then return false, "reviewer" end
	return true
end

function Sight.Sharing()
	local Ly = ns.Layers
	return type(Ly) == "table" and type(Ly.Sharing) == "function" and Ly.Sharing() == true
end

-- The server's "No player named <reviewer> is currently playing" that answers a whisper this
-- client sent him on its own (a sighting, or taking them back): kept out of the chat frames for
-- SIGHT_QUIET seconds after it went (Wanted.NotFound still reads it, and drops him). The player
-- typed nothing, and a line naming the King out of nowhere says nothing to him. A line for anyone
-- else, or later, shows as ever.
function Wanted.QuietLine(_, _, text)
	if not ns.Gate.Allowed("system-filters") then return false end
	if next(told.quiet) == nil or type(text) ~= "string" or Secret(text) then return false end
	local T = ns.Treasury
	local pattern = T and type(T.NotFoundPattern) == "function" and T.NotFoundPattern()
	local who = type(pattern) == "string" and text:match(pattern)
	if type(who) ~= "string" then return false end
	local untilAt = told.quiet[who:lower()]
	local now = math.floor(Clock())
	return untilAt ~= nil and now <= untilAt and untilAt - now <= Wanted.SIGHT_QUIET
end

function Sight.Quiet(name)
	local now = math.floor(Clock())
	for who, untilAt in pairs(told.quiet) do if untilAt < now then told.quiet[who] = nil end end
	for _, shown in ipairs({ ns.TellName and ns.TellName(name), ns.DisplayName and ns.DisplayName(name) }) do
		if type(shown) == "string" and shown ~= "" then told.quiet[shown:lower()] = now + Wanted.SIGHT_QUIET end
	end
	if told.filter or not ns.Gate.Allowed("system-filters") then return end
	local U = rawget(_G, "ChatFrameUtil") -- gp:system-filters
	local add = type(U) == "table" and type(U.AddMessageEventFilter) == "function" and U.AddMessageEventFilter
		or rawget(_G, "ChatFrame_AddMessageEventFilter") -- gp:system-filters
	if type(add) ~= "function" then return end
	told.filter = true
	pcall(add, "CHAT_MSG_SYSTEM", Wanted.QuietLine) -- gp:system-filters
end

-- A reviewer this client's sightings reached this session (Withdraw takes them back).
function Sight.Told(job)
	if not told.by[job.toKey] then told.by[job.toKey] = { name = job.to, target = job.target } end
	Sight.Quiet(job.to)
end

-- Takes this client's sightings off the maps of the reviewers they reached this session (a No,
-- the King's crown hidden): one whisper each. (A reviewer who logged out since kept none: his
-- pins are his session's.) Returns how many were asked.
function Sight.Withdraw()
	local C = ns.Comm
	local list = {}
	for key, r in pairs(told.by) do list[#list + 1] = { key = key, name = r.name, target = r.target } end
	for key in pairs(told.by) do told.by[key] = nil end
	if type(C) ~= "table" or type(C.Whisper) ~= "function" then return 0 end
	table.sort(list, function(a, b) return a.key < b.key end)
	local n = 0
	for _, r in ipairs(list) do
		local asked = C.Whisper(r.target, "WS~X~1", "wanted-sighting-back:" .. r.key, false, false, function(sent)
			if sent then Sight.Quiet(r.name) end
		end)
		if asked then n = n + 1 end
	end
	return n
end

local function SendSighting(e)
	local C = ns.Comm
	-- (Only through a Comm that can cancel what waits: a No must reach every queued sighting.)
	if type(C) ~= "table" or type(C.Whisper) ~= "function" or type(C.CancelQueued) ~= "function" then return 0, "transport" end
	if Sight.CrownHidden() then return 0, "crown" end
	-- (1.2.0: a sighting carries where this player stands and his layer: none goes while he keeps
	-- his zone and layer private.)
	if not Sight.Sharing() then return 0, "private" end
	local guild = Sight.OwnGuild()
	if not guild then return 0, "guild" end
	local now = math.floor(Clock())
	for i = #sightSends, 1, -1 do
		if now - sightSends[i] >= Wanted.SIGHT_WINDOW or sightSends[i] > now then table.remove(sightSends, i) end
	end
	if #sightSends >= Wanted.SIGHT_SEND_MAX then stats.sightRate = stats.sightRate + 1 return 0, "rate" end
	local to = Recipients(now)
	if #to == 0 then return 0, "reviewers" end
	local wire = WireGuid(e.guid)
	if not wire then return 0, "identity" end
	local body = ("WS~S~1~%s~%s~%d~%d~%d~%d~%d~%s~%s"):format(guild, e.id, e.at, e.mapID, e.x, e.y, e.layer, wire, e.name)
	if #body > 255 then return 0, "size" end
	local queued = 0
	for _, name in ipairs(to) do
		if sightJobCount >= Wanted.SIGHT_QUEUE_MAX then break end
		local toKey = ns.Fold(name)
		local key = "wanted-sighting:" .. toKey .. ":" .. e.id
		local target = ns.TellName and ns.TellName(name) or name
		local job = { key = key, toKey = toKey, to = name, target = target, body = body, at = now }
		sightJobs[key], sightJobCount = job, sightJobCount + 1
		local accepted = C.Whisper(target, body, nil, false, false, function(sent)
			DropJob(job)
			if sent then stats.sightSent = stats.sightSent + 1 Sight.Told(job) end
		end, { owner = Wanted, key = key, permit = function(owner, permitKey, dist, permitTarget, msg)
			if owner ~= Wanted or permitKey ~= key or dist ~= "WHISPER" or permitTarget ~= target or msg ~= body then return false, "target" end
			return SightPermit(job)
		end })
		if accepted then queued = queued + 1 else DropJob(job) end
	end
	if queued == 0 then return 0, "queue" end
	sightSends[#sightSends + 1] = now
	WatchNotFound()
	return queued
end

local function RememberOwn(guid, now, mapID)
	if not ownSeen[guid] then ownSeenCount = ownSeenCount + 1 end
	ownSeen[guid] = { at = now, mapID = mapID }
	if ownSeenCount <= Wanted.SIGHT_OWN_MAX then return end
	for key, o in pairs(ownSeen) do
		if now - o.at >= Wanted.SIGHT_GAP or o.at > now then ownSeen[key], ownSeenCount = nil, ownSeenCount - 1 end
	end
	while ownSeenCount > Wanted.SIGHT_OWN_MAX do
		local oldest
		for key, o in pairs(ownSeen) do if not oldest or o.at < ownSeen[oldest].at then oldest = key end end
		ownSeen[oldest], ownSeenCount = nil, ownSeenCount - 1
	end
end

-- What this client sees (a nameplate, its target, the unit under the mouse). Returns true and the
-- sighting, or false and why it is none.
function Wanted.ObserveUnit(unit)
	local ok, why = Collects()
	if not ok then
		-- (1.2.0: sightings wait for a Yes; until one is answered, a hostile Horde player seen is
		-- still remembered here, never sent, for one's own death recap. A No stops that too.)
		if why == "off" and type(ns.db) == "table" and ns.db.wantedSightings == nil and type(unit) == "string" and not InInstance() then
			local _, _, horde = SightedUnit(unit)
			if horde then RememberHorde(horde) end
		end
		return false, why
	end
	if InInstance() then return false, "instance" end
	if type(unit) ~= "string" then return false, "unit" end
	-- A Horde player this client recorded on this map within SIGHT_GAP: dropped before anything
	-- else is asked of the game (nameplates come and go all through a fight).
	local now = math.floor(Clock())
	local last = ownSeen[Guid(Ask(UnitGUID, unit)) or false]
	if last and now - last.at < Wanted.SIGHT_GAP and last.at <= now and type(C_Map) == "table"
		and last.mapID == Ask(C_Map.GetBestMapForUnit, "player") then
		stats.sightRepeat = stats.sightRepeat + 1
		return false, "repeat"
	end
	local ident, listed, horde = SightedUnit(unit)
	if horde then RememberHorde(horde) end
	if not ident then return false, listed end
	RememberHorde(ident)
	local mapID, x, y = Sight.Spot()
	if not mapID then return false, "position" end
	local observer = CleanName(ns.me)
	local id = observer and Digest(table.concat({ "OLYS1", observer, ident.guid, now, mapID, x, y }, "|"))
	if not id then return false, "identity" end
	RememberOwn(ident.guid, now, mapID)
	local e = { id = id, guid = ident.guid, name = ident.name, mapID = mapID, x = x, y = y, layer = Sight.MyLayer(mapID),
		at = now, observer = observer, own = true, listed = listed }
	stats.sightSeen = stats.sightSeen + 1
	Keep(e)
	e.sent = SendSighting(e)
	Wanted.RefreshPins()
	return true, e
end

-- The No (or Yes again). Off, at once: no more collecting, what waits in Comm cancelled, what
-- reached a reviewer taken back (Withdraw), every pin off this client's map, and a reviewer stops
-- taking them: his lease goes off on the channel (WS~R~0), so members stop whispering him. On
-- again: a reviewer says at once that he takes them.
function Wanted.SetSightings(on, silent)
	if type(ns.db) ~= "table" then return false end
	on = on == true
	ns.db.wantedSightings = on
	if not on then
		knownHorde = {}
		CancelSightings("off")
		Sight.Withdraw()
		for guid in pairs(pins) do pins[guid] = nil end
		for key in pairs(ownSeen) do ownSeen[key] = nil end
		ownSeenCount = 0
		local C = ns.Comm
		if leaseAt ~= nil and type(C) == "table" and type(C.Send) == "function" then
			leaseAt = nil
			-- (The lease's key: a lease still waiting in Comm is replaced, not sent before it.)
			C.Send("CHANNEL", "WS~R~0", "wanted-reviewer", false, false, nil, { owner = Wanted })
		end
	end
	Wanted.RefreshPins()
	if not silent then ns.Print(on and L.WANTED_SIGHTINGS_ON or L.WANTED_SIGHTINGS_OFF) end
	if on and TakesSightings() and leaseAt == nil then Wanted.AnnounceReviewer() end
	return true
end

-- /oly sightings on | off; alone, says which.
function Wanted.SightingsSlash(rest)
	local word = type(rest) == "string" and rest:lower():match("^%s*(%S*)") or ""
	if word == "on" or word == "off" then return Wanted.SetSightings(word == "on") end
	ns.Print(SightingsOn() and L.WANTED_SIGHTINGS_ON or L.WANTED_SIGHTINGS_OFF)
	return true
end

-- The reviewer's lease: "I take sightings", on the channel (no place, no name but his own, which
-- the server stamps). Every client checks his role itself.
function Wanted.AnnounceReviewer()
	local C = ns.Comm
	if not TakesSightings() then return false, "reviewer" end
	if type(C) ~= "table" or type(C.Send) ~= "function" then return false, "transport" end
	leaseAt = math.floor(Clock())
	return C.Send("CHANNEL", "WS~R~1", "wanted-reviewer", false, false, nil, { owner = Wanted, guard = TakesSightings })
end

local function HeardLease(dist, sender, text)
	if dist ~= "CHANNEL" or (text ~= "WS~R~1" and text ~= "WS~R~0") then return false, "shape" end
	sender = CleanName(sender)
	-- His No: no lease, nothing waiting for him (only his own: the server stamps the sender).
	if text == "WS~R~0" then
		local key = sender and ns.Fold(sender)
		if not key or not reviewers[key] then return false, "unknown" end
		reviewers[key], reviewerCount = nil, reviewerCount - 1
		CancelSightings("reviewer", key)
		return true
	end
	if not sender or SameName(sender, ns.me) or not Wanted.CanPublish(sender) then return false, "authority" end
	local key, now = ns.Fold(sender), math.floor(Clock())
	if not reviewers[key] then
		if reviewerCount >= Wanted.REVIEWERS_MAX then
			local oldest
			for k, r in pairs(reviewers) do if not oldest or r.at < reviewers[oldest].at then oldest = k end end
			reviewers[oldest], reviewerCount = nil, reviewerCount - 1
			CancelSightings("reviewer", oldest)
		end
		reviewerCount = reviewerCount + 1
	end
	reviewers[key] = { key = key, name = sender, at = now }
	stats.leases = stats.leases + 1
	return true
end

-- The server says a reviewer is not online: no lease, nothing waiting for him.
SightingNotFound = function(who)
	local hit = false
	for key, r in pairs(reviewers) do
		if (ns.TellName(r.name) or ""):lower() == who or (ns.DisplayName(r.name) or ""):lower() == who then
			reviewers[key], reviewerCount = nil, reviewerCount - 1
			CancelSightings("offline", key)
			hit = true
		end
	end
	return hit
end

-- The sender speaks for an Olympus guild as the Olympus chats check it (Channels.VerifiedLevel),
-- and the moderators did not take him off.
local function FromOlympian(sender, guild)
	local Ch = ns.Channels
	if type(Ch) ~= "table" or Ch.missing or type(Ch.VerifiedLevel) ~= "function" then return false end
	local ok, level, verified = pcall(Ch.VerifiedLevel, sender, guild)
	if not ok or type(level) ~= "number" or level < 1 or verified ~= true then return false end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" then
		local okHides, hidden = pcall(M.Hides, sender, guild)
		if not okHides or hidden then return false end
	end
	return true
end

-- SIGHT_RECV_MAX a window from one sender, SIGHT_INTAKE_MAX from all, SIGHT_SENDERS_MAX counted.
local function SightAdmit(sender, now)
	if now - sightIntake.at >= Wanted.SIGHT_WINDOW or sightIntake.at > now then sightIntake.at, sightIntake.n = now, 0 end
	if sightIntake.n >= Wanted.SIGHT_INTAKE_MAX then return false end
	local key = ns.Fold(sender)
	local b = sightFrom[key]
	if not b then
		if sightFromCount >= Wanted.SIGHT_SENDERS_MAX then
			for other, held in pairs(sightFrom) do
				if now - held.at >= Wanted.SIGHT_WINDOW then sightFrom[other], sightFromCount = nil, sightFromCount - 1 end
			end
			if sightFromCount >= Wanted.SIGHT_SENDERS_MAX then return false end
		end
		b = { at = now, n = 0 }
		sightFrom[key], sightFromCount = b, sightFromCount + 1
	elseif now - b.at >= Wanted.SIGHT_WINDOW or b.at > now then
		b.at, b.n = now, 0
	end
	if b.n >= Wanted.SIGHT_RECV_MAX then return false end
	b.n, sightIntake.n = b.n + 1, sightIntake.n + 1
	return true
end

local function RememberSight(key)
	sightSeen[key] = true
	sightSeenOrder[#sightSeenOrder + 1] = key
	while #sightSeenOrder > Wanted.SIGHT_SEEN_MAX do sightSeen[table.remove(sightSeenOrder, 1)] = nil end
end

local function Refuse(why)
	stats.sightRefused = stats.sightRefused + 1
	return false, why
end

-- This window is full (everyone's, or this sender's): checked before anything is parsed.
function Sight.Full(sender, now)
	if now - sightIntake.at < Wanted.SIGHT_WINDOW and sightIntake.at <= now and sightIntake.n >= Wanted.SIGHT_INTAKE_MAX then return true end
	local b = sightFrom[ns.Fold(sender)]
	return b ~= nil and now - b.at < Wanted.SIGHT_WINDOW and b.at <= now and b.n >= Wanted.SIGHT_RECV_MAX
end

local function TakeSighting(dist, sender, text)
	if dist ~= "WHISPER" then return Refuse("lane") end
	if not TakesSightings() then return Refuse("reviewer") end
	local cleanSender = CleanName(sender)
	if cleanSender and Sight.Full(cleanSender, math.floor(Clock())) then stats.sightRate = stats.sightRate + 1 return false, "rate" end
	if #text > 255 then return Refuse("shape") end
	local version, guild, id, at, mapID, x, y, layer, wire, name =
		text:match("^WS~S~(%d+)~([^~]+)~(%x+)~(%d+)~(%d+)~(%d+)~(%d+)~(%d+)~([^~]+)~([^~]+)$")
	at, mapID, x, y, layer = tonumber(at), tonumber(mapID), tonumber(x), tonumber(y), tonumber(layer)
	local guid = GameGuid(wire)
	local ident = guid and Identity(name, guid) or nil
	guild = Sight.GuildName(guild)
	if version ~= "1" or not id or #id ~= 16 or not Whole(at, 0, 4294967295) or not Whole(x, 0, 1000) or not Whole(y, 0, 1000)
		or not Whole(layer, 0, 2147483647) or not Sight.OpenMap(mapID) or not ident or not ident.name or not guild then return Refuse("shape") end
	local now = math.floor(Clock())
	if at > now + Wanted.GLOBAL_SKEW or now - at > Wanted.SIGHT_TTL then return Refuse("stale") end
	sender = CleanName(sender)
	if not sender or SameName(sender, ns.me) then return Refuse("sender") end
	if not FromOlympian(sender, guild) then return Refuse("olympus") end
	local listed = Store(false)
	listed = listed and ResolveTarget(listed, ident, false)
	if not (listed and listed.active) then return Refuse("unlisted") end
	local key = ns.Fold(sender) .. "#" .. id
	if sightSeen[key] then stats.sightReplay = stats.sightReplay + 1 return false, "replay" end
	if not SightAdmit(sender, now) then stats.sightRate = stats.sightRate + 1 return false, "rate" end
	RememberSight(key)
	local e = { id = id, guid = ident.guid, name = ident.name, mapID = mapID, x = x, y = y, layer = layer, at = at,
		observer = sender, guild = guild, own = false }
	stats.sightTaken = stats.sightTaken + 1
	Keep(e)
	Wanted.RefreshPins()
	return true, e
end

-- The sender takes his sightings back (his No, or the King's crown hidden): his pins leave this
-- map, whatever this client's own answer. (Only his own: the server stamps the sender.)
function Sight.TakeBack(dist, sender, text)
	if dist ~= "WHISPER" or text ~= "WS~X~1" then return false, "shape" end
	sender = CleanName(sender)
	if not sender then return false, "sender" end
	local n = 0
	for guid, e in pairs(pins) do
		if not e.own and SameName(e.observer, sender) then pins[guid], n = nil, n + 1 end
	end
	stats.sightWithdrawn = stats.sightWithdrawn + n
	if n > 0 then Wanted.RefreshPins() end
	return true, n
end

function Wanted.HandleSighting(dist, sender, text)
	if type(text) ~= "string" or type(sender) ~= "string" then return false, "shape" end
	local kind = text:match("^WS~(%u)~")
	if kind == "R" then return HeardLease(dist, sender, text) end
	if kind == "S" then return TakeSighting(dist, sender, text) end
	if kind == "X" then return Sight.TakeBack(dist, sender, text) end
	return false, "shape"
end

-- The pins held now (copies), the newest first.
function Wanted.Sightings()
	local now, out = math.floor(Clock()), {}
	for _, e in pairs(pins) do
		if SightLive(e, now) then local c = {} for k, v in pairs(e) do c[k] = v end out[#out + 1] = c end
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then return a.at > b.at end
		return a.guid < b.guid
	end)
	return out
end

-- How long ago, in this computer's clock (ns.Ago) from the server's.
local function SightAgo(at)
	return ns.Ago(ns.Now() - math.max(0, math.floor(Clock()) - at))
end

-- A pin's hover: his name, his kills by this client's ledger, when and by whom he was seen, the
-- layer against this player's, and that the spot is where the Olympian stood.
function Wanted.SightingTip(tt, e)
	if type(tt) ~= "table" or type(e) ~= "table" then return false end
	tt:AddLine(Display({ name = e.name }), 1, 0.82, 0)
	local s = Store(false)
	local t = s and ResolveTarget(s, Identity(e.name, e.guid), false)
	if t and t.active then
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills or 0), 1, 1, 1)
		tt:AddLine(L.WANTED_BOUNTY:format(t.current or 0), 0.8, 0.8, 0.8)
	elseif t then
		-- Taken off the list here: his kills stay a fact, no bounty is said.
		tt:AddLine(L.WANTED_LIFETIME:format(t.lifetimeKills or 0), 1, 1, 1)
		tt:AddLine(L.WANTED_SIGHT_REMOVED, 0.8, 0.8, 0.8, true)
	else
		tt:AddLine(L.WANTED_SIGHT_UNLISTED, 0.8, 0.8, 0.8, true)
	end
	tt:AddLine(L.WANTED_SIGHT_SEEN:format(SightAgo(e.at), e.own and L.WANTED_SIGHT_BY_YOU or IssuerName(e.observer)), 1, 1, 1, true)
	if (e.layer or 0) > 0 then
		local mine = Sight.MyLayer(e.mapID)
		if mine > 0 then tt:AddLine(mine == e.layer and L.WANTED_SIGHT_YOUR_LAYER or L.WANTED_SIGHT_OTHER_LAYER, 0.8, 0.8, 0.8) end
	end
	tt:AddLine(L.WANTED_SIGHT_NEARBY, 0.6, 0.6, 0.6, true)
	return true
end

local function PinEnter(self)
	local e = self and self.sighting and pins[self.sighting]
	if not e or type(GameTooltip) ~= "table" then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	Wanted.SightingTip(GameTooltip, e)
	GameTooltip:Show()
end
local function PinLeave() if type(GameTooltip) == "table" then GameTooltip:Hide() end end

-- A pin's two frames: the world map's badge (Map.Badge: the orc banner in a red disc) and the
-- minimap's icon. nil where the map module or frames are missing.
local function MakeFrames()
	local M = ns.Map
	if type(M) ~= "table" or M.missing or type(M.Badge) ~= "function" or type(M.SetBadge) ~= "function" then return nil end
	local world = M.Badge(Wanted.SIGHT_BADGE, true)
	M.SetBadge(world, Wanted.Icon(), 0.8, 0.12, 0.08)
	world.badge:SetScript("OnEnter", PinEnter)
	world.badge:SetScript("OnLeave", PinLeave)
	local mini = CreateFrame("Frame", nil, UIParent)
	mini.olympus = true -- (ours: photo mode leaves it shown, UI.TogglePhoto)
	mini:SetSize(Wanted.SIGHT_MINI, Wanted.SIGHT_MINI)
	mini.icon = mini:CreateTexture(nil, "OVERLAY")
	mini.icon:SetAllPoints()
	mini.icon:SetTexture(Wanted.Icon())
	mini:EnableMouse(true)
	mini:SetScript("OnEnter", PinEnter)
	mini:SetScript("OnLeave", PinLeave)
	mini:Hide() -- (the pin library shows it when it puts it on the minimap)
	return { world = world, mini = mini }
end

local SIGHT_SHOW = HBD_PINS_WORLDMAP_SHOW_PARENT or 1

local function RefreshPinsNow()
	local now = math.floor(Clock())
	for guid, e in pairs(pins) do
		if not SightLive(e, now) then pins[guid] = nil stats.sightExpired = stats.sightExpired + 1 end
	end
	if next(pins) == nil and next(pinFrames) == nil then return true end -- (nothing to draw or take off)
	local P = ns.Pins and ns.Pins()
	if not P then return false end
	local world = ns.WorldMapIcons(P, Wanted)
	-- This map-menu choice hides only world-map artwork, not consent or minimap sightings.
	if ns.db and ns.db.showWanted == false then
		for _, f in pairs(pinFrames) do
			if world and f.onWorld then P:RemoveWorldMapIcon(Wanted, f.world) end
			f.onWorld = nil
		end
		world = false
	end
	-- Members only, never in an instance.
	local allowed = ns.IsMember ~= nil and ns.IsMember() == true and not InInstance()
	for guid, f in pairs(pinFrames) do
		if not (allowed and pins[guid]) then
			if world and f.onWorld then P:RemoveWorldMapIcon(Wanted, f.world) end
			P:RemoveMinimapIcon(Wanted, f.mini)
			f.world:Hide()
			f.mini:Hide()
			f.onWorld, f.drawn, f.world.badge.sighting, f.mini.sighting = nil, nil, nil, nil
			pinFrames[guid] = nil
			spareFrames[#spareFrames + 1] = f
		end
	end
	if not allowed then return true end
	for guid, e in pairs(pins) do
		local f = pinFrames[guid]
		if not f then
			f = table.remove(spareFrames) or MakeFrames()
			if not f then return false end
			pinFrames[guid] = f
		end
		f.world.badge.sighting, f.mini.sighting, f.world.since = guid, guid, e.at
		-- (With the gamepad UI ns.WorldMapIcons took this module's world icons off already.)
		if not world then f.onWorld = nil end
		if f.drawn ~= e or (world and not f.onWorld) then
			if world then
				P:AddWorldMapIconMap(Wanted, f.world, e.mapID, e.x / 1000, e.y / 1000, SIGHT_SHOW)
				f.onWorld = true
			end
			if f.drawn ~= e then P:AddMinimapIconMap(Wanted, f.mini, e.mapID, e.x / 1000, e.y / 1000, false, false) end
			f.drawn = e
		end
	end
	return true
end

function Wanted.RefreshPins()
	if ns.SafeCall then return ns.SafeCall("wanted pins", RefreshPinsNow) end
	return RefreshPinsNow()
end

-- (Tests: the frames each pin has now.)
function Wanted.PinFrames() return pinFrames end

-- A reviewer's lease is due: he takes sightings and has not said so for a beat (a few seconds'
-- slack: the timer's beat and the role's arrival may come close together).
local function LeaseDue()
	return TakesSightings() and (leaseAt == nil or math.floor(Clock()) - leaseAt >= Wanted.REVIEWER_EVERY - 5)
end

-- The lease, LOGIN's REVIEWER_FIRST later, then every REVIEWER_EVERY while the reviewer stays.
local function ScheduleLease(gen, wait)
	if not ns.After then return end
	ns.After(wait, "wanted reviewer", function()
		if gen ~= leaseGen then return end
		if LeaseDue() then Wanted.AnnounceReviewer() end
		ScheduleLease(gen, Wanted.REVIEWER_EVERY)
	end)
end

if ns.Consent and ns.Consent.Register then
	ns.Consent.Register({
		key = "wantedsightings", label = "CONSENT_WANTED_SIGHTINGS", text = "CONSENT_WANTED_SIGHTINGS_TEXT",
		shown = function() return ns.IsMember() == true and ns.faction ~= "Horde" end,
		get = function() return SightingsOn() end,
		set = function(on) Wanted.SetSightings(on) end,
		-- 1.2.0: off until its own Yes, and asked like the page's other lines until it is answered
		-- (1.2.1: the page opens by itself for it once, never again once shown); the bulk Yes never
		-- turns it on.
		pending = function() return type(ns.db) == "table" and ns.db.wantedSightings == nil end,
		explicit = true,
	})
end

---------------------------------------------------------------------------
-- Shared kills and deaths (1.2.3)
--
-- This client's own row (its player's own death to a Horde player, or his own killing blow on one)
-- goes at once to the Olympus channel, and every member's client counts it straight away:
--   WK~1~<scope>~<guild>~<digest>~<at>~<month>~<S|P>~<horde guid>~<own guid>~<horde name>
--       channel: one own row. S: the sender's death, a bounty on the Horde player. P: the
--       sender's killing blow, a claim of the Horde player's open bounty.
--   WK~R~1~<scope>~<from>~<b>~<digest>~<at>~<month>~<S|P>~<horde guid>~<own guid|->~<horde name>
--       channel: a reviewer's relay of a row his client took from <from>: b is 1 when his client
--       proved the GUID is the sender's (else 0, and no GUID: -).
--   WK~C~1~...   the same, in his answer to a late login's catch-up ask (W4)
--   WV~T~1~<scope>~<horde guid>~<at>            channel: a reviewer took that Horde player off
--   WV~V~1~<scope>~<from>~<digest>~<at>         channel: a reviewer voided that member's row
-- GUIDs as WY writes them (server.id), <scope> the realm group and faction (Scope), <digest> the
-- row's own (16 hex), <at> its time and <month> its month as the sender's client counted them.
-- What a receiver takes (Share.Take): a row of its own realm group and faction, fresh (SHARE_AGE,
-- GLOBAL_SKEW), from a member it verifies (its own guild's fresh roster, a guild rank it can verify
-- for the guild the row names, or a reviewer), whom the moderators do not hide, about the
-- sender's own death or killing blow: the Olympian side is the sender, by the name the server
-- stamps, his GUID only where this client proves it is his (GuidIsSender: a unit, or the game's
-- lookup), refused where it proves it is someone else's. The Horde side as the sender's client
-- proved it, refused where this client sees him as no Horde player (a unit, an Alliance race) or
-- as an Olympian. Once (its id: the sender and the digest), unless voided, SHARE_RATE_MAX a window
-- from one member and SHARE_TARGET_MAX about one Horde player from everyone. A relay only from a
-- reviewer (the King, a signed High Councillor, the author), on whose word a member this client
-- cannot verify (one of another guild, whose rank no census names) counts, SHARE_RELAY_MAX a
-- window from one. A mark (WV) only from a reviewer, on his own word. A client before 1.2.3 has
-- no handler for WK or WV, and ignores them.
---------------------------------------------------------------------------

Share.ALLIANCE_RACES = { Human = true, Dwarf = true, NightElf = true, Gnome = true, Draenei = true, Worgen = true,
	VoidElf = true, LightforgedDraenei = true, DarkIronDwarf = true, KulTiran = true, Mechagnome = true }

-- (This session's captures and refusals, the newest last, DIAG_MAX at most: /oly wanted status.)
-- kind: "kill" (own killing blow), "death" (own death), "heard" (a member's row), "relay" (a
-- reviewer's relay), "mark" (a reviewer's removal or void). why: the row recorded, or the reason.
function Share.Note(kind, ok, why, who, from)
	local reason = ok and "ok" or tostring(why or "?")
	Share.counts[kind] = (Share.counts[kind] or 0) + 1
	if ok then Share.counts.counted = (Share.counts.counted or 0) + 1 else Share.why[reason] = (Share.why[reason] or 0) + 1 end
	local e = ok and type(why) == "table" and why or nil
	local row = { at = math.floor(Clock()), kind = kind, ok = ok == true, why = not ok and reason or nil, who = Clean(who, 72),
		from = Clean(from, 72), action = e and e.action or nil, points = e and e.points or nil }
	Share.log[#Share.log + 1] = row
	while #Share.log > Wanted.DIAG_MAX do table.remove(Share.log, 1) end
	return row
end

-- One death's reading (PLAYER_DEAD and its retries): one line, the last answer.
function Share.NoteDeath(serial, ok, why, who)
	local last = Share.deathRow
	if last and last.serial == serial then
		Share.counts.death = math.max(0, (Share.counts.death or 1) - 1)
		if last.ok then Share.counts.counted = math.max(0, (Share.counts.counted or 1) - 1)
		else Share.why[last.why] = math.max(0, (Share.why[last.why] or 1) - 1) end
		for i = #Share.log, 1, -1 do if Share.log[i] == last then table.remove(Share.log, i) break end end
	end
	local row = Share.Note("death", ok, why, who)
	row.serial, Share.deathRow = serial, row
	return row
end

-- (A reviewer's own part of a few seconds: two reviewers online do not relay at the same moment.)
function Share.Offset()
	local n, me = 0, tostring(ns.me or "")
	for i = 1, #me do n = n + me:byte(i) end
	return n
end

-- A window's count for key, one more within max: false when it is full. The table holds keysMax
-- keys at most (SHARE_SENDERS_MAX by default; those whose window ended go first; none, false).
function Share.Count(list, key, now, window, max, keysMax)
	keysMax = keysMax or Wanted.SHARE_SENDERS_MAX
	local b = list[key]
	if not b then
		if Count(list) >= keysMax then
			for other, held in pairs(list) do if now - held.at >= window or held.at > now then list[other] = nil end end
			if Count(list) >= keysMax then return false end
		end
		b = { at = now, n = 0 }
		list[key] = b
	elseif now - b.at >= window or b.at > now then
		b.at, b.n = now, 0
	end
	if b.n >= max then return false end
	b.n = b.n + 1
	return true
end

-- SHARE_RATE_MAX rows a window from one member and SHARE_DAY_MAX a day (SHARE_RELAY_MAX a window
-- from one reviewer's relays), and SHARE_TARGET_MAX about one Horde player from everyone.
function Share.Admit(who, hordeGuid, now, relay)
	local key, max = ns.Fold(who), Wanted.SHARE_RATE_MAX
	if relay then key, max = "r:" .. key, Wanted.SHARE_RELAY_MAX end
	if not Share.Count(Share.rates, key, now, Wanted.SHARE_RATE_WINDOW, max) then return false, "rate" end
	if not relay and not Share.Count(Share.days, key, now, Wanted.SHARE_DAY, Wanted.SHARE_DAY_MAX, Wanted.SHARE_DAY_SENDERS_MAX) then
		return false, "rate"
	end
	if not Share.Count(Share.targets, hordeGuid, now, Wanted.SHARE_TARGET_WINDOW, Wanted.SHARE_TARGET_MAX) then return false, "target" end
	return true
end

-- A row's Horde side and Olympian side as the wire carries them: (horde GUID, Olympian GUID, the
-- Horde player's name).
function Share.Sides(e)
	if e.action == "bounty" then return e.killerGuid, e.victimGuid, e.killerName end
	return e.victimGuid, e.killerGuid, e.victimName
end

-- This client's own row on the channel (WK~1), its done marking it shared (saved); one the channel
-- did not take goes again later (Share.Resend). Nothing goes from a client outside an Olympus
-- guild, of the Horde, or one the moderators took off (net-off).
function Share.Send(e)
	if type(e) ~= "table" or not e.own or e.void or not e.digest then return false, "row" end
	local C = ns.Comm
	if type(C) ~= "table" or type(C.Send) ~= "function" then return false, "transport" end
	if not ns.IsMember or ns.IsMember() ~= true or ns.faction == "Horde" or NetOff() then return false, "member" end
	local guild = Sight.OwnGuild()
	if not guild then return false, "guild" end
	local horde, own, name = Share.Sides(e)
	name = CleanName(name)
	if not WireGuid(horde) or not WireGuid(own) or not name then return false, "shape" end
	local scope = Scope()
	local body = table.concat({ "WK", 1, scope, guild, e.digest, e.at, e.month, e.kind == "SELF_DEATH" and "S" or "P",
		WireGuid(horde), WireGuid(own), name }, "~")
	if #body > 255 then return false, "size" end
	local sent = C.Send("CHANNEL", body, "wanted-kill:" .. e.digest, false, false, function(went)
		if went then e.shared = true end
		local key = went and "sent" or "unsent"
		Share.counts[key] = (Share.counts[key] or 0) + 1
	end, { owner = Wanted, guardKey = "wanted-kill", guard = function()
		return ns.IsMember() == true and ns.faction ~= "Horde" and not NetOff() and Scope() == scope
	end })
	return sent == true
end

-- This client's own rows the channel did not take (sent while it was not on it, or refused there)
-- go again, SHARE_RESEND_MAX at a time, while they are fresh (SHARE_AGE).
function Share.Resend()
	local s = Store(false)
	if not s then return 0 end
	local now, n = math.floor(Clock()), 0
	for i = #s.evidence, 1, -1 do
		if n >= Wanted.SHARE_RESEND_MAX then break end
		local e = s.evidence[i]
		local t = s.targets[e.targetKey]
		if e.own and not e.shared and not e.void and type(t) == "table" and t.active == true
			and now - (tonumber(e.at) or 0) <= Wanted.SHARE_AGE and Share.Send(e) then n = n + 1 end
	end
	return n
end

function Share.ScheduleResend(gen, wait)
	if not ns.After then return end
	ns.After(wait, "wanted resend", function()
		if gen ~= Share.resendGen then return end
		Share.Resend()
		Share.ScheduleResend(gen, Wanted.SHARE_RESEND_EVERY)
	end)
end

-- A relayed row's id remembered (SHARE_HEARD_MAX): this reviewer relays it no more.
function Share.Heard(id)
	if Share.relayed[id] then return end
	Share.relayed[id] = true
	Share.relayedOrder[#Share.relayedOrder + 1] = id
	while #Share.relayedOrder > Wanted.SHARE_HEARD_MAX do Share.relayed[table.remove(Share.relayedOrder, 1)] = nil end
end

-- A reviewer's relay of a row his client holds (via "R": one he took now, "C": a catch-up answer),
-- while Comm's queue has room (SHARE_ROOM kept free).
function Share.Relay(e, via)
	local C = ns.Comm
	if type(C) ~= "table" or type(C.Send) ~= "function" or not Wanted.CanPublish(ns.me) then return false end
	if type(C.QueueRoom) == "function" and C.QueueRoom() <= Wanted.SHARE_ROOM then return false end
	local horde, own, name = Share.Sides(e)
	local from = CleanName(e.from)
	name = CleanName(name)
	if not (e.own or e.peer) or e.void or not from or not name or not WireGuid(horde) or type(e.digest) ~= "string" then return false end
	local scope = Scope()
	local body = table.concat({ "WK", via, 1, scope, from, WireGuid(own) and 1 or 0, e.digest, e.at, e.month,
		e.kind == "SELF_DEATH" and "S" or "P", WireGuid(horde), WireGuid(own) or "-", name }, "~")
	if #body > 255 then return false end
	Share.Heard(e.id)
	return C.Send("CHANNEL", body, "wanted-relay:" .. via .. ":" .. e.id, false, false, nil, { owner = Wanted, guardKey = "wanted-relay",
		guard = function() return Wanted.CanPublish(ns.me) and Scope() == scope end }) == true
end

-- A reviewer relays a row he took from a member (once, SHARE_RELAY_DELAY and a part of 8 s of his
-- own later, unless another reviewer's relay of it came first), so that the members whose clients
-- cannot verify its sender (other guilds') count it on his word.
function Share.RelaySoon(e)
	local function Go()
		if Share.relayed[e.id] or e.void or not Wanted.CanPublish(ns.me) then return end
		Share.Relay(e, "R")
	end
	if ns.After then ns.After(Wanted.SHARE_RELAY_DELAY + Share.Offset() % 8, "wanted relay", Go) else Go() end
end

-- WK's fields, or nil.
function Share.Parse(text)
	if type(text) ~= "string" or #text > 255 then return nil end
	local r = {}
	if text:sub(1, 5) == "WK~1~" then
		r.scope, r.guild, r.digest, r.at, r.month, r.kind, r.horde, r.own, r.name =
			text:match("^WK~1~(%x+)~([^~]+)~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~([^~]+)$")
	else
		r.via, r.scope, r.from, r.bound, r.digest, r.at, r.month, r.kind, r.horde, r.own, r.name =
			text:match("^WK~([RC])~1~(%x+)~([^~]+)~([01])~(%x+)~(%d+)~(%d+)~([PS])~([^~]+)~([^~]+)~([^~]+)$")
	end
	if not r.scope or #r.digest ~= 16 then return nil end
	r.at, r.month = Whole(tonumber(r.at), 0, 4294967295), Whole(tonumber(r.month), 0, 120000)
	r.horde = GameGuid(r.horde)
	if r.own == "-" then r.own = nil elseif r.own then r.own = GameGuid(r.own) or false end
	if not r.at or not r.month or not r.horde or r.own == false or not r.via and not r.own then return nil end
	return r
end

-- Whether two names can be one character's: the same given name (Forever's death recap, and a
-- client the game's lookup did not answer, write "Given-Realm"; the lookup "Given Surname-Realm").
function Share.SameGiven(a, b)
	local function Given(name) return ns.Fold((ns.ShortName(tostring(name or "")) or ""):match("^%s*(%S+)") or "") end
	local given = Given(a)
	return given ~= "" and given == Given(b)
end

-- One shared row (WK) taken into this client's ledger: true and the row recorded, or false, why.
function Share.Take(dist, sender, row)
	if dist ~= "CHANNEL" then return false, "lane" end
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if ns.faction == "Horde" then return false, "faction" end
	if not row then return false, "shape" end
	if row.scope ~= Scope() then return false, "scope" end
	sender = CleanName(sender)
	if not sender then return false, "sender" end
	local relay = row.via ~= nil
	local from = relay and CleanName(row.from) or sender
	if not from then return false, "shape" end
	-- (Our own row, back in a reviewer's relay: this client holds it.)
	if SameName(from, ns.me) then return false, "own" end
	if relay and not Wanted.CanPublish(sender) then return false, "authority" end
	local now = math.floor(Clock())
	if row.at > now + Wanted.GLOBAL_SKEW or now - row.at > Wanted.SHARE_AGE then return false, "stale" end
	if not Whole(row.month, MonthNow() - Wanted.MAX_MONTHS + 1, MonthNow() + 1) then return false, "shape" end
	local M = ns.Moderation
	if type(M) == "table" and not M.missing and type(M.Hides) == "function" then
		local ok, hidden = pcall(M.Hides, from)
		if not ok or hidden then return false, "olympus" end
	end
	if not relay and not Wanted.CanPublish(from) and not EvidenceMember(from, Sight.GuildName(row.guild)) then return false, "olympus" end
	local horde = Identity(row.name, row.horde)
	if not horde or not horde.name then return false, "shape" end
	-- The Horde side as the sender's client proved it, unless this client sees him otherwise.
	if VerifiedOlympian(horde) then return false, "olympus" end
	local seen, contradicted = KnownHorde(horde)
	if contradicted then return false, "faction" end
	if not seen and type(GetPlayerInfoByGUID) == "function" then
		local ok, _, _, _, race = pcall(GetPlayerInfoByGUID, horde.guid)
		if ok and type(race) == "string" and not Secret(race) and Share.ALLIANCE_RACES[race] then return false, "faction" end
	end
	-- His name as this client's game knows his GUID (a unit of his, or its lookup), never as the
	-- row writes it: a row that gives his GUID another character's name is refused. One the game
	-- cannot check keeps the row's name as its sender's word (wire): it finds and teaches no entry
	-- by that name, and holds the name's alias only where no better entry does (Share.Name).
	local known = seen and seen.name or Share.InfoName(horde.guid)
	local wire = known == nil
	if known then
		if not Share.SameGiven(known, horde.name) then return false, "identity" end
		horde = Identity(known, horde.guid)
		if not horde or not horde.name then return false, "shape" end
		if VerifiedOlympian(horde) then return false, "olympus" end
	end
	-- The Olympian side: the sender, his GUID only where this client proves it is his (or the
	-- reviewer who relays it says his own client did).
	local ownGuid = row.own
	if ownGuid then
		local mine = GuidIsSender(ownGuid, from)
		if mine == false then return false, "not-own" end
		if mine == nil and not (relay and row.bound == "1") then ownGuid = nil end
	end
	local s = Store(true)
	if not s then return false, "store" end
	local key = ns.Fold(from) .. "#" .. row.digest
	if s.voids[key] then return false, "void" end
	local id = "p:" .. key
	if s.seen[id] then return false, "replay" end
	local admitted, why = Share.Admit(relay and sender or from, horde.guid, now, relay)
	if not admitted then return false, why end
	local olympian = Identity(from, ownGuid)
	local killer, victim, side = olympian, horde, "victim"
	if row.kind == "S" then killer, victim, side = horde, olympian, "killer" end
	local ok, e = RecordKill(row.kind == "S" and "SELF_DEATH" or "PARTY_KILL", id, killer, victim,
		{ peer = true, from = from, digest = row.digest, id = id, at = row.at, month = row.month, horde = side, wire = wire })
	-- (A reviewer relays what he took from a member; another reviewer's own row every client takes
	-- from him directly.)
	if ok and not relay and Wanted.CanPublish(ns.me) and not Wanted.CanPublish(from) then Share.RelaySoon(e) end
	return ok, e
end

-- The WK handler: a member's row, or a reviewer's relay of one.
function Wanted.HandleShared(dist, sender, text)
	local row = Share.Parse(text)
	-- A reviewer's relay of a row, whatever this client makes of it: this reviewer's own relay of it
	-- is not needed any more, nor, after a catch-up answer, his own answer.
	if row and row.via and dist == "CHANNEL" and Wanted.CanPublish(CleanName(sender)) then
		local from = CleanName(row.from)
		if from then Share.Heard("p:" .. ns.Fold(from) .. "#" .. row.digest) end
		if row.via == "C" then Share.catchHeard = math.floor(Clock()) end
	end
	local ok, e = Share.Take(dist, sender, row)
	-- (Not noted: our own row coming back, and a relay of a row held already.)
	if ok or not (e == "own" or e == "replay" and row and row.via) then
		Share.Note(row and row.via and "relay" or "heard", ok, e, row and row.name, row and row.from or sender)
	end
	return ok, e
end

-- A reviewer's mark on the channel (WV): "T" a Horde player taken off (a: his GUID), "V" a row
-- voided (a: its sender, b: its digest). at: when (now by default).
function Share.SendMark(kind, a, b, at)
	local C = ns.Comm
	if type(C) ~= "table" or type(C.Send) ~= "function" or not Wanted.CanPublish(ns.me) then return false end
	at = Whole(at, 0, 4294967295) or math.floor(Clock())
	local scope, body, key = Scope(), nil, nil
	if kind == "T" then
		local wire = WireGuid(a)
		if not wire then return false end
		body, key = table.concat({ "WV", "T", 1, scope, wire, at }, "~"), wire
	else
		local from = CleanName(a)
		if not from or type(b) ~= "string" or not b:match("^%x+$") or #b ~= 16 then return false end
		body, key = table.concat({ "WV", "V", 1, scope, from, b, at }, "~"), ns.Fold(from) .. "#" .. b
	end
	if #body > 255 then return false end
	return C.Send("CHANNEL", body, "wanted-mark:" .. kind .. ":" .. key, false, false, nil, { owner = Wanted, guardKey = "wanted-mark",
		guard = function() return Wanted.CanPublish(ns.me) and Scope() == scope end }) == true
end

-- The WV handler: a reviewer's word that a Horde player is off (his rows count for nothing here
-- any more, and a later event does not bring him in: an entry is kept for him, off), or that one
-- member's row is void (and one heard later too).
function Share.Mark(dist, sender, text)
	if dist ~= "CHANNEL" then return false, "lane" end
	if not ns.IsMember or ns.IsMember() ~= true or not ns.me then return false, "member" end
	if type(text) ~= "string" or #text > 255 then return false, "shape" end
	sender = CleanName(sender)
	if not sender or SameName(sender, ns.me) then return false, "own" end
	if not Wanted.CanPublish(sender) then return false, "authority" end
	local kind, scope, a, b, at = text:sub(4, 4), nil, nil, nil, nil
	if kind == "T" then scope, a, at = text:match("^WV~T~1~(%x+)~([^~]+)~(%d+)$")
	elseif kind == "V" then scope, a, b, at = text:match("^WV~V~1~(%x+)~([^~]+)~(%x+)~(%d+)$") end
	if not scope then return false, "shape" end
	if scope ~= Scope() then return false, "scope" end
	at = Whole(tonumber(at), 0, 4294967295)
	local now = math.floor(Clock())
	if not at or at > now + Wanted.GLOBAL_SKEW or now - at > Wanted.SHARE_AGE then return false, "stale" end
	if not Share.Count(Share.rates, "m:" .. ns.Fold(sender), now, Wanted.SHARE_RATE_WINDOW, Wanted.SHARE_RELAY_MAX) then return false, "rate" end
	local s = Store(true)
	if not s then return false, "store" end
	if kind == "T" then
		local guid = GameGuid(a)
		if not guid then return false, "shape" end
		local key = GuidKey(guid)
		local t = s.targets[s.aliases[key] or key]
		if type(t) == "table" and t.guid == guid then
			if t.active ~= true then return false, "held" end
			Share.TakeOff(s, t, sender, at)
		else
			-- No entry here: one is kept for him, off, so that a later event does not bring him in.
			-- (Apart from the list: it takes no place there, MAX_REMOVED.)
			t = { key = key, guid = guid, active = false, removedAt = at, removedBy = sender, addedAt = at, source = "removed",
				current = 0, lifetimeKills = 0, cycle = 1, openSince = at, victims = {}, claims = {}, victimOverflow = 0 }
			s.targets[key], s.aliases[key] = t, key
			Share.TrimRemoved(s)
		end
		Audit(s, "remove", t.key, sender)
		if opened == t.key then mode, opened = "list", nil end
	else
		local from = CleanName(a)
		if not from or #b ~= 16 then return false, "shape" end
		if s.voids[ns.Fold(from) .. "#" .. b] then return false, "held" end
		Share.KeepVoid(s, from, b, at)
		for _, e in ipairs(s.evidence) do
			if not e.void and e.digest == b and SameName(e.from, from) then
				e.void, e.correctedAt, e.correctedBy = true, at, sender
				Audit(s, "correct", e.targetKey, e.id)
			end
		end
		Rebuild(s)
	end
	Changed()
	return true
end

function Wanted.HandleMark(dist, sender, text)
	local ok, why = Share.Mark(dist, sender, text)
	if ok or why ~= "own" and why ~= "held" then Share.Note("mark", ok, why, nil, sender) end
	return ok, why
end

-- A late login's catch-up ask (W4, AskGlobal): a reviewer answers with the Horde players taken off
-- and the rows voided lately (SHARE_CATCH_MARKS each), then the newest rows his client holds
-- (SHARE_CATCH_ROWS, of SHARE_AGE), once every GLOBAL_ASK_GAP at most, a part of 20 s of his own
-- after the ask, and not when another reviewer's answer came first; only what Comm's queue has
-- room for (SHARE_ROOM kept free).
function Share.Answer(dist, sender, text)
	if dist ~= "CHANNEL" or text ~= "W4~1" or SameName(sender, ns.me) or not Wanted.CanPublish(ns.me) then return false end
	local now = math.floor(Clock())
	if now - Share.catchReplied < Wanted.GLOBAL_ASK_GAP then return false, "rate" end
	Share.catchReplied = now
	local function Go()
		if Share.catchHeard >= now or not Wanted.CanPublish(ns.me) then return end
		Share.CatchUp()
	end
	if ns.After then ns.After(2 + Share.Offset() % 20, "wanted catch-up", Go) else Go() end
	return true
end

function Share.CatchUp()
	local s, C = Store(false), ns.Comm
	if not s or type(C) ~= "table" then return 0 end
	local now, n = math.floor(Clock()), 0
	local function Fresh(at) return now - (tonumber(at) or 0) <= Wanted.SHARE_AGE end
	local off = {}
	for _, t in pairs(s.targets) do if t.active ~= true and Guid(t.guid) and Fresh(t.removedAt) then off[#off + 1] = t end end
	table.sort(off, function(a, b) return (a.removedAt or 0) > (b.removedAt or 0) end)
	for i = 1, math.min(#off, Wanted.SHARE_CATCH_MARKS) do
		if type(C.QueueRoom) == "function" and C.QueueRoom() <= Wanted.SHARE_ROOM then return n end
		if Share.SendMark("T", off[i].guid, nil, off[i].removedAt) then n = n + 1 end
	end
	local voids = {}
	for _, v in pairs(s.voids) do if type(v) == "table" and Fresh(v.at) then voids[#voids + 1] = v end end
	table.sort(voids, function(a, b) return (a.at or 0) > (b.at or 0) end)
	for i = 1, math.min(#voids, Wanted.SHARE_CATCH_MARKS) do
		if type(C.QueueRoom) == "function" and C.QueueRoom() <= Wanted.SHARE_ROOM then return n end
		if Share.SendMark("V", voids[i].from, voids[i].digest, voids[i].at) then n = n + 1 end
	end
	-- The newest rows, sent oldest first: each client takes them in the order of the deaths.
	local rows = {}
	for i = #s.evidence, 1, -1 do
		if #rows >= Wanted.SHARE_CATCH_ROWS then break end
		local e = s.evidence[i]
		local t = s.targets[e.targetKey]
		if (e.own or e.peer) and not e.void and Fresh(e.at) and type(t) == "table" and t.active == true then rows[#rows + 1] = e end
	end
	for i = #rows, 1, -1 do if Share.Relay(rows[i], "C") then n = n + 1 end end
	return n
end

-- /oly wanted status: what Most Wanted holds and did this session, in the copy window (a chat line
-- cannot be copied): the store, the sources it reads (the game's own APIs, the native kill event's
-- registration), what this client captured and shared, what it heard, and why each capture or row
-- was refused, the newest first, with a key to the reasons.
function Wanted.StatusText()
	local s = Store(false)
	local out = {}
	local function Add(text) out[#out + 1] = text end
	local function Yes(v) return v and L.WANTED_STATUS_YES or L.WANTED_STATUS_NO end
	local active, off, rows, mine, unsent = 0, 0, 0, 0, 0
	for _, t in pairs(s and s.targets or {}) do if t.active then active = active + 1 else off = off + 1 end end
	for _, e in ipairs(s and s.evidence or {}) do
		if not e.void then rows = rows + 1 end
		if e.own then mine = mine + 1 if not e.shared then unsent = unsent + 1 end end
	end
	Add(L.WANTED_STATUS_STORE:format(tostring(ns.group or ns.realm or "?"), tostring(ns.faction or "?"), active, off, rows,
		Count(s and s.slayers or {}), s and L.WANTED_STATUS_YES or L.WANTED_STATUS_NO))
	local C = ns.Comm
	Add(L.WANTED_STATUS_SOURCES:format(Yes(Share.partyKill), Yes(type(C_DeathRecap) == "table" and type(C_DeathRecap.GetRecapEvents) == "function"),
		Yes(type(GetPlayerInfoByGUID) == "function"), Yes(InInstance()),
		Yes(type(C) == "table" and type(C.ChannelReady) == "function" and C.ChannelReady() == true)))
	local n = Share.counts
	Add(L.WANTED_STATUS_SESSION:format(n.kill or 0, n.death or 0, n.sent or 0, n.unsent or 0, mine, unsent,
		n.heard or 0, n.relay or 0, n.mark or 0, n.counted or 0))
	local reasons = {}
	for why, count in pairs(Share.why) do if count > 0 then reasons[#reasons + 1] = why .. " " .. count end end
	table.sort(reasons)
	Add(L.WANTED_STATUS_REFUSED:format(#reasons > 0 and table.concat(reasons, ", ") or "-"))
	Add("")
	Add(L.WANTED_STATUS_LAST)
	local kinds = { kill = L.WANTED_STATUS_KILL, death = L.WANTED_STATUS_DEATH, heard = L.WANTED_STATUS_HEARD,
		relay = L.WANTED_STATUS_RELAY, mark = L.WANTED_STATUS_MARK }
	local dateFn = date or (os and os.date)
	for i = #Share.log, 1, -1 do
		local r = Share.log[i]
		local when = type(dateFn) == "function" and dateFn("%H:%M:%S", r.at) or tostring(r.at)
		local result = r.ok and (r.action == "claim" and L.WANTED_STATUS_CLAIM:format(r.points or 0) or L.WANTED_STATUS_BOUNTY)
			or L.WANTED_STATUS_REFUSAL:format(r.why or "?")
		Add(("  %s  %s  %s%s  %s"):format(when, kinds[r.kind] or r.kind, r.who or "?", r.from and (" · " .. r.from) or "", result))
	end
	if #Share.log == 0 then Add("  " .. L.WANTED_STATUS_EMPTY) end
	Add("")
	Add(L.WANTED_STATUS_KEY)
	return table.concat(out, "\n")
end

function Wanted.ShowStatus()
	local text = Wanted.StatusText()
	if ns.UI and ns.UI.ShowCopy then
		ns.UI.ShowCopy(L.WANTED_STATUS_TITLE, text, { label = L.WANTED_STATUS_REFRESH, fn = function() Wanted.ShowStatus() end },
			{ key = "wanted", big = true })
		return true
	end
	for line in text:gmatch("[^\n]+") do ns.Print(line) end
	return true
end

-- /oly wanted [status]
function Wanted.Slash(rest)
	local word = (tostring(rest or ""):match("^%s*(%S*)") or ""):lower()
	if word == "" or word == "status" then return Wanted.ShowStatus() end
	ns.Print(L.WANTED_STATUS_USAGE)
	return false
end

function Wanted.Prune()
	local s = Store(false)
	if not s then return false end
	local SOURCES = { manual = true, SELF_DEATH = true, PARTY_KILL = true, shared = true, removed = true }
	for key, t in pairs(s.targets) do
		local ident = type(t) == "table" and Identity(t.name, t.guid, t.realm) or nil
		if not ident or type(key) ~= "string" then
			s.targets[key] = nil
		else
			t.key, t.name, t.guid, t.realm = key, ident.name, ident.guid, ident.realm
			t.active = t.active == true
			t.addedAt = Whole(t.addedAt, 0, 4294967295) or 0
			t.addedBy = CleanName(t.addedBy)
			t.source = SOURCES[t.source] and t.source or "manual"
			t.removedAt, t.removedBy = Whole(t.removedAt, 0, 4294967295), CleanName(t.removedBy)
			t.wireName = t.wireName == true and t.name ~= nil or nil
			local d = TargetDerived(t)
			for field, value in pairs(d) do t[field] = value end
			t.victims, t.claims = CopyList(t.victims, Wanted.MAX_VICTIMS), CopyList(t.claims, Wanted.MAX_CLAIMS)
			if ident.guidKey then s.aliases[ident.guidKey] = key end
		end
	end
	local evidence, first = {}, math.max(1, #s.evidence - Wanted.MAX_EVIDENCE + 1)
	for i = first, #s.evidence do
		local e = s.evidence[i]
		local id = type(e) == "table" and Clean(e.id, 160) or nil
		local targetKey = type(e) == "table" and type(e.targetKey) == "string" and (s.aliases[e.targetKey] or e.targetKey) or nil
		local target = targetKey and s.targets[targetKey] or nil
		local killer = type(e) == "table" and Identity(e.killerName, e.killerGuid) or nil
		local victim = type(e) == "table" and Identity(e.victimName, e.victimGuid) or nil
		local targetIdentity = e and e.action == "bounty" and killer or victim
		-- (1.2.3: a shared row's Olympian side may be its sender's name alone.)
		local peer = type(e) == "table" and e.peer == true
		local olympian = e and e.action == "bounty" and victim or killer
		if id and target and killer and killer.name and victim and victim.name and targetIdentity and targetIdentity.guid
			and (olympian and olympian.guid or peer)
			and (e.kind == "PARTY_KILL" or e.kind == "SELF_DEATH") and (e.action == "bounty" or e.action == "claim")
			and SameIdentity(Identity(target), targetIdentity) and Whole(e.at, 0, 4294967295) and Whole(e.month, 0, 200000) then
			local digest = type(e.digest) == "string" and e.digest:match("^%x+$") and #e.digest == 16 and e.digest or nil
			evidence[#evidence + 1] = { id = id, seq = Whole(e.seq, 0, 2147483647) or 0, at = math.floor(e.at), month = math.floor(e.month),
				kind = e.kind, action = e.action, targetKey = targetKey, killerName = killer.name, killerGuid = killer.guid,
				victimName = victim.name, victimGuid = victim.guid, zone = Clean(e.zone, 80),
				precision = e.precision == "consented" and "consented" or "approximate", void = e.void == true,
				correctedAt = Whole(e.correctedAt, 0, 4294967295), correctedBy = CleanName(e.correctedBy),
				correction = Clean(e.correction, 80), from = CleanName(e.from), digest = digest,
				peer = peer or nil, own = e.own == true and not peer or nil, shared = e.shared == true or nil }
		end
	end
	-- (In the order of the deaths, as RecordKill keeps them.)
	for i = 2, #evidence do
		local e, j = evidence[i], i
		while j > 1 and evidence[j - 1].at > e.at do evidence[j] = evidence[j - 1] j = j - 1 end
		evidence[j] = e
	end
	s.evidence = evidence
	-- (The names' aliases, 1.2.3: each name to the best entry under it, Share.Better.)
	for alias, held in pairs(s.aliases) do
		if type(alias) ~= "string" or type(s.targets[held]) ~= "table" then s.aliases[alias] = nil end
	end
	for key, t in pairs(s.targets) do
		local nk = NameKey(t.name)
		if nk and nk ~= key then
			local holder = s.targets[s.aliases[nk] or nk]
			if holder ~= t and Share.Better(t, holder) then s.aliases[nk] = key end
		end
	end
	local order, seen, have = {}, {}, {}
	first = math.max(1, #s.seenOrder - Wanted.MAX_SEEN + 1)
	for i = first, #s.seenOrder do
		local id = Clean(s.seenOrder[i], 160)
		local old = id and s.seen[id]
		if id and not have[id] and type(old) == "table" then
			local at, seq = Whole(old.at, 0, 4294967295), Whole(old.seq, 0, 2147483647)
			if at and seq then order[#order + 1], seen[id], have[id] = id, { at = at, seq = seq }, true end
		end
	end
	s.seenOrder, s.seen = order, seen
	local now = math.floor(Clock())
	for fingerprint, at in pairs(s.recent) do
		if type(fingerprint) ~= "string" or not Whole(at, 0, 4294967295) or now - at > 30 then s.recent[fingerprint] = nil end
	end
	TrimList(s.audit, Wanted.MAX_AUDIT)
	-- The voided shared rows, by shape (1.2.3), within SHARE_AGE and VOIDS_MAX.
	for key, v in pairs(s.voids) do
		if type(key) ~= "string" or #key > 120 or type(v) ~= "table" or not Whole(v.at, 0, 4294967295) or not CleanName(v.from)
			or type(v.digest) ~= "string" or now - v.at > Wanted.SHARE_AGE then s.voids[key] = nil end
	end
	s.foldedAt = Whole(s.foldedAt, 0, 4294967295)
	-- 1.2.2's review: its ledger (a reviewer's accepted rows) and when his evidence went to each
	-- reviewer. There is no review any more (1.2.3); they count for nothing and are dropped.
	s.ledger, s.sentAt = nil, nil
	-- The saved word, by shape only: RestoreGlobal checks everything else before it shows it.
	local g = s.global
	if type(g) ~= "table" or type(g.text) ~= "string" or #g.text > 1200 or type(g.issuer) ~= "string" then s.global = nil end
	if type(s.globalHeads) ~= "table" then s.globalHeads = nil end
	if type(s.reviewer) ~= "string" or not CleanName(s.reviewer) then s.reviewer = nil end
	Rebuild(s)
	for _, r in pairs(s.slayers) do TrimMonths(r, MonthNow()) end
	return true
end

-- At login: the saved data checked (Prune), the saved word looked at again (RestoreGlobal),
-- and the publisher's own last word repeated once he is back online (the same body and expiry),
-- unless a newer one replaced it. On LOGIN (PLAYER_LOGIN), not INIT (ADDON_LOADED): only then
-- does the client know the character's name (ns.me), and so whether the word is his, and its
-- faction's store (ns.CheckFaction). 1.2.3: this client's own rows the channel did not take go
-- again SHARE_RESEND_FIRST after login, then every SHARE_RESEND_EVERY.
function Wanted.Load()
	Wanted.Prune()
	local p = type(ns.db) == "table" and type(ns.db.wantedPublisher) == "table" and ns.db.wantedPublisher.last or nil
	if not publishedGlobal and type(p) == "table" and type(p.body) == "string" and Whole(p.expires, 0, 4294967295)
		and not p.replaced and p.expires >= math.floor(Clock()) and SameName(p.issuer, ns.me) and p.scope == Scope() then
		local held = { body = p.body, expires = p.expires, issuer = p.issuer, scope = p.scope }
		publishedGlobal = held
		if ns.After then
			ns.After(Wanted.GLOBAL_LOGIN_REPEAT, "wanted global login", function()
				if publishedGlobal ~= held or held.replaced then return end
				Wanted.RepeatGlobal()
				ScheduleGlobalRepeat(held, Wanted.GLOBAL_BURST)
			end)
		end
	end
	-- Once the publisher's own word is known: a newer saved word, checked again, replaces it.
	RestoreGlobal()
	Wanted.globalCatch.generation = Wanted.globalCatch.generation + 1
	Wanted.ScheduleGlobalCatchUp(Wanted.globalCatch.generation, 1)
	-- Sightings: a reviewer's lease REVIEWER_FIRST after login (his name is known now), then on
	-- its beat; the pins expire on theirs.
	leaseGen = leaseGen + 1
	ScheduleLease(leaseGen, Wanted.REVIEWER_FIRST)
	Share.resendGen = (Share.resendGen or 0) + 1
	Share.ScheduleResend(Share.resendGen, Wanted.SHARE_RESEND_FIRST)
	if ns.Every and not pinTicker then
		pinTicker = true
		ns.Every(Wanted.SIGHT_TICK, "wanted pins", Wanted.RefreshPins)
	end
	return true
end

function Wanted.Stats() return stats end
-- (Tests: this session's shared-row state, as /oly wanted status reads it.)
function Wanted.ShareState() return Share end
function Wanted.ResetForTests()
	deathSerial = deathSerial + 1
	knownHorde = {}
	rate, mode, opened = {}, "list", nil
	authenticatedGlobal, globalFloor, publisherHeads = nil, nil, {}
	pendingGlobal, pendingGlobalCount = {}, 0
	publishedGlobal = nil
	Wanted.globalCatch.asked, Wanted.globalCatch.replied = -math.huge, -math.huge
	Wanted.globalCatch.generation = Wanted.globalCatch.generation + 1
	restoring, restoreChecked = nil, {}
	pins, pinFrames, spareFrames = {}, {}, {}
	sightSeen, sightSeenOrder, ownSeen, ownSeenCount, sightSends = {}, {}, {}, 0, {}
	sightJobs, sightJobCount, sightFrom, sightFromCount, sightIntake = {}, 0, {}, 0, { at = 0, n = 0 }
	told.by, told.quiet = {}, {}
	reviewers, reviewerCount, leaseGen, leaseAt = {}, 0, leaseGen + 1, nil
	for key in pairs(stats) do stats[key] = 0 end
	Share.rates, Share.days, Share.targets, Share.relayed, Share.relayedOrder = {}, {}, {}, {}, {}
	Share.log, Share.why, Share.counts, Share.deathRow = {}, {}, {}, nil
	Share.catchReplied, Share.catchHeard = -math.huge, -math.huge
	Share.resendGen = (Share.resendGen or 0) + 1
end

if ns.UI and ns.UI.AddTab then
	ns.UI.AddTab({ key = "wanted", label = "TAB_WANTED", after = "realm",
		icon = Wanted.Icon, visible = function() return ns.IsMember and ns.IsMember() end, build = Wanted.Build, buttons = buttons })
end

-- Never COMBAT_LOG_EVENT_UNFILTERED: on Forever it is a restricted event (HasRestrictions in the
-- client's CombatLog API documentation), and an addon's RegisterEvent on it is blocked with the
-- game's "blocked from an action" pop-up at every login (Daniel's test build, taint.log:
-- Frame:RegisterEvent() from this line). The native PARTY_KILL (our own killing blow) and the
-- player's own death recap (PLAYER_DEAD) are what the client allows.
-- Unsupported/restricted registration must not abort login; this is not the restricted CLEU.
-- (Whether it registered: /oly wanted status says so.)
Share.partyKill = pcall(ns.RegisterEvent, "PARTY_KILL", Wanted.CapturePartyKill)
ns.RegisterEvent("PLAYER_DEAD", function()
	deathSerial = deathSerial + 1
	local serial = deathSerial
	local captured, why, who = ReadSelfDeathRecap()
	Share.NoteDeath(serial, captured, why, who)
	-- The native recap may arrive after PLAYER_DEAD. Bounded retries belong to this death
	-- alone, and the native timestamp/identity/fatal checks still run on every attempt.
	if not captured and ns.After and C_DeathRecap and type(C_DeathRecap.HasRecapEvents) == "function" then
		for _, delay in ipairs({ 0.3, 1, 2 }) do
			ns.After(delay, "wanted death recap", function()
				if not captured and serial == deathSerial then
					captured, why, who = ReadSelfDeathRecap()
					Share.NoteDeath(serial, captured, why, who)
				end
			end)
		end
	end
end)
ns.On("LOGIN", Wanted.Load)
-- An expiry or a lost role clears the word shown; a role that came back (the council's list),
-- or another realm group's store, may bring a saved one back.
-- A reviewer whose role came (the council's list) says at once that he takes sightings.
ns.On("DATA_CHANGED", function()
	CurrentGlobal()
	if not authenticatedGlobal then RestoreGlobal() end
	if LeaseDue() then Wanted.AnnounceReviewer() end
end)
-- The King hid his crown: what waits for a reviewer is cancelled, what went is taken back.
ns.On("KING_LOCATION_CHANGED", function()
	if Sight.CrownHidden() and (sightJobCount > 0 or next(told.by) ~= nil) then
		CancelSightings("crown")
		Sight.Withdraw()
	end
end)
ns.On("LAYER_SHARING_CHANGED", function(on)
	if on ~= true and (sightJobCount > 0 or next(told.by) ~= nil) then
		CancelSightings("private")
		Sight.Withdraw()
	end
end)
-- What this client sees: the nameplates, its target, the unit under the mouse (sightings); the
-- pins follow it in and out of instances.
ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(unit) Wanted.ObserveUnit(unit) end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() Wanted.ObserveUnit("target") end)
ns.RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() Wanted.ObserveUnit("mouseover") end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() Wanted.RefreshPins() end)
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() Wanted.RefreshPins() end)
-- (1.2.3: no WX handler, 1.2.2's evidence whispered for a review: there is none any more, and a
-- member of 1.2.2 who still sends one is heard by nobody.)
if ns.Comm and ns.Comm.Handle then
	ns.Comm.Handle("WK", function(...) return Wanted.HandleShared(...) end)
	ns.Comm.Handle("WV", function(...) return Wanted.HandleMark(...) end)
	ns.Comm.Handle("WY", function(...) Wanted.HandleGlobalSnapshot(...) end)
	-- A late login's ask: the signed word, and (a reviewer's) the recent shared rows.
	ns.Comm.Handle("W4", function(...) Wanted.AnswerGlobal(...) Share.Answer(...) end)
	ns.Comm.Handle("W5", function(...) Wanted.HandleGlobalRelay(...) end)
	ns.Comm.Handle("WS", function(...) Wanted.HandleSighting(...) end)
end

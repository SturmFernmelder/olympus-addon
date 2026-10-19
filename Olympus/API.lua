local ADDON, ns = ...
local L = ns.L

-- The Olympus API for other addons (1.2.4, Daniel: an API inside the addon "for anyone to integrate
-- with what can be integrated, with what the permissions allow", each seeing only what that player
-- sees; his worry, someone using it to mine data). docs/API.md is its page for addon authors.
--
-- What it is, and what it never is:
--   - Read-only ordinary data. Its getters send no chat line, decree, whisper or other message and
--     change no Olympus data. Network actions are separately feature-detected: the request-bound
--     player-sighting search is a verified operator's explicit Start/Cancel, or a
--     bounded rotation while a visible session the operator explicitly started remains on, with
--     the observer consent, short life, audience and last-seen semantics below; the bounded
--     profile-presentation session is host-owned, self-only and fixed-style. A registered addon
--     may also contribute one page to the Olympus window; Olympus still owns its lifecycle.
--   - Only what this player already sees on Olympus's own pages, at no more detail: the Wanted list
--     and its bounties (the Wanted tab's rows), the public rankings (the Slayers boards of the Wanted
--     tab and the signed top three, the donors' top three while the King shows the army the
--     Treasury's ranking (Donors below), the Church's public top three, and each game's ranking the
--     King made public: never a staff view), the player's own frame and title, his own Olympus
--     guild, rank and role, and the leader's presence as the King's lines on the Census and the
--     Realm, his crown and the Realm tab's layer list show it (LeaderPresence below). Never the
--     census, another player's private data, the Wanted page's victims or stored sightings, a
--     movement history, a staff view or a secret (a key, sealed channel name, signature or private
--     list). The optional search returns only a fresh native
--     observation or bounded memory-only recent observation: the target's game-reported unit point
--     when available, its matching group-unit point when it is in the observer's party/raid,
--     otherwise the observer's encounter point. Each row is labelled with that distinction and
--     goes only to the verified request's owner.
--     Each row is built field by field, so what a module adds later never reaches an addon by itself.
--   - Asked, one addon at a time. OlympusAPI.Register("TheirAddon") gives that addon its handle and
--     a line of its own on the privacy page (Consent.lua): explicit, so nothing comes back before
--     its own Yes or the page's clearly labelled Authorize all. The page opens by itself for it once
--     (Consent.Ask). Nothing comes back before
--     the player's Yes, nor after his No; the answer is kept for the account (ns.db.apiAddons) and
--     asked again when what the API gives changes (API.CONSENT_VERSION). Outside an Olympus guild a
--     granted addon learns that the player is in none, and nothing else.
--   - Copies. Every table returned (and each callback's) is built fresh for that call: an addon that
--     changes it changes its own copy, never Olympus's state nor another addon's.
--   - Versioned and pushed: OlympusAPI.VERSION and OlympusAPI.Has(feature) say what this build gives;
--     handle:On(event, fn) tells of a change (WANTED_CHANGED, RANKINGS_CHANGED, PROFILE_CHANGED,
--     LEADER_CHANGED, SIGHTING_CHANGED for a search that same handle owns,
--     PROFILE_EFFECT_SESSION_CHANGED for the sanitized host-owned profile session, and PERMISSION_CHANGED when the player answers), once
--     a burst settles (DISPATCH_DELAY, never in combat), and only when what that
--     call would return changed: nobody needs to poll.
--   - Bounded. RATE_MAX data calls a RATE_WINDOW per addon, MAX_ADDONS addons a session, MAX_CALLBACKS
--     callbacks per event. A callback runs protected: its error is logged with the addon's name
--     (never Olympus's error report) and never stops Olympus or the other callbacks; one that keeps
--     failing (CALLBACK_FAILS) is dropped.
--   - Reserved (Daniel, 2026-10-19: no third-party addon may keep a log of where the King has been).
--     The leader's presence and the sightings searches answer only the addons the Olympus team
--     authorized (API.AUTHORIZED: a digest of each one's folded name, so the list names nobody). Any
--     other addon gets "unauthorized" from those methods (RESERVED_METHODS), cannot listen to their
--     events (RESERVED_EVENTS), and its privacy line says only what it may read
--     (API_CONSENT_TEXT_BASIC). OlympusAPI.Has still says what this build has.
-- A handle is the addon's own: Register gives it once a session for a name, to the first caller
-- (a second Register for that name gets nil, "taken"), and only for an addon the game has installed
-- (its TOC's Title, which the privacy line shows). That is a courtesy boundary, not a lock: every
-- addon runs in the same Lua as Olympus and can read its saved variables directly. The API gives
-- honest addons a supported, consented path, so that Olympus itself never hands anything out
-- unasked.
-- Its own file, loaded after the boards it reads (the TOC): a file the TOC adds loads only once the
-- game restarts, so after the update to 1.2.4 OlympusAPI is nil until then (docs/API.md says to
-- check for it). No game event, no frame and no timer of its own while nobody listens.
-- The mods' OlympusBridge (Bridge.lua) is another door, for their companion: unchanged.

local API = {}
ns.API = API

API.VERSION = 1
-- Version 8 bounds hostile-area rotation to one live area per handle, no faster than once a minute,
-- and only the player's current map or a fresh exact result map already owned by that handle. A
-- visible user-started consumer session must still declare the chosen/configured names or list
-- sources it includes. Every older Yes must be asked again even though the compatible API version
-- stays 1.
-- Version 9 adds the leader's presence (GetLeaderPresence, LEADER_CHANGED) and the wider "outsiders"
-- area scope: what a Yes gives grew, so it is asked again.
API.CONSENT_VERSION = 9
API.MAX_ADDONS = 16       -- addons registered in one session
API.SURFACE_LIMIT = 1     -- one client-owned page in the shared tab rail per session
API.RATE_MAX = 20         -- data calls one addon makes...
API.RATE_WINDOW = 10      -- ...in this many seconds
API.MAX_CALLBACKS = 4     -- one addon's callbacks for one event
API.CALLBACK_FAILS = 3    -- a callback that failed this many times is dropped
API.DISPATCH_DELAY = 2    -- a change is told this long after it, a burst of them once
API.COMBAT_RETRY = 5      -- in combat, looked at again this long after
API.AREA_ROTATE_MIN = 60  -- minimum seconds between successful area starts by one handle
API.AREA_PROOF_MAX = 64   -- fresh exact result maps retained by one handle until those rows expire
API.MAX_ROWS = 50         -- rows of one Slayers board
API.MAX_WANTED = 200      -- Wanted rows (Wanted.MAX_TARGETS)
API.MAX_LEADER_LAYERS = 16 -- layers of the leader's zone (the Realm tab's list)
API.TITLE_MAX = 40        -- the addon's title on the privacy page
API.EVENTS = { "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "LEADER_CHANGED", "SIGHTING_CHANGED",
	"PROFILE_EFFECT_SESSION_CHANGED", "PERMISSION_CHANGED" }
API.DATA_EVENTS = { "WANTED_CHANGED", "RANKINGS_CHANGED", "PROFILE_CHANGED", "LEADER_CHANGED", "PROFILE_EFFECT_SESSION_CHANGED" }
API.AREA_SCOPES = { hostile = true, outsiders = true }
API.RANKINGS = { "slayers", "donors", "church", "games" }

-- The reserved features (the header's Reserved): their methods, with the "no" an addon that is not
-- authorized gets ("nil" for a read or a start, "false" for a cancel or a map call), and their events.
-- A method a reserved feature adds later belongs here too (the tests look for it).
API.RESERVED_METHODS = {
	GetLeaderPresence = "nil", StartPlayerSearch = "nil", GetPlayerSearch = "nil", GetPlayerSearches = "nil",
	StartAreaSearch = "nil", GetAreaSearch = "nil", GetAreaSearches = "nil",
	CancelPlayerSearch = "false", CancelAreaSearch = "false", ShowAreaSearchOnMap = "false", ClearAreaSearchMap = "false",
}
API.RESERVED_EVENTS = { LEADER_CHANGED = true, SIGHTING_CHANGED = true }
-- The authorized addons, each as API.AuthorizedKey(its name) gives it.
API.AUTHORIZED = {
	["2def22f6a5e0801fa6e2de4a41ff7be28858d142b209b6c180ebb930ce2cd7dc94aebbc21f452ab7d36e8cc0b2ad61285561c4bd29089f30dfd48e78a77ea072"] = true,
}

local IS_EVENT = {}
for _, e in ipairs(API.EVENTS) do IS_EVENT[e] = true end

local clients = {} -- [folded addon name] = this session's client
local order = {}   -- the clients, in the order they registered
local pending = {} -- [event] = true: a change not looked at yet
local pendingSightings = {} -- [request id] = true: one request/result changed
local scheduled = false

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Secret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, secret = pcall(issecretvalue, value)
	return not ok or secret == true
end

-- A module of the addon this build has (not a stand-in for a file the game has not loaded yet,
-- Core.lua's StandIn), with that function.
local function Has(key, fn)
	local m = ns[key]
	return type(m) == "table" and not m.missing and type(m[fn]) == "function"
end

-- That module's function, protected: its results, or nothing when it is missing or failed.
local function Call(key, fn, ...)
	if not Has(key, fn) then return nil end
	local ok, a, b = pcall(ns[key][fn], ...)
	if not ok then return nil end
	return a, b
end

-- A plain string for another addon: no colour, texture, atlas or link codes, no control
-- characters, max bytes at most (never half a letter); nil when nothing is left.
local function Plain(v, max)
	if Secret(v) or type(v) ~= "string" then return nil end
	v = v:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
		:gsub("|H.-|h(.-)|h", "%1"):gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "" then return nil end
	return ns.Cut(v, max or 96)
end

-- A finite number, whole when whole is asked; nil otherwise.
local function Num(v, whole)
	if Secret(v) then return nil end
	local ok, value = pcall(tonumber, v)
	if not ok or Secret(value) then return nil end
	v = value
	if not v or v ~= v or v == math.huge or v == -math.huge then return nil end
	if whole then v = math.floor(v + 0.5) end
	return v
end

-- A fresh copy of plain data (strings, numbers, booleans and tables of them).
local function Copy(v, depth)
	if Secret(v) then return nil end
	if type(v) ~= "table" then
		if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then return v end
		return nil
	end
	depth = depth or 0
	if depth > 6 then return nil end
	local out = {}
	for k, x in pairs(v) do
		if type(k) == "string" or type(k) == "number" then out[k] = Copy(x, depth + 1) end
	end
	return out
end

-- The same text for the same data, whatever order pairs walks it in: what a callback was last told.
local function Signature(v)
	if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) ~= type(b) then return type(a) < type(b) end
		return a < b
	end)
	local out = {}
	for i, k in ipairs(keys) do out[i] = tostring(k) .. "=" .. Signature(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

local function Member() return ns.IsMember and ns.IsMember() == true end

local function Busy() return InCombatLockdown and InCombatLockdown() and true or false end

-- An addon's digest on API.AUTHORIZED: SHA-512 (Ed25519.lua's, loaded before this file) of
-- "olympus-api-authorized:" and its folded name, in hex; nil without the hash, so nobody is
-- authorized then.
function API.AuthorizedKey(name)
	if type(name) ~= "string" or not Has("Ed25519", "SHA512") then return nil end
	local ok, digest = pcall(ns.Ed25519.SHA512, "olympus-api-authorized:" .. ns.Fold(name))
	if not ok or type(digest) ~= "string" then return nil end
	return (digest:gsub(".", function(ch) return string.format("%02x", ch:byte()) end))
end

local function Authorized(c) return c.authKey ~= nil and API.AUTHORIZED[c.authKey] == true end

---------------------------------------------------------------------------
-- What an addon may read: each built from the page's own functions, field by field
---------------------------------------------------------------------------

-- The Wanted tab's list: its entries in its order (Wanted.Targets, "listed": 1.2.4, a Horde player
-- with a bounty or a kill of ours, never one with 0 points and 0 kills), each with what its row
-- shows (the name, the bounty and the kills) and the cycle its page shows; the Horde player's GUID,
-- which is who he is on the list (Wanted.lua). Never the victims, the claims, the sightings, who
-- added or took off an entry, nor any time.
function API.Wanted()
	local out = {}
	for i, t in ipairs(Call("Wanted", "Targets", "listed") or {}) do
		if #out >= API.MAX_WANTED then break end
		if type(t) == "table" and t.active == true then
			out[#out + 1] = { place = i, name = Plain(t.name, 72), guid = Plain(t.guid, 64),
				bounty = Num(t.current, true) or 0, kills = Num(t.lifetimeKills, true) or 0, cycle = Num(t.cycle, true) or 1 }
		end
	end
	return out
end

-- A Slayers board as the Wanted tab lists it: place, name, points and claims.
local function SlayerRows(rows)
	local out = {}
	for i, r in ipairs(type(rows) == "table" and rows or {}) do
		if #out >= API.MAX_ROWS then break end
		if type(r) == "table" then
			out[#out + 1] = { place = Num(r.place, true) or i, name = Plain(r.name, 72),
				points = Num(r.points, true) or 0, claims = Num(r.claims, true) or 0 }
		end
	end
	return out
end

-- The Wanted tab's boards: this month's and all time's (what this client observed), and the
-- signed top three it holds, by the names its boards know for those GUIDs (the GUIDs stay here).
local function Slayers()
	if not Has("Wanted", "Rankings") then return nil end
	local rank = Call("Wanted", "Rankings")
	if type(rank) ~= "table" then return nil end
	local out = { month = SlayerRows(rank.month), all = SlayerRows(rank.all), signed = nil }
	local g = Call("Wanted", "GlobalSnapshot")
	if type(g) == "table" and type(g.rows) == "table" then
		local names = {}
		for _, r in ipairs(type(rank.all) == "table" and rank.all or {}) do
			if type(r) == "table" and type(r.guid) == "string" and type(r.name) == "string" then names[r.guid] = r.name end
		end
		out.signed = {}
		for i, r in ipairs(g.rows) do
			if type(r) == "table" and i <= 3 then
				out.signed[#out.signed + 1] = { place = i, name = Plain(names[r.guid], 72),
					points = Num(r.points, true) or 0, claims = Num(r.claims, true) or 0 }
			end
		end
	end
	return out
end

local function Names(list, max)
	local out = {}
	for _, n in ipairs(type(list) == "table" and list or {}) do
		if #out >= (max or 3) then break end
		local name = Plain(n, 72)
		if name then out[#out + 1] = name end
	end
	return out
end

-- The donors' top three, only where every member's own screen shows them (review of 1.2.4: they
-- came back whatever the King's switch, names no page showed). The names the Treasurer's word gives
-- every client (HonorsNet.Donors), names alone, as the word:
--   - nil unless the King shows the army the Treasury's ranking (Treasury.PublicShows("ranking"):
--     his own switch as every client keeps it, off by default; never the keepers' or the King's
--     own view, nor the author's preview, as the games are never a staff view). Off, no page lists
--     the donors, and a portrait's frame tells of one donor at a time, to whoever looks at him.
--   - all: the all-time top three, which head that ranking on the Treasury tab.
--   - month: the month's three only in a build that wears their koi frame (Honors.FrameShipped);
--     1.2.4 does (the borders lane released the koi); a build without it lists them nowhere: nil.
local function Donors()
	if not Has("HonorsNet", "Donors") then return nil end
	if Call("Treasury", "PublicShows", "ranking") ~= true then return nil end
	local d = Call("HonorsNet", "Donors")
	d = type(d) == "table" and d or {}
	local out = { all = Names(d.all) }
	if Call("Honors", "FrameShipped", { family = "donor-month" }) == true then out.month = Names(d.month) end
	return out
end

-- The Church's public top three (HonorsNet.ChurchTop: nil while its public ranking is closed).
local function Church()
	if not Has("HonorsNet", "ChurchTop") then return nil end
	local t = Call("HonorsNet", "ChurchTop")
	if type(t) ~= "table" then return nil end
	return { missionaries = Names(t.missionaries), apostles = Names(t.apostles) }
end

-- Each game's ranking the King made public (ArenaHome.RankingsPublic: the one everybody's Games tab
-- shows), as that tab shows it; a game kept to the staff is not there, whoever this player is.
local function Games()
	if not Has("ArenaHome", "RankingsPublic") then return nil end
	local out = {}
	if Call("ArenaHome", "RankingsPublic", "arena") == true then
		local rows = {}
		local view = Call("ArenaLedger", "RankingView", "all", "A", 1, { mode = "L" })
		for i, x in ipairs(type(view) == "table" and type(view.rows) == "table" and view.rows or {}) do
			if type(x) == "table" then
				rows[#rows + 1] = { place = Num(x.rank, true) or i, name = Plain(x.name, 72), rating = Num(x.rating, true),
					wins = Num(x.wins, true) or 0, losses = Num(x.losses, true) or 0 }
			end
		end
		out.arena = rows
	end
	if Call("ArenaHome", "RankingsPublic", "bones") == true then
		local rows = {}
		for i, x in ipairs(Call("FarkleTable", "Best", "L") or {}) do
			if i > 10 then break end
			if type(x) == "table" then
				rows[#rows + 1] = { place = Num(x.place, true) or i, name = Plain(x.name, 72),
					games = Num(x.games, true) or 0, won = Num(x.won, true) or 0 }
			end
		end
		out.bones = rows
	end
	-- Lottery's saved winners are private history, even with an older game's publish word.
	return out
end

local RANKING = { slayers = Slayers, donors = Donors, church = Church, games = Games }

-- Every public ranking (kind nil), or one: "slayers", "donors", "church" or "games". A kind this
-- build lacks (no arena: no games, no donors) is nil.
function API.Rankings(kind)
	if kind ~= nil then
		local fn = RANKING[kind]
		return fn and fn() or nil
	end
	local out = {}
	for _, k in ipairs(API.RANKINGS) do out[k] = RANKING[k]() end
	return out
end

-- The player's own role in Olympus, the highest he holds: "king", "councillor" (the signed High
-- Council), "steward", "treasurer" (his characters), "guildmaster", "officer" (his guild's officer
-- ranks) or "member".
local function Role(rankIndex)
	if Call("King", "IsKing") == true then return "king" end
	local me = ns.me
	if type(me) == "string" and me ~= "" then
		if type(ns.IsHighCouncillor) == "function" and select(2, pcall(ns.IsHighCouncillor, me)) == true then return "councillor" end
		if type(ns.IsSteward) == "function" and select(2, pcall(ns.IsSteward, me)) == true then return "steward" end
		if type(ns.IsTreasurerCharacter) == "function" and select(2, pcall(ns.IsTreasurerCharacter, me)) == true then return "treasurer" end
	end
	if rankIndex == 0 then return "guildmaster" end
	if Call("Roster", "IsOfficer") == true then return "officer" end
	return "member"
end

-- The player himself: whether he is in an Olympus guild, and there his guild, its rank's name and
-- index (0 its master), his role, and the frame and title his profile shows (HonorsNet.Verified:
-- the frame an honour key, "rank" his rank's or "none"; the title its words, or nil).
function API.Profile()
	if not Member() then return { member = false } end
	local guild, rankName, rankIndex
	if GetGuildInfo then guild, rankName, rankIndex = GetGuildInfo("player") end
	rankIndex = Num(rankIndex, true)
	local out = { member = true, name = Plain(ns.me, 72), guild = Plain(guild, 64), rank = Plain(rankName, 64), rankIndex = rankIndex,
		role = Role(rankIndex), frame = "rank", title = nil }
	local v = type(ns.me) == "string" and Call("HonorsNet", "Verified", ns.me) or nil
	if type(v) == "table" then
		out.frame = Plain(v.frame, 48) or "rank"
		if type(v.title) == "string" then out.title = Plain(Call("HonorsNet", "TitleText", v.title), 64) end
	end
	return out
end

-- The current host-owned profile-presentation session, without its internal issuer, grant id,
-- transport epoch or caption. The remaining lifetime is deliberately approximate and bounded by
-- the host module; callers should use PROFILE_EFFECT_SESSION_CHANGED instead of polling it.
function API.ProfileSession()
	if not Has("ProfileEffects", "Session") then return nil end
	local state = Call("ProfileEffects", "Session")
	if type(state) ~= "table" then return nil end
	local style, expiresIn = Plain(state.style, 32), Num(state.expiresIn, false)
	if not style or not expiresIn or expiresIn < 0 or expiresIn > 3600 then return nil end
	return { style = style, expiresIn = expiresIn }
end

-- The leader's presence, as this player's own pages show it, field by field (review: nothing the
-- lines do not say, nothing guessed):
--   - name, online: the King's lines on the Census and the Realm (Hop.KingLines: Hop.King, the name
--     those lines give him). Not online: { online = false } alone. The King himself: isYou.
--   - Barred from locations (WatchChat.Barred, as King.Location and Hop.KingLines): no field of
--     where he is.
--   - otherRealm (and then realm): Hop.KingOtherRealm, which those lines say.
--   - mapID, mapName: the zone those lines name (his announced layer's), else his crown's.
--   - position: his crown on the map (King.Location: only while he shares it), in thousandths.
--   - onYourLayer: the line "on the King's layer" (Hop.OnKingLayer, strict as the line).
--   - layers, layer: only while this player is in that zone, the Realm tab's list of its layers
--     (Layers.ForMap, Layers.Name, its "~N with Olympus" count, a sample), and the name of his.
-- Never a population (the game gives none), the census, or a member's name beyond the layer
-- names the Realm tab already shows.
local function LeaderZone(mapID)
	local name = Plain(Call("Hop", "ZoneName", mapID), 64)
	return name ~= "?" and name or nil
end

function API.LeaderPresence()
	if not Has("Hop", "King") then return nil end
	local k = Call("Hop", "King")
	if type(k) ~= "table" then return { online = false } end
	local out = { name = Plain(k.name, 72), online = true }
	if Call("King", "IsKing") == true then out.isYou = true return out end
	if Call("WatchChat", "Barred", "locations") then return out end
	local away = Call("Hop", "KingOtherRealm", k) == true
	out.otherRealm = away
	if away then out.realm = Plain(k.realm, 64) end
	local zoneUID, kingMap = Num(k.zoneUID, true), Num(k.mapID, true)
	local at = Call("King", "Location")
	at = type(at) == "table" and at or nil
	local mapID = (not away and zoneUID and kingMap) or (at and Num(at.mapID, true)) or nil
	if mapID and mapID > 0 then out.mapID, out.mapName = mapID, LeaderZone(mapID) end
	if at then
		local am, ax, ay, seenAt = Num(at.mapID, true), Num(at.x), Num(at.y), Num(at.t, true)
		if am and am > 0 and ax and ay and ax >= 0 and ax <= 1 and ay >= 0 and ay <= 1 then
			out.position = { mapID = am, x = math.floor(ax * 1000 + 0.5), y = math.floor(ay * 1000 + 0.5), seenAt = seenAt }
		end
	end
	out.onYourLayer = not away and Call("Hop", "OnKingLayer", true) == true or false
	local here = Num(Call("Layers", "CurrentMap"), true)
	if not away and here and mapID == here then
		local mine = Call("Layers", "Mine")
		local his = (zoneUID and kingMap == here) and zoneUID
			or (out.onYourLayer and type(mine) == "table" and Num(mine.zoneUID, true)) or nil
		out.layers = {}
		for _, layer in ipairs(Call("Layers", "ForMap", here) or {}) do
			if #out.layers >= API.MAX_LEADER_LAYERS then break end
			if type(layer) == "table" then
				local count, name = Num(layer.count, true), Plain(Call("Layers", "Name", layer), 72)
				if count and count > 0 and name then
					local leader = his ~= nil and Num(layer.zoneUID, true) == his
					out.layers[#out.layers + 1] = { name = name, olympus = count, yours = layer.mine == true, leader = leader }
					if leader then out.layer = name end
				end
			end
		end
	end
	return out
end

-- One short, request-bound search owned by this client. PlayerSightings keeps the transport,
-- authority, consent, expiry and observation rules; the API only copies the already-normalized
-- public result. "exact-unit" and "exact-group" are native map/world unit points; "nearby" is the
-- observer's encounter point. Missing kinds from the pre-release transport remain nearby.
function API.PlayerSearch(id)
	if not Has("PlayerSightings", "Session") then return nil end
	local state = Call("PlayerSightings", "Session", id)
	if type(state) ~= "table" or state.mode == "area" then return nil end
	local rawStatus = state.status or state.phase
	local status = (rawStatus == "sending" or rawStatus == "waiting") and "searching"
		or ({ searching = true, cancelled = true, expired = true, complete = true })[rawStatus] and rawStatus
		or "searching"
	local out = {
		id = Plain(type(state.id) == "number" and tostring(state.id) or state.id, 64), mode = "player",
		target = Plain(state.target, 72), status = status,
		createdAt = Num(state.createdAt, true) or 0, expiresAt = Num(state.expiresAt, true) or 0,
		sightings = {},
	}
	local observers = {}
	for _, row in ipairs(type(state.sightings) == "table" and state.sightings
		or type(state.results) == "table" and state.results or {}) do
		if #out.sightings >= 16 then break end
		if type(row) == "table" then
			local observer = Plain(row.observer or row.reporter, 72)
			local mapID, x, y = Num(row.mapID, true), Num(row.x, true), Num(row.y, true)
			local at = Num(row.seenAt or row.at, true)
			local receivedAt, expiresAt = Num(row.receivedAt, true), Num(row.expiresAt, true)
			local rawKind, kind = row.kind, nil
			if rawKind == nil or rawKind == "seen-nearby" or rawKind == "nearby" then kind = "nearby"
			elseif rawKind == "exact-group" or rawKind == "exact-unit" then kind = rawKind end
			local accuracy = Num(row.accuracyYards, true)
			local validAccuracy = accuracy == nil or accuracy >= 0 and accuracy <= 100000
				and (kind ~= "exact-group" and kind ~= "exact-unit" or accuracy == 0)
			if observer and kind and validAccuracy and mapID and mapID > 0 and x and x >= 0 and x <= 1000
				and y and y >= 0 and y <= 1000 and at then
				local sighting = {
					target = Plain(row.target or state.target, 72), observer = observer,
					observerGuild = Plain(row.observerGuild or row.guild, 64), seenAt = at,
					mapID = mapID, x = x, y = y, layer = Num(row.layer, true) or 0, kind = kind,
				}
				if receivedAt and receivedAt >= at then sighting.receivedAt = receivedAt end
				if expiresAt and expiresAt >= at then sighting.expiresAt = expiresAt end
				if accuracy ~= nil then sighting.accuracyYards = accuracy end
				out.sightings[#out.sightings + 1] = sighting
				observers[ns.Fold(observer)] = true
			end
		end
	end
	local count = 0
	for _ in pairs(observers) do count = count + 1 end
	out.observers, out.confirmed = count, count >= 2
	return out.id and out.target and out or nil
end

-- A hostile-area session is deliberately a smaller public shape than an exact-name search: rows
-- identify the directly observed hostile player and the labelled last-seen point, never the member
-- whose client observed it. The internal transport still verifies that member before accepting it.
function API.AreaSearch(id)
	if not Has("PlayerSightings", "AreaSession") then return nil end
	local state = Call("PlayerSightings", "AreaSession", id)
	if type(state) ~= "table" or state.mode ~= "area" then return nil end
	local rawStatus = state.status or state.phase
	local status = (rawStatus == "sending" or rawStatus == "waiting") and "searching"
		or ({ searching = true, cancelled = true, expired = true, complete = true })[rawStatus] and rawStatus
		or "searching"
	local out = {
		id = Plain(type(state.id) == "number" and tostring(state.id) or state.id, 64), mode = "area",
		scope = state.scope == "outsiders" and "outsiders" or "hostile", mapID = Num(state.mapID, true), status = status,
		createdAt = Num(state.createdAt, true) or 0, expiresAt = Num(state.expiresAt, true) or 0,
		sightings = {},
	}
	local targets = {}
	for _, row in ipairs(type(state.sightings) == "table" and state.sightings
		or type(state.results) == "table" and state.results or {}) do
		if #out.sightings >= 48 then break end
		if type(row) == "table" then
			local target = Plain(row.target, 72)
			local mapID, x, y = Num(row.mapID, true), Num(row.x, true), Num(row.y, true)
			local at = Num(row.seenAt or row.at, true)
			local receivedAt, expiresAt = Num(row.receivedAt, true), Num(row.expiresAt, true)
			local rawKind, kind = row.kind, nil
			if rawKind == nil or rawKind == "seen-nearby" or rawKind == "nearby" then kind = "nearby"
			elseif rawKind == "exact-group" or rawKind == "exact-unit" then kind = rawKind end
			local accuracy = Num(row.accuracyYards, true)
			local validAccuracy = accuracy == nil or accuracy >= 0 and accuracy <= 100000
				and (kind ~= "exact-group" and kind ~= "exact-unit" or accuracy == 0)
			local key = target and ns.Fold(target)
			-- A not-hostile row only in the wider scope that asked for it.
			local hostile = row.hostile ~= false
			if key and not targets[key] and kind and validAccuracy and mapID == out.mapID
				and (hostile or out.scope == "outsiders")
				and x and x >= 0 and x <= 1000 and y and y >= 0 and y <= 1000 and at
				and expiresAt and expiresAt >= at then
				local sighting = { target = target, seenAt = at, expiresAt = expiresAt,
					mapID = mapID, x = x, y = y, layer = Num(row.layer, true) or 0, kind = kind, hostile = hostile }
				if receivedAt and receivedAt >= at then sighting.receivedAt = receivedAt end
				if accuracy ~= nil then sighting.accuracyYards = accuracy end
				out.sightings[#out.sightings + 1], targets[key] = sighting, true
			end
		end
	end
	return out.id and out.mapID and out or nil
end

local function AnySearch(id)
	return API.PlayerSearch(id) or API.AreaSearch(id)
end

-- Ownership is tied to the exact session, not merely its small transport id. PlayerSightings may
-- reuse an id after a request is gone; a stale handle must never inherit another addon's later
-- request with that id. The target and creation time are both public, immutable session fields.
local function SearchFingerprint(state)
	if type(state) ~= "table" or type(state.createdAt) ~= "number" then return nil end
	if state.mode == "area" and type(state.mapID) == "number" then
		return "area\0" .. tostring(state.mapID) .. "\0" .. tostring(state.createdAt)
	end
	if type(state.target) ~= "string" then return nil end
	return "player\0" .. state.target .. "\0" .. tostring(state.createdAt)
end

local ClearAreaMap, DrawAreaMap

-- A consumer may rotate an exact-name request before it rotates its hostile-area coverage. Keep
-- only the already-sanitized exact target/map binding until that result's own expiry; cancellation
-- of the transport request does not turn the point into a live tracker. The cache belongs to one
-- API handle, is bounded, and is discarded on permission loss or UI reload.
local function PruneAreaProofs(c, now)
	c.areaProofs = type(c.areaProofs) == "table" and c.areaProofs or {}
	local count = 0
	for key, proof in pairs(c.areaProofs) do
		if type(proof) ~= "table" or type(proof.expiresAt) ~= "number" or proof.expiresAt <= now then
			c.areaProofs[key] = nil
		else
			count = count + 1
		end
	end
	while count > API.AREA_PROOF_MAX do
		local oldestKey, oldestAt
		for key, proof in pairs(c.areaProofs) do
			if oldestAt == nil or proof.expiresAt < oldestAt then oldestKey, oldestAt = key, proof.expiresAt end
		end
		if not oldestKey then break end
		c.areaProofs[oldestKey] = nil
		count = count - 1
	end
	return c.areaProofs
end

local function EachExactAreaProof(state, now, take)
	now = type(now) == "number" and now or ns.Now and ns.Now() or 0
	if type(state) ~= "table" or state.mode ~= "player" then return end
	local target = type(state.target) == "string" and ns.Fold(state.target) or nil
	if not target then return end
	for _, row in ipairs(type(state.sightings) == "table" and state.sightings or {}) do
		local rowTarget = type(row.target) == "string" and ns.Fold(row.target) or nil
		local exact = row.kind == "exact-unit" or row.kind == "exact-group"
		local mapID, expiresAt = row.mapID, row.expiresAt
		if exact and rowTarget == target and type(mapID) == "number" and mapID > 0
			and mapID == math.floor(mapID) and type(expiresAt) == "number" and expiresAt > now then
			local key = table.concat({ target, tostring(mapID), row.kind }, "\031")
			take(key, { target = target, mapID = mapID, kind = row.kind, expiresAt = expiresAt })
		end
	end
end

local function RetainAreaProofs(c, state, now)
	now = type(now) == "number" and now or ns.Now and ns.Now() or 0
	PruneAreaProofs(c, now)
	EachExactAreaProof(state, now, function(key, proof)
		local old = c.areaProofs[key]
		if not old or proof.expiresAt > old.expiresAt then c.areaProofs[key] = proof end
	end)
	return PruneAreaProofs(c, now)
end

local function ForgetSearch(c, id)
	if c.areaMapID == id and ClearAreaMap then ClearAreaMap(c) end
	c.searches[id] = nil
	c.sightingTold[id] = nil
end

local function OwnedSearch(c, id, mode)
	if Secret(id) then return nil end
	local fingerprint = type(id) == "string" and c.searches[id] or nil
	if type(fingerprint) ~= "string" then return nil end
	local state = AnySearch(id)
	if not state or SearchFingerprint(state) ~= fingerprint then
		ForgetSearch(c, id)
		return nil
	end
	if mode and state.mode ~= mode then return nil end
	return state
end

-- A handle can choose not to subscribe and never call GetPlayerSearches. Prune its small ownership
-- index whenever it starts another request so completed/expired transport sessions cannot build up
-- for the rest of the UI session. PlayerSightings itself keeps at most eight current sessions.
local function PruneOwnedSearches(c, mode)
	local ids, out = {}, {}
	for id in pairs(c.searches) do ids[#ids + 1] = id end
	for _, id in ipairs(ids) do
		local state = OwnedSearch(c, id)
		if state and (not mode or state.mode == mode) then out[#out + 1] = state end
	end
	return out
end

-- Area coverage may follow only evidence the same handle already owns. This is deliberately
-- narrower than accepting any map id from a consumer: the player's current map is explicit at the
-- time of the click, and another map must come from an unexpired native point in one of this
-- handle's exact-name searches. Nearby encounter points do not authorize a different area.
local function CurrentMapID()
	if type(C_Map) ~= "table" or type(C_Map.GetBestMapForUnit) ~= "function" then return nil end
	local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
	mapID = ok and Num(mapID, true) or nil
	return mapID and mapID > 0 and mapID or nil
end

local function AreaMapAllowed(c, mapID, now)
	if CurrentMapID() == mapID then return true end
	for _, search in ipairs(PruneOwnedSearches(c, "player")) do
		if search.status ~= "cancelled" and search.status ~= "expired" then
			local found = false
			EachExactAreaProof(search, now, function(_, proof)
				if proof.mapID == mapID then found = true end
			end)
			if found then return true end
		end
	end
	for _, proof in pairs(PruneAreaProofs(c, now)) do
		if proof.mapID == mapID then return true end
	end
	return false
end

-- What each data event's callback is given: what its call returns.
local BUILD = {
	WANTED_CHANGED = function() return Member() and API.Wanted() or nil end,
	RANKINGS_CHANGED = function() return Member() and API.Rankings() or nil end,
	PROFILE_CHANGED = function() return API.Profile() end,
	LEADER_CHANGED = function() return Member() and API.LeaderPresence() or nil end,
	PROFILE_EFFECT_SESSION_CHANGED = function() return Member() and API.ProfileSession() or nil end,
}

local NIL_DATA_EVENT = { PROFILE_EFFECT_SESSION_CHANGED = true }

---------------------------------------------------------------------------
-- The addons, their answers and their handles
---------------------------------------------------------------------------

local function Answers(make)
	if type(ns.db) ~= "table" then return nil end
	if type(ns.db.apiAddons) ~= "table" then
		if not make then return nil end
		ns.db.apiAddons = {}
	end
	return ns.db.apiAddons
end

-- The player's answer for this addon: true, false, or nil (never asked, or asked about less than
-- this version gives).
local function Answer(c)
	local all = Answers(false)
	local e = all and all[c.key]
	if type(e) ~= "table" or e.v ~= API.CONSENT_VERSION then return nil end
	if e.on == true then return true end
	if e.on == false then return false end
	return nil
end

local function Granted(c) return Answer(c) == true end

local function Status(c)
	local a = Answer(c)
	return a == true and "granted" or a == false and "refused" or "pending"
end

local function Listens(c, event)
	return type(c.callbacks[event]) == "table" and #c.callbacks[event] > 0
end

-- The addon's callbacks for the event, each protected; one that keeps failing goes.
local function Tell(c, event, payload)
	if API.RESERVED_EVENTS[event] and not Authorized(c) then return end
	local list = c.callbacks[event]
	if type(list) ~= "table" then return end
	local now = {}
	for i, fn in ipairs(list) do now[i] = fn end
	for _, fn in ipairs(now) do
		local ok, err = pcall(fn, event, Copy(payload))
		if not ok then
			c.fails[fn] = (c.fails[fn] or 0) + 1
			ns.Log("api: %s's %s callback failed (%d): %s", c.name, event, c.fails[fn], ns.Cut(tostring(err), 200))
			if c.fails[fn] >= API.CALLBACK_FAILS then
				for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
				c.fails[fn] = nil
				ns.Log("api: %s's %s callback dropped after %d errors", c.name, event, API.CALLBACK_FAILS)
			end
		end
	end
end

local Dispatch, Mark

-- The leader's crown leaves the map on its own (King.LOCATION_EXPIRE after his last word) with no
-- event of Olympus's: while a built presence holds a position, one timer looks again just after it
-- would expire. Never while nobody listens (only a built LEADER_CHANGED arms it), one at a time.
local leaderTimer = false
local function WatchLeaderExpiry(data)
	if leaderTimer or not ns.After or type(data) ~= "table" or type(data.position) ~= "table" then return end
	local seenAt = data.position.seenAt
	local life = Has("King", "Location") and tonumber(ns.King.LOCATION_EXPIRE) or nil
	if type(seenAt) ~= "number" or not life then return end
	local now = ns.Now and ns.Now() or 0
	leaderTimer = true
	ns.After(math.max(1, seenAt + life + 1 - now), "api leader expiry", function()
		leaderTimer = false
		Mark("LEADER_CHANGED")
	end)
end

-- What a data event would give this addon now becomes what it was last told (no call when it
-- listens to nothing: nothing is built).
local function Baseline(c, event)
	local build = BUILD[event]
	if not build or not Listens(c, event) or not Granted(c) then return end
	local data = build()
	if event == "LEADER_CHANGED" then WatchLeaderExpiry(data) end
	if data ~= nil or NIL_DATA_EVENT[event] then c.told[event] = Signature(data) end
end

local function Schedule(delay)
	if scheduled or not ns.After then return end
	scheduled = true
	ns.After(delay or API.DISPATCH_DELAY, "api dispatch", function() Dispatch() end)
end

-- A change Olympus saw: looked at once the burst settles, only for events a granted addon listens
-- to (nobody listening: nothing is built and no timer starts).
Mark = function(...)
	local any = false
	for i = 1, select("#", ...) do
		local event = select(i, ...)
		for _, c in ipairs(order) do
			if Listens(c, event) and Granted(c) then pending[event], any = true, true break end
		end
	end
	if any then Schedule() end
end

-- Builds each pending event's data once and tells each granted addon that listens, when it is not
-- what that addon was last told. In combat, waits.
Dispatch = function()
	scheduled = false
	if next(pending) == nil and next(pendingSightings) == nil then return end
	if Busy() then Schedule(API.COMBAT_RETRY) return end
	local events = pending
	pending = {}
	for _, event in ipairs(API.DATA_EVENTS) do
		if events[event] then
			local data = BUILD[event]()
			if event == "LEADER_CHANGED" then WatchLeaderExpiry(data) end
			if data ~= nil or NIL_DATA_EVENT[event] then
				local sig = Signature(data)
				for _, c in ipairs(order) do
					if Listens(c, event) and Granted(c) and c.told[event] ~= sig then
						c.told[event] = sig
						Tell(c, event, data)
					end
				end
			end
		end
	end
	local sightings = pendingSightings
	pendingSightings = {}
	for id in pairs(sightings) do
		local state = AnySearch(id)
		for _, c in ipairs(order) do
			local terminal = c.sightingEnded[id]
			if terminal then
				c.sightingEnded[id] = nil
				if c.areaMapID == id then ClearAreaMap(c) end
				if Granted(c) and Listens(c, "SIGHTING_CHANGED") then Tell(c, "SIGHTING_CHANGED", terminal) end
			elseif c.searches[id] and SearchFingerprint(state) ~= c.searches[id] then
				-- Gone, or the bounded transport id now names a different session. End only the
				-- old handle's view. Validate this before drawing so a replacement session is never
				-- copied into stale map-pin frames, even briefly, across handles.
				ForgetSearch(c, id)
				if Granted(c) and Listens(c, "SIGHTING_CHANGED") then
					Tell(c, "SIGHTING_CHANGED", { id = id, status = "ended" })
				end
			else
				if c.areaMapID == id then
					if c.searches[id] and state and state.mode == "area" and state.status == "searching" and Granted(c) then
						DrawAreaMap(c, state, false)
					else
						ClearAreaMap(c)
					end
				end
				if c.searches[id] and Granted(c) and Listens(c, "SIGHTING_CHANGED") then
					local sig = Signature(state)
					if c.sightingTold[id] ~= sig then
						c.sightingTold[id] = sig
						Tell(c, "SIGHTING_CHANGED", state)
					end
				end
			end
		end
	end
end

local function MarkSighting(id)
	if type(id) == "number" then id = tostring(id) end
	if type(id) ~= "string" or id == "" then return end
	for _, c in ipairs(order) do
		if c.searches[id] and Granted(c) and (Listens(c, "SIGHTING_CHANGED") or c.areaMapID == id) then
			pendingSightings[id] = true
			Schedule()
			return
		end
	end
end

-- The player answered on the privacy page: kept for the account, the addon told (PERMISSION_CHANGED,
-- at once, protected) and, on a Yes, what it listens to now taken as what it was told.
local function SetAnswer(c, on)
	local all = Answers(true)
	if not all then return end
	-- Revocation is active, not merely a read gate: stop every request this handle started before
	-- saving the No. PlayerSightings also withdraws any live observer evidence when its own sharing
	-- permission is revoked.
	if not on then
		-- Release both sides of this handle's host-owned presentation before the saved answer changes.
		-- Close/disable are safe after a No as well, but doing them here guarantees that revocation is
		-- an active boundary rather than waiting for the short network leases to expire.
		if Has("ProfileEffects", "CloseSession") then pcall(ns.ProfileEffects.CloseSession, c.profileOwner) end
		if Has("ProfileEffects", "DisableOwner") then pcall(ns.ProfileEffects.DisableOwner, c.profileOwner) end
		local ids = {}
		for id in pairs(c.searches) do ids[#ids + 1] = id end
		if Has("PlayerSightings", "Cancel") then
			for _, id in ipairs(ids) do
				-- The bounded transport may already have reused this id. Only cancel the exact
				-- session this handle started; a stale handle must not stop its replacement.
				if OwnedSearch(c, id) then pcall(ns.PlayerSightings.Cancel, id, "permission") end
			end
		end
		c.searches = {}
		c.sightingEnded = {}
		c.areaProofs = {}
		c.areaStartedAt = nil
		ClearAreaMap(c)
	end
	all[c.key] = { on = on and true or false, v = API.CONSENT_VERSION, at = ns.Now and ns.Now() or 0 }
	c.told = {}
	c.sightingTold = {}
	if on then for _, event in ipairs(API.DATA_EVENTS) do Baseline(c, event) end end
	ns.Log("api: %s %s", c.name, on and "granted" or "refused")
	Tell(c, "PERMISSION_CHANGED", Status(c))
end

-- The addon's line on the privacy page (Consent.lua): its own Yes and No, or the page's deliberately
-- labelled Authorize all. A new
-- question, never one of the lines 1.2.1 and 1.2.2 showed at every login (adopt = false: review of
-- 1.2.4, an account updating from 1.2.2 straight to 1.2.4 had it taken as asked, and the page never
-- opened by itself for it).
local function Line(c)
	if not Has("Consent", "Register") then return false end
	return ns.Consent.Register({
		key = c.consentKey,
		label = function() return L.API_CONSENT_LABEL:format(c.title) end,
		-- An addon that is not authorized is asked only about what it can read (the header's Reserved).
		text = Authorized(c) and "API_CONSENT_TEXT" or "API_CONSENT_TEXT_BASIC",
		explicit = true,
		adopt = false,
		version = API.CONSENT_VERSION,
		get = function() return Answer(c) end,
		set = function(on) SetAnswer(c, on) end,
	}) == true
end

-- The installed addon's title (its TOC's, plain), its name when it has none but the game has it
-- loaded, or nil: a name the game knows nothing of gets no line on the privacy page.
local function Installed(name)
	local AO = C_AddOns
	if type(AO) ~= "table" then return nil end
	local title, loaded
	if type(AO.GetAddOnMetadata) == "function" then
		local ok, t = pcall(AO.GetAddOnMetadata, name, "Title")
		if ok then title = Plain(t, API.TITLE_MAX) end
	end
	if not title and type(AO.IsAddOnLoaded) == "function" then
		local ok, yes = pcall(AO.IsAddOnLoaded, name)
		loaded = ok and yes and true or false
	end
	if title then return title end
	if loaded then return Plain(name, API.TITLE_MAX) end
	return nil
end

-- A method of the handle, for handle:Method(...) and handle.Method(...) alike.
local function Method(c, fn)
	return function(first, ...)
		if first == c.handle then return fn(c, ...) end
		return fn(c, first, ...)
	end
end

-- A data call: the player's Yes, an Olympus guild (where asked), and the addon within its rate.
-- Past it, said in the log once a session for that addon (review of 1.2.4: once a window filled the
-- log's ring, and the 25 lines /oly bug copies, with one addon polling).
local function Spend(c)
	local now = ns.Now and ns.Now() or 0
	local r = c.rate
	if now - r.at >= API.RATE_WINDOW or now < r.at then r.at, r.n = now, 0 end
	if r.n >= API.RATE_MAX then
		if not c.rateSaid then
			c.rateSaid = true
			ns.Log("api: %s asked more than %d times in %d s (said once a session)", c.name, API.RATE_MAX, API.RATE_WINDOW)
		end
		return false
	end
	r.n = r.n + 1
	return true
end
local function Read(c, needsGuild, build, ...)
	if not Granted(c) then return nil, Status(c) end
	if needsGuild and not Member() then return nil, "guild" end
	if not Spend(c) then return nil, "busy" end
	return build(...)
end

local function SightingRead(c, build, ...)
	if not Has("PlayerSightings", "Session") then return nil, "unavailable" end
	return Read(c, true, build, ...)
end

local function ProfileAction(c, fn, ...)
	if not Has("ProfileEffects", fn) then return false, "unavailable" end
	if not Granted(c) then return false, Status(c) end
	if not Member() then return false, "guild" end
	if not Spend(c) then return false, "busy" end
	local ok, result, why = pcall(ns.ProfileEffects[fn], ...)
	if not ok then return false, "failed" end
	return result == true, why
end

-- Stop/disable remain available after revocation because they can only remove this handle's own
-- bounded state. The internal owner check prevents one API handle from changing another's state.
local function ProfileRelease(c, fn, ...)
	if not Has("ProfileEffects", fn) then return false, "unavailable" end
	local ok, result, why = pcall(ns.ProfileEffects[fn], ...)
	if not ok then return false, "failed" end
	return result == true, why
end

local function AreaPin(row) -- gp:worldmap-icons
	if not ns.Gate.Allowed("worldmap-icons") then return nil end
	if UIParent == nil then return nil end
	local frame = CreateFrame("Frame", nil, UIParent)
	frame:SetSize(18, 18)
	local icon = frame:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
	frame.row = Copy(row)
	frame:SetScript("OnEnter", function(self) -- gp:worldmap-icons
		if not ns.Gate.Allowed("worldmap-icons") then return end
		if type(GameTooltip) ~= "table" or type(GameTooltip.SetOwner) ~= "function" then return end
		if type(self.row) ~= "table" then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(self.row.target or "", 1, 0.82, 0)
		local line = self.row.kind == "nearby" and (L.API_AREA_NEARBY or "Seen nearby")
			or (L.API_AREA_EXACT or "Exact last-seen point")
		if self.row.hostile == false then line = line .. "\n" .. (L.API_AREA_OUTSIDER or "Not hostile, outside Olympus's guilds") end
		GameTooltip:AddLine(line, 0.75, 0.75, 0.75, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() -- gp:worldmap-icons
		if not ns.Gate.Allowed("worldmap-icons") then return end
		if GameTooltip then GameTooltip:Hide() end
	end)
	frame:Hide()
	return frame
end

-- HereBeDragons owns the anchors, while Olympus owns a bounded pool of the frames it gives the
-- library. WoW frames cannot be destroyed, so keep at most the 48 frames one area result can use
-- and reuse them on every refresh instead of orphaning another set after each network answer.
local function HideAreaPins(c) -- gp:worldmap-icons!undo
	local P = ns.Pins and ns.Pins()
	if ns.Gate.Allowed("worldmap-icons") and P and type(P.RemoveAllWorldMapIcons) == "function" and c.areaMapOwner then
		pcall(P.RemoveAllWorldMapIcons, P, c.areaMapOwner)
	end
	for _, frame in ipairs(c.areaMapFrames or {}) do
		frame.row = nil
		pcall(frame.Hide, frame)
	end
end

ClearAreaMap = function(c, expected)
	if Secret(expected) then return false, "unknown" end
	if expected ~= nil and c.areaMapID ~= expected then return false, "unknown" end
	HideAreaPins(c)
	c.areaMapID = nil
	return true
end

DrawAreaMap = function(c, state, open) -- gp:worldmap-icons
	if not ns.Gate.Allowed("worldmap-icons") then ClearAreaMap(c) return false, "unsupported" end
	if type(state) ~= "table" or state.mode ~= "area" then return false, "unknown" end
	if state.status ~= "searching" then ClearAreaMap(c) return false, "ended" end
	local P = ns.Pins and ns.Pins()
	if not P or type(P.AddWorldMapIconMap) ~= "function" or type(P.RemoveAllWorldMapIcons) ~= "function"
		or type(ns.WorldMapIcons) ~= "function" then ClearAreaMap(c) return false, "unavailable" end
	local okWorld, world = pcall(ns.WorldMapIcons, P, c.areaMapOwner)
	if not okWorld or world ~= true then ClearAreaMap(c) return false, "unsupported" end
	local watched = c.areaMapID == state.id
	HideAreaPins(c)
	local now = ns.Now and ns.Now() or 0
	local used = 0
	for _, row in ipairs(state.sightings or {}) do
		if used >= 48 then break end
		if type(row) == "table" and row.mapID == state.mapID and type(row.x) == "number" and type(row.y) == "number"
			and type(row.expiresAt) == "number" and row.expiresAt > now then
			used = used + 1
			local frame = c.areaMapFrames[used]
			if not frame then
				frame = AreaPin(row)
				c.areaMapFrames[used] = frame
			else
				frame.row = Copy(row)
			end
			if not frame then ClearAreaMap(c) return false, "unavailable" end
			local ok, added = pcall(P.AddWorldMapIconMap, P, c.areaMapOwner, frame, row.mapID,
				row.x / 1000, row.y / 1000, HBD_PINS_WORLDMAP_SHOW_PARENT or 1)
			if not ok or added ~= true then ClearAreaMap(c) return false, "failed" end
			if type(frame.Show) == "function" then pcall(frame.Show, frame) end
		end
	end
	if used == 0 then
		-- A map the player already opened remains armed across a temporarily empty result set. A later
		-- sighting can therefore restore its pins without forcing the consumer to subscribe to events
		-- or ask the player to click Show again. A first empty Show still fails closed and opens nothing.
		c.areaMapID = watched and state.id or nil
		return false, "empty"
	end
	c.areaMapID = state.id
	if open then
		if type(WorldMapFrame) ~= "table" or type(WorldMapFrame.SetMapID) ~= "function"
			or type(ShowUIPanel) ~= "function" then ClearAreaMap(c) return false, "unavailable" end
		local shown = pcall(ShowUIPanel, WorldMapFrame)
		local focused = shown and pcall(WorldMapFrame.SetMapID, WorldMapFrame, state.mapID)
		if not focused then ClearAreaMap(c) return false, "failed" end
	end
	return true
end

-- Surface ownership is deliberately separate from the addon's name and consent key. UI.lua sees
-- only this session-local slot, so its page context and lifecycle logs do not identify the caller.
local function SurfaceCall(fn, owner, ...)
	if not Has("UI", fn) then return false, "unavailable" end
	local ok, result, why = pcall(ns.UI[fn], owner, ...)
	if not ok then return false, "failed" end
	return result, why
end

local function RegisteredSurfaceCall(c, fn, ...)
	if not c.surfaceRegistered then return false, "unregistered" end
	return SurfaceCall(fn, c.surfaceOwner, ...)
end

local METHODS = {}
function METHODS.Status(c) return Status(c) end
function METHODS.Name(c) return c.name end
function METHODS.GetWanted(c) return Read(c, true, API.Wanted) end
function METHODS.GetRankings(c, kind)
	if kind ~= nil and not RANKING[kind] then return nil, "kind" end
	return Read(c, true, API.Rankings, kind)
end
function METHODS.GetProfile(c) return Read(c, false, API.Profile) end
function METHODS.GetLeaderPresence(c)
	if not Has("Hop", "King") then return nil, "unavailable" end
	return Read(c, true, API.LeaderPresence)
end
function METHODS.StartProfileSession(c, style)
	style = Plain(style, 32)
	if not style then return false, "style" end
	return ProfileAction(c, "OpenSession", c.profileOwner, style)
end
function METHODS.StopProfileSession(c)
	return ProfileRelease(c, "CloseSession", c.profileOwner)
end
function METHODS.SetProfileEffect(c, style, enabled, caption)
	style = Plain(style, 32)
	if not style then return false, "style" end
	if enabled ~= true and enabled ~= false then return false, "state" end
	if enabled then
		if Secret(caption) or type(caption) ~= "string" then return false, "caption" end
		return ProfileAction(c, "Set", c.profileOwner, style, true, caption)
	end
	return ProfileRelease(c, "Set", c.profileOwner, style, false)
end
function METHODS.GetProfileSession(c)
	if not Has("ProfileEffects", "Session") then return nil, "unavailable" end
	return Read(c, true, function()
		local state = API.ProfileSession()
		return state, state and nil or "none"
	end)
end
function METHODS.StartPlayerSearch(c, target)
	if not Has("PlayerSightings", "Start") then return nil, "unavailable" end
	local state, why = SightingRead(c, function() return Call("PlayerSightings", "Start", target) end)
	-- The internal transport returns true plus its opaque id; keep accepting a table too so this
	-- adapter remains stable if the internal module later returns its initial snapshot directly.
	if state == true and (type(why) == "string" or type(why) == "number") then
		local id = why
		state, why = API.PlayerSearch(id), nil
	end
	if type(state) == "table" and type(state.id) == "string" and state.id ~= "" then
		PruneOwnedSearches(c)
		c.sightingEnded[state.id] = nil
		c.searches[state.id] = SearchFingerprint(state)
		c.sightingTold[state.id] = Signature(state)
		return Copy(state)
	end
	return nil, why or "failed"
end
function METHODS.CancelPlayerSearch(c, id)
	local state = OwnedSearch(c, id, "player")
	if not state then return false, "unknown" end
	if not Has("PlayerSightings", "Cancel") then return false, "unavailable" end
	-- This method has no read-permission gate because cancellation can only reduce disclosure. A No
	-- already cancels and forgets every owned request in SetAnswer above.
	local ok, result, why = pcall(ns.PlayerSightings.Cancel, id, "api")
	if not ok then return false, "failed" end
	if result == true then
		RetainAreaProofs(c, state)
		ForgetSearch(c, id)
		if Granted(c) and Listens(c, "SIGHTING_CHANGED") then
			c.sightingEnded[id] = { id = id, status = "cancelled" }
			pendingSightings[id] = true
			Schedule()
		end
	elseif why == "not-found" then
		ForgetSearch(c, id)
	end
	return result == true, why
end
function METHODS.GetPlayerSearch(c, id)
	return SightingRead(c, function()
		local state = OwnedSearch(c, id, "player")
		return state, state and nil or "unknown"
	end)
end
function METHODS.GetPlayerSearches(c)
	return SightingRead(c, function()
		local out = PruneOwnedSearches(c, "player")
		table.sort(out, function(a, b)
			local aa, bb = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
			if aa ~= bb then return aa > bb end
			return tostring(a.id or "") < tostring(b.id or "")
		end)
		return out
	end)
end
function METHODS.StartAreaSearch(c, mapID, scope)
	if not Has("PlayerSightings", "StartArea") then return nil, "unavailable" end
	return SightingRead(c, function()
		if Secret(mapID) then return nil, "map" end
		mapID = Num(mapID, false)
		if not mapID or mapID <= 0 or mapID ~= math.floor(mapID) then return nil, "map" end
		-- "hostile" (also nil: the original contract) or "outsiders", which this build's transport
		-- must list too.
		if Secret(scope) then return nil, "scope" end
		if scope == nil then scope = "hostile" end
		local scopes = ns.PlayerSightings.AREA_SCOPES
		if type(scope) ~= "string" or not API.AREA_SCOPES[scope]
			or (scope ~= "hostile" and not (type(scopes) == "table" and scopes[scope] == true)) then
			return nil, "scope"
		end
		for _, search in ipairs(PruneOwnedSearches(c, "area")) do
			if search.status == "searching" then return nil, "active" end
		end
		local now = ns.Now and ns.Now() or 0
		if c.areaStartedAt ~= nil and now - c.areaStartedAt < API.AREA_ROTATE_MIN then
			return nil, "cooldown"
		end
		if not AreaMapAllowed(c, mapID, now) then return nil, "map" end
		local state, why
		if scope == "hostile" then state, why = Call("PlayerSightings", "StartArea", mapID)
		else state, why = Call("PlayerSightings", "StartArea", mapID, scope) end
		if state == true and (type(why) == "string" or type(why) == "number") then
			local id = why
			state, why = API.AreaSearch(id), nil
		end
		if type(state) == "table" and type(state.id) == "string" and state.id ~= "" then
			PruneOwnedSearches(c)
			c.sightingEnded[state.id] = nil
			c.searches[state.id] = SearchFingerprint(state)
			c.sightingTold[state.id] = Signature(state)
			c.areaStartedAt = now
			return Copy(state)
		end
		return nil, why or "failed"
	end)
end
function METHODS.CancelAreaSearch(c, id)
	if not OwnedSearch(c, id, "area") then return false, "unknown" end
	if not Has("PlayerSightings", "CancelArea") then return false, "unavailable" end
	local ok, result, why = pcall(ns.PlayerSightings.CancelArea, id, "api")
	if not ok then return false, "failed" end
	if result == true then
		ClearAreaMap(c, id)
		ForgetSearch(c, id)
		if Granted(c) and Listens(c, "SIGHTING_CHANGED") then
			c.sightingEnded[id] = { id = id, mode = "area", status = "cancelled" }
			pendingSightings[id] = true
			Schedule()
		end
	elseif why == "not-found" then
		ForgetSearch(c, id)
	end
	return result == true, why
end
function METHODS.GetAreaSearch(c, id)
	return SightingRead(c, function()
		local state = OwnedSearch(c, id, "area")
		return state, state and nil or "unknown"
	end)
end
function METHODS.GetAreaSearches(c)
	return SightingRead(c, function()
		local out = PruneOwnedSearches(c, "area")
		table.sort(out, function(a, b)
			local aa, bb = tonumber(a.createdAt) or 0, tonumber(b.createdAt) or 0
			if aa ~= bb then return aa > bb end
			return tostring(a.id or "") < tostring(b.id or "")
		end)
		return out
	end)
end
function METHODS.ShowAreaSearchOnMap(c, id)
	local state, why = SightingRead(c, function() return OwnedSearch(c, id, "area") end)
	if not state then return false, why or "unknown" end
	return DrawAreaMap(c, state, true)
end
function METHODS.ClearAreaSearchMap(c, id)
	if Secret(id) then return false, "unknown" end
	if id ~= nil and type(id) ~= "string" then return false, "unknown" end
	return ClearAreaMap(c, id)
end
local GUILD_TOOL_SECTIONS = { desk = true, reports = true, cases = true, chat = true, justice = true, profile = true }

local function ShowGuildToolsSection(section, target)
	if section == "profile" then return ns.Watch.OpenMember(target) end
	ns.Watch.Show(section == "desk" and nil or section)
	return true
end

local function RestoreGuildToolsSection(page)
	if type(page) ~= "string" then return end
	local kind, key = page:match("^(case):(.*)$")
	if not kind then kind, key = page:match("^(profile):(.*)$") end
	pcall(ns.Watch.Show, kind or page == "desk" and nil or page, key)
end

-- Opens only Olympus-owned Watch UI. The caller receives success/failure, never the page's
-- records. A named profile is resolved and access-checked by Watch.OpenMember itself.
function METHODS.OpenGuildTools(c, section, target)
	section = section == nil and "desk" or section
	if Secret(section) or type(section) ~= "string" or not GUILD_TOOL_SECTIONS[section] then
		return false, "section"
	end
	if section == "profile" and (Secret(target) or type(target) ~= "string" or target == "") then
		return false, "target"
	end
	if not Member() then return false, "guild" end
	if not Has("UI", "SelectTab") or not Has("Watch", "Show") or not Has("Watch", "PageId")
		or (section == "profile" and not Has("Watch", "OpenMember")) then
		return false, "unavailable"
	end

	local priorOK, prior = pcall(ns.Watch.PageId)
	if not priorOK or type(prior) ~= "string" then return false, "failed" end
	local okShow, shown, showWhy = pcall(ShowGuildToolsSection, section, target)
	local pageOK, page = pcall(ns.Watch.PageId)
	local pageMatches = section == "profile" and type(page) == "string" and page:match("^profile:.+$") ~= nil
		or section ~= "profile" and page == section
	if not okShow or shown ~= true or not pageOK or not pageMatches then
		RestoreGuildToolsSection(prior)
		if not okShow or not pageOK then return false, "failed" end
		return false, showWhy or "access"
	end

	local ok, selected, why = pcall(ns.UI.SelectTab, "watch")
	if not ok or selected ~= true then
		RestoreGuildToolsSection(prior)
		return false, ok and (why or "failed") or "failed"
	end
	return true
end
function METHODS.RegisterSurface(c, spec)
	if c.surfaceRegistered then return false, "registered" end
	local ok, why = SurfaceCall("RegisterAPISurface", c.surfaceOwner, spec)
	if ok == true then c.surfaceRegistered = true end
	return ok, why
end
function METHODS.OpenSurface(c) return RegisteredSurfaceCall(c, "OpenAPISurface") end
function METHODS.ToggleSurface(c) return RegisteredSurfaceCall(c, "ToggleAPISurface") end
function METHODS.RefreshSurface(c) return RegisteredSurfaceCall(c, "RefreshAPISurface") end
function METHODS.IsSurfaceOpen(c) return RegisteredSurfaceCall(c, "IsAPISurfaceOpen") end
function METHODS.On(c, event, fn)
	if not IS_EVENT[event] or type(fn) ~= "function" then return false end
	if API.RESERVED_EVENTS[event] and not Authorized(c) then return false end
	local list = c.callbacks[event] or {}
	for _, f in ipairs(list) do if f == fn then return true end end
	if #list >= API.MAX_CALLBACKS then return false end
	list[#list + 1] = fn
	c.callbacks[event] = list
	if c.told[event] == nil then Baseline(c, event) end
	return true
end
function METHODS.Off(c, event, fn)
	local list = c.callbacks[event]
	if type(list) ~= "table" then return false end
	for i = #list, 1, -1 do
		if list[i] == fn or fn == nil then table.remove(list, i) end
	end
	return true
end

local function ReadOnly(_, k) error("OlympusAPI: read-only (" .. tostring(k) .. ")", 2) end

local function NewClient(name, key, title, slot)
	local c = { name = name, key = key, title = title, consentKey = "api:" .. key, callbacks = {}, told = {}, fails = {},
		rate = { at = -math.huge, n = 0 }, surfaceOwner = "api-surface:" .. tostring(slot), searches = {}, sightingTold = {}, sightingEnded = {},
		areaMapOwner = {}, areaMapFrames = {}, areaProofs = {}, profileOwner = "api-profile:" .. tostring(slot),
		authKey = API.AuthorizedKey(key) }
	local methods = {}
	for k, fn in pairs(METHODS) do
		local no = API.RESERVED_METHODS[k]
		if no then
			local inner = fn
			fn = function(client, ...)
				if not Authorized(client) then
					if no == "false" then return false, "unauthorized" end
					return nil, "unauthorized"
				end
				return inner(client, ...)
			end
		end
		methods[k] = Method(c, fn)
	end
	c.handle = setmetatable({}, { __index = methods, __newindex = ReadOnly, __metatable = false })
	return c
end

-- OlympusAPI.Register: the handle of a named, installed addon, once a session; nil and why else
-- ("name", "self", "taken", "full", "unknown", "consent").
function API.Register(name)
	if type(name) ~= "string" then return nil, "name" end
	name = name:match("^%s*(.-)%s*$")
	if name == "" or #name > 64 or name:find("[%c|]") then return nil, "name" end
	local key = ns.Fold(name)
	if key == "olympus" or key == "olympus_arena" then return nil, "self" end
	if clients[key] then return nil, "taken" end
	if #order >= API.MAX_ADDONS then return nil, "full" end
	local title = Installed(name)
	if not title then return nil, "unknown" end
	local c = NewClient(name, key, title, #order + 1)
	if not Line(c) then return nil, "consent" end
	clients[key] = c
	order[#order + 1] = c
	ns.Log("api: %s registered (%s)", name, Status(c))
	return c.handle
end

-- What this build gives: a feature ("wanted", "rankings", "rankings.<kind>", "profile", "leader",
-- "callbacks", "network.sightings", "network.sightings.area-scope", "ui.guild-tools", "ui.surface")
-- or an event's name.
local function SightingsComplete()
	for _, fn in ipairs({ "Start", "Cancel", "Session", "StartArea", "CancelArea", "AreaSession" }) do
		if not Has("PlayerSightings", fn) then return false end
	end
	return true
end
local FEATURES = {
	wanted = function() return Has("Wanted", "Targets") end,
	rankings = function() return true end,
	["rankings.slayers"] = function() return Has("Wanted", "Rankings") end,
	["rankings.donors"] = function() return Has("HonorsNet", "Donors") end,
	["rankings.church"] = function() return Has("HonorsNet", "ChurchTop") end,
	["rankings.games"] = function() return Has("ArenaHome", "RankingsPublic") end,
	profile = function() return true end,
	leader = function() return Has("Hop", "King") and Has("King", "Location") and Has("Layers", "ForMap") end,
	callbacks = function() return true end,
	["network.sightings"] = SightingsComplete,
	["network.sightings.area-scope"] = function()
		if not SightingsComplete() then return false end
		local scopes = ns.PlayerSightings.AREA_SCOPES
		return type(scopes) == "table" and scopes.outsiders == true
	end,
	["network.profile-effects"] = function()
		for _, fn in ipairs({ "OpenSession", "CloseSession", "Set", "DisableOwner", "Session" }) do
			if not Has("ProfileEffects", fn) then return false end
		end
		return true
	end,
	["ui.guild-tools"] = function()
		return Has("UI", "SelectTab") and Has("Watch", "Show") and Has("Watch", "PageId")
			and Has("Watch", "OpenMember")
	end,
	["ui.surface"] = function()
		for _, fn in ipairs({ "RegisterAPISurface", "OpenAPISurface", "ToggleAPISurface", "RefreshAPISurface", "IsAPISurfaceOpen" }) do
			if not Has("UI", fn) then return false end
		end
		return true
	end,
}
for _, e in ipairs(API.EVENTS) do FEATURES[e] = FEATURES.callbacks end
function API.Has(feature)
	local fn = type(feature) == "string" and FEATURES[feature]
	if not fn then return false end
	local ok, yes = pcall(fn)
	return ok and yes == true
end

---------------------------------------------------------------------------
-- The global other addons see: OlympusAPI.VERSION, .Has, .Register (read-only)
---------------------------------------------------------------------------

local public = { VERSION = API.VERSION, SURFACE_LIMIT = API.SURFACE_LIMIT, Has = API.Has, Register = API.Register }
OlympusAPI = setmetatable({}, { __index = public, __newindex = ReadOnly, __metatable = false })

---------------------------------------------------------------------------
-- What tells of a change (Olympus's own events: none of the game's)
---------------------------------------------------------------------------

-- Wanted's list and its Slayers boards (and the signed top three).
ns.On("WANTED_CHANGED", function() Mark("WANTED_CHANGED", "RANKINGS_CHANGED") end)
-- An honour, a pick (the profile's frame and title), the donors' word (HonorsNet).
ns.On("HONORS_CHANGED", function() Mark("RANKINGS_CHANGED", "PROFILE_CHANGED") end)
-- The Church's top three, or its public ranking's switch.
ns.On("CHURCH_TOP_CHANGED", function() Mark("RANKINGS_CHANGED") end)
ns.On("CHURCH_PUBLIC_CHANGED", function() Mark("RANKINGS_CHANGED") end)
-- The King's switch of the Treasury's ranking, which the donors' top three follow (looked at only
-- when it turned: the treasury changes often, and nothing else of it is read here).
local rankingShown
ns.On("TREASURY_CHANGED", function()
	local shown = Call("Treasury", "PublicShows", "ranking") == true
	if shown ~= rankingShown then
		rankingShown = shown
		Mark("RANKINGS_CHANGED")
	end
end)
-- The games: a result, a ranking made public or kept to the staff (ArenaRoles: Arena.Changed).
ns.On("ARENA_CHANGED", function() Mark("RANKINGS_CHANGED") end)
ns.On("LOTTERY_RESULT", function() Mark("RANKINGS_CHANGED") end)
-- A guild joined or left, a rank (Roster.lua: DATA_CHANGED), the signed lists (the role); the census
-- that names the leader online.
ns.On("DATA_CHANGED", function() Mark("PROFILE_CHANGED", "LEADER_CHANGED") end)
-- (1.2.5.1) The Olympus Accord accepted or asked again (Accord.lua): every read's answer changed
-- (Member, "guild").
ns.On("ACCORD_CHANGED", function() Mark(unpack(API.DATA_EVENTS)) end)
-- The leader's crown, the layers announced, a local layer sighting (HOP_CHANGED) and a sanction on
-- locations (WATCHCHAT_CHANGED): what his lines and the Realm tab's layers show.
for _, event in ipairs({ "KING_LOCATION_CHANGED", "LAYERS_CHANGED", "HOP_CHANGED", "WATCHCHAT_CHANGED" }) do
	ns.On(event, function() Mark("LEADER_CHANGED") end)
end
-- A request started by one handle changed or received a fresh, normalized observation. Only the
-- handle that owns that opaque request id is told; the event never exposes another addon's search.
ns.On("PLAYER_SIGHTINGS_CHANGED", function(id) MarkSighting(id) end)
-- The profile module owns the issuer, grant and transport. The public event rebuilds only its
-- sanitized style and remaining lease, including nil when the session closes or expires.
ns.On("PROFILE_EFFECT_SESSION_CHANGED", function() Mark("PROFILE_EFFECT_SESSION_CHANGED") end)

local ADDON, ns = ...
local L = ns.L

-- 1.2.5.1: the Olympus Accord, Olympus's terms of use (its name in one place: L.ACCORD_NAME). A
-- letter on parchment, in Olympus's own window, that every account accepts once before Olympus
-- works: until then ns.IsMember is false (Core.lua), so this client sends nothing and hears nothing
-- of the army, and the Olympus window shows the Accord's page alone (UI.lua). The privacy page
-- (Consent.lua) comes after it, as before.
--
-- When it asks: LOGIN_WAIT after login, then every RETRY until it could (never in combat or an
-- instance, as the privacy page); when the window opens, when the author's signed list makes our
-- guild an Olympus guild, when this account's BattleTag changed and on /oly privacy (each of these
-- a deliberate ask: Not now at login is for the login's tries alone). Not now saves nothing: the
-- next login asks again. Accepted: ns.db.accord, for the game account (its alts are not asked
-- again): the version, when, and 16 bits of the BattleTag's hash (fp), enough to see it changed,
-- never the tag itself. A higher ns.ACCORD_VERSION asks again.
--
-- The BattleTag. Only the player's own, read from his own game (BNGetInfo, as Blizzard's own
-- FriendsFrame reads it once Battle.net is connected, on every supported client); I accept is
-- enabled only while it can be read. An account that accepted is never locked out by a Battle.net
-- outage: the gate (ns.AccordAccepted) reads saved data alone, and Check acts only on a tag it read.
-- It shows masked on the letter (its digits; Show reveals them for REVEAL seconds), and on the
-- King's screen its name too, with no Show (he streams).
--
-- Who gets it: the moderation team alone (WatchChat.InRoom: the author, the King, the High
-- Council and the Olympus moderators they named). A team member's client asks on the Olympus
-- channel (BQ, ASK_FIRST after login, then every ASK_EVERY); each player's client that accepted
-- answers that one asker by a logged whisper (BT), after a random delay, at most once every
-- TELL_EVERY from each character to each asker. Nothing goes to a team member who did not just
-- show he is online (no "No player named..." lines), nothing ever goes on the channel or GUILD, and
-- no other player's client keeps or shows one. The team's clients keep them (ns.rdb.battletags,
-- KEEP after the last one) and The Watch shows them, grouped by tag (the characters one player
-- plays), masked on the King's screen even after his eye button. A tag is what that player's own
-- addon read and sent: a modified addon can send someone else's, so nothing is ever done with one
-- automatically (a later option, with that in mind).
--
--   BQ~1                                          a team member's ask (the channel, not logged)
--   BT~1~<version>~<accepted at>~<guild>~<tag>    a player's answer (a logged whisper to the asker)

local Accord = {}
ns.Accord = Accord

Accord.LOGIN_WAIT = 30      -- after login (before the privacy page's 45)
Accord.RETRY = 60           -- then on the minute until it could ask
Accord.READ_GAP = 2         -- seconds between Battle.net reads while the letter shows
Accord.HANDOFF = 1.5        -- accepted: the privacy page a moment after
Accord.REVEAL = 10          -- seconds Show reveals the tag's digits
Accord.TAG_MAX = 64
Accord.ASK_FIRST = 90       -- a team member's first ask after login
Accord.ASK_EVERY = 1800     -- and then
Accord.TELL_EVERY = 72000   -- each character to each asker at most once in 20 hours
Accord.DELAY_MIN, Accord.DELAY_MAX = 5, 240 -- an answer's random delay
Accord.TAKE_WINDOW = 4200   -- a team client keeps answers this long after its own last ask
Accord.TAKE_GAP = 600       -- the same character and tag kept again at most this often
Accord.KEEP = 180 * 86400   -- a kept tag, after it was last received
Accord.ROWS_MAX = 3000
Accord.ASKERS_MAX = 40
Accord.TOLD_MAX = 400
Accord.SHOWN_MAX = 150
Accord.WIDTH = 560
Accord.HEIGHT = 680
Accord.SCREEN_MARGIN = 48
-- The letter's topics: { n, bullets }, keys ACCORD_T<n>_HEAD and ACCORD_T<n>_<i> (AccordText.lua).
Accord.TOPICS = { { 1, 2 }, { 2, 2 }, { 3, 4 }, { 4, 3 }, { 5, 4 }, { 6, 2 }, { 7, 1 }, { 8, 1 }, { 9, 1 } }
-- A BattleTag as Battle.net writes one: a name, "#", digits. Never "~", "|" or a control byte.
Accord.TAG_SHAPE = "^[^#~|%c]+#%d+$"
Accord.random = math.random -- (swappable in tests)

local frame
local session = { declined = false, newSaid = false, lastAsk = nil, gen = 0, revealUntil = 0, lastRead = -math.huge }
local askers = {}  -- [Fold(name)] = { name, at }: team members whose ask was heard this session
local pending = {} -- [Fold(name)] = true: an answer waiting for its delay
local stats = { asks = 0, heard = 0, told = 0, kept = 0, refused = 0, askNotTeam = 0 }

local function Mono() return type(GetTime) == "function" and GetTime() or 0 end
local function Grey(s) return "|cff9d9d9d" .. tostring(s) .. "|r" end

-- Values the client hides from addons (secret values): never compared, never read.
local function Secret(v) return type(issecretvalue) == "function" and issecretvalue(v) == true end
local function Call(fn)
	local ok, v = pcall(fn)
	return ok and not Secret(v) and v == true
end

-- The player's own BattleTag, or nil and why: "api" (no BNGetInfo), "offline" (Battle.net down,
-- its features off, a secret or no value), "shape" (not Name#digits).
function Accord.ReadTag()
	if type(BNGetInfo) ~= "function" then return nil, "api" end
	local up
	if type(BNFeaturesEnabledAndConnected) == "function" then up = Call(BNFeaturesEnabledAndConnected)
	elseif type(BNConnected) == "function" then up = Call(BNConnected) else up = true end
	if not up then return nil, "offline" end
	local ok, _, tag = pcall(BNGetInfo)
	if not ok or Secret(tag) or type(tag) ~= "string" or tag == "" then return nil, "offline" end
	if #tag > Accord.TAG_MAX or not tag:match(Accord.TAG_SHAPE) then return nil, "shape" end
	return tag
end

-- 16 bits of the tag's hash: a changed tag shows, a known name's digits can't be told from it.
function Accord.Fp(tag)
	local h = ns.Sign.SHA256("OlympusAccord\0" .. ns.Fold(tag))
	return ("%02x%02x"):format(h:byte(1), h:byte(2))
end

local function Saved()
	local a = type(ns.db) == "table" and ns.db.accord or nil
	return type(a) == "table" and a or nil
end

local function Busy()
	return (InCombatLockdown and InCombatLockdown()) or (IsInInstance and IsInInstance()) and true or false
end

---------------------------------------------------------------------------
-- The moderation team (WatchChat.lua's room: InRoom)
---------------------------------------------------------------------------

local function WC()
	local w = ns.WatchChat
	return type(w) == "table" and not w.missing and type(w.InRoom) == "function" and w or nil
end
local function TeamName(name)
	local w = WC()
	return w ~= nil and type(name) == "string" and name ~= "" and w.InRoom(name) == true
end
function Accord.TeamMember()
	return ns.IsMember() == true and type(ns.me) == "string" and TeamName(ns.me)
end
local function Previewing()
	local V = ns.ViewAs
	return type(V) == "table" and not V.missing and type(V.Available) == "function" and V.Available() == true
		and type(V.Role) == "function" and V.Role() ~= "my"
end
-- The team's page and lines show: a team member's client, never in the author's role preview.
function Accord.TeamShown() return Accord.TeamMember() and not Previewing() end

-- A tag as this screen shows it: on the King's (his stream) its name cut short and no digits,
-- whatever his eye button says (ns.CouncilNamesShown is not asked).
function Accord.ShownTag(tag)
	tag = tostring(tag or "")
	if ns.KingsScreen() then return ns.MaskName(tag:match("^(.-)#") or tag) .. "#****" end
	return tag
end
local function ShownName(name)
	local shown = ns.DisplayName(name) or tostring(name)
	if ns.CouncilMasked() then return ns.MaskName(shown) end
	return shown
end

---------------------------------------------------------------------------
-- Accepting
---------------------------------------------------------------------------

-- The addon starts or stops as when one joins or leaves an Olympus guild (Roster.lua's guild
-- change): the roster, the channel (left now, or joined and the census asked for), the realm key,
-- the hello, and every page.
local function Changed(on)
	ns.Fire("ACCORD_CHANGED", on)
	local R, C = ns.Roster, ns.Comm
	if R and R.RequestScan then ns.SafeCall("accord roster", R.RequestScan, true) end
	if C and C.CheckMembership then ns.SafeCall("accord membership", C.CheckMembership) end
	if on and C then
		if C.JoinSoon then ns.SafeCall("accord channel", C.JoinSoon, math.huge) end
		if C.RequestKey then ns.SafeCall("accord key", C.RequestKey) end
		if C.Hello then ns.SafeCall("accord hello", C.Hello, true) end
	end
	ns.Fire("DATA_CHANGED")
end

local Tell -- (below)

-- I accept: the tag read again at the click (never the one the letter showed). True when taken;
-- false and "tag" when no tag can be read now (the letter says why).
function Accord.Accept()
	if type(ns.db) ~= "table" then return false, "db" end
	local tag = Accord.ReadTag()
	if not tag then
		if frame and frame:IsShown() then Accord.Refresh(true) end
		return false, "tag"
	end
	local old, v, fp = Saved(), ns.ACCORD_VERSION, Accord.Fp(tag)
	-- (Another tag: the team is told again, whenever it last was.)
	local told = old and type(old.told) == "table" and old.fp == fp and old.told or {}
	ns.db.accord = { v = v, yes = true, at = ns.Now(), fp = fp, told = told }
	ns.Log("olympus accord accepted (v%d)", v)
	Changed(true)
	ns.Print(L.ACCORD_ACCEPTED:format(v))
	if frame then frame:Hide() end
	-- Team members heard asking lately (an account asked again: a new version, another tag).
	local now = Mono()
	for _, e in pairs(askers) do
		if now - e.at <= 2 * Accord.ASK_EVERY then Tell(e.name, true) end
	end
	ns.After(Accord.HANDOFF, "olympus accord", function()
		local C = ns.Consent
		if C and not C.missing and C.Ask then C.Ask("accord") end
	end)
	return true
end

-- Not now: Olympus stays off, nothing saved; the login's tries leave it until the next login.
function Accord.NotNow()
	session.declined = true
	if frame then frame:Hide() end
	if not ns.AccordAccepted() then ns.Print(L.ACCORD_DECLINED) end
	return true
end

-- The letter by itself: in an Olympus guild, not accepted, not shown already, not in combat or an
-- instance, and at login only while Not now was not said this session. True when it showed.
function Accord.Ask(reason)
	if not ns.InOlympusGuild() or ns.AccordAccepted() then return false end
	if frame and frame:IsShown() then return false end
	if Busy() then return false end
	if reason == "login" and session.declined then return false end
	ns.Log("olympus accord shown (%s)", tostring(reason or "?"))
	Accord.Show(reason)
	return true
end

-- At login, on each loading screen and when Battle.net comes or goes: an accepted account whose
-- tag is read and differs is asked again; one accepted for an older version is told once; an
-- unreadable tag changes nothing.
function Accord.Check()
	local a = Saved()
	local tag = Accord.ReadTag()
	if a and ns.AccordAccepted() and tag and type(a.fp) == "string" and a.fp ~= Accord.Fp(tag) then
		a.yes, a.why = false, "tag"
		ns.Log("olympus accord: this account's BattleTag changed, asked again")
		Changed(false)
		ns.Print(L.ACCORD_TAG_CHANGED)
		Accord.Ask("tag")
	elseif a and a.yes == true and (tonumber(a.v) or 0) < ns.ACCORD_VERSION and not session.newSaid then
		session.newSaid = true
		ns.Print(L.ACCORD_NEW_VERSION:format(ns.ACCORD_VERSION))
	end
	if frame and frame:IsShown() then Accord.Refresh(true) end
end

---------------------------------------------------------------------------
-- The player's side: answering the team's ask
---------------------------------------------------------------------------

local function ToldKey(name) return ns.Fold(ns.me or "") .. ">" .. ns.Fold(name) end
local function PruneTold(t)
	local now, list = ns.Now(), {}
	for k, at in pairs(t) do
		if type(at) ~= "number" or now - at > 2 * Accord.TELL_EVERY or at > now + 86400 then t[k] = nil
		else list[#list + 1] = { k = k, at = at } end
	end
	if #list <= Accord.TOLD_MAX then return end
	table.sort(list, function(x, y) return x.at < y.at end)
	for i = 1, #list - Accord.TOLD_MAX do t[list[i].k] = nil end
end
local function Told()
	local a = Saved()
	if not a then return nil end
	if type(a.told) ~= "table" then a.told = {} end
	return a.told
end
local function RecordTold(name)
	local t = Told()
	if not t then return end
	t[ToldKey(name)] = ns.Now()
	PruneTold(t)
	stats.told = stats.told + 1
end

-- The answer: the accepted version and time, our guild (as Watch.OwnGuild has it), the tag last.
local function Wire(tag)
	local a = Saved()
	local guild = GetGuildInfo and GetGuildInfo("player")
	if not a or type(guild) ~= "string" or guild == "" or guild:find("[~|%c]") then return nil end
	local msg = ("BT~1~%d~%d~%s~%s"):format(tonumber(a.v) or 0, math.floor(tonumber(a.at) or 0), ns.Cut(guild, 72), tag)
	return #msg <= 255 and msg or nil
end

-- Our tag to one team member, now: only while we are a member, he is still in the team and our
-- tag reads the same at the game's send (the permit), logged (the server keeps it).
function Accord.SendTag(name)
	local tag = Accord.ReadTag()
	if not tag or not ns.IsMember() or not TeamName(name) then return false end
	local C = ns.Comm
	if not (C and C.Whisper) or (C.QueueRoom and C.QueueRoom() < 1) then return false end
	local msg = Wire(tag)
	if not msg then return false end
	local guardKey = "accord-tag:" .. ns.Fold(name)
	return C.Whisper(name, msg, guardKey, false, true, function(sent) if sent then RecordTold(name) end end,
		{ owner = Accord, key = guardKey, permit = function(owner, key, dist, to, payload)
			if owner ~= Accord or key ~= guardKey or dist ~= "WHISPER" or payload ~= msg or ns.Fold(ns.FullName(ns.Normal(to))) ~= ns.Fold(name) then
				return false, "guard"
			end
			if not ns.IsMember() or not TeamName(name) or Accord.ReadTag() ~= tag then return false, "revoked" end
			return true
		end }) ~= false
end

-- After a random delay, unless this character told him within TELL_EVERY (force: whenever), one
-- already waits, or no tag can be read.
Tell = function(name, force)
	if type(name) ~= "string" or name == "" or not ns.IsMember() then return false end
	local key = ns.Fold(name)
	if pending[key] then return false end
	local t = Told()
	if not force and t and ns.Now() - (tonumber(t[ToldKey(name)]) or -math.huge) < Accord.TELL_EVERY then return false end
	if not Accord.ReadTag() then return false end
	pending[key] = true
	local gen = session.gen
	ns.After(Accord.random(Accord.DELAY_MIN, Accord.DELAY_MAX), "olympus accord tell", function()
		if gen ~= session.gen then return end
		pending[key] = nil
		Accord.SendTag(name)
	end)
	return true
end
Accord.Tell = function(name, force) return Tell(name, force) end

local function Remember(name)
	askers[ns.Fold(name)] = { name = name, at = Mono() }
	local n, oldest, oldAt = 0, nil, nil
	for k, e in pairs(askers) do
		n = n + 1
		if not oldAt or e.at < oldAt then oldest, oldAt = k, e.at end
	end
	if n > Accord.ASKERS_MAX and oldest then askers[oldest] = nil end
end

-- BQ, heard on the channel (Comm dispatches it to members alone): from a team member, answered.
function Accord.HandleAsk(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or not (text == "BQ~1" or text:match("^BQ~1~")) then
		stats.refused = stats.refused + 1
		return false, "shape"
	end
	sender = ns.FullName(ns.Normal(sender))
	if not TeamName(sender) then
		stats.askNotTeam = stats.askNotTeam + 1
		return false, "team"
	end
	stats.heard = stats.heard + 1
	Remember(sender)
	Tell(sender, false)
	return true
end

---------------------------------------------------------------------------
-- The team's side: asking, and keeping what comes back
---------------------------------------------------------------------------

function Accord.AskTeam()
	if not Accord.TeamMember() then return false end
	local C = ns.Comm
	if not (C and C.ChannelName and C.ChannelName()) then return false end
	session.lastAsk = Mono()
	stats.asks = stats.asks + 1
	return C.Send("CHANNEL", "BQ~1", "accord ask") ~= false
end

local function Store(make)
	local r = ns.rdb
	if type(r) ~= "table" then return nil end
	local s = r.battletags
	if type(s) ~= "table" or type(s.rows) ~= "table" then
		if not make then return nil end
		s = { v = 1, rows = {} }
		r.battletags = s
	end
	return s
end

-- Drops what is past KEEP, then the oldest over ROWS_MAX.
function Accord.Prune()
	local s = Store(false)
	if not s then return end
	local now, list = ns.Now(), {}
	for k, r in pairs(s.rows) do
		if type(r) ~= "table" or type(r.tag) ~= "string" or type(r.name) ~= "string" or now - (tonumber(r.last) or 0) > Accord.KEEP then
			s.rows[k] = nil
		else
			list[#list + 1] = { k = k, last = tonumber(r.last) or 0 }
		end
	end
	if #list <= Accord.ROWS_MAX then return end
	table.sort(list, function(x, y) return x.last < y.last end)
	for i = 1, #list - Accord.ROWS_MAX do s.rows[list[i].k] = nil end
end

-- How the sender's guild is known: "roster" (ours: the server's roster), "claim" (his own Olympus
-- messages spoke for it, Data.ClaimGuild), "self" (his word alone), as Watch's council reports.
local function Via(sender, guild)
	local R = ns.Roster
	if R and R.RankOf and R.RankOf(sender) ~= nil then return "roster", GetGuildInfo("player") or guild end
	local D = ns.Data
	local claimed = D and D.ClaimedGuild and D.ClaimedGuild(sender)
	if type(claimed) == "string" and claimed:lower() == guild:lower() then return "claim", guild end
	return "self", guild
end

-- BT, a logged whisper: kept on a team member's client that asked lately. True when kept; false
-- and why not.
function Accord.HandleTag(dist, sender, text)
	local function No(why)
		stats.refused = stats.refused + 1
		return false, why
	end
	if dist ~= "WHISPER" then return No("dist") end
	local C = ns.Comm
	if C_ChatInfo and C_ChatInfo.SendAddonMessageLogged and C and C.DeliveredLogged and not C.DeliveredLogged() then return No("unlogged") end
	if not Accord.TeamMember() then return No("team") end
	if not session.lastAsk or Mono() - session.lastAsk > Accord.TAKE_WINDOW then return No("unasked") end
	if type(text) ~= "string" or #text > 255 then return No("shape") end
	local av, aat, guild, tag = text:match("^BT~1~(%d+)~(%d+)~([^~]*)~([^~]+)$")
	if not av or #tag > Accord.TAG_MAX or not tag:match(Accord.TAG_SHAPE) then return No("shape") end
	if not ns.IsFederation(guild) then return No("guild") end
	sender = ns.FullName(ns.Normal(sender))
	if type(sender) ~= "string" or sender == "" then return No("shape") end
	local s = Store(true)
	if not s then return No("store") end
	local key, now = ns.Fold(sender), ns.Now()
	local row = s.rows[key]
	local same = type(row) == "table" and type(row.tag) == "string" and ns.Fold(row.tag) == ns.Fold(tag)
	if same and now - (tonumber(row.last) or 0) < Accord.TAKE_GAP then return No("rate") end
	local via, shownGuild = Via(sender, guild)
	local prev = type(row) == "table" and (same and row.prev or row.tag) or nil
	s.rows[key] = { name = sender, tag = tag, guild = shownGuild, first = type(row) == "table" and row.first or now, last = now,
		av = tonumber(av), aat = tonumber(aat), via = via, prev = prev }
	Accord.Prune()
	stats.kept = stats.kept + 1
	ns.Log("olympus accord: a BattleTag from %s kept (%s)", sender, via) -- (never the tag)
	ns.Fire("ACCORD_TEAM_CHANGED")
	return true
end

function Accord.Count()
	local s, n = Store(false), 0
	if s then for _ in pairs(s.rows) do n = n + 1 end end
	return n
end

-- The rows grouped by tag (one player's characters), the most characters first, then the newest.
function Accord.Groups()
	local s, groups, byTag = Store(false), {}, {}
	if not s then return groups end
	for _, r in pairs(s.rows) do
		if type(r) == "table" and type(r.tag) == "string" then
			local k = ns.Fold(r.tag)
			local g = byTag[k]
			if not g then
				g = { tag = r.tag, rows = {}, last = 0 }
				byTag[k], groups[#groups + 1] = g, g
			end
			g.rows[#g.rows + 1] = r
			g.last = math.max(g.last, tonumber(r.last) or 0)
		end
	end
	for _, g in ipairs(groups) do
		table.sort(g.rows, function(x, y)
			if (x.last or 0) ~= (y.last or 0) then return (x.last or 0) > (y.last or 0) end
			return tostring(x.name) < tostring(y.name)
		end)
	end
	table.sort(groups, function(x, y)
		if #x.rows ~= #y.rows then return #x.rows > #y.rows end
		if x.last ~= y.last then return x.last > y.last end
		return ns.Fold(x.tag) < ns.Fold(y.tag)
	end)
	return groups
end

local VIA = { roster = "ACCORD_TEAM_VIA_ROSTER", claim = "ACCORD_TEAM_VIA_CLAIM", self = "ACCORD_TEAM_UNVERIFIED" }

-- The Watch's BattleTags page (Watch.lua): nothing on a client that is not the team's.
function Accord.TeamLines()
	if not Accord.TeamShown() then return {} end
	local groups = Accord.Groups()
	local lines = {
		{ id = "accord-team", header = true, text = L.ACCORD_TEAM_TITLE, right = Grey(Accord.Count()) },
		{ text = Grey(L.ACCORD_TEAM_SCOPE), wrap = true, gapAfter = true },
	}
	if #groups == 0 then
		lines[#lines + 1] = { text = Grey(L.ACCORD_TEAM_EMPTY), wrap = true }
		return lines
	end
	local masked = ns.CouncilMasked()
	local W = ns.Watch
	for i, g in ipairs(groups) do
		if i > Accord.SHOWN_MAX then break end
		local n = #g.rows
		lines[#lines + 1] = { text = Accord.ShownTag(g.tag), right = Grey(n == 1 and L.ACCORD_TEAM_ONE or L.ACCORD_TEAM_SHARED:format(n)) }
		for _, r in ipairs(g.rows) do
			local name = r.name
			local open = type(W) == "table" and not W.missing and type(W.CanRead) == "function" and W.CanRead() == true
				and type(W.OpenMember) == "function"
			lines[#lines + 1] = {
				indent = 1, text = L.ACCORD_TEAM_ROW:format(ShownName(name), masked and "?" or tostring(r.guild or "?")),
				right = Grey(L.ACCORD_TEAM_LAST:format(ns.Ago(r.last))),
				tooltip = function(tt)
					tt:AddLine(ShownName(name), 1, 0.82, 0)
					tt:AddLine(rawget(L, VIA[r.via] or "") or L.ACCORD_TEAM_UNVERIFIED, 1, 1, 1, true)
					tt:AddLine(L.ACCORD_TEAM_ACCORD:format(tonumber(r.av) or 0, date("%Y-%m-%d", tonumber(r.aat) or 0)), 0.7, 0.7, 0.7)
					if type(r.prev) == "string" then tt:AddLine(L.ACCORD_TEAM_PREV:format(Accord.ShownTag(r.prev)), 0.7, 0.7, 0.7) end
				end,
				onClick = open and function() W.OpenMember(name) end or nil,
			}
		end
		lines[#lines].gapAfter = true
	end
	return lines
end

-- The person page's lines in The Watch (Watch.lua's ProfileLines): his tag, the others sharing it.
function Accord.ProfileLines(target)
	if not Accord.TeamShown() or type(target) ~= "string" then return {} end
	local s = Store(false)
	local row = s and s.rows[ns.Fold(ns.FullName(target))]
	if type(row) ~= "table" or type(row.tag) ~= "string" then
		return { { id = "watch-profile-battletag", text = Grey(L.ACCORD_TEAM_PROFILE_NONE) } }
	end
	local out = { { id = "watch-profile-battletag", text = L.ACCORD_TEAM_PROFILE:format(Accord.ShownTag(row.tag)) } }
	local others = {}
	for _, r in pairs(s.rows) do
		if r ~= row and type(r) == "table" and type(r.tag) == "string" and ns.Fold(r.tag) == ns.Fold(row.tag) then others[#others + 1] = ShownName(r.name) end
	end
	table.sort(others)
	if #others > 0 then
		out[#out + 1] = { id = "watch-profile-battletag-also", text = L.ACCORD_TEAM_PROFILE_ALSO:format(table.concat(others, ", ")), wrap = true }
	end
	return out
end

---------------------------------------------------------------------------
-- The letter
---------------------------------------------------------------------------

local INK = { 0.18, 0.10, 0.02 }
local TITLE_INK = { 0.24, 0.12, 0.03 }
local SUB_INK = { 0.35, 0.25, 0.12 }
local HEAD_INK = { 0.40, 0.12, 0.04 }
local WARN = "|cff8c1a0a"

local function Font(title)
	if title then return _G.QuestTitleFont and "QuestTitleFont" or "GameFontNormalLarge" end
	return _G.QuestFont and "QuestFont" or "GameFontHighlight"
end
-- A font string's size: px exactly (exact), or at least px.
local function Px(fs, px, exact)
	if not (fs and fs.GetFont and fs.SetFont) then return end
	local ok, path, size, flags = pcall(fs.GetFont, fs)
	if ok and type(path) == "string" and type(size) == "number" and (size < px or (exact and size ~= px)) then fs:SetFont(path, px, flags) end
end
local function Ink(fs, c) if fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end end
local function Text(parent, title, px, exact, color)
	local fs = parent:CreateFontString(nil, "ARTWORK", Font(title))
	Px(fs, px, exact)
	Ink(fs, color or INK)
	fs:SetJustifyH("LEFT")
	if fs.SetWordWrap then fs:SetWordWrap(true) end
	return fs
end
local function Height(fs, width)
	if fs.GetStringHeight then
		local h = fs:GetStringHeight()
		if type(h) == "number" and h > 0 then return h end
	end
	-- (No measure: about 6 pixels a letter, 15 a line.)
	local per = math.max(1, math.floor(width / 6))
	return math.max(1, math.ceil(#(fs:GetText() or "") / per)) * 15
end
local function Button(parent, label, w, h, fn)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(w, h)
	b:SetText(label)
	b:SetScript("OnClick", function() ns.SafeCall("olympus accord", fn) end)
	return b
end

local PAGE_W, TEXT_X = 484, 16

-- The body's words, in the topics' order (built once): the opening, then each topic's heading
-- and its bullets (a dot, its text beside it).
local function Body(f)
	local child = f.bodyChild
	f.parts = {}
	local function Add(kind, fs, x, gap, width) f.parts[#f.parts + 1] = { kind = kind, fs = fs, x = x, gap = gap, width = width } end
	local opening = Text(child, false, 13)
	opening:SetText(L.ACCORD_OPENING)
	Add("block", opening, 0, 0, PAGE_W)
	for _, t in ipairs(Accord.TOPICS) do
		local head = Text(child, true, 15, true, HEAD_INK)
		head:SetText(L["ACCORD_T" .. t[1] .. "_HEAD"])
		Add("block", head, 0, 10, PAGE_W)
		for i = 1, t[2] do
			local dot = Text(child, false, 13)
			dot:SetText("·")
			Add("dot", dot, 4, 4, 10)
			local line = Text(child, false, 13)
			line:SetText(L["ACCORD_T" .. t[1] .. "_" .. i])
			Add("bullet", line, TEXT_X, 0, PAGE_W - TEXT_X)
		end
	end
end

-- Lays the body out: each part under the one before, a bullet's text beside its dot.
local function LayoutBody(f)
	local y, top = 0, 0
	for _, p in ipairs(f.parts) do
		p.fs:ClearAllPoints()
		p.fs:SetWidth(p.width)
		if p.kind ~= "bullet" then top = y + (p.gap or 0) end
		p.fs:SetPoint("TOPLEFT", f.bodyChild, "TOPLEFT", p.x, -top)
		if p.kind ~= "dot" then y = top + Height(p.fs, p.width) end
	end
	f.bodyChild:SetSize(PAGE_W, math.max(1, y + 4))
end

local function Stream() return (ns.IsKingCharacter and ns.IsKingCharacter(ns.me) == true) or ns.KingsScreen() == true end

-- The tag as the letter shows it: its digits hidden unless revealed; on the King's screen its name
-- cut short too, never revealed.
function Accord.LetterTag(tag, revealed)
	if type(tag) ~= "string" then return nil end
	local name = tag:match("^(.-)#%d+$") or tag
	if Stream() then return ns.MaskName(name) .. "#****" end
	if revealed then return tag end
	return name .. "#****"
end

local function Make()
	local f = ns.Window("OlympusAccordFrame", UIParent, { title = L.TITLE, inset = false, close = false, escape = false })
	f:SetFrameStrata("DIALOG")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetWidth(Accord.WIDTH)
	-- The parchment over the inside (the writ's own ground, Acts.lua).
	local paper = f:CreateTexture(nil, "BACKGROUND")
	paper:SetPoint("TOPLEFT", f.inner[1], f.inner[2])
	paper:SetPoint("BOTTOMRIGHT", f.inner[3], f.inner[4])
	local UI = ns.UI
	local function First(paths) return UI and UI.FirstTexture and UI.FirstTexture(paths) or paths[#paths] end
	local file = First(UI and UI.PARCHMENTS or { "Interface\\QuestFrame\\QuestBG" })
	if GetFileIDFromPath and not GetFileIDFromPath(file) then
		paper:SetColorTexture(0.87, 0.80, 0.64, 0.97)
	else
		paper:SetTexture(file)
		if file:find("QuestBG", 1, true) then paper:SetTexCoord(0, 296 / 512, 0, 331 / 512) end
	end
	f.paper = paper
	f.title = f:CreateFontString(nil, "ARTWORK", Font(true))
	Px(f.title, 24)
	Ink(f.title, TITLE_INK)
	f.title:SetPoint("TOP", 0, -38)
	f.title:SetText(L.ACCORD_NAME)
	f.sub = f:CreateFontString(nil, "ARTWORK", Font(false))
	Ink(f.sub, SUB_INK)
	f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
	local rule = f:CreateTexture(nil, "BORDER")
	rule:SetColorTexture(0.25, 0.13, 0.04, 0.45)
	rule:SetPoint("TOPLEFT", 40, -96)
	rule:SetPoint("TOPRIGHT", -40, -96)
	rule:SetHeight(1)
	-- The words scroll (with the mouse wheel too); everything else stays where it is.
	f.body = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	f.body:SetPoint("TOPLEFT", 28, -104)
	f.body:SetPoint("BOTTOMRIGHT", -40, 134)
	f.bodyChild = CreateFrame("Frame", nil, f.body)
	f.bodyChild:SetSize(PAGE_W, 1)
	f.body:SetScrollChild(f.bodyChild)
	if f.body.EnableMouseWheel then f.body:EnableMouseWheel(true) end
	f.body:SetScript("OnMouseWheel", function(self, delta)
		local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
		local current = self.GetVerticalScroll and self:GetVerticalScroll() or 0
		self:SetVerticalScroll(math.max(0, math.min(range, current - (delta or 0) * 36)))
	end)
	Body(f)
	-- The BattleTag's band, always in sight.
	f.band = f:CreateTexture(nil, "BORDER")
	f.band:SetColorTexture(0.55, 0.42, 0.25, 0.18)
	f.band:SetPoint("BOTTOMLEFT", 28, 86)
	f.band:SetPoint("BOTTOMRIGHT", -28, 86)
	f.band:SetHeight(44)
	f.seal = f:CreateTexture(nil, "ARTWORK")
	f.seal:SetSize(32, 32)
	f.seal:SetPoint("BOTTOMLEFT", 34, 92)
	f.seal:SetTexture(First({ "Interface\\Icons\\Spell_Holy_SealOfWrath", "Interface\\Icons\\Spell_Holy_SealOfMight" }))
	f.tagLabel = Text(f, false, 13)
	f.tagLabel:SetPoint("TOPLEFT", f.band, "TOPLEFT", 46, -5)
	f.tagLabel:SetText(L.ACCORD_TAG_LABEL)
	f.tag = Text(f, true, 15, true, TITLE_INK)
	f.tag:SetPoint("LEFT", f.tagLabel, "RIGHT", 6, 0)
	f.tagNote = Text(f, false, 12, true)
	f.tagNote:SetPoint("BOTTOMLEFT", f.band, "BOTTOMLEFT", 46, 5)
	f.tagNote:SetWidth(Accord.WIDTH - 56 - 46 - 110)
	f.reveal = Button(f, L.ACCORD_TAG_SHOW, 70, 20, function()
		session.revealUntil = session.revealUntil > Mono() and 0 or Mono() + Accord.REVEAL
		Accord.Refresh(false)
	end)
	f.reveal:SetPoint("RIGHT", f.band, "RIGHT", -8, 0)
	f.retry = Button(f, L.ACCORD_TAG_RETRY, 100, 20, function() Accord.Refresh(true) end)
	f.retry:SetPoint("RIGHT", f.band, "RIGHT", -8, 0)
	-- The version and its date, a line, then the two answers (the conservative one on the left).
	f.footer = Text(f, false, 12, true, SUB_INK)
	f.footer:SetJustifyH("CENTER")
	f.footer:SetPoint("BOTTOM", 0, 62)
	f.footer:SetWidth(Accord.WIDTH - 80)
	local low = f:CreateTexture(nil, "BORDER")
	low:SetColorTexture(0.25, 0.13, 0.04, 0.45)
	low:SetPoint("BOTTOMLEFT", 40, 54)
	low:SetPoint("BOTTOMRIGHT", -40, 54)
	low:SetHeight(1)
	f.notNow = Button(f, L.ACCORD_NOT_NOW, 170, 26, function() Accord.NotNow() end)
	f.notNow:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -8, 18)
	f.accept = Button(f, L.ACCORD_ACCEPT, 170, 26, function()
		if not f.acceptEnabled then return end
		Accord.Accept()
	end)
	f.accept:SetPoint("BOTTOMLEFT", f, "BOTTOM", 8, 18)
	f.close = Button(f, L.ACCORD_CLOSE, 170, 26, function() f:Hide() end)
	f.close:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
	-- Battle.net coming back, a reveal running out: the letter follows, once a second.
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 1 then return end
		elapsed = 0
		ns.SafeCall("olympus accord", Accord.Refresh, false)
	end)
	f:Hide()
	-- Closed (Accept, Not now, Close), not hidden with the whole interface (Alt+Z: it still says
	-- shown): the privacy page and the version letter may come after (Consent.lua's rule).
	f:HookScript("OnHide", function(self) if not self:IsShown() then ns.Fire("ACCORD_CLOSED") end end)
	return f
end

-- Lays the letter out again: its size for the screen, the tag (read again every READ_GAP, or now
-- when `read`), the answers.
function Accord.Refresh(read)
	local f = frame
	if not f then return end
	local now = Mono()
	if read or now - session.lastRead >= Accord.READ_GAP then
		session.lastRead = now
		f.tagValue, f.tagWhy = Accord.ReadTag()
	end
	local screenH = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
	if type(screenH) ~= "number" or screenH <= 0 then screenH = 768 end
	f:SetSize(Accord.WIDTH, math.max(320, math.min(Accord.HEIGHT, screenH - Accord.SCREEN_MARGIN)))
	f.sub:SetText(L.ACCORD_SUBTITLE:format(ns.ACCORD_VERSION))
	LayoutBody(f)
	local accepted = ns.AccordAccepted()
	local tag, why = f.tagValue, f.tagWhy
	local stream = Stream()
	local revealed = not stream and session.revealUntil > now
	f.tag:SetText(tag and Accord.LetterTag(tag, revealed) or "-")
	if tag then
		f.tagNote:SetText(stream and L.ACCORD_TAG_HIDDEN_STREAM or L.ACCORD_TAG_TO)
		Ink(f.tagNote, INK)
	else
		f.tagNote:SetText(WARN .. (why == "offline" and L.ACCORD_TAG_WAIT or L.ACCORD_TAG_NONE) .. "|r")
	end
	f.reveal:SetText(revealed and L.ACCORD_TAG_HIDE or L.ACCORD_TAG_SHOW)
	f.reveal:SetShown(tag ~= nil and not stream)
	f.retry:SetShown(tag == nil and why == "offline")
	local a = Saved()
	local footer = L.ACCORD_FOOTER:format(ns.ACCORD_VERSION, L.ACCORD_DATE)
	if accepted and a and tonumber(a.at) then footer = footer .. "  ·  " .. L.ACCORD_ACCEPTED_ON:format(date("%Y-%m-%d", a.at)) end
	f.acceptEnabled = not accepted and tag ~= nil
	if not accepted and not tag then footer = footer .. "  ·  " .. WARN .. L.ACCORD_ACCEPT_WAIT_TIP .. "|r" end
	f.footer:SetText(footer)
	f.accept:SetEnabled(f.acceptEnabled)
	f.accept:SetShown(not accepted)
	f.notNow:SetShown(not accepted)
	f.close:SetShown(accepted)
end

-- The letter, accepted or not (/oly accord, and Ask).
function Accord.Show(reason)
	frame = frame or Make()
	session.revealUntil = 0
	frame.reason = reason
	if frame.body.SetVerticalScroll then frame.body:SetVerticalScroll(0) end
	Accord.Refresh(true)
	frame:Show()
	local AH = ns.ArenaHome
	if type(AH) == "table" and not AH.missing and type(AH.FadeIn) == "function" then ns.SafeCall("olympus accord fade", AH.FadeIn, frame) end
	return frame
end
function Accord.Slash() return Accord.Show("slash") end
function Accord.Frame() return frame end
function Accord.Hide() if frame then frame:Hide() end end

-- The Olympus window's page while the Accord waits (UI.lua): what is off, and the letter again.
function Accord.LockedLines()
	return {
		{ header = true, text = L.ACCORD_NAME },
		{ text = L.ACCORD_LOCKED_HINT, wrap = true, gapAfter = true },
		{ text = "|cffffd200" .. L.ACCORD_LOCKED_OPEN .. "|r", onClick = function() Accord.Show("window") end },
	}
end

-- For /oly status: never a tag.
function Accord.StatusLine()
	local a = Saved()
	local state
	if ns.AccordAccepted() then state = ("v%d accepted %s"):format(a.v, date("%m-%d %H:%M", tonumber(a.at) or 0))
	elseif a and a.why == "tag" then state = ("v%s asked again (another BattleTag)"):format(tostring(a.v))
	elseif a and a.yes == true then state = ("v%s accepted, v%d waits"):format(tostring(a.v), ns.ACCORD_VERSION)
	else state = ("v%d not accepted%s"):format(ns.ACCORD_VERSION, session.declined and " (not now)" or "") end
	local _, why = Accord.ReadTag()
	local team = Accord.TeamMember() and (" | team: %d characters, %d BattleTags"):format(Accord.Count(), #Accord.Groups()) or ""
	return ("%s | battletag %s%s | asks %d, heard %d, told %d, kept %d, refused %d, not team %d"):format(state, why or "readable", team,
		stats.asks, stats.heard, stats.told, stats.kept, stats.refused, stats.askNotTeam)
end
function Accord.Stats() return stats end

-- Tests start from a clean session (ns.db.accord, the account's, is theirs to set).
function Accord.Reset()
	session.declined, session.newSaid, session.lastAsk, session.revealUntil, session.lastRead = false, false, nil, 0, -math.huge
	session.gen = session.gen + 1
	wipe(askers); wipe(pending)
	for k in pairs(stats) do stats[k] = 0 end
	if frame and rawget(_G, "OlympusAccordFrame") ~= frame then frame = nil elseif frame then frame:Hide() end
end

---------------------------------------------------------------------------
-- Login
---------------------------------------------------------------------------

ns.Comm.Handle("BQ", function(...) Accord.HandleAsk(...) end)
ns.Comm.Handle("BT", function(...) Accord.HandleTag(...) end)

function Accord.OnLogin()
	-- (Each through pcall: a client without one of these events refuses to register it.)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BN_CONNECTED", "BN_DISCONNECTED", "BN_INFO_CHANGED" }) do
		pcall(ns.RegisterEvent, event, function() Accord.Check() end)
	end
	Accord.Prune()
	ns.After(Accord.LOGIN_WAIT, "olympus accord", function() Accord.Ask("login") end)
	ns.Every(Accord.RETRY, "olympus accord", function() Accord.Ask("login") end)
	ns.After(Accord.ASK_FIRST, "olympus accord team", Accord.AskTeam)
	ns.Every(Accord.ASK_EVERY, "olympus accord team", Accord.AskTeam)
end
ns.On("LOGIN", function() Accord.OnLogin() end)

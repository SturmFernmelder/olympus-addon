local ADDON, ns = ...

-- A read-only door for a companion addon the mods run (OfficerSpy). It answers "is this a High
-- Councillor?" from the signed list, hands out a copy of that list, and passes along each chat
-- line this client has already accepted. Nothing here sends, writes or changes anything in
-- Olympus: a companion only reads, and Olympus never learns what it does with what it read.

OlympusBridge = OlympusBridge or {}
OlympusBridge.API_VERSION = 1
OlympusBridge.CENSUS_CHECKPOINT_API_VERSION = 1

local COUNCIL_MAX = 64  -- a copy never grows past this (the signed list itself stops at 30)
local OBSERVERS_MAX = 8 -- one companion listens, realistically
local CHECKPOINT_SCHEMA = "olympus-census-checkpoint"
local CHECKPOINT_VERSION = 1
local CHECKPOINT_MAX_GUILDS = 256
local CHECKPOINT_MAX_SEEN = 256
local CHECKPOINT_MAX_TIME = 9999999999

-- The private desktop bridge gets census aggregates through this separate contract. It never
-- receives OlympusDB (or a reference into it), chat, settings, keys, moderation records, member
-- names, officers, reporters or the High Council. Every call builds fresh plain tables so a
-- consumer can change its copy without changing Olympus.
local function Whole(value, maximum)
	local n = tonumber(value)
	if not n or n ~= n then return 0 end
	n = math.floor(n)
	if n < 0 then return 0 end
	if maximum and n > maximum then return maximum end
	return n
end

local function Plain(value, maximum)
	if type(value) ~= "string" then return nil end
	local C = ns.Codec
	local s = C and C.Plain and C.Plain(value) or value:gsub("[|%c]", "")
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	if maximum and #s > maximum then s = ns.Cut(s, maximum) end
	return s ~= "" and s or nil
end

local function GuildKey(faction, realmGroup, name)
	return ("g1:%s:%s:%s"):format(faction:lower(), realmGroup:lower(), name:lower())
end

local function ReporterCount(vouch)
	local n = 0
	if type(vouch) == "table" then
		for _ in pairs(vouch) do
			n = n + 1
			if n >= 8 then break end
		end
	end
	return n
end

local function CensusScope()
	local realm = Plain(ns.realm or (ns.CurrentRealm and ns.CurrentRealm()), 80)
	local realmGroup = Plain(ns.group, 160) or realm
	local faction = ns.faction == "Alliance" and "Alliance" or ns.faction == "Horde" and "Horde" or nil
	if not realm or not realmGroup or not faction then return nil end
	return { realm = realm, realmGroup = realmGroup, faction = faction }
end

local function GuildEntry(source, scope, now)
	local g = type(source) == "table" and source.g
	local name = type(source) == "table" and Plain(source.name, 96)
	if type(g) ~= "table" or not name then return nil end

	local observedAt = Whole(g.t, CHECKPOINT_MAX_TIME)
	local members = Whole(g.total, ns.Codec and ns.Codec.GUILD_CAP or 1000)
	local counted = source.counted == true
	-- Data.Summary guarantees that a fresh guild is inside the longer counted window. Keep
	-- that invariant explicit at this narrow boundary too, so online can never exceed the
	-- exported character total even if an incomplete source slips through during startup.
	local fresh = source.fresh == true and counted
	local online = fresh and math.min(members, Whole(g.online, members)) or 0
	local dispute
	if ns.Data and type(ns.Data.Dispute) == "function" then
		local ok, result = pcall(ns.Data.Dispute, g, now)
		if ok and type(result) == "table" then dispute = result end
	end
	local provenance = {
		source = g.mine and "roster" or "relay",
		reporters = g.mine and 1 or ReporterCount(g.vouch),
		disputed = dispute and dispute.disputed == true or false,
		singleSource = dispute and dispute.single ~= nil or false,
	}
	provenance.realm = Plain(g.realm or g.from, 80)
	provenance.heardOn = Plain(g.heardOn, 80)

	local out = {
		key = GuildKey(scope.faction, scope.realmGroup, name),
		name = name,
		members = members,
		online = online,
		fresh = fresh,
		counted = counted,
		observedAt = observedAt,
		provenance = provenance,
	}
	local serverTime = Whole(g.st, CHECKPOINT_MAX_TIME)
	if serverTime > 0 then out.observedAtServer = serverTime end
	return out
end

local function SeenEntry(source, scope)
	if type(source) ~= "table" then return nil end
	local name = Plain(source.name, 96)
	if not name then return nil end
	return {
		key = GuildKey(scope.faction, scope.realmGroup, name),
		name = name,
		online = Whole(source.online, ns.Codec and ns.Codec.GUILD_CAP or 1000),
		capped = source.capped == true,
		observedAt = Whole(source.t, CHECKPOINT_MAX_TIME),
	}
end

local function SortAndBound(byKey, maximum)
	local out = {}
	for _, value in pairs(byKey) do out[#out + 1] = value end
	table.sort(out, function(a, b) return a.key < b.key end)
	while #out > maximum do out[#out] = nil end
	return out
end

local function Summary(guilds, seen, linkedAlts)
	local out = {
		members = 0,
		characters = 0,
		linkedAlts = 0,
		online = 0,
		guilds = #guilds,
		freshGuilds = 0,
		seenOnlyGuilds = #seen,
		newestObservedAt = 0,
	}
	for _, g in ipairs(guilds) do
		if g.counted then out.characters = out.characters + g.members end
		if g.fresh then
			out.freshGuilds = out.freshGuilds + 1
			out.online = out.online + g.online
		end
		if g.observedAt > out.newestObservedAt then out.newestObservedAt = g.observedAt end
	end
	out.linkedAlts = math.min(out.characters, Whole(linkedAlts, out.characters))
	out.members = out.characters - out.linkedAlts
	return out
end

-- Versioned, additive, read-only census checkpoint source for the private bridge addon. The
-- bridge addon adds checkpoint identity, previousKey and tombstones in its own SavedVariables;
-- Olympus deliberately knows nothing about that file.
function OlympusBridge.GetCensusCheckpoint()
	local D = ns.Data
	if type(D) ~= "table" or type(D.Summary) ~= "function" then return nil end
	local ok, source = pcall(D.Summary)
	if not ok or type(source) ~= "table" then return nil end

	local scope = CensusScope()
	if not scope then return nil end
	local now = Whole(ns.Now and ns.Now(), CHECKPOINT_MAX_TIME)
	local serverNow
	if type(D.ServerTime) == "function" then
		local serverOK, value = pcall(D.ServerTime)
		if serverOK then
			value = Whole(value, CHECKPOINT_MAX_TIME)
			if value > 0 then serverNow = value end
		end
	end

	local guildByKey = {}
	for _, candidate in ipairs(source.guilds or {}) do
		local entry = GuildEntry(candidate, scope, now)
		if entry then
			local old = guildByKey[entry.key]
			if not old or entry.observedAt > old.observedAt then guildByKey[entry.key] = entry end
		end
	end
	local guilds = SortAndBound(guildByKey, CHECKPOINT_MAX_GUILDS)

	local seenByKey = {}
	for _, candidate in ipairs(source.seen or {}) do
		local entry = SeenEntry(candidate, scope)
		if entry and not guildByKey[entry.key] then
			local old = seenByKey[entry.key]
			if not old or entry.observedAt > old.observedAt then seenByKey[entry.key] = entry end
		end
	end
	local seen = SortAndBound(seenByKey, CHECKPOINT_MAX_SEEN)

	local checkpoint = {
		schema = CHECKPOINT_SCHEMA,
		version = CHECKPOINT_VERSION,
		capturedAt = now,
		timeSource = serverNow and "server" or "local",
		scope = scope,
		guilds = guilds,
		seenOnly = seen,
		summary = Summary(guilds, seen, source.alts),
	}
	if serverNow then checkpoint.capturedAtServer = serverNow end
	return checkpoint
end

-- The King's screen while the councillors' names are hidden there (his stream, ns.CouncilMasked,
-- 0.9.9): the chats put no mark on a councillor's line and /oly council cuts each name short, so
-- the bridge names nobody either, until he clicks the eye. An error there counts as hidden.
local function Masked()
	if type(ns.CouncilMasked) ~= "function" then return false end
	local ok, masked = pcall(ns.CouncilMasked)
	return not ok or masked == true
end

-- The same answer as the councillor mark in the Olympus chats (ns.IsHighCouncillor, not on the
-- King's screen while the names are hidden): a name on the signed list, on that list's realm
-- group. Anything else, or an error, is false.
function OlympusBridge.IsHighCouncillor(name)
	if type(name) ~= "string" or name == "" or type(ns.IsHighCouncillor) ~= "function" or Masked() then return false end
	local ok, yes = pcall(ns.IsHighCouncillor, name)
	return ok and yes == true
end

-- A fresh, sorted copy of the signed list's names (Workshop.CouncilNames, the names /oly council
-- prints), and the list's realm group ("A+B", or nil when it names none): the names count on
-- that group only, which OlympusBridge.IsHighCouncillor checks. Empty until a signed list has
-- been checked on this client, and on the King's screen while the names are hidden.
function OlympusBridge.GetCouncil()
	local c, W = ns.rdb and ns.rdb.council, ns.Workshop
	if type(c) ~= "table" or type(c.names) ~= "table" or type(W) ~= "table" or type(W.CouncilNames) ~= "function"
		or Masked() then
		return {}, nil
	end
	local ok, names = pcall(W.CouncilNames)
	if not ok or type(names) ~= "table" then return {}, nil end
	local out = {}
	for i = 1, math.min(#names, COUNCIL_MAX) do
		if type(names[i]) == "string" then out[#out + 1] = names[i] end
	end
	return out, type(c.realm) == "string" and c.realm or nil
end

-- Chat lines for a companion: fn(tier, sender, text) for each line from someone else that this
-- client accepted, after its checks (rank, blocked and ignored players, repeats, rate) and
-- Codec.SanitizeChat: the lines the history keeps and the Chat tab shows, our own left out. A
-- muted channel and a line the flood guard holds back pass on the same way, as those only decide
-- what this player's chat frame shows. Plain strings only, and an observer that errors is
-- skipped: it can never stop a line or the others.
local observers = {}
function OlympusBridge.RegisterChatObserver(fn)
	if type(fn) ~= "function" or #observers >= OBSERVERS_MAX then return false end
	observers[#observers + 1] = fn
	return true
end

ns.On("CHAT_LINE", function(tier, sender, text)
	if type(tier) ~= "string" or type(sender) ~= "string" or type(text) ~= "string" then return end
	for i = 1, #observers do pcall(observers[i], tier, sender, text) end
end)

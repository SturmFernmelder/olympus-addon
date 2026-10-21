local ADDON, addon = ...

local DB_SCHEMA = "olympus-companion-db"
local CHECKPOINT_SCHEMA = "olympus-census-checkpoint"
local VERSION = 1
local MAX_GUILDS = 256
local MAX_SEEN = 256
local MAX_TOMBSTONES = 512
local MAX_TIME = 9999999999
local MAX_CLOCK_SKEW = 300
local MAX_MEMBERS = 1000
local MAX_TOTAL = MAX_GUILDS * MAX_MEMBERS
local HASH_MOD = 4294967296

local function Whole(value, maximum)
	if type(value) ~= "number" or value ~= value or value ~= math.floor(value) or value < 0 then return nil end
	if maximum and value > maximum then return nil end
	return value
end

local function Plain(value, maximum)
	if type(value) ~= "string" or value == "" or #value > maximum or value:find("[|%c]") then return nil end
	return value
end

local function OptionalPlain(value, maximum)
	if value == nil then return nil, true end
	local out = Plain(value, maximum)
	return out, out ~= nil
end

local function Boolean(value)
	if type(value) == "boolean" then return value end
	return nil
end

local function NotAfter(value, ceiling)
	return value <= ceiling + MAX_CLOCK_SKEW
end

local function ArrayLength(value, maximum)
	if type(value) ~= "table" then return nil end
	local n = 0
	while value[n + 1] ~= nil do
		n = n + 1
		if n > maximum then return nil end
	end
	for key in pairs(value) do
		if type(key) == "number" and (key ~= math.floor(key) or key < 1 or key > n) then return nil end
	end
	return n
end

local function GuildKey(scope, name)
	return ("g1:%s:%s:%s"):format(scope.faction:lower(), scope.realmGroup:lower(), name:lower())
end

local function CheckpointKey(value)
	if type(value) ~= "string" or #value ~= 21 or value:sub(1, 5) ~= "ocp1-" then return nil end
	local hex = value:sub(6)
	if hex ~= hex:lower() or not hex:find("^[0-9a-f]+$") then return nil end
	return value
end

local function Hex(value)
	local digits, out = "0123456789abcdef", ""
	for _ = 1, 8 do
		local digit = value % 16
		out = digits:sub(digit + 1, digit + 1) .. out
		value = math.floor(value / 16)
	end
	return out
end

local function Fingerprint(checkpoint)
	local parts = {}
	local function Add(value)
		local text
		if value == nil then text = "-"
		elseif type(value) == "boolean" then text = value and "1" or "0"
		else text = tostring(value) end
		parts[#parts + 1] = #text .. ":" .. text
	end

	Add(checkpoint.schema); Add(checkpoint.version); Add(checkpoint.previousKey)
	Add(checkpoint.capturedAt); Add(checkpoint.capturedAtServer); Add(checkpoint.timeSource)
	Add(checkpoint.scope.realm); Add(checkpoint.scope.realmGroup); Add(checkpoint.scope.faction)
	local s = checkpoint.summary
	for _, key in ipairs({ "members", "characters", "linkedAlts", "online", "guilds", "freshGuilds", "seenOnlyGuilds", "newestObservedAt" }) do Add(s[key]) end
	for _, guild in ipairs(checkpoint.guilds) do
		Add(guild.key); Add(guild.name); Add(guild.members); Add(guild.online); Add(guild.fresh); Add(guild.counted)
		Add(guild.observedAt); Add(guild.observedAtServer)
		local p = guild.provenance
		Add(p.source); Add(p.realm); Add(p.heardOn); Add(p.reporters); Add(p.disputed); Add(p.singleSource)
	end
	for _, seen in ipairs(checkpoint.seenOnly) do
		Add(seen.key); Add(seen.name); Add(seen.online); Add(seen.capped); Add(seen.observedAt)
	end
	for _, tombstone in ipairs(checkpoint.tombstones or {}) do
		Add(tombstone.key); Add(tombstone.name); Add(tombstone.removedAt); Add(tombstone.removedAtServer)
		Add(tombstone.lastObservedAt); Add(tombstone.lastObservedAtServer); Add(tombstone.previousKey)
	end
	Add(checkpoint.tombstoneFloor or 0); Add(checkpoint.tombstoneFloorServer)

	local text = table.concat(parts)
	local first, second = 5381, 52711
	for i = 1, #text do
		local byte = text:byte(i)
		first = (first * 33 + byte) % HASH_MOD
		second = (second * 65599 + byte) % HASH_MOD
	end
	return "ocp1-" .. Hex(first) .. Hex(second)
end

local function CopyScope(raw)
	if type(raw) ~= "table" then return nil end
	local realm = Plain(raw.realm, 80)
	local realmGroup = Plain(raw.realmGroup, 160)
	local faction = raw.faction == "Alliance" and "Alliance" or raw.faction == "Horde" and "Horde" or nil
	if not realm or not realmGroup or not faction then return nil end
	return { realm = realm, realmGroup = realmGroup, faction = faction }
end

local function CopyGuild(raw, scope)
	if type(raw) ~= "table" or type(raw.provenance) ~= "table" then return nil end
	local name = Plain(raw.name, 96)
	local members = Whole(raw.members, MAX_MEMBERS)
	local online = Whole(raw.online, MAX_MEMBERS)
	local observedAt = Whole(raw.observedAt, MAX_TIME)
	local fresh, counted = Boolean(raw.fresh), Boolean(raw.counted)
	local source = raw.provenance.source
	if source ~= "roster" and source ~= "relay" then return nil end
	local reporters = Whole(raw.provenance.reporters, 8)
	local disputed = Boolean(raw.provenance.disputed)
	local singleSource = Boolean(raw.provenance.singleSource)
	local realm, realmOK = OptionalPlain(raw.provenance.realm, 80)
	local heardOn, heardOK = OptionalPlain(raw.provenance.heardOn, 80)
	local observedAtServer = raw.observedAtServer and Whole(raw.observedAtServer, MAX_TIME) or nil
	if not name or members == nil or online == nil or observedAt == nil or fresh == nil or counted == nil
		or reporters == nil or disputed == nil or singleSource == nil or not realmOK or not heardOK
		or (raw.observedAtServer ~= nil and observedAtServer == nil) or online > members or (not fresh and online ~= 0) then
		return nil
	end
	if fresh and not counted then return nil end
	local key = GuildKey(scope, name)
	if raw.key ~= key then return nil end
	local out = {
		key = key,
		name = name,
		members = members,
		online = online,
		fresh = fresh,
		counted = counted,
		observedAt = observedAt,
		provenance = {
			source = source,
			reporters = reporters,
			disputed = disputed,
			singleSource = singleSource,
		},
	}
	if observedAtServer then out.observedAtServer = observedAtServer end
	if realm then out.provenance.realm = realm end
	if heardOn then out.provenance.heardOn = heardOn end
	return out
end

local function CopySeen(raw, scope)
	if type(raw) ~= "table" then return nil end
	local name = Plain(raw.name, 96)
	local online = Whole(raw.online, MAX_MEMBERS)
	local capped = Boolean(raw.capped)
	local observedAt = Whole(raw.observedAt, MAX_TIME)
	if not name or online == nil or capped == nil or observedAt == nil then return nil end
	local key = GuildKey(scope, name)
	if raw.key ~= key then return nil end
	return { key = key, name = name, online = online, capped = capped, observedAt = observedAt }
end

local function BuildSummary(guilds, seen, linkedAlts)
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
	for _, guild in ipairs(guilds) do
		if guild.counted then out.characters = out.characters + guild.members end
		if guild.fresh then
			out.freshGuilds = out.freshGuilds + 1
			out.online = out.online + guild.online
		end
		if guild.observedAt > out.newestObservedAt then out.newestObservedAt = guild.observedAt end
	end
	out.linkedAlts = math.min(out.characters, linkedAlts or 0)
	out.members = out.characters - out.linkedAlts
	return out
end

local function SameSummary(left, right)
	for _, key in ipairs({ "members", "characters", "linkedAlts", "online", "guilds", "freshGuilds", "seenOnlyGuilds", "newestObservedAt" }) do
		if left[key] ~= right[key] then return false end
	end
	return true
end

local function CopySource(raw)
	if type(raw) ~= "table" or raw.schema ~= CHECKPOINT_SCHEMA or raw.version ~= VERSION then return nil end
	local capturedAt = Whole(raw.capturedAt, MAX_TIME)
	local capturedAtServer = raw.capturedAtServer and Whole(raw.capturedAtServer, MAX_TIME) or nil
	if not capturedAt or (raw.capturedAtServer ~= nil and not capturedAtServer) then return nil end
	if raw.timeSource ~= "local" and raw.timeSource ~= "server" then return nil end
	if (raw.timeSource == "server") ~= (capturedAtServer ~= nil) then return nil end
	local scope = CopyScope(raw.scope)
	local guildCount = ArrayLength(raw.guilds, MAX_GUILDS)
	local seenCount = ArrayLength(raw.seenOnly, MAX_SEEN)
	if not scope or guildCount == nil or seenCount == nil or type(raw.summary) ~= "table" then return nil end

	local guilds, guildKeys, previousKey = {}, {}, nil
	for i = 1, guildCount do
		local guild = CopyGuild(raw.guilds[i], scope)
		if not guild or not NotAfter(guild.observedAt, capturedAt)
			or (guild.observedAtServer and capturedAtServer and not NotAfter(guild.observedAtServer, capturedAtServer))
			or guildKeys[guild.key] or (previousKey and guild.key <= previousKey) then return nil end
		guilds[i], guildKeys[guild.key], previousKey = guild, true, guild.key
	end
	local seen, seenKeys = {}, {}
	previousKey = nil
	for i = 1, seenCount do
		local entry = CopySeen(raw.seenOnly[i], scope)
		if not entry or not NotAfter(entry.observedAt, capturedAt)
			or guildKeys[entry.key] or seenKeys[entry.key] or (previousKey and entry.key <= previousKey) then return nil end
		seen[i], seenKeys[entry.key], previousKey = entry, true, entry.key
	end

	local linkedAlts = Whole(raw.summary.linkedAlts, MAX_TOTAL)
	if linkedAlts == nil then return nil end
	local expected = BuildSummary(guilds, seen, linkedAlts)
	if not NotAfter(expected.newestObservedAt, capturedAt) then return nil end
	local supplied = {}
	for _, key in ipairs({ "members", "characters", "linkedAlts", "online", "guilds", "freshGuilds", "seenOnlyGuilds", "newestObservedAt" }) do
		supplied[key] = Whole(raw.summary[key], key == "newestObservedAt" and MAX_TIME or MAX_TOTAL)
		if supplied[key] == nil then return nil end
	end
	if not SameSummary(expected, supplied) then return nil end

	local out = {
		schema = CHECKPOINT_SCHEMA,
		version = VERSION,
		capturedAt = capturedAt,
		timeSource = raw.timeSource,
		scope = scope,
		summary = expected,
		guilds = guilds,
		seenOnly = seen,
	}
	if capturedAtServer then out.capturedAtServer = capturedAtServer end
	return out
end

local function CopyTombstone(raw, scope)
	if type(raw) ~= "table" then return nil end
	local name = Plain(raw.name, 96)
	local removedAt = Whole(raw.removedAt, MAX_TIME)
	local lastObservedAt = Whole(raw.lastObservedAt, MAX_TIME)
	local previousKey = CheckpointKey(raw.previousKey)
	local removedAtServer = raw.removedAtServer and Whole(raw.removedAtServer, MAX_TIME) or nil
	local lastObservedAtServer = raw.lastObservedAtServer and Whole(raw.lastObservedAtServer, MAX_TIME) or nil
	if not name or not removedAt or not lastObservedAt or not previousKey
		or (raw.removedAtServer ~= nil and not removedAtServer)
		or (raw.lastObservedAtServer ~= nil and not lastObservedAtServer) then return nil end
	local key = GuildKey(scope, name)
	if raw.key ~= key then return nil end
	local out = {
		key = key,
		name = name,
		removedAt = removedAt,
		lastObservedAt = lastObservedAt,
		previousKey = previousKey,
	}
	if removedAtServer then out.removedAtServer = removedAtServer end
	if lastObservedAtServer then out.lastObservedAtServer = lastObservedAtServer end
	return out
end

local function CopyFinal(raw)
	local out = CopySource(raw)
	if not out then return nil end
	local key = CheckpointKey(raw.key)
	local previousKey = raw.previousKey and CheckpointKey(raw.previousKey) or nil
	local floor = Whole(raw.tombstoneFloor, MAX_TIME)
	local floorServer = raw.tombstoneFloorServer and Whole(raw.tombstoneFloorServer, MAX_TIME) or nil
	local count = ArrayLength(raw.tombstones, MAX_TOMBSTONES)
	if not key or (raw.previousKey ~= nil and not previousKey) or floor == nil
		or (raw.tombstoneFloorServer ~= nil and not floorServer) or count == nil then return nil end
	if previousKey == key then return nil end

	local live, seen, tombstones, last = {}, {}, {}, nil
	for _, guild in ipairs(out.guilds) do live[guild.key] = true end
	for i = 1, count do
		local tombstone = CopyTombstone(raw.tombstones[i], out.scope)
		if not tombstone or not NotAfter(tombstone.removedAt, out.capturedAt)
			or not NotAfter(tombstone.lastObservedAt, tombstone.removedAt)
			or (tombstone.removedAtServer and out.capturedAtServer
				and not NotAfter(tombstone.removedAtServer, out.capturedAtServer))
			or (tombstone.lastObservedAtServer and tombstone.removedAtServer
				and not NotAfter(tombstone.lastObservedAtServer, tombstone.removedAtServer))
			or live[tombstone.key] or seen[tombstone.key] or (last and tombstone.key <= last) then return nil end
		tombstones[i], seen[tombstone.key], last = tombstone, true, tombstone.key
	end
	if not NotAfter(floor, out.capturedAt)
		or (floorServer and out.capturedAtServer and not NotAfter(floorServer, out.capturedAtServer)) then return nil end
	out.key = key
	out.previousKey = previousKey
	out.tombstones = tombstones
	out.tombstoneFloor = floor
	if floorServer then out.tombstoneFloorServer = floorServer end
	if Fingerprint(out) ~= key then return nil end
	return out
end

local function SameScope(left, right)
	return left and right and left.realm == right.realm and left.realmGroup == right.realmGroup and left.faction == right.faction
end

local function NewerThanTombstone(guild, tombstone)
	if guild.observedAtServer and tombstone.removedAtServer then return guild.observedAtServer > tombstone.removedAtServer end
	return guild.observedAt > tombstone.removedAt
end

local function NewerThanFloor(guild, floor, floorServer)
	if guild.observedAtServer and floorServer then return guild.observedAtServer > floorServer end
	return guild.observedAt > floor
end

local function CopyTable(value)
	local out = {}
	for key, item in pairs(value) do out[key] = item end
	return out
end

local function FinalizeSource(source, previous)
	if previous and not SameScope(source.scope, previous.scope) then previous = nil end
	if previous and #source.guilds == 0 and #previous.guilds > 0 then return nil end

	local floor = previous and previous.tombstoneFloor or 0
	local floorServer = previous and previous.tombstoneFloorServer or nil
	local tombstoneByKey = {}
	if previous then
		for _, tombstone in ipairs(previous.tombstones) do tombstoneByKey[tombstone.key] = CopyTable(tombstone) end
	end

	local guilds, live = {}, {}
	for _, guild in ipairs(source.guilds) do
		local tombstone = tombstoneByKey[guild.key]
		if NewerThanFloor(guild, floor, floorServer) and (not tombstone or NewerThanTombstone(guild, tombstone)) then
			guilds[#guilds + 1], live[guild.key], tombstoneByKey[guild.key] = guild, true, nil
		end
	end

	local previousKey = previous and previous.key or nil
	if previous then
		local removedAt = math.max(source.capturedAt, previous.capturedAt)
		local removedAtServer
		if source.capturedAtServer or previous.capturedAtServer then
			removedAtServer = math.max(source.capturedAtServer or 0, previous.capturedAtServer or 0)
		end
		for _, guild in ipairs(previous.guilds) do
			if not live[guild.key] then
				tombstoneByKey[guild.key] = {
					key = guild.key,
					name = guild.name,
					removedAt = removedAt,
					lastObservedAt = guild.observedAt,
					previousKey = previous.key,
					removedAtServer = removedAtServer,
					lastObservedAtServer = guild.observedAtServer,
				}
			end
		end
	end

	local ranked = {}
	for _, tombstone in pairs(tombstoneByKey) do ranked[#ranked + 1] = tombstone end
	table.sort(ranked, function(a, b)
		if a.removedAt ~= b.removedAt then return a.removedAt > b.removedAt end
		return a.key < b.key
	end)
	for i = MAX_TOMBSTONES + 1, #ranked do
		floor = math.max(floor, ranked[i].removedAt)
		if ranked[i].removedAtServer then floorServer = math.max(floorServer or 0, ranked[i].removedAtServer) end
	end
	while #ranked > MAX_TOMBSTONES do ranked[#ranked] = nil end
	table.sort(ranked, function(a, b) return a.key < b.key end)

	table.sort(guilds, function(a, b) return a.key < b.key end)
	local finalGuilds = {}
	for _, guild in ipairs(guilds) do
		if NewerThanFloor(guild, floor, floorServer) then finalGuilds[#finalGuilds + 1] = guild end
	end
	source.guilds = finalGuilds
	source.tombstones = ranked
	source.tombstoneFloor = floor
	if floorServer and floorServer > 0 then source.tombstoneFloorServer = floorServer end
	source.previousKey = previousKey
	source.summary = BuildSummary(source.guilds, source.seenOnly, source.summary.linkedAlts)
	source.key = Fingerprint(source)
	return source
end

local function CurrentDB()
	if type(OlympusCompanionDB) ~= "table" or OlympusCompanionDB.schema ~= DB_SCHEMA or OlympusCompanionDB.version ~= VERSION then return nil end
	return OlympusCompanionDB
end

local function ResetDB(checkpoint)
	OlympusCompanionDB = { schema = DB_SCHEMA, version = VERSION }
	if checkpoint then OlympusCompanionDB.checkpoint = checkpoint end
	return OlympusCompanionDB
end

-- Chat reaches this private SavedVariable only through Olympus's consent-gated recorder. Rows are
-- compact because the file shares the addon's 4 MiB read budget; text is last and may contain ~.
-- A revoked/missing answer discards both the in-memory record and a previous session's copy.
local CHAT_VERSION = 1
local CHAT_MAX = 5000
local CHAT_BYTES = 1572864
local CHAT_TEXT = 255
local CHAT_ROOMS = { A = true, C = true, L = true }
local chatLines, chatBytes = {}, 0

local function ClearChat()
	chatLines, chatBytes = {}, 0
end

local function CompanionAccepted()
	local bridge = rawget(_G, "OlympusBridge")
	if type(bridge) ~= "table" or type(bridge.CompanionAccepted) ~= "function" then return false end
	local ok, accepted = pcall(bridge.CompanionAccepted)
	return ok and accepted == true
end

local function Cut(value, maximum)
	if #value <= maximum then return value end
	local byte = value:byte(maximum + 1)
	while maximum > 0 and byte and byte >= 128 and byte < 192 do
		maximum = maximum - 1
		byte = value:byte(maximum + 1)
	end
	return value:sub(1, maximum)
end

local function ChatText(value)
	if type(value) ~= "string" then return nil end
	local s = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
	s = s:gsub("[|%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if s == "" then return nil end
	if #s > CHAT_TEXT then s = Cut(s, CHAT_TEXT) end
	return s
end

local function ChatRow(at, room, isSelf, author, text)
	at = Whole(at, MAX_TIME)
	room = CHAT_ROOMS[room] and room or nil -- the exact native Olympus/Captains/Lords lane
	author = Plain(author, 64)
	if author and author:find("~", 1, true) then author = nil end
	text = ChatText(text)
	if not (at and room and author and text) then return nil end
	return ("%d~%s~%d~%s~%s"):format(at, room, isSelf and 1 or 0, author, text)
end

local function KeepChat(row)
	if not row then return end
	chatLines[#chatLines + 1] = row
	chatBytes = chatBytes + #row
	while #chatLines > CHAT_MAX or chatBytes > CHAT_BYTES do
		chatBytes = chatBytes - #table.remove(chatLines, 1)
	end
end

local function ChatNow()
	for _, name in ipairs({ "GetServerTime", "time" }) do
		local get = rawget(_G, name)
		if type(get) == "function" then
			local ok, now = pcall(get)
			if ok and Whole(now, MAX_TIME) and now > 0 then return now end
		end
	end
	return 0
end

local function OnChatLine(room, author, text, isSelf)
	if not CompanionAccepted() then ClearChat() return end
	KeepChat(ChatRow(ChatNow(), room, isSelf == true, author, text))
end

local chatObserved, consentObserved = false, false
local function ObserveChat()
	local bridge = rawget(_G, "OlympusBridge")
	if type(bridge) ~= "table" then return end
	if not chatObserved and type(bridge.RegisterChatRecorder) == "function" then
		local ok, registered = pcall(bridge.RegisterChatRecorder, OnChatLine)
		chatObserved = ok and registered == true
	end
	if not consentObserved and type(bridge.RegisterCompanionConsentObserver) == "function" then
		local ok, registered = pcall(bridge.RegisterCompanionConsentObserver, function(accepted)
			if accepted ~= true then ClearChat() end
		end)
		consentObserved = ok and registered == true
	end
end

local function ChatRecord()
	if not CompanionAccepted() then ClearChat() return nil end
	if #chatLines == 0 then return nil end
	local lines = {}
	for i, row in ipairs(chatLines) do lines[i] = row end
	return { version = CHAT_VERSION, lines = lines }
end

local function LoadDB()
	local db = CurrentDB()
	local checkpoint = db and CopyFinal(db.checkpoint) or nil
	ClearChat()
	if CompanionAccepted() and db and type(db.chat) == "table" and db.chat.version == CHAT_VERSION and type(db.chat.lines) == "table" then
		for i = 1, math.min(#db.chat.lines, CHAT_MAX) do
			local row = db.chat.lines[i]
			if type(row) == "string" then
				local at, room, isSelf, author, text = row:match("^(%d+)~([^~]+)~([01])~([^~]+)~(.+)$")
				if at then KeepChat(ChatRow(tonumber(at), room, isSelf == "1", author, text)) end
			end
		end
	end
	return ResetDB(checkpoint)
end

-- The sections this sidecar knows, at the version it knows (Bridge.lua's registry). Olympus has
-- already copied each into plain tables within its limits; an unknown name or version is skipped.
-- (931: every tab's, companion/BRIDGE-SECTIONS.md: the realm's, the roster's, the Church's, the
-- games', the profile's, and the affairs' of Olympus/BridgeAffairs.lua.)
local KNOWN_SECTIONS = { guilds = 1, membership = 1, rankings = 1, self = 1, stats = 1, wanted = 1,
	realm = 1, roster = 1, church = 1, games = 1, profile = 1,
	crafting = 1, crafters = 1, treasury = 1, decrees = 1, agenda = 1, notices = 1, watch = 1, chatRooms = 1 }

local function CopySections(bridge)
	if type(bridge) ~= "table" or bridge.SECTIONS_API_VERSION ~= 1 or type(bridge.GetSection) ~= "function" then return nil end
	local out, any = {}, false
	for name, version in pairs(KNOWN_SECTIONS) do
		local ok, section = pcall(bridge.GetSection, name)
		if ok and type(section) == "table" and section.version == version and type(section.data) == "table" then
			out[name] = { version = version, data = section.data }
			any = true
		end
	end
	return any and out or nil
end

local function Finalize()
	local db = CurrentDB() or LoadDB()
	local previous = CopyFinal(db.checkpoint)
	local bridge = rawget(_G, "OlympusBridge")
	local sections = CopySections(bridge)
	local chat = ChatRecord()
	local function Keep(checkpoint)
		local out = ResetDB(checkpoint)
		out.sections = sections
		out.chat = chat
	end
	if type(bridge) ~= "table" or bridge.CENSUS_CHECKPOINT_API_VERSION ~= VERSION
		or type(bridge.GetCensusCheckpoint) ~= "function" then Keep(previous) return false end
	local ok, raw = pcall(bridge.GetCensusCheckpoint)
	if not ok then Keep(previous) return false end
	local source = CopySource(raw)
	if not source then Keep(previous) return false end
	local checkpoint = FinalizeSource(source, previous)
	if not checkpoint then Keep(previous) return false end
	Keep(checkpoint)
	return true
end

addon.Finalize = Finalize
addon.LoadDB = LoadDB
addon.CopySource = CopySource
addon.Fingerprint = Fingerprint
addon.OnChatLine = OnChatLine

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		local bridge = rawget(_G, "OlympusBridge")
		if type(bridge) == "table" then bridge.COMPANION_ATTACHED = true end
		ObserveChat()
		LoadDB()
	elseif event == "PLAYER_LOGOUT" then
		Finalize()
	end
end)

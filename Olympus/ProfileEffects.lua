local ADDON, ns = ...

-- A bounded, host-owned profile presentation for integrations.  The caller chooses only a
-- supported style and one pre-approved caption; Olympus owns the art, transport, lifetime and
-- target-frame rendering.  It is deliberately self-only: a client can announce a temporary
-- presentation for its own character, never assign one to another player or provide texture
-- paths, atlas names, colours, coordinates or arbitrary text.
--
--   FX~2~G~<style>~<session>~<sequence>~<server time>~<guild>~<grant id>
--   FX~2~C~<style>~<session>~<sequence>~<server time>~<guild>~<grant id>
--   FX~2~S~<style>~<session>~<sequence>~<server time>~<guild>~<issuer>~<grant id>~<caption>
--   FX~2~X~<style>~<session>~<sequence>~<server time>~<guild>~<issuer>~<grant id>
--
-- The server stamps the sender.  An authorized Olympus issuer opens and renews one bounded grant;
-- while it is live an admitted guild member may announce only the fixed host-owned style and
-- caption for their own character.  Receivers keep grants and presentations in memory only and
-- show one only while directly targeting its sender.  Stops and closes win over older words; every
-- missed close expires on its own.  Nothing here changes a protected unit frame or performs a
-- protected action: the two textures and the portrait copy belong to Olympus.

local Effects = {}
ns.ProfileEffects = Effects

Effects.VERSION = 2
Effects.HEARTBEAT = 10
Effects.LEASE_TTL = 32
Effects.SESSION_TTL = 32
Effects.DISPLAY_FOR = 2.5
Effects.CAPTION_MAX = 160
Effects.MAX_SENDERS = 128
Effects.ORDER_MAX = 256
Effects.RATE_SENDERS = 256
Effects.MAX_SESSIONS = 16
Effects.SESSION_ORDER_MAX = 32

-- SHA-256, not the caption itself.  Keeping the sentence out of the public source also prevents
-- this generic API from becoming an arbitrary remote-message primitive.  A supported integration
-- supplies the exact approved sentence; a different byte is refused on both sender and receiver.
local STYLES = {
	shadow = { wire = "s", caption = "195ea567b71354d2c4b1a6c87f46c27a10badea18c9705efad159d8c0e5056df" },
}
local BY_WIRE = {}
for name, spec in pairs(STYLES) do spec.name = name; BY_WIRE[spec.wire] = spec end

local session = math.random and math.random(1, 999999) or 1
local grantSequence = math.random and math.random(1, 999999) or 1
local sequence = 0
local outgoing -- { owner, style, caption, grantIssuer, grantID, grantKey }
local outgoingSession -- { owner, style, id, key }
local ticker
local sessionTicker
local leases = {} -- folded sender -> { name, guild, style, caption, session, sequence, at, expires }
local leaseCount = 0
local order = {} -- folded sender -> latest control word, including a stop
local orderCount = 0
local retired = {} -- folded sender -> { [old session] = monotonic time }, bounded by lease cleanup
local grants, grantCount = {}, 0 -- issuer + grant id -> authenticated, bounded session lease
local grantOrder, grantOrderCount = {}, 0 -- folded issuer -> latest G/C control word
local grantRetired = {} -- folded issuer -> old addon sessions, bounded like effect replay state
local buckets, bucketCount, admissionStats = {}, 0, {}
local ui, waitingUI
local shownTarget, shownSession
local displayGeneration, displayUntil = 0, 0
local screenshotHidden = false
local stats = { sent = 0, received = 0, shown = 0, stopped = 0, expired = 0, dropped = {} }

local function Drop(why)
	stats.dropped[why] = (stats.dropped[why] or 0) + 1
	return false, why
end

local function Mono()
	if type(GetTime) == "function" then
		local ok, value = pcall(GetTime)
		if ok and type(value) == "number" then return value end
	end
	return ns.Now and ns.Now() or 0
end

local function Clock()
	local D = ns.Data
	if type(D) == "table" and type(D.ServerTime) == "function" then
		local ok, value = pcall(D.ServerTime)
		if ok and type(value) == "number" then return math.floor(value) end
	end
	if type(GetServerTime) == "function" then
		local ok, value = pcall(GetServerTime)
		if ok and type(value) == "number" then return math.floor(value) end
	end
	return math.floor(ns.Now and ns.Now() or 0)
end

local function Integer(value, low, high)
	value = tonumber(value)
	return value and value == math.floor(value) and value >= low and value <= high and value or nil
end

local function Secret(value)
	if type(issecretvalue) ~= "function" then return false end
	local ok, yes = pcall(issecretvalue, value)
	return not ok or yes == true
end

local function Plain(value, max)
	if Secret(value) or type(value) ~= "string" or value == "" or #value > max then return nil end
	if value:find("[~|%c]") then return nil end
	return value
end

local function Hex(bytes)
	if type(bytes) ~= "string" then return nil end
	return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local function Caption(style, text)
	local spec = STYLES[style]
	text = Plain(text, Effects.CAPTION_MAX)
	local S = ns.Sign
	if not spec or not text or type(S) ~= "table" or type(S.SHA256) ~= "function" then return nil end
	local ok, digest = pcall(S.SHA256, text)
	if not ok or Hex(digest) ~= spec.caption then return nil end
	return text
end

local function Guild(value)
	value = Plain(value, 48)
	return value and ns.IsFederation and ns.IsFederation(value) and value or nil
end

local function SelfOff()
	local M = ns.Moderation
	return type(M) == "table" and type(M.SelfOff) == "function" and M.SelfOff() or nil
end

local function Fold(value)
	value = ns.FullName and ns.FullName(value) or value
	if type(value) ~= "string" then return nil end
	return ns.Fold and ns.Fold(value) or value:lower()
end

local function CurrentGuild()
	if type(GetGuildInfo) ~= "function" then return nil end
	local ok, guild = pcall(GetGuildInfo, "player")
	return ok and Guild(guild) or nil
end

local function Member()
	return type(ns.IsMember) == "function" and ns.IsMember() == true and CurrentGuild() ~= nil
end

-- Only a signed Olympus authority may open the short shared session.  Once that authenticated
-- grant is live, an admitted member may present the one host-owned effect on themself; channel
-- admission alone can neither create nor prolong the grant.
local function Authorized(name)
	local M = ns.Moderation
	if type(M) ~= "table" or type(M.IsIssuer) ~= "function" or type(name) ~= "string" then return false end
	local ok, allowed = pcall(M.IsIssuer, name)
	return ok and allowed == true
end

local function AuthorizedSelf()
	return type(ns.me) == "string" and Authorized(ns.me)
end

local function GuardedComm()
	local C = ns.Comm
	return type(C) == "table" and type(C.Send) == "function" and C or nil
end

local function NextSequence()
	sequence = sequence % 999999 + 1
	return sequence
end

local function StopTicker()
	if ticker and type(ticker.Cancel) == "function" then ticker.Cancel() end
	ticker = nil
end

local function StopSessionTicker()
	if sessionTicker and type(sessionTicker.Cancel) == "function" then sessionTicker.Cancel() end
	sessionTicker = nil
end

local function GrantKey(issuer, id)
	local key = Fold(issuer)
	id = Integer(id, 1, 999999)
	return key and id and (key .. "\031" .. tostring(id)) or nil
end

local FindGrant, CurrentGrant, PutGrant, DropGrant, Hidden, HideUI

local function Message(kind, state)
	local spec, guild = STYLES[state.style], CurrentGuild()
	if not spec or not guild then return nil end
	local seq, at = NextSequence(), Clock()
	local text = ("FX~%d~%s~%s~%d~%d~%d~%s"):format(Effects.VERSION, kind, spec.wire, session, seq, at, guild)
	if kind == "G" or kind == "C" then
		text = text .. "~" .. tostring(state.id)
	else
		text = text .. "~" .. state.grantIssuer .. "~" .. tostring(state.grantID)
		if kind == "S" then text = text .. "~" .. state.caption end
	end
	-- ChatThrottleLib and the game both cap one addon payload at 255 bytes.  The current fixed
	-- caption is comfortably below it, but fail closed if a future host-owned style is not.
	if #text > 255 then return nil end
	return text, seq, at
end

local function SendEffect(kind, state)
	local C = GuardedComm()
	if not C or not Member() or SelfOff() then return false, "unavailable" end
	if not FindGrant or not FindGrant(state.grantIssuer, state.grantID, Mono()) then return false, "session" end
	local text, seq = Message(kind, state)
	if not text then return false, "guild" end
	local expectedOwner, expectedStyle, expectedGrant = state.owner, state.style, state.grantKey
	local function Guard()
		if not Member() or SelfOff() or not FindGrant(state.grantIssuer, state.grantID, Mono()) then return false end
		if kind == "X" then return outgoing == nil end
		return outgoing ~= nil and outgoing.owner == expectedOwner and outgoing.style == expectedStyle
			and outgoing.grantKey == expectedGrant
	end
	local accepted = C.Send("CHANNEL", text, "profile-effect", false, false, nil, { owner = Effects, guard = Guard })
	if accepted then stats.sent = stats.sent + 1 end
	return accepted == true, accepted == true and seq or "busy"
end

local function SendSession(kind, state)
	local C = GuardedComm()
	if not C or not Member() or SelfOff() or not AuthorizedSelf() then return false, "unavailable" end
	local text, seq = Message(kind, state)
	if not text then return false, "guild" end
	local expectedOwner, expectedID = state.owner, state.id
	local function Guard()
		if not Member() or SelfOff() or not AuthorizedSelf() then return false end
		if kind == "C" then return outgoingSession == nil end
		return outgoingSession ~= nil and outgoingSession.owner == expectedOwner and outgoingSession.id == expectedID
	end
	local accepted = C.Send("CHANNEL", text, "profile-effect session", false, false, nil, { owner = Effects, guard = Guard })
	if accepted then stats.sent = stats.sent + 1 end
	return accepted == true, accepted == true and seq or "busy"
end

local function Heartbeat()
	if not outgoing then StopTicker() return end
	if not Member() or SelfOff() or not FindGrant(outgoing.grantIssuer, outgoing.grantID, Mono()) then
		outgoing = nil
		StopTicker()
		return
	end
	SendEffect("S", outgoing)
end

local function StartTicker()
	if ticker or type(ns.Every) ~= "function" then return end
	ticker = ns.Every(Effects.HEARTBEAT, "profile effect", Heartbeat)
end

local function SessionHeartbeat()
	if not outgoingSession then StopSessionTicker() return end
	if not Member() or SelfOff() or not AuthorizedSelf() then
		local key = outgoingSession.key
		outgoingSession = nil
		StopSessionTicker()
		if DropGrant then DropGrant(key) end
		return
	end
	local now = Mono()
	if PutGrant then
		PutGrant({ issuer = ns.me, guild = CurrentGuild(), style = outgoingSession.style,
			id = outgoingSession.id, key = outgoingSession.key, at = Clock(), expires = now + Effects.SESSION_TTL })
	end
	SendSession("G", outgoingSession)
end

local function StartSessionTicker()
	if sessionTicker or type(ns.Every) ~= "function" then return end
	sessionTicker = ns.Every(Effects.HEARTBEAT, "profile effect session", SessionHeartbeat)
end

local function NextGrantID()
	for _ = 1, 8 do
		grantSequence = grantSequence % 999999 + 1
		local key = GrantKey(ns.me, grantSequence)
		if key and grants[key] == nil then return grantSequence, key end
	end
	return nil
end

-- Called by the consented public API. `owner` is the handle's opaque session-local key.  Opening
-- the session remains issuer-only; its only payload is the fixed host-owned style and duration.
function Effects.SetSession(owner, style, enabled)
	if type(owner) ~= "string" or owner == "" then return false, "owner" end
	if enabled ~= true and enabled ~= false then return false, "state" end
	if enabled then
		if not Member() then return false, "guild" end
		if SelfOff() then return false, "held" end
		if not AuthorizedSelf() then return false, "authority" end
		if not STYLES[style] then return false, "style" end
		if outgoingSession and outgoingSession.owner ~= owner then return false, "busy" end
		if outgoingSession and outgoingSession.style == style then return true end
		local id, key = NextGrantID()
		if not id then return false, "full" end
		local prior = outgoingSession
		outgoingSession = { owner = owner, style = style, id = id, key = key }
		PutGrant({ issuer = ns.me, guild = CurrentGuild(), style = style, id = id, key = key,
			at = Clock(), expires = Mono() + Effects.SESSION_TTL })
		local ok, why = SendSession("G", outgoingSession)
		if not ok then
			DropGrant(key)
			outgoingSession = prior
			return false, why
		end
		StartSessionTicker()
		return true
	end
	if not outgoingSession then return true end
	if outgoingSession.owner ~= owner then return false, "owner" end
	local ending = outgoingSession
	outgoingSession = nil
	StopSessionTicker()
	-- Queue the authenticated close before removing the local grant.  A refused close cannot keep
	-- it alive: every receiver expires it after SESSION_TTL.
	SendSession("C", ending)
	DropGrant(ending.key)
	return true
end

function Effects.OpenSession(owner, style) return Effects.SetSession(owner, style, true) end
function Effects.CloseSession(owner)
	return Effects.SetSession(owner, outgoingSession and outgoingSession.style or "shadow", false)
end

-- Called by the consented public API. `owner` is the handle's opaque session-local key.
function Effects.Set(owner, style, enabled, caption)
	if type(owner) ~= "string" or owner == "" then return false, "owner" end
	if enabled ~= true and enabled ~= false then return false, "state" end
	if enabled then
		if not Member() then return false, "guild" end
		if SelfOff() then return false, "held" end
		caption = Caption(style, caption)
		if not caption then return false, STYLES[style] and "caption" or "style" end
		local grant = CurrentGrant and CurrentGrant(Mono()) or nil
		if not grant or grant.style ~= style then return false, "session" end
		if outgoing and outgoing.owner ~= owner then return false, "busy" end
		if outgoing and outgoing.style == style and outgoing.caption == caption and outgoing.grantKey == grant.key then return true end
		local prior = outgoing
		outgoing = { owner = owner, style = style, caption = caption, grantIssuer = grant.issuer,
			grantID = grant.id, grantKey = grant.key }
		local ok, why = SendEffect("S", outgoing)
		if not ok then outgoing = prior return false, why end
		StartTicker()
		return true
	end
	if not outgoing then return true end
	if outgoing.owner ~= owner then return false, "owner" end
	local ending = outgoing
	outgoing = nil
	StopTicker()
	-- A refused stop cannot prolong a lease: every receiver drops it after LEASE_TTL.
	SendEffect("X", ending)
	return true
end

function Effects.DisableOwner(owner)
	if not outgoing or outgoing.owner ~= owner then return false end
	Effects.Set(owner, outgoing.style, false)
	return true
end

function Effects.Outgoing()
	return outgoing and { style = outgoing.style } or nil
end

function Effects.Session()
	local grant = CurrentGrant and CurrentGrant(Mono()) or nil
	return grant and { style = grant.style, issuer = grant.issuer,
		expiresIn = math.max(0, grant.expires - Mono()) } or nil
end

local function Retire(key, oldSession, now)
	if not oldSession then return end
	local list = retired[key] or {}
	retired[key] = list
	list[oldSession] = now
	local n = 0
	for id, at in pairs(list) do
		if now - at > Effects.LEASE_TTL * 2 then list[id] = nil else n = n + 1 end
	end
	if n > 4 then
		local first, firstAt
		for id, at in pairs(list) do if not firstAt or at < firstAt then first, firstAt = id, at end end
		if first then list[first] = nil end
	end
end

local function Newer(key, remoteSession, remoteSequence, at, now)
	local last = order[key]
	if not last then return true end
	if last.session == remoteSession then return remoteSequence > last.sequence end
	if retired[key] and retired[key][remoteSession] then return false end
	-- A different addon session in the same server second waits for its next heartbeat. This closes
	-- a replay lane in which many fabricated sessions could otherwise displace the small retired set.
	if at <= last.at then return false end
	Retire(key, last.session, now)
	return true
end

local function RetireGrant(key, oldSession, now)
	if not oldSession then return end
	local list = grantRetired[key] or {}
	grantRetired[key] = list
	list[oldSession] = now
	local n = 0
	for id, heard in pairs(list) do
		if now - heard > Effects.SESSION_TTL * 2 then list[id] = nil else n = n + 1 end
	end
	if n > 4 then
		local first, firstAt
		for id, heard in pairs(list) do if not firstAt or heard < firstAt then first, firstAt = id, heard end end
		if first then list[first] = nil end
	end
end

local function NewerGrant(key, remoteSession, remoteSequence, at, now)
	local last = grantOrder[key]
	if not last then return true end
	if last.session == remoteSession then return remoteSequence > last.sequence end
	if grantRetired[key] and grantRetired[key][remoteSession] then return false end
	if at <= last.at then return false end
	RetireGrant(key, last.session, now)
	return true
end

local function IssuerHasGrant(issuerKey)
	for _, grant in pairs(grants) do
		if Fold(grant.issuer) == issuerKey then return true end
	end
	return false
end

local function RememberGrant(key, word, now)
	if not grantOrder[key] then
		if grantOrderCount >= Effects.SESSION_ORDER_MAX then
			local oldest, oldestAt
			for candidate, prior in pairs(grantOrder) do
				if not IssuerHasGrant(candidate) and (not oldestAt or (prior.heard or 0) < oldestAt) then
					oldest, oldestAt = candidate, prior.heard or 0
				end
			end
			if not oldest then return false end
			grantOrder[oldest], grantRetired[oldest], grantOrderCount = nil, nil, grantOrderCount - 1
		end
		grantOrderCount = grantOrderCount + 1
	end
	word.heard = now
	grantOrder[key] = word
	return true
end

local function Prune(now)
	local oldestKey, oldest
	for key, grant in pairs(grants) do
		if now >= grant.expires or not Authorized(grant.issuer)
			or (Hidden and Hidden(grant.issuer, grant.guild)) then
			DropGrant(key)
		end
	end
	for key, lease in pairs(leases) do
		if now >= lease.expires or grants[lease.grantKey] == nil then
			leases[key], leaseCount = nil, leaseCount - 1
			stats.expired = stats.expired + 1
		elseif not oldest or lease.expires < oldest then
			oldestKey, oldest = key, lease.expires
		end
	end
	for key, list in pairs(retired) do
		for id, at in pairs(list) do if now - at > Effects.LEASE_TTL * 2 then list[id] = nil end end
		if next(list) == nil then retired[key] = nil end
	end
	for key, list in pairs(grantRetired) do
		for id, heard in pairs(list) do if now - heard > Effects.SESSION_TTL * 2 then list[id] = nil end end
		if next(list) == nil then grantRetired[key] = nil end
	end
	for key, word in pairs(grantOrder) do
		if not IssuerHasGrant(key) and (type(word.heard) ~= "number" or now - word.heard > Effects.SESSION_TTL * 2) then
			grantOrder[key], grantRetired[key], grantOrderCount = nil, nil, grantOrderCount - 1
		end
	end
	for key, word in pairs(order) do
		if not leases[key] and (type(word.heard) ~= "number" or now - word.heard > Effects.LEASE_TTL * 2) then
			order[key], retired[key], orderCount = nil, nil, orderCount - 1
		end
	end
	for sender, bucket in pairs(buckets) do
		if type(bucket) ~= "table" or type(bucket.t) ~= "number" or now - bucket.t > Effects.LEASE_TTL * 2 then
			buckets[sender], bucketCount = nil, bucketCount - 1
		end
	end
	return oldestKey
end

local function Admit(sender, guild, now, id)
	local C = ns.Channels
	if type(C) ~= "table" or type(C.Admit) ~= "function" then return false end
	Prune(now)
	local known = buckets[sender] ~= nil
	if not known and bucketCount >= Effects.RATE_SENDERS then return false end
	local ok, accepted = pcall(C.Admit, sender, guild, "", now, {
		level = 1, id = id, buckets = buckets, stats = admissionStats, where = "profile effect",
	})
	if not ok or accepted ~= true then
		-- Channels.Admit allocates its bucket before its identity checks. A failed identity must not
		-- occupy this module's bounded sender registry.
		if not known then buckets[sender] = nil end
		return false
	end
	if not known and buckets[sender] then bucketCount = bucketCount + 1 end
	return true
end

local function Remember(key, word, now)
	if not order[key] then
		if orderCount >= Effects.ORDER_MAX then
			local oldest, oldestAt
			for candidate, prior in pairs(order) do
				if not leases[candidate] and (not oldestAt or (prior.heard or 0) < oldestAt) then
					oldest, oldestAt = candidate, prior.heard or 0
				end
			end
			if not oldest then return false end
			order[oldest], retired[oldest], orderCount = nil, nil, orderCount - 1
		end
		orderCount = orderCount + 1
	end
	word.heard = now
	order[key] = word
	return true
end

Hidden = function(sender, guild)
	local M = ns.Moderation
	if type(M) ~= "table" or type(M.Hides) ~= "function" then return false end
	local ok, hidden = pcall(M.Hides, sender, guild, true)
	return not ok or hidden ~= nil
end

local function Atlas(texture, name)
	if type(texture.SetAtlas) ~= "function" then return false end
	local ok, loaded = pcall(texture.SetAtlas, texture, name, true)
	return ok and loaded ~= false
end

local function Texture(parent, layer, sublevel)
	local ok, texture = pcall(parent.CreateTexture, parent, nil, layer, nil, sublevel)
	return ok and type(texture) == "table" and texture or nil
end

local function MakeMask(parent, texture, size, point)
	if type(parent.CreateMaskTexture) ~= "function" or type(texture.AddMaskTexture) ~= "function" then return nil end
	local ok, mask = pcall(parent.CreateMaskTexture, parent)
	if not ok or type(mask) ~= "table" or type(mask.SetTexture) ~= "function" then return nil end
	local set, loaded = pcall(mask.SetTexture, mask, "Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	if not set or loaded == false then return nil end
	mask:SetSize(size, size)
	mask:SetPoint(unpack(point))
	if not pcall(texture.AddMaskTexture, texture, mask) then return nil end
	return mask
end

HideUI = function()
	if not ui then return end
	if ui.target then ui.target:Hide() end
	if ui.message then ui.message:Hide() end
end

local function SessionChanged()
	if type(ns.Fire) == "function" then ns.Fire("PROFILE_EFFECT_SESSION_CHANGED") end
end

DropGrant = function(key)
	local grant = grants[key]
	if not grant then return false end
	grants[key], grantCount = nil, grantCount - 1
	if outgoingSession and outgoingSession.key == key then
		outgoingSession = nil
		StopSessionTicker()
	end
	if outgoing and outgoing.grantKey == key then
		outgoing = nil
		StopTicker()
	end
	local hid = false
	for senderKey, lease in pairs(leases) do
		if lease.grantKey == key then
			leases[senderKey], leaseCount = nil, leaseCount - 1
			if shownTarget == senderKey then hid = true end
		end
	end
	if hid then
		shownTarget, shownSession = nil, nil
		displayGeneration = displayGeneration + 1
		displayUntil = 0
		HideUI()
	end
	SessionChanged()
	return true
end

PutGrant = function(grant)
	if type(grant) ~= "table" or type(grant.issuer) ~= "string" or not STYLES[grant.style]
		or type(grant.guild) ~= "string" or type(grant.key) ~= "string"
		or not Integer(grant.id, 1, 999999) or type(grant.expires) ~= "number" then return false end
	local prior = grants[grant.key]
	if not prior and grantCount >= Effects.MAX_SESSIONS then
		local oldest, oldestAt
		for key, held in pairs(grants) do
			if not oldestAt or held.expires < oldestAt then oldest, oldestAt = key, held.expires end
		end
		if oldest then DropGrant(oldest) end
	end
	if not prior and grantCount >= Effects.MAX_SESSIONS then return false end
	grants[grant.key] = grant
	if type(ns.After) == "function" then
		local expected = grant.expires
		ns.After(math.max(0.05, expected - Mono() + 0.05), "profile effect session", function()
			local held = grants[grant.key]
			if held and held.expires == expected and Mono() >= expected then DropGrant(grant.key) end
		end)
	end
	if not prior then
		grantCount = grantCount + 1
		SessionChanged()
	end
	return true
end

FindGrant = function(issuer, id, now)
	local key = GrantKey(issuer, id)
	local grant = key and grants[key] or nil
	if not grant then return nil end
	now = type(now) == "number" and now or Mono()
	if now >= grant.expires or not Authorized(grant.issuer) or Hidden(grant.issuer, grant.guild) then
		DropGrant(key)
		return nil
	end
	return grant
end

CurrentGrant = function(now)
	now = type(now) == "number" and now or Mono()
	Prune(now)
	local best
	for _, grant in pairs(grants) do
		if not best or grant.at > best.at or (grant.at == best.at and grant.key < best.key) then best = grant end
	end
	return best
end

local function ClearTable(t)
	for key in pairs(t) do t[key] = nil end
end

-- Inbound grants are session memory only.  Leaving the federation or enabling the local hold is
-- an immediate boundary, not something an already accepted lease may outlive for 32 seconds.
local function ClearInbound()
	local hadSession = grantCount > 0
	ClearTable(leases)
	ClearTable(order)
	ClearTable(retired)
	ClearTable(grants)
	ClearTable(grantOrder)
	ClearTable(grantRetired)
	ClearTable(buckets)
	leaseCount, orderCount, bucketCount, grantCount, grantOrderCount = 0, 0, 0, 0, 0
	outgoing = nil
	outgoingSession = nil
	StopTicker()
	StopSessionTicker()
	shownTarget, shownSession = nil, nil
	displayGeneration = displayGeneration + 1
	displayUntil = 0
	screenshotHidden = false
	HideUI()
	if hadSession then SessionChanged() end
end

local function CanRender()
	if not Member() or SelfOff() then return false end
	if type(ns.GamepadUI) == "function" and ns.GamepadUI() then return false end
	local G = ns.Gate
	return type(G) == "table" and type(G.Allowed) == "function" and G.Allowed("borders") == true
end

local function EnsureUI()
	-- The live gate must precede the cached-frame return.  Otherwise a mouse-mode frame created
	-- earlier can be shown again after the client switches to its gamepad UI.
	if not CanRender() then return nil end
	if ui then return ui end
	if InCombatLockdown and InCombatLockdown() then waitingUI = true return nil end
	if type(CreateFrame) ~= "function" or type(UIParent) ~= "table" then return nil end
	local targetFrame = rawget(_G, "TargetFrame") -- gp:borders
	local container = type(targetFrame) == "table" and targetFrame.TargetFrameContainer or nil
	if type(container) ~= "table" then return nil end
	-- Both pieces are children of the target container.  They therefore inherit the game's own
	-- target-frame visibility instead of leaving an orphaned overlay on UIParent.
	local target = CreateFrame("Frame", nil, container) -- gp:borders
	target.olympus = true
	target:SetAllPoints(container) -- gp:borders
	if type(target.SetFrameStrata) == "function" then target:SetFrameStrata("HIGH") end
	if type(target.EnableMouse) == "function" then target:EnableMouse(false) end

	local main = Texture(target, "OVERLAY", 6)
	local light = Texture(target, "OVERLAY", 7)
	for _, texture in ipairs({ main, light }) do
		if texture and Atlas(texture, "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged") then
			texture:SetPoint("TOPRIGHT", target, "TOPRIGHT", 11, -4)
		else
			if texture then texture:Hide() end
		end
	end
	if main and type(main.SetVertexColor) == "function" then main:SetVertexColor(0.12, 0.14, 0.17, 1) end
	if light and type(light.SetVertexColor) == "function" then light:SetVertexColor(0.20, 0.32, 0.40, 0.75) end
	if light and type(light.SetBlendMode) == "function" then light:SetBlendMode("ADD") end

	local portrait = Texture(target, "OVERLAY", 5)
	if portrait then
		portrait:SetSize(58, 58)
		portrait:SetPoint("TOPRIGHT", target, "TOPRIGHT", -26, -19)
		if type(portrait.SetDesaturated) == "function" then portrait:SetDesaturated(true) end
		if type(portrait.SetVertexColor) == "function" then portrait:SetVertexColor(0.035, 0.04, 0.055, 1) end
		local point = { "TOPRIGHT", target, "TOPRIGHT", -26, -19 }
		local mask = MakeMask(target, portrait, 58, point)
		if not mask and type(portrait.SetMask) == "function" then
			pcall(portrait.SetMask, portrait, "Interface\\CharacterFrame\\TempPortraitAlphaMask")
		end
	end
	target:Hide()
	ui = { target = target, portrait = portrait, main = main, light = light }

	local message = CreateFrame("Frame", nil, container) -- gp:borders
	message.olympus = true
	message:SetSize(660, 92)
	message:SetPoint("CENTER", UIParent, "CENTER", 0, 145)
	if type(message.SetFrameStrata) == "function" then message:SetFrameStrata("DIALOG") end
	if type(message.EnableMouse) == "function" then message:EnableMouse(false) end
	local bg = Texture(message, "BACKGROUND", 0)
	if bg then bg:SetAllPoints(); if type(bg.SetColorTexture) == "function" then bg:SetColorTexture(0.015, 0.02, 0.03, 0.90) end end
	local top = Texture(message, "BORDER", 0)
	if top then top:SetColorTexture(0.52, 0.38, 0.21, 0.85); top:SetPoint("TOPLEFT", 8, -7); top:SetPoint("TOPRIGHT", -8, -7); top:SetHeight(1) end
	local bottom = Texture(message, "BORDER", 0)
	if bottom then bottom:SetColorTexture(0.20, 0.32, 0.40, 0.75); bottom:SetPoint("BOTTOMLEFT", 8, 7); bottom:SetPoint("BOTTOMRIGHT", -8, 7); bottom:SetHeight(1) end
	local text = message:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetPoint("TOPLEFT", message, "TOPLEFT", 22, -19)
	text:SetPoint("TOPRIGHT", message, "TOPRIGHT", -22, -19)
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	if type(text.SetTextColor) == "function" then text:SetTextColor(0.88, 0.82, 0.69, 1) end
	local clue = message:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	clue:SetPoint("BOTTOMLEFT", message, "BOTTOMLEFT", 18, 15)
	clue:SetPoint("BOTTOMRIGHT", message, "BOTTOMRIGHT", -18, 15)
	clue:SetJustifyH("CENTER")
	if type(clue.SetTextColor) == "function" then clue:SetTextColor(0.44, 0.58, 0.66, 1) end
	message:Hide()
	ui.message, ui.text, ui.clue = message, text, clue
	waitingUI = false
	return ui
end

local function Coordinates()
	local C = C_Map
	if type(C) ~= "table" or type(C.GetBestMapForUnit) ~= "function" or type(C.GetPlayerMapPosition) ~= "function" then return "" end
	local okMap, mapID = pcall(C.GetBestMapForUnit, "target")
	if not okMap or type(mapID) ~= "number" then return "" end
	local okPos, pos = pcall(C.GetPlayerMapPosition, mapID, "target")
	if not okPos or type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return "" end
	local okXY, x, y = pcall(pos.GetXY, pos)
	if not okXY or type(x) ~= "number" or type(y) ~= "number" or x <= 0 or y <= 0 or x > 1 or y > 1 then return "" end
	local name
	if type(C.GetMapInfo) == "function" then
		local okInfo, info = pcall(C.GetMapInfo, mapID)
		if okInfo and type(info) == "table" and type(info.name) == "string" then name = info.name end
	end
	local point = ("%.1f, %.1f"):format(x * 100, y * 100)
	return name and (name .. "  |  " .. point) or point
end

local function TargetName()
	if type(UnitExists) == "function" and not UnitExists("target") then return nil end
	if type(UnitIsPlayer) == "function" and not UnitIsPlayer("target") then return nil end
	if type(ns.UnitFullName) ~= "function" then return nil end
	local ok, name = pcall(ns.UnitFullName, "target")
	return ok and type(name) == "string" and name or nil
end

local function Show(lease)
	if not CanRender() then HideUI() return false end
	local view = EnsureUI()
	if not view then return false end
	if view.portrait and type(SetPortraitTexture) == "function" then
		pcall(SetPortraitTexture, view.portrait, "target", true)
	end
	if view.text then view.text:SetText(lease.caption) end
	if view.clue then view.clue:SetText(Coordinates()) end
	if view.target then view.target:Show() end
	if view.message then view.message:Show() end
	stats.shown = stats.shown + 1
	displayGeneration = displayGeneration + 1
	local generation = displayGeneration
	displayUntil = Mono() + Effects.DISPLAY_FOR
	if type(ns.After) == "function" then
		ns.After(Effects.DISPLAY_FOR, "profile effect", function()
			if generation ~= displayGeneration then return end
			displayUntil = 0
			HideUI()
		end)
	end
	return true
end

function Effects.Refresh()
	if not Member() or SelfOff() then ClearInbound() return false end
	local now = Mono()
	Prune(now)
	-- A member's own moderation boundary can change while the short lease is live.  The session
	-- issuer's authority and expiry are revalidated by Prune; the presenting member needs admission,
	-- not issuer rank of their own.
	for leaseKey, candidate in pairs(leases) do
		if Hidden(candidate.name, candidate.guild) or grants[candidate.grantKey] == nil then
			leases[leaseKey], leaseCount = nil, leaseCount - 1
		end
	end
	if not CanRender() then
		shownTarget, shownSession = nil, nil
		HideUI()
		return false
	end
	local target = TargetName()
	local key = target and Fold(target) or nil
	local lease = key and leases[key] or nil
	if lease and (now >= lease.expires or Hidden(lease.name, lease.guild) or grants[lease.grantKey] == nil) then
		leases[key], leaseCount, lease = nil, leaseCount - 1, nil
	end
	if not lease or screenshotHidden then
		HideUI()
		if not lease then shownTarget, shownSession = nil, nil end
		return false
	end
	if shownTarget == key and shownSession == lease.session then return true end
	shownTarget, shownSession = key, lease.session
	return Show(lease)
end

local function Parse(text)
	if Secret(text) or type(text) ~= "string" or #text > 255 then return nil end
	local version, kind, wire, remoteSession, remoteSequence, at, guild, tail =
		text:match("^FX~(%d+)~([GCSX])~([a-z])~(%d+)~(%d+)~(%d+)~([^~]+)~(.+)$")
	version = Integer(version, 1, 9)
	remoteSession = Integer(remoteSession, 1, 999999)
	remoteSequence = Integer(remoteSequence, 1, 999999)
	at = Integer(at, 1, 9999999999)
	local spec = BY_WIRE[wire]
	guild = Guild(guild)
	if version ~= Effects.VERSION or not spec or not remoteSession or not remoteSequence or not at or not guild then return nil end
	if kind == "G" or kind == "C" then
		local grantID = Integer(tail, 1, 999999)
		if not grantID then return nil end
		return { kind = kind, style = spec.name, session = remoteSession, sequence = remoteSequence,
			at = at, guild = guild, grantID = grantID }
	end
	local grantIssuer, grantID, caption = tail:match("^([^~]+)~(%d+)~?(.*)$")
	grantIssuer = Plain(grantIssuer, 80)
	grantID = Integer(grantID, 1, 999999)
	if not grantIssuer or not grantID then return nil end
	if kind == "S" then caption = Caption(spec.name, caption) else if caption ~= "" then return nil end caption = nil end
	if kind == "S" and not caption then return nil end
	return { kind = kind, style = spec.name, session = remoteSession, sequence = remoteSequence,
		at = at, guild = guild, grantIssuer = grantIssuer, grantID = grantID, caption = caption }
end

function Effects.Handle(dist, sender, text)
	if dist ~= "CHANNEL" then return Drop("scope") end
	if not Member() or SelfOff() then ClearInbound() return Drop("scope") end
	if Secret(sender) or type(sender) ~= "string" or sender == "" then return Drop("sender") end
	local word = Parse(text)
	if not word then return Drop("shape") end
	local now, clock = Mono(), Clock()
	if word.at < clock - 60 or word.at > clock + 15 then return Drop("time") end
	sender = ns.FullName and ns.FullName(sender) or sender
	local key = Fold(sender)
	if not key or Hidden(sender, word.guild) then return Drop("hidden") end
	if (word.kind == "G" or word.kind == "C") and not Authorized(sender) then return Drop("authority") end
	if not Admit(sender, word.guild, now, table.concat({ word.session, word.sequence, word.kind }, ":")) then return Drop("authority") end
	if word.kind == "G" or word.kind == "C" then
		if not NewerGrant(key, word.session, word.sequence, word.at, now) then return Drop("replay") end
		local previous = grantOrder[key]
		if previous and previous.session ~= word.session then RetireGrant(key, previous.session, now) end
		if not RememberGrant(key, { session = word.session, sequence = word.sequence, at = word.at,
			id = word.grantID, active = word.kind == "G" }, now) then return Drop("full") end
		local grantKey = GrantKey(sender, word.grantID)
		if word.kind == "C" then
			DropGrant(grantKey)
		else
			-- A newer open from one issuer replaces that issuer's previous epoch.  Another issuer's
			-- independent authenticated session may coexist within the small global bound.
			for heldKey, grant in pairs(grants) do
				if heldKey ~= grantKey and Fold(grant.issuer) == key then DropGrant(heldKey) end
			end
			if not PutGrant({ issuer = sender, guild = word.guild, style = word.style, id = word.grantID,
				key = grantKey, at = word.at, expires = now + Effects.SESSION_TTL }) then return Drop("full") end
		end
		Effects.Refresh()
		return true
	end
	local grant = FindGrant(word.grantIssuer, word.grantID, now)
	if not grant or grant.style ~= word.style then return Drop("session") end
	if not Newer(key, word.session, word.sequence, word.at, now) then return Drop("replay") end
	local previous = order[key]
	if previous and previous.session ~= word.session then Retire(key, previous.session, now) end
	if not Remember(key, { session = word.session, sequence = word.sequence, at = word.at,
		active = word.kind == "S" }, now) then return Drop("full") end
	if word.kind == "X" then
		if leases[key] then leases[key], leaseCount = nil, leaseCount - 1 end
		stats.stopped = stats.stopped + 1
	else
		if not leases[key] then
			if leaseCount >= Effects.MAX_SENDERS then
				local oldest = Prune(now)
				if oldest and leases[oldest] then leases[oldest], leaseCount = nil, leaseCount - 1 end
			end
			if leaseCount >= Effects.MAX_SENDERS then return Drop("full") end
			leaseCount = leaseCount + 1
		end
		leases[key] = { name = sender, guild = word.guild, style = word.style, caption = word.caption,
			session = word.session, sequence = word.sequence, at = word.at, expires = now + Effects.LEASE_TTL,
			grantKey = grant.key }
		stats.received = stats.received + 1
	end
	Effects.Refresh()
	return true
end

function Effects.Active(name)
	if not Member() or SelfOff() then ClearInbound() return nil end
	local key, now = Fold(name), Mono()
	Prune(now)
	local lease = key and leases[key] or nil
	if not lease or now >= lease.expires or Hidden(lease.name, lease.guild) or grants[lease.grantKey] == nil then return nil end
	return { name = lease.name, guild = lease.guild, style = lease.style, expiresIn = math.max(0, lease.expires - now) }
end

function Effects.Visible()
	local function Visible(frame)
		if not frame then return false end
		if type(frame.IsVisible) == "function" then return frame:IsVisible() == true end
		return type(frame.IsShown) == "function" and frame:IsShown() == true
	end
	return ui ~= nil and (Visible(ui.target) or Visible(ui.message)) or false
end

function Effects.Stats()
	local dropped = {}
	for key, value in pairs(stats.dropped) do dropped[key] = value end
	return { sent = stats.sent, received = stats.received, shown = stats.shown, stopped = stats.stopped,
		expired = stats.expired, active = leaseCount, sessions = grantCount,
		order = orderCount, sessionOrder = grantOrderCount, senders = bucketCount, dropped = dropped }
end

local function ScreenshotStart()
	if not Effects.Visible() then return end
	screenshotHidden = true
	HideUI()
end

local function ScreenshotEnd()
	if not screenshotHidden then return end
	screenshotHidden = false
	if Mono() >= displayUntil or not CanRender() then return end
	if type(ns.After) ~= "function" then return Effects.Refresh() end
	ns.After(0.05, "profile effect screenshot", function()
		if Mono() < displayUntil and CanRender() then
			local target, key = TargetName(), nil
			if target then key = Fold(target) end
			local lease = key and leases[key]
			if lease and shownTarget == key and shownSession == lease.session then
				local view = EnsureUI()
				if view then
					if view.target then view.target:Show() end
					if view.message then view.message:Show() end
				end
			end
		end
	end)
end

if ns.Comm and ns.Comm.Handle then ns.Comm.Handle("FX", function(...) return Effects.Handle(...) end) end
ns.RegisterEvent("PLAYER_TARGET_CHANGED", Effects.Refresh)
ns.RegisterEvent("PLAYER_GUILD_UPDATE", function(unit)
	if unit == nil or unit == "player" then
		Effects.Refresh()
	end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if waitingUI then EnsureUI(); Effects.Refresh() end
end)
ns.On("NETOFF_CHANGED", function()
	Effects.Refresh()
end)
ns.On("DATA_CHANGED", function()
	if outgoingSession and not AuthorizedSelf() then
		local key = outgoingSession.key
		outgoingSession = nil
		StopSessionTicker()
		DropGrant(key)
	end
	Effects.Refresh()
end)
-- Best effort only: some supported clients do not expose these events, the event can arrive after
-- pixels were captured, and an external camera is outside the client entirely.  This hides Olympus's
-- own frames when the client gives us a timely signal; it is not screenshot prevention.
pcall(ns.RegisterEvent, "SCREENSHOT_STARTED", ScreenshotStart)
pcall(ns.RegisterEvent, "SCREENSHOT_SUCCEEDED", ScreenshotEnd)
pcall(ns.RegisterEvent, "SCREENSHOT_FAILED", ScreenshotEnd)

-- Test hooks: state only, no production caller needs them.
Effects._ScreenshotStart = ScreenshotStart
Effects._ScreenshotEnd = ScreenshotEnd

-- A switch to the game's gamepad UI cancels the transient presentation and clears its cached
-- target.  Returning to mouse mode may show a still-live lease once, through the normal gate.
ns.Gate.Hooks("borders", {
	key = "profile-effects",
	park = function()
		displayGeneration = displayGeneration + 1
		displayUntil = 0
		screenshotHidden = false
		shownTarget, shownSession = nil, nil
		HideUI()
	end,
	install = Effects.Refresh,
})

local _, ns = ...

-- Portable declarations, never authoritative ledger imports. Original records are signed
-- only at their actor-owned event; a later witness has a different kind and signing time.
-- A forwarded self-signed public key is not a certificate. Only a directly authenticated
-- original sender or an independently enrolled key can authenticate the signature.
local H = {}
ns.CarryHistory = H
H.RECORDS, H.KEYS, H.FIELDS, H.TEXT = 256, 64, 16, 4096
H.JOBS, H.SKEW = 4, 60
local jobs = 0
local requested = {}
-- Moderator identities never enter a subject-readable capsule. M stays unavailable until a
-- separate protected staff-to-staff route exists; hiding its UI would not hide the payload.
local KINDS = { L = true, C = true, P = true, D = true, W = true }
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Whole(n) return type(n) == "number" and n == n and n >= 0 and n <= 4294967295 and n % 1 == 0 end
local function Name(s)
	if type(s) ~= "string" or s == "" or #s > 72 or s:find("[|~^%c]") then return nil end
	local full = ns.FullName(ns.Normal(s))
	return type(full) == "string" and #full <= 72 and ns.RealmOf(full) and full or nil
end
local function Same(a, b) return Name(a) and Name(b) and ns.Fold(Name(a)) == ns.Fold(Name(b)) end
local function Guild(s) return type(s) == "string" and #s <= 72 and s ~= "" and not s:find("[|~^%c]") and ns.IsFederation(s) end
local function Scope() return tostring(ns.faction) .. ":" .. tostring(ns.group or ns.GroupOf(ns.realm)) end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Preview() return ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing() or ns.King and ns.King.Preview and ns.King.Preview() end
local function Fresh()
	return ns.IsMember() and ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh() ~= nil
end
local function Member(name) return Fresh() and ns.Roster.RankOf(name) ~= nil end
local function OwnRole(kind, subject, guild)
	if Preview() or not Fresh() or not Member(ns.me) or not Guild(guild) then return false end
	if ns.Moderation and ns.Moderation.SelfOff and ns.Moderation.SelfOff() then return false end
	if kind == "C" or kind == "P" then return ns.King and ns.King.IsKing and ns.King.IsKing() == true end
	if kind == "D" then return ns.IsTreasurer and ns.IsTreasurer(ns.me, GetGuildInfo("player")) == true end
	if guild ~= GetGuildInfo("player") then return false end
	local rank = ns.Roster.RankOf(ns.me)
	return type(rank) == "number" and (kind == "W" and rank == 0 or kind == "L" and rank <= ns.CAPTAIN_RANK)
end
local function Store()
	if type(ns.db) ~= "table" or not Name(ns.me) then return nil end
	local root = ns.db.carryHistory
	if root == nil then root = { version = 1, scopes = {} }; ns.db.carryHistory = root end
	if type(root) ~= "table" or root.version ~= 1 or type(root.scopes) ~= "table" then return nil end
	local scope = Scope()
	if root.scopes[scope] == nil then
		if Count(root.scopes) >= 8 then return nil end
		root.scopes[scope] = { characters = {} }
	end
	local bucket = root.scopes[scope]
	if type(bucket) ~= "table" or type(bucket.characters) ~= "table" then return nil end
	local key = ns.Fold(ns.me)
	if bucket.characters[key] == nil then
		if Count(bucket.characters) >= 32 then return nil end
		bucket.characters[key] = { seq = 0, originals = {}, archive = {}, keys = {} }
	end
	local s = bucket.characters[key]
	if type(s) ~= "table" or not Whole(s.seq) or type(s.originals) ~= "table" or type(s.archive) ~= "table" or type(s.keys) ~= "table" then return nil end
	for _, field in ipairs({ "imports", "floors", "completed" }) do
		if s[field] == nil then s[field] = {} end
		if type(s[field]) ~= "table" then return nil end
	end
	return s
end
local function Escape(s) return tostring(s):gsub("[^%w %.%-%_]", function(c) return ("%%%02X"):format(c:byte()) end) end
local function Unescape(s)
	if type(s) ~= "string" or s:find("%%[^%x]") or s:find("%%[%x][^%x]") or s:match("%%[%x]?$") then return nil end
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local function Fields(s) local out = {}; for f in (s .. "~"):gmatch("(.-)~") do out[#out + 1] = f end; return out end
local function Digest(s) return ns.Ed25519.ToHex(ns.Sign.SHA256(s)) end
function H.Payload(fields)
	if type(fields) ~= "table" then return nil end
	local keys, out = {}, {}
	for key, value in pairs(fields) do
		if type(key) ~= "string" or not key:match("^[a-z][a-zA-Z]*$") or #key > 24 or type(value) ~= "string" and type(value) ~= "number" then return nil end
		value = tostring(value)
		if #value > 320 or value:find("[|%c]") then return nil end
		keys[#keys + 1] = key
	end
	if #keys > H.FIELDS then return nil end
	table.sort(keys)
	for _, key in ipairs(keys) do out[#out + 1] = Escape(key) .. "=" .. Escape(fields[key]) end
	local text = table.concat(out, ";")
	return #text <= 1800 and text or nil
end
local function PayloadFields(text)
	local out, n = {}, 0
	if text ~= "" then
		for entry in (text .. ";"):gmatch("(.-);") do
			local key, value = entry:match("^([^=]+)=(.*)$")
			key, value = Unescape(key), Unescape(value)
			if not key or not value or out[key] ~= nil then return nil end
			out[key], n = value, n + 1
		end
	end
	if n > H.FIELDS or H.Payload(out) ~= text then return nil end
	return out
end
function H.Text(r)
	if type(r) ~= "table" or not KINDS[r.kind] or not Name(r.issuer) or not Name(r.subject) or not Guild(r.guild)
		or type(r.guid) ~= "string" or #r.guid < 1 or #r.guid > 64 or r.guid:find("[^%w%-]")
		or r.scope ~= Scope() or type(r.id) ~= "string" or #r.id < 1 or #r.id > 160 or r.id:find("[|%c]")
		or not Whole(r.at) or not Whole(r.signedAt) or r.at > r.signedAt + H.SKEW or not Whole(r.seq) or r.seq < 1
		or type(r.payload) ~= "string" or not PayloadFields(r.payload) then return nil end
	local f = { "OLYHC1", r.scope, r.kind, r.issuer, r.subject, r.guild, r.id, r.at, r.signedAt, r.seq, r.payload, r.guid }
	for i = 1, #f do f[i] = Escape(f[i]) end
	local text = table.concat(f, "~")
	return #text <= H.TEXT and text or nil
end
function H.Parse(text)
	if type(text) ~= "string" or #text > H.TEXT then return nil end
	local f = Fields(text); if #f ~= 12 then return nil end
	for i = 1, #f do f[i] = Unescape(f[i]); if f[i] == nil then return nil end end
	if f[1] ~= "OLYHC1" then return nil end
	local r = { scope = f[2], kind = f[3], issuer = f[4], subject = f[5], guild = f[6], id = f[7], at = tonumber(f[8]),
		signedAt = tonumber(f[9]), seq = tonumber(f[10]), payload = f[11], guid = f[12] }
	if H.Text(r) ~= text then return nil end
	r.fields = PayloadFields(r.payload)
	return r
end
local function Copy(r) local out = {}; for k, v in pairs(r) do if type(v) ~= "table" then out[k] = v end end; return out end
local function Run(fn, done)
	local Ed = ns.Ed25519
	if not Ed or not Ed.Run or jobs >= H.JOBS then return false end
	jobs = jobs + 1
	local queued = Ed.Run(fn, function(ok, result)
		jobs = jobs - 1
		if done then done(ok and result or nil, ok and nil or "crypto") end
	end)
	if not queued then jobs = jobs - 1 end
	return queued == true
end
local function Capture(kind, subject, id, at, guild, fields, done)
	if not KINDS[kind] or not Name(subject) or not OwnRole(kind, subject, guild) then return false, "authority" end
	local s, payload = Store(), H.Payload(fields)
	if not s or not payload or Count(s.originals) >= H.RECORDS then return false, "retention-or-fields" end
	-- An original declaration is captured at issuance, not manufactured from an old saved quote.
	if not Whole(at) or math.abs(Clock() - at) > H.SKEW then return false, "not-original-event" end
	if kind == "P" and (not ns.Acts or not Whole(ns.Acts.PARDON_DAYS) or not fields or tonumber(fields.expires) ~= at + ns.Acts.PARDON_DAYS * 86400) then return false, "pardon-deadline" end
	local guid = UnitGUID and UnitGUID("player")
	if type(guid) ~= "string" or issecretvalue and issecretvalue(guid) then return false, "native-identity" end
	local record = { scope = Scope(), kind = kind, issuer = Name(ns.me), subject = Name(subject), guild = guild, guid = guid,
		id = id, at = at, signedAt = Clock(), seq = s.seq + 1, payload = payload }
	local text = H.Text(record)
	if not text then return false, "shape" end
	local key = kind .. ":" .. guild .. ":" .. id
	if s.originals[key] then return false, "already-captured" end
	local D = ns.Debts
	if not D or D.missing or not D.Sign or not D.MyKey then return false, "signing-unavailable" end
	s.seq = record.seq -- reserved across async jobs and reload; gaps grant nothing
	s.originals[key] = { pending = true, id = id }
	local actor, scope = ns.me, Scope()
	local queued = Run(function()
		local _, pk = D.MyKey()
		if type(pk) ~= "string" or #pk ~= 32 then return nil end
		local sig = D.Sign(text)
		if type(sig) ~= "string" or #sig ~= 64 then return nil end
		return { text = text, pk = ns.Ed25519.ToB64(pk), sig = ns.Ed25519.ToB64(sig) }
	end, function(capsule, why)
		if s.originals[key] and s.originals[key].pending then
			if capsule and Same(actor, ns.me) and scope == Scope() then s.originals[key] = capsule
			else s.originals[key] = nil end -- failed reservation was never a historical record
		end
		if done then done(capsule and Copy(capsule) or nil, why) end
	end)
	if not queued then s.originals[key] = nil; return false, "crypto-busy" end
	return true
end
function H.CaptureOriginal(kind, subject, id, at, guild, fields, done)
	if kind == "W" then return false, "not-an-original" end
	return Capture(kind, subject, id, at, guild, fields, done)
end
function H.CaptureWitness(subject, guild, fields, done)
	if type(fields) ~= "table" or not ({ L = true, C = true, P = true, D = true })[fields.sourceKind] then return false, "private-or-unknown-kind" end
	local observed = {}
	for key, value in pairs(fields) do observed[key] = value end
	observed.scope = "retained-copy-observed-now"
	local payload = H.Payload(observed)
	if not payload then return false, "shape" end
	return Capture("W", subject, "witness:" .. Digest(payload), Clock(), guild, observed, done)
end
function H.Originals(subject)
	local out, s = {}, Store()
	for _, capsule in pairs(s and s.originals or {}) do
		local r = capsule.text and H.Parse(capsule.text)
		if r and Same(r.issuer, ns.me) and Same(r.subject, subject) then out[#out + 1] = Copy(capsule) end
	end
	table.sort(out, function(a, b) return H.Parse(a.text).seq < H.Parse(b.text).seq end)
	return out
end
local function IssuerRole(r)
	if r.kind == "C" or r.kind == "P" then return ns.IsKingCharacter and ns.IsKingCharacter(r.issuer) == true end
	if r.kind == "D" then return ns.IsTreasurerCharacter and ns.IsTreasurerCharacter(r.issuer) == true end
	local rank, source
	-- Preserve multiple returns; a census rank is never source authority.
	if ns.Data and ns.Data.AuthorizedRank then rank, source = ns.Data.AuthorizedRank(r.issuer, r.guild) end
	if r.guild == GetGuildInfo("player") then
		if not Fresh() or source ~= "roster" then return false end
	elseif source ~= "signed" and source ~= "pinned" then return false end
	return type(rank) == "number" and (r.kind == "W" and rank == 0 or r.kind == "L" and rank <= ns.CAPTAIN_RANK)
end
local function Capsule(c)
	if type(c) ~= "table" or type(c.pk) ~= "string" or #c.pk ~= 43 or type(c.sig) ~= "string" or #c.sig ~= 86 then return nil end
	local r = H.Parse(c.text)
	local Ed = ns.Ed25519
	local pk, sig = Ed and Ed.FromB64(c.pk), Ed and Ed.FromB64(c.sig)
	if not r or not pk or #pk ~= 32 or not sig or #sig ~= 64 or r.signedAt > Clock() + H.SKEW then return nil end
	return r, pk, sig
end
function H.Verify(capsule, done)
	capsule = type(capsule) == "table" and Copy(capsule) or capsule
	local r, pk, sig = Capsule(capsule)
	local s = Store()
	if not r or not s then return false, "shape" end
	local pin = s.keys[ns.Fold(r.issuer)]
	if type(pin) ~= "table" or pin.pk ~= capsule.pk or pin.guid ~= r.guid then return false, "original-key-unverified" end
	local actor, scope = ns.me, Scope()
	return Run(function() return ns.Ed25519.Verify(pk, capsule.text, sig) == true end,
		function(ok, why)
			ok = ok and Same(actor, ns.me) and scope == Scope() and s.keys[ns.Fold(r.issuer)] == pin
			if done then done(ok and Copy(r) or nil, why or (not ok and "signature-or-session" or nil)) end
		end)
end
-- An explicit local collection request, never an unsolicited key enrolment. Transport binds
-- its nonce separately; this reader also confines material to the actual consenting subject.
function H.OpenRequest(issuer)
	issuer = Name(issuer)
	if not issuer or Same(issuer, ns.me) or Preview() or not Fresh() or not Member(ns.me) then return false end
	if not requested[ns.Fold(issuer)] and Count(requested) >= 8 then return false end
	requested[ns.Fold(issuer)] = { issuer = issuer, subject = ns.me, guild = GetGuildInfo("player"), scope = Scope(), at = Clock() }
	return true
end
function H.ReceiveOriginal(sender, capsule, done)
	capsule = type(capsule) == "table" and Copy(capsule) or capsule
	sender = Name(sender)
	local r, pk, sig = Capsule(capsule)
	local s = Store()
	local request = sender and requested[ns.Fold(sender)]
	if not s or not r or not request or not Same(sender, r.issuer) or not Same(r.subject, ns.me)
		or request.subject ~= ns.me or request.scope ~= Scope() or request.guild ~= GetGuildInfo("player")
		or Clock() - request.at < 0 or Clock() - request.at > 300 or Preview() or not Fresh() or not Member(ns.me)
		or r.kind == "L" or r.kind == "W" then return false, "consent-or-private-material" end
	if not IssuerRole(r) then return false, "issuer-authority" end
	local pinKey, old = ns.Fold(sender), s.keys[ns.Fold(sender)]
	if old and (old.pk ~= capsule.pk or old.guid ~= r.guid) then return false, "key-conflict" end
	local D = ns.Debts
	if not D or not D.Bind or not D.Bind(sender, r.guid) then return false, "native-identity-unverified" end
	local key = Digest(capsule.text)
	local prior = s.archive[key]
	if prior then return false, prior.pk == capsule.pk and prior.sig == capsule.sig and "already-retained" or "conflict" end
	if Count(s.archive) >= H.RECORDS or not old and Count(s.keys) >= H.KEYS then return false, "retention" end
	local actor, scope = ns.me, Scope()
	return Run(function() return ns.Ed25519.Verify(pk, capsule.text, sig) == true end, function(ok, why)
		-- Nothing is granted by the crypto callback if consent, actor, guild or authority changed.
		if not ok or not Same(actor, ns.me) or scope ~= Scope() or requested[pinKey] ~= request
			or request.guild ~= GetGuildInfo("player") or Clock() - request.at > 300 or Preview() or not Fresh()
			or not Member(ns.me) or not IssuerRole(r) or not D.Bind(sender, r.guid) then
			if done then done(nil, why or "revoked-or-signature") end
			return
		end
		local current = s.keys[pinKey]
		if current and (current.pk ~= capsule.pk or current.guid ~= r.guid) or Count(s.archive) >= H.RECORDS
			or not current and Count(s.keys) >= H.KEYS then
			if done then done(nil, "conflict-or-retention") end
			return
		end
		s.keys[pinKey] = { pk = capsule.pk, guid = r.guid, enrolledAt = Clock(), direct = true }
		local kept = Copy(capsule)
		kept.receivedAt, kept.directIssuer = Clock(), sender
		s.archive[key] = kept
		if done then done(Copy(r)) end
		ns.Fire("HISTORY_CARRY_CHANGED")
	end)
end
function H.CancelRequest(issuer)
	issuer = Name(issuer)
	if not issuer then return false end
	requested[ns.Fold(issuer)] = nil
	return true
end
function H.Archive()
	local out, s = {}, Store()
	for _, capsule in pairs(s and s.archive or {}) do
		local r = H.Parse(capsule.text)
		if r and Same(r.subject, ns.me) then out[#out + 1] = Copy(capsule) end
	end
	table.sort(out, function(a, b) return a.text < b.text end)
	return out
end

-- XC version 2 shares Carry's one registration. A page is ONE immutable declaration,
-- no more than 34 small packets; the next page waits for its exact cursor/digest ACK.
-- Unknown ORIGINAL keys stay unknown after forwarding. A direct, solicited key response
-- can verify their signatures later; neither that verification nor a transfer imports powers.
H.PART, H.PARTS, H.LIFE, H.STREAMS, H.IMPORTS = 160, 34, 300, 8, 32
H.TOTAL = 3600
H.ACK_WAIT = 90
H.SENDER_OFFERS, H.SENDER_FLOORS = 2, 32
local streams, inboxes, offers, staffGrants = {}, {}, {}, {}
local function Key(sender, id) return ns.Fold(Name(sender)) .. ":" .. id end
local function Live(actor, scope, guild)
	return Same(actor, ns.me) and scope == Scope() and guild == GetGuildInfo("player") and not Preview()
		and Fresh() and Member(ns.me) and not (ns.Moderation and ns.Moderation.SelfOff and ns.Moderation.SelfOff())
end
local function Master(name, guild)
	if not Name(name) or not Guild(guild) or Preview() then return false end
	if ns.WatchChat and ns.WatchChat.Barred and ns.WatchChat.Barred("powers", name) then return false end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(name, guild) then return false end
	local rank, source
	if ns.Data and ns.Data.AuthorizedRank then rank, source = ns.Data.AuthorizedRank(name, guild) end
	if guild == GetGuildInfo("player") then return Fresh() and rank == 0 and source == "roster" end
	return rank == 0 and (source == "signed" or source == "pinned")
end
local function Destination(name)
	name = Name(name); if not name then return nil end
	local mine = GetGuildInfo("player")
	if Master(name, mine) then return mine end
	local guild, rank, source
	if ns.Authority and ns.Authority.Role then guild, rank, source = ns.Authority.Role(name) end
	if rank == 0 and source == "signed" and Master(name, guild) then return guild end
	local main = ns.KingGuildName and ns.KingGuildName()
	if ns.IsKingCharacter and ns.IsKingCharacter(name) and Master(name, main) then return main end
end
local function Current(t)
	return t and Live(t.actor, t.scope, t.localGuild) and Clock() - t.at >= 0 and Clock() - t.at <= H.LIFE
		and Clock() - (t.born or t.at) <= H.TOTAL and not t.revoked
end
local function Touch(t) t.born = t.born or t.at; t.at = Clock() end
local function Prune()
	local s = Store(); if not s then return end
	for key, t in pairs(streams) do if not Current(t) then streams[key] = nil end end
	for key, b in pairs(inboxes) do if not Current(b) or s.floors[key] then inboxes[key] = nil end end
	for key, o in pairs(offers) do if not Current(o) or s.floors[key] then
		-- An expired accepted nonce cannot be resurrected by a late packet after reuse.
		s.floors[key] = s.floors[key] or "expired"; offers[key], inboxes[key] = nil, nil
	end end
	for key, t in pairs(staffGrants) do if not Current(t) then staffGrants[key] = nil end end
	for key, r in pairs(requested) do
		if r.actor and not Current(r) or not r.actor and (Clock() - r.at < 0 or Clock() - r.at > H.LIFE) then requested[key] = nil end
	end
end
local function SenderCapacity(sender, reserve)
	local s = Store(); if not s then return false end
	local prefix, active, floors = ns.Fold(Name(sender)) .. ":", 0, 0
	for key in pairs(offers) do if key:sub(1, #prefix) == prefix then active = active + 1 end end
	for key in pairs(s.floors) do if key:sub(1, #prefix) == prefix then floors = floors + 1 end end
	return active < H.SENDER_OFFERS and floors + active + (reserve or 1) <= H.SENDER_FLOORS
end
local function Nonce()
	local s = Store(); if not s then return nil end
	s.seq = s.seq + 1
	return Digest(ns.me .. "|" .. Scope() .. "|" .. Clock() .. "|" .. s.seq):sub(1, 16)
end
local function Send(to, message, guard, done)
	if #message > 255 or not ns.Comm or not ns.Comm.Whisper then return false end
	return ns.Comm.Whisper(to, message, nil, nil, nil, done, { owner = H, guard = guard }) == true
end
local function Pack(c)
	if not Capsule(c) then return nil end
	-- Text already escapes every field; escaping it again could make a valid declaration
	-- larger than a bounded page. The caret never occurs literally in canonical Text.
	local text = c.text .. "^" .. c.pk .. "^" .. c.sig
	return #text <= H.PART * H.PARTS and text or nil
end
local function Unpack(text)
	local original, pk, sig = text:match("^(.*)%^([^%^]+)%^([^%^]+)$")
	if not original then return nil end
	local c = { text = original, pk = pk, sig = sig }
	return Capsule(c) and c or nil
end
local function Manifest(list)
	local text = {}
	for i, c in ipairs(list) do
		local packed = Pack(c); if not packed then return nil end
		text[i] = Digest(packed):sub(1, 16)
	end
	return #list <= H.RECORDS and Digest(#list == 0 and "OLYHC EMPTY CONSENT" or table.concat(text, ":")):sub(1, 16) or nil
end
local function SendPage(t)
	if not Current(t) or streams[Key(t.to, t.id)] ~= t or not t.guard() then return false end
	local c = t.list[t.cursor]
	if not c then
		t.tries = (t.tries or 0) + 1
		if t.tries > 3 then streams[Key(t.to, t.id)] = nil; return false end
		return Send(t.to, ("XC~2~Z~%s~%d~%s"):format(t.id, #t.list, t.manifest), t.guard, function()
			if ns.After then ns.After(H.ACK_WAIT, "carry final acknowledgement", function()
				if streams[Key(t.to, t.id)] == t and Current(t) and t.guard() then SendPage(t) end
			end) end
		end)
	end
	local body = Pack(c); if not body then return false end
	local parts, digest = math.ceil(#body / H.PART), Digest(body):sub(1, 16)
	if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < parts then return false end
	t.digest, t.tries = digest, (t.tries or 0) + 1
	if t.tries > 3 then
		streams[Key(t.to, t.id)] = nil
		local s = Store(); if s then s.lastError = "acknowledgement-timeout" end
		ns.Fire("HISTORY_CARRY_CHANGED"); return false
	end
	for i = 1, parts do
		local msg = ("XC~2~D~%s~%d~%d~%d~%s~%s"):format(t.id, t.cursor, i, parts, digest, body:sub((i - 1) * H.PART + 1, i * H.PART))
		local cursor = t.cursor
		local guard = function() return t.cursor == cursor and t.guard() end
		local done
		if i == parts then done = function()
			if ns.After then ns.After(H.ACK_WAIT, "carry page acknowledgement", function()
				if streams[Key(t.to, t.id)] == t and t.cursor == cursor and Current(t) and t.guard() then SendPage(t) end
			end) end
		end end
		if not Send(t.to, msg, guard, done) then return false end
	end
	return true
end
local function StartStream(to, id, list, mode, guard)
	local key, manifest = Key(to, id), Manifest(list)
	if not manifest or streams[key] or Count(streams) >= H.STREAMS then return false end
	local peerStreams = 0
	for _, stream in pairs(streams) do if Same(stream.to, to) then peerStreams = peerStreams + 1 end end
	if peerStreams >= H.SENDER_OFFERS then return false end
	local t = { actor = ns.me, scope = Scope(), localGuild = GetGuildInfo("player"), at = Clock(), id = id,
		to = to, list = list, manifest = manifest, cursor = 1, mode = mode }
	t.guard = function() return streams[key] == t and Current(t) and guard() end
	streams[key] = t
	if not Send(to, ("XC~2~B~%s~%s~%d~%s"):format(id, mode, #list, manifest), t.guard) or not SendPage(t) then
		streams[key] = nil; return false
	end
	return true
end
local function Request(issuer, mode)
	Prune()
	issuer = Name(issuer)
	if not H.OpenRequest(issuer) then return false, "identity-or-consent" end
	local request = requested[ns.Fold(issuer)]
	request.actor, request.localGuild, request.mode, request.id = ns.me, request.guild, mode, Nonce()
	if not request.id then return false, "retention" end
	return Send(issuer, "XC~2~Q~" .. request.id .. "~" .. mode,
		function() return requested[ns.Fold(issuer)] == request and Current(request) end)
end
function H.Collect(issuer) return Request(issuer, "C") end
function H.RequestKey(issuer) return Request(issuer, "K") end
local function KeyText(issuer, id, guid, pk)
	return table.concat({ "OLYHK1", Escape(Scope()), Escape(issuer), id, guid, pk }, "~")
end
local function SendKey(to, id, guard)
	local D, Ed = ns.Debts, ns.Ed25519
	local guid = UnitGUID and UnitGUID("player")
	if not D or D.missing or not D.MyKey or not D.Sign or type(guid) ~= "string" or issecretvalue and issecretvalue(guid) then return false end
	return Run(function()
		local _, pk = D.MyKey(); if type(pk) ~= "string" or #pk ~= 32 then return nil end
		local b64 = Ed.ToB64(pk)
		return { pk = b64, sig = Ed.ToB64(D.Sign(KeyText(ns.me, id, guid, b64))) }
	end, function(key)
		if key and guard() then Send(to, table.concat({ "XC", 2, "K", id, guid, key.pk, key.sig }, "~"), guard) end
	end)
end
local function RefreshPending()
	local s = Store(); if not s then return end
	local pending = {}
	for _, entry in pairs(s.imports) do
		if not entry.revoked and entry.scope == Scope() and Same(entry.recipient, ns.me) and Master(ns.me, entry.guild) and Member(entry.subject) then
			for _, c in ipairs(entry.capsules) do
				if c.status == "pending-key" then pending[#pending + 1] = { entry = entry, capsule = c } end
				end
		end
	end
	local i = 0
	local function Next()
		i = i + 1
		local row = pending[i]; if not row then return end
		local entry, c = row.entry, row.capsule
		local queued = H.Verify(c, function(r)
			if not entry.revoked and Master(ns.me, entry.guild) and Member(entry.subject) then
				c.status = r and "signature-verified" or "signature-invalid"; ns.Fire("HISTORY_CARRY_CHANGED")
			end
			Next()
		end)
		if not queued then Next() end
	end
	Next()
end
local function ReceiveKey(sender, f)
	local req, s = requested[ns.Fold(sender)], Store()
	local guid, pk, sig = f[5], ns.Ed25519.FromB64(f[6] or ""), ns.Ed25519.FromB64(f[7] or "")
	if #f ~= 7 or not req or req.id ~= f[4] or not Current(req) or not s or not pk or #pk ~= 32 or not sig or #sig ~= 64
		or type(guid) ~= "string" or #guid > 64 or guid:find("[^%w%-]") or not ns.Debts.Bind(sender, guid) then return false end
	local pinKey, old = ns.Fold(sender), s.keys[ns.Fold(sender)]
	if old and (old.pk ~= f[6] or old.guid ~= guid) or not old and Count(s.keys) >= H.KEYS then return false end
	local text = KeyText(sender, req.id, guid, f[6])
	return Run(function() return ns.Ed25519.Verify(pk, text, sig) == true end, function(ok)
		if not ok or requested[pinKey] ~= req or not Current(req) or not ns.Debts.Bind(sender, guid) then return end
		local current = s.keys[pinKey]
		if current and (current.pk ~= f[6] or current.guid ~= guid) or not current and Count(s.keys) >= H.KEYS then return end
		s.keys[pinKey] = { pk = f[6], guid = guid, enrolledAt = Clock(), direct = true }
		RefreshPending(); ns.Fire("HISTORY_CARRY_CHANGED")
		if req.mode == "K" then requested[pinKey] = nil end
	end)
end
local function Draft(d)
	return d and d.version == 2 and Same(d.subject, ns.me) and d.scope == Scope() and Guild(d.sourceGuild) and Guild(d.guild)
		and type(d.capsules) == "table" and Manifest(d.capsules) == d.digest and not d.revoked
end
local function Ready(d)
	return Draft(d) and Fresh() and Member(ns.me) and GetGuildInfo("player") == d.guild and Master(d.to, d.guild) and not Preview()
end
function H.HasDraft() local s = Store(); return s and Draft(s.draft) or false end
function H.Prepare(to)
	local source, guild = GetGuildInfo("player"), Destination(to)
	if not Fresh() or not Member(ns.me) or Preview() or not guild or source == guild then return false, "destination" end
	local list = H.Archive(); local digest = Manifest(list)
	if not digest then return false, "empty-or-size" end
	local d = { version = 2, subject = ns.me, scope = Scope(), sourceGuild = source, guild = guild, to = Name(to), capsules = list, digest = digest }
	if not ns.Dialog or ns.Dialog.missing then return false, "dialog" end
	ns.Dialog.Show("OLYMPUS_CARRY_PREPARE", ns.L.CARRY_CONFIRM:format(#list, source, ns.DisplayName(d.to), guild), nil, d)
	return true
end
function H.Confirm(d)
	local s = Store()
	if not s or not Draft(d) or not Fresh() or not Member(ns.me) or GetGuildInfo("player") ~= d.sourceGuild
		or Destination(d.to) ~= d.guild or Preview() or s.draft and not s.draft.revoked then return false end
	d.id, d.at = Nonce(), Clock(); s.draft = d; ns.Fire("HISTORY_CARRY_CHANGED"); return true
end
function H.Offer()
	Prune()
	local s = Store(); local d = s and s.draft
	if not Ready(d) then return false, "join-destination-first" end
	if d.completed then return false, "already-received" end
	d.offeredAt = Clock()
	return Send(d.to, table.concat({ "XC", 2, "O", d.id, Escape(d.sourceGuild), Escape(d.guild), Escape(d.scope), #d.capsules, d.digest }, "~"),
		function() return s.draft == d and Ready(d) end)
end
local function OfferCurrent(o)
	return Current(o) and GetGuildInfo("player") == o.guild and Master(ns.me, o.guild) and Member(o.subject)
end
function H.HasOffer(key) return offers[key] ~= nil end
function H.Accept(key, confirmed)
	Prune()
	local o = offers[key]; if not OfferCurrent(o) then return false end
	if not confirmed then
		if not ns.Dialog or ns.Dialog.missing then return false end
		ns.Dialog.Show("OLYMPUS_CARRY_ACCEPT", ns.L.CARRY_ACCEPT:format(o.count, ns.DisplayName(o.subject), o.sourceGuild), nil, { version = 2, key = key, offer = o })
		return true
	end
	if type(confirmed) ~= "table" or confirmed.offer ~= o or confirmed.key ~= key then return false end
	o.accepted = true
	return Send(o.sender or o.subject, "XC~2~A~" .. o.id .. "~" .. o.digest, function() return offers[key] == o and OfferCurrent(o) and o.accepted end)
end
-- The member sends consent tokens only, never Loot text or moderator identities. The
-- source GM explicitly authorizes their own retained book; the destination GM then accepts.
function H.StaffConsent(sourceMaster)
	local s = Store(); local d = s and s.draft
	sourceMaster = Name(sourceMaster)
	if not Ready(d) or not sourceMaster or not Master(sourceMaster, d.sourceGuild) then return false, "source-guild-master" end
	local guard = function() return s.draft == d and Ready(d) and Master(sourceMaster, d.sourceGuild) end
	local grant = table.concat({ "XC", 2, "G", d.id, Escape(sourceMaster), Escape(d.sourceGuild), d.digest }, "~")
	local request = table.concat({ "XC", 2, "S", d.id, Escape(d.to), Escape(d.guild), Escape(d.sourceGuild), d.digest }, "~")
	if #grant > 255 or #request > 255 then return false, "packet-size" end
	d.staff = sourceMaster
	return Send(d.to, grant, guard) and Send(sourceMaster, request, guard)
end
local function StaffOutCurrent(t)
	return Current(t) and t.outgoing and Master(ns.me, t.sourceGuild) and Master(t.to, t.guild)
end
function H.StaffAccept(key, confirmed)
	local t = staffGrants[key]
	if not StaffOutCurrent(t) then return false end
	if not confirmed then
		if not ns.Dialog or ns.Dialog.missing or not ns.L.CARRY_HISTORY_STAFF then return false end
		ns.Dialog.Show("OLYMPUS_CARRY_STAFF", ns.L.CARRY_HISTORY_STAFF:format(ns.DisplayName(t.subject), ns.DisplayName(t.to)), nil, { key = key, grant = t })
		return true
	end
	if type(confirmed) ~= "table" or confirmed.key ~= key or confirmed.grant ~= t then return false end
	t.accepted = true
	local list, seen, witnesses = {}, {}, {}
	for _, c in ipairs(H.Originals(t.subject)) do local r = H.Parse(c.text)
		if r.guild == t.sourceGuild and (r.kind == "L" or r.kind == "W" and r.fields.sourceKind == "L") then
			list[#list + 1] = c; seen[r.kind == "W" and r.fields.originalId or r.id] = true
		end
	end
	-- Earlier unsigned notes remain a GM's new witness declaration, never the old writer's
	-- signature or historical authority. Its observed time differs from the original quote.
	for _, entry in ipairs(ns.Loot and ns.Loot.Notes and ns.Loot.Notes() or {}) do
		local n = entry.n
		if type(n) == "table" and Same(n.to, t.subject) and not seen[entry.key] then
			witnesses[#witnesses + 1] = { sourceKind = "L", originalWriter = n.writer or "?", originalAt = n.t or 0,
				originalId = entry.key, originalGuild = t.sourceGuild, words = n.text or "", via = n.via or "" }
		end
	end
	if #list + #witnesses > H.RECORDS then t.accepted = nil; return false end
	local i = 0
	local function Next()
		if staffGrants[key] ~= t or not StaffOutCurrent(t) or not t.accepted then return end
		i = i + 1
		local fields = witnesses[i]
		if fields then
			local queued = H.CaptureWitness(t.subject, t.sourceGuild, fields, function(c)
				if c then list[#list + 1] = c; Next() else t.failed = "witness-signing" end
			end)
			if not queued then t.failed = "witness-signing" end
			return
		end
		local manifest = Manifest(list)
		if not manifest then t.failed = "empty-or-size"; return end
		t.list, t.manifest = list, manifest
		Send(t.to, table.concat({ "XC", 2, "V", t.id, Escape(t.subject), Escape(t.sourceGuild), #list, manifest }, "~"),
			function() return staffGrants[key] == t and StaffOutCurrent(t) and t.accepted end)
		ns.Fire("HISTORY_CARRY_CHANGED")
	end
	Next(); return true
end
function H.Revoke()
	local s = Store(); local d = s and s.draft
	if not Draft(d) then return false end
	d.revoked = true
	if ns.Comm.CancelOwner then ns.Comm.CancelOwner(H) end
	Send(d.to, "XC~2~R~" .. d.id .. "~" .. d.digest, function() return Same(d.subject, ns.me) and d.scope == Scope() end)
	if d.staff then Send(d.staff, "XC~2~R~" .. d.id .. "~" .. d.digest, function() return Same(d.subject, ns.me) and d.scope == Scope() end) end
	ns.Fire("HISTORY_CARRY_CHANGED"); return true
end
local function ReceiptPage(sender, b, c, done)
	local r = Capsule(c)
	if not r or not Same(r.subject, b.subject) then return false end
	if b.mode == "S" then
		if not Same(r.issuer, sender) or r.guild ~= b.sourceGuild or not (r.kind == "L" or r.kind == "W" and r.fields.sourceKind == "L") then return false end
	elseif r.kind == "L" or r.kind == "W" then return false end
	if b.mode == "C" then
		if not Same(sender, r.issuer) then return false end
		local ok, why = H.ReceiveOriginal(sender, c, done)
		if not ok and why == "already-retained" then return H.Verify(c, done) end
		return ok
	end
	-- The transferring member is NOT the original issuer or a key authority.
	local queued, why = H.Verify(c, done)
	if not queued and why == "original-key-unverified" then done(r, "pending-key"); return true end
	return queued
end
local function ReceivePage(sender, f, text)
	local key, s = Key(sender, f[4]), Store()
	local b = inboxes[key]
	local cursor, part, n, digest, fragment = text:match("^XC~2~D~%x+~(%d+)~(%d+)~(%d+)~(%x+)~(.*)$")
	cursor, part, n = tonumber(cursor), tonumber(part), tonumber(n)
	if not b or not Current(b) or s.floors[key] or not b.guard() or not Whole(cursor) or cursor < 1 or cursor > b.count
		or not Whole(part) or part < 1 or not Whole(n) or n < part or n > H.PARTS or not digest or #digest ~= 16 or #fragment > H.PART then return false end
	if cursor < b.cursor then
		if b.hashes[cursor] == digest then return Send(sender, ("XC~2~N~%s~%d~%s"):format(b.id, cursor, digest), b.guard) end
		return false
	end
	if cursor ~= b.cursor or b.verifying then return false end
	local page = b.page or { n = n, digest = digest, parts = {} }; b.page = page
	if page.n ~= n or page.digest ~= digest or page.parts[part] and page.parts[part] ~= fragment then b.revoked = true; s.floors[key] = "conflict"; return false end
	page.parts[part] = fragment
	for i = 1, n do if not page.parts[i] then return true end end
	local body = table.concat(page.parts)
	if Digest(body):sub(1, 16) ~= digest then b.revoked = true; s.floors[key] = "digest"; return false end
	local c = Unpack(body); if not c then return false end
	b.verifying = true
	local queued = ReceiptPage(sender, b, c, function(record, why)
		b.verifying = nil
		if not record or inboxes[key] ~= b or not Current(b) or not b.guard() or s.floors[key] then return end
		c.status = why == "pending-key" and "pending-key" or "signature-verified"
		b.capsules[cursor], b.hashes[cursor], b.page, b.cursor = Copy(c), digest, nil, cursor + 1
		Touch(b); if b.consent then Touch(b.consent) end
		Send(sender, ("XC~2~N~%s~%d~%s"):format(b.id, cursor, digest), b.guard)
		ns.Fire("HISTORY_CARRY_CHANGED")
	end)
	if not queued then b.verifying = nil end
	return queued
end
function H.Handle(dist, sender, text)
	if dist ~= "WHISPER" or not Name(sender) or type(text) ~= "string" or #text > 255 then return false end
	sender = Name(sender)
	local f = Fields(text)
	if f[1] ~= "XC" or f[2] ~= "2" or not f[4] or #f[4] ~= 16 or not f[4]:match("^%x+$") then return false end
	Prune()
	local s, id, key = Store(), f[4], Key(sender, f[4]); if not s then return false end
	if f[3] == "Q" then
		if #f ~= 5 or not ({ C = true, K = true })[f[5]] or not Fresh() or not Member(ns.me) or Preview() then return false end
		local actor, scope, guild = ns.me, Scope(), GetGuildInfo("player")
		local guard = function() return Live(actor, scope, guild) end
		-- Q is a request by its server-stamped subject, never a body-supplied third party.
		if not SendKey(sender, id, guard) then return false end
		if f[5] == "C" then
			local list = {}
			for _, c in ipairs(H.Originals(sender)) do local r = H.Parse(c.text)
				if r.kind ~= "L" and r.kind ~= "W" and IssuerRole(r) then list[#list + 1] = c end
			end
			if #list > 0 then return StartStream(sender, id, list, "C", guard) end
		end
		return true
	elseif f[3] == "K" then return ReceiveKey(sender, f)
	elseif f[3] == "O" then
		if #f ~= 9 or not Fresh() or not Member(sender) or not Master(ns.me, GetGuildInfo("player")) or s.floors[key] then return false end
		local source, guild, scope, count = Unescape(f[5]), Unescape(f[6]), Unescape(f[7]), tonumber(f[8])
		if not Guild(source) or source == guild or guild ~= GetGuildInfo("player") or scope ~= Scope()
			or not Whole(count) or count > H.RECORDS or #f[9] ~= 16 or not f[9]:match("^%x+$")
			or count == 0 and f[9] ~= Manifest({}) then return false end
		local old = offers[key]
		if old then
			if old.digest ~= f[9] or old.count ~= count or old.sourceGuild ~= source then old.revoked = true; s.floors[key] = "conflict" end
			return false
		end
		if Count(offers) >= H.STREAMS or Count(s.floors) + Count(offers) >= 256 or Count(s.imports) >= H.IMPORTS or not SenderCapacity(sender) then return false end
		offers[key] = { actor = ns.me, scope = scope, localGuild = guild, guild = guild, sourceGuild = source,
			subject = sender, count = count, digest = f[9], id = id, at = Clock() }
		ns.Fire("HISTORY_CARRY_CHANGED"); return true
	elseif f[3] == "A" then
		local grant = staffGrants[Key(sender, id)]
		if #f == 5 and grant and StaffOutCurrent(grant) and grant.accepted and grant.manifest == f[5] and Same(sender, grant.to) then
			return StartStream(sender, id, grant.list, "S", function() return staffGrants[Key(sender, id)] == grant and StaffOutCurrent(grant) and grant.accepted end)
		end
		local d = s.draft
		if #f ~= 5 or not Ready(d) or not Same(sender, d.to) or d.id ~= id or d.digest ~= f[5]
			or not d.offeredAt or Clock() - d.offeredAt > H.LIFE then return false end
		return StartStream(sender, id, d.capsules, "T", function() return s.draft == d and Ready(d) end)
	elseif f[3] == "B" then
		local mode, count, manifest = f[5], tonumber(f[6]), f[7]
		if #f ~= 7 or not Whole(count) or count > H.RECORDS or not manifest or #manifest ~= 16 or not manifest:match("^%x+$")
			or count == 0 and manifest ~= Manifest({})
			or inboxes[key] or Count(inboxes) >= H.STREAMS or s.floors[key] then return false end
		local req, o = requested[ns.Fold(sender)], offers[key]
		local guard, subject
		if mode == "C" and req and req.id == id and req.mode == "C" and Current(req) then
			guard, subject = function() return requested[ns.Fold(sender)] == req and Current(req) end, ns.me
		elseif (mode == "T" or mode == "S" and o and o.staff) and o and o.accepted and OfferCurrent(o) and o.count == count and o.digest == manifest then
			guard, subject = function() return offers[key] == o and o.accepted and OfferCurrent(o) end, o.subject
		else return false end
		inboxes[key] = { actor = ns.me, scope = Scope(), localGuild = GetGuildInfo("player"), at = Clock(), id = id,
			mode = mode, count = count, manifest = manifest, subject = subject, sourceGuild = o and o.sourceGuild,
			cursor = 1, capsules = {}, hashes = {}, guard = guard, consent = mode == "C" and req or o }
		return true
	elseif f[3] == "D" then return ReceivePage(sender, f, text)
	elseif f[3] == "N" then
		local t, cursor = streams[key], tonumber(f[5])
		if #f ~= 6 or not t or not Current(t) or not t.guard() or cursor ~= t.cursor or f[6] ~= t.digest then return false end
		Touch(t)
		t.cursor, t.tries = t.cursor + 1, 0
		return SendPage(t)
	elseif f[3] == "Z" then
		local b = inboxes[key]
		local completed = s.completed[key]
		if #f == 6 and completed and not completed.revoked and completed.count == tonumber(f[5]) and completed.digest == f[6]
			and Live(completed.actor, completed.scope, completed.localGuild)
			and (completed.mode == "C" or Master(ns.me, completed.localGuild) and Member(completed.subject)) then
			return Send(sender, "XC~2~F~" .. id .. "~" .. f[6], function()
				return not completed.revoked and Live(completed.actor, completed.scope, completed.localGuild)
					and (completed.mode == "C" or Master(ns.me, completed.localGuild) and Member(completed.subject))
			end)
		end
		if #f ~= 6 or not b or not Current(b) or not b.guard() or tonumber(f[5]) ~= b.count or f[6] ~= b.manifest
			or b.cursor ~= b.count + 1 or Manifest(b.capsules) ~= b.manifest then return false end
		if not s.floors[key] and Count(s.floors) + Count(offers) >= 256 and not offers[key] then return false end
		if b.mode == "T" or b.mode == "S" then
			local o = offers[key]
			if Count(s.imports) >= H.IMPORTS then return false end
			s.imports[key] = { subject = b.subject, recipient = ns.me, scope = Scope(), sourceGuild = o.sourceGuild,
				guild = o.guild, digest = o.digest, capsules = b.capsules, receivedAt = Clock(), staff = b.mode == "S", baseKey = o.baseKey }
			s.floors[key] = "received"; offers[key] = nil
		end
		if b.mode == "C" then requested[ns.Fold(sender)] = nil end
		completed = { actor = ns.me, scope = Scope(), localGuild = GetGuildInfo("player"), mode = b.mode,
			subject = b.subject, count = b.count, digest = b.manifest }
		s.completed[key], s.floors[key] = completed, "received"
		Send(sender, "XC~2~F~" .. id .. "~" .. b.manifest, function()
			return not completed.revoked and Live(completed.actor, completed.scope, completed.localGuild)
				and (completed.mode == "C" or Master(ns.me, completed.localGuild) and Member(completed.subject))
		end)
		inboxes[key] = nil; ns.Fire("HISTORY_CARRY_CHANGED"); return true
	elseif f[3] == "F" then
		local t = streams[key]
		if #f ~= 5 or not t or not Current(t) or not t.guard() or t.cursor ~= #t.list + 1 or f[5] ~= t.manifest then return false end
		streams[key] = nil
		if t.mode == "T" and s.draft and s.draft.id == id then s.draft.completed = true end
		ns.Fire("HISTORY_CARRY_CHANGED"); return true
	elseif f[3] == "R" then
		local o, e = offers[key], s.imports[key]
		local grant = staffGrants[key]
		if #f == 5 and grant and grant.outgoing and Same(sender, grant.subject) and grant.digest == f[5] then
			grant.revoked = true; staffGrants[key] = nil
			s.floors[key], s.floors[Key(grant.to, id)] = "revoked", "revoked"
			Send(grant.to, "XC~2~U~" .. id .. "~" .. Escape(grant.subject) .. "~" .. grant.digest,
				function() return Same(grant.actor, ns.me) and grant.scope == Scope() end)
			return true
		end
		if #f ~= 5 or not f[5]:match("^%x+$") or #f[5] ~= 16 or o and o.digest ~= f[5] or e and e.digest ~= f[5] then return false end
		if not o and not e then
			if not Fresh() or not Member(sender) or not Master(ns.me, GetGuildInfo("player")) then return false end
			if not s.floors[key] and (Count(s.floors) + Count(offers) >= 256 or not SenderCapacity(sender)) then return false end
		end
		if e then e.revoked = true end
		if s.completed[key] then s.completed[key].revoked = true end
		if o then o.revoked = true end
		s.floors[key], offers[key], inboxes[key] = "revoked", nil, nil
		for k, imported in pairs(s.imports) do if imported.baseKey == key then imported.revoked = true; s.floors[k] = "revoked"; if s.completed[k] then s.completed[k].revoked = true end end end
		for k, pending in pairs(offers) do if pending.baseKey == key then pending.revoked = true; offers[k], inboxes[k] = nil, nil; s.floors[k] = "revoked" end end
		ns.Fire("HISTORY_CARRY_CHANGED"); return true
	elseif f[3] == "G" then
		local sourceMaster, source = Name(Unescape(f[5])), Unescape(f[6])
		local entry = s.imports[key]
		if #f ~= 7 or not entry or entry.revoked or entry.digest ~= f[7] or not Same(entry.subject, sender)
			or not Master(ns.me, entry.guild) or not Member(sender) or not Master(sourceMaster, source) or entry.sourceGuild ~= source then return false end
		if Count(staffGrants) >= H.STREAMS then return false end
		staffGrants[Key(sourceMaster, id)] = { actor = ns.me, localGuild = GetGuildInfo("player"), scope = Scope(), at = Clock(),
			id = id, subject = sender, sourceGuild = source, guild = entry.guild, to = ns.me, digest = entry.digest, baseKey = key }
		return true
	elseif f[3] == "S" then
		local to, guild, source = Name(Unescape(f[5])), Unescape(f[6]), Unescape(f[7])
		if #f ~= 8 or not Master(ns.me, source) or not Master(to, guild) or source == guild
			or not f[8]:match("^%x+$") or #f[8] ~= 16 or Count(staffGrants) + 2 > H.STREAMS or staffGrants[key] or s.floors[key] then return false end
		staffGrants[key] = { actor = ns.me, localGuild = source, scope = Scope(), at = Clock(), id = id,
			subject = sender, sourceGuild = source, guild = guild, to = to, digest = f[8], outgoing = true }
		-- Destination-address index lets its later A select only this explicit source consent.
		staffGrants[Key(to, id)] = staffGrants[key]
		ns.Fire("HISTORY_CARRY_CHANGED"); return true
	elseif f[3] == "V" then
		local grant = staffGrants[key]
		local subject, source, count = Name(Unescape(f[5])), Unescape(f[6]), tonumber(f[7])
		local base = grant and s.imports[grant.baseKey]
		if #f ~= 8 or not grant or grant.outgoing or not Current(grant) or not base or base.revoked or not Master(sender, source)
			or not Master(ns.me, grant.guild) or not Member(subject) or not Same(subject, grant.subject) or source ~= grant.sourceGuild
			or not Whole(count) or count < 1 or count > H.RECORDS or #f[8] ~= 16 or not f[8]:match("^%x+$") or s.floors[key] or offers[key]
			or Count(offers) >= H.STREAMS or Count(s.floors) + Count(offers) >= 256 or Count(s.imports) >= H.IMPORTS or not SenderCapacity(sender) then return false end
		offers[key] = { actor = ns.me, scope = Scope(), localGuild = grant.guild, guild = grant.guild, sourceGuild = source,
			subject = subject, sender = sender, count = count, digest = f[8], id = id, at = Clock(), staff = true, baseKey = grant.baseKey }
		ns.Fire("HISTORY_CARRY_CHANGED"); return true
	elseif f[3] == "U" then
		local grant = staffGrants[key]
		if #f ~= 6 or not grant or grant.outgoing or not Same(Name(Unescape(f[5])), grant.subject) or f[6] ~= grant.digest then return false end
		local e = s.imports[key]; if e then e.revoked = true end
		if s.completed[key] then s.completed[key].revoked = true end
		s.floors[key], offers[key], inboxes[key], staffGrants[key] = "revoked", nil, nil, nil
		ns.Fire("HISTORY_CARRY_CHANGED"); return true
	end
	return false
end
function H.Imports()
	local out, s = {}, Store()
	for _, e in pairs(s and s.imports or {}) do
		if not e.revoked and Same(e.recipient, ns.me) and e.scope == Scope() and Master(ns.me, e.guild) and Member(e.subject) then out[#out + 1] = e end
	end
	return out
end
function H.Lines()
	Prune()
	local L, lines = ns.L, {}
	if not L.CARRY_HISTORY_TITLE then return lines end
	lines[#lines + 1] = { header = true, text = L.CARRY_HISTORY_TITLE }
	lines[#lines + 1] = { text = L.CARRY_HISTORY_NOTE, gapAfter = true }
	lines[#lines + 1] = { text = L.CARRY_HISTORY_COLLECT, gapAfter = true }
	local function Add(c)
		local r = H.Parse(c.text); if not r then return end
		local words = r.fields.words or r.fields.expires or r.fields.copper or ""
		if ns.Filter and ns.Filter.Hides and ns.Filter.Hides(words) then words = L.FILTER_WORDS_HIDDEN_SHORT end
		lines[#lines + 1] = { text = L.CARRY_HISTORY_ARCHIVED:format(r.kind, ns.DisplayName(r.issuer), date("%Y-%m-%d %H:%M", r.at), r.guild, words), indent = 1 }
		if r.kind == "W" and L.CARRY_HISTORY_WITNESS then
			lines[#lines + 1] = { text = L.CARRY_HISTORY_WITNESS:format(r.fields.originalWriter or "?", tostring(r.fields.originalAt or "?")), indent = 1 }
		end
		if c.status == "pending-key" then
			local issuer = r.issuer
			lines[#lines + 1] = { text = L.CARRY_HISTORY_PENDING_KEY:format(ns.DisplayName(issuer)), indent = 1, onClick = function() H.RequestKey(issuer) end, gapAfter = true }
		elseif c.status == "signature-invalid" then lines[#lines + 1] = { text = L.CARRY_HISTORY_INVALID or L.CARRY_HISTORY_EMPTY, indent = 1, gapAfter = true }
		else lines[#lines + 1] = { text = L.CARRY_HISTORY_VERIFIED, indent = 1, gapAfter = true } end
	end
	local mine, imported = H.Archive(), H.Imports()
	for _, c in ipairs(mine) do Add(c) end
	for _, entry in ipairs(imported) do for _, c in ipairs(entry.capsules) do Add(c) end end
	for key, o in pairs(offers) do if OfferCurrent(o) then local k = key
		lines[#lines + 1] = { text = L.CARRY_PENDING:format(ns.DisplayName(o.subject), o.count, o.sourceGuild) }
		lines[#lines + 1] = { text = L.CARRY_ACCEPT_BUTTON, onClick = function() H.Accept(k) end, gapAfter = true }
	end end
	local shown = {}
	for key, grant in pairs(staffGrants) do if StaffOutCurrent(grant) and not shown[grant] and not grant.accepted and L.CARRY_HISTORY_STAFF then
		shown[grant] = true; local k = key
		lines[#lines + 1] = { text = L.CARRY_HISTORY_STAFF:format(ns.DisplayName(grant.subject), ns.DisplayName(grant.to)), onClick = function() H.StaffAccept(k) end, gapAfter = true }
	end end
	local s = Store(); local d = s and s.draft
	if Draft(d) then
		lines[#lines + 1] = { text = L.CARRY_READY:format(d.sourceGuild, d.guild, ns.DisplayName(d.to), #d.capsules) }
		if Ready(d) and not d.completed then lines[#lines + 1] = { text = L.CARRY_OFFER, onClick = H.Offer } end
		lines[#lines + 1] = { text = L.CARRY_CANCEL, onClick = H.Revoke, gapAfter = true }
	end
	for _, b in pairs(inboxes) do if Current(b) then lines[#lines + 1] = { text = L.CARRY_HISTORY_PROGRESS:format(b.cursor - 1, b.count) } end end
	if #mine == 0 and #imported == 0 then lines[#lines + 1] = { text = L.CARRY_HISTORY_EMPTY } end
	return lines
end
StaticPopupDialogs.OLYMPUS_CARRY_STAFF = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self) local d = self.data; if d then ns.SafeCall("carry staff", H.StaffAccept, d.key, d) end end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }

local _, ns = ...
local L = ns.L

-- F26-14, deliberately partial: the same server-stamped character transports a small quoted
-- sidecar, not authoritative imports. No original ledger/status/role/key is ever written here.
-- Prepare while still in the source guild; move by a human invitation; offer after joining the
-- destination. Both ends explicitly confirm. XC is private, individually bounded packets, not
-- a new public or outsider assembler. Original unsigned evidence stays unverified after relay.
local Carry = {}
ns.Carry = Carry
Carry.ROWS, Carry.BYTES, Carry.PART, Carry.PARTS = 24, 4096, 180, 24
Carry.OFFER_LIFE, Carry.PENDING, Carry.IMPORTS, Carry.FLOORS = 180, 8, 32, 128
local offers, receiving, sending = {}, {}, nil

local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Full(s)
	if type(s) ~= "string" or s == "" or #s > 64 or s:find("[|~^%c]") then return nil end
	local n = ns.FullName(ns.Normal(s))
	return type(n) == "string" and #n <= 64 and ns.RealmOf(n) and n or nil
end
local function Same(a, b) return Full(a) ~= nil and Full(b) ~= nil and ns.Fold(Full(a)) == ns.Fold(Full(b)) end
local function Guild(s) return type(s) == "string" and #s <= 72 and s ~= "" and not s:find("[|~^%c]") and ns.IsFederation(s) end
local function Scope() return tostring(ns.faction) .. ":" .. tostring(ns.group or ns.GroupOf(ns.realm)) end
local function Fresh() return ns.IsMember() and ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh() ~= nil end
local function Member(name) return Fresh() and ns.Roster.RankOf(name) ~= nil end
local function Master(name, guild)
	if not Full(name) or not Guild(guild) then return false end
	if ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing() then return false end
	if ns.WatchChat and ns.WatchChat.Barred and ns.WatchChat.Barred("powers", name) then return false end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(name, guild) then return false end
	local rank, source = ns.Data.AuthorizedRank(name, guild)
	if guild == GetGuildInfo("player") then
		return Fresh() and rank == 0 and source == "roster" and (not Same(name, ns.me) or select(3, GetGuildInfo("player")) == 0)
	end
	return rank == 0 and (source == "signed" or source == "pinned")
end
local function Destination(name)
	name = Full(name)
	if not name then return nil end
	local mine = GetGuildInfo("player")
	if Master(name, mine) then return mine end
	local A = ns.Authority
	local guild, rank, source
	if A and A.Role then guild, rank, source = A.Role(name) end
	if rank == 0 and source == "signed" and Master(name, guild) then return guild end
	local kingGuild = ns.KingGuildName and ns.KingGuildName()
	if ns.IsKingCharacter and ns.IsKingCharacter(name) and Master(name, kingGuild) then return kingGuild end
end
local function Store()
	if not ns.rdb then return nil end
	local s = ns.rdb.historyCarry
	if type(s) ~= "table" or s.version ~= 1 then s = { version = 1, seq = 0, imported = {}, floors = {} }; ns.rdb.historyCarry = s end
	if type(s.imported) ~= "table" then s.imported = {} end
	if type(s.floors) ~= "table" then s.floors = {} end
	return s
end
local function Number(v, max) return type(v) == "number" and v == v and v >= 0 and v <= (max or 4294967295) and v % 1 == 0 end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Changed() ns.Fire("HISTORY_CARRY_CHANGED"); if ns.UI and ns.UI.RefreshSoon then ns.UI.RefreshSoon() end end
local function Escape(s) return tostring(s or ""):gsub("[^%w %.%-%_]", function(c) return ("%%%02X"):format(c:byte()) end) end
local function Unescape(s)
	if type(s) ~= "string" or s:find("%%[^%x]") or s:find("%%[%x][^%x]") or s:match("%%[%x]?$") then return nil end
	return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local function Fields(s, sep)
	local out = {}; for x in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = x end; return out
end
local function Digest(body)
	-- Sign.SHA256 returns binary bytes, not hex; a digest must survive addon-message
	-- sanitation and match the receiver's bounded hex field.
	return (ns.Sign.SHA256(body):sub(1, 8):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end
local function Row(kind, id, by, at, guild, words, via, a, b, c)
	return { kind = kind, id = tostring(id or ""), by = tostring(by or "?"), at = tonumber(at) or 0,
		guild = guild or "", words = tostring(words or ""), via = via or "", a = tostring(a or ""), b = tostring(b or ""), c = tostring(c or "") }
end
function Carry.Gather()
	local out, guild = {}, GetGuildInfo("player")
	local function Add(row)
		if #out < Carry.ROWS and #row.id <= 160 and #row.by <= 64 and #row.guild <= 72 and #row.words <= 160 and #row.via <= 64
			and Number(row.at) and #row.a <= 32 and #row.b <= 32 and #row.c <= 64 then out[#out + 1] = row end
	end
	-- Being named by a private loot note is not permission to export its author's book.
	-- Such records travel only over CarryHistory's separately consented staff route.
	for _, e in ipairs(ns.Court and ns.Court.Messages and ns.Court.Messages() or {}) do
		if Same(e.to, ns.me) then
			-- Court's retained id preserves the original server time; Chronicle's st is when
			-- this client observed it. Keep both, with no invented source guild.
			local original = type(e.id) == "string" and tonumber(e.id:match(":(%d+):[^:]+$"))
			Add(Row("C", e.id, e.by, original or 0, "", e.words, "", e.st or e.t))
		end
	end
	-- Ordinary readers retain the time they first heard a pardon, not the King's deadline.
	-- Preserve that observation only. Never turn it into an end date or apply a pardon.
	local heard = ns.rdb and ns.rdb.pardons and ns.rdb.pardons[ns.ShortName(ns.me):lower()]
	if Number(heard) and ns.Acts and ns.Acts.Pardoned(ns.me) then
		Add(Row("P", "observed-pardon", "?", heard, "", "", ""))
	end
	local D = ns.Dues
	if D and D.Week and D.PayerReceiptFacts then
		for week = D.Week(), D.Week() - (D.WEEKS_KEPT or 5) + 1, -1 do
			for _, e in ipairs(D.PayerReceiptFacts(week) or {}) do
				if Same(e.payer, ns.me) then Add(Row("D", tostring(e.bookPin) .. ":" .. tostring(e.sequence), e.issuer, e.at,
					e.guild, e.source, "", e.week, e.copper, e.amount)) end
			end
		end
	end
	return out
end
function Carry.Encode(rows)
	if type(rows) ~= "table" or #rows == 0 or #rows > Carry.ROWS then return nil end
	local parts = {}
	for _, r in ipairs(rows) do
		local f = { r.kind, r.id, r.by, r.at, r.guild, r.words, r.via, r.a, r.b, r.c }
		for i = 1, 10 do f[i] = Escape(f[i]) end
		parts[#parts + 1] = table.concat(f, "~")
	end
	local body = table.concat(parts, ";")
	return #body <= Carry.BYTES and body or nil
end
function Carry.Decode(body, count)
	if type(body) ~= "string" or #body > Carry.BYTES or not Number(count, Carry.ROWS) or count < 1 then return nil end
	local rows = {}
	for _, text in ipairs(Fields(body, ";")) do
		local f = Fields(text, "~")
		if #f ~= 10 then return nil end
		for i = 1, 10 do f[i] = Unescape(f[i]); if f[i] == nil or f[i]:find("[|%c]") then return nil end end
		if not ({ C = true, P = true, D = true })[f[1]] or #f[2] > 160 or #f[3] > 64 or #f[5] > 72
			or #f[6] > 160 or #f[7] > 64 or #f[8] > 32 or #f[9] > 32 or #f[10] > 64 or not Number(tonumber(f[4])) then return nil end
		rows[#rows + 1] = Row(f[1], f[2], f[3], tonumber(f[4]), f[5], f[6], f[7], f[8], f[9], f[10])
		if #rows > Carry.ROWS then return nil end
	end
	return #rows == count and rows or nil
end
local function Source(d)
	return type(d) == "table" and Same(d.subject, ns.me) and d.scope == Scope() and not d.revoked and Guild(d.sourceGuild) and Guild(d.guild)
		and type(d.rows) == "table" and type(d.body) == "string" and type(d.to) == "string"
end
local function Ready(d)
	return Source(d) and GetGuildInfo("player") == d.guild and Member(ns.me) and Master(d.to, d.guild)
end
function Carry.Prepare(to)
	local H = ns.CarryHistory
	if H and H.Prepare and (#H.Archive() > 0 or #Carry.Gather() == 0) then return H.Prepare(to) end
	local source, guild = GetGuildInfo("player"), Destination(to)
	if not Fresh() or not guild or not Guild(source) or guild == source then return false, "destination" end
	local rows = Carry.Gather()
	local body = Carry.Encode(rows)
	if not body then return false, "empty-or-size" end
	local d = { subject = ns.me, scope = Scope(), sourceGuild = source, guild = guild, to = Full(to), rows = rows, body = body, digest = Digest(body) }
	if not ns.Dialog or ns.Dialog.missing then return false, "dialog" end
	ns.Dialog.Show("OLYMPUS_CARRY_PREPARE", L.CARRY_CONFIRM:format(#rows, source, ns.DisplayName(d.to), guild), nil, d)
	return true
end
function Carry.Confirm(d)
	if type(d) == "table" and d.version == 2 then return ns.CarryHistory and ns.CarryHistory.Confirm(d) end
	local s = Store()
	if not s or not Source(d) or GetGuildInfo("player") ~= d.sourceGuild or not Fresh() or Destination(d.to) ~= d.guild
		or not Carry.Decode(d.body, #d.rows) or Digest(d.body) ~= d.digest then return false end
	if s.draft and not s.draft.revoked then return false end
	s.seq = math.floor(tonumber(s.seq) or 0) + 1
	d.id, d.at = Digest(ns.me .. Scope() .. Clock() .. s.seq), Clock()
	s.draft = d
	Changed(); return true
end
function Carry.Offer()
	if ns.CarryHistory and ns.CarryHistory.HasDraft and ns.CarryHistory.HasDraft() then return ns.CarryHistory.Offer() end
	local s = Store(); local d = s and s.draft
	if not Ready(d) then return false, "join-destination-first" end
	d.offeredAt = Clock()
	local msg = table.concat({ "XC", 1, "O", d.id, Escape(d.sourceGuild), Escape(d.guild), Escape(d.scope), #d.body, #d.rows, d.digest }, "~")
	local ok = ns.Comm.Whisper(d.to, msg, "carry-offer", nil, nil, nil, { owner = Carry, guard = function() return s.draft == d and Ready(d) end })
	return ok == true
end
local function Reader(subject, guild)
	return Guild(guild) and GetGuildInfo("player") == guild and Master(ns.me, guild) and Member(subject)
end
local function Current(o)
	return o and o.scope == Scope() and Clock() - o.at >= 0 and Clock() - o.at <= Carry.OFFER_LIFE
		and Reader(o.subject, o.guild)
end
local function Key(subject, id) return ns.Fold(subject) .. ":" .. id end
function Carry.Accept(key, confirmed)
	if ns.CarryHistory and ns.CarryHistory.HasOffer and ns.CarryHistory.HasOffer(key) then return ns.CarryHistory.Accept(key, confirmed) end
	local o = offers[key]
	if not Current(o) then return false end
	if not confirmed then
		if not ns.Dialog or ns.Dialog.missing then return false end
		ns.Dialog.Show("OLYMPUS_CARRY_ACCEPT", L.CARRY_ACCEPT:format(o.count, ns.DisplayName(o.subject), o.sourceGuild), nil, { key = key, offer = o })
		return true
	end
	if type(confirmed) ~= "table" or confirmed.offer ~= o or confirmed.key ~= key then return false end
	o.accepted = true
	return ns.Comm.Whisper(o.subject, table.concat({ "XC", 1, "A", o.id, o.digest }, "~"), nil, nil, nil, nil,
		{ owner = Carry, guard = function() return offers[key] == o and o.accepted and Current(o) end }) == true
end
function Carry.Revoke()
	if ns.CarryHistory and ns.CarryHistory.HasDraft and ns.CarryHistory.HasDraft() then return ns.CarryHistory.Revoke() end
	local s = Store(); local d = s and s.draft
	if not d or not Same(d.subject, ns.me) or d.scope ~= Scope() then return false end
	d.revoked = true
	if ns.Comm.CancelOwner then ns.Comm.CancelOwner(Carry) end
	ns.Comm.Whisper(d.to, table.concat({ "XC", 1, "R", d.id, d.digest }, "~"), nil, nil, nil, nil,
		{ owner = Carry, guard = function() return Same(d.subject, ns.me) and d.scope == Scope() end })
	Changed(); return true
end
function Carry.Handle(dist, sender, text)
	if type(text) == "string" and text:sub(1, 5) == "XC~3~" then
		return ns.CarryMerger and ns.CarryMerger.Handle(dist, sender, text) or false
	end
	if type(text) == "string" and text:sub(1, 5) == "XC~2~" then
		return ns.CarryHistory and ns.CarryHistory.Handle(dist, sender, text) or false
	end
	if dist ~= "WHISPER" or not Full(sender) or type(text) ~= "string" or #text > 255 then return false end
	sender = Full(sender)
	local f = Fields(text, "~")
	if f[1] ~= "XC" or f[2] ~= "1" or not f[4] or not f[4]:match("^%x+$") or #f[4] ~= 16 then return false end
	local s, id = Store(), f[4]; if not s then return false end
	local key = Key(sender, id)
	if f[3] == "O" then
		if #f ~= 10 then return false end
		local sourceGuild, guild, scope, bytes, count = Unescape(f[5]), Unescape(f[6]), Unescape(f[7]), tonumber(f[8]), tonumber(f[9])
		if not Guild(sourceGuild) or sourceGuild == guild or not Reader(sender, guild) or scope ~= Scope()
			or not Number(bytes, Carry.BYTES) or bytes < 1 or not Number(count, Carry.ROWS) or count < 1
			or not f[10]:match("^%x+$") or #f[10] ~= 16 or s.floors[key] then return false end
		local old = offers[key]
		if old then
			if old.digest ~= f[10] or old.bytes ~= bytes or old.count ~= count or old.sourceGuild ~= sourceGuild or old.guild ~= guild then
				s.floors[key] = "conflict"; offers[key], receiving[key] = nil, nil
			end
			return false
		end
		for k, o in pairs(offers) do if not Current(o) then offers[k], receiving[k] = nil, nil end end
		if Count(offers) >= Carry.PENDING or Count(s.floors) + Count(offers) >= Carry.FLOORS then return false end
		offers[key] = { id = id, subject = sender, sourceGuild = sourceGuild, guild = guild, scope = scope, bytes = bytes, count = count, digest = f[10], at = Clock() }
		Changed(); return true
	elseif f[3] == "A" then
		local d = s.draft
		if #f ~= 5 or not Ready(d) or not Same(sender, d.to) or d.id ~= id or f[5] ~= d.digest
			or not d.offeredAt or Clock() - d.offeredAt < 0 or Clock() - d.offeredAt > Carry.OFFER_LIFE or d.sent or sending == d then return false end
		local parts = {}; local n = math.ceil(#d.body / Carry.PART)
		if n > Carry.PARTS then return false end
		for i = 1, n do parts[i] = table.concat({ "XC", 1, "D", id, d.digest, i, n, d.body:sub((i - 1) * Carry.PART + 1, i * Carry.PART) }, "~") end
		sending = d
		local ok = ns.Comm.SendBatch("WHISPER", parts, "carry-data", d.to, nil, function(sent)
			if sending == d then sending = nil; d.sent = sent == true; Changed() end
		end, { owner = Carry, guard = function() return s.draft == d and Ready(d) end })
		return ok == true
	elseif f[3] == "R" then
		if #f ~= 5 then return false end
		local o, saved = offers[key], s.imported[key]
		if (o and o.digest ~= f[5]) or (saved and saved.digest ~= f[5]) then return false end
		if not o and not saved and not Reader(sender, GetGuildInfo("player")) then return false end
		if not s.floors[key] and not o and Count(s.floors) + Count(offers) >= Carry.FLOORS then return false end
		s.floors[key] = "revoked"; offers[key], receiving[key] = nil, nil
		if saved then saved.revoked = true end
		Changed(); return true
	elseif f[3] == "D" then
		local digest, i, n, fragment = text:match("^XC~1~D~%x+~(%x+)~(%d+)~(%d+)~(.*)$")
		i, n = tonumber(i), tonumber(n)
		local o = offers[key]
		if not Current(o) or not o.accepted or s.floors[key] or digest ~= o.digest or not Number(i, Carry.PARTS) or i < 1
			or not Number(n, Carry.PARTS) or n < i or n ~= math.ceil(o.bytes / Carry.PART) or #fragment ~= math.min(Carry.PART, o.bytes - (i - 1) * Carry.PART) then return false end
		local b = receiving[key] or { parts = {}, bytes = 0 }; receiving[key] = b
		if b.parts[i] then
			if b.parts[i] ~= fragment then s.floors[key] = "conflict"; offers[key], receiving[key] = nil, nil end
			return false
		end
		b.parts[i], b.bytes = fragment, b.bytes + #fragment
		if b.bytes > o.bytes then s.floors[key] = "size"; offers[key], receiving[key] = nil, nil; return false end
		for j = 1, n do if not b.parts[j] then return true end end
		local body = table.concat(b.parts); local rows = Carry.Decode(body, o.count)
		if #body ~= o.bytes or Digest(body) ~= o.digest or not rows or Count(s.imported) >= Carry.IMPORTS then
			s.floors[key] = "invalid"; offers[key], receiving[key] = nil, nil; return false
		end
		for _, r in ipairs(rows) do
			if r.kind == "L" and not Same(r.c, sender) then
				s.floors[key] = "subject"; offers[key], receiving[key] = nil, nil; return false
			end
		end
		s.imported[key] = { subject = sender, recipient = ns.me, sourceGuild = o.sourceGuild, guild = o.guild, scope = o.scope, digest = digest, rows = rows, receivedAt = Clock(), unverified = true }
		s.floors[key] = "received"; offers[key], receiving[key] = nil, nil
		Changed(); return true
	end
	return false
end
function Carry.List()
	local out, s = {}, Store()
	for key, e in pairs(s and s.imported or {}) do
		if type(e) == "table" and not e.revoked and Same(e.recipient, ns.me) and e.scope == Scope() and Reader(e.subject, e.guild) then out[#out + 1] = { key = key, entry = e } end
	end
	table.sort(out, function(a, b) return a.key < b.key end)
	return out
end
local function When(at) return type(at) == "number" and at > 0 and date("%Y-%m-%d %H:%M", at) or L.CARRY_UNKNOWN end
function Carry.Lines()
	local lines = { { header = true, text = L.CARRY_TITLE }, { text = L.CARRY_NOTE, gapAfter = true }, { text = L.CARRY_PREPARE, gapAfter = true } }
	if ns.CarryHistory and ns.CarryHistory.Lines then
		for _, line in ipairs(ns.CarryHistory.Lines()) do lines[#lines + 1] = line end
	end
	if ns.CarryMerger and ns.CarryMerger.Lines then
		for _, line in ipairs(ns.CarryMerger.Lines()) do lines[#lines + 1] = line end
	end
	local s = Store(); local d = s and s.draft
	if Source(d) then
		lines[#lines + 1] = { text = L.CARRY_READY:format(d.sourceGuild, d.guild, ns.DisplayName(d.to), #d.rows) }
		if Ready(d) then lines[#lines + 1] = { text = L.CARRY_OFFER, onClick = Carry.Offer } end
		lines[#lines + 1] = { text = L.CARRY_CANCEL, onClick = Carry.Revoke, gapAfter = true }
	end
	for key, o in pairs(offers) do
		if Current(o) then
			local k = key
			lines[#lines + 1] = { text = L.CARRY_PENDING:format(ns.DisplayName(o.subject), o.count, o.sourceGuild) }
			lines[#lines + 1] = { text = L.CARRY_ACCEPT_BUTTON, onClick = function() Carry.Accept(k) end, gapAfter = true }
		end
	end
	local listed = Carry.List()
	for _, x in ipairs(listed) do
		local e = x.entry
		lines[#lines + 1] = { header = true, text = L.CARRY_IMPORTED:format(ns.DisplayName(e.subject), e.sourceGuild, ns.DisplayName(e.subject)) }
		for _, r in ipairs(e.rows) do
			local words = r.words
			if ns.Filter and ns.Filter.Hides and ns.Filter.Hides(words) then words = L.FILTER_WORDS_HIDDEN_SHORT end
			if r.kind == "P" then words = L.CARRY_PARDON:format(When(r.at))
			elseif r.kind == "D" then words = L.CARRY_DUES:format(r.a, r.b, r.c) end
			lines[#lines + 1] = { text = L.CARRY_QUOTE .. ": " .. words, indent = 1 }
			lines[#lines + 1] = { text = L.CARRY_PROVENANCE:format(r.by, When(r.at), r.guild ~= "" and r.guild or L.CARRY_UNKNOWN,
				r.via ~= "" and r.via or e.subject), indent = 1, gapAfter = true }
		end
	end
	if #listed == 0 and next(offers) == nil and not Source(d) then lines[#lines + 1] = { text = L.CARRY_EMPTY } end
	return lines
end
function Carry.Slash(rest)
	local cmd, tail = (rest or ""):match("^(%S*)%s*(.-)$")
	local ok, why
	if cmd == "merger" then
		if ns.CarryMerger and ns.CarryMerger.Slash then ns.CarryMerger.Slash(tail) end
		return
	elseif cmd == "history" then
		local action, name = tail:match("^(%S*)%s*(.-)$")
		if action == "collect" then ok, why = ns.CarryHistory and ns.CarryHistory.Collect(name)
		elseif action == "key" then ok, why = ns.CarryHistory and ns.CarryHistory.RequestKey(name)
		elseif action == "staff" then ok, why = ns.CarryHistory and ns.CarryHistory.StaffConsent(name)
		else if ns.Views then ns.Views.ShowPage("carry") end; return end
	elseif cmd == "prepare" then ok, why = Carry.Prepare(tail)
	elseif cmd == "offer" then ok, why = Carry.Offer()
	elseif cmd == "cancel" then ok = Carry.Revoke()
	else if ns.Views then ns.Views.ShowPage("carry") end; return end
	if not ok then ns.Print(L.CARRY_REFUSED:format(why or "permission-or-stale")) end
end
StaticPopupDialogs.OLYMPUS_CARRY_PREPARE = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self) ns.SafeCall("carry prepare", Carry.Confirm, self.data) end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
StaticPopupDialogs.OLYMPUS_CARRY_ACCEPT = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self) local d = self.data; if d then ns.SafeCall("carry accept", Carry.Accept, d.key, d) end end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
table.insert(ns.RealmPages, { key = "carry", Link = function()
	if ns.IsMember() then return { text = "|cffffd200> " .. L.CARRY_TITLE .. "|r", onClick = function() ns.Views.ShowPage("carry") end } end
end, Lines = Carry.Lines, tip = "CARRY_TITLE" })
ns.Comm.Handle("XC", Carry.Handle)

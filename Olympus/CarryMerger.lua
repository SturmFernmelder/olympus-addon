local _, ns = ...

-- A named-heir mandate is permission for one CLOSED archive, not a portable guild office.
-- K/S/D accept directly while the source exists. Serving an approved frozen archive later
-- never reads a new source book, appoints anyone, applies a pardon or confirms a payment.
local M = {}
ns.CarryMerger = M
M.MAX, M.ROWS, M.PART, M.PARTS = 16, 256, 180, 34
M.PENDING, M.FLOORS, M.APPROVAL, M.LIFE, M.IDLE = 4, 128, 3600, 30 * 86400, 300
local assembling, outgoing, drafts, jobs = {}, {}, {}, 0
local Changed, Process, Dispatch, ValidPolicy
local function H() return ns.CarryHistory end
local function Clock() return math.floor((GetServerTime and GetServerTime()) or ns.Now()) end
local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function Whole(n) return type(n) == "number" and n == n and n >= 0 and n < 4294967296 and n % 1 == 0 end
local function Hex(s, n) return type(s) == "string" and #s == n and s:match("^%x+$") ~= nil end
local function Name(s)
	if type(s) ~= "string" or s == "" or #s > 72 or s:find("[|~^%c]") then return nil end
	local full = ns.FullName(ns.Normal(s)); return ns.RealmOf(full) and full or nil
end
local function Same(a, b) return Name(a) and Name(b) and ns.Fold(Name(a)) == ns.Fold(Name(b)) end
local function Scope() return tostring(ns.faction) .. ":" .. tostring(ns.group or ns.GroupOf(ns.realm)):lower() end
local function Sha(s) return ns.Ed25519.ToHex(ns.Sign.SHA256(s)) end
local function Preview() return ns.ViewAs and ns.ViewAs.Previewing and ns.ViewAs.Previewing() or ns.King and ns.King.Preview and ns.King.Preview() end
local function Fresh() return ns.IsMember() and ns.Roster and ns.Roster.Fresh and ns.Roster.Fresh() ~= nil end
local function Live(actor, scope)
	return Same(actor, ns.me) and scope == Scope() and Fresh() and not Preview()
		and not (ns.Moderation and ns.Moderation.SelfOff and ns.Moderation.SelfOff())
end
local function Master(name, guild)
	if not Name(name) or not H().GuildShape(guild) or not ns.IsFederation(guild) or Preview() then return false end
	if ns.WatchChat and ns.WatchChat.Barred and ns.WatchChat.Barred("powers", name) then return false end
	if ns.Moderation and ns.Moderation.Hides and ns.Moderation.Hides(name, guild) then return false end
	local rank, source = ns.Data.AuthorizedRank(name, guild)
	if guild == GetGuildInfo("player") then
		local nativeRank = select(3, GetGuildInfo("player"))
		return Fresh() and rank == 0 and source == "roster" and (not Same(name, ns.me) or nativeRank == 0)
	end
	return rank == 0 and (source == "signed" or source == "pinned")
end
local function King(name)
	-- FromKing's legacy census fallback is intentionally not a merger authorization.
	local pin, realm = ns.KingCharacter(), ns.KingRealm()
	return pin ~= nil and realm ~= nil and Same(name, ns.FullName(pin, realm)) and ns.IsKingCharacter(name) == true
end
local function OwnGuid()
	local guid = UnitGUID and UnitGUID("player")
	return type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) and guid or nil
end
local function Bound(name, guid)
	return Same(name, ns.me) and OwnGuid() == guid or ns.Debts.Bind(name, guid)
end
local function Store()
	if type(ns.db) ~= "table" or not Name(ns.me) then return nil end
	local root = ns.db.carryMerger
	if root == nil then root = { version = 1, scopes = {} }; ns.db.carryMerger = root end
	if type(root) ~= "table" or root.version ~= 1 or type(root.scopes) ~= "table" then return nil end
	local scope = Scope()
	if root.scopes[scope] == nil then if Count(root.scopes) >= 8 then return nil end; root.scopes[scope] = {} end
	local bucket = root.scopes[scope]; local who = ns.Fold(ns.me)
	if type(bucket) ~= "table" then return nil end
	if bucket[who] == nil then
		if Count(bucket) >= 32 then return nil end
		bucket[who] = { seq = 0, policies = {}, floors = {} }
	end
	local s = bucket[who]
	if type(s) ~= "table" or not Whole(s.seq) or type(s.policies) ~= "table" or type(s.floors) ~= "table" then return nil end
	if ValidPolicy then for id, p in pairs(s.policies) do if not Hex(id, 16) or not ValidPolicy(p, id) then return nil end end end
	return s
end
local function Guid(s) return type(s) == "string" and #s > 0 and #s <= 64 and not s:find("[^%w%-]") end
local function Body(data)
	return H().Payload(data)
end
function M.Parse(body)
	local d = type(body) == "string" and #body <= 1800 and H().ReadPayload(body)
	if not d or Count(d) ~= 14 or d.scope ~= Scope() or not Hex(d.id, 16) or not Hex(d.root, 64)
		or not H().GuildShape(d.source) or not H().GuildShape(d.destination) or d.source == d.destination
		or not Name(d.sourceMaster) or not Name(d.destinationMaster) or not Name(d.king)
		or Same(d.sourceMaster, d.destinationMaster) or not Guid(d.sourceGuid) or not Guid(d.destinationGuid) or not Guid(d.kingGuid) then return nil end
	d.count, d.created, d.expires = tonumber(d.count), tonumber(d.created), tonumber(d.expires)
	if not Whole(d.count) or d.count > M.ROWS or not Whole(d.created) or d.created > Clock() + 60
		or not Whole(d.expires) or d.expires ~= d.created + M.LIFE or Body(d) ~= body then return nil end
	return d
end
ValidPolicy = function(p, id)
	if type(p) ~= "table" or type(p.data) ~= "table" or not M.Parse(p.body) or p.data.id ~= id or Body(p.data) ~= p.body
		or not Whole(p.data.count) or not Whole(p.data.created) or not Whole(p.data.expires)
		or not Name(p.actor) or type(p.approvals) ~= "table" or type(p.index) ~= "table" or type(p.subjects) ~= "table"
		or type(p.consents) ~= "table" or type(p.requests) ~= "table" or type(p.imported) ~= "table"
		or p.pending ~= nil and type(p.pending) ~= "table" or p.consentFloors ~= nil and type(p.consentFloors) ~= "table" then return false end
	for _, a in pairs(p.approvals) do
		if type(a) ~= "table" or type(a.pk) ~= "string" or #a.pk ~= 43 or type(a.sig) ~= "string" or #a.sig ~= 86 or not Guid(a.guid) then return false end
	end
	for _, a in pairs(p.pending or {}) do if type(a) ~= "table" or not Name(a.sender) or type(a.pk) ~= "string" or type(a.sig) ~= "string" then return false end end
	for _, request in pairs(p.requests) do if type(request) ~= "table" or not Whole(request.at) or not Hex(request.nonce, 16) then return false end end
	if p.ownRequest and (type(p.ownRequest) ~= "table" or not Whole(p.ownRequest.at) or not Hex(p.ownRequest.nonce, 16)) then return false end
	for _, token in pairs(p.consents) do if type(token) ~= "table" or not Name(token.name) or not Guid(token.guid) or not Hex(token.nonce, 16) then return false end end
	for _, row in pairs(p.index) do if type(row) ~= "string" then return false end end
	for _, name in pairs(p.subjects) do if not Name(name) then return false end end
	for _, c in pairs(p.imported) do if type(c) ~= "table" or not H().Parse(c.text) then return false end end
	return true
end
local function Slot(d, role)
	if role == "S" then return d.sourceMaster, d.sourceGuid end
	if role == "D" then return d.destinationMaster, d.destinationGuid end
	if role == "K" then return d.king, d.kingGuid end
end
local function RoleNow(d, role, who)
	local name = Slot(d, role)
	if not Same(name, who) then return false end
	if role == "K" then return King(who) and (not Same(who, ns.me) or ns.King.IsKing()) end
	return Master(who, role == "S" and d.source or d.destination)
end
local function Participant(d)
	return Same(ns.me, d.sourceMaster) or Same(ns.me, d.destinationMaster) or Same(ns.me, d.king)
end
local function Approving(p)
	return p and not p.revoked and Live(p.actor, p.data.scope) and Participant(p.data)
		and Clock() <= p.data.created + M.APPROVAL and not p.approved
end
local function ApprovalLive(p)
	return p and not p.revoked and Live(p.actor, p.data.scope) and Participant(p.data) and Clock() <= p.data.created + M.APPROVAL
end
local function AllRoles(d)
	return RoleNow(d, "S", d.sourceMaster) and RoleNow(d, "D", d.destinationMaster) and RoleNow(d, "K", d.king)
end
local function Target(p)
	return p and not p.revoked and p.approved and not p.retired and Live(p.actor, p.data.scope)
		and Clock() <= p.data.expires and Same(ns.me, p.data.destinationMaster) and OwnGuid() == p.data.destinationGuid and Master(ns.me, p.data.destination)
end
local function Serving(p)
	return p and not p.revoked and p.approved and not p.retired and Live(p.actor, p.data.scope) and Clock() <= p.data.expires
		and Same(ns.me, p.data.sourceMaster) and OwnGuid() == p.data.sourceGuid and Master(p.data.destinationMaster, p.data.destination)
end
local function Run(fn, done)
	if jobs >= 4 or not ns.Ed25519 or not ns.Ed25519.Run then return false end
	jobs = jobs + 1
	local queued = ns.Ed25519.Run(fn, function(ok, result)
		jobs = jobs - 1; if done then done(ok and result or nil) end
	end)
	if not queued then jobs = jobs - 1 end
	return queued == true
end
local function Copy(c) return { text = c.text, pk = c.pk, sig = c.sig } end
local function Pack(c)
	if type(c) ~= "table" or not H().Parse(c.text) or type(c.pk) ~= "string" or #c.pk ~= 43 or type(c.sig) ~= "string" or #c.sig ~= 86 then return nil end
	return c.text .. "^" .. c.pk .. "^" .. c.sig
end
local function Capsule(text)
	local original, pk, sig = text:match("^(.*)%^([^%^]+)%^([^%^]+)$")
	local c = original and { text = original, pk = pk, sig = sig }
	return c and Pack(c) == text and c or nil
end
local function Index(capsules)
	local copied, rows, subjects = {}, {}, {}
	for i, c in ipairs(capsules) do copied[i] = Copy(c) end
	table.sort(copied, function(a, b) return Sha(Pack(a)) < Sha(Pack(b)) end)
	for i, c in ipairs(copied) do
		local r = H().Parse(c.text); local hash = Sha(Pack(c))
		if i > 1 and Sha(Pack(copied[i - 1])) == hash then return nil end
		rows[i] = Body({ hash = hash, subject = r.subject })
		subjects[ns.Fold(r.subject)] = r.subject
	end
	return rows, copied, subjects
end
local function Signed(role, body) return "OLYCM1~" .. role .. "~" .. body end
local function Split(text)
	local out = {}; for field in (text .. "^"):gmatch("(.-)%^") do out[#out + 1] = field end; return out
end
local function Key(sender, id, lane, page) return ns.Fold(Name(sender)) .. ":" .. id .. ":" .. lane .. ":" .. tostring(page) end
local function Send(to, msg, guard, done)
	return #msg <= 255 and ns.Comm.Whisper(to, msg, nil, nil, nil, done, { owner = M, guard = guard }) == true
end
local function SendData(to, id, lane, page, body, guard, done)
	-- A GM is also allowed to be a subject. His deliberate local confirmation does not
	-- depend on a native whisper echo (Comm correctly ignores those).
	if Same(to, ns.me) then
		if not guard() then return false end
		return Dispatch(ns.me, id, lane, page, body, function() if guard() and done then done(true) end end)
	end
	local key = Key(to, id, lane, page)
	if outgoing[key] or Count(outgoing) >= 4 or #body > M.PART * M.PARTS then return false end
	local t = { to = to, id = id, lane = lane, page = page, body = body, digest = Sha(body):sub(1, 16),
		actor = ns.me, scope = Scope(), at = Clock(), tries = 0 }
	outgoing[key] = t
	local function Current() return outgoing[key] == t and Live(t.actor, t.scope) and Clock() - t.at <= M.IDLE and guard() end
	local function Again()
		if not Current() then outgoing[key] = nil; if done then done(false) end; return false end
		t.tries = t.tries + 1
		if t.tries > 3 then outgoing[key] = nil; if done then done(false) end; return false end
		local n = math.ceil(#body / M.PART)
		if ns.Comm.QueueRoom and ns.Comm.QueueRoom() < n then outgoing[key] = nil; if done then done(false) end; return false end
		for i = 1, n do
			local after
			if i == n then after = function() ns.After(90, "merger acknowledgement", function() if outgoing[key] == t then Again() end end) end end
			if not Send(to, ("XC~3~D~%s~%s~%d~%d~%d~%s~%s"):format(id, lane, page, i, n, t.digest, body:sub((i - 1) * M.PART + 1, i * M.PART)), Current, after) then
				outgoing[key] = nil; if done then done(false) end; return false
			end
		end
		return true
	end
	t.done, t.current = done, Current; return Again()
end
local function SendApproval(p, role, approval)
	local payload = table.concat({ role, p.body, approval.pk, approval.sig }, "^")
	local targets, sent = {}, true
	for _, name in ipairs({ p.data.sourceMaster, p.data.destinationMaster, p.data.king }) do
		if not Same(name, ns.me) and not targets[ns.Fold(name)] then
			targets[ns.Fold(name)] = true
			local ok = SendData(name, p.data.id, "A", role == "S" and 1 or role == "D" and 2 or 3, payload,
				function() return ApprovalLive(p) and RoleNow(p.data, role, ns.me) end)
			sent = sent and ok
		end
	end
	return sent
end
local function Pin(name, guid, pk64)
	local pin = H().KeyPin(name)
	return pin and pin.guid == guid and pin.pk == pk64 and pin or nil
end
local function Complete(p)
	if p.approved or not Approving(p) or not AllRoles(p.data) then return false end
	if not p.approvals.S or not p.approvals.D or not p.approvals.K then return false end
	if Same(ns.me, p.data.destinationMaster) and not p.indexClosed then return false end
	p.approved, p.approvedAt = true, Clock(); Changed(); return true
end
local function TakeApproval(p, sender, role, pk64, sig64, done)
	local name, guid = Slot(p.data, role)
	local pin = name and Pin(name, guid, pk64)
	local pk, sig = ns.Ed25519.FromB64(pk64 or ""), ns.Ed25519.FromB64(sig64 or "")
	if not pin or not Same(sender, name) or not pk or #pk ~= 32 or not sig or #sig ~= 64 then return false end
	if p.approvals[role] then
		local same = p.approvals[role].pk == pk64 and p.approvals[role].sig == sig64
		if same and done then done(true) end; return same
	end
	if not Approving(p) or not RoleNow(p.data, role, sender) then return false end
	return Run(function() return ns.Ed25519.Verify(pk, Signed(role, p.body), sig) == true end, function(ok)
		if not ok or not Approving(p) or not RoleNow(p.data, role, sender) or not Pin(name, guid, pk64) then if done then done(false) end; return end
		p.approvals[role] = { pk = pk64, sig = sig64, guid = guid, at = Clock(), firsthand = true }
		Complete(p); Changed(); if done then done(true) end
	end)
end
local function SignOwn(p, role)
	if not Approving(p) or not RoleNow(p.data, role, ns.me) or role == "D" and not p.indexClosed then return false end
	local _, guid = Slot(p.data, role)
	if OwnGuid() ~= guid then return false end
	return Run(function()
		local _, pk = ns.Debts.MyKey(); if not pk then return nil end
		return { pk = ns.Ed25519.ToB64(pk), sig = ns.Ed25519.ToB64(ns.Debts.Sign(Signed(role, p.body))), guid = guid, at = Clock(), firsthand = true }
	end, function(a)
		if not a or not Approving(p) or OwnGuid() ~= guid or not RoleNow(p.data, role, ns.me) then return end
		p.approvals[role] = a
		SendApproval(p, role, a); Complete(p); Changed()
	end)
end
function M.Approve(id, role, confirmation)
	local s = Store(); local p = s and s.policies[id]
	if not Approving(p) or not RoleNow(p.data, role, ns.me) or role == "D" and not p.indexClosed then return false end
	if not confirmation then
		if not ns.Dialog or ns.Dialog.missing then return false end
		ns.Dialog.Show("OLYMPUS_MERGER_APPROVE", ns.L.MERGER_APPROVE:format(ns.L["MERGER_ROLE_" .. role], p.data.source, p.data.destination, p.data.count), nil, { id = id, role = role, policy = p })
		return true
	end
	if type(confirmation) ~= "table" or confirmation.policy ~= p or confirmation.id ~= id or confirmation.role ~= role then return false end
	return SignOwn(p, role)
end
function M.Prepare(destination)
	Process()
	for id, draft in pairs(drafts) do if Clock() > draft.data.created + M.APPROVAL or not Live(draft.actor, draft.data.scope) then drafts[id] = nil end end
	if Count(drafts) >= M.PENDING then return false, "draft-capacity" end
	destination = Name(destination)
	local source, actor = GetGuildInfo("player"), ns.me
	if not destination or not Live(actor, Scope()) or not Master(actor, source) then return false, "source-master" end
	local guild, rank, how = ns.Authority.Role(destination)
	if rank ~= 0 or how ~= "signed" or guild == source or not Master(destination, guild) then return false, "destination-master" end
	local king = ns.KingCharacter() and ns.KingRealm() and ns.FullName(ns.KingCharacter(), ns.KingRealm())
	if not king or not King(king) then return false, "king-pin" end
	local toPin = H().KeyPin(destination)
	local kingPin = Same(king, actor) and { guid = OwnGuid() } or H().KeyPin(king)
	if not toPin or not kingPin then
		if not toPin then H().RequestKey(destination) end
		if not kingPin then H().RequestKey(king) end
		return false, "firsthand-keys-pending"
	end
	local scope, guid = Scope(), OwnGuid()
	if not guid then return false, "native-guid" end
	return H().FreezeOwnSource(source, function(capsules, why)
		if not capsules or not Live(actor, scope) or not Master(actor, source) or GetGuildInfo("player") ~= source then ns.Print(ns.L.MERGER_REFUSED:format(why or "source-changed")); return end
		local index, frozen, subjects = Index(capsules)
		local s = Store(); if not index or not s or Count(s.policies) >= M.MAX or Count(s.floors) >= M.FLOORS or Count(drafts) >= M.PENDING then return end
		s.seq = s.seq + 1
		local d = { id = Sha(actor .. scope .. Clock() .. s.seq):sub(1, 16), scope = scope, source = source, sourceMaster = actor, sourceGuid = guid,
			destination = guild, destinationMaster = destination, destinationGuid = toPin.guid, king = king, kingGuid = kingPin.guid,
			root = Sha(table.concat(index, "^")), count = #index, created = Clock(), expires = Clock() + M.LIFE }
		local body = Body(d); if not M.Parse(body) then return end
		local p = { actor = actor, body = body, data = d, index = index, capsules = frozen, subjects = subjects,
			approvals = {}, consents = {}, requests = {}, imported = {}, indexClosed = true }
		drafts[d.id] = p
		ns.Dialog.Show("OLYMPUS_MERGER_PREPARE", ns.L.MERGER_PREPARE:format(source, guild, ns.DisplayName(destination), #index), nil, { policy = p })
	end)
end
function M.Confirm(confirmation)
	local p = type(confirmation) == "table" and confirmation.policy
	local s = Store()
	if not p or not s or drafts[p.data.id] ~= p or not Approving(p) or not Master(ns.me, p.data.source) or GetGuildInfo("player") ~= p.data.source
		or OwnGuid() ~= p.data.sourceGuid or Count(s.policies) >= M.MAX or s.floors[p.data.id] then return false end
	s.policies[p.data.id], drafts[p.data.id] = p, nil
	return SignOwn(p, "S")
end
local function SendIndex(p)
	if not p.approvals.S or not Same(ns.me, p.data.sourceMaster) or not Approving(p) then return false end
	local i = 0
	local function Next(ok)
		if ok == false or not Approving(p) or not RoleNow(p.data, "S", ns.me) then return end
		i = i + 1; if not p.index[i] then return end
		SendData(p.data.destinationMaster, p.data.id, "I", i, p.index[i], function() return Approving(p) and RoleNow(p.data, "S", ns.me) end, Next)
	end
	Next(); return true
end
local function NewPolicy(body, sender)
	local d, s = M.Parse(body), Store()
	if not d or not s or not Same(sender, d.sourceMaster) or not Participant(d) or not Live(ns.me, d.scope)
		or Clock() > d.created + M.APPROVAL or not RoleNow(d, "S", sender) or not AllRoles(d) or s.floors[d.id] then return nil end
	local p = s.policies[d.id]
	if p then return p.body == body and p or nil end
	local pending = 0; for _, old in pairs(s.policies) do if Approving(old) then pending = pending + 1 end end
	if Count(s.policies) >= M.MAX or pending >= M.PENDING then return nil end
	p = { actor = ns.me, body = body, data = d, approvals = {}, consents = {}, requests = {}, imported = {}, index = {}, subjects = {},
		indexClosed = d.count == 0 and d.root == Sha("") }
	s.policies[d.id] = p; Changed(); return p
end
local function ConsentText(p, name, guid, nonce) return "OLYCMC1~" .. p.data.scope .. "~" .. p.data.id .. "~" .. p.data.root .. "~" .. name .. "~" .. guid .. "~" .. nonce .. "~" .. p.data.destinationMaster .. "~" .. p.data.destinationGuid end
function M.RequestConsent(id, name)
	local s = Store(); local p = s and s.policies[id]; name = Name(name)
	if not Target(p) or Clock() > p.data.expires or not name or not p.subjects[ns.Fold(name)] then return false end
	if Count(p.requests) >= M.ROWS and not p.requests[ns.Fold(name)] then return false end
	s.seq = s.seq + 1
	local nonce = Sha(ns.me .. Clock() .. s.seq):sub(1, 16)
	p.requests[ns.Fold(name)] = { nonce = nonce, at = Clock(), name = name }
	local payload = p.body .. "^" .. nonce
	local guard = function() return Target(p) and p.requests[ns.Fold(name)].nonce == nonce and Clock() <= p.data.expires end
	-- The source independently expects the same solicited direct response. A destination
	-- cannot fabricate a subject consent by forwarding a self-signed arbitrary public key.
	return SendData(p.data.sourceMaster, id, "U", 1, Body({ subject = name, nonce = nonce }), guard, function(ok)
		if ok and guard() then SendData(name, id, "Q", 1, payload, guard) end
	end)
end
function M.Consent(id, confirmation)
	local s = Store(); local p = s and s.policies[id]; local request = p and p.ownRequest
	if not p or not request or request.withdrawn or not Live(p.actor, p.data.scope) or Clock() - request.at > M.IDLE or Clock() > p.data.expires
		or not Master(p.data.destinationMaster, p.data.destination) then return false end
	if not confirmation then
		ns.Dialog.Show("OLYMPUS_MERGER_CONSENT", ns.L.MERGER_CONSENT:format(p.data.source, ns.DisplayName(p.data.destinationMaster), p.data.destination), nil, { id = id, policy = p, request = request })
		return true
	end
	if type(confirmation) ~= "table" or confirmation.policy ~= p or confirmation.request ~= request or confirmation.id ~= id then return false end
	local guid, actor = OwnGuid(), ns.me; if not guid then return false end
	local text = ConsentText(p, actor, guid, request.nonce)
	return Run(function()
		local _, pk = ns.Debts.MyKey(); if not pk then return nil end
		return ns.Ed25519.ToB64(pk) .. "^" .. ns.Ed25519.ToB64(ns.Debts.Sign(text))
	end, function(a)
		if not a or not Live(actor, p.data.scope) or p.ownRequest ~= request or not Master(p.data.destinationMaster, p.data.destination) then return end
		for _, who in ipairs({ p.data.sourceMaster, p.data.destinationMaster }) do
			SendData(who, id, "C", 1, guid .. "^" .. request.nonce .. "^" .. a,
				function() return Live(actor, p.data.scope) and p.ownRequest == request and Clock() - request.at <= M.IDLE end)
		end
	end)
end
function M.Withdraw(id)
	local s = Store(); local p = s and s.policies[id]; local request = p and p.ownRequest
	if not request or not Live(p.actor, p.data.scope) or Clock() > p.data.expires then return false end
	local actor, guid = ns.me, OwnGuid(); if not guid then return false end
	local text = "OLYCMW1~" .. ConsentText(p, actor, guid, request.nonce)
	return Run(function()
		local _, pk = ns.Debts.MyKey()
		return pk and ns.Ed25519.ToB64(pk) .. "^" .. ns.Ed25519.ToB64(ns.Debts.Sign(text))
	end, function(a)
		if not a or not Live(actor, p.data.scope) or p.ownRequest ~= request then return end
		request.withdrawn = true
		for _, who in ipairs({ p.data.sourceMaster, p.data.destinationMaster }) do
			SendData(who, id, "V", 1, guid .. "^" .. request.nonce .. "^" .. a,
				function() return Live(actor, p.data.scope) and p.ownRequest == request end)
		end
		Changed()
	end)
end
local function SendSubject(p, subject, token)
	if not Serving(p) or not p.capsules then return false end
	local selected = {}
	for i, c in ipairs(p.capsules) do if Same(H().Parse(c.text).subject, subject) then selected[#selected + 1] = { page = i, capsule = c } end end
	local i = 0
	local function Next(ok)
		if ok == false or not Serving(p) or p.consents[ns.Fold(subject)] ~= token then return end
		i = i + 1; local row = selected[i]; if not row then return end
		SendData(p.data.destinationMaster, p.data.id, "T", row.page, Pack(row.capsule),
			function() return Serving(p) and p.consents[ns.Fold(subject)] == token end, Next)
	end
	Next(); return true
end
local function VerifyConsent(p, sender, guid, nonce, pk64, sig64, request, done)
	local pk, sig = ns.Ed25519.FromB64(pk64 or ""), ns.Ed25519.FromB64(sig64 or "")
	if not Guid(guid) or not Hex(nonce, 16) or not pk or #pk ~= 32 or not sig or #sig ~= 64 or not p.subjects[ns.Fold(sender)] then return false end
	-- Both keepers first hear the solicited subject response themselves. A forwarded public
	-- key and signature are not identity or consent evidence.
	if request and (request.nonce ~= nonce or Clock() - request.at > M.IDLE or not Bound(sender, guid)) then return false end
	return Run(function() return ns.Ed25519.Verify(pk, ConsentText(p, sender, guid, nonce), sig) == true end, function(ok)
		if not ok or p.revoked or Clock() > p.data.expires then if done then done(false) end; return end
		if p.consentFloors and p.consentFloors[ns.Fold(sender)] == nonce then if done then done(false) end; return end
		if request and (not (Target(p) or Serving(p)) or p.requests[ns.Fold(sender)] ~= request or Clock() - request.at > M.IDLE or not Bound(sender, guid)) then if done then done(false) end; return end
		if done then done(true) end
	end)
end
function M.Revoke(id)
	local s = Store(); local p = s and s.policies[id]
	if not p or p.revoked or not Live(p.actor, p.data.scope) or not Participant(p.data) then return false end
	local role = Same(ns.me, p.data.sourceMaster) and "S" or Same(ns.me, p.data.destinationMaster) and "D" or "K"
	local _, guid = Slot(p.data, role); if OwnGuid() ~= guid then return false end
	return Run(function()
		local _, pk = ns.Debts.MyKey(); return pk and { pk = ns.Ed25519.ToB64(pk), sig = ns.Ed25519.ToB64(ns.Debts.Sign("OLYCMR1~" .. role .. "~" .. p.body)) }
	end, function(a)
		if not a or not Live(p.actor, p.data.scope) then return end
		p.revoked, s.floors[id] = true, Sha(p.body)
		for _, who in ipairs({ p.data.sourceMaster, p.data.destinationMaster, p.data.king }) do if not Same(who, ns.me) then
			SendData(who, id, "R", 1, role .. "^" .. p.body .. "^" .. a.pk .. "^" .. a.sig, function() return Live(p.actor, p.data.scope) end)
		end end
		Changed()
	end)
end
Dispatch = function(sender, id, lane, page, payload, acknowledge)
	local s = Store(); local p = s and s.policies[id]
	if not s then return false end
	local f = Split(payload)
	if lane == "A" then
		local data = #f == 4 and M.Parse(f[2])
		if not data or data.id ~= id or not ({ S = true, D = true, K = true })[f[1]] then return false end
		if not p then if f[1] ~= "S" then return false end; p = NewPolicy(f[2], sender) end
		if not p or p.body ~= f[2] then return false end
		local role = f[1]
		if not Pin(Slot(p.data, role), select(2, Slot(p.data, role)), f[3]) then
			local name = Slot(p.data, role)
			if Same(sender, name) and RoleNow(p.data, role, sender) then p.pending = p.pending or {}; p.pending[role] = { sender = sender, pk = f[3], sig = f[4] }; H().RequestKey(sender); Changed() end
			return false
		end
		return TakeApproval(p, sender, role, f[3], f[4], function(ok)
			if not ok then acknowledge(false); return end
			if ok then acknowledge(); if role == "S" and Same(ns.me, p.data.destinationMaster) then
				Send(p.data.sourceMaster, "XC~3~I~" .. id, function() return Approving(p) end)
			end end
		end)
	elseif lane == "I" then
		if not p or not Approving(p) or not Same(sender, p.data.sourceMaster) or not Same(ns.me, p.data.destinationMaster)
			or not p.approvals.S or not RoleNow(p.data, "S", sender) or page < 1 or page > p.data.count then return false end
		local row = H().ReadPayload(payload)
		if not row or Count(row) ~= 2 or not Hex(row.hash, 64) or not Name(row.subject) then return false end
		if p.index[page] and p.index[page] ~= payload then p.revoked = true; s.floors[id] = Sha(p.body); return false end
		p.index[page], p.subjects[ns.Fold(row.subject)] = payload, row.subject
		local full = true; for i = 1, p.data.count do if not p.index[i] then full = false; break end end
		if full then
			if Sha(table.concat(p.index, "^")) ~= p.data.root then p.revoked = true; s.floors[id] = Sha(p.body); return false end
			p.indexClosed = true; Complete(p)
		end
		acknowledge(); Changed(); return true
	elseif lane == "Q" then
		local d = #f == 2 and M.Parse(f[1])
		if not d or d.id ~= id or not Hex(f[2], 16) or Clock() > d.expires or not Same(sender, d.destinationMaster) or not Master(sender, d.destination) then return false end
		if not p then
			if Count(s.policies) >= M.MAX or s.floors[id] then return false end
			p = { actor = ns.me, body = f[1], data = d, approvals = {}, consents = {}, requests = {}, imported = {}, index = {}, subjects = {}, subjectOnly = true }; s.policies[id] = p
		end
		if p.body ~= f[1] or p.revoked or p.ownRequest and p.ownRequest.nonce == f[2] and p.ownRequest.withdrawn then return false end
		p.ownRequest = { nonce = f[2], at = Clock() }; acknowledge(); Changed(); return true
	elseif lane == "C" then
		local request = p and p.requests[ns.Fold(sender)]
		if #f ~= 4 or not (Target(p) or Serving(p)) or not request then return false end
		return VerifyConsent(p, sender, f[1], f[2], f[3], f[4], request, function(ok)
			if not ok then acknowledge(false); return end
			local token = { name = sender, guid = f[1], nonce = f[2], pk = f[3], sig = f[4], at = Clock(), firsthand = true }
			p.consents[ns.Fold(sender)] = token
			if Serving(p) and request.ready then SendSubject(p, sender, token)
			elseif Target(p) then
				-- Delivery is released only after both ends verified the subject themselves.
				-- This is a readiness acknowledgement, never a forwarded identity proof.
				SendData(p.data.sourceMaster, id, "G", 1, Body({ subject = sender, nonce = f[2] }), function() return Target(p) and p.consents[ns.Fold(sender)] == token end)
			end
			acknowledge(); Changed()
		end)
	elseif lane == "G" then
		local data = H().ReadPayload(payload)
		local request = data and p and p.requests[ns.Fold(data.subject or "")]
		if not data or Count(data) ~= 2 or not Serving(p) or not Same(sender, p.data.destinationMaster) or not request or request.nonce ~= data.nonce then return false end
		request.ready = true
		local token = p.consents[ns.Fold(data.subject)]
		if token and token.nonce == data.nonce then SendSubject(p, data.subject, token) end
		acknowledge(); return true
	elseif lane == "V" then
		local request = p and p.requests[ns.Fold(sender)]
		local pk, sig = ns.Ed25519.FromB64(f[3] or ""), ns.Ed25519.FromB64(f[4] or "")
		if #f ~= 4 or not (Target(p) or Serving(p)) or not request or request.nonce ~= f[2] or not Guid(f[1])
			or not pk or #pk ~= 32 or not sig or #sig ~= 64 or not Bound(sender, f[1]) then return false end
		return Run(function() return ns.Ed25519.Verify(pk, "OLYCMW1~" .. ConsentText(p, sender, f[1], f[2]), sig) == true end, function(ok)
			if not ok or not (Target(p) or Serving(p)) or p.requests[ns.Fold(sender)] ~= request or not Bound(sender, f[1]) then acknowledge(false); return end
			local token = p.consents[ns.Fold(sender)]
			if token and (token.pk ~= f[3] or token.guid ~= f[1]) then acknowledge(false); return end
			p.consentFloors = p.consentFloors or {}; p.consentFloors[ns.Fold(sender)] = f[2]
			p.consents[ns.Fold(sender)] = nil
			for cursor, c in pairs(p.imported) do if Same(H().Parse(c.text).subject, sender) then p.imported[cursor] = nil end end
			acknowledge(); Changed()
		end)
	elseif lane == "U" then
		local token = H().ReadPayload(payload)
		if not token or Count(token) ~= 2 or not Serving(p) or not Same(sender, p.data.destinationMaster) or not Name(token.subject)
			or not Hex(token.nonce, 16) or not p.subjects[ns.Fold(token.subject)] then return false end
		p.requests[ns.Fold(token.subject)] = { nonce = token.nonce, at = Clock(), name = token.subject }
		acknowledge(); return true
	elseif lane == "T" then
		if not Target(p) or not Same(sender, p.data.sourceMaster) or not p.indexClosed or page < 1 or page > p.data.count then return false end
		local c, row = Capsule(payload), H().ReadPayload(p.index[page])
		local r = c and H().Parse(c.text); local token = r and p.consents[ns.Fold(r.subject)]
		if not r or not row or not token or not Same(r.subject, row.subject) or not Same(r.issuer, p.data.sourceMaster)
			or r.guid ~= p.data.sourceGuid or r.guild ~= p.data.source or Sha(payload) ~= row.hash then return false end
		local pin = p.approvals.S
		local pk, sig = ns.Ed25519.FromB64(c.pk), ns.Ed25519.FromB64(c.sig)
		if not pin or pin.pk ~= c.pk or not pk or #pk ~= 32 or not sig or #sig ~= 64 then return false end
		return Run(function() return ns.Ed25519.Verify(pk, c.text, sig) == true end, function(ok)
			if not ok or not Target(p) or p.consents[ns.Fold(r.subject)] ~= token then acknowledge(false); return end
			p.imported[page] = Copy(c); acknowledge(); Changed()
		end)
	elseif lane == "R" then
		local d = #f == 4 and M.Parse(f[2])
		if not d or d.id ~= id or p and f[2] ~= p.body or not Participant(d) then return false end
		-- A signed cancellation may arrive before its proposal. Only a currently verified
		-- participant with a firsthand native identity can reserve this bounded tombstone.
		if not p and (not RoleNow(d, f[1], sender) or Count(s.floors) >= M.FLOORS) then return false end
		local who, guid = Slot(d, f[1]); local pin = who and Pin(who, guid, f[3])
		local pk, sig = ns.Ed25519.FromB64(f[3]), ns.Ed25519.FromB64(f[4])
		if not pin or not Same(sender, who) or not pk or #pk ~= 32 or not sig or #sig ~= 64 then return false end
		return Run(function() return ns.Ed25519.Verify(pk, "OLYCMR1~" .. f[1] .. "~" .. f[2], sig) == true end, function(ok)
			if ok and Live(ns.me, d.scope) and Pin(who, guid, f[3]) and (p or RoleNow(d, f[1], sender)) then
				if p then p.revoked = true end
				s.floors[id] = Sha(f[2]); acknowledge(); Changed()
			else acknowledge(false) end
		end)
	end
	return false
end
function M.Handle(dist, sender, text)
	if dist ~= "WHISPER" or not Name(sender) or type(text) ~= "string" or #text > 255 or not Live(ns.me, Scope()) then return false end
	Process()
	sender = Name(sender)
	local id = text:match("^XC~3~[DNI]~(%x+)"); if not Hex(id, 16) then return false end
	for key, a in pairs(assembling) do if Clock() - a.at > M.IDLE or a.actor ~= ns.me or a.scope ~= Scope() then assembling[key] = nil end end
	local s = Store(); if not s then return false end
	local p = s.policies[id]
	if text:sub(1, 7) == "XC~3~I~" then
		return p and Same(sender, p.data.destinationMaster) and SendIndex(p) or false
	end
	if text:sub(1, 7) == "XC~3~N~" then
		local lane, page, digest = text:match("^XC~3~N~%x+~([A-Z])~(%d+)~(%x+)$")
		page = tonumber(page); if not lane or not Whole(page) then return false end
		local key = Key(sender, id, lane, page); local t = outgoing[key]
		if not t or digest ~= t.digest or not t.current() then return false end
		outgoing[key] = nil; if t.done then t.done(true) end; return true
	end
	local lane, page, part, n, digest, fragment = text:match("^XC~3~D~%x+~([A-Z])~(%d+)~(%d+)~(%d+)~(%x+)~(.*)$")
	page, part, n = tonumber(page), tonumber(part), tonumber(n)
	if not ({ A = true, I = true, Q = true, C = true, U = true, G = true, T = true, R = true, V = true })[lane or ""] or not Whole(page) or page < 1 or page > M.ROWS
		or not Whole(part) or part < 1 or not Whole(n) or n < part or n > M.PARTS or not Hex(digest, 16) or #fragment > M.PART then return false end
	if s.floors[id] and lane ~= "R" then return false end
	local key = Key(sender, id, lane, page); local a = assembling[key]
	if not a then
		if Count(assembling) >= 8 then return false end
		local peer = 0; for _, old in pairs(assembling) do if Same(old.sender, sender) then peer = peer + 1 end end
		if peer >= 2 then return false end
		a = { actor = ns.me, scope = Scope(), sender = sender, at = Clock(), n = n, digest = digest, parts = {} }; assembling[key] = a
	end
	if a.n ~= n or a.digest ~= digest or a.parts[part] and a.parts[part] ~= fragment then assembling[key] = nil; return false end
	a.parts[part] = fragment
	for i = 1, n do if not a.parts[i] then return true end end
	local payload = table.concat(a.parts); if Sha(payload):sub(1, 16) ~= digest then assembling[key] = nil; return false end
	if a.verifying then return true end
	a.verifying = true
	local function Ack(ok)
		if ok == false then if assembling[key] == a then assembling[key] = nil end; return end
		if assembling[key] ~= a or not Live(a.actor, a.scope) then return end
		a.verifying = nil; a.complete = true
		Send(sender, ("XC~3~N~%s~%s~%d~%s"):format(id, lane, page, digest), function() return Live(a.actor, a.scope) end,
			function(sent) if sent and assembling[key] == a then assembling[key] = nil end end)
	end
	local ok = Dispatch(sender, id, lane, page, payload, Ack)
	if not ok then a.verifying = nil; assembling[key] = nil end
	return ok
end
Changed = function() ns.Fire("MERGER_HISTORY_CHANGED"); ns.Fire("HISTORY_CARRY_CHANGED") end
Process = function()
	local s = Store(); if not s then return end
	for id, p in pairs(s.policies) do
		if (not p.approved and Clock() > p.data.created + M.APPROVAL) or Clock() > p.data.expires then
			if s.floors[id] or Count(s.floors) < M.FLOORS then s.floors[id] = Sha(p.body); s.policies[id] = nil end
			p.revoked = true
		end
		if p.approved and Same(ns.me, p.data.destinationMaster) and Fresh() then
			local guild, _, native = GetGuildInfo("player")
			if guild ~= p.data.destination or type(native) == "number" and native ~= 0 or ns.Roster.RankOf(ns.me) ~= 0 then p.retired = true end
		end
		for role, a in pairs(p.pending or {}) do if Approving(p) and Pin(Slot(p.data, role), select(2, Slot(p.data, role)), a.pk) then
			p.pending[role] = nil; TakeApproval(p, a.sender, role, a.pk, a.sig, function(ok)
				if ok and role == "S" and Same(ns.me, p.data.destinationMaster) then
					Send(p.data.sourceMaster, "XC~3~I~" .. id, function() return Approving(p) end)
				end
			end)
		end end
	end
end
ns.On("HISTORY_CARRY_CHANGED", Process)
function M.Policies()
	Process(); local out, s = {}, Store()
	for _, p in pairs(s and s.policies or {}) do if Live(p.actor, p.data.scope) and (Participant(p.data) or p.subjectOnly) then out[#out + 1] = p end end
	table.sort(out, function(a, b) return a.data.id < b.data.id end); return out
end
function M.Archives()
	local out = {}
	for _, p in ipairs(M.Policies()) do if Target(p) then for _, c in pairs(p.imported) do out[#out + 1] = Copy(c) end end end
	return out
end
function M.Lines()
	local L, lines = ns.L, { { header = true, text = ns.L.MERGER_TITLE }, { text = ns.L.MERGER_NOTE, gapAfter = true } }
	for _, p in ipairs(M.Policies()) do
		local id = p.data.id
		lines[#lines + 1] = { header = true, text = L.MERGER_ROW:format(p.data.source, p.data.destination, p.data.count, id) }
		for _, role in ipairs({ "S", "D", "K" }) do
			lines[#lines + 1] = { text = L.MERGER_ROLE:format(L["MERGER_ROLE_" .. role], p.approvals[role] and L.MERGER_YES or L.MERGER_WAIT), indent = 1 }
			if Approving(p) and RoleNow(p.data, role, ns.me) and not p.approvals[role] then local r = role
				lines[#lines + 1] = { text = L.MERGER_REVIEW, onClick = function() M.Approve(id, r) end, indent = 1 }
			end
		end
		if Target(p) then for _, name in pairs(p.subjects) do local who = name
			if not p.consents[ns.Fold(name)] then lines[#lines + 1] = { text = L.MERGER_ASK:format(ns.DisplayName(name)), onClick = function() M.RequestConsent(id, who) end, indent = 1 } end
		end end
		if p.ownRequest and not p.revoked then
			if not p.ownRequest.withdrawn then
				lines[#lines + 1] = { text = L.MERGER_CONSENT_BUTTON, onClick = function() M.Consent(id) end }
				lines[#lines + 1] = { text = L.MERGER_WITHDRAW, onClick = function() M.Withdraw(id) end }
			end
		end
		if p.revoked or p.retired then lines[#lines + 1] = { text = L.MERGER_REVOKED }
		elseif Participant(p.data) then lines[#lines + 1] = { text = L.MERGER_CANCEL, onClick = function() M.Revoke(id) end } end
	end
	for _, c in ipairs(M.Archives()) do local r = H().Parse(c.text)
		local words = r.fields.words or r.fields.expires or r.fields.copper or ""
		if not (ns.Filter and ns.Filter.Hides and ns.Filter.Hides(words)) then
			lines[#lines + 1] = { text = L.MERGER_RECORD:format(r.kind, ns.DisplayName(r.subject), ns.DisplayName(r.issuer), r.guild, words), indent = 1 }
		end
	end
	return lines
end
function M.Slash(tail)
	local cmd, value = (tail or ""):match("^(%S*)%s*(.-)$")
	local ok, why
	if cmd == "prepare" then ok, why = M.Prepare(value)
	elseif cmd == "consent" then ok = M.Consent(value)
	elseif cmd == "cancel" then ok = M.Revoke(value)
	elseif cmd == "withdraw" then ok = M.Withdraw(value)
	else if ns.Views then ns.Views.ShowPage("carry") end; return end
	if not ok then ns.Print(ns.L.MERGER_REFUSED:format(why or "permission-or-stale")) end
end
StaticPopupDialogs.OLYMPUS_MERGER_PREPARE = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self) ns.SafeCall("merger prepare", M.Confirm, self.data) end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
StaticPopupDialogs.OLYMPUS_MERGER_APPROVE = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self) local d = self.data; if d then ns.SafeCall("merger approve", M.Approve, d.id, d.role, d) end end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
StaticPopupDialogs.OLYMPUS_MERGER_CONSENT = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self) local d = self.data; if d then ns.SafeCall("merger consent", M.Consent, d.id, d) end end,
	timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }

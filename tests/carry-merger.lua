local base, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]carry%-merger%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = base })
local function LoadClient(w, c)
	w:As(c, function()
		c.ns.Roster = { Fresh = function() return c.fresh ~= false and {} or nil end,
			RankOf = function(name) for _, other in ipairs(w.clients) do if name == other.name and other.guild == c.guild then return other.rank end end end }
		-- These verdicts model a fresh native roster and verified signed foreign authority,
		-- not cryptography. The production Ed25519 signing/verification and native GUID
		-- binding run below, with different account keys and isolated clients.
		c.ns.Data = { AuthorizedRank = function(name, guild)
			for _, other in ipairs(w.clients) do if name == other.name and other.guild == guild then
				if guild == c.guild then return other.rank, "roster" end
				if other.rank == 0 then return other.rank, c.peerSource or "signed" end
			end end
		end }
		c.ns.Authority = { Role = function(name)
			for _, other in ipairs(w.clients) do if name == other.name and other.rank == 0 then return other.guild, 0, c.peerSource or "signed" end end
		end }
		c.ns.ViewAs = { Previewing = function() return false end }
		c.ns.Dialog = { Show = function(_, _, _, data) c.question = data; return true end }
		c.ns.RealmPages = {}
		assert(loadfile(ROOT .. "Olympus/Locales/CarryText.lua"))("Olympus", c.ns)
		assert(loadfile(ROOT .. "Olympus/Locales/CarryMergerText.lua"))("Olympus", c.ns)
		assert(loadfile(ROOT .. "Olympus/CarryHistory.lua"))("Olympus", c.ns)
		assert(loadfile(ROOT .. "Olympus/Carry.lua"))("Olympus", c.ns)
		assert(loadfile(ROOT .. "Olympus/CarryMerger.lua"))("Olympus", c.ns)
	end)
end
local function Setup()
	local w = World.New({ council = false, compliance = "shipped", arenaFiles = { "ArenaMath", "ArenaNet", "ArenaMoney", "Debts" } })
	local king, member = w:Role("king"), w:Role("fighterA")
	local dest = w:Role("fighterB", { rank = 0, guild = "Olympus II" })
	local source = w:Client("Source Warden-Emberfall", { rank = 0, guild = member.guild })
	for _, c in ipairs({ king, member, dest, source }) do LoadClient(w, c) end
	w:Group({ king.name, member.name, dest.name, source.name })
	for _, c in ipairs({ king, dest, source }) do w:As(c, function()
		for _, other in ipairs({ king, dest, source }) do if other ~= c then assert(c.ns.CarryHistory.RequestKey(other.name)) end end
	end) end
	w:Run(6)
	for _, c in ipairs({ king, dest, source }) do w:As(c, function()
		for _, other in ipairs({ king, dest, source }) do if other ~= c then assert(c.ns.CarryHistory.KeyPin(other.name), "firsthand public pin " .. c.name .. " -> " .. other.name) end end
	end) end
	return w, king, member, dest, source
end
local function Notes(w, source, member, count)
	for i = 1, count or 1 do
		w:As(source, function()
			assert(source.ns.CarryHistory.CaptureOriginal("L", member.name, "note-" .. i, w.clock, source.guild,
				{ writer = source.name, words = "PRIVATE LOOT " .. i .. string.rep(" x", 110), to = member.name }))
		end)
		if i % 3 == 0 then w:Run(2) end
	end
	w:Run(2)
end
local function Prepare(w, source, dest)
	w:As(source, function() assert(source.ns.CarryMerger.Prepare(dest.name)) end); w:Run(3)
	local id = assert(source.question and source.question.policy).data.id
	w:As(source, function() assert(source.ns.CarryMerger.Confirm(source.question)) end); w:Run(8)
	return id
end
local function Approve(w, c, id, role)
	w:As(c, function()
		assert(c.ns.CarryMerger.Approve(id, role)); eq(c.ns.CarryMerger.Approve(id, role, true), false, "forged confirmation boolean")
		assert(c.ns.CarryMerger.Approve(id, role, c.question))
	end); w:Run(5)
end
local function Approved(w, king, dest, source)
	local id = Prepare(w, source, dest)
	Approve(w, dest, id, "D"); Approve(w, king, id, "K")
	for _, c in ipairs({ king, dest, source }) do w:As(c, function()
		local p = c.ns.CarryMerger.Policies()[1]; assert(p and p.approved, "all three clients receive the final approval: " .. c.name)
		for _, role in ipairs({ "S", "D", "K" }) do
			local a = p.approvals[role]; assert(a and a.firsthand)
			assert(c.ns.Ed25519.Verify(c.ns.Ed25519.FromB64(a.pk), "OLYCM1~" .. role .. "~" .. p.body, c.ns.Ed25519.FromB64(a.sig)), "actual role-specific Ed signature")
		end
	end) end
	return id
end
local function Consent(w, member, dest, id)
	w:As(dest, function() assert(dest.ns.CarryMerger.RequestConsent(id, member.name)) end); w:Run(3)
	w:As(member, function()
		assert(member.ns.CarryMerger.Consent(id)); eq(member.ns.CarryMerger.Consent(id, true), false)
		assert(member.ns.CarryMerger.Consent(id, member.question))
	end); w:Run(20)
end
local function Errors(w)
	for _, c in ipairs(w.clients) do eq(#w:Errors(c), 0, c.name .. ": " .. table.concat(w:Errors(c), "\n")) end
end

test("carry-merger: same SHA256 manifest receives three firsthand actual signatures; private records require individual direct consent and never import status", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member, 12)
	local id = Approved(w, king, dest, source)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0, "three offices cannot bypass each subject") end)
	Consent(w, member, dest, id)
	w:As(dest, function()
		local all = dest.ns.CarryMerger.Archives(); eq(#all, 12)
		for _, c in ipairs(all) do local r = dest.ns.CarryHistory.Parse(c.text); eq(r.issuer, source.name); eq(r.subject, member.name); eq(r.guild, source.guild) end
		local lines = dest.ns.Carry.Lines(); assert(#lines > 20, "real Carry UI exposes archive and confirmations")
		eq(dest.ns.rdb.pardons, nil); eq(dest.ns.rdb.dues, nil); eq(dest.ns.rdb.loot, nil)
	end)
	local fragments, acks, directSource, directDest = 0, 0, false, false
	for _, m in ipairs(w.sent) do if m.msg:sub(1, 5) == "XC~3~" then
		eq(m.dist, "WHISPER"); assert(#m.msg <= 255)
		if m.msg:find("~T~", 1, true) and m.from == source.name then eq(m.target, dest.name); fragments = fragments + 1 end
		if m.msg:find("~T~", 1, true) and m.from == dest.name then acks = acks + 1 end
		if m.from == member.name and m.msg:find("~C~", 1, true) then if m.target == source.name then directSource = true elseif m.target == dest.name then directDest = true end end
		if m.target == member.name or m.target == king.name then assert(not m.msg:find("PRIVATE LOOT", 1, true), "private plaintext is never broadcast or sent to subject/King") end
	end end
	assert(fragments > 34, "bounded pages still carry an archive above 34 messages"); eq(acks, 12); assert(directSource and directDest)
	Errors(w)
end)

test("carry-merger: approved source keeper can later serve from another Olympus guild; historical guild labels survive its removal but no new facts enter frozen root", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local former = source.guild; local id = Approved(w, king, dest, source)
	w:As(source, function()
		assert(source.ns.CarryHistory.CaptureOriginal("L", member.name, "after-freeze", w.clock, former, { writer = source.name, words = "NOT IN FROZEN MANIFEST", to = member.name }))
	end); w:Run(2)
	source.guild, member.guild = "Olympus Refuge", dest.guild
	for _, c in ipairs(w.clients) do local original = c.ns.IsFederation; c.ns.IsFederation = function(guild) return guild ~= former and original(guild) end end
	Consent(w, member, dest, id)
	w:As(dest, function() local all = dest.ns.CarryMerger.Archives(); eq(#all, 1); eq(dest.ns.CarryHistory.Parse(all[1].text).guild, former) end)
	for _, m in ipairs(w.sent) do assert(not m.msg:find("NOT IN FROZEN", 1, true)) end
	Errors(w)
end)

test("carry-merger: incomplete mandate cannot invent historical source authority after dissolution; preview/census/unknown King realm never approve", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	w:As(source, function()
		source.peerSource = "census"; eq(source.ns.CarryMerger.Prepare(dest.name), false); source.peerSource = nil
		local pin = source.ns.KingRealm; source.ns.KingRealm = function() return nil end; eq(source.ns.CarryMerger.Prepare(dest.name), false); source.ns.KingRealm = pin
		source.ns.ViewAs.Previewing = function() return true end; eq(source.ns.CarryMerger.Prepare(dest.name), false); source.ns.ViewAs.Previewing = function() return false end
	end)
	local id = Prepare(w, source, dest); Approve(w, dest, id, "D")
	source.guild = "Olympus Refuge"
	Approve(w, king, id, "K")
	w:As(dest, function()
		eq(dest.ns.CarryMerger.Policies()[1].approved, nil); eq(dest.ns.CarryMerger.RequestConsent(id, member.name), false); eq(#dest.ns.CarryMerger.Archives(), 0)
	end)
	Errors(w)
end)

test("carry-merger: subject withdrawal cancels queued and retained records; replayed consent and another GM cannot resurrect permission", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local id = Approved(w, king, dest, source); Consent(w, member, dest, id)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1) end)
	local replay = {}; for _, m in ipairs(w.sent) do if m.from == member.name and m.target == dest.name and m.msg:find("~C~", 1, true) then replay[#replay + 1] = m.msg end end
	w:As(member, function() assert(member.ns.CarryMerger.Withdraw(id)) end); w:Run(5)
	w:As(dest, function()
		eq(#dest.ns.CarryMerger.Archives(), 0)
		for _, msg in ipairs(replay) do dest.ns.Carry.Handle("WHISPER", member.name, msg) end
	end); w:Run(3)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0); dest.rank = 1; eq(#dest.ns.CarryMerger.Archives(), 0); dest.rank = 0; eq(dest.ns.CarryMerger.RequestConsent(id, member.name), false) end)
	Errors(w)
end)

test("carry-merger: revocation is signed and durable even before a delayed source proposal; public and outsider routing cannot activate it", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local id = Prepare(w, source, dest)
	local proposal = {}; for _, m in ipairs(w.sent) do if m.from == source.name and m.target == dest.name and m.msg:find("~A~1~", 1, true) then proposal[#proposal + 1] = m.msg end end
	assert(#proposal > 1)
	-- Forget only the destination's not-yet-approved proposal to model revocation arriving first.
	w:As(dest, function() for _, bucket in pairs(dest.ns.db.carryMerger.scopes) do bucket[dest.ns.Fold(dest.name)].policies[id] = nil end end)
	w:As(source, function() assert(source.ns.CarryMerger.Revoke(id)) end); w:Run(6)
	w:As(dest, function()
		for _, m in ipairs(proposal) do eq(dest.ns.Carry.Handle("WHISPER", source.name, m), false, "cancel-before-proposal floor") end
		eq(dest.ns.Carry.Handle("CHANNEL", source.name, proposal[1]), false)
		dest.guild = "Unrelated Guild"; eq(dest.ns.Carry.Handle("WHISPER", source.name, proposal[1]), false)
	end)
	Errors(w)
end)

test("carry-merger: a source-GM subject explicitly consents without relying on a whisper to himself", function()
	local w, king, _, dest, source = Setup(); Notes(w, source, source)
	local id = Approved(w, king, dest, source); Consent(w, source, dest, id)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1) end); Errors(w)
end)

test("carry-merger: an alt may consent only through a current explicit Olympus Link pair and provenance remains on the original subject", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local delegate = w:Client("Linked Delegate-Emberfall", { rank = 3, guild = member.guild })
	LoadClient(w, delegate)
	w:Group({ king.name, member.name, dest.name, source.name, delegate.name })
	local id = Approved(w, king, dest, source)
	for _, c in ipairs({ source, dest, delegate }) do
		c.ns.Alts = { Linked = function() return { member.name, delegate.name } end }
	end
	w:As(dest, function()
		eq(dest.ns.CarryMerger.RequestConsent(id, member.name, delegate.name), false,
			"legacy alt lists are not identity or subject consent")
	end)
	local proof = { version = 1, id = string.rep("a", 32), issued = w.clock - 10,
		expires = w.clock + 3600, revision = 1, bothConsented = true }
	for _, c in ipairs({ source, dest, delegate }) do c.ns.LinkIdentity = { VerifiedPair = function(a, b)
		if c.ns.Fold(a) == c.ns.Fold(member.name) and c.ns.Fold(b) == c.ns.Fold(delegate.name) then return proof end
	end } end
	w:As(dest, function() assert(dest.ns.CarryMerger.RequestConsent(id, member.name, delegate.name)) end); w:Run(3)
	w:As(delegate, function()
		assert(delegate.ns.CarryMerger.Consent(id)); assert(delegate.ns.CarryMerger.Consent(id, delegate.question))
	end); w:Run(20)
	w:As(dest, function()
		local all = dest.ns.CarryMerger.Archives(); eq(#all, 1)
		local record = dest.ns.CarryHistory.Parse(all[1].text)
		eq(record.subject, member.name); eq(record.issuer, source.name)
		local token = dest.ns.CarryMerger.Policies()[1].consents[dest.ns.Fold(member.name)]
		eq(token.name, member.name); eq(token.signer, delegate.name); eq(token.identityId, proof.id)
		proof.expires = w.clock - 1
		eq(dest.ns.CarryMerger.Resume(id, member.name), false, "expired Link identity cannot authorize more transport")
	end)
	Errors(w)
end)

local function Wire(w, c, sender, id, lane, page, payload)
	w:As(c, function()
		local digest = c.ns.Ed25519.ToHex(c.ns.Sign.SHA256(payload)):sub(1, 16)
		local parts = math.ceil(#payload / c.ns.CarryMerger.PART)
		for part = 1, parts do c.ns.Carry.Handle("WHISPER", sender, ("XC~3~D~%s~%s~%d~%d~%d~%s~%s"):format(id, lane, page, part, parts, digest,
			payload:sub((part - 1) * c.ns.CarryMerger.PART + 1, part * c.ns.CarryMerger.PART))) end
	end)
end
test("carry-merger: bad actual signature releases assembly for a corrected proof; forwarded consent under a GM's sender cannot impersonate the subject", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local id = Approved(w, king, dest, source)
	w:As(dest, function() assert(dest.ns.CarryMerger.RequestConsent(id, member.name)) end); w:Run(3)
	local payload
	w:As(member, function()
		local p = member.ns.CarryMerger.Policies()[1]; local nonce = p.ownRequest.nonce
		local text = "OLYCMC2~" .. p.data.scope .. "~" .. id .. "~" .. p.data.root .. "~" .. member.name .. "~" .. member.name
			.. "~" .. member.guid .. "~" .. nonce .. "~-~" .. dest.name .. "~" .. dest.guid
		member.ns.Ed25519.Run(function()
			local _, pk = member.ns.Debts.MyKey()
			return member.guid .. "^" .. nonce .. "^" .. member.ns.Ed25519.ToB64(pk) .. "^" .. member.ns.Ed25519.ToB64(member.ns.Debts.Sign(text))
				.. "^" .. member.name .. "^-"
		end, function(ok, result) if ok then payload = result end end)
	end); w:Run(3); assert(payload)
	Wire(w, dest, dest.name, id, "C", 1, payload); w:Run(2)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0); eq(dest.ns.CarryMerger.Policies()[1].consents[dest.ns.Fold(member.name)], nil) end)
	local altered = payload:sub(1, -2) .. (payload:sub(-1) == "A" and "B" or "A")
	Wire(w, source, member.name, id, "C", 1, altered); w:Run(2)
	Wire(w, source, member.name, id, "C", 1, payload); Wire(w, dest, member.name, id, "C", 1, payload); w:Run(20)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1) end); Errors(w)
end)

test("carry-merger: malformed saved scopes and policies fail unknown without throwing or using imported powers", function()
	local w, _, _, dest, source = Setup()
	w:As(dest, function()
		dest.ns.db.carryMerger = { version = 1, scopes = { ["Alliance:" .. dest.ns.group:lower()] = false } }
		eq(#dest.ns.CarryMerger.Policies(), 0)
		dest.ns.db.carryMerger = nil; dest.ns.CarryMerger.Policies()
		for _, bucket in pairs(dest.ns.db.carryMerger.scopes) do bucket[dest.ns.Fold(dest.name)].policies.aaaaaaaaaaaaaaaa = true end
		eq(#dest.ns.CarryMerger.Policies(), 0); eq(#dest.ns.CarryMerger.Archives(), 0)
	end)
	w:As(source, function()
		for _, scope in pairs(source.ns.db.carryHistory.scopes) do scope.characters[source.ns.Fold(source.name)].originals.corrupt = false end
		eq(source.ns.CarryHistory.FreezeOwnSource(source.guild), false, "malformed source book fails unknown")
	end); Errors(w)
end)

test("carry-merger: fresh but stale rank-zero roster cannot override live native self demotion at freeze or receiving callback", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local ownRank, ownData = source.ns.Roster.RankOf, source.ns.Data.AuthorizedRank
	source.ns.Roster.RankOf = function(name) if name == source.name then return 0 end; return ownRank(name) end
	source.ns.Data.AuthorizedRank = function(name, guild) if name == source.name and guild == source.guild then return 0, "roster" end; return ownData(name, guild) end
	source.rank = 1
	w:As(source, function()
		eq(source.ns.CarryMerger.Prepare(dest.name), false, "native rank wins over still-fresh completed roster")
		eq(source.ns.CarryHistory.FreezeOwnSource(source.guild), false)
	end)
	source.rank = 0
	local id = Approved(w, king, dest, source); Consent(w, member, dest, id)
	local destRank, destData = dest.ns.Roster.RankOf, dest.ns.Data.AuthorizedRank
	dest.ns.Roster.RankOf = function(name) if name == dest.name then return 0 end; return destRank(name) end
	dest.ns.Data.AuthorizedRank = function(name, guild) if name == dest.name and guild == dest.guild then return 0, "roster" end; return destData(name, guild) end
	dest.rank = 1
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0); eq(dest.ns.CarryMerger.RequestConsent(id, member.name), false) end)
	dest.rank = 0
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0, "reappointment cannot reopen the retired exact-recipient mandate") end)
	Errors(w)
end)

test("carry-merger: expired mandate forbids retained viewing and delayed record imports with old signatures and consents", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local id = Approved(w, king, dest, source); Consent(w, member, dest, id)
	local replay = {}; for _, m in ipairs(w.sent) do if m.from == source.name and m.target == dest.name and m.msg:find("~T~", 1, true) then replay[#replay + 1] = m.msg end end
	w.clock = w.clock + dest.ns.CarryMerger.LIFE + 1
	w:As(dest, function()
		eq(#dest.ns.CarryMerger.Archives(), 0)
		for _, msg in ipairs(replay) do eq(dest.ns.Carry.Handle("WHISPER", source.name, msg), false) end
		eq(dest.ns.CarryMerger.RequestConsent(id, member.name), false)
	end); Errors(w)
end)

test("carry-merger: missing original key defers approval until a solicited native response then recovers the exact closed index", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	w:As(dest, function()
		for _, scope in pairs(dest.ns.db.carryHistory.scopes) do scope.characters[dest.ns.Fold(dest.name)].keys[dest.ns.Fold(source.name)] = nil end
	end)
	local id = Prepare(w, source, dest)
	w:As(dest, function()
		local p = dest.ns.CarryMerger.Policies()[1]; assert(p.approvals.S and p.indexClosed, "original direct key response resumes rather than promotes the forwarded signature")
		assert(dest.ns.CarryHistory.KeyPin(source.name))
	end)
	Approve(w, dest, id, "D"); Approve(w, king, id, "K"); Consent(w, member, dest, id)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1) end); Errors(w)
end)

test("carry-merger: lost frozen-record fragment is retried under the same guarded cursor and acknowledged only after complete verification", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local id = Approved(w, king, dest, source)
	w:As(dest, function() assert(dest.ns.CarryMerger.RequestConsent(id, member.name)) end); w:Run(3)
	w:Results(source, { 0, 0, 2 }) -- direct-consent ACK, first record fragment, missing fragment
	w:As(member, function() assert(member.ns.CarryMerger.Consent(id)); assert(member.ns.CarryMerger.Consent(id, member.question)) end)
	w:Run(15)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0, "partial record cannot be imported") end)
	w:Run(100)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1, "validated same-page retry finishes") end)
	local ack = false; for _, m in ipairs(w.sent) do if m.from == dest.name and m.msg:find("XC~3~N~" .. id .. "~T~", 1, true) then ack = true end end
	assert(ack); Errors(w)
end)

test("carry-merger: unanswered drafts are bounded and expired pending policies release their slots without reviving old nonces", function()
	local w, _, _, dest, source = Setup()
	for _ = 1, source.ns.CarryMerger.PENDING do
		w:As(source, function() assert(source.ns.CarryMerger.Prepare(dest.name)) end); w:Run(2)
	end
	w:As(source, function() eq(source.ns.CarryMerger.Prepare(dest.name), false, "unanswered preparation cannot grow without bound") end)
	w.clock = w.clock + source.ns.CarryMerger.APPROVAL + 1
	local id = Prepare(w, source, dest)
	w.clock = w.clock + source.ns.CarryMerger.APPROVAL + 1
	w:As(source, function() eq(#source.ns.CarryMerger.Policies(), 0, "expired policy is removed after reserving its replay floor") end)
	local replacement = Prepare(w, source, dest); assert(replacement ~= id)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Policies(), 1, "receiving new packets prunes expired pending slots too") end)
	Errors(w)
end)

test("carry-merger: old unsigned private notes are visibly present witness quotes, never forged old authors or dates", function()
	local w, king, member, dest, source = Setup()
	source.ns.Loot = { Notes = function() return { { key = "old-note", n = { writer = "Previous Officer-Emberfall", to = member.name,
		t = w.clock - 900, text = "OLDER UNSIGNED QUOTE" } } } end }
	local id = Approved(w, king, dest, source); Consent(w, member, dest, id)
	w:As(dest, function()
		local all = dest.ns.CarryMerger.Archives(); eq(#all, 1)
		local r = dest.ns.CarryHistory.Parse(all[1].text); eq(r.kind, "W"); eq(r.issuer, source.name); eq(r.fields.originalWriter, "Previous Officer-Emberfall")
		assert(r.at > tonumber(r.fields.originalAt)); eq(r.fields.scope, "retained-copy-observed-now")
		local text = {}; for _, line in ipairs(dest.ns.CarryMerger.Lines()) do text[#text + 1] = line.text end
		text = table.concat(text, "\n"); assert(text:find("Witness quote only", 1, true)); assert(text:find("Previous Officer", 1, true)); assert(text:find(date("%Y-%m-%d %H:%M", r.at), 1, true))
	end); Errors(w)
end)

test("carry-merger: reloading transport can resume already-consented exact pages with visible progress and no new authority", function()
	local w, king, member, dest, source = Setup(); Notes(w, source, member)
	local id = Approved(w, king, dest, source)
	w:As(dest, function() assert(dest.ns.CarryMerger.RequestConsent(id, member.name)) end); w:Run(3)
	w:Results(source, { 0, 0, 2 })
	w:As(member, function() assert(member.ns.CarryMerger.Consent(id)); assert(member.ns.CarryMerger.Consent(id, member.question)) end); w:Run(15)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 0) end)
	-- A reload clears only the transport jobs/assemblers, preserving real saved mandates,
	-- direct signatures, subject consents and imported cursor rows. No synthetic consent.
	for _, timer in ipairs(w.timers) do if timer.c == source or timer.c == dest then timer.Cancel() end end
	for _, c in ipairs({ source, dest }) do w:As(c, function() assert(loadfile(ROOT .. "Olympus/CarryMerger.lua"))("Olympus", c.ns) end) end
	w:As(dest, function()
		local resume
		for _, line in ipairs(dest.ns.CarryMerger.Lines()) do if line.text:find("already-consented frozen archive", 1, true) then resume = line.onClick end end
		assert(resume, "partial kept count exposes an explicit retry click"); assert(dest.ns.CarryMerger.Resume(id, member.name))
	end); w:Run(20)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1); assert(dest.ns.CarryMerger.Resume(id, member.name)) end); w:Run(10)
	w:As(dest, function() eq(#dest.ns.CarryMerger.Archives(), 1, "same frozen cursor stays idempotent") end); Errors(w)
end)

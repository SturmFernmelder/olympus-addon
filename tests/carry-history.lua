local base, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]carry%-history%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = base })
local function Setup()
	local w = World.New({ council = false, compliance = "shipped", arenaFiles = { "ArenaMath", "ArenaNet", "ArenaMoney", "Debts" } })
	local king, member = w:Role("king"), w:Role("fighterA")
	for _, c in ipairs({ king, member }) do
		w:As(c, function()
			c.ns.ViewAs = { Previewing = function() return false end }
			c.ns.Roster = { Fresh = function() return c.fresh ~= false and {} or nil end,
				RankOf = function(name) for _, other in ipairs({ king, member }) do if name == other.name and other.guild == c.guild then return other.rank end end end }
			assert(loadfile(ROOT .. "Olympus/CarryHistory.lua"))("Olympus", c.ns)
		end)
	end
	w:Group({ king.name, member.name })
	return w, king, member
end
local function Original(w, king, member, kind, fields)
	local capsule
	w:As(king, function()
		local H = king.ns.CarryHistory
		assert(H.CaptureOriginal(kind or "C", member.name, "native-note", w.clock, king.guild,
			fields or { words = "Keep your word", court = "42", to = member.name }, function(c) capsule = c end))
	end)
	w:Run(2)
	assert(capsule, "actual account signing completes")
	return capsule
end

test("carry-history: original capture uses actual Ed25519, immutable author/time/GUID/subject and append-only private per-character storage", function()
	local w, king, member = Setup()
	local capsule = Original(w, king, member)
	w:As(king, function()
		local H = king.ns.CarryHistory
		local r = H.Parse(capsule.text)
		eq(r.issuer, king.name); eq(r.subject, member.name); eq(r.guid, king.guid); eq(r.at, r.signedAt)
		eq(r.guild, king.guild); eq(r.kind, "C"); eq(r.fields.words, "Keep your word")
		assert(king.ns.Ed25519.Verify(king.ns.Ed25519.FromB64(capsule.pk), capsule.text, king.ns.Ed25519.FromB64(capsule.sig)))
		eq(H.CaptureOriginal("C", member.name, "native-note", w.clock, king.guild, { words = "Replacement" }), false, "same original cannot be overwritten")
		capsule.text = "changed callback copy"
		local originals = H.Originals(member.name)
		eq(#originals, 1); assert(H.Parse(originals[1].text))
		originals[1].text = "changed reader copy"
		assert(H.Parse(H.Originals(member.name)[1].text), "callers cannot mutate retained declarations")
		eq(#H.Originals("Other-Emberfall"), 0)
	end)
end)

test("carry-history: no legacy origin promotion, invented pardon deadline, preview authority, unsigned receipt or moderator export", function()
	local w, king, member = Setup()
	w:As(king, function()
		local H = king.ns.CarryHistory
		eq(H.CaptureOriginal("C", member.name, "old", w.clock - 3600, king.guild, { words = "Old quote" }), false)
		eq(H.CaptureOriginal("P", member.name, "pardon", w.clock, king.guild, { expires = w.clock + 86400 }), false)
		eq(H.CaptureOriginal("M", member.name, "punishment", w.clock, king.guild, { words = "Private moderator" }), false)
		eq(H.CaptureWitness(member.name, king.guild, { sourceKind = "M", originalWriter = king.name }), false)
		king.ns.ViewAs.Previewing = function() return true end
		eq(H.CaptureOriginal("C", member.name, "preview", w.clock, king.guild, { words = "Preview" }), false)
	end)
	w:As(member, function()
		eq(member.ns.CarryHistory.CaptureOriginal("C", member.name, "forged", w.clock, member.guild, { words = "Claimed King" }), false)
		eq(member.ns.CarryHistory.CaptureOriginal("D", member.name, "forged", w.clock, member.guild, { copper = 100 }), false)
	end)
end)

test("carry-history: only an explicitly requested original sender with native GUID binding can enroll a verified key; relays and partial identities grant nothing", function()
	local w, king, member = Setup()
	local capsule = Original(w, king, member)
	local got
	w:As(member, function()
		local H = member.ns.CarryHistory
		eq(H.ReceiveOriginal(king.name, capsule), false, "unsolicited copy never enrolls a key")
		assert(H.OpenRequest(king.name))
		eq(H.ReceiveOriginal(member.name, capsule), false, "an ordinary relay cannot claim to be the issuer")
		member.target, member.groupId = nil, nil
		eq(H.ReceiveOriginal(king.name, capsule), false, "a matching self-asserted name/GUID is not independent native binding")
		member.target = king.name
		assert(H.ReceiveOriginal(king.name, capsule, function(r) got = r end))
	end)
	w:Run(2); assert(got)
	w:As(member, function()
		local H = member.ns.CarryHistory
		eq(#H.Archive(), 1); eq(H.ReceiveOriginal(king.name, capsule), false, "exact replay adds nothing")
		local verified
		assert(H.Verify(capsule, function(r) verified = r end))
		w:Run(2); assert(verified)
	end)
end)

test("carry-history: crypto callbacks recheck cancellation, guild transfer and current role; forged signatures cannot pin or append", function()
	for _, mode in ipairs({ "cancel", "guild", "signature" }) do
		local w, king, member = Setup()
		local capsule = Original(w, king, member)
		w:As(member, function()
			local H = member.ns.CarryHistory
			assert(H.OpenRequest(king.name))
			if mode == "signature" then capsule.text = capsule.text:gsub("Keep your word", "Changed") end
			assert(H.ReceiveOriginal(king.name, capsule))
			if mode == "cancel" then H.CancelRequest(king.name)
			elseif mode == "guild" then member.guild = "Olympus II" end
		end)
		w:Run(2)
		w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 0, mode) end)
	end
end)

local function TransferWorld()
	local w, king, member = Setup()
	local lord = w:Role("fighterB", { rank = 0, guild = "Olympus II" })
	local source = w:Client("Source Warden-Emberfall", { rank = 0, guild = member.guild })
	for _, c in ipairs({ king, member, lord, source }) do w:As(c, function()
		c.ns.Roster = { Fresh = function() return c.fresh ~= false and {} or nil end,
			RankOf = function(name) for _, other in ipairs(w.clients) do if name == other.name and other.guild == c.guild then return other.rank end end end }
		c.ns.Data = { AuthorizedRank = function(name, guild)
			for _, other in ipairs(w.clients) do if name == other.name and other.guild == guild then
				if guild == c.guild then return other.rank, "roster" end
				if other.rank == 0 then return other.rank, "signed" end
			end end
		end }
		c.ns.Authority = { Role = function(name)
			for _, other in ipairs(w.clients) do if name == other.name and other.rank == 0 then return other.guild, 0, "signed" end end
		end }
		c.ns.ViewAs = { Previewing = function() return false end }
		c.ns.Dialog = { Show = function(_, _, _, data) c.question = data; return true end }
		c.ns.RealmPages = {}
		assert(loadfile(ROOT .. "Olympus/Locales/CarryText.lua"))("Olympus", c.ns)
		if c == lord or c == source then assert(loadfile(ROOT .. "Olympus/CarryHistory.lua"))("Olympus", c.ns) end
		assert(loadfile(ROOT .. "Olympus/Carry.lua"))("Olympus", c.ns)
	end) end
	w:Group({ king.name, member.name, lord.name, source.name })
	return w, king, member, lord, source
end
local function Collect(w, king, member)
	w:As(member, function() assert(member.ns.CarryHistory.Collect(king.name)) end)
	w:Run(20)
	w:As(member, function() assert(#member.ns.CarryHistory.Archive() > 0, "real XC dispatcher collects original signatures") end)
end
local function Transfer(w, member, lord)
	w:As(member, function()
		assert(member.ns.Carry.Prepare(lord.name)); assert(member.ns.Carry.Confirm(member.question))
		eq(member.ns.Carry.Offer(), false, "move still happens by the game's human invitation")
	end)
	member.guild = lord.guild
	w:As(member, function() assert(member.ns.Carry.Offer()) end)
	w:Run(1)
	local key
	w:As(member, function()
		local scopes = member.ns.db.carryHistory.scopes
		for _, scope in pairs(scopes) do key = member.ns.Fold(member.name) .. ":" .. scope.characters[member.ns.Fold(member.name)].draft.id end
	end)
	w:As(lord, function()
		assert(lord.ns.Carry.Accept(key)); assert(lord.ns.Carry.Accept(key, lord.question))
	end)
	w:Run(30)
	return key
end

test("carry-history: XC2 collects and transfers more than 34 messages with per-declaration ACK cursors, not a truncated batch", function()
	local w, king, member, lord = TransferWorld()
	for i = 1, 12 do
		w:As(king, function()
			assert(king.ns.CarryHistory.CaptureOriginal("C", member.name, "court-" .. i, w.clock, king.guild,
				{ court = i, words = string.rep("a", 300), to = member.name }))
		end)
		if i % 3 == 0 then w:Run(2) end
	end
	Collect(w, king, member)
	w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 12) end)
	Transfer(w, member, lord)
	w:As(lord, function()
		local entries = lord.ns.CarryHistory.Imports(); eq(#entries, 1); eq(#entries[1].capsules, 12)
		for _, c in ipairs(entries[1].capsules) do eq(c.status, "pending-key", "member-forwarded keys confer no identity") end
		eq(lord.ns.rdb.pardons, nil); eq(lord.ns.rdb.dues, nil)
		assert(lord.ns.CarryHistory.RequestKey(king.name))
	end)
	w:Run(8)
	w:As(lord, function()
		local entries = lord.ns.CarryHistory.Imports()
		for _, c in ipairs(entries[1].capsules) do eq(c.status, "signature-verified", "prior unknown keys require a firsthand original response") end
		local lines = lord.ns.Carry.Lines(); assert(#lines > 20, "archive is reachable through the real Carry page")
	end)
	local data, acks = 0, 0
	for _, msg in ipairs(w.sent) do
		if msg.msg:sub(1, 5) == "XC~2~" then eq(msg.dist, "WHISPER"); assert(#msg.msg <= 255) end
		if msg.from == member.name and msg.msg:sub(1, 7) == "XC~2~D~" then data = data + 1 end
		if msg.from == lord.name and msg.msg:sub(1, 7) == "XC~2~N~" then acks = acks + 1 end
	end
	assert(data > 34, "archive exceeds the old batch ceiling"); eq(acks, 12)
	for _, c in ipairs({ king, member, lord }) do
		assert(#w:Errors(c) == 0, c.name .. ": " .. table.concat(w:Errors(c), "\n"))
	end
end)

test("carry-history: private Loot requires subject token and two real GM consents, travels staff-to-staff, and legacy quotes remain new witness observations", function()
	local w, king, member, lord, source = TransferWorld()
	Original(w, king, member)
	w:As(source, function()
		assert(source.ns.CarryHistory.CaptureOriginal("L", member.name, "original-loot", w.clock, source.guild,
			{ writer = source.name, words = "PRIVATE ORIGINAL NOTE", to = member.name }))
		source.ns.Watch = { CanManage = function() return true end }
		assert(source.ns.CarryHistory.CaptureOriginal("M", member.name, "moderation:W:1:" .. source.name, w.clock, source.guild,
			{ action = "W", actor = source.name, reason = "conduct", sequence = 1, scope = "watch", untilAt = 0, via = "" }))
		source.ns.Loot = { Notes = function() return { { key = "legacy-loot", n = { writer = "Previous Officer-Emberfall", t = w.clock - 900,
			text = "PRIVATE OLDER NOTE", to = member.name } } } end }
	end)
	w:Run(2); Collect(w, king, member)
	local baseKey = Transfer(w, member, lord)
	w:As(member, function() assert(member.ns.CarryHistory.StaffConsent(source.name)) end)
	w:Run(1)
	local sourceKey, recipientKey = baseKey, source.ns.Fold(lord.name) .. ":" .. baseKey:match(":([^:]+)$")
	w:As(source, function()
		assert(source.ns.CarryHistory.StaffAccept(sourceKey))
		eq(source.ns.CarryHistory.StaffAccept(sourceKey, true), false, "a forged yes grants no export")
		assert(source.ns.CarryHistory.StaffAccept(sourceKey, source.question))
	end)
	w:Run(3)
	local incoming = lord.ns.Fold(source.name) .. ":" .. baseKey:match(":([^:]+)$")
	w:As(lord, function()
		eq(#lord.ns.CarryHistory.Imports(), 1, "source consent alone sends no private record")
		assert(lord.ns.Carry.Accept(incoming)); assert(lord.ns.Carry.Accept(incoming, lord.question))
	end)
	w:Run(15)
	w:As(lord, function()
		local all, staff = lord.ns.CarryHistory.Imports()
		eq(#all, 2)
		for _, e in ipairs(all) do if e.staff then staff = e end end
		assert(staff); eq(#staff.capsules, 3)
		local kinds = {}
		for _, c in ipairs(staff.capsules) do local r = lord.ns.CarryHistory.Parse(c.text); kinds[r.kind] = r end
		assert(kinds.L); assert(kinds.M); assert(kinds.W); eq(kinds.W.fields.scope, "retained-copy-observed-now")
		eq(kinds.M.fields.action, "W"); eq(kinds.M.fields.actor, source.name); eq(kinds.M.fields.reason, "conduct")
		eq(kinds.M.fields.text, nil, "deleted chat text is never in the staff archive declaration")
		eq(kinds.W.issuer, source.name); eq(kinds.W.fields.originalWriter, "Previous Officer-Emberfall")
		assert(kinds.W.at > tonumber(kinds.W.fields.originalAt), "witness signing time is not forged old authorship")
	end)
	for _, msg in ipairs(w.sent) do
		if msg.msg:sub(1, 7) == "XC~2~D~" and msg.from == source.name then eq(msg.target, lord.name, "private payload never goes to the subject") end
	end
	w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 1); assert(member.ns.Carry.Revoke()) end)
	w:Run(1)
	w:As(lord, function() eq(#lord.ns.CarryHistory.Imports(), 0, "subject revocation also seals staff sidecars") end)
	w:As(source, function() eq(source.ns.CarryHistory.StaffAccept(sourceKey, source.question), false); eq(source.ns.CarryHistory.StaffAccept(recipientKey), false) end)
	for _, c in ipairs({ king, member, lord, source }) do assert(#w:Errors(c) == 0, table.concat(w:Errors(c), "\n")) end
end)

test("carry-history: private Loot never appears in subject collection wire and revoked destination archives cannot be resurrected", function()
	local w, king, member, lord = TransferWorld()
	Original(w, king, member)
	w:As(king, function()
		assert(king.ns.CarryHistory.CaptureOriginal("L", member.name, "private-loot", w.clock, king.guild,
			{ writer = king.name, words = "Secret officer-only loot note", to = member.name }))
	end)
	w:Run(2); Collect(w, king, member)
	w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 1) end)
	local key = Transfer(w, member, lord)
	local offer
	for _, msg in ipairs(w.sent) do
		assert(not msg.msg:find("Secret officer", 1, true), "private note is absent from subject raw payload")
		if msg.from == member.name and msg.msg:sub(1, 7) == "XC~2~O~" then offer = msg.msg end
	end
	w:As(lord, function() eq(#lord.ns.CarryHistory.Imports(), 1); lord.rank = 1; eq(#lord.ns.CarryHistory.Imports(), 0); lord.rank = 0 end)
	w:As(member, function() assert(member.ns.Carry.Revoke()) end); w:Run(1)
	w:As(lord, function()
		eq(#lord.ns.CarryHistory.Imports(), 0)
		eq(lord.ns.Carry.Handle("WHISPER", member.name, offer), false)
		eq(lord.ns.Carry.Accept(key), false)
		eq(lord.ns.Carry.Handle("CHANNEL", member.name, offer), false)
	end)
end)

test("carry-history: expired offers release bounded slots and cancellation before an offer creates a durable native-subject floor", function()
	local w, king, member, lord = TransferWorld()
	Original(w, king, member); Collect(w, king, member)
	w:As(member, function() assert(member.ns.Carry.Prepare(lord.name)); assert(member.ns.Carry.Confirm(member.question)) end)
	member.guild = lord.guild
	w:As(member, function() assert(member.ns.Carry.Offer()) end); w:Run(1)
	local offer
	for _, msg in ipairs(w.sent) do if msg.from == member.name and msg.msg:sub(1, 7) == "XC~2~O~" then offer = msg.msg end end
	local oldId = offer:match("^XC~2~O~(%x+)~")
	w:As(lord, function()
		for i = 1, lord.ns.CarryHistory.SENDER_OFFERS - 1 do
			assert(lord.ns.Carry.Handle("WHISPER", member.name, offer:gsub(oldId, ("%016x"):format(i))))
		end
		eq(lord.ns.Carry.Handle("WHISPER", member.name, offer:gsub(oldId, "eeeeeeeeeeeeeeee")), false, "active bound enforced")
	end)
	w.clock = w.clock + lord.ns.CarryHistory.LIFE + 1
	w:As(lord, function()
		assert(lord.ns.Carry.Handle("WHISPER", member.name, offer:gsub(oldId, "eeeeeeeeeeeeeeee")), "expired offers release their slots")
		local digest = offer:match("~(%x+)$")
		assert(lord.ns.Carry.Handle("WHISPER", member.name, "XC~2~R~ffffffffffffffff~" .. digest))
		eq(lord.ns.Carry.Handle("WHISPER", member.name, offer:gsub(oldId, "ffffffffffffffff")), false, "a delayed offer cannot undo an earlier cancel")
		eq(lord.ns.Carry.Handle("WHISPER", "Unknown-Emberfall", "XC~2~R~dddddddddddddddd~" .. digest), false, "a stranger cannot allocate cancellation floors")
	end)
end)

test("carry-history: a member with only private Loot can prepare a consent-only transfer without seeing or carrying any note", function()
	local w, _, member, lord, source = TransferWorld()
	w:As(source, function()
		assert(source.ns.CarryHistory.CaptureOriginal("L", member.name, "only-private", w.clock, source.guild,
			{ writer = source.name, words = "ONLY STAFF MAY SEE THIS", to = member.name }))
	end)
	w:Run(2)
	local key = Transfer(w, member, lord)
	w:As(lord, function() local all = lord.ns.CarryHistory.Imports(); eq(#all, 1); eq(#all[1].capsules, 0, "explicit consent without invented personal data") end)
	w:As(member, function() assert(member.ns.CarryHistory.StaffConsent(source.name)) end); w:Run(1)
	w:As(source, function() assert(source.ns.CarryHistory.StaffAccept(key)); assert(source.ns.CarryHistory.StaffAccept(key, source.question)) end); w:Run(2)
	local incoming = source.ns.Fold(source.name) .. ":" .. key:match(":([^:]+)$")
	w:As(lord, function() assert(lord.ns.Carry.Accept(incoming)); assert(lord.ns.Carry.Accept(incoming, lord.question)) end); w:Run(10)
	w:As(lord, function() eq(#lord.ns.CarryHistory.Imports(), 2) end)
	w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 0) end)
	for _, msg in ipairs(w.sent) do if msg.target == member.name then assert(not msg.msg:find("ONLY STAFF", 1, true), "the subject receives no private plaintext") end end
end)

test("carry-history: real Court, Loot write/removal and royal Pardon functions capture only their actor-owned issuance with original deadline", function()
	local w, king, member, _, source = TransferWorld()
	w:As(king, function()
		assert(loadfile(ROOT .. "Olympus/Chronicle.lua"))("Olympus", king.ns)
		assert(loadfile(ROOT .. "Olympus/Court.lua"))("Olympus", king.ns)
		assert(loadfile(ROOT .. "Olympus/Acts.lua"))("Olympus", king.ns)
		king.ns.Court.Toggle()
		king.ns.Court.Request(member.name, king.ns.Court.Holding().id, member.guild)
		king.ns.Court.Call(member.name, "A kept royal promise")
		king.ns.Acts.Pardon(member.name)
	end)
	w:As(source, function()
		source.ns.Roster.IsOfficer = function() return source.rank <= 1 end
		assert(loadfile(ROOT .. "Olympus/Loot.lua"))("Olympus", source.ns)
		local note = source.ns.Loot.Write("Native officer note", 123, member.name)
		assert(note); source.ns.Loot.Remove(note.writer .. "#" .. note.id)
	end)
	w:Run(3)
	w:As(king, function()
		local kinds = {}
		for _, c in ipairs(king.ns.CarryHistory.Originals(member.name)) do local r = king.ns.CarryHistory.Parse(c.text); kinds[r.kind] = r end
		assert(kinds.C); assert(kinds.P); eq(kinds.C.fields.words, "A kept royal promise")
		eq(tonumber(kinds.P.fields.expires), kinds.P.at + king.ns.Acts.PARDON_DAYS * 86400)
		eq(kinds.P.at, king.ns.rdb.pardonsGiven[king.ns.King.CleanName(member.name)], "matches the actual royal book key, not the lowercase receiver cache")
	end)
	w:As(source, function()
		local all = source.ns.CarryHistory.Originals(member.name); eq(#all, 2)
		local original, removal = source.ns.CarryHistory.Parse(all[1].text), source.ns.CarryHistory.Parse(all[2].text)
		eq(original.fields.removed, "0"); eq(removal.fields.removed, "1"); eq(removal.fields.removedBy, source.name)
		eq(removal.fields.writer, source.name, "writer remains separate from removal actor")
		eq(removal.fields.words, original.fields.words)
	end)
end)

test("carry-history: a lost fragment is retried with the same bounded cursor and completion requires the final receiver acknowledgement", function()
	local w, king, member = TransferWorld()
	Original(w, king, member, "C", { words = string.rep("r", 300), to = member.name, court = 45 })
	w:Results(king, { 0, 0, 2 }) -- begin, first fragment, missing second fragment
	w:As(member, function() assert(member.ns.CarryHistory.Collect(king.name)) end)
	w:Run(5)
	w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 0, "an incomplete page cannot be retained") end)
	w:Run(100)
	w:As(member, function() eq(#member.ns.CarryHistory.Archive(), 1, "same-cursor retry recovers the lost page") end)
	local ack = false
	for _, msg in ipairs(w.sent) do if msg.from == member.name and msg.msg:sub(1, 7) == "XC~2~F~" then ack = true end end
	assert(ack, "final destination confirmation is distinct from native send completion")
	eq(#w:Errors(king), 0); eq(#w:Errors(member), 0)
end)

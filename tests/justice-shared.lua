local base, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]justice%-shared%.lua$") or "./"
-- Actual Comm queue/dispatch, native Roster.Scan/Fresh, Members manual removal and Watch UI.
-- The simulated server supplies identity/appointment verdicts and its native roster rows.
local function Client(name)
	local w = { name = name, guild = "Olympus II", now = 1800000000, sent = {}, events = {}, listeners = {}, ranks = {},
		justice = "Justice-Realm", council = { ["Council-Realm"] = true }, native = {}, dialogs = {} }
	local n = setmetatable({ me = name, realm = "Realm", group = "Realm", faction = "Alliance", CAPTAIN_RANK = 1,
		db = { blocked = {} }, rdb = { guilds = {} }, ViewAs = {}, WatchChat = {}, Nominees = {}, King = {}, Workshop = {}, UI = {},
		Moderation = { Blocks = function() return false end }, TabardsV2 = { SurfaceVisible = function() return false end },
		Judgment = { Visible = function() return false end }, RealmPages = {} }, { __index = base })
	w.ns = n
	n.Now = function() return w.now end; n.Fold = string.lower
	n.FullName = function(s) return s:find("-", 1, true) and s or s .. "-Realm" end
	n.ShortName = function(s) return s:match("^[^-]+") end; n.DisplayName = n.ShortName
	n.Moderation.CharName = function(s) return type(s) == "string" and n.FullName(s) or nil end
	n.RealmOf = function(s) return s:match("%-(.+)$") end; n.GroupOf = function(s) return s end
	n.IsMember = function() return w.guild ~= nil end; n.IsFederation = function(g) return g == "Olympus II" or g == "Olympus III" end
	n.IsKingCharacter = function(s) return s == "Crown-Realm" end; n.IsHighCouncillor = function(s) return w.council[s] == true end
	n.KingRealm = function() return "Realm" end; n.IsKingGuild = function() return false end
	n.King.Preview = function() return w.preview == true end; n.King.IsKing = function() return n.IsKingCharacter(n.me) end
	n.Workshop.IsAuthor = function() return n.me == "Author-Realm" end; n.Workshop.Visible = function() return false end
	n.Workshop.IsAuthorName = function(s) return s == "Author-Realm" end
	n.ViewAs.Previewing = n.King.Preview; n.ViewAs.Available = function() return false end
	n.WatchChat.Justice = function() return w.justice end
	n.WatchChat.IsNamedWatcher = function(s) return s == w.justice end
	n.WatchChat.PowersBarred = function() return w.barred and "blocked" or nil end
	n.Nominees.IsCorrespondent = function(s) return s == w.justice end
	n.Data = { AuthorizedRank = function(s, guild)
		if guild == w.guild then local rank = w.ranks[s]; return rank, rank ~= nil and "roster" or nil end
		local fact = w.remote and w.remote[s]; if fact then return fact.rank, fact.source end
	end }
	n.Zones = { KeyForName = function() return nil end }
	n.On = function(event, fn) w.listeners[event] = w.listeners[event] or {}; table.insert(w.listeners[event], fn) end
	n.Fire = function(event, ...) for _, fn in ipairs(w.listeners[event] or {}) do fn(...) end end
	n.RegisterEvent = function(event, fn) w.events[event] = fn end
	n.After, n.Every, n.Print, n.Log = function() end, function() end, function() end, function() end
	n.SafeCall = function(_, fn, ...) return fn(...) end
	n.ShowDialog = function(which, a, b, data) w.dialogs[#w.dialogs + 1] = { which = which, data = data }; return true end
	n.CouncilMasked = function() return false end
	local rows = {}
	local env = setmetatable({ StaticPopupDialogs = {}, GetGuildInfo = function() return w.guild, "Rank", w.ranks[n.me] or 9 end,
		IsInGuild = function() return w.guild ~= nil end, GetTime = function() return w.now end, GetServerTime = function() return math.floor(w.now) end,
		GetNumGuildMembers = function() return #rows + (w.partial and 1 or 0), #rows end,
		GetGuildRosterInfo = function(i) local row = rows[i]; if row then return row.name, "Member", row.rank, 60, "Warrior", "Town", "", "", true, 0, "WARRIOR" end end,
		GuildControlGetNumRanks = function() return 0 end, GetGuildRosterLastOnline = function() return 0, 0, 0, 0 end,
		CanGuildRemove = function() return w.canRemove ~= false end,
		C_GuildInfo = { GuildRoster = function() end, Uninvite = function(raw) w.native[#w.native + 1] = raw end },
		GetChannelName = function() return 0 end, JoinChannelByName = function() end, LeaveChannelByName = function() end, HideChannelFromChat = function() end,
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end,
			SendAddonMessage = function(_, text, dist, target) w.sent[#w.sent + 1] = { text = text, dist = dist, target = target, logged = false }; return 0 end,
			SendAddonMessageLogged = function(_, text, dist, target) w.sent[#w.sent + 1] = { text = text, dist = dist, target = target, logged = true }; return 0 end } }, { __index = _G })
	w.env = env
	local function Load(file) local f = assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua")); setfenv(f, env); f("Olympus", n) end
	Load("Comm"); for _, login in ipairs(w.listeners.LOGIN or {}) do login() end
	Load("Roster"); Load("Members"); Load("Watch"); Load("Ed25519"); Load("JusticeTasks")
	function w.scan()
		rows = {}; for who, rank in pairs(w.ranks) do rows[#rows + 1] = { name = who, rank = rank } end
		table.sort(rows, function(a, b) return a.name < b.name end); n.Roster.Scan()
	end
	function w.pump() for _ = 1, 20 do w.now = w.now + 1.2; n.Comm.Pump() end end
	function w.receive(sender, text, logged)
		local event = logged == false and "CHAT_MSG_ADDON" or "CHAT_MSG_ADDON_LOGGED"
		if not w.events[event] then event = "CHAT_MSG_ADDON" end
		return w.events[event](n.PREFIX, text, "WHISPER", sender)
	end
	function w.reloadTasks() Load("JusticeTasks") end
	return w
end
local function Setup()
	local a, b = Client("Crown-Realm"), Client("Justice-Realm")
	for _, w in ipairs({ a, b }) do w.ranks = { ["Crown-Realm"] = 0, ["Justice-Realm"] = 1, ["Subject-Realm"] = 9, ["Other-Realm"] = 9, ["Council-Realm"] = 3, ["Author-Realm"] = 9 }; w.scan() end
	return a, b
end
local function Row(w, key) for _, e in ipairs(w.ns.JusticeTasks.Tasks()) do if e.key == key then return e.task end end end
local function Last(w, op) for i = #w.sent, 1, -1 do if w.sent[i].text:sub(1, 7) == "JT~1~" .. op .. "~" then return w.sent[i].text end end end
local function Issue(a, b)
	local ok, key = a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject-Realm"); assert(ok); a.pump()
	return key, assert(Last(a, "I"))
end
local function Receive(a, b, key, text)
	b.now = a.now; b.scan(); b.receive(a.name, text); b.pump(); a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "R")))
	assert(Row(a, key).receivedAt); return Row(b, key)
end
local function Attempt(a, b, key)
	b.now = b.now + 30; b.scan(); assert(b.ns.JusticeTasks.AskRemoval(key))
	local dialog = b.dialogs[#b.dialogs]; eq(dialog.which, "OLYMPUS_GUILD_REMOVE")
	assert(b.ns.Members.Remove(dialog.data)); b.pump(); a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "R")))
end
local function Absent(a, b, key)
	b.now = b.now + 10; b.ranks["Subject-Realm"] = nil; b.scan(); b.ns.Fire("DATA_CHANGED"); b.pump()
	a.now = b.now; a.scan(); a.receive(b.name, assert(Last(b, "R"))); assert(Row(a, key).absentAt)
end


-- A composition of the existing actual native-Comm fixture with actual Ed25519 signatures.
-- These deterministic throwaway keys and native identity answers are fixtures, not production
-- credentials. Arena.Check is scheduled here so revocation between verification and callback
-- is observable; its Ed25519 verdict is the real implementation, never an asserted true mock.
local clients = {}
local function Crypto(w)
	local n = w.ns
	local seed = base.Sign.SHA256("justice-shared-fixture|" .. w.name)
	local pk = n.Ed25519.PublicKey(seed)
	w.guid = ("Player-1-%08X"):format(#clients + 1); clients[#clients + 1] = w
	local gk = "1." .. w.guid:match("%-(%x+)$"):lower()
	local jobs = {}
	n.Arena = { GuidOf = function(key)
		if type(key) ~= "string" then return nil end
		local server, id = key:match("^(%d+)%.(%x+)$")
		return server and #id == 8 and ("Player-%s-%s"):format(server, id:upper()) or nil
	end, Check = function(_, claim, cb) jobs[#jobs + 1] = { claim = claim, cb = cb } end }
	n.Debts = { MyKey = function() return gk, pk end,
		Sign = function(text) return n.Ed25519.Sign(seed, text, pk) end,
		ClaimParts = function() return gk, n.Ed25519.ToB64(pk), n.Ed25519.ToB64(n.Ed25519.Sign(seed, "OLYA1|" .. w.guid .. "|" .. w.name, pk)) end,
		Bind = function(name, guid)
			for _, actor in ipairs(clients) do if actor.guid == guid and actor.name == name and not w.bindingMissing then return "info" end end
		end }
	function w.verify()
		local batch = jobs; jobs = {}
		for _, job in ipairs(batch) do job.cb(n.Ed25519.Verify(job.claim.pk, job.claim.msg, job.claim.sig)) end
	end
	function w.inject(sender, text, dist)
		return n.JusticeTasks.Handle(dist or "WHISPER", sender, text)
	end
	w.position = {}
	return w
end
local function Triple()
	clients = {}
	local a, b = Setup(); local c = Client("Council-Realm"); c.ranks = a.ranks; c.scan()
	return Crypto(a), Crypto(b), Crypto(c)
end
local function Transfer(a, b, only, delayed)
	if a.offline or b.offline then return end
	a.pump(); b.now = math.max(a.now, b.now); b.scan()
	local key = b.name .. (only or "")
	local since = a.position[key] or 0
	for i = since + 1, #a.sent do
		local packet = a.sent[i]
		if a.ns.FullName(packet.target or "") == b.name and (not only or packet.text:sub(1, #only) == only) then
			b.receive(a.name, packet.text, packet.logged)
		end
	end
	a.position[key] = #a.sent; if not delayed then b.verify() end
end
local function Complete(a, b)
	local ok, key = a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject-Realm"); assert(ok)
	Transfer(a, b); b.ns.JusticeTasks.Tick(); Transfer(b, a); a.ns.JusticeTasks.Tick(); Transfer(a, b); Transfer(b, a)
	Attempt(a, b, key); Transfer(b, a)
	Absent(a, b, key); Transfer(b, a)
	assert(a.ns.JusticeTasks.Confirm(key)); Transfer(a, b); Transfer(b, a)
	return key
end
local function Enroll(a, c)
	assert(a.ns.JusticeTasks.SendKey(c.name)); Transfer(a, c)
end
local function Sync(a, c)
	-- GetServerTime is one server clock, not time since each fixture started. Align a late
	-- collector before its request so packet delivery cannot jump across its five-minute lease.
	c.now = math.max(a.now, c.now); c.scan()
	assert(c.ns.JusticeTasks.Sync(a.name)); Transfer(c, a); Transfer(a, c)
	for _ = 1, 4 do
		c.ns.JusticeTasks.Tick(); c.verify()
		for _, actor in ipairs(clients) do if actor ~= c then Transfer(c, actor); Transfer(actor, c) end end
	end
end
test("Justice shared: new original signatures consolidate privately across staff with original actor attribution and receipt timing", function()
	local a, b, c = Triple(); local key = Complete(a, b)
	Enroll(a, c); Enroll(b, c); Sync(a, c)
	local t = assert(Row(c, key)); eq(t.issuer, a.name); eq(t.assignee, b.name); eq(t.confirmedBy, a.name)
	local m = c.ns.JusticeTasks.ResponseMetric(); local row = assert(m.by[b.name])
	eq(row.received, 1); eq(row.attempted, 1); eq(row.completed, 1); eq(row.pending, 0); eq(row.medianSeconds, t.attemptedAt - t.receivedAt)
	eq(c.ns.JusticeTasks.ReportMetric(), nil, "tasks never manufacture member reports")
	for _, actor in ipairs({ a, b, c }) do for _, packet in ipairs(actor.sent) do if packet.text:sub(1, 3) == "JT~" then eq(packet.dist, "WHISPER"); eq(packet.logged, true) end end end
	eq(#c.native, 0); eq(#b.native, 1)
end)
test("Justice shared: offline collector cannot enroll a relayed embedded key; independently bound originals resolve pending evidence later", function()
	local a, b, c = Triple(); local key = Complete(a, b)
	local d = Crypto(Client("CouncilTwo-Realm")); d.ranks = c.ranks; d.ranks[d.name] = 3; d.scan()
	for _, actor in ipairs({ a, b, c, d }) do actor.council[d.name] = true end
	Enroll(a, d); Enroll(b, d); Sync(a, d)
	a.offline, b.offline = true, true
	Sync(d, c) -- the originals never contact this later collector during relay recovery
	eq(Row(c, key), nil, "the original issuer key is unknown, so relay evidence remains pending")
	local _, issuerPK = a.ns.Debts.ClaimParts()
	eq(c.ns.JusticeTasks.HasKey(a.name, issuerPK), false)
	a.offline = false
	c.bindingMissing = true; Enroll(a, c); eq(c.ns.JusticeTasks.HasKey(a.name, issuerPK), false, "self-signature alone never binds a native identity")
	c.bindingMissing = false; Enroll(a, c); c.ns.JusticeTasks.Tick(); c.verify()
	assert(Row(c, key)); eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].received, 0, "missing assignee key cannot fabricate received credit")
	b.offline = false
	Enroll(b, c); c.now = c.now + 60; c.scan(); c.ns.JusticeTasks.Tick(); c.verify(); c.ns.JusticeTasks.Tick(); c.verify()
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].completed, 1)
end)
test("Justice shared: private recovery rejects public delivery, role/realm spoof, preview and asynchronous authority revocation", function()
	local a, b, c = Triple(); Complete(a, b); Enroll(a, c); Enroll(b, c)
	eq(c.ns.JusticeTasks.Sync("Other-Realm"), false)
	eq(c.ns.JusticeTasks.Sync("Council-Elsewhere"), false)
	c.preview = true; eq(c.ns.JusticeTasks.Sync(a.name), false); c.preview = false
	local before = #c.sent
	assert(c.ns.JusticeTasks.Sync(a.name)); c.preview = true; Transfer(c, a); eq(#c.sent, before, "queued key and recovery ask are both denied after preview")
	c.preview = false; c.now = c.now + 60; c.scan(); c.position = {}; assert(c.ns.JusticeTasks.Sync(a.name)); Transfer(c, a); a.pump()
	for _, p in ipairs(a.sent) do if a.ns.FullName(p.target or "") == c.name and p.text:sub(1, 7) == "JT~2~P~" then eq(c.inject(a.name, p.text, "CHANNEL"), false) end end
	Transfer(a, c, nil, true); c.council[c.name] = nil; c.verify(); eq(c.ns.JusticeTasks.Visible(), false); eq(#c.ns.JusticeTasks.Tasks(), 0)
	c.council[c.name] = true; c.scan(); eq(#c.ns.JusticeTasks.Tasks(), 0, "revoked verification callback did not apply evidence")
end)
test("Justice shared: signed task identity conflicts and tampered legacy fields cannot change response metrics or award completion", function()
	local a, b, c = Triple(); local key = Complete(a, b); Enroll(a, c); Enroll(b, c); Sync(a, c)
	local t = Row(c, key); local before = c.ns.JusticeTasks.ResponseMetric().by[b.name].medianSeconds
	t.attemptedAt, t.receivedAt, t.confirmedAt = t.createdAt + 9999, t.createdAt, nil
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].medianSeconds, before, "metrics read signed receipt, never mutable legacy fields")
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].completed, 1, "human completion reads original signed terminal")
	t.subject = "Other-Realm"; eq(c.ns.JusticeTasks.ResponseMetric().by[b.name], nil, "I binds original subject and the entire immutable task")
end)
test("Justice shared: receipt-less offline delivery is unknown, old JT1 facts stay unranked, and report pairs remain separate", function()
	local a, b, c = Triple()
	local ok, key = a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject-Realm"); assert(ok)
	a.now = a.now + 3600; a.scan()
	local m = a.ns.JusticeTasks.ResponseMetric(); local row = m.by[b.name]
	eq(row.received, 0); eq(row.deliveryUnknown, 1); eq(row.pending, 0); eq(row.medianSeconds, nil)
	local t = Row(a, key); t.signedVersion, t.proofs = nil, nil
	m = a.ns.JusticeTasks.ResponseMetric(); eq(m.legacy, 1); eq(m.by[b.name], nil)
	Sync(a, c); eq(#c.ns.JusticeTasks.Tasks(), 0, "a staff relay never signs or promotes old direct-only evidence")
end)
test("Justice shared: accepted sister-guild ordinary correspondent is addressable, but false or demoted appointments and stale own roster are not", function()
	local a, b = Triple()
	local n = a.ns; local guild, gm = "Olympus III", "SisterMaster-Realm"
	n.Data.KnownRank = function(who, g) if g == guild and who == gm then return 0, 2 end end
	n.Data.AuthorizedRank = function(who, g) if g == guild and who == gm then return 0, "signed" end end
	n.Data.Guild = function(g) if g == guild then return { leader = gm, realm = "Realm" } end end
	n.Borders = { Changed = function() end }; n.ChatRooms = {}; n.PlayerMenu = {}
	n.IsKingGuild = function(g) return g == "Olympus" end; n.KingGuildName = function() return "Olympus" end
	local f = assert(loadfile(ROOT .. "Olympus/Nominees.lua")); setfenv(f, a.env); f("Olympus", n)
	local packet = ("NM~1~%s~%d~1~1~d=Council of Justice=%s"):format(guild, a.now, b.name)
	n.Nominees.Handle("CHANNEL", "Other-Realm", packet)
	eq(n.JusticeTasks.Issue(guild, b.name, "Subject-Realm"), false, "unrecognized issuer cannot name the correspondent")
	n.Nominees.Handle("CHANNEL", gm, packet); eq(n.Nominees.RoleOf(b.name, guild), "correspondent")
	local accepted = n.JusticeTasks.Issue(guild, b.name, "Subject-Realm"); eq(accepted, true, "an appointed ordinary rank need not be a signed officer")
	b.guild = guild; b.now = a.now; b.ranks = { [gm] = 0, [b.name] = 3, ["Subject-Realm"] = 9 }; b.scan()
	b.ns.Data.KnownRank = function() return nil end; b.ns.Data.Guild = function() return nil end
	b.ns.Borders = { Changed = function() end }; b.ns.ChatRooms = {}; b.ns.PlayerMenu = {}
	b.ns.IsKingGuild = n.IsKingGuild; b.ns.KingGuildName = n.KingGuildName
	local recipient = assert(loadfile(ROOT .. "Olympus/Nominees.lua")); setfenv(recipient, b.env); recipient("Olympus", b.ns)
	b.ns.Nominees.Handle("CHANNEL", gm, packet)
	eq(b.ns.Nominees.IsCorrespondent(b.name, guild, "Council of Justice"), true, "the ordinary recipient is named by its actual native guild master")
	Transfer(a, b); eq(#b.ns.JusticeTasks.Tasks(), 1); assert(b.ns.JusticeTasks.Tasks()[1].task.receivedAt)
	eq(#b.native, 0, "a received explicit task still performs no native removal")
	b.ns.Nominees.Handle("CHANNEL", gm, ("NM~1~%s~%d~1~1~"):format(guild, a.now + 1))
	eq(b.ns.JusticeTasks.Own(), false, "authoritative appointment removal stops recipient acknowledgment and action")
	n.Data.AuthorizedRank = function() return 1, "signed" end
	eq(n.JusticeTasks.Issue(guild, b.name, "Other-Realm"), false)
	n.Data.AuthorizedRank = function() return 0, "census" end
	eq(n.JusticeTasks.Issue(guild, b.name, "Other-Realm"), false)
	a.now = a.now + 601; eq(n.JusticeTasks.CanIssue(), false, "stale own roster never grants dispatch authority")
end)
test("Justice shared: recovery loss retries bounded pages, replay is idempotent and saved proofs are reverified after reload", function()
	local a, b, c = Triple(); local key = Complete(a, b); Enroll(a, c); Enroll(b, c)
	assert(c.ns.JusticeTasks.Sync(a.name)); Transfer(c, a); a.pump(); a.position[c.name] = #a.sent -- deliberately lose a complete response
	eq(Row(c, key), nil)
	c.now = c.now + 60; c.scan(); Sync(a, c)
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].received, 1)
	c.now = c.now + 60; c.scan(); Sync(a, c)
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].received, 1, "replay never adds another task or completion")
	c.reloadTasks(); local m = c.ns.JusticeTasks.ResponseMetric(); eq(m.by[b.name], nil, "reload starts with no ephemeral verified trust")
	c.verify(); m = c.ns.JusticeTasks.ResponseMetric(); eq(m.by[b.name].completed, 1)
end)
local function ProofPackets(proof)
	local hash = (base.Sign.SHA256(proof):gsub(".", function(byte) return ("%02x"):format(byte:byte()) end)):sub(1, 16)
	local out, total = {}, math.ceil(#proof / 180)
	for i = 1, total do out[i] = ("JT~2~P~A~%s~%d~%d~%s"):format(hash, i, total, proof:sub((i - 1) * 180 + 1, i * 180)) end
	return out
end
test("Justice shared: invalid original signature and wrong task hash cannot replace evidence, change an actor or poison a valid task", function()
	local a, b, c = Triple(); local key = Complete(a, b); Sync(a, c)
	local t = Row(c, key); local metric = c.ns.JusticeTasks.ResponseMetric().by[b.name]
	local original = t.proofs.I
	local fake = original:gsub("Subject%-Realm", "Other-Realm")
	for _, packet in ipairs(ProofPackets(fake)) do c.receive(a.name, packet) end; c.verify()
	eq(Row(c, key).subject, "Subject-Realm"); eq(Row(c, key).proofs.I, original)
	local wrong = t.proofs.R:gsub("R~[%da-f]+~", "R~" .. string.rep("0", 64) .. "~", 1)
	for _, packet in ipairs(ProofPackets(wrong)) do c.receive(a.name, packet) end; c.verify()
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].completed, metric.completed)
	local _, issuerPK = a.ns.Debts.ClaimParts(); local _, assigneePK = b.ns.Debts.ClaimParts()
	local gk, pk, sig = a.ns.Debts.ClaimParts(); local badKey = ("JT~2~K~A~%s~%s~%s"):format(gk, pk, sig)
	c.receive(b.name, badKey); c.verify()
	eq(c.ns.JusticeTasks.HasKey(b.name, issuerPK), false, "native GUID/name binding cannot be relabelled as the other actor")
	eq(c.ns.JusticeTasks.HasKey(b.name, assigneePK), true)
end)
test("Justice shared: private pending pieces, proof jobs and keys are bounded and current appointment loss makes historical timing unknown", function()
	local a, b, c = Triple(); local key = Complete(a, b); Sync(a, c)
	c.now = c.now + 60; c.scan(); assert(c.ns.JusticeTasks.Sync(a.name))
	for i = 1, 50 do c.receive(a.name, ("JT~2~P~A~%016x~1~6~partial"):format(i)) end
	eq(c.ns.JusticeTasks.SharedStatus().openPieces, 2, "one peer cannot occupy more than two partial proofs")
	c.now = c.now + c.ns.JusticeTasks.SHARE_KEEP + 1; c.scan(); c.ns.JusticeTasks.Tick()
	eq(c.ns.JusticeTasks.SharedStatus().openPieces, 0)
	c.justice = "Other-Realm"
	local m = c.ns.JusticeTasks.ResponseMetric(); eq(m.by[b.name], nil); eq(m.unknown, 1)
	assert(Row(c, key).proofs.I, "current duty loss hides ranking eligibility, not the original signed audit")
	c.justice = b.name; c.preview = true; eq(c.ns.JusticeTasks.SharedStatus(), nil); eq(c.ns.JusticeTasks.ResponseMetric(), nil)
end)
test("Justice shared: direct key callbacks recheck the local reader role, and a real assignee can retry native key enrollment", function()
	local a, b, c = Triple()
	assert(a.ns.JusticeTasks.SendKey(c.name)); Transfer(a, c, nil, true)
	c.council[c.name] = nil; c.verify()
	local _, pk = a.ns.Debts.ClaimParts(); eq(c.ns.JusticeTasks.HasKey(a.name, pk), false, "the asynchronous key callback cannot enroll for a now-ordinary reader")
	local ok, key = a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject-Realm"); assert(ok)
	b.bindingMissing = true; Transfer(a, b); Transfer(b, a)
	assert(Row(a, key).receivedAt); eq(Row(a, key).proofs.R, nil, "direct JT1 delivery is not a signed receipt")
	b.bindingMissing = false; b.now = b.now + 60; b.scan(); b.ns.JusticeTasks.Tick(); Transfer(b, a); Transfer(a, b)
	b.ns.JusticeTasks.Tick(); b.verify(); Transfer(b, a)
	assert(Row(b, key).signedVersion == 2, "the recipient recovered the issuer's signed immutable task")
	assert(Row(b, key).proofs.R, "the recipient produced its own signed receipt")
	a.ns.JusticeTasks.Tick(); a.verify()
	assert(Row(a, key).proofs.R, "the true assignee's private B request recovers the independently native-bound issuer key")
end)
test("Justice shared: lost signed issue retries even after a plain receipt; unknown delivery never becomes a response duration", function()
	local a, b = Triple(); local ok, key = a.ns.JusticeTasks.Issue(a.guild, b.name, "Subject-Realm"); assert(ok)
	Transfer(a, b, "JT~1~"); Transfer(b, a)
	assert(Row(a, key).receivedAt); eq(Row(a, key).proofs.R, nil)
	a.position[b.name] = #a.sent -- the original JT2 proof/key packets were actually lost, not queued
	a.now = a.now + a.ns.JusticeTasks.SHARE_EVERY + 1; a.scan(); a.ns.JusticeTasks.Tick(); Transfer(a, b)
	b.ns.JusticeTasks.Tick(); b.verify(); Transfer(b, a)
	assert(Row(b, key).signedVersion == 2, "the recipient recovered the retried immutable signature")
	assert(Row(b, key).proofs.R, "the recipient produced a signed receipt after retry")
	a.ns.JusticeTasks.Tick(); a.verify()
	assert(Row(a, key).proofs.R, "signed issue recovery did not stop merely because JT1 acknowledged delivery")
	local row = a.ns.JusticeTasks.ResponseMetric().by[b.name]
	eq(row.received, 1); eq(row.attempted, 0); eq(row.medianSeconds, nil); eq(row.completed, 0)
end)
test("Justice shared: missing native keys expire pending proofs rather than extending their lifetime on every retry", function()
	local a, b, c = Triple(); Complete(a, b)
	c.bindingMissing = true
	c.now = a.now; c.scan()
	assert(c.ns.JusticeTasks.Sync(a.name)); Transfer(c, a); Transfer(a, c)
	assert(c.ns.JusticeTasks.SharedStatus().pendingProofs > 0)
	for _ = 1, 6 do c.now = c.now + 60; c.scan(); c.ns.JusticeTasks.Tick(); c.verify() end
	eq(c.ns.JusticeTasks.SharedStatus().pendingProofs, 0, "unavailable original identity cannot permanently occupy a pending-proof slot")
end)
test("Justice shared: revoked reader or issuer cannot leave reusable cryptographic trust from a delayed callback", function()
	local a, b, c = Triple(); local key = Complete(a, b); Enroll(a, c); Enroll(b, c)
	assert(c.ns.JusticeTasks.Sync(a.name)); Transfer(c, a); Transfer(a, c, nil, true)
	c.council[c.name] = nil; c.verify(); eq(Row(c, key), nil)
	c.council[c.name] = true; c.scan()
	local proof = Row(a, key).proofs.I
	for _, packet in ipairs(ProofPackets(proof)) do c.receive(a.name, packet) end
	eq(Row(c, key), nil, "restored authority must verify again, not reuse a verdict completed while revoked")
	c.verify(); assert(Row(c, key))
	c.reloadTasks(); c.ns.JusticeTasks.ResponseMetric()
	c.council[c.name] = nil; c.verify(); c.council[c.name] = true
	c.ns.JusticeTasks.ResponseMetric()
	eq(c.ns.JusticeTasks.ResponseMetric().by[b.name], nil, "saved-proof verification also refuses a verdict completed without reader authority")
	c.verify(); assert(c.ns.JusticeTasks.ResponseMetric().by[b.name])
	local x, y, z = Triple(); local other = Complete(x, y); Enroll(x, z); Enroll(y, z)
	assert(z.ns.JusticeTasks.Sync(x.name)); Transfer(z, x); Transfer(x, z, nil, true)
	local wasKing = z.ns.IsKingCharacter; z.ns.IsKingCharacter = function() return false end
	z.verify(); eq(Row(z, other), nil, "a queued original issuer verdict cannot survive current Crown authority loss")
	z.ns.IsKingCharacter = wasKing; z.scan()
	for _, packet in ipairs(ProofPackets(Row(x, other).proofs.I)) do z.receive(x.name, packet) end
	eq(Row(z, other), nil, "restored original issuer authority still requires a fresh verification")
	z.verify(); assert(Row(z, other))
end)
test("Justice shared: an expired solicitation cannot accept later unsolicited relay pages", function()
	local a, b, c = Triple(); local key = Complete(a, b)
	local d = Crypto(Client("CouncilTwo-Realm")); d.ranks = c.ranks; d.ranks[d.name] = 3; d.scan()
	for _, actor in ipairs({ a, b, c, d }) do actor.council[d.name] = true end
	Enroll(a, c); Enroll(b, c); Enroll(a, d); Enroll(b, d); Sync(a, d)
	assert(c.ns.JusticeTasks.Sync(d.name)); Transfer(c, d)
	c.now = c.now + c.ns.JusticeTasks.SHARE_KEEP + 1; c.scan()
	for _, packet in ipairs(ProofPackets(Row(d, key).proofs.I)) do c.receive(d.name, packet) end
	c.verify(); eq(Row(c, key), nil, "original signatures do not turn a past query into an indefinite relay subscription")
end)
test("Justice shared: the canonical author can consolidate and relay original proofs privately without issue, terminal or kick powers", function()
	local a, b, c = Triple(); local key = Complete(a, b)
	local d = Crypto(Client("Author-Realm")); d.ranks = a.ranks; d.scan()
	eq(d.ns.JusticeTasks.CanReadShared(), true); eq(d.ns.JusticeTasks.CanIssue(), false)
	Enroll(a, d); Enroll(b, d); Sync(a, d)
	local t = assert(Row(d, key)); eq(t.confirmedBy, a.name)
	eq(d.ns.JusticeTasks.ResponseMetric().by[b.name].completed, 1)
	eq(d.ns.JusticeTasks.Issue(d.guild, b.name, "Other-Realm"), false)
	eq(d.ns.JusticeTasks.Confirm(key), false); eq(d.ns.JusticeTasks.Cancel(key), false)
	eq(d.ns.JusticeTasks.AskRemoval(key), false); eq(#d.native, 0)
	Enroll(a, c); Enroll(b, c); a.offline, b.offline = true, true
	local _, assigneePK = b.ns.Debts.ClaimParts()
	eq(c.ns.JusticeTasks.HasKey(b.name, assigneePK), true, "a firsthand native-confirmed correspondent key can arrive before its task")
	Sync(d, c); eq(c.ns.JusticeTasks.ResponseMetric().by[b.name].completed, 1, "the read-only author remains a private recovery peer while originals are offline")
	d.preview = true; eq(d.ns.JusticeTasks.CanReadShared(), false); eq(d.ns.JusticeTasks.Sync(c.name), false)
	d.preview = false; d.ns.me = "Other-Realm"; eq(d.ns.JusticeTasks.CanReadShared(), false)
	d.ns.me = "Author-Elsewhere"; eq(d.ns.JusticeTasks.CanReadShared(), false, "same short author name from another realm group is not the pinned author")
	eq(c.ns.JusticeTasks.Sync(d.ns.me), false)
end)

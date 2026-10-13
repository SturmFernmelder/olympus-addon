local base, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]history%-carry%.lua$") or "./"

-- Real Carry, Comm scheduler/dispatch, Loot book and Court/Chronicle readers. The fixture
-- supplies a server roster/authority verdict and native whisper API, never a second codec.
local function Client(name, guild)
	local w = { name = name, guild = guild, snapshotGuild = guild, fresh = true, now = 1800000000,
		members = {}, roles = {}, sent = {}, events = {}, dialogs = {}, login = nil }
	local n = setmetatable({ me = name, realm = "Realm", group = "Realm", faction = "Alliance",
		db = { blocked = {} }, rdb = { guilds = {} }, RealmPages = {}, UI = {}, Filter = {},
		WatchChat = {}, Moderation = { OwnGuildOff = function() return false end, Blocks = function() return false end },
		ViewAs = { Previewing = function() return false end } }, { __index = base })
	w.ns = n
	n.Now = function() return w.now end
	n.IsMember = function() return type(w.guild) == "string" and base.IsFederation(w.guild) end
	n.On = function(event, fn) if event == "LOGIN" then w.login = fn end end
	n.After, n.Every, n.Fire, n.Print, n.Log = function() end, function() end, function() end, function() end, function() end
	n.RegisterEvent = function(event, fn) w.events[event] = fn end
	n.SafeCall = function(_, fn, ...) return fn(...) end
	n.King = { Register = function() end }
	n.Roster = { Fresh = function() return w.fresh and w.snapshotGuild == w.guild and {} or nil end,
		RankOf = function(who) return w.members[base.Fold(base.FullName(who))] end,
		IsOfficer = function() return (w.members[base.Fold(name)] or 99) <= 1 end }
	n.Data = { AuthorizedRank = function(who, where)
		if where == w.guild then
			local rank = n.Roster.RankOf(who); return rank, rank ~= nil and "roster" or nil
		end
		local r = w.roles[base.Fold(who)]
		if r and r.guild == where then return r.rank, r.source end
	end }
	n.Authority = { Role = function(who)
		local r = w.roles[base.Fold(who)]
		if r then return r.guild, r.rank, r.source end
	end }
	n.Dialog = { Show = function(which, a, b, data)
		w.dialogs[#w.dialogs + 1] = { which = which, data = data }; return true
	end }
	n.Acts = { Pardoned = function() return w.pardoned == true end }
	local env = setmetatable({ StaticPopupDialogs = {}, GetGuildInfo = function() return w.guild end,
		IsInGuild = function() return w.guild ~= nil end, GetTime = function() return w.now end,
		GetServerTime = function() return w.now end, GetLocale = function() return "enUS" end,
		GetChannelName = function() return 0 end, JoinChannelByName = function() end,
		LeaveChannelByName = function() end, HideChannelFromChat = function() end,
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function(_, msg, dist, target)
			w.sent[#w.sent + 1] = { text = msg, dist = dist, target = target }; return true
		end } }, { __index = _G })
	w.env = env
	local function Load(file) local chunk = assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua")); setfenv(chunk, env); chunk("Olympus", n) end
	Load("Comm"); local login = w.login; login()
	n.L = setmetatable({}, { __index = base.L })
	Load("Locales/CarryText"); Load("Loot"); Load("Chronicle"); Load("Court"); Load("Carry")
	function w.member(who, rank) w.members[base.Fold(base.FullName(who))] = rank end
	function w.move(to) w.guild, w.snapshotGuild = to, to end
	function w.pump()
		for _ = 1, 70 do w.now = w.now + 1.2; n.Comm.Pump() end
	end
	function w.receive(sender, text, dist)
		w.events.CHAT_MSG_ADDON(n.PREFIX, text, dist or "WHISPER", sender)
	end
	return w
end
local function Setup()
	local m, g = Client("Migrant-Realm", "Olympus II"), Client("Lord-Realm", "Olympus III")
	m.member(m.name, 3); g.member(g.name, 0); g.member(m.name, 3)
	m.roles[base.Fold(g.name)] = { guild = g.guild, rank = 0, source = "signed" }
	local book = m.ns.Loot.Book()
	book.notes.first = { writer = "Writer-Realm", by = "Relay-Realm", via = "Relay-Realm", t = m.now - 100,
		rev = m.now - 100, text = "Passed the gloves", item = 1, to = m.name }
	book.notes.other = { writer = "Writer-Realm", t = m.now - 90, text = "Other person's loot", to = "Other-Realm" }
	assert(m.ns.Chronicle.Add("court", "King-Realm", "Private royal message", {
		id = "King-Realm:42:" .. (m.now - 80) .. ":" .. m.name, to = m.name, words = "Keep your word" }))
	assert(m.ns.Chronicle.Add("court", "King-Realm", "Other", { to = "Other-Realm", words = "Do not carry this" }))
	return m, g
end
local function Prepared(m, g)
	assert(m.ns.Carry.Prepare(g.name)); eq(#m.sent, 0)
	local d = m.dialogs[#m.dialogs].data
	assert(m.ns.Carry.Confirm(d)); return d
end
local function Offered(m, g)
	local d = Prepared(m, g)
	m.move(g.guild); m.member(g.name, 0)
	assert(m.ns.Carry.Offer()); m.pump()
	local text = m.sent[#m.sent].text
	g.receive(m.name, text)
	local key = base.Fold(m.name) .. ":" .. d.id
	return d, key, text
end
local function Accept(g, key)
	assert(g.ns.Carry.Accept(key)); eq(#g.sent, 0, "opening the question sends nothing")
	assert(g.ns.Carry.Accept(key, g.dialogs[#g.dialogs].data)); g.pump()
	return g.sent[#g.sent].text
end
local function Data(m, g, acceptance)
	m.receive(g.name, acceptance); m.pump()
	local pieces = {}
	for _, msg in ipairs(m.sent) do if msg.text:sub(1, 7) == "XC~1~D~" then pieces[#pieces + 1] = msg.text end end
	return pieces
end

test("carry: member export excludes private Loot even when named as recipient and preserves own Court server time", function()
	local m, g = Setup(); local rows = m.ns.Carry.Gather()
	eq(#rows, 1, "private Loot is not subject-readable/exportable material")
	eq(rows[1].kind, "C"); eq(rows[1].at, m.now - 80); eq(tonumber(rows[1].a), m.now)
	eq(rows[1].by, "King-Realm")
	m.ns.rdb.pardons = { migrant = m.now - 20 }; m.pardoned = true
	rows = m.ns.Carry.Gather(); eq(#rows, 2); eq(rows[2].kind, "P"); eq(rows[2].a, "", "no fabricated King's deadline")
	eq(#m.sent, 0); eq(m.ns.Carry.Prepare("Unknown-Realm"), false)
	m.roles[base.Fold(g.name)].source = "census"; eq(m.ns.Carry.Prepare(g.name), false, "census rank is no authority")
	m.roles[base.Fold(g.name)].source = "signed"; m.fresh = false; eq(m.ns.Carry.Prepare(g.name), false)
end)

test("carry: two explicit consents, manual guild move, private real transport, and no authoritative writes", function()
	local m, g = Setup(); local d = Prepared(m, g)
	eq(m.ns.Carry.Offer(), false, "source guild cannot send the snapshot")
	m.move(g.guild); m.member(g.name, 0); assert(m.ns.Carry.Offer()); m.pump()
	local offer = m.sent[#m.sent]; g.receive(m.name, offer.text)
	local key = base.Fold(m.name) .. ":" .. d.id
	eq(g.ns.Carry.Accept(key, true), false, "forged confirmation")
	local pieces = Data(m, g, Accept(g, key)); assert(#pieces > 0)
	for _, msg in ipairs(pieces) do assert(#msg <= 255); g.receive(m.name, msg) end
	local entries = g.ns.Carry.List(); eq(#entries, 1); eq(entries[1].entry.unverified, true)
	eq(entries[1].entry.recipient, g.name); eq(#entries[1].entry.rows, 1)
	local text = {}; for _, line in ipairs(g.ns.Carry.Lines()) do text[#text + 1] = line.text end
	text = table.concat(text, "\n"); assert(text:find("Unverified quote", 1, true)); assert(text:find("King-Realm", 1, true))
	assert(text:find("Keep your word", 1, true)); assert(not text:find("Passed the gloves", 1, true), "member cannot expose the private Loot book")
	eq(next(g.ns.Loot.Book().notes), nil); eq(#g.ns.Court.Messages(), 0); eq(g.ns.rdb.pardons, nil); eq(g.ns.rdb.dues, nil)
	for _, msg in ipairs(m.sent) do eq(msg.dist, "WHISPER"); eq(msg.target, base.TellName(g.name)) end
	for _, msg in ipairs(g.sent) do eq(msg.dist, "WHISPER"); eq(msg.target, base.TellName(m.name)) end
	g.receive(m.name, offer.text); eq(g.ns.Carry.Accept(key), false, "durable replay floor")
	for _, msg in ipairs(pieces) do g.receive(m.name, msg) end
	eq(#g.ns.Carry.List(), 1)
	assert(m.ns.Carry.Revoke()); m.pump(); g.receive(m.name, m.sent[#m.sent].text)
	eq(#g.ns.Carry.List(), 0); eq(entries[1].entry.revoked, true)
	g.receive(m.name, offer.text); eq(g.ns.Carry.Accept(key), false)
end)

test("carry: sender forgery, wrong recipient, missing consent, public packets and realm/faction mismatch are refused", function()
	local m, g = Setup(); local d, key, offer = Offered(m, g)
	local other = Client("OtherLord-Realm", g.guild); other.member(other.name, 1); other.member(m.name, 3)
	other.receive(m.name, offer); eq(other.ns.Carry.Accept(key), false)
	m.receive("Pretender-Realm", "XC~1~A~" .. d.id .. "~" .. d.digest); m.pump(); eq(#m.sent, 1)
	g.receive("Unknown-Realm", offer); eq(g.ns.Carry.Accept(base.Fold("Unknown-Realm") .. ":" .. d.id), false)
	local blind = Client(g.name, g.guild); blind.member(g.name, 0); blind.member(m.name, 3)
	blind.receive(m.name, offer, "CHANNEL"); eq(blind.ns.Carry.Accept(key), false)
	blind.ns.faction = "Horde"; blind.receive(m.name, offer); eq(blind.ns.Carry.Accept(key), false)
	blind.ns.faction, blind.ns.group = "Alliance", "OtherGroup"; blind.receive(m.name, offer); eq(blind.ns.Carry.Accept(key), false)
	local pieces = Data(m, g, Accept(g, key))
	local unaccepted = Client(g.name, g.guild); unaccepted.member(g.name, 0); unaccepted.member(m.name, 3); unaccepted.receive(m.name, offer)
	for _, msg in ipairs(pieces) do unaccepted.receive(m.name, msg); g.receive("Unknown-Realm", msg) end
	eq(#unaccepted.ns.Carry.List(), 0); eq(#g.ns.Carry.List(), 0)
end)

test("carry: guild and role changes invalidate consent, queued batches and imported private views", function()
	local m, g = Setup(); local d, key = Offered(m, g); local accept = Accept(g, key)
	m.receive(g.name, accept); m.member(g.name, 1); m.pump(); eq(#m.sent, 1, "real queue guard refuses demoted recipient")
	m.member(g.name, 0); m.receive(g.name, accept); m.move("Olympus IV"); m.pump(); eq(#m.sent, 1, "real guild session cancels queued pieces")
	m.move(g.guild); m.ns.me = "UnknownAlt-Realm"; eq(m.ns.Carry.Offer(), false, "no alt identity inheritance")
	m.ns.me = m.name; m.ns.group = "OtherGroup"; eq(m.ns.Carry.Offer(), false)
	local a, b = Setup(); local _, k = Offered(a, b); local parts = Data(a, b, Accept(b, k))
	for _, msg in ipairs(parts) do b.receive(a.name, msg) end
	eq(#b.ns.Carry.List(), 1); b.member(b.name, 1); eq(#b.ns.Carry.List(), 0)
	b.member("Replacement-Realm", 0); b.ns.me = "Replacement-Realm"; eq(#b.ns.Carry.List(), 0, "saved quote copy belongs to its exact consenting GM")
	b.ns.me = b.name; b.member(b.name, 0); b.snapshotGuild = "Olympus II"; eq(#b.ns.Carry.List(), 0, "old roster is not authority after moving")
end)

test("carry: revocation before completion and conflicting duplicate offer/fragment close the transfer", function()
	local m, g = Setup(); local d, key, offer = Offered(m, g); local parts = Data(m, g, Accept(g, key))
	g.receive(m.name, parts[1]); g.receive(m.name, "XC~1~R~" .. d.id .. "~" .. d.digest)
	for _, msg in ipairs(parts) do g.receive(m.name, msg) end
	eq(#g.ns.Carry.List(), 0); g.receive(m.name, offer); eq(g.ns.Carry.Accept(key), false)
	local a, b = Setup(); local _, k, o = Offered(a, b)
	b.receive(a.name, o:sub(1, -2) .. (o:sub(-1) == "0" and "1" or "0")); eq(b.ns.Carry.Accept(k), false)
	local x, y = Setup()
	-- Removing the private Loot row makes the fixture shorter than one packet. Keep this
	-- assembler regression genuinely multipart with an allowed own Court quote instead.
	local gather = x.ns.Carry.Gather
	x.ns.Carry.Gather = function() local rows = gather(); rows[1].words = string.rep("x", 160); return rows end
	local _, z = Offered(x, y); local p = Data(x, y, Accept(y, z)); assert(#p > 1)
	y.receive(x.name, p[1]); y.receive(x.name, p[1]:sub(1, -2) .. "Z")
	for _, msg in ipairs(p) do y.receive(x.name, msg) end
	eq(#y.ns.Carry.List(), 0); eq(y.ns.Carry.Accept(z), false)
end)

test("carry: packet, assembler, pending, import and durable floor bounds reject malformed inputs", function()
	local m, g = Setup(); local d, key, offer = Offered(m, g); Accept(g, key)
	eq(g.ns.Carry.Handle("WHISPER", m.name, "XC~1~D~" .. d.id .. "~" .. d.digest .. "~1~99~x"), false)
	eq(g.ns.Carry.Handle("WHISPER", m.name, string.rep("x", 256)), false)
	eq(g.ns.Carry.Decode(string.rep("x", 4097), 1), nil)
	eq(g.ns.Carry.Decode("L~i~b~1~~%7C~~~Migrant-Realm", 1), nil, "no UI escape injection")
	eq(g.ns.Carry.Decode("L~i~b~1~~%GG~~~Migrant-Realm", 1), nil)
	local reader = Client(g.name, g.guild); reader.member(g.name, 0); reader.member(m.name, 3)
	for i = 1, reader.ns.Carry.PENDING do
		local id = ("%016x"):format(i); local o = offer:gsub(d.id, id)
		assert(reader.ns.Carry.Handle("WHISPER", m.name, o))
	end
	eq(reader.ns.Carry.Handle("WHISPER", m.name, offer:gsub(d.id, "ffffffffffffffff")), false)
	local floors = g.ns.rdb.historyCarry.floors
	for i = 1, g.ns.Carry.FLOORS - 1 do floors["floor" .. i] = "received" end
	eq(g.ns.Carry.Handle("WHISPER", m.name, offer:gsub(d.id, "ffffffffffffffff")), false, "pending offer reserves its floor")
	g.receive(m.name, "XC~1~R~" .. d.id .. "~" .. d.digest)
	local total = 0; for _ in pairs(floors) do total = total + 1 end; eq(total, g.ns.Carry.FLOORS)
end)

test("carry: expiry and explicit sender cancellation stop real queued transfer data", function()
	local m, g = Setup(); local _, key = Offered(m, g)
	g.now = g.now + g.ns.Carry.OFFER_LIFE + 1; eq(g.ns.Carry.Accept(key), false)
	local a, b = Setup(); local _, k = Offered(a, b); local acceptance = Accept(b, k)
	a.receive(b.name, acceptance); assert(a.ns.Carry.Revoke()); a.pump()
	for _, msg in ipairs(a.sent) do assert(msg.text:sub(1, 7) ~= "XC~1~D~", "cancelled data never reaches native whisper") end
end)

test("carry: legacy private Loot rows and a full import store never become visible quotes", function()
	local m, g = Setup()
	local private = m.ns.Carry.Encode({ { kind = "L", id = "private", by = "Writer-Realm", at = m.now,
		guild = m.guild, words = "Secret officer note", via = "", a = "1", b = "item", c = m.name } })
	assert(private); eq(g.ns.Carry.Decode(private, 1), nil, "old XC1 Loot claims are refused even for the exact named member")
	eq(#g.ns.Carry.List(), 0)
	local a, b = Setup(); local _, k = Offered(a, b); local p = Data(a, b, Accept(b, k))
	for i = 1, b.ns.Carry.IMPORTS do b.ns.rdb.historyCarry.imported["retained" .. i] = {} end
	for _, msg in ipairs(p) do b.receive(a.name, msg) end
	eq(#b.ns.Carry.List(), 0); eq(b.ns.rdb.historyCarry.floors[k], "invalid")
end)

test("carry: both consent popups recheck current identity, guild, roster and role when answered", function()
	local m, g = Setup(); assert(m.ns.Carry.Prepare(g.name)); local d = m.dialogs[#m.dialogs].data
	m.move(g.guild); eq(m.ns.Carry.Confirm(d), false, "changing guild while preparing closes consent")
	local a, b = Setup(); local _, key = Offered(a, b)
	assert(b.ns.Carry.Accept(key)); local confirmation = b.dialogs[#b.dialogs].data
	b.member(b.name, 1); eq(b.ns.Carry.Accept(key, confirmation), false)
	b.member(b.name, 0); b.fresh = false; eq(b.ns.Carry.Accept(key, confirmation), false)
	b.fresh = true; assert(b.ns.Carry.Accept(key, confirmation)); b.member(b.name, 1); b.pump()
	eq(#b.sent, 0, "acceptance queued before demotion is cancelled at native send")
end)

test("carry: optional payer receipt quotes remain own-character observations and apply no payment", function()
	local m, g = Setup()
	m.ns.Dues = { Week = function() return 400 end, WEEKS_KEPT = 5, PayerReceiptFacts = function(week)
		if week ~= 400 then return {} end
		return {
			{ payer = m.name, issuer = "Pyralis-Realm", at = m.now - 50, guild = m.guild, bookPin = 1,
				sequence = 9, week = week, copper = 1000, amount = 1000, source = "pinned-treasurer-whisper" },
			{ payer = "UnknownAlt-Realm", issuer = "Pyralis-Realm", at = m.now - 50, guild = m.guild,
				bookPin = 1, sequence = 10, week = week, copper = 1000, amount = 1000 },
		}
	end }
	local rows = m.ns.Carry.Gather(); eq(#rows, 2); eq(rows[2].kind, "D"); eq(rows[2].by, "Pyralis-Realm")
	eq(rows[2].at, m.now - 50); eq(rows[2].words, "pinned-treasurer-whisper"); eq(rows[2].a, "400")
	local _, key = Offered(m, g); local pieces = Data(m, g, Accept(g, key))
	for _, msg in ipairs(pieces) do g.receive(m.name, msg) end
	eq(#g.ns.Carry.List(), 1); eq(g.ns.rdb.dues, nil); eq(g.ns.rdb.payerReceipts, nil)
end)

test("carry: all five shipped translations keep the same consent and provenance placeholders", function()
	local w = Client("Reader-Realm", "Olympus III")
	local english
	local function Placeholders(text) local out = {}; for p in text:gmatch("%%[ds]") do out[#out + 1] = p end; return table.concat(out) end
	for _, locale in ipairs({ "enUS", "ptBR", "deDE", "esES", "frFR" }) do
		w.env.GetLocale = function() return locale end
		w.ns.L = {}
		local chunk = assert(loadfile(ROOT .. "Olympus/Locales/CarryText.lua")); setfenv(chunk, w.env); chunk("Olympus", w.ns)
		if locale == "enUS" then english = w.ns.L else
			for key, text in pairs(english) do
				assert(type(w.ns.L[key]) == "string" and w.ns.L[key] ~= "", locale .. ": " .. key)
				eq(Placeholders(w.ns.L[key]), Placeholders(text), locale .. ": " .. key)
			end
		end
	end
end)

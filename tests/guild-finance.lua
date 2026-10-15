local ns, test, eq, H = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]guild%-finance%.lua$") or "./"
local FINANCE = os.getenv("OLYMPUS_FINANCE_MODULE_PREFIX") or ROOT .. "Olympus/GuildFinance.lua"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = ns })
-- Actual RSA-2048/e=3 public fixture and HA1 signatures, made in memory with the existing
-- council-sign.py algorithm. Its private half was discarded; no user key is read or changed.
-- Every scenario runs the real verifier with this public key, never a true-returning mock.
local AUTH = {
	N = "a090122fd7db1b1a7605d1bfa33051bf175acec3e69a15d643022623065acdbb71fd2c45a373022f12762951ac796d61e536ef610207f5e347a015ab49abdd29b9ad570dd6103c208ab49e04cf9fd8474a1bddb9097c73c5a78373125c77bf40128fad0933e8d905bcd26481c3f812a46732ea8c8bc466ed8f2731ec3cc93ab2e4e9d3b99170c255c523a6eda722164819b71e60466987dd428672d63bec250eff21ee4b47b5cff5a2d1d2c221b640b2f3074163d6bd42578cdf058030387fbe8d7537ed43bf92e8781fa33e4d09ac5d6883cb05cee94d94b95cef7f5e4ef782e122f2b66a9833072b000935e6700f849c42f96f3487872e4f75e2de31623717",
	MU = "1982a12241743cb767e1d256ada5ac726bc6b6c2a07bad1eceb001738d6701c0d906f948680f5a22930e8f4ae5deae1b5acaf16c96fdbb5a8441ef1e23af521b946aa5716abdd8109b7cf91c0a2c861ca20d460767a5f904b574f8e66f45d0f368645851ade01a70d6f9a6fbcac6fc669d60027350d41ff869e40bdf847c4cb9b2e7b897e5024d8a5ce19f7751d5b7b1496d8e404326a7016dc6de3aaec137baf448e7f09c005368aca14b02dec5bbee82739c3c10fbf9117d7be7c0d7c78b4057e12a35cca668ae0fb0a396bfc124258f7f3d855395150926556f2ee7bf4475eefd0a94b991214d21c80572cf0ea21a1ef499d031502475e3b6f5a8f19df52fa9376ccc0",
	K = 86,
	INITIAL = "HA1~1800000000~Emberfall+Emberfall2~Alliance~enforce~1~1800000000~1800100000~719efef9470684bd5667ff7ccc8189164f1ff1bfac71df1a04a3d5c12e4cdc84~1~1~Olympus Ember=Torvin Hale-Emberfall!Olympus Willow=Selka Drummond-Emberfall~0c62b1cbdc44e928c15421a94668b3c82ffd5ed4a75baef70c9d4cb3a458123ce7be8f6fba71a543453cd27bd44df0d1633e5a2a0e8e606a3a59cf40c2b50ac8b436badba11b981fd641fbe398ad17f4538b0c66a347103875c5c604f48b803065105dc34fc41140cfde36791031f9d8bbb729027033dd2f0a1003e53cd5d1fb1e4c8272f792985d8570c4d288c3265b2047348ac939fd2fce037f9d880a9a33dd699ec33078bbd71ef4ae68bda1570b11ef1d4d3cb686feb5e0db2f652c592787df249187d56f1e3b8898ec929e0dc45615df3765f10ded4bb6e9d5a28ac182f28495ce2f99ee75aa0ee123ec8dbbbc48752ad8166f5d44674baaf882094cc2",
	REVOKED = "HA1~1800000001~Emberfall+Emberfall2~Alliance~enforce~2~1800000000~1800100000~ee88405fe9cd0427166746a9c4b7a056204404dff1a693fb5a1c09ab8cb1212d~1~1~Olympus Willow=Selka Drummond-Emberfall~1804c05934eb85a125c6eaf554fde25136793b26369ded24f992b3e26fe2e55466e3cdb6ef0ffa2aa6c46d90dea70dfbee036609acce5a17347204e78839bb67ef805ec8717b696f95808fa136b59a94f3ea686ff893697e69b98f9e8a077f621e6fe2a1491411047877e7c1bcf95f9f7b506291e014452e988530fb94e7d54dfce8b2468ad828c05390a74d8d33222dac6a2349fd991f86ef54ce281946e88e35bbadc91e34dcc6077c27adbdd3c906191346a8c5416b48af00e9faf81ac33a73a82bd28362f3d8957fa5483b9ca76cfe8fae0297d2a92bc69f0820b4a35a5c059c9cda17b02ee5144b67ad669d7770194003d0c22cd7356d7b94701f912386",
}
local runTest = test
test = function(name, fn) runTest(name, function() ns.Sign.WithKey(AUTH.N, AUTH.MU, AUTH.K, fn) end) end
local function Client(w, role, options)
	local c = w:Role(role, options)
	w:As(c, function()
		c.ns.L = setmetatable({}, { __index = ns.L })
		c.ns.ViewAs = { Previewing = function() return false end }
		local prefix = os.getenv("OLYMPUS_FINANCE_TREASURY_PREFIX")
		if prefix then
			-- Prefix proof uses the old complete Treasury source, including its real native
			-- event registrations; it must not retain the world's newer expense callbacks.
			local on, login = c.ns.On
			c.ns.On = function(event, fn) if event == "LOGIN" then login = fn else on(event, fn) end end
			assert(loadfile(prefix))("Olympus", c.ns)
			c.ns.On = on
			for _, event in ipairs({ "TRADE_SHOW", "TRADE_MONEY_CHANGED", "TRADE_ACCEPT_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED",
				"UI_INFO_MESSAGE", "TRADE_CLOSED", "MAIL_SEND_SUCCESS", "MAIL_FAILED", "PLAYER_MONEY" }) do c.events[event] = {} end
			assert(login); login()
		end
		for _, file in ipairs({ "Roster", "Authority", "Data" }) do assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c.ns) end
		assert(loadfile(FINANCE))("Olympus", c.ns)
		c.ns.Comm.Hash36 = ns.Comm.Hash36
		c.ns.Comm.Cancel = function() end
		-- The existing Treasury private-batch fixture: every piece still runs its real
		-- permission guard. No broad public transport or unguarded single-message shortcut.
		c.ns.Comm.SendBatch = function(dist, pieces, _, target, urgent, done, opts)
			w:Timer(c, 0, nil, function()
				if opts and opts.guard and not opts.guard() then if done then done(false) end; return end
				local left, failed = #pieces, false
				for _, piece in ipairs(pieces) do
					c.ns.Comm.Whisper(target, piece, nil, urgent, false, function(ok)
						failed, left = failed or not ok, left - 1
						if left == 0 and done then done(not failed) end
					end, opts)
				end
			end, "finance private batch")
			return true
		end
		local b = c.ns.Treasury.Book(); b.opening, b.openedAt = 0, w.clock
	end)
	return c
end
local function Scan(w)
	for _, c in ipairs(w.clients) do
		local peers = {}; for _, peer in ipairs(w.clients) do if peer.guild == c.guild then peers[#peers + 1] = peer end end
		c.globals.GetNumGuildMembers = function() return #peers, #peers end
		c.globals.GetGuildRosterInfo = function(i)
			local p = peers[i]; if p then return p.name, p.rankName, p.rank, 60, "Mage", "Stormwind", "", "", true, nil, "MAGE", nil, nil, nil, nil, nil, p.guid end
		end
		w:As(c, function() assert(c.ns.Roster.Scan()) end)
	end
end
local function Reports(w)
	for _, c in ipairs(w.clients) do
		w:As(c, function()
			c.ns.Comm.loginAt = w.clock - c.ns.Data.CROWN_AFTER - 1
			for _, leader in ipairs(w.clients) do if leader.rank == 0 and leader.guild ~= c.guild then
				for _, source in ipairs({ "First " .. leader.short .. "-Emberfall", "Second " .. leader.short .. "-Emberfall" }) do
					assert(c.ns.Data.Receive({ guild = leader.guild, leader = leader.short, total = 20, online = 2, faction = "Alliance", officers = {}, zones = {} }, source))
				end
			end end
		end)
	end
end
local function Setup(legacy)
	local w = World.New({ clock = 1800000000, council = false, arenaFiles = {}, compliance = "shipped" })
	local king, keeper = Client(w, "king"), Client(w, "treasurer")
	local lord, other, member = Client(w, "fighterA", { rank = 0 }), Client(w, "fighterB", { guild = "Olympus Willow", rank = 0 }), Client(w, "bettor1")
	Scan(w); Reports(w)
	if not legacy then for _, c in ipairs(w.clients) do w:As(c, function()
		assert(c.ns.Authority.TakePart(AUTH.INITIAL, nil, "LOCAL"), "the actual signed HA1 fixture must be accepted")
	end) end end
	w:As(keeper, function() keeper.db.keeperShares = { [keeper.name:lower()] = true } end)
	return w, king, keeper, lord, other, member
end
local function Event(w, keeper, guild, text)
	return w:As(keeper, function() return assert(keeper.ns.GuildFinance.CreateEvent(guild .. " | " .. (text or "Raid supplies"))) end)
end
local function Last(c) return c.ns.Treasury.Lines()[#c.ns.Treasury.Lines()] end
local function Receipt(w, keeper, donor, copper, out)
	w:Trade(keeper, donor, { aGives = out and copper or 0, bGives = out and 0 or copper })
	local e = Last(keeper); assert(e and e.financeReceipt, "actual native completed trade creates a finance receipt")
	return e
end
local function Allocate(w, keeper, e, event)
	return w:As(keeper, function() return keeper.ns.GuildFinance.Allocate(e.financeReceipt, event) end)
end

test("Guild finance: native completed trade expense is attributed once; offered/closed trade, manual book and item gold guesses are not proof", function()
	local w, _, t, lord = Setup()
	local id = Event(w, t, lord.guild)
	w:Trade(t, lord, { aGives = 20000, complete = false })
	w:As(t, function() eq(#t.ns.Treasury.Lines(), 0, "closing an offered trade is not a completed expense") end)
	w:Run(3)
	local e = Receipt(w, t, lord, 20000, true)
	eq(Allocate(w, t, e, id), true); eq(Allocate(w, t, e, id), false)
	w:As(t, function()
		local F, T = t.ns.GuildFinance, t.ns.Treasury
		local rows = F.LocalRows(); eq(rows[1].out, 20000); eq(rows[1].sent, 0)
		local manual = T.Record(lord.name, 30000, "trade", true, { quiet = true })
		eq(manual.financeReceipt, nil); eq(F.Allocate(99999, id), false)
		local item = T.Record(lord.name, 0, "trade", true, { item = 1710, count = 20, observed = true, quiet = true })
		eq(item.financeReceipt, nil, "materials are not guessed copper")
		eq(F.Allocate(e.financeReceipt, -1), false)
	end)
end)

test("Guild finance: native successful mail expense is sent not recipient received; pending/failed/success replay cannot allocate again", function()
	local w, _, t, lord = Setup(); local id = Event(w, t, lord.guild)
	t.mailOut = { copper = 12000, cod = 0, subject = "Raid supply payment" }
	w:As(t, function() SendMail(lord.name, "Raid supply payment", "") end)
	w:As(t, function() eq(#t.ns.Treasury.Lines(), 0) end)
	w:Fire(t, "MAIL_FAILED"); w:Fire(t, "MAIL_SEND_SUCCESS")
	w:As(t, function() eq(#t.ns.Treasury.Lines(), 0, "failed send cannot later become a finance receipt") end)
	w:Mail(t, lord, 12000, "Raid supply payment")
	local e = Last(t); assert(e.financeReceipt, "MAIL_SEND_SUCCESS proves the captured native outgoing money")
	eq(Allocate(w, t, e, id), true)
	w:Fire(t, "MAIL_SEND_SUCCESS")
	w:As(t, function()
		local row = t.ns.GuildFinance.LocalRows()[1]
		eq(row.out, 12000); eq(row.sent, 12000, "sent is a separate caveat, not delivery")
		eq(#t.ns.Treasury.Lines(), 1)
	end)
end)

test("Guild finance: recognized income guild cannot cross guild; unknown native income is visible but unattributed; excluded/custody/transfer receipts never inflate totals", function()
	local w, _, t, lord, other = Setup()
	local own, wrong = Event(w, t, lord.guild), Event(w, t, other.guild)
	local e = Receipt(w, t, lord, 17000)
	eq(Allocate(w, t, e, wrong), false); eq(Allocate(w, t, e, own), true)
	w:As(t, function()
		local F, T = t.ns.GuildFinance, t.ns.Treasury
		local unknown = T.Record("Unknown Giver", 15000, "trade", nil, { observed = true, quiet = true })
		assert(unknown.financeReceipt); eq(F.Allocate(unknown.financeReceipt, own), false)
		local lines = F.Build(); local found = false
		for _, line in ipairs(lines) do if tostring(line.text):find("unknown guild", 1, true) then found = true end end
		assert(found, "unknown-source native income has an explicit unattributed bucket")
		for _, kind in ipairs({ "transfer", "craft", "arena", "fee", "own", "sale" }) do
			local r = T.Record("Excluded Giver", 10000, "trade", nil, { kind = kind, guild = lord.guild, observed = true, quiet = true })
			eq(r.financeReceipt, nil, kind)
		end
		local row = F.LocalRows()[1]; eq(row.inn, 17000)
	end)
end)

test("Guild finance: correction and ambiguous returned mail zero attribution, stay auditable, and cannot revive after source eviction or reload", function()
	local w, _, t, lord = Setup(); local id = Event(w, t, lord.guild)
	w:Mail(t, lord, 12000, "Same payment"); local e = Last(t); assert(e.financeReceipt); eq(Allocate(w, t, e, id), true)
	w:Mail(t, lord, 12000, "Same payment"); local newer = Last(t); assert(newer.financeReceipt); eq(Allocate(w, t, newer, id), true)
	w:Return(lord, 1); w:Take(t, #t.inbox)
	w:As(t, function()
		local F = t.ns.GuildFinance
		F.Reconcile()
		local row = F.LocalRows()[1]; eq(row.out, 0); eq(row.corrected, 2); eq(row.unknown, 24000, "an equal-amount return cannot identify which event's receipt returned")
		local a = t.ns.rdb.guildFinance.actors[t.name]
		eq(a.receipts[newer.financeReceipt].status, "return-unknown", "same-value legacy matching is not an exact certified refund")
		local rev = a.rev; F.Reconcile(); eq(a.rev, rev, "stable unknown return does not churn revisions")
		t.ns.Treasury.Toggle(e); eq(F.LocalRows()[1].out, 0)
		local b = t.ns.Treasury.Book(); b.lines = {}
		t.ns.rdb = World.Copy(t.ns.rdb)
		assert(loadfile(FINANCE))("Olympus", t.ns)
		eq(t.ns.GuildFinance.LocalRows()[1].out, 0, "eviction/reload cannot revive corrected attributed money")
	end)
end)

test("Guild finance: current Lord sees only own guild aggregates by real private transport; outsider, wrong guild, preview and revoked role receive nothing", function()
	local w, king, t, lord, other, member = Setup()
	local id, otherid = Event(w, t, lord.guild), Event(w, t, other.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 15000), id), true)
	eq(Allocate(w, t, Receipt(w, t, other, 35000), otherid), true)
	w:As(t, function() eq(t.ns.GuildFinance.MayView(lord.guild, lord.name), true, "keeper verifies the current remote Lord from the actual signed manifest") end)
	w:As(lord, function() eq(lord.ns.GuildFinance.Visible(), true); eq(lord.ns.GuildFinance.MayView("*"), false); eq(lord.ns.GuildFinance.Ask(other.guild), false); assert(lord.ns.GuildFinance.Ask(lord.guild)) end)
	w:Run(15)
	w:As(lord, function()
		local held = lord.ns.GuildFinance.Held(lord.guild); eq(#held, 1, table.concat(t.errors, "; ") .. " / " .. table.concat(lord.errors, "; "))
		for _, r in pairs(held[1].rows) do eq(r.guild, lord.guild); eq(r.inn, 15000) end
	end)
	for _, c in ipairs({ member, other }) do w:As(c, function() eq(c.ns.GuildFinance.Ask(lord.guild), false); eq(#c.ns.GuildFinance.Held(lord.guild), 0) end) end
	w:As(king, function() assert(king.ns.GuildFinance.Ask("*")) end); w:Run(15)
	w:As(king, function() eq(#king.ns.GuildFinance.Held("*"), 1) end)
	lord.rank = 1; Scan(w)
	w:As(lord, function() eq(lord.ns.GuildFinance.Visible(), false); eq(#lord.ns.GuildFinance.Held(lord.guild), 0) end)
	w:As(t, function() t.ns.ViewAs.Previewing = function() return true end; eq(t.ns.GuildFinance.CreateEvent(lord.guild .. " | Pretend"), false); eq(t.ns.GuildFinance.Visible(), false) end)
	local channel = w:ChannelText(); assert(not channel:find("GF~", 1, true)); assert(not channel:find("Raid supplies", 1, true), "finance event categories/details never reach the army by default")
end)
test("Guild finance: two census claims cannot grant a private financial audience, while a real signed current Lord can", function()
	local w, king, t, lord, _, member = Setup(true)
	local event = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 19000), event), true)
	w:As(t, function()
		local invented = "Olympus Phony"
		for _, witness in ipairs({ "False Witness-Emberfall", "Other Witness-Emberfall" }) do
			assert(t.ns.Data.Receive({ guild = invented, leader = member.short, total = 20, online = 2, faction = "Alliance", officers = {}, zones = {} }, witness))
		end
		local fakeRank, fakeSource, votes = t.ns.Data.AuthorizedRank(member.name, invented)
		eq(fakeRank, 0); eq(fakeSource, "census"); assert(votes >= 2)
		eq(t.ns.GuildFinance.MayView(invented, member.name), false, "two reports cannot turn a real ordinary member into a private-book reader")
		eq(t.ns.GuildFinance.Handle("WHISPER", member.name, ("GF~1~Q~%.0f~%s~%s"):format(w.clock * 1000, invented, invented)), false)
		local rank, source, support = t.ns.Data.AuthorizedRank(lord.name, lord.guild)
		eq(rank, 0); eq(source, "census"); assert(support >= 2)
		eq(t.ns.GuildFinance.MayView(lord.guild, lord.name), false, "corroborated directory reports are not current office proof")
		eq(t.ns.GuildFinance.Handle("WHISPER", lord.name, ("GF~1~Q~%.0f~%s~%s"):format(w.clock * 1000, lord.guild, lord.guild)), false)
		local forged = AUTH.INITIAL:gsub("Torvin Hale", "Lida Fenn")
		eq(t.ns.Authority.TakePart(forged, nil, "LOCAL"), false, "a changed manifest fails the real RSA signature")
		eq(t.ns.GuildFinance.MayView(lord.guild, lord.name), false)
		assert(t.ns.Authority.TakePart(AUTH.INITIAL, nil, "LOCAL"))
		eq(select(2, t.ns.Data.AuthorizedRank(lord.name, lord.guild)), "signed")
		eq(t.ns.GuildFinance.MayView(lord.guild, lord.name), true)
	end)
	w:As(lord, function() assert(lord.ns.GuildFinance.Ask(lord.guild)) end); w:Run(15)
	w:As(lord, function() eq(#lord.ns.GuildFinance.Held(lord.guild), 1) end)
	w:As(t, function()
		assert(t.ns.Authority.TakePart(AUTH.REVOKED, nil, "LOCAL"))
		eq(t.ns.GuildFinance.MayView(lord.guild, lord.name), false, "a newer signed revocation supersedes the still-present census reports")
	end)
end)

test("Guild finance: fresh requested snapshots survive offline/reload as stale partial facts, reject replay/conflicts and native source revocation", function()
	local w, king, t, lord = Setup(); local id = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 19000), id), true)
	local query
	w:As(king, function()
		local private = king.ns.Treasury.Private; king.ns.Treasury.Private = function(_, _, text) query = text; return true end
		assert(king.ns.GuildFinance.Ask("*")); king.ns.Treasury.Private = private
	end)
	local q = assert(tonumber(query:match("Q~(%d+)")))
	local msg = w:As(t, function() return assert(t.ns.GuildFinance.Message(q, t.name, "*")) end)
	w:As(king, function()
		local F = king.ns.GuildFinance
		eq(F.Handle("CHANNEL", t.name, msg), false); eq(F.Handle("WHISPER", lord.name, msg), false)
		eq(F.Handle("WHISPER", t.name, msg), true); eq(F.Handle("WHISPER", t.name, msg), true)
		local saved = World.Copy(king.ns.rdb); king.ns.rdb = saved
		assert(loadfile(FINANCE))("Olympus", king.ns)
		eq(#king.ns.GuildFinance.Held("*"), 1, "old offline facts persist without pretending to be fresh")
	end)
	w:Run(901)
	w:As(king, function()
		local lines = king.ns.GuildFinance.Build(); local stale = false
		for _, line in ipairs(lines) do if tostring(line.text):find("stale", 1, true) then stale = true end end
		assert(stale)
	end)
	w:Run(15)
	w:As(t, function() t.ns.Treasury.SetConsent(false) end)
	w:Run(181)
	w:As(king, function() assert(king.ns.GuildFinance.Ask("*")) end)
	w:Run(15)
	w:As(king, function() eq(#king.ns.GuildFinance.Held("*"), 0, "authenticated no removes the retained source") end)
end)

test("Guild finance: source and assignment bounds are explicit, and a revoked keeper's queued response guard cannot leak an earlier snapshot", function()
	local w, king, t, lord = Setup(); local id = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 23000), id), true)
	local guards, q = {}, math.floor(w.clock) * 1000
	w:As(t, function()
		local private = t.ns.Treasury.Private
		t.ns.Treasury.Private = function(to, kind, msg, key)
			local ok = private(to, kind, msg, key)
			local state = t.ns.Treasury.PrivateState(); if state.sending then guards[#guards + 1] = state.sending end
			return ok
		end
		eq(t.ns.GuildFinance.Handle("WHISPER", king.name, ("GF~1~Q~%.0f~*~%s"):format(q, king.guild)), true)
		t.ns.Treasury.Private = private
		t.ns.ViewAs.Previewing = function() return true end
	end)
	w:Run(15)
	for _, wire in ipairs(w:Sent({ from = t, to = king.name })) do assert(not wire.msg:find("TW~GF", 1, true), "preview/role change invalidates queued source") end
	w:As(t, function()
		t.ns.ViewAs.Previewing = function() return false end
		local F = t.ns.GuildFinance; F.RECEIPTS = 1
		local e = t.ns.Treasury.Record("New Giver", 10000, "trade", nil, { guild = lord.guild, observed = true, quiet = true })
		eq(e.financeReceipt, nil)
		eq(t.ns.rdb.guildFinance.actors[t.name].cut, true)
		F.EVENTS = 1; eq(F.CreateEvent(lord.guild .. " | Beyond cap"), false)
	end)
end)

test("Guild finance: same-revision conflict becomes unknown, lower replay cannot replace it, and only a newer requested actual source recovers", function()
	local w, king, t, lord = Setup(); local id = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 19000), id), true)
	local query
	w:As(king, function()
		local private = king.ns.Treasury.Private; king.ns.Treasury.Private = function(_, _, text) query = text; return true end
		assert(king.ns.GuildFinance.Ask("*")); king.ns.Treasury.Private = private
	end)
	local q = assert(tonumber(query:match("Q~(%d+)")))
	local msg = w:As(t, function() return assert(t.ns.GuildFinance.Message(q, t.name, "*")) end)
	w:As(king, function()
		local F = king.ns.GuildFinance
		eq(F.Handle("WHISPER", t.name, msg), true)
		local conflicting = msg:gsub("/19000/0/0/0/19000/0$", "/29000/0/0/0/19000/0")
		assert(conflicting ~= msg)
		eq(F.Handle("WHISPER", t.name, conflicting), false); eq(#F.Held("*"), 0)
		eq(F.Handle("WHISPER", t.name, msg), false, "same revision cannot wish away conflicting provenance")
		local old = msg:gsub("(~%d+)(~%d+~0~)", function(rev, tail) return "~" .. (tonumber(rev:sub(2)) - 1) .. tail end, 1)
		eq(F.Handle("WHISPER", t.name, old), false)
	end)
	eq(Allocate(w, t, Receipt(w, t, lord, 5000), id), true)
	local newer = w:As(t, function() return assert(t.ns.GuildFinance.Message(q, t.name, "*")) end)
	w:As(king, function() eq(king.ns.GuildFinance.Handle("WHISPER", t.name, newer), true); eq(#king.ns.GuildFinance.Held("*"), 1) end)
end)

test("Guild finance: pinned primary privately relays its own-account mail actor only with both current consents; held provenance remains the real original sender", function()
	local w, king, t, lord = Setup()
	local mail = Client(w, "treasurerMail", { guild = "Mail House" })
	Scan(w)
	local e = Receipt(w, mail, lord, 25000)
	w:As(t, function()
		-- The same account's character-specific SavedVariables, not a received peer ledger.
		t.ns.GuildFinance.Build()
		t.ns.rdb.guildFinance.actors[mail.name] = World.Copy(mail.ns.rdb.guildFinance.actors[mail.name])
		t.ns.rdb.treasuryBooks[mail.name:lower()] = World.Copy(mail.ns.Treasury.Book())
		t.db.keeperShares[mail.name:lower()] = true
		local id = assert(t.ns.GuildFinance.CreateEvent(lord.guild .. " | Mail supplies", mail.name))
		eq(t.ns.GuildFinance.Allocate(e.financeReceipt, id, mail.name), true)
	end)
	w:As(king, function() assert(king.ns.GuildFinance.Ask("*")) end); w:Run(15)
	w:As(king, function()
		local held = king.ns.GuildFinance.Held("*"); eq(#held, 1)
		eq(held[1].actor, mail.name); eq(held[1].from, t.name)
		for _, r in pairs(held[1].rows) do eq(r.inn, 25000) end
	end)
	w:As(t, function() t.ns.Treasury.SetConsent(false) end); w:Run(2)
	w:As(king, function() eq(#king.ns.GuildFinance.Held("*"), 0, "the primary's current no also ends the snapshots it relayed for its mail character") end)
	w:As(t, function() t.ns.Treasury.SetConsent(true) end)
	w:Run(181); Scan(w); Reports(w)
	w:As(t, function() t.db.keeperShares[mail.name:lower()] = false end)
	w:As(king, function() assert(king.ns.GuildFinance.Ask("*")) end); w:Run(15)
	w:As(king, function() eq(#king.ns.GuildFinance.Held("*"), 0, "mail actor's own consent cannot be replaced by the primary's yes") end)
end)

test("Guild finance: native amount/guild edits, stale recognition and keeper loss reject allocation; a counted actual native purchase can be attributed without inventing item value", function()
	local w, _, t, lord, other = Setup(); local id = Event(w, t, lord.guild)
	local e = Receipt(w, t, lord, 23000)
	w:As(t, function()
		local F = t.ns.GuildFinance
		e.money = 46000; eq(F.Allocate(e.financeReceipt, id), false, "manual amount edits are not a larger native receipt")
		e.money = 23000; e.guild = other.guild; eq(F.Allocate(e.financeReceipt, id), false, "changing the book guild cannot change original capture provenance")
		e.guild = lord.guild
		local original = e.name; e.name = other.name
		eq(F.Allocate(e.financeReceipt, id), false, "editing the receipt recipient cannot rewrite the observed native partner")
		e.name = original
		t.ns.rdb.guilds[lord.guild].t = w.clock - t.ns.Data.FRESH - 1
		eq(F.Allocate(e.financeReceipt, id), false, "stale guild recognition cannot authorize a new attribution")
	end)
	Reports(w)
	w:As(t, function()
		t.ns.faction = "Horde"; eq(t.ns.GuildFinance.Allocate(e.financeReceipt, id), false)
		t.ns.faction = "Alliance"
	end)
	w:Trade(t, lord, { aGives = 11000, bItems = { { name = "Potion", link = "item:1710", count = 2 } } })
	local lines = t.ns.Treasury.Lines(); local purchase
	for _, r in ipairs(lines) do if r.kind == "purchase" and not r.item then purchase = r end end
	assert(purchase and purchase.financeReceipt, "native money paid for items retains its actual expense source")
	eq(Allocate(w, t, purchase, id), false, "the keeper has not counted this purchase as the treasury's")
	w:As(t, function() t.ns.Treasury.Toggle(purchase) end)
	eq(Allocate(w, t, purchase, id), true)
	w:As(t, function() eq(t.ns.GuildFinance.LocalRows()[1].out, 11000, "only exact native copper paid, not the items' guessed vendor/market value") end)
end)

test("Guild finance: private transport completion callback is not receiver ACK and never runs for failed or revoked queued sends", function()
	local w, king, t = Setup()
	local completed, valid = {}, true
	w:As(t, function()
		t.ns.Treasury.OnPrivate("XF", { send = function() return valid end,
			dispatched = function(to, msg) completed[#completed + 1] = { to = to, msg = msg } end })
		assert(t.ns.Treasury.Private(king.name, "XF", "XF~first", "dispatch-first"))
	end)
	w:Run(2)
	eq(#completed, 1); eq(completed[1].to, king.name); eq(completed[1].msg, "XF~first")
	eq(king.comm.handlers.XF, nil, "transport completion is not proof a recipient understood or accepted the message")
	w:As(t, function() assert(t.ns.Treasury.Private(king.name, "XF", "XF~revoked", "dispatch-revoked")); valid = false end)
	w:Run(2); eq(#completed, 1)
	valid = true; w:Results(t, { 2 })
	w:As(t, function() assert(t.ns.Treasury.Private(king.name, "XF", "XF~failed", "dispatch-failed")) end)
	w:Run(2); eq(#completed, 1, "a refused native send invokes no successful completion seam")
end)

test("Guild finance: authenticated existing withdrawal immediately hides private aggregates and in-flight replay; a later consent needs its newer source revision", function()
	local w, king, t, lord = Setup(); local id = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 19000), id), true)
	w:As(king, function() assert(king.ns.GuildFinance.Ask("*")) end); w:Run(15)
	local q, old
	w:As(king, function() local held = king.ns.GuildFinance.Held("*"); eq(#held, 1); q = held[1].q end)
	old = w:As(t, function() return assert(t.ns.GuildFinance.Message(q, t.name, "*")) end)
	w:As(king, function()
		king.ns.Treasury.HandleWithdraw("CHANNEL", lord.name, "TX~" .. t.guild)
		eq(#king.ns.GuildFinance.Held("*"), 1, "an ordinary member cannot withdraw the actual keeper's source")
	end)
	w:As(t, function() t.ns.Treasury.SetConsent(false) end); w:Run(2)
	w:As(king, function()
		eq(#king.ns.GuildFinance.Held("*"), 0, "the authenticated existing TX applies without waiting for another GF ask")
		eq(king.ns.GuildFinance.Handle("WHISPER", t.name, old), false, "old in-flight bytes cannot revive a withdrawn revision")
	end)
	w:As(t, function() t.ns.Treasury.SetConsent(true) end)
	local newer = w:As(t, function() return assert(t.ns.GuildFinance.Message(q, t.name, "*")) end)
	w:As(king, function() eq(king.ns.GuildFinance.Handle("WHISPER", t.name, newer), true); eq(#king.ns.GuildFinance.Held("*"), 1) end)
end)

test("Guild finance: private withdrawal admission obeys the same retained cap and request clock as data", function()
	local w, king, t, lord = Setup(); local id = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 19000), id), true)
	local query
	w:As(king, function()
		local private = king.ns.Treasury.Private; king.ns.Treasury.Private = function(_, _, text) query = text; return true end
		assert(king.ns.GuildFinance.Ask("*")); king.ns.Treasury.Private = private
	end)
	local q = assert(tonumber(query:match("Q~(%d+)")))
	local withdrawal = w:As(t, function()
		local a = t.ns.rdb.guildFinance.actors[t.name]
		return ("GF~1~X~%.0f~%s~%s~*~%d"):format(q, t.name, t.guild, a.rev)
	end)
	local at = w.clock; w.clock = at - 1
	w:As(king, function() eq(king.ns.GuildFinance.Handle("WHISPER", t.name, withdrawal), false, "a clock reversal invalidates the outstanding request") end)
	w.clock = at
	w:As(king, function()
		local F = king.ns.GuildFinance; F.EVENTS = 0
		local s = king.ns.rdb.guildFinance
		for i = 1, king.ns.Treasury.MAX_KEEPERS + 3 do s.held["retained:" .. i] = { rev = i, revoked = true } end
		eq(F.Handle("WHISPER", t.name, withdrawal), false, "withdrawal tombstones cannot bypass the bounded held store")
		eq(s.held[t.name .. "|*"], nil)
	end)
end)

test("Guild finance: newly detected snapshot conflict refreshes the visible private page once and cannot be hidden by replay", function()
	local w, king, t, lord = Setup(); local id = Event(w, t, lord.guild)
	eq(Allocate(w, t, Receipt(w, t, lord, 19000), id), true)
	w:As(king, function() assert(king.ns.GuildFinance.Ask("*")) end); w:Run(15)
	local q = w:As(king, function() return king.ns.GuildFinance.Held("*")[1].q end)
	local msg = w:As(t, function() return assert(t.ns.GuildFinance.Message(q, t.name, "*")) end)
	w:As(king, function()
		local changed = 0; king.ns.On("TREASURY_CHANGED", function() changed = changed + 1 end)
		local conflict = msg:gsub("/19000/0/0/0/19000/0$", "/29000/0/0/0/19000/0")
		assert(conflict ~= msg)
		eq(king.ns.GuildFinance.Handle("WHISPER", t.name, conflict), false); eq(changed, 1)
		eq(#king.ns.GuildFinance.Held("*"), 0)
		eq(king.ns.GuildFinance.Handle("WHISPER", t.name, conflict), false); eq(changed, 1, "a repeated malformed source does not churn the page")
	end)
end)

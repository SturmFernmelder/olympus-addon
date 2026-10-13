local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]dues%-roster%-checkpoints%.lua$") or "./"
local MODULE = os.getenv("OLYMPUS_DUESROSTER_PREFIX") or ROOT .. "Olympus/DuesRosterCheckpoints.lua"
local AUTH = assert(loadfile(ROOT .. "tests/fixtures/dues-roster-authority.lua"))()
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = ns })
local runTest = test
test = function(name, fn) runTest(name, function() ns.Sign.WithKey(AUTH.N, AUTH.MU, AUTH.K, fn) end) end
local function Scan(w)
	for _, c in ipairs(w.clients) do
		local peers = {}; for _, p in ipairs(w.clients) do if p.guild == c.guild then peers[#peers + 1] = p end end
		for _, p in ipairs(c.extraNative or {}) do peers[#peers + 1] = p end
		c.globals.GetNumGuildMembers = function() return #peers, #peers end
		c.globals.GetGuildRosterInfo = function(i)
			local p = peers[i]; if p then return p.name, p.rankName or "Member", p.rank or 5, 60, "Mage", "Stormwind", "", "", p.online, nil, "MAGE", nil, nil, nil, nil, nil, p.guid end
		end
		c.globals.GetPlayerInfoByGUID = function(guid)
			for _, p in ipairs(w.clients) do if p.guid == guid then return "Mage", "MAGE", "Human", "HUMAN", 2, p.name:match("^(.+)%-[^%-]+$"), p.realm end end
		end
		w:As(c, function() assert(c.ns.Roster.Scan()) end)
	end
end
local function Load(w, c)
	w:As(c, function()
		c.ns.splitNames = true
		c.ns.L = setmetatable({}, { __index = ns.L })
		c.ns.ViewAs = { Previewing = function() return false end }
		for _, file in ipairs({ "Roster", "Authority", "Data", "Locales/DuesGraceText", "Locales/DuesRosterText", "DuesGrace" }) do
			assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c.ns)
		end
		assert(loadfile(MODULE))("Olympus", c.ns)
		local C = c.ns.Comm; C.Hash36 = ns.Comm.Hash36; C.Cancel = function() end
		C.SendBatch = function(_, pieces, _, target, urgent, done, opts)
			w:Timer(c, 0, nil, function()
				if opts and opts.guard and not opts.guard() then if done then done(false) end; return end
				local left, failed = #pieces, false
				for _, piece in ipairs(pieces) do C.Whisper(target, piece, nil, urgent, false, function(ok)
					failed, left = failed or not ok, left - 1; if left == 0 and done then done(not failed) end
				end, opts) end
			end, "dues roster private native transport")
			return true
		end
		assert(c.ns.Authority.TakePart(AUTH.INITIAL))
	end)
end
local function Setup()
	local w = World.New({ clock = AUTH.START - 604800, council = false, arenaFiles = { "ArenaMath", "ArenaNet", "ArenaMoney", "Debts" }, compliance = "shipped" })
	local t, king = w:Role("treasurer"), w:Role("king")
	local gm = w:Role("fighterA", { guild = World.GUILD, rank = 0 })
	local p = w:Role("bettor1", { guild = World.GUILD, rank = 5 })
	local foreign = w:Role("fighterB", { guild = "Olympus Willow", rank = 0 })
	local mail = w:Role("treasurerMail", { guild = t.guild })
	for _, c in ipairs(w.clients) do Load(w, c) end
	Scan(w)
	w:As(t, function()
		t.db.keeperShares = { [t.name:lower()] = true }
		for _, name in ipairs({ t.name, World.NAMES.treasurerMail }) do
			local b = t.ns.Treasury.BookOf(name, true); b.opened, b.openedAt, b.opening = AUTH.START - 4 * 604800, AUTH.START - 4 * 604800, 0
		end
	end)
	mail.ns.rdb = t.ns.rdb
	for _, actor in ipairs({ t, mail }) do w:As(actor, function() assert(actor.ns.Dues.StartNativePayerTracking()) end) end
	local delta = AUTH.START + 1 - w.clock; for _, timer in ipairs(w.timers) do timer.at = timer.at + delta end; w.clock = AUTH.START + 1
	Scan(w)
	return w, t, king, gm, p, foreign
end
local function Jump(w, at)
	local delta = at - w.clock; for _, timer in ipairs(w.timers) do timer.at = timer.at + delta end
	w.clock = at; Scan(w)
end
local function Observe(w, t, gm)
	w:As(t, function() t.ns.DuesGrace.Observe() end)
	w:As(gm, function() gm.ns.DuesRosterCheckpoints.Observe() end)
	w:Run(2)
end
local function Send(w, gm, ticks)
	for _ = 1, ticks or 5 do
		Scan(w); w:As(gm, function() gm.ns.DuesRosterCheckpoints.Pump() end); w:Run(2)
	end
end
local function Close(w, t, gm, week)
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(week + 1) - 1 end)); Observe(w, t, gm)
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(week + 1) + 1 end)); Observe(w, t, gm); Send(w, gm, 8)
end
local function NoErrors(w) for _, c in ipairs(w.clients) do eq(#c.errors, 0, table.concat(c.errors, "; ")) end end
local function Window(w, t, guild, week) return w:As(t, function() return t.ns.DuesRosterCheckpoints.ValidatedWindow(guild, week) end) end
local function Enable(w, gm) w:As(gm, function() eq(gm.ns.DuesRosterCheckpoints.Sharing(), false); assert(gm.ns.DuesRosterCheckpoints.SetSharing(true)) end) end
local function Describe(t, gm)
	local out = { table.concat(t.errors, ";"), table.concat(gm.errors, ";") }
	for key, c in pairs(t.ns.rdb.duesRosterCheckpoints and t.ns.rdb.duesRosterCheckpoints.received or {}) do out[#out + 1] = "received=" .. key .. ":" .. tostring(c.root) end
	for key, o in pairs(gm.ns.rdb.duesRosterCheckpoints and gm.ns.rdb.duesRosterCheckpoints.own or {}) do
		for slot, c in pairs(o.snapshots) do out[#out + 1] = "own=" .. slot .. ":sent=" .. tostring(c.sent) .. ":pending=" .. tostring(c.pending) end
	end
	return table.concat(out, " | ")
end
local function Feed(w, t, gm, text, sig)
	local encoded = ns.Ed25519.ToB64(text)
	local root = ns.Ed25519.ToHex(ns.Sign.SHA256(text)); local chunks = math.ceil(#encoded / gm.ns.DuesRosterCheckpoints.PART)
	for i = 1, chunks do
		local body = encoded:sub((i - 1) * gm.ns.DuesRosterCheckpoints.PART + 1, i * gm.ns.DuesRosterCheckpoints.PART)
		local hash = ns.Ed25519.ToHex(ns.Sign.SHA256(body))
		w:As(t, function() t.ns.DuesRosterCheckpoints.Handle("WHISPER", gm.name, table.concat({ "DQ", "1", "P", root, i, chunks, sig, hash, body }, "~")) end)
	end
	w:Run(2)
end

test("Dues roster checkpoints: historical role verifies real original signatures without importing power, rejects superseded or malformed grants", function()
	local w, t, _, gm = Setup()
	w:As(t, function()
		local A, before = t.ns.Authority, World.Copy(t.ns.db.authorityEnforced)
		local proof = { kind = "HA", realm = t.ns.group, blobs = { AUTH.INITIAL } }
		local role = A.VerifyHistoricalRoleProof(proof, gm.name, gm.guild, AUTH.START + 1, t.ns.faction)
		assert(role); eq(role.actor, gm.name); eq(role.published, AUTH.ISSUED)
		eq(t.ns.db.authorityEnforced["emberfall|Alliance"].at, before["emberfall|Alliance"].at)
		local ok, value = pcall(A.VerifyHistoricalRoleProof, { kind = "HT", realm = t.ns.group, blobs = 7 }, gm.name, gm.guild, AUTH.START, "Alliance")
		eq(ok, true); eq(value, nil)
		eq(A.VerifyHistoricalRoleProof(proof, gm.name, gm.guild, AUTH.ISSUED - 1, "Alliance"), nil)
		proof.blobs[1] = AUTH.INITIAL:gsub("Torvin", "Forvin")
		eq(A.VerifyHistoricalRoleProof(proof, gm.name, gm.guild, AUTH.START + 1, "Alliance"), nil)
	end)
	Jump(w, AUTH.START + 101)
	w:As(t, function()
		assert(t.ns.Authority.TakePart(AUTH.REVOKED))
		local proof = { kind = "HA", realm = t.ns.group, blobs = { AUTH.INITIAL } }
		eq(t.ns.Authority.VerifyHistoricalRoleProof(proof, gm.name, gm.guild, AUTH.START + 101, "Alliance"), nil)
		assert(t.ns.Authority.VerifyHistoricalRoleProof(proof, gm.name, gm.guild, AUTH.START + 1, "Alliance"))
		eq(t.ns.Authority.Rank(gm.name, gm.guild), nil, "archival verification never resurrects revoked office")
	end)
	NoErrors(w)
end)

test("Dues roster checkpoints: explicit native GM opt-in and complete signed reset observations reach only the pinned federal Treasurer", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Observe(w, t, gm); Send(w, gm); eq(Window(w, t, gm.guild, week), nil)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm)
	eq(Window(w, t, gm.guild, week), nil, "one boundary cannot prove a closed week")
	Close(w, t, gm, week)
	local row = Window(w, t, gm.guild, week); assert(row, "complete native start and end should arrive through actual private transport: " .. Describe(t, gm))
	eq(row.members[p.name:lower()], p.name); eq(row.ends[p.name:lower()], p.name)
	eq(row.amount, 10000)
	w:As(t, function() local progress = t.ns.DuesGrace.Progress(p.name, nil, gm.guild); eq(progress.misses, 1); eq(progress.grace, true) end)
	for _, sent in ipairs(w.sent) do if sent.msg and sent.msg:match("^TW~DQ") then eq(sent.dist, "WHISPER"); assert(sent.target == t.name or sent.target == gm.name) end end
	NoErrors(w)
end)

test("Dues roster checkpoints: two covered unconfirmed foreign weeks send payer before the current native GM, never a public channel", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm)
	Close(w, t, gm, week); Close(w, t, gm, week + 1)
	w:As(t, function()
		local progress = t.ns.DuesGrace.Progress(p.name, nil, gm.guild); eq(progress.misses, 2)
		t.ns.DuesGrace.QueueNotices(week + 1); assert(t.ns.DuesGrace.Pump())
	end)
	-- Both the GM and this member can be eligible. Exercise the bounded queue until
	-- every phase has had a slot; its table iteration order is deliberately unspecified.
	for _ = 1, 6 do w:Run(2); Scan(w); w:As(t, function() t.ns.DuesGrace.Pump() end) end
	w:Run(2)
	local payer, officer
	for i, sent in ipairs(w.sent) do if sent.msg and sent.msg:find("DG~1~N", 1, true) and sent.msg:find(p.name, 1, true) then
		if sent.target == p.name then payer = payer or i elseif sent.target == gm.name then officer = officer or i end
	end end
	assert(payer and officer and payer < officer, "actual transport must finish payer phase before the GM")
	NoErrors(w)
end)

test("Dues roster checkpoints: missing boundary, capped proof book and missed amount reset stay unknown without latest-word backfill", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	w:As(t, function()
		local b = t.ns.Treasury.BookOf(t.name); b.duesProofsCut = { [week] = true }
		eq(t.ns.DuesGrace.Progress(p.name, nil, gm.guild).misses, 0)
		b.duesProofsCut = nil
		t.ns.rdb.duesRosterCheckpoints.amounts[week] = nil
		eq(t.ns.DuesGrace.Progress(p.name, nil, gm.guild).misses, 0)
	end)
	Observe(w, t, gm); eq(Window(w, t, gm.guild, week), nil)
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(week + 2) + 200 end)); Observe(w, t, gm); Send(w, gm)
	eq(Window(w, t, gm.guild, week + 1), nil)
	NoErrors(w)
end)

test("Dues roster checkpoints: withdrawal and real authority revocation invalidate retained foreign coverage and queued notices", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	assert(Window(w, t, gm.guild, week))
	w:As(gm, function() assert(gm.ns.DuesRosterCheckpoints.SetSharing(false)) end); w:Run(2); Send(w, gm)
	eq(Window(w, t, gm.guild, week), nil)
	w:As(t, function()
		eq(t.ns.DuesGrace.Progress(p.name, nil, gm.guild).misses, 0)
		assert(t.ns.Authority.TakePart(AUTH.REVOKED)); eq(t.ns.DuesRosterCheckpoints.CurrentGM(gm.guild), nil)
	end)
	NoErrors(w)
end)

test("Dues roster checkpoints: retained original key and real signatures revalidate after Treasurer reload without an online GM or imported powers", function()
	local w, t, _, gm = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	assert(Window(w, t, gm.guild, week)); gm.online = false
	w:As(t, function()
		t.ns.rdb = World.Copy(t.ns.rdb)
		assert(loadfile(MODULE))("Olympus", t.ns)
		eq(t.ns.DuesRosterCheckpoints.ValidatedWindow(gm.guild, week), nil)
		t.ns.DuesRosterCheckpoints.RecheckSaved()
	end)
	w:Run(3)
	assert(Window(w, t, gm.guild, week), "native GUID pin and original signatures survive offline relog")
	NoErrors(w)
end)

test("Dues roster checkpoints: malformed saved floors, identity keys and rows fail unknown without throwing or importing a false enrollment", function()
	local w, t, _, gm = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	local original = World.Copy(gm.ns.rdb.duesRosterCheckpoints.own[gm.guild].snapshots[gm.guild .. "|" .. week .. "|B"])
	w:As(t, function()
		local s = t.ns.rdb.duesRosterCheckpoints
		local floor = World.Copy(s.floors[gm.guild])
		s.floors[gm.guild] = 7; eq(t.ns.DuesRosterCheckpoints.ValidatedWindow(gm.guild, week), nil)
		s.floors[gm.guild] = floor; s.received[gm.guild .. "|" .. week .. "|B"] = 7
		s.keys[gm.name:lower()] = 7; s.received.bad = { issuer = 7, text = "fake", sig = "fake", root = "fake" }
		eq(pcall(t.ns.DuesRosterCheckpoints.RecheckSaved), true)
		eq(t.ns.DuesRosterCheckpoints.Handle("CHANNEL", gm.name, "DQ~1~Q"), false)
	end)
	Feed(w, t, gm, original.text, original.sig)
	eq(Window(w, t, gm.guild, week), nil)
	w:As(gm, function()
		gm.ns.rdb.duesRosterCheckpoints.own[gm.guild].snapshots.bad = 7
		local broken = World.Copy(original); broken.sent, broken.expires = false, nil
		gm.ns.rdb.duesRosterCheckpoints.own[gm.guild].snapshots.malformed = broken
		eq(pcall(gm.ns.DuesRosterCheckpoints.Pump), true)
		eq(pcall(gm.ns.DuesRosterCheckpoints.Handle, "WHISPER", t.name, "DQ~1~Q"), true)
	end)
	NoErrors(w)
end)

test("Dues roster checkpoints: thousand-name native roster uses complete ACKed base64 pages, with bounded batch scans and no truncation", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	gm.extraNative = {}
	for i = 1, 998 do gm.extraNative[i] = { name = ("Raider %04d-Emberfall"):format(i), guid = "Player-0-" .. i, rank = 5 } end
	Scan(w); Enable(w, gm); Observe(w, t, gm)
	local o = gm.ns.rdb.duesRosterCheckpoints.own[gm.guild]
	local c = o.snapshots[gm.guild .. "|" .. week .. "|B"]
	eq(#c.rows, 1000); assert(#c.wire > 7480, "the roster deliberately cannot fit one logical Codec message")
	Send(w, gm, 24); Close(w, t, gm, week); Send(w, gm, 24)
	local row = Window(w, t, gm.guild, week); assert(row, Describe(t, gm)); local count = 0; for _ in pairs(row.members) do count = count + 1 end; eq(count, 1000)
	w:As(t, function()
		local R, actual, calls = t.ns.DuesRosterCheckpoints, t.ns.DuesRosterCheckpoints.ValidatedWindow, 0
		R.ValidatedWindow = function(...) calls = calls + 1; return actual(...) end
		t.ns.DuesGrace.QueueNotices(week)
		assert(calls <= 6, "historical full rosters are expanded once per batch, not 1000 times")
		R.ValidatedWindow = actual
	end)
	NoErrors(w)
end)

test("Dues roster checkpoints: legitimate new signed GM starts at revision one despite the old GM's withdrawal floor and survives relog", function()
	local w, t, _, gm, p, nextGM = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm)
	w:As(gm, function() assert(gm.ns.DuesRosterCheckpoints.SetSharing(false)) end); w:Run(2); Send(w, gm)
	Jump(w, AUTH.START + 604800 + 1)
	gm.rank, nextGM.rank, nextGM.guild = 1, 0, gm.guild; Scan(w)
	for _, c in ipairs(w.clients) do w:As(c, function() assert(c.ns.Authority.TakePart(AUTH.NEWMASTER)) end) end
	Enable(w, nextGM); Observe(w, t, nextGM); Send(w, nextGM); Close(w, t, nextGM, week + 1)
	local row = Window(w, t, gm.guild, week + 1); assert(row, Describe(t, nextGM)); eq(row.issuer, nextGM.name)
	w:As(t, function()
		local floor = t.ns.rdb.duesRosterCheckpoints.floors[gm.guild]; eq(floor.revision, 1); eq(floor.issuer, nextGM.name)
		t.ns.rdb = World.Copy(t.ns.rdb); assert(loadfile(MODULE))("Olympus", t.ns); t.ns.DuesRosterCheckpoints.RecheckSaved()
	end)
	w:Run(3); assert(Window(w, t, gm.guild, week + 1))
	w:As(gm, function() eq(gm.ns.DuesRosterCheckpoints.Pump(), false, "old GM can no longer replay its capture") end)
	NoErrors(w)
end)

test("Dues roster checkpoints: current GM without original author proof gets honest disabled UI and cannot enroll a census-only financial scope", function()
	local w, t, _, gm = Setup()
	w:As(gm, function()
		gm.ns.db.authorityEnforced, gm.ns.rdb.authorityBundles = {}, {}
		local lines = {}; gm.ns.DuesRosterCheckpoints.GuildLines(lines)
		eq(#lines, 1); eq(lines[1].onClick, nil); eq(lines[1].text, gm.ns.L.DUESROSTER_NO_PROOF)
		eq(gm.ns.DuesRosterCheckpoints.SetSharing(true), false)
	end)
	w:As(t, function()
		eq(t.ns.DuesRosterCheckpoints.Handle("WHISPER", gm.name, "DQ~1~K~" .. gm.guild .. "~fake~fake~fake~" .. string.rep("a", 64)), false)
	end)
	NoErrors(w)
end)

test("Dues roster checkpoints: pre-reset observations, duplicate native names, over-limit rosters and malformed saved amount never manufacture coverage", function()
	local w, t, _, gm = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	w:As(gm, function()
		local c = World.Copy(gm.ns.rdb.duesRosterCheckpoints.own[gm.guild].snapshots[gm.guild .. "|" .. week .. "|B"])
		c.at = gm.ns.Dues.WeekStart(week) - 1; eq(gm.ns.DuesRosterCheckpoints.Text(c), nil)
	end)
	w:As(t, function()
		t.ns.rdb.duesRosterCheckpoints.amounts[week] = 7
		eq(pcall(t.ns.DuesRosterCheckpoints.ValidatedWindow, gm.guild, week), true)
		eq(t.ns.DuesRosterCheckpoints.ValidatedWindow(gm.guild, week), nil)
	end)
	gm.extraNative = { { name = gm.name, guid = gm.guid, rank = 0 } }; Scan(w)
	w:As(gm, function() eq(gm.ns.DuesRosterCheckpoints.NativeRows(), nil) end)
	gm.extraNative = {}; for i = 1, 999 do gm.extraNative[i] = { name = "Raider " .. i .. "-Emberfall", rank = 5 } end; Scan(w)
	w:As(gm, function() eq(gm.ns.DuesRosterCheckpoints.NativeRows(), nil) end)
	NoErrors(w)
end)

test("Dues roster checkpoints: rejected signatures free assembly slots, exact signature cache cannot authenticate replacements, same revision conflicts persist across reload", function()
	local w, t, _, gm = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	local c = gm.ns.rdb.duesRosterCheckpoints.own[gm.guild].snapshots[gm.guild .. "|" .. week .. "|B"]
	Feed(w, t, gm, c.text, ns.Ed25519.ToB64(string.rep("\0", 64)))
	assert(Window(w, t, gm.guild, week), "bad replacement cannot erase the genuine previously verified checkpoint")
	for i = 1, 9 do
		local r = World.Copy(c); r.at = r.at + i
		local text = w:As(gm, function() return gm.ns.DuesRosterCheckpoints.Text(r) end)
		Feed(w, t, gm, text, ns.Ed25519.ToB64(string.rep("\0", 64)))
	end
	local r = World.Copy(c); r.at = r.at + 10
	local text = w:As(gm, function() return gm.ns.DuesRosterCheckpoints.Text(r) end)
	local root = ns.Ed25519.ToHex(ns.Sign.SHA256(text))
	local sig = w:As(gm, function() return gm.ns.Ed25519.ToB64(gm.ns.Debts.Sign("OLYDR1|" .. root)) end)
	Feed(w, t, gm, text, sig)
	eq(Window(w, t, gm.guild, week), nil, "genuine contradictory original under one revision invalidates negative coverage")
	w:As(t, function()
		t.ns.rdb = World.Copy(t.ns.rdb); assert(loadfile(MODULE))("Olympus", t.ns); t.ns.DuesRosterCheckpoints.RecheckSaved()
	end)
	w:Run(2); Feed(w, t, gm, c.text, c.sig)
	eq(Window(w, t, gm.guild, week), nil, "original replay cannot heal a persisted same-revision conflict")
	NoErrors(w)
end)

test("Dues roster checkpoints: missing native GUID binding keeps retained keys unknown and no forged forwarded claim enrolls an issuer", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm); Close(w, t, gm, week)
	local c = gm.ns.rdb.duesRosterCheckpoints.own[gm.guild].snapshots[gm.guild .. "|" .. week .. "|B"]
	t.globals.GetPlayerInfoByGUID, t.globals.UnitTokenFromGUID = nil, function() return nil end
	w:As(t, function()
		t.ns.rdb = World.Copy(t.ns.rdb); assert(loadfile(MODULE))("Olympus", t.ns); t.ns.DuesRosterCheckpoints.RecheckSaved()
		local claim = table.concat({ "DQ", "1", "K", gm.guild, gm.guid, c.pk, c.claim, c.root }, "~")
		eq(t.ns.DuesRosterCheckpoints.Handle("WHISPER", p.name, claim), false, "a participant forwarding the GM's claim is not the original stamped sender")
		eq(t.ns.DuesRosterCheckpoints.Handle("WHISPER", gm.name, claim), false, "self-signed key alone cannot replace native GUID identity")
	end)
	w:Run(2); eq(Window(w, t, gm.guild, week), nil)
	NoErrors(w)
end)

test("Dues roster checkpoints: actual native foreign receipt is a positive lower bound, with stable same-guild mutual alts pooled only for the main", function()
	local w, t, _, gm, p = Setup(); local week = w:As(t, function() return t.ns.Dues.Week() end)
	local alt = w:Role("bettor2", { guild = gm.guild, rank = 5 }); Load(w, alt); Scan(w)
	w:As(gm, function()
		gm.ns.Alts.Handle("CHANNEL", p.name, ("AL~%d~M~%s~%s"):format(w.clock, p.guild, alt.name))
		gm.ns.Alts.Handle("CHANNEL", alt.name, ("AL~%d~A~%s~%s"):format(w.clock, alt.guild, p.name))
	end)
	Enable(w, gm); Observe(w, t, gm); Send(w, gm)
	w:Trade(t, alt, { bGives = 10000 }); Close(w, t, gm, week)
	w:As(t, function()
		local main = t.ns.DuesGrace.Progress(p.name, nil, gm.guild)
		eq(main.latest.state, "counted"); eq(main.latest.copper, 10000)
		eq(t.ns.DuesGrace.Progress(alt.name, nil, gm.guild).latest.state, "counted")
		local book = t.ns.Treasury.BookOf(t.name); book.duesProofsCut = { [week] = true }
		eq(t.ns.DuesGrace.Progress(p.name, nil, gm.guild).latest.state, "counted", "valid intake stays a lower bound when other proofs have been cut")
	end)
	NoErrors(w)
end)

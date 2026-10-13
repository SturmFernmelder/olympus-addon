local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]dues%-grace%.lua$") or "./"
local MODULE = os.getenv("OLYMPUS_DUESGRACE_PREFIX") or ROOT .. "Olympus/DuesGrace.lua"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = ns })

local function Load(w, c)
	w:As(c, function()
		c.ns.splitNames = true -- the supported Forever surname client
		c.ns.L = setmetatable({}, { __index = ns.L })
		c.ns.ViewAs = { Previewing = function() return false end }
		for _, file in ipairs({ "Roster", "Locales/DuesGraceText" }) do assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c.ns) end
		assert(loadfile(MODULE))("Olympus", c.ns)
		local C = c.ns.Comm
		C.Hash36 = ns.Comm.Hash36
		C.Cancel = function() end -- cancellation still invalidates every queued piece's real guard
		C.SendBatch = function(_, pieces, _, target, urgent, done, opts)
			w:Timer(c, 0, nil, function()
				if opts and opts.guard and not opts.guard() then if done then done(false) end; return end
				local left, failed = #pieces, false
				for _, piece in ipairs(pieces) do
					C.Whisper(target, piece, nil, urgent, false, function(ok)
						failed, left = failed or not ok, left - 1
						if left == 0 and done then done(not failed) end
					end, opts)
				end
			end, "dues grace native transport")
			return true
		end
	end)
end
local function Scan(w)
	for _, c in ipairs(w.clients) do
		local peers = {}; for _, p in ipairs(w.clients) do if p.guild == c.guild then peers[#peers + 1] = p end end
		c.globals.GetNumGuildMembers = function() return #peers, #peers end
		c.globals.GetGuildRosterInfo = function(i)
			local p = peers[i]; if p then return p.name, p.rankName, p.rank, 60, "Mage", "Stormwind", "", "", p.online, nil, "MAGE", nil, nil, nil, nil, nil, p.guid end
		end
		w:As(c, function() assert(c.ns.Roster.Scan()) end)
	end
end
local function Setup()
	local w = World.New({ council = false, arenaFiles = {}, compliance = "shipped" })
	local t, king = w:Role("treasurer"), w:Role("king")
	local p, other = w:Role("fighterA", { guild = t.guild }), w:Role("fighterB", { guild = t.guild })
	for _, c in ipairs(w.clients) do Load(w, c) end
	Scan(w)
	w:As(t, function()
		t.db.keeperShares = { [t.name:lower()] = true }
		for _, name in ipairs({ t.name, World.NAMES.treasurerMail }) do
			local b = t.ns.Treasury.BookOf(name, true)
			b.opened, b.openedAt, b.opening = t.ns.Dues.WeekStart(t.ns.Dues.Week() - 4), t.ns.Dues.WeekStart(t.ns.Dues.Week() - 4), 0
		end
	end)
	return w, t, king, p, other
end
-- Jump between the two observed reset boundaries instead of simulating millions of
-- unchanged gameplay ticks. Preserve pending timers' relative delays; all receipts and
-- transport completions are still the actual addon event handlers near each boundary.
local function Jump(w, at)
	local delta = at - w.clock
	for _, timer in ipairs(w.timers) do timer.at = timer.at + delta end
	w.clock = at
	Scan(w)
end
local function Start(w, t, week)
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(week) + 1 end))
	w:As(t, function() assert(t.ns.DuesGrace.Observe()) end)
end
local function Close(w, t, week)
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(week + 1) - 1 end))
	w:As(t, function() assert(t.ns.DuesGrace.Observe()) end)
	Start(w, t, week + 1)
end
local function Week(w, t) return w:As(t, function() return t.ns.Dues.Week() end) end
local function Progress(w, t, p) return w:As(t, function() return t.ns.DuesGrace.Progress(p.name) end) end
local function TwoMisses(w, t)
	local week = Week(w, t) - 2
	Start(w, t, week); Close(w, t, week); Close(w, t, week + 1)
	return week + 1
end
local function NoticeCount(w, c)
	local n = 0
	for _, text in ipairs(c.printed) do if text:find("covered week", 1, true) then n = n + 1 end end
	return n
end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do eq(#c.errors, 0, table.concat(c.errors, "; ")) end
end

test("Dues grace: native three-week paid, first missing tolerance, second notice and transport-completed payer before GM", function()
	local w, t, king, p, other = Setup(); local first = Week(w, t) - 3
	Start(w, t, first)
	w:Trade(t, p, { bGives = 10000 }); w:Trade(t, other, { bGives = 10000 }); Close(w, t, first)
	local one = Progress(w, t, p); eq(one.kept, 1); eq(one.misses, 0)
	w:Trade(t, other, { bGives = 10000 }); Close(w, t, first + 1)
	local grace = Progress(w, t, p); eq(grace.kept, 1); eq(grace.misses, 1); eq(grace.grace, true)
	w:Trade(t, other, { bGives = 10000 }); Close(w, t, first + 2)
	local second = Progress(w, t, p); eq(second.kept, 0); eq(second.misses, 2)
	w:As(t, function()
		eq(t.ns.DuesGrace.captainPolicy, "gm", "the approved notice goes to the current native GM after the payer")
		assert(t.ns.DuesGrace.Pump())
		eq(t.ns.DuesGrace.Pump(), false, "enqueueing does not advance the payer phase")
	end)
	eq(NoticeCount(w, king), 0)
	w:Run(10)
	eq(NoticeCount(w, p), 1, "only a private explanatory notice, never an unpaid verdict")
	eq(NoticeCount(w, king), 0, "a successful enqueue was not the participant delivery callback")
	w:As(t, function() assert(t.ns.DuesGrace.Pump()) end); w:Run(10)
	eq(NoticeCount(w, king), 1)
	local channel = w:ChannelText(); assert(not channel:find("DG~", 1, true)); assert(not channel:find("not confirmed", 1, true))
	NoErrors(w)
end)

test("Dues grace: late login, missing reset boundary and incomplete native roster never backfill a missed week", function()
	local w, t, _, p = Setup(); local week = Week(w, t) - 1
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(week) + 1000 end))
	w:As(t, function() t.ns.DuesGrace.Observe(); eq(t.ns.rdb.duesGrace.weeks[week], nil) end)
	Start(w, t, week + 1)
	eq(Progress(w, t, p).known, 0)
	local nextWeek = week + 2
	Jump(w, w:As(t, function() return t.ns.Dues.WeekStart(nextWeek) + 1 end))
	t.globals.GetNumGuildMembers = function() return #w.clients + 1 end
	w:As(t, function() t.ns.DuesGrace.Observe(); eq(t.ns.rdb.duesGrace.weeks[nextWeek], nil) end)
	eq(Progress(w, t, p).misses, 0); NoErrors(w)
end)

test("Dues grace: missing or capped books and duplicate pinned aliases remain unknown; own positive native proof is a lower bound", function()
	local w, t, _, p = Setup(); local week = Week(w, t) - 1
	Start(w, t, week); w:Trade(t, p, { bGives = 5000 }); Close(w, t, week)
	w:As(t, function()
		local book, mail = t.ns.Treasury.Book(), t.ns.Dues.MailTo():lower()
		t.ns.rdb.treasuryBooks[mail] = nil
		eq(t.ns.DuesGrace.Rows(p.name)[1].state, "unknown")
		t.ns.rdb.treasuryBooks["native-alias-copy"] = World.Copy(book)
		eq(t.ns.DuesGrace.Rows(p.name)[1].state, "unknown", "the same pinned source is not two payments")
		t.ns.rdb.treasuryBooks["native-alias-copy"] = nil
		local b = t.ns.Treasury.BookOf(t.ns.Dues.MailTo(), true); b.openedAt = t.ns.Dues.WeekStart(week) - 1
		book.duesProofsCut = { [week] = true }
		eq(t.ns.DuesGrace.Rows(p.name)[1].state, "unknown")
	end)
	-- An actual late receipt naming the old week may repair the positive lower bound.
	local note = w:As(t, function() return t.ns.Dues.Note(week, p.guild) end)
	w:Take(t, w:Mail(p, t, 5000, note))
	w:As(t, function() eq(t.ns.DuesGrace.Rows(p.name)[1].state, "counted", "cap/absence cannot erase proof already held") end)
	NoErrors(w)
end)

test("Dues grace: manual ledger edits are not native proofs, guild switches cannot relabel cumulative copper and native proof cap is recorded", function()
	local w, t, _, p = Setup(); local week = Week(w, t) - 1
	Start(w, t, week)
	w:As(t, function() t.ns.Treasury.Record(p.name, 1000000, "mail", nil, { guild = p.guild, quiet = true }) end)
	w:Trade(t, p, { bGives = 1000 })
	p.guild = "Olympus Willow"; Scan(w); w:Trade(t, p, { bGives = 2000 })
	local fresh = w:Role("bettor3", { guild = t.guild }); Load(w, fresh); Scan(w)
	w:As(t, function()
		local b = t.ns.Treasury.Book(); local proof = b.duesPayerProofs[week][p.name:lower()]
		eq(proof.copper, 2000); eq(proof.guild, p.guild)
		t.ns.Dues.PAYER_PROOFS_MAX = 1
	end)
	w:Trade(t, fresh, { bGives = 5000 })
	w:As(t, function()
		local b = t.ns.Treasury.Book(); local e = b.lines[#b.lines]
		eq(e.duesPayerReceipt, nil); eq(b.duesProofsCut[week], true)
	end)
	p.guild = t.guild; Close(w, t, week)
	eq(Progress(w, t, p).latest.state, "unknown"); NoErrors(w)
end)

test("Dues grace: unavailable current GM never guesses a recipient or blocks other player notices", function()
	local w, t, king, p, other = Setup(); TwoMisses(w, t)
	king.rank = 1; Scan(w)
	w:As(t, function() assert(t.ns.DuesGrace.Pump()) end); w:Run(10)
	w:As(t, function() assert(t.ns.DuesGrace.Pump()) end); w:Run(10)
	eq(NoticeCount(w, p), 1); eq(NoticeCount(w, other), 1); eq(NoticeCount(w, king), 0)
	w:As(t, function() eq(t.ns.DuesGrace.Pump(), false) end); NoErrors(w)
end)

test("Dues grace: a blocked recipient does not starve the next queue member and retries are bounded", function()
	local w, t, king = Setup(); TwoMisses(w, t)
	king.rank = 1; Scan(w) -- isolate recipient backoff while no current GM is available
	local attempts, blocked = {}, nil
	w:As(t, function()
		local real = t.ns.Treasury.Private
		t.ns.Treasury.Private = function(to, kind, ...)
			if kind ~= "DG" then return real(to, kind, ...) end
			attempts[#attempts + 1] = to
			blocked = blocked or to
			if to == blocked then return false end
			return real(to, kind, ...)
		end
		assert(t.ns.DuesGrace.Pump(), "one blocked target cannot prevent a later eligible target")
		eq(#attempts, 2)
	end)
	w:Run(10)
	w:As(t, function() eq(t.ns.DuesGrace.Pump(), false); eq(#attempts, 2, "the failed recipient has its own backoff") end)
	w:Run(181); Scan(w)
	w:As(t, function() t.ns.DuesGrace.Pump(); eq(#attempts, 3) end)
	NoErrors(w)
end)

test("Dues grace: relog resumes an already completed payer phase only for the native GM and never reconstructs absent reset observations", function()
	local w, t, king, p, other = Setup(); local week = TwoMisses(w, t)
	local note = w:As(t, function() return t.ns.Dues.Note(week, other.guild) end)
	w:Take(t, w:Mail(other, t, 10000, note))
	w:As(t, function() assert(t.ns.DuesGrace.Pump()) end); w:Run(10)
	eq(NoticeCount(w, p), 1); eq(NoticeCount(w, king), 0)
	w:Logout(t); w:Login(t); Load(w, t); Scan(w)
	w:As(t, function() t.ns.DuesGrace.Observe(); assert(t.ns.DuesGrace.Pump()) end); w:Run(10)
	eq(NoticeCount(w, p), 1, "persisted transport-completed phase is not sent to the player twice")
	eq(NoticeCount(w, king), 1)
	w:As(t, function()
		local s = t.ns.rdb.duesGrace; s.weeks[week - 1] = nil
		local n = 0; for _ in pairs(s.weeks) do n = n + 1 end
		t.ns.DuesGrace.Observe()
		local later = 0; for _ in pairs(s.weeks) do later = later + 1 end
		eq(later, n, "a resumed notice never fills an unknown historical membership gap")
	end)
	NoErrors(w)
end)

test("Dues grace: native proof capture supplies carry facts only for confirmed intake, never manual history or a repeated line", function()
	local w, t, _, p = Setup(); local captured = {}
	w:As(t, function()
		t.ns.CarryHistory = { CaptureOriginal = function(kind, payer, id, at, guild, fields)
			captured[#captured + 1] = { kind = kind, payer = payer, id = id, at = at, guild = guild, fields = fields }
		end }
		t.ns.Treasury.Record(p.name, 1000000, "mail", nil, { guild = p.guild, quiet = true })
	end)
	eq(#captured, 0)
	w:Trade(t, p, { bGives = 5000 })
	eq(#captured, 1); eq(captured[1].kind, "D"); eq(captured[1].payer, p.name); eq(captured[1].guild, p.guild)
	eq(captured[1].fields.copper, 5000); eq(captured[1].fields.bookPin, 1)
	w:As(t, function()
		local b = t.ns.Treasury.Book(); local e = b.lines[#b.lines]
		eq(t.ns.Dues.PayerBooked(b, e, p.name, true), false)
	end)
	eq(#captured, 1); NoErrors(w)
end)

test("Dues grace: native net-off and an active powers hold invalidate queued reminders without affecting recorded payment history", function()
	local w, t, king, p, other = Setup(); local week = TwoMisses(w, t)
	w:As(king, function() assert(king.ns.Moderation.Set("c", p.name, true, "Test net-off")) end)
	w:Run(1)
	w:As(t, function()
		assert(t.ns.Moderation.Hides(p.name, p.guild))
		t.ns.WatchChat = { Barred = function(kind, name) return kind == "powers" and name == t.name end }
		eq(t.ns.DuesGrace.Pump(), false, "a held issuer cannot stage a financial reminder")
		t.ns.WatchChat = nil
		local note = t.ns.Dues.Note(week, other.guild)
		-- Remove the other eligible reminder through its real native receipt below.
		return note
	end)
	local note = w:As(t, function() return t.ns.Dues.Note(week, other.guild) end)
	w:Take(t, w:Mail(other, t, 10000, note))
	w:As(t, function() eq(t.ns.DuesGrace.Pump(), false, "the net-off payer is not contacted") end)
	eq(NoticeCount(w, p), 0)
	NoErrors(w)
end)

test("Dues grace: corrected or removed queued week, preview, changed guild and consent cancellation invalidate actual transport", function()
	for _, change in ipairs({ "week", "paid", "preview", "guild", "consent" }) do
		local w, t, king, p = Setup(); local week = TwoMisses(w, t)
		w:As(t, function() t.ns.DuesGrace.captainPolicy = "gm"; assert(t.ns.DuesGrace.Pump()) end)
		w:As(t, function()
			if change == "week" then t.ns.rdb.duesGrace.weeks[week] = nil
			elseif change == "paid" then
				for _, target in ipairs({ p, w:Find(World.NAMES.fighterB) }) do
					t.ns.Treasury.Record(target.name, 10000, "mail", nil, { note = t.ns.Dues.Note(week, t.guild), observed = true, quiet = true })
				end
			elseif change == "preview" then t.ns.ViewAs.Previewing = function() return true end
			elseif change == "guild" then t.guild = "Olympus Willow"
			else t.ns.Treasury.SetConsent(false) end
		end)
		w:Run(10)
		eq(NoticeCount(w, p), 0, change); eq(NoticeCount(w, king), 0, change)
		NoErrors(w)
	end
end)

test("Dues grace: TTL, backward clock and stale native roster cannot authorize a queued notice", function()
	for _, mode in ipairs({ "expired", "backward", "roster" }) do
		local w, t, _, p = Setup(); TwoMisses(w, t)
		if mode == "expired" then Jump(w, w.clock + t.ns.DuesGrace.NOTICE_FOR + 1)
		elseif mode == "backward" then Jump(w, w.clock - 5)
		else t.ns.Roster.snapshotAt = w.clock - 1000 end
		w:As(t, function() eq(t.ns.DuesGrace.Pump(), false, mode) end)
		eq(NoticeCount(w, p), 0)
	end
end)

test("Dues grace: malformed saved weeks fail closed without crashes, invented misses, or deleting original malformed evidence", function()
	local w, t, _, p = Setup(); local week = TwoMisses(w, t)
	local original = World.Copy(t.ns.rdb.duesGrace.weeks[week])
	for _, change in ipairs({ "nilAmount", "nan", "infinite", "negative", "zero", "members", "ends", "groups", "name", "date", "closed" }) do
		w:As(t, function()
			local r = World.Copy(original); t.ns.rdb.duesGrace.weeks[week] = r
			if change == "nilAmount" then r.amount = nil elseif change == "nan" then r.amount = 0/0
			elseif change == "infinite" then r.amount = math.huge elseif change == "negative" then r.amount = -1 elseif change == "zero" then r.amount = 0
			elseif change == "members" then r.members = "bad" elseif change == "ends" then r.ends = "bad"
			elseif change == "groups" then r.groups, r.endGroups = "bad", "bad"
			elseif change == "name" then r.members[p.name:lower()] = {}
			elseif change == "date" then r.at = math.huge else r.closed = "yes" end
			local progress = t.ns.DuesGrace.Progress(p.name)
			assert(progress.misses < 2, change .. " cannot authorize a second miss")
			eq(t.ns.rdb.duesGrace.weeks[week], r, "retain malformed evidence rather than rewriting it into a zero payment")
		end)
	end
	NoErrors(w)
end)

test("Dues grace: malformed native proof containers or payer proof never manufacture a negative week", function()
	local w, t, _, p = Setup(); local week = Week(w, t) - 1
	Start(w, t, week); w:Trade(t, p, { bGives = 1000 }); Close(w, t, week)
	w:As(t, function()
		local b, key = t.ns.Treasury.Book(), p.name:lower()
		local actual = World.Copy(b.duesPayerProofs)
		for _, mode in ipairs({ "store", "week", "payer", "nan", "guild", "date", "seq" }) do
			b.duesPayerProofs = World.Copy(actual)
			if mode == "store" then b.duesPayerProofs = "bad"
			elseif mode == "week" then b.duesPayerProofs[week] = "bad"
			elseif mode == "payer" then b.duesPayerProofs[week][key] = "bad"
			elseif mode == "nan" then b.duesPayerProofs[week][key].copper = 0/0
			elseif mode == "guild" then b.duesPayerProofs[week][key].guild = "Olympus Willow"
			elseif mode == "date" then b.duesPayerProofs[week][key].at = math.huge
			else b.duesPayerProofs[week][key].seq = -1 end
			eq(t.ns.DuesGrace.Rows(p.name)[1].state, "unknown", mode)
		end
		b.duesPayerProofs = actual
	end)
	NoErrors(w)
end)

test("Dues grace: removing the queued last week cannot substitute an older second missed week at native dispatch", function()
	local w, t, king, p = Setup(); local first = Week(w, t) - 3
	Start(w, t, first); Close(w, t, first); Close(w, t, first + 1); Close(w, t, first + 2)
	w:As(t, function()
		assert(t.ns.DuesGrace.Pump())
		t.ns.rdb.duesGrace.weeks[first + 2] = nil
		eq(t.ns.DuesGrace.Progress(p.name).misses, 2, "older covered weeks still exist but are not the queued last week")
	end)
	w:Run(10)
	eq(NoticeCount(w, p), 0); eq(NoticeCount(w, king), 0); NoErrors(w)
end)

test("Dues grace: native mutual alt groups count stable same-guild receipts for the main; changed links never create an alt missed-payment notice", function()
	local w, t, _, p, alt = Setup(); local week = Week(w, t) - 1
	local function Claims(role)
		w:As(t, function()
			local at = w.clock
			t.ns.Alts.Handle("CHANNEL", p.name, ("AL~%d~M~%s~%s"):format(at, p.guild, alt.name))
			t.ns.Alts.Handle("CHANNEL", alt.name, ("AL~%d~%s~%s~%s"):format(at, role, alt.guild, role == "A" and p.name or ""))
		end)
	end
	Start(w, t, week); Claims("A")
	-- The beginning snapshot must observe the actual confirmed links.
	w:As(t, function() t.ns.rdb.duesGrace.weeks[week] = nil; t.ns.DuesGrace.Observe() end)
	w:Trade(t, p, { bGives = 5000 }); w:Trade(t, alt, { bGives = 5000 }); Close(w, t, week)
	eq(Progress(w, t, p).latest.state, "counted"); eq(Progress(w, t, p).latest.copper, 10000)
	eq(Progress(w, t, alt).latest.state, "unknown", "the main's shared payment does not count the same run twice")
	Claims("-")
	eq(Progress(w, t, p).latest.state, "unknown", "a changed historical group cannot manufacture a negative payment verdict")
	NoErrors(w)
end)

test("Dues grace: batch summary and notices read the native roster once rather than once per person and historical week", function()
	local w, t = Setup(); TwoMisses(w, t)
	w:As(t, function()
		local actual, calls = t.ns.Dues.Roster, 0
		t.ns.Dues.Roster = function() calls = calls + 1; return actual() end
		local lines = {}; t.ns.DuesGrace.SummaryLines(lines); eq(calls, 1, "one native roster snapshot per render")
		calls = 0; t.ns.DuesGrace.QueueNotices(t.ns.Dues.Week() - 1); eq(calls, 1, "one native roster snapshot per queue population")
		t.ns.Dues.Roster = actual
	end)
end)

test("Dues grace: private notice authentication, local opt-out, receiver demotion and relog preserve once-only notification without granting payment", function()
	local w, t, king, p = Setup(); local week = TwoMisses(w, t)
	local msg = ("DG~1~N~%d~%s~%s~0~10000~0~2"):format(week, p.guild, p.name)
	w:As(p, function()
		local G = p.ns.DuesGrace
		eq(G.Handle("CHANNEL", t.name, msg), false); eq(G.Handle("WHISPER", king.name, msg), false)
		eq(G.Handle("WHISPER", t.name, msg:gsub("~0~10000~", "~0~0~")), false)
		p.ns.rdb.duesPayer = { [p.name] = { reminderOff = true } }
		eq(G.Handle("WHISPER", t.name, msg), true); eq(NoticeCount(w, p), 0)
		p.ns.rdb.duesPayer[p.name].reminderOff = false
		eq(G.Handle("WHISPER", t.name, msg), false)
		p.ns.rdb = World.Copy(p.ns.rdb); assert(loadfile(MODULE))("Olympus", p.ns)
		eq(p.ns.DuesGrace.Handle("WHISPER", t.name, msg), false, "the local seen record survives relog")
		eq(p.ns.Dues.PayerStatus(), "unknown", "a reminder is not a native payment receipt")
	end)
	local officer = msg:gsub("~0~10000~", "~1~10000~")
	king.rank = 1; Scan(w)
	w:As(king, function() eq(king.ns.DuesGrace.Handle("WHISPER", t.name, officer), false, "previewing a King cannot grant the native GM's private notice") end)
	NoErrors(w)
end)

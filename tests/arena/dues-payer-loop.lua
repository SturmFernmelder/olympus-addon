-- F26-10 through the real mail/trade observations and private whisper queue, on separate clients.
local H = ...
local test, eq, W = H.test, H.eq, H.World
local M = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)
local function Setup()
	local w = W.New({ compliance = "shipped" })
	local p, t, mail = M.Client(w, W.NAMES.fighterA, { money = 1000000 }), M.Role(w, "treasurer", { money = 1000000 }), M.Role(w, "treasurerMail", { money = 1000000 })
	for _, c in ipairs({ p, t, mail }) do
		c.ns.splitNames = true; c.ns.Comm.Hash36 = H.ns.Comm.Hash36
		-- World has its own Locales table; fill that same table (Dues captured it at load),
		-- as the actual TOC does before the runtime modules, without replacing its identity.
		assert(loadfile(H.ADDON_DIR .. "Locales/WeeklyBriefText.lua"))("Olympus", c.ns)
	end
	return w, p, t, mail
end
local function Intent(w, p)
	p.globals.MailFrame:Show(); p.globals.SendMailFrame:Show()
	eq(w:As(p, p.ns.Dues.SendDues), "mail")
	return w:As(p, p.ns.Dues.Note, p.ns.Dues.Week(), p.guild)
end
local function Status(w, p) return w:As(p, p.ns.Dues.PayerStatus) end
local function Receipts(w)
	local out = {}
	for _, s in ipairs(w.sent) do if s.msg:sub(1, 3) == "FR~" then out[#out + 1] = s end end
	return out
end

test("Dues payer loop: real manual mail success is sent, actual gold intake alone produces a private counted receipt", function()
	local w, p, _, mail = Setup()
	local note = Intent(w, p)
	eq(Status(w, p), "unknown", "preparing is no evidence of sending or paying")
	local i = w:Mail(p, mail, 10000, note)
	eq(Status(w, p), "sent", "matched MAIL_SEND_SUCCESS is only awaiting the book")
	eq(#Receipts(w), 0, "mail still holds its gold")
	w:Take(mail, i); w:Run(8)
	local status, copper = Status(w, p)
	eq(status, "counted"); eq(copper, 10000)
	local r = Receipts(w); eq(#r, 1); eq(r[1].dist, "WHISPER"); eq(r[1].target, p.name)
	local facts = w:As(p, p.ns.Dues.PayerReceiptFacts)
	eq(#facts, 1); eq(facts[1].issuer, mail.name); eq(facts[1].payer, p.name)
	facts[1].copper = 7; eq(select(2, Status(w, p)), 10000, "read-only facts are copies")
	w:As(p, function()
		p.ns.RealmPages = {}
		assert(loadfile(H.ADDON_DIR .. "WeeklyBrief.lua"))("Olympus", p.ns)
		local lines = p.ns.WeeklyBrief.PersonalLines()
		eq(lines[5], p.ns.L.BRIEF_PAYMENT:format(p.ns.Dues.PaymentText()), "personal brief reads the actual payer proof")
	end)
	w:Fire(p, "MAIL_SEND_SUCCESS"); eq(Status(w, p), "counted", "an unrelated repeat success cannot replace confirmed evidence")
	w:Logout(p); w:Login(p); p.ns.splitNames = true
	eq(Status(w, p), "counted", "own bounded receipt survives actual relog")
end)

test("Dues payer loop: wrong recipient, edited amount, note, guild, COD, failed send and unobserved success remain unknown", function()
	for _, change in ipairs({ "recipient", "amount", "note", "guild", "cod", "failed", "unobserved" }) do
		local w, p, t, mail = Setup()
		local note = Intent(w, p)
		if change == "unobserved" then w:Fire(p, "MAIL_SEND_SUCCESS")
		else
			p.mailOut = { copper = change == "amount" and 9999 or 10000, cod = change == "cod" and 10000 or 0 }
			if change == "note" then note = "unrelated donation" end
			if change == "guild" then note = note:gsub(p.guild, "Olympus Vale") end
			w:As(p, p.globals.SendMail, change == "recipient" and t.name or mail.name, note)
			if change == "failed" then w:Fire(p, "MAIL_FAILED") end
			w:Fire(p, "MAIL_SEND_SUCCESS")
		end
		eq(Status(w, p), "unknown", change)
	end
end)

test("Dues payer loop: manual book lines, failed intake and missing money observation never emit a confirmation", function()
	local w, p, t, mail = Setup()
	w:As(t, t.ns.Treasury.Record, p.name, 10000, "mail", nil, { note = w:As(p, p.ns.Dues.Note, nil, p.guild), quiet = true })
	w:Run(5); eq(#Receipts(w), 0); eq(Status(w, p), "unknown")
	local i = w:Mail(p, mail, 10000, Intent(w, p))
	w:As(mail, mail.globals.TakeInboxMoney, i); w:Fire(mail, "MAIL_FAILED"); w:Fire(mail, "PLAYER_MONEY")
	w:Run(5); eq(#Receipts(w), 0); eq(Status(w, p), "sent")
	mail.globals.GetMoney = nil
	w:As(mail, mail.ns.Treasury.MailTaking, i)
	w:Run(5); eq(#Receipts(w), 0, "legacy book fallback is not an observed receipt")
end)

test("Dues payer loop: a tiny observed gift cannot authenticate prior manual money and the same native line counts once", function()
	local w, p, _, mail = Setup()
	local note = w:As(p, p.ns.Dues.Note, nil, p.guild)
	w:As(mail, mail.ns.Treasury.Record, p.name, 1000000, "mail", nil, { note = note, quiet = true })
	local i = w:Mail(p, mail, 100, note); w:Take(mail, i); w:Run(8)
	local status, copper = Status(w, p); eq(status, "partial"); eq(copper, 100, "only native observed gold, not book aggregate")
	local book = w:As(mail, mail.ns.Treasury.BookOf, mail.name)
	local e = book.lines[#book.lines]
	eq(w:As(mail, mail.ns.Dues.PayerBooked, book, e, p.name, true), false, "same stable recorded line cannot count twice")
	w:Run(8); eq(select(2, Status(w, p)), 100); eq(#Receipts(w), 1)
end)

test("Dues payer loop: actual completed gold-only trade counts, a closed or item-for-gold trade does not", function()
	local w, p, t = Setup()
	w:Trade(p, t, { aGives = 10000 }); w:Run(8)
	eq(Status(w, p), "counted", "original native completed-trade book observation")
	local count = #Receipts(w)
	w:Fire(t, "TRADE_SHOW"); w:Fire(t, "TRADE_CLOSED"); w:Run(5)
	eq(#Receipts(w), count, "opening or cancelling gives no gold")
	w:Trade(p, t, { aGives = 10000, complete = false }); w:Run(5)
	eq(#Receipts(w), count, "a cancelled native trade is not a contribution")
	w:Trade(p, t, { aGives = 10000, bItems = { { name = "Linen Cloth", count = 1 } } }); w:Run(5)
	eq(#Receipts(w), count, "gold paid for an item is no dues receipt")
end)

test("Dues payer loop: role spoof, wrong lane, amount, guild, faction and replays cannot grant or duplicate a receipt", function()
	local w, p, t, mail = Setup()
	local i = w:Mail(p, mail, 10000, Intent(w, p)); w:Take(mail, i); w:Run(8)
	local wire = assert(Receipts(w)[1]).msg
	local row = p.rdb.duesPayer[p.name].weeks[p.ns.Dues.Week()]
	local before = row.sources[2]
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", mail.name, wire), false, "replay")
	eq(row.sources[2], before, "keeps the original verified source rather than adding")
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "CHANNEL", mail.name, wire), false)
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", p.name, wire), false)
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", t.name, wire), false, "main Treasurer cannot claim the mail book's identity")
	local seq = tonumber(wire:match("^FR~1~2~(%d+)"))
	local new = wire:gsub("^FR~1~2~%d+", "FR~1~2~" .. (seq + 1))
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", mail.name, new:gsub("~10000~10000~", "~9000~10000~")), false, "wrong weekly amount")
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", mail.name, new:gsub(p.guild, "Olympus Vale")), false, "wrong guild")
	p.ns.faction = "Horde"
	eq(w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", mail.name, new), false)
end)

test("Dues payer loop: observed partial receipts are not full payment and cumulative replay-safe books add once", function()
	local w, p, _, mail = Setup()
	local note = w:As(p, p.ns.Dues.Note, nil, p.guild)
	local i = w:Mail(p, mail, 4000, note); w:Take(mail, i); w:Run(8)
	local status, copper = Status(w, p); eq(status, "partial"); eq(copper, 4000)
	i = w:Mail(p, mail, 6000, note); w:Take(mail, i); w:Run(8)
	status, copper = Status(w, p); eq(status, "counted"); eq(copper, 10000, "book cumulative totals replace, never sum receipt replays")
	eq(#Receipts(w), 2)
	w.clock = w.clock + p.ns.Dues.WEEK * 6
	eq(Status(w, p), "unknown")
	local n = 0; for _ in pairs(p.rdb.duesPayer[p.name].weeks) do n = n + 1 end
	eq(n, 0, "saved payer facts stay bounded to the kept reset window")
end)

test("Dues payer loop: receipt bursts stay private, paced and coalesced, replay does not flood the payer's notices", function()
	local w, p, t = Setup()
	for _ = 1, 5 do w:Trade(p, t, { aGives = 2000 }) end
	w:Run(12)
	eq(Status(w, p), "counted")
	local receipts = Receipts(w)
	eq(#receipts <= 5, true, "pending cumulative words coalesce")
	for _, r in ipairs(receipts) do eq(r.dist, "WHISPER"); eq(r.target, p.name) end
	local notices = 0
	local prefix = p.ns.L.DUES_PAYER_RECEIPT:match("^(.-)%%s")
	for _, line in ipairs(p.printed) do if line:find(prefix, 1, true) then notices = notices + 1 end end
	eq(notices, 1, "one notice per issuer in a 30 second burst")
	local count = #p.printed
	for _ = 1, 30 do w:As(p, p.ns.Dues.HandlePayerReceipt, "WHISPER", t.name, assert(receipts[#receipts]).msg) end
	eq(#p.printed, count, "replays grant no new receipt or notice")
end)

test("Dues payer loop: local reminders are once per reset, dismissible and opt-out, never fill, send, accept or sanction", function()
	local w, p, t = Setup()
	local calls, sent = #p.win.calls, #w.sent
	w:Fire(p, "MAIL_INBOX_UPDATE")
	local s = p.rdb.duesPayer[p.name]; eq(s.reminded, p.ns.Dues.Week())
	eq(w:As(p, p.ns.Dues.PayerReminder, "mail"), false)
	eq(#p.win.calls, calls); eq(#w.sent, sent)
	w.clock = w.clock + p.ns.Dues.WEEK
	assert(w:As(p, p.ns.Dues.DismissPayerReminder)); eq(w:As(p, p.ns.Dues.PayerReminder, "mail"), false)
	w.clock = w.clock + p.ns.Dues.WEEK
	assert(w:As(p, p.ns.Dues.DismissPayerReminder, true)); eq(w:As(p, p.ns.Dues.PayerReminder, "mail"), false)
	w.clock = w.clock + p.ns.Dues.WEEK
	eq(w:As(p, p.ns.Dues.PayerReminder, "mail"), false, "opt-out survives later resets")
	eq(#p.win.calls, calls); eq(#w.sent, sent)
	eq(t.ns.Dues.Outbox()[1], nil, "no private player/Captain escalation was invented")
end)

test("Dues payer loop: an offline payer recovers only his observed receipt after both clients reload, not another name or manual totals", function()
	local w, p, _, mail = Setup()
	local i = w:Mail(p, mail, 10000, Intent(w, p))
	w:Logout(p); w:Take(mail, i); w:Run(8)
	w:Logout(mail); w:Login(mail); mail.ns.splitNames = true; mail.ns.Comm.Hash36 = H.ns.Comm.Hash36
	w:Login(p); p.ns.splitNames = true; p.ns.Comm.Hash36 = H.ns.Comm.Hash36
	eq(Status(w, p), "sent", "offline delivery never invents an acknowledgement")
	assert(w:As(p, p.ns.Dues.RequestPayerReceipt)); eq(w:As(p, p.ns.Dues.RequestPayerReceipt), false, "payer request paced")
	w:Run(8); eq(Status(w, p), "counted", "only keeper-held observed receipt replayed privately")
	local ask = "FP~1~" .. p.ns.Dues.Week()
	eq(w:As(mail, mail.ns.Dues.HandlePayerAsk, "WHISPER", p.name, ask), false, "server-side repeat asker paced")
	eq(w:As(mail, mail.ns.Dues.HandlePayerAsk, "CHANNEL", p.name, ask), false)
	eq(w:As(mail, mail.ns.Dues.HandlePayerAsk, "WHISPER", W.NAMES.bettor2, ask), false, "unknown payer has no proof")
	eq(w:As(mail, mail.ns.Dues.HandlePayerAsk, "WHISPER", W.NAMES.bettor2, ask .. "~" .. p.name), false, "body cannot select another payer")
	eq(w:As(mail, mail.ns.Dues.HandlePayerAsk, "WHISPER", W.NAMES.bettor2:gsub("Emberfall", "Wrongrealm"), ask), false)
	local before = #Receipts(w)
	w:As(mail, mail.ns.Treasury.Record, W.NAMES.bettor2, 10000, "mail", nil,
		{ note = w:As(p, p.ns.Dues.Note, nil, p.guild), quiet = true })
	eq(w:As(mail, mail.ns.Dues.HandlePayerAsk, "WHISPER", W.NAMES.bettor2, ask), false, "manual ledger totals do not become observed receipts")
	w:Run(8); eq(#Receipts(w), before)
end)

test("Dues payer loop: native proof and pending queue caps preserve observed facts without granting overflow payer credit", function()
	local w, p, t = Setup()
	local p2, p3 = M.Client(w, W.NAMES.fighterB, { money = 1000000 }), M.Client(w, W.NAMES.bettor1, { money = 1000000 })
	for _, c in ipairs({ p2, p3 }) do c.ns.splitNames = true end
	t.ns.Dues.PAYER_PROOFS_MAX, t.ns.Dues.PAYER_RECEIPTS_MAX = 2, 1
	for _, c in ipairs({ p, p2, p3 }) do w:Trade(c, t, { aGives = 10000 }) end
	w:Run(8)
	eq(#Receipts(w), 1, "one pending native whisper at the configured cap")
	eq(Status(w, p), "counted"); eq(Status(w, p2), "unknown"); eq(Status(w, p3), "unknown")
	local book = w:As(t, t.ns.Treasury.BookOf, t.name)
	local n = 0; for _, rows in pairs(book.duesPayerProofs) do for _ in pairs(rows) do n = n + 1 end end
	eq(n, 2, "proof cap never authenticates manual book aggregates for an overflow payer")
	assert(w:As(p2, p2.ns.Dues.RequestPayerReceipt)); w:Run(8)
	eq(Status(w, p2), "counted", "native proof survives transient queue overflow for later own-payer recovery")
	eq(Status(w, p3), "unknown")
end)

test("Dues payer loop: the same short name on another linked realm cannot retrieve the original payer's private proof", function()
	local w, p, t = Setup()
	w:Trade(p, t, { aGives = 10000 }); w:Run(8)
	local twin = M.Client(w, p.short .. "-" .. W.REALMS[2], { realm = W.REALMS[2], money = 1000000 })
	twin.ns.splitNames = true
	local ask = "FP~1~" .. p.ns.Dues.Week()
	eq(w:As(t, t.ns.Dues.HandlePayerAsk, "WHISPER", twin.name, ask), false, "server-stamped full identity, not legacy ShortName ledger key")
	eq(Status(w, twin), "unknown")
	w:Run(8); eq(#Receipts(w), 1, "no whisper of another payer's confirmed facts")
	local book = w:As(t, t.ns.Treasury.BookOf, t.name)
	assert(book.duesPayerProofs[p.ns.Dues.Week()][p.name:lower()])
	eq(book.duesPayerProofs[p.ns.Dues.Week()][twin.name:lower()], nil)
end)

test("Dues payer loop: real Privacy choice is per character, local only, never pending or an automatic popup", function()
	local w, p, t = Setup()
	local C, key = p.ns.Consent, "dues-reminder"
	eq(w:As(p, C.Answer, key), true, "local reminder default, not a new sharing default")
	local item
	for _, i in ipairs(w:As(p, C.Items)) do if i.key == key then item = i end end
	assert(item); eq(item.perCharacter, true)
	local pending, due = #w:As(p, C.Pending), w:As(p, C.NoticeDue)
	for _, i in ipairs(w:As(p, C.Pending)) do eq(i.key == key, false) end
	local calls, sends = #p.win.calls, #w.sent
	assert(w:As(p, C.Choose, key, false)); eq(w:As(p, C.Answer, key), false)
	eq(w:As(p, p.ns.Dues.PayerReminder, "mail"), false)
	assert(w:As(p, C.Choose, key, true)); eq(w:As(p, C.Answer, key), true)
	eq(w:As(p, p.ns.Dues.PayerReminder, "mail"), false, "reenabling does not reopen this reset's reminder")
	eq(#w:As(p, C.Pending), pending); eq(w:As(p, C.NoticeDue), due)
	eq(w:As(p, C.Frame), nil); eq(#p.win.calls, calls); eq(#w.sent, sends)
	assert(w:As(p, C.Choose, key, false)); w:Logout(p); w:Login(p); p.ns.splitNames = true
	eq(w:As(p, p.ns.Consent.Answer, key), false, "actual relog keeps the character's local opt-out")
	for _, i in ipairs(w:As(t, t.ns.Consent.Items)) do eq(i.key == key, false, "keeper has no payer reminder line") end
end)

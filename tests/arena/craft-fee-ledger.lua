-- 1.2.1, the fee desk's ledger (CraftRequests.lua): the guild's 6% of direct sales as the desk's
-- client books it, against made-up fee words and fee mails. On the test world: each client holds its
-- own records and hears the others only through the world's lanes. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)
local NoErrors = K.NoErrors
local ITEM = 14342

print("CraftRequests: the fee desk's ledger")

-- A requester and a crafter who makes ITEM.
local function Cast(w)
	local a = K.Client(w, "Sage Owl", { money = 500000 })
	local b = K.Client(w, "Wren Thistle", { money = 500000 })
	K.Recipes(w, b, { [ITEM] = "Mooncloth" })
	return a, b
end

-- A taken request with agreed direct terms, the crafter started: a's record.
local function DirectDeal(w, a, b, unit)
	w:Run(61) -- (a minute apart: each party's words are bounded per minute)
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id))
	w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", unit or 10000, 0, { source = "manual" }, { rail = "direct", payment = "trade" }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id))
	w:Run(0)
	assert(b.Craft.Start(r.id))
	w:Run(0)
	assert(r.state == "in_progress", r.state)
	return r
end
local function Completed(w, a, b, unit)
	local r = DirectDeal(w, a, b, unit)
	assert(b.Craft.Deliver(r.id, 1, unit or 10000, "trade")); w:Run(0)
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	return r, K.Rec(w, b, r.id)
end
local function HearsDesk(clients, desk)
	for _, c in ipairs(clients) do
		c.Treasury.Heard(desk.name)
		c.Treasury.MarkReader(desk.name)
	end
end
local function Ledger(desk)
	return desk.Craft.FeeLedger() or { entries = {} }
end
local function Rows(desk, pred)
	local n = 0
	for _, e in pairs(Ledger(desk).entries or {}) do if not pred or pred(e) then n = n + 1 end end
	return n
end
local function Entry(desk, id)
	for _, e in pairs(Ledger(desk).entries or {}) do if e.id == id then return e end end
end
-- A modified client's word of a sale, straight to the desk (gross in base 36).
local function FeeWordTo(w, from, desk, id, role, requester, crafter, gross36)
	from.Comm.Whisper(desk.name, ("CK~1~%s~%d~fee~%s~%s~%s~%s~b2m~1~"):format(id, w.clock + 7, role, requester, crafter, gross36), nil, true, true)
	w:Run(0)
end

test("1.2.1 craft fee desk: with the Wallet off the desk books no made-up word of a sale and no fee mail, and the buyer who saw the trade sends no word of one", function()
	local w = World.New({ compliance = "shipped" })
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c }, desk)
	-- A modified client's words of sales nobody made, as seller and as buyer.
	FeeWordTo(w, c, desk, "fk001", "s", a.name, c.name, "8ow")
	w:Run(61)
	FeeWordTo(w, c, desk, "fk002", "b", c.name, b.name, "8ow")
	eq(Rows(desk), 0, "no fee is owed while the Wallet is off: the desk's ledger takes no word of one")
	-- A mail titled as a fee is still the guild's money in the desk's book, but no fee row.
	local i = w:Mail(c, desk, 50, "Olympus craft fee fk003")
	w:Take(desk, i)
	eq(Rows(desk), 0, "nor a row for a fee mail")
	-- The buyer saw the trade and never confirmed: his copy tells the desk nothing.
	local r = DirectDeal(w, a, b)
	K.Trade(w, a, b, { aGives = 10000, bItems = { { id = ITEM, count = 1 } } })
	K.Jump(w, (a.Craft.CONFIRM_WAIT or 72 * 60 * 60) + 60)
	HearsDesk({ a, b, c }, desk)
	w:Run(61)
	eq(r.settlement.feeReport, nil, "no fee report from the buyer's copy")
	eq(K.Rec(w, b, r.id).settlement.feeReport, nil, "nor from the seller's")
	eq(Rows(desk), 0)
	NoErrors(w)
end)

test("1.2.1 craft fee desk: a flood cannot wedge a full ledger nor push out others' fees: room comes from whoever holds the most, a real sale is booked, an honest buyer's word and the desk's own confirmation stay, and each eviction is kept, logged and counted", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local d = K.Client(w, "Brindle Ash", { money = 500000 })
	local f = K.Client(w, "Fen Marlow", { money = 500000 })
	local t = K.Client(w, "Tansy Brook", { money = 500000 })
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c, d, f, t }, desk)
	w:As(desk, function()
		desk.ns.CraftRequests.FEES_MAX = 6
		desk.ns.CraftRequests.FEES_PER_SELLER = 3
	end)
	-- A fee on a buyer's word that the desk checked and confirmed by hand: the oldest row.
	FeeWordTo(w, c, desk, "held01", "b", c.name, a.name, "8ow")
	local held = assert(Entry(desk, "held01"))
	eq(desk.Craft.SettleFee(held.key, "confirmed", "checked with both"), true)
	-- An honest buyer's word of a sale its seller never told the desk of: older than any flood, it
	-- waits apart (his client tells the desk no more once it answered).
	FeeWordTo(w, t, desk, "real01", "b", t.name, b.name, "7ps")
	-- Two characters of one member fill the rest with sales nobody made, each within his own cap.
	w:Run(61)
	for n = 1, 3 do FeeWordTo(w, c, desk, "fk00" .. n, "s", a.name, c.name, "h") end
	FeeWordTo(w, d, desk, "fk004", "s", a.name, d.name, "h")
	eq(Rows(desk), 6, "the ledger is full")
	-- A real sale: booked all the same, in the place of the oldest fee of whoever holds the most.
	w:Run(61)
	local r = Completed(w, a, b)
	local e = assert(Entry(desk, r.id), "the real sale is booked on a full ledger")
	eq(e.fee, 600)
	assert(e.by.s and e.by.b, "both parties' words")
	eq(Rows(desk), 6, "never over FEES_MAX")
	eq(Entry(desk, "fk001"), nil, "the oldest fee of the one holding the most went")
	assert(Entry(desk, "real01"), "never the honest buyer's word, older though it is")
	-- More made-up words: a name holding fewer takes room from the one holding the most; once
	-- nobody holds more than the sender would then, a full ledger takes no more.
	w:Run(61)
	FeeWordTo(w, f, desk, "fk005", "s", a.name, f.name, "h")
	assert(Entry(desk, "fk005"))
	eq(Entry(desk, "fk002"), nil, "the flood's own fee went")
	FeeWordTo(w, f, desk, "fk006", "s", a.name, f.name, "h")
	FeeWordTo(w, d, desk, "fk007", "s", a.name, d.name, "h")
	eq(Entry(desk, "fk006"), nil, "nobody holds more than he would")
	eq(Entry(desk, "fk007"), nil)
	assert(Entry(desk, r.id), "the real sale stays")
	assert(Entry(desk, "real01"), "the honest buyer's word stays")
	assert(Entry(desk, "held01"), "the desk's own confirmation stays")
	eq(Rows(desk), 6)
	-- Each fee evicted is kept for its return, logged, and counted in /oly status on the desk.
	local led = desk.Craft.FeeLedger()
	eq(led.evicted, 2)
	assert(type(led.gone) == "table", "the evicted are kept")
	local kept = {}
	for _, x in pairs(led.gone) do kept[#kept + 1] = x.id end
	table.sort(kept)
	eq(table.concat(kept, " "), "fk001 fk002")
	local line = assert(desk.Craft.FeeStatusLine())
	assert(line:find("evicted for room: 2", 1, true) and line:find("kept for their return: 2", 1, true), line)
	local logged = 0
	for _, l in ipairs(desk.log or {}) do if l:find("evicted for room", 1, true) then logged = logged + 1 end end
	eq(logged, 2, "each eviction is logged")
	eq(a.Craft.FeeStatusLine(), nil, "the line is the desk's alone")
	NoErrors(w)
end)

test("1.2.1 craft fee desk: each sender's fees the desk never confirmed are capped, his fee mails no word named too; a fee the desk confirmed by hand frees his room, and a later word still finds its mail", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	HearsDesk({ a, b, c }, desk)
	w:As(desk, function()
		desk.ns.CraftRequests.FEES_BUYER_ONLY = 2
		desk.ns.CraftRequests.FEES_PER_SELLER = 3
	end)
	-- c names himself the buyer of sales nobody made: two at most wait apart.
	for n = 1, 3 do FeeWordTo(w, c, desk, "by00" .. n, "b", c.name, n == 2 and a.name or b.name, "8ow") end
	eq(Rows(desk, function(e) return e.requester == c.name end), 2, "FEES_BUYER_ONLY on his word alone")
	eq(Entry(desk, "by003"), nil)
	-- The desk checks both with the parties and confirms them by hand: his word alone no longer.
	for _, id in ipairs({ "by001", "by002" }) do eq(desk.Craft.SettleFee(Entry(desk, id).key, "confirmed", "checked with both"), true) end
	w:Run(61)
	FeeWordTo(w, c, desk, "by003", "b", c.name, b.name, "8ow")
	assert(Entry(desk, "by003"), "room again once the desk confirmed his others")
	-- Fee mails for sales no word ever named: FEES_PER_SELLER per payer, never the whole ledger.
	for n = 1, 4 do w:Take(desk, w:Mail(c, desk, 2, "Olympus craft fee ml00" .. n)) end
	eq(Rows(desk, function(e) return e.crafter == c.name and not e.fee end), 3, "his fee mails alone open FEES_PER_SELLER rows at most")
	eq(Entry(desk, "ml004"), nil)
	-- Those count with his own words of sales: at his cap, a fourth sale of his is refused...
	w:Run(61)
	FeeWordTo(w, c, desk, "sl001", "s", a.name, c.name, "8ow")
	eq(Entry(desk, "sl001"), nil, "his cap holds across his words and his mails")
	-- ...while his word of the sale a mail paid takes that mail, with no room needed.
	FeeWordTo(w, c, desk, "ml001", "s", a.name, c.name, "8ow")
	local e = assert(Entry(desk, "ml001"))
	eq(e.paid, 2); eq(e.requester, a.name); eq(e.fee, 675)
	NoErrors(w)
end)

test("1.2.1 craft fee desk: a fee word is taken only from the party it names as its sender: nobody books a sale between two others", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c }, desk)
	-- c says a bought from b, and then that b sold to a: he is neither.
	FeeWordTo(w, c, desk, "tp001", "b", a.name, b.name, "8ow")
	FeeWordTo(w, c, desk, "tp002", "s", a.name, b.name, "8ow")
	-- Nor may one name himself both parties.
	FeeWordTo(w, c, desk, "tp003", "s", c.name, c.name, "8ow")
	eq(Rows(desk), 0, "no row for a sale its sender is no party to")
	NoErrors(w)
end)

-- The fee of request id between requester and crafter, on the desk's ledger.
local function Fee(desk, id, crafter, requester)
	return desk.Craft.FeeLedger().entries[("%s|%s|%s"):format(id, crafter.name:lower(), requester and requester.name:lower() or "-")]
end

test("1.2.1 craft fee desk: a made-up buyer's word never takes the seller's fee mail, whichever came first: the gold he paid is on his own fee, which is paid, and he is nobody's debtor", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	HearsDesk({ a, b, c }, desk)
	-- b's fee mail for his sale to a reaches the desk before either party's word of it; then c names
	-- himself the buyer of that sale.
	w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee sale01"))
	FeeWordTo(w, c, desk, "sale01", "b", c.name, b.name, "7ps")
	-- Another sale: c's word comes first, then b's mail.
	w:Run(61)
	FeeWordTo(w, c, desk, "sale02", "b", c.name, b.name, "7ps")
	w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee sale02"))
	-- The parties' own words of both sales, the buyer's first.
	for _, id in ipairs({ "sale01", "sale02" }) do
		w:Run(61)
		FeeWordTo(w, a, desk, id, "b", a.name, b.name, "7ps")
		FeeWordTo(w, b, desk, id, "s", a.name, b.name, "7ps")
		local real = assert(Fee(desk, id, b, a), id .. ": the real sale's fee")
		assert(real.by.s and real.by.b, "both parties' words")
		eq(real.paid, 600, id .. ": the seller's gold is on his own fee")
		eq(real.state, "paid")
		local fake = assert(Fee(desk, id, b, c), id .. ": the made-up purchase waits apart")
		eq(fake.paid, 0, id .. ": with none of the seller's gold")
		eq(Fee(desk, id, b), nil, id .. ": no payment left waiting")
	end
	for _, d in ipairs(desk.Craft.Debtors().ranking) do assert(d.name ~= b.name, "the seller who paid is nobody's debtor") end
	NoErrors(w)
end)

test("1.2.1 craft fee desk: a seller's fee mail on a sale only its buyer named waits apart, and is the seller's once his word comes or the desk confirms that sale by hand", function()
	local w = World.New()
	local a, b = Cast(w)
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	HearsDesk({ a, b }, desk)
	for _, id in ipairs({ "sale03", "sale04" }) do
		FeeWordTo(w, a, desk, id, "b", a.name, b.name, "7ps")
		w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee " .. id))
		local e = assert(Fee(desk, id, b, a), "the buyer's word")
		eq(e.paid, 0, "a buyer's word alone takes none of the seller's gold")
		eq(Fee(desk, id, b).paid, 600, "it waits for the seller's word")
		w:Run(61)
	end
	eq(#desk.Craft.Debtors().ranking, 0)
	-- sale03: the seller's word comes.
	FeeWordTo(w, b, desk, "sale03", "s", a.name, b.name, "7ps")
	eq(Fee(desk, "sale03", b, a).paid, 600); eq(Fee(desk, "sale03", b, a).state, "paid")
	-- sale04: it never does; the desk checks with both and confirms it by hand.
	local e = Fee(desk, "sale04", b, a)
	eq(desk.Craft.SettleFee(e.key, "confirmed", "checked with both"), true)
	eq(e.paid, 600, "the desk's confirmation joins the mail he sent for it")
	eq(e.state, "paid")
	eq(Rows(desk), 2, "one row for each sale")
	eq(#desk.Craft.Debtors().ranking, 0, "he owes nothing")
	NoErrors(w)
end)

test("1.2.1 craft fee desk: a seller's own made-up sales never push out his buyer's word of a real one, nor its higher figure", function()
	local w = World.New()
	local a, b = Cast(w)
	local d = K.Client(w, "Brindle Ash", { money = 500000 })
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, d }, desk)
	w:As(desk, function() desk.ns.CraftRequests.FEES_MAX = 5 end)
	-- a bought for 100g; b says 1g: the gap waits for the desk.
	FeeWordTo(w, a, desk, "own01", "b", a.name, b.name, "7ps")
	FeeWordTo(w, b, desk, "own01", "s", a.name, b.name, "2s")
	local e = assert(Fee(desk, "own01", b, a))
	eq(e.fee, 600); eq(e.grossB, 10000); eq(e.grossS, 100)
	-- b fills the ledger with sales nobody made, then his other character's word asks for room.
	w:Run(61)
	FeeWordTo(w, b, desk, "own02", "s", a.name, b.name, "h")
	FeeWordTo(w, b, desk, "own03", "s", a.name, b.name, "h")
	FeeWordTo(w, b, desk, "own06", "s", a.name, b.name, "h")
	FeeWordTo(w, d, desk, "own04", "s", a.name, d.name, "h")
	eq(Rows(desk), 5, "full")
	w:Run(61)
	FeeWordTo(w, d, desk, "own05", "s", a.name, d.name, "h")
	assert(Fee(desk, "own05", d, a), "room was made")
	eq(Fee(desk, "own02", b, a), nil, "from his own made-up sale")
	e = assert(Fee(desk, "own01", b, a), "the buyer's word of the real sale stays")
	eq(e.fee, 600, "with the buyer's figure")
	local found = false
	for _, x in ipairs(desk.Craft.Debtors().toCheck) do if x.id == "own01" then found = true end end
	assert(found, "still waiting for the desk")
	NoErrors(w)
end)

test("1.2.1 craft fee desk: a fee evicted for room comes back as it was when its seller tells the desk again: its first deadline, the buyer's word and his figure above the seller's", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local d = K.Client(w, "Brindle Ash", { money = 500000 })
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	HearsDesk({ a, b, c, d }, desk)
	w:As(desk, function() desk.ns.CraftRequests.FEES_MAX = 5 end)
	-- A real sale, both parties' words, its deadline the desk's.
	local r, rb = Completed(w, a, b)
	local e = assert(Fee(desk, r.id, b, a))
	local due = e.due
	assert(e.by.s and e.by.b)
	-- Another sale of b's to a, at 100g on a's word and 1g on b's: the desk is to check it.
	w:Run(61)
	FeeWordTo(w, a, desk, "gap01", "b", a.name, b.name, "7ps")
	FeeWordTo(w, b, desk, "gap01", "s", a.name, b.name, "2s")
	eq(Fee(desk, "gap01", b, a).fee, 600)
	-- a holds most of the ledger (two more words of his), c the rest: full.
	w:Run(61)
	FeeWordTo(w, a, desk, "buy01", "b", a.name, b.name, "8ow")
	FeeWordTo(w, a, desk, "buy02", "b", a.name, b.name, "8ow")
	FeeWordTo(w, c, desk, "fk001", "s", b.name, c.name, "h")
	eq(Rows(desk), 5, "full")
	-- 71 hours on, d's words take room from a's oldest: the real sale, then the gap.
	K.Jump(w, b.Craft.FEE_DUE - 3600)
	FeeWordTo(w, d, desk, "fk002", "s", b.name, d.name, "h")
	FeeWordTo(w, d, desk, "fk003", "s", b.name, d.name, "h")
	eq(Fee(desk, r.id, b, a), nil, "evicted")
	eq(Fee(desk, "gap01", b, a), nil, "evicted")
	-- The desk waives c's and d's made-up sales: room for both to come back.
	for _, x in ipairs({ Fee(desk, "fk001", c, b), Fee(desk, "fk002", d, b) }) do eq(desk.Craft.SettleFee(x.key, "waived", "no such sale"), true) end
	-- b's client tells the desk again while his fee is open: the same fee, its first deadline.
	eq(rb.settlement.feeState, "due")
	K.Jump(w, b.Craft.ASK_GAP + 1)
	HearsDesk({ a, b, c, d }, desk)
	w:Run(61)
	e = assert(Fee(desk, r.id, b, a), "his word came again")
	eq(e.due, due, "its first deadline, never a fresh one")
	assert(e.by.b and e.by.s, "the buyer's word with it")
	eq(e.fee, 600)
	-- b's word of the gap again: the buyer's 100g still sets the fee, which still waits apart.
	FeeWordTo(w, b, desk, "gap01", "s", a.name, b.name, "2s")
	e = assert(Fee(desk, "gap01", b, a), "booked again")
	eq(e.grossB, 10000, "the buyer's figure kept")
	eq(e.fee, 600)
	local waiting = false
	for _, x in ipairs(desk.Craft.Debtors().toCheck) do if x.id == "gap01" then waiting = true end end
	assert(waiting, "not taken as confirmed on the seller's lower word")
	w:Take(desk, w:Mail(b, desk, 6, "Olympus craft fee gap01"))
	eq(Fee(desk, "gap01", b, a).state, "due", "a 6-copper mail pays none of it off")
	-- Two hours past the first deadline, he is late with the real sale's fee.
	K.Jump(w, due + 7200 - w.clock)
	local late = 0
	for _, x in ipairs(desk.Craft.Debtors().ranking) do if x.name == b.name then late = x.late end end
	eq(late, 600, "late from the first deadline")
	NoErrors(w)
end)

test("1.2.1 craft fee desk: the gold on a fee evicted for room is still the seller's: his fee mail evicted joins his word when it comes, and his evicted word takes the mail he sent after", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local d = K.Client(w, "Brindle Ash", { money = 500000 })
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	HearsDesk({ a, b, c, d }, desk)
	w:As(desk, function() desk.ns.CraftRequests.FEES_MAX = 3 end)
	-- b's fee mails for two sales come before any word of them; c's word fills the ledger.
	w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee ml001"))
	w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee ml002"))
	FeeWordTo(w, c, desk, "fk001", "s", a.name, c.name, "h")
	eq(Rows(desk), 3, "full")
	-- d's word takes room from b, who holds the most: his oldest mail.
	FeeWordTo(w, d, desk, "fk002", "s", a.name, d.name, "h")
	eq(Fee(desk, "ml001", b), nil, "evicted")
	-- The desk waives c's made-up fee (room again), and b's word of the sale comes: his mail is on it.
	eq(desk.Craft.SettleFee(Fee(desk, "fk001", c, a).key, "waived", "no such sale"), true)
	w:Run(61)
	FeeWordTo(w, b, desk, "ml001", "s", a.name, b.name, "7ps")
	local e = assert(Fee(desk, "ml001", b, a))
	eq(e.paid, 600, "the evicted mail's gold joined his word")
	eq(e.state, "paid")
	-- Now his word is the one evicted (he holds the most again), and his mail comes after it.
	w:Run(61)
	FeeWordTo(w, b, desk, "sl001", "s", a.name, b.name, "7ps")
	local due = Fee(desk, "sl001", b, a).due
	eq(desk.Craft.SettleFee(Fee(desk, "fk002", d, a).key, "waived", "no such sale"), true)
	FeeWordTo(w, c, desk, "fk003", "s", a.name, c.name, "h") -- (the waived fee's room)
	w:Run(61)
	FeeWordTo(w, d, desk, "fk004", "s", a.name, d.name, "h")
	eq(Fee(desk, "sl001", b, a), nil, "his word evicted")
	eq(desk.Craft.SettleFee(Fee(desk, "fk003", c, a).key, "waived", "no such sale"), true)
	w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee sl001"))
	eq(Fee(desk, "sl001", b).paid, 600, "the mail waits on its own")
	K.Jump(w, 3600)
	FeeWordTo(w, b, desk, "sl001", "s", a.name, b.name, "7ps")
	e = assert(Fee(desk, "sl001", b, a))
	eq(e.paid, 600); eq(e.state, "paid")
	eq(e.due, due, "the same fee, its first deadline")
	eq(Fee(desk, "sl001", b), nil, "no payment left waiting")
	for _, x in ipairs(desk.Craft.Debtors().ranking) do assert(x.name ~= b.name, "he owes nothing") end
	NoErrors(w)
end)

test("1.2.1 craft fee desk: the fees kept for their return are bounded, whoever has the most kept losing his oldest first", function()
	local w = World.New()
	local a, b = Cast(w)
	local names = { "Moss Harrow", "Brindle Ash", "Fen Marlow", "Tansy Brook", "Rook Elder", "Ivy Calder" }
	local x = {}
	for i, n in ipairs(names) do x[i] = K.Client(w, n, { money = 500000 }) end
	local c, d, e, f, g, h = unpack(x)
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c, d, e, f, g, h }, desk)
	w:As(desk, function()
		desk.ns.CraftRequests.FEES_MAX = 6
		desk.ns.CraftRequests.FEES_GONE_MAX = 2
	end)
	-- a's two words of sales its seller never told; four others' one each: full.
	FeeWordTo(w, a, desk, "ab001", "b", a.name, b.name, "7ps")
	FeeWordTo(w, a, desk, "ab002", "b", a.name, b.name, "7ps")
	for i, who in ipairs({ c, d, e, f }) do FeeWordTo(w, who, desk, "one0" .. i, "s", a.name, who.name, "h") end
	eq(Rows(desk), 6, "full")
	-- g's word: room from a, who holds the most; his fee is kept.
	w:Run(61)
	FeeWordTo(w, g, desk, "gg001", "s", a.name, g.name, "h")
	local gone = desk.Craft.FeeLedger().gone
	assert(gone and Fee(desk, "ab001", b, a) == nil, "a's oldest evicted")
	-- c floods: the desk waives the others' made-up sales, and his words fill their room.
	for i, who in ipairs({ d, e, f }) do eq(desk.Craft.SettleFee(Fee(desk, "one0" .. (i + 1), who, a).key, "waived", "no such sale"), true) end
	w:Run(61)
	for n = 1, 3 do FeeWordTo(w, c, desk, "cc00" .. n, "s", a.name, c.name, "h") end
	-- h's words: room from c twice; three kept, over FEES_GONE_MAX: c's oldest kept goes, never a's.
	w:Run(61)
	FeeWordTo(w, h, desk, "hh001", "s", a.name, h.name, "h")
	w:Run(61)
	FeeWordTo(w, h, desk, "hh002", "s", a.name, h.name, "h")
	local kept = {}
	for _, k in pairs(gone) do kept[#kept + 1] = k.id end
	table.sort(kept)
	eq(table.concat(kept, " "), "ab001 cc001", "a's kept fee stays; c's oldest kept went")
	eq(desk.Craft.FeeLedger().evicted, 3)
	NoErrors(w)
end)

-- (The review's suggestion to refuse a word whose requester is not the one on the desk's card of that
-- request: a card is the first one the desk heard for that id, from whoever sent it, so a card sent
-- with another request's id while the desk missed the real one would have the real parties' words
-- refused. Pinned here: the words of the sale's own parties are booked whatever card the desk holds.)
test("1.2.1 craft fee desk: a card sent with another request's id, where the desk missed the real one, never keeps the sale's own parties' words off the ledger", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local r = DirectDeal(w, a, b)
	-- The desk logs in after the card was taken: it never saw the real one. c sends one with its id.
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c }, desk)
	local text = w:As(a, function() return a.ns.CraftRequests.Card(a.ns.CraftRequests.Get(r.id)) end)
	local f = {}
	for part in (text .. "~"):gmatch("([^~]*)~") do f[#f + 1] = part end
	f[11] = "o"
	assert(desk.Craft.ReceiveSnapshot("CHANNEL", c.name, table.concat(f, "~")))
	eq(K.Rec(w, desk, r.id).requester, c.name, "the desk's card of that request is c's")
	-- The sale completes: both parties' words are booked all the same.
	assert(b.Craft.Deliver(r.id, 1, 10000, "trade")); w:Run(0)
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	local e = assert(Fee(desk, r.id, b, a), "the real sale's fee")
	assert(e.by.s and e.by.b, "both parties' words")
	eq(e.fee, 600)
	NoErrors(w)
end)

test("1.2.1 craft fee desk: a seller's evicted word that the buyer's late word brings back takes the fee mail he sent meanwhile", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local d = K.Client(w, "Brindle Ash", { money = 500000 })
	local desk = K.Role(w, "treasurerMail", { money = 1000 })
	HearsDesk({ a, b, c, d }, desk)
	w:As(desk, function() desk.ns.CraftRequests.FEES_MAX = 3 end)
	FeeWordTo(w, b, desk, "lw001", "s", a.name, b.name, "7ps")
	FeeWordTo(w, b, desk, "lw002", "s", a.name, b.name, "7ps")
	FeeWordTo(w, c, desk, "fk001", "s", a.name, c.name, "h")
	w:Run(61)
	FeeWordTo(w, d, desk, "fk002", "s", a.name, d.name, "h")
	eq(Fee(desk, "lw001", b, a), nil, "his oldest word evicted")
	for _, x in ipairs({ Fee(desk, "fk001", c, a), Fee(desk, "fk002", d, a) }) do eq(desk.Craft.SettleFee(x.key, "waived", "no such sale"), true) end
	-- His fee mail finds no word of his on the ledger: it waits on its own.
	w:Take(desk, w:Mail(b, desk, 600, "Olympus craft fee lw001"))
	eq(Fee(desk, "lw001", b).paid, 600)
	-- The buyer's word comes late: his seller's word is back with it, and so is his gold.
	FeeWordTo(w, a, desk, "lw001", "b", a.name, b.name, "7ps")
	local e = assert(Fee(desk, "lw001", b, a))
	assert(e.by.s and e.by.b, "both words")
	eq(e.paid, 600); eq(e.state, "paid")
	eq(Fee(desk, "lw001", b), nil, "no payment left waiting")
	NoErrors(w)
end)

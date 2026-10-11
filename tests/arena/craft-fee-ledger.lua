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
local function Cast(w, opts)
	opts = opts or {}
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

test("1.2.1 craft fee desk: a member's characters cannot wedge a full ledger: a real sale is still booked, the oldest unconfirmed fee goes first, the desk's own confirmation never goes, and an evicted seller's fee comes back", function()
	local w = World.New()
	local a, b = Cast(w)
	local c = K.Client(w, "Moss Harrow", { money = 500000 })
	local d = K.Client(w, "Brindle Ash", { money = 500000 })
	local desk = K.Role(w, "treasurerMail")
	HearsDesk({ a, b, c, d }, desk)
	w:As(desk, function()
		desk.ns.CraftRequests.FEES_MAX = 5
		desk.ns.CraftRequests.FEES_PER_SELLER = 3
	end)
	-- A fee on a buyer's word that the desk checked and confirmed by hand: the oldest row.
	FeeWordTo(w, c, desk, "held01", "b", c.name, a.name, "8ow")
	local held = assert(Entry(desk, "held01"))
	eq(desk.Craft.SettleFee(held.key, "confirmed", "checked with both"), true)
	-- Two characters of one member fill the rest with sales nobody made, each within his own cap.
	w:Run(61)
	for n = 1, 3 do FeeWordTo(w, c, desk, "fk00" .. n, "s", a.name, c.name, "h") end
	w:Run(61)
	FeeWordTo(w, d, desk, "fk004", "s", a.name, d.name, "h")
	eq(Rows(desk), 5, "the ledger is full")
	-- A real sale: booked all the same, in the oldest unconfirmed fee's place.
	w:Run(61)
	local r, rb = Completed(w, a, b)
	local e = assert(Entry(desk, r.id), "the real sale is booked on a full ledger")
	eq(e.fee, 600)
	assert(e.by.s and e.by.b, "both parties' words")
	eq(Rows(desk), 5, "never over FEES_MAX")
	eq(Entry(desk, "fk001"), nil, "the oldest fee nobody confirmed went")
	assert(Entry(desk, "fk002") and Entry(desk, "fk003") and Entry(desk, "fk004"), "one row for one")
	assert(Entry(desk, "held01"), "the desk's own confirmation stays")
	-- More made-up words push the real sale out in the end: never the confirmed fee.
	w:Run(61)
	for n = 5, 6 do FeeWordTo(w, d, desk, "fk00" .. n, "s", a.name, d.name, "h") end
	w:Run(61)
	FeeWordTo(w, c, desk, "fk007", "s", a.name, c.name, "h")
	FeeWordTo(w, c, desk, "fk008", "s", a.name, c.name, "h")
	eq(Entry(desk, r.id), nil, "the real sale's row was the oldest left")
	assert(Entry(desk, "held01"), "the confirmed fee still stays")
	eq(Rows(desk), 5)
	-- The seller's fee is still open on his client: it tells the desk again, which books it again.
	eq(rb.settlement.feeState, "due")
	K.Jump(w, b.Craft.ASK_GAP + 1)
	HearsDesk({ a, b, c, d }, desk)
	w:Run(61)
	e = assert(Entry(desk, r.id), "the seller's word came again")
	assert(e.by.s, "his own word")
	eq(e.fee, 600)
	eq(Rows(desk), 5)
	NoErrors(w)
end)

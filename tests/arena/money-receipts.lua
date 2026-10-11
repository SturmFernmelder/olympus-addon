-- 1.2.1, the money part's receipts (ZR, Debts.lua) and an arbiter's exposure (Stakes.lua): what a
-- stranger's receipts can do to an auditor's saved data. With the Wallet off (the release) a receipt
-- is only its two parties' own, and crafting's guild rail still settles its custodian's debt by them;
-- with the Wallet and the stakes on, a match counts toward an arbiter's exposure once both its
-- parties' receipts name it, only a party takes it off, and the records stay bounded. On the test
-- world. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local N = World.NAMES
local M = assert(loadfile(H.ROOT .. "tests/arena/lib/money-world.lua"))(H)
local K = assert(loadfile(H.ROOT .. "tests/arena/lib/craft-world.lua"))(H)
local NoErrors = M.NoErrors
local G = 10000
local ITEM = 14342

-- A receipt's body as Debts.Receipt writes it, sent by `from` (a modified client may say anything).
local function SendReceipt(w, from, to, ref, payer, payee, copper)
	local B36 = from.ns.Arena.B36
	local body = table.concat({ ref, payer, payee, B36(copper), "t", B36(w.clock), "1" }, "~")
	assert(w:As(from, from.ns.Arena.Send, "ZR", "L", body, { to = to.name }), "sent")
end
-- Every key of a table, nested ones too: the size of what a client keeps.
local function Size(t)
	if type(t) ~= "table" then return 0 end
	local n = 0
	for _, v in pairs(t) do n = n + 1 + Size(v) end
	return n
end
local function Kept(w, c, key) return w:As(c, function() return c.ns.Arena.Store("L")[key] end) end

print("1.2.1 the money part: receipts and exposure")

test("1.2.1 the money part: with the Wallet off a stranger's receipts leave an auditor's saved data as it was (no evidence list, no arbiter's exposure)", function()
	local w = World.New({ compliance = "shipped" })
	local aud = w:Role("auditor")
	local x = w:Client("Mabry Quell")
	assert(w:As(aud, aud.ns.ArenaRoles.Auditor, aud.name, "L"), "an auditor")
	for i = 1, 30 do
		SendReceipt(w, x, aud, "S" .. i .. "zz", x.name, N.arbiter, 5 * G)
		SendReceipt(w, x, aud, "D" .. i .. "zz", x.name, N.bettor1, G)
	end
	w:Run(0)
	eq(#w:Sent({ from = x, type = "ZR" }), 60, "the modified client sent them all")
	eq(Size(Kept(w, aud, "receipts")), 0, "no receipt kept")
	eq(Size(Kept(w, aud, "exposure")), 0, "no arbiter's exposure")
	NoErrors(w)
end)

test("1.2.1 the money part: with the Wallet off a keeper's payout on crafting's guild rail still clears his own debt by the seller's receipt", function()
	local w = World.New({ compliance = "shipped" })
	local a, b = K.Client(w, "Sage Owl", { money = 500000 }), K.Client(w, "Wren Thistle", { money = 500000 })
	local t = K.Role(w, "treasurer", { money = 500000 })
	K.Recipes(w, b, { [ITEM] = "Mooncloth" })
	K.GoLive(w, { a, b, t })
	w:Run(10)
	eq(w:As(t, t.ns.Compliance.Wallet), false, "the Wallet is off")
	eq(t.Craft.GoldGate(), nil, "the arena's live gold is on")
	local r = K.Request(w, a, ITEM, "Mooncloth", 1)
	assert(b.Craft.Accept(r.id)); w:Run(0)
	assert(b.Craft.ProposeTerms(r.id, "finished", 10000, 0, { source = "manual" }, { rail = "guild", payment = "trade", custodian = t.name, postage = 30 }))
	w:Run(0)
	assert(a.Craft.ConfirmTerms(r.id)); assert(b.Craft.ConfirmTerms(r.id)); w:Run(0)
	local st = assert(K.Rec(w, t, r.id).settlement, "the custodian took the contract")
	K.Trade(w, b, t, { aItems = { { id = ITEM, count = 1 } } })
	K.Trade(w, a, t, { aGives = 10000 })
	assert(t.Craft.PrepareCustodianForward(r.id, 30))
	K.Trade(w, t, a, { aItems = { { id = ITEM, count = 1 } } })
	assert(a.Craft.ConfirmDelivery(r.id)); w:Run(0)
	assert(t.Craft.ReleaseSettlement(r.id)); w:Run(0)
	assert(st.payoutObligation, "the custodian's payout is his own debt")
	eq(#w:As(t, t.ns.Debts.Open, "L"), 1)
	K.Trade(w, t, b, { aGives = 9400 })
	w:Run(5)
	eq(st.state, "settled")
	eq(#w:As(t, t.ns.Debts.Open, "L"), 0, "the seller's receipt cleared it")
	K.NoErrors(w)
end)

-- The money's cast with an arbiter (cap 2 g) and two fighters, the auditor's hello heard.
local function Arbitered(w)
	local cast = M.Cast(w, { duty = false })
	local king, aud = cast.king, cast.auditor
	local arb = M.Role(w, "arbiter")
	local A, B = M.Client(w, "Torvin Hale", { money = 50000 }), M.Client(w, "Selka Drummond", { money = 50000 })
	for _, c in ipairs({ arb, A, B }) do M.Relog(w, c) end
	assert(king.Roles.SetArbiters({ { name = N.arbiter, cap = 2 } }))
	w:Run(301)
	aud.Wallet.Hello()
	w:Run(0)
	return aud, arb, A, B
end
-- A real match: both stakes (1 g each) held by the arbiter, the receipts to the auditor.
local function Held(w, arb, A, B, id)
	local t = { id = id, kind = "fight", A = { name = A.name }, B = { name = B.name }, stake = { A = G, B = G }, arbiter = N.arbiter }
	for _, c in ipairs({ arb, A, B }) do assert(c.Stakes.Open(t)) end
	w:Trade(A, arb, { aGives = G })
	w:Trade(B, arb, { aGives = G })
	w:Run(5)
end

test("1.2.1 the money part: a stranger's stake receipts alone never count toward an arbiter's exposure, nor make him busy; a match counts once both its parties' receipts name it", function()
	local w = World.New()
	local aud, arb, A, B = Arbitered(w)
	local x = M.Client(w, "Mabry Quell")
	SendReceipt(w, x, aud, "SF9q", x.name, N.arbiter, 2 * G)
	w:Run(0)
	eq(aud.Stakes.ExposureOf(N.arbiter), 0, "one sender's word")
	eq(aud.Debts.Busy(N.arbiter), false)
	Held(w, arb, A, B, "F1s")
	eq(aud.Stakes.ExposureOf(N.arbiter), 2 * G, "both parties' receipts")
	eq(aud.Debts.Busy(N.arbiter), true, "at his cap")
	NoErrors(w)
end)

test("1.2.1 the money part: only a party of a match takes it off an arbiter's exposure; a stranger's payout receipt erases nothing", function()
	local w = World.New()
	local aud, arb, A, B = Arbitered(w)
	local x = M.Client(w, "Mabry Quell")
	Held(w, arb, A, B, "F1s")
	eq(aud.Stakes.ExposureOf(N.arbiter), 2 * G)
	for _, kind in ipairs({ "P", "R", "N" }) do SendReceipt(w, x, aud, kind .. "F1s", N.arbiter, x.name, 19400) end
	w:Run(0)
	eq(aud.Stakes.ExposureOf(N.arbiter), 2 * G, "still held")
	eq(aud.Debts.Busy(N.arbiter), true)
	-- The arbiter's payout to the winner, a party: off, and free again.
	local lines = arb.Stakes.Result("F1s", "A")
	eq(lines[1].copper, 19400)
	arb.trade = nil
	w:Trade(arb, A, { aGives = 19400 })
	w:Run(5)
	eq(aud.Stakes.ExposureOf(N.arbiter), 0)
	eq(aud.Debts.Busy(N.arbiter), false)
	NoErrors(w)
end)

test("1.2.1 the money part: an arbiter's exposure record stays bounded per sender and per arbiter, and a real match still counts past a flood", function()
	local w = World.New()
	local aud, arb, A, B = Arbitered(w)
	local x = M.Client(w, "Mabry Quell")
	local per = aud.ns.Stakes.EXPOSURE_PER_SENDER
	assert(type(per) == "number" and per < 40, "a sender's share")
	for i = 1, 40 do SendReceipt(w, x, aud, "SF" .. i .. "q", x.name, N.arbiter, 100) end
	w:Run(0)
	local one = Size(Kept(w, aud, "exposure"))
	for i = 41, 200 do SendReceipt(w, x, aud, "SF" .. i .. "q", x.name, N.arbiter, 100) end
	w:Run(0)
	eq(Size(Kept(w, aud, "exposure")), one, "one sender's flood stops at his share")
	-- Many senders: the arbiter's record keeps EXPOSURE_MATCHES matches, the oldest uncounted going first.
	aud.ns.Stakes.EXPOSURE_MATCHES = 5
	for i = 1, 12 do
		local y = M.Client(w, "Tobin Rusk" .. string.char(96 + i))
		SendReceipt(w, y, aud, "SG" .. i .. "q", y.name, N.arbiter, 100)
	end
	w:Run(0)
	local e = Kept(w, aud, "exposure")[N.arbiter:lower()]
	local n = 0
	for _ in pairs(e.stakes) do n = n + 1 end
	assert(n <= 5, "at most the arbiter's share: " .. n)
	Held(w, arb, A, B, "F1s")
	eq(aud.Stakes.ExposureOf(N.arbiter), 2 * G, "the real match counts")
	NoErrors(w)
end)

test("1.2.1 the money part: one sender's receipts take at most his share of an auditor's evidence list", function()
	local w = World.New()
	local cast = M.Cast(w, { duty = false })
	local aud = cast.auditor
	local x, y = M.Client(w, "Mabry Quell"), M.Client(w, "Tobin Rusk")
	SendReceipt(w, y, aud, "Dy1q", y.name, N.bettor1, G)
	w:Run(0)
	local share = aud.ns.Debts.RECEIPTS_PER_SENDER
	assert(type(share) == "number" and share < 400, "a sender's share")
	for i = 1, share + 50 do SendReceipt(w, x, aud, "Dx" .. i .. "q", x.name, N.bettor1, G) end
	w:Run(0)
	local list, his, other = Kept(w, aud, "receipts"), 0, 0
	for _, r in ipairs(list) do
		if r.from:lower() == x.name:lower() then his = his + 1 elseif r.from:lower() == y.name:lower() then other = other + 1 end
	end
	eq(his, share, "his oldest went")
	eq(other, 1, "the other sender's receipt stays")
	NoErrors(w)
end)

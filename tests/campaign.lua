local ns, test, eq, H = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]campaign%.lua$") or "./"
local World = assert(loadfile(ROOT .. "tests/arena/lib/world.lua"))({ ROOT = ROOT, ADDON_DIR = ROOT .. "Olympus/", ns = ns })
local function Client(w, role)
	local c = w:Role(role)
	w:As(c, function()
		c.ns.ViewAs = { Previewing = function() return false end }
		for _, file in ipairs({ "Locales/CampaignText", "Chronicle", "Campaign" }) do assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c.ns) end
		local b = c.ns.Treasury.Book(); b.opening, b.openedAt = 0, w.clock
	end)
	return c
end
local function Setup()
	local w = World.New({ council = false, arenaFiles = {}, compliance = "shipped" })
	local king, keeper, member, steward = Client(w, "king"), Client(w, "treasurer"), Client(w, "fighterA"), Client(w, "steward")
	return w, king, keeper, member, steward
end
local function Start(w, king, text)
	w:As(king, function() assert(king.ns.Campaign.Start(text or "Raid supplies | 100 | 1710=20")) end)
	w:Run(1)
end
local function Confirmed(w, keeper, name, amount, options)
	options = options or {}; options.quiet, options.observed = true, true
	return w:As(keeper, function() return keeper.ns.Treasury.Record(name, amount, "trade", nil, options) end)
end
local function NativeTrade(w, keeper, name, amount, item, count)
	local g = keeper.globals
	g.ERR_TRADE_COMPLETE = "Confirmed trade"
	g.GetTargetTradeMoney, g.GetPlayerTradeMoney = function() return amount or 0 end, function() return 0 end
	g.GetTradePlayerItemInfo = function() end
	g.GetTradeTargetItemInfo = function(slot) if slot == 1 and item then return "Potion", nil, count end end
	g.GetTradeTargetItemLink = function(slot) if slot == 1 and item then return "item:" .. item end end
	w:As(keeper, function()
		keeper.ns.UnitFullName = function(unit) return unit == "NPC" and name or keeper.name end
		local T = keeper.ns.Treasury
		T.TradeShow(); T.TradeMoney(); T.Info("Confirmed trade")
	end)
	local lines = keeper.ns.Treasury.Lines()
	return lines[#lines]
end

test("Campaign: actual shared Comm dispatch delivers public campaign and private crafting chat after both modules load", function()
	local w, king, keeper, member = Setup()
	Start(w, king)
	local wire = w:Sent({ from = king, dist = "CHANNEL" })
	local message = wire[#wire].msg
	local registered, campaignType = {}, nil
	w:As(member, function()
		member.ns.rdb.campaign = nil -- no previously delivered fake-transport state can mask a lost native packet
		member.ns.ChatRooms = { RegisterProvider = function() end }
		local on, login = member.ns.On
		member.ns.On = function(event, fn) if event == "LOGIN" then login = fn else on(event, fn) end end
		assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", member.ns)
		member.ns.On = on
		assert(login); login() -- register the real native receive events, not the fixture's fake dispatcher
		local handle = member.ns.Comm.Handle
		member.ns.Comm.Handle = function(kind, fn)
			registered[kind] = (registered[kind] or 0) + 1
			handle(kind, fn)
			if fn == member.ns.Campaign.Handle then campaignType = kind end
		end
		-- The real runtime load order: crafting must not replace Campaign's handler.
		assert(loadfile(ROOT .. "Olympus/Campaign.lua"))("Olympus", member.ns)
		assert(loadfile(ROOT .. "Olympus/CraftRequests.lua"))("Olympus", member.ns)
		member.ns.rdb.craftRequests = { records = { proof1 = {
			id = "proof1", requester = member.name, crafter = keeper.name, guild = member.guild, state = "accepted",
		} }, invites = {} }
	end)
	eq(w:Fire(member, "CHAT_MSG_ADDON_LOGGED", member.ns.PREFIX, message, "CHANNEL", king.name), 1)
	eq(#member.errors, 0, table.concat(member.errors, "\n"))
	w:As(member, function()
		local s = member.ns.Campaign.State()
		assert(s and s.purpose == "Raid supplies", "native campaign announcement must arrive after crafting registers its private chat")
	end)
	eq(w:Fire(member, "CHAT_MSG_ADDON_LOGGED", member.ns.PREFIX, "CJ~1~proof1~1~Supplies ready", "WHISPER", keeper.name), 1)
	eq(#member.errors, 0, table.concat(member.errors, "\n"))
	w:As(member, function()
		local r = member.ns.CraftRequests.Get("proof1")
		eq(#r.chat, 1); eq(r.chat[1].text, "Supplies ready"); eq(r.chat[1].sender, keeper.name)
		eq(member.ns.Campaign.State().purpose, "Raid supplies", "craft chat changes no campaign state")
	end)
	eq(registered.CJ, 1, "the original crafting chat namespace remains its own")
	assert(campaignType ~= "CJ", "campaign has an independent top-level namespace")
end)

test("Campaign: only the real King defines one voluntary purpose with fixed fourteen-day gold/material goals; no preview or second dues", function()
	local w, king, keeper, member, steward = Setup()
	for _, c in ipairs({ keeper, member, steward }) do w:As(c, function() eq(c.ns.Campaign.Start("Supplies | 100"), false) end) end
	w:As(king, function()
		local C = king.ns.Campaign
		for _, text in ipairs({ "", "No goal | 0", "Bad | word", "Bad | 1 | 1=0", "Too many | 1 | 1=1,2=2,3=3,4=4,5=5" }) do eq(C.Start(text), false, text) end
		king.ns.ViewAs.Previewing = function() return true end
		eq(C.Start("Preview | 100"), false)
		king.ns.ViewAs.Previewing = function() return false end
		eq(C.Start("Raid supplies | 100 | 1710=20"), true)
		local s = C.State(); eq(s.finish - s.start, 14 * 86400); eq(s.target, 1000000); eq(s.goals[1710], 20)
		eq(C.Start("Replacement | 1"), false)
	end)
	w:Run(1)
	w:As(member, function()
		eq(member.ns.Treasury.Visible(), true, "a King-announced public campaign opens the Treasury without sharing private books")
		local lines = member.ns.Treasury.Build()
		local meters = 0; for _, line in ipairs(lines) do if line.meter then meters = meters + 1; eq(line.onClick, nil) end end
		eq(meters, 2)
		local public = {}; member.ns.Campaign.Lines(public)
		for _, line in ipairs(public) do assert(not line.onClick, "public campaign progress has no payment or privileged action; normal Treasury navigation remains") end
	end)
end)

test("Campaign: confirmed receipts require explicit once-only allocation; old gifts, manual edits, dues notes, excluded deals and custody never enter the jar", function()
	local w, king, keeper = Setup()
	local old = Confirmed(w, keeper, "Old Giver", 1000000)
	Start(w, king)
	w:As(keeper, function()
		local C, T = keeper.ns.Campaign, keeper.ns.Treasury
		eq(C.Allocate(old), false, "nothing sweeps old gifts")
		local manual = T.Record("Manual Giver", 1000000, "mail", nil, { quiet = true })
		eq(C.Allocate(manual), false, "Record alone is not native confirmation")
	end)
	for _, options in ipairs({ { excluded = true }, { kind = "sale" }, { kind = "transfer" }, { kind = "arena" }, { kind = "craft" }, { kind = "fee" } }) do
		local e = Confirmed(w, keeper, "Rejected Giver", 1000000, options)
		w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), false) end)
	end
	local e = Confirmed(w, keeper, "Voluntary Giver", 2000000)
	eq(king.ns.Campaign.State().got, 0, "confirmed intake alone changes no public campaign total")
	w:As(keeper, function()
		local C = keeper.ns.Campaign
		eq(C.Allocate(e), true); eq(C.Allocate(e), false, "stable receipt id prevents a second allocation")
		assert(e.jarReceipt and e.jarCampaign)
	end)
	w:Run(2)
	local expected = 2000000 - keeper.ns.Dues.Amount()
	eq(king.ns.Campaign.State().got, expected, "baseline weekly amount stays out of voluntary gold")
	local saved = World.Copy(keeper.ns.rdb)
	w:As(keeper, function()
		keeper.ns.rdb = saved
		assert(loadfile(ROOT .. "Olympus/Campaign.lua"))("Olympus", keeper.ns)
		local line = keeper.ns.Treasury.Lines()[#keeper.ns.Treasury.Lines()]
		eq(keeper.ns.Campaign.Allocate(line), false, "reload cannot allocate the same receipt again")
		keeper.ns.Campaign.Report(true)
	end)
	w:Run(2); eq(king.ns.Campaign.State().got, expected, "a repeated aggregate replaces, never adds")
	local wire = w:ChannelText()
	for _, name in ipairs({ "Old Giver", "Manual Giver", "Rejected Giver", "Voluntary Giver" }) do assert(not wire:find(name, 1, true), "campaign publishes no contributor name: " .. name) end
end)

test("Campaign: native completed trade gold and material receipts count, never the offered trade; minimum and noted dues do not count", function()
	local w, king, keeper = Setup(); Start(w, king)
	local minimum = keeper.ns.Dues.Amount()
	local e = NativeTrade(w, keeper, "Minimum Giver", minimum)
	assert(e.jarReceipt, "a real native gold receipt is marked before voluntary allocation")
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), false, "a weekly baseline is not voluntary campaign funding") end)
	w:As(keeper, function() keeper.ns.Treasury.Record("Manual Baseline Giver", minimum * 10, "trade", nil, { quiet = true }) end)
	e = NativeTrade(w, keeper, "Manual Baseline Giver", minimum)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), false, "manual money cannot meet the native payer's reserved baseline") end)
	e = NativeTrade(w, keeper, "Manual Baseline Giver", 5000)
	w:As(keeper, function()
		eq(keeper.ns.Campaign.Allocate(e), true)
		local r = keeper.ns.rdb.campaignReceipts[keeper.name]
		eq(r.allocations[e.jarReceipt].money, 5000, "only the actual native excess is allocated")
	end)
	e = NativeTrade(w, keeper, "Direct Excess Giver", minimum + 5000)
	w:As(keeper, function()
		eq(keeper.ns.Campaign.Allocate(e), true)
		local r = keeper.ns.rdb.campaignReceipts[keeper.name]
		eq(r.allocations[e.jarReceipt].money, 5000, "a large first native trade never allocates its whole amount")
	end)
	e = NativeTrade(w, keeper, "Material Giver", 0, 1710, 20)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), true, "actual completed incoming material trade") end)
	w:Run(2); eq(king.ns.Campaign.State().counts[1710], 20)
	local noted = Confirmed(w, keeper, "Noted Giver", minimum * 2, { note = keeper.ns.Dues.Note() })
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(noted), false, "noted dues are excluded in full") end)
end)

test("Campaign: mail materials wait for actual bag arrival, and missing count APIs or failed mail cannot create campaign receipts", function()
	local w, king, keeper = Setup(); Start(w, king)
	local bags, empty, mode = 0, false, "confirmed"
	local g = keeper.globals
	g.GetInboxInvoiceInfo = function() end
	g.GetInboxHeaderInfo = function() return nil, nil, "Mail Giver", "Raid potions", 0, 0, nil, nil, nil, false, nil, true, false end
	g.GetInboxItem = function() if not empty then return "Potion", 1710, nil, 20 end end
	g.GetInboxItemLink = function() if not empty then return "item:1710" end end
	g.C_Item = { GetItemCount = function() if mode == "unavailable" then return nil end return bags end }
	g.GetItemCount = false
	w:As(keeper, function()
		local T, C = keeper.ns.Treasury, keeper.ns.Campaign
		T.MailItemTaking(1, 1); eq(#T.Lines(), 0, "taking an attachment is not receipt")
		bags = 10; T.ItemsChanged(); eq(#T.Lines(), 0, "a partial bag increase is insufficient")
		bags, empty = 20, true; T.ItemsChanged()
		local e = T.Lines()[1]; assert(e and e.jarReceipt); eq(C.Allocate(e), true)
		T.ItemsChanged(); eq(#T.Lines(), 1, "one pending attachment settles once")
		mode, empty = "unavailable", false
		T.MailItemTaking(2, 1)
		local unknown = T.Lines()[2]; assert(unknown); eq(C.Allocate(unknown), false, "legacy fallback is not a confirmed campaign receipt")
		mode, bags = "confirmed", 20
		T.MailItemTaking(3, 1); T.MailFailed(1710); bags = 40; T.ItemsChanged()
		eq(#T.Lines(), 2, "failed attachment is never counted later")
	end)
	w:Run(2); eq(king.ns.Campaign.State().counts[1710], 20)
end)

test("Campaign: missing native cash history fails closed while a confirmed material goal remains allocatable", function()
	local w, king, keeper = Setup(); Start(w, king)
	local e = NativeTrade(w, keeper, "Unknown History Giver", keeper.ns.Dues.Amount() + 5000)
	w:As(keeper, function()
		keeper.ns.Treasury.Book().jarNativeWeeks = nil
		eq(keeper.ns.Campaign.Allocate(e), false, "general book sums cannot substitute for missing native proof")
	end)
	e = NativeTrade(w, keeper, "Material Only Giver", 0, 1710, 20)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), true) end)
	w:Run(2); eq(king.ns.Campaign.State().got, 0); eq(king.ns.Campaign.State().counts[1710], 20)
end)

test("Campaign: a verified increase next reset reserves that week's new minimum; materials and other keepers' voluntary gifts stay unchanged", function()
	local w, king, keeper = Setup(); Start(w, king)
	w:As(king, function() king.ns.Dues.SetAmount("2"); eq(king.ns.Dues.Pending(), 20000) end)
	w:Run(2)
	w.clock = w:As(keeper, function() return keeper.ns.Dues.WeekStart(keeper.ns.Dues.Week() + 1) end) + 60
	w:As(keeper, function() eq(keeper.ns.Dues.Amount(), 20000, "actual King's amount becomes this week's amount") end)
	local e = NativeTrade(w, keeper, "Raised Minimum Giver", 20000)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), false, "the initial campaign baseline cannot turn the raised minimum into voluntary gold") end)
	e = NativeTrade(w, keeper, "Raised Excess Giver", 25000)
	w:As(keeper, function()
		eq(keeper.ns.Campaign.Allocate(e), true)
		eq(keeper.ns.rdb.campaignReceipts[keeper.name].allocations[e.jarReceipt].money, 5000)
	end)
	e = NativeTrade(w, keeper, "Raised Material Giver", 0, 1710, 20)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), true) end)
	e = NativeTrade(w, king, "Other Keeper Giver", 20000)
	w:As(king, function()
		eq(king.ns.Campaign.Allocate(e), true, "the King is a non-Treasurer keeper; this gift is not a second dues collection")
		eq(king.ns.rdb.campaignReceipts[king.name].allocations[e.jarReceipt].money, 20000)
	end)
	w:Run(2); eq(king.ns.Campaign.State().counts[1710], 20); eq(king.ns.Campaign.State().got, 25000)
end)

test("Campaign: an unverified or malformed current dues word cannot supply cash eligibility, without blocking confirmed materials", function()
	local w, king, keeper = Setup(); Start(w, king)
	local e = NativeTrade(w, keeper, "Unknown Amount Giver", 20000)
	w:As(keeper, function()
		local C = keeper.ns.Campaign
		keeper.ns.rdb.duesAmount = { copper = 10000, before = 10000, at = w.clock, from = "Forged King-Emberfall" }
		eq(C.Allocate(e), false, "a claimed policy issuer is not verified")
		keeper.ns.rdb.duesAmount.from = king.name; keeper.ns.rdb.duesAmount.before = 0
		eq(C.Allocate(e), false, "malformed history is not silently replaced by the default")
	end)
	e = NativeTrade(w, keeper, "Known Material Giver", 0, 1710, 20)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), true) end)
	w:Run(2); eq(king.ns.Campaign.State().got, 0); eq(king.ns.Campaign.State().counts[1710], 20)
end)

test("Campaign: the pinned mail keeper outside an Olympus guild can assign actual receipts locally; only his Treasurer relays that account's aggregate", function()
	local w, king, keeper = Setup()
	local mail = Client(w, "treasurerMail"); mail.guild = nil
	mail.ns.rdb = keeper.ns.rdb -- actual same-account realm store, as the existing mail book uses
	mail.ns.Comm.Whisper = function() return false end -- real Comm refuses a non-member's outgoing lane
	Start(w, king)
	local e = NativeTrade(w, mail, "Mail Account Giver", mail.ns.Dues.Amount() + 5000)
	w:As(mail, function()
		local rows = {}; mail.ns.Campaign.Lines(rows)
		local assign
		for _, row in ipairs(rows) do if row.text and row.text:find("Assign received", 1, true) then assign = row end end
		assert(assign and assign.onClick, "the pinned private mail keeper has the normal attribution action")
		eq(mail.ns.Campaign.Allocate(e), true)
	end)
	w:Run(1); eq(king.ns.Campaign.State().got, 0, "local attribution is not delivery")
	w:As(keeper, function() assert(keeper.ns.Campaign.Report(true)) end)
	w:Run(2); eq(king.ns.Campaign.State().got, 5000)
	for _, packet in ipairs(w:Sent({ type = "VG", dist = "WHISPER" })) do eq(packet.target, king.name) end
	assert(not w:ChannelText():find("Mail Account Giver", 1, true))
end)

test("Campaign: a new unallocated gift cannot grow an old assigned portion; trimmed receipt rows and bounded allocation ledgers keep confirmed totals", function()
	local w, king, keeper = Setup(); Start(w, king)
	local amount = keeper.ns.Dues.Amount()
	local e = Confirmed(w, keeper, "Partial Giver", amount + 5000)
	w:As(keeper, function() assert(keeper.ns.Campaign.Allocate(e)) end)
	w:Run(2); eq(king.ns.Campaign.State().got, 5000)
	Confirmed(w, keeper, "Partial Giver", 5000) -- deliberately not assigned
	w:As(keeper, function() keeper.ns.Campaign.Report(true) end)
	w:Run(2); eq(king.ns.Campaign.State().got, 5000, "later unassigned gold is not swept into the old receipt")
	w:As(keeper, function()
		local b = keeper.ns.Treasury.Book()
		for i = 1, keeper.ns.Treasury.MAX + 1 do keeper.ns.Treasury.Record("Other Giver", 1, "trade", nil, { quiet = true }) end
		eq(#b.lines, keeper.ns.Treasury.MAX)
		keeper.ns.Campaign.Report(true)
	end)
	w:Run(2); eq(king.ns.Campaign.State().got, 5000, "500-row book rotation keeps the confirmed assigned aggregate")
	local nextReceipt = Confirmed(w, keeper, "Boundary Giver", amount + 10000)
	w:As(keeper, function()
		local r = keeper.ns.rdb.campaignReceipts[keeper.name]
		-- Exactly the declared persistent allocation boundary, not a merely forged count.
		for id = 2, keeper.ns.Campaign.MAX_RECEIPTS + 1 do
			if id ~= nextReceipt.jarReceipt then r.allocations[id] = { item = 1710, count = 0, maximumCount = 1 } end
		end
		r.n, r.next = keeper.ns.Campaign.MAX_RECEIPTS, keeper.ns.Campaign.MAX_RECEIPTS + 1
		assert(keeper.ns.Campaign.Eligible(nextReceipt, keeper.ns.Treasury.Book()), "otherwise eligible; not rejected as an already assigned id")
		eq(keeper.ns.Campaign.Allocate(nextReceipt), false, "the persistent allocation bound sends nothing extra")
	end)
end)

test("Campaign: allocation corrections reduce aggregates; sender, actor, replay, range and queued authority checks remain bounded", function()
	local w, king, keeper, member = Setup(); Start(w, king)
	local e = Confirmed(w, keeper, "Correction Giver", 2000000)
	w:As(keeper, function() assert(keeper.ns.Campaign.Allocate(e)) end)
	w:Run(2)
	local before = king.ns.Campaign.State().got
	assert(before > 0)
	w:As(keeper, function() keeper.ns.Treasury.Toggle(e); keeper.ns.Campaign.Report(true) end)
	w:Run(2); eq(king.ns.Campaign.State().got, 0, "a no-longer-counted receipt rolls back once")
	local s = king.ns.Campaign.State()
	w:As(king, function()
		local C = king.ns.Campaign
		C.Handle("WHISPER", member.name, ("VG~R~%d~2000000000~%s~%s~999999~"):format(s.id, member.guild, member.name))
		eq(C.State().got, 0, "a non-keeper's claim is not a receipt")
		C.Handle("WHISPER", keeper.name, ("VG~R~%d~2000000000~%s~%s~999999~"):format(s.id, keeper.guild, member.name))
		eq(C.State().got, 0, "a keeper cannot impersonate another actor")
		C.Handle("CHANNEL", keeper.name, ("VG~R~%d~2000000000~%s~%s~999999~"):format(s.id, keeper.guild, keeper.name))
		eq(C.State().got, 0, "keeper aggregates are never accepted on the public lane")
		C.Handle("WHISPER", keeper.name, ("VG~R~%d~2000000000~%s~%s~-1~"):format(s.id, keeper.guild, keeper.name))
		eq(C.State().got, 0, "negative and malformed totals grant nothing")
	end)
	w:As(keeper, function()
		keeper.ns.Treasury.Toggle(e)
		assert(keeper.ns.Campaign.Report(true))
		keeper.ns.ViewAs.Previewing = function() return true end
	end)
	w:Run(2); eq(king.ns.Campaign.State().got, 0, "queued reports recheck real duties and preview state")
end)

test("Campaign: fourteen days stops intake; one manual King purchase note closes once, hides meters and survives reload/replay without reopening", function()
	local w, king, keeper, member = Setup(); Start(w, king)
	w.clock = king.ns.Campaign.State().finish
	local late = Confirmed(w, keeper, "Late Giver", 2000000)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(late), false) end)
	w:As(king, function()
		local C = king.ns.Campaign
		eq(C.Close(""), false); eq(C.Close("Bought twenty potions for the raid."), true); eq(C.Close("Repeated"), false)
		eq(#king.ns.rdb.acts, 1); eq(king.ns.rdb.acts[1].words, "Bought twenty potions for the raid.")
	end)
	w:Run(2)
	w:As(member, function()
		local C = member.ns.Campaign
		local s = C.State(); assert(s.closed)
		local rows = {}; C.Lines(rows); eq(#rows, 0, "the public campaign bar disappears")
		eq(#member.ns.rdb.acts, 1)
		local baselines = {}; for week, amount in pairs(s.baselines) do baselines[#baselines + 1] = week .. "=" .. amount end
		C.Handle("CHANNEL", king.name, ("VG~S~%d~%d~%d~%d~%d~0~1710=20~~0~Raid supplies~~%s"):format(s.id, s.rev + 1, s.start, s.finish, s.target, table.concat(baselines, ",")))
		eq(C.State(), s, "an ended id cannot be reopened")
		assert(loadfile(ROOT .. "Olympus/Campaign.lua"))("Olympus", member.ns)
		member.ns.Campaign.Handle("CHANNEL", king.name, w:Sent({ from = king, type = "VG" })[#w:Sent({ from = king, type = "VG" })].msg)
		eq(#member.ns.rdb.acts, 1, "closure repeats and reload keep one Chronicle entry")
	end)
end)

test("Campaign meter: actual row rendering clamps the reusable fill, keeps numeric labels and removes reused meters in mouse and gamepad UI", function()
	local function Draw()
		local content = CreateFrame("Frame", nil, UIParent); content:SetWidth(200)
		ns.Views.Render(content, { { text = "Gold received", right = "25 / 100", meter = { value = 25, total = 100 } } })
		local row = content.rows[1]
		eq(row.right:GetText(), "25 / 100")
		assert(row.meterBack:IsShown() and row.meterFill:IsShown())
		eq(row.meterFill:GetWidth(), row.meterBack:GetWidth() * 0.25)
		ns.Views.Render(content, { { text = "Full", right = "200 / 100", meter = { value = 200, total = 100 } } })
		eq(row.meterFill:GetWidth(), row.meterBack:GetWidth())
		ns.Views.Render(content, { { text = "Empty", right = "0 / 100", meter = { value = 0, total = 100 } } })
		eq(row.meterFill:IsShown(), false); eq(row.right:GetText(), "0 / 100")
		ns.Views.Render(content, { { text = "Ordinary row" } }); eq(row.meterBack:IsShown(), false); eq(row.meterFill:IsShown(), false)
	end
	H.WithUI(function() Draw(); H.WithGamepadUI(true, Draw) end)
end)

test("Campaign: excluded assigned materials remain excluded after their source receipt row rotates away", function()
	local w, king, keeper = Setup(); Start(w, king)
	local e = NativeTrade(w, keeper, "Material Giver", 0, 1710, 20)
	w:As(keeper, function() assert(keeper.ns.Campaign.Allocate(e)) end); w:Run(2)
	eq(king.ns.Campaign.State().counts[1710], 20)
	w:As(keeper, function() keeper.ns.Treasury.Toggle(e); keeper.ns.Campaign.Report(true) end); w:Run(2)
	eq(king.ns.Campaign.State().counts[1710], 0)
	w:As(keeper, function()
		for i = 1, keeper.ns.Treasury.MAX + 1 do keeper.ns.Treasury.Record("Other Giver", 1, "trade", nil, { quiet = true }) end
		keeper.ns.Campaign.Report(true)
	end); w:Run(2)
	eq(king.ns.Campaign.State().counts[1710], 0, "row eviction does not restore a previously excluded maximum")
end)

test("Campaign: excluded assigned cash cannot return after row rotation and a later unassigned native gift from the same donor", function()
	local w, king, keeper = Setup(); Start(w, king)
	local minimum = keeper.ns.Dues.Amount()
	local e = NativeTrade(w, keeper, "Repeat Cash Giver", minimum + 5000)
	w:As(keeper, function() assert(keeper.ns.Campaign.Allocate(e)) end); w:Run(2)
	eq(king.ns.Campaign.State().got, 5000)
	w:As(keeper, function() keeper.ns.Treasury.Toggle(e); keeper.ns.Campaign.Report(true) end); w:Run(2)
	eq(king.ns.Campaign.State().got, 0)
	w:As(keeper, function()
		for i = 1, keeper.ns.Treasury.MAX + 1 do keeper.ns.Treasury.Record("Other Giver", 1, "trade", nil, { quiet = true }) end
		keeper.ns.Campaign.Report(true)
	end); w:Run(2)
	eq(king.ns.Campaign.State().got, 0)
	w:As(keeper, function()
		for _, row in ipairs(keeper.ns.Treasury.Book().lines) do assert(row.jarReceipt ~= e.jarReceipt, "the excluded source row really rotated away") end
		keeper.ns.rdb = World.Copy(keeper.ns.rdb)
		assert(loadfile(ROOT .. "Olympus/Campaign.lua"))("Olympus", keeper.ns)
		eq(keeper.ns.rdb.campaignReceipts[keeper.name].allocations[e.jarReceipt].sourceValid, false, "exclusion remains persisted across reload")
	end)
	local later = NativeTrade(w, keeper, "Repeat Cash Giver", minimum + 5000)
	w:As(keeper, function()
		local r = keeper.ns.rdb.campaignReceipts[keeper.name]
		eq(r.allocations[later.jarReceipt], nil, "the later native gift was never manually assigned")
		keeper.ns.Campaign.Report(true)
	end); w:Run(2)
	eq(king.ns.Campaign.State().got, 0, "new native proof cannot revive an excluded attribution whose source row was evicted")
	eq(keeper.ns.rdb.campaignReceipts[keeper.name].allocations[e.jarReceipt].money, 0)
	w:As(keeper, function()
		keeper.ns.rdb.campaignReceipts[keeper.name].allocations[e.jarReceipt].sourceValid = nil -- pre-field saved allocation
		keeper.ns.Campaign.Report(true)
	end); w:Run(2)
	eq(king.ns.Campaign.State().got, 0, "an older absent zeroed source also fails closed instead of guessing permission")
end)

test("Campaign: a valid rotated cash attribution still rechecks the verified current minimum", function()
	local w, king, keeper = Setup(); Start(w, king)
	local minimum = keeper.ns.Dues.Amount()
	local e = NativeTrade(w, keeper, "Valid Rotated Giver", minimum + 5000)
	w:As(keeper, function()
		assert(keeper.ns.Campaign.Allocate(e))
		for i = 1, keeper.ns.Treasury.MAX + 1 do keeper.ns.Treasury.Record("Other Giver", 1, "trade", nil, { quiet = true }) end
		keeper.ns.rdb.campaignReceipts[keeper.name].allocations[e.jarReceipt].sourceValid = nil -- pre-field positive allocation
		keeper.ns.Campaign.Report(true)
	end); w:Run(2)
	eq(king.ns.Campaign.State().got, 5000, "a valid attributed receipt survives bounded row rotation")
	w:As(king, function()
		local s = king.ns.Campaign.State(); s.baselines[e.wk] = minimum + 5000; s.rev = s.rev + 1
		king.ns.Campaign.Publish(true)
	end); w:Run(2)
	w:As(keeper, function() keeper.ns.Campaign.Report(true) end); w:Run(2)
	eq(king.ns.Campaign.State().got, 0, "row rotation cannot freeze an obsolete weekly minimum")
	eq(keeper.ns.rdb.campaignReceipts[keeper.name].allocations[e.jarReceipt].sourceValid, true, "a zero amount caused by the minimum is not an excluded source")
	-- The attribution is still valid, merely reduced by the reserved baseline. A later native
	-- receipt can meet that baseline without increasing the earlier manually assigned maximum.
	NativeTrade(w, keeper, "Valid Rotated Giver", 5000)
	w:As(keeper, function() keeper.ns.Campaign.Report(true) end); w:Run(2)
	eq(king.ns.Campaign.State().got, 5000, "only a still-valid original attributed maximum is recalibrated")
end)

test("Campaign: missing or invalid native trade quantity preserves the legacy book fallback but authenticates no material", function()
	local w, king, keeper = Setup(); Start(w, king)
	for _, example in ipairs({ { label = "missing" }, { label = "zero", count = 0 }, { label = "negative", count = -1 },
		{ label = "fraction", count = 1.5 }, { label = "bad", count = "unknown" } }) do
		local e = NativeTrade(w, keeper, "Unknown Count " .. example.label, 0, 1710, example.count)
		assert(e and e.item == 1710); eq(e.count, 1, "existing non-campaign fallback remains unchanged")
		w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), false, "unknown native quantity: " .. example.label) end)
	end
end)

test("Campaign: missing native mail attachment quantity cannot authenticate an inferred material count", function()
	local w, king, keeper = Setup(); Start(w, king)
	local bags = 0; local g = keeper.globals
	g.GetInboxInvoiceInfo = function() end
	g.GetInboxHeaderInfo = function() return nil, nil, "Unknown Mail Count", "Potions", 0, 0, nil, nil, nil, false, nil, true, false end
	g.GetInboxItem = function() return "Potion", 1710, nil, nil end
	g.GetInboxItemLink = function() return "item:1710" end
	g.C_Item = { GetItemCount = function() return bags end }; g.GetItemCount = false
	w:As(keeper, function()
		keeper.ns.Treasury.MailItemTaking(1, 1); bags = 1; keeper.ns.Treasury.ItemsChanged()
		local e = keeper.ns.Treasury.Lines()[1]; assert(e); eq(e.count, 1, "legacy book fallback")
		eq(keeper.ns.Campaign.Allocate(e), false, "bag growth cannot verify a missing attachment quantity")
	end)
end)

test("Campaign: Treasurer revalidates only the permitted mail actor before relaying its aggregate", function()
	local w, king, keeper, member = Setup(); local mail = Client(w, "treasurerMail")
	mail.guild = nil; mail.ns.rdb = keeper.ns.rdb; mail.ns.Comm.Whisper = function() return false end
	Start(w, king)
	local minimum = mail.ns.Dues.Amount()
	local e = NativeTrade(w, mail, "Mail Account Giver", minimum + 5000)
	w:As(mail, function() assert(mail.ns.Campaign.Allocate(e)) end)
	w:As(keeper, function() keeper.ns.Campaign.Report(true) end); w:Run(2)
	eq(king.ns.Campaign.State().got, 5000)
	-- A valid newer public King policy raises the campaign's reserved baseline. Both sender
	-- roles still exist; this exercises reconciliation, not a fixture that disables the sender.
	w:As(king, function()
		local s = king.ns.Campaign.State(); s.baselines[e.wk] = minimum + 5000; s.rev = s.rev + 1
		king.ns.Campaign.Publish(true)
	end); w:Run(2)
	eq(keeper.ns.Campaign.State().baselines[e.wk], minimum + 5000)
	w:As(keeper, function() keeper.ns.Campaign.Report(true) end); w:Run(2)
	eq(king.ns.Campaign.State().got, 0, "relay updates the mail actor's revision after its eligibility changes")
	w:As(keeper, function()
		local private = { id = keeper.ns.Campaign.State().id, rev = 1, next = 1, n = 1, books = {},
			allocations = { [1] = { item = 1710, count = 20, maximumCount = 20 } } }
		keeper.ns.rdb.campaignReceipts[member.name] = private
		eq(keeper.ns.Campaign.Reconcile(member.name), false, "no arbitrary other-actor reconciliation")
		eq(private.allocations[1].count, 20)
	end)
end)

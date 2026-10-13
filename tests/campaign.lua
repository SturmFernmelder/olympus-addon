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
	e = NativeTrade(w, keeper, "Material Giver", 0, 1710, 20)
	w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(e), true, "actual completed incoming material trade") end)
	w:Run(2); eq(king.ns.Campaign.State().counts[1710], 20)
	local note = keeper.ns.Dues.Note and keeper.ns.Dues.Note()
	if note then
		local noted = Confirmed(w, keeper, "Noted Giver", minimum * 2, { note = note })
		w:As(keeper, function() eq(keeper.ns.Campaign.Allocate(noted), false, "noted dues are excluded in full") end)
	end
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
		r.n = keeper.ns.Campaign.MAX_RECEIPTS
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
		C.Handle("WHISPER", member.name, ("CJ~R~%d~2000000000~%s~%s~999999~"):format(s.id, member.guild, member.name))
		eq(C.State().got, 0, "a non-keeper's claim is not a receipt")
		C.Handle("WHISPER", keeper.name, ("CJ~R~%d~2000000000~%s~%s~999999~"):format(s.id, keeper.guild, member.name))
		eq(C.State().got, 0, "a keeper cannot impersonate another actor")
		C.Handle("CHANNEL", keeper.name, ("CJ~R~%d~2000000000~%s~%s~999999~"):format(s.id, keeper.guild, keeper.name))
		eq(C.State().got, 0, "keeper aggregates are never accepted on the public lane")
		C.Handle("WHISPER", keeper.name, ("CJ~R~%d~2000000000~%s~%s~-1~"):format(s.id, keeper.guild, keeper.name))
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
		C.Handle("CHANNEL", king.name, ("CJ~S~%d~%d~%d~%d~%d~0~1710=20~~0~Raid supplies~~%s"):format(s.id, s.rev + 1, s.start, s.finish, s.target, table.concat(baselines, ",")))
		eq(C.State(), s, "an ended id cannot be reopened")
		assert(loadfile(ROOT .. "Olympus/Campaign.lua"))("Olympus", member.ns)
		member.ns.Campaign.Handle("CHANNEL", king.name, w:Sent({ from = king, type = "CJ" })[#w:Sent({ from = king, type = "CJ" })].msg)
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

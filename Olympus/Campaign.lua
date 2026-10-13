local ADDON, ns = ...
local L = ns.L

-- Voluntary campaign jar (Fern F26-11). No money moves here. Only actual Treasury receipt
-- callbacks create eligible local lines; a real keeper assigns them by hand. Receipt identities
-- stay in that keeper's saved ledger. Only aggregates go to the King, and only the King publishes
-- them. The existing dues exclusion and donor-ranking/publication rules are not changed.
local Campaign = {}
ns.Campaign = Campaign
Campaign.DAYS = 14
Campaign.MAX_ITEMS = 4
Campaign.MAX_RECEIPTS = 2000
Campaign.SHOWN = 15
Campaign.EVERY = 300
local MAX = 2147483647
local lastReport, lastPublic = -math.huge, -math.huge

local function Number(v, max)
	local n = tonumber(v)
	return n and n == n and n >= 0 and n <= (max or MAX) and n == math.floor(n) and n or nil
end
local function Clean(s, max)
	s = tostring(s or ""):gsub("[|~%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, max or 80)
end
local function Preview()
	local V = ns.ViewAs
	return ns.King.Preview() or (V and V.Previewing and V.Previewing()) or ns.Treasury.DevView()
end
local function Off()
	local M, W = ns.Moderation, ns.WatchChat
	return (M and M.SelfOff and M.SelfOff()) or (W and not W.missing and W.Barred and W.Barred("powers"))
end
function Campaign.MaySet() return ns.King.IsKing() and ns.IsKingCharacter(ns.me) and not Preview() and not Off() end
function Campaign.MayAllocate() return ns.Treasury.RealKeeper() and not Preview() and not Off() end
function Campaign.State()
	local s = ns.rdb and ns.rdb.campaign
	if type(s) ~= "table" or not Number(s.id) or not Number(s.rev) or not Number(s.start) or not Number(s.finish)
		or s.finish - s.start ~= Campaign.DAYS * 86400 or type(s.purpose) ~= "string" or s.purpose == ""
		or not Number(s.target) or not Number(s.got) or type(s.goals) ~= "table" or type(s.counts) ~= "table" or type(s.baselines) ~= "table"
		or not ns.IsKingCharacter(s.by) or (s.closed and (type(s.note) ~= "string" or s.note == "")) then return nil end
	local n = 0
	for id, count in pairs(s.goals) do
		n = n + 1
		if n > Campaign.MAX_ITEMS or not Number(id, 10000000) or id == 0 or not Number(count, ns.Treasury.MAX_COUNT) or count == 0 then return nil end
	end
	for id, count in pairs(s.counts) do if not s.goals[id] or not Number(count, ns.Treasury.MAX_COUNT) then return nil end end
	for week = ns.Dues.WeekOf(s.start), ns.Dues.WeekOf(s.finish - 1) do
		if not Number(s.baselines[week], ns.Dues.MAX_AMOUNT) or s.baselines[week] == 0 then return nil end
	end
	return s
end
function Campaign.Open()
	local s = Campaign.State()
	return s and not s.closed and ns.Now() >= s.start and ns.Now() < s.finish and s or nil
end
local function Local(actor, create)
	if not ns.rdb then return nil end
	local all = ns.rdb.campaignReceipts
	if type(all) ~= "table" then if not create then return nil end all = {}; ns.rdb.campaignReceipts = all end
	local key = ns.FullName(actor or ns.me)
	local r, s = all[key], Campaign.State()
	if not s then return nil end
	if type(r) ~= "table" or r.id ~= s.id then
		if not create then return nil end
		r = { id = s.id, rev = 0, next = 0, allocations = {}, books = {}, n = 0 }; all[key] = r
	end
	if type(r.allocations) ~= "table" or type(r.books) ~= "table" or not Number(r.n, Campaign.MAX_RECEIPTS) or not Number(r.rev) or not Number(r.next) then return nil end
	local books = 0
	for name in pairs(r.books) do books = books + 1; if books > ns.Treasury.MAX_KEEPERS + 3 or type(name) ~= "string" then return nil end end
	local n = 0
	for id, a in pairs(r.allocations) do
		n = n + 1
		if n > Campaign.MAX_RECEIPTS or not Number(id) or type(a) ~= "table" or (a.item and not Number(a.count, ns.Treasury.MAX_COUNT))
			or (not a.item and not Number(a.money)) then return nil end
	end
	if n ~= r.n or r.next < r.n then return nil end
	return r
end
local function Items(text, goals, max)
	local out, n = {}, 0
	for part in tostring(text or ""):gmatch("[^,]+") do
		local id, count = part:match("^(%d+)=(%d+)$")
		id, count = Number(id, 10000000), Number(count, max or ns.Treasury.MAX_COUNT)
		if not id or id == 0 or not count or out[id] or (goals and not goals[id]) then return nil end
		n = n + 1; if n > Campaign.MAX_ITEMS then return nil end
		out[id] = count
	end
	if text ~= nil and text ~= "" and n == 0 then return nil end
	return out
end
local function ItemWord(t)
	local ids, out = {}, {}
	for id in pairs(t or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do out[#out + 1] = ("%d=%d"):format(id, t[id]) end
	return table.concat(out, ",")
end
local function Revision(r) r.rev = math.max(math.floor(ns.Now()), (tonumber(r.rev) or 0) + 1) end
local function Changed() ns.Fire("TREASURY_CHANGED") end

function Campaign.Start(input)
	if not Campaign.MaySet() then return false end
	local current = Campaign.State()
	if current and not current.closed then return false end -- close the previous purpose explicitly
	local purpose, gold, materials = tostring(input or ""):match("^%s*(.-)%s*|%s*([^|]+)%s*|?%s*([^|]*)$")
	purpose = Clean(purpose)
	local target = ns.Treasury.ParseGold(gold or "")
	local goals = Items(((materials or ""):gsub("%s", "")))
	if purpose == "" or not Number(target) or not goals then return false end
	local any = target > 0
	for _, n in pairs(goals) do if n == 0 then return false end any = true end
	if not any then return false end
	local now = math.floor(ns.Now())
	local s = { id = math.max(now, current and current.id + 1 or 0), rev = math.max(now, current and current.rev + 1 or 0), start = now,
		finish = now + Campaign.DAYS * 86400, purpose = purpose, target = target, got = 0, goals = goals, counts = {}, baselines = {}, by = ns.me }
	for week = ns.Dues.WeekOf(s.start), ns.Dues.WeekOf(s.finish - 1) do s.baselines[week] = ns.Dues.AmountOf(week) end
	ns.rdb.campaign, ns.rdb.campaignReports, ns.rdb.campaignReceipts = s, {}, {}
	Campaign.Publish(true); Changed()
	return true
end

-- Confirmed live intake only. Manual book edits, pre-existing gifts, fees, transfers, sales,
-- purchases, craft/arena custody and dues-noted mail never become candidates.
function Campaign.Received(e, b)
	if not Campaign.MayAllocate() or type(e) ~= "table" or type(b) ~= "table" or e.out or e.excluded or e.kind
		or (e.how ~= "mail" and e.how ~= "trade") then return false end
	local found = false
	for _, line in ipairs(b.lines or {}) do if line == e then found = true; break end end
	if not found then return false end
	-- Native sums are separate from the general book, which can contain manually entered or
	-- legacy money. Such money can never satisfy a campaign payer's reserved weekly baseline.
	if not e.item and not e.jarNative then
		local week, key, money = Number(e.wk), ns.Dues.Key(e.name), Number(e.money)
		if not week or not key or not money then return false end
		e.jarNative = { week = week, key = key, money = money, noted = e.noted or nil, included = true }
		b.jarNativeWeeks = type(b.jarNativeWeeks) == "table" and b.jarNativeWeeks or {}
		for old in pairs(b.jarNativeWeeks) do if type(old) ~= "number" or old < ns.Dues.Week() - 4 then b.jarNativeWeeks[old] = nil end end
		local per = b.jarNativeWeeks[week] or {}; b.jarNativeWeeks[week] = per
		local p = per[key] or { c = 0, d = 0 }; per[key] = p
		p.c = math.min(MAX, p.c + money); if e.noted then p.d = math.min(MAX, p.d + money) end
	end
	local s = Campaign.Open()
	if not s or e.jarReceipt or e.noted or e.t < s.start or e.t >= s.finish then return false end
	local r = Local(nil, true)
	if not r then return false end
	r.books[b.name] = true
	r.next = (tonumber(r.next) or 0) + 1
	e.jarReceipt, e.jarCampaign, e.jarActor = r.next, s.id, ns.FullName(ns.me)
	e.jarBook = b.name
	return true
end

-- A Treasurer book reserves everything that may be weekly dues, exactly as the established
-- public donor ranking does. Another keeper's genuine gifts are not a second dues collection.
local function Allowance(b, e)
	local D, s = ns.Dues, Campaign.State()
	local wk, key = tonumber(e.wk), D.Key(e.name)
	local p = wk and b.jarNativeWeeks and b.jarNativeWeeks[wk] and b.jarNativeWeeks[wk][key]
	if type(p) ~= "table" then return 0 end
	if not ns.Treasury.TreasurerPin(b.name) then return Number(p.c) or 0 end
	local baseline = s and s.baselines[wk]
	if not Number(baseline, D.MAX_AMOUNT) or baseline == 0 then return 0 end
	local word = ns.rdb and ns.rdb.duesAmount
	if word ~= nil and (type(word) ~= "table" or not Number(word.at) or not Number(word.copper, D.MAX_AMOUNT) or tonumber(word.copper) == 0
		or not Number(word.before, D.MAX_AMOUNT) or tonumber(word.before) == 0 or not (ns.IsKingCharacter(word.from) or ns.King.IsStewardName(word.from))) then return 0 end
	local current = D.AmountOf(wk)
	if not Number(current, D.MAX_AMOUNT) or current == 0 then return 0 end
	local amount = math.max(baseline, current, tonumber(p.d) or 0)
	return math.max(0, (tonumber(p.c) or 0) - amount)
end
local function Group(e) return tostring(e.jarBook) .. "|" .. tostring(e.wk) .. "|" .. tostring(ns.Dues.Key(e.name)) end
local function BookLines(actor)
	local out = {}
	local r = Local(actor)
	for name in pairs(r and r.books or {}) do
		local b = ns.Treasury.BookOf(name)
		if type(b) == "table" and b.epoch == ns.Treasury.EPOCH then
			for _, e in ipairs(b.lines or {}) do
				if e.jarActor == ns.FullName(actor or ns.me) then out[#out + 1] = { e = e, b = b } end
			end
		end
	end
	table.sort(out, function(a, b) return (a.e.jarReceipt or 0) < (b.e.jarReceipt or 0) end)
	return out
end
function Campaign.Eligible(e, b)
	local s, r = Campaign.Open(), Local()
	if not s or not r or e.jarCampaign ~= s.id or e.jarActor ~= ns.FullName(ns.me) or r.allocations[e.jarReceipt]
		or e.out or e.excluded or e.kind or e.noted then return nil end
	if e.item then return s.goals[e.item] and { item = e.item, count = Number(e.count, ns.Treasury.MAX_COUNT) } or nil end
	local left = Allowance(b, e)
	local group = Group(e)
	for _, a in pairs(r.allocations) do if a.group == group then left = left - (a.money or 0) end end
	local money = math.min(Number(e.money) or 0, math.max(0, left))
	return money > 0 and { money = money, group = group } or nil
end
function Campaign.Allocate(e)
	if not Campaign.MayAllocate() then return false end
	local found
	for _, x in ipairs(BookLines()) do if x.e == e then found = x; break end end
	if not found then return false end
	local a = Campaign.Eligible(e, found.b)
	local r = Local()
	if not a or not r or (a.item and (not a.count or a.count == 0)) then return false end
	if r.n >= Campaign.MAX_RECEIPTS then ns.Print(L.CAMPAIGN_FULL:format(Campaign.MAX_RECEIPTS)); return false end
	a.receipt, a.book = e.jarReceipt, e.jarBook
	a.maximum, a.maximumCount, a.week, a.donor = a.money, a.count, e.wk, ns.Dues.Key(e.name)
	r.allocations[e.jarReceipt], r.n = a, r.n + 1
	Revision(r); Campaign.Report(true); Changed()
	return true
end

-- Correct an assigned line if the Treasury later stops counting it. Removed old book rows do
-- not erase confirmed contributions (books themselves keep cumulative sums apart from 500 rows).
function Campaign.Reconcile()
	local r = Local()
	if not r then return false end
	local changed, used, present, ids = false, {}, {}, {}
	for _, x in ipairs(BookLines()) do if x.e.jarCampaign == r.id then present[x.e.jarReceipt] = x.e end end
	for name in pairs(r.books) do
		local b = ns.Treasury.BookOf(name)
		for _, e in ipairs(b and b.lines or {}) do
			local proof = e.jarNative
			if proof then
				local valid = not e.out and not e.excluded and not e.kind
				local p = b.jarNativeWeeks and b.jarNativeWeeks[proof.week] and b.jarNativeWeeks[proof.week][proof.key]
				if p and valid ~= proof.included then
					local delta = valid and proof.money or -proof.money
					p.c = math.max(0, p.c + delta); if proof.noted then p.d = math.max(0, p.d + delta) end
					proof.included = valid
				end
			end
		end
	end
	for id in pairs(r.allocations) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local a, e = r.allocations[id], present[id]
		local valid = not e or (not e.out and not e.excluded and not e.kind and not e.noted)
		if a.item then
			local count = valid and math.min(a.maximumCount or 0, e and (Number(e.count, ns.Treasury.MAX_COUNT) or 0) or (a.maximumCount or 0)) or 0
			if a.count ~= count then a.count, changed = count, true end
		else
			local b = ns.Treasury.BookOf(a.book)
			local allowed = b and Allowance(b, { name = a.donor, wk = a.week, money = a.maximum }) or 0
			local money = valid and math.min(a.maximum or 0, math.max(0, allowed - (used[a.group] or 0))) or 0
			used[a.group] = (used[a.group] or 0) + money
			if a.money ~= money then a.money, changed = money, true end
		end
	end
	if changed then Revision(r) end
	return changed
end
local function Totals(r)
	local money, counts = 0, {}
	for _, a in pairs(r and r.allocations or {}) do
		if a.item then counts[a.item] = math.min(ns.Treasury.MAX_COUNT, (counts[a.item] or 0) + (Number(a.count, ns.Treasury.MAX_COUNT) or 0))
		else money = math.min(MAX, money + (Number(a.money) or 0)) end
	end
	return money, counts
end
function Campaign.Report(force)
	if not Campaign.MayAllocate() or not Campaign.State() or Campaign.State().closed then return false end
	local now = ns.Now()
	if not force and now - lastReport < Campaign.EVERY then return false end
	lastReport = now
	Campaign.Reconcile()
	local any = false
	for actor in pairs(ns.rdb.campaignReceipts or {}) do
		local r = type(actor) == "string" and Local(actor)
		local mine = actor == ns.FullName(ns.me)
		local relay = type(actor) == "string" and ns.IsTreasurer(ns.me, GetGuildInfo("player")) and ns.IsTreasurerMail(actor)
		if (mine or relay) and r and r.id == Campaign.State().id and r.rev > 0 then
			local money, counts = Totals(r)
			local rev, id = r.rev, r.id
			local message = ("CJ~R~%d~%d~%s~%s~%d~%s"):format(id, rev, GetGuildInfo("player") or "", actor, money, ItemWord(counts))
			if Campaign.MaySet() and mine then Campaign.Handle("WHISPER", ns.me, message)
			else
				local king = ns.KingCharacter() and ns.FullName(ns.KingCharacter())
				if king then ns.Comm.Whisper(king, message, "campaign:" .. actor, false, false, nil,
					{ owner = Campaign, guard = function() return Campaign.MayAllocate() and Campaign.State() and Campaign.State().id == id and r.rev == rev end }) end
			end
			any = true
		end
	end
	return any
end
function Campaign.Publish(force)
	local s = Campaign.State()
	if not s or not Campaign.MaySet() then return false end
	local now = ns.Now()
	if not force and now - lastPublic < Campaign.EVERY then return false end
	lastPublic = now
	if not s.closed then
		for week, amount in pairs(s.baselines) do
			local current = ns.Dues.AmountOf(week)
			if current > amount then s.baselines[week] = current; Revision(s) end
		end
	end
	local rev = s.rev
	local message = ("CJ~S~%d~%d~%d~%d~%d~%d~%s~%s~%d~%s~%s~%s"):format(s.id, rev, s.start, s.finish, s.target, s.got,
		ItemWord(s.goals), ItemWord(s.counts), s.closed and 1 or 0, s.purpose, s.note or "", ItemWord(s.baselines))
	local options = { owner = Campaign, guard = function() return Campaign.MaySet() and Campaign.State() == s and s.rev == rev end }
	if #message <= 250 then ns.Comm.Send("CHANNEL", message, "campaign", nil, nil, nil, options)
	else ns.Comm.SendChunked(message, nil, "CHANNEL", nil, options) end
	return true
end
function Campaign.Close(note)
	local s = Campaign.State()
	note = Clean(note, 120)
	if not s or s.closed or not Campaign.MaySet() or note == "" then return false end
	s.closed, s.note = true, note; Revision(s)
	ns.Chronicle.Add("campaign", ns.me, L.CAMPAIGN_CLOSED:format(s.purpose), { id = "campaign:" .. s.id, words = note })
	Campaign.Publish(true); Changed()
	return true
end
local function Fields(message)
	local out = {}
	for field in (message .. "~"):gmatch("(.-)~") do out[#out + 1] = field; if #out > 14 then return nil end end
	return out
end
function Campaign.Handle(dist, sender, message)
	if type(message) ~= "string" or #message > 512 or not ns.IsMember() then return end
	local f = Fields(message)
	if not f or f[1] ~= "CJ" then return end
	if f[2] == "S" then
		if dist ~= "CHANNEL" or not ns.IsKingCharacter(sender) or #f ~= 14 then return end
		local id, rev, start, finish, target, got = Number(f[3]), Number(f[4]), Number(f[5]), Number(f[6]), Number(f[7]), Number(f[8])
		local goals = Items(f[9]); local counts = goals and Items(f[10], goals)
		local baselines = Items(f[14], nil, ns.Dues.MAX_AMOUNT)
		local purpose, note = Clean(f[12]), Clean(f[13], 120)
		if not id or id == 0 or not rev or not start or not finish or start > ns.Now() + 60 or finish - start ~= Campaign.DAYS * 86400
			or not target or not got or not goals or not counts or not baselines or purpose == "" or (f[11] ~= "0" and f[11] ~= "1") or (f[11] == "1" and note == "") then return end
		for week = ns.Dues.WeekOf(start), ns.Dues.WeekOf(finish - 1) do if not baselines[week] or baselines[week] == 0 then return end end
		local any = target > 0
		for _, n in pairs(goals) do if n == 0 then return end any = true end
		if not any then return end
		local old = Campaign.State()
		if old and (rev <= old.rev or id < old.id) then return end
		if old and old.id == id and old.closed then return end -- one immutable closing note
		if old and old.id == id and (old.start ~= start or old.finish ~= finish or old.purpose ~= purpose or old.target ~= target or ItemWord(old.goals) ~= ItemWord(goals)
			or (old.closed and f[11] ~= "1")) then return end
		local s = { id = id, rev = rev, start = start, finish = finish, target = target, got = got, goals = goals, counts = counts,
			purpose = purpose, closed = f[11] == "1" or nil, note = note, by = sender, baselines = baselines }
		ns.rdb.campaign = s
		if s.closed then ns.Chronicle.Add("campaign", sender, L.CAMPAIGN_CLOSED:format(purpose), { id = "campaign:" .. id, words = note }) end
		Changed()
	elseif f[2] == "R" then
		local s = Campaign.State()
		if dist ~= "WHISPER" or not Campaign.MaySet() or not s or s.closed or #f ~= 8 or Number(f[3]) ~= s.id then return end
		local rev, actor, money = Number(f[4]), ns.FullName(f[6]), Number(f[7])
		local counts = Items(f[8], s.goals)
		if not rev or not money or not counts or not ns.Treasury.IsKeeperName(sender, f[5]) then return end
		if actor ~= ns.FullName(sender) and not (ns.IsTreasurer(sender, f[5]) and ns.IsTreasurerMail(actor)) then return end
		local all = ns.rdb.campaignReports
		if type(all) ~= "table" then all = {}; ns.rdb.campaignReports = all end
		local key = ns.Dues.Key(actor) -- Forever names are unique across the connected realm group.
		if not key then return end
		local old = all[key]
		if old and rev <= old.rev then return end
		local n = 0; for _ in pairs(all) do n = n + 1 end
		if not old and n >= ns.Treasury.MAX_KEEPERS + 3 then return end
		all[key] = { rev = rev, got = money, counts = counts }
		s.got, s.counts = 0, {}
		for _, r in pairs(all) do
			s.got = math.min(MAX, s.got + r.got)
			for item, count in pairs(r.counts) do s.counts[item] = math.min(ns.Treasury.MAX_COUNT, (s.counts[item] or 0) + count) end
		end
		Revision(s); Campaign.Publish(true); Changed()
	end
end
ns.Comm.Handle("CJ", Campaign.Handle)

local function ItemName(id) return (GetItemInfo and GetItemInfo(id)) or ("Item " .. id) end
function Campaign.Lines(lines)
	if (not ns.IsMember() and not Campaign.MayAllocate()) or Preview() then return end
	local s = Campaign.State()
	if s and not s.closed then
		lines[#lines + 1] = { header = true, text = L.CAMPAIGN_TITLE, tooltip = function(tt) tt:AddLine(L.CAMPAIGN_TIP, 1, 1, 1, true) end }
		lines[#lines + 1] = { text = s.purpose, right = ns.Now() < s.finish and L.CAMPAIGN_UNTIL:format(date("%d/%m", s.finish)) or L.CAMPAIGN_ENDED }
		if s.target > 0 then lines[#lines + 1] = { text = L.CAMPAIGN_GOLD, right = ns.Treasury.Coins(s.got) .. " / " .. ns.Treasury.Coins(s.target), meter = { value = s.got, total = s.target } } end
		local ids = {}; for id in pairs(s.goals) do ids[#ids + 1] = id end; table.sort(ids)
		for _, id in ipairs(ids) do lines[#lines + 1] = { text = ItemName(id), right = (s.counts[id] or 0) .. " / " .. s.goals[id], meter = { value = s.counts[id] or 0, total = s.goals[id] } } end
		if Campaign.MaySet() then lines[#lines + 1] = { text = "> " .. L.CAMPAIGN_CLOSE, onClick = function() Campaign.PromptClose() end } end
		if Campaign.MayAllocate() and Campaign.Open() then
			local shown = 0
			for _, x in ipairs(BookLines()) do
				local e = x.e; local a = Campaign.Eligible(e, x.b)
				if a and shown < Campaign.SHOWN then
					shown = shown + 1
					local amount = a.item and (a.count .. "x " .. ItemName(a.item)) or ns.Treasury.Coins(a.money)
					lines[#lines + 1] = { indent = 1, text = L.CAMPAIGN_ASSIGN:format(amount), right = ns.DisplayName(e.name),
						onClick = function() ns.ShowDialog("OLYMPUS_CAMPAIGN_ASSIGN", L.CAMPAIGN_ASSIGN_PROMPT:format(amount, s.purpose), nil, e) end,
						tooltip = function(tt) tt:AddLine(L.CAMPAIGN_ASSIGN_TIP, 1, 1, 1, true) end }
				end
			end
		end
		lines[#lines].gapAfter = true
	elseif Campaign.MaySet() then lines[#lines + 1] = { text = "+ " .. L.CAMPAIGN_NEW, onClick = function() Campaign.PromptStart() end, gapAfter = true } end
end
local function EditShow(self) local eb = self.editBox or self.EditBox; if eb then eb:SetText(""); eb:SetFocus() end end
StaticPopupDialogs["OLYMPUS_CAMPAIGN_START"] = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, OnShow = EditShow,
	OnAccept = function(self) local eb = self.editBox or self.EditBox; if not Campaign.Start(eb and eb:GetText()) then ns.Print(L.CAMPAIGN_USAGE) end end,
	EditBoxOnEnterPressed = function(self) if not Campaign.Start(self:GetText()) then ns.Print(L.CAMPAIGN_USAGE) end self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
StaticPopupDialogs["OLYMPUS_CAMPAIGN_CLOSE"] = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, OnShow = EditShow,
	OnAccept = function(self) local eb = self.editBox or self.EditBox; Campaign.Close(eb and eb:GetText()) end,
	EditBoxOnEnterPressed = function(self) Campaign.Close(self:GetText()); self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
StaticPopupDialogs["OLYMPUS_CAMPAIGN_ASSIGN"] = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
	OnAccept = function(self, data) Campaign.Allocate(data or self.data) end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
function Campaign.PromptStart() if Campaign.MaySet() then ns.ShowDialog("OLYMPUS_CAMPAIGN_START", L.CAMPAIGN_USAGE) end end
function Campaign.PromptClose() if Campaign.MaySet() then ns.ShowDialog("OLYMPUS_CAMPAIGN_CLOSE", L.CAMPAIGN_CLOSE_PROMPT) end end
ns.On("TREASURY_RECEIPT", Campaign.Received)
ns.On("TREASURY_CHANGED", function() if Campaign.Reconcile() then Campaign.Report(true) end end)
ns.On("LOGIN", function() ns.Every(60, "campaign jar", function() Campaign.Report(); Campaign.Publish() end) end)

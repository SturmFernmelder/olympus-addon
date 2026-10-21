local ADDON, ns = ...
local L = ns.L

-- Completed crafting requests become durable two-party records.  A recipe list by itself earns
-- nothing: the requester and the crafter each sign the same delivered request, then Records.lua
-- retains and relays the combined proof even after both original players log out.
local Craft = {}
ns.CraftRanking = Craft

Craft.TYPE = "c"
Craft.PAIR_DAY_MAX = 3
Craft.DAY_MAX = 24
Craft.HALF_GAP = 60 * 60
Craft.RETAIN = 90 * 86400
Craft.RARITY_BONUS = { [0] = 0, [1] = 6, [2] = 15, [3] = 30, [4] = 60 }
-- Curated recipe-output exceptions can be added without changing old signed records.  A record
-- freezes the tier both parties observed; the lower tier wins if their clients disagree.
Craft.RARITY = {}

local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt
local function Now() return ns.Now() end
local function Full(name) return type(name) == "string" and name ~= "" and ns.FullName(ns.Normal(name)) or nil end
local function Low(name) local n = Full(name) return n and n:lower() or nil end
local function Same(a, b) return Low(a) ~= nil and Low(a) == Low(b) end
local function Number(v, lo, hi)
	v = tonumber(v)
	if not v or v ~= floor(v) or v < lo or v > hi then return nil end
	return v
end
local function Split(text)
	local out = {}
	for s in (tostring(text or "") .. "~"):gmatch("(.-)~") do out[#out + 1] = s end
	return out
end
local function B64(raw)
	local E = ns.Ed25519
	return type(raw) == "string" and E and E.ToB64 and E.ToB64(raw) or nil
end
local function Raw(text, n)
	local E = ns.Ed25519
	local ok, value = pcall(function() return E and E.FromB64 and E.FromB64(text or "") end)
	return ok and type(value) == "string" and #value == n and value or nil
end

function Craft.Score(quantity, tier)
	quantity, tier = Number(quantity, 1, 1000), Number(tier, 0, 4)
	if not quantity or not tier then return nil end
	-- Quantity helps, but sub-linearly: a crate of cheap consumables is useful without letting one
	-- bulk order erase many separate deliveries.  A truly rare output is worth about seven simple
	-- single-item deliveries, not an unbeatable amount.
	local quantityBonus = min(30, floor(sqrt(max(0, quantity - 1)) * 3))
	return 10 + quantityBonus + (Craft.RARITY_BONUS[tier] or 0)
end

local function ItemTier(itemID)
	local override = Craft.RARITY[tonumber(itemID)]
	if override then return min(4, max(0, floor(override))) end
	local quality
	if type(GetItemInfo) == "function" then
		local ok, _, _, q = pcall(GetItemInfo, itemID)
		if ok and type(q) == "number" then quality = q end
	end
	if quality == nil and type(C_Item) == "table" and type(C_Item.GetItemInfo) == "function" then
		local ok, info = pcall(C_Item.GetItemInfo, itemID)
		if ok and type(info) == "table" then quality = info.quality end
	end
	-- WoW qualities: poor/common earn no rarity bonus; uncommon through legendary map to 1..4.
	return min(4, max(0, floor(tonumber(quality) or 1) - 1))
end
Craft.ItemTier = ItemTier

local function Core(r, role, itemID, quantity, tier, day)
	return table.concat({ r.id, Full(r.requester), Full(r.crafter), itemID, quantity, tier, day, role }, "~")
end

local function OwnHalf(r)
	if type(r) ~= "table" or r.state ~= "completed" or r.kind ~= "c" or not Same(ns.me, r.requester) and not Same(ns.me, r.crafter) then return nil end
	local itemID, quantity = Number(r.itemID, 1, 999999999), Number(r.delivery and r.delivery.quantity or r.quantity, 1, 1000)
	if not itemID or not quantity then return nil end
	local D, E = ns.Debts, ns.Ed25519
	if not (D and D.MyKey and D.Sign and E and E.ToB64) then return nil end
	local ok, _, pk = pcall(D.MyKey)
	if not ok or type(pk) ~= "string" or #pk ~= 32 then return nil end
	local role = Same(ns.me, r.requester) and "r" or "c"
	local day = floor((tonumber(r.completedAt) or tonumber(r.updated) or Now()) / 86400)
	local tier = ItemTier(itemID)
	local core = Core(r, role, itemID, quantity, tier, day)
	local signed, sig = pcall(D.Sign, "OLYC1|" .. core)
	if not signed or type(sig) ~= "string" or #sig ~= 64 then return nil end
	return { role = role, itemID = itemID, quantity = quantity, tier = tier, day = day,
		pk64 = B64(pk), sig64 = B64(sig), core = core }
end

local function HalfText(h)
	return table.concat({ h.core, h.pk64, h.sig64 }, "~")
end
local function ParseHalf(text)
	local f = Split(text)
	if #f ~= 10 then return nil end
	local id, requester, crafter = f[1], Full(f[2]), Full(f[3])
	local itemID, quantity, tier, day, role = Number(f[4], 1, 999999999), Number(f[5], 1, 1000), Number(f[6], 0, 4), Number(f[7], 1, 999999), f[8]
	local pk, sig = Raw(f[9], 32), Raw(f[10], 64)
	if not id or #id < 3 or #id > 24 or not id:find("^[0-9a-z]+$") or not requester or not crafter or Same(requester, crafter)
		or not itemID or not quantity or not tier or not day or (role ~= "r" and role ~= "c") or not pk or not sig then return nil end
	local signer = role == "r" and requester or crafter
	return { id = id, requester = requester, crafter = crafter, itemID = itemID, quantity = quantity,
		tier = tier, day = day, role = role, signer = signer, pk64 = f[9], sig64 = f[10], pk = pk, sig = sig,
		core = table.concat({ id, requester, crafter, itemID, quantity, tier, day, role }, "~") }
end

function Craft.ReadRecord(body)
	local left, right = tostring(body or ""):match("^([^^]+)%^([^^]+)$")
	local a, b = left and ParseHalf(left), right and ParseHalf(right)
	if not a or not b or a.role == b.role then return nil, "half" end
	local r, c = a.role == "r" and a or b, a.role == "c" and a or b
	if r.id ~= c.id or not Same(r.requester, c.requester) or not Same(r.crafter, c.crafter)
		or r.itemID ~= c.itemID or r.quantity ~= c.quantity or math.abs(r.day - c.day) > 1 then return nil, "result" end
	local tier, day = min(r.tier, c.tier), max(r.day, c.day)
	local points = Craft.Score(r.quantity, tier)
	local id = "c" .. r.id .. ":" .. Low(r.requester) .. ":" .. Low(r.crafter)
	return { id = id, t = day * 86400 + 43200,
		content = table.concat({ r.itemID, r.quantity, tier, points, day }, "|"),
		request = r.id, requester = r.requester, crafter = r.crafter, itemID = r.itemID,
		quantity = r.quantity, tier = tier, points = points, day = day,
		parts = {
			{ name = r.signer, pk64 = r.pk64, sig64 = r.sig64, pk = r.pk, sig = r.sig, msg = "OLYC1|" .. r.core },
			{ name = c.signer, pk64 = c.pk64, sig64 = c.sig64, pk = c.pk, sig = c.sig, msg = "OLYC1|" .. c.core },
		} }
end

local function RecordBody(rank)
	local a, b = rank and rank.halves and rank.halves.r, rank and rank.halves and rank.halves.c
	return a and b and (HalfText(a) .. "^" .. HalfText(b)) or nil
end

local function KeepHalf(r, half)
	r.craftRank = type(r.craftRank) == "table" and r.craftRank or { halves = {} }
	r.craftRank.halves = type(r.craftRank.halves) == "table" and r.craftRank.halves or {}
	local old = r.craftRank.halves[half.role]
	if old and HalfText(old) ~= HalfText(half) then return false, "conflict" end
	r.craftRank.halves[half.role] = half
	local R = ns.Records
	if R and R.Pin then R.Pin(half.signer or (half.role == "r" and r.requester or r.crafter), half.pk64) end
	local body = RecordBody(r.craftRank)
	if body and R and R.Take then R.Take(Craft.TYPE, body, ns.me, "self") end
	return true
end

local function SendHalf(r, force)
	if not r or r.state ~= "completed" or r.kind ~= "c" then return false, "state" end
	r.craftRank = type(r.craftRank) == "table" and r.craftRank or { halves = {} }
	r.craftRank.halves = type(r.craftRank.halves) == "table" and r.craftRank.halves or {}
	local role = Same(ns.me, r.requester) and "r" or (Same(ns.me, r.crafter) and "c" or nil)
	if not role then return false, "party" end
	local half = r.craftRank.halves[role] or OwnHalf(r)
	if not half then return false, "sign" end
	half.signer = ns.me
	KeepHalf(r, half)
	if r.craftRank.halves[role == "r" and "c" or "r"] then return true, "complete" end
	if not force and Now() - (tonumber(r.craftRank.sentAt) or -math.huge) < Craft.HALF_GAP then return false, "fresh" end
	local Q = ns.CraftRequests
	local ok, why = Q and Q.SendRankHalf and Q.SendRankHalf(r.id, half.role, half.itemID, half.quantity, half.tier, half.day, half.pk64, half.sig64)
	if ok then r.craftRank.sentAt = Now() end
	return ok, why
end
Craft.SendHalf = SendHalf

-- `f` is CraftRequests' CR split: role, item, quantity, tier, day, key, signature at 6..12.
function Craft.ReceiveHalf(r, sender, f)
	if type(r) ~= "table" or r.state ~= "completed" or r.kind ~= "c" then return false, "state" end
	local role = f[6]
	if (role == "r" and not Same(sender, r.requester)) or (role == "c" and not Same(sender, r.crafter)) then return false, "role" end
	local itemID, quantity, tier, day = Number(f[7], 1, 999999999), Number(f[8], 1, 1000), Number(f[9], 0, 4), Number(f[10], 1, 999999)
	local pk, sig = Raw(f[11], 32), Raw(f[12], 64)
	if not itemID or not quantity or not tier or not day or not pk or not sig
		or itemID ~= tonumber(r.itemID) or quantity ~= tonumber(r.delivery and r.delivery.quantity or r.quantity) then return false, "shape" end
	local half = { role = role, itemID = itemID, quantity = quantity, tier = tier, day = day,
		pk64 = f[11], sig64 = f[12], pk = pk, sig = sig, signer = sender }
	half.core = Core(r, role, itemID, quantity, tier, day)
	local kept, why = KeepHalf(r, half)
	if not kept then return false, why end
	-- A player who first learns the other half answers with his own.  The next Records digest then
	-- makes the combined proof available to every client, not just these two.
	SendHalf(r, true)
	return true
end

function Craft.Totals(month)
	local R = ns.Records
	if not (R and R.Bodies and R.MonthStart) then return {} end
	local first, last = floor(R.MonthStart(month) / 86400), floor(R.MonthStart(month + 1) / 86400) - 1
	local records = {}
	for _, body in ipairs(R.Bodies(Craft.TYPE, first, last)) do
		local rec = Craft.ReadRecord(body)
		if rec then records[#records + 1] = rec end
	end
	table.sort(records, function(a, b) if a.day ~= b.day then return a.day < b.day end return a.id < b.id end)
	local rows, by, pairs, days = {}, {}, {}, {}
	for _, rec in ipairs(records) do
		local pair = Low(rec.requester) .. "|" .. Low(rec.crafter) .. "|" .. rec.day
		local craftDay = Low(rec.crafter) .. "|" .. rec.day
		pairs[pair] = (pairs[pair] or 0) + 1
		days[craftDay] = (days[craftDay] or 0) + 1
		if pairs[pair] <= Craft.PAIR_DAY_MAX and days[craftDay] <= Craft.DAY_MAX then
			local key = Low(rec.crafter)
			local row = by[key]
			if not row then row = { name = rec.crafter, points = 0, deliveries = 0, customers = 0, _customers = {} }; by[key] = row; rows[#rows + 1] = row end
			row.points, row.deliveries = row.points + rec.points, row.deliveries + 1
			local customer = Low(rec.requester)
			if not row._customers[customer] then row._customers[customer] = true; row.customers = row.customers + 1 end
		end
	end
	for _, row in ipairs(rows) do row._customers = nil end
	table.sort(rows, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.customers ~= b.customers then return a.customers > b.customers end
		if a.deliveries ~= b.deliveries then return a.deliveries > b.deliveries end
		return a.name:lower() < b.name:lower()
	end)
	for i, row in ipairs(rows) do row.place = i end
	return rows
end

function Craft.RowsText(rows)
	local list, seen = {}, {}
	for _, row in ipairs(type(rows) == "table" and rows or {}) do
		local name = type(row) == "table" and Full(row.name) or nil
		local p, d, c = row and Number(row.points, 0, 2147483647), row and Number(row.deliveries, 0, 2147483647), row and Number(row.customers, 0, 2147483647)
		if name and not name:find("[,;~|]") and p and d and c and not seen[name:lower()] then
			seen[name:lower()] = true
			list[#list + 1] = { key = name:lower(), text = ("%s,%d,%d,%d"):format(name, p, d, c) }
		end
	end
	table.sort(list, function(a, b) return a.key < b.key end)
	local out = {}
	for _, item in ipairs(list) do out[#out + 1] = item.text end
	return table.concat(out, ";"), #out
end
function Craft.ReadRows(text)
	local out = {}
	for part in (tostring(text or "") .. ";"):gmatch("([^;]*);") do
		local name, p, d, c = part:match("^([^,]+),(%d+),(%d+),(%d+)$")
		if name then out[#out + 1] = { name = name, points = tonumber(p), deliveries = tonumber(d), customers = tonumber(c) } end
	end
	return out
end

function Craft.Current(month)
	month = tonumber(month) or (ns.Records and ns.Records.MonthOf and ns.Records.MonthOf(Now()))
	if not month then return {} end
	local sealed = ns.Records and ns.Records.Sealed and ns.Records.Sealed(Craft.TYPE, month)
	local rows = sealed or Craft.Totals(month)
	table.sort(rows, function(a, b)
		if a.points ~= b.points then return a.points > b.points end
		if a.customers ~= b.customers then return a.customers > b.customers end
		if a.deliveries ~= b.deliveries then return a.deliveries > b.deliveries end
		return a.name:lower() < b.name:lower()
	end)
	for i, row in ipairs(rows) do row.place = i end
	return rows
end

function Craft.Lines(lines)
	lines[#lines + 1] = { header = true, text = L.CRAFT_RANK_TITLE, right = L.CRAFT_RANK_GLOBAL }
	if ns.RankingRules and ns.RankingRules.Link then
		local link = ns.RankingRules.Link("craft-deliveries", function()
			if ns.RankingRules.OpenRealm then ns.RankingRules.OpenRealm("craft-deliveries") end
		end)
		if link then lines[#lines + 1] = link end
	end
	lines[#lines + 1] = { text = L.CRAFT_RANK_ABOUT, wrap = true }
	local rows = Craft.Current()
	if not rows[1] then lines[#lines + 1] = { text = "|cff9d9d9d" .. L.CRAFT_RANK_EMPTY .. "|r" } return end
	for _, row in ipairs(rows) do
		lines[#lines + 1] = { indent = 1, player = row.name, text = ("%d. %s"):format(row.place, ns.DisplayName(row.name)),
			right = L.CRAFT_RANK_POINTS:format(row.points),
			tooltip = function(tt) tt:AddLine(row.name, 1, 0.82, 0); tt:AddLine(L.CRAFT_RANK_DETAIL:format(row.deliveries, row.customers), 1, 1, 1, true) end }
	end
end

if ns.RankingRules then
	ns.RankingRules.Register("craft-deliveries", {
		title = L.RANK_RULE_CRAFT_TITLE,
		icon = "Interface\\Icons\\Trade_BlackSmithing",
		sections = function()
			return {
				{ topic = "score", text = L.RANK_RULE_CRAFT_SCORE },
				{ topic = "limits", text = L.RANK_RULE_CRAFT_LIMITS:format(Craft.PAIR_DAY_MAX, Craft.DAY_MAX) },
				{ topic = "order", text = L.RANK_RULE_CRAFT_ORDER },
				{ topic = "evidence", text = L.RANK_RULE_CRAFT_EVIDENCE },
				{ topic = "visibility", text = L.RANK_RULE_CRAFT_VISIBILITY },
			}
		end,
	})
end

-- A completed delivery of this player's whose other half has not come yet: the only work the
-- resend has. (Retained RETAIN after its completion, as Tick's own window.)
local function Waiting(r)
	if type(r) ~= "table" or r.state ~= "completed" or r.kind ~= "c" or Now() - (tonumber(r.completedAt) or Now()) > Craft.RETAIN then return false end
	local role = Same(ns.me, r.requester) and "r" or (Same(ns.me, r.crafter) and "c" or nil)
	if not role then return false end
	local halves = type(r.craftRank) == "table" and type(r.craftRank.halves) == "table" and r.craftRank.halves or {}
	return not halves[role == "r" and "c" or "r"]
end
function Craft.Due()
	local Q = ns.CraftRequests
	for _, r in ipairs(Q and Q.All and Q.All() or {}) do if Waiting(r) then return true end end
	return false
end

local ticker
function Craft.Tick(force)
	local Q = ns.CraftRequests
	for _, r in ipairs(Q and Q.All and Q.All() or {}) do
		if r.state == "completed" and r.kind == "c" and Now() - (tonumber(r.completedAt) or Now()) <= Craft.RETAIN then SendHalf(r, force) end
	end
	-- Both halves everywhere: nothing left to resend, the timer stops (the weight rule).
	if ticker and not Craft.Due() then
		if ticker.Cancel then ticker.Cancel() end
		ticker = nil
	end
end
-- The weight rule (the design: an idle client runs no arena-family timer): the hourly resend of an
-- own half runs only while a delivery of this player's waits for the other party's half.
local function EnsureTicker()
	if ticker or not Craft.Due() then return end
	ticker = ns.Every(600, "craft ranking", Craft.Tick)
end

if ns.Records and ns.Records.Register then
	ns.Records.Register(Craft.TYPE, {
		Read = Craft.ReadRecord, DAY_MAX = Craft.DAY_MAX, Totals = Craft.Totals,
		RowsText = Craft.RowsText, ReadRows = Craft.ReadRows,
		Mine = function()
			local out, Q = {}, ns.CraftRequests
			for _, r in ipairs(Q and Q.All and Q.All() or {}) do
				local body = RecordBody(r.craftRank)
				if body then out[#out + 1] = body end
			end
			return out
		end,
		Pins = function()
			local out, Q = {}, ns.CraftRequests
			for _, r in ipairs(Q and Q.All and Q.All() or {}) do
				for role, half in pairs(type(r.craftRank) == "table" and type(r.craftRank.halves) == "table" and r.craftRank.halves or {}) do
					local who = role == "r" and r.requester or r.crafter
					if who and half.pk64 then out[who] = half.pk64 end
				end
			end
			return out
		end,
		Has = function()
			local Q = ns.CraftRequests
			for _, r in ipairs(Q and Q.All and Q.All() or {}) do if type(r.craftRank) == "table" then return true end end
			return false
		end,
	})
end

ns.On("CRAFT_REQUEST_COMPLETED", function(r) SendHalf(r, true) EnsureTicker() end)
ns.On("LOGIN", function()
	ticker = nil -- (a timer of the session before is gone with it)
	if not Craft.Due() then return end
	ns.After(15, "craft ranking", function() Craft.Tick(true) end)
	EnsureTicker()
end)

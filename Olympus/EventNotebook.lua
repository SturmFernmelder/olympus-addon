local ADDON, ns = ...
local L = ns.L

-- Fern F26-15: a small organizer-owned event notebook. It is deliberately not a
-- loot window, a wager, or a purse. The public word contains the bracket alone;
-- every copper figure stays local or crosses in Treasury's bounded private
-- whisper lane to the King, Steward, or pinned Treasurer.
local Notebook = {}
ns.EventNotebook = Notebook

Notebook.MAX_BOOKS = 20
Notebook.MAX_PARTICIPANTS = 64
Notebook.MAX_RESULTS = 127
Notebook.ROOM = 6000
Notebook.REPEAT = 300

local opened, pending = {}, {}
local lastRepeat = -math.huge
local MAX_COPPER = 2147483647

local function Gold(s) return "|cffffd200" .. tostring(s or "") .. "|r" end
local function Grey(s) return "|cff888888" .. tostring(s or "") .. "|r" end
local function Green(s) return "|cff33ff99" .. tostring(s or "") .. "|r" end
local function Red(s) return "|cffff5555" .. tostring(s or "") .. "|r" end
local function Same(a, b)
	return type(a) == "string" and type(b) == "string" and ns.FullName(ns.Normal(a)):lower() == ns.FullName(ns.Normal(b)):lower()
end
local function Clean(s, n)
	s = tostring(s or ""):gsub("[~|%^/,%c]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
	return ns.Cut(s, n or 80)
end
local function Whole(v, max)
	local n = tonumber(v)
	return n and n == n and n >= 0 and n <= (max or MAX_COPPER) and n == math.floor(n) and n or nil
end
local function Name(v)
	v = Clean(v, 80)
	return v ~= "" and ns.FullName(ns.Normal(v)) or nil
end
local function Display(v) return ns.DisplayName(v) or tostring(v or "?") end
local function Coins(v) return ns.Treasury.Coins(tonumber(v) or 0) end
local function Refresh()
	ns.Fire("BOARD_CHANGED")
	if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end
local function Revision(book)
	book.rev = math.max(math.floor(ns.Now()), (tonumber(book.rev) or 0) + 1)
	book.updated = ns.Now()
end

local function Root(create)
	if not ns.rdb then return nil end
	local root = ns.rdb.eventNotebooks
	if type(root) ~= "table" then
		if not create then return nil end
		root = { version = 1, actors = {}, public = {}, private = {}, receipts = {} }
		ns.rdb.eventNotebooks = root
	end
	root.actors = type(root.actors) == "table" and root.actors or {}
	root.public = type(root.public) == "table" and root.public or {}
	root.private = type(root.private) == "table" and root.private or {}
	root.receipts = type(root.receipts) == "table" and root.receipts or {}
	return root
end
local function Event(id) return ns.Week and ns.Week.Entry and ns.Week.Entry(tonumber(id) or id) or nil end
local function Owns(e)
	return type(e) == "table" and e.mine == true and Same(e.by, ns.me)
end
local function MayCreate(e)
	return Owns(e) and ns.Week and ns.Week.MayEdit and ns.Week.MayEdit(e) == true
end
local function Actor(create)
	local root = Root(create)
	if not root or not ns.me then return nil end
	local key = ns.FullName(ns.me):lower()
	local actor = root.actors[key]
	if type(actor) ~= "table" then
		if not create then return nil end
		actor = { books = {} }; root.actors[key] = actor
	end
	actor.books = type(actor.books) == "table" and actor.books or {}
	return actor
end
local function Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end return n end

function Notebook.Book(id, create)
	local e = Event(id)
	if not Owns(e) then return nil end
	local actor = Actor(create)
	if not actor then return nil end
	local key = tostring(e.id)
	local book = actor.books[key]
	if type(book) ~= "table" then
		if not create or not MayCreate(e) or Count(actor.books) >= Notebook.MAX_BOOKS then return nil end
		book = { version = 1, id = e.id, by = ns.FullName(ns.me), title = Clean(e.title, 100), created = ns.Now(), rev = 1,
			pot = 0, cut = 0, participants = {}, results = {}, podium = {}, prizes = {}, entries = {},
			paid = { prizes = {} } }
		actor.books[key] = book
	end
	if book.version ~= 1 or tostring(book.id) ~= key or not Same(book.by, ns.me) then return nil end
	for _, field in ipairs({ "participants", "results", "podium", "prizes", "entries" }) do
		if type(book[field]) ~= "table" then return nil end
	end
	book.paid = type(book.paid) == "table" and book.paid or { prizes = {} }
	book.paid.prizes = type(book.paid.prizes) == "table" and book.paid.prizes or {}
	book.title = Clean(e.title, 100)
	return book
end

local function Has(book, name)
	for _, v in ipairs(book.participants) do if Same(v, name) then return v end end
end
local function Sum(t) local n = 0; for _, v in pairs(t or {}) do n = n + (tonumber(v) or 0) end return n end
function Notebook.Arithmetic(book)
	if type(book) ~= "table" then return nil end
	local pot, percent = Whole(book.pot) or 0, Whole(book.cut, 100) or 0
	local cut = math.floor(pot * percent / 100)
	local organizer = math.floor(cut / 2)
	local treasurer = cut - organizer
	local pool, assigned = pot - cut, Sum(book.prizes)
	return { pot = pot, percent = percent, cut = cut, organizer = organizer, treasurer = treasurer,
		pool = pool, assigned = assigned, unassigned = pool - assigned }
end

local SharePrivateToTreasurer
local function Changed(book)
	Revision(book)
	if book.public then Notebook.Publish(book.id) end
	if SharePrivateToTreasurer then SharePrivateToTreasurer(book) end
	Refresh()
	return true
end

local function ParseNames(text)
	local out, seen = {}, {}
	for part in tostring(text or ""):gmatch("[^,]+") do
		local name = Name(part)
		local key = name and name:lower()
		if not name or seen[key] or #out >= Notebook.MAX_PARTICIPANTS then return nil end
		seen[key], out[#out + 1] = true, name
	end
	return #out > 0 and out or nil
end
function Notebook.SetParticipants(id, text)
	local book, names = Notebook.Book(id, true), ParseNames(text)
	if not book or not names then return false end
	local keep = {}; for _, name in ipairs(names) do keep[name:lower()] = true end
	for _, r in ipairs(book.results) do
		if not keep[r.a:lower()] or not keep[r.b:lower()] or not keep[r.winner:lower()] then return false end
	end
	for _, name in ipairs(book.podium) do if not keep[name:lower()] then return false end end
	for name in pairs(book.prizes) do if not keep[name:lower()] then return false end end
	book.participants = names
	return Changed(book)
end
function Notebook.AddResult(id, round, a, b, winner)
	local book = Notebook.Book(id, true)
	round, a, b, winner = Clean(round, 40), Name(a), Name(b), Name(winner)
	if not book or round == "" or #book.results >= Notebook.MAX_RESULTS then return false end
	a, b, winner = Has(book, a), Has(book, b), Has(book, winner)
	if not a or not b or Same(a, b) or not winner or (not Same(winner, a) and not Same(winner, b)) then return false end
	book.results[#book.results + 1] = { round = round, a = a, b = b, winner = winner }
	return Changed(book)
end
function Notebook.SetPodium(id, text)
	local book, names = Notebook.Book(id, true), ParseNames(text)
	if not book or not names or #names > 3 then return false end
	for i, name in ipairs(names) do names[i] = Has(book, name); if not names[i] then return false end end
	book.podium = names
	return Changed(book)
end
function Notebook.SetMoney(id, pot, cut)
	local book = Notebook.Book(id, true)
	pot, cut = Whole(pot), Whole(cut, 100)
	if not book or not pot or not cut then return false end
	local available = pot - math.floor(pot * cut / 100)
	if Sum(book.prizes) > available then return false end
	book.pot, book.cut = pot, cut
	return Changed(book)
end
function Notebook.SetPrize(id, name, copper)
	local book = Notebook.Book(id, true)
	name, copper = Name(name), Whole(copper)
	if not book or not name or not copper then return false end
	name = Has(book, name); if not name then return false end
	local key, before = name:lower(), book.prizes[name:lower()] or 0
	local a = Notebook.Arithmetic(book)
	if a.assigned - before + copper > a.pool then return false end
	book.prizes[key] = copper > 0 and copper or nil
	book.paid.prizes[key] = nil
	return Changed(book)
end
function Notebook.MarkEntry(id, name, copper)
	local book = Notebook.Book(id, true)
	name, copper = Name(name), Whole(copper)
	if not book or not name or not copper then return false end
	name = Has(book, name); if not name then return false end
	book.entries[name:lower()] = copper > 0 and copper or nil
	return Changed(book)
end
function Notebook.MarkPaid(id, kind, name, on)
	local book = Notebook.Book(id)
	if not book then return false end
	if kind == "treasurer" then
		book.paid.treasurer = on and true or nil
	elseif kind == "prize" then
		name = Has(book, Name(name)); if not name or not book.prizes[name:lower()] then return false end
		book.paid.prizes[name:lower()] = on and true or nil
	else return false end
	return Changed(book)
end

local function Rows(t, fields)
	local out = {}
	for _, row in ipairs(t or {}) do
		local p = {}; for _, field in ipairs(fields) do p[#p + 1] = Clean(row[field], field == "round" and 40 or 80) end
		out[#out + 1] = table.concat(p, "^")
	end
	return table.concat(out, "/")
end
local function MoneyRows(t)
	local out = {}; for name, copper in pairs(t or {}) do out[#out + 1] = Clean(name, 80) .. "^" .. tostring(Whole(copper) or 0) end
	table.sort(out); return table.concat(out, "/")
end
local function Names(t) local out = {}; for _, name in ipairs(t or {}) do out[#out + 1] = Clean(name, 80) end return table.concat(out, "/") end
local function PaidNames(t) local out = {}; for name, on in pairs(t or {}) do if on then out[#out + 1] = Clean(name, 80) end end table.sort(out); return table.concat(out, "/") end
local function Fields(text)
	local out = {}; for field in (tostring(text or "") .. "~"):gmatch("(.-)~") do out[#out + 1] = field end return out
end
local function DecodeNames(text, max)
	local out, seen = {}, {}
	if text == "" then return out end
	for value in text:gmatch("[^/]+") do
		local name, key = Name(value); key = name and name:lower()
		if not name or seen[key] or #out >= (max or Notebook.MAX_PARTICIPANTS) then return nil end
		seen[key], out[#out + 1] = true, name
	end
	return out
end
local function DecodeResults(text, participants)
	local out = {}; if text == "" then return out end
	local valid = {}; for _, n in ipairs(participants) do valid[n:lower()] = true end
	for value in text:gmatch("[^/]+") do
		local round, a, b, winner = value:match("^([^%^]+)%^([^%^]+)%^([^%^]+)%^([^%^]+)$")
		round, a, b, winner = Clean(round, 40), Name(a), Name(b), Name(winner)
		if not a or not b or not winner or not valid[a:lower()] or not valid[b:lower()] or not valid[winner:lower()]
			or (not Same(winner, a) and not Same(winner, b)) or #out >= Notebook.MAX_RESULTS then return nil end
		out[#out + 1] = { round = round, a = a, b = b, winner = winner }
	end
	return out
end
local function DecodeMoney(text, participants)
	local out, valid = {}, {}; for _, n in ipairs(participants) do valid[n:lower()] = true end
	if text == "" then return out end
	for value in text:gmatch("[^/]+") do
		local name, copper = value:match("^([^%^]+)%^(%d+)$"); name, copper = Name(name), Whole(copper)
		if not name or not copper or not valid[name:lower()] or out[name:lower()] then return nil end
		out[name:lower()] = copper
	end
	return out
end

function Notebook.PublicMessage(book)
	if type(book) ~= "table" then return nil end
	return ("E3~1~%s~%d~%s~%s~%s~%s~%s"):format(tostring(book.id), Whole(book.rev) or 0, book.public and "1" or "0",
		Clean(book.title, 100), Names(book.participants), Rows(book.results, { "round", "a", "b", "winner" }), Names(book.podium))
end
function Notebook.PrivateMessage(book, nonce)
	if type(book) ~= "table" then return nil end
	return ("EN~1~D~%d~%s~%d~%s~%s~%d~%d~%s~%s~%s~%s~%s~%s~%s"):format(Whole(nonce) or 0,
		tostring(book.id), Whole(book.rev) or 0, Clean(book.title, 100), Clean(book.by, 80), Whole(book.pot) or 0,
		Whole(book.cut, 100) or 0, Names(book.participants), Rows(book.results, { "round", "a", "b", "winner" }),
		Names(book.podium), MoneyRows(book.prizes), MoneyRows(book.entries), book.paid.treasurer and "1" or "0", PaidNames(book.paid.prizes))
end

local function DecodeSnapshot(f, first)
	local id, rev, title, by = f[first], Whole(f[first + 1]), Clean(f[first + 2], 100), Name(f[first + 3])
	local pot, cut = Whole(f[first + 4]), Whole(f[first + 5], 100)
	local participants = DecodeNames(f[first + 6])
	local results = participants and DecodeResults(f[first + 7], participants)
	local podium = participants and DecodeNames(f[first + 8], 3)
	local prizes = participants and DecodeMoney(f[first + 9], participants)
	local entries = participants and DecodeMoney(f[first + 10], participants)
	local paidTreasurer = f[first + 11] == "1" and true or f[first + 11] == "0" and nil
	local paid = participants and DecodeNames(f[first + 12])
	if not id or id == "" or not rev or title == "" or not by or not pot or not cut or not participants or not results or not podium
		or not prizes or not entries or f[first + 11] ~= "0" and f[first + 11] ~= "1" or not paid then return nil end
	local valid = {}; for _, n in ipairs(participants) do valid[n:lower()] = true end
	for _, n in ipairs(podium) do if not valid[n:lower()] then return nil end end
	local paidPrizes = {}; for _, n in ipairs(paid) do if not prizes[n:lower()] then return nil end paidPrizes[n:lower()] = true end
	local book = { version = 1, id = tonumber(id) or id, rev = rev, title = title, by = by, pot = pot, cut = cut,
		participants = participants, results = results, podium = podium, prizes = prizes, entries = entries,
		paid = { treasurer = paidTreasurer, prizes = paidPrizes } }
	local a = Notebook.Arithmetic(book); if a.unassigned < 0 then return nil end
	return book
end

local function StaffName(name)
	return ns.IsKingCharacter(name) or (ns.King and ns.King.IsStewardName and ns.King.IsStewardName(name))
		or (ns.Treasury and ns.Treasury.TreasurerPin and ns.Treasury.TreasurerPin(ns.FullName(ns.Normal(name))) ~= nil)
end
local function LocalStaff()
	return ns.King and ((ns.King.IsKing and ns.King.IsKing()) or (ns.King.IsSteward and ns.King.IsSteward()))
		or (ns.Treasury and ns.Treasury.TreasurerPin and ns.Treasury.TreasurerPin(ns.me) ~= nil)
end
local function Organizer(name)
	if not ns.Week or not ns.Week.Entries then return false end
	for _, e in ipairs(ns.Week.Entries()) do if Same(e.by, name) then return true end end
	return false
end
local function TreasurerName()
	return ns.TREASURER and ns.FullName(ns.TREASURER, ns.TREASURER_REALM) or nil
end

function Notebook.Publish(id)
	local book = Notebook.Book(id)
	if not book then return false end
	local root = Root(true)
	root.public[tostring(book.id)] = book.public and {
		id = book.id, rev = book.rev, title = book.title, by = book.by, participants = book.participants,
		results = book.results, podium = book.podium, public = true,
	} or nil
	local msg = Notebook.PublicMessage(book)
	return ns.Comm.SendChunked(msg, nil, "CHANNEL", nil, { owner = Notebook, guard = function()
		local current = Notebook.Book(id); return current ~= nil and current.rev == book.rev and current.public == book.public
	end }) ~= false
end
function Notebook.SetPublic(id, on)
	local book = Notebook.Book(id, true); if not book then return false end
	book.public = on and true or nil
	Revision(book); Notebook.Publish(id); SharePrivateToTreasurer(book); Refresh(); return true
end

function Notebook.HandlePublic(dist, sender, text)
	if dist ~= "CHANNEL" or type(text) ~= "string" or #text > Notebook.ROOM then return false end
	local f = Fields(text)
	if #f ~= 9 or f[1] ~= "E3" or f[2] ~= "1" then return false end
	local id, rev, shown = f[3], Whole(f[4]), f[5]
	local e = id and Event(id)
	if not e or not rev or (shown ~= "0" and shown ~= "1") or not Same(e.by, sender) then return false end
	local root, key = Root(true), tostring(e.id)
	local old = root.public[key]
	if old and rev <= (tonumber(old.rev) or 0) then return false end
	if shown == "0" then root.public[key] = nil; Refresh(); return true end
	local participants = DecodeNames(f[7]); local results = participants and DecodeResults(f[8], participants)
	local podium = participants and DecodeNames(f[9], 3)
	if Clean(f[6], 100) == "" or not participants or not results or not podium then return false end
	local valid = {}; for _, n in ipairs(participants) do valid[n:lower()] = true end
	for _, n in ipairs(podium) do if not valid[n:lower()] then return false end end
	root.public[key] = { id = e.id, rev = rev, title = Clean(f[6], 100), by = ns.FullName(sender), participants = participants,
		results = results, podium = podium, public = true }
	Refresh(); return true
end
ns.Comm.Handle("E3", Notebook.HandlePublic)

local function SendPrivate(to, book, nonce)
	local msg = Notebook.PrivateMessage(book, nonce)
	return msg and ns.Treasury.Private(to, "EN", msg, "event " .. tostring(book.id)) or false
end
SharePrivateToTreasurer = function(book)
	local to = TreasurerName()
	if not to or Same(to, ns.me) then return false end
	return SendPrivate(to, book, 0)
end
function Notebook.Request(id)
	local e = Event(id)
	if not e or not LocalStaff() or Same(e.by, ns.me) then return false end
	local nonce = math.max(math.floor(ns.Now()), (pending.seq or 0) + 1); pending.seq = nonce
	pending[ns.FullName(e.by):lower() .. ":" .. tostring(e.id)] = nonce
	local msg = ("EN~1~Q~%d~%s"):format(nonce, tostring(e.id))
	local ok = ns.Treasury.Private(e.by, "EN", msg, "event ask " .. tostring(e.id))
	if ok then ns.Print(L.EVENT_NOTEBOOK_REQUESTED:format(Display(e.by))) end
	return ok
end
function Notebook.HandlePrivate(dist, sender, text)
	if dist ~= "WHISPER" or type(text) ~= "string" or #text > Notebook.ROOM then return false end
	local f = Fields(text)
	if f[1] ~= "EN" or f[2] ~= "1" then return false end
	if f[3] == "Q" then
		if #f ~= 5 or not StaffName(sender) then return false end
		local nonce, book = Whole(f[4]), Notebook.Book(f[5])
		if not nonce or nonce == 0 or not book then return false end
		return SendPrivate(sender, book, nonce) == true
	elseif f[3] == "D" then
		if #f ~= 17 or not LocalStaff() then return false end
		local nonce = Whole(f[4]); if nonce == nil then return false end
		local book = DecodeSnapshot(f, 5)
		local e = book and Event(book.id)
		if not book or not e or not Same(book.by, sender) or not Same(e.by, sender) then return false end
		local key = ns.FullName(sender):lower() .. ":" .. tostring(e.id)
		if nonce == 0 then
			if not (ns.Treasury.TreasurerPin(ns.me) and Same(TreasurerName(), ns.me)) then return false end
		elseif pending[key] ~= nonce then return false end
		local root = Root(true); local old = root.private[key]
		if old and book.rev <= (tonumber(old.rev) or 0) then return false end
		pending[key] = nil; root.private[key] = book; Refresh(); return true
	end
	return false
end
ns.Treasury.OnPrivate("EN", {
	from = function(sender) return StaffName(sender) or Organizer(sender) end,
	to = function() return LocalStaff() or Actor(false) ~= nil end,
	send = function(to, msg)
		local f = Fields(msg)
		if f[3] == "Q" then
			local e = Event(f[5]); return LocalStaff() and e ~= nil and Same(e.by, to)
		elseif f[3] == "D" then
			local book = Notebook.Book(f[5]); return book ~= nil and StaffName(to)
		end
		return false
	end,
	handle = Notebook.HandlePrivate,
})

function Notebook.TreasuryFlow(name, out, copper, note, item, how)
	if out or item or not ns.Treasury.TreasurerPin(ns.me) or not Whole(copper) then return nil end
	local root = Root(false); if not root then return nil end
	local match, matches
	for key, book in pairs(root.private) do
		local a = Notebook.Arithmetic(book)
		local subject = Notebook.Subject(book.id, "treasurer")
		if type(book) == "table" and Same(book.by, name) and a and a.treasurer > 0 and a.treasurer == copper
			and not root.receipts[key] and ((how == "trade" and (note == nil or note == "")) or note == subject) then
			match, matches = key, (matches or 0) + 1
		end
	end
	if matches ~= 1 then return nil end
	root.receipts[match] = { at = ns.Now(), copper = copper, from = ns.FullName(name) }
	root.private[match].treasurerReceived = true
	return match
end

-- Stable across client languages so a Treasurer can recognize a real incoming mail.
function Notebook.Subject(id, kind, name)
	local suffix = kind == "treasurer" and "treasurer" or ("prize " .. Clean(Display(name), 40))
	return ("Olympus event %s %s"):format(Clean(id, 24), suffix)
end

local function Owed(book, kind, name)
	local a = Notebook.Arithmetic(book)
	if kind == "treasurer" then return a.treasurer, TreasurerName(), book.paid.treasurer end
	if kind ~= "prize" then return end
	name = Has(book, Name(name)); if not name then return end
	return book.prizes[name:lower()], name, book.paid.prizes[name:lower()]
end
local function Shown(frame) return type(frame) == "table" and frame.IsShown and frame:IsShown() and true or false end
function Notebook.Fill(id, kind, name)
	local book = Notebook.Book(id)
	if not book then return false, "state" end
	local amount, to, paid = Owed(book, kind, name)
	if not amount or amount <= 0 or paid then return false, "state" end
	if not Shown(TradeFrame) then ns.Print(L.EVENT_NOTEBOOK_TRADE_CLOSED:format(Display(to), Coins(amount))); return false, "closed" end
	local target = ns.UnitFullName and ns.UnitFullName("NPC") or (UnitName and UnitName("NPC"))
	if not Same(target, to) then ns.Print(L.EVENT_NOTEBOOK_TRADE_OTHER:format(Display(target), Display(to))); return false, "other" end
	local money = GetMoney and tonumber(GetMoney()) or nil
	if money and money < amount then ns.Print(L.EVENT_NOTEBOOK_NOT_ENOUGH:format(Coins(amount))); return false, "short" end
	local set = C_TradeInfo and C_TradeInfo.SetTradeMoney or SetTradeMoney
	if ns.GamepadUI() or not set or (ns.db and ns.db.eventTradeBlocked) then
		ns.Print(L.EVENT_NOTEBOOK_TRADE_TYPE:format(Coins(amount), Display(to))); return true, "type"
	end
	local ok = pcall(set, amount)
	if not ok then ns.Print(L.EVENT_NOTEBOOK_TRADE_TYPE:format(Coins(amount), Display(to))); return true, "type" end
	ns.Print(L.EVENT_NOTEBOOK_TRADE_FILLED:format(Coins(amount), Display(to)))
	return true, "trade"
end

function Notebook.Apply(id, input)
	input = tostring(input or "")
	local cmd, rest = input:match("^%s*(%S+)%s+(.+)%s*$"); cmd = cmd and cmd:lower()
	if cmd == "participants" then return Notebook.SetParticipants(id, rest) end
	if cmd == "podium" then return Notebook.SetPodium(id, rest) end
	local a, b, c, d
	if cmd == "result" then a, b, c, d = rest:match("^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$"); return Notebook.AddResult(id, a, b, c, d) end
	if cmd == "money" then
		a, b = rest:match("^%s*(.-)%s*|%s*(%d+)%s*$")
		return Notebook.SetMoney(id, ns.Treasury.ParseGold(a), tonumber(b))
	end
	if cmd == "prize" or cmd == "entry" then
		a, b = rest:match("^%s*(.-)%s*|%s*(.-)%s*$")
		local copper = ns.Treasury.ParseGold(b)
		return cmd == "prize" and Notebook.SetPrize(id, a, copper) or Notebook.MarkEntry(id, a, copper)
	end
	return false
end

function Notebook.Prompt(id)
	if not Notebook.Book(id, true) then return false end
	return ns.ShowDialog("OLYMPUS_EVENT_NOTEBOOK", L.EVENT_NOTEBOOK_COMMAND, nil, id) ~= nil
end
local function EditShow(self) local box = self.editBox or self.EditBox; if box then box:SetText(""); box:SetFocus() end end
StaticPopupDialogs.OLYMPUS_EVENT_NOTEBOOK = { text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Cancel", hasEditBox = true, OnShow = EditShow,
	OnAccept = function(self, data) local box = self.editBox or self.EditBox; if not Notebook.Apply(data or self.data, box and box:GetText()) then ns.Print(L.EVENT_NOTEBOOK_BAD_COMMAND) end end,
	EditBoxOnEnterPressed = function(self) if not Notebook.Apply(self:GetParent().data, self:GetText()) then ns.Print(L.EVENT_NOTEBOOK_BAD_COMMAND) end self:GetParent():Hide() end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end, timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }

local function PublicOf(e)
	local own = Notebook.Book(e.id)
	if own and own.public then return own end
	local root = Root(false); return root and root.public[tostring(e.id)] or nil
end
local function PrivateOf(e)
	local own = Notebook.Book(e.id)
	if own then return own end
	local root = Root(false); return root and root.private[ns.FullName(e.by):lower() .. ":" .. tostring(e.id)] or nil
end
local function BracketLines(lines, book, indent)
	indent = indent or 4
	if #book.participants == 0 then lines[#lines + 1] = { indent = indent, text = Grey(L.EVENT_NOTEBOOK_EMPTY), wrap = true } return end
	lines[#lines + 1] = { indent = indent, text = L.EVENT_NOTEBOOK_PARTICIPANTS, right = tostring(#book.participants) }
	lines[#lines + 1] = { indent = indent + 1, text = table.concat((function() local t = {}; for _, n in ipairs(book.participants) do t[#t + 1] = Display(n) end return t end)(), ", "), wrap = true }
	if #book.results > 0 then lines[#lines + 1] = { indent = indent, text = L.EVENT_NOTEBOOK_RESULTS }
		for _, r in ipairs(book.results) do lines[#lines + 1] = { indent = indent + 1, text = L.EVENT_NOTEBOOK_RESULT:format(r.round, Display(r.a), Display(r.b), Display(r.winner)), wrap = true } end end
	if #book.podium > 0 then
		local p = {}; for i, n in ipairs(book.podium) do p[#p + 1] = i .. ". " .. Display(n) end
		lines[#lines + 1] = { indent = indent, text = L.EVENT_NOTEBOOK_PODIUM, right = table.concat(p, "  ") }
	end
end
local function FinanceLines(lines, book)
	local a = Notebook.Arithmetic(book)
	lines[#lines + 1] = { indent = 4, text = L.EVENT_NOTEBOOK_POT, right = Coins(a.pot) }
	lines[#lines + 1] = { indent = 4, text = L.EVENT_NOTEBOOK_CUT:format(a.percent), right = Coins(a.cut) }
	lines[#lines + 1] = { indent = 5, text = L.EVENT_NOTEBOOK_ORGANIZER, right = Coins(a.organizer) }
	local treasurerPaid = book.paid.treasurer and Green(L.EVENT_NOTEBOOK_PAID) or Red(L.EVENT_NOTEBOOK_UNPAID)
	lines[#lines + 1] = { indent = 5, text = L.EVENT_NOTEBOOK_TREASURER .. " · " .. treasurerPaid, right = Coins(a.treasurer),
		onClick = function() Notebook.MarkPaid(book.id, "treasurer", nil, not book.paid.treasurer) end }
	if a.treasurer > 0 and not book.paid.treasurer then lines[#lines + 1] = { indent = 6, text = Gold("> " .. L.EVENT_NOTEBOOK_FILL:format(Coins(a.treasurer), Display(TreasurerName()))),
		onClick = function() Notebook.Fill(book.id, "treasurer") end } end
	if a.treasurer > 0 then lines[#lines + 1] = { indent = 6, text = Grey(L.EVENT_NOTEBOOK_MAIL_NOTE:format(Notebook.Subject(book.id, "treasurer"))), wrap = true } end
	lines[#lines + 1] = { indent = 4, text = L.EVENT_NOTEBOOK_PRIZES, right = Coins(a.assigned) }
	local prizes = {}; for name, amount in pairs(book.prizes) do prizes[#prizes + 1] = { name = name, amount = amount } end
	table.sort(prizes, function(x, y) return x.name < y.name end)
	for _, p in ipairs(prizes) do
		local name = p.name
		local paid = book.paid.prizes[name] and Green(L.EVENT_NOTEBOOK_PAID) or Red(L.EVENT_NOTEBOOK_UNPAID)
		lines[#lines + 1] = { indent = 5, text = Display(name) .. " · " .. paid, right = Coins(p.amount),
			onClick = function() Notebook.MarkPaid(book.id, "prize", name, not book.paid.prizes[name]) end }
		if not book.paid.prizes[name] then lines[#lines + 1] = { indent = 6, text = Gold("> " .. L.EVENT_NOTEBOOK_FILL:format(Coins(p.amount), Display(name))),
			onClick = function() Notebook.Fill(book.id, "prize", name) end } end
		lines[#lines + 1] = { indent = 6, text = Grey(L.EVENT_NOTEBOOK_MAIL_NOTE:format(Notebook.Subject(book.id, "prize", name))), wrap = true }
	end
	lines[#lines + 1] = { indent = 4, text = L.EVENT_NOTEBOOK_UNASSIGNED, right = Coins(a.unassigned) }
	lines[#lines + 1] = { indent = 4, text = L.EVENT_NOTEBOOK_ENTRIES, right = Coins(Sum(book.entries)) }
end
function Notebook.Lines(lines, e)
	if type(lines) ~= "table" or type(e) ~= "table" then return end
	local public, own = PublicOf(e), Owns(e)
	local private = own and Notebook.Book(e.id, true) or (LocalStaff() and PrivateOf(e) or nil)
	if not public and not private and not own then return end
	local open = opened[tostring(e.id)]
	lines[#lines + 1] = { indent = 3, text = Gold((open and "[-] " or "[+] ") .. L.EVENT_NOTEBOOK),
		onClick = function() opened[tostring(e.id)] = not open or nil; Refresh() end,
		tooltip = function(tt) tt:AddLine(L.EVENT_NOTEBOOK, 1, 0.82, 0); tt:AddLine(L.EVENT_NOTEBOOK_MONEY_NOTE, 1, 1, 1, true) end }
	if not open then return end
	if public then lines[#lines + 1] = { indent = 4, text = Gold(L.EVENT_NOTEBOOK_PUBLIC) }; BracketLines(lines, public, 5) end
	if private then
		lines[#lines + 1] = { indent = 4, text = Gold(L.EVENT_NOTEBOOK_PRIVATE) }
		if not public then BracketLines(lines, private, 5) end
		FinanceLines(lines, private)
	end
	if own then
		local book = Notebook.Book(e.id, true)
		lines[#lines + 1] = { indent = 4, text = Gold("> " .. L.EVENT_NOTEBOOK_EDIT), onClick = function() Notebook.Prompt(e.id) end }
		lines[#lines + 1] = { indent = 4, text = Gold("> " .. (book.public and L.EVENT_NOTEBOOK_UNSHARE or L.EVENT_NOTEBOOK_SHARE)), onClick = function() Notebook.SetPublic(e.id, not book.public) end }
	elseif LocalStaff() and not private then
		lines[#lines + 1] = { indent = 4, text = Gold("> " .. L.EVENT_NOTEBOOK_REQUEST), onClick = function() Notebook.Request(e.id) end }
	end
	lines[#lines + 1] = { indent = 4, text = Grey(L.EVENT_NOTEBOOK_ENTRY_NOTE), wrap = true }
	lines[#lines + 1] = { indent = 4, text = Grey(L.EVENT_NOTEBOOK_MONEY_NOTE), wrap = true }
	lines[#lines + 1] = { indent = 4, text = Grey(L.EVENT_NOTEBOOK_PRIVACY_NOTE), wrap = true, gapAfter = true }
end

function Notebook.Tick()
	if ns.Now() - lastRepeat < Notebook.REPEAT then return end
	lastRepeat = ns.Now()
	local actor = Actor(false)
	for _, book in pairs(actor and actor.books or {}) do
		if book.public then Notebook.Publish(book.id) end
		SharePrivateToTreasurer(book)
	end
end
ns.On("LOGIN", function()
	ns.RegisterEvent("TRADE_SHOW", Refresh) -- recognition only: never fills from this event
	ns.RegisterEvent("TRADE_CLOSED", Refresh)
	for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
		ns.RegisterEvent(event, function(addon, func)
			if addon ~= ADDON or not tostring(func):find("TradeMoney", 1, true) or not ns.db or ns.db.eventTradeBlocked then return end
			ns.db.eventTradeBlocked = true; ns.Print(L.EVENT_NOTEBOOK_TRADE_BLOCKED)
		end)
	end
	ns.Every(60, "event notebook", Notebook.Tick)
end)


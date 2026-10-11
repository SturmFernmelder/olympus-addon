-- 1.2.1, the Bones tables' notices (Olympus/FarkleTable.lua's KN, the live tables list): a player
-- who allows watchers announces his table, and anyone on the channel can send one naming himself
-- as a player. Before 1.2.1 every new id was kept for the session, so one sender with made-up ids
-- grew the list without end. Now one sender keeps at most FT.NOTICES_EACH (his oldest goes), the
-- list FT.NOTICES_MAX in all (the oldest heard goes first), and a table this client watches keeps
-- its notice. Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local FW = assert(loadfile(H.ROOT .. "tests/arena/lib/farkle-world.lua"))(H)
local N = H.World.NAMES
local P1, P2 = N.fighterA, N.fighterB

local function FT(c) return c.ns.FarkleTable end
local function Notices(c) return FT(c)._.notices() end
local function Count(c)
	local n = 0
	for _ in pairs(Notices(c)) do n = n + 1 end
	return n
end
local function From(c, sender)
	local n = 0
	for _, x in pairs(Notices(c)) do if x.by:lower() == sender.name:lower() then n = n + 1 end end
	return n
end
-- A notice from `from` for table `id`, naming `from` as its first player.
local function Notice(w, from, id, other)
	w:As(from, function() from.ns.Arena.Send("KN", "T", ("%s~%s~%s~-~2~-~o~-"):format(id, from.name, other or P2), {}) end)
	w:Run(0)
end
local function NoErrors(w)
	for _, c in ipairs(w.clients) do
		for _, e in ipairs(c.errors) do error(c.name .. ": " .. e, 2) end
	end
end

print("1.2.1: the Bones tables' notices are bounded")

test("1.2.1 Bones notices: one sender's made-up tables are kept FT.NOTICES_EACH at most, his newest; his live table stays listed", function()
	local w = FW.New()
	local a, c = w:Player(P1), w:Player("Wenna Crale")
	local each = FT(c).NOTICES_EACH or 3
	for i = 1, 50 do Notice(w, a, "Kflood" .. i) end
	eq(From(c, a), each, "one sender's notices")
	eq(Count(c), each)
	-- the newest are the ones kept
	for i = 51 - each, 50 do eq(Notices(c)["Kflood" .. i] ~= nil, true, "Kflood" .. i) end
	eq(Notices(c).Kflood1, nil, "the oldest went")
	eq(#FT(c).LiveTables(), each, "the live list shows what is kept")
	-- the same table announced again replaces its notice: nothing else goes
	Notice(w, a, "Kflood50")
	eq(Count(c), each)
	NoErrors(w)
end)

test("1.2.1 Bones notices: many senders fill FT.NOTICES_MAX at most, the oldest heard going first; a watched table keeps its notice", function()
	local w = FW.New()
	local c = w:Player("Wenna Crale")
	local max, each = FT(c).NOTICES_MAX or 100, FT(c).NOTICES_EACH or 3
	local senders = math.ceil(max / each) + 4
	local players = {}
	for s = 1, senders do
		players[s] = w:Player(("Torin Vale%s%s"):format(string.char(97 + (s - 1) % 26), string.char(97 + math.floor((s - 1) / 26))))
	end
	-- the first notice heard is a table this client then watches
	Notice(w, players[1], "Kwatched")
	assert(FT(c).Watch("Kwatched"))
	w:Run(0)
	w:Run(61)
	for s = 1, senders do
		for i = 1, each do Notice(w, players[s], ("Kp%dn%d"):format(s, i)) end
		w:Run(1)
	end
	eq(Count(c) <= max, true, "at most NOTICES_MAX: " .. Count(c))
	eq(Count(c), max)
	eq(Notices(c).Kwatched ~= nil, true, "the watched table's notice stays")
	eq(Notices(c)[("Kp%dn%d"):format(senders, each)] ~= nil, true, "the newest is kept")
	eq(Notices(c)[("Kp%dn%d"):format(2, 1)], nil, "an old one went")
	NoErrors(w)
end)

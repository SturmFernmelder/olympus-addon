local H = ...
local test, eq = H.test, H.eq
local ns = H.ns

print("Codec.lua: a full buffer of open pieces makes room instead of refusing everyone")

-- Codec.lua in a namespace of its own: guildmates (the roster), the pinned King and a signed
-- councillor as this world has them.
local function Fresh()
	local kin = {}
	local cns = setmetatable({
		Roster = { RankOf = function(name) return kin[name] end },
		IsKingCharacter = function(name) return name == "Crowned-Realm" end,
		IsHighCouncillor = function(name) return name == "Sage-Realm" end,
	}, { __index = ns })
	assert(loadfile(H.ADDON_DIR .. "Codec.lua"))("Olympus", cns)
	return cns.Codec, kin
end

-- n senders named prefix1..prefixN, each opening `each` two-piece messages that never complete.
local function Fill(C, asm, prefix, n, each, now)
	for s = 1, n do
		for m = 1, each do C.Feed(asm, prefix .. s .. "-Realm", ("C%d:1:2:x"):format(m), now + s) end
	end
end

test("1.2.1 leaks: a hundred characters holding their open pieces no longer keep everyone's multi-piece messages out", function()
	local C = Fresh()
	local asm, now = C.NewAssembler(), 1000
	Fill(C, asm, "Hoarder", C.OPEN_MAX / C.OPEN_PER_SENDER, C.OPEN_PER_SENDER, now)
	eq(asm.open, C.OPEN_MAX, "the buffer is full")
	-- A stranger's report in two pieces: room is made, it completes.
	eq(C.Feed(asm, "Reporter-Realm", "C9:1:2:ab", now + 200), nil)
	eq(C.Feed(asm, "Reporter-Realm", "C9:2:2:cd", now + 201), "abcd", "it got through")
	eq(asm.evicted, 1, "one open message closed for it")
	eq(asm.bySender["Hoarder1-Realm"], C.OPEN_PER_SENDER - 1, "the oldest of those holding the most")
	eq(asm.open, C.OPEN_MAX - 1)
	-- Full again; another newcomer's message is taken, and a hoarder can't take its room back from
	-- one who holds fewer than he does.
	C.Feed(asm, "Hoarder1-Realm", "C7:1:2:x", now + 300)
	eq(asm.open, C.OPEN_MAX)
	eq(C.Feed(asm, "Newcomer-Realm", "C3:1:2:ab", now + 301), nil)
	eq(asm.bySender["Newcomer-Realm"], 1, "the newcomer's message is open")
	eq(asm.bySender["Hoarder1-Realm"], C.OPEN_PER_SENDER - 1, "again the oldest of those holding the most")
	local refused = asm.refused
	eq(C.Feed(asm, "Hoarder1-Realm", "C8:1:2:x", now + 302), nil)
	eq(asm.refused, refused + 1, "three open: nobody holds more than four, so he waits")
	eq(C.Feed(asm, "Hoarder1-Realm", "C8:1:2:x", now + 302), nil)
	eq(asm.refused, refused + 2, "and again, the buffer unchanged")
	eq(asm.bySender["Newcomer-Realm"], 1, "the newcomer's stays")
	-- A stranger holding none still finds room after the hoarder's tries.
	local evicted = asm.evicted
	C.Feed(asm, "Second-Realm", "C4:1:2:ab", now + 302)
	eq(asm.bySender["Second-Realm"], 1); eq(asm.evicted, evicted + 1)
	eq(C.Feed(asm, "Newcomer-Realm", "C3:2:2:cd", now + 303), "abcd")
	-- The per-sender cap is as before.
	local b = C.NewAssembler()
	for k = 1, 10 do C.Feed(b, "Greedy-Realm", ("C%d:1:30:x"):format(k), now) end
	eq(b.open, C.OPEN_PER_SENDER); eq(b.refused, 10 - C.OPEN_PER_SENDER)
end)

test("1.2.1 leaks: a buffer full of strangers' single messages lets in our guildmates, the King and a councillor, never another stranger over them; theirs are never closed", function()
	local C, kin = Fresh()
	kin["Kinsman-Realm"] = 3
	local asm, now = C.NewAssembler(), 1000
	Fill(C, asm, "Single", C.OPEN_MAX, 1, now)
	eq(asm.open, C.OPEN_MAX)
	eq(C.Feed(asm, "Late-Realm", "C1:1:2:x", now + 900), nil)
	eq(asm.bySender["Late-Realm"], nil, "a stranger takes no one's room when each holds one")
	for i, who in ipairs({ "Kinsman-Realm", "Crowned-Realm", "Sage-Realm" }) do
		eq(C.Feed(asm, who, "C1:1:2:ab", now + 900 + i), nil)
		eq(asm.bySender[who], 1, who .. " is in")
		eq(asm.bySender["Single" .. i .. "-Realm"], nil, "the oldest stranger's closed")
	end
	eq(asm.evicted, 3)
	eq(C.Feed(asm, "Kinsman-Realm", "C1:2:2:cd", now + 950), "abcd")
	eq(C.Trusted("Kinsman-Realm"), true); eq(C.Trusted("Crowned-Realm"), true); eq(C.Trusted("Sage-Realm"), true)
	eq(C.Trusted("Single9-Realm"), false)
	-- Guildmates' open messages are never closed for anyone.
	local g = C.NewAssembler()
	for s = 1, C.OPEN_MAX / C.OPEN_PER_SENDER do kin["Kin" .. s .. "-Realm"] = 3 end
	Fill(C, g, "Kin", C.OPEN_MAX / C.OPEN_PER_SENDER, C.OPEN_PER_SENDER, now)
	eq(C.Feed(g, "Stranger-Realm", "C1:1:2:x", now + 900), nil)
	kin["Kinsman-Realm"] = 3
	eq(C.Feed(g, "Kinsman-Realm", "C1:1:2:x", now + 901), nil)
	eq(g.evicted, 0); eq(g.open, C.OPEN_MAX); eq(g.refused, 2, "both wait: no stranger's message to close")
end)

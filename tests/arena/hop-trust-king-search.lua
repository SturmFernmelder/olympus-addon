-- 1.2.1: the King's match search lists only the names the addon can vouch for (ArenaMatch.lua's
-- answer handler asks Hop.Trusted). The match world stands Hop.Trusted in for each client
-- (tests/arena/lib/match-world.lua), so this file loads the real Hop.lua into the King's client
-- and checks what that trust is now: a guildmate of his is listed, an officer of another Olympus
-- guild only the census names is not (two cooperating characters can forge that rank while signed
-- enforcement is off). Every name is invented.
local H = ...
local test, eq = H.test, H.eq
local World = H.World
local MW = assert(loadfile(H.ROOT .. "tests/arena/lib/match-world.lua"))(H)

local SEEKER = { cont = 0, wx = -13000, wy = 300 }
local OTHER = { cont = 0, wx = -13400, wy = 250 }

-- An answer whispered to a searcher's client by `from`.
local function O(w, c, from, body) w:As(c, function() c.ns.Arena.Inject("WHISPER", from, "AM~L1~O~" .. body) end) end

test("1.2.1 the King's match search: the real Hop.Trusted lists his guildmate, never an officer only the census names", function()
	local w = World.New()
	local king = MW.Client(w, World.NAMES.king, { guild = World.KING_GUILD, rank = 0, pos = SEEKER })
	local mate = MW.Client(w, "Mirela Stonecroft", { guild = World.KING_GUILD, rank = 3, pos = OTHER })
	local officer = "Orrin Valecourt-Emberfall" -- (plays on no client of this world)
	king.db.throneLocation = true
	-- The real Hop in the King's client, in place of the world's stand-in.
	w:As(king, function() assert(loadfile(H.ADDON_DIR .. "Hop.lua"))("Olympus", king.ns) end)
	assert(rawget(king.ns, "Hop") and king.ns.Hop.HandleAsk, "the real Hop")
	-- The King's census names Orrin an officer of <Olympus Ash>, as two of its reports would.
	king.rdb.guilds["Olympus Ash"] = { total = 40, online = 4, zones = {}, t = w.clock, leader = "Leda Ashgrove",
		leaderOnline = false, officers = { { name = "Orrin Valecourt" } }, top = {} }
	king.ns.Data.KnownRank = function(n, g)
		if king.ns.FullName(n) == officer and g == "Olympus Ash" then return 1, 2 end
		return nil
	end
	w:As(king, function()
		eq(king.ns.Hop.Trusted(mate.name), true, "a guildmate: our roster")
		eq(king.ns.Hop.Trusted(officer), false, "a census rank alone vouches for nobody")
		eq(king.ns.ArenaMatch.MemberOK(officer, "Olympus Ash"), true, "he passes the member check: only trust drops him")
	end)
	assert(king.Match.Start({ game = "d", kind = "c", level = 0 }))
	eq(king.Match.View().search ~= nil, true, "the King's search runs")
	O(w, king, officer, "9ix~f~Olympus Ash~1~1o~1~d~c~0")
	O(w, king, mate.name, "9ix~f~" .. World.KING_GUILD .. "~1~1o~1~d~c~0")
	local names = {}
	for _, e in ipairs(king.Match.Ranked()) do names[#names + 1] = e.o.name end
	eq(table.concat(names, ","), mate.name, "only the guildmate is listed")
	MW.NoErrors(w)
end)

local H = ...
local test, eq = H.test, H.eq

local function Ranking(bodies)
	local registered, events = {}, {}
	local fake = setmetatable({
		L = setmetatable({}, { __index = function(_, k) return k end }),
		Now = function() return 1790000000 end,
		Normal = function(v) return v end,
		FullName = function(v) return v and (v:find("-", 1, true) and v or (v .. "-Emberfall")) end,
		DisplayName = function(v) return v end,
		Ed25519 = {
			FromB64 = function(v) return #v == 43 and string.rep("k", 32) or (#v == 86 and string.rep("s", 64) or nil) end,
			ToB64 = function(v) return #v == 32 and string.rep("A", 43) or string.rep("B", 86) end,
		},
		Records = {
			Register = function(letter, spec) registered[letter] = spec return true end,
			Bodies = function() return bodies or {} end,
			MonthStart = function(month) return month * 31 * 86400 end,
		},
		RankingRules = { Register = function() end },
		On = function(name, fn) events[name] = fn end,
		After = function() end,
		Every = function() end,
	}, { __index = H.ns })
	assert(loadfile(H.ADDON_DIR .. "CraftRanking.lua"))("Olympus", fake)
	return fake.CraftRanking, registered.c, events
end

local function Half(id, requester, crafter, item, quantity, tier, day, role)
	return table.concat({ id, requester, crafter, item, quantity, tier, day, role,
		string.rep("A", 43), string.rep("B", 86) }, "~")
end

test("craft ranking: only bilateral delivered work scores, weighted by useful quantity and rarity", function()
	local C = Ranking()
	eq(C.Score(1, 0), 10)
	assert(C.Score(25, 0) > C.Score(1, 0), "a useful bulk delivery earns more than one basic item")
	assert(C.Score(1000, 0) < C.Score(1, 4), "bulk common goods do not erase a truly rare delivery")

	local day = 20000
	local body = Half("abc", "Buyer-Emberfall", "Smith-Emberfall", 123, 5, 4, day, "r") .. "^"
		.. Half("abc", "Buyer-Emberfall", "Smith-Emberfall", 123, 5, 2, day, "c")
	local rec = assert(C.ReadRecord(body))
	eq(rec.tier, 2, "a rarity disagreement uses the lower claim")
	eq(rec.points, C.Score(5, 2))
	eq(C.ReadRecord(Half("abc", "Buyer-Emberfall", "Smith-Emberfall", 123, 5, 4, day, "r")), nil,
		"one player's claim is not a ranking record")
end)

test("craft ranking: records aggregate deliveries rather than recipes known", function()
	local day, buyer, crafter = 20000, "Buyer-Emberfall", "Smith-Emberfall"
	local bodies = {}
	for i = 1, 4 do
		bodies[i] = Half("abc" .. i, buyer, crafter, 100 + i, 1, 0, day, "r") .. "^"
			.. Half("abc" .. i, buyer, crafter, 100 + i, 1, 0, day, "c")
	end
	local C = Ranking(bodies)
	local rows = C.Totals(math.floor(day / 31))
	eq(#rows, 1)
	eq(rows[1].deliveries, C.PAIR_DAY_MAX, "the repeated-pair daily cap prevents farming")
	eq(rows[1].points, C.PAIR_DAY_MAX * C.Score(1, 0))
	eq(rows[1].customers, 1)
end)

test("craft ranking: a crafter cannot farm beyond the documented daily cap through many customers", function()
	local day, crafter, bodies = 20000, "Smith-Emberfall", {}
	for i = 1, 30 do
		local buyer, id = ("Buyer%d-Emberfall"):format(i), "many" .. i
		bodies[i] = Half(id, buyer, crafter, 100 + i, 1, 0, day, "r") .. "^"
			.. Half(id, buyer, crafter, 100 + i, 1, 0, day, "c")
	end
	local C = Ranking(bodies)
	local rows = C.Totals(math.floor(day / 31))
	eq(#rows, 1)
	eq(rows[1].deliveries, C.DAY_MAX, "the advertised overall daily cap is enforced")
	eq(rows[1].points, C.DAY_MAX * C.Score(1, 0))
	eq(rows[1].customers, C.DAY_MAX)
end)

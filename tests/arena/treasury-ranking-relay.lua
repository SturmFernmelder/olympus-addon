local H = ...
local test, eq, World = H.test, H.eq, H.World

local function Client(w, name)
	local c = w:Client(name)
	w:As(c, function()
		local allowed = {}
		c.rankAllowed = allowed
		c.ns.Bank = {
			DirectoryViewer = function(who) return allowed[c.ns.Fold(c.ns.FullName(who))] == true end,
			SeesSisters = function() return true end,
			LordOrCaptain = function(who, guild)
				return c.ns.Fold(c.ns.FullName(who)) == c.ns.Fold("Aster Officer-Emberfall") and guild == "Olympus Ash"
			end,
			Current = function() return nil end,
			Own = function() return nil end,
			Sisters = function() return {} end,
			PriceAsks = function() end,
			Index = function() return { units = 0, stacks = 0 } end,
			Value = function() return { value = 0, pending = 0, unpriced = 0 } end,
			Correspondent = function() end,
			SISTER_OLD = 7 * 86400,
		}
	end)
	return c
end

test("treasury ranking relay: two distinct authorized holders make a dated numeric row durable without exposing a bank", function()
	local w = World.New({ compliance = "shipped" })
	local late = Client(w, "Quillon Scribe")
	local first = "Brannoc Weald-Emberfall"
	local second = "Idris Vane-Emberfall"
	w:As(late, function()
		late.rankAllowed[late.ns.Fold(first)] = true
		late.rankAllowed[late.ns.Fold(second)] = true
		local row = { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock - 20,
			money = 120000, units = 41, stacks = 12, value = 33000, pending = 2, unpriced = 1,
			total = 153000, level = 57, correspondent = "Cora Ledger-Emberfall", home = false }
		local wire = assert(late.ns.Treasury.RankRelayWire(row))
		local ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", "Stranger-Emberfall", wire)
		eq(ok, false); eq(why, "access", "an unauthorized holder cannot witness a row")
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, wire)
		eq(ok, true); eq(why, "witness")
		eq(#late.ns.Treasury.RelayedRanking(), 0, "one holder is not consensus")
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, wire)
		eq(ok, true); eq(why, "witness")
		eq(#late.ns.Treasury.RelayedRanking(), 0, "repeating one identity is still one witness")
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", second, wire)
		eq(ok, true); eq(why, "accepted")
		local rows = late.ns.Treasury.RelayedRanking()
		eq(#rows, 1); eq(rows[1].guild, "Olympus Ash"); eq(rows[1].total, 153000)
		local ranking = late.ns.Treasury.Ranking()
		eq(#ranking.rows, 1, "the accepted total appears without a local bank snapshot")
		eq(ranking.rows[1].guild, "Olympus Ash"); eq(ranking.rows[1].relay, true)
		eq(late.rdb.treasuryRankRelay.rows[late.ns.Fold("Olympus Ash")][wire].accepted, true,
			"the accepted row is saved for later logins and relays")
	end)
end)

test("treasury ranking relay: malformed totals and a sender without source authority fail closed", function()
	local w = World.New({ compliance = "shipped" })
	local late = Client(w, "Quillon Scribe")
	local first = "Brannoc Weald-Emberfall"
	w:As(late, function()
		late.rankAllowed[late.ns.Fold(first)] = true
		local row = { guild = "Olympus Ash", by = "Aster Officer-Emberfall", t = w.clock,
			money = 100, units = 1, stacks = 1, value = 20, pending = 0, unpriced = 0,
			total = 120, level = 60, home = false }
		local wire = assert(late.ns.Treasury.RankRelayWire(row))
		local forged = wire:gsub("~120~60~", "~999~60~", 1)
		local ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, forged)
		eq(ok, false); eq(why, "shape")
		late.ns.Bank.LordOrCaptain = function() return false end
		ok, why = late.ns.Treasury.HandleRankRelay("WHISPER", first, wire)
		eq(ok, false); eq(why, "source")
	end)
end)

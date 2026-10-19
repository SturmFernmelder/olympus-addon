local ns, test, eq, h = ...
-- The treasury's relays (TD-07): what the Treasurer's client passes on, as the army takes it.

test("1.0 the Treasurer's mail character's book passed on again unchanged: its week moves on with each relay; its own book as new still stays", function()
	h.WithThrone(function(w)
		local T = ns.Treasury
		local mail = h.MailWorld()
		local saved = { split = ns.splitNames, inGuild = IsInGuild, chunked = ns.Comm.SendChunked }
		local ok, err = pcall(function()
			ns.splitNames = true
			ns.Comm.SendChunked = function(msg) w.sent[#w.sent + 1] = { dist = "CHANNEL", msg = msg } end
			local function Relayed()
				local out = {}
				for _, s in ipairs(w.sent) do if s.msg:sub(1, 3) == "TR~" then out[#out + 1] = s.msg end end
				return out
			end
			ns.db.myCharacters = { [h.TREASURER_KEY] = true, [h.ANDARAI_KEY] = true }
			ns.db.keeperShares = { [h.TREASURER_KEY] = true, [h.ANDARAI_KEY] = true }
			ns.rdb.treasuryFlags = { balance = true, ranking = true, book = true, at = 1 }
			-- A gift to his mail character, which then stops playing: its book never changes again.
			h.AsAndarai(nil)
			mail.gold = 400000
			T.OpenBook()
			w.clock = w.clock + 10
			T.Record("Generous Donor", 50000, "mail", nil, { quiet = true })
			local changed = w.clock
			-- The Treasurer's client passes it on that day...
			w.clock = w.clock + 600
			h.AsTreasurer(); IsInGuild = saved.inGuild
			local treasurer = ns.me
			mail.gold = 1000000
			w.sent = {}
			T.Share(true)
			local first = Relayed()[1]
			assert(first and first:find("~TB~1%.0~Olympus~400000~450000~50000~0~50000~1~~"), tostring(first))
			-- ...and again eight days later: the same book, the same date, its week now empty.
			w.clock = w.clock + 8 * 86400
			w.sent = {}
			T.Share(true)
			local later = Relayed()[1]
			assert(later and later:find("~TB~1%.0~Olympus~400000~450000~50000~0~0~0~~"), tostring(later))
			eq(later:match("^TR~[^~]*~(%d+)~"), tostring(changed), "dated when its book last changed, as before")
			-- A soldier who took the first copy takes the second in its place.
			ns.db.myCharacters = {}
			h.AsSoldier()
			T.HandleRelay("CHANNEL", treasurer, first)
			eq(T.Report().week, 50000)
			T.HandleRelay("CHANNEL", treasurer, later)
			local r = T.Report()
			eq(r.week, 0, "the week the Treasurer's client counts now, not the one it first sent")
			eq(r.donors, 0); eq(r.balance, 450000); eq(#r.keepers, 1)
			eq(r.keepers[1].t, changed, "still as of when its book changed")
			-- Its own book, when it comes, stays over a copy passed on as new (or older).
			T.HandleReport("CHANNEL", h.ANDARAI, (later:gsub("^TR~[^~]*~%d+~", ""):gsub("~450000~50000~0~0~0~", "~470000~70000~0~0~0~")))
			eq(T.Report().balance, 470000)
			local heard = w.clock
			T.HandleRelay("CHANNEL", treasurer, (later:gsub("^(TR~[^~]*~)%d+", "%1" .. heard)))
			eq(T.Report().balance, 470000, "a copy as new as its own book")
			T.HandleRelay("CHANNEL", treasurer, later)
			eq(T.Report().balance, 470000, "an older copy")
			-- A newer copy replaces it, as before.
			w.clock = w.clock + 60
			T.HandleRelay("CHANNEL", treasurer, (later:gsub("^(TR~[^~]*~)%d+", "%1" .. w.clock):gsub("~450000~50000~0~0~0~", "~480000~80000~0~0~0~")))
			eq(T.Report().balance, 480000)
		end)
		mail.Restore()
		ns.splitNames, IsInGuild, ns.Comm.SendChunked = saved.split, saved.inGuild, saved.chunked
		if not ok then error(err, 0) end
	end)
end)

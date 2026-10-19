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

test("1.0 the early supporters from two of the Treasurer's characters: each one's pieces put together apart, never one's filling the other's gaps", function()
	h.WithThrone(function(w)
		local T = ns.Treasury
		local saved = { split = ns.splitNames, after = ns.After, inGuild = IsInGuild, archive = ns.rdb.treasuryArchive, early = ns.rdb.treasuryEarly }
		local ok, err = pcall(function()
			ns.splitNames = true
			local timers = {}
			ns.After = function(_, _, fn) timers[#timers + 1] = fn end
			local function RunTimers() while #timers > 0 do table.remove(timers, 1)() end end
			local function Pieces()
				local out = {}
				for _, s in ipairs(w.sent) do if s.msg:sub(1, 3) == "TE~" then out[#out + 1] = s.msg end end
				return out
			end
			local function Early() local l = T.EarlySupporters() return l and table.concat(l.names, ",") end
			-- 0.9's book on his account, read by both his characters: fifteen names of 21 letters.
			local names, lines = {}, {}
			for i = 1, 15 do names[i] = "Supporter " .. string.char(96 + i, 96 + i) .. "longnamex" end
			for i, n in ipairs(names) do lines[i] = { name = n, money = 10, how = "mail", t = w.clock - 1000 } end
			ns.rdb.treasuryArchive = { ["0.9"] = { lines = lines, closed = w.clock - 500 } }
			ns.rdb.treasuryFlags = { ranking = true, at = w.clock - 1 }
			ns.db.myCharacters = { [h.TREASURER_KEY] = true, [h.ANDARAI_KEY] = true }
			ns.db.keeperShares = { [h.TREASURER_KEY] = true, [h.ANDARAI_KEY] = true }
			-- The Treasurer in <Olympus> sends the list; later his mail character, in a guild of a
			-- longer name, sends the same list: as many pieces, cut elsewhere.
			h.AsTreasurer(); IsInGuild = saved.inGuild
			local treasurer = ns.me
			w.sent = {}
			eq(T.SendEarly(true), true); RunTimers()
			local his = Pieces()
			h.AsAndarai("Olympus Zeus")
			w.clock = w.clock + T.EARLY_GAP
			w.sent = {}
			eq(T.SendEarly(true), true); RunTimers()
			local its = Pieces()
			eq(#his, 2); eq(#its, 2, "as many pieces")
			assert(his[1] ~= its[1]:gsub("~Olympus Zeus~", "~Olympus~"), "cut elsewhere: " .. his[1] .. " / " .. its[1])
			-- A soldier hears its first piece (its sending cut short), then his second: no list yet.
			h.AsSoldier()
			T.HandleEarly("CHANNEL", h.ANDARAI, its[1])
			T.HandleEarly("CHANNEL", treasurer, his[2])
			eq(Early(), nil, "one's piece never completes the other's list")
			-- Either one's list, once all its own pieces are in, every name.
			T.HandleEarly("CHANNEL", treasurer, his[1])
			eq(Early(), table.concat(names, ","))
			T.HandleEarly("CHANNEL", h.ANDARAI, its[2])
			eq(Early(), table.concat(names, ","), "the same list again changes nothing")
		end)
		ns.splitNames, ns.After, IsInGuild = saved.split, saved.after, saved.inGuild
		ns.rdb.treasuryArchive, ns.rdb.treasuryEarly = saved.archive, saved.early
		if not ok then error(err, 0) end
	end)
end)

test("1.0 the early supporters: an ask inside EARLY_GAP is answered once the gap is over, not at the asker's next ask; once a gap still", function()
	h.WithThrone(function(w)
		local T = ns.Treasury
		local saved = { split = ns.splitNames, after = ns.After, inGuild = IsInGuild, archive = ns.rdb.treasuryArchive, early = ns.rdb.treasuryEarly }
		local ok, err = pcall(function()
			ns.splitNames = true
			local timers = {}
			ns.After = function(seconds, _, fn) timers[#timers + 1] = { at = w.clock + seconds, fn = fn } end
			local function RunDue()
				local due = timers
				timers = {}
				for _, t in ipairs(due) do if t.at <= w.clock then t.fn() else timers[#timers + 1] = t end end
			end
			local function Pieces()
				local out = {}
				for _, s in ipairs(w.sent) do if s.msg:sub(1, 3) == "TE~" then out[#out + 1] = s.msg end end
				return out
			end
			ns.rdb.treasuryArchive = { ["0.9"] = { lines = { { name = "Alice Early", money = 100, how = "mail", t = w.clock - 1000 } }, closed = w.clock - 500 } }
			ns.rdb.treasuryFlags = { ranking = true, at = w.clock - 1 }
			ns.db.myCharacters = { [h.TREASURER_KEY] = true }
			ns.db.keeperShares = { [h.TREASURER_KEY] = true }
			h.AsTreasurer(); IsInGuild = saved.inGuild
			-- An ask answered at once.
			w.sent = {}
			T.HandleEarlyAsk("CHANNEL", "Early Bird-Realm", "TQ~0")
			eq(#Pieces(), 1)
			-- A late login asks 100 seconds later: nothing yet (EARLY_GAP), its answer when the gap is over.
			w.clock = w.clock + 100
			w.sent = {}
			T.HandleEarlyAsk("CHANNEL", "Late Login-Realm", "TQ~0")
			T.HandleEarlyAsk("CHANNEL", "Later Login-Realm", "TQ~0")
			eq(#Pieces(), 0, "EARLY_GAP apart")
			w.clock = w.clock + T.EARLY_GAP - 100 - 1
			RunDue()
			eq(#Pieces(), 0, "not before the gap is over")
			w.clock = w.clock + 1
			RunDue()
			eq(#Pieces(), 1, "answered once the gap is over, once however many asked")
			w.clock = w.clock + T.EARLY_GAP - 30
			RunDue()
			eq(#Pieces(), 1, "and only then")
			-- The list sent meanwhile by his own sending: the waiting answer sends nothing more.
			w.clock = w.clock + 10
			w.sent = {}
			T.HandleEarlyAsk("CHANNEL", "Late Login-Realm", "TQ~0")
			eq(#Pieces(), 0)
			w.clock = w.clock + 20
			T.SendEarly(true)
			eq(#Pieces(), 1, "his own sending, forced")
			w.clock = w.clock + T.EARLY_GAP
			RunDue()
			eq(#Pieces(), 1, "nothing more: the list went out inside that gap")
			-- An ask inside the next gap waits again; his no meanwhile: it sends nothing.
			w.sent = {}
			T.SendEarly(true)
			w.clock = w.clock + 10
			T.HandleEarlyAsk("CHANNEL", "Late Login-Realm", "TQ~0")
			eq(#Pieces(), 1)
			ns.db.keeperShares = { [h.TREASURER_KEY] = false }
			w.clock = w.clock + T.EARLY_GAP
			RunDue()
			eq(#Pieces(), 1, "his no: nothing more")
		end)
		ns.splitNames, ns.After, IsInGuild = saved.split, saved.after, saved.inGuild
		ns.rdb.treasuryArchive, ns.rdb.treasuryEarly = saved.archive, saved.early
		if not ok then error(err, 0) end
	end)
end)

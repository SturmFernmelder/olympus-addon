-- 1.2.4, the role rooms the author asked for on the Chat page (ChatRooms.lua), over the real file in
-- tests/chat-rooms.lua's fixture (WithRooms). His words, voice-transcribed: "Eu acho que esses roles
-- aqui estão bagunçados. A gente me ajuda a repensar quais são todos os chats de função que
-- precisam"; on the set proposed: "Sobre as salas, eu concordo com todas as que você colocou. Só que
-- a gente precisa também de uma só dos Guild Masters". Every name here is invented.
local ns, test, eq, WithRooms, RoomMessage = ...

local GUILD_B = "Olympus III"

-- Two guilds of the army as the room checks read them: ours (the fixture's "Olympus II", from our
-- fresh roster) and GUILD_B (from the census, which the rooms never take, or from the author's
-- signed leadership list once it counts: w.enforced). Each with its master, an officer, a named
-- centurion and its Department of War correspondent. Returns the cast's names.
local function Guilds(w, R, c)
	local A, B = w.guild, GUILD_B
	local cast = {
		aMaster = "Ash Holt-Realm", aOfficer = "Bram Holt-Realm", aCenturion = "Cass Holt-Realm", aWar = "Dain Holt-Realm",
		aMember = "Member-Realm",
		bMaster = "Ezra Fenn-Realm", bOfficer = "Fala Fenn-Realm", bCenturion = "Gale Fenn-Realm", bWar = "Hale Fenn-Realm",
	}
	w.ranks = {
		[A] = { [cast.aMaster] = 0, [cast.aOfficer] = 1, [cast.aCenturion] = 3, [cast.aWar] = 3, [cast.aMember] = 3 },
		[B] = { [cast.bMaster] = 0, [cast.bOfficer] = 1, [cast.bCenturion] = 3, [cast.bWar] = 3 },
	}
	w.lists = {
		[A] = { by = cast.aMaster, entries = { { name = cast.aCenturion, role = "centurion" },
			{ name = cast.aWar, role = "correspondent", dept = "Department of War" } } },
		[B] = { by = cast.bMaster, entries = { { name = cast.bCenturion, role = "centurion" },
			{ name = cast.bWar, role = "correspondent", dept = "Department of War" } } },
	}
	c.rdb.guilds = { [B] = { leader = "Ezra Fenn", officers = { { name = "Fala Fenn" } } } }
	c.Data = setmetatable({
		Guild = function(g) return c.rdb.guilds[g] end,
		AuthorizedRank = function(name, guild)
			local rank = (w.ranks[guild] or {})[c.FullName(name)]
			if guild == w.guild then return rank, rank ~= nil and "roster" or nil end
			if w.enforced then return rank, rank ~= nil and "signed" or "enforced" end
			return rank, rank ~= nil and "census" or nil
		end,
	}, { __index = ns.Data })
	c.Authority = { Enforced = function() return w.enforced == true end, Manifest = function() return nil end }
	c.Roster.members = {}
	for name in pairs(w.ranks[A]) do c.Roster.members[#c.Roster.members + 1] = { name = name } end
	c.Roster.Fresh = function() return c.Roster end
	c.Roster.RankOf = function(name) return w.ranks[w.guild] and w.ranks[w.guild][c.FullName(name)] end
	c.Nominees = setmetatable({
		ListOf = function(guild) return w.lists[guild] end,
		RoleOf = function(name, guild)
			for _, e in ipairs(w.lists[guild] and w.lists[guild].entries or {}) do
				if c.FullName(e.name) == c.FullName(name) then return e.role, e.dept end
			end
		end,
		Proven = function(name, guild) return (w.ranks[guild] or {})[c.FullName(name)] == 0 end,
	}, { __index = ns.Nominees })
	local isFederation = c.IsFederation
	c.IsFederation = function(g) return g == A or g == B or isFederation(g) end
	return cast, R.GuildRoom("gcorr", A), R.GuildRoom("gcent", A), R.GuildRoom("gcorr", B), R.GuildRoom("gcent", B)
end

local function Ids(list)
	local out = {}
	for _, e in ipairs(list) do out[#out + 1] = e.id end
	return table.concat(out, ",")
end

local function Targets(w)
	local out = {}
	for _, job in ipairs(w.jobs) do out[#out + 1] = job.target end
	table.sort(out)
	return table.concat(out, ",")
end

-- "um com o guild master e os correspondentes ... um só com centuriões ... Mesma coisa para a guilda
-- principal": each guild's master with his correspondents, and with his centurions.
test("chat rooms (1.2.4): each guild has its master's room with his correspondents and with his centurions; nobody of another guild is in them, sent to or heard", function()
	WithRooms(function(w, R, c)
		local cast, aCorr, aCent, bCorr, bCent = Guilds(w, R, c)
		-- The ids: the guild's key, never its name (a moderator's reference carries 24 bytes of [%w:_]).
		for _, id in ipairs({ aCorr, aCent, bCorr, bCent }) do
			assert(id:match("^g[a-z]+:%x+$") and #id == 18, id)
			assert(id:match("^[%w:_]+$") and #id <= 24, "a moderator's reference holds it: " .. id)
		end
		assert(aCorr ~= bCorr and aCent ~= bCent and aCorr:sub(7) == aCent:sub(7))
		eq(R.GuildRoom("gcent", "OLYMPUS II"), aCent, "the guild's folded name")
		eq(R.Info(aCorr).label, "Master & Correspondents"); eq(R.Info(aCent).label, "Master & Centurions")
		eq(R.Info(aCent).guild, w.guild)
		eq(R.Info(bCent).label, GUILD_B .. ": Master & Centurions", "another guild's: its name")
		eq(R.Info("gcent:000000000000"), nil, "a key of no guild this client lists")
		eq(R.Info("gcent:" .. ("f"):rep(13)), nil); eq(R.Info("gcorr:Olympus II"), nil, "never by name")
		-- Who is in our guild's two rooms.
		local function In(id, name) return R.CanAccess(id, name) end
		eq(In(aCorr, cast.aMaster), true); eq(In(aCorr, cast.aWar), true)
		eq(In(aCorr, cast.aOfficer), false); eq(In(aCorr, cast.aCenturion), false); eq(In(aCorr, cast.aMember), false)
		eq(In(aCent, cast.aMaster), true); eq(In(aCent, cast.aOfficer), true); eq(In(aCent, cast.aCenturion), true)
		eq(In(aCent, cast.aWar), false); eq(In(aCent, cast.aMember), false)
		for _, b in ipairs({ cast.bMaster, cast.bOfficer, cast.bCenturion, cast.bWar }) do
			eq(In(aCorr, b), false, b); eq(In(aCent, b), false, b)
		end
		-- Another guild's rooms on our client: its census is never taken.
		eq(In(bCent, cast.bMaster), false, "a census guild master"); eq(In(bCorr, cast.bWar), false)
		-- Our own master's list cannot put one of ours in another guild's room, nor theirs one of ours in it.
		w.lists[GUILD_B].entries[#w.lists[GUILD_B].entries + 1] = { name = cast.aOfficer, role = "centurion" }
		w.enforced = true
		eq(In(bCent, cast.bMaster), true, "with the signed list: that guild's master")
		eq(In(bCent, cast.bCenturion), true)
		eq(In(bCent, cast.aOfficer), false, "a member of our guild is in no other guild's room")
		-- The menu lists our guild's rooms alone (a member of ours, whatever the signed list says).
		c.me = cast.aMaster
		eq(Ids(R.Options("role")), "masters,allcenturions," .. aCorr .. "," .. aCent)
		c.me = cast.aWar
		eq(Ids(R.Options("role")), "dept:war," .. aCorr)
		-- A line: one logged whisper to each member of the room, nobody else.
		eq(R.Send(aCorr, "the war report is due"), true)
		eq(Targets(w), cast.aMaster)
		for _, job in ipairs(w.jobs) do eq(job.dist, "WHISPER"); eq(job.logged, true) end
		w.clearJobs(); w.advance(2)
		c.me = cast.aCenturion
		eq(R.Send(aCent, "patrol at eight"), true)
		eq(Targets(w), table.concat({ cast.aMaster, cast.aOfficer }, ","))
		-- Heard: from the room's members alone.
		eq(R.Receive("WHISPER", cast.aOfficer, RoomMessage(aCent, 1, "on my way"), 2000), true)
		eq(R.Receive("WHISPER", cast.bMaster, RoomMessage(aCent, 2, "may I join"), 2001), false)
		eq(R.Stats().dropped.audience, 1)
		eq(R.Receive("WHISPER", cast.aOfficer, RoomMessage(bCent, 3, "wrong room"), 2002), false, "a room this character is not in")
		eq(R.Receive("WHISPER", cast.aOfficer, RoomMessage("gcent:000000000000", 4, "no such room"), 2003), false)
		-- (Changed with the silent send's fix, the author: "Eu dou Enter para enviar a mensagem na igreja
		-- e não aparece a mensagem": our own line is in the room at Enter, pending until its whispers
		-- leave, before the line heard after it.)
		local kept = R.History(aCent)
		eq(#kept, 2); eq(kept[1].text, "patrol at eight"); eq(kept[1].mine, true); eq(kept[2].text, "on my way")
		-- A 150-byte line in a guild's room still fits one whisper.
		w.clearJobs(); w.advance(2)
		local long = ("x"):rep(R.TEXT_MAX)
		eq(R.Send(aCent, long), true)
		for _, job in ipairs(w.jobs) do assert(#job.msg <= 255, #job.msg) end
	end)
end)

-- "Mesma coisa para a guilda principal": the King's own guild's master is the King (Core.lua's pin),
-- and its centurions are the list the King and the High Council name (Nominees.lua). It has no
-- correspondents (Nominees.lua), so no master-and-correspondents room.
test("chat rooms (1.2.4): the King's guild's centurions sit with the King in its room; it has no correspondents' room", function()
	WithRooms(function(w, R, c)
		local cast = Guilds(w, R, c)
		local KG = "Olympus"
		w.king = "Crown Rook-Realm"
		w.council["sage rook-realm"] = true
		w.lists[KG] = { by = "Sage Rook-Realm", entries = { { name = "Iris Rook-Realm", role = "centurion" } } }
		local cent, corr = R.GuildRoom("gcent", KG), R.GuildRoom("gcorr", KG)
		eq(R.Info(corr), nil, "no correspondents' room for the King's guild")
		eq(R.Info(cent).label, KG .. ": Master & Centurions")
		eq(R.CanAccess(cent, w.king), true, "the King, its master, without the signed list")
		eq(R.CanAccess(cent, "Iris Rook-Realm"), true, "a centurion of the King's and the High Council's naming")
		eq(R.CanAccess(cent, cast.bMaster), false)
		eq(R.CanAccess("allcenturions", "Iris Rook-Realm"), true)
		eq(R.CanAccess("masters", w.king), true); eq(R.CanAccess("allcenturions", w.king), true)
	end)
end)

-- The departments come from one list (Nominees.DEPARTMENT_LIST): its names are the correspondents'
-- roles, its rooms the Chat page's, its labels the menu's. One more line there is one more room.
test("chat rooms (1.2.4): a department is one line of Nominees.DEPARTMENT_LIST: its room, its label (English until translated) and its correspondents follow", function()
	local N = ns.Nominees
	eq(#N.DEPARTMENT_LIST, 6); eq(N.MAX_DEPTS, #N.DEPARTMENT_LIST)
	eq(ns.DEPARTMENT_LIST, N.DEPARTMENT_LIST)
	for i, d in ipairs(N.DEPARTMENT_LIST) do eq(N.DEPARTMENTS[i], d.name) end
	WithRooms(function(w, R, c)
		for _, d in ipairs(N.DEPARTMENT_LIST) do
			local info = R.Info(d.room)
			eq(info.label, d.name, d.room); eq(info.kind, "department"); eq(info.group, "dept")
		end
		eq(R.Info("dept:citizenry").label, "Association of Artisanry", "the room keeps its old id")
	end)
	WithRooms(function(w, R, c)
		local list = {}
		for i, d in ipairs(N.DEPARTMENT_LIST) do list[i] = d end
		list[#list + 1] = { name = "Department of Lore", room = "dept:lore", aliases = { "lore" }, label = "CHATROOM_DEPT_LORE" }
		c.Nominees = setmetatable({ DEPARTMENT_LIST = list }, { __index = ns.Nominees })
		eq(R.Info("dept:lore").label, "Department of Lore", "no label yet: its English name")
		local me = c.me:lower()
		w.council[me], w.departments[me] = true, "Lore"
		eq(R.CanAccess("dept:lore"), true, "a councillor whose signed title names it")
		eq(R.Options("department")[1].id, "dept:lore")
		local ids = {}
		for _, option in ipairs(R.Options("role")) do ids[#ids + 1] = option.id end
		eq(table.concat(ids, ","), "council,dept:lore")
	end)
end)

-- 1.2.3's treasurers', all departments' and one guild's centurions' rooms are gone: a line an older
-- client still sends to one is dropped without a word to the player and said once a session.
test("chat rooms (1.2.4): an older client's line to the treasurers', the departments' or the centurions' room is dropped quietly and said once a session", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.departments[me] = true, "Federal Treasury"
		for _, id in ipairs({ "treasurers", "departments", "centurions" }) do eq(R.Info(id), nil, id); eq(R.CanAccess(id), false, id) end
		local lines = { RoomMessage("treasurers", 1, "the ledger"), RoomMessage("departments", 2, "all hands"),
			RoomMessage("centurions", 3, "patrol"), RoomMessage("treasurers", 4, "again") }
		for i, line in ipairs(lines) do
			local ok, why = R.Receive("WHISPER", "Peer " .. i .. "-Realm", line, 1000 + i)
			eq(ok, false, line); eq(why, "retired", line)
		end
		eq(R.Stats().dropped.retired, #lines); eq(R.Stats().shown, 0)
		eq(#R.KeptRooms(), 0, "nothing kept")
		for _, e in ipairs(w.events) do assert(e[1] ~= "CHAT_ROOM_LINE" and e[1] ~= "CHAT_ROOM_CHANGED", tostring(e[1])) end
		eq(w.printed, nil, "not a word to the player")
		eq(#w.logs, 1, "said once a session"); assert(w.logs[1]:find("treasurers room", 1, true), w.logs[1])
		assert(not w.logs[1]:find("ledger", 1, true) and not w.logs[1]:find("Peer", 1, true), w.logs[1])
		-- (The race and class rooms' word is its own, as before.)
		eq(select(2, R.Receive("CHANNEL", "Peer-Realm", RoomMessage("race:1", 5, "old"), 1010)), "retired")
		eq(#w.logs, 2)
		R.Reset()
		eq(select(2, R.Receive("WHISPER", "Peer-Realm", RoomMessage("centurions", 6, "next session"), 1011)), "retired")
		eq(#w.logs, 3, "said again the next session")
		-- Its room is the Federal Treasury's now.
		w.council["peer-realm"], w.departments["peer-realm"] = true, "Federal Treasury"
		eq(R.Receive("WHISPER", "Peer-Realm", RoomMessage("dept:treasury", 7, "here now"), 1012), true)
	end)
end)

local function Has(list, name)
	for _, n in ipairs(list) do if n:lower() == name:lower() then return true end end
	return false
end

-- "Em relação à minha visão de suas outras salas, deixa fora a do High Council. Todas as outras, eu
-- preciso estar. Eu preciso poder ver e, se precisar, mandar mensagem como desenvolvedor".
test("chat rooms (1.2.4): the author is in every room but the High Council's: listed for him, a recipient only while his presence is heard, heard as a sender", function()
	WithRooms(function(w, R, c)
		local cast, aCorr, aCent, bCorr, bCent = Guilds(w, R, c)
		c.ApprovedGuilds = function() return {} end
		w.authorName = "Quill Wright-Realm"
		local author = w.authorName
		local kingCent = R.GuildRoom("gcent", "Olympus")
		-- His own menu: every room but the High Council's and the Secretariat's; each guild's rooms
		-- (his own, the King's, then the others this client knows of).
		c.me = author
		eq(R.CanAccess("council"), false, "never the High Council's by his name"); eq(R.CanAccess("secretariat"), false)
		eq(Ids(R.Options("role")), table.concat({ "masters", "allcenturions", "dept:treasury", "dept:war", "dept:justice", "dept:citizenry",
			"dept:heritage", "dept:church", aCorr, bCorr, aCent, kingCent, bCent }, ","))
		for _, id in ipairs({ "masters", "allcenturions", "dept:justice", aCorr, aCent, bCorr, bCent }) do eq(R.CanAccess(id), true, id) end
		-- His own guild's rooms reach its people; another guild's, only once the signed list counts.
		eq(table.concat(R.Recipients(aCent), ","), table.concat({ cast.aMaster, cast.aOfficer, cast.aCenturion }, ","))
		eq(#R.Recipients(bCent), 0, "another guild's census is never taken")
		w.enforced = true
		eq(table.concat(R.Recipients(bCent), ","), table.concat({ cast.bMaster, cast.bOfficer, cast.bCenturion }, ","))
		w.enforced = false
		-- Another member's client: he is a recipient while his presence is heard, never of the High Council's.
		c.me = cast.aMaster
		w.council[c.me:lower()] = true
		c.rdb.council.names = { ["ash holt"] = "Ash Holt" }
		w.authorOnline = false
		for _, id in ipairs({ "masters", "allcenturions", aCorr, aCent }) do eq(Has(R.Recipients(id), author), false, id) end
		w.authorOnline = true
		for _, id in ipairs({ "masters", "allcenturions", aCorr, aCent }) do eq(Has(R.Recipients(id), author), true, id) end
		w.departments[c.me:lower()] = "Department of War"
		eq(Has(R.Recipients("dept:war"), author), true)
		eq(Has(R.Recipients("council"), author), false, "not the High Council's")
		eq(R.Send(aCent, "the dev may read this"), true)
		local whispered = false
		for _, job in ipairs(w.jobs) do if job.target == author then whispered = true end end
		eq(whispered, true, "one logged whisper to him too")
		-- His lines are heard as any member's; not in the High Council.
		eq(R.Receive("WHISPER", author, RoomMessage(aCent, 1, "a word from the dev"), 3000), true)
		eq(R.Receive("WHISPER", author, RoomMessage("masters", 2, "to the masters"), 3001), true)
		eq(R.Receive("WHISPER", author, RoomMessage("council", 3, "not here"), 3002), false)
		eq(R.Stats().dropped.audience, 1)
		-- A preview of his is a preview: his own rooms stay closed under it.
		c.me = author
		c.ViewAs = { Previewing = function() return true end, Role = function() return "officer" end }
		eq(Ids(R.Options("role")), "allcenturions," .. aCent)
		eq(R.Select(aCent), false); eq(#R.History(aCent), 0)
	end)
end)

-- 1.2.4 ("Não, não bota limite de 12 salas por pessoa"): no room is let go for another (1.2.3 dropped
-- the least recently used room's whole history at the thirteenth). Every room's lines together are
-- bounded instead (LINES_TOTAL), the oldest of all going first, each room keeping its newest.
test("chat rooms (1.2.4): forty rooms keep their lines: no room is let go, LINES_TOTAL lines in all, the oldest of every room first, each room its newest", function()
	WithRooms(function(w, R, c)
		eq(R.ROOMS_MAX, nil, "no cap on rooms")
		c.ApprovedGuilds = function() return {} end
		w.authorName, c.me = "Quill Wright-Realm", "Quill Wright-Realm"
		w.enforced = true
		c.rdb.guilds = {}
		local ranks, rooms, leads = {}, {}, {}
		for i = 1, 20 do
			local guild, lead = "Olympus " .. (i + 10), "Lead" .. string.char(64 + i) .. " Holt-Realm"
			c.rdb.guilds[guild] = { leader = lead }
			ranks[guild] = { [lead] = 0 }
			for _, prefix in ipairs({ "gcorr", "gcent" }) do rooms[#rooms + 1], leads[#leads + 1] = R.GuildRoom(prefix, guild), lead end
		end
		c.Data = setmetatable({ Guild = function(g) return c.rdb.guilds[g] end,
			AuthorizedRank = function(name, guild)
				local rank = (ranks[guild] or {})[c.FullName(name)]
				return rank, rank ~= nil and "signed" or "enforced"
			end }, { __index = ns.Data })
		c.Authority = { Enforced = function() return true end, Manifest = function() return nil end }
		local isFederation = c.IsFederation
		c.IsFederation = function(g) return c.rdb.guilds[g] ~= nil or isFederation(g) end
		eq(#rooms, 40)
		local t = 1000
		for k = 1, 40 do
			t = t + 61
			for j, id in ipairs(rooms) do
				assert(R.Receive("WHISPER", leads[j], RoomMessage(id, k, "line " .. k), t), id .. " " .. k)
			end
		end
		eq(R.KeptLines(), R.LINES_TOTAL, "1600 lines came, 1200 kept")
		eq(#R.KeptRooms(), 40, "no room let go")
		for _, id in ipairs(rooms) do
			local h = R.History(id)
			eq(#h, 30, id); eq(h[1].text, "line 11", id .. ": the oldest went first"); eq(h[30].text, "line 40", id)
		end
		-- A room quiet since its first line keeps it, however many lines the others bring.
		R.Reset()
		eq(R.KeptLines(), 0)
		t = t + 61
		assert(R.Receive("WHISPER", leads[1], RoomMessage(rooms[1], 1, "the only line"), t))
		for k = 1, 40 do
			t = t + 61
			for j = 2, #rooms do assert(R.Receive("WHISPER", leads[j], RoomMessage(rooms[j], k, "line " .. k), t)) end
		end
		eq(R.KeptLines(), R.LINES_TOTAL)
		eq(#R.History(rooms[1]), 1, "its newest, its only line, kept"); eq(R.History(rooms[1])[1].text, "the only line")
		eq(#R.KeptRooms(), 40)
		-- Each room still its own HISTORY at most.
		R.Reset(); R.LINES_TOTAL = 10000
		for k = 1, R.HISTORY + 5 do t = t + 61; assert(R.Receive("WHISPER", leads[1], RoomMessage(rooms[1], k % 10000, "l" .. k), t)) end
		eq(#R.History(rooms[1]), R.HISTORY); eq(R.KeptLines(), R.HISTORY)
	end)
end)

-- A room's lines go as one whisper to each member (1.2 s apart, Comm's queue holding 60): FANOUT a
-- line at most, the author, the King, the High Council and the guild masters first, then those who
-- wrote in the room in the last ten minutes, then the others by name; the sender is told how many.
test("chat rooms (1.2.4): a line goes to FANOUT members at most, the author, the King and those heard lately first, and the sender is told how many it missed", function()
	WithRooms(function(w, R, c)
		eq(R.FANOUT, 40)
		w.authorName, w.authorOnline = "Quill Wright-Realm", true
		local names = { w.king }
		for i = 1, 50 do names[#names + 1] = ("Tester %02d-Realm"):format(i) end
		local left = 3
		assert(R.RegisterAudience("testers", { label = "Testers", CanAccess = function() return true end,
			Recipients = function() return names, left end }))
		-- Tester 50 wrote in the room lately: he goes before the testers he would follow by name.
		assert(R.Receive("WHISPER", "Tester 50-Realm", RoomMessage("testers", 1, "hello"), 1000))
		local list, missed = R.Recipients("testers")
		eq(#list, 40); eq(missed, 11 + left, "51 members, and the 3 the audience left out")
		eq(list[1], w.king, "the King first"); eq(list[2], "Tester 50-Realm", "heard lately")
		eq(list[3], "Tester 01-Realm"); eq(list[40], "Tester 38-Realm")
		-- The author when he is a member of the room: first of all.
		names[#names + 1] = w.authorName
		list = R.Recipients("testers")
		eq(list[1], w.authorName); eq(list[2], w.king)
		eq(R.Send("testers", "to all"), true)
		eq(#w.jobs, 40, "40 whispers")
		eq(w.printed, ns.L.CHATROOM_NOT_REACHED:format(12 + left, 40), "the sender is told")
		-- Nothing said under the share.
		w.clearJobs(); w.advance(2); w.printed = nil
		for i = #names, 30, -1 do names[i] = nil end
		left = 0
		eq(R.Send("testers", "to fewer"), true)
		eq(#w.jobs, 29); eq(w.printed, nil)
	end)
end)

-- "não precisa ficar atualizando a todo o tempo ... uma atualização mais lenta, de 1 minuto em 1
-- minuto": the census's notices check the rooms kept again once a minute at most; a room read or
-- picked is checked at once, its lines let go when it is no longer this character's.
test("chat rooms (1.2.4): the census's notices recheck the rooms kept once a minute at most; a room read or picked is checked at once and a room lost lets its lines go", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.council["peer-realm"], w.departments[me], w.departments["peer-realm"] = true, true, "Department of War", "Department of War"
		assert(R.Receive("WHISPER", "Peer-Realm", RoomMessage("council", 1, "council"), 1000))
		assert(R.Receive("WHISPER", "Peer-Realm", RoomMessage("dept:war", 2, "war"), 1001))
		local notice = assert(w.listeners.DATA_CHANGED, "the census's notice heard")
		notice()
		w.departments[me] = nil
		notice()
		eq(table.concat(R.KeptRooms(), ","), "council,dept:war", "a notice within the minute checks nothing")
		w.advance(R.REFRESH_EVERY)
		notice()
		eq(table.concat(R.KeptRooms(), ","), "council", "a minute later: the room lost, its lines gone")
		-- A room read is checked at once, whatever the minute.
		w.council[me] = nil
		eq(#R.History("council"), 0)
		eq(#R.KeptRooms(), 0, "discarded, not merely hidden")
		w.council[me] = true
		eq(#R.History("council"), 0, "nothing comes back")
		-- And a room picked.
		assert(R.Receive("WHISPER", "Peer-Realm", RoomMessage("council", 3, "again"), 1100))
		w.council[me] = nil
		eq(R.Select("council"), false); eq(#R.KeptRooms(), 0)
	end)
end)

-- How many a room reaches, for a page to show, without a census pass at every redraw.
test("chat rooms (1.2.4): a room's recipients counted for a page at most every RECIPIENTS_EVERY, and at once when it is picked or written in", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me] = true
		c.rdb.council.names = { member = "Member", alpha = "Alpha" }
		w.council["alpha-realm"] = true
		local n = R.RecipientCount("council")
		eq(n, 3, "the King, the Treasurer, Alpha")
		c.rdb.council.names.beta = "Beta"; w.council["beta-realm"] = true
		eq(R.RecipientCount("council"), 3, "not counted again yet")
		w.advance(R.RECIPIENTS_EVERY)
		eq(R.RecipientCount("council"), 4)
		c.rdb.council.names.gamma = "Gamma"; w.council["gamma-realm"] = true
		eq(R.Select("council"), true)
		eq(R.RecipientCount("council"), 5, "picked: counted at once")
		c.rdb.council.names.delta = "Delta"; w.council["delta-realm"] = true
		eq(R.Send("council", "hello"), true)
		eq(R.RecipientCount("council"), 6, "written in: counted at once")
		eq(R.RecipientCount("dept:war"), nil, "not a room of his")
	end)
end)

-- 1.2.4: until the author's signed leadership list counts (Authority.Enforced), another guild's ranks
-- come from the census alone, which the rooms never take: the rooms that reach other guilds reach
-- this character's own guild and the signed people (the King, the High Council's, the author) alone,
-- and the page says so over their lines; /oly status says whether the list counts.
test("chat rooms (1.2.4): without the signed leadership list each room reaches its own guild and the signed people, the page says so, and /oly status tells", function()
	WithRooms(function(w, R, c)
		local cast, aCorr, aCent, bCorr, bCent = Guilds(w, R, c)
		c.ApprovedGuilds = function() return {} end
		w.authorName, w.authorOnline = "Quill Wright-Realm", true
		local me = cast.aMaster
		c.me = me
		w.departments[me:lower()] = nil
		local NOTE = ns.L.CHATROOM_NEEDS_LEADERS
		-- The masters': our master (me), the King, the author; not another guild's census master.
		eq(table.concat(R.Recipients("masters"), ","), table.concat({ w.authorName, w.king }, ","))
		eq(R.StatusText("masters"), NOTE); eq(R.Info("masters").note, NOTE); eq(R.Info("masters").dim, nil)
		-- Every guild's masters and centurions: ours, the King's, the author.
		eq(table.concat(R.Recipients("allcenturions"), ","), table.concat({ w.authorName, w.king, cast.aOfficer, cast.aCenturion }, ","))
		eq(R.StatusText("allcenturions"), NOTE)
		-- A department's: its correspondent of ours, the author; not another guild's.
		c.me = cast.aWar
		eq(table.concat(R.Recipients("dept:war"), ","), w.authorName)
		eq(R.StatusText("dept:war"), NOTE)
		-- Our guild's own rooms, the High Council's: no note.
		eq(R.StatusText(aCorr), nil); eq(R.Info(aCorr).note, nil)
		w.council[cast.aWar:lower()] = true
		eq(R.StatusText("council"), nil)
		-- The author's list: another guild's rooms greyed, their note in the tooltip; ours and the King's not.
		c.me = w.authorName
		eq(R.Info(bCent).dim, true); eq(R.Info(bCent).note, NOTE); eq(R.StatusText(bCent), NOTE)
		eq(R.Info(aCent).dim, nil); eq(R.Info(R.GuildRoom("gcent", "Olympus")).dim, nil, "the King's guild: the pinned King and the signed list")
		-- Once the list counts: every guild's people, no note.
		w.enforced = true
		c.me = me
		eq(table.concat(R.Recipients("masters"), ","), table.concat({ w.authorName, w.king, cast.bMaster }, ","))
		eq(R.StatusText("masters"), nil); eq(R.Info("masters").note, nil)
		c.me = cast.aWar
		eq(table.concat(R.Recipients("dept:war"), ","), table.concat({ w.authorName, cast.bWar }, ","))
		c.me = w.authorName
		eq(R.Info(bCent).dim, nil); eq(R.StatusText(bCent), nil)
	end)
	-- /oly status: whether it counts here, and until when.
	local A = ns.Authority
	local saved = { enforced = A.Enforced, manifest = A.Manifest }
	local ok, err = pcall(function()
		A.Enforced = function() return false end
		eq(A.StatusLine(), "off")
		assert(ns.StatusText():find("signed leadership: off", 1, true), "in /oly status")
		A.Enforced = function() return true end
		A.Manifest = function() return nil end
		assert(A.StatusLine():find("^on, %a+, no current list"), A.StatusLine())
		A.Manifest = function() return { expires = 1800086400, guilds = {} } end
		assert(A.StatusLine():find("^on, %a+, expires 2027%-01%-16 08:00 UTC$"), A.StatusLine())
	end)
	A.Enforced, A.Manifest = saved.enforced, saved.manifest
	if not ok then error(err, 0) end
end)

-- The approved set against the whole cast, as another member's client sees each (the High
-- Council's, the King's Secretariat, the masters', every guild's masters and centurions, a
-- department's, and each guild's two rooms), without the signed leadership list and with it.
test("chat rooms (1.2.4): every room against the cast: the King, councillors titled and not, a Steward, the Treasurer, each guild's master, officer, centurion and correspondent, the author", function()
	WithRooms(function(w, R, c)
		local cast, aCorr, aCent, bCorr, bCent = Guilds(w, R, c)
		c.ApprovedGuilds = function() return {} end
		w.authorName = "Quill Wright-Realm"
		local titled, seat, steward = "Wren Titled-Realm", "Una Seat-Realm", "Stew Ard-Realm"
		w.council[titled:lower()], w.departments[titled:lower()], w.council[seat:lower()] = true, "Department of War", true
		w.stewards[steward:lower()] = true
		local treasurer = c.FullName(c.TREASURER)
		local ROOMS = { "council", "secretariat", "masters", "allcenturions", "dept:war", "dept:treasury", aCorr, aCent, bCorr, bCent }
		local NAMES = { "council", "secretariat", "masters", "allcenturions", "dept:war", "dept:treasury", "gcorr:A", "gcent:A", "gcorr:B", "gcent:B" }
		local function Rooms(name)
			local out = {}
			for i, id in ipairs(ROOMS) do if R.CanAccess(id, name) then out[#out + 1] = NAMES[i] end end
			return table.concat(out, ",")
		end
		local everyButCouncil = "masters,allcenturions,dept:war,dept:treasury,gcorr:A,gcent:A,gcorr:B,gcent:B"
		local want = {
			{ w.king, "council,secretariat,masters,allcenturions" },
			{ titled, "council,dept:war" }, { seat, "council" }, { steward, "secretariat" }, { treasurer, "council,dept:treasury" },
			{ cast.aMaster, "masters,allcenturions,gcorr:A,gcent:A" }, { cast.aOfficer, "allcenturions,gcent:A" },
			{ cast.aCenturion, "allcenturions,gcent:A" }, { cast.aWar, "dept:war,gcorr:A" }, { cast.aMember, "" },
			{ cast.bMaster, "" }, { cast.bOfficer, "" }, { cast.bCenturion, "" }, { cast.bWar, "" },
			{ w.authorName, everyButCouncil },
		}
		for _, row in ipairs(want) do eq(Rooms(row[1]), row[2], row[1] .. ", without the signed list") end
		w.enforced = true
		want[11][2], want[12][2] = "masters,allcenturions,gcorr:B,gcent:B", "allcenturions,gcent:B"
		want[13][2], want[14][2] = "allcenturions,gcent:B", "dept:war,gcorr:B"
		for _, row in ipairs(want) do eq(Rooms(row[1]), row[2], row[1] .. ", with it") end
	end)
end)

-- Until the signed list counts, another guild's rank is the census's (Data.AuthorizedRank), which the
-- rooms never take: they no longer ask it at all. A line to the masters' room asked every guild's
-- rank of every candidate before, the census's votes counted at each (a long pause in a large army).
test("chat rooms (1.2.4): without the signed leadership list no room asks another guild's rank; with it, once a name and guild", function()
	WithRooms(function(w, R, c)
		local cast = Guilds(w, R, c)
		for i = 1, 30 do c.rdb.guilds["Olympus " .. (i + 40)] = { leader = "Lead" .. i, officers = { { name = "Aide" .. i } } } end
		local isFederation = c.IsFederation
		c.IsFederation = function(g) return c.rdb.guilds[g] ~= nil or isFederation(g) end
		local asked, abroad = 0, 0
		local rank = c.Data.AuthorizedRank
		c.Data.AuthorizedRank = function(name, guild)
			asked = asked + 1
			if guild ~= w.guild then abroad = abroad + 1 end
			return rank(name, guild)
		end
		c.me = cast.aMaster
		eq(R.Send("masters", "to the masters"), true)
		eq(R.Send("allcenturions", "and the centurions"), false, "(too fast)")
		w.advance(2)
		eq(R.Send("allcenturions", "and the centurions"), true)
		eq(abroad, 0, "another guild's rank never asked")
		assert(asked > 0, "our own roster asked")
		w.enforced = true
		w.advance(2)
		local counted = {}
		c.Data.AuthorizedRank = function(name, guild)
			local key = name .. " in " .. guild
			counted[key] = (counted[key] or 0) + 1
			return rank(name, guild)
		end
		eq(R.Send("masters", "once more"), true)
		for key, n in pairs(counted) do eq(n, 1, key .. ": once a send") end
		eq(table.concat(R.Recipients("masters"), ","), table.concat({ w.king, cast.bMaster }, ","))
	end)
end)

-- The role rooms' words in English and pt-BR, with the same placeholders (the author's titles, The
-- Royal Dev, and the menu's arrow the same in both).
test("chat rooms (1.2.4): the role rooms' words in English and pt-BR, with the same placeholders", function()
	local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-rooms%-124%.lua$")) or "./"
	local oldLocale = GetLocale
	local en, pt = {}, {}
	local ok, err = pcall(function()
		for _, pair in ipairs({ { en, "enUS" }, { pt, "ptBR" } }) do
			GetLocale = function() return pair[2] end
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", pair[1])
			assert(loadfile(ROOT .. "Olympus/Locales/ChurchText.lua"))("Olympus", pair[1])
		end
	end)
	GetLocale = oldLocale
	if not ok then error(err, 0) end
	local SAME = { CHATWIN_TAG_DEV = true, CHATWIN_MENU_GROUP = true }
	for _, d in ipairs(ns.Nominees.DEPARTMENT_LIST) do
		eq(en.L[d.label], d.name, d.label .. ": its English is the department's name")
	end
	for _, key in ipairs({ "CHATROOM_COUNCIL", "CHATROOM_MASTERS", "CHATROOM_ALLCENTURIONS", "CHATROOM_GCORR", "CHATROOM_GCORR_OF",
		"CHATROOM_GCENT", "CHATROOM_GCENT_OF", "CHATROOM_GROUP_DEPARTMENTS", "CHATROOM_DEPT_TREASURY", "CHATROOM_DEPT_WAR",
		"CHATROOM_DEPT_JUSTICE", "CHATROOM_DEPT_ARTISANRY", "CHATROOM_DEPT_HERITAGE", "CHATROOM_DEPT_CHURCH", "CHATROOM_NOT_REACHED",
		"CHATROOM_NEEDS_LEADERS", "CHATWIN_TAG_DEV", "CHATWIN_MENU_GROUP", "CHATWIN_MENU_PREV", "CHATWIN_MENU_MORE",
		"CHURCH_ROOM_APOSTLES", "CHURCH_ROOM_MISSIONARIES" }) do
		local e, p = rawget(en.L, key), rawget(pt.L, key)
		assert(type(e) == "string" and type(p) == "string", key)
		if SAME[key] then eq(p, e, key) else assert(p ~= e, "pt-BR: " .. key) end
		local a, b = {}, {}
		for x in e:gmatch("%%%d*[sd]") do a[#a + 1] = x end
		for x in p:gmatch("%%%d*[sd]") do b[#b + 1] = x end
		eq(table.concat(b, ","), table.concat(a, ","), "the same placeholders: " .. key)
	end
	eq(pt.L.CHATROOM_COUNCIL, "Alto Conselho"); eq(en.L.CHATROOM_COUNCIL, "High Council")
end)

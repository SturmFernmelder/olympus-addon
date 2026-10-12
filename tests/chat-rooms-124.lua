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
		eq(#R.History(aCent), 1); eq(R.History(aCent)[1].text, "on my way")
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

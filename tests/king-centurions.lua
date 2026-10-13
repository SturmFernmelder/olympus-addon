-- 1.2.4 (the author's rule, his words: "cada high counselor seria o equivalente a um centurião para o
-- líder principal"): in the King's guild the High Council are the King's centurions. The signed
-- council list says who; nobody names them in game, so the Throne (the King's own, the author's preview's,
-- a councillor's) offers no "+ Name a centurion" any more and lists them to read, each councillor of
-- the King's guild with his War Room squad. They count where the King's guild's centurions count:
-- the War Room's squads (WarSquads.Leaders, since 1.2.0), the centurions' chat rooms, and their own
-- silver border and bounty office above a centurion's. 1.1.5's list of the King's guild's centurions
-- counts for nothing on 1.2.4; the King's and the councillors' clients end it where clients of 1.2.3
-- or older still hold it (tests/fixtures/nominees-1.2.3.lua, the shipped file).
-- Made-up names; the King's character by the constant (ns.KING_CHARACTER), never written out here.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]king%-centurions%.lua$") or "./"
local L, N, K = ns.L, ns.Nominees, ns.King
local KING = ns.KING_CHARACTER.Alliance .. "-Realm"
local VERA, OLAF, PIP = "Vera Councillor-Realm", "Olaf Councillor-Realm", "Pip Officer-Realm"
local function Msg(guild, rev, body) return ("NM~1~%s~%d~1~1~%s"):format(guild, rev, body) end
local function Find(lines, text)
	for i, l in ipairs(lines) do if type(l.text) == "string" and l.text:find(text, 1, true) then return l, i end end
end

test("1.2.4 King's centurions: final EN/PT locale assignments do not restore the retired manual appointment instructions", function()
	local saved = GetLocale
	local ok, why = pcall(function()
		for _, language in ipairs({ "enUS", "ptBR" }) do
			GetLocale = function() return language end
			local words = { L = {} }
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", words)
			assert(words.L.NOMINEES_MAIN_TITLE:find("High Council", 1, true), language .. ": signed council replaces the manual title")
			assert(not words.L.NOMINEES_MAIN_TITLE:find("%s", 1, true))
			assert(words.L.NOMINEES_MAIN_HINT:find(language == "ptBR" and "ninguém é indicado" or "nobody is named", 1, true))
			local note = words.L.NOMINEES_MAIN_NOTE:format("Olympus", 99)
			assert(note:find("99", 1, true), "leader plus ninety-nine soldiers")
			assert(not note:find("1.1.6", 1, true), "no obsolete appointment expiry instructions")
		end
	end)
	GetLocale = saved
	if not ok then error(why, 0) end
end)

-- The King's guild, its roster fresh (the server's word): the King, an officer, Vera (a councillor),
-- two soldiers. Olaf, the other councillor, is of another guild. The signed list's order: Vera, Olaf.
local function With(fn)
	local R = ns.Roster
	local saved = { me = ns.me, Now = ns.Now, Send = ns.Comm.Send, Guild = GetGuildInfo, Print = ns.Print, After = ns.After,
		Log = ns.Log, council = ns.rdb.council, titles = ns.rdb.councilTitles, main = ns.rdb.mainNominees,
		preview = ns.db.previewMainNominees, kingView = ns.db.devKingView, store = ns.rdb.warSquads, squads = rawget(ns, "WarSquads"),
		show = ns.War.Show, shown = ns.CouncilNamesShown(), vis = ns.Workshop.Visible, author = ns.Workshop.IsAuthor,
		roster = { R.byName, R.guild, R.complete, R.generation, R.group, R.faction, R.snapshotAt, R.members } }
	local w = { sent = {}, printed = {}, timers = {}, logged = {}, clock = 1800000000 }
	local ok, err = pcall(function()
		N.Reset()
		ns.rdb.mainNominees, ns.db.previewMainNominees, ns.db.devKingView, ns.rdb.warSquads = nil, nil, nil, nil
		ns.rdb.council = { names = { ["vera councillor"] = "Vera Councillor", ["olaf councillor"] = "Olaf Councillor" },
			blob = "HS1~1~~Vera Councillor,Olaf Councillor~00" }
		ns.rdb.councilTitles = nil
		ns.Now = function() return w.clock end
		ns.Comm.Send = function(dist, msg, key) w.sent[#w.sent + 1] = { dist = dist, msg = msg, key = key } end
		ns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		ns.Log = function(fmt, ...) w.logged[#w.logged + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end
		ns.After = function(_, _, f) w.timers[#w.timers + 1] = f end
		ns.War.Show = function() w.warShown = (w.warShown or 0) + 1 end
		R.byName = { [KING] = 0, [PIP] = 1, [VERA] = 3, ["Ada-Realm"] = 3, ["Bea-Realm"] = 3 }
		R.guild, R.complete, R.generation, R.group, R.faction, R.snapshotAt, R.members = "Olympus", true, 1, ns.group, ns.faction, w.clock, {}
		w.as = function(me, guild, rank)
			ns.me = me
			GetGuildInfo = function() return guild, rank == 0 and "King" or "Member", rank end
		end
		w.asKing = function() w.as(KING, "Olympus", 0) end
		w.flush = function() local due = w.timers; w.timers = {}; for _, f in ipairs(due) do f() end end
		w.parts = function()
			local out = {}
			for _, s in ipairs(w.sent) do if s.msg:find("^NM~") then out[#out + 1] = s.msg end end
			return out
		end
		-- The War Room's squads (WarSquads.lua as the game loads it), into a namespace of their own over
		-- the harness's: its listeners and chat provider stay there; ns.WarSquads is it for the test.
		w.squads = function()
			local c = setmetatable({ On = function() end, ChatRooms = { RegisterProvider = function() end },
				Comm = setmetatable({ Handle = function() end }, { __index = ns.Comm }) }, { __index = ns })
			assert(loadfile(ROOT .. "Olympus/WarSquads.lua"))("Olympus", c)
			rawset(ns, "WarSquads", c.WarSquads)
			return c.WarSquads
		end
		fn(w)
	end)
	ns.me, ns.Now, ns.Comm.Send, GetGuildInfo, ns.Print, ns.After, ns.Log = saved.me, saved.Now, saved.Send, saved.Guild, saved.Print, saved.After, saved.Log
	ns.rdb.council, ns.rdb.councilTitles, ns.rdb.mainNominees, ns.db.previewMainNominees = saved.council, saved.titles, saved.main, saved.preview
	ns.db.devKingView, ns.rdb.warSquads, ns.War.Show = saved.kingView, saved.store, saved.show
	rawset(ns, "WarSquads", saved.squads)
	ns.SetCouncilNamesShown(saved.shown)
	if ns.ViewAs.Role() ~= "my" then ns.ViewAs.Set("my") end
	ns.Workshop.Visible, ns.Workshop.IsAuthor = saved.vis, saved.author
	local R = ns.Roster
	R.byName, R.guild, R.complete, R.generation, R.group, R.faction, R.snapshotAt, R.members = unpack(saved.roster, 1, 8)
	K.Reset(); N.Reset()
	if not ok then error(err, 0) end
end

test("1.2.4 King's centurions: the High Council; the King's Throne offers no + Name a centurion; it lists the signed councillors to read, in the signed order, each of his guild with his War Room squad, one of another guild said so; their names hidden while he streams; /oly nominees names nobody, nothing sent or kept", function()
	With(function(w)
		local S = w.squads()
		w.asKing()
		eq(K.IsKing(), true)
		-- The War Room: one squad per councillor of his guild (WarSquads, 1.2.0), the King assigns its soldiers.
		local leaders = S.Leaders()
		eq(#leaders, 1); eq(leaders[1].name, VERA); eq(leaders[1].kind, "councillor")
		eq(S.Assign(VERA, "Ada"), true, "the King assigns a soldier to a councillor's squad")
		ns.SetCouncilNamesShown(true) -- (the eye under the council's header: names shown)
		local lines, title, detail = K.Build()
		eq(title, L.TAB_THRONE); eq(detail, L.THRONE_YOU_ARE_KING)
		eq(Find(lines, L.NOMINEES_ADD_CENTURION), nil, "no + Name a centurion on the King's Throne")
		assert(Find(lines, L.NOMINEES_MAIN_TITLE), "the King's centurions")
		local vera, at = Find(lines, "Vera Councillor")
		local olaf, after = Find(lines, "Olaf Councillor")
		assert(vera and olaf and at < after, "the signed order")
		eq(vera.right, L.SQUAD_COUNT:format(1), "her squad, its soldiers")
		eq(olaf.right, ns.Views.Grey(L.NOMINEES_MAIN_OUTSIDE:format("Olympus")), "of another guild: no squad here")
		eq(vera.onClick, nil, "to read: nobody's title to take back"); eq(olaf.onClick, nil)
		local war = Find(lines, L.NOMINEES_MAIN_WAR)
		assert(war and war.onClick, "the War Room, where he assigns their soldiers")
		war.onClick(); eq(w.warShown, 1)
		-- While he streams: no name, each "High Councillor N" in the signed order.
		ns.SetCouncilNamesShown(false)
		eq(ns.CouncilMasked(), true)
		lines = K.Build()
		eq(Find(lines, "Vera"), nil, "no name while he streams"); eq(Find(lines, "Olaf"), nil)
		eq(Find(lines, L.SQUAD_COUNCILLOR:format(1)).right, L.SQUAD_COUNT:format(1))
		assert(Find(lines, L.SQUAD_COUNCILLOR:format(2)), "the second councillor")
		-- Naming one: nobody, from the chat too; nothing sent, nothing kept.
		SlashCmdList.OLYMPUS("nominees centurion Bea")
		eq(w.printed[#w.printed], L.NOMINEES_MAIN_NOBODY)
		SlashCmdList.OLYMPUS("nominees remove Ada")
		eq(w.printed[#w.printed], L.NOMINEES_MAIN_NOBODY)
		w.flush()
		eq(#w.parts(), 0, "no list sent"); eq(ns.rdb.mainNominees, nil, "none kept")
		eq(N.RoleOf("Bea-Realm", "Olympus"), nil); eq(N.ListOf("Olympus"), nil)
		-- A councillor of his guild: one of the King's centurions, her squad in the War Room; nothing to name.
		w.as(VERA, "Olympus", 3)
		lines, _, detail = K.Build()
		eq(lines[1].text, L.THRONE_ROOM_COUNCIL); eq(detail, L.THRONE_YOU_ARE_COUNCILLOR)
		assert(Find(lines, L.THRONE_COUNCIL_HINT:sub(1, 20)), "what she is")
		eq(Find(lines, L.NOMINEES_ADD_CENTURION), nil, "nothing for her to name")
		eq(Find(lines, "Vera Councillor").right, L.SQUAD_COUNT:format(1))
		SlashCmdList.OLYMPUS("nominees centurion Bea")
		eq(w.printed[#w.printed], L.NOMINEES_MAIN_NOBODY)
		-- The other councillor, of another guild: the same list, no squad counts (not his guild's roster), no War Room line.
		w.as(OLAF, "Olympus II", 3)
		lines = K.Build()
		eq(Find(lines, L.NOMINEES_ADD_CENTURION), nil)
		eq(Find(lines, "Vera Councillor").right, nil); eq(Find(lines, L.NOMINEES_MAIN_WAR), nil)
	end)
end)

test("1.2.4 King's centurions: View as King (the author's preview): the same read-only list, no + Name a centurion, nothing named, stored or sent", function()
	With(function(w)
		local V = ns.ViewAs
		ns.SetCouncilNamesShown(false)
		ns.Workshop.Visible, ns.Workshop.IsAuthor = function() return true end, function() return true end
		w.as("Writer-Realm", "Olympus II", 3)
		eq(V.Set("king"), true)
		eq(K.Preview(), true); eq(K.ThroneShown(), true)
		local lines = K.Build()
		eq(Find(lines, L.NOMINEES_ADD_CENTURION), nil, "no + Name a centurion in the King preview")
		assert(Find(lines, L.NOMINEES_MAIN_TITLE), "the King's centurions")
		assert(Find(lines, L.SQUAD_COUNCILLOR:format(1)) and Find(lines, L.SQUAD_COUNCILLOR:format(2)), "as the King sees them while he streams")
		local war = Find(lines, L.NOMINEES_MAIN_WAR)
		assert(war, "the War Room line, as the King has it"); eq(war.onClick, nil, "inert in the preview")
		SlashCmdList.OLYMPUS("nominees centurion Ada")
		eq(w.printed[#w.printed], L.NOMINEES_MAIN_NOBODY)
		w.flush()
		eq(#w.parts(), 0, "nothing sent"); eq(ns.db.previewMainNominees, nil, "nothing kept on his screen")
		eq(N.RoleOf("Ada-Realm", "Olympus"), nil)
		eq(V.Set("my"), true)
	end)
end)

test("1.2.4 King's centurions: the chat rooms: in the King's guild its councillors are in Guild Centurions (its officers still, by rank) and reached there; every signed councillor is in All Centurions; nobody an older client's list names is in either", function()
	With(function(w)
		local Rooms = ns.ChatRooms
		w.as(PIP, "Olympus", 1)
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), VERA), true, "a councillor of the King's guild: one of the King's centurions")
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), PIP), true, "an officer, by his rank")
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), "Ada-Realm"), false, "a soldier")
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), OLAF), false, "a councillor of another guild: not this guild's room")
		eq(Rooms.CanAccess("allcenturions", VERA), true)
		eq(Rooms.CanAccess("allcenturions", OLAF), true, "every councillor is one of the King's centurions")
		local reached = table.concat(Rooms.Recipients(Rooms.GuildRoom("gcent", GetGuildInfo("player"))), ",")
		assert(reached:find(VERA, 1, true), "she is reached in Guild Centurions: " .. reached)
		assert(table.concat(Rooms.Recipients("allcenturions"), ","):find(OLAF, 1, true), "he is reached in All Centurions")
		-- 1.1.5's list, from the King's older client, names Bea: no room for her.
		N.Handle("CHANNEL", KING, Msg("Olympus", w.clock, "c=Bea"))
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), "Bea-Realm"), false); eq(Rooms.CanAccess("allcenturions", "Bea-Realm"), false)
		-- Signed off the council: in neither (the signed list alone says who).
		ns.rdb.council.names["vera councillor"] = nil
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), VERA), false); eq(Rooms.CanAccess("allcenturions", VERA), false)
		-- From another Olympus guild: All Centurions has every councillor, Guild Centurions is that guild's own.
		ns.rdb.council.names["vera councillor"] = "Vera Councillor"
		w.as("Nemo-Realm", "Olympus II", 1)
		eq(Rooms.CanAccess("allcenturions", VERA), true); eq(Rooms.CanAccess("allcenturions", OLAF), true)
		eq(Rooms.CanAccess(Rooms.GuildRoom("gcent", GetGuildInfo("player")), VERA), false, "the King's guild's councillor, not this guild's")
	end)
end)

test("1.2.4 King's centurions: an older client's list of the King's guild's centurions counts for nothing (no centurion, no bronze, nothing held); the King's or a councillor's client answers one that names anyone with one empty, newer list, which ends it on a 1.2.3 client; an empty one, a repeat or a forged one is never answered; a member's client sends nothing", function()
	With(function(w)
		-- A member of the King's guild: the King's older client's list names Ada and Bea.
		w.as("Ada-Realm", "Olympus", 3)
		N.Handle("CHANNEL", KING, Msg("Olympus", w.clock, "c=Ada;c=Bea"))
		eq(N.RoleOf("Ada-Realm", "Olympus"), nil, "no centurion of the King's guild by a list")
		eq(N.ListOf("Olympus"), nil, "none held")
		w.flush(); eq(#w.parts(), 0, "a member's client answers nothing")
		-- The King's client hears a councillor's older client's list: one empty, newer list answers it.
		w.asKing()
		local rev = w.clock + 5
		N.Handle("CHANNEL", VERA, Msg("Olympus", rev, "c=Ada"))
		eq(#w.parts(), 0, "not at once")
		w.flush()
		eq(#w.parts(), 1); local answer = w.parts()[1]
		eq(answer, Msg("Olympus", rev + 1, ""), "empty, and newer than the one heard")
		eq(N.RoleOf("Ada-Realm", "Olympus"), nil)
		-- Its repeat, an empty list (another's answer), a list from neither the King nor a councillor: no answer.
		N.Handle("CHANNEL", VERA, Msg("Olympus", rev, "c=Ada"))
		N.Handle("CHANNEL", OLAF, Msg("Olympus", rev + 50, ""))
		N.Handle("CHANNEL", "Nemo-Realm", Msg("Olympus", rev + 100, "c=Nemo"))
		w.flush(); eq(#w.parts(), 1, "nothing more")
		-- A newer one that names someone: answered again, once a minute at most.
		N.Handle("CHANNEL", VERA, Msg("Olympus", rev + 60, "c=Bea"))
		w.flush(); eq(#w.parts(), 1, "not again within the minute")
		w.clock = w.clock + 60
		w.flush()
		eq(#w.parts(), 2); eq(w.parts()[2], Msg("Olympus", math.max(w.clock, rev + 61), ""))
		-- A 1.2.3 client (its Nominees.lua as it shipped): a member's takes the councillor's list (the
		-- bronze there), then the answer ends it; a councillor's that holds it as its own takes the
		-- answer as its own and sends no name again.
		local saved = { StaticPopupDialogs.OLYMPUS_NOMINEE, StaticPopupDialogs.OLYMPUS_NOMINEE_REMOVE }
		local ok, err = pcall(function()
			local oldSent = {}
			local old = setmetatable({ On = function() end, Comm = setmetatable({ Handle = function() end,
				Send = function(_, msg) oldSent[#oldSent + 1] = msg end }, { __index = ns.Comm }) }, { __index = ns })
			assert(loadfile(ROOT .. "tests/fixtures/nominees-1.2.3.lua"))("Olympus", old)
			local O = old.Nominees
			w.as("Ada-Realm", "Olympus", 3)
			O.Handle("CHANNEL", VERA, Msg("Olympus", rev, "c=Ada"))
			eq(O.RoleOf("Ada-Realm", "Olympus"), "centurion", "a 1.2.3 member's client: Ada a centurion, in bronze")
			O.Handle("CHANNEL", KING, answer)
			eq(O.RoleOf("Ada-Realm", "Olympus"), nil, "ended there by the answer")
			O.Reset()
			w.as(VERA, "Olympus", 3)
			ns.rdb.mainNominees = { rev = rev, by = VERA, list = { { r = "c", n = "Ada-Realm" } } }
			eq(O.MainEditor(), true)
			O.Handle("CHANNEL", KING, answer)
			eq(#ns.rdb.mainNominees.list, 0, "her client takes the empty one as its own")
			eq(O.SendMain(), false, "and repeats nothing")
			O.SendMain(true)
			for _, msg in ipairs(oldSent) do eq(msg:match("~([^~]*)$"), "", "never a name again: " .. msg) end
			ns.rdb.mainNominees = nil
		end)
		StaticPopupDialogs.OLYMPUS_NOMINEE, StaticPopupDialogs.OLYMPUS_NOMINEE_REMOVE = saved[1], saved[2]
		if not ok then error(err, 0) end
	end)
end)

test("1.2.4 King's centurions: a King's or a councillor's client that still holds 1.1.5's list of the King's guild's centurions ends it at its first minute (one empty, newer list), then forgets it; one naming nobody, or anyone else's, is forgotten without a word; the King preview's copy goes too", function()
	With(function(w)
		w.asKing()
		ns.rdb.mainNominees = { rev = w.clock + 30, by = KING, list = { { r = "c", n = "Ada-Realm" } } }
		ns.db.previewMainNominees = { rev = 1, list = { { r = "c", n = "Bea-Realm" } } }
		N.Minute()
		eq(ns.rdb.mainNominees, nil, "forgotten"); eq(ns.db.previewMainNominees, nil, "the King preview's too")
		eq(#w.parts(), 1); eq(w.parts()[1], Msg("Olympus", w.clock + 31, ""), "one empty list, newer than it")
		N.Minute(); eq(#w.parts(), 1, "once")
		ns.rdb.mainNominees = { rev = w.clock + 40, by = KING, list = {} }
		N.Minute(); eq(ns.rdb.mainNominees, nil); eq(#w.parts(), 1, "naming nobody: nothing to end")
		w.as("Ada-Realm", "Olympus", 3)
		ns.rdb.mainNominees = { rev = 5, by = "Ada-Realm", list = { { r = "c", n = "Bea-Realm" } } }
		N.Minute(); eq(ns.rdb.mainNominees, nil); eq(#w.parts(), 1, "neither the King nor a councillor: no older client takes his")
		-- The signed councillor of another guild holds one too: hers ends the same way.
		w.as(OLAF, "Olympus II", 3)
		ns.rdb.mainNominees = { rev = 7, by = OLAF, list = { { r = "c", n = "Bea-Realm" } } }
		N.Minute(); eq(ns.rdb.mainNominees, nil); eq(#w.parts(), 2); eq(w.parts()[2], Msg("Olympus", w.clock, ""))
	end)
end)

test("1.2.4 King's centurions: an older client's list heard after the end went out, even one older than that end (a councillor's 1.2.3 client offline then, repeating its copy at its login), is answered again, once a minute at most: a 1.2.3 client that logged in since took it, and the new answer ends it there", function()
	With(function(w)
		w.asKing()
		-- His client ends its own old copy at its first minute.
		local rev = w.clock - 600
		ns.rdb.mainNominees = { rev = rev, by = KING, list = { { r = "c", n = "Ada-Realm" } } }
		N.Minute()
		eq(#w.parts(), 1); local first = w.parts()[1]
		eq(first, Msg("Olympus", w.clock, ""))
		-- Ten minutes on, a councillor's 1.2.3 client, offline then, logs in and repeats that same list.
		w.clock = w.clock + 600
		N.Handle("CHANNEL", VERA, Msg("Olympus", rev, "c=Ada"))
		w.flush()
		eq(#w.parts(), 2, "answered, though older than the end he sent")
		local answer = w.parts()[2]
		eq(answer, Msg("Olympus", w.clock, ""), "empty, newer than anything heard")
		-- Within the minute, its next repeat waits; an end another sends after it, newer, answers it.
		N.Handle("CHANNEL", VERA, Msg("Olympus", rev, "c=Ada"))
		w.flush(); eq(#w.parts(), 2, "not again within the minute")
		N.Handle("CHANNEL", OLAF, Msg("Olympus", w.clock + 1, ""))
		w.clock = w.clock + 60
		w.flush(); eq(#w.parts(), 2, "another's newer end came after it: nothing more")
		-- A 1.2.3 member's client that logged in after the first end: it took the repeat (the bronze),
		-- held the first end not; the new answer ends it.
		local saved = { StaticPopupDialogs.OLYMPUS_NOMINEE, StaticPopupDialogs.OLYMPUS_NOMINEE_REMOVE }
		local ok, err = pcall(function()
			local old = setmetatable({ On = function() end, Comm = setmetatable({ Handle = function() end,
				Send = function() end }, { __index = ns.Comm }) }, { __index = ns })
			assert(loadfile(ROOT .. "tests/fixtures/nominees-1.2.3.lua"))("Olympus", old)
			local O = old.Nominees
			w.as("Ada-Realm", "Olympus", 3)
			O.Handle("CHANNEL", VERA, Msg("Olympus", rev, "c=Ada"))
			eq(O.RoleOf("Ada-Realm", "Olympus"), "centurion", "a 1.2.3 client that logged in later takes the repeat")
			O.Handle("CHANNEL", KING, answer)
			eq(O.RoleOf("Ada-Realm", "Olympus"), nil, "the new answer ends it")
		end)
		StaticPopupDialogs.OLYMPUS_NOMINEE, StaticPopupDialogs.OLYMPUS_NOMINEE_REMOVE = saved[1], saved[2]
		if not ok then error(err, 0) end
	end)
end)

test("1.2.4 King's centurions: in another Olympus guild the War Room's squads are still led by its guild master's centurions (his own list, heard as it comes), a High Councillor in it by none of his seat; the King's guild's leaders stay the councillors", function()
	With(function(w)
		local S = w.squads()
		local R = ns.Roster
		local BOSS = "Boss Master-Realm"
		R.byName, R.guild = { [BOSS] = 0, [OLAF] = 3, ["Cid-Realm"] = 3, ["Dax-Realm"] = 3 }, "Olympus II"
		w.as("Cid-Realm", "Olympus II", 3)
		eq(#S.Leaders(), 0, "nobody named yet: no squad, the councillor in it neither")
		N.Handle("CHANNEL", BOSS, Msg("Olympus II", w.clock, "c=Cid;c=Dax"))
		eq(N.RoleOf("Dax-Realm", "Olympus II"), "centurion")
		local leaders = S.Leaders()
		eq(#leaders, 2, "his two centurions lead its squads")
		eq(leaders[1].name, "Cid-Realm"); eq(leaders[2].name, "Dax-Realm"); eq(leaders[1].kind, "centurion")
		for _, e in ipairs(leaders) do assert(e.name ~= OLAF, "a councillor leads no squad here by his seat") end
		-- A list for the King's guild from the King's older client changes nothing there either.
		N.Handle("CHANNEL", KING, Msg("Olympus", w.clock, "c=Cid"))
		eq(#S.Leaders(), 2)
		-- Back in the King's guild: its squads' leaders are its councillors alone.
		R.byName, R.guild = { [KING] = 0, [VERA] = 3, ["Ada-Realm"] = 3 }, "Olympus"
		w.asKing()
		leaders = S.Leaders()
		eq(#leaders, 1); eq(leaders[1].name, VERA); eq(leaders[1].kind, "councillor")
	end)
end)

-- (Review fix: the Throne numbered the councillors in the signed order, the War Room its squads' leaders
-- alone. With a councillor of another guild signed first, while the King streams the Throne's "High
-- Councillor 1" was that outsider and "High Councillor 2" the War Room's "High Councillor 1".)
test("1.2.4 King's centurions: while the King streams, the Throne's High Councillor N is the War Room's: its squads' leaders first, in its order, then the others in the signed order; the same order with the names shown", function()
	With(function(w)
		-- The signed order: Olaf (of another guild) before Vera (of the King's guild).
		ns.rdb.council.blob = "HS1~1~~Olaf Councillor,Vera Councillor~00"
		local S = w.squads()
		w.asKing()
		eq(S.Assign(VERA, "Ada"), true)
		ns.SetCouncilNamesShown(false)
		eq(ns.CouncilMasked(), true)
		local squad = Find(S.Lines(), L.SQUAD_COUNCILLOR:format(1))
		assert(squad, "the War Room: her squad, High Councillor 1")
		eq(squad.right, L.SQUAD_COUNT:format(1)); eq(Find(S.Lines(), L.SQUAD_COUNCILLOR:format(2)), nil, "its only one")
		local lines = K.Build()
		local first, at = Find(lines, L.SQUAD_COUNCILLOR:format(1))
		local second, after = Find(lines, L.SQUAD_COUNCILLOR:format(2))
		eq(first.right, L.SQUAD_COUNT:format(1), "the Throne's High Councillor 1 is the War Room's, her squad")
		eq(second.right, ns.Views.Grey(L.NOMINEES_MAIN_OUTSIDE:format("Olympus")), "the councillor of another guild after her")
		assert(at < after, "in that order")
		-- Names shown: the same order, so nothing moves when he clicks the eye.
		ns.SetCouncilNamesShown(true)
		lines = K.Build()
		local _, vera = Find(lines, "Vera Councillor")
		local _, olaf = Find(lines, "Olaf Councillor")
		assert(vera and olaf and vera < olaf, "her squad's line first, as the War Room has it")
		-- A reader outside the King's guild (no squads to read): the signed order.
		w.as(OLAF, "Olympus II", 3)
		lines = K.Build()
		_, olaf = Find(lines, "Olaf Councillor")
		_, vera = Find(lines, "Vera Councillor")
		assert(vera and olaf and olaf < vera, "the signed order")
	end)
end)

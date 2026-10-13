-- Newer 1.2.4 rule: manual Legates, not automatic council leaders. Legacy c= IDs stay compatible.
local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]king%-centurions%.lua$") or "./"
local L, N, K = ns.L, ns.Nominees, ns.King
local KING = ns.KING_CHARACTER.Alliance .. "-Realm"
local VERA, OLAF, PIP = "Vera Councillor-Realm", "Olaf Councillor-Realm", "Pip Officer-Realm"
local function Msg(guild, rev, body) return ("NM~1~%s~%d~1~1~%s"):format(guild, rev, body) end
local function Find(lines, text)
	for i, l in ipairs(lines) do if type(l.text) == "string" and l.text:find(text, 1, true) then return l, i end end
end

test("King's Legates: final EN/PT locale assignments describe manual twenty-five appointments and forty-person agreed groups", function()
	local saved = GetLocale
	local ok, why = pcall(function()
		for _, language in ipairs({ "enUS", "ptBR" }) do
			GetLocale = function() return language end
			local words = { L = {} }
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", words)
			assert(words.L.NOMINEES_MAIN_TITLE:find("Legates", 1, true), language .. ": current manual title")
			assert(not words.L.NOMINEES_MAIN_TITLE:find("%s", 1, true))
			assert(words.L.NOMINEES_MAIN_HINT:find("25", 1, true))
			local note = words.L.NOMINEES_MAIN_NOTE:format("Olympus", 39)
			assert(note:find("39", 1, true) and note:find("40", 1, true), "leader plus thirty-nine agreed guildmates")
			assert(not note:find("99", 1, true))
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
		roster = { R.byName, R.guild, R.complete, R.generation, R.group, R.faction, R.snapshotAt, R.members },
		popups = { StaticPopupDialogs.OLYMPUS_SQUAD_REVIEW, StaticPopupDialogs.OLYMPUS_SQUAD_REPLACE } }
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
	StaticPopupDialogs.OLYMPUS_SQUAD_REVIEW, StaticPopupDialogs.OLYMPUS_SQUAD_REPLACE = unpack(saved.popups, 1, 2)
	K.Reset(); N.Reset()
	if not ok then error(err, 0) end
end


test("King's Legates: actual manual appointments rather than a council seat create own-guild groups", function()
	With(function(w)
		local S = w.squads(); w.asKing()
		eq(#S.Leaders(), 0, "no implicit HC leadership")
		eq(N.NameMain("Ada"), true); eq(N.NameMain("Bea"), true)
		eq(N.NameMain("Unknown"), false, "current own roster required")
		eq(N.RoleOf("Ada-Realm", "Olympus"), "centurion", "legacy role id, not automatic rank")
		eq(#S.Leaders(), 2); eq(S.Leaders()[1].name, "Ada-Realm")
		eq(S.Assign("Ada", VERA), true); eq(S.Get("Ada").total, 2)
		eq(S.Get(VERA), nil, "the councillor may be a soldier without becoming a leader")
		w.flush()
		local part
		for _, msg in ipairs(w.parts()) do if msg:find("c=Ada", 1, true) then part = msg end end
		assert(part, "actual unchanged c= transport contains the manual appointment")
		w.as("Ada-Realm", "Olympus", 3); N.Handle("CHANNEL", KING, part)
		eq(N.RoleOf("Ada-Realm", "Olympus"), "centurion"); eq(S.CanManage(), true)
		eq(S.Assign("Ada", "Bea"), true, "actual ordinary-rank appointee manages own group")
		eq(S.Assign("Bea", VERA), false, "no other group's write authority")
		w.as(VERA, "Olympus", 3)
		eq(S.Get(VERA), nil); eq(S.CanAccess(S.Get("Bea").room), false, "no implicit HC room access")
	end)
end)

test("King's Legates: actual manual revocation removes leadership without deleting the old assignment", function()
	With(function(w)
		local S = w.squads(); w.asKing()
		eq(N.NameMain("Ada"), true); eq(S.Assign("Ada", "Bea"), true)
		local store = ns.rdb.warSquads[ns.Fold("Olympus")]
		local retained = store.rows[ns.Fold("Ada-Realm")]
		eq(N.RemoveMain("Ada"), true); eq(N.RoleOf("Ada-Realm", "Olympus"), nil)
		eq(S.Get("Ada"), nil); eq(store.rows[ns.Fold("Ada-Realm")], retained)
		w.as("Ada-Realm", "Olympus", 3); eq(S.CanManage(), false); eq(S.Assign("Ada", VERA), false)
	end)
end)

test("King's Legates: existing manual c= saves remain held rather than automatically retired", function()
	With(function(w)
		local S = w.squads(); w.asKing()
		ns.rdb.mainNominees = { rev = w.clock, by = KING, list = { { r = "c", n = "Ada-Realm" } } }
		eq(N.ListOf("Olympus").entries[1].name, "Ada-Realm"); eq(S.Get("Ada").name, "Ada-Realm")
		local retained = ns.rdb.mainNominees
		eq(N.Retire(), false); N.Minute()
		eq(ns.rdb.mainNominees, retained); eq(N.RoleOf("Ada-Realm", "Olympus"), "centurion")
		for _, msg in ipairs(w.parts()) do assert(msg:find("c=Ada", 1, true), "no automatic empty retirement word") end
	end)
end)

test("King's Legates: actual author King preview names only a local sample and grants no group management", function()
	With(function(w)
		local S = w.squads()
		ns.Workshop.Visible, ns.Workshop.IsAuthor = function() return true end, function() return true end
		w.as("Writer-Realm", "Olympus II", 3); eq(ns.ViewAs.Set("king"), true)
		eq(K.Preview(), true); eq(N.NameMain("Ada"), true)
		eq(N.MainEditor(), false); eq(N.SendMain(true), false); eq(S.CanManage(), false)
		w.flush(); eq(#w.parts(), 0); eq(ns.rdb.mainNominees, nil)
		assert(ns.db.previewMainNominees and #ns.db.previewMainNominees.list == 1, "only local preview stored")
		local lines = {}; N.MainLines(lines)
		for _, row in ipairs(lines) do eq(row.onClick, nil, "all preview actions inert") end
	end)
end)

test("King's Legates: other guilds require their own verified master's manual appointments", function()
	With(function(w)
		local S, BOSS = w.squads(), "Boss Master-Realm"
		local R = ns.Roster
		R.byName, R.guild = { [BOSS] = 0, [OLAF] = 3, ["Ada-Realm"] = 3, ["Bea-Realm"] = 3 }, "Olympus II"
		w.as("Ada-Realm", "Olympus II", 3); eq(#S.Leaders(), 0)
		N.Handle("CHANNEL", BOSS, Msg("Olympus II", w.clock, "c=Ada;c=Bea"))
		eq(#S.Leaders(), 2); eq(S.Leaders()[1].name, "Ada-Realm"); eq(S.Get(OLAF), nil)
		R.byName[BOSS] = 3; eq(#S.Leaders(), 0, "deposed issuer supplies no active leadership")
	end)
end)

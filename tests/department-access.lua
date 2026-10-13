local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]department%-access%.lua$")) or "./"

local function World(fn)
	local savedGuild, savedIn = GetGuildInfo, IsInGuild
	local savedMap, savedPosition = C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition
	local dialogs = {}; for key, value in pairs(StaticPopupDialogs) do dialogs[key] = value end
	local w = { now = 1800000000, guild = "Olympus II", rank = 3, packets = {}, selected = nil, handlers = {} }
	local c = setmetatable({ me = "Envoy-Realm", realm = "Realm", group = "RealmGroup", faction = "Alliance", db = {}, rdb = {} }, { __index = ns })
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild, "Member", w.rank end
		IsInGuild = function() return true end
		c.Now = function() return w.now end
		c.IsMember = function() return c.IsFederation(w.guild) end
		c.IsKingGuild = function(g) return g == "Olympus" end
		c.KingGuildName = function() return "Olympus" end
		c.IsHighCouncillor, c.IsKingCharacter = function() return false end, function() return false end
		c.FullName = function(n) if not n then return nil end return n:find("-", 1, true) and n or n .. "-Realm" end
		c.ShortName = function(n) return n and n:match("^[^-]+") end
		c.RealmOf = function(n) return n and n:match("%-([^%-]+)$") or "Realm" end
		c.Print, c.Log, c.Fire, c.On, c.After = function() end, function() end, function() end, function() end, function() end
		c.ChatLocked = function() return false end
		c.Roster = { complete = true, guild = w.guild, group = c.group, faction = c.faction, generation = 1, snapshotAt = w.now,
			byName = { ["Guildmaster-Realm"] = 0, [c.me] = 3, ["Peer-Realm"] = 3 }, members = {} }
		c.Roster.RankOf = function(n) return c.Roster.byName[c.FullName(n)] end
		c.Roster.IsOfficer = function() return w.rank <= 1 end
		c.Roster.Fresh = function()
			return c.Roster.complete and c.Roster.guild == w.guild and w.now - c.Roster.snapshotAt <= 600 and c.Roster or nil
		end
		c.Data = setmetatable({ KnownRank = function() return nil end }, { __index = ns.Data })
		c.ViewAs = { Available = function() return false end, Is = function() return false end }
		c.Workshop = { Visible = function() return false end }
		c.ChatRooms, c.PlayerMenu = {}, {}
		c.Moderation = { CharName = c.FullName, IsIssuer = function() return false end, Hides = function() return nil end,
			Hidden = function() return false end, SelfOff = function() return nil end, IsKing = function() return false end }
		c.UI = { SelectTab = function(key) w.selected = key end }
		c.Comm = { Handle = function(kind, fn) w.handlers[kind] = fn end, Send = function(dist, msg, _, _, _, _, options)
			w.packets[#w.packets + 1] = { dist = dist, msg = msg, options = options }; return true end }
		c.Borders = { Changed = function() end }
		assert(loadfile(ROOT .. "Olympus/Nominees.lua"))("Olympus", c)
		function w.name(dept, sender, name)
			w.now = w.now + 1; c.Roster.snapshotAt = w.now
			c.Nominees.Handle("CHANNEL", sender or "Guildmaster-Realm",
				("NM~1~%s~%d~1~1~d=%s=%s"):format(w.guild, w.now, dept, name or c.me))
		end
		function w.agenda()
			c.Gate = { Allowed = function() return true end, Hooks = function() end }
			c.IsSteward = function() return false end
			c.KingCharacter = function() return "Pinned King-Realm" end
			c.IsKingCharacter = function(name) return name == "Pinned King-Realm" end
			c.Workshop.IsAuthorName = function(name) return name == "Royal Dev-Realm" end
			c.CouncilTitle = function(name) return w.titles and w.titles[name] end
			c.IsHighCouncillor = function(name) return w.council and w.council[name] == true or false end
			c.Alert = function() end
			c.ShowDialog = function(which, _, _, data) w.dialog = { which = which, data = data } end
			c.Comm.SendChunked = function(msg, _, dist, _, options) return c.Comm.Send(dist or "CHANNEL", msg, nil, nil, nil, nil, options) end
			assert(loadfile(ROOT .. "Olympus/King.lua"))("Olympus", c)
			assert(loadfile(ROOT .. "Olympus/Week.lua"))("Olympus", c)
		end
		function w.decrees()
			w.agenda()
			c.Pins = function() return nil end
			c.Chronicle = { Add = function() end }
			c.Comm.DeliveredLogged = function() return true end
			c.Roster.MyRank = function() return w.rank end
			C_Map.GetBestMapForUnit = function() return 1411 end
			C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.42, 0.51 end } end
			assert(loadfile(ROOT .. "Olympus/Decree.lua"))("Olympus", c)
		end
		fn(w, c)
	end)
	GetGuildInfo, IsInGuild = savedGuild, savedIn
	C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = savedMap, savedPosition
	for key in pairs(StaticPopupDialogs) do StaticPopupDialogs[key] = nil end
	for key, value in pairs(dialogs) do StaticPopupDialogs[key] = value end
	if not ok then error(err, 0) end
end

test("1.2.4 Heraldry: old nominations keep their wire and duties under the corrected department name", function()
	World(function(w, c)
		w.name("Department of Heritage")
		eq(c.Nominees.OwnDepartment(), "Department of Heraldry")
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, "Department of Heritage"), true, "old list alias remains compatible")
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, "Department of Heraldry"), true)
		local found = false
		for _, dept in ipairs(c.Nominees.Departments()) do
			if dept == "Department of Heraldry" then found = true end
			assert(dept ~= "Department of Heritage", "only the current label is shown")
		end
		assert(found)
		local parts = c.Nominees.Parts(w.guild, w.now, { { role = "correspondent", dept = "Department of Heraldry", name = c.me } })
		assert(parts[1]:find("d=Department of Heritage=", 1, true), "the existing NM wire key remains readable by old clients")
	end)
end)

test("1.2.4 Heraldry Agenda: army authority is the King, author and actual Heraldry council; guild masters and other titles never command the army", function()
	World(function(w, c)
		w.agenda()
		local K, W = c.King, c.Week
		w.titles = { [c.me] = { dept = "Department of Heritage" }, ["War Head-Realm"] = { dept = "Department of War" } }
		w.council = { [c.me] = true, ["War Head-Realm"] = true }
		eq(K.SetAgenda("30 Army gathering", "army"), true)
		eq(K.AgendaAuthorized(c.me, w.guild, false), true, "actual council and old signed department alias")
		eq(w.packets[#w.packets].dist, "CHANNEL")
		assert(K.Agenda())
		w.council[c.me] = nil
		eq(K.AgendaAuthorized(c.me, w.guild, false), false, "a claimed title alone grants nothing")
		eq(K.Agenda(), nil, "revocation hides the current event")
		local count = #w.packets
		K.SendAgenda(); eq(#w.packets, count, "revocation stops repeats")
		eq(K.SetAgenda("30 Forged", "army"), false)
		eq(K.AgendaAuthorized("War Head-Realm", w.guild, false), false, "another council portfolio is not Heraldry")
		for _, root in ipairs({ "Pinned King-Realm", "Royal Dev-Realm" }) do eq(K.AgendaAuthorized(root, w.guild, false), true) end
		c.me = "Royal Dev-Realm"
		c.ViewAs = { Available = function() return true end, Is = function() return false end, Previewing = function() return true end }
		eq(K.SetAgenda("30 Preview intrusion", "army"), false, "another role's preview is inert even for the author")
		c.ViewAs = { Available = function() return false end, Is = function() return false end }
		c.me, w.rank = "Guildmaster-Realm", 0
		eq(K.CanAgenda("guild"), true); eq(K.CanAgenda("army"), false)
		eq(W.SetEntry("tomorrow 20:00 Army intrusion", "army"), false)
		eq(K.SetAgenda("30 Army intrusion", "army"), false)
		eq(#w.packets, count, "a rejected action sends nothing")
	end)
end)

test("1.2.4 Heraldry Agenda repeats: only the same admitted setter can adjust the current event's time", function()
	World(function(w, c)
		w.agenda()
		local K = c.King
		w.titles = { [c.me] = { dept = "Department of Heraldry" } }; w.council = { [c.me] = true }
		eq(K.SetAgenda("30 Army gathering", "army"), true)
		local a = K.Agenda()
		K.HandleCommand("CHANNEL", c.me, ("T1~A~%d~%s~3600~~Army gathering"):format(a.id, w.guild))
		eq(K.Agenda().at, w.now + 3600, "the legitimate setter's repeat adjusts drift")
		K.HandleCommand("CHANNEL", "Royal Dev-Realm", ("T1~A~%d~%s~1800~~Borrowed event"):format(a.id, w.guild))
		eq(K.Agenda().at, w.now + 3600, "even another authorized setter cannot overwrite this id")
	end)
end)

test("1.2.4 Heraldry Agenda: the own guild's master and verified correspondent schedule, sign, cancel and resend only to that guild; revocation and a guild change stop every path", function()
	World(function(w, c)
		w.agenda(); w.name("Department of Heritage")
		local K, W = c.King, c.Week
		eq(K.SetAgenda("30 Guild gathering"), true, "default scope for a guild correspondent is his guild")
		eq(K.CanAgenda("guild"), true); eq(K.CanAgenda("army"), false)
		local e = W.Entries()[1]
		assert(e and e.guildOnly and e.setterGuild == w.guild)
		eq(K.Agenda(), nil, "a guild event never replaces the royal event")
		eq(w.packets[#w.packets].dist, "GUILD")
		local guarded = w.packets[#w.packets].options.guard
		eq(guarded(), true)
		W.HandleSignup("WHISPER", "Peer-Realm", ("Y2~%d~D~%s"):format(e.id, w.guild))
		eq(W.Counts(e).D, 1, "our roster member can sign")
		W.HandleSignup("WHISPER", "Outsider-Realm", ("Y2~%d~H~Olympus Elsewhere"):format(e.id))
		W.HandleSignup("WHISPER", "Outsider-Realm", ("Y2~%d~H~%s"):format(e.id, w.guild))
		eq(W.Counts(e).H, 0); eq(W.Counts(e).others, 0, "outside signups never enter a guild sheet")
		eq(W.SendSheet(true), true); eq(w.packets[#w.packets].dist, "GUILD")
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(guarded(), false, "queued entry rechecks the current master and nomination")
		eq(#W.Entries(), 0); eq(W.SendSheet(true), false); eq(W.MayEdit(e), false)
		local count = #w.packets
		w.now = w.now + 601; c.Roster.snapshotAt = w.now; W.Tick(w.now)
		eq(#w.packets, count, "no resend after revocation")
		c.Roster.byName["Guildmaster-Realm"] = 0
		eq(W.Cancel(e.id), true); eq(w.packets[#w.packets].dist, "GUILD")
		w.now = w.now + 11
		eq(W.SetEntry("tomorrow 20:00 Guild raid", "guild"), true)
		eq(c.rdb.week[c.me][1].guildOnly, true, "saved entries keep the audience")
		w.guild = "Olympus Elsewhere"
		eq(#W.Entries(), 0); eq(K.CanAgenda("guild"), false)
		count = #w.packets; W.Tick(w.now + 3600)
		eq(#w.packets, count, "a changed guild never broadcasts a saved event")
	end)
end)

test("1.2.4 Heraldry Agenda: guild ingress cannot become army data or cancel an army entry; the scoped actions and restored entries keep their audience", function()
	World(function(w, c)
		w.agenda(); w.name("Department of Heraldry")
		local K, W = c.King, c.Week
		local message = ("T1~D~812~%s~1800~1~~Guild raid"):format(w.guild)
		K.HandleCommand("CHANNEL", "Guildmaster-Realm", message)
		eq(W.Entry(812), nil, "a guild master has no army ingress")
		K.HandleCommand("GUILD", "Peer-Realm", message); eq(W.Entry(812), nil, "a guild member alone has no posting duty")
		K.HandleCommand("GUILD", "Guildmaster-Realm", message)
		local e = W.Entry(812); assert(e and e.guildOnly)
		local saved = c.rdb.weekHeard
		local rows = {}; W.Section(rows)
		local guildButton, armyButton
		for _, row in ipairs(rows) do
			if row.text and row.text:find(c.L.WEEK_SET_GUILD, 1, true) then guildButton = row end
			if row.text and row.text:find(c.L.WEEK_SET_ARMY, 1, true) then armyButton = row end
		end
		assert(guildButton and guildButton.onClick); eq(armyButton, nil)
		guildButton.onClick(); eq(w.dialog.data.scope, "guild")
		W.Reset(); c.rdb.weekHeard = saved; c.Roster.complete = false; W.Restore()
		eq(W.Entry(812), nil, "loading roster grants no authority")
		assert(c.rdb.weekHeard and c.rdb.weekHeard[1], "loading the roster never erases a saved guild event")
		c.Roster.complete = true
		eq(W.Entry(812).guildOnly, true, "same-guild reload preserves the audience")
		K.HandleCommand("CHANNEL", "Royal Dev-Realm", "T1~D~813~Olympus~3600~1~~Army event")
		assert(W.Entry(813) and not W.Entry(813).guildOnly)
		K.HandleCommand("GUILD", "Guildmaster-Realm", ("T1~D~813~%s~0~0~~"):format(w.guild))
		assert(W.Entry(813), "a guild cancel cannot touch an army entry")
		K.HandleCommand("GUILD", "Guildmaster-Realm", "T1~D~814~Olympus Other~3600~1~~Other guild")
		eq(W.Entry(814), nil, "a payload cannot claim another guild")
		w.guild = "Olympus Other"
		W.Reset(); c.rdb.weekHeard = saved; W.Restore()
		eq(W.Entry(812), nil, "a different guild never restores the old guild's entry")
	end)
end)

test("1.2.4 Heraldry Agenda reminders: a saved guild signup cannot nudge another guild or a revoked appointment", function()
	World(function(w, c)
		w.agenda(); w.name("Department of Heraldry")
		local W = c.Week
		eq(W.SetEntry("30 Guild gathering", "guild"), true)
		local e = W.Entries()[1]
		eq(W.Sign(e.id, "D"), true)
		local lines, sounds = {}, 0
		c.Print = function(line) lines[#lines + 1] = line end
		c.PlayAlert = function() sounds = sounds + 1 end
		w.now = e.at - 240; c.Roster.snapshotAt = w.now
		w.guild = "Olympus Other"
		W.Remind(w.now)
		eq(#lines, 0, "a former guild's saved signup stays private")
		eq(sounds, 0)
		w.guild = "Olympus II"; c.Roster.byName["Guildmaster-Realm"] = 1
		W.Remind(w.now)
		eq(#lines, 0, "a revoked appointment cannot give a hidden event's reminder")
		c.Roster.byName["Guildmaster-Realm"] = 0
		W.Remind(w.now)
		eq(#lines, 1, "the admitted same-guild event still nudges once")
		eq(sounds, 1)
		W.Remind(w.now); eq(#lines, 1)
	end)
end)

test("1.2.4 Heraldry decrees: the verified correspondent sends every existing kind to his guild alone; queued sends lose authority with the appointment", function()
	World(function(w, c)
		w.decrees(); w.name("Department of Heritage")
		local D = c.Decree
		for _, kind in ipairs({ "ROYAL", "HERALDRY", "MUSTER", "ARMS" }) do eq(D.Scope(kind), "guild", kind) end
		D.Send("MUSTER", "Guild gathering")
		local sent = w.packets[#w.packets]
		eq(sent.dist, "GUILD")
		eq(c.Codec.DecodeDecree(sent.msg).guild, w.guild)
		eq(sent.options.guard(), true)
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(sent.options.guard(), false, "a queued message rechecks the original nomination")
		local n = #w.packets
		w.now = w.now + 61; c.Roster.snapshotAt = w.now
		D.Send("ROYAL", "No longer authorized")
		eq(#w.packets, n)
		c.Roster.byName["Guildmaster-Realm"] = 0
		w.name("Department of War"); eq(D.CanSend("MUSTER"), false, "another department gains no Heraldry duty")
		w.name("Department of Heraldry"); c.Roster.complete = false
		eq(D.CanSend("ROYAL"), false, "an incomplete roster proves no appointment")
		c.Roster.complete = true; w.now = w.now + 601
		eq(D.CanSend("MUSTER"), false, "a stale roster grants nothing")
	end)
end)

test("1.2.4 Heraldry decrees: receivers verify the current own-guild appointment, never the claimed rank, another guild or a global Crown", function()
	World(function(w, c)
		w.decrees(); w.name("Department of Heritage")
		local D = c.Decree
		local function Message(kind, guild) return c.Codec.EncodeDecree(kind or "ROYAL", 1411, 0.42, 0.51, guild or w.guild, 0, "Gather") end
		local msg = Message()
		w.handlers.D1("CHANNEL", c.me, msg); eq(#D.Active(), 0, "Heraldry nomination grants no army decree")
		w.handlers.D1("GUILD", "Peer-Realm", msg); eq(#D.Active(), 0, "a member cannot claim rank zero on the wire")
		w.handlers.D1("GUILD", c.me, Message("ROYAL", "Olympus Other")); eq(#D.Active(), 0, "another guild grants no authority")
		for i, kind in ipairs({ "ROYAL", "MUSTER", "HERALDRY", "ARMS" }) do
			w.now = w.now + 61; c.Roster.snapshotAt = w.now
			w.handlers.D1("GUILD", c.me, Message(kind))
			eq(#D.Active(), i, kind)
			eq(D.Active()[1].scope, "guild")
		end
		c.Roster.byName["Guildmaster-Realm"] = 1
		w.now = w.now + 61; c.Roster.snapshotAt = w.now
		w.handlers.D1("GUILD", c.me, msg); eq(#D.Active(), 4, "a deposed master's nomination admits no new decree")
		c.Roster.byName["Guildmaster-Realm"] = 0; c.Roster.byName[c.me] = nil
		w.now = w.now + 61; c.Roster.snapshotAt = w.now
		w.handlers.D1("GUILD", c.me, msg); eq(#D.Active(), 4, "a departed correspondent admits none")
		c.Roster.byName[c.me] = 3; c.Roster.complete = false
		w.now = w.now + 61; c.Roster.snapshotAt = w.now
		w.handlers.D1("GUILD", c.me, msg); eq(#D.Active(), 4, "an incomplete roster proves no appointment")
		c.Roster.complete = true; w.now = w.now + 61; c.Roster.snapshotAt = w.now - 601
		w.handlers.D1("GUILD", c.me, msg); eq(#D.Active(), 4, "a stale roster proves no appointment")
	end)
end)

test("1.2.4 Heraldry nomination hovers: every department explains its actual duties on empty and named rows", function()
	World(function(w, c)
		local N = c.Nominees
		local duties = { ["Federal Treasury"] = "bank sharing", ["Department of War"] = "raids and PvP",
			["Council of Justice"] = "moderation", ["Association of Artisanry"] = "crafters",
			["Department of Heraldry"] = "Decrees, Agenda and musters", ["The Missionary Church of Olympus"] = "guild full" }
		w.rank, c.me = 0, "Guildmaster-Realm"
		eq(N.Name("correspondent", "Peer-Realm", "Department of War"), true)
		local found = {}
		for _, row in ipairs(N.GuildLines()) do
			for _, dept in ipairs(N.Departments()) do
				if row.text and row.text:find(dept, 1, true) and row.tooltip then
					local tip = { lines = {}, AddLine = function(self, line) self.lines[#self.lines + 1] = line end }
					row.tooltip(tip)
					local words = table.concat(tip.lines, "\n")
					assert(words:find(N.DepartmentHelp(dept), 1, true), dept .. " explains its duty")
					assert(words:find(duties[dept], 1, true), dept .. " explains the agreed responsibility")
					found[dept] = true
				end
			end
		end
		for _, dept in ipairs(N.Departments()) do assert(found[dept], dept) end
		eq(N.DepartmentHelp("Department of Heritage"), N.DepartmentHelp("Department of Heraldry"), "old lists get the same current duty text")
	end)
end)

test("1.2.4 Heraldry locales: both final locales describe scoped scheduling and department duties", function()
	local savedLocale = GetLocale
	local ok, err = pcall(function()
		for _, locale in ipairs({ "enUS", "ptBR" }) do
			GetLocale = function() return locale end
			local c = {}
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", c)
			for _, suffix in ipairs({ "TREASURY", "WAR", "JUSTICE", "ARTISANRY", "HERALDRY", "CHURCH" }) do
				local key = "NOMINEES_DUTY_" .. suffix
				assert(c.L[key] ~= key and #c.L[key] > 30, locale .. " has an actual duty, not a missing-key fallback")
			end
			local own = locale == "ptBR" and "própria guilda" or "own guild"
			assert(c.L.NOMINEES_DUTY_HERALDRY:find(own, 1, true), locale .. " makes the audience explicit")
			assert(c.L.WEEK_GUILD_PROMPT:find("30", 1, true), locale .. " has the guild entry's actual input format")
			eq(c.L.YOU_ARE_GUILD_HERALDRY:format("Olympus II"):find("Olympus II", 1, true) ~= nil, true)
		end
	end)
	GetLocale = savedLocale
	if not ok then error(err, 0) end
end)

test("guild departments: exact own-guild correspondent authority comes from a fresh roster and its current master's list", function()
	World(function(w, c)
		local N, dept = c.Nominees, "Department of War"
		w.name(dept, "Peer-Realm")
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "forged master rejected")
		w.name(dept)
		eq(N.IsCorrespondent(c.me, w.guild, dept), true)
		eq(N.OwnDepartment(), dept); eq(N.Correspondent(w.guild, dept), c.me)
		eq(N.IsCorrespondent(c.me, "Olympus of Ash", dept), false)
		eq(N.IsCorrespondent(c.me, w.guild, "Federal Treasury"), false)
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "deposed before pruning")
		c.Roster.byName["Guildmaster-Realm"] = 0
		c.Roster.byName[c.me] = nil
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "left the guild")
		c.Roster.byName[c.me] = 3
		c.Roster.complete = false
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "partial roster")
		c.Roster.complete = true; w.now = w.now + 601
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "stale roster")
		c.Roster.snapshotAt = w.now
		eq(N.IsCorrespondent(c.me, w.guild, dept), true)
		w.now = w.now + N.FRESH + 1; c.Roster.snapshotAt = w.now
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "expired nomination")
	end)
end)

-- (1.2.4, the author's ask: "if the GM isn't online ... it has to be kept".) Fails before: the guild
-- master's list lived in memory 6 hours, so with him offline since the evening, or after any /reload, a
-- correspondent lost his department, its Guild workspace and the department line said nobody was named.
test("guild departments (1.2.4): a correspondent keeps his department while the guild master is offline, across a reload, until the master's list ends", function()
	World(function(w, c)
		local dept = "Department of War"
		w.name(dept)
		local heardAt = w.now
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, dept), true)
		-- The guild master logs off for the night: nobody repeats the list; our roster still names him master.
		w.now = w.now + 9 * 3600; c.Roster.snapshotAt = w.now
		eq(c.Nominees.IsCorrespondent(c.me, w.guild, dept), true, "kept past the old six hours")
		-- A /reload: Nominees.lua loads again, its memory empty; the saved list comes back.
		assert(loadfile(ROOT .. "Olympus/Nominees.lua"))("Olympus", c)
		local N = c.Nominees
		eq(N.IsCorrespondent(c.me, w.guild, dept), true, "kept across a reload")
		eq(N.OwnDepartment(), dept); eq((N.GuildAccess()), true)
		eq(N.Correspondent(w.guild, dept), c.me, "the department line names him")
		-- Our roster still decides: a demotion of the master ends it at once.
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "deposed")
		c.Roster.byName["Guildmaster-Realm"] = 0
		-- Thirty days without a word from him: it ends.
		w.now = heardAt + N.FRESH + 1; c.Roster.snapshotAt = w.now
		eq(N.IsCorrespondent(c.me, w.guild, dept), false, "expired nomination")
		eq((N.GuildAccess()), false)
	end)
end)

test("guild departments: each correspondent sees their own panel with inert previews and no other department controls", function()
	World(function(w, c)
		local N = c.Nominees
		w.name("Association of Citizenry")
		eq(N.GuildAccess(), true)
		local rows, text, open = N.GuildLines(), {}, nil
		for _, row in ipairs(rows) do text[#text + 1] = tostring(row.text); if row.onClick then open = row end end
		text = table.concat(text, "\n")
		assert(text:find("Association of Artisanry", 1, true)); assert(not text:find("Association of Citizenry", 1, true)); assert(not text:find("Department of War", 1, true))
		eq(N.OwnDepartment(), "Association of Artisanry", "legacy nominations keep their operational duties under the corrected label")
		eq(N.IsCorrespondent(c.me, w.guild, "Association of Citizenry"), true, "older clients' department key remains compatible")
		assert(text:find("Dedicated department workflows", 1, true), "unavailable workflows are explicit after paragraph wrapping")
		assert(open); open.onClick(); eq(w.selected, "crafters")
		w.selected = nil; c.Roster.byName["Guildmaster-Realm"] = 1
		open.onClick(); eq(w.selected, nil, "stale button after authority revoked")
		eq(N.GuildAccess(), false)
		c.ViewAs = { Available = function() return true end, Role = function() return "correspondent" end, Previewing = function() return true end }
		eq(N.GuildAccess(), true)
		for _, row in ipairs(N.GuildLines()) do eq(row.onClick, nil, "preview is inert") end
	end)
end)

test("guild departments: guild master uses Artisanry throughout and canonical nominations preserve legacy lookup", function()
	World(function(w, c)
		local N = c.Nominees
		w.rank = 0; c.me = "Guildmaster-Realm"
		local text = {}
		for _, row in ipairs(N.GuildLines()) do text[#text + 1] = tostring(row.text) end
		text = table.concat(text, "\n")
		assert(text:find("Association of Artisanry", 1, true)); assert(not text:find("Citizenry", 1, true))
		-- The master's client owns its local list; test receiving his update on a member's client.
		w.rank = 3; c.me = "Envoy-Realm"
		w.name("Association of Artisanry", "Guildmaster-Realm", "Peer-Realm")
		eq(N.IsCorrespondent("Peer-Realm", w.guild, "Association of Artisanry"), true)
		eq(N.Correspondent(w.guild, "Association of Citizenry"), "Peer-Realm")
	end)
end)

test("guild departments: Justice duties use the verified nomination but Church authority still needs its canonical appointment", function()
	World(function(w, c)
		assert(loadfile(ROOT .. "Olympus/Watch.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", c)
		assert(loadfile(ROOT .. "Olympus/Church.lua"))("Olympus", c)
		w.name("Council of Justice")
		eq(c.WatchChat.Justice(), c.me); eq(c.WatchChat.IsNamedWatcher(c.me), true)
		eq(c.Watch.CanManage(), true, "same own-guild Watch duty as an appointed Justice correspondent")
		eq(c.WatchChat.CouncilSide(), false, "no federal authority")
		w.name("The Missionary Church of Olympus")
		eq(c.WatchChat.IsNamedWatcher(c.me), false, "prior department removed")
		eq(c.Church.Role(c.me), nil); eq(c.Church.IsPerson(c.me), false, "a contact nomination cannot silently grant Church duties")
		eq(c.Church.MayNameApostle(c.me), false)
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(c.Nominees.OwnDepartment(), nil, "a deposed master's nomination immediately loses authority")
	end)
end)

test("guild departments: a War correspondent may write only in their own guild and queued writes lose authority on revocation", function()
	World(function(w, c)
		assert(loadfile(ROOT .. "Olympus/War.lua"))("Olympus", c)
		local W = c.War
		w.name("Federal Treasury"); eq(W.IsOfficer(), false, "other department grants no War duty")
		w.name("Department of War"); eq(W.IsOfficer(), true)
		local operation = W.CreateOperation("raid 30 tank=1 | First operation")
		assert(operation, "real operation created")
		local packet = w.packets[#w.packets]
		eq(packet.dist, "GUILD", "no federal channel")
		c.Roster.byName["Guildmaster-Realm"] = 1
		eq(W.IsOfficer(), false)
		assert(packet.options and packet.options.permit)
		eq(packet.options.permit(W, packet.options.key, "GUILD", nil, packet.msg), false, "queued write revoked")
		c.Roster.byName["Guildmaster-Realm"] = 0
		w.guild = "Olympus of Ash"
		eq(W.IsOfficer(), false, "guild transfer cannot reuse the old roster")
	end)
end)

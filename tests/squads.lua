local ns, test, eq = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]squads%.lua$") or "./"
local function World(fn)
	local saved = { GetGuildInfo, IsInGuild, GetServerTime, GetTime, C_ChatInfo, StaticPopupDialogs }
	local w = { guild = "Olympus II", now = 1800000000, fresh = true, jobs = {}, council = {}, ranks = {}, events = {}, on = {} }
	local ok, err = pcall(function()
		GetGuildInfo = function() return w.guild end
		IsInGuild = function() return w.guild ~= nil end
		GetServerTime = function() return w.now end
		GetTime = function() return w.now end
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		StaticPopupDialogs = {}
		local c = setmetatable({ me = "Officer-Realm", db = { chatRooms = true }, rdb = { war = { centuries = { old = "preserved" } } },
			CAPTAIN_RANK = 1, Roster = { byName = {} }, ViewAs = {}, War = {}, ChatRooms = {}, Comm = {}, Nominees = {}, PartyGuard = {} }, { __index = ns })
		w.c = c
		c.Fold = string.lower
		c.FullName = function(name) return name:find("-", 1, true) and name or name .. "-Realm" end
		c.ShortName = function(name) return name:match("^[^-]+") end
		c.DisplayName = c.ShortName
		c.Normal = function(s) return s end
		c.Holds = function(q, ...) for _, text in ipairs({ ... }) do if text:lower():find(q:lower(), 1, true) then return true end end return false end
		c.ShowDialog = function(...) w.dialog = { ... }; return true end
		c.CouncilMasked = function() return w.masked == true end
		c.Now = function() return w.now end
		c.IsMember = function() return w.member ~= false end
		c.IsFederation = function(guild) return guild == "Olympus II" or guild == "Olympus" end
		c.IsKingGuild = function(guild) return guild == "Olympus" end
		c.IsHighCouncillor = function(name) return w.council[name] == true end
		c.ChatLocked = function() return w.locked == true end
		c.ViewAs.Previewing = function() return w.preview == true end
		c.Roster.Fresh = function() return w.fresh and c.Roster or nil end
		c.Roster.RankOf = function(name) return w.ranks[name] end
		c.Roster.IsOfficer = function() return (w.ranks[c.me] or 9) <= 1 end
		for _, name in ipairs({ "Officer", "Leader", "OtherLeader", "Outsider" }) do
			c.Roster.byName[name .. "-Realm"] = {}; w.ranks[name .. "-Realm"] = name == "Officer" and 0 or 9
		end
		for i = 1, 100 do c.Roster.byName["Soldier" .. i .. "-Realm"] = {}; w.ranks["Soldier" .. i .. "-Realm"] = 9 end
		w.list = { by = c.me, entries = { { name = "Leader-Realm", role = "centurion" }, { name = "OtherLeader-Realm", role = "centurion" } } }
		c.Nominees.ListOf = function() return w.list end
		c.Nominees.Proven = function(name) return name == "Officer-Realm" and w.proven ~= false end
		c.Nominees.RoleOf = function(name) for _, e in ipairs(w.list.entries) do if e.name == name then return e.role end end end
		c.Nominees.IsCorrespondent = function() return false end
		c.War.IsWarCouncillor = function() return false end
		c.Fire = function(...) w.events[#w.events + 1] = { ... } end
		c.On = function(event, f) w.on[event] = w.on[event] or {}; table.insert(w.on[event], f) end -- (heard by w.on)
		c.Consent = {}; c.L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
		c.RealmPages = {}
		c.ChatRooms.RegisterProvider = function(p) w.provider = p end
		c.Comm.Handle = function() end
		c.Comm.DeliveredLogged = function() return w.logged ~= false end
		c.Comm.Send = function(dist, msg, key, _, _, _, options)
			assert(options.owner and options.key and type(options.permit) == "function", "actual Comm capability contract")
			w.jobs[#w.jobs + 1] = { dist = dist, msg = msg, key = options.key or key, options = options }; return true
		end
		c.Comm.SendChunked = function(msg, _, dist, _, options) return c.Comm.Send(dist, msg, options.key, nil, nil, nil, options) end
		c.Comm.Whisper = function(to, msg, key, _, logged, done, options)
			w.jobs[#w.jobs + 1] = { to = to, msg = msg, key = key, logged = logged, done = done, options = options }; return true
		end
		c.PartyGuard.InviteGuildmate = function(name) w.invited = name; return true end
		c.Channels = { Admit = function() return not w.filtered, "filtered" end }
		c.Moderation = { Hides = function() return w.hidden == true end, Blocks = function() return false end }
		assert(loadfile(ROOT .. "Olympus/WarSquads.lua"))("Olympus", c)
		fn(w, c.WarSquads)
	end)
	GetGuildInfo, IsInGuild, GetServerTime, GetTime, C_ChatInfo, StaticPopupDialogs = unpack(saved, 1, 6)
	if not ok then error(err, 0) end
end
local function RealTransport(w)
	local c, events, login = w.c, {}, {}
	c.PREFIX = ns.PREFIX or "Olympus"
	c.db.blocked = {}
	c.RegisterEvent = function(event, callback) events[event] = callback end
	c.On = function(event, callback) if event == "LOGIN" then login[#login + 1] = callback end end
	c.After, c.Every, c.Log = function() end, function() end, function() end
	c.SafeCall = function(_, fn, ...) return fn(...) end
	w.native = {}
	local function Send(prefix, msg, dist, target) w.native[#w.native + 1] = { prefix = prefix, msg = msg, dist = dist, target = target }; return 0 end
	C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = Send, SendAddonMessageLogged = Send }
	assert(loadfile(ROOT .. "Olympus/Comm.lua"))("Olympus", c)
	for _, callback in ipairs(login) do callback() end
	c.Comm.Handle("WU", c.WarSquads.Handle)
	c.Comm.Handle("SC", c.WarSquads.ReceiveChat)
	return events
end

test("Legates: native online count includes the leader, leaves unknown honest, and allows fluid shared membership", function()
	World(function(w, s)
		local R = w.c.Roster
		R.generation, R.snapshotAt = 1, w.now
		R.members = { { full = "Leader-Realm", online = true }, { full = "OtherLeader-Realm", online = false },
			{ full = "Soldier1-Realm", online = true }, { full = "Soldier2-Realm", online = false } }
		eq(s.Replace("Leader", { "Soldier1", "Soldier2", "Soldier3" }), true)
		eq(s.Replace("OtherLeader", { "Soldier1" }), true, "not an exclusive partition of the guild")
		local group = s.Get("Leader")
		eq(group.total, 4); eq(group.online, 2); eq(group.onlineUnknown, 1, "missing row is not silently offline")
		eq(s.Get("OtherLeader").online, 1); eq(s.Get("OtherLeader").total, 2)
		local row
		for _, line in ipairs(s.Lines("Leader")) do if line.squadOnline == "Leader-Realm" then row = line end end
		assert(row and row.text:find("1 unknown", 1, true), "unknown coverage is visible")
		R.members[1].online = false; R.members[2].online = true; R.members[3].online = false
		R.members[#R.members + 1] = { full = "Soldier3-Realm", online = true }
		R.generation, R.snapshotAt = 2, w.now + 1
		group = s.Get("Leader"); eq(group.online, 1); eq(group.onlineUnknown, 0)
		eq(s.Get("OtherLeader").online, 1)
		w.fresh = false; eq(s.Get("Leader"), nil, "stale or incomplete roster cannot claim a current group count")
	end)
end)

test("Legates: an assigned online member has one deliberate raid invite action; offline members do not", function()
	World(function(w, s)
		local R = w.c.Roster
		R.generation, R.snapshotAt = 1, w.now
		R.members = { { full = "Leader-Realm", online = true }, { full = "Soldier1-Realm", online = true },
			{ full = "Soldier2-Realm", online = false } }
		assert(s.Replace("Leader", { "Soldier1", "Soldier2", "Soldier3" }))
		local invite, inviteCount = nil, 0
		for _, line in ipairs(s.Lines("Leader")) do
			if line.text == (w.c.L.SQUAD_INVITE or "Invite online member to raid") then invite, inviteCount = line, inviteCount + 1 end
		end
		eq(inviteCount, 1, "only the member confirmed online is actionable")
		assert(invite and invite.onClick())
		eq(w.invited, "Soldier1-Realm")
	end)
end)

test("Legates: a group is its manually appointed leader and at most thirty-nine current guildmates", function()
	World(function(w, s)
		eq(s.MAX_SOLDIERS, 39); eq(s.MAX_MEMBERS, 40)
		local soldiers = {}; for i = 1, 39 do soldiers[i] = "Soldier" .. i end
		eq(s.Replace("Leader", soldiers), true)
		local group = s.Get("Leader"); eq(group.count, 39); eq(group.total, 40); eq(group.overflow, false)
		eq(s.Assign("Leader", "Soldier40"), false); eq(s.Get("Leader").count, 39)
		soldiers[40] = "Soldier40"; eq(s.Replace("Leader", soldiers), false)
		local full = {}; for i = 1, 40 do full[i] = "Soldier" .. i .. "-Realm" end
		table.sort(full, function(a, b) return a:lower() < b:lower() end)
		eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000001~" .. table.concat(full, ",")), false)
		eq(s.Get("Leader").total, 40)
	end)
end)

test("Legates: a King's guild High Councillor without a manual appointment has no group or implicit room", function()
	World(function(w, s)
		w.guild = "Olympus"; w.council["Leader-Realm"] = true
		w.c.rdb.council = { blob = "HS1~1~Alliance~Leader~abcd" }
		w.list.entries = {}
		eq(#s.Leaders(), 0); eq(s.Get("Leader"), nil); eq(#w.provider.Options("role"), 0)
		w.list.entries = { { name = "OtherLeader-Realm", role = "centurion" } }
		eq(#s.Leaders(), 1); eq(s.Leaders()[1].name, "OtherLeader-Realm", "ordinary-rank manual appointee, not automatic council")
		eq(s.Assign("OtherLeader", "Soldier1"), true)
		local room = s.Get("OtherLeader").room
		w.c.me = "Leader-Realm"; eq(s.CanAccess(room), false); eq(#w.provider.Options("role"), 0)
		w.c.me = "OtherLeader-Realm"; eq(s.CanAccess(room), true)
		local lines = s.Lines(); assert(#lines > 0)
		for _, line in ipairs(lines) do assert(not (line.squadLeader == "Leader-Realm"), "unappointed HC has no hierarchy row") end
		w.proven = false; eq(#s.Leaders(), 0); eq(s.CanAccess(room), false)
	end)
end)

test("Legates: legacy oversized saved groups remain intact as read-only overflow, never new forty-plus membership", function()
	World(function(w, s)
		assert(s.Replace("Leader", { "Soldier1" }))
		local store = w.c.rdb.warSquads["olympus ii"]
		local members = {}; for i = 1, 99 do members[i] = "Soldier" .. i .. "-Realm" end
		local row = { leader = "Leader-Realm", rev = w.now, members = members }
		store.rows["leader-realm"] = row
		local group = s.Get("Leader"); eq(group.count, 99); eq(group.total, 100); eq(group.overflow, true)
		eq(s.Assign("Leader", "Soldier100"), false); eq(s.Remove("Leader", "Soldier1"), false)
		eq(s.Replace("Leader", {}), false); eq(store.rows["leader-realm"], row); eq(#row.members, 99)
		local displayed, notice, inLegacy = 0, false, false
		for _, line in ipairs(s.Lines("Leader")) do
			if line.squadLeader then inLegacy = line.squadLeader == "Leader-Realm" end
			if inLegacy then
				if line.player then displayed = displayed + 1 end
				if line.text == (rawget(w.c.L, "SQUAD_OVERFLOW") or "Legacy group: %d/40 members; read-only until reviewed."):format(100) then notice = true end
				assert(not line.onClick or line.text == (rawget(w.c.L, "SQUAD_REVIEW") or "Review legacy group"), "legacy overflow offers only deliberate review, not implicit mutation or live chat")
			end
		end
		eq(displayed, 99); eq(notice, true)
		w.c.me = "Leader-Realm"; eq(s.ChatSend(group.room, "not a forty-member live group"), false)
		eq(store.rows["leader-realm"], row); eq(#row.members, 99)
		w.c.me = "Officer-Realm"
		local jobs = #w.jobs; eq(s.Handle("GUILD", "Soldier1-Realm", "WU~1~Q"), true)
		eq(#w.jobs, jobs, "legacy oversized membership is not reissued as a new live assignment")
		eq(s.Review("Leader"), true); eq(w.dialog[1], "OLYMPUS_SQUAD_REVIEW")
		local reset, focus = nil, false
		StaticPopupDialogs.OLYMPUS_SQUAD_REVIEW.OnShow({ editBox = { SetText = function(_, text) reset = text end, SetFocus = function() focus = true end } })
		eq(reset, ""); eq(focus, true, "a reviewed list is a fresh explicit input")
		local input = { data = w.dialog[4], editBox = { GetText = function() return "Soldier1, Soldier2" end } }
		eq(select(2, StaticPopupDialogs.OLYMPUS_SQUAD_REVIEW.OnAccept(input)), "confirmation", "actual review dialog requires a separate explicit confirmation")
		eq(select(2, s.Replace("Leader", { "Soldier1", "Soldier2" })), "confirmation")
		eq(w.dialog[1], "OLYMPUS_SQUAD_REPLACE"); eq(store.rows["leader-realm"], row)
		local confirmation = w.dialog[4]
		w.preview = true; eq(s.ConfirmReplacement(confirmation), false); w.preview = false
		eq(s.ConfirmReplacement(confirmation), true)
		eq(store.legacy["leader-realm"], row); eq(#store.legacy["leader-realm"].members, 99)
		eq(s.Get("Leader").total, 3); eq(s.Get("Leader").overflow, false)
		eq(s.ConfirmReplacement(confirmation), false, "stale confirmation cannot replace a newer row")
	end)
end)

test("Legates: a full legacy archive refuses reviewed replacement without discarding either membership", function()
	World(function(w, s)
		assert(s.Replace("Leader", { "Soldier1" }))
		local store = w.c.rdb.warSquads["olympus ii"]
		local members = {}; for i = 1, 40 do members[i] = "Soldier" .. i .. "-Realm" end
		local row = { leader = "Leader-Realm", rev = w.now, members = members }; store.rows["leader-realm"] = row
		store.legacy = {}; for i = 1, s.MAX_ROWS do store.legacy["old" .. i] = { retained = true } end
		eq(select(2, s.Replace("Leader", { "Soldier1" })), "confirmation")
		eq(select(2, s.ConfirmReplacement(w.dialog[4])), "archive")
		eq(store.rows["leader-realm"], row); eq(#row.members, 40)
		local count = 0; for _ in pairs(store.legacy) do count = count + 1 end; eq(count, s.MAX_ROWS)
	end)
end)

test("Legates: twenty-five manually appointed own-guild leaders are available, never a twenty-sixth", function()
	World(function(w, s)
		w.list.entries = {}
		for i = 1, 26 do w.list.entries[i] = { name = "Soldier" .. i .. "-Realm", role = "centurion" } end
		eq(s.MAX_LEADERS, 25); eq(#s.Leaders(), 25); eq(s.Get("Soldier25").total, 1)
		eq(s.Get("Soldier26"), nil); eq(s.Assign("Soldier26", "Soldier50"), false)
	end)
end)

test("Legate live overflow: provider access, options and queued writes close while the old transcript stays privately read-only", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room; local store = w.c.rdb.warSquads[w.c.Fold(w.guild)]
		w.c.me = "Leader-Realm"; eq(s.ChatSend(room, "queued before overflow"), true)
		local guard = w.jobs[#w.jobs].options.guard
		local members = {}; for i = 1, 99 do members[i] = "Soldier" .. i .. "-Realm" end
		store.rows["leader-realm"] = { leader = "Leader-Realm", members = members, rev = w.now + 1, by = "Officer-Realm" }
		store.chats[room] = { seq = 0, seen = {}, lines = { { sender = "Soldier1-Realm", text = "already received", id = 1, t = w.now } } }
		eq(s.CanAccess(room), false, "old room is not a live capability")
		eq(w.provider.CanAccess(room), false); eq(w.provider.Select(room), false); eq(w.provider.IsOpen(room), false)
		for _, option in ipairs(w.provider.Options("role")) do eq(option.id == room, false) end
		eq(guard(), false, "queued pre-overflow message cannot be delivered later")
		eq(s.ChatSend(room, "no live send"), false)
		eq(s.ReceiveChat("WHISPER", "Soldier1-Realm", "SC~1~" .. room:sub(7) .. "~2~no live receive"), false)
		eq(#s.ChatHistory(room), 1, "already-held transcript is not deleted")
		w.c.UI = { ShowCopy = function(title, body) w.copy = { title, body }; return true end }
		local read
		for _, line in ipairs(s.Lines("Leader")) do if line.readonlyHistory == room then read = line.onClick end end
		assert(read); eq(read(), true); assert(w.copy[2]:find("already received", 1, true))
		w.c.me = "Outsider-Realm"; eq(#s.ChatHistory(room), 0); eq(read(), false, "stale history button rechecks private membership")
		w.c.me = "Leader-Realm"; w.guild = "Olympus"; eq(read(), false, "another guild cannot read the old transcript")
	end)
end)

test("Legates: a verified appointee edits only their own group and queued writes lose authority when the appointment ends", function()
	World(function(w, s)
		w.c.me = "Leader-Realm"
		eq(s.CanManage(), true); eq(s.Assign("Leader", "Soldier1"), true)
		eq(s.Assign("OtherLeader", "Soldier2"), false); eq(s.Get("OtherLeader").count, 0)
		eq(s.Handle("GUILD", "Leader-Realm", "WU~1~S~OtherLeader-Realm~1800000001~Soldier2-Realm"), false)
		eq(s.Handle("GUILD", "OtherLeader-Realm", "WU~1~S~OtherLeader-Realm~1800000001~Soldier2-Realm"), true)
		local own, foreign = 0, 0
		for _, row in ipairs(s.Lines()) do
			if row.text == "Assign soldier" and row.onClick then row.onClick(); if w.dialog[4].prefix:find("OtherLeader", 1, true) then foreign = foreign + 1 else own = own + 1 end end
		end
		eq(own, 1); eq(foreign, 0, "no other Legate's edit action")
		local queued = w.jobs[1]; eq(queued.options.permit(nil, queued.key, "GUILD", nil, queued.msg), true)
		w.list.entries[1] = w.list.entries[2]; w.list.entries[2] = nil
		eq(s.CanManage(), false); eq(s.Get("Leader"), nil)
		eq(queued.options.permit(nil, queued.key, "GUILD", nil, queued.msg), false)
	end)
end)

test("Squads: bounded assignments preserve Centuries and require current officer authority", function()
	World(function(w, s)
		eq(#s.Leaders(), 2); eq(s.Get("Leader").count, 0)
		local soldiers = {}; for i = 1, 39 do soldiers[i] = "Soldier" .. i end
		eq(s.Replace("Leader", soldiers), true); eq(s.Get("Leader").count, 39)
		local oldJob = w.jobs[#w.jobs]
		eq(s.Assign("Leader", "Soldier40"), false); eq(s.Get("Leader").count, 39)
		soldiers[40] = "Soldier40"; eq(s.Replace("Leader", soldiers), false); eq(s.Get("Leader").count, 39)
		eq(s.Replace("Leader", { "Leader" }), false)
		eq(s.Replace("Leader", { "Soldier1", "Soldier1" }), false)
		eq(s.Replace("Leader", { "Unknown" }), false)
		eq(s.Remove("Leader", "Soldier10"), true)
		eq(oldJob.options.permit(nil, oldJob.key, "GUILD", nil, oldJob.msg), false)
		eq(s.Assign("Leader", "Soldier10"), true)
		w.preview = true; eq(s.Replace("Leader", {}), false); w.preview = false
		eq(s.Request(), true); eq(s.Request(), false)
		local query = w.jobs[#w.jobs]
		eq(query.options.permit(nil, query.key, "GUILD", nil, query.msg), true)
		w.c.me = "Outsider-Realm"; eq(s.Replace("Leader", {}), false)
		w.c.me = "Officer-Realm"; w.fresh = false; eq(s.Replace("Leader", {}), false)
		eq(w.c.rdb.war.centuries.old, "preserved")
	end)
end)
test("Squads: asks are throttled (not every roster scan) and answered once a window by one officer, on the normal lane", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local urgent = {}
		local send = w.c.Comm.Send
		w.c.Comm.Send = function(dist, msg, key, isUrgent, ...)
			urgent[#urgent + 1] = { msg = msg, urgent = isUrgent }
			return send(dist, msg, key, isUrgent, ...)
		end
		-- The asks: ASK_GAP apart, ASKS a session.
		eq(s.Request(), true); eq(s.Request(), false, "a roster scan right after")
		w.now = w.now + s.ASK_GAP; eq(s.Request(), true)
		w.now = w.now + s.ASK_GAP; eq(s.Request(), true)
		w.now = w.now + s.ASK_GAP; eq(s.Request(), false, "ASKS a session")
		-- An answer: once a window, not urgent.
		local before = #urgent
		eq(s.Handle("GUILD", "Soldier1-Realm", "WU~1~Q"), true)
		eq(#urgent, before + 1); eq(urgent[#urgent].urgent, false, "the normal lane")
		eq(select(2, s.Handle("GUILD", "Soldier2-Realm", "WU~1~Q")), "window"); eq(#urgent, before + 1)
		-- Another officer first by name heard on WU lately: he answers, not this client.
		w.c.Roster.byName["Able-Realm"] = {}; w.ranks["Able-Realm"] = 1
		eq(s.Handle("GUILD", "Able-Realm", "WU~1~Q"), true)
		w.now = w.now + s.REPLY_GAP
		eq(select(2, s.Handle("GUILD", "Soldier3-Realm", "WU~1~Q")), "other"); eq(#urgent, before + 1)
		-- Once he has not been heard for ELECT_FOR, this one answers again.
		w.now = w.now + s.ELECT_FOR + 1
		eq(s.Handle("GUILD", "Soldier4-Realm", "WU~1~Q"), true); eq(#urgent, before + 2)
	end)
end)
test("Squads: a client that heard an officer's rows asks no more", function()
	World(function(w, s)
		w.c.me = "Soldier1-Realm"
		eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000000~Soldier1-Realm"), true)
		eq(s.Request(), false)
	end)
end)
test("Squads: actual Realm tree inserts only own-guild hierarchy when that guild is expanded", function()
	World(function(w, s)
		local c = w.c
		c.UI = { Refresh = function() end }
		c.CouncilVisible = function() return false end
		c.Court, c.Hop, c.Board, c.Members, c.Treasury, c.Who = {}, {}, {}, {}, {}, {}
		c.Hop.State = function() return nil end
		c.Layers = { CurrentMap = function() return nil end }
		c.King = { CanCommand = function() return false end, Preview = function() return false end }
		c.Acts = { Gates = function() return nil end }
		c.FormatNumber = tostring
		c.Roster.online = {}
		-- (1.2.4: the rest is Data's own: the Realm's guild headers and Recruiting carry their average
		-- level, its order a tie-break, Data.AvgLevelText and Data.SortGuildCounts.)
		c.Data = setmetatable({ Dispute = function() return nil end, Summary = function() return { guilds = {
			{ name = w.guild, fresh = true, g = { leader = "Officer", total = 15, online = 0, mine = true } },
			{ name = "Olympus III", fresh = true, g = { leader = "Foreign", total = 15, online = 0 } },
		} } end }, { __index = ns.Data })
		assert(loadfile(ROOT .. "Olympus/Views.lua"))("Olympus", c)
		local function Count(lines) local count = 0; for _, line in ipairs(lines) do if line.squadLeader then count = count + 1 end end return count end
		eq(Count(c.Views.RealmLines()), 0)
		local header
		for _, line in ipairs(c.Views.RealmLines()) do if line.id == c.Views.GuildId(w.guild) then header = line end end
		eq(header ~= nil, true); header.onClick()
		eq(Count(c.Views.RealmLines()), 2)
		header.onClick(); eq(Count(c.Views.RealmLines()), 0)
	end)
end)
test("Squads: discoverable leader hierarchy includes zero squads, capped officer dialog/actions and masked/search views", function()
	World(function(w, s)
		local lines = s.Lines()
		local empty, add = 0, nil
		for _, line in ipairs(lines) do if line.text == "No soldiers assigned" then empty = empty + 1 end; if line.text == "Assign soldier" then add = line end end
		eq(empty, 2); eq(add ~= nil, true); eq(add.onClick(), true)
		eq(w.dialog[1], "OLYMPUS_WAR_INPUT"); eq(w.dialog[4].prefix, "squadadd OtherLeader-Realm|")
		assert(loadfile(ROOT .. "Olympus/War.lua"))("Olympus", w.c)
		local seen = false; for _, line in ipairs(w.c.War.Lines("OtherLeader")) do if line.squadLeader == "OtherLeader-Realm" then seen = true end end
		eq(seen, true)
		eq(w.c.War.Slash(w.dialog[4].prefix .. "Soldier1"), true)
		eq(s.Get("OtherLeader").count, 1)
		local remove
		for _, line in ipairs(s.Lines("Soldier1")) do if line.text == "Remove soldier" then remove = line end end
		eq(remove ~= nil, true)
		w.c.me = "Outsider-Realm"; eq(remove.onClick(), false); eq(s.Get("OtherLeader").count, 1)
		w.c.me = "Officer-Realm"; eq(remove.onClick(), true); eq(s.Get("OtherLeader").count, 0)
		eq(#s.Lines("not found"), 0)
		w.guild = "Olympus"; w.c.rdb.council = { blob = "HS1~1~Alliance~Leader~abcd" }; w.council["Leader-Realm"] = true; w.masked = true
		for _, line in ipairs(s.Lines()) do eq(line.text:find("Leader", 1, true), nil); eq(line.player, nil); eq(line.squadLeader, nil); eq(line.onClick, nil) end
		eq(#s.Lines("Leader"), 0)
	end)
end)
test("Squads: actual ChatRooms dynamic Roles menu discovers only authorized private squad rooms", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room
		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", w.c)
		local r = w.c.ChatRooms; eq(r.RegisterProvider(s.ChatProvider), true)
		w.c.me = "Soldier1-Realm"
		local found = false; for _, info in ipairs(r.Options("role")) do if info.id == room then found = true end end
		eq(found, true); eq(r.Select(room), true)
		found = false; for _, tab in ipairs(r.Tabs()) do if tab.kind == "role" then found = true end end
		eq(found, true)
		w.c.me = "Outsider-Realm"
		for _, info in ipairs(r.Options("role")) do eq(info.id == room, false) end
		eq(r.Select(room), false)
	end)
end)
test("Squads: actual hierarchy chat callback and OpenMatter route select only the authenticated room", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room; w.c.me = "Soldier1-Realm"
		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", w.c)
		local rooms = w.c.ChatRooms; eq(rooms.RegisterProvider(s.ChatProvider), true)
		-- Only the native window boundary is simulated; both the row callback and
		-- logical room/opening dispatcher are the actual addon functions.
		local pane, opened, raised, selected = {}, 0, 0, nil
		w.c.ChatWindow = {
			Open = function() opened = opened + 1; return pane end,
			SelectLogical = function(id) selected = id; return rooms.Select(id) end,
			Window = function() return { Raise = function() raised = raised + 1 end } end,
		}
		local action
		for _, line in ipairs(s.Lines()) do if line.text == (rawget(w.c.L, "SQUAD_OPEN_CHAT") or "Open private squad chat") then action = line.onClick end end
		eq(type(action), "function"); eq(action(), pane); eq(selected, room); eq(opened, 1); eq(raised, 1)
		w.c.me = "Outsider-Realm"; eq(action(), false); eq(rooms.OpenMatter({ room = room }), false); eq(opened, 1)
	end)
end)
test("Squads: main leaders follow verified manual appointment order without invented identities or foreign roster authority", function()
	World(function(w, s)
		w.guild = "Olympus"; w.c.council = nil
		w.c.rdb.council = { blob = "HS1~1~Alliance~OtherLeader,Missing,Leader~abcd" }
		w.council["OtherLeader-Realm"], w.council["Leader-Realm"] = true, true
		w.list.entries = { { name = "OtherLeader-Realm", role = "centurion" }, { name = "Missing-Realm", role = "centurion" }, { name = "Leader-Realm", role = "centurion" } }
		local leaders = s.Leaders(); eq(#leaders, 2); eq(leaders[1].name, "OtherLeader-Realm"); eq(leaders[2].name, "Leader-Realm")
		w.council["Leader-Realm"] = nil; eq(#s.Leaders(), 2, "council membership is not the appointment")
		w.list.entries[3] = nil; eq(#s.Leaders(), 1)
		w.guild = "Olympus II"; w.proven = false; eq(#s.Leaders(), 0)
		w.proven = true; w.ranks["Officer-Realm"] = 1; eq(#s.Leaders(), 0)
	end)
end)
test("Squads: guild-local authenticated snapshots reject malformed, stale and unauthorized input", function()
	World(function(w, s)
		local msg = "WU~1~S~Leader-Realm~1800000000~Soldier1-Realm"
		eq(s.Handle("WHISPER", "Officer-Realm", msg), false)
		eq(s.Handle("GUILD", "Outsider-Realm", msg), false)
		eq(s.Handle("GUILD", "Officer-Realm", msg), true); eq(s.Get("Leader").count, 1)
		eq(s.Handle("GUILD", "Officer-Realm", msg), false)
		eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000301~"), false)
		eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000001~,Soldier2-Realm"), false)
		eq(s.Handle("GUILD", "Soldier1-Realm", "WU~1~Q"), true)
		local job = w.jobs[#w.jobs]; eq(job.options.permit(nil, job.key, "GUILD", nil, job.msg), true)
		eq(job.options.permit(nil, job.key, "WHISPER", nil, job.msg), false)
		w.ranks["Officer-Realm"] = 9; eq(job.options.permit(nil, job.key, "GUILD", nil, job.msg), false)
	end)
end)
test("Squads: private chat excludes implicit royal/officer access and revalidates queued recipients and history", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room
		eq(s.CanAccess(room), false); eq(s.CanAccess(room, "Leader"), true)
		w.c.me = "Leader-Realm"; eq(#w.provider.Options("role"), 1)
		eq(s.ChatSend(room, "hello"), true)
		local job = w.jobs[#w.jobs]; eq(job.logged, true); eq(job.options.guard(), true)
		w.c.Roster.byName["Soldier1-Realm"] = nil; eq(job.options.guard(), false)
		job.done(true); eq(#s.ChatHistory(room), 0)
		w.c.Roster.byName["Soldier1-Realm"] = {}
		eq(s.ChatSend(room, "second"), true); w.jobs[#w.jobs].done(true); eq(#s.ChatHistory(room), 1)
		w.hidden = true; eq(#s.ChatHistory(room), 0); w.hidden = false
		w.preview = true; eq(#s.ChatHistory(room), 0); eq(s.ChatSend(room, "no"), false); w.preview = false
		w.c.me = "Outsider-Realm"; eq(#s.ChatHistory(room), 0); eq(#w.provider.Options("role"), 0)
		w.c.me = "Soldier1-Realm"; eq(#s.ChatHistory(room), 1)
		w.c.Roster.byName["Soldier1-Realm"] = nil; eq(#s.ChatHistory(room), 0)
	end)
end)
test("Squads: live private receive validates both participants, logged transport, replay and actual filter", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room; w.c.me = "Soldier1-Realm"
		local msg = "SC~1~" .. room:sub(7) .. "~1~hello"
		eq(s.ReceiveChat("GUILD", "Leader", msg), false)
		w.logged = false; eq(s.ReceiveChat("WHISPER", "Leader", msg), false); w.logged = true
		eq(s.ReceiveChat("WHISPER", "Outsider", msg), false)
		w.filtered = true; eq(s.ReceiveChat("WHISPER", "Leader", msg), false); w.filtered = false
		eq(s.ReceiveChat("WHISPER", "Leader", msg), true); eq(#s.ChatHistory(room), 1)
		eq(s.ReceiveChat("WHISPER", "Leader", msg), false)
		w.list.entries = {}; eq(s.ReceiveChat("WHISPER", "Leader", msg:gsub("~1~hello", "~2~later")), false); eq(#s.ChatHistory(room), 0)
	end)
end)
test("Squads: two actual clients converge complete assignments and exchange only private logged chat", function()
	World(function(a, sa)
		eq(sa.Replace("Leader", { "Soldier1" }), true)
		local assignment, room = a.jobs[1].msg, sa.Get("Leader").room
		a.c.me = "Leader-Realm"; eq(sa.ChatSend(room, "private"), true)
		local whisper = a.jobs[#a.jobs]; eq(whisper.to, "Soldier1-Realm")
		World(function(b, sb)
			b.c.me = "Soldier1-Realm"
			eq(sb.Handle("GUILD", "Officer-Realm", assignment), true)
			eq(sb.Get("Leader").room, room); eq(sb.Get("Leader").count, 1)
			eq(sb.ReceiveChat("WHISPER", "Leader-Realm", whisper.msg), true)
			eq(sb.ChatHistory(room)[1].text, "private")
			local first = "WU~1~S~Leader-Realm~1800000001~Soldier1-Realm"
			local second = "WU~1~S~Leader-Realm~1800000001~Soldier2-Realm"
			eq(sb.Handle("GUILD", "Officer-Realm", second), true)
			eq(sb.Handle("GUILD", "Officer-Realm", first), false)
			eq(sa.Handle("GUILD", "Officer-Realm", first), true)
			eq(sa.Handle("GUILD", "Officer-Realm", second), true)
			eq(sa.Get("Leader").soldiers[1], sb.Get("Leader").soldiers[1])
			eq(sb.CanAccess(room), false); eq(#sb.ChatHistory(room), 0)
		end)
	end)
end)
test("Squads: real SendChunked pump and GUILD reassembly deliver 39 maximum-length full names end to end", function()
	local names = {}
	local leader = "Leader" .. string.rep("a", 58) .. "AA-Realm"
	for i = 1, 39 do names[i] = "Soldier" .. string.rep("a", 57) .. string.char(65 + math.floor((i - 1) / 26), 65 + (i - 1) % 26) .. "-Realm" end
	World(function(a, sa)
		a.c.Roster.byName[leader], a.ranks[leader] = {}, 9; a.list.entries[1].name = leader
		for _, name in ipairs(names) do a.c.Roster.byName[name], a.ranks[name] = {}, 9 end
		RealTransport(a)
		eq(sa.Replace(leader, names), true)
		eq(#leader, 72); eq(#names[1], 72)
		eq(39 * 72 + 38 + 72 + 10 + 9 <= a.c.Codec.CHUNK * a.c.Codec.MAX_CHUNKS, true, "worst-case full header and members fit")
		eq(a.c.Comm.QueueSize() > 1, true, "the actual queue must contain a multipart transfer")
		for _ = 1, 40 do a.c.Comm.Pump(); a.now = a.now + 2 end
		eq(a.c.Comm.QueueSize(), 0); eq(#a.native, 14, "the forty-member group's inclusive worst-case wire is bounded")
		for _, piece in ipairs(a.native) do eq(piece.dist, "GUILD"); eq(#piece.msg <= 255, true) end
		World(function(b, sb)
			b.c.me = names[1]
			b.c.Roster.byName[leader], b.ranks[leader] = {}, 9; b.list.entries[1].name = leader
			for _, name in ipairs(names) do b.c.Roster.byName[name], b.ranks[name] = {}, 9 end
			local events = RealTransport(b)
			for i = #a.native, 1, -1 do
				local piece = a.native[i]
				events.CHAT_MSG_ADDON(piece.prefix, piece.msg, piece.dist, "Officer-Realm")
			end
			eq(sb.Get(leader).count, 39, "the actual guild assembler must dispatch WU to the actual model")
			for i, name in ipairs(sa.Get(leader).soldiers) do eq(sb.Get(leader).soldiers[i], name) end
			eq(sb.CanAccess(sb.Get(leader).room), true)
			local asm = b.c.Codec.NewAssembler()
			eq(b.c.Codec.Feed(asm, "Officer-Realm", "Coversize:1:35:WU~1~Q", b.now), nil)
			eq(asm.open, 0, "35 parts are refused before allocating an assembly")
		end)
	end)
end)
test("Squads: only transfers above 30 parts receive the bounded 70 second assembly lifetime", function()
	World(function(w)
		RealTransport(w)
		local codec, asm = w.c.Codec, w.c.Codec.NewAssembler()
		eq(codec.Feed(asm, "Officer-Realm", "Csmall:1:30:WU~1~Q", w.now), nil)
		eq(codec.Feed(asm, "Officer-Realm", "Clarge:1:34:WU~1~Q", w.now), nil)
		eq(asm.open, 2)
		eq(codec.Gc(asm, w.now + 61), 1); eq(asm.open, 1)
		eq(codec.Gc(asm, w.now + 70), 0); eq(asm.open, 1)
		eq(codec.Gc(asm, w.now + 71), 1); eq(asm.open, 0)
	end)
end)
test("Squads: malformed saved containers fail closed without replacing existing data", function()
	World(function(w, s)
		for _, bad in ipairs({ false, "broken", 12 }) do
			w.c.rdb.warSquads = bad; eq(s.Replace("Leader", {}), false); eq(w.c.rdb.warSquads, bad)
			w.c.rdb.warSquads = { ["olympus ii"] = bad }; eq(s.Replace("Leader", {}), false); eq(w.c.rdb.warSquads["olympus ii"], bad)
		end
	end)
end)
test("Squads: malformed saved rows reject rendering, mutation, replay and unsafe query serialization", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local store = w.c.rdb.warSquads["olympus ii"]
		for _, members in ipairs({ { false }, { [2] = "Soldier1-Realm" }, { "Soldier1-Realm", "Soldier1-Realm" }, { "Leader-Realm" }, { junk = "Soldier1-Realm" } }) do
			local row = { leader = "Leader-Realm", rev = w.now, members = members }; store.rows["leader-realm"] = row
			eq(s.Get("Leader").count, 0); eq(s.Replace("Leader", {}), false); eq(store.rows["leader-realm"], row)
			eq(s.Handle("GUILD", "Officer-Realm", "WU~1~S~Leader-Realm~1800000000~"), false)
		end
		store.rows["leader-realm"] = { leader = "Leader-Realm", rev = w.now, members = { "Soldier1-Realm" } }
		store.rows.bad = false
		eq(s.Handle("GUILD", "Soldier1-Realm", "WU~1~Q"), true); eq(store.rows.bad, false)
	end)
end)
test("Squads: malformed saved chat lines and seen maps fail closed without overwriting history", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local store, room = w.c.rdb.warSquads["olympus ii"], s.Get("Leader").room
		w.c.me = "Leader-Realm"
		local badChats = { false, "broken", { seq = 0, lines = {}, seen = false }, { seq = 0, lines = { false }, seen = {} },
			{ seq = 0, lines = { [2] = { sender = "Leader-Realm", text = "old", t = w.now, id = 1 } }, seen = {} },
			{ seq = 0, lines = {}, seen = { [false] = 1 } }, { seq = 0, lines = {}, seen = { ["Soldier1-Realm"] = "bad" } } }
		local tooManyLines, tooManySeen = {}, {}
		for i = 1, s.CHAT_MAX + 1 do tooManyLines[i] = { sender = "Leader-Realm", text = "old", t = w.now, id = i } end
		for i = 1, s.SEEN_MAX + 1 do tooManySeen["Old" .. i .. "-Realm"] = i end
		badChats[#badChats + 1] = { seq = 0, lines = tooManyLines, seen = {} }
		badChats[#badChats + 1] = { seq = 0, lines = {}, seen = tooManySeen }
		local msg = "SC~1~" .. room:sub(7) .. "~1~hello"
		for _, bad in ipairs(badChats) do
			store.chats[room] = bad
			eq(s.ChatSend(room, "new"), false); eq(#s.ChatHistory(room), 0)
			eq(s.ReceiveChat("WHISPER", "Soldier1-Realm", msg), false); eq(store.chats[room], bad)
		end
	end)
end)
-- 1.2.3 (the author's measure on his game: each redraw of the Chat tab made 2.5 MB of garbage, most of
-- it here): ChatRooms asks every provider about every room id it is given, the Olympus channels',
-- the race, class, guild and role rooms' too, a few hundred times a redraw of the tab's destinations,
-- and each ask read the squads' leaders again (in the King's guild, the signed council list parsed
-- and each councillor's name checked). An id that is not a squad's reads none; the Roles menu reads
-- them once, and offers what each room's own checks (CanAccess, ChatInfo) say.
test("Squads (1.2.3): a room id that is not a squad's reads no leaders; the Roles menu reads them once and offers what each room's own checks say", function()
	World(function(w, s)
		eq(s.Replace("Leader", { "Soldier1" }), true)
		eq(s.Replace("OtherLeader", { "Soldier2", "Soldier3" }), true)
		local room = s.Get("Leader").room
		local reads, leaders = 0, s.Leaders
		s.Leaders = function(...) reads = reads + 1; return leaders(...) end
		local ok, err = pcall(function()
			local p = w.provider
			for _, id in ipairs({ "guild", "race:human", "class:WA", "council", "secretariat", "dept:war", "masters", "craft:d00r",
				"arena:x", "squad", "A" }) do
				eq(p.Info(id), nil, id); eq(p.CanAccess(id, "Leader"), false, id); eq(p.IsOpen(id), false, id); eq(p.Select(id), false, id)
			end
			eq(reads, 0, "no leaders read for another room's id")
			eq(p.Info(room).id, room, "its own room still found")
			assert(reads > 0, "(its own room reads them)")
			for _, me in ipairs({ "Officer-Realm", "Leader-Realm", "OtherLeader-Realm", "Soldier1-Realm", "Soldier3-Realm", "Outsider-Realm" }) do
				w.c.me = me
				-- Each room's own checks, as the menu asked them before.
				local want = {}
				for _, e in ipairs(leaders()) do
					if s.CanAccess(e.room) then
						local info = s.ChatInfo(e.room)
						want[#want + 1] = table.concat({ info.id, info.kind, info.scope, info.label }, " ")
					end
				end
				reads = 0
				local got = {}
				for _, info in ipairs(p.Options("role")) do got[#got + 1] = table.concat({ info.id, info.kind, info.scope, info.label }, " ") end
				eq(reads, 1, me .. ": the leaders read once")
				eq(table.concat(got, ", "), table.concat(want, ", "), me .. ": the rooms offered")
			end
			w.c.me = "Leader-Realm"; w.preview = true
			eq(#p.Options("role"), 0, "a preview offers none, as before")
		end)
		s.Leaders = leaders
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.3, the review of the Chat tab's eras: the census tells DATA_CHANGED every second or so on a
-- busy realm (Data.NOTIFY_GAP; 891 census redraws in the author's 50 minutes), and WarSquads told
-- SQUADS_CHANGED and CHAT_ROOMS_CHANGED at each of them whatever they changed. The Chat tab starts a
-- new era at CHAT_ROOMS_CHANGED: on his game (the King's guild) it worked every line and room out
-- again 0.2 s after each notice, never waiting for its DATA_GAP. They are told when what the squads'
-- rooms rest on changed: our guild, our own place (in the roster, a preview, the chats on), a
-- leader, his place in the list (his room's label); whenever nothing is told, what the Chat tab
-- keeps for its era (the Roles menu, each room's description, ChatWindow.NavItems and .Logical) is
-- still what it would read. The asks and the roster read anew as before.
test("Squads (1.2.3): a census notice (DATA_CHANGED) tells SQUADS_CHANGED and CHAT_ROOMS_CHANGED only when what the squads' rooms rest on changed (a leader added, moved or gone, our own place: the roster, a preview, the chats locked, the guild), and what the Chat tab keeps for its era is right whenever it tells nothing; it still asks for rows and reads the roster anew", function()
	World(function(w, s)
		local p = w.provider
		eq(#(w.on.DATA_CHANGED or {}), 1, "its listener")
		eq(s.Replace("Leader", { "Soldier1", "Soldier2" }), true)
		eq(s.Replace("OtherLeader", { "Soldier3" }), true)
		-- What the Chat tab keeps for an era, and what its ticker asks: the Roles menu, and each
		-- room's (every leader's seen so far) description, access and whether it is open.
		local rooms, seenRoom = {}, {}
		local function Kept()
			for _, e in ipairs(s.Leaders()) do if not seenRoom[e.room] then seenRoom[e.room] = true; rooms[#rooms + 1] = e.room end end
			local out = {}
			for _, info in ipairs(p.Options("role")) do out[#out + 1] = "menu " .. info.id .. " " .. info.label end
			for _, room in ipairs(rooms) do
				local info = p.Info(room)
				out[#out + 1] = table.concat({ room, info and info.label or "none", tostring(p.CanAccess(room)), tostring(p.IsOpen(room)) }, " ")
			end
			return table.concat(out, "; ")
		end
		local last = Kept()
		local function Notice(what)
			w.events = {}
			for _, f in ipairs(w.on.DATA_CHANGED) do f() end
			local told = {}
			for _, e in ipairs(w.events) do told[#told + 1] = e[1] end
			local now = Kept()
			if #told == 0 then eq(now, last, what .. ": what the Chat tab keeps") end
			last = now
			return table.concat(told, " ")
		end
		local BOTH = "SQUADS_CHANGED CHAT_ROOMS_CHANGED"
		local jobs = #w.jobs
		eq(Notice("its own rows"), "", "nothing changed since its own rows (told as they were made)")
		eq(#w.jobs, jobs + 1, "the ask still made"); eq(w.jobs[#w.jobs].msg, "WU~1~Q")
		eq(Notice("again"), "", "nor at the next")
		-- The roster read anew at each notice (a name changed in place, found through its index).
		eq(s.Get("leader").name, "Leader-Realm", "(the index made)")
		w.c.Roster.byName["Newcomer-Realm"] = {}; w.ranks["Newcomer-Realm"] = 9
		eq(Notice("a member more"), "", "a member more, no room changed")
		eq(s.Assign("Leader", "newcomer"), true, "the roster read anew")
		eq(Notice("an assignment"), "", "his assignment told as it was made")
		-- A soldier of the Leader's squad looks.
		w.c.me = "Soldier1-Realm"
		eq(Notice("another of us"), BOTH, "our own place"); eq(Notice("again"), "")
		assert(last:find("menu " .. s.Get("Leader").room, 1, true), "his squad's room in his Roles menu")
		-- Another soldier gone from the guild: nothing the tab keeps changed; his access goes at once.
		w.c.Roster.byName["Soldier2-Realm"] = nil
		eq(Notice("a soldier gone"), "", "a soldier gone"); eq(s.Get("Leader").count, 2)
		eq(p.CanAccess(s.Get("Leader").room, "Soldier2-Realm"), false, "his access, asked at each look")
		-- Our own name gone from the roster, and back.
		w.c.Roster.byName["Soldier1-Realm"] = nil; eq(Notice("we left"), BOTH, "we left the roster")
		w.c.Roster.byName["Soldier1-Realm"] = {}; eq(Notice("back"), BOTH, "back in it"); eq(Notice("again"), "")
		-- A leader added, the leaders' order (each room's label, Squad %d), a leader gone.
		table.insert(w.list.entries, { name = "Soldier50-Realm", role = "centurion" })
		eq(Notice("a leader added"), BOTH, "a leader added"); eq(#s.Leaders(), 3); eq(Notice("again"), "")
		w.list.entries[1], w.list.entries[2] = w.list.entries[2], w.list.entries[1]
		eq(Notice("the order"), BOTH, "the leaders' order"); eq(Notice("again"), "")
		table.remove(w.list.entries)
		eq(Notice("a leader gone"), BOTH, "a leader gone"); eq(#s.Leaders(), 2); eq(Notice("again"), "")
		-- Our own place: a preview, the chats locked, out of the guild and back.
		w.preview = true; eq(Notice("a preview"), BOTH, "a preview"); w.preview = false; eq(Notice("over"), BOTH, "the preview over")
		w.locked = true; eq(Notice("locked"), BOTH, "the chats locked"); w.locked = false; eq(Notice("unlocked"), BOTH, "unlocked")
		w.guild = nil; eq(Notice("out"), BOTH, "out of the guild"); eq(Notice("still out"), "", "nothing more while out")
		w.guild = "Olympus II"; eq(Notice("in"), BOTH, "back in it"); eq(Notice("again"), "")
		-- What a notice reads, every second or so: the leaders once, each one's name folded once
		-- (his room found by the names as they were given).
		local reads, folds, leaders, fold = 0, 0, s.Leaders, w.c.Fold
		local count = #leaders(); eq(count, 2)
		s.Leaders = function(...) reads = reads + 1; return leaders(...) end
		w.c.Fold = function(x) folds = folds + 1; return fold(x) end
		local ok, err = pcall(function()
			for _, f in ipairs(w.on.DATA_CHANGED) do f() end
			eq(reads, 1, "the leaders read once")
			eq(folds, count, "a fold for each leader")
		end)
		s.Leaders, w.c.Fold = leaders, fold
		if not ok then error(err, 0) end
	end)
end)

-- The Companion's chat record (Bridge.lua's ns.RecordChat, a stand-in noting each call here): a
-- squad room's line kept and shown, the sender's own once its whisper left, as his own; never a
-- line that never left, one Olympus's checks refused, or one from outside the room.
test("Squads: the Companion's chat record: each squad line kept, the sender's own once it left, never one refused or unsent", function()
	World(function(w, s)
		local rec = {}
		w.c.RecordChat = function(tier, sender, text, isSelf) rec[#rec + 1] = { tier = tier, sender = sender, text = text, isSelf = isSelf } end
		eq(s.Replace("Leader", { "Soldier1" }), true)
		local room = s.Get("Leader").room
		w.c.me = "Leader-Realm"
		eq(s.ChatSend(room, "form up"), true)
		eq(#rec, 0, "not while its whisper waits")
		w.jobs[#w.jobs].done(false)
		eq(#rec, 0, "never one that did not leave")
		eq(s.ChatSend(room, "form up now"), true); w.jobs[#w.jobs].done(true)
		eq(#rec, 1); eq(rec[1].tier, room); eq(rec[1].sender, "Leader-Realm"); eq(rec[1].text, "form up now"); eq(rec[1].isSelf, true)
		w.c.me = "Soldier1-Realm"
		local function Line(seq, words) return "SC~1~" .. room:sub(7) .. "~" .. seq .. "~" .. words end
		w.filtered = true; eq(s.ReceiveChat("WHISPER", "Leader", Line(1, "refused by the checks")), false); w.filtered = false
		eq(s.ReceiveChat("WHISPER", "Outsider", Line(1, "not of the squad")), false)
		eq(#rec, 1, "nothing refused")
		eq(s.ReceiveChat("WHISPER", "Leader", Line(2, "on me")), true)
		eq(#rec, 2); eq(rec[2].sender, "Leader-Realm"); eq(rec[2].text, "on me"); eq(rec[2].isSelf, false)
	end)
end)

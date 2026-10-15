-- Logical Chat destinations: explicit topic choices, scoped transports, and revocable audiences.
local ns, test, eq = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-rooms%.lua$")) or "./"

local function WithRooms(fn)
	local globals = { "GetTime", "GetGuildInfo", "UnitClass", "UnitRace", "C_ChatInfo", "C_CreatureInfo", "LOCALIZED_CLASS_NAMES_MALE" }
	local saved = {}
	for _, name in ipairs(globals) do saved[name] = _G[name] end
	local w = { mono = 1000, epoch = 1800000000, guild = "Olympus II", channel = "OlympusNet",
		jobs = {}, events = {}, nativeEvents = {}, nativeSent = {}, listeners = {}, asked = {}, cancelled = 0, logged = true, attempts = 0,
		council = {}, stewards = {}, departments = {}, king = "The King-Realm" }
	local ok, err = pcall(function()
		GetTime = function() return w.mono end
		GetGuildInfo = function() return w.guild end
		UnitClass = function() return "Warrior", "WARRIOR" end
		UnitRace = function() return "Human", "Human", 1 end
		C_ChatInfo = { SendAddonMessageLogged = function() end, InChatMessagingLockdown = function() return false end }
		-- Verified native API/event in fixtures/forever-api.lua:605,669,690; no addon-message echo.
		C_ChatInfo.SendChatMessage = function(text, lane) w.nativeSent[#w.nativeSent + 1] = { text, lane } end
		C_CreatureInfo, LOCALIZED_CLASS_NAMES_MALE = nil, nil

		local c = setmetatable({ db = { chatRooms = true, addonChat = true }, rdb = { council = { names = {} } },
			me = "Member-Realm", realm = "Realm", faction = "Alliance" }, { __index = ns })
		c.Now = function() return w.epoch end
		c.FullName = function(name)
			if type(name) ~= "string" then return "" end
			return name:find("-", 1, true) and name or (name .. "-Realm")
		end
		c.ShortName = function(name) return tostring(name or ""):match("^([^%-]+)") or "" end
		c.IsMember = function() return w.member ~= false end
		c.IsHighCouncillor = function(name) return w.council[c.FullName(name or c.me):lower()] == true end
		c.CouncilTitle = function(name)
			local who = c.FullName(name or c.me):lower()
			return c.IsHighCouncillor(name or c.me) and w.departments[who] and { dept = w.departments[who] } or nil
		end
		c.CouncilTitles = function()
			local grouped, order = {}, {}
			for who, dept in pairs(w.departments) do
				if w.council[who] then
					if not grouped[dept] then grouped[dept], order[#order + 1] = {}, dept end
					grouped[dept][#grouped[dept] + 1] = { name = c.ShortName(who) }
				end
			end
			local depts = {}
			for _, dept in ipairs(order) do depts[#depts + 1] = { name = dept, members = grouped[dept] } end
			return { depts = depts }
		end
		c.KingCharacter = function() return w.king end
		c.IsKingCharacter = function(name) return c.FullName(name):lower() == w.king:lower() end
		c.Stewards = function()
			local out = {}
			for who in pairs(w.stewards) do out[#out + 1] = who end
			return out
		end
		c.IsSteward = function(name) return w.stewards[c.FullName(name):lower()] == true end
		c.Roster = { members = {}, ClassCode = function(file)
			local codes = { WARRIOR = "WA", MAGE = "MA", PALADIN = "PA" }
			return codes[file] or ""
		end }
		-- (1.2.4: the author's character by name, w.authorName, and his presence heard, w.authorOnline.)
		c.Workshop = { IsAuthor = function() return w.author == true end, Visible = function() return w.preview == true end,
			IsAuthorName = function(name) return w.authorName ~= nil and c.FullName(name):lower() == w.authorName:lower() end,
			AuthorOnline = function() return w.authorOnline == true end, AuthorName = function() return w.authorName end }
		c.Moderation = {
			SelfOff = function() return nil end, YouText = function() return "off" end,
			Hides = function() return false end, Any = function() return false end,
		}
		c.Channels = {
			IsMe = function(name) return c.FullName(name):lower() == c.me:lower() end,
			Admit = function() if w.filtered then return false, "filtered" end return true, "ok" end,
		}
		c.Fire = function(name, ...) w.events[#w.events + 1] = { name, ... } end
		c.On = function(name, call) w.listeners[name] = call end
		c.RegisterEvent = function(name, call) w.nativeEvents[name] = call end
		c.Print = function(message) w.printed = tostring(message) end
		w.logs = {}
		c.Log = function(fmt, ...) w.logs[#w.logs + 1] = tostring(fmt):format(...) end
		c.ShowDialog = function(which, a, b, data) w.dialog = { which = which, a = a, b = b, data = data } end
		c.Consent = {
			Register = function(spec) w.consent = spec end,
			Ask = function(key) w.asked[#w.asked + 1] = key end,
		}

		local function Queue(dist, msg, target, logged, done, options)
			w.attempts = w.attempts + 1
			if w.rejectAt == w.attempts then
				if done then done(false, "full") end
				return false
			end
			w.jobs[#w.jobs + 1] = { dist = dist, msg = msg, target = target, logged = logged,
				done = done, options = options }
			return true
		end
		c.Comm = {
			Handle = function(kind, call) w.handlerKind, w.handler = kind, call end,
			QueueRoom = function() return 60 - #w.jobs end,
			ChannelReady = function() return w.channel ~= nil end,
			ChannelName = function() return w.channel end,
			DeliveredLogged = function() return w.logged end,
			Send = function(dist, msg, _, _, logged, done, options) return Queue(dist, msg, nil, logged, done, options) end,
			Whisper = function(target, msg, _, _, logged, done, options) return Queue("WHISPER", msg, target, logged, done, options) end,
			Cancel = function(owner)
				local kept = {}
				for _, job in ipairs(w.jobs) do
					if job.options and job.options.owner == owner then
						w.cancelled = w.cancelled + 1
						if job.done then job.done(false, "cancelled") end
					else kept[#kept + 1] = job end
				end
				w.jobs = kept
			end,
			CancelQueued = function(owner, key, why)
				local dropped, kept = {}, {}
				for _, job in ipairs(w.jobs) do
					if job.options and job.options.owner == owner and job.options.key == key then dropped[#dropped + 1] = job
					else kept[#kept + 1] = job end
				end
				w.jobs = kept
				for _, job in ipairs(dropped) do if job.done then job.done(false, why) end end
				return #dropped
			end,
		}
		function w.finish(job, sent, why)
			local permitted, permitWhy = true, nil
			if job.options and job.options.permit then
				permitted, permitWhy = job.options.permit(job.options.owner, job.options.key, job.dist, job.target, job.msg)
			end
			if job.done then job.done(permitted and sent ~= false, permitWhy or why) end
			return permitted, permitWhy
		end
		function w.clearJobs() w.jobs, w.attempts, w.rejectAt = {}, 0, nil end
		function w.advance(seconds) w.mono, w.epoch = w.mono + seconds, w.epoch + seconds end

		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", c)
		w.ns, w.Rooms = c, c.ChatRooms
		w.Rooms.Reset()
		fn(w, w.Rooms, c)
	end)
	for _, name in ipairs(globals) do _G[name] = saved[name] end
	if not ok then error(err, 0) end
end

local function RoomMessage(id, line, words, version, guild, class)
	return ("M2~%s~%s~%d~%s~%s~%s"):format(version or "1", id, line, class == nil and "WA" or class, guild or "Olympus II", words)
end

test("chat Artisanry department: canonical label and signed legacy aliases preserve the room id", function()
	WithRooms(function(w, R, c)
		eq(R.Info("dept:citizenry").label, "Association of Artisanry")
		w.council[c.me:lower()] = true
		for _, title in ipairs({ "Association of Artisanry", "Association of Citizenry", "Artisanship" }) do
			w.departments[c.me:lower()] = title
			eq(R.CanAccess("dept:citizenry"), true, title)
		end
		w.council[c.me:lower()] = nil
		eq(R.CanAccess("dept:citizenry"), false, "a title without signed membership grants nothing")
	end)
end)

-- 1.2.3 (the author: "remove class and race chats from chat tab... no one uses them"): the race and
-- class rooms are gone for every member, of either faction: no tab, no list, no room to select,
-- subscribe to or send in, and nothing of the character is read to decide it.
test("chat rooms (1.2.3): no race or class room for a member of either faction: not listed, selectable or subscribable", function()
	WithRooms(function(w, R, c)
		UnitClass = function() error("room discovery must not inspect the character's class") end
		UnitRace = function() error("room discovery must not inspect the character's race") end
		C_CreatureInfo = { GetRaceInfo = function() error("room discovery must not inspect the character's race") end }
		local RETIRED = { "race:1", "race:2", "race:8", "race:95", "class:WA", "class:SH", "class:DR" }
		for _, faction in ipairs({ "Alliance", "Horde" }) do
			c.faction = faction
			local tabs = R.Tabs()
			eq(#tabs, 1, faction .. ": Guild alone for an ordinary member"); eq(tabs[1].id, "guild")
			for _, tab in ipairs(tabs) do
				assert(tab.kind ~= "race" and tab.kind ~= "class", faction .. ": no " .. tostring(tab.kind) .. " tab")
			end
			eq(#R.Options("race"), 0, faction); eq(#R.Options("class"), 0, faction)
			for _, id in ipairs(RETIRED) do
				local where = faction .. ", " .. id
				eq(R.Info(id), nil, where); eq(R.CanAccess(id), false, where); eq(R.IsOpen(id), false, where)
				local ok, why = R.Select(id)
				eq(ok, false, where); eq(why, "access", where)
				eq(#R.History(id), 0, where)
				ok, why = R.Send(id, "anyone here?")
				eq(ok, false, where); eq(why, "access", where)
			end
		end
		eq(#w.jobs, 0, "nothing queued"); eq(w.attempts, 0); eq(#w.nativeSent, 0, "nothing sent")
		eq(c.db.chatRoomChoices, nil, "no choice saved")
		for _, e in ipairs(w.events) do assert(e[1] ~= "CHAT_ROOM_SELECTED", "nothing selected") end
	end)
end)

test("chat rooms (1.2.3): an older client's line to a race or class room is dropped quietly and said once a session in the log", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.council["peer-realm"] = true, true
		local lines = {
			{ "CHANNEL", RoomMessage("race:1", 1, "for the Alliance") },
			{ "CHANNEL", RoomMessage("race:95", 2, "Skyborn hello") },
			{ "CHANNEL", RoomMessage("class:MA", 3, "please invite me", "1", nil, "RQ") },
			{ "WHISPER", RoomMessage("class:WA", 4, "a whisper") },
			{ "GUILD", RoomMessage("race:2", 5, "over guild") },
		}
		for i, line in ipairs(lines) do
			local ok, why = R.Receive(line[1], "Peer " .. i .. "-Realm", line[2], 1000 + i)
			eq(ok, false, line[2]); eq(why, "retired", line[2])
		end
		-- The M2 handler this file gives Comm takes the same road.
		eq(w.handlerKind, "M2")
		w.handler("CHANNEL", "Peer Six-Realm", RoomMessage("race:3", 6, "through the handler"))
		eq(R.Stats().dropped.retired, #lines + 1); eq(R.Stats().shown, 0)
		eq(#R.KeptRooms(), 0, "no history kept for them")
		for _, e in ipairs(w.events) do
			assert(e[1] ~= "CHAT_ROOM_LINE" and e[1] ~= "CHAT_ROOM_CHANGED", "no unread count, no redraw: " .. tostring(e[1]))
		end
		eq(w.printed, nil, "not a word to the player")
		eq(#w.logs, 1, "said once a session"); assert(w.logs[1]:find("race room", 1, true), w.logs[1])
		assert(not w.logs[1]:find("Peer", 1, true) and not w.logs[1]:find("Alliance", 1, true), "nothing of the wire in the log: " .. w.logs[1])
		-- Every other room still hears its lines.
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 7, "still heard"), 1010), true)
		eq(R.Receive("WHISPER", "Peer-Realm", RoomMessage("council", 8, "council still heard"), 1011), true)
		eq(R.History("guild")[1].text, "still heard"); eq(R.History("council")[1].text, "council still heard")
		-- The next session says it once again.
		R.Reset()
		eq(select(2, R.Receive("CHANNEL", "Peer-Realm", RoomMessage("class:DR", 9, "next session"), 1012)), "retired")
		eq(select(2, R.Receive("CHANNEL", "Peer-Realm", RoomMessage("race:4", 10, "and again"), 1013)), "retired")
		eq(#w.logs, 2); assert(w.logs[2]:find("class room", 1, true), w.logs[2])
	end)
end)

test("chat rooms (1.2.3): a saved race or class choice falls back without an error, and the old saved records go", function()
	WithRooms(function(w, R, c)
		c.db.chatRoomChoices = { race = "race:1", class = "class:WA" }
		c.db.chatRoomRequests = { ["member-realm|class:MA"] = { sentAt = w.epoch } }
		R.Reset() -- (what INIT does at login)
		eq(c.db.chatRoomChoices, nil); eq(c.db.chatRoomRequests, nil)
		local tabs = R.Tabs()
		eq(#tabs, 1); eq(tabs[1].id, "guild", "the default room")
		eq(R.IsOpen("race:1"), false); eq(R.IsOpen("class:WA"), false)
		eq(R.Receive("CHANNEL", "Peer-Realm", RoomMessage("race:1", 1, "the old choice"), 1000), false, "no subscription survives")
		eq(#R.History("race:1"), 0)
	end)
end)

-- (Changed in 1.2.3: two logical rooms' independent bounded histories, shown before with a race and
-- a class room, now with two restricted rooms.)
test("chat rooms: logical rooms keep independent bounded histories", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.departments[me] = true, "War"
		for i = 1, 7 do w.council["peer " .. i .. "-realm"] = true end
		w.departments["peer 2-realm"] = "War"
		eq(R.Receive("WHISPER", "Peer 1-Realm", RoomMessage("council", 1, "council one"), 1001), true)
		eq(R.Receive("WHISPER", "Peer 2-Realm", RoomMessage("dept:war", 2, "war one"), 1002), true)
		R.HISTORY = 3
		for i = 3, 7 do assert(R.Receive("WHISPER", "Peer " .. i .. "-Realm", RoomMessage("council", i, "line " .. i), 1000 + i)) end
		local history = R.History("council")
		eq(#history, 3); eq(history[1].text, "line 5"); eq(history[3].text, "line 7")
		eq(#R.History("dept:war"), 1, "another logical room is untouched")
	end)
end)

test("chat rooms: the new audiences have separate consent and old or malformed wires fail closed", function()
	WithRooms(function(w, R, c)
		c.db.chatRooms = nil
		local sent, why = R.Send("guild", "hello")
		eq(sent, false); eq(why, "off"); eq(w.asked[1], "chatrooms")
		eq(c.db.addonChat, true, "the existing Olympus chat consent is independent")
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 1, "old", "0"), 1000), false)
		c.db.chatRooms = true
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 1, "old", "0"), 1000), false)
		eq(R.Receive("CHANNEL", "Peer-Realm", RoomMessage("guild", 2, "wrong lane"), 1001), false)
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 3, "wrong guild", "1", "Olympus III"), 1002), false)
		w.logged = false
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 4, "not logged"), 1003), false)
		w.logged = true
		eq(R.Receive("GUILD", "Peer-Realm", RoomMessage("guild", 5, "good"), 1004), true)
		eq(R.History("guild")[1].text, "good")
	end)
end)

-- (Changed in 1.2.3: its second half, a class room's line refused once the Olympus channel moved,
-- went with the class rooms; Guild's native transport is unchanged.)
test("chat rooms: Guild uses native chat, never a hidden addon guild message", function()
	WithRooms(function(w, R)
		UnitClass = function() error("M2 must not inspect or publish the character's class") end
		assert(R.Send("guild", "guild line"))
		eq(#w.jobs, 0, "never a hidden addon guild message")
		eq(w.nativeSent[1][1], "guild line"); eq(w.nativeSent[1][2], "GUILD")
		eq(#R.History("guild"), 0, "wait for the server's native echo")
		assert(w.nativeEvents.CHAT_MSG_GUILD("guild line", "Member-Realm"))
		eq(R.History("guild")[1].text, "guild line")
		local roomChanged, roomLine = 0, 0
		for _, event in ipairs(w.events) do
			if event[1] == "CHAT_ROOM_CHANGED" then roomChanged = roomChanged + 1 end
			if event[1] == "CHAT_ROOM_LINE" then roomLine = roomLine + 1 end
		end
		eq(roomChanged, 1); eq(roomLine, 0, "a local echo must not create unread state")
	end)
end)

test("native Guild destination: actual server event, identical messages, bounded history and consent", function()
	WithRooms(function(w, R, c)
		local receive = assert(w.nativeEvents.CHAT_MSG_GUILD)
		assert(receive("same words", "Guildmate-Realm"))
		assert(receive("same words", "Guildmate-Realm"))
		eq(#R.History("guild"), 2, "intentional identical sequential guild lines remain distinct")
		eq(#w.jobs, 0); eq(#w.nativeSent, 0, "receive never republishes")
		c.db.chatRooms = false; eq(receive("hidden", "Guildmate-Realm"), false)
		c.db.chatRooms = true; w.member = false; eq(receive("outside", "Guildmate-Realm"), false)
		w.member = true; w.guild = "Another guild"; eq(#R.History("guild"), 0, "prior guild history cannot leak into a new guild")
		assert(receive("new guild", "Guildmate-Realm")); eq(#R.History("guild"), 1)
		R.HISTORY = 2
		assert(receive("second", "Guildmate-Realm")); assert(receive("third", "Guildmate-Realm"))
		eq(#R.History("guild"), 2); eq(R.History("guild")[1].text, "second")
		C_ChatInfo.SendChatMessage = function() error("native send rejected") end
		local ok, why = R.Send("guild", "not echoed"); eq(ok, false); eq(why, "failed")
		eq(#R.History("guild"), 2, "failed native send adds no optimistic line")
	end)
end)

-- (1.2.3: the outsider-request tests, the warning before a request and its two gates on both ends,
-- went with the race and class rooms, the only rooms that had outsiders. Below, Guild alone before
-- Roles: the Race and Class tabs are gone.)
test("chat rooms: restricted tabs and recipients come only from current shared authority", function()
	WithRooms(function(w, R, c)
		eq(#R.Tabs(), 1, "ordinary members get no restricted destination")
		local me = c.me:lower()
		w.council[me] = true
		c.rdb.council.names[me] = true -- an older retained signed-list representation
		c.rdb.council.names["other councillor"] = "Other Councillor"
		w.council["other councillor-realm"] = true
		local tabs = R.Tabs()
		eq(#tabs, 2); eq(tabs[2].kind, "role"); eq(tabs[2].dropdown, true)
		eq(R.Options("role")[1].id, "council")
		local recipients = R.Recipients("council")
		eq(#recipients, 3)
		local expected = { [c.FullName(w.king)] = true, [c.FullName(c.TREASURER)] = true, ["Other Councillor-Realm"] = true }
		for _, recipient in ipairs(recipients) do eq(expected[recipient], true, "Council includes the actual crown and federal treasurer") end

		local names = {
			["Federal Treasury"] = "Federal Treasury", ["Department of War"] = "Department of War",
			["Artisanship"] = "Association of Artisanry", ["Heraldry"] = "Department of Heraldry",
			["Justice"] = "Council of Justice",
		}
		for signed, canonical in pairs(names) do
			w.departments[me] = signed
			local options = R.Options("department")
			eq(#options, 1); eq(options[1].label, canonical, signed)
		end
		w.council[me] = nil
		eq(#R.Options("department"), 0, "a department string without signed Council authority grants nothing")
	end)
end)

test("chat rooms: a restricted room whispers no one the server says is offline (the roster's offline members, a name just not found)", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me] = true
		w.council["alpha-realm"], w.council["beta-realm"], w.council["gamma-realm"] = true, true, true
		c.rdb.council.names = { [me] = "Member", alpha = "Alpha", beta = "Beta", gamma = "Gamma" }
		c.Roster.members = { { name = "Alpha", online = true }, { name = "Beta", online = false } }
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		assert(R.Send("council", "first line"))
		local function Targets()
			local out = {}
			for _, job in ipairs(w.jobs) do out[job.target] = true end
			return out
		end
		local t = Targets()
		eq(t["Alpha-Realm"], true); eq(t["Beta-Realm"], nil, "offline in the roster"); eq(t["Gamma-Realm"], true, "not in the roster: tried")
		eq(#w.jobs, 4, "the King, the Treasurer, Alpha and Gamma")
		-- The server answers Gamma is not playing: the next line leaves him out, until GONE_FOR passes.
		w.nativeEvents.CHAT_MSG_SYSTEM("No player named 'Gamma-Realm' is currently playing.")
		w.clearJobs(); w.advance(10)
		assert(R.Send("council", "second line"))
		eq(Targets()["Gamma-Realm"], nil); eq(#w.jobs, 3)
		w.clearJobs(); w.advance(R.GONE_FOR)
		assert(R.Send("council", "third line"))
		eq(Targets()["Gamma-Realm"], true)
		ERR_CHAT_PLAYER_NOT_FOUND_S = nil
	end)
end)

-- (Changed in 1.2.3: shown before in a race room; the share is every room's, here the Council's.)
test("chat rooms: a room gives each sender a fair share of its minute (PER_MINUTE), so one sender cannot crowd the others out", function()
	WithRooms(function(w, R, c)
		w.council[c.me:lower()], w.council["loud one-realm"], w.council["quiet two-realm"] = true, true, true
		for i = 1, R.PER_MINUTE do eq(R.Receive("WHISPER", "Loud One-Realm", RoomMessage("council", i, "line " .. i), 1000 + i), true) end
		eq(R.Receive("WHISPER", "Loud One-Realm", RoomMessage("council", 50, "one too many"), 1010), false, "past his share")
		eq(R.Receive("WHISPER", "Quiet Two-Realm", RoomMessage("council", 51, "still heard"), 1011), true, "another sender")
		eq(R.Receive("WHISPER", "Loud One-Realm", RoomMessage("council", 52, "a minute later"), 1062), true)
	end)
end)

assert(loadfile(ROOT .. "tests/chat-role-rooms.lua"))(ns, test, eq, WithRooms, RoomMessage)
-- (1.2.4: the role rooms the author asked for.)
assert(loadfile(ROOT .. "tests/chat-rooms-124.lua"))(ns, test, eq, WithRooms, RoomMessage)

test("chat rooms: restricted delivery is whisper-only, all-or-none on admission, and revocable in queue", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me] = true
		w.council["alpha-realm"], w.council["beta-realm"] = true, true
		c.rdb.council.names = { [me] = "Member", alpha = true, beta = "Beta" }
		assert(R.Send("council", "private line"))
		eq(#w.jobs, 4)
		local expected = { [c.FullName(w.king)] = true, [c.FullName(c.TREASURER)] = true, ["alpha-Realm"] = true, ["Beta-Realm"] = true }
		for _, job in ipairs(w.jobs) do eq(job.dist, "WHISPER"); eq(job.logged, true); eq(expected[job.target], true, "only the current Council audience") end
		w.council["alpha-realm"] = nil
		for _, job in ipairs(w.jobs) do
			local permitted = w.finish(job, true)
			if job.target:lower() == "alpha-realm" then eq(permitted, false) else eq(permitted, true) end
		end
		eq(#R.History("council"), 1, "a successful recipient produces one local echo")

		R.Reset(); w.clearJobs(); w.advance(2)
		w.council["alpha-realm"] = true
		w.rejectAt = 2
		local admitted = R.Send("council", "must be whole")
		eq(admitted, false); eq(#w.jobs, 0, "an admitted prefix is cancelled after a synchronous refusal")
		eq(#R.History("council"), 0)

		R.Reset(); w.clearJobs(); w.advance(2); w.rejectAt = nil
		assert(R.Send("council", "sender can be revoked"))
		w.council[me] = nil
		for _, job in ipairs(w.jobs) do eq((w.finish(job, true)), false, "sender authority checked at final send") end
		eq(#R.History("council"), 0)
	end)
end)

test("chat rooms: spoofed restricted senders are dropped and revocation erases retained history", function()
	WithRooms(function(w, R, c)
		local me = c.me:lower()
		w.council[me], w.council["peer-realm"] = true, true
		c.rdb.council.names = { [me] = "Member", peer = "Peer" }
		local msg = RoomMessage("council", 1, "classified")
		eq(R.Receive("CHANNEL", "Peer-Realm", msg, 1000), false, "wrong transport")
		eq(R.Receive("WHISPER", "Outsider-Realm", msg, 1001), false, "not in the signed audience")
		eq(R.Receive("WHISPER", "Peer-Realm", msg, 1002), true)
		eq(#R.History("council"), 1)
		w.council[me] = nil
		eq(R.RefreshAuthority(), true)
		w.council[me] = true
		eq(#R.History("council"), 0, "revoked restricted history is discarded, not merely hidden")
	end)
end)

-- 1.2 (CraftRequests.lua's private request rooms): a later file can own private rooms. The provider
-- alone answers for them; nothing of them goes over M2, and the rooms' own consent is untouched.
test("chat rooms: a provider's private rooms answer for themselves, never ride M2, and leave the rooms' consent alone", function()
	WithRooms(function(w, R, c)
		local sent, heard = {}, { { sender = "Wren Thistle-Realm", text = "context" } }
		local p = {
			Info = function(id) if id == "craft:abc1" then return { id = id, kind = id, label = "Mooncloth", scope = "private" } end end,
			CanAccess = function(id, name) return id == "craft:abc1" and (name == "Member-Realm" or name == "Wren Thistle-Realm") end,
			History = function() return heard end,
			Send = function(id, text) sent[#sent + 1] = text return true, "ok" end,
			Tabs = function() return { { kind = "craft:abc1", id = "craft:abc1", label = "Mooncloth" } } end,
			IsOpen = function() return true end,
			ChatOn = function() return true end,
		}
		eq(R.RegisterProvider({ Info = function() end }), false, "an incomplete provider is refused")
		eq(R.RegisterProvider(p), true); eq(R.RegisterProvider(p), true, "once")
		local tabs = R.Tabs()
		eq(tabs[#tabs].id, "craft:abc1")
		eq(R.Info("craft:abc1").scope, "private")
		eq(R.CanAccess("craft:abc1"), true); eq(R.CanAccess("craft:abc1", "Stranger-Realm"), false)
		c.db.chatRooms = false
		eq(R.ChatOn(), false, "the rooms' consent is the player's")
		eq(R.ChatOn("guild"), false)
		eq(R.ChatOn("craft:abc1"), true, "the provider's room answers for itself")
		eq(R.Select("craft:abc1"), true)
		eq(R.History("craft:abc1")[1].text, "context")
		eq(R.Send("craft:abc1", "a fellow-member price?"), true)
		eq(sent[1], "a fellow-member price?"); eq(#w.jobs, 0, "nothing queued by the rooms themselves")
		c.db.chatRooms = true
		eq(R.Receive("WHISPER", "Wren Thistle-Realm", RoomMessage("craft:abc1", 1, "over M2"), 1000), false, "an M2 line never lands in a provider's room")
		-- (1.2.3: no request status to ask any more: the outsider requests went with the race and class rooms.)
	end)
end)

-- 1.2.4 (the author, in the Church's room: "Eu dou Enter para enviar a mensagem na igreja e não
-- aparece a mensagem. No histórico, não aparece nada e não me avisa por que não foi"): the line
-- showed in its sender's history only once the last of its whispers had left (Comm sends one every
-- 1.2 s: eight members online, ten seconds; behind a census transfer, over a minute), with the box
-- already empty; and nobody else of the room online kept it on his screen alone, without a word.
-- Now the line shows at Enter, marked as sending, and settles once its whispers left; a line that
-- cannot go is refused with its reason (the Chat page's note). The audience is the room's own: the
-- room registered as Church.lua registers the Church's.
local function ChurchLike(w, R, c, count)
	local audience, online = { [c.me:lower()] = true }, {}
	for i = 1, count do
		local name = "Brother " .. string.char(96 + i) .. "-Realm"
		audience[name:lower()], online[#online + 1] = true, name
	end
	assert(R.RegisterAudience("church", { label = "Church",
		CanAccess = function(name) return audience[c.FullName(name or c.me):lower()] == true end,
		Recipients = function() return online end }))
	return audience, online
end
local function Fired(w, name)
	local out = {}
	for _, e in ipairs(w.events) do if e[1] == name then out[#out + 1] = e end end
	return out
end

test("chat rooms (1.2.4): a role room's line shows in its sender's history at Enter, marked sending, and settles once every whisper left", function()
	WithRooms(function(w, R, c)
		local audience, online = ChurchLike(w, R, c, 8)
		local ok, why = R.Send("church", "hello brothers")
		eq(ok, true); eq(why, "ok")
		eq(#w.jobs, 8, "one whisper to each audience member online")
		local to = {}
		for _, job in ipairs(w.jobs) do
			eq(job.dist, "WHISPER"); eq(job.logged, true); eq(audience[job.target:lower()], true, "only the room's audience")
			to[job.target] = true
		end
		for _, name in ipairs(online) do eq(to[name], true, name) end
		local history = R.History("church")
		eq(#history, 1, "the sender's own line shows at Enter")
		eq(history[1].text, "hello brothers"); eq(history[1].mine, true)
		eq(history[1].pending, true, "marked as still sending")
		for i = 1, 7 do w.finish(w.jobs[i], true) end
		eq(#R.History("church"), 1); eq(R.History("church")[1].pending, true, "still sending while one whisper waits")
		w.finish(w.jobs[8], true)
		eq(#R.History("church"), 1, "one line, not a second echo")
		eq(R.History("church")[1].pending, nil, "settled once every whisper left")
		eq(#Fired(w, "CHAT_ROOM_SEND_FAILED"), 0, "nothing failed")
		for _, e in ipairs(Fired(w, "CHAT_ROOM_LINE")) do assert(e[2] ~= "church", "a local echo makes no unread count") end
	end)
end)

test("chat rooms (1.2.4): a line none of whose whispers left goes from the sender's history and the page is told; one that reached some stays", function()
	WithRooms(function(w, R, c)
		local audience = ChurchLike(w, R, c, 3)
		assert(R.Send("church", "nobody will hear"))
		eq(#R.History("church"), 1, "shown at Enter"); eq(R.History("church")[1].pending, true)
		-- Every recipient left the audience while the line waited: each permit refuses it.
		for _, job in ipairs(w.jobs) do audience[job.target:lower()] = nil end
		for _, job in ipairs(w.jobs) do eq((w.finish(job, true)), false, "the permit refuses " .. job.target) end
		eq(#R.History("church"), 0, "nothing reached anyone: not shown as said")
		local failed = Fired(w, "CHAT_ROOM_SEND_FAILED")
		eq(#failed, 1); eq(failed[1][2], "church"); eq(failed[1][3], "revoked", "the reason the page shows")
		eq(failed[1][4], "nobody will hear", "the words, to put back"); eq(failed[1][5], 0, "reached nobody")

		w.clearJobs(); w.events = {}; w.advance(2)
		for i = 1, 3 do audience[("brother " .. string.char(96 + i) .. "-realm")] = true end
		assert(R.Send("church", "two of three"))
		-- (The review: the lost whisper's own reason, Comm's "dropped" (its queue made room), not the
		-- last whisper to finish's: that one left, and "failed" alone could not tell the two apart.)
		w.finish(w.jobs[1], true); w.finish(w.jobs[2], false, "dropped"); w.finish(w.jobs[3], true)
		eq(#R.History("church"), 1, "reached two: shown")
		eq(R.History("church")[1].pending, nil)
		failed = Fired(w, "CHAT_ROOM_SEND_FAILED")
		eq(#failed, 1); eq(failed[1][3], "dropped", "the lost whisper's reason"); eq(failed[1][5], 2, "reached two")
	end)
end)

test("chat rooms (1.2.4): with nobody else of the room online the line is refused as alone: nothing sent, nothing kept, and the next try is not too fast", function()
	WithRooms(function(w, R, c)
		local audience, online = ChurchLike(w, R, c, 0)
		audience["brother a-realm"] = true -- in the room, not online yet
		local ok, why = R.Send("church", "anyone?")
		eq(ok, false); eq(why, "alone", "the reason the page shows")
		eq(#w.jobs, 0, "no whisper"); eq(w.attempts, 0)
		eq(#R.History("church"), 0, "not kept as if said")
		online[1] = "Brother a-Realm"
		ok, why = R.Send("church", "anyone now?")
		eq(ok, true, "a refused line does not count against the send gap"); eq(why, "ok")
		eq(#w.jobs, 1)
	end)
end)

test("chat rooms (1.2.4): a refusal returns its reason before any whisper, and an admission refused part way leaves no line and no late note", function()
	WithRooms(function(w, R, c)
		ChurchLike(w, R, c, 3)
		assert(R.Send("church", "first"))
		local ok, why = R.Send("church", "at once again")
		eq(ok, false); eq(why, "fast")
		w.advance(2)
		w.guild = nil
		ok, why = R.Send("church", "no guild yet")
		eq(ok, false); eq(why, "guild")
		w.guild = "Olympus II"
		ok, why = R.Send("church", ("x"):rep(R.TEXT_MAX + 40))
		eq(ok, true, "a long line is cut to the room's length, not refused")
		eq(#R.History("church"), 2, "both lines shown at Enter"); eq(#R.History("church")[2].text, R.TEXT_MAX)
		w.clearJobs(); w.events = {}; w.advance(2)
		w.rejectAt = 2
		ok, why = R.Send("church", "must be whole")
		-- (The review: Comm's own reason for the whisper it refused at once, its queue full here, as
		-- Comm's Enqueue says it; no longer "busy" for any refusal at all.)
		eq(ok, false); eq(why, "full")
		eq(#w.jobs, 0, "the admitted prefix cancelled")
		eq(#R.History("church"), 2, "no line for a refused send")
		eq(#Fired(w, "CHAT_ROOM_SEND_FAILED"), 0, "refused at Enter: the page says it there, once, and the words stay in the box")
		eq(R.Own("church"), true); eq(R.Own("guild"), true); eq(R.Own("council"), true); eq(R.Own("dept:war"), true)
		eq(R.Own("no such room"), false)
	end)
end)

-- 1.2.4 (the review): Comm refuses a whisper at once by calling its done before it returns (Refuse:
-- "left", "held", "guard"; a full queue). The room's only member online refused so: the line is
-- refused with that reason, nothing kept, and no late "not sent" note on top of the page's own (the
-- send settles only once every whisper was handed over). A provider's room is not this file's own.
test("chat rooms (1.2.4): a whisper refused at once, the room's only one, gives Comm's reason and leaves no line and no late note; a provider's room is not this file's", function()
	WithRooms(function(w, R, c)
		ChurchLike(w, R, c, 1)
		w.rejectAt = 1
		local ok, why = R.Send("church", "only one to hear")
		eq(ok, false); eq(why, "full", "Comm's reason")
		eq(#w.jobs, 0); eq(#R.History("church"), 0, "nothing kept as if said")
		eq(#Fired(w, "CHAT_ROOM_SEND_FAILED"), 0, "refused at Enter: no late note on top of the page's")
		w.clearJobs()
		ok, why = R.Send("church", "only one to hear")
		eq(ok, true, "a refused line does not count against the send gap"); eq(why, "ok")
		eq(#w.jobs, 1); eq(#R.History("church"), 1)

		eq(R.RegisterProvider({
			Info = function(id) if id == "craft:abc1" then return { id = id, kind = id, label = "Mooncloth", scope = "private" } end end,
			CanAccess = function(id) return id == "craft:abc1" end,
			History = function() return {} end,
			Send = function() return false, "closed" end,
		}), true)
		eq(R.Own("craft:abc1"), false, "a provider's room answers for itself")
		eq(R.Own("church"), true, "the Church's room is this file's")
	end)
end)

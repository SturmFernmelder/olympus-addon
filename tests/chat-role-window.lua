local ns, test, eq, WithWindow, WithGamepadUI = ...

test("watch chat context menu: actions are opt-in and recheck permission and target", function()
	WithWindow(function(w)
		local saved, allowed, calls, timed = rawget(ns, "WatchChat"), true, {}, true
		rawset(ns, "WatchChat", {
			StripText = function() return nil end, RecordLines = function() return {} end,
			CanModerateAny = function() return true end,
			CanModerateEntry = function() return allowed end,
			TimeoutOf = function() return timed end,
			AskEntry = function() error("initial action modal must not open") end,
			AskWhy = function(data, op) calls[#calls + 1] = { op, data.entry, data.chat } end,
			AskName = function(name, op) calls[#calls + 1] = { op, name } end,
		})
		local ok, err = pcall(function()
			local f = w.CW.Open("A")
			local b = CreateFrame("Frame", nil, f)
			b:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -130); b:SetSize(200, 30)
			b.chat, b.entry = "A", { sender = "Example-Realm", text = "line", id = 123 }
			local e = b.entry
			eq(w.CW.ModerateLine(b), true); eq(f.subMenu:IsShown(), true); eq(#calls, 0)
			eq(f.subMenu.rows[1].text:GetText(), ns.L.WATCHCHAT_DELETE_LINE)
			w.fire("DATA_CHANGED"); eq(f.subMenu:IsShown(), true)
			f.subMenu.rows[1]:Click(); eq(calls[1][1], "D"); eq(calls[1][2], e); eq(calls[1][3], "A")
			for i, op in ipairs({ "timeout", "purge", "lift" }) do
				w.CW.ModerateLine(b); f.subMenu.rows[i + 1]:Click(); eq(calls[i + 1][1], op)
			end
			w.CW.ModerateLine(b); allowed = false; f.subMenu.rows[1]:Click(); eq(#calls, 4, "stale callback cannot moderate")
			allowed = true; w.CW.ModerateLine(b); allowed = false; w.fire("WATCHCHAT_CHANGED"); eq(f.subMenu:IsShown(), false)
			allowed = true; w.CW.ModerateLine(b); b.entry = { sender = "Other-Realm" }; f.subMenu.rows[1]:Click(); eq(#calls, 4, "reused bubble cannot change the target")
			b.entry = e; w.CW.ModerateLine(b); e.del = true; w.fire("DATA_CHANGED"); eq(f.subMenu:IsShown(), false)
			e.del = nil; timed = false; w.CW.ModerateLine(b); eq(f.subMenu.rows[4]:IsShown(), false)
			f.subCatcher:Click(); eq(f.subMenu:IsShown(), false)
		end)
		rawset(ns, "WatchChat", saved)
		if not ok then error(err, 0) end
	end)
end)

-- (Changed in 1.2.3: shown before with the Race dropdown, gone with the race rooms; the Roles
-- dropdown of a High Councillor behaves the same.)
test("chat destination dropdown: unchanged census redraw keeps menu open; selection and outside click close it", function()
	WithWindow(function(w)
		local council = ns.IsHighCouncillor
		ns.IsHighCouncillor = function(name) return name == nil or name == ns.me end
		local ok, err = pcall(function()
			ns.db.chatRooms = true
			local f = w.CW.Open("A")
			local roles
			for _, button in ipairs(f.subtabs.nav) do if button:IsShown() and button.item.entry.kind == "role" then roles = button end end
			assert(roles); roles:Click(); eq(f.subMenu:IsShown(), true)
			w.fire("DATA_CHANGED"); w.CW.Render()
			eq(f.subMenu:IsShown(), true, "ordinary census refresh must not eat the user's dropdown")
			f.subCatcher:Click(); eq(f.subMenu:IsShown(), false)
			roles:Click(); eq(f.subMenu.rows[1].roomId, "council"); f.subMenu.rows[1]:Click()
			eq(f.subMenu:IsShown(), false); eq(w.CW.Tier(), "council")
		end)
		ns.IsHighCouncillor = council
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.3 (the author: "remove class and race chats from chat tab... no one uses them"): a Chat page
-- last left on a race or class room (its saved room, the old saved choices, a draft) opens on its
-- channel without an error, shows no Race or Class tab, and refuses one asked for by name.
test("Chat tab (1.2.3): a page last left on a race or class room opens on its channel, and no Race or Class tab shows", function()
	WithWindow(function(w)
		local R = ns.ChatRooms
		ns.db.chatRooms = true
		ns.db.chatRoomChoices = { race = "race:1", class = "class:WA" }
		R.Reset()
		ns.db.chatWin = { tier = "A", room = "race:1" }
		w.CW.drafts["race:1"] = "an old race draft"
		local f = assert(w.CW.Open(), "the Chat tab opens")
		eq(w.CW.Tier(), "A", "the channel last shown, not the race room")
		eq(f.input:GetText(), "", "the race room's draft is not the box's")
		local kinds = {}
		for _, b in ipairs(f.subtabs.nav) do if b:IsShown() then kinds[#kinds + 1] = b.item.entry.kind end end
		eq(table.concat(kinds, ","), "global,guild,arena", "no Race or Class tab")
		eq(w.CW.SelectLogical("class:WA"), false, "one asked for by name is refused")
		eq(w.CW.Tier(), "A"); eq(w.printed[#w.printed], ns.L.CHATROOM_NO_ACCESS)
		eq(w.CW.SelectLogical("race:95"), false); eq(w.CW.Tier(), "A")
		w.CW.Render()
		eq(w.CW.Tier(), "A", "a redraw keeps the channel")
	end)
end)

test("role chat navigation: real dropdown redraws with the preview without opening private history", function()
	WithWindow(function(w)
		local R, V = ns.ChatRooms, ns.ViewAs
		local saved = { preview = V.Previewing, role = V.Role, council = ns.IsHighCouncillor, history = R.History }
		local ok, err = pcall(function()
			local role, council, reads = "member", false, 0
			V.Previewing = function() return role ~= "my" end
			V.Role = function() return role end
			ns.IsHighCouncillor = function() return council end
			R.History = function(id) if id == "council" then reads = reads + 1 end return {} end
			ns.db.chatRooms = true
			local f = w.CW.Open("A")
			local function Tab(kind)
				for _, b in ipairs(f.subtabs.nav) do if b:IsShown() and b.item.entry.kind == kind then return b end end
			end
			-- (1.2.3: no Race or Class tab any more.)
			for _, kind in ipairs({ "global", "guild", "arena" }) do assert(Tab(kind), kind) end
			eq(Tab("race"), nil); eq(Tab("class"), nil); eq(Tab("role"), nil)
			role = "king"; w.fire("DATA_CHANGED"); w.CW.Render()
			assert(Tab("role")); eq(Tab("authority"), nil); eq(Tab("department"), nil); eq(Tab("church"), nil)
			w.fire("CHAT_ROOM_LINE", "council"); w.CW.Render()
			eq(Tab("role").label:GetText():find("(1)", 1, true), nil, "preview does not reveal private unread counts")
			Tab("role"):Click()
			eq(f.subMenu:IsShown(), true); eq(f.subMenu.rows[1].roomId, "council")
			eq(f.subMenu.rows[2].roomId, "secretariat")
			f.subMenu.rows[1]:Click()
			eq(w.CW.Tier(), "A"); eq(reads, 0)
			eq(w.printed[#w.printed], ns.L.CHATROOM_ROLE_PREVIEW)
			role = "councillor"; w.fire("DATA_CHANGED"); w.CW.Render()
			eq(f.subMenu:IsShown(), false, "stale popup closes when the view changes")
			Tab("role"):Click(); eq(f.subMenu.rows[2].roomId, "dept:treasury")
			council = true
			eq(w.CW.SelectLogical("council"), false, "real authority does not unlock a preview")
			eq(reads, 0)
			role = "my"; w.fire("DATA_CHANGED"); w.CW.Render()
			Tab("role"):Click(); f.subMenu.rows[1]:Click()
			eq(w.CW.Tier(), "council"); eq(reads > 0, true)
			eq(Tab("role").underline:IsShown(), true, "all restricted rooms select the single role tab")
			local before = reads
			role = "member"; w.fire("DATA_CHANGED"); w.CW.Render()
			eq(Tab("role"), nil); eq(w.CW.Tier(), "A"); eq(reads, before, "private room leaves the screen under a preview")
		end)
		V.Previewing, V.Role, ns.IsHighCouncillor, R.History = saved.preview, saved.role, saved.council, saved.history
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.1, the author's ask: a member who moderates nobody right-clicks another player's line of the
-- public Olympus channel, on its words or on its name, and reports that very line (Report to
-- Olympus, The Watch's: Watch.LineMessage says whether it may go, Watch.AskReport asks). Before,
-- the right-click did nothing for him.
test("chat: an ordinary member right-clicks another player's Olympus line, its words or its name, and reports that line", function()
	WithWindow(function(w)
		local C = ns.Channels
		local saved = { history = C.History, watch = rawget(ns, "Watch"), wc = rawget(ns, "WatchChat") }
		local theirs = { t = 100, sender = "Rude Guy-Realm", guild = "Olympus II", text = "rude words" }
		local mine = { t = 101, sender = ns.me, guild = "Olympus II", text = "my own words", mine = true }
		local asked, reported = {}, {}
		C.History = function(t) if t == "A" then return { theirs, mine } end return {} end
		rawset(ns, "WatchChat", { StripText = function() return nil end, RecordLines = function() return {} end,
			CanModerateAny = function() return false end, CanModerateEntry = function() return false end })
		rawset(ns, "Watch", {
			LineMessage = function(entry, chat)
				asked[#asked + 1] = { entry = entry, chat = chat }
				if entry == theirs and chat == "A" and not entry.del then return { sender = entry.sender, t = entry.t, text = entry.text, tier = "A" } end
			end,
			AskReport = function(name, message) reported[#reported + 1] = { name = name, message = message } return true end,
		})
		local ok, err = pcall(function()
			local f = w.CW.Open("A")
			local function BubbleOf(e)
				for _, b in ipairs(f.bubbles) do if b:IsShown() and b.entry == e then return b end end
				error("no bubble for " .. tostring(e.text))
			end
			local b = BubbleOf(theirs)
			b:Fire("OnMouseUp", "RightButton")
			eq(f.subMenu:IsShown(), true, "the right-click opens the line's menu")
			eq(f.subMenu.rows[1].text:GetText(), ns.L.WATCH_REPORT); eq(f.subMenu.rows[2]:IsShown(), false, "one choice")
			eq(asked[#asked].entry, theirs); eq(asked[#asked].chat, "A", "asked about that line, in the Olympus channel")
			eq(#reported, 0, "nothing before the click")
			w.fire("DATA_CHANGED"); eq(f.subMenu:IsShown(), true, "a census redraw leaves it open")
			f.subMenu.rows[1]:Click()
			eq(#reported, 1); eq(reported[1].name, "Rude Guy-Realm")
			eq(reported[1].message.t, 100); eq(reported[1].message.text, "rude words"); eq(reported[1].message.tier, "A")
			eq(f.subMenu:IsShown(), false)
			-- On his name (the header) too; a left click there stays the whisper's.
			b.header:Fire("OnMouseUp", "LeftButton"); eq(f.subMenu:IsShown(), false)
			b.header:Fire("OnMouseUp", "RightButton"); eq(f.subMenu:IsShown(), true, "the name's right-click")
			-- The bubble showing another line by the click: nothing reported.
			b.entry = { t = 102, sender = "Other-Realm", text = "other words" }
			f.subMenu.rows[1]:Click(); eq(#reported, 1, "a reused bubble cannot change the line")
			b.entry = theirs
			-- A line deleted meanwhile: its menu closes.
			w.CW.ModerateLine(b); eq(f.subMenu:IsShown(), true)
			theirs.del = true; w.fire("DATA_CHANGED"); eq(f.subMenu:IsShown(), false, "closed once it may no longer go")
			theirs.del = nil
			-- His own line: no menu, and nothing asked.
			local n = #asked
			eq(w.CW.ModerateLine(BubbleOf(mine)), false); eq(f.subMenu:IsShown(), false); eq(#asked, n)
			-- A client updated without a restart (The Watch a stand-in): nothing.
			rawset(ns, "Watch", { missing = true })
			eq(w.CW.ModerateLine(b), false); eq(f.subMenu:IsShown(), false)
		end)
		C.History = saved.history
		rawset(ns, "Watch", saved.watch); rawset(ns, "WatchChat", saved.wc)
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.4, the author ("mandar mensagem como desenvolvedor"): "The Royal Dev" after his name on each
-- of his lines of the Chat tab, a tag (no mark before a name since 1.1.5); nobody else's.
test("Chat tab (1.2.4): the author's lines carry The Royal Dev after his name, nobody else's", function()
	WithWindow(function(w)
		local C = ns.Channels
		local saved = { history = C.History, borders = ns.Borders }
		local dev, other = "Quill Wright-Realm", "Plain Writer-Realm"
		C.History = function(t)
			if t ~= "A" then return {} end
			return { { t = 100, sender = dev, guild = "Olympus II", text = "a word from the dev" },
				{ t = 400, sender = other, guild = "Olympus II", text = "thanks" } }
		end
		ns.Borders = setmetatable({ IsDevName = function(name) return ns.FullName(name) == dev end }, { __index = saved.borders })
		local ok, err = pcall(function()
			local f = w.CW.Open("A")
			local heads = {}
			for _, b in ipairs(f.bubbles) do
				if b:IsShown() and b.entry and b.header:IsShown() then heads[b.entry.sender] = b.who:GetText() end
			end
			assert(heads[dev] and heads[dev]:find("The Royal Dev", 1, true), tostring(heads[dev]))
			assert(heads[dev]:find("Quill Wright", 1, true) < heads[dev]:find("The Royal Dev", 1, true), "after his name")
			assert(heads[other] and not heads[other]:find("The Royal Dev", 1, true), tostring(heads[other]))
			eq(ns.L.CHATWIN_TAG_DEV, "The Royal Dev")
		end)
		C.History, ns.Borders = saved.history, saved.borders
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.4 (the author: "para mim, que estou em 200 rows, ou para quem está no rankals, que também tem
-- um monte, pode não ficar atualizando o tempo todo, talvez. Tem uma atualização mais lenta, de 1
-- minuto em 1 minuto"): a line in a room not shown is only counted; the destinations' rooms are
-- listed again when the tab opens, and else at most once a minute (never at the census's redraw);
-- the room shown stays live.
test("Chat tab (1.2.4): a line in a room not shown is only counted, no redraw; the rooms are listed at the opening and at most once a minute after; the room shown stays live", function()
	WithWindow(function(w)
		local council, savedTime = ns.IsHighCouncillor, GetTime
		local real = w.CW.Render
		local clock = 1000
		local ok, err = pcall(function()
			GetTime = function() return clock end
			ns.IsHighCouncillor = function(name) return name == nil or name == ns.me end
			ns.db.chatRooms = true
			local renders = 0
			w.CW.Render = function(...) renders = renders + 1; return real(...) end
			local f = w.CW.Open("A")
			local function Tick(s) clock = clock + s; f:Fire("OnUpdate", s) end
			local function Roles()
				for _, b in ipairs(f.subtabs.nav) do if b:IsShown() and b.item.entry.kind == "role" then return b end end
			end
			Tick(0.3)
			local builds = w.CW.navBuilds
			renders = 0
			for i = 1, 20 do w.fire("CHAT_ROOM_LINE", "council", "Peer-Realm", "line " .. i); Tick(0.3) end
			eq(renders, 0, "twenty lines in a room not shown: no redraw")
			eq(w.CW.navBuilds, builds, "nor a listing of the rooms")
			-- The census's notices redraw the tab (DATA_GAP) and list no room.
			for _ = 1, 10 do w.fire("DATA_CHANGED"); Tick(5.1) end
			assert(renders > 0, "the census's redraws")
			eq(w.CW.navBuilds, builds, "the census's redraws list no room")
			assert(Roles().label:GetText():find("(20)", 1, true), "the count drawn at a redraw: " .. Roles().label:GetText())
			Tick(w.CW.NAV_EVERY - 51 + 0.3)
			eq(w.CW.navBuilds, builds + 1, "listed again once the minute went by")
			Tick(30); eq(w.CW.navBuilds, builds + 1, "not before the next minute")
			-- The room shown is live.
			assert(w.CW.SelectLogical("council"))
			renders = 0
			w.fire("CHAT_ROOM_LINE", "council", "Peer-Realm", "in the room shown")
			Tick(0.3)
			eq(renders, 1, "a line in the room shown: drawn at the next look")
			-- Opening the tab lists them at once.
			builds = w.CW.navBuilds
			w.CW.Window():Hide()
			w.CW.Open("A")
			eq(w.CW.navBuilds, builds + 1, "listed at the opening")
		end)
		w.CW.Render, GetTime, ns.IsHighCouncillor = real, savedTime, council
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.4: the Roles list had ten rows, made with the tab, and every option wrote to one: an eleventh
-- room stopped it from opening (the King's preview already filled the ten; the author's own view,
-- in every room but the High Council's, has dozens). Any number of rooms now: a long list folds
-- each group into one row whose click opens its own list beside it, a list still longer pages, and
-- every room is a click or a few away, with the mouse and with the gamepad UI (the cursor clicks
-- Olympus's own buttons; no game menu, no key).
local function AuthorsRoles(w, gamepad)
	local saved = { isAuthor = ns.Workshop.IsAuthorName, approved = ns.ApprovedGuilds, guilds = ns.rdb.guilds }
	local ok, err = pcall(function()
		local R = ns.ChatRooms
		ns.db.chatRooms = true
		ns.Workshop.IsAuthorName = function(name) return ns.FullName(name) == ns.me end
		ns.ApprovedGuilds = function() return {} end
		ns.rdb.guilds = {}
		local base = #R.Options("role")
		local k = 0
		while base + 2 * k < 34 do
			k = k + 1
			ns.rdb.guilds[("Olympus Guild %02d"):format(k)] = { t = 1 }
		end
		local options = R.Options("role")
		assert(#options >= 34, "the author's rooms: " .. #options)
		local f = w.CW.Open("A")
		local function Roles()
			for _, b in ipairs(f.subtabs.nav) do if b:IsShown() and b.item.entry.kind == "role" then return b end end
		end
		local function Rows(menu)
			local out = {}
			for _, r in ipairs(menu.rows) do if r:IsShown() then out[#out + 1] = r end end
			return out
		end
		local function Labels(menu)
			local out = {}
			for _, r in ipairs(Rows(menu)) do out[#out + 1] = r.text:GetText() end
			return table.concat(out, " | ")
		end
		assert(Roles(), "Roles"):Click()
		eq(f.subMenu:IsShown(), true, "the list opens")
		local top = Rows(f.subMenu)
		assert(#top <= 10, "ten rows at most: " .. Labels(f.subMenu))
		eq(top[1].roomId, "masters"); eq(top[2].roomId, "allcenturions")
		assert(top[3].text:GetText():find("^Departments %(6%) >"), top[3].text:GetText())
		local groups = 0
		for _, r in ipairs(top) do if r.groupItem then groups = groups + 1 end end
		assert(groups >= 3, "the departments' and each kind of guild room folded: " .. Labels(f.subMenu))
		-- A group's own list: beside the first, paged past ten; a census redraw leaves both open.
		local cent
		for _, r in ipairs(top) do if r.groupItem and r.groupItem.group == "gcent" then cent = r end end
		assert(cent, "the guilds' masters and centurions: " .. Labels(f.subMenu))
		cent:Click()
		eq(f.subMenu:IsShown(), true); eq(f.subMenu2:IsShown(), true, "its own list")
		local rows = Rows(f.subMenu2)
		eq(#rows, 9, "eight rooms and More"); assert(rows[9].text:GetText():find("^More %(%d+%)"), rows[9].text:GetText())
		-- Beside the first list, on its left where the tab has the room, and inside the tab always.
		local child, menu = f.subMenu2, f.subMenu
		assert(child:GetLeft() >= f:GetLeft() and child:GetRight() <= f:GetRight(), "inside the tab")
		assert(child:GetRight() <= menu:GetLeft() - 2 or child:GetLeft() == f:GetLeft() + 12,
			("on the first list's left, or at the tab's left edge: %s-%s, %s-%s"):format(child:GetLeft(), child:GetRight(), menu:GetLeft(), menu:GetRight()))
		w.fire("DATA_CHANGED"); w.CW.Render()
		eq(f.subMenu2:IsShown(), true, "a census redraw keeps it"); eq(f.subMenu:IsShown(), true)
		rows[9]:Click()
		rows = Rows(f.subMenu2)
		eq(rows[1].text:GetText(), "Previous"); eq(f.subMenu:IsShown(), true)
		rows[1]:Click(); eq(#Rows(f.subMenu2), 9, "back to the first page")
		f.subCatcher:Click()
		eq(f.subMenu:IsShown(), false); eq(f.subMenu2:IsShown(), false, "a click outside closes both")
		-- Every room reached by clicks alone: the list, a group's list, its pages.
		local function Reach(id)
			Roles():Click()
			local function Pick(menu)
				for _ = 1, 20 do
					local more
					for _, r in ipairs(Rows(menu)) do
						if r.roomId == id then r:Click() return true end
						if r.pageTo and r.text:GetText():find("^More") then more = r end
					end
					if not more then return false end
					more:Click()
				end
				return false
			end
			if Pick(f.subMenu) then return true end
			for i = 1, 20 do
				local parents = {}
				for _, r in ipairs(Rows(f.subMenu)) do if r.groupItem then parents[#parents + 1] = r end end
				for _, r in ipairs(parents) do
					r:Click()
					if Pick(f.subMenu2) then return true end
				end
				local more
				for _, r in ipairs(Rows(f.subMenu)) do if r.pageTo and r.text:GetText():find("^More") then more = r end end
				if not more then return false end
				more:Click()
			end
			return false
		end
		for _, option in ipairs(options) do
			assert(Reach(option.id), (gamepad and "gamepad: " or "") .. "reached: " .. option.id)
			eq(f.subMenu:IsShown(), false, option.id); eq(f.subMenu2:IsShown(), false, option.id .. ": both lists close")
			eq(w.CW.Tier(), option.id, option.id)
		end
	end)
	ns.Workshop.IsAuthorName, ns.ApprovedGuilds, ns.rdb.guilds = saved.isAuthor, saved.approved, saved.guilds
	if not ok then error(err, 0) end
end

test("Chat tab (1.2.4): thirty-four rooms in the Roles list (the author's): grouped and paged, each room a click or a few away, both lists closing", function()
	WithWindow(function(w) AuthorsRoles(w, false) end)
end)

test("Chat tab (1.2.4): thirty-four rooms in the Roles list with the gamepad UI: the same lists, Olympus's own buttons, every room reached", function()
	WithGamepadUI(true, function()
		WithWindow(function(w) AuthorsRoles(w, true) end)
	end)
end)

-- A list of ten or fewer stays as it was: one row an option, in order.
test("Chat tab (1.2.4): ten rooms or fewer show as they come, without groups or pages", function()
	WithWindow(function(w)
		local R = ns.ChatRooms
		local saved = R.Options
		local ok, err = pcall(function()
			local list = {}
			for i = 1, 10 do list[i] = { id = "dept:war", label = "Room " .. i, group = "dept", groupLabel = "Departments" } end
			R.Options = function(kind) if kind == "role" then return list end return saved(kind) end
			ns.db.chatRooms = true
			local f = w.CW.Open("A")
			for _, b in ipairs(f.subtabs.nav) do if b:IsShown() and b.item.entry.kind == "role" then b:Click() end end
			eq(f.subMenu:IsShown(), true)
			for i = 1, 10 do eq(f.subMenu.rows[i].text:GetText(), "Room " .. i); eq(f.subMenu.rows[i].groupItem, nil) end
			f.subCatcher:Click()
			list[11] = { id = "council", label = "Room 11" }
			for _, b in ipairs(f.subtabs.nav) do if b:IsShown() and b.item.entry.kind == "role" then b:Click() end end
			eq(f.subMenu.rows[1].text:GetText(), "Departments (10) >"); eq(f.subMenu.rows[2].text:GetText(), "Room 11")
			eq(f.subMenu.rows[3]:IsShown(), false)
		end)
		R.Options = saved
		if not ok then error(err, 0) end
	end)
end)

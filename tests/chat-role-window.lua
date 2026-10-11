local ns, test, eq, WithWindow = ...

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

test("chat destination dropdown: unchanged census redraw keeps menu open; selection and outside click close it", function()
	WithWindow(function(w)
		ns.db.chatRooms = true
		local f = w.CW.Open("A")
		local race
		for _, button in ipairs(f.subtabs.nav) do if button.item.entry.kind == "race" then race = button end end
		assert(race); race:Click(); eq(f.subMenu:IsShown(), true)
		w.fire("DATA_CHANGED"); w.CW.Render()
		eq(f.subMenu:IsShown(), true, "ordinary census refresh must not eat the user's dropdown")
		f.subCatcher:Click(); eq(f.subMenu:IsShown(), false)
		race:Click(); f.subMenu.rows[1]:Click()
		eq(f.subMenu:IsShown(), false); eq(w.CW.Tier(), "race:1")
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
			for _, kind in ipairs({ "global", "guild", "race", "class", "arena" }) do assert(Tab(kind), kind) end
			eq(Tab("role"), nil)
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

local ns, test, eq, WithWindow, WithGamepadUI = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-role%-window%.lua$") or "./"

test("1.2.4 chat performance: census packets coalesce the main window while local message events remain independent", function()
	WithWindow(function(w)
		w.CW.Open("A")
		local UI = w.UI
		local oldRefresh, oldAfter = UI.RefreshSoon, ns.After
		local calls, queued, now = 0, {}, 0
		GetTime = function() return now end
		local ok, err = pcall(function()
			UI.RefreshSoon = function() calls = calls + 1 end
			ns.After = function(delay, label, fn) queued[#queued + 1] = { delay = delay, fn = fn } end
			-- WithWindow captures ChatWindow's listeners separately from UI's; invoke the
			-- actual UI listener here rather than the isolated chat-only event bus.
			for i = 0, 11 do now = i * 5; UI.DataChanged() end
			eq(calls, 1, "twelve packets do not rebuild the main window twelve times")
			eq(#queued, 1, "one timer, not one per packet")
			now = 60; queued[1].fn(); eq(calls, 2)
			w.fire("CHAT_LINE", "A", ns.me, "still immediate")
			eq(calls, 2, "a line uses the chat's own refresh, not a census rebuild")
		end)
		UI.RefreshSoon, ns.After = oldRefresh, oldAfter
		if not ok then error(err, 0) end
	end)
end)

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
			e.del = nil; timed = false; w.CW.ModerateLine(b)
			eq(f.subMenu.rows[4].text:GetText(), ns.L.CHATWIN_REPLY)
			eq(f.subMenu.rows[4]:IsShown(), true, "reply remains available when there is no timeout to lift")
			eq(f.subMenu.rows[5]:IsShown(), false)
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
		local asked, reported, sent = {}, {}, {}
		C.History = function(t) if t == "A" then return { theirs, mine } end return {} end
		C.Send = function(tier, text) sent[#sent + 1] = { tier = tier, text = text }; return true end
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
			eq(f.subMenu.rows[1].text:GetText(), ns.L.WATCH_REPORT)
			eq(f.subMenu.rows[2].text:GetText(), ns.L.CHATWIN_REPLY); eq(f.subMenu.rows[2]:IsShown(), true, "report and reply")
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
			-- His own line: reply is available, but reporting himself is not.
			local n = #asked
			eq(w.CW.ModerateLine(BubbleOf(mine)), true); eq(f.subMenu:IsShown(), true); eq(#asked, n)
			eq(f.subMenu.rows[1].text:GetText(), ns.L.CHATWIN_REPLY); eq(f.subMenu.rows[2]:IsShown(), false)
			f.subMenu.rows[1]:Click(); eq(f.replyComposer:IsShown(), true)
			assert(f.replyComposer.label:GetText():find(ns.DisplayName(ns.me), 1, true))
			f.input:SetText("answer from me"); f.input:Fire("OnEnterPressed")
			eq(#sent, 1); eq(sent[1].tier, "A")
			local quote, answer = w.CW.DecodeReply(sent[1].text)
			-- (Changed in CH-04: the quote names its writer in full, Name-Realm, so a client on another
			-- realm shows him as its own realm does and finds the line quoted; the box still shows the
			-- name as this client does, above.)
			eq(quote.who, ns.me); eq(quote.text, "my own words"); eq(answer, "answer from me")
			eq(f.replyComposer:IsShown(), false); eq(f.input:GetText(), "")
			-- A client updated without a restart (The Watch a stand-in): reply still works by itself.
			rawset(ns, "Watch", { missing = true })
			eq(w.CW.ModerateLine(b), true); eq(f.subMenu:IsShown(), true)
			eq(f.subMenu.rows[1].text:GetText(), ns.L.CHATWIN_REPLY)
		end)
		C.History = saved.history
		rawset(ns, "Watch", saved.watch); rawset(ns, "WatchChat", saved.wc)
		if not ok then error(err, 0) end
	end)
end)

-- (Changed in CH-04: the prefix is "[reply @Name-Realm: quote] answer", one printable line; 1.2.5's
-- "[reply @Name] quote" and a newline never survived the chats' cleaning, see below.)
test("chat replies: the compatible prefix round-trips safely and leaves ordinary text unchanged", function()
	WithWindow(function(w)
		local reply = { who = "Rude Guy-Realm", text = "a referenced line with [brackets]\nand controls\t" }
		local wire = w.CW.EncodeReply(reply, "new answer")
		assert(wire:find("^%[reply @Rude Guy%-Realm: "), wire)
		assert(not wire:find("%c"), "no control byte: Codec.SanitizeChat would drop it")
		eq(ns.Codec.SanitizeChat(wire), wire, "the chats' cleaning leaves it as it is")
		local decoded, body = w.CW.DecodeReply(wire)
		eq(decoded.who, "Rude Guy-Realm"); eq(decoded.text, "a referenced line with brackets and controls")
		eq(body, "new answer")
		local none, plain = w.CW.DecodeReply("ordinary line")
		eq(none, nil); eq(plain, "ordinary line")
		-- 1.2.5's form, as it arrived (its newline already gone): ordinary text.
		none, plain = w.CW.DecodeReply("[reply @Rude Guy] a quotenew answer")
		eq(none, nil); eq(plain, "[reply @Rude Guy] a quotenew answer")
		-- A history line's sender names the writer in full, whatever the name shown.
		wire = w.CW.EncodeReply({ sender = "Quoted Friend", who = "Quoted Friend", text = "hello" }, "hi")
		eq(wire, "[reply @Quoted Friend-Realm: hello] hi")
	end)
end)

-- Two bugs of 1.2.5's quote, each fixed with CH-04: a cut inside a two-byte character left its first
-- byte behind (a broken character before the "..."), and a link came out as its code ("cff1eff00
-- Hitem:14342...h Mooncloth hr") instead of its name.
test("chat replies (CH-04): a quote is cut before a character, never inside one, and shows a link by its name", function()
	WithWindow(function(w)
		eq(w.CW.ReplyPart("ab\195\169 and more words", 3), "ab...")
		eq(w.CW.ReplyPart("ab\195\169 and more words", 4), "ab\195\169...")
		eq(w.CW.ReplyPart("|cff1eff00|Hitem:14342::::::::60:::::|h[Mooncloth]|h|r for sale", 60), "Mooncloth for sale")
		eq(w.CW.ReplyPart("a || pipe", 60), "a pipe", "a typed pipe goes, as Codec.Plain takes it")
	end)
end)

-- CH-04 (the author, 2026-10-19: "Quando você responde uma mensagem, ela aparece menorzinha em
-- cima"). The real way out for the three channels: the Chat tab's Enter, Channels.Send, the wire,
-- Comm (its lane the only stand-in) and the line's arrival at another member's Channels.Receive.
local function WithChannelLane(fn)
	local C, Comm = ns.Channels, ns.Comm
	local saved = { ready = Comm.ChannelReady, room = Comm.ChatRoom, send = Comm.SendChat, warned = ns.db.chatWarned }
	local at, was
	for i = 1, 200 do
		local n, v = debug.getupvalue(C.Send, i)
		if n == nil then break end
		if n == "lastSend" then at, was = i, v break end
	end
	assert(at, "(Channels.Send's lastSend)")
	local wire = {}
	local ok, err = pcall(function()
		debug.setupvalue(C.Send, at, -math.huge) -- (an earlier test's line is not "too fast" for this one)
		ns.db.addonChat, ns.db.chatWarned = true, { A = true }
		Comm.ChannelReady = function() return true end
		Comm.ChatRoom = function() return 3 end
		Comm.SendChat = function(msg, done) wire[#wire + 1] = msg; done(true); return true end
		fn(wire)
	end)
	debug.setupvalue(C.Send, at, was)
	Comm.ChannelReady, Comm.ChatRoom, Comm.SendChat, ns.db.chatWarned = saved.ready, saved.room, saved.send, saved.warned
	if not ok then error(err, 0) end
end
local function Shown(f, body)
	local out = {}
	for _, b in ipairs(f.bubbles) do if b:IsShown() and b.body:GetText() == body then out[#out + 1] = b end end
	return out
end

-- The bug: 1.2.5 put a "\n" between the quoted words and the answer. Codec.SanitizeChat drops every
-- control byte in Channels.Send itself (and again on arrival), so the quote and the answer left
-- glued together as one plain line, and no client ever drew a reply: the test above mocked
-- Channels.Send and never saw it.
test("chat replies (CH-04): a reply sent through Channels.Send reaches another member as a smaller quote above the answer", function()
	WithWindow(function(w)
		WithChannelLane(function(wire)
			local C = ns.Channels
			local clock = 2e6
			GetTime = function() return clock end
			ns.rdb.chat = { A = { { t = 1800000000, sender = "Quoted Friend-Realm", guild = "Olympus II", text = "where do we meet tonight?" } } }
			local f = w.CW.Open("A")
			local quoted = assert(Shown(f, "where do we meet tonight?")[1], "the line to answer")
			eq(w.CW.BeginReply(quoted), true)
			f.input:SetText("at the bank, after the raid")
			f.input:Fire("OnEnterPressed")
			eq(#wire, 1, "sent: " .. table.concat(w.printed, " / "))
			-- What travels: the quote and the answer apart, each whole, on one printable line.
			local m = assert(ns.Codec.DecodeChat(wire[1]), wire[1])
			assert(not m.text:find("%c"), "no control byte left to strip")
			local quote, answer = w.CW.DecodeReply(m.text)
			assert(quote, "the line as it arrives still reads as a reply: " .. m.text)
			eq(quote.who, "Quoted Friend-Realm", "the writer's full name: each client shows it as its realm does")
			eq(quote.text, "where do we meet tonight?"); eq(answer, "at the bank, after the raid")
			-- Another member's line, as it arrives from the channel (he is in our roster, a member).
			clock = clock + 5
			local byName = ns.Roster.byName
			ns.Roster.byName = { ["Other Member-Realm"] = 3 }
			local shown, why = C.Receive("CHANNEL", "Other Member-Realm", wire[1], clock)
			ns.Roster.byName = byName
			eq(shown, true, tostring(why))
			w.CW.Render()
			-- The sender's own bubble (the echo of what left) and the other member's: the answer alone in
			-- the bubble's words, the quote over it, in the small font, with its writer.
			local bubbles = Shown(f, "at the bank, after the raid")
			eq(#bubbles, 2, "ours and his")
			for _, b in ipairs(bubbles) do
				eq(b.replyWho:IsShown(), true); eq(b.replyText:IsShown(), true); eq(b.replyBg:IsShown(), true)
				eq(b.replyWho:GetText(), "Quoted Friend"); eq(b.replyText:GetText(), "where do we meet tonight?")
				eq(b.replyText.font, "GameFontHighlightSmall"); eq(b.body.font, "ChatFontNormal", "smaller than the answer")
				local quoteTop, bodyTop = -b.replyBg:Anchor("TOPLEFT")[5], -b.body:Anchor("TOPLEFT")[5]
				assert(quoteTop < bodyTop, "the quote above the answer")
			end
			eq(bubbles[1].mine ~= bubbles[2].mine, true, "one ours, one his")
		end)
	end)
end)

-- CH-04: anyone can type the prefix, so the quote is drawn only over a line this client holds, by
-- the writer it names, with those words. Else the reply shows as written, prefix and all: no words
-- put in anyone's mouth. The line it quotes deleted by a moderator: its words stay gone.
test("chat replies (CH-04): the quote shows only over a line this client holds; a typed prefix quotes nobody, a deleted line's words stay gone", function()
	WithWindow(function(w)
		local C = ns.Channels
		local saved = rawget(ns, "WatchChat")
		local lines = {}
		C.History = function(t) if t == "A" then return lines end return {} end
		rawset(ns, "WatchChat", { StripText = function() return nil end, RecordLines = function() return {} end,
			CanModerateAny = function() return false end, CanModerateEntry = function() return false end,
			TimeoutOf = function() return nil end, DeletedTip = function() end,
			DeletedBody = function() return "|cff808080(deleted by a moderator)|r" end })
		local ok, err = pcall(function()
			local function Line(t, sender, text, extra)
				local e = { t = 1800000000 + t, sender = sender, guild = "Olympus II", text = text }
				for k, v in pairs(extra or {}) do e[k] = v end
				lines[#lines + 1] = e
				return e
			end
			local function Reply(t, sender, to, answer)
				return Line(t, sender, w.CW.EncodeReply({ sender = to.sender, text = to.text }, answer))
			end
			local long = "a long line about the raid tonight, the bank and the guild's dues, much longer than any quote can be"
			local friend = Line(1, "Quoted Friend-Realm", "where do we meet tonight?")
			local said = Line(2, "Quoted Friend-Realm", long)
			local far = Line(3, "Far Away-OtherRealm", "hello from afar")
			local mine = Line(4, ns.me, "my own words", { mine = true })
			local rude = Line(5, "Quoted Friend-Realm", "rude words", { del = true, delAt = 1800000005, delRole = "council" })
			Reply(10, "Other Member-Realm", friend, "at the bank")
			Reply(11, "Other Member-Realm", said, "agreed")
			Reply(12, "Other Member-Realm", far, "hi there")
			Reply(13, "Other Member-Realm", mine, "you said it")
			Reply(14, "Other Member-Realm", rude, "how dare you")
			-- Typed by hand: a quote of words he never said, and of a line this client never had.
			Line(15, "Forger-Realm", "[reply @Quoted Friend-Realm: I sold the guild bank] he admits it")
			Line(16, "Forger-Realm", "[reply @Quoted Friend-Realm: where do we meet] a cut that is no cut")
			local f = w.CW.Open("A")
			local function Quote(body)
				local b = assert(Shown(f, body)[1], "a bubble for " .. body)
				return b.replyWho:IsShown() and b.replyWho:GetText() or nil, b.replyText:IsShown() and b.replyText:GetText() or nil, b
			end
			local who, words = Quote("at the bank")
			eq(who, "Quoted Friend"); eq(words, "where do we meet tonight?")
			who, words = Quote("agreed")
			eq(who, "Quoted Friend"); assert(words and words:sub(-3) == "..." and long:find(words:sub(1, -4), 1, true) == 1, tostring(words))
			eq(#words <= w.CW.REPLY_QUOTE + 3, true, "the quote cut short")
			who, words = Quote("hi there")
			eq(who, "Far Away-OtherRealm", "another realm's writer, with his realm"); eq(words, "hello from afar")
			who, words = Quote("you said it")
			eq(who, ns.L.CHATWIN_YOU, "a quote of ours: You"); eq(words, "my own words")
			who, words = Quote("how dare you")
			eq(who, "Quoted Friend"); eq(words, "|cff808080(deleted by a moderator)|r", "the deleted line's words are not drawn again")
			-- The typed prefixes: shown as written, no quote.
			eq(Quote("[reply @Quoted Friend-Realm: I sold the guild bank] he admits it"), nil)
			eq(Quote("[reply @Quoted Friend-Realm: where do we meet] a cut that is no cut"), nil, "a part of his words without the cut's ...: no match")
			-- The quoted line leaves this client's history (the oldest of a channel go): the reply shows as written.
			table.remove(lines, 1)
			w.CW.Render()
			eq(#Shown(f, "at the bank"), 0, "no longer drawn as a reply")
			local _, _, b = Quote(w.CW.EncodeReply({ sender = "Quoted Friend-Realm", text = "where do we meet tonight?" }, "at the bank"))
			eq(b.replyBg:IsShown(), false)
		end)
		rawset(ns, "WatchChat", saved)
		if not ok then error(err, 0) end
	end)
end)

-- CH-04: a room keeps 150 bytes of a line (ChatRooms.TEXT_MAX: Guild, the role rooms, a deal's and a
-- squad's), and 1.2.5's prefix alone could take as many: the room's cut then took the answer. The
-- quote gives way instead, and an answer that leaves it no room is kept in the box, with why. Here
-- through ChatRooms.Send's Guild room, to the game's guild chat (the only stand-in: the game's send).
test("chat replies (CH-04): in a room the quote gives way to the answer, and an answer too long to reply with stays in the box", function()
	WithWindow(function(w)
		local R = ns.ChatRooms
		local savedCI, said = C_ChatInfo, {}
		C_ChatInfo = setmetatable({ SendChatMessage = function(text, lane) said[#said + 1] = { text = text, lane = lane } end },
			{ __index = savedCI or {} })
		local ok, err = pcall(function()
			ns.db.chatRooms = true
			R.Reset()
			local clock = 3e6
			GetTime = function() return clock end
			local quoted = { t = 1800000000, sender = "Quoted Friend-Realm", guild = "Olympus II",
				text = "who brings the flasks and the food for the raid on Thursday, and who keeps the bank tab?" }
			R.History = function(id) if id == "guild" then return { quoted } end return {} end
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("guild"), true); eq(w.CW.Tier(), "guild")
			w.CW.Render()
			eq(w.CW.BeginReply(assert(Shown(f, quoted.text)[1], "the line to answer")), true)
			local answer = "I bring the flasks, the cook brings the food, and the bank tab stays with the officers this week."
			f.input:SetText(answer); f.input:Fire("OnEnterPressed")
			eq(#said, 1, "sent: " .. table.concat(w.printed, " / ")); eq(said[1].lane, "GUILD")
			assert(#said[1].text <= R.TEXT_MAX, #said[1].text .. " bytes")
			local quote, body = w.CW.DecodeReply(said[1].text)
			assert(quote, said[1].text)
			eq(body, answer, "the answer whole"); eq(quote.who, "Quoted Friend-Realm")
			assert(quote.text:sub(-3) == "..." and quoted.text:find(quote.text:sub(1, -4), 1, true) == 1, quote.text)
			eq(f.input:GetText(), ""); eq(f.replyComposer:IsShown(), false)
			-- Too long to go with a quote: nothing sent, the words and the reply kept, the room says why.
			w.CW.BeginReply(Shown(f, quoted.text)[1])
			local long = answer .. " And the dues are due on Sunday."
			f.input:SetText(long); f.input:Fire("OnEnterPressed")
			eq(#said, 1, "not sent"); eq(f.input:GetText(), long); eq(f.replyComposer:IsShown(), true)
			w.CW.Render()
			local why = ns.L.CHATWIN_NOT_SENT:format(ns.L.CHATWIN_WHY_REPLY_LONG)
			local found = false
			for _, r in ipairs(f.rows) do if r:IsShown() and (r.text:GetText() or ""):find(why, 1, true) then found = true end end
			eq(found, true, "the room says why")
			-- The reply cancelled (its x), the same words go, alone.
			f.replyComposer.cancel:Click()
			clock = clock + R.SEND_GAP
			f.input:Fire("OnEnterPressed")
			eq(#said, 2); eq(said[2].text, long, "as any line of the room")
			eq(w.CW.DecodeReply(said[2].text), nil, "no quote")
		end)
		C_ChatInfo = savedCI
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

-- 1.2.4: until the author's signed leadership list counts, a room reaching other guilds (a
-- department's, the masters') says over its lines that it reaches this guild and the signed people
-- alone (ChatRooms.StatusText); the High Council's says nothing.
test("Chat tab (1.2.4): a department's room says over its lines that other guilds wait for the signed leadership list; the High Council's does not", function()
	WithWindow(function(w)
		local saved = { council = ns.IsHighCouncillor, title = ns.CouncilTitle, enforced = ns.Authority.Enforced }
		local ok, err = pcall(function()
			ns.IsHighCouncillor = function(name) return name == nil or name == ns.me end
			ns.CouncilTitle = function(name) if name == nil or name == ns.me then return { dept = "Department of War" } end end
			ns.Authority.Enforced = function() return false end
			ns.db.chatRooms = true
			local f = w.CW.Open("A")
			assert(w.CW.SelectLogical("dept:war"))
			w.CW.Render()
			eq(f.topicStatus:IsShown(), true)
			assert(f.topicStatus.text:GetText():find(ns.L.CHATROOM_NEEDS_LEADERS, 1, true), tostring(f.topicStatus.text:GetText()))
			assert(w.CW.SelectLogical("council"))
			w.CW.Render()
			eq(f.topicStatus:IsShown(), false, "the High Council's: signed people alone")
			ns.Authority.Enforced = function() return true end
			assert(w.CW.SelectLogical("dept:war"))
			w.CW.Render()
			eq(f.topicStatus:IsShown(), false, "once it counts")
		end)
		ns.IsHighCouncillor, ns.CouncilTitle, ns.Authority.Enforced = saved.council, saved.title, saved.enforced
		if not ok then error(err, 0) end
	end)
end)

-- 1.2.4 (the author, in the Church's room: "Eu dou Enter para enviar a mensagem na igreja e não
-- aparece a mensagem. No histórico, não aparece nada e não me avisa por que não foi"): the real
-- Chat page over the real rooms (ChatRooms.lua loaded fresh for the page, its events the page's),
-- with the Church's room registered as Church.lua registers it, its audience and its members
-- online stood in for, and a send queue whose whispers leave when the test says.
local function WithChurchRoom(w, fn)
	local saved = { rooms = ns.ChatRooms, getTime = GetTime, guildInfo = GetGuildInfo }
	local room = { clock = 5000, audience = {}, online = {}, jobs = {} }
	local ok, err = pcall(function()
		GetTime = function() return room.clock end
		ns.db.chatRooms = true
		room.audience[ns.me:lower()] = true
		for i = 1, 3 do
			local name = "Brother " .. string.char(96 + i) .. "-Realm"
			room.audience[name:lower()], room.online[#room.online + 1] = true, name
		end
		local rns = setmetatable({}, { __index = ns })
		rns.On, rns.RegisterEvent = function() end, function() end
		rns.Fire = function(name, ...) w.fire(name, ...) end
		rns.Consent = { Register = function() end, Ask = function() end }
		rns.Comm = setmetatable({
			Handle = function() end,
			QueueRoom = function() return 60 end,
			Whisper = function(target, msg, _, _, logged, done, options)
				room.jobs[#room.jobs + 1] = { target = target, msg = msg, logged = logged, done = done, options = options }
				return true
			end,
		}, { __index = ns.Comm })
		assert(loadfile(ROOT .. "Olympus/ChatRooms.lua"))("Olympus", rns)
		local R = rns.ChatRooms
		R.Reset()
		assert(R.RegisterAudience("church", { label = function() return ns.L.CHURCH_ROOM end,
			CanAccess = function(name) return room.audience[ns.FullName(name or ns.me):lower()] == true end,
			Recipients = function() return room.online, room.left end }))
		ns.ChatRooms = R
		room.R = R
		-- A queued whisper's last check, then its send: as Comm does when its turn comes.
		function room.Finish(job)
			local o = job.options
			local permitted, why = o.permit(o.owner, o.key, "WHISPER", job.target, job.msg)
			job.done(permitted, why)
			return permitted, why
		end
		function room.Shown(list)
			local out = {}
			for _, x in ipairs(list) do if x:IsShown() then out[#out + 1] = x end end
			return out
		end
		function room.RowWith(f, text)
			for _, r in ipairs(room.Shown(f.rows)) do if (r.text:GetText() or ""):find(text, 1, true) then return r end end
		end
		function room.BubbleWith(f, text)
			for _, b in ipairs(room.Shown(f.bubbles)) do if (b.body:GetText() or ""):find(text, 1, true) then return b end end
		end
		-- (The review: "Not sent:" alone, the start every such note shares, whatever its reason.)
		room.NOT_SENT = assert(ns.L.CHATWIN_NOT_SENT:match("^(.-)%%s"))
		fn(room, R)
	end)
	ns.ChatRooms, GetTime, GetGuildInfo = saved.rooms, saved.getTime, saved.guildInfo
	if not ok then error(err, 0) end
end

test("Chat tab (1.2.4): a line written in the Church's room shows at once, marked sending, and a line that cannot go says why in the room", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room)
			local L, jobs = ns.L, room.jobs
			local RowWith, BubbleWith = room.RowWith, room.BubbleWith
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("church"), true, "the Church's room, his own")
			f.input:SetText("hello brothers")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(f.input:GetText(), "", "the box empties")
			eq(#jobs, 3, "one logged whisper to each of the room's members online")
			for _, job in ipairs(jobs) do eq(job.logged, true); eq(room.audience[job.target:lower()], true, job.target) end
			local b = BubbleWith(f, "hello brothers")
			assert(b, "his line shows at Enter")
			assert(b.body:GetText():find(L.CHATWIN_SENDING, 1, true), "marked as sending: " .. b.body:GetText())
			room.Finish(jobs[1]); room.Finish(jobs[2])
			w.CW.Render()
			assert(BubbleWith(f, L.CHATWIN_SENDING), "still sending while a whisper waits")
			room.Finish(jobs[3])
			w.CW.Render()
			b = BubbleWith(f, "hello brothers")
			assert(b, "still shown once sent")
			eq(b.body:GetText():find(L.CHATWIN_SENDING, 1, true), nil, "no longer marked once every whisper left")
			eq(RowWith(f, room.NOT_SENT), nil, "no note")

			-- Enter again at once: too fast, told in the room, the words kept in the box.
			f.input:SetText("again")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(f.input:GetText(), "again", "kept in the box")
			eq(#jobs, 3, "nothing sent")
			assert(RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_FAST)), "the reason, in the room")
			eq(RowWith(f, L.CHATWIN_PUT_BACK), nil, "no put-back: the words never left the box")

			-- Nobody else of the room online: told so; one note, the latest refusal's.
			room.clock = room.clock + 2
			for i = #room.online, 1, -1 do room.online[i] = nil end
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(f.input:GetText(), "again"); eq(#jobs, 3)
			assert(RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_ALONE)), "nobody else online, said in the room")
			eq(RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_FAST)), nil, "the older refusal's note gone")
			eq(BubbleWith(f, "again"), nil, "not shown as said")

			-- The game has not said his guild yet (a loading screen): told so.
			room.online[1] = "Brother a-Realm"
			local guildInfo = GetGuildInfo
			GetGuildInfo = function() return nil end
			f.input:Fire("OnEnterPressed")
			GetGuildInfo = guildInfo
			w.CW.Render()
			assert(RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_GUILD)), "no guild yet, said in the room")

			-- Sent again: the line shows, the refusal's note goes.
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(f.input:GetText(), ""); eq(#jobs, 4)
			assert(BubbleWith(f, "again"), "shown at Enter")
			eq(RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_GUILD)), nil, "the note gone with a line sent")
		end)
	end)
end)

-- 1.2.4: a role room's line every whisper of which failed after it showed: it leaves the room, and
-- the room's note names the reason (here the audience changed while it waited), its words to put
-- back in the box.
test("Chat tab (1.2.4): a role room's line none of whose whispers left goes from the room, and its note says why and puts it back", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room)
			local L, jobs = ns.L, room.jobs
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("church"), true)
			f.input:SetText("lost on the way")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			assert(room.BubbleWith(f, "lost on the way"), "shown at Enter")
			eq(#jobs, 3)
			for k in pairs(room.audience) do if k ~= ns.me:lower() then room.audience[k] = nil end end
			for _, job in ipairs(jobs) do eq((room.Finish(job)), false, "the permit refuses " .. job.target) end
			w.CW.Render()
			eq(room.BubbleWith(f, "lost on the way"), nil, "gone: it reached nobody")
			local note = room.RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_REVOKED))
			assert(note, "the reason, in the room")
			assert(room.RowWith(f, L.CHATWIN_PUT_BACK), "its words can go back in the box")
			note:Click()
			eq(f.input:GetText(), "lost on the way")
		end)
	end)
end)

-- 1.2.4: a role room's line goes to its share of the members online at most (ChatRooms.FANOUT, the
-- Church's rooms 30): how many it missed is said in the room, under the line, and not only in the
-- game's chat frame under the Olympus window (the silent send's lesson); the next line takes it away.
test("Chat tab (1.2.4): a line that went to its room's share of members says in the room how many it missed", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room, R)
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("church"), true)
			room.left = 4
			f.input:SetText("to the brothers")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(f.input:GetText(), ""); eq(#room.jobs, 3)
			local said = R.NotReachedText("church", 4)
			eq(said, ns.L.CHATROOM_NOT_REACHED:format(4, R.FANOUT))
			assert(room.RowWith(f, said), "said in the room")
			eq(room.RowWith(f, ns.L.CHATWIN_PUT_BACK), nil, "it went: nothing to put back")
			room.left, room.clock = nil, room.clock + 2
			f.input:SetText("to all of them")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(#room.jobs, 6)
			eq(room.RowWith(f, said), nil, "the next line takes it away")
		end)
	end)
end)

-- 1.2.4 (the review): a role room's line that reached some of the room but not all stays in the room
-- as said, and its note says not everyone got it, and why; nothing to put back: sent again, it would
-- reach twice those who had it. Before, it read "Not sent: ... Click to put it back in the box."
test("Chat tab (1.2.4): a role room's line some of the room got stays, and its note says not everyone got it, with nothing to put back", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room)
			local L, jobs = ns.L, room.jobs
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("church"), true)
			f.input:SetText("two of three")
			f.input:Fire("OnEnterPressed")
			eq(#jobs, 3)
			room.Finish(jobs[1]); room.Finish(jobs[2])
			jobs[3].done(false, "dropped") -- (Comm: its queue made room for newer work)
			w.CW.Render()
			local b = room.BubbleWith(f, "two of three")
			assert(b, "it reached two: shown as said")
			eq(b.body:GetText():find(L.CHATWIN_SENDING, 1, true), nil, "settled")
			assert(room.RowWith(f, L.CHATWIN_PART_SENT:format(L.CHATWIN_WHY_QUEUE)), "not everyone got it, and why")
			eq(room.RowWith(f, room.NOT_SENT), nil, "not told as not sent")
			eq(room.RowWith(f, L.CHATWIN_PUT_BACK), nil, "nothing to put back")
			eq(f.input:GetText(), "", "the box stays empty")
		end)
	end)
end)

-- 1.2.4 (the review): a refusal's note lives as long as its words in the box: emptied (or only spaces
-- left), the note goes; the words changed, it stays. (The game's SetText fires OnTextChanged too,
-- userInput false; the test's box fires it by hand.)
test("Chat tab (1.2.4): a room's refusal note goes once its words are cleared from the box, and stays while they are there", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room)
			local L = ns.L
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("church"), true)
			for i = #room.online, 1, -1 do room.online[i] = nil end
			f.input:SetText("anyone?")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			local alone = L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_ALONE)
			assert(room.RowWith(f, alone), "refused, said in the room")
			f.input:SetText("anyone at all?"); f.input:Fire("OnTextChanged", true)
			w.CW.Render()
			assert(room.RowWith(f, alone), "the words still in the box: the note stays")
			f.input:SetText(""); f.input:Fire("OnTextChanged", true)
			w.CW.Render()
			eq(room.RowWith(f, room.NOT_SENT), nil, "the box emptied: the note goes")

			f.input:SetText("anyone?")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			assert(room.RowWith(f, alone), "refused again: said again")
			f.input:SetText("   "); f.input:Fire("OnTextChanged", true)
			w.CW.Render()
			eq(room.RowWith(f, room.NOT_SENT), nil, "only spaces left (Enter sends nothing): the note goes")
		end)
	end)
end)

-- 1.2.4 (the review): a provider's room (a crafting deal's, a squad's) answers for its own refusals;
-- the Chat page puts no "not sent" note of its own in it (ChatRooms.Own).
test("Chat tab (1.2.4): a provider's room refusing a line gets no note from the page", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room, R)
			local sent = 0
			eq(R.RegisterProvider({
				Info = function(id) if id == "craft:abc1" then return { id = id, kind = id, label = "Mooncloth", scope = "private" } end end,
				CanAccess = function(id) return id == "craft:abc1" end,
				History = function() return {} end,
				Send = function() sent = sent + 1 return false, "closed" end,
			}), true)
			local f = w.CW.Open("A")
			eq(w.CW.SelectLogical("craft:abc1"), true)
			f.input:SetText("a fellow-member price?")
			f.input:Fire("OnEnterPressed")
			w.CW.Render()
			eq(sent, 1, "the provider was asked")
			eq(f.input:GetText(), "a fellow-member price?", "refused: kept in the box")
			eq(room.RowWith(f, room.NOT_SENT), nil, "no note from the page: the provider answers for itself")
		end)
	end)
end)

-- The chat warnings (ChatStrikes.lua; the author, 2026-10-19: "apaga e esconde a mensagem que a
-- pessoa mandou"): a line refused for a warning ("severe") leaves the Chat tab's box with its reply
-- and lets the keyboard go (the pop-up's OK takes the next Enter); a line refused while paused keeps
-- both, as every other refusal. The same in an embedded pane (the Bones pane), whose composer, while
-- paused, says why instead of doing nothing.
test("watch: chat moderation: strikes: the Chat tab and an embedded pane: a struck line leaves the box with its reply and lets the keyboard go; a paused one keeps both; a paused pane says why", function()
	WithWindow(function(w)
		local C = ns.Channels
		local saved = rawget(ns, "WatchChat")
		local result, told = { false, "severe" }, 0
		C.Send = function() return result[1], result[2] end
		rawset(ns, "WatchChat", { StripText = function() return nil end, RecordLines = function() return {} end,
			CanModerateAny = function() return false end, CanModerateEntry = function() return false end,
			RefuseSend = function() told = told + 1 return {}, "paused" end })
		local ok, err = pcall(function()
			local f = w.CW.Open("A")
			local function Try(box, owner, why)
				result = { false, why }
				owner.reply = { who = "Other", sender = "Other-Realm", text = "their line" }
				w.CW.UpdateReplyComposer(owner)
				box:SetText("typed words"); box.focused = true
				box:Fire("OnEnterPressed")
			end
			Try(f.input, f, "severe")
			eq(f.input:GetText(), "", "the struck line leaves the box"); eq(f.reply, nil, "its reply too")
			eq(f.input.focused, false, "the keyboard goes")
			Try(f.input, f, "paused")
			eq(f.input:GetText(), "typed words", "a paused line stays"); assert(f.reply, "with its reply")
			eq(f.input.focused, true, "and the cursor (mouse and keyboard)")
			WithGamepadUI(true, function()
				Try(f.input, f, "severe")
				eq(f.input:GetText(), ""); eq(f.input.focused, false, "the gamepad UI: the box lets go")
			end)
			-- An embedded pane (the Bones pane's).
			local writable, sent = true, {}
			local p = w.CW.CreateEmbedded(f, { room = function() return "r1" end, lines = function() return {} end,
				maySend = function() return writable end, label = function() return "Bones" end,
				send = function(text) sent[#sent + 1] = text return result[1], result[2] end })
			Try(p.input, p, "severe")
			eq(#sent, 1); eq(p.input:GetText(), ""); eq(p.reply, nil); eq(p.input.focused, false)
			Try(p.input, p, "paused")
			eq(p.input:GetText(), "typed words"); assert(p.reply)
			writable = false
			Try(p.input, p, "paused")
			eq(#sent, 2, "nothing sent while it may not"); eq(told, 1, "told why")
		end)
		rawset(ns, "WatchChat", saved)
		if not ok then error(err, 0) end
	end)
end)

-- (The review: the Chat tab's own rooms (Guild, the role rooms, the Church's) put a "not sent" note
-- under a refused line, and a struck one must leave none: nothing of it stays. The test above swaps
-- Channels.Send, so it never reached ChatRooms' branch, nor a fight room's, ArenaChat's.) This
-- harness's box fires no OnTextChanged on SetText: the note is the guard's to keep out.
test("watch: chat moderation: strikes: the Chat tab's own rooms and a fight room: a struck line leaves the box, its reply and the keyboard, with no note in the room; a paused one stays, and the room says why", function()
	WithWindow(function(w)
		WithChurchRoom(w, function(room, R)
			local saved, savedArena = rawget(ns, "WatchChat"), rawget(ns, "ArenaChat")
			local result, send = { false, "severe" }, R.Send
			rawset(ns, "WatchChat", { StripText = function() return nil end, RecordLines = function() return {} end,
				CanModerateAny = function() return false end, CanModerateEntry = function() return false end })
			R.Send = function() return result[1], result[2] end
			local ok, err = pcall(function()
				local L = ns.L
				local f = w.CW.Open("A")
				local function Try(why)
					result = { false, why }
					f.reply = { who = "Other", sender = "Other-Realm", text = "their line" }
					w.CW.UpdateReplyComposer(f)
					f.input:SetText("typed words"); f.input.focused = true
					f.input:Fire("OnEnterPressed")
					w.CW.Render()
				end
				eq(w.CW.SelectLogical("church"), true)
				eq(R.Own("church"), true, "a room of the page's own")
				Try("severe")
				eq(f.input:GetText(), "", "the struck line leaves the box"); eq(f.reply, nil, "its reply too")
				eq(f.input.focused, false, "the keyboard goes")
				eq(room.RowWith(f, room.NOT_SENT), nil, "no note in the room")
				Try("paused")
				eq(f.input:GetText(), "typed words", "a paused line stays"); assert(f.reply, "with its reply")
				assert(room.RowWith(f, L.CHATWIN_NOT_SENT:format(L.CHATWIN_WHY_PAUSED)), "the room says why")
				-- A fight room: its line goes through ArenaChat.Send alone.
				local sent = 0
				local spec = { id = "Fstrike-1", key = "arena:Fstrike-1", kind = "fight", audience = "duel", access = "participants",
					title = "Fixture fight", phase = "live", active = true, recoverable = true, supportsComments = true }
				ns.ArenaChat = { Open = function() return true end, Lines = function() return {} end, Rooms = function() return { spec } end,
					Close = function() return true end, Send = function() sent = sent + 1 return result[1], result[2] end }
				local pane = assert(w.CW.OpenDynamicRoom(spec))
				eq(pane, f)
				R.Send = function() error("a fight room's line went to ChatRooms") end
				Try("severe")
				eq(sent, 1, "ArenaChat's send")
				eq(f.input:GetText(), ""); eq(f.reply, nil); eq(f.input.focused, false)
				eq(room.RowWith(f, room.NOT_SENT), nil)
				Try("paused")
				eq(sent, 2); eq(f.input:GetText(), "typed words")
			end)
			R.Send = send
			rawset(ns, "WatchChat", saved)
			rawset(ns, "ArenaChat", savedArena)
			if not ok then error(err, 0) end
		end)
	end)
end)

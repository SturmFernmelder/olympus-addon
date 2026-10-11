local ns, test, eq, extra = ...
local ROOT = debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]chat%-channel%-links%.lua$") or "./"
local WithGamepadUI = assert(extra and extra.WithGamepadUI, "WithGamepadUI")

-- 1.2.1: [Olympus], [Captains] and [Lords] before a line in the game's chat are links, as the game's
-- [Party] is, where this client may write in that channel: a left click opens the chat box with
-- /ol, /olc or /oll in it (Channels.lua's end). Channels.lua is loaded with Comm.lua and a gate of
-- their own (as the gate's typed-commands test loads them) in a namespace over the harness's, with
-- its own saved variables, so the hook it registers never reaches the harness's Channels. The game's
-- side stood in for as Forever's UI source has it: hooksecurefunc's post-hook after SetItemRef, which
-- is the game's own handling (it is called first, with the same arguments), the chat box
-- (ChatFrame_OpenChat), the main chat window, Shift. Generic names alone.
local GUILD = "Olympus II"
local SPEAKER, CAPTAIN, LORD = "Test Speaker-Realm", "Test Captain-Realm", "Test Lord-Realm"

local function WithLinks(fn)
	local GLOBALS = { "hooksecurefunc", "SetItemRef", "ChatFrame_OpenChat", "IsShiftKeyDown", "DEFAULT_CHAT_FRAME", "GetGuildInfo",
		"C_ChatInfo", "IsInGuild", "SLASH_OLYMPUSALL1", "SLASH_OLYMPUSCAPTAINS1", "SLASH_OLYMPUSLORDS1" }
	local SLASH = { "OLYMPUSALL", "OLYMPUSCAPTAINS", "OLYMPUSLORDS" }
	local DIALOGS = { "OLYMPUS_CHAT_PRIVACY", "OLYMPUS_PIN", "OLYMPUS_PIN_DOWN", "OLYMPUS_GAMEPAD_RELOAD" }
	local saved = { g = {}, slash = {}, dialogs = {}, events = #EVENT_SCRIPTS, channels = rawget(ns, "Channels") }
	for _, k in ipairs(GLOBALS) do saved.g[k] = rawget(_G, k) end
	for _, k in ipairs(SLASH) do saved.slash[k] = SlashCmdList[k] end
	for _, k in ipairs(DIALOGS) do saved.dialogs[k] = StaticPopupDialogs[k] end
	local w = { rank = 0, printed = {}, opened = {}, refs = {}, hooks = {}, lines = {}, errors = {}, roster = {}, on = {} }
	local ok, err = pcall(function()
		-- The game's side.
		SetItemRef = function(link, text, button, frame) w.refs[#w.refs + 1] = { link = link, text = text, button = button, frame = frame } end
		hooksecurefunc = function(a, b, c)
			local t, key, post = _G, a, b
			if type(a) == "table" then t, key, post = a, b, c end
			local original = t[key]
			assert(type(original) == "function", "hooksecurefunc on something that is no function: " .. tostring(key))
			w.hooks[#w.hooks + 1] = key
			t[key] = function(...) original(...); post(...) end
		end
		ChatFrame_OpenChat = function(text, frame) w.opened[#w.opened + 1] = { text = text, frame = frame } end
		IsShiftKeyDown = function() return w.shift == true end
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) w.lines[#w.lines + 1] = text end }
		GetGuildInfo = function() return GUILD, "rank", w.rank end
		C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
		w.frame = { editBox = {} } -- (one of the game's chat windows: its own box)
		-- The files, in a namespace of their own.
		local cns = setmetatable({}, { __index = ns })
		cns.RegisterEvent, cns.After, cns.Every = function() end, function() end, function() end
		cns.On = function(name, f) w.on[name] = w.on[name] or {}; table.insert(w.on[name], f) end
		cns.db = { addonChat = true, chatWarned = { A = true, C = true, L = true } }
		cns.rdb = {}
		cns.me = "Tester-Realm"
		cns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		cns.SafeCall = function(_, f, ...)
			local fine, e = pcall(f, ...)
			if not fine then w.errors[#w.errors + 1] = tostring(e) end
			return fine
		end
		cns.Moderation = { Hides = function() return false end, SelfOff = function() return w.off end,
			YouText = function(o) return "taken off the chats: " .. tostring(o) end }
		cns.WatchChat = { SelfTimeout = function() return w.timeout end,
			TellTimeout = function(e) w.printed[#w.printed + 1] = "timed out: " .. tostring(e) end }
		cns.Filter = { Hides = function() return false end }
		cns.Roster = setmetatable({ RankOf = function(n) return w.roster[n] end }, { __index = ns.Roster })
		for _, file in ipairs({ "GamepadRegistry", "Gamepad", "Comm", "Channels" }) do
			assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", cns)
		end
		w.ns, w.C = cns, cns.Channels
		w.roster[ns.FullName(SPEAKER)], w.roster[ns.FullName(CAPTAIN)], w.roster[ns.FullName(LORD)] = 3, 1, 0
		-- The login with mouse and keyboard: the commands (Core.lua's "slash"), then each of Channels.lua's.
		cns.Gate.Install("slash")
		w.Login = function() for _, f in ipairs(w.on.LOGIN or {}) do f() end end
		-- A line heard on the channel (new id and time each).
		local id, at = 100, 9000000
		function w.Hear(tier, sender, text)
			id, at = id + 1, at + 100
			return (w.C.Receive("CHANNEL", sender, ns.Codec.EncodeChat(tier, GUILD, id, "PA", text), at))
		end
		-- A click in the game's chat, the game's way: SetItemRef, then the hooks.
		function w.Click(link, button, frame)
			w.opened, w.printed = {}, {}
			SetItemRef(link, "[x]", button or "LeftButton", frame == nil and w.frame or frame or nil)
			return w.opened[1]
		end
		fn(w)
		eq(#w.errors, 0, "no error in the hook: " .. tostring(w.errors[1]))
	end)
	for _, k in ipairs(GLOBALS) do _G[k] = saved.g[k] end
	for _, k in ipairs(SLASH) do SlashCmdList[k] = saved.slash[k] end
	for _, k in ipairs(DIALOGS) do StaticPopupDialogs[k] = saved.dialogs[k] end
	for i = #EVENT_SCRIPTS, saved.events + 1, -1 do EVENT_SCRIPTS[i] = nil end
	rawset(ns, "Channels", saved.channels)
	if not ok then error(err, 0) end
end

local function Link(tier, label) return "|Haddon:Olympus:chan:" .. tier .. "|h[" .. label .. "]|h" end

test("1.2.1 chat channel links: [Olympus], [Captains] and [Lords] are links only where this client may write there (its rank, the chats on, not off them nor timed out), plain before the login's hook and with the gamepad UI", function()
	WithLinks(function(w)
		local C, L = w.C, ns.L
		local A, CA, LO = "[" .. L.CHAN_ALL .. "]", "[" .. L.CHAN_CAPTAINS .. "]", "[" .. L.CHAN_LORDS .. "]"
		w.rank = 0
		eq(C.Tag("A"), A, "before the login's hook: the plain name")
		eq(#w.hooks, 0)
		w.Login()
		eq(table.concat(w.hooks, ","), "SetItemRef", "one post-hook, on SetItemRef")
		w.Login()
		eq(#w.hooks, 1, "once a session")
		-- A Lord writes in all three; a Captain in [Olympus] and [Captains]; a member in [Olympus] alone.
		eq(C.Tag("A"), Link("A", L.CHAN_ALL)); eq(C.Tag("C"), Link("C", L.CHAN_CAPTAINS)); eq(C.Tag("L"), Link("L", L.CHAN_LORDS))
		w.rank = 1
		eq(C.Tag("A"), Link("A", L.CHAN_ALL)); eq(C.Tag("C"), Link("C", L.CHAN_CAPTAINS)); eq(C.Tag("L"), LO, "no [Lords] link for a Captain")
		w.rank = 3
		eq(C.Tag("A"), Link("A", L.CHAN_ALL)); eq(C.Tag("C"), CA); eq(C.Tag("L"), LO)
		-- The line itself: the tag, then the rest byte for byte as before; the Olympus tab's has no tag.
		local line = C.FormatLine("A", SPEAKER, GUILD, "PA", "hello")
		assert(line:find("^" .. Link("A", L.CHAN_ALL):gsub("%p", "%%%0") .. " |Hplayer:"), line)
		eq(line, C.Tag("A") .. " " .. C.FormatLine("A", SPEAKER, GUILD, "PA", "hello", true))
		assert(C.FormatDeleted("A", SPEAKER, GUILD):find("^" .. Link("A", L.CHAN_ALL):gsub("%p", "%%%0") .. " |Hplayer:"), "a deleted line's in its place too")
		eq(C.FormatLine("A", SPEAKER, GUILD, "PA", "hello", true):find("|Haddon:", 1, true), nil, "the Olympus tab's line: no tag")
		-- Can't write: the plain name.
		w.timeout = "until later"
		eq(C.Tag("A"), A, "timed out"); eq(C.CanWrite("A"), false)
		w.timeout, w.off = nil, "netoff"
		eq(C.Tag("A"), A, "taken off the chats")
		w.off = nil
		w.ns.db.addonChat = false
		eq(C.Tag("A"), A, "the chats off")
		w.ns.db.addonChat = true
		local inGuild = IsInGuild
		IsInGuild = function() return false end -- (put back by WithLinks, whatever happens)
		eq(C.Tag("A"), A, "out of every guild")
		IsInGuild = inGuild
		eq(C.Tag("A"), Link("A", L.CHAN_ALL), "writable again: the link again")
		WithGamepadUI(true, function() eq(C.Tag("A"), A, "the gamepad UI: no link") end)
		WithGamepadUI(false, function() eq(C.Tag("A"), Link("A", L.CHAN_ALL)) end)
	end)
end)

test("1.2.1 chat channel links: a line shown in the game's chat carries the link where this client writes, the plain name where it only reads", function()
	WithLinks(function(w)
		local L = ns.L
		w.Login()
		w.rank = 1 -- (a Captain: reads and writes [Olympus] and [Captains])
		eq(w.Hear("A", SPEAKER, "army line"), true)
		eq(w.Hear("C", CAPTAIN, "captains line"), true)
		eq(#w.lines, 2)
		assert(w.lines[1]:find(Link("A", L.CHAN_ALL) .. " |Hplayer:", 1, true), w.lines[1])
		assert(w.lines[2]:find(Link("C", L.CHAN_CAPTAINS) .. " |Hplayer:", 1, true), w.lines[2])
		-- Timed out: he still reads the channel, and the line names it without a link.
		w.timeout = "until later"
		eq(w.Hear("C", CAPTAIN, "while timed out"), true)
		eq(w.lines[3]:find("|Haddon:", 1, true), nil, w.lines[3])
		assert(w.lines[3]:find("^%[" .. L.CHAN_CAPTAINS .. "%] |Hplayer:"), w.lines[3])
		w.timeout = nil
		-- The donations line in the [Olympus] chat (Treasury.lua): its [Olympus] the same.
		local T, keeper = ns.Treasury, "Test Keeper-Realm"
		local savedKeeper, savedMute = T.IsKeeperName, ns.db.chatMute
		rawset(ns, "Channels", w.C)
		ns.db.chatMute = nil
		T.IsKeeperName = function(name) return name == keeper end
		local fine, e = pcall(function()
			T.HandleDonations("CHANNEL", keeper, ("TD~%s~1~%d~"):format(GUILD, ns.Now()))
			assert(w.lines[4] and w.lines[4]:find("^" .. Link("A", L.CHAN_ALL):gsub("%p", "%%%0") .. " "), tostring(w.lines[4]))
		end)
		T.HandleDonations("CHANNEL", keeper, ("TD~%s~0~0~"):format(GUILD))
		T.IsKeeperName, ns.db.chatMute = savedKeeper, savedMute
		if not fine then error(e, 0) end
	end)
end)

test("1.2.1 chat channel links: a left click opens the chat box with /ol, /olc or /oll, in the window clicked; right-click, Shift, a channel closed since and the gamepad UI open nothing", function()
	WithLinks(function(w)
		local L = ns.L
		w.Login()
		w.rank = 0
		local box = w.Click("addon:Olympus:chan:A")
		eq(box and box.text, "/ol ", "[Olympus]: /ol and a space, ready for the line")
		eq(box.frame, w.frame, "the box of the window clicked")
		eq(w.refs[#w.refs].link, "addon:Olympus:chan:A", "the game's own handling first, as for any link")
		eq(w.Click("addon:Olympus:chan:C").text, "/olc ")
		eq(w.Click("addon:Olympus:chan:L").text, "/oll ")
		-- A window without a box of its own (Chattynator's): the game picks the box.
		local other = w.Click("addon:Olympus:chan:A", "LeftButton", { name = "a window of another addon" })
		eq(other.text, "/ol "); eq(other.frame, nil)
		-- Right-click and Shift-click: nothing, as on the plain name before.
		eq(w.Click("addon:Olympus:chan:A", "RightButton"), nil, "right-click")
		w.shift = true
		eq(w.Click("addon:Olympus:chan:A"), nil, "Shift-click")
		w.shift = nil
		eq(#w.printed, 0)
		-- A link printed while he could write, clicked once he can't: nothing opens, he is told why.
		w.rank = 1
		eq(w.Click("addon:Olympus:chan:L"), nil, "demoted since: no box")
		eq(w.printed[1], L.CHAN_ONLY_LORDS:format(L.CHAN_LORDS), "told in Send's words")
		w.timeout = "until later"
		eq(w.Click("addon:Olympus:chan:A"), nil, "timed out since")
		eq(w.printed[1], "timed out: until later", "told by the moderators' own words (WatchChat.TellTimeout)")
		w.timeout = nil
		w.ns.db.addonChat = false
		eq(w.Click("addon:Olympus:chan:A"), nil, "the chats off since")
		eq(w.printed[1], L.CHAT_OFF)
		w.ns.db.addonChat = true
		-- The gamepad UI: the hook the game keeps does nothing.
		WithGamepadUI(true, function()
			eq(w.Click("addon:Olympus:chan:A"), nil, "no chat box with the gamepad UI")
			eq(#w.printed, 0)
		end)
		eq(w.Click("addon:Olympus:chan:A").text, "/ol ", "mouse and keyboard again")
	end)
end)

test("1.2.1 chat channel links: every other link is the game's alone (an item, a player, another addon's, a tag of no channel), and a gamepad login registers no hook", function()
	WithLinks(function(w)
		w.Login()
		w.rank = 0
		for _, link in ipairs({ "item:19019::::::::60:::::::::", "player:Test Speaker-Realm", "channel:PARTY", "addon:OtherAddon:chan:A",
			"addon:Olympus:chan:X", "addon:Olympus:chan:AA", "addon:Olympus:chan:", "addon:Olympus", "" }) do
			local before = #w.refs
			eq(w.Click(link), nil, "not ours: " .. link)
			eq(#w.refs, before + 1, "the game handled it: " .. link); eq(w.refs[#w.refs].link, link)
			eq(#w.printed, 0, "nothing said: " .. link)
		end
		eq(w.Click(nil), nil, "no link")
	end)
	-- A login with the gamepad UI: nothing registered, no link; mouse and keyboard then: hooked, once.
	WithGamepadUI(true, function()
		WithLinks(function(w)
			w.Login()
			eq(#w.hooks, 0, "no hook at a gamepad login")
			eq(w.C.Tag("A"), "[" .. ns.L.CHAN_ALL .. "]")
			eq(w.ns.Gate.Install("chat-links"), false)
			eq(#w.hooks, 0)
		end)
	end)
	WithLinks(function(w)
		WithGamepadUI(true, function() w.Login() end)
		eq(#w.hooks, 0)
		eq(w.ns.Gate.Install("chat-links"), true, "the switch to mouse and keyboard")
		eq(#w.hooks, 1)
		w.ns.Gate.Install("chat-links")
		eq(#w.hooks, 1, "once a session")
		eq(w.C.Tag("A"), Link("A", ns.L.CHAN_ALL))
	end)
end)

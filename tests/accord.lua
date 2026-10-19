-- 1.2.5.1: the Olympus Accord (Olympus/Accord.lua), Olympus's terms of use, and the BattleTag it
-- asks for. These tests run the real Accord.lua, Comm.lua, WatchChat.lua and UI.lua against the
-- harness's stand-ins of the game: Battle.net (BNGetInfo, BNConnected) is stubbed per test and put
-- back after (a stub proves nothing about the client: the in-game checks are in docs/BETA-TESTING.md).
-- Every name and BattleTag here is invented.
local ns, test, eq, H = ...
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]accord%.lua$")) or "./"
local L = ns.L
local TAG = "Tester#1234"
local RealFire = ns.Fire -- (Scene records ns.Fire; a test that needs the real listeners calls this)
local COUNCILLOR = "Iron Warden-Realm"
local MEMBER = "Member7-Realm" -- (one of the harness's guild roster)

local GLOBALS = { "BNGetInfo", "BNConnected", "BNFeaturesEnabledAndConnected", "issecretvalue", "GetTime", "GetGuildInfo",
	"IsInGuild", "InCombatLockdown", "IsInInstance", "C_ChatInfo" }
local FIELDS = { "Print", "After", "Every", "Now", "Fire", "KingsScreen", "IsKingCharacter", "RegisterEvent", "me", "ACCORD_VERSION" }
local COMM = { "Whisper", "Send", "CheckMembership", "JoinSoon", "RequestKey", "Hello", "ChannelName", "QueueRoom", "DeliveredLogged" }

-- A scene: this account's Olympus Accord as opts says (opts.accepted: accepted for TAG), the game's
-- Battle.net (w.bn: up, tag), time (w.Run), what Accord.lua asks of Comm (recorded, never sent:
-- the transport's own tests use the real Comm), The Watch's chat moderation loaded fresh (its
-- InRoom: the moderation team; opts.team puts this character on the High Council's list).
local function Scene(fn, opts)
	opts = opts or {}
	local A = ns.Accord
	local saved = { g = {}, f = {}, c = {}, accord = ns.db.accord, kingAccount = ns.db.kingAccount, wc = rawget(ns, "WatchChat"), viewAs = rawget(ns, "ViewAs"),
		council = ns.rdb.council, tags = ns.rdb.battletags, chatMod = ns.rdb.chatMod, claimed = ns.Data.ClaimedGuild,
		consentAsk = ns.Consent.Ask }
	for _, k in ipairs(GLOBALS) do saved.g[k] = rawget(_G, k) end
	for _, k in ipairs(FIELDS) do saved.f[k] = rawget(ns, k) end
	for _, k in ipairs(COMM) do saved.c[k] = ns.Comm[k] end
	local w = { now = 1800000000, mono = 5000, printed = {}, timers = {}, tickers = {}, fired = {}, whispers = {}, sends = {},
		calls = {}, events = {}, claims = {}, bn = { up = true, tag = TAG }, channel = "OlympusNet" }
	local ok, err = pcall(function()
		GetTime = function() return w.mono end
		ns.Now = function() return w.now end
		ns.Print = function(m) w.printed[#w.printed + 1] = tostring(m) end
		ns.After = function(sec, where, f) w.timers[#w.timers + 1] = { at = w.mono + (tonumber(sec) or 0), where = where, f = f } end
		ns.Every = function(sec, where, f) w.tickers[#w.tickers + 1] = { sec = sec, where = where, f = f } return { Cancel = function() end } end
		ns.Fire = function(name, ...) w.fired[#w.fired + 1] = { name, ... } end
		ns.RegisterEvent = function(event, f) w.events[event] = w.events[event] or {}; table.insert(w.events[event], f) end
		ns.KingsScreen = function() return w.kingScreen == true end
		ns.IsKingCharacter = function(name) return w.king == true and name == ns.me end
		BNConnected = function() return w.bn.up end
		BNGetInfo = function() if not w.bn.up then return nil end return 1, w.bn.tag, nil, "", false, false, false end
		BNFeaturesEnabledAndConnected, issecretvalue = nil, nil
		InCombatLockdown, IsInInstance = function() return false end, function() return false end
		ns.Comm.Whisper = function(to, msg, key, urgent, logged, done, options)
			w.whispers[#w.whispers + 1] = { to = to, msg = msg, key = key, logged = logged, done = done, options = options }
			return true
		end
		ns.Comm.Send = function(dist, msg, key) w.sends[#w.sends + 1] = { dist = dist, msg = msg, key = key } return true end
		for _, k in ipairs({ "CheckMembership", "JoinSoon", "RequestKey", "Hello" }) do
			ns.Comm[k] = function(...) w.calls[#w.calls + 1] = k .. "(" .. table.concat((function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return t end)(...), ",") .. ")" end
		end
		ns.Comm.ChannelName = function() return w.channel end
		ns.Comm.QueueRoom = function() return 60 end
		ns.Comm.DeliveredLogged = function() return w.logged ~= false end
		ns.Data.ClaimedGuild = function(name) return w.claims[ns.FullName(name)] end
		-- (The privacy page that follows an accept: its own tests; here who asked it.)
		ns.Consent.Ask = function(reason) w.consentAsked = reason return false end
		-- This character is the harness's own, whatever an earlier file's test left in ns.me
		-- (AsSoldier's "Soldier-Realm" made the team scenes fail in a full run; put back after).
		ns.me = "Tester-Realm"
		-- The moderation team: WatchChat.lua's own InRoom (the High Council's list here).
		ns.rdb.council = { at = 1, names = { ["iron warden"] = "Iron Warden" } }
		if opts.team then ns.rdb.council.names.tester = "Tester" end
		ns.rdb.battletags, ns.rdb.chatMod = nil, nil
		local wns = setmetatable({ On = function() end, RegisterEvent = function() end,
			Comm = setmetatable({ Handle = function() end }, { __index = ns.Comm }) }, { __index = ns })
		assert(loadfile(ROOT .. "Olympus/WatchChat.lua"))("Olympus", wns)
		ns.WatchChat = wns.WatchChat
		A.Reset()
		ns.db.kingAccount = nil
		ns.db.accord = opts.accepted and { v = ns.ACCORD_VERSION, yes = true, at = w.now - 100, fp = A.Fp(TAG), told = {} } or nil
		-- Time on, and every timer due runs (in order).
		function w.Run(sec)
			local stop = w.mono + (sec or 0)
			while true do
				local first
				for i, t in ipairs(w.timers) do if t.at <= stop and (not first or t.at < w.timers[first].at) then first = i end end
				if not first then break end
				local t = table.remove(w.timers, first)
				w.now, w.mono = w.now + (t.at - w.mono), t.at
				t.f()
			end
			w.now, w.mono = w.now + (stop - w.mono), stop
		end
		function w.Fired(name)
			local out = {}
			for _, e in ipairs(w.fired) do if e[1] == name then out[#out + 1] = e end end
			return out
		end
		function w.Said(text)
			for _, p in ipairs(w.printed) do if p == text then return true end end
			return false
		end
		fn(w, A)
	end)
	for _, k in ipairs(GLOBALS) do rawset(_G, k, saved.g[k]) end
	for _, k in ipairs(FIELDS) do rawset(ns, k, saved.f[k]) end
	for _, k in ipairs(COMM) do ns.Comm[k] = saved.c[k] end
	ns.db.accord, ns.db.kingAccount, ns.WatchChat, ns.ViewAs = saved.accord, saved.kingAccount, saved.wc, saved.viewAs
	ns.rdb.council, ns.rdb.battletags, ns.rdb.chatMod, ns.Data.ClaimedGuild = saved.council, saved.tags, saved.chatMod, saved.claimed
	ns.Consent.Ask = saved.consentAsk
	A.Reset()
	if not ok then error(err, 0) end
end

-- Every text a list of lines shows: its text, right side and tooltip.
local function Shown(lines)
	local out = {}
	for _, l in ipairs(lines) do
		out[#out + 1] = tostring(l.text or "") .. " | " .. tostring(l.right or "")
		if type(l.tooltip) == "function" then
			local tt = { AddLine = function(_, text) out[#out + 1] = tostring(text) end }
			l.tooltip(tt)
		end
	end
	return table.concat(out, "\n")
end

-- A BT as the player's client words it.
local function BT(at, guild, tag) return ("BT~1~1~%d~%s~%s"):format(at or 1799990000, guild or "Olympus II", tag or TAG) end

test("accord: an account that has not accepted it is no member: nothing is sent (the hello, a line, a whisper, the Join screen's asks), no channel joined, no census election, no recruiting nag", function()
	local saved = { accord = ns.db.accord, info = C_ChatInfo, join = rawget(_G, "JoinChannelByName"), channel = GetChannelName,
		broadcast = ns.Comm.MaybeBroadcast, rdb = ns.rdb, dialogs = {}, guild = GetGuildInfo }
	for k, v in pairs(StaticPopupDialogs) do saved.dialogs[k] = v end
	local ok, err = pcall(function()
		ns.db.accord = nil
		eq(ns.AccordAccepted(), false); eq(ns.InOlympusGuild(), true, "in an Olympus guild"); eq(ns.IsMember(), false, "but no member")
		local cns = H.FreshComm()
		local sent, joined = {}, {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist, to) sent[#sent + 1] = dist .. " " .. msg end
		C_ChatInfo.SendAddonMessageLogged = C_ChatInfo.SendAddonMessage
		JoinChannelByName = function(name) joined[#joined + 1] = name end
		GetChannelName = function() return 0 end
		local C = cns.Comm
		C.Hello(true); C.Pump()
		eq(#sent, 0, "no hello")
		C.JoinChannel()
		eq(#joined, 0, "no channel")
		local why
		C.Send("GUILD", "Z9~a line", nil, nil, nil, function(okSend, w) why = w end)
		eq(why, "left", "a line refused")
		why = nil
		C.Whisper("Somebody-Realm", "Z9~a word", nil, nil, true, function(okSend, w) why = w end)
		eq(why, "left", "a whisper refused")
		C.SendBatch("GUILD", { "Z9~a", "Z9~b" }, nil, nil, nil, function(okSend, w) why = w end)
		eq(why, "left")
		for _, msg in ipairs({ "J1~1", "J3~Olympus II~12~MAGE", "QC~1~A" }) do
			eq(C.WhisperOutside("Somebody", msg), false, "an outsider's ask: " .. msg)
		end
		C.Pump()
		eq(#sent, 0, "nothing at all")
		-- The census: the roster is read, this client elects nobody (the guild's others report).
		local elected = 0
		ns.Comm.MaybeBroadcast = function() elected = elected + 1 end
		ns.rdb = { guilds = {}, seen = {} }
		ns.Roster.RequestScan(true); ns.Roster.TryScan()
		eq(elected, 0, "no census election")
		ns.db.accord = { v = ns.ACCORD_VERSION, yes = true, at = 0 }
		ns.Roster.RequestScan(true); ns.Roster.TryScan()
		eq(elected, 1, "accepted: it takes part")
		ns.db.accord = nil
		-- Recruit's daily nag is for players outside Olympus, never this one.
		local rns, login, printed = nil, {}, {}
		rns = setmetatable({ On = function(name, f) if name == "LOGIN" then login[#login + 1] = f end end,
			After = function(_, _, f) f() end, RegisterEvent = function() end, Print = function(m) printed[#printed + 1] = m end,
			Comm = setmetatable({ Handle = function() end, HandleOutside = function() end }, { __index = ns.Comm }),
			Who = setmetatable({ Listen = function() end }, { __index = ns.Who }) }, { __index = ns })
		local lastNag = ns.db.lastNag
		ns.db.lastNag = nil
		assert(loadfile(ROOT .. "Olympus/Recruit.lua"))("Olympus", rns)
		for _, f in ipairs(login) do f() end
		eq(#printed, 0, "no join-Olympus nag in an Olympus guild")
		GetGuildInfo = function() return "Some Other Guild" end
		for _, f in ipairs(login) do f() end
		eq(#printed, 1, "outside Olympus: the nag, as before")
		ns.db.lastNag = lastNag
	end)
	ns.db.accord, C_ChatInfo, JoinChannelByName, GetChannelName = saved.accord, saved.info, saved.join, saved.channel
	ns.Comm.MaybeBroadcast, ns.rdb, GetGuildInfo = saved.broadcast, saved.rdb, saved.guild
	wipe(StaticPopupDialogs); for k, v in pairs(saved.dialogs) do StaticPopupDialogs[k] = v end
	ns.Roster.Scan() -- (the roster of the other tests back)
	if not ok then error(err, 0) end
end)

test("accord: before it is accepted the privacy page never asks; I accept keeps the version, the time and the tag's hash (never the tag) for the account, then starts the addon (the roster, the channel and its census ask, the realm key, the hello) and the privacy page follows", function()
	H.WithUI(function() Scene(function(w, A)
		local savedAsk = ns.Consent.Ask
		local ok, err = pcall(function()
			eq(ns.Consent.Ask("login"), false, "the privacy page waits for the Accord")
			eq(ns.Consent.Waiting(), false)
			local asked
			ns.Consent.Ask = function(reason) asked = reason return true end
			A.Show("login")
			eq(A.Accept(), true)
			local a = ns.db.accord
			eq(a.v, ns.ACCORD_VERSION); eq(a.yes, true); eq(a.at, w.now); eq(a.fp, A.Fp(TAG))
			-- (Changed on purpose, 1.2.5.1's review: one byte of the hash, not two. With two, a known
			-- name's digits came back from the saved file almost alone; see the fingerprint's test.)
			assert(type(a.fp) == "string" and #a.fp == 2, "one byte of the hash")
			for k, v in pairs(a) do assert(not tostring(v):find("1234", 1, true), "the tag is never saved: " .. k) end
			eq(ns.IsMember(), true, "a member now")
			eq(#w.Fired("ACCORD_CHANGED"), 1); eq(w.Fired("ACCORD_CHANGED")[1][2], true)
			eq(table.concat(w.calls, " "), "CheckMembership() JoinSoon(inf) RequestKey() Hello(true)",
				"as when one joins an Olympus guild: the channel at once (its census ask follows), the key, the hello")
			eq(#w.Fired("DATA_CHANGED"), 1)
			assert(w.Said(L.ACCORD_ACCEPTED:format(ns.ACCORD_VERSION)))
			eq(A.Frame():IsShown(), false)
			eq(asked, nil, "the privacy page a moment after")
			w.Run(A.HANDOFF)
			eq(asked, "accord")
			-- The account's, so an alt of it is not asked again.
			eq(A.Ask("login"), false); eq(A.Ask("window"), false)
		end)
		ns.Consent.Ask = savedAsk
		if not ok then error(err, 0) end
	end) end)
end)

test("accord: the real transport after I accept: the hello goes on GUILD, the channel is joined and the census asked for", function()
	local saved = { accord = ns.db.accord, info = C_ChatInfo, join = rawget(_G, "JoinChannelByName"), channel = GetChannelName, time = GetTime }
	local ok, err = pcall(function()
		ns.db.accord = nil
		local cns = H.FreshComm()
		local sent, joined, timers = {}, {}, {}
		C_ChatInfo.SendAddonMessage = function(_, msg, dist) sent[#sent + 1] = dist .. " " .. msg end
		JoinChannelByName = function(name) joined[#joined + 1] = name end
		GetChannelName = function() return 0 end
		cns.After = function(sec, where, f) timers[#timers + 1] = where end
		cns.Every = function() return { Cancel = function() end } end
		cns.Print, cns.Fire = function() end, function() end
		cns.Consent = { Ask = function() end }
		cns.Roster = setmetatable({ RequestScan = function() end }, { __index = ns.Roster })
		BNGetInfo, BNConnected = function() return 1, TAG end, function() return true end
		assert(loadfile(ROOT .. "Olympus/Accord.lua"))("Olympus", cns)
		cns.Comm.Hello(true); cns.Comm.Pump()
		eq(#sent, 0, "nothing before")
		eq(cns.Accord.Accept(), true)
		local clock = 1000
		GetTime = function() return clock end
		for _ = 1, 10 do clock = clock + 2; cns.Comm.Pump() end
		local hello
		for _, m in ipairs(sent) do if m:find("^GUILD H1~") then hello = m end end
		eq(hello, "GUILD H1~" .. ns.VERSION .. "~Realm~p", "the hello")
		eq(sent[1], "GUILD K0~", "and the realm key asked of the guild")
		eq(#joined, 1, "the channel")
		local census = false
		for _, where in ipairs(timers) do if where == "census request" then census = true end end
		eq(census, true, "the census asked for once on it")
	end)
	ns.db.accord, C_ChatInfo, JoinChannelByName, GetChannelName, GetTime = saved.accord, saved.info, saved.join, saved.channel, saved.time
	BNGetInfo, BNConnected = nil, nil
	if not ok then error(err, 0) end
end)

test("accord: no BattleTag to read: I accept stays off and the letter says why (Battle.net down: it tries again by itself and enables it when Battle.net is back); no BNGetInfo, or a tag of another shape: Olympus can't be used here", function()
	H.WithUI(function()
		Scene(function(w, A)
			w.bn.up = false
			eq(select(2, A.ReadTag()), "offline")
			local f = A.Show("login")
			eq(f.acceptEnabled, false, "I accept off")
			assert(f.tagNote:GetText():find(L.ACCORD_TAG_WAIT, 1, true), "why")
			eq(f.retry:IsShown(), true); eq(f.reveal:IsShown(), false)
			assert(f.footer:GetText():find(L.ACCORD_ACCEPT_WAIT_TIP, 1, true), "and what I accept waits for")
			local okAccept, why = A.Accept()
			eq(okAccept, false); eq(why, "tag"); eq(ns.db.accord, nil, "nothing kept")
			f.accept:Click()
			eq(ns.db.accord, nil, "a click on the greyed button does nothing")
			-- Battle.net back: its event (registered at login, each through pcall) and the letter follows.
			A.OnLogin()
			for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "BN_CONNECTED", "BN_DISCONNECTED", "BN_INFO_CHANGED" }) do assert(w.events[e], e) end
			w.bn.up = true
			w.events.BN_CONNECTED[1]()
			eq(f.acceptEnabled, true, "on again")
			assert(f.tagNote:GetText():find(L.ACCORD_TAG_TO, 1, true))
			eq(f.retry:IsShown(), false)
			-- (While it waits it reads Battle.net again every READ_GAP, on its own.)
			w.bn.up = false
			w.mono = w.mono + A.READ_GAP
			A.Refresh(false)
			eq(f.acceptEnabled, false)
			w.bn.up = true
			f.retry:Click()
			eq(f.acceptEnabled, true, "Try again reads it at once")
			-- A client without BNGetInfo, and tags of another shape: never a tag.
			local function Reason() return select(2, A.ReadTag()) end
			BNGetInfo = nil
			eq(Reason(), "api")
			A.Refresh(true)
			assert(f.tagNote:GetText():find(L.ACCORD_TAG_NONE, 1, true)); eq(f.retry:IsShown(), false)
			BNGetInfo = function() return 1, w.bn.tag end
			for _, bad in ipairs({ "x", "a~b#1", "Name#12a", "|cffff0000Red#1", ("a"):rep(60) .. "#12345" }) do
				w.bn.tag = bad
				eq(A.ReadTag(), nil, bad); eq(Reason(), "shape", bad)
			end
			w.bn.tag = ""
			eq(Reason(), "offline", "an empty value: not there yet")
			-- A secret value (Forever hides some from addons): never compared, never read.
			w.bn.tag = TAG
			issecretvalue = function(v) return v == TAG end
			eq(A.ReadTag(), nil); eq(Reason(), "offline")
			issecretvalue = function(v) return v == true end
			eq(Reason(), "offline", "a secret connected flag too")
			issecretvalue = nil
			-- Where the client has BNFeaturesEnabledAndConnected (Classic's FriendsFrame asks it), it decides.
			BNFeaturesEnabledAndConnected = function() return false end
			eq(Reason(), "offline")
			BNFeaturesEnabledAndConnected = function() return true end
			eq(A.ReadTag(), TAG)
			f:Hide()
		end)
	end)
end)

test("accord: an account that accepted is never locked out while Battle.net is down: the gate reads the saved acceptance alone", function()
	Scene(function(w, A)
		w.bn.up = false
		A.OnLogin()
		for _, f in ipairs(w.events.PLAYER_ENTERING_WORLD) do f() end
		A.Check()
		eq(ns.IsMember(), true); eq(ns.db.accord.yes, true)
		w.Run(A.LOGIN_WAIT + 1)
		for _, t in ipairs(w.tickers) do t.f() end
		eq(A.Frame(), nil, "never asked again")
		eq(#w.printed, 0)
		BNGetInfo = nil
		A.Check()
		eq(ns.IsMember(), true, "nor on a client that gives no tag at all")
	end, { accepted = true })
end)

test("accord: this account's BattleTag changed: Olympus stops (the channel left), the player is told and asked again; accepting again starts it", function()
	H.WithUI(function()
		Scene(function(w, A)
			w.bn.tag = "Another#5678"
			A.Check()
			eq(ns.IsMember(), false, "off"); eq(ns.db.accord.yes, false); eq(ns.db.accord.why, "tag")
			eq(w.Fired("ACCORD_CHANGED")[1][2], false)
			eq(w.calls[1], "CheckMembership()", "the channel left (Comm.CheckMembership)")
			assert(w.Said(L.ACCORD_TAG_CHANGED))
			assert(A.Frame() and A.Frame():IsShown(), "the letter")
			assert(A.StatusLine():find("asked again", 1, true))
			eq(A.Accept(), true)
			eq(ns.IsMember(), true); eq(ns.db.accord.fp, A.Fp("Another#5678"))
			-- The new tag reads the same: nothing more.
			A.Check()
			eq(ns.IsMember(), true)
		end, { accepted = true })
	end)
end)

test("accord: Not now keeps Olympus off and sends nothing; the login's tries leave it for this session, the window's open asks again; no X and never on the escape list, with mouse and keyboard or the gamepad UI", function()
	H.WithUI(function()
		for _, pad in ipairs({ false, true }) do
			H.WithGamepadUI(pad, function(game)
				Scene(function(w, A)
					A.OnLogin()
					w.Run(A.LOGIN_WAIT)
					local f = A.Frame()
					assert(f and f:IsShown(), "the letter, LOGIN_WAIT after login")
					eq(#game.shown, 0, "Olympus's own window, never the game's popup")
					eq(f:GetName(), "OlympusAccordFrame"); eq(f:GetFrameStrata(), "DIALOG")
					eq(f.CloseButton, nil, "no X")
					for _, name in ipairs(UISpecialFrames or {}) do assert(name ~= "OlympusAccordFrame", "not on the escape list") end
					eq(f.notNow:GetText(), L.ACCORD_NOT_NOW); eq(f.accept:GetText(), L.ACCORD_ACCEPT)
					eq(f.notNow.points[#f.notNow.points][1], "BOTTOMRIGHT", "the conservative choice on the left")
					eq(f.accept.points[#f.accept.points][1], "BOTTOMLEFT", "the primary one on the right")
					eq(f.notNow:GetWidth(), f.accept:GetWidth())
					f.notNow:Click()
					eq(f:IsShown(), false); eq(ns.db.accord, nil, "nothing saved")
					assert(w.Said(L.ACCORD_DECLINED))
					eq(#w.whispers + #w.sends, 0, "nothing sent")
					eq(#w.Fired("ACCORD_CLOSED"), 1)
					for _, t in ipairs(w.tickers) do t.f() end
					eq(f:IsShown(), false, "not again by itself this session")
					eq(A.Ask("login"), false)
					eq(A.Ask("window"), true, "the window's open is the player's own ask")
					f.notNow:Click()
					-- A combat or an instance: never then.
					A.Reset()
					InCombatLockdown = function() return true end
					eq(A.Ask("window"), false)
					InCombatLockdown = function() return false end
					IsInInstance = function() return true end
					eq(A.Ask("window"), false)
				end)
			end)
		end
	end)
end)

test("accord: a new version of the Accord asks again: Olympus off until it is accepted, said once, the new version kept", function()
	H.WithUI(function() Scene(function(w, A)
		ns.ACCORD_VERSION = 2
		eq(ns.AccordAccepted(), false); eq(ns.IsMember(), false)
		A.Check(); A.Check()
		local n = 0
		for _, p in ipairs(w.printed) do if p == L.ACCORD_NEW_VERSION:format(2) then n = n + 1 end end
		eq(n, 1, "said once a session")
		eq(A.Ask("login"), true)
		eq(A.Accept(), true)
		eq(ns.db.accord.v, 2); eq(ns.IsMember(), true)
	end, { accepted = true }) end)
end)

test("accord: an alt of the same game account is not asked again; each character answers the team's ask on its own", function()
	Scene(function(w, A)
		eq(A.Accept(), true)
		ns.me = "Tester Alt-Realm"
		eq(ns.IsMember(), true, "the account's acceptance")
		eq(A.Ask("login"), false)
		local function Told()
			A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
			w.Run(A.DELAY_MAX)
			local job = w.whispers[#w.whispers]
			if job and job.done then job.done(true) end
			return #w.whispers
		end
		eq(Told(), 1, "the alt tells")
		ns.me = "Tester-Realm"
		eq(Told(), 2, "the main tells too: its own character")
		eq(Told(), 2, "not again within TELL_EVERY")
		ns.me = "Tester Alt-Realm"
		eq(Told(), 2)
	end)
end)

test("accord: the team's ask: only a team member's, on the channel, answered once by a logged whisper after a random delay, to him alone, its permit checked again at the game's send; not again within 20 hours; I accept tells recent askers at once", function()
	Scene(function(w, A)
		A.random = function(lo, hi) return lo end
		-- Not the team: nothing.
		eq(select(2, A.HandleAsk("CHANNEL", "Plain Member-Realm", "BQ~1")), "team")
		eq(A.HandleAsk("GUILD", COUNCILLOR, "BQ~1"), false, "never over GUILD")
		eq(A.HandleAsk("WHISPER", COUNCILLOR, "BQ~1"), false, "nor whispered")
		eq(A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~2"), false, "a version it doesn't know")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 0)
		-- A councillor's ask: answered after the delay, not at once.
		eq(A.HandleAsk("CHANNEL", "Iron Warden", "BQ~1"), true, "a same-realm name")
		eq(#w.whispers, 0, "not at once")
		w.Run(A.DELAY_MIN)
		eq(#w.whispers, 1)
		local job = w.whispers[1]
		eq(job.to, COUNCILLOR); eq(job.logged, true, "logged: the server keeps it")
		eq(job.msg, ("BT~1~1~%d~Olympus II~%s"):format(ns.db.accord.at, TAG))
		assert(#job.msg <= 255)
		local o = job.options
		local function Permit(to, payload) return o.permit(o.owner, o.key, "WHISPER", to or COUNCILLOR, payload or job.msg) end
		eq(Permit(), true)
		eq(Permit("Somebody Else-Realm"), false, "to him alone")
		eq(Permit(nil, job.msg .. "x"), false)
		eq(o.permit(o.owner, o.key, "CHANNEL", COUNCILLOR, job.msg), false, "never on the channel")
		w.bn.tag = "Other#9999"
		eq(select(2, Permit()), "revoked", "the tag changed before the send")
		w.bn.tag = TAG
		ns.rdb.council.names["iron warden"] = nil
		eq(select(2, Permit()), "revoked", "no longer in the team")
		ns.rdb.council.names["iron warden"] = "Iron Warden"
		job.done(true)
		-- Again within TELL_EVERY: nothing; after it: once more.
		A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 1, "once in 20 hours")
		w.now = w.now + A.TELL_EVERY
		A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 2)
		-- Two asks while one waits: one answer.
		w.whispers[2].done(true)
		w.now = w.now + A.TELL_EVERY
		A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1"); A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 3, "one answer")
		-- Asked again (a new version) and accepted: the recent asker is told at once, whenever he last was.
		w.whispers[3].done(true)
		ns.db.accord.v = 0
		eq(ns.IsMember(), false)
		A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 3, "no member: no answer")
		eq(A.Accept(), true)
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 4, "told on accepting")
		eq(w.whispers[4].to, COUNCILLOR)
		assert(A.StatusLine():find("told 3", 1, true), A.StatusLine())
	end, { accepted = true })
end)

test("accord: a team client asks on the channel and keeps an answer only when logged, asked lately, well made, from an Olympus guild and not too often; the guild known by the roster, the sender's own messages or his word alone", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		ns.Roster.Scan() -- (the harness's guild roster: Member1 to Member1000)
		eq(A.TeamMember(), true)
		local function Why(dist, sender, text) return select(2, A.HandleTag(dist, sender, text)) end
		eq(Why("WHISPER", MEMBER, BT()), "unasked", "before any ask of ours")
		eq(A.AskTeam(), true)
		eq(#w.sends, 1); eq(w.sends[1].dist, "CHANNEL"); eq(w.sends[1].msg, "BQ~1")
		w.channel = nil
		eq(A.AskTeam(), false, "off the channel: no ask")
		w.channel = "OlympusNet"
		eq(Why("CHANNEL", MEMBER, BT()), "dist"); eq(Why("GUILD", MEMBER, BT()), "dist")
		w.logged = false
		eq(Why("WHISPER", MEMBER, BT()), "unlogged")
		w.logged = true
		for _, bad in ipairs({ "BT~1~1~x~Olympus II~" .. TAG, "BT~1~1~5~Olympus II~Tag", "BT~1~1~5~Olympus II~a#1~b", "BT~2~1~5~Olympus II~" .. TAG,
			"BT~1~1~5~Olympus II~" .. ("a"):rep(70) .. "#1", "BT~1~1~5~Olympus II~" .. TAG .. ("x"):rep(250) }) do
			eq(Why("WHISPER", MEMBER, bad), "shape", bad)
		end
		eq(Why("WHISPER", MEMBER, BT(nil, "Some Other Guild")), "guild")
		eq(ns.rdb.battletags == nil or next(ns.rdb.battletags.rows) == nil, true, "nothing kept so far")
		-- Kept: a guildmate (our roster), one his messages tied to an Olympus guild, one on his word.
		eq(A.HandleTag("WHISPER", MEMBER, BT()), true)
		w.claims["Quiet Mender-Realm"] = "Olympus III"
		eq(A.HandleTag("WHISPER", "Quiet Mender-Realm", BT(nil, "Olympus III", "Mender#4321")), true)
		eq(A.HandleTag("WHISPER", "Brisk Lantern-Realm", BT(nil, "Olympus III", "Lantern#7777")), true)
		local rows = ns.rdb.battletags.rows
		eq(rows[ns.Fold(MEMBER)].via, "roster"); eq(rows[ns.Fold("Quiet Mender-Realm")].via, "claim"); eq(rows[ns.Fold("Brisk Lantern-Realm")].via, "self")
		eq(rows[ns.Fold(MEMBER)].tag, TAG); eq(rows[ns.Fold(MEMBER)].guild, "Olympus II")
		eq(#w.Fired("ACCORD_TEAM_CHANGED"), 3)
		-- The same again soon: refused; another tag: kept, the old one as before.
		eq(Why("WHISPER", MEMBER, BT()), "rate")
		eq(A.HandleTag("WHISPER", MEMBER, BT(nil, nil, "Changed#2222")), true)
		eq(rows[ns.Fold(MEMBER)].prev, TAG); eq(rows[ns.Fold(MEMBER)].tag, "Changed#2222")
		-- Past TAKE_WINDOW after our last ask: unasked again.
		w.Run(A.TAKE_WINDOW + 1)
		eq(Why("WHISPER", "Late Comer-Realm", BT(nil, nil, "Late#1")), "unasked")
		-- Kept KEEP after the last one received, then dropped.
		w.now = w.now + A.KEEP + 1
		A.Prune()
		eq(next(ns.rdb.battletags.rows), nil, "dropped after 180 days")
	end, { accepted = true, team = true })
end)

test("accord: an ordinary member's client never keeps, sends on or shows a BattleTag", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		eq(A.TeamMember(), false); eq(A.TeamShown(), false)
		eq(A.AskTeam(), false); eq(#w.sends, 0, "no ask")
		eq(select(2, A.HandleTag("WHISPER", MEMBER, BT())), "team")
		eq(ns.rdb.battletags, nil, "nothing kept")
		eq(#A.TeamLines(), 0); eq(#A.ProfileLines(MEMBER), 0)
		-- His own answer goes to the team alone, never anywhere else.
		A.random = function(lo) return lo end
		A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 1); eq(w.whispers[1].to, COUNCILLOR); eq(#w.sends, 0, "nothing on the channel or GUILD")
	end, { accepted = true })
end)

-- (Changed on purpose, 1.2.5.1's review: a BattleTag's digits were shown in full on every team
-- screen but the King's; they now stay hidden there too until the page's Show, for REVEAL seconds.
-- On the King's screen no part of a tag shows: a name of four letters or fewer showed whole.)
test("accord: the team's page groups one player's characters, the digits hidden until its Show (a moment); the King's screen never shows any part of a BattleTag, his eye button included, and masks the names; never in a role preview", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		A.AskTeam()
		A.HandleTag("WHISPER", MEMBER, BT())
		A.HandleTag("WHISPER", "Second Alt-Realm", BT())
		A.HandleTag("WHISPER", "Brisk Lantern-Realm", BT(nil, nil, "Bob#7777"))
		eq(A.Count(), 3); eq(#A.Groups(), 2)
		eq(A.Groups()[1].tag, TAG, "the most characters first"); eq(#A.Groups()[1].rows, 2)
		local function Page() return Shown(A.TeamLines()) .. "\n" .. Shown(A.ProfileLines(MEMBER)) end
		local text = Page()
		assert(not text:find("1234", 1, true) and not text:find("7777", 1, true), "no digits until Show: " .. text)
		assert(text:find("Tester#****", 1, true) and text:find("Bob#****", 1, true), text)
		assert(text:find(L.ACCORD_TEAM_SHARED:format(2), 1, true)); assert(text:find(L.ACCORD_TEAM_ONE, 1, true))
		assert(text:find(L.ACCORD_TEAM_SCOPE, 1, true), "never act on one alone")
		assert(text:find(L.ACCORD_TEAM_PROFILE:format("Tester#****"), 1, true))
		assert(text:find(L.ACCORD_TEAM_PROFILE_ALSO:format("Second Alt"), 1, true), text)
		assert(Shown(A.ProfileLines("Nobody Here-Realm")):find(L.ACCORD_TEAM_PROFILE_NONE, 1, true))
		-- The page's Show: the digits for REVEAL seconds, the page redrawn now and when they hide again.
		local show
		for _, l in ipairs(A.TeamLines()) do if l.id == "accord-team-reveal" then show = l end end
		assert(show and show.text:find(L.ACCORD_TEAM_SHOW, 1, true) and show.onClick, "the page's Show")
		local fired = #w.Fired("ACCORD_TEAM_CHANGED")
		show.onClick()
		eq(#w.Fired("ACCORD_TEAM_CHANGED"), fired + 1, "the page redrawn")
		text = Page()
		assert(text:find(TAG, 1, true) and text:find("Bob#7777", 1, true), text)
		assert(text:find(L.ACCORD_TEAM_PROFILE:format(TAG), 1, true))
		assert(text:find(L.ACCORD_TEAM_HIDE, 1, true), "and its Hide")
		w.Run(A.REVEAL + 1)
		eq(#w.Fired("ACCORD_TEAM_CHANGED"), fired + 2, "redrawn when they hide by themselves")
		assert(not Page():find("1234", 1, true), "hidden again")
		eq(A.RevealTeam(), true); eq(A.RevealTeam(), true)
		assert(not Page():find("1234", 1, true), "Hide")
		-- The King's screen: no part of any tag, no Show; his eye changes nothing for tags.
		w.kingScreen = true
		for _, shown in ipairs({ false, true }) do
			ns.SetCouncilNamesShown(shown)
			local all = Page()
			assert(not all:find("1234", 1, true) and not all:find("7777", 1, true), "a tag on the King's screen")
			assert(not all:find("Tester#", 1, true) and not all:find("Bob", 1, true), "no part of a tag, a short one included: " .. all)
			assert(all:find(L.ACCORD_TEAM_HIDDEN:format(1), 1, true) and all:find(L.ACCORD_TEAM_HIDDEN:format(2), 1, true), all)
			assert(all:find(L.ACCORD_TEAM_PROFILE:format(L.ACCORD_TAG_HIDDEN_STREAM), 1, true), all)
			assert(not all:find(L.ACCORD_TEAM_SHOW, 1, true), "no Show on his screen")
			eq(all:find("Second Alt", 1, true) ~= nil, shown, "names masked until his eye")
		end
		eq(A.RevealTeam(), false, "his screen never reveals")
		ns.SetCouncilNamesShown(false)
		w.kingScreen = false
		-- The author's role preview: hidden.
		ns.ViewAs = { Available = function() return true end, Role = function() return "member" end }
		eq(A.TeamShown(), false); eq(#A.TeamLines(), 0)
	end, { accepted = true, team = true })
end)

test("accord: never a BattleTag in the log, the errors, the bug report or /oly status", function()
	H.WithUI(function() Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		local log, errors = #ns.db.log, #ns.db.errors
		A.random = function(lo) return lo end
		A.Show("login"); A.Accept(); A.Check()
		A.AskTeam()
		A.HandleTag("WHISPER", MEMBER, BT())
		A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")
		w.Run(A.DELAY_MAX)
		eq(#w.whispers, 1)
		local seen = {}
		for i = log + 1, #ns.db.log do seen[#seen + 1] = ns.db.log[i] end
		for i = errors + 1, #ns.db.errors do seen[#seen + 1] = tostring(ns.db.errors[i]) end
		assert(#seen > 0, "the flows logged")
		seen[#seen + 1] = ns.BuildBugReport()
		seen[#seen + 1] = ns.StatusText()
		seen[#seen + 1] = A.StatusLine()
		local all = table.concat(seen, "\n")
		assert(all:find("accord: v1 accepted", 1, true), "the status says it")
		assert(not all:find("1234", 1, true) and not all:find("Tester#", 1, true), "a tag written out")
		assert(A.StatusLine():find("team: 1 characters, 1 BattleTags", 1, true), A.StatusLine())
	end, { team = true }) end)
end)

-- (Changed on purpose, 1.2.5.1's review: the owner asked for a letter "não muito grande, em tópicos
-- bonitinho, fácil de ler", "com negrito, quando necessário". Its 20 long bullets became short
-- one-sentence ones (fewer words in all, each bounded below), the key ones in bold; and on the
-- King's screen no part of the tag shows: a short name cut to four letters was the whole name.)
test("accord: the letter: Olympus's own bronze window over parchment, the Accord's name in the quest title font, every topic and its short bullets, the key ones bold, the version and its date; the tag masked (Show reveals it a moment), and on the King's screen no part of it, with no Show", function()
	H.WithUI(function()
		Scene(function(w, A)
			local f = A.Show("slash")
			eq(f.windowLook, "metal", "the bronze metal (no portrait, no logo)")
			eq(f.TitleText:GetText(), L.TITLE)
			eq(f.paper.texture, "Interface\\QuestFrame\\QuestBG", "the parchment"); eq(f.paper.texCoord, ("0 %s 0 %s"):format(296 / 512, 331 / 512))
			eq(f.title:GetText(), L.ACCORD_NAME); eq(f.title.font, "GameFontNormalLarge", "(QuestTitleFont where the client has it)")
			eq(f.sub:GetText(), L.ACCORD_SUBTITLE:format(1))
			local words = {}
			for _, p in ipairs(f.parts) do words[#words + 1] = p.fs:GetText() end
			local body = table.concat(words, "\n")
			assert(body:find(L.ACCORD_OPENING, 1, true))
			local n = 0
			for _, t in ipairs(A.TOPICS) do
				assert(body:find(L["ACCORD_T" .. t[1] .. "_HEAD"], 1, true), t[1])
				for i = 1, t[2] do n = n + 1; assert(body:find(L["ACCORD_T" .. t[1] .. "_" .. i], 1, true), t[1] .. "." .. i) end
			end
			local want = 0
			for _, t in ipairs(A.TOPICS) do want = want + t[2] end
			eq(n, want)
			eq(#f.parts, 1 + #A.TOPICS + 2 * n, "a dot beside each bullet")
			-- Short: one sentence a bullet, the whole letter well under the first draft's 571 words.
			local total = select(2, L.ACCORD_OPENING:gsub("%S+", ""))
			for _, t in ipairs(A.TOPICS) do
				for i = 1, t[2] do
					local text = L["ACCORD_T" .. t[1] .. "_" .. i]
					local count = select(2, text:gsub("%S+", ""))
					total = total + count
					assert(count <= 22, ("bullet %d.%d is %d words"):format(t[1], i, count))
					assert(not text:find("|c", 1, true), "no colour codes in a bullet: bold is the font string's")
				end
			end
			assert(total <= 360, "the letter is " .. total .. " words")
			-- Bold where it matters: who gets the BattleTag (the moderation team in game, the
			-- Companion's census staff), that no other player sees it, and Blizzard's rules first, a
			-- deep red ink and doubled strokes (the dot too); the other bullets in the plain ink.
			-- (Changed on purpose, 2026-10-19: the owner's "sair para o Companion só" became a bullet
			-- of its own, T5_3, in bold with the in-game promise it qualifies; the 360-word bound
			-- stays, the letter trimmed elsewhere to fit.)
			local bold = {}
			for _, p in ipairs(f.parts) do
				if p.kind == "bullet" and p.bold then bold[#bold + 1] = p.fs:GetText() end
				if p.kind == "bullet" and not p.bold then eq(p.fs.textColor[1], 0.18, "plain ink") end
			end
			eq(#bold, 4)
			for _, key in ipairs({ "ACCORD_T2_1", "ACCORD_T5_2", "ACCORD_T5_3", "ACCORD_T5_4" }) do
				local found = false
				for _, text in ipairs(bold) do if text == L[key] then found = true end end
				assert(found, key .. " in bold")
			end
			for _, p in ipairs(f.parts) do if p.bold then eq(p.fs.textColor[1], 0.36, "bold ink") end end
			assert(f.bodyChild:GetHeight() > 300, "laid out")
			eq(f.footer:GetText(), L.ACCORD_FOOTER:format(1, L.ACCORD_DATE))
			-- The tag: its digits hidden; Show for REVEAL seconds; Hide.
			eq(f.tag:GetText(), "Tester#****")
			f.reveal:Click()
			eq(f.tag:GetText(), TAG); eq(f.reveal:GetText(), L.ACCORD_TAG_HIDE)
			w.mono = w.mono + A.REVEAL + 1
			A.Refresh(false)
			eq(f.tag:GetText(), "Tester#****", "hidden again by itself")
			f.reveal:Click(); f.reveal:Click()
			eq(f.tag:GetText(), "Tester#****", "Hide")
			f:Hide()
			-- The King's own character, before he accepted (his King's screen not yet his): no part of
			-- the tag, no Show.
			w.king = true
			f = A.Show("login")
			eq(f.tag:GetText(), "****#****"); eq(f.reveal:IsShown(), false)
			eq(f.tagNote:GetText(), L.ACCORD_TAG_HIDDEN_STREAM)
			f.reveal:Click()
			eq(f.tag:GetText(), "****#****")
			-- Accepted, from /oly accord: the date, and Close alone.
			eq(A.Accept(), true)
			w.king = false
			f = A.Show("slash")
			eq(f.close:IsShown(), true); eq(f.accept:IsShown(), false); eq(f.notNow:IsShown(), false)
			assert(f.footer:GetText():find(L.ACCORD_ACCEPTED_ON:format(date("%Y-%m-%d", ns.db.accord.at)), 1, true))
			f.close:Click()
			eq(f:IsShown(), false)
		end)
	end)
end)

test("accord: /oly accord shows the letter, accepted or not; /oly privacy shows the Accord first while it waits; the Olympus window opens on the Accord's page and shows the letter", function()
	H.WithUI(function()
		Scene(function(w, A)
			SlashCmdList.OLYMPUS("accord")
			assert(A.Frame() and A.Frame():IsShown())
			A.Frame():Hide()
			SlashCmdList.OLYMPUS("privacy")
			assert(A.Frame():IsShown(), "the Accord first"); eq(ns.Consent.Frame() == nil or not ns.Consent.Frame():IsShown(), true)
			A.Frame().notNow:Click()
			local UI = H.LoadUI()
			UI.Toggle()
			local main = OlympusFrame
			eq(main:IsShown(), true)
			eq(UI.PageId(), "accord")
			eq(main.total:GetText(), L.ACCORD_NAME)
			assert(A.Frame():IsShown(), "the window's open asks, after Not now too")
			local found
			for _, r in ipairs(main.views[main.tab] and main.views[main.tab].rows or {}) do
				if r:IsShown() and r.line and tostring(r.line.text or ""):find(L.ACCORD_LOCKED_OPEN, 1, true) then found = r.line end
			end
			assert(found and found.onClick, "the letter again from the page")
			eq(main.buttons[1]:GetText(), L.ACCORD_READ)
			A.Frame().accept:Click()
			eq(ns.IsMember(), true)
			UI.Refresh()
			eq(UI.PageId() ~= "accord", true, "its tabs")
			SlashCmdList.OLYMPUS("accord")
			assert(A.Frame():IsShown(), "accepted: shown again"); eq(A.Frame().close:IsShown(), true)
			A.Frame():Hide()
			main:Hide()
		end)
	end)
end)

test("accord: a client updated without a restart (Accord.lua not loaded yet): /oly accord says to restart, Olympus stays off, the window's page says so", function()
	H.WithUI(function()
		Scene(function(w, A)
			local stub = setmetatable({ missing = true, Show = function() ns.Print(L.RESTART_NEEDED) end,
				Slash = function() ns.Print(L.RESTART_NEEDED) end }, { __index = function() return function() end end })
			ns.Accord = stub
			local ok, err = pcall(function()
				SlashCmdList.OLYMPUS("accord")
				assert(w.Said(L.RESTART_NEEDED))
				eq(ns.IsMember(), false)
				local UI = H.LoadUI()
				UI.Toggle()
				local main = OlympusFrame
				eq(UI.PageId(), "accord")
				local found = false
				for _, r in ipairs(main.views[main.tab].rows or {}) do
					if r:IsShown() and r.line and r.line.text == L.RESTART_NEEDED then found = true end
				end
				eq(found, true, "the page says to restart")
				main:Hide()
			end)
			ns.Accord = A
			if not ok then error(err, 0) end
		end)
	end)
end)

test("accord: its words in English and pt-BR, the same format codes; the name in one key; the letter's text holds the rules the code keeps", function()
	local function LoadedL(locale)
		local lns = {}
		local savedLocale = GetLocale
		GetLocale = function() return locale end
		local ok, err = pcall(function()
			assert(loadfile(ROOT .. "Olympus/Locales.lua"))("Olympus", lns)
			assert(loadfile(ROOT .. "Olympus/Locales/AccordText.lua"))("Olympus", lns)
		end)
		GetLocale = savedLocale
		if not ok then error(err, 0) end
		return lns.L
	end
	local en, pt = LoadedL("enUS"), LoadedL("ptBR")
	local keys = { "ACCORD_NAME", "ACCORD_LOCKED_TITLE", "ACCORD_LOCKED_HINT", "ACCORD_LOCKED_OPEN", "ACCORD_READ", "HELP_ACCORD" }
	local f = assert(io.open(ROOT .. "Olympus/Locales/AccordText.lua", "rb"))
	local src = f:read("*a")
	f:close()
	local seen = {}
	for k in src:gmatch("\nL%.(ACCORD_[%w_]+) = ") do if not seen[k] then seen[k] = true; keys[#keys + 1] = k end end
	assert(#keys > 60, "the keys: " .. #keys)
	-- (Words that read the same in both: the BattleTags' heading, a row's shape.)
	local SAME = { ACCORD_TEAM_NAV = true, ACCORD_TEAM_TITLE = true, ACCORD_TEAM_ROW = true, ACCORD_TEAM_PROFILE = true }
	local function Codes(s) local out = {} for c in s:gmatch("%%%a") do out[#out + 1] = c end return table.concat(out) end
	for _, k in ipairs(keys) do
		assert(type(en[k]) == "string" and en[k] ~= "" and en[k] ~= k, k .. ": English")
		assert(type(pt[k]) == "string" and pt[k] ~= "" and (SAME[k] or pt[k] ~= en[k]), k .. ": pt-BR")
		eq(Codes(pt[k]), Codes(en[k]), k .. ": format codes")
	end
	eq(en.ACCORD_NAME, "The Olympus Accord"); eq(pt.ACCORD_NAME, "O Acordo do Olympus")
	assert(en.ACCORD_SUBTITLE:find("Terms of use", 1, true) and en.ACCORD_OPENING:find("terms of use", 1, true), "it says what it is")
	assert(pt.ACCORD_SUBTITLE:find("Termos de uso", 1, true))
	-- The rules it states are the code's: the ladder, the 30 days, English only, no stakes, 180 days.
	assert(en.ACCORD_T4_2:find("1 hour, 24 hours and 7 days", 1, true) and en.ACCORD_T4_2:find("30 days", 1, true))
	eq(ns.Accord.KEEP, 180 * 86400); assert(en.ACCORD_T5_2:find("180 days", 1, true))
	-- (2026-10-19) Where the BattleTag goes: the moderation team in game, and with the Companion
	-- app the online census, staff only (BridgeSections.lua's self section), in both languages.
	assert(en.ACCORD_T5_2:find("In game, only the moderation team", 1, true) and pt.ACCORD_T5_2:find("No jogo, só a equipe de moderação", 1, true))
	for _, must in ipairs({ "Olympus Companion app", "online census", "staff only", "security and control" }) do
		assert(en.ACCORD_T5_3:find(must, 1, true), "ACCORD_T5_3: " .. must)
	end
	for _, must in ipairs({ "Olympus Companion", "censo online", "staff", "segurança e controle" }) do
		assert(pt.ACCORD_T5_3:find(must, 1, true), "pt-BR ACCORD_T5_3: " .. must)
	end
	assert(en.ACCORD_TAG_TO:find("staff", 1, true) and pt.ACCORD_TAG_TO:find("staff", 1, true), "the band's note says staff too")
	-- The privacy page that opens right after I accept (Consent.lua) says the same: the moderation
	-- team alone in game, as with the Companion (the letter's T5_3) the online census gets it too.
	assert(en.CONSENT_INTRO:find("And in game, your BattleTag goes privately to the moderation team alone", 1, true), "the privacy page: in game")
	assert(pt.CONSENT_INTRO:find("E no jogo a sua BattleTag vai em privado apenas para a equipe de moderação", 1, true), "pt-BR privacy page: no jogo")
	-- Each topic's bullets are the letter's (Accord.TOPICS), in both languages: none past its count.
	for _, t in ipairs(ns.Accord.TOPICS) do
		for _, lang in ipairs({ en, pt }) do
			assert(type(rawget(lang, "ACCORD_T" .. t[1] .. "_" .. t[2])) == "string", "topic " .. t[1] .. ": its last bullet")
			eq(rawget(lang, "ACCORD_T" .. t[1] .. "_" .. (t[2] + 1)), nil, "topic " .. t[1] .. ": a bullet the letter never shows")
		end
	end
	local enKeys, ptKeys = {}, {}
	local ptAt = src:find("\nif GetLocale and GetLocale() == \"ptBR\" then", 1, true)
	assert(ptAt, "the pt-BR block")
	for k in src:sub(1, ptAt):gmatch("\nL%.(ACCORD_[%w_]+) = ") do enKeys[#enKeys + 1] = k end
	for k in src:sub(ptAt):gmatch("\n\tL%.(ACCORD_[%w_]+) = ") do ptKeys[#ptKeys + 1] = k end
	eq(table.concat(ptKeys, " "), table.concat(enKeys, " "), "the pt-BR block has every English key, in order")
	assert(en.ACCORD_T3_2:find("English", 1, true))
	local watch = assert(io.open(ROOT .. "Olympus/Watch.lua", "rb")):read("*a")
	assert(watch:find("Watch.TIMEOUTS = { 0, 60 * 60, 24 * 60 * 60, 7 * 24 * 60 * 60 }", 1, true), "the ladder the letter states")
	assert(watch:find("Watch.WARNING_KEEP = 30 * 86400", 1, true))
	assert(watch:find("Olympus's chats are in English only", 1, true))
	-- /oly help names it.
	local lines, savedPrint = {}, print
	print = function(s) lines[#lines + 1] = tostring(s) end
	SlashCmdList.OLYMPUS("help")
	print = savedPrint
	assert(table.concat(lines, "\n"):find(ns.L.HELP_ACCORD, 1, true), "in /oly help")
end)

-- 1.2.5.1's review: the fixes after the Accord's first build, each against the real Accord.lua.

test("accord: a team member who left before the answer went: the server's not-found line drops what waits for him and I accept no longer tells him; the line our own whisper causes stays out of the chat a moment (mouse and keyboard)", function()
	Scene(function(w, A)
		local savedErr = rawget(_G, "ERR_CHAT_PLAYER_NOT_FOUND_S")
		ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
		local ok, err = pcall(function()
			A.random = function(lo, hi) return hi end
			eq(A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1"), true)
			assert(w.events.CHAT_MSG_SYSTEM, "the server's lines read once an answer waits")
			local line = ERR_CHAT_PLAYER_NOT_FOUND_S:format(ns.TellName(COUNCILLOR))
			eq(A.NotFound(ERR_CHAT_PLAYER_NOT_FOUND_S:format("Somebody Else")), false, "another name")
			eq(A.NotFound("Some other system line"), false)
			-- He logged off before his answer's delay ran out: the server says so (another addon's
			-- whisper, or ours to him a moment ago), and nothing goes to him.
			w.events.CHAT_MSG_SYSTEM[1](line)
			w.Run(A.DELAY_MAX)
			eq(#w.whispers, 0, "nothing to a name the server says is not online")
			-- I accept (asked again): he is not told either.
			ns.db.accord.v = 0
			eq(A.Accept(), true)
			w.Run(A.DELAY_MAX)
			eq(#w.whispers, 0, "not on accepting either")
			-- Back, he asks again: answered; the not-found line our whisper may cause stays out of the
			-- chat QUIET seconds (he may leave between the delay and the send), anyone else's shows.
			A.random = function(lo) return lo end
			eq(A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1"), true)
			w.Run(A.DELAY_MIN)
			eq(#w.whispers, 1)
			eq(A.QuietLine(nil, "CHAT_MSG_SYSTEM", line), true, "kept out of the chat")
			eq(A.QuietLine(nil, "CHAT_MSG_SYSTEM", ERR_CHAT_PLAYER_NOT_FOUND_S:format("Somebody Else")), false, "anyone else's shows")
			eq(A.QuietLine(nil, "CHAT_MSG_SYSTEM", "Some other system line"), false)
			w.mono = w.mono + A.QUIET + 1
			eq(A.QuietLine(nil, "CHAT_MSG_SYSTEM", line), false, "and later, as ever")
			assert(A.StatusLine():find("gone 1", 1, true), A.StatusLine())
		end)
		ERR_CHAT_PLAYER_NOT_FOUND_S = savedErr
		if not ok then error(err, 0) end
	end, { accepted = true })
end)

test("accord: a team client's ask is kept by the server's clock: after a /reload the answers to it are still taken, until TAKE_WINDOW", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		eq(A.AskTeam(), true)
		w.Run(60)
		A.Reset() -- (a /reload: this session's state gone, the saved data kept)
		eq(A.HandleTag("WHISPER", MEMBER, BT()), true, "an answer to the ask before the reload")
		w.Run(A.TAKE_WINDOW)
		eq(select(2, A.HandleTag("WHISPER", "Late Comer-Realm", BT(nil, nil, "Late#1"))), "unasked")
	end, { accepted = true, team = true })
end)

test("accord: a team member's own BattleTag never goes down the team: the King's client answers no councillor (the author, yes), a councillor's answers the council, an ordinary player's any team member; the game's send checks it again", function()
	local W = ns.Workshop
	local savedAuthor = W.IsAuthorName
	local ok, err = pcall(function()
		W.IsAuthorName = function(name) return ns.FullName(name) == "Author Person-Realm" end
		Scene(function(w, A)
			A.random = function(lo) return lo end
			w.king = true
			eq(select(2, A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1")), "level", "the King's own tag: not to a councillor")
			w.Run(A.DELAY_MAX)
			eq(#w.whispers, 0)
			eq(A.HandleAsk("CHANNEL", "Author Person-Realm", "BQ~1"), true, "to the author")
			w.Run(A.DELAY_MAX)
			eq(#w.whispers, 1); eq(w.whispers[1].to, "Author Person-Realm")
			-- An answer that waited from before he was the King (a test of the permit): no send.
			w.king = false
			eq(A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1"), true)
			w.king = true
			w.Run(A.DELAY_MAX)
			eq(#w.whispers, 1, "checked again at the send")
			w.king = false
			assert(A.StatusLine():find("below 1", 1, true), A.StatusLine())
		end, { accepted = true })
		Scene(function(w, A)
			A.random = function(lo) return lo end
			eq(A.HandleAsk("CHANNEL", COUNCILLOR, "BQ~1"), true, "a councillor's own: to a councillor")
			w.Run(A.DELAY_MAX)
			eq(#w.whispers, 1)
		end, { accepted = true, team = true })
	end)
	W.IsAuthorName = savedAuthor
	if not ok then error(err, 0) end
end)

test("accord: a client off the moderation team drops its BattleTags: at once on its own sanction or a lost seat, else after TEAM_GRACE off the team (an alt played a while, a namer's list lapsed)", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		local function Kept()
			A.AskTeam()
			eq(A.HandleTag("WHISPER", MEMBER, BT()), true)
			return ns.rdb.battletags ~= nil and A.Count() == 1
		end
		A.OnLogin()
		local tick = false
		for _, t in ipairs(w.tickers) do if t.where == "olympus accord guard" and t.f == A.Guard then tick = true end end
		eq(tick, true, "checked every GUARD_EVERY")
		assert(Kept())
		eq(A.Guard(), false, "on the team: kept")
		-- An alt of the account, off the team: kept within TEAM_GRACE, dropped after it.
		ns.me = "Tester Alt-Realm"
		eq(A.TeamMember(), false)
		eq(A.Guard(), false)
		w.now = w.now + A.TEAM_GRACE - 60
		eq(A.Guard(), false, "within the grace")
		w.now = w.now + 120
		eq(A.Guard(), true); eq(ns.rdb.battletags, nil, "dropped after it")
		ns.me = "Tester-Realm"
		-- The seat lost (the signed council list no longer names him): at once.
		assert(Kept())
		ns.rdb.council.names.tester = nil
		eq(A.TeamMember(), false)
		eq(A.Guard(), true); eq(ns.rdb.battletags, nil, "a lost seat: at once")
		ns.rdb.council.names.tester = "Tester"
		-- His own sanction barring his powers (a timeout, a hold, net-off): at once.
		assert(Kept())
		local WCt = ns.WatchChat
		local barred = WCt.Barred
		WCt.Barred = function(what, name) if name == nil then return { kind = "timeout" } end return barred(what, name) end
		eq(A.Guard(), true); eq(ns.rdb.battletags, nil, "a sanction: at once")
		WCt.Barred = barred
		eq(#w.Fired("ACCORD_TEAM_CHANGED") > 0, true)
		assert(A.StatusLine():find("wiped 3", 1, true), A.StatusLine())
	end, { accepted = true, team = true })
end)

test("accord: accepted after the login's own asks ran (the letter shows 30 seconds in): the guild's newer realm key is asked for then (K5 over GUILD), as at login", function()
	H.WithUI(function() Scene(function(w, A)
		A.OnLogin()
		w.Run(A.LOGIN_WAIT + 5)
		assert(A.Frame() and A.Frame():IsShown(), "the letter")
		eq(#w.sends, 0, "nothing while it waits")
		A.Frame().accept:Click()
		eq(ns.IsMember(), true)
		local k5 = false
		for _, m in ipairs(w.sends) do if m.dist == "GUILD" and m.msg:match("^K5~") then k5 = true end end
		eq(k5, true, "the key epoch ask")
	end) end)
end)

test("accord: on any character of the King's game account, once his own was seen there, the letter shows no part of the BattleTag and no Show; another account's alt as before", function()
	H.WithUI(function() Scene(function(w, A)
		w.king = true
		A.Check() -- (a loading screen on his own character)
		eq(ns.db.kingAccount, true)
		w.king = false
		ns.me = "Kings Alt-Realm"
		eq(A.Stream(), true)
		local f = A.Show("login")
		eq(f.tag:GetText(), "****#****"); eq(f.reveal:IsShown(), false)
		eq(f.tagNote:GetText(), L.ACCORD_TAG_HIDDEN_STREAM)
		f:Hide()
		ns.db.kingAccount = nil
		f = A.Show("login")
		eq(f.tag:GetText(), "Tester#****"); eq(f.reveal:IsShown(), true)
		f:Hide()
	end) end)
end)

test("accord: in an Olympus guild before the Accord, a members-only refusal says it waits for the Accord (/oly accord), never that he is no member; elsewhere as ever", function()
	Scene(function(w, A)
		eq(ns.InOlympusGuild(), true); eq(ns.IsMember(), false)
		local ok, why = ns.Channels.Send("A", "hello")
		eq(ok, false); eq(why, "member")
		assert(w.Said(L.ACCORD_DECLINED), "the Accord named")
		assert(not w.Said(L.MEMBERS_ONLY))
		eq(ns.MembersOnlyText(), L.ACCORD_DECLINED)
		GetGuildInfo = function() return "Some Other Guild" end
		eq(ns.MembersOnlyText(), L.MEMBERS_ONLY, "outside Olympus")
	end)
end)

test("accord: /oly accord forget <name> on a team client drops that player's BattleTag, every character sharing it; elsewhere nothing is kept to drop", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		A.AskTeam()
		A.HandleTag("WHISPER", MEMBER, BT())
		A.HandleTag("WHISPER", "Second Alt-Realm", BT())
		A.HandleTag("WHISPER", "Brisk Lantern-Realm", BT(nil, nil, "Lantern#7777"))
		eq(A.Count(), 3)
		SlashCmdList.OLYMPUS("accord forget " .. MEMBER)
		eq(A.Count(), 1, "both characters of that tag")
		assert(ns.rdb.battletags.rows[ns.Fold("Brisk Lantern-Realm")], "the other player's kept")
		assert(w.Said(L.ACCORD_FORGOT:format(2)))
		eq(A.Slash("forget Nobody Here"), false)
		assert(w.Said(L.ACCORD_FORGET_NONE:format("Nobody Here")))
		ns.rdb.council.names.tester = nil
		eq(A.Slash("forget Brisk Lantern-Realm"), false)
		assert(w.Said(L.ACCORD_FORGET_TEAM))
		ns.rdb.council.names.tester = "Tester"
	end, { accepted = true, team = true })
end)

test("accord: the BattleTag's band grows with a two-line note under its label, and the words end above it (Battle.net down)", function()
	H.WithUI(function() Scene(function(w, A)
		w.bn.up = false
		local f = A.Show("login")
		local p = f.tagNote.points[1]
		eq(p[1], "TOPLEFT"); eq(p[2], f.tagLabel); eq(p[3], "BOTTOMLEFT", "the note under the label, never over it")
		-- (The harness measures no font: about 6 pixels a letter and 15 a line, Accord's own fallback.)
		local noteH = 15 * math.ceil(#f.tagNote:GetText() / math.floor(f.tagNote:GetWidth() / 6))
		assert(noteH >= 30, "a note of two lines here")
		assert(f.bandH >= 5 + 15 + 3 + noteH + 5, ("the band holds both: %d"):format(f.bandH))
		eq(f.band:Anchor("BOTTOMLEFT")[5], f.bandY)
		eq(f.body:Anchor("BOTTOMRIGHT")[5], f.bandY + f.bandH + 4, "the words end above the band")
		assert(f.bandY >= 62 + 15 + 10, "the band above the footer")
		w.bn.up = true
		A.Refresh(true)
		eq(f.bandH, 44, "one line: the band as drawn")
		f:Hide()
	end) end)
end)

test("accord: a BattleTag kept, dropped or shown redraws The Watch while it shows", function()
	H.WithUI(function() Scene(function(w, A)
		local uns, listeners = setmetatable({}, { __index = ns }), {}
		uns.On = function(name, f) listeners[name] = listeners[name] or {}; table.insert(listeners[name], f) end
		assert(loadfile(ROOT .. "Olympus/UI.lua"))("Olympus", uns)
		ns.UI = uns.UI
		local UI = uns.UI
		UI.Toggle()
		local main = OlympusFrame
		local calls = 0
		UI.RefreshSoon = function() calls = calls + 1 end
		assert(listeners.ACCORD_TEAM_CHANGED, "UI.lua listens")
		local tab = main.tab
		main.tab = "watch"
		for _, f in ipairs(listeners.ACCORD_TEAM_CHANGED) do f() end
		eq(calls, 1, "The Watch redrawn")
		main.tab = "census"
		for _, f in ipairs(listeners.ACCORD_TEAM_CHANGED) do f() end
		eq(calls, 1, "another tab: nothing")
		main.tab = tab
		main:Hide()
	end, { accepted = true }) end)
end)

test("accord: the saved fingerprint keeps one byte: for a known name dozens of four-digit numbers fit it; a test build's two bytes are cut to one at login, not asked again", function()
	Scene(function(w, A)
		local fp, fits = A.Fp(TAG), 0
		for n = 1000, 9999 do if A.Fp("Tester#" .. n) == fp then fits = fits + 1 end end
		assert(fits >= 10, "only " .. fits .. " four-digit numbers fit: the digits come back from the file")
		local h = ns.Sign.SHA256("OlympusAccord\0" .. ns.Fold(TAG))
		ns.db.accord.fp = ("%02x%02x"):format(h:byte(1), h:byte(2))
		A.OnLogin()
		eq(ns.db.accord.fp, fp, "its first byte kept")
		A.Check()
		eq(ns.IsMember(), true, "not asked again")
	end, { accepted = true })
end)

-- The Companion's "self" section (Olympus/BridgeSections.lua; the owner, 2026-10-19: the BattleTag
-- goes to the Companion's online census, staff only, "para a gente poder saber quem é quem"): the
-- player's own character and tag, once the Accord that says so is accepted. The real registry
-- (Olympus/Bridge.lua) copies it; the sidecar's own tests are in tests/run.lua.
local function Strings(v, out, depth)
	out = out or {}
	depth = depth or 0
	if type(v) == "string" or type(v) == "number" then out[#out + 1] = tostring(v)
	elseif type(v) == "table" and depth < 8 then
		for k, x in pairs(v) do
			out[#out + 1] = tostring(k)
			Strings(x, out, depth + 1)
		end
	end
	return out
end

local function WithServerTime(t, fn)
	local saved = rawget(_G, "GetServerTime")
	GetServerTime = t and function() return t end or nil
	local ok, err = pcall(fn)
	GetServerTime = saved
	if not ok then error(err, 0) end
end

test("accord: the Companion's self section: nothing before the Olympus Accord is accepted, for an older version or while the tag can't be read; after it, this character, his own BattleTag, the Accord's version and the server's time, a fresh copy within the bridge's limits", function()
	H.WithUI(function() Scene(function(w, A)
		local B = OlympusBridge
		local listed
		for _, s in ipairs(B.Sections()) do if s.name == "self" then listed = s.version end end
		eq(listed, 1, "registered as self, version 1")
		WithServerTime(1800000777, function()
			eq(ns.AccordAccepted(), false)
			eq(B.GetSection("self"), nil, "not accepted: nothing")
			ns.db.accord = { v = ns.ACCORD_VERSION - 1, yes = true, at = w.now - 100, fp = A.Fp(TAG), told = {} }
			eq(B.GetSection("self"), nil, "an older version accepted: nothing")
			ns.db.accord = nil
			eq(A.Accept(), true)
			local got = assert(B.GetSection("self"), "accepted: the section")
			eq(got.name, "self"); eq(got.version, 1)
			local d = got.data
			eq(d.character, ns.me); eq(d.character, "Tester-Realm")
			eq(d.battleTag, TAG, "his own, as his game gives it")
			eq(d.accord, ns.ACCORD_VERSION); eq(d.accord, 1)
			eq(d.at, 1800000777, "the server's clock, not this computer's")
			for k, v in pairs(d) do
				assert(({ character = true, battleTag = true, accord = true, at = true })[k], "field " .. tostring(k))
				assert(type(v) ~= "table", "flat: " .. k)
				if type(v) == "string" then assert(#v <= B.SECTION_LIMITS.string and not v:find("[|%c]"), k) end
			end
			d.battleTag = "Changed#1"
			eq(B.GetSection("self").data.battleTag, TAG, "every call a fresh copy")
			-- Read again each time: Battle.net down, a tag of another shape, a secret value: nothing.
			w.bn.up = false
			eq(B.GetSection("self"), nil, "Battle.net down: nothing")
			w.bn.up = true
			w.bn.tag = "No Digits Here"
			eq(B.GetSection("self"), nil, "not Name#digits: nothing")
			w.bn.tag = TAG
			issecretvalue = function(v) return v == TAG end
			eq(B.GetSection("self"), nil, "a secret value: never read")
			issecretvalue = nil
			eq(B.GetSection("self").data.battleTag, TAG)
		end)
		-- A client without the server's clock: this computer's.
		WithServerTime(nil, function() eq(B.GetSection("self").data.at, w.now) end)
		-- Asked again (another tag on the account): nothing until accepted again.
		w.bn.tag = "Other Name#4321"
		A.Check()
		eq(ns.AccordAccepted(), false)
		eq(B.GetSection("self"), nil, "the account asked again: nothing")
	end) end)
end)

test("accord: the Companion's self section never carries another player's BattleTag: a moderation team client's kept tags stay out of every section, a kept row under his own name included; nothing printed or logged, the King's screen too", function()
	Scene(function(w, A)
		C_ChatInfo = { SendAddonMessageLogged = function() end }
		local B = OlympusBridge
		A.AskTeam()
		eq(A.HandleTag("WHISPER", MEMBER, BT(nil, nil, "Other Player#5678")), true)
		eq(A.HandleTag("WHISPER", "Brisk Lantern-Realm", BT(nil, nil, "Lantern#7777")), true)
		-- A row under this very character's name (another addon's answer claiming it): the
		-- section reads his own game, never the team's store.
		ns.rdb.battletags.rows[ns.Fold(ns.me)] = { name = ns.me, tag = "Spoofed#9999", guild = "Olympus II", first = w.now, last = w.now }
		eq(A.Count(), 3)
		-- (What is logged meanwhile, as ns.Log is called: the saved log is a ring that stops growing.)
		local printed, logged, realLog = #w.printed, {}, ns.Log
		ns.Log = function(...)
			logged[#logged + 1] = table.concat(Strings({ ... }), " ")
			return realLog(...)
		end
		local ok, err = pcall(function()
			local self = assert(B.GetSection("self"))
			eq(self.data.battleTag, TAG)
			eq(self.data.character, ns.me)
			for _, s in ipairs(B.Sections()) do
				local got = B.GetSection(s.name)
				local all = table.concat(Strings(got and got.data), "\n")
				for _, other in ipairs({ "5678", "7777", "9999", "Other Player#", "Lantern#", "Spoofed#" }) do
					assert(not all:find(other, 1, true), s.name .. " carries another player's tag: " .. other)
				end
				if s.name ~= "self" then assert(not all:find(TAG, 1, true), s.name .. " carries the player's tag") end
			end
			-- The King's screen: a file on his own computer, not a screen; exported, never printed.
			w.kingScreen = true
			eq(B.GetSection("self").data.battleTag, TAG, "file-only: kept on his account")
			w.kingScreen = false
		end)
		ns.Log = realLog
		if not ok then error(err, 0) end
		eq(#w.printed, printed, "nothing printed")
		for _, line in ipairs(logged) do assert(not line:find("1234", 1, true) and not line:find("Tester#", 1, true), "a tag logged: " .. line) end
	end, { accepted = true, team = true })
end)

test("accord: the private Companion sidecar saves the self section at logout once the Accord is accepted, never before, and the docs say where it goes", function()
	Scene(function(w, A)
		local saved = { db = rawget(_G, "OlympusCompanionDB") }
		local before = #EVENT_SCRIPTS
		local ok, err = pcall(function()
			OlympusCompanionDB = nil
			assert(loadfile(ROOT .. "OlympusCompanionBridge/Checkpoint.lua"))("OlympusCompanionBridge", {})
			local OnEvent = assert(EVENT_SCRIPTS[before + 1], "the sidecar's event frame")
			OnEvent(nil, "ADDON_LOADED", "OlympusCompanionBridge")
			OnEvent(nil, "PLAYER_LOGOUT")
			eq((OlympusCompanionDB.sections or {}).self, nil, "before the Accord: no self section")
			eq(A.Accept(), true)
			OnEvent(nil, "PLAYER_LOGOUT")
			local s = assert(OlympusCompanionDB.sections and OlympusCompanionDB.sections.self, "after it: saved")
			eq(s.version, 1); eq(s.data.battleTag, TAG); eq(s.data.character, ns.me); eq(s.data.accord, 1)
		end)
		for i = #EVENT_SCRIPTS, before + 1, -1 do EVENT_SCRIPTS[i] = nil end
		OlympusCompanionDB = saved.db
		if not ok then error(err, 0) end
		-- The README's privacy table and the sidecar's README name it, as the code does it.
		local function Read(path)
			local f = assert(io.open(ROOT .. path, "rb"))
			local text = f:read("*a")
			f:close()
			return text
		end
		local row
		for line in Read("README.md"):gmatch("[^\n]+") do
			if line:sub(1, 2) == "| " and line:find("`self` section", 1, true) then row = line end
		end
		assert(row, "README: the self section's privacy row")
		for _, must in ipairs({ "Olympus Accord", "Olympus Companion", "online census", "staff", "never another player's BattleTag", "`OlympusBridge`" }) do
			assert(row:find(must, 1, true), "README's self row: " .. must)
		end
		local sidecar = Read("OlympusCompanionBridge/README.md"):gsub("%s+", " ")
		for _, must in ipairs({ "`self`", "character", "battleTag", "accord", "never another player's" }) do
			assert(sidecar:find(must, 1, true), "the sidecar's README: " .. must)
		end
	end)
end)

-- A sanction follows the BattleTag (TagFollow.lua). A small world of clients, each with the real
-- Watch.lua, Channels.lua, ChatRooms.lua, Moderation.lua, Accord.lua, WatchChat.lua, ChatStrikes.lua
-- and TagFollow.lua loaded into a namespace of its own (as tests/watch-chat.lua builds its world),
-- talks through a stand-in transport: the server stamps the sender, GUILD reaches the sender's
-- guild, CHANNEL everyone, a whisper its one player, a queued message's permit runs when it
-- "leaves". Battle.net is stubbed per client (BNGetInfo gives that client's own BattleTag), which
-- proves nothing about a game client: the in-game checks are in docs/BETA-TESTING.md.
-- Every name and BattleTag here is invented. Every test name starts with "accord: tag follow:", so
--   luajit tests/run.lua "tag follow"
-- runs them alone (and "accord" with the Accord's own).
local ns, test, eq, extra = ...
extra = extra or {}
local ROOT = (debug.getinfo(1, "S").source:sub(2):match("^(.*)tests[/\\]tag%-follow%.lua$")) or "./"
local L = ns.L

local TAG, TAG2, OTHER = "Lantern#1234", "Lantern#1235", "Ember#5678"
-- The game account of TAG's follow key (Accord.AccountKey), and its codes: SHA-256 of
-- "olympus-tag-2|" .. the folded tag .. "|" .. the key, 16 hex digits (shasum's answers).
local KEY = "5eed00000000a001"
local CODE, CODE2 = "204fd53eb90ad60f", "807e08f5ca538598"
local X, Y = "Olympus II", "Olympus of Ash"
local AAT = 1799990000 -- (one game account's Accord accept time: its characters share it)

local function Fold(s) return ns.Fold(tostring(s or "")) end
-- Each game account's follow key: TAG's (and TAG2's, the same account renamed) is KEY; any other
-- BattleTag stands for an account of its own, with a key of its own.
local function KeyFor(tag)
	if tag == nil then return nil end
	local f = Fold(tag)
	if f == Fold(TAG) or f == Fold(TAG2) then return KEY end
	local h = ns.Sign.SHA256("tests: another account|" .. f)
	local out = {}
	for i = 1, 8 do out[i] = ("%02x"):format(h:byte(i)) end
	return table.concat(out)
end

local GLOBALS = { "GetGuildInfo", "IsInGuild", "UnitIsPlayer", "C_ChatInfo", "GetTime", "GetChannelName", "DEFAULT_CHAT_FRAME", "IsCombatLog",
	"issecretvalue", "UnitClass", "C_FriendList", "BNGetInfo", "BNConnected", "BNFeaturesEnabledAndConnected", "InCombatLockdown", "IsInInstance",
	"SLASH_OLYMPUSALL1", "SLASH_OLYMPUSCAPTAINS1", "SLASH_OLYMPUSLORDS1" }

local function Full(name)
	name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if name == "" or name:find("-", 1, true) then return name end
	return name .. "-Realm"
end

-- ChatWindow's own reply codec, loaded once into a namespace of its own (the chat warnings read a
-- reply's words apart from its quote).
local replyCodec
local function ReplyCodec()
	if replyCodec then return replyCodec end
	local cns = setmetatable({}, { __index = ns })
	cns.On, cns.RegisterEvent = function() end, function() end
	assert(loadfile(ROOT .. "Olympus/GamepadRegistry.lua"))("Olympus", cns)
	assert(loadfile(ROOT .. "Olympus/Gamepad.lua"))("Olympus", cns)
	assert(loadfile(ROOT .. "Olympus/ChatWindow.lua"))("Olympus", cns)
	replyCodec = { DecodeReply = cns.ChatWindow.DecodeReply, EncodeReply = cns.ChatWindow.EncodeReply }
	return replyCodec
end

local function Frame()
	local f = { lines = {}, calls = 0 }
	function f:AddMessage(text) self.lines[#self.lines + 1] = { message = text } end
	function f:TransformMessages() self.calls = self.calls + 1 end
	return f
end

-- Every text a list of lines shows: its text, right side and tooltip.
local function Shown(lines)
	local out = {}
	for _, l in ipairs(lines or {}) do
		out[#out + 1] = tostring(l.text or "") .. " | " .. tostring(l.right or "")
		if type(l.tooltip) == "function" then
			local tt = { AddLine = function(_, text) out[#out + 1] = tostring(text) end }
			l.tooltip(tt)
		end
	end
	return table.concat(out, "\n")
end

-- Everything a table holds, as text (keys and values, nested).
local function Dump(t, seen, out)
	seen, out = seen or {}, out or {}
	if type(t) ~= "table" then out[#out + 1] = tostring(t) return out end
	if seen[t] then return out end
	seen[t] = true
	for k, v in pairs(t) do
		out[#out + 1] = tostring(k)
		if type(v) == "table" then Dump(v, seen, out) else out[#out + 1] = tostring(v) end
	end
	return out
end

local function World(fn)
	local saved, dialogs, slash = {}, {}, {}
	for _, k in ipairs(GLOBALS) do saved[k] = rawget(_G, k) end
	for k, v in pairs(StaticPopupDialogs) do dialogs[k] = v end
	for k, v in pairs(SlashCmdList) do slash[k] = v end
	local w = { epoch = 1800000000, clients = {}, wire = {}, sent = {}, guilds = {}, council = {}, stewards = {}, hands = {},
		links = {}, census = {}, namers = {} }
	local ok, err = pcall(function()
		GetGuildInfo = function(unit)
			local c = w.current
			if c and (unit == nil or unit == "player") and c.guild then return c.guild, "Rank", c.rank end
		end
		IsInGuild = function() return w.current ~= nil and w.current.guild ~= nil end
		UnitIsPlayer = function() return false end
		C_ChatInfo = { SendAddonMessageLogged = function() return true end }
		GetTime = function() return w.epoch end
		IsCombatLog = function() return false end
		issecretvalue = nil
		UnitClass = function() return "Warrior", "WARRIOR" end
		C_FriendList = nil
		InCombatLockdown, IsInInstance = function() return false end, function() return false end
		-- Battle.net: each client's own BattleTag (nil: it can't be read).
		BNConnected, BNFeaturesEnabledAndConnected = nil, nil
		BNGetInfo = function()
			local c = w.current
			if not c or not c.tag then return nil end
			return 1, c.tag, nil, "", false, false, false
		end

		function w.As(cl, f, ...)
			local was, frame = w.current, DEFAULT_CHAT_FRAME
			w.current, DEFAULT_CHAT_FRAME = cl, cl.frame
			local res = { pcall(f, ...) }
			w.current, DEFAULT_CHAT_FRAME = was, frame
			if not res[1] then error(res[2], 0) end
			return unpack(res, 2, table.maxn(res))
		end

		function w.SetRank(name, guild, rank)
			name = Full(name)
			for g, list in pairs(w.guilds) do if g ~= guild then list[name] = nil end end
			if guild then
				w.guilds[guild] = w.guilds[guild] or {}
				w.guilds[guild][name] = rank
			end
		end

		-- opts: tag (its BattleTag), aat (its game account's Accord accept time), key (its game
		-- account's follow key: KeyFor(tag) by default, so one BattleTag is one account), kingAccount, standIn
		-- (TagFollow.lua not loaded: Core.lua's stand-in, as a client updated without a restart),
		-- realDialogs (the harness's ns.ShowDialog: Olympus's own window under the gamepad UI).
		function w.Client(short, guild, rank, opts)
			opts = opts or {}
			local name = Full(short)
			local cl = { name = name, short = short, guild = guild, rank = rank, tag = opts.tag, handlers = {}, events = {}, listeners = {},
				dialogs = {}, prints = {}, logs = {}, timers = {}, frame = Frame(), online = true }
			w.SetRank(name, guild, rank)
			local c = setmetatable({}, { __index = ns })
			cl.ns = c
			c.L = ns.L
			c.me, c.realm, c.group, c.faction = name, "Realm", "RealmGroup", "Alliance"
			c.CAPTAIN_RANK = 1
			c.db = { addonChat = true, chatRooms = true, chatWarned = { A = true, C = true, L = true }, blocked = {}, log = {},
				kingAccount = opts.kingAccount or nil,
				accord = { v = ns.ACCORD_VERSION, yes = true, at = opts.aat or AAT, told = {}, key = opts.key or KeyFor(opts.tag) } }
			c.rdb = { guilds = {} }
			c.Now = function() return w.epoch end
			c.Data = { ServerTime = function() return w.epoch end, ClaimGuild = function() return true end,
				AuthorizedRank = function(n, g)
					local list = g and w.guilds[g]
					local r = list and list[c.FullName(n)]
					return r, r ~= nil and (g == cl.guild and "roster" or (w.census[g] and "census" or "signed")) or nil
				end, FRESH = 900 }
			c.FullName = function(n, realm)
				n = tostring(n or ""):gsub("^%s+", ""):gsub("%s+$", "")
				if n == "" or n:find("-", 1, true) then return n end
				return n .. "-" .. (realm or "Realm")
			end
			c.DisplayName = function(n) return (tostring(n or ""):gsub("%-Realm$", "")) end
			c.IsMember = function() return cl.guild ~= nil and ns.IsFederation(cl.guild) end
			c.CouncilMasked = function() return cl.masked == true end
			c.KingsScreen = function() return cl.kingScreen == true end
			c.GamepadUI = function() return w.gamepad == true end
			c.IsKingCharacter = function(n) return w.king ~= nil and type(n) == "string" and Fold(c.FullName(n)) == Fold(w.king) end
			c.KingCharacter = function() return w.king and (w.king:gsub("%-.*$", "")) or nil end
			c.IsHighCouncillor = function(n) return type(n) == "string" and w.council[Fold(c.FullName(n))] == true end
			c.IsSteward = function(n) return type(n) == "string" and w.stewards[Fold(c.FullName(n))] == true end
			c.Workshop = { IsAuthorName = function() return false end }
			-- (The real King.lua's name checks: Moderation.CharName reads them.)
			c.King = { CleanName = ns.King.CleanName, CleanGuild = ns.King.CleanGuild,
				IsHandName = function(n) return type(n) == "string" and w.hands[Fold(c.FullName(n))] == true end,
				IsStewardName = function(n) return c.IsSteward(n) end, IsKing = function() return c.IsKingCharacter(name) end,
				IsSteward = function() return false end, IsHand = function() return false end, Preview = function() return false end }
			c.Alts = { Linked = function(n) return w.links[Fold(c.FullName(n))] or {} end }
			c.ChatWindow = ReplyCodec()
			local roster = { byName = {}, complete = true, generation = 1, group = c.group, faction = c.faction, online = {} }
			setmetatable(roster, { __index = function(_, k)
				if k == "guild" then return cl.guild end
				if k == "snapshotAt" then return w.epoch end
			end })
			roster.RankOf = function(n) local list = cl.guild and w.guilds[cl.guild] return list and list[c.FullName(n)] or nil end
			roster.MyRank = function() return cl.rank end
			roster.IsOfficer = function() return cl.rank ~= nil and cl.rank <= 1 end
			roster.ClassCode = ns.Roster.ClassCode
			c.Roster = roster
			c.Fire = function(event, ...)
				cl.events[#cl.events + 1] = { event, ... }
				for _, f in ipairs(cl.listeners[event] or {}) do f(...) end
			end
			c.On = function(event, f) cl.listeners[event] = cl.listeners[event] or {}; table.insert(cl.listeners[event], f) end
			c.RegisterEvent = function() end
			c.Print = function(text) cl.prints[#cl.prints + 1] = tostring(text) end
			c.Log = function(fmt, ...)
				local okFmt, s = pcall(string.format, fmt, ...)
				cl.logs[#cl.logs + 1] = okFmt and s or tostring(fmt)
			end
			c.CaptureError = function(where, e) error(tostring(where) .. ": " .. tostring(e), 0) end
			c.PlayAlert = function() end
			c.SafeCall = function(_, f, ...) return f(...) end
			c.After = function(seconds, _, f) cl.timers[#cl.timers + 1] = { at = w.epoch + (tonumber(seconds) or 0), fn = f } end
			c.Every = function() end
			if not opts.realDialogs then
				c.ShowDialog = function(which, a, b, data) cl.dialogs[#cl.dialogs + 1] = { which = which, a = a, b = b, data = data } return true end
			end
			c.UI = { TABS = {}, AddTab = function() return true end, SelectTab = function() end, ShowCopy = function() end }
			c.PlayerMenu = { Add = function() return true end }
			c.Court = { HomeLines = function() return {} end, Holding = function() return false end }
			c.Filter = { Hides = function() return false end, Hit = function() return nil end, SharedOn = function() return true end, WordsOf = ns.Filter.WordsOf }
			c.Authority = { Enforced = function() return false end }
			c.TabardsV2 = { SurfaceVisible = function() return false end }
			c.ViewAs = { Available = function() return false end }
			c.Consent = { Register = function() end, Ask = function() end }
			c.Comm = {
				Handle = function(kind, f) cl.handlers[kind] = f end,
				DeliveredLogged = function() return w.deliveredLogged ~= false end,
				QueueRoom = function() return 60 end, ChannelReady = function() return true end, ChatRoom = function() return 10 end,
				ChannelName = function() return "OlympusChannel" end, Audience = function() return "everyone" end,
				IsPublic = function() return true end, DropLine = function() end, PeerCount = function() return 1 end,
				CancelQueued = function() return 0 end,
				Send = function(dist, msg, key, plain, logged, done, options)
					w.wire[#w.wire + 1] = { from = cl, dist = dist, msg = msg, key = key, logged = logged, done = done, options = options }
					return true
				end,
				SendChat = function(msg, done, line, guard)
					w.wire[#w.wire + 1] = { from = cl, dist = "CHANNEL", msg = msg, logged = true, done = done, guard = guard }
					return true
				end,
				Whisper = function(target, msg, key, plain, logged, done, options)
					w.wire[#w.wire + 1] = { from = cl, dist = "WHISPER", target = target, msg = msg, key = key, logged = logged, done = done, options = options }
					return true
				end,
			}
			w.clients[#w.clients + 1] = cl
			w.As(cl, function()
				for _, file in ipairs({ "Watch", "Channels", "ChatRooms", "Moderation", "Accord", "WatchChat", "ChatStrikes" }) do
					assert(loadfile(ROOT .. "Olympus/" .. file .. ".lua"))("Olympus", c)
				end
				if not opts.standIn then assert(loadfile(ROOT .. "Olympus/TagFollow.lua"))("Olympus", c) end
			end)
			cl.W, cl.C, cl.WC, cl.M, cl.A, cl.TF = c.Watch, c.Channels, c.WatchChat, c.Moderation, c.Accord, c.TagFollow
			c.Watch.ResetForTests()
			c.WatchChat.ResetForTests()
			c.ChatStrikes.ResetForTests()
			c.Moderation.Reset()
			c.Accord.Reset()
			c.Accord.random = function(lo) return lo end
			c.WatchChat.random = function() return 0 end
			c.Moderation.random = function() return 0 end
			if not opts.standIn then
				c.TagFollow.ResetForTests()
				c.TagFollow.random = function() return 0 end
			end
			return cl
		end

		local function Deliver(r, job)
			local kind = job.msg:match("^(%w%w)~")
			local h = kind and r.handlers[kind]
			if not h or not r.online then return end
			w.deliveredLogged = job.logged == true
			w.As(r, h, job.dist, job.from.name, job.msg)
			w.deliveredLogged = nil
		end

		-- Everything queued leaves, in order (what it queues on the way too), and timers due run.
		function w.Run()
			local guard = 0
			while true do
				for _, cl in ipairs(w.clients) do
					for i = #cl.timers, 1, -1 do
						local t = cl.timers[i]
						if t and t.at <= w.epoch then table.remove(cl.timers, i); w.As(cl, t.fn) end
					end
				end
				local job = table.remove(w.wire, 1)
				if not job then return end
				guard = guard + 1
				assert(guard < 4000, "the world's wire never empties")
				local allowed = true
				if job.guard then allowed = w.As(job.from, job.guard) and true or false end
				if allowed and job.options and job.options.permit then
					allowed = w.As(job.from, job.options.permit, job.options.owner, job.options.key, job.dist, job.target, job.msg) == true
				end
				if job.done then w.As(job.from, job.done, allowed, allowed and nil or "guard") end
				if allowed then
					w.sent[#w.sent + 1] = { from = job.from.name, dist = job.dist, msg = job.msg, target = job.target, logged = job.logged == true }
					for _, r in ipairs(w.clients) do
						if r ~= job.from and ((job.dist == "CHANNEL")
							or (job.dist == "GUILD" and r.guild ~= nil and r.guild == job.from.guild)
							or (job.dist == "WHISPER" and Fold(r.name) == Fold(Full(job.target)))) then
							Deliver(r, job)
						end
					end
				end
			end
		end

		-- A word written by hand, as the server stamps `from` on it, to TagFollow.Handle: its answer.
		function w.TF(to, dist, from, msg, logged)
			w.deliveredLogged = logged ~= false
			local res = { w.As(to, to.TF.Handle, dist, from, msg) }
			w.deliveredLogged = nil
			return unpack(res)
		end
		-- Any other message by hand, to the handler of its type.
		function w.Inject(dist, from, to, msg, logged)
			w.deliveredLogged = logged ~= false
			local kind = msg:match("^(%w%w)~")
			local h = kind == "MD" and to.WC.Handle or kind == "M1" and to.C.Receive or kind == "BT" and to.A.HandleTag or to.handlers[kind or ""]
			local res = { w.As(to, h, dist, from, msg) }
			w.deliveredLogged = nil
			return unpack(res)
		end

		-- A team member's client asked for BattleTags (its ask on the channel not delivered: each
		-- test says whose answer comes, with the player's own Accord.SendTag).
		function w.Asked(team)
			local n = #w.wire
			assert(w.As(team, team.A.AskTeam), "the ask")
			for i = #w.wire, n + 1, -1 do if w.wire[i].msg == "BQ~1" then table.remove(w.wire, i) end end
		end
		-- The player's own client sends its BattleTag to `team` (its real answer, a logged whisper).
		function w.TagTo(team, cl)
			w.Asked(team)
			assert(w.As(cl, cl.A.SendTag, team.name), "BT from " .. cl.short)
			w.Run()
			assert(w.As(team, team.A.TagOf, cl.name), "kept on " .. team.short)
		end
		-- A BattleTag answer of a character that has no client in the scene (key: its game account's
		-- follow key, KeyFor(tag) by default; a modified addon sends any tag with its own key).
		function w.TagOf(team, name, tag, aat, guild, key)
			w.Asked(team)
			local ok, why = w.Inject("WHISPER", Full(name), team, ("BT~1~1~%d~%s~%s~%s"):format(aat or AAT, guild or X, tag, key or KeyFor(tag)), true)
			assert(ok, "BT of " .. name .. ": " .. tostring(why))
		end

		-- A namer names Olympus moderators (their list on the channel); every later Pass repeats it.
		function w.Mods(namer, ...)
			for _, m in ipairs({ ... }) do assert(w.As(namer, namer.WC.SetMod, m.name, true)) end
			w.namers[#w.namers + 1] = namer
			w.epoch = w.epoch + 3
			w.Run()
		end
		-- Time goes on (the namers' lists repeated, as their clients do while on).
		function w.Pass(seconds)
			w.epoch = w.epoch + seconds
			for _, n in ipairs(w.namers) do w.As(n, n.WC.SendMods, true) end
			w.Run()
		end

		function w.Dialog(cl, which)
			for i = #cl.dialogs, 1, -1 do if cl.dialogs[i].which == which then return cl.dialogs[i] end end
		end
		function w.Printed(cl, needle)
			for _, p in ipairs(cl.prints) do if p:find(needle, 1, true) then return p end end
		end
		function w.Sent(prefix)
			local out = {}
			for _, s in ipairs(w.sent) do if s.msg:sub(1, #prefix) == prefix then out[#out + 1] = s end end
			return out
		end
		-- The words of this client's own follows store.
		function w.Kept(cl)
			local out = {}
			local s = cl.ns.rdb.tagFollow
			for key, F in pairs(s and s.f or {}) do out[#out + 1] = { key = key, F = F } end
			return out
		end
		-- A chat line of `name` as the channel carries it, for a client that ignores its own block.
		w.lineId = 100
		function w.Line(name, text)
			w.lineId = w.lineId + 1
			return ns.Codec.EncodeChat("A", X, w.lineId, "", text)
		end

		fn(w)
	end)
	for _, k in ipairs(GLOBALS) do _G[k] = saved[k] end
	for k in pairs(StaticPopupDialogs) do StaticPopupDialogs[k] = nil end
	for k, v in pairs(dialogs) do StaticPopupDialogs[k] = v end
	for k in pairs(SlashCmdList) do SlashCmdList[k] = nil end
	for k, v in pairs(slash) do SlashCmdList[k] = v end
	if not ok then error(err, 0) end
end

-- The usual scene: a High Councillor (Warden, guild X) on the moderation team; Sootfang (X), who
-- will be sanctioned, and Sootwing (Y), another character of his BattleTag that never sent his
-- BattleTag to anyone; Brightmoor (X), a bystander with another BattleTag.
local function Basic(w, opts)
	opts = opts or {}
	w.council[Fold("Warden-Realm")] = true
	local HC = w.Client("Warden", X, 3, { tag = "Warden#4242" })
	local S = w.Client("Sootfang", X, 3, { tag = TAG })
	local V = w.Client("Sootwing", Y, 3, { tag = TAG })
	local B = w.Client("Brightmoor", X, 3, { tag = OTHER })
	return HC, S, V, B
end

-- The pop-up a client last showed of this kind, and its text.
local function Popup(w, cl, which)
	local d = w.Dialog(cl, which)
	return d, d and tostring(d.a or "") or nil
end

---------------------------------------------------------------------------
-- The code
---------------------------------------------------------------------------

-- (Changed on purpose, the review: the code now takes the game account's follow key, which only
-- the moderation team receives, so it can no longer be found by guessing a BattleTag; the header's
-- line that said it could is gone, and this test asserts the opposite claim instead.)
test("accord: tag follow: the code: SHA-256 of the prefix, the folded BattleTag and the game account's follow key, 16 hex digits; the same for any case, another for other digits or another key; never without a BattleTag or a key; its header says only the team can tell whose it is", function()
	local savedStop = StaticPopupDialogs.OLYMPUS_TAGFOLLOW_STOP
	local tns = setmetatable({ On = function() end, Comm = { Handle = function() end } }, { __index = ns })
	assert(loadfile(ROOT .. "Olympus/TagFollow.lua"))("Olympus", tns)
	StaticPopupDialogs.OLYMPUS_TAGFOLLOW_STOP = savedStop
	local TF = tns.TagFollow
	-- (The known answers, from `printf 'olympus-tag-2|lantern#1234|5eed00000000a001' | shasum -a 256`.)
	eq(TF.Hash(TAG, KEY), CODE)
	eq(TF.Hash(TAG2, KEY), CODE2)
	eq(TF.Hash(TAG, "0000000000000002"), "387d653788508cac", "another account's key: another code")
	eq(TF.Hash("lantern#1234", KEY), CODE, "case folded"); eq(TF.Hash("LANTERN#1234", KEY), CODE)
	assert(TF.Hash(TAG, KEY) ~= TF.Hash(OTHER, KEY))
	eq(TF.Hash(TAG), nil, "never without a key"); eq(TF.Hash(TAG, "5EED00000000A001"), nil); eq(TF.Hash(TAG, KEY:sub(2)), nil)
	for _, bad in ipairs({ "Lantern", "Lantern#", "Lan~tern#12", "#1234", "Lantern#12a", "", string.rep("a", 70) .. "#1" }) do
		eq(TF.Hash(bad, KEY), nil, "no code for " .. bad)
	end
	eq(TF.IsCode(CODE), true); eq(TF.IsCode(CODE:upper()), false); eq(TF.IsCode(CODE:sub(2)), false)
	local f = assert(io.open(ROOT .. "Olympus/TagFollow.lua", "rb"))
	local src = f:read("*a")
	f:close()
	assert(src:find("nobody else can tell from a code whose BattleTag it is", 1, true), "the header says the key keeps it private")
	assert(not src:find("It is NOT secret", 1, true), "the old claim is gone")
end)

---------------------------------------------------------------------------
-- Net-off
---------------------------------------------------------------------------

test("accord: tag follow: a councillor's net-off word on a character follows his BattleTag: another character of it that never sent one is off on his own client (his chats, what he sends, his powers), told in Olympus's pop-up without the giver's name, the Decrees say so; a bystander untouched", function()
	World(function(w)
		local HC, S, V, B = Basic(w)
		w.TagTo(HC, S)
		eq(w.As(HC, HC.A.HashOf, S.name), CODE)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		local at = w.epoch
		w.Run()
		eq(#w.Sent("O1~c~1~"), 1, "the word by name")
		local tf = w.Sent("TF~")
		eq(#tf, 1, "and its follow")
		eq(tf[1].msg, ("TF~1~N~1~%d~%s~%s~%s"):format(at, CODE, S.name, HC.name))
		eq(tf[1].dist, "CHANNEL"); eq(tf[1].logged, true)
		assert(w.Printed(HC, L.ACCORD_FOLLOW_DONE:format(0)), "the giver told (no other character known)")
		-- Sootwing: off on his own client, through his BattleTag.
		local e, src, via = w.As(V, V.M.SelfOff)
		assert(e, "followed (this fails without TagFollow.lua)")
		eq(via, "tag"); eq(src, S.name); eq(e.name, S.name); eq(e.reason, "spam")
		eq(w.As(V, V.M.Blocks, "M1~A~a line"), true, "he sends none of what net-off holds")
		eq(w.As(V, V.M.Blocks, "TF~1~N~1~1~" .. CODE .. "~A-Realm~B-Realm"), true)
		assert(w.As(V, V.WC.Barred, "powers"), "his powers barred")
		eq(w.As(V, V.WC.Sanction).kind, "netoff")
		local okSend = w.As(V, V.C.Send, "A", "hello")
		eq(okSend, false, "his line refused")
		local d, text = Popup(w, V, "OLYMPUS_WATCHCHAT_DECISION")
		assert(d, "told in Olympus's pop-up")
		eq(text, L.ACCORD_FOLLOW_YOU_NETOFF:format("spam", V.M.When(e)))
		-- His own line in the Decrees (the list below it shows Sootfang's word, its giver included, to
		-- every member as before).
		local mine
		for _, l in ipairs(w.As(V, V.M.Lines)) do if tostring(l.text):find(L.ACCORD_FOLLOW_YOU_SHORT, 1, true) then mine = l end end
		assert(mine, "the Decrees say so: " .. Shown(w.As(V, V.M.Lines)))
		local decree = Shown({ mine })
		assert(decree:find(L.ACCORD_FOLLOW_YOU_NETOFF:format("spam", V.M.When(e)), 1, true), "its tooltip: " .. decree)
		for _, said in ipairs({ text, table.concat(V.prints, "\n"), decree }) do
			assert(not said:find("Warden", 1, true), "never who gave it: " .. said)
		end
		-- Once a session.
		local n = #V.dialogs
		w.As(V, V.TF.TellMine)
		eq(#V.dialogs, n, "told once")
		-- Sootfang himself: his own word, as before; Brightmoor (another BattleTag) untouched.
		local own, _, ownVia = w.As(S, S.M.SelfOff)
		assert(own); eq(ownVia, nil, "his own word")
		eq(w.As(B, B.M.SelfOff), nil); eq(w.As(B, B.M.Blocks, "M1~A~a line"), false); eq(w.As(B, B.WC.Barred, "powers"), nil)
		eq(#w.Kept(B), 0, "a bystander keeps none of it")
		-- The team's client holds no BattleTag of Sootwing: nothing hides him there.
		eq(w.As(HC, HC.M.Hides, V.name), nil)
		-- Once it holds it, the councillor's "on" word on Sootwing's own name frees him of the
		-- follow; Sootfang stays off.
		w.TagTo(HC, V)
		local _, _, teamVia = w.As(HC, HC.M.Hides, V.name)
		eq(teamVia, "tag", "now hidden on the team's client too")
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", V.name, false, ""), "an on word for one hidden only by the follow")
		w.Run()
		eq(w.As(V, V.M.SelfOff), nil, "freed")
		assert(w.Printed(V, L.ACCORD_FOLLOW_YOU_BACK), "and told")
		assert(w.As(S, S.M.SelfOff), "Sootfang still off")
		assert(w.As(B, B.M.Hides, S.name))
	end)
end)

-- (Regression: the first draft told any word not on his own name or a linked one as a follow's,
-- so a client that splits names, where the same name on another realm of the group is the same
-- player, Moderation.Character, read its own word as another character's, without who gave it.)
test("accord: tag follow: the same name on another realm of the group is still told as his own word, who gave it included, never as a follow's", function()
	World(function(w)
		local HC, _, V = Basic(w)
		V.ns.splitNames = true
		V.ns.GroupOf = function() return "Realm+Other" end
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", "Sootwing-Other", true, "spam"))
		w.Run()
		local e, on, via = w.As(V, V.M.SelfOff)
		assert(e, "the same name on the group's other realm hides him")
		eq(on, "Sootwing-Other"); eq(via, nil, "not a follow")
		eq(w.As(V, V.M.YouText, e), L.NETOFF_YOU:format("spam", "Warden", V.M.When(e)))
		local short
		for _, l in ipairs(w.As(V, V.M.Lines)) do if tostring(l.text):find(L.NETOFF_YOU_SHORT, 1, true) then short = l end end
		assert(short, "the Decrees' own line")
		assert(Shown({ short }):find("Warden", 1, true), "its tooltip names who gave it")
	end)
end)

---------------------------------------------------------------------------
-- Timeouts
---------------------------------------------------------------------------

test("accord: tag follow: a named moderator's timeout follows the BattleTag: the other character is timed out on his own client and told with the follow's lead; his appeal works and the council's lift frees him while the sanctioned one stays timed out", function()
	World(function(w)
		local HC, S, V, B = Basic(w)
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		w.Mods(HC, M)
		eq(w.As(V, V.WC.ActorLevel, M.name), V.WC.LEVEL.mod, "a moderator everywhere")
		w.TagTo(M, S)
		w.epoch = w.epoch + 5
		local okAct, scope = w.As(M, M.WC.Act, "T", S.name, { seconds = 3600, reason = "flooding" })
		eq(okAct, true); eq(scope, "O")
		w.Run()
		local tf = w.Sent("TF~1~T~1~")
		eq(#tf, 1, "the timeout follows")
		assert(tf[1].msg:find("~" .. CODE .. "~" .. S.name .. "~" .. M.name, 1, true), tf[1].msg)
		local e, via = w.As(V, V.WC.SelfTimeout)
		assert(e, "timed out through his BattleTag")
		eq(via, S.name); eq(e.name, S.name)
		local b, why = w.As(V, V.WC.RefuseSend)
		assert(b); eq(why, "timeout")
		local d, text = Popup(w, V, "OLYMPUS_WATCHCHAT_TIMED_OUT")
		assert(d, "the timed-out pop-up")
		eq(text:sub(1, #L.ACCORD_FOLLOW_YOU_LEAD), L.ACCORD_FOLLOW_YOU_LEAD, "its lead says it follows his BattleTag")
		assert(not text:find("Gloomwatch", 1, true), "never who gave it")
		-- His appeal (the record his client keeps of the followed timeout).
		local okAppeal, whyAppeal = w.As(V, V.WC.Appeal, d.data.by, d.data.seq, "not my character")
		eq(okAppeal, true, tostring(whyAppeal))
		w.Run()
		local key
		for k, a in pairs(HC.WC.Store().appeals) do if Fold(a.name) == Fold(V.name) then key = k end end
		assert(key, "the council has his appeal")
		w.epoch = w.epoch + 5
		eq(w.As(HC, HC.WC.Answer, key, "L", "not his"), true)
		w.Run()
		eq(w.As(V, V.WC.SelfTimeout), nil, "freed")
		assert(w.As(V, V.WC.TimeoutOf, S.name), "Sootfang still timed out on his client")
		assert(w.As(B, B.WC.TimeoutOf, S.name), "and everywhere")
		local _, decision = Popup(w, V, "OLYMPUS_WATCHCHAT_DECISION")
		eq(decision, L.WATCHCHAT_APPEAL_LIFTED_YOU:format(L.WATCHCHAT_ROLE_ANY, L.WATCHCHAT_REASON_PART:format("not his")), "told he is free")
		-- Still free once the council's lift is past its own short keep: it lasts until the timeout it freed him of ends.
		w.Pass(V.WC.REPEAT + 60)
		w.As(V, V.WC.Prune)
		eq(w.As(V, V.WC.SelfTimeout), nil, "still freed after the lift's own repeat window")
	end)
end)

---------------------------------------------------------------------------
-- The original's lift
---------------------------------------------------------------------------

test("accord: tag follow: the sanctioned character's own lift frees every character of his BattleTag at once, whoever gives it (a Steward off the team holds no BattleTag), with no stop of the follow; another moderator's lift and a timeout's end too", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.stewards[Fold("Highreeve-Realm")] = true
		local St = w.Client("Highreeve", X, 2, { tag = "Reeve#2222" })
		eq(w.As(St, St.A.TeamMember), false, "the Steward is not on the moderation team")
		w.TagTo(HC, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		assert(w.As(V, V.M.SelfOff), "followed")
		w.epoch = w.epoch + 5
		assert(w.As(St, St.M.Set, "c", S.name, false, ""), "the Steward shows him again")
		w.Run()
		eq(w.As(V, V.M.SelfOff), nil, "free at once")
		assert(w.Printed(V, L.ACCORD_FOLLOW_YOU_BACK), "and told")
		eq(#w.Sent("TF~1~N~0~"), 0, "no stop was needed")
		-- A timeout: another moderator's lift on the sanctioned one, then a timeout's end.
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		local M2 = w.Client("Dusktally", Y, 3, { tag = "Dusk#3333" })
		w.Mods(HC, M, M2)
		w.TagTo(M, S)
		w.epoch = w.epoch + 5
		assert(w.As(M, M.WC.Act, "T", S.name, { seconds = 3600, reason = "flooding" }))
		w.Run()
		assert(w.As(V, V.WC.SelfTimeout), "followed")
		w.epoch = w.epoch + 5
		local prints = #V.prints
		assert(w.As(M2, M2.WC.Lift, S.name, "done"))
		w.Run()
		eq(w.As(V, V.WC.SelfTimeout), nil, "another moderator's lift frees him")
		local back = false
		for i = prints + 1, #V.prints do if V.prints[i]:find(L.ACCORD_FOLLOW_YOU_BACK, 1, true) then back = true end end
		eq(back, true, "told")
		w.epoch = w.epoch + 5
		assert(w.As(M, M.WC.Act, "T", S.name, { seconds = 300, reason = "again" }))
		w.Run()
		assert(w.As(V, V.WC.SelfTimeout), "followed again (the follow points at his sanction, whichever it is)")
		w.Pass(301)
		eq(w.As(V, V.WC.SelfTimeout), nil, "its end frees him")
	end)
end)

---------------------------------------------------------------------------
-- Evidence and the derived by-name word
---------------------------------------------------------------------------

-- (Changed on purpose, the review: a line counts as evidence only once the follow reached him, its
-- word on the wire right after one of his hidden lines (here the giver's client sends it again for
-- his first line), so each evading character now chats once, then again EVADE_AFTER later; and the
-- giver's TF count includes that second send, so "never followed again" is checked by source.)
test("accord: tag follow: a character whose addon skips the follow and keeps chatting: his first hidden line makes the giver send the follow again; a line EVADE_AFTER after that gives exactly one by-name word; never one for an honest character; six an hour at most; taken back once the sanction ends", function()
	World(function(w)
		local HC, S, V = Basic(w)
		local V2 = w.Client("Sootclaw", Y, 3, { tag = TAG })
		V2.TF.Mine = function() return nil end -- (a modified client: it never matches its own BattleTag)
		w.TagTo(HC, S); w.TagTo(HC, V2); w.TagTo(HC, V)
		-- Five more characters of that account, with no client here (their addon sends lines anyway).
		local more = { "Sootkina", "Sootkinb", "Sootkinc", "Sootkind", "Sootkine", "Sootkinf" }
		for _, name in ipairs(more) do w.TagOf(HC, name, TAG) end
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		assert(w.Printed(HC, L.ACCORD_FOLLOW_DONE:format(8)), "eight other characters known")
		eq(w.As(V2, V2.M.SelfOff), nil, "the modified client does not apply it")
		-- His first line: hidden on the team's client, the follow sent again (he is online now),
		-- nothing by name.
		w.epoch = w.epoch + 2
		assert(w.As(V2, V2.C.Send, "A", "first line"))
		w.Run()
		local _, _, via = w.As(HC, HC.M.Hides, V2.name)
		eq(via, "tag", "hidden on the team's client")
		local function Derived()
			local out = {}
			for _, s in ipairs(w.Sent("O1~c~1~")) do if s.msg:find(HC.TF.DERIVED_REASON, 1, true) then out[#out + 1] = s end end
			return out
		end
		eq(#Derived(), 0, "not on his first line")
		eq(#w.Sent("TF~1~N~1~"), 2, "the follow sent again for his line")
		-- Still too early: EVADE_AFTER counts from that send.
		w.epoch = w.epoch + 60
		assert(w.As(V2, V2.C.Send, "A", "early line"))
		w.Run()
		eq(#Derived(), 0, "not before EVADE_AFTER")
		-- After it: one line gives exactly one word by name.
		w.epoch = w.epoch + HC.TF.EVADE_AFTER
		assert(w.As(V2, V2.C.Send, "A", "second line"))
		w.Run()
		local derived = Derived()
		eq(#derived, 1, "one by-name word")
		assert(derived[1].msg:find("~" .. V2.name .. "~" .. HC.name .. "~", 1, true), derived[1].msg)
		for _, t in ipairs(w.Sent("TF~")) do assert(not t.msg:find("~" .. V2.name .. "~", 1, true), "a derived word is never followed again: " .. t.msg) end
		assert(w.As(V2, V2.M.SelfOff), "now off by name on his own client")
		-- His client ignoring that too: the next line is hidden by name, no second word.
		w.Inject("CHANNEL", V2.name, HC, w.Line(V2.name, "third line"))
		eq(#Derived(), 1, "no second word")
		-- The honest character sends nothing, and gets no word.
		eq(w.As(V, V.C.Send, "A", "a line"), false)
		w.Run()
		for _, s in ipairs(Derived()) do assert(not s.msg:find(V.name, 1, true), "nothing for the honest one") end
		-- Six an hour at most from one client (each chats once, the follow goes again, each chats on).
		for _, name in ipairs(more) do w.Inject("CHANNEL", Full(name), HC, w.Line(name, "evading")) end
		w.Run()
		eq(#Derived(), 1, "nothing on their first lines")
		w.epoch = w.epoch + HC.TF.EVADE_AFTER + 1
		for _, name in ipairs(more) do w.Inject("CHANNEL", Full(name), HC, w.Line(name, "still evading")) end
		w.Run()
		eq(#Derived(), HC.TF.DERIVE_HOUR, "the seventh is refused by the hour's budget")
		local last = Full(more[#more])
		for _, s in ipairs(Derived()) do assert(not s.msg:find(last, 1, true), "the seventh") end
		-- Sootfang shown again: on the next round every word given so is taken back.
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, false, ""))
		w.Run()
		w.As(HC, HC.TF.Tick)
		w.Run()
		eq(w.As(V2, V2.M.SelfOff), nil, "his by-name word taken back")
		local on = 0
		for _, s in ipairs(w.Sent("O1~c~0~")) do if s.from == HC.name and not s.msg:find("~" .. S.name .. "~", 1, true) then on = on + 1 end end
		eq(on, HC.TF.DERIVE_HOUR, "each taken back")
		eq(next(HC.ns.rdb.tagFollow.derived), nil, "no record left")
	end)
end)

test("accord: tag follow: a team member's stop takes back the by-name word his client gave for evading the follow, on the next round", function()
	World(function(w)
		local HC, S = Basic(w)
		local V2 = w.Client("Sootclaw", Y, 3, { tag = TAG })
		V2.TF.Mine = function() return nil end
		w.TagTo(HC, S); w.TagTo(HC, V2)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		w.epoch = w.epoch + 5
		assert(w.As(V2, V2.C.Send, "A", "a line"))
		w.Run()
		w.epoch = w.epoch + HC.TF.EVADE_AFTER + 1
		assert(w.As(V2, V2.C.Send, "A", "another line"))
		w.Run()
		assert(w.As(V2, V2.M.SelfOff), "off by name")
		eq(w.As(HC, HC.TF.Stop, "N", S.name), true)
		w.Run()
		assert(w.Printed(HC, L.ACCORD_FOLLOW_STOPPED:format("Sootfang")))
		eq(#w.Sent("TF~1~N~0~"), 1, "the stop on the channel")
		w.As(HC, HC.TF.Tick)
		w.Run()
		eq(w.As(V2, V2.M.SelfOff), nil, "taken back")
		assert(w.As(S, S.M.SelfOff), "Sootfang's own word stays")
	end)
end)

test("accord: tag follow: /oly accord unfollow and follow on a team client; and the author's switch DERIVE_ON_MATCH, off by default, gives the by-name word on the match alone when on", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.TagTo(HC, S); w.TagTo(HC, V)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(HC.TF.DERIVE_ON_MATCH, false, "off as it ships")
		w.As(HC, HC.TF.Tick)
		w.Run()
		eq(#w.Sent("O1~c~1~"), 1, "off: nothing by name on a match alone")
		w.epoch = w.epoch + 5
		eq(w.As(HC, HC.A.Slash, "unfollow Sootfang"), true)
		w.Run()
		assert(w.Printed(HC, L.ACCORD_FOLLOW_STOPPED:format("Sootfang")))
		eq(w.As(V, V.M.SelfOff), nil, "unfollowed")
		w.As(HC, HC.A.Slash, "unfollow Sootfang")
		assert(w.Printed(HC, L.ACCORD_FOLLOW_NONE:format("Sootfang")), "nothing more to stop")
		w.As(HC, HC.A.Slash, "follow Brightmoor")
		assert(w.Printed(HC, L.ACCORD_FOLLOW_NOTHING:format("Brightmoor")), "no sanction of his own")
		w.epoch = w.epoch + 5
		eq(w.As(HC, HC.A.Slash, "follow Sootfang"), true, "followed again by hand, over the stop")
		w.Run()
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag")
		HC.TF.DERIVE_ON_MATCH = true
		w.As(HC, HC.TF.Tick)
		w.Run()
		local derived = 0
		for _, sent in ipairs(w.Sent("O1~c~1~")) do if sent.msg:find("~" .. V.name .. "~", 1, true) then derived = derived + 1 end end
		eq(derived, 1, "on: the honest character's word by name at once")
	end)
end)

---------------------------------------------------------------------------
-- Forged and misdirected words
---------------------------------------------------------------------------

test("accord: tag follow: a forged follow is refused and the other character stays free: from a random member, a Hand off the team, passed on, over GUILD or a whisper, unlogged, a malformed code, a sanctioned councillor, aimed at the King or by a councillor at a Steward", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", "Olympus", 0, { tag = "Crown#0001" })
		w.hands[Fold("Palmguard-Realm")] = true
		w.stewards[Fold("Highreeve-Realm")] = true
		w.council[Fold("Ironbrow-Realm")] = true
		local R = w.Client("Randall", X, 3, { tag = "Rand#5555" })
		local Hd = w.Client("Palmguard", X, 3, { tag = "Palm#6666" })
		local St = w.Client("Highreeve", X, 2, { tag = "Reeve#2222" })
		local BC = w.Client("Ironbrow", Y, 3, { tag = "Brow#7777" })
		-- Sootfang off by the King's word (every client holds it), so a wrongly taken follow would bite.
		assert(w.As(K, K.M.Set, "c", S.name, true, "spam"))
		w.Run()
		-- The King times the councillor out: he gives nothing while it lasts.
		assert(w.As(K, K.WC.Act, "T", BC.name, { seconds = 3600, reason = "abuse" }))
		w.Run()
		local function Word(kind, source, by, code) return ("TF~1~%s~1~%d~%s~%s~%s"):format(kind, w.epoch, code or CODE, source, by) end
		local cases = {
			{ "a random member", "CHANNEL", R.name, Word("N", S.name, R.name), true, "standing" },
			{ "a Hand off the team", "CHANNEL", Hd.name, Word("N", S.name, Hd.name), true, "standing" },
			{ "passed on for a councillor", "CHANNEL", R.name, Word("N", S.name, HC.name), true, "relay" },
			{ "over GUILD", "GUILD", HC.name, Word("N", S.name, HC.name), true, "lane" },
			{ "by whisper", "WHISPER", HC.name, Word("N", S.name, HC.name), true, "lane" },
			{ "unlogged", "CHANNEL", HC.name, Word("N", S.name, HC.name), false, "unlogged" },
			{ "a 15-digit code", "CHANNEL", HC.name, Word("N", S.name, HC.name, CODE:sub(2)), true, "shape" },
			{ "an uppercase code", "CHANNEL", HC.name, Word("N", S.name, HC.name, CODE:upper()), true, "shape" },
			{ "a code with #", "CHANNEL", HC.name, Word("N", S.name, HC.name, "afc28b0e#8b84eab"), true, "shape" },
			{ "a sanctioned councillor", "CHANNEL", BC.name, Word("N", S.name, BC.name), true, "standing" },
			{ "aimed at the King", "CHANNEL", HC.name, Word("N", K.name, HC.name), true, "source" },
			{ "a councillor at a Steward (net-off)", "CHANNEL", HC.name, Word("N", St.name, HC.name), true, "rank" },
			{ "a councillor at a Steward (timeout)", "CHANNEL", HC.name, Word("T", St.name, HC.name), true, "rank" },
		}
		for _, c in ipairs(cases) do
			local ok, why = w.TF(V, c[2], c[3], c[4], c[5])
			eq(ok, false, c[1]); eq(why, c[6], c[1])
			local _, _, via = w.As(V, V.M.SelfOff)
			eq(via, nil, "free after " .. c[1])
			eq(w.As(V, V.WC.SelfTimeout), nil, "free after " .. c[1])
		end
		eq(#w.Kept(V), 0, "nothing kept")
		-- The very same word from the councillor himself is taken (the matrix is not refusing everything).
		local ok = w.TF(V, "CHANNEL", HC.name, Word("N", S.name, HC.name), true)
		eq(ok, true)
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag")
	end)
end)

test("accord: tag follow: a guild's Watcher gives no follow; a guild timeout followed by a councillor reaches the other character in that guild alone", function()
	World(function(w)
		w.council[Fold("Warden-Realm")] = true
		local HC = w.Client("Warden", X, 3, { tag = "Warden#4242" })
		local A = w.Client("Watchoff", X, 1, { tag = "Watch#8888" }) -- (an officer: his guild's Watcher)
		local S = w.Client("Sootfang", X, 3, { tag = TAG })
		local V1 = w.Client("Sootwing", X, 3, { tag = TAG })
		local V2 = w.Client("Sootclaw", Y, 3, { tag = TAG })
		local Word = ("TF~1~T~1~%d~%s~%s~%s"):format(w.epoch, CODE, S.name, A.name)
		local ok, why = w.TF(V1, "CHANNEL", A.name, Word, true)
		eq(ok, false); eq(why, "standing", "a Watcher is not the moderation team")
		ok, why = w.TF(V1, "GUILD", A.name, Word, true)
		eq(ok, false); eq(why, "lane")
		w.TagTo(HC, S); w.TagTo(HC, V1); w.TagTo(HC, V2)
		w.epoch = w.epoch + 5
		local okAct, scope = w.As(A, A.WC.Act, "T", S.name, { seconds = 3600, reason = "spam" })
		eq(okAct, true); eq(scope, "G")
		w.Run()
		eq(#w.Sent("TF~"), 0, "the Watcher's own timeout follows nothing")
		local okGive, n = w.As(HC, HC.TF.Give, "T", S.name)
		eq(okGive, true, tostring(n)); eq(n, 2)
		w.Run()
		local e, via = w.As(V1, V1.WC.SelfTimeout)
		assert(e, "the other character in that guild is timed out")
		eq(via, S.name); eq(e.scope, "G")
		eq(w.As(V2, V2.WC.SelfTimeout), nil, "never in another guild")
		local _, onTeam = w.As(HC, HC.WC.TimeoutOf, V1.name)
		eq(onTeam, S.name, "the councillor's client (that guild) holds him timed out")
		local x, viaOther = w.As(HC, HC.WC.TimeoutOf, V2.name)
		eq(x, nil, "but not the character in another guild"); eq(viaOther, nil)
	end)
end)

---------------------------------------------------------------------------
-- Who a follow never reaches
---------------------------------------------------------------------------

test("accord: tag follow: never the King's game account, nor a councillor's own client; an account's remembered Steward protects its alts for two days and not after; a moderator's follow of the King's timeout never reaches a Hand", function()
	World(function(w)
		local HC, S = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", "Olympus", 0, { tag = "Crown#0001" })
		local KA = w.Client("Crownalt", X, 3, { tag = TAG, kingAccount = true })
		w.council[Fold("Ironbrow-Realm")] = true
		local C2 = w.Client("Ironbrow", Y, 3, { tag = TAG })
		local RS = w.Client("Reevealt", Y, 3, { tag = TAG })
		RS.ns.db.tagShield = { n = 2, t = 5, at = w.epoch }
		w.hands[Fold("Palmguard-Realm")] = true
		local Hd = w.Client("Palmguard", Y, 3, { tag = TAG })
		w.TagTo(HC, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		for _, cl in ipairs({ KA, C2, RS }) do
			eq(#w.Kept(cl), 1, "kept on " .. cl.short)
			local _, _, via = w.As(cl, cl.M.SelfOff)
			eq(via, nil, "never reached: " .. cl.short)
		end
		-- Two days on: the remembered rank no longer counts (the follow still stands: STALE is three).
		w.epoch = w.epoch + 2 * 86400 + 1
		local _, _, via = w.As(RS, RS.M.SelfOff)
		eq(via, "tag", "after TEAM_GRACE the alt is reached")
		_, _, via = w.As(KA, KA.M.SelfOff)
		eq(via, nil, "the King's account always shielded")
		-- The King's timeout, followed by a moderator: never a Hand.
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		w.Mods(HC, M)
		w.TagTo(M, S)
		w.epoch = w.epoch + 5
		assert(w.As(K, K.WC.Act, "T", S.name, { seconds = 3600, reason = "abuse" }))
		w.Run()
		local okGive = w.As(M, M.TF.Give, "T", S.name)
		eq(okGive, true)
		w.Run()
		eq(#w.Kept(Hd) >= 1, true, "the Hand's client kept the word")
		eq(w.As(Hd, Hd.WC.SelfTimeout), nil, "a Hand stands above a moderator's follow")
		assert(w.As(RS, RS.WC.SelfTimeout), "an ordinary alt is reached")
	end)
end)

---------------------------------------------------------------------------
-- The giver's checks
---------------------------------------------------------------------------

-- (Changed on purpose, the review: two game accounts of one BattleTag are now two codes, each
-- account's key in it. The sanctioned player's own account is followed by itself (no copied tag
-- can reach it, and a copy no longer stops it), and the other account waits for the click, as before.)
test("accord: tag follow: the giver follows only within his reach: a BattleTag shared with a Steward is not followed (told so); another game account of the same BattleTag (another code) waits for a click in The Watch, his own is followed", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.stewards[Fold("Highreeve-Realm")] = true
		local St = w.Client("Highreeve", Y, 2, { tag = TAG })
		w.TagTo(HC, S); w.TagTo(HC, St)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(#w.Sent("TF~"), 0, "no follow")
		assert(w.Printed(HC, L.ACCORD_FOLLOW_SKIPPED), "and he is told why")
		eq(w.As(V, V.M.SelfOff), nil)
	end)
	World(function(w)
		local HC, S, V = Basic(w)
		V.ns.db.accord.key = "0000000000000002" -- (another game account, or a copied BattleTag)
		w.TagTo(HC, S); w.TagTo(HC, V)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(#w.Sent("TF~1~N~1~"), 1, "his own account's code followed by itself")
		assert(w.Sent("TF~1~N~1~")[1].msg:find("~" .. CODE .. "~", 1, true))
		eq(w.As(V, V.M.SelfOff), nil, "the other account not by itself")
		assert(w.Printed(HC, L.ACCORD_FOLLOW_CONTESTED))
		local page = w.As(HC, HC.A.TeamLines)
		local click
		for _, l in ipairs(page) do if tostring(l.text):find(L.ACCORD_FOLLOW_CONTESTED, 1, true) then click = l end end
		assert(click and click.onClick, "the disputed line, with a click: " .. Shown(page))
		w.As(HC, click.onClick)
		w.Run()
		eq(#w.Sent("TF~1~N~1~"), 2, "the click follows it there")
		assert(w.Sent("TF~1~N~1~")[2].msg:find("~387d653788508cac~", 1, true), "on the other account's code")
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag")
	end)
end)

test("accord: tag follow: a BattleTag that arrives after the sanction is followed then; a changed BattleTag gets the follow on its new code", function()
	World(function(w)
		local HC, S = Basic(w)
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(#w.Sent("TF~"), 0, "no BattleTag known yet: nothing")
		eq(w.Printed(HC, L.ACCORD_FOLLOW_DONE:format(0)), nil, "nothing said")
		w.TagTo(HC, S)
		local tf = w.Sent("TF~1~N~1~")
		eq(#tf, 1, "followed once his BattleTag came")
		assert(tf[1].msg:find("~" .. CODE .. "~", 1, true))
		-- His BattleTag changes (a new name or digits on the same character).
		w.epoch = w.epoch + S.A.TAKE_GAP + 1
		S.tag = TAG2
		w.TagTo(HC, S)
		tf = w.Sent("TF~1~N~1~")
		eq(#tf, 2)
		assert(tf[2].msg:find("~" .. CODE2 .. "~", 1, true), "the follow on the new code: " .. tf[2].msg)
	end)
end)

---------------------------------------------------------------------------
-- Privacy
---------------------------------------------------------------------------

test("accord: tag follow: the plain BattleTag never leaves: only BT carries it; TF on the channel, logged; no tag or code in any log, nor on an ordinary client's disk; on the King's screen the Watch shows no tag and masks the names", function()
	World(function(w)
		local HC, S, V, B = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", "Olympus", 0, { tag = "Crown#0001" })
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		w.Mods(HC, M)
		w.TagTo(HC, S); w.TagTo(M, S); w.TagTo(K, S); w.TagTo(K, V)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		assert(w.As(M, M.WC.Act, "T", S.name, { seconds = 3600, reason = "flooding" }))
		w.Run()
		w.Pass(HC.TF.REPEAT + 1)
		w.As(HC, HC.TF.Tick); w.As(M, M.TF.Tick)
		w.Run()
		eq(#w.Sent("TF~"), 4, "two follows, each repeated once")
		for _, s in ipairs(w.sent) do
			if s.msg:sub(1, 3) ~= "BT~" then
				local low = s.msg:lower()
				assert(not low:find("lantern", 1, true) and not low:find("ember", 1, true) and not s.msg:find("#%d"), "a tag in " .. s.msg)
			end
			if s.msg:sub(1, 3) == "TF~" then eq(s.dist, "CHANNEL"); eq(s.logged, true) end
		end
		for _, cl in ipairs(w.clients) do
			local log = table.concat(cl.logs, "\n"):lower()
			assert(not log:find("lantern", 1, true) and not log:find(CODE, 1, true) and not log:find("#1234", 1, true), "a tag or code in " .. cl.short .. "'s log")
		end
		-- Sootwing's disk: his follows without a code, no tag or code anywhere.
		local kept = w.Kept(V)
		eq(#kept, 2)
		for _, k in ipairs(kept) do
			eq(k.F.hash, nil); eq(k.F.mine, true)
			assert(not k.key:find(CODE, 1, true), k.key)
		end
		local disk = table.concat(Dump(V.ns.db), "\n") .. table.concat(Dump(V.ns.rdb), "\n")
		assert(not disk:find(CODE, 1, true) and not disk:lower():find("lantern", 1, true), "a tag or code on an ordinary client's disk")
		-- The King's screen: the follow marked, no part of a tag, the names masked.
		K.masked = true
		local page = Shown(w.As(K, K.A.TeamLines)) .. "\n" .. Shown(w.As(K, K.A.ProfileLines, V.name))
		assert(page:find(L.ACCORD_FOLLOW_SAME, 1, true), "the mark: " .. page)
		assert(page:find(ns.MaskName("Sootfang"), 1, true), page)
		assert(not page:find("Sootfang", 1, true) and not page:find("Sootwing", 1, true), "names masked: " .. page)
		assert(not page:lower():find("lantern", 1, true) and not page:find("1234", 1, true), "no tag: " .. page)
		-- /oly status: counts alone.
		local status = w.As(HC, HC.A.StatusLine)
		assert(status:find("follows ", 1, true) and not status:find(CODE, 1, true) and not status:lower():find("lantern", 1, true), status)
		eq(#w.Kept(B), 0)
	end)
end)

---------------------------------------------------------------------------
-- Old clients
---------------------------------------------------------------------------

test("accord: tag follow: a client of before this release ignores TF without an error; one updated without a restart (the stand-in) still hides by name and never by a follow", function()
	if extra.FreshComm then
		local savedChannel, savedChat = GetChannelName, C_ChatInfo
		local ok, err = pcall(function()
			GetChannelName = function() return 5 end
			local old, Deliver = extra.FreshComm(true)
			old.Comm.JoinChannel()
			Deliver("CHANNEL", "Warden-Realm", ("TF~1~N~1~1800000000~%s~Sootfang-Realm~Warden-Realm"):format(CODE))
			local stats = old.Comm.Stats()
			eq(stats.recv, 1, "heard by the old transport")
			eq(stats.bad, 0, "an unknown type is not misparsed")
		end)
		GetChannelName, C_ChatInfo = savedChannel, savedChat
		if not ok then error(err, 0) end
	end
	World(function(w)
		local HC, S = Basic(w)
		local O = w.Client("Sootmark", Y, 3, { tag = TAG, standIn = true })
		eq(O.ns.TagFollow.missing, true, "Core.lua's stand-in")
		w.TagTo(HC, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(#w.Sent("TF~"), 1)
		assert(w.As(O, O.M.Hides, S.name), "hidden by name as before")
		eq(w.As(O, O.M.SelfOff), nil, "never by a follow")
		eq(w.As(O, O.WC.SelfTimeout), nil)
	end)
end)

---------------------------------------------------------------------------
-- Repeats, lapses, stops
---------------------------------------------------------------------------

test("accord: tag follow: its giver repeats it while the sanction stands and stops once lifted; another client lapses it 3 days unheard and 30 days after it was given; a stop blocks an equal automatic follow, never a higher manual one", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.TagTo(HC, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(#w.Sent("TF~"), 1)
		w.epoch = w.epoch + HC.TF.REPEAT - 10
		eq(w.As(HC, HC.TF.Repeat), 0, "not yet")
		w.epoch = w.epoch + 11
		eq(w.As(HC, HC.TF.Repeat), 1, "repeated")
		w.Run()
		eq(#w.Sent("TF~"), 2)
		eq(w.As(V, V.TF.Stats).same, 1, "a repeat to the other character's client")
		-- Lapses: unheard 3 days on another client.
		w.epoch = w.epoch + V.TF.STALE + 1
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, nil, "lapsed on another client")
		w.As(HC, HC.TF.Repeat)
		w.Run()
		_, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag", "its giver's repeat brings it back")
		-- Lifted: no more repeats.
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, false, ""))
		w.Run()
		local before = #w.Sent("TF~")
		w.epoch = w.epoch + HC.TF.REPEAT + 1
		eq(w.As(HC, HC.TF.Repeat), 0, "not repeated once lifted")
		eq(#w.Sent("TF~"), before)
	end)
	World(function(w)
		local HC, S, V = Basic(w)
		w.TagTo(HC, S)
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		local word = w.Sent("TF~")[1].msg
		-- 30 days after it was given: refused, and the kept one is no longer in force.
		w.epoch = w.epoch + HC.TF.KEEP + 1
		local ok, why = w.TF(V, "CHANNEL", HC.name, word, true)
		eq(ok, false); eq(why, "time")
		eq(#w.As(V, V.TF.Sources, V.name, "N"), 0, "lapsed")
	end)
	World(function(w)
		local HC, S, V = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", "Olympus", 0, { tag = "Crown#0001" })
		w.council[Fold("Ironbrow-Realm")] = true
		local C2 = w.Client("Ironbrow", Y, 3, { tag = "Brow#7777" })
		w.TagTo(HC, S); w.TagTo(C2, S); w.TagTo(K, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		w.epoch = w.epoch + 5
		eq(w.As(C2, C2.TF.Stop, "N", S.name), true, "another councillor stops it")
		w.Run()
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, nil, "the stop frees him")
		local ok, why = w.As(HC, HC.TF.Give, "N", S.name)
		eq(ok, false); eq(why, "stopped", "an automatic follow of the same weight is held off")
		w.epoch = w.epoch + 5
		ok = w.As(K, K.TF.Give, "N", S.name, { manual = true })
		eq(ok, true, "the King's own click follows it again")
		w.Run()
		_, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag")
	end)
end)

---------------------------------------------------------------------------
-- The gamepad UI
---------------------------------------------------------------------------

if extra.WithUI and extra.WithGamepadUI then
	test("accord: tag follow: under the gamepad UI the player's notice and the team's stop dialog are Olympus's own windows, never the game's popups", function()
		extra.WithUI(function()
			extra.WithGamepadUI(true, function(game)
				World(function(w)
					w.council[Fold("Warden-Realm")] = true
					local S = w.Client("Sootfang", X, 3, { tag = TAG })
					local V = w.Client("Sootwing", Y, 3, { tag = TAG, realDialogs = true })
					-- (Loaded last: the game's popup definitions are one table every client here
					-- shares, so the stop dialog's Yes is the councillor's own.)
					local HC = w.Client("Warden", X, 3, { tag = "Warden#4242", realDialogs = true })
					w.TagTo(HC, S); w.TagTo(HC, V)
					w.epoch = w.epoch + 5
					assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
					w.Run()
					eq(#game.shown, 0, "no game popup")
					local f = ns.Dialog.Find("OLYMPUS_WATCHCHAT_DECISION")
					assert(f and f:IsShown(), "the notice in Olympus's window")
					assert(f.text:GetText():find(L.ACCORD_FOLLOW_YOU_NETOFF:sub(1, 30), 1, true), f.text:GetText())
					f:Hide()
					local stop
					for _, l in ipairs(w.As(HC, HC.A.TeamLines)) do if tostring(l.text):find(L.ACCORD_FOLLOW_GROUP:sub(1, 20), 1, true) then stop = l end end
					assert(stop and stop.onClick, "the follow's line, with a click")
					w.As(HC, stop.onClick)
					local d = ns.Dialog.Find("OLYMPUS_TAGFOLLOW_STOP")
					assert(d and d:IsShown(), "the stop dialog in Olympus's window")
					eq(#game.shown, 0)
					w.As(HC, function() d.buttons[1]:Click() end)
					w.Run()
					eq(#w.Sent("TF~1~N~0~"), 1, "Yes stops it")
					eq(#game.shown, 0)
				end)
			end)
		end)
	end)
end

---------------------------------------------------------------------------
-- Structure
---------------------------------------------------------------------------

test("accord: tag follow: the TOC loads it after Moderation, Accord and WatchChat; Comm.lua's list and Core's stand-in name it; net-off holds TF; the Accord's letter stays within its bound (tests/accord.lua's)", function()
	local function Read(path)
		local f = assert(io.open(ROOT .. path, "rb"))
		local s = f:read("*a")
		f:close()
		return s
	end
	local at, n = {}, 0
	for line in Read("Olympus/Olympus.toc"):gmatch("[^\n]+") do n = n + 1; at[line:gsub("%s+$", "")] = n end
	assert(at["TagFollow.lua"], "in the TOC")
	for _, f in ipairs({ "Moderation.lua", "Accord.lua", "WatchChat.lua", "ChatStrikes.lua" }) do assert(at[f] < at["TagFollow.lua"], f .. " first") end
	assert(Read("Olympus/Comm.lua"):find("TagFollow TF", 1, true), "Comm.lua's list")
	local core = Read("Olympus/Core.lua")
	assert(core:find('StandIn("TagFollow", {})', 1, true), "the stand-in")
	-- (Changed on purpose, the merge into the integration: PLAYER_LOGIN's list gained Record before
	-- TagFollow, so the list itself is read and must name it, wherever it stands.)
	local loginList = core:match('for _, key in ipairs%(({ "Who", [^}]*})%) do')
	assert(loginList and loginList:find('"TagFollow"', 1, true), "PLAYER_LOGIN checks it")
	assert(Read("Olympus/Moderation.lua"):find("MW = true, MR = true, MD = true, TF = true,", 1, true), "a net-off client sends no TF")
	local total = select(2, L.ACCORD_OPENING:gsub("%S+", ""))
	for _, t in ipairs(ns.Accord.TOPICS) do
		for i = 1, t[2] do total = total + select(2, L["ACCORD_T" .. t[1] .. "_" .. i]:gsub("%S+", "")) end
	end
	-- (Changed on purpose, the merge into the integration: the letter's bound is tests/accord.lua's,
	-- 389 since the Companion's and the cover names' bullets joined it; the follow is bullet 5.5 there,
	-- in place of "It helps spot one player's characters", one word trimmed to keep that bound.)
	assert(total <= 389, "the letter is " .. total .. " words")
	assert(L.ACCORD_T5_5:find("follows your BattleTag", 1, true), L.ACCORD_T5_5)
end)

---------------------------------------------------------------------------
-- The hot paths
---------------------------------------------------------------------------

test("accord: tag follow: the hot paths: with no follow, 1,000 lines ask no BattleTag; with one, each name is looked up once", function()
	World(function(w)
		local HC, S, V, B = Basic(w)
		w.TagTo(HC, S); w.TagTo(HC, V)
		local calls, real = 0, HC.A.HashOf
		HC.A.HashOf = function(...) calls = calls + 1 return real(...) end
		for _ = 1, 1000 do
			w.As(HC, HC.M.Hides, V.name)
			w.As(HC, HC.WC.Silenced, V.name)
		end
		eq(calls, 0, "no follow: no lookup")
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		calls = 0
		for _ = 1, 1000 do
			w.As(HC, HC.M.Hides, V.name)
			w.As(HC, HC.M.Hides, B.name)
		end
		assert(calls <= 3, "looked up once a name, not each line: " .. calls)
		local _, _, via = w.As(HC, HC.M.Hides, V.name)
		eq(via, "tag", "and the team's client hides him")
	end)
end)

---------------------------------------------------------------------------
-- The review (each test fails on the first draft and passes now)
---------------------------------------------------------------------------

-- The by-name words given for evading a follow: net-off (O1) or timeout (MD) on `name`, from `from`.
local function DerivedOn(w, name, prefix, from)
	local out = {}
	for _, s in ipairs(w.Sent(prefix)) do
		if s.msg:find("~" .. name .. "~", 1, true) and s.msg:find(w.clients[1].TF.DERIVED_REASON, 1, true)
			and (not from or s.from == from) then out[#out + 1] = s end
	end
	return out
end

-- A sanctioned player's modified addon answers the team with someone else's BattleTag (a copied
-- tag goes with his own account's key: the other account's key never left it).
test("accord: tag follow: a sanctioned player's addon that sends someone else's BattleTag reaches nobody, before or after his sanction; a tag sent again and again follows on a few codes at most", function()
	World(function(w)
		local HC, S, _, B = Basic(w)
		w.TagTo(HC, S); w.TagTo(HC, B)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		w.epoch = w.epoch + 700
		w.TagOf(HC, S.name, OTHER, AAT + 5, X, KEY)
		w.Run()
		local _, _, via = w.As(B, B.M.SelfOff)
		eq(via, nil, "the bystander stays free")
		eq(w.As(B, B.WC.Barred, "powers"), nil)
		eq(select(3, w.As(HC, HC.M.Hides, B.name)), nil, "and is not hidden on the team's client")
		-- Tag after tag: the follows of his sanction go on a few codes at most.
		for i = 1, 6 do
			w.epoch = w.epoch + 5
			w.TagOf(HC, S.name, ("Decoy%d#%d"):format(i, 1000 + i), AAT + 5, X, KEY)
			w.Run()
		end
		local codes = {}
		for _, t in ipairs(w.Sent("TF~1~N~1~")) do
			local code = t.msg:match("^TF~1~N~1~%d+~(%x+)~" .. S.name:gsub("%-", "%%-") .. "~")
			if code then codes[code] = true end
		end
		local n = 0
		for _ in pairs(codes) do n = n + 1 end
		eq(n <= HC.TF.CODES_PER_SOURCE, true, "codes followed: " .. n)
	end)
	World(function(w)
		local HC, S, _, B = Basic(w)
		w.TagTo(HC, B)
		w.TagOf(HC, S.name, OTHER, AAT + 5, X, KEY) -- (from the start: a throwaway plan)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		local _, _, via = w.As(B, B.M.SelfOff)
		eq(via, nil, "the bystander stays free")
		eq(w.As(B, B.WC.Barred, "powers"), nil)
		-- The team sees the copy: one BattleTag, two codes, the other account's waits for a click.
		assert(Shown(w.As(HC, HC.A.TeamLines)):find(L.ACCORD_FOLLOW_CONTESTED, 1, true), "the copy shows")
	end)
end)

-- The King's account: his alts' tag reaches the King and the author alone; a forged King's tag
-- reaches none of his characters; a code with his own character on it never resolves.
test("accord: tag follow: never the King's game account: his alts answer no councillor or moderator; a player who sends the King's BattleTag reaches no character of his, and no by-name word reaches his alt; a code holding the King's own row never resolves on the King's client", function()
	World(function(w)
		local HC, S = Basic(w)
		local CROWN = "Crown#0001"
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", X, 3, { tag = CROWN, kingAccount = true })
		local KA = w.Client("Crownalt", X, 3, { tag = CROWN, kingAccount = true })
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		w.Mods(HC, M)
		w.Asked(HC)
		eq(w.As(KA, KA.A.SendTag, HC.name), false, "no councillor gets the King's alt's tag")
		w.Asked(M)
		eq(w.As(KA, KA.A.SendTag, M.name), false, "nor a moderator")
		-- S sends the King's BattleTag (with his own account's key) and is timed out.
		w.TagOf(M, S.name, CROWN, AAT + 5, X, KEY)
		w.epoch = w.epoch + 5
		assert(w.As(M, M.WC.Act, "T", S.name, { seconds = 3600, reason = "spam" }))
		w.Run()
		eq(w.As(KA, KA.WC.SelfTimeout), nil)
		w.Pass(HC.TF.EVADE_AFTER + 5)
		w.As(KA, KA.C.Send, "A", "hello chat")
		w.Run()
		w.Pass(HC.TF.EVADE_AFTER + 5)
		w.As(KA, KA.C.Send, "A", "hello again")
		w.Run()
		eq(#DerivedOn(w, KA.name, "MD~"), 0, "never a by-name sanction on the King's account")
		eq(w.As(KA, KA.WC.SelfTimeout), nil)
		-- The King's own client holds his rows (his main's and his alts', one code): a follow on that
		-- code (here sent by hand) never resolves there.
		w.TagOf(K, K.name, CROWN, AAT, X, KeyFor(CROWN))
		w.TagOf(K, "Crownbit", CROWN, AAT, X, KeyFor(CROWN))
		w.Asked(K)
		assert(w.As(KA, KA.A.SendTag, K.name), "the King gets it")
		w.Run()
		local code = w.As(K, K.A.HashOf, KA.name)
		assert(code, "a code on the King's client")
		eq(w.As(K, K.TF.KingCode, code), true)
		w.epoch = w.epoch + 5
		assert(w.As(M, M.WC.Act, "T", "Crownbit-Realm", { seconds = 3600, reason = "spam" }))
		w.Run()
		local word = ("TF~1~T~1~%d~%s~Crownbit-Realm~%s"):format(w.epoch, code, M.name)
		eq(w.TF(K, "CHANNEL", M.name, word, true), true, "kept")
		eq(w.As(K, K.WC.TimeoutOf, KA.name), nil, "but it never reaches the King's alt there")
		eq(#w.As(K, K.TF.Sources, KA.name, "T"), 0)
	end)
end)

-- An honest alt that never had the follow: nothing by name for his lines.
test("accord: tag follow: an honest alt that logs in after the follow went, or while its giver is away, gets nothing by name for chatting: his first line makes the giver send the follow, his own addon then applies it", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.TagTo(HC, S); w.TagTo(HC, V)
		V.online = false
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(#w.Kept(V), 0, "offline: nothing kept")
		w.epoch = w.epoch + HC.TF.EVADE_AFTER + 60
		V.online = true
		-- (At login his client hears the net-off word on Sootfang, as Moderation's repeats bring it.)
		w.Inject("CHANNEL", HC.name, V, w.Sent("O1~c~1~")[1].msg)
		eq(w.As(V, V.C.Send, "A", "hi all, just logged in"), true, "his addon had no follow yet")
		w.Run()
		eq(#DerivedOn(w, V.name, "O1~c~1~"), 0, "nothing by name for that line")
		eq(#w.Sent("TF~1~N~1~"), 2, "the giver sent the follow again")
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag", "his own addon applies it now")
		w.epoch = w.epoch + HC.TF.EVADE_AFTER + 60
		eq(w.As(V, V.C.Send, "A", "why can't I talk"), false, "and sends nothing more")
		w.Run()
		eq(#DerivedOn(w, V.name, "O1~c~1~"), 0)
	end)
	World(function(w)
		local HC, S, V = Basic(w)
		w.council[Fold("Ironbrow-Realm")] = true
		local C2 = w.Client("Ironbrow", Y, 3, { tag = "Brow#7777" })
		w.TagTo(HC, S); w.TagTo(C2, S); w.TagTo(C2, V)
		V.online = false
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		HC.online = false -- (the giver logs off: nobody repeats it)
		w.epoch = w.epoch + 7200
		V.online = true
		w.Inject("CHANNEL", HC.name, V, w.Sent("O1~c~1~")[1].msg)
		w.As(V, V.C.Send, "A", "hello")
		w.Run()
		w.epoch = w.epoch + C2.TF.EVADE_AFTER + 60
		w.As(V, V.C.Send, "A", "anyone here")
		w.Run()
		eq(#DerivedOn(w, V.name, "O1~c~1~"), 0, "the other councillor never saw the follow reach him")
		eq(#DerivedOn(w, V.name, "MD~"), 0)
	end)
end)

test("accord: tag follow: a line in the game's own guild chat is never evidence (an honest addon cannot stop it); an Olympus line is", function()
	World(function(w)
		w.council[Fold("Warden-Realm")] = true
		local HC = w.Client("Warden", X, 3, { tag = "Warden#4242" })
		local S = w.Client("Sootfang", X, 3, { tag = TAG })
		local V = w.Client("Sootwing", X, 3, { tag = TAG })
		w.TagTo(HC, S); w.TagTo(HC, V)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		local _, _, via = w.As(V, V.M.SelfOff)
		eq(via, "tag", "his addon obeys")
		for i = 1, 3 do
			w.As(HC, HC.ns.ChatRooms.ReceiveGuild, "typed in /g " .. i, V.name)
			w.epoch = w.epoch + HC.TF.EVADE_AFTER + 1
		end
		w.Run()
		eq(#DerivedOn(w, V.name, "O1~c~1~"), 0, "the game's guild chat proves nothing")
		eq(#w.Sent("TF~1~N~1~"), 1, "nor sends the follow again")
		-- The same character's Olympus line (his addon skipping the follow) is.
		w.Inject("CHANNEL", V.name, HC, w.Line(V.name, "olympus line"))
		w.Run()
		w.epoch = w.epoch + HC.TF.EVADE_AFTER + 1
		w.Inject("CHANNEL", V.name, HC, w.Line(V.name, "olympus line again"))
		w.Run()
		eq(#DerivedOn(w, V.name, "O1~c~1~"), 1)
	end)
end)

-- A freeing word or lift on the followed character's own name lasts until his source's sanction changes.
test("accord: tag follow: an on word that freed the alt lasts through another team client's sweep and a later follow by hand, until the sanctioned character's own word changes", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", X, 3, { tag = "Crown#0001" })
		w.TagTo(HC, S); w.TagTo(HC, V); w.TagTo(K, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(select(3, w.As(V, V.M.SelfOff)), "tag", "followed")
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", V.name, false, ""), "freed by an on word")
		w.Run()
		eq(w.As(V, V.M.SelfOff), nil, "freed")
		local before = #w.Sent("TF~1~N~1~")
		w.epoch = w.epoch + 700
		w.As(K, K.TF.Tick)
		w.Run()
		eq(#w.Sent("TF~1~N~1~"), before, "the King's sweep leaves the kept follow alone")
		eq(w.As(V, V.M.SelfOff), nil, "still free after the sweep")
		w.epoch = w.epoch + 5
		eq(w.As(K, K.A.Slash, "follow Sootfang"), true, "a follow by hand, newer than the on word")
		w.Run()
		eq(w.As(V, V.M.SelfOff), nil, "still free: the on word stands until Sootfang's word changes")
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, false, ""))
		w.Run()
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "again"))
		w.Run()
		eq(select(3, w.As(V, V.M.SelfOff)), "tag", "a new word on Sootfang follows again")
	end)
end)

test("accord: tag follow: a stop given while a higher team member was away holds against his automatic follow when he comes back, everywhere, the stop's giver's client included; his follow by hand passes it", function()
	World(function(w)
		local HC, S, V = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", X, 3, { tag = "Crown#0001" })
		w.TagTo(HC, S); w.TagTo(K, S)
		K.online = false
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		w.epoch = w.epoch + 5
		eq(w.As(HC, HC.TF.Stop, "N", S.name), true)
		w.Run()
		eq(w.As(V, V.M.SelfOff), nil, "stopped")
		-- Back on, the King's client hears Sootfang's word and, after WARMUP, its sweep follows it by
		-- itself (it never heard the stop), at the King's weight, above the councillor's stop.
		K.online = true
		w.Inject("CHANNEL", HC.name, K, w.Sent("O1~c~1~")[1].msg)
		local before = #w.Sent("TF~1~N~1~")
		w.epoch = w.epoch + K.TF.WARMUP + 61
		w.As(K, K.TF.Tick)
		w.Run()
		eq(#w.Sent("TF~1~N~1~"), before + 1, "his automatic follow went")
		eq(select(3, w.As(V, V.M.SelfOff)), nil, "the stop holds on the other character's client")
		local stops = 0
		for _, k in ipairs(w.Kept(HC)) do if k.F.on == false then stops = stops + 1 end end
		eq(stops, 1, "and on the stop's giver's client")
		-- The stop's next repeat reaches the King's client, which takes it (every client orders the
		-- two words the same way) and stops repeating its own follow.
		w.epoch = w.epoch + HC.TF.STOP_EVERY + HC.TF.JITTER + 1
		w.As(HC, HC.TF.Repeat)
		w.Run()
		local kept
		for _, k in ipairs(w.Kept(K)) do if k.F.hash == CODE then kept = k.F end end
		eq(kept and kept.on, false, "the King's client keeps the stop")
		-- The King's own click: a follow given after the stop, so it passes it.
		w.epoch = w.epoch + 5
		eq(w.As(K, K.A.Slash, "follow Sootfang"), true)
		w.Run()
		eq(select(3, w.As(V, V.M.SelfOff)), "tag", "followed again by hand")
	end)
end)

-- A giver who lost his standing takes his follows with him.
test("accord: tag follow: a councillor removed from the council: his follow goes on every client within a minute; a team client takes a code only of the sanctioned player's own BattleTag", function()
	World(function(w)
		local HC, S, V, B = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", X, 3, { tag = "Crown#0001" })
		w.TagTo(HC, S)
		assert(w.As(K, K.M.Set, "c", S.name, true, "spam"))
		w.Run()
		w.epoch = w.epoch + 5
		eq(w.As(HC, HC.TF.Give, "N", S.name), true)
		w.Run()
		eq(select(3, w.As(V, V.M.SelfOff)), "tag", "followed")
		w.council[Fold(HC.name)] = nil
		w.epoch = w.epoch + 60
		w.As(V, V.TF.Tick)
		eq(select(3, w.As(V, V.M.SelfOff)), nil, "his follow went with his seat")
		-- A code that is not the sanctioned player's, on a team client holding his BattleTag: refused.
		w.council[Fold(HC.name)] = true
		w.council[Fold("Ironbrow-Realm")] = true
		local C2 = w.Client("Ironbrow", Y, 3, { tag = "Brow#7777" })
		w.TagTo(HC, B)
		local other = w.As(HC, HC.A.HashOf, B.name)
		local ok, why = w.TF(HC, "CHANNEL", C2.name, ("TF~1~N~1~%d~%s~%s~%s"):format(w.epoch, other, S.name, C2.name), true)
		eq(ok, false); eq(why, "code")
		eq(select(3, w.As(HC, HC.M.Hides, B.name)), nil)
	end)
end)

test("accord: tag follow: /oly accord forget drops the follows that carry that BattleTag's code: never sent again from here", function()
	World(function(w)
		local HC, S = Basic(w)
		w.TagTo(HC, S)
		w.epoch = w.epoch + 5
		assert(w.As(HC, HC.M.Set, "c", S.name, true, "spam"))
		w.Run()
		eq(w.As(HC, HC.A.Forget, S.name), true)
		for _, k in ipairs(w.Kept(HC)) do assert(k.F.hash ~= CODE, "a follow with the forgotten code kept") end
		local before = #w.Sent("TF~")
		w.epoch = w.epoch + HC.TF.REPEAT + HC.TF.JITTER + 5
		w.As(HC, HC.TF.Tick)
		w.Run()
		eq(#w.Sent("TF~") - before, 0, "not repeated")
	end)
end)

-- The derived word: never above the follow's weight, never a guild's, once for one evasion.
test("accord: tag follow: a by-name timeout for evading a moderator's follow comes from a moderator's client, never a councillor's (it would weigh more)", function()
	World(function(w)
		local HC, S = Basic(w)
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		local V2 = w.Client("Sootclaw", Y, 3, { tag = TAG })
		V2.TF.Mine = function() return nil end
		w.Mods(HC, M)
		w.TagTo(M, S); w.TagTo(M, V2); w.TagTo(HC, S); w.TagTo(HC, V2)
		w.epoch = w.epoch + 5
		assert(w.As(M, M.WC.Act, "T", S.name, { seconds = 7200, reason = "flood" }))
		w.Run()
		w.As(V2, V2.C.Send, "A", "one")
		w.Run()
		w.Pass(HC.TF.EVADE_AFTER + 5)
		w.As(V2, V2.C.Send, "A", "two")
		w.Run()
		eq(#DerivedOn(w, V2.name, "MD~", HC.name), 0, "not from the councillor's client")
		eq(#DerivedOn(w, V2.name, "MD~", M.name), 1, "from the moderator's")
	end)
end)

test("accord: tag follow: a guild's timeout followed to an alt that evades it is never given by name (it binds in that guild alone)", function()
	World(function(w)
		w.council[Fold("Warden-Realm")] = true
		local HC = w.Client("Warden", X, 3, { tag = "Warden#4242" })
		local A = w.Client("Watchoff", X, 1, { tag = "Watch#8888" })
		local S = w.Client("Sootfang", X, 3, { tag = TAG })
		local V2 = w.Client("Sootclaw", X, 3, { tag = TAG })
		V2.TF.Mine = function() return nil end
		w.TagTo(HC, S); w.TagTo(HC, V2)
		w.epoch = w.epoch + 5
		assert(w.As(A, A.WC.Act, "T", S.name, { seconds = 3600, reason = "spam" }))
		w.Run()
		assert(w.As(HC, HC.TF.Give, "T", S.name))
		w.Run()
		w.As(V2, V2.C.Send, "A", "one")
		w.Run()
		w.Pass(HC.TF.EVADE_AFTER + 5)
		w.As(V2, V2.C.Send, "A", "two")
		w.Run()
		eq(#DerivedOn(w, V2.name, "MD~"), 0, "a guild's timeout binds in that guild alone: never derived Olympus-wide")
	end)
end)

test("accord: tag follow: two moderators' clients that see the same evasion give one by-name timeout, not two", function()
	World(function(w)
		local HC, S = Basic(w)
		w.king = "Crownhold-Realm"
		local K = w.Client("Crownhold", "Olympus", 0, { tag = "Crown#0001" })
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		local M2 = w.Client("Dusktally", Y, 3, { tag = "Dusk#3333" })
		local V2 = w.Client("Sootclaw", Y, 3, { tag = TAG })
		V2.TF.Mine = function() return nil end
		w.Mods(HC, M, M2)
		w.TagTo(M, S); w.TagTo(M, V2); w.TagTo(M2, S); w.TagTo(M2, V2)
		w.epoch = w.epoch + 5
		assert(w.As(K, K.WC.Act, "T", S.name, { seconds = 7200, reason = "abuse" }))
		w.Run()
		assert(w.As(M, M.TF.Give, "T", S.name))
		w.Run()
		w.As(V2, V2.C.Send, "A", "one")
		w.Run()
		w.Pass(HC.TF.EVADE_AFTER + 5)
		w.Inject("CHANNEL", V2.name, M, w.Line(V2.name, "two"))
		w.Run()
		eq(#DerivedOn(w, V2.name, "MD~", M.name), 1, "the first moderator's client gives it")
		w.Inject("CHANNEL", V2.name, M2, w.Line(V2.name, "three"))
		w.Run()
		eq(#DerivedOn(w, V2.name, "MD~"), 1, "the second sees it and gives none")
	end)
end)

test("accord: tag follow: a followed alt's client never says the guild timeout as its own on the channel (it would show the two share a BattleTag)", function()
	World(function(w)
		w.council[Fold("Warden-Realm")] = true
		local HC = w.Client("Warden", X, 3, { tag = "Warden#4242" })
		local A = w.Client("Watchoff", X, 1, { tag = "Watch#8888" })
		local S = w.Client("Sootfang", X, 3, { tag = TAG })
		local V = w.Client("Sootwing", X, 3, { tag = TAG })
		w.TagTo(HC, S)
		w.epoch = w.epoch + 5
		assert(w.As(A, A.WC.Act, "T", S.name, { seconds = 3600, reason = "spam" }))
		w.Run()
		assert(w.As(HC, HC.TF.Give, "T", S.name))
		w.Run()
		local _, via = w.As(V, V.WC.SelfTimeout)
		eq(via, S.name, "followed")
		w.epoch = w.epoch + 5
		w.As(S, S.WC.Tick); w.As(V, V.WC.Tick)
		w.Run()
		local fromS, fromV = 0, 0
		for _, s in ipairs(w.Sent("MD~1~S~")) do
			if s.from == S.name then fromS = fromS + 1 end
			if s.from == V.name then fromV = fromV + 1 end
		end
		eq(fromS >= 1, true, "the sanctioned character's own client says his, as before")
		eq(fromV, 0, "the followed alt's says nothing")
	end)
end)

test("accord: tag follow: at login a followed timeout's pop-up shows once, not twice", function()
	World(function(w)
		local HC, S, V = Basic(w)
		local M = w.Client("Gloomwatch", Y, 3, { tag = "Gloom#1111" })
		w.Mods(HC, M)
		w.TagTo(M, S)
		w.epoch = w.epoch + 5
		assert(w.As(M, M.WC.Act, "T", S.name, { seconds = 3600, reason = "flooding" }))
		w.Run()
		assert(w.As(V, V.WC.SelfTimeout), "followed")
		-- A new session on V's client: its login notices, 30 seconds on.
		w.As(V, V.TF.ResetForTests, w.epoch)
		w.As(V, V.WC.ResetForTests)
		local n = #V.dialogs
		w.As(V, V.ns.Fire, "LOGIN")
		w.epoch = w.epoch + 31
		w.Run()
		local shown = 0
		for i = n + 1, #V.dialogs do if V.dialogs[i].which == "OLYMPUS_WATCHCHAT_TIMED_OUT" then shown = shown + 1 end end
		eq(shown, 1)
	end)
end)
